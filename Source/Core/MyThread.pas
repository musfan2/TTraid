{
  Содержит базовый класс потока с контролем жизни для Ресурса и УСПД.
  Используйте его для создания своих потоков!

  Чтобы правильно использовать TMyThread нужно:
  1. Первой строчкой в Execute вызвать inherited, чтобы потоку было присвоено имя для отладки (сработает NameThread(ClassName)).
  2. Далее внутри цикла в Execute (желательно первой строчкой цикла) постоянно дергаем метод ImAlive (говорим, что живы и поток работает).
  3. Время до "паники" (без ImAlive) задаётся свойством SecondsToPanic в секундах. По умолчанию 60 сек.
  4. Последней строчкой в Destroy вызвать inherited, чтобы объект корректно убрался из списка контролируемых потоков.
  Если в течении этого времени не будет ни разу вызван метод ImAlive - поток считается зависшим!

  Не рекомендуется дергать ImAlive чаще, чем раз в 100 мс - будет грузить процессор. Используйте пример, если цикл выполняется быстрее:

  var
  . LastImAlive: TDaTeTime;
  if SecondsBetween(Now, LastImAlive) > 3 then
  begin
  . ImAlive; // Вызываем не слишком часто, но и не реже SecondsToPanic
  . LastImAlive := Now;
  end;

  DoctorS, 2024-2025!
}

unit MyThread;

interface

uses
{$IFDEF MSWINDOWS}
  Windows,
{$ENDIF MSWINDOWS}
  Classes, SysUtils, Generics.Collections, MyThreadList, MyCriticalSection;

type

  // Параметры жизни потока
  TParams = record
    SecondsToPanic: Integer; // Число секунд без ImAlive до поднятия паники
    LastALiveTime: TDateTime; // Время последнего вызова ImAlive
  end;

  // FIX: Снимок данных потока для безопасного анализа вне блокировки FThreads
  // Решает проблему: доступ к полям потока внутри блокировки мог вызвать deadlock
  TThreadSnapshot = record
    ThreadID: TThreadID;
    Params: TParams;
    SpecialName: string;
    ClassName: string;
  end;

  { TMyThread }

  // Базовый класс потока с разными дополнительными фишками для Ресурса и УСПД
  TMyThread = class(TThread)
  strict private
    FLastALiveUnixTime: Integer; // Когда поток последний раз был жив - В 2038 умрет, а int64 не пашет в FPC =(
    FSecondsToPanic: Integer;
    FSpecialName: string;
    // FIX: Блокировка для потокобезопасного доступа к FSpecialName
    // Решает проблему: чтение строки без синхронизации могло привести к AV
    FSpecialNameLock: TMyCriticalSection;

    procedure Init;
    function GetSecondsToPanic: Integer;
    procedure SetSecondsToPanic(const Value: Integer);
    procedure SetSpecialName(const Value: string);
    function GetSpecialName: string;
  protected
    function GetParams: TParams; // Вернет параметры для контроля зависания
    function GetLastALiveTime: TDateTime;
    procedure Execute; override;
    // FIX: Возвращает снимок данных потока для безопасного анализа вне блокировки
    function GetSnapshot: TThreadSnapshot;
  public
    // Используем AfterConstruction для установки настроек по умолчанию, чтобы не перекрывать конструктор
    constructor Create; overload;
    constructor Create(CreateSuspended: Boolean); overload;
    destructor Destroy; override;

    // Дождаться завершения, убить поток и освободить память
    // Вернёт True - если умер своей смертью, False - если насильственной =)
    // Версия для Delphi - не требует приведения к TThread за счёт крутых дженериков
    class function TerminateAndFree<T: TThread>(var AThread: T; const TimeOutMS: Cardinal = 10000): Boolean; overload; static;
    // Версия для FPC - требует приведения к TThread из-за плохих дженериков
    class function TerminateAndFree(var AThread: TThread; const TimeOutMS: Cardinal = 10000): Boolean; overload; static;

    { Нужно дергать в Execute, но не чаще чем раз в 100 мс. Если цикл повторяется чаще, используйте пример:
      var
      . LastImAlive: TDaTeTime;
      if SecondsBetween(Now, LastImAlive) > 3 then
      begin
      . ImAlive; // Первым делом говорим, что живы для TThreadMonitor
      . LastImAlive := Now;
      end; }
    procedure ImAlive;

    // Упрощенная версия Delay для потоков с контролем Terminated, но без ProgramClosing (!!)
    // Thread может быть nil - тогда проверка Terminated не выполняется
    // Используйте, если нужна пауза более 100 мс (иначе просто Sleep)
    class procedure DelayForThread(const Thread: TThread; const SleepTimeMS: Cardinal); static;

    // Позволяет задать число секунд без дерганья ImAlive до поднятия тревоги!
    property SecondsToPanic: Integer read GetSecondsToPanic write SetSecondsToPanic;

    // Позвоялет задать потоку особое имя, чтобы его было проще идентифицировать
    property SpecialName: string read GetSpecialName write SetSpecialName;
  end;

  // Монитор потоков - следит, чтобы ни кто не завис!
  TThreadMonitor = class(TThread)
  strict private
    class var FThreads: TMyThreadList<TMyThread>;
    class var FLastMonitorMonitorUnixTime: Integer; // В 2038 умрет, а int64 не пашет в FPC =(
    class var FMonitorThread: TThread;
    // FIX: Словарь для отслеживания уже залогированных зависших потоков (по ThreadID)
    class var FDeadThreads: TMyThreadDictionary<TThreadID, Boolean>;

    // Главный метод проверки живучисти потоков
    class procedure MonitorExecute;
  private
    class function GetLastMonitorMonitorTime: TDateTime; static;
    class procedure SetLastMonitorMonitorTime(const Value: TDateTime); static;
  public
    class constructor Create;
    class destructor Destroy;

    class procedure AddThread(const InThread: TMyThread);
    class procedure DelThread(const InThread: TMyThread);

    class property LastMonitorMonitorTime: TDateTime read GetLastMonitorMonitorTime write SetLastMonitorMonitorTime;
  end;

  // Монитор монитора - следит, что бы не завис TThreadMonitor =)
  TThreadMonitorMonitor = class(TThread)
  private
    FLastALifeTime: TDateTime;
  protected
    procedure Execute; override;
  end;

  // Ждёт завершение потока в течении X миллисекунд
function WaitForThreadFinish(const Thread: TThread; const MilliSecToWait: Cardinal): Boolean;

// Пытается дождаться завершения потока, если не получается ставит FreeOnTerminate := True
// !!! Вместо неё рекомендуется использовать TMyThread.TerminateAndFree !!!
function KillThreadWithTimeout(var Thread: TThread; const MilliSecToWait: Cardinal): Boolean; overload;

implementation

uses DateUtils, SyncObjs;

// Локальные заглушки для функций, которые были в ClearFunctions/LoggerUnit
// В будущем замените на свою реализацию логирования

procedure SaveToFile(const Mes: string);
begin
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Mes));
{$ENDIF MSWINDOWS}
end;

procedure SaveLifeLog(const Mes: string);
begin
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar('LifeLog: ' + Mes));
{$ENDIF MSWINDOWS}
end;

procedure NameThread(const AName: string);
begin
  TThread.NameThreadForDebugging(AName);
end;

procedure WaitProgramLoading;
begin
  // Заглушка: в новом проекте загрузка мгновенная
end;

procedure ApplicationProcessMessages;
begin
  // Заглушка: обработка сообщений приложения
end;

var // ЛОКАЛЬНЫЕ переменные модуля
  ErrorLine: Integer; // Номер строки с ошибкой (для try except)
  ThreadMonitorMonitor: TThreadMonitorMonitor;

  { Функции модуля }

function WaitForThreadFinish(const Thread: TThread; const MilliSecToWait: Cardinal): Boolean;
var
  ThreadName: string;
begin
  if not Assigned(Thread) then
    Exit(False);

  if Thread.Finished then
    Exit(True);

  if MilliSecToWait = 0 then
    Exit(Thread.Finished);

  var ST := GetTickCount64;
  var MainThread := (TThread.Current.ThreadID = MainThreadID);

  while not Thread.Finished do
  begin
    if (GetTickCount64 - ST) >= MilliSecToWait then
      break;

    Sleep(10);

    if MainThread then
      ApplicationProcessMessages;
  end;

  Result := Thread.Finished;
  // Логируем таймаут
  if not Result then
  begin
    if (Thread is TMyThread) and (TMyThread(Thread).SpecialName <> '') then
      ThreadName := TMyThread(Thread).SpecialName
    else
      ThreadName := Thread.ClassName;
    SaveToFile('WaitForThreadFinish: ТАЙМАУТ для ' + ThreadName + ' (' + (MilliSecToWait div 1000).ToString +
      ' сек)');
  end;
end;

function KillThreadWithTimeout(var Thread: TThread; const MilliSecToWait: Cardinal): Boolean;
// Пытается дождаться завершения потока, если не получается ставит FreeOnTerminate := True
begin
  if Assigned(Thread) then
  begin
    Thread.FreeOnTerminate := False; // На всякий случай
    Thread.Terminate; // Просим Умиреть
    // Пытаемся дождаться кончины!
    Result := WaitForThreadFinish(Thread, MilliSecToWait);
    if Assigned(Thread) then
      if Result then
        FreeAndNil(Thread) // Ура, он завершился - добъём!
      else
      begin
        Thread.FreeOnTerminate := True; // Если не дождались - будем надеяться, что умрёт сам
        Thread := nil; // Только занулим ссылку, зависший убивать нельзя!
      end;
  end
  else
    Result := True; // Если поток не Assigned - считаем, что уже завершили :)
end;

{ TMyThread }

procedure TMyThread.Init;
begin
  // FIX: Создаём блокировку для потокобезопасного доступа к SpecialName
  FSpecialNameLock := TMyCriticalSection.Create('TMyThread.FSpecialName');
  TInterlocked.Exchange(FSecondsToPanic, 60);
  TInterlocked.Exchange(FLastALiveUnixTime, DateTimeToUnix(Now));

  // Добавим себя в монитор потоков
  TThreadMonitor.AddThread(Self);
end;

constructor TMyThread.Create;
begin
  inherited Create(False);
  Init;
end;

constructor TMyThread.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);
  Init;
end;

destructor TMyThread.Destroy;
begin
  // Удалим себя из монитора потоков
  TThreadMonitor.DelThread(Self);

  // FIX: Освобождаем объект блокировки SpecialName
  FreeAndNil(FSpecialNameLock);

  inherited;
end;

procedure TMyThread.Execute;
begin
  // Даём имя потоку, чтобы можно было легче понять в каком потоке мы находимся
  NameThread(ClassName);
end;

procedure TMyThread.SetSpecialName(const Value: string);
begin
  // FIX: Потокобезопасная запись строки SpecialName
  FSpecialNameLock.Enter('SetSpecialName');
  try
    FSpecialName := Value;
  finally
    FSpecialNameLock.Leave('SetSpecialName');
  end;
  NameThread(Value); // Перезададим имя потока, если его указали
end;

function TMyThread.GetSpecialName: string;
begin
  // FIX: Потокобезопасное чтение строки SpecialName
  FSpecialNameLock.Enter('GetSpecialName');
  try
    Result := FSpecialName;
  finally
    FSpecialNameLock.Leave('GetSpecialName');
  end;
end;

function TMyThread.GetSnapshot: TThreadSnapshot;
// FIX: Возвращает снимок данных потока для безопасного анализа вне блокировки FThreads
// Это позволяет MonitorExecute работать со снимками без удержания блокировки
begin
  Result.ThreadID := Self.ThreadID;
  Result.Params := GetParams;
  Result.SpecialName := GetSpecialName;
  Result.ClassName := ClassName;
end;

procedure TMyThread.ImAlive;
begin
  TInterlocked.Exchange(FLastALiveUnixTime, DateTimeToUnix(Now));
end;

function TMyThread.GetLastALiveTime: TDateTime;
begin
  Result := UnixToDateTime(TInterlocked.CompareExchange(FLastALiveUnixTime, 0, 0));
end;

function TMyThread.GetParams: TParams;
// Вернет параметры для контроля зависания
begin
  Result.SecondsToPanic := GetSecondsToPanic;
  Result.LastALiveTime := GetLastALiveTime;
end;

function TMyThread.GetSecondsToPanic: Integer;
begin
  Result := TInterlocked.CompareExchange(FSecondsToPanic, 0, 0);
end;

procedure TMyThread.SetSecondsToPanic(const Value: Integer);
begin
  TInterlocked.Exchange(FSecondsToPanic, Value);
end;

class function TMyThread.TerminateAndFree<T>(var AThread: T; const TimeOutMS: Cardinal = 10000): Boolean;
// Дождаться завершения, убить поток и освободить память.
// Вернёт True - если умер своей смертью, False - если насильственной =)
// Версия для Delphi - не требует приведения к TThread за счёт крутых дженериков
begin
  Result := KillThreadWithTimeout(TThread(AThread), TimeOutMS);
end;

class function TMyThread.TerminateAndFree(var AThread: TThread; const TimeOutMS: Cardinal = 10000): Boolean;
// Дождаться завершения, убить поток и освободить память.
// Вернёт True - если умер своей смертью, False - если насильственной =)
// Версия для FPC - требует приведения к TThread из-за плохих дженериков
begin
  Result := KillThreadWithTimeout(AThread, TimeOutMS);
end;

class procedure TMyThread.DelayForThread(const Thread: TThread; const SleepTimeMS: Cardinal);
// Упрощенная версия Delay для потоков с контролем Terminated, но без ProgramClosing (!!)
// Thread может быть nil - тогда проверка Terminated не выполняется
// Используйте, если нужна пауза более 100 мс (иначе просто Sleep)
var
  StepMS: Cardinal;
  ST, MS: UInt64;
begin
  // GetTickCount64 быстрее Now - вернет число мс с момента запуска системы, не боится перевода времени!
  ST := GetTickCount64;
  repeat
    // Столько всего ОСТАЛОСЬ ждать
    StepMS := SleepTimeMS - (GetTickCount64 - ST);

    // Теперь скорректируем
    if StepMS > 300 then
      StepMS := 200 // Нельзя спать больше 200 мс, чтобы поток быстро завершился
    else // Т.к. Sleep может спать гораздо больше, чем его просили...
      StepMS := StepMS div 2; // ... будем спать 50% от оставшегося времени

    if StepMS > 10 then
      Sleep(StepMS)
    else
    begin // Если осталось ждать меньше 10 мс - спим еще 1 мс и выходим
      Sleep(1); // При высокой нагрузке, это может быть и 1 и 100 мс...
      break;
    end;

    MS := GetTickCount64 - ST;
  until (Assigned(Thread) and Thread.CheckTerminated) or (MS >= SleepTimeMS);

  // Залогируем не стандартное ожидание!
  MS := GetTickCount64 - ST; // Обновим реальное время сна
  if (not Assigned(Thread) or not Thread.CheckTerminated) then
    if (MS > UInt64(SleepTimeMS) * 2) or (MS < UInt64(SleepTimeMS) * 0.9) then
      SaveToFile('DelayForThread СПАЛ ' + MS.ToString + 'мс вместо ' + SleepTimeMS.ToString + 'мс!!!'
        + ' StepMS = ' + StepMS.ToString);
end;

{ TThreadMonitor }

class constructor TThreadMonitor.Create;
begin
  FLastMonitorMonitorUnixTime := DateTimeToUnix(Now);
  FThreads := TMyThreadList<TMyThread>.Create('TThreadMonitor.FThreads');
  FDeadThreads := TMyThreadDictionary<TThreadID, Boolean>.Create('TThreadMonitor.FDeadThreads');

  // Создаем и запускаем внутренний поток мониторинга
  FMonitorThread := TThread.CreateAnonymousThread(
    procedure
    begin
      // Даём имя потоку, чтобы можно было легче понять в каком потоке мы находимся
      NameThread(ClassName);

      // Дождёмся окончания загрузки - она может занимать несколько минут на больших базах, особенно при обновлении
      WaitProgramLoading;

      // Время собственного пинга
      LastMonitorMonitorTime := Now;

      // Спим еще 30 сек шагами по 200 мс, чтобы потоки успели обновить ImAlive
      TMyThread.DelayForThread(FMonitorThread, 30 * 1000);

      while not FMonitorThread.CheckTerminated do
      begin
        // Время собственного пинга
        LastMonitorMonitorTime := Now;

        // Главный метод
        MonitorExecute;

        // Спим 10 сек шагами по 200 мс
        TMyThread.DelayForThread(FMonitorThread, 10 * 1000);
      end;

      // Логируем завершение потока-монитора
      SaveLifeLog(ClassName + ': Terminated !');
    end);
  FMonitorThread.FreeOnTerminate := False;
  FMonitorThread.Start;
end;

class destructor TThreadMonitor.Destroy;
begin
  // Останавливаем внутренний поток мониторинга
  TMyThread.TerminateAndFree(FMonitorThread);

  FreeAndNil(FThreads);
  FreeAndNil(FDeadThreads);
end;

class procedure TThreadMonitor.AddThread(const InThread: TMyThread);
begin
  if Assigned(FThreads) then
    FThreads.Add(InThread);
end;

class procedure TThreadMonitor.DelThread(const InThread: TMyThread);
begin
  if Assigned(FThreads) then
    FThreads.Remove(InThread, 'TThreadMonitor.DelThread');
end;

class procedure TThreadMonitor.MonitorExecute;
var
  Mes: string;
  Thread: TMyThread;
  Threads: TList<TMyThread>;
  Snapshots: array of TThreadSnapshot;
  Snapshot: TThreadSnapshot;
  ST: TDateTime;
  ThreadName: string;
  ErrorLine: Integer;
  I, ThreadCount: Integer;
  IsDead, WasDead: Boolean;
begin
  ErrorLine := 0;
  try
    if Assigned(FThreads) and not TThread.CheckTerminated then
    begin
      ST := Now;
      ErrorLine := 1;

      // FIX: Собираем снимки данных потоков под блокировкой, анализируем без неё
      // Решает проблему: долгий анализ внутри блокировки мог вызвать deadlock
      Threads := FThreads.LockForRead('TThreadMonitor.Execute');
      try
        ErrorLine := 2;
        ThreadCount := Threads.Count;
        SetLength(Snapshots, ThreadCount);
        for I := 0 to ThreadCount - 1 do
        begin
          Thread := Threads[I];
          if Assigned(Thread) then
            Snapshots[I] := Thread.GetSnapshot;
        end;
      finally
        ErrorLine := 3;
        FThreads.UnlockAfterRead('TThreadMonitor.Execute');
      end;

      ErrorLine := 4;
      // FIX: Анализируем снимки уже без блокировки - это безопасно
      for I := 0 to high(Snapshots) do
      begin
        Snapshot := Snapshots[I];
        ErrorLine := 5;

        IsDead := SecondsBetween(Now, Snapshot.Params.LastALiveTime) > Snapshot.Params.SecondsToPanic;
        WasDead := FDeadThreads.ContainsKey(Snapshot.ThreadID);

        ErrorLine := 6;
        if not Snapshot.SpecialName.IsEmpty then
          ThreadName := Snapshot.SpecialName
        else
          ThreadName := Snapshot.ClassName;

        if IsDead then
        begin
          // FIX: Логируем зависание только однократно
          if not WasDead then
          begin
            ErrorLine := 7;
            Mes := 'Поток ' + ThreadName + ' перестал отвечать!';
            SaveToFile(Mes);
{$IFDEF RELEASE}
            SaveLifeLog(Mes);
{$ENDIF RELEASE}
            FDeadThreads.AddOrSetValue(Snapshot.ThreadID, True);
          end;
        end
        else if WasDead then
        begin
          // FIX: Поток "отвис" - логируем восстановление
          ErrorLine := 10;
          Mes := 'Поток ' + ThreadName + ' возобновил работу!';
          SaveToFile(Mes);
{$IFDEF RELEASE}
          SaveLifeLog(Mes);
{$ENDIF RELEASE}
          FDeadThreads.Remove(Snapshot.ThreadID);
        end;
      end;

      ErrorLine := 11;
      // Логируем замедление работы
      if SecondsBetween(ST, Now) >= 1 then
        SaveLifeLog('Обход ' + ThreadCount.ToString + ' потоков в TThreadMonitor занял ' + SecondsBetween(ST,
          Now).ToString + ' c!');
    end;
  except
    on E: Exception do
    begin
      SaveToFile('Упали в TThreadMonitor.MonitorExecute ! ErrorLine = ' + ErrorLine.ToString +
        ', ThreadName = ' + ThreadName + ', Ошибка: ' + E.Message);
    end;
  end;
end;

class procedure TThreadMonitor.SetLastMonitorMonitorTime(const Value: TDateTime);
begin
  TInterlocked.Exchange(FLastMonitorMonitorUnixTime, DateTimeToUnix(Value));
end;

class function TThreadMonitor.GetLastMonitorMonitorTime: TDateTime;
begin
  Result := UnixToDateTime(TInterlocked.CompareExchange(FLastMonitorMonitorUnixTime, 0, 0));
end;

{ TThreadMonitorMonitor }

procedure TThreadMonitorMonitor.Execute;
const
  SecondsToDead: Int64 = 60; // Int64 чтобы не было варнинга на УСПД
var
  Mes: string;
  ST: TDateTime;
  ErrorLine: Integer;
begin
  // FIX: Инициализируем время жизни (ранее переменная была неинициализирована)
  FLastALifeTime := Now;

  // Дождёмся окончания загрузки - она может занимать несколько минут на больших базах, особенно при обновлении
  WaitProgramLoading;

  // Спим ещё 10 сек шагами по 200 мс, чтобы вышел в рабочий режим TThreadMonitor
  TMyThread.DelayForThread(Self, 10 * 1000);

  while not Terminated do
  begin
    try
      ErrorLine := 0;
      if MinutesBetween(Now, FLastALifeTime) >= 60 then
      begin
        SaveLifeLog(Self.ClassName + ' - живой!');
        FLastALifeTime := Now;
      end;

      ST := Now;

      ErrorLine := 10;
      if SecondsBetween(Now, TThreadMonitor.LastMonitorMonitorTime) >= SecondsToDead then
      begin
        ErrorLine := 20;
        Mes := 'Монитор потоков ' + TThreadMonitor.ClassName + ' перестал отвечать!!!!';
        SaveToFile(Mes);
{$IFDEF RELEASE}
        SaveLifeLog(Mes);
{$ENDIF RELEASE}
      end;

      // Логируем замедление работы
      ErrorLine := 30;
      if SecondsBetween(ST, Now) >= 1 then
        SaveToFile('Проверка жизни монитора потоков в TThreadMonitorMonitor заняла ' + SecondsBetween(ST, Now)
          .ToString + (' c!'));

      // Спим 10 сек шагами по 200 мс
      ErrorLine := 40;
      TMyThread.DelayForThread(Self, 10 * 1000);
    except
      on E: Exception do
      begin
        SaveToFile('Упали в TThreadMonitorMonitor.Execute ! ErrorLine = ' + ErrorLine.ToString + ', Ошибка: '
          + E.Message);
      end;
    end;
  end;

  // Логируем завершение потока-монитора
  SaveLifeLog(ClassName + ': Terminated !');
end;

initialization

// Запускаем монитор монитора потоков :)
ThreadMonitorMonitor := TThreadMonitorMonitor.Create(False);

finalization

try
  ErrorLine := 0;

  // Глушим монитор монитора потоков :)
  TMyThread.TerminateAndFree(TThread(ThreadMonitorMonitor));

  ErrorLine := 1;
except
  on E: Exception do
  begin
    SaveToFile('Упали в MyThread.Finalization ! ErrorLine = ' + ErrorLine.ToString + ', Ошибка: ' +
      E.Message);
  end;
end;

end.
