{
  Самописный аналог iTask на базе TThread.
  В отличии от iTask, должен нормально работать на однопроцессорных системах.
  По умолчанию самостоятельно умирает (Free делать не надо, если AutoFree = True). Пример: TWebApiWorkerClass.DoRPC
  Если нужно дождаться завершения работы, используйте метод WaitForFinish из главного потока. Пример: TWebGlobalDialog.GetDialogResult
  Так же есть возможность запуска с автоматической синхронизацией с главным потоком.

  Внимание!
  Если Вы используете вариант с AutoFree, то присваивать экземпляр класса переменной (и обращаться к ней) настрого запрещено!!

  DoctorS, 2022-2024.
}

unit MyTask;

// Включает отладку TMyTask
{$IFDEF DEBUG}
// {$DEFINE MyTaskDEBUG} // Отладка по умолчанию только в дебаге!
{$ENDIF DEBUG}

interface

// Здесь не должно быть SysFunc и других зависимостей от Ресурса и УСПД!
uses
  Classes,
  SysUtils,
  SyncObjs,
  Windows,
  Generics.Collections,
  MyCriticalSection,
  MyFlag,
  MyThread;

type

  // Определяем свой тип для совместимости
  TMyProc = TProc; // reference to procedure

  // Самописный аналог iTask на базе TThread. Подробности в заголовке модуля.
  TMyTask = class(TMyThread)
  private
    FMethod: TThreadProcedure;
    FStartDelay: Cardinal;
    FSynchronize: Boolean;
    FProgramClosing: TMyFlag; // Указатель на ProgramClosing
{$IFDEF MyTaskDEBUG} FTaskNumber: Int64; {$ENDIF MyTaskDEBUG}
  protected
    procedure Execute; override;
    procedure LogDebug( { const } Mes: string);
  public
    // Базовый конструктор с кучей парамметров - лучше не использовать! Используйте методы (ниже) вместо него
    constructor Create(const FuncName: string; const AutoFree: Boolean; const StartDelayMS: Cardinal;
      const Synchronize: Boolean; const Method: TThreadProcedure; const inProgramClosing: TMyFlag); overload;
    destructor Destroy; override;
    // Ждёт завершения выполнения задачи
    // Данный метод можно использовать, только если FreeOnTerminate = False!!!!
    procedure WaitForFinish(const inProgramClosing: TMyFlag);
  end;

  { Абстрактная задача для TTimerThread }
  TAbstractTimerTask = class(TInterfacedObject)
  strict protected
    function GetLastTime: TDatetime; virtual; abstract;
    procedure SetLastTime(const ATime: TDatetime); virtual; abstract;
    function IsShouldRepeat: Boolean; virtual; abstract;
    procedure SetShouldRepeat(const AValue: Boolean); virtual; abstract;
    function GetRepeatTimeout: Cardinal; virtual; abstract;
    function IsOwnerFree: Boolean; virtual; abstract;
  public
    { Спрашиваем, пришло ли время выполнить задачу? }
    function CanRun: Boolean; virtual; abstract;
    { Вернёт время создания задачи }
    function GetCreateTime: TDatetime; virtual; abstract;
    { Стартануть таймер. }
    procedure Start; virtual; abstract;
    { Остановить таймер. }
    procedure Stop; virtual; abstract;
    { Выполнить задачу сейчас }
    procedure ExecuteNow; virtual; abstract;
    { Когда задача была создана или когда последний раз вызвали Update.
      Время используется для отсчёта таймаута через
      сколько минут задачу стартануть. }
    property LastTime: TDatetime read GetLastTime write SetLastTime;
    { Задача должна повторяться или выполниться только 1 раз? }
    property ShouldRepeat: Boolean read IsShouldRepeat write SetShouldRepeat;
    { Время повтора задачи }
    property RepeatTimeout: Cardinal read GetRepeatTimeout;
    { Владелец задачи убивает ее }
    property OwnerFree: Boolean read IsOwnerFree;
  end;

  { Поток для задач по таймеру. }
  TTimerThread = class(TMyThread)
  private type
    { Список задач таймера }
    TTimerTaskList = class(TList<TAbstractTimerTask>)
    public
      constructor Create;
      destructor Destroy; override;
    end;
  strict private
    FSync: TMyCriticalSection; { Объект синхронизации }
    FTickSleep: Cardinal; { Задержа между витками проверки времени выполнения задач }
    FEnabled: Boolean; { Активность потока таймера }
    FTasks: TTimerTaskList; { Список задач по таймеру }
    function GetTickSleep: Cardinal;
    procedure SetTickSleep(const AValue: Cardinal);
    function GetEnabled: Boolean;
    procedure SetEnabled(const AValue: Boolean);
    { Обработать по наступившему таймауту добавленные задачи. Под обработать
      подразумевается спросить каждую, пришло ли время выполнится или нет. }
    procedure DoTimer;
  protected
    procedure Execute; override; { Если ты не знаешь, что это такое - обязательно изучи! }
  public
    constructor Create(
      { } const AEnabled: Boolean;
      { } const ATimeoutMS: Cardinal;
      { } const ATimerName: string); overload;
    constructor Create(const ATimerName: string); overload;
    destructor Destroy; override;

    procedure Add(const ATask: TAbstractTimerTask); { Добавить задачу. Используется в TThreadTimerTask.Start }
    procedure Remove(const ATask: TAbstractTimerTask); { Удалить задачу. Используется в TThreadTimerTask.Stop }
    { Задержа между витками проверки времени выполнения задач }
    property TickSleep: Cardinal read GetTickSleep write SetTickSleep;
    property Enabled: Boolean read GetEnabled write SetEnabled;
  end;

  { Задача таймера на основе потока из котрого сделали таймер. }
  TTimerTask = class(TAbstractTimerTask)
  private type
    { Действие выполняемое по наступлению подходящего времени по таймеру }
    TTimerAction = reference to procedure(const ATask: TAbstractTimerTask);
  strict private
    { Поток в котором задача сейчас висит. Не убивает задачу. }
    FOwner: TTimerThread;
    { Флаг - убивать владеющим потоком задачу или нет }
    FOwnerFreeTask: Boolean;
    { Через сколько секунд начать стандартный отсчёт выполнения задачи }
    FInitialTimeout: Cardinal;
    { Через сколько секунд выполнить от FLastTime }
    FRepeatTimeout: Cardinal;
    { Флаг - повторяемая задача }
    FShouldRepeat: Boolean;
    { Действие выполняемое задачей }
    FAction: TTimerAction;
    { Время последнего выполнения задачи }
    // Используем целые числа для атомарной работы
{$IF Defined(WIN64)}
    FLastTime: Int64;
{$ELSE}
    FLastTime: Integer; // Хватит до 2038 года
{$ENDIF}
    { Флаг - была ли задача выполнена. }
    FExecuted: Boolean;
    { Время создания задачи }
    FCreateTime: TDatetime;
  strict protected
    function GetLastTime: TDatetime; override;
    procedure SetLastTime(const ATime: TDatetime); override;
    function IsShouldRepeat: Boolean; override;
    procedure SetShouldRepeat(const AValue: Boolean); override;
    function GetRepeatTimeout: Cardinal; override;
    function IsOwnerFree: Boolean; override;
    procedure CheckOwnerAssigned;
  public

    { Максимально гибкий конструктор для тех кто знает, что ему нужно и для среды тестирования.
      Для началы работы необходимо вызвать метод Start! В конце задачу нужно убить, если AOwnerFreeTask = False ! }
    constructor Create(
      { } const AOwner: TTimerThread;
      { } const AOwnerFreeTask: Boolean;
      { } const AInitialTimeoutSec: Cardinal;
      { } const ARepeatTimeoutSec: Cardinal;
      { } const AShouldRepeat: Boolean;
      { } const AAction: TTimerAction); overload;

    { Конструктор с авто стартом для задач с повтором. Используется в главном таймере MainLogic. Задачу убьёт поток-владелец! }
    constructor Create(
      { } const AOwner: TTimerThread;
      { } const AInitialTimeoutSec: Cardinal;
      { } const ARepeatTimeoutSec: Cardinal;
      { } const AAction: TTimerAction); overload;

    { Конструктор с авто стартом для однократного выполнения задачи. Задачу убьёт поток-владелец! }
    constructor Create(
      { } const AOwner: TTimerThread;
      { } const AInitialTimeoutSec: Cardinal;
      { } const AAction: TTimerAction); overload;

    { Golovachev: Не хватает вариантов создания?
      Либо добавьте свой, либо используете самый верхний гибкий конструктор. }

    destructor Destroy; override;

    function CanRun: Boolean; override;
    function GetCreateTime: TDatetime; override; { Вернёт время создания задачи }

    procedure Start; override; { Стартануть таймер. }
    procedure Stop; override; { Остановить таймер. }
    procedure ExecuteNow; override; { Выполнить задачу сейчас }
  end;



  // ============== Удобные функции для безопасного использования класса ===============

  // 4 варианта без задержки

  // Самоубивающийся вариант без задержки и синхронизации
procedure TMyTaskAutoFree(const FuncName: string; const Method: TMyProc); overload;
// Не самоубивающийся вариант без задержки и синхронизации
function TMyTaskNotAutoFree(const FuncName: string; const Method: TThreadProcedure): TMyTask; overload;
// Самоубивающися вариант с синхронизацией с главным потоком и без задержки
procedure TMyTaskSynchronizedAutoFree(const FuncName: string; const Method: TMyProc); overload;
// Не самоубивающися вариант с синхронизацией с главным потоком и без задержки
function TMyTaskSynchronizedNotAutoFree(const FuncName: string; const Method: TThreadProcedure): TMyTask; overload;

// 4 варианта с задержкой

// Самоубивающийся вариант с задержкой и синхронизацией
procedure TMyTaskAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
  const Method: TMyProc); overload;
// Не самоубивающийся вариант с задержкой и синхронизацией
function TMyTaskNotAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
  const Method: TThreadProcedure): TMyTask; overload;
// Самоубивающися вариант с синхронизацией и задержкой
procedure TMyTaskSynchronizedAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
  const Method: TMyProc); overload;
// Не самоубивающися вариант с синхронизацией и задержкой
function TMyTaskSynchronizedNotAutoFree(const FuncName: string; const StartDelayMS: Cardinal;
  const inProgramClosing: TMyFlag; const Method: TThreadProcedure): TMyTask; overload;

{
  Пример:

  TMyTaskAutoFree('TWebConnectionsList.DisconnectOnLogout', 100, ProgramClosing, // Free делать не надо! Он умерёт сам!
  procedure // Пауза 100 мс
  begin

  end);
}

implementation

uses
{$IFDEF MSWINDOWS}
  VCL.Forms,
{$ENDIF MSWINDOWS}
{$IFDEF ISFMX}
  FMX.Forms,
{$ENDIF ISFMX}
  System.Threading,
  DateUtils;

{$IFDEF MyTaskDEBUG}

var
  TaskCount: Int64;
  TaskNumber: Int64;
{$ENDIF MyTaskDEBUG}

procedure MyTaskDelay(const FStartDelay: Cardinal; const FProgramClosing: TMyFlag; const DelphiTaskSleep: Boolean);
// Местный упрощенный аналог Delay, чтобы не тянуть зависимости
// DelphiTaskSleep - если используем с тасками Delphi должен быть True, если с потоками - False

  procedure DelphiSleep(const ST: Cardinal);
  begin
    { Таски не треды и таски работают на тредах, соответственно
      если тред заснул, заснули где то и другие таски - а нам такого
      не надо. Нужно пробросить делей в механизмы тасков }
    TTask.CurrentTask.Wait(ST);
  end;

var
  SleepTime: Integer;
  StartTime: UInt64;
begin
  if FStartDelay > 0 then
  begin
    StartTime := GetTickCount64;

    repeat
      // Спим по 50% от оставшегося времени сна, но не больше 200 мс за раз (для контроля FProgramClosing)
      SleepTime := (FStartDelay - (GetTickCount64 - StartTime)) div 2;
      if SleepTime > 200 then
        SleepTime := 200; // Спим не больше 200 мс за раз для контроля FProgramClosing
      if SleepTime < 1 then
        Break; // Могли уже "переспать", тогда выходим =)

      if DelphiTaskSleep then
        DelphiSleep(SleepTime)
      else
        Sleep(SleepTime);

      if FProgramClosing then
        Break;
    until GetTickCount64 - StartTime >= FStartDelay;
  end;
end;


// 4 варианта без задержки

procedure TMyTaskAutoFree(const FuncName: string; const Method: TMyProc);
// Самоубивающийся вариант без задержки и синхронизации
begin
  TTask.Run(Method);
end;

function TMyTaskNotAutoFree(const FuncName: string; const Method: TThreadProcedure): TMyTask;
// Не самоубивающийся вариант без задержки и синхронизации
begin
  Result := TMyTask.Create(FuncName, False, 0, False, Method, TMyFlag.GetFalse);
end;

procedure TMyTaskSynchronizedAutoFree(const FuncName: string; const Method: TMyProc);
// Самоубивающися вариант с синхронизацией с главным потоком и без задержки
begin
  TTask.Run(
    procedure
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          Method;
        end);
    end);
end;

function TMyTaskSynchronizedNotAutoFree(const FuncName: string; const Method: TThreadProcedure): TMyTask;
// Не самоубивающися вариант с синхронизацией с главным потоком и без задержки
begin
  Result := TMyTask.Create(FuncName, False, 0, True, Method, TMyFlag.GetFalse)
end;

// 4 варианта с задержкой

procedure TMyTaskAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
const Method: TMyProc);
// Самоубивающийся вариант с задержкой и синхронизацией
begin
  TTask.Run(
    procedure
    begin
      MyTaskDelay(StartDelayMS, inProgramClosing, True);
      Method;
    end);
end;

function TMyTaskNotAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
const Method: TThreadProcedure): TMyTask;
// Не самоубивающийся вариант с задержкой и синхронизацией
begin
  Result := TMyTask.Create(FuncName, False, StartDelayMS, False, Method, inProgramClosing);
end;

procedure TMyTaskSynchronizedAutoFree(const FuncName: string; const StartDelayMS: Cardinal; const inProgramClosing: TMyFlag;
const Method: TMyProc);
// Самоубивающися вариант с синхронизацией и задержкой
begin
  TTask.Run(
    procedure
    begin
      MyTaskDelay(StartDelayMS, inProgramClosing, True);
      TThread.Synchronize(nil,
        procedure
        begin
          Method;
        end);
    end);
end;

function TMyTaskSynchronizedNotAutoFree(const FuncName: string; const StartDelayMS: Cardinal;
const inProgramClosing: TMyFlag; const Method: TThreadProcedure): TMyTask;
// Не самоубивающися вариант с синхронизацией и задержкой
begin
  Result := TMyTask.Create(FuncName, False, StartDelayMS, True, Method, inProgramClosing)
end;

{$REGION 'TMyTask'}

constructor TMyTask.Create(const FuncName: string; const AutoFree: Boolean; const StartDelayMS: Cardinal;
const Synchronize: Boolean; const Method: TThreadProcedure; const inProgramClosing: TMyFlag);
begin
{$IFDEF MyTaskDEBUG}
  AtomicIncrement(TaskNumber);
  FTaskNumber := TaskNumber; // Запомним порядковый номер таска с момента запуска программы
  AtomicIncrement(TaskCount);
  LogDebug('Create: TaskNumber = ' + FTaskNumber.ToString + ', Counter = ' + TInterlocked.Read(TaskCount).ToString);
{$ENDIF MyTaskDEBUG}
  FMethod := Method;
  FreeOnTerminate := AutoFree;
  FStartDelay := StartDelayMS;
  FSynchronize := Synchronize;
  FProgramClosing := inProgramClosing;

  // Пробуждаем поток!
  inherited Create(False);

  SpecialName := FuncName; // Имя потока  только после Create!! Иначе будет падать
end;

destructor TMyTask.Destroy;
begin
{$IFDEF MyTaskDEBUG}
  AtomicDecrement(TaskCount);
  LogDebug('Destroy: TaskNumber = ' + FTaskNumber.ToString + ', Counter = ' + TInterlocked.Read(TaskCount).ToString);
{$ENDIF MyTaskDEBUG}
  inherited;
end;

procedure TMyTask.LogDebug(Mes: string);
// Логирование Важных событий
begin
  Mes := 'TMyTask.LogDebug: ' + Mes;
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Mes));
{$ENDIF MSWINDOWS}
end;

procedure TMyTask.Execute;
begin
  inherited; // Должно быть первой строчкой, чтобы сработал NameThread(ClassName) у TMyThread.Execute

  // ImAlive;  Тут не нужно, т.к. поток только что создался (падало по непонятной причине)

  MyTaskDelay(FStartDelay, FProgramClosing, False { Работаем на потоке, а не таске } );

  if FSynchronize then
    Synchronize(FMethod)
  else
    FMethod();

  Terminate; // Самоубъёмся
end;

// Ждёт завершения выполнения задачи
// Данный метод можно использовать, только если FreeOnTerminate = False!!!!
procedure TMyTask.WaitForFinish(const inProgramClosing: TMyFlag);
// inProgramClosing - чтобы не тянуть ClearFunction
begin
  if FreeOnTerminate then
  begin
    raise Exception.Create('Не правильное использование TMyTask.WaitForFinish!');
    Exit;
  end;

  repeat
    // Обращаемся к переменной по ссылке, чтобы не тянуть UClearFunction
    if inProgramClosing then
      Terminate;

    Application.ProcessMessages; // Нужен, чтобы не зависал интерфейс

    if Assigned(self) and not Finished and not Terminated then
      Sleep(10); // Ждём, только если нужно!
  until not Assigned(self) or Finished or Terminated;
end;

{$ENDREGION 'TMyTask'}
{$REGION 'TTimerTask'}

{ Максимально гибкий конструктор для тех кто знает, что ему нужно и для среды тестирования.
  Для началы работы необходимо вызвать метод Start! В конце задачу нужно убить, если AOwnerFreeTask = False ! }
constructor TTimerTask.Create(
{ } const AOwner: TTimerThread;
{ } const AOwnerFreeTask: Boolean;
{ } const AInitialTimeoutSec: Cardinal;
{ } const ARepeatTimeoutSec: Cardinal;
{ } const AShouldRepeat: Boolean;
{ } const AAction: TTimerAction);
begin
  inherited Create;
  FOwner := AOwner;
  FOwnerFreeTask := AOwnerFreeTask;
  FInitialTimeout := AInitialTimeoutSec;
  FRepeatTimeout := ARepeatTimeoutSec;
  FShouldRepeat := AShouldRepeat;
  FAction := AAction;
  FExecuted := False;
  FCreateTime := Now;
  LastTime := Now; // Нельзя работать через FLastTime!
  // Для начала работы нужно вручную вызвать метод Start !
end;

{ Конструктор с авто стартом для задач с повтором. Используется в главном таймере MainLogic. Задачу убьёт поток-владелец! }
constructor TTimerTask.Create(
{ } const AOwner: TTimerThread;
{ } const AInitialTimeoutSec: Cardinal;
{ } const ARepeatTimeoutSec: Cardinal;
{ } const AAction: TTimerAction);
begin
  // Поток-владелец сам убъёт задачу
  self.Create(AOwner, True, AInitialTimeoutSec, ARepeatTimeoutSec, True, AAction);

  Start; // Сразу сами запускаем себя в работу!
end;

{ Конструктор с авто стартом для однократного выполнения задачи. Задачу убьёт поток-владелец! }
constructor TTimerTask.Create(
{ } const AOwner: TTimerThread;
{ } const AInitialTimeoutSec: Cardinal;
{ } const AAction: TTimerAction);
begin
  // Поток-владелец сам убъёт задачу
  self.Create(AOwner, True, AInitialTimeoutSec, 0, False, AAction);

  Start; // Сразу сами запускаем себя в работу!
end;

destructor TTimerTask.Destroy;
begin
  // Удалить себя из треда таймера
  FOwner := nil;
  FAction := nil;
  inherited Destroy;
end;

function TTimerTask.CanRun: Boolean;
begin
  {
    Golovachev: 2025-08-29:
    Сначала смотрим, если указали задержку перед началом таймера то проверяем ее.
    Потом как только выяснили, что момент нужный наступил по изначальной задержке,
    сбрасываем изначальную задержку и следим уже за таймаутом как часто
    повторять задачу.

    Vova: 2025-10-02:
    После проверки начальной задержки идёт проверка на одноразовые события по
    задержки повтора, иначе после первого повтора, таймер выполняет событие каждый
    такт.
  }
  if FInitialTimeout <= 0 then // Нельзя работать через FLastTime!
    Result := SecondsBetween(LastTime, Now) >= FRepeatTimeout
  else
  begin // Нельзя работать через FLastTime!
    Result := SecondsBetween(LastTime, Now) >= FInitialTimeout;
    if Result then
      FInitialTimeout := 0;
  end;
end;

function TTimerTask.GetCreateTime: TDatetime;
begin
  Result := FCreateTime;
end;

procedure TTimerTask.Start;
begin
  CheckOwnerAssigned();
  if not FOwner.Terminated then
  begin
    FOwner.Add(self);
    // При добавлении задачи, начинаем отсчёт времени для срабатывания
    LastTime := Now;
  end;
end;

procedure TTimerTask.Stop;
begin
  CheckOwnerAssigned();
  if not FOwner.Terminated then
    FOwner.Remove(self);
end;

procedure TTimerTask.ExecuteNow;
begin
  if not FExecuted then
  begin
    if Assigned(FAction) then
      // Задача может выполняться долго, поэтому запускаем таску, что бы не держать поток таймера
      TMyTaskAutoFree('TTimerTask.ExecuteNow',
        procedure()
        begin
          FAction(self);
        end);

    LastTime := Now; // Обновляем время выполнения (запуска) задачи

    { Golovachev: 2025-08-29
      Если не стоит флаг повтора - то мы один раз запустимся и все. Далее
      таска должна дойти в какой то момент до стопа и себя убрать из
      потока таймера (сама) }
    if not FShouldRepeat then
      FExecuted := True;
  end;
end;

{ -------------------------------------------------------------------------- }

function TTimerTask.GetLastTime: TDatetime;
begin
  // Атамарное чтение времени
  Result := UnixToDateTime(TInterlocked.CompareExchange(FLastTime, 0, 0), False);
end;

procedure TTimerTask.SetLastTime(const ATime: TDatetime);
begin
  // Атамарная установка времени
  TInterlocked.Exchange(FLastTime, DateTimeToUnix(ATime, False));
end;

function TTimerTask.IsOwnerFree: Boolean;
begin
  Result := FOwnerFreeTask;
end;

function TTimerTask.IsShouldRepeat: Boolean;
begin
  Result := False;
end;

procedure TTimerTask.SetShouldRepeat(const AValue: Boolean);
begin
  FShouldRepeat := AValue;
end;

function TTimerTask.GetRepeatTimeout: Cardinal;
begin
  Result := FRepeatTimeout;
end;

procedure TTimerTask.CheckOwnerAssigned;
begin
  if not Assigned(FOwner) then
    raise Exception.Create(Format('%s: Не задан поток выполнения!', [self.Classname]));
end;

{$ENDREGION 'TTimerTask'}
{$REGION 'TTimerThread'}

constructor TTimerThread.Create(
{ } const AEnabled: Boolean;
{ } const ATimeoutMS: Cardinal;
{ } const ATimerName: string);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSync := TMyCriticalSection.Create(ATimerName);
  FTickSleep := ATimeoutMS;
  FTasks := TTimerTaskList.Create();
  FEnabled := AEnabled;
  SpecialName := ATimerName;
  Suspended := not FEnabled; // Сразу будим поток, если таймер активен
end;

constructor TTimerThread.Create(const ATimerName: string);
begin
  // По умолчанию таймер будет срабатывать раз в 1 секунду
  self.Create(True, 1000, ATimerName);
end;

destructor TTimerThread.Destroy;
var
  Task: TAbstractTimerTask;
begin
  FSync.Enter('Destroy');
  try
    for Task in FTasks do
      if Task.OwnerFree then
        Task.Free; // Нельзя использовать FreeAndNil для переменной цикла for-in
  finally
    FSync.Leave('Destroy');
  end;
  //
  // FreeAndNIl(FTasks);
  // finally
  // FSync.Leave('Destroy');
  // end;

  FreeAndNIl(FSync);
  FreeAndNIl(FTasks);

  inherited Destroy;
end;

procedure TTimerThread.Add(const ATask: TAbstractTimerTask);
{ Добавить задачу. Используется в TTimerTask.Start }
begin
  FSync.Enter('Add');
  try
    if FTasks.IndexOf(ATask) < 0 then
      FTasks.Add(ATask);
    FTasks.TrimExcess();
  finally
    FSync.Leave('Add');
  end;
end;

procedure TTimerThread.Remove(const ATask: TAbstractTimerTask);
{ Добавить задачу. Используется в TTimerTask.Start }
var
  Idx: NativeInt;
begin
  FSync.Enter('Remove');
  try
    Idx := FTasks.IndexOf(ATask);
    if Idx >= 0 then
      FTasks.Delete(Idx);
    // FTasks.Remove(ATask);
    FTasks.TrimExcess();
  finally
    FSync.Leave('Remove');
  end;
end;

procedure TTimerThread.DoTimer;
{ Обработать по наступившему таймауту добавленные задачи. Под обработать
  подразумевается спросить каждую, пришло ли время выполнится или нет. }
var
  Task: TAbstractTimerTask;
begin
  FSync.Enter('DoTimer');
  try
    for Task in FTasks do
      if not Terminated and Assigned(Task) and Task.CanRun then
        Task.ExecuteNow;
  finally
    FSync.Leave('DoTimer');
  end;
end;

procedure TTimerThread.Execute;
var
  ST: UInt64; { }
  TimeToSleep: Integer; { Должно быть со знаком, чтобы не было переполнения при минусе }
begin
  inherited Execute;

  // Первый раз просто спим указанный интервал
  DelayForThread(self, FTickSleep);

  while not Terminated do
  begin
    ImAlive();
    ST := GetTickCount64; // Засекаем время выполения таймера. GetTickCount64 не боится перевода времени!

    if Enabled then
      DoTimer;

    // Спим столько, сколько осталось до FTickSleep с учётом времени выполнения таймера
    TimeToSleep := FTickSleep - (GetTickCount64 - ST);
    if TimeToSleep > 200 then // При долгом сне используем метод с контролем завершения потока\программы
      DelayForThread(self, TimeToSleep)
    else if TimeToSleep > 0 then
      Sleep(TimeToSleep)
    else
      Sleep(1); // Минимальное обязательное время сна, чтобы не грузить проц
  end;
end;

function TTimerThread.GetTickSleep: Cardinal;
begin
  Result := FTickSleep;
end;

procedure TTimerThread.SetTickSleep(const AValue: Cardinal);
begin
  FTickSleep := AValue;
end;

function TTimerThread.GetEnabled: Boolean;
begin
  FSync.Enter(self.Classname + '.GetEnabled');
  try
    Result := FEnabled;
  finally
    FSync.Leave(self.Classname + '.GetEnabled');
  end;
end;

procedure TTimerThread.SetEnabled(const AValue: Boolean);
var
  Task: TAbstractTimerTask;
begin
  FSync.Enter(self.Classname + '.SetEnabled');
  try
    FEnabled := AValue;

    { Обновим время последнего выполнения при активации таймера,
      чтобы пошел отсчёт времени "с нуля" }
    for Task in FTasks do
      Task.LastTime := Now;
  finally
    FSync.Leave(self.Classname + '.SetEnabled');
  end;

  { Будим поток, если нужно }
  if AValue and Suspended then
    Suspended := False;
end;

{$ENDREGION 'TTimerThread'}
{$REGION 'TTimerThread.TTimerTaskList'}

constructor TTimerThread.TTimerTaskList.Create;
begin
  inherited Create;
  // inherited Create(True);
end;

destructor TTimerThread.TTimerTaskList.Destroy;
begin
  //
  inherited Destroy;
end;

{$ENDREGION 'TTimerThread.TTimerTaskList'}

end.
