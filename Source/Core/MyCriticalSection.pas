{ ******************************************************************************
  Класс безопасной критической секции, которая автоматически логирует
  зависания Deadlock и замедление работы (долгое ожидание входа).

  При работе из под Delphi позволяет использовать TMonitor вместо TCriticalSection,
  что даёт ускорение до 4 раз!!

  Разработал DoctorS, 2024.
  ****************************************************************************** }

unit MyCriticalSection;

{$IF defined(USPD) and defined(DEBUG)}
{$DEFINE DEBUGMEM} // На УСПД в дебаге всегда включаем DEBUGMEM
{$ENDIF}
// Включение отладки крит.секций в дебаге
{$IFDEF DEBUGMEM}
{$DEFINE DEBUG_CRIT_SEC} // Отладка Критических секций по умолчанию только в дебаге!
{$ENDIF DEBUGMEM}
//
// Совместимость с УСПД
{$IFDEF USPD}
{$I 'directives.inc'}
{$ENDIF USPD}

interface

// Здесь не должно быть ClearFunctions, SysFunc и других зависимостей от Ресурса и УСПД!
uses SysUtils, Classes,
{$IFDEF DEBUG_CRIT_SEC}
  Generics.Collections,
{$ENDIF DEBUG_CRIT_SEC}
  SyncObjs;

type

{$IFNDEF FPC}
  // Особенности стандартного TLightweightMREW, которые призван решить TMyLightweightMREW
  // Проблемы:
  // 1. Отсутсвует поддержка рекурсивной записи (в Windows зависнет, в POSIX возникнет исключение) - решено
  // 2. Отсуствует поддержка чтения для потока, который пишет - решаю
  // Плюсы:
  // 1. Рекурсивное чтение поддерживается "из коробки"
  TMyLightweightMREW = record
  private
    FRWLock: TLightweightMREW;
    FLockForWriteThreadID: Int64;
    FLockForWriteCount: Int64;
    FLockForReadCount: Int64;
    FLastWriteFuncName: string;
  public
    class operator Initialize(out Dest: TMyLightweightMREW);

    procedure BeginWrite(const FuncName: string);
    function TryBeginWrite(const FuncName: string): Boolean;
    procedure EndWrite(const FuncName: string);

    procedure BeginRead;
    function TryBeginRead: Boolean;
    procedure EndRead;
  end;
{$ENDIF FPC}

  // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

  TMyCriticalSection = class(TSynchroObject)
  type
    // Тип блокировки: крит.секция, на чтение, на запись, объект
    TLockType = (ltCritSec, ltRead, ltWrite, ltObj);
  strict private
    FProtectedObj: TObject; // Защищаемый объект для TMonitor
    FCriticalSection: TCriticalSection; // Крит.секция, если используется не TMonitor
{$IFNDEF FPC}
    // Синхронайзер для защиты объекта, который гораздо чаще читают, чем пишут (только Delphi)
    FSynchronizer: TMyLightweightMREW; // Быстрее TMultiReadExclusiveWriteSynchronizer
{$ENDIF FPC}
    FProtectedObjName: string;
    FFullLog: Boolean;
    FDeadTimeMS: Word;
{$HINTS OFF} // FLastFuncName может быть нужен УСПД
    FLastFuncName: string; // H2219 Private symbol 'FLastFuncName' declared but never used
{$HINTS ON}
{$IFDEF DEBUG_CRIT_SEC}
    // Стек типа блокировок. Работает по принципу: "Послений вошел, первый вышел"
    FLockTypeStack: TStack<TLockType>;
    // Служебная крит.сек. для атомарности операций Enter, Leave, LockObj, UnLockObj и т.д.
    FStackCritSec: TCriticalSection;
{$ENDIF DEBUG_CRIT_SEC}
    // Логирование событий
    procedure LogDebug( { const } Mes: string); // Логирование Рядовых событий
    procedure LogWarning( { const } Mes: string); // Логирование Тревожных событий
    procedure LogCritSec( { const } Mes: string); // Логирование Критических секций
{$IFDEF DEBUG_CRIT_SEC}
    function LockTypeToString(lt: TLockType): string;
    procedure AddLockType(const LockType: TLockType); // Запоминает тип блокировки
{$ENDIF DEBUG_CRIT_SEC}
    // Используются только в Дебаге и при DEFINE DEBUG_CRIT_SEC
{$HINTS OFF} // Чтобы собирался УСПД в релизе
    procedure LogEnterResult(const StartTime: UInt64; const AFuncName, AMethodName: string);
    procedure LogExitResult(const AFuncName, AMethodName: string);
    procedure LogDeadLock(const AFuncName: string);
{$HINTS ON}
    // Поднимаем тревогу, если нужно!
{$IFDEF DEBUG_CRIT_SEC}
    procedure CheckLockType(const AFuncName: string; const LockType: TLockType);
    procedure CheckAssignedProtectedObj(const AFuncName: string);
{$ENDIF DEBUG_CRIT_SEC}
    procedure CheckEnterTimeAndLogDeadLock(var ShowedError: Boolean; const StartTime: UInt64; const AFuncName: string);
  public
    // Первый вариант конструктора: использует кртические секции для защиты произвольного куска кода
    constructor Create(const ObjectName: string; const DeadTimeMS: Word = 2000); overload;

    // Второй вариант конструктора: использует TMonitor в Delphi для защиты конкретного объекта !!
    // В Delphi TMonitor работает в 3 раза быстрее TCriticalSection
    // В FPC нет TMonitor, поэтому автоматически будет использоваться TCriticalSection для совместимости
    constructor Create(const ProtectedObj: TObject; const ObjectName: string; const DeadTimeMS: Word = 2000); overload;

    // Тут все умирают :)
    destructor Destroy; override;

    // Унаследовано от TSynchroObject }
    procedure Acquire; override;
    procedure Release; override;

    // Контролируемый вход и выход в крит.сек. с отслеживанием зависания DEAD LOCK !!!
    // Используется для защиты определённого куска кода от одновременных обращений из разных потоков !!!
    // Использовать только с Try Finally  !!!
    procedure Enter(const AFuncName: string); virtual;
    procedure Leave(const AFuncName: string); virtual;

    // Однократная(!) попытка входа. Вернёт True, если было свободно и вошли.
    function TryEnter(const AFuncName: string): Boolean;

    // Тоже самое, но для защиты одного конкретного объекта !!
    // В Delphi работает в 3 раза быстрее, чем Enter и Leave !!
    // Использовать только с Try Finally !!
    procedure LockObj(const AFuncName: string); virtual;
    procedure UnLockObj(const AFuncName: string); virtual;

{$IFNDEF FPC}
    // Если "критическую секцию" гораздо чаще читают, а не изменяют, то выгоднее использовать вот эти методы
    // Использовать только с Try Finally !!
    // ВНИМАНИЕ: Эти методы доступны только в Delphi! В FPC используйте Enter/Leave или LockObj/UnLockObj
    procedure LockForRead(const AFuncName: string); virtual;
    procedure UnLockAfterRead(const AFuncName: string); virtual;
    procedure LockForWrite(const AFuncName: string); virtual;
    procedure UnLockAfterWrite(const AFuncName: string); virtual;
{$ENDIF FPC}

    // Обновить защищаемый объект. Используется в TMySaveIniFile
    procedure UpdateProtectedObj(const ProtectedObj: TObject; const AutoLeaveEnter: Boolean);
  end;

  // Вариант критической секции с подсчётом числа входов\выходов (при рекурсивных входах\выходах)
  // Используется в TAbstractUndoHistoryManager
  TMyCriticalSectionWithEnterCount = class(TMyCriticalSection)
  strict private
    FEnterCount: Integer; // Число входов\выходов при рекурсивной работе с крит.секцией
    function GetEnterCount: Integer;
  public
    // Контролируемый вход и выход в крит.сек. с отслеживанием зависания DEAD LOCK !!!
    // Используется для защиты определённого куска кода от одновременных обращений из разных потоков !!!
    // Использовать только с Try Finally  !!!
    procedure Enter(const AFuncName: string); override;
    procedure Leave(const AFuncName: string); override;

    // Тоже самое, но для защиты одного конкретного объекта !!
    // В Delphi работает в 3 раза быстрее, чем Enter и Leave !!
    // Использовать только с Try Finally !!
    procedure LockObj(const AFuncName: string); override;
    procedure UnLockObj(const AFuncName: string); override;

{$IFNDEF FPC}
    // Если "критическую секцию" гораздо чаще читают, а не изменяют, то выгоднее использовать вот эти методы
    // Использовать только с Try Finally !!
    // ВНИМАНИЕ: Эти методы доступны только в Delphi! В FPC используйте Enter/Leave или LockObj/UnLockObj
    procedure LockForRead(const AFuncName: string); override;
    procedure UnLockAfterRead(const AFuncName: string); override;
    procedure LockForWrite(const AFuncName: string); override;
    procedure UnLockAfterWrite(const AFuncName: string); override;
{$ENDIF FPC}

    // Число входов\выходов при рекурсивной работе с крит.секцией
    property EnterCount: Integer read GetEnterCount; // Для TUndoHistoryManager и TMyThreadList
  end;

implementation

uses
{$IFNDEF FPC}
{$IFDEF MSWINDOWS} // То, что нужно в Windows, но не FPC
  Windows,
{$ENDIF MSWINDOWS}
{$ENDIF FPC}
{$IFDEF FPC} // То, что нужно в FPC
{$IFNDEF USPD_TEST}
  uLog, GlobalObjects,
{$ENDIF USPD_TEST}
{$ENDIF FPC}
{$IFDEF OLDRESURS} // То, что нужно в Ресурсе
  LoggerUnit,
{$ENDIF OLDRESURS}
  // То, что нужно всем!
  TypInfo, DateUtils;

{ TMyLightweightMREW }
{$IFNDEF FPC}

class operator TMyLightweightMREW.Initialize(out Dest: TMyLightweightMREW);
begin
  Dest.FRWLock := default (TLightweightMREW); // Явная инициализация
  Dest.FLockForWriteThreadID := 0;
  Dest.FLockForWriteCount := 0;
  Dest.FLockForReadCount := 0;
  Dest.FLastWriteFuncName := '';
end;

// =============================== Запись ======================================

procedure TMyLightweightMREW.BeginWrite(const FuncName: string);
begin
  if TInterlocked.Read(FLockForWriteThreadID) = TThread.Current.ThreadID then
    AtomicIncrement(FLockForWriteCount)
  else
  begin
    FRWLock.BeginWrite;
    TInterlocked.Exchange(FLockForWriteThreadID, TThread.Current.ThreadID);
    TInterlocked.Exchange(FLockForWriteCount, 1);

    // Запомним первого, кто заблокировал на запись
    FLastWriteFuncName := FuncName;
  end;
end;

function TMyLightweightMREW.TryBeginWrite(const FuncName: string): Boolean;
begin
  if TInterlocked.Read(FLockForWriteThreadID) = TThread.Current.ThreadID then
  begin
    AtomicIncrement(FLockForWriteCount);
    Result := True;
  end
  else
  begin
    Result := FRWLock.TryBeginWrite;
    if Result then
    begin
      TInterlocked.Exchange(FLockForWriteThreadID, TThread.Current.ThreadID);
      TInterlocked.Exchange(FLockForWriteCount, 1);
      // Запомним первого, кто заблокировал на запись
      FLastWriteFuncName := FuncName;
    end;
  end;
end;

procedure TMyLightweightMREW.EndWrite(const FuncName: string);
var
  LockForWriteCount, LockForReadCount: Int64;
begin
  // Пытаются разблокировать из другого потока!
  if TInterlocked.Read(FLockForWriteThreadID) <> TThread.Current.ThreadID then
    raise Exception.Create('TMyLightweightMREW.EndWrite: разблокировка не из того потока! FuncName = ' + FuncName +
      ', FLastWriteFuncName = ' + FLastWriteFuncName + ', FLockForWriteThreadID = ' + TInterlocked.
      Read(FLockForWriteThreadID).ToString + ', Current.ThreadID = ' + TThread.Current.ThreadID.ToString);

  LockForWriteCount := AtomicDecrement(FLockForWriteCount);

  if LockForWriteCount = 0 then
  begin
    LockForReadCount := TInterlocked.Read(FLockForReadCount);
    if LockForReadCount <> 0 then
      raise Exception.Create('TMyLightweightMREW.EndWrite: число блокировок на чтение не равно нулю (' +
        LockForReadCount.ToString + ')' + ' в EndWrite!');

    // ВАЖНО: Правильный порядок освобождения для избежания race condition!
    // Сначала сбрасываем состояние (пока блокировка ещё удерживается)
    FLastWriteFuncName := '';
    TInterlocked.Exchange(FLockForWriteThreadID, 0);
    // Освобождаем базовую блокировку ПОСЛЕДНЕЙ!
    FRWLock.EndWrite;
  end
  else if LockForWriteCount < 0 then
    raise Exception.Create('TMyLightweightMREW.EndWrite: число блокировок на запись меньше нуля');
end;

// ============================== Чтение =======================================

procedure TMyLightweightMREW.BeginRead;
begin
  // Если текущий поток уже удерживает запись - увеличиваем внутренний счётчик чтений для этого потока
  if TInterlocked.Read(FLockForWriteThreadID) = TThread.Current.ThreadID then
    AtomicIncrement(FLockForReadCount)
  else // Иначе захватываем реальную блокировку на чтение, если её еще не было
    FRWLock.BeginRead;
end;

function TMyLightweightMREW.TryBeginRead: Boolean;
begin
  // Если текущий поток уже удерживает запись - увеличиваем внутренний счётчик чтений для этого потока
  if TInterlocked.Read(FLockForWriteThreadID) = TThread.Current.ThreadID then
  begin
    AtomicIncrement(FLockForReadCount);
    Result := True;
  end
  else // Иначе пробуем захватить реальную блокировку на чтение, если раньше этого ни кто не сделал
    Result := FRWLock.TryBeginRead;
end;

procedure TMyLightweightMREW.EndRead;
begin
  // Если окончание чтения из потока записи - просто уменьшаем счётчик
  if TInterlocked.Read(FLockForWriteThreadID) = TThread.Current.ThreadID then
  begin
    if AtomicDecrement(FLockForReadCount) < 0 then
      raise Exception.Create('TMyLightweightMREW.EndRead: число блокировок на чтение меньше нуля!');
  end
  else // Иначе заканчиваем настоящее чтение
    FRWLock.EndRead;
end;

{$ENDIF FPC}
{ TMyCriticalSection }

constructor TMyCriticalSection.Create(const ObjectName: string; const DeadTimeMS: Word = 2000);
// Первый вариант конструктора: использует кртические секции или Synchronizer для защиты произвольного куска кода
begin
  FProtectedObj := nil;
  FProtectedObjName := ObjectName;
  FDeadTimeMS := DeadTimeMS;
  FCriticalSection := TCriticalSection.Create;

  // В FPC включаем подробный лог, если активирована отладка крит.секций в настройках!!!
{$IFDEF FPC}
{$IFNDEF USPD_TEST}
// Включаем DEBUG_CRIT_SEC, если на УСПД включена отладка крит.секций !!!
  // К сожалению, так не работает! $DEFINE работает всегда независимо от if
  if Assigned(ConfigManager) then
  begin
    if ConfigManager.WriteCriticalSection then
    begin
      FFullLog := True; // Не трогай! А то сломается логирование крит.секций на УСПД!!
      // {$DEFINE DEBUG_CRIT_SEC}; // К сожалению, так не работает! $DEFINE работает всегда независимо от if
    end;
  end
  else
    SaveCriticalSectionDebug('ERROR:   TMyCriticalSection.Create 1 NOT Assigned(ConfigManager) !!!');
{$ENDIF USPD_TEST}
{$ELSE FPC} // В Delphi по умолчанию он не нужен
  FFullLog := False;
{$ENDIF FPC}
{$IFDEF DEBUG_CRIT_SEC}
  // Стек типа блокировок. Работает по принципу: "Послений вошел, первый вышел"
  FLockTypeStack := TStack<TLockType>.Create;
  // Служебная крит.сек. для атомарности операций Enter, Leave, LockObj, UnLockObj и т.д.
  FStackCritSec := TCriticalSection.Create;
{$ENDIF DEBUG_CRIT_SEC}
end;

constructor TMyCriticalSection.Create(const ProtectedObj: TObject; const ObjectName: string; const DeadTimeMS: Word = 2000);
// Второй вариант конструктора: использует TMonitor в Delphi для защиты конкретного объекта !!
// В Delphi TMonitor работает в 3 раза быстрее TCriticalSection
// В FPC нет TMonitor, поэтому автоматически будет использоваться TCriticalSection для совместимости
begin
  FProtectedObj := ProtectedObj;
  FProtectedObjName := ObjectName;
  FDeadTimeMS := DeadTimeMS;

  FCriticalSection := TCriticalSection.Create;

  // В FPC включаем подробный лог, если активирована отладка крит.секций в настройках!!!
{$IFDEF FPC}
{$IFNDEF USPD_TEST}
  // Включаем DEBUG_CRIT_SEC, если на УСПД включена отладка крит.секций !!!
  // К сожалению, так не работает! $DEFINE работает всегда независимо от if
  if Assigned(ConfigManager) then
  begin
    if ConfigManager.WriteCriticalSection then
    begin
      FFullLog := True; // Не трогай! А то сломается логирование крит.секций на УСПД!!
      // {$DEFINE DEBUG_CRIT_SEC}; // К сожалению, так не работает! $DEFINE работает всегда независимо от if
    end;
  end
  else
    SaveCriticalSectionDebug('ERROR:   TMyCriticalSection.Create 2 NOT Assigned(ConfigManager) !!!');
{$ENDIF USPD_TEST}
{$ELSE FPC} // В Delphi по умолчанию он не нужен
  FFullLog := False;
{$ENDIF FPC}
{$IFDEF DEBUG_CRIT_SEC}
  // Стек типа блокировок. Работает по принципу: "Послений вошел, первый вышел"
  FLockTypeStack := TStack<TLockType>.Create;
  // Служебная крит.сек. для атомарности операций Enter, Leave, LockObj, UnLockObj и т.д.
  FStackCritSec := TCriticalSection.Create;
{$ENDIF DEBUG_CRIT_SEC}
end;

destructor TMyCriticalSection.Destroy;
begin
  // Войдём, перед уничтожением, чтобы это не сделал кто-то другой
  if Assigned(FProtectedObj) then
  begin
    LockObj('TMyCriticalSection.Destroy');
    try
      // Критическая секция занята, можно безопасно освобождать ресурсы
    finally
      UnLockObj('TMyCriticalSection.Destroy');
    end;
  end
  else
  begin
    Enter('TMyCriticalSection.Destroy');
    try
      // Критическая секция занята, можно безопасно освобождать ресурсы
    finally
      Leave('TMyCriticalSection.Destroy');
    end;
  end;

  FreeAndNil(FCriticalSection);
{$IFDEF DEBUG_CRIT_SEC}
  FreeAndNil(FLockTypeStack);
  FreeAndNil(FStackCritSec); // В самом конце
{$ENDIF DEBUG_CRIT_SEC}
  FLastFuncName := ''; // Пробуем бороться с утечкой строк
  FProtectedObjName := ''; // Пробуем бороться с утечкой строк
  inherited;
end;

procedure TMyCriticalSection.Acquire;
begin
  Enter('TMyCriticalSection.Acquire');
end;

procedure TMyCriticalSection.Release;
begin
  Leave('TMyCriticalSection.Release');
end;

procedure TMyCriticalSection.UpdateProtectedObj(const ProtectedObj: TObject; const AutoLeaveEnter: Boolean);
// Обновить защищаемый объект. Используется в TMySaveIniFile
begin
  if AutoLeaveEnter then
    UnLockObj('UpdateProtectedObj');

  FProtectedObj := ProtectedObj;

  if AutoLeaveEnter then
    LockObj('UpdateProtectedObj');
end;

procedure TMyCriticalSection.Enter(const AFuncName: string);
// Контролируемый вход в крит.сек. с отслеживанием зависания DEAD LOCK !!!
{$IFDEF DEBUG_CRIT_SEC}
var
  StartTime: UInt64;
  ShowedError: Boolean;
{$ENDIF DEBUG_CRIT_SEC}
begin
{$IFNDEF DEBUG_CRIT_SEC}
  FCriticalSection.Enter; // Быстрый вариант
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой

  // Пробуем войти в критическую секцию
  StartTime := GetTickCount64;
  ShowedError := False;
  while not FCriticalSection.TryEnter do
    CheckEnterTimeAndLogDeadLock(ShowedError, StartTime, AFuncName);

  LogEnterResult(StartTime, AFuncName, 'TCriticalSection');  
  AddLockType(TLockType.ltCritSec); // Запомним тип блокировки!
{$ENDIF DEBUG_CRIT_SEC}

  FLastFuncName := AFuncName; // Запомним, какая сволочь заняла крит.секцию! (нужно всегда для LogDeadLock)
end;

procedure TMyCriticalSection.Leave(const AFuncName: string);
begin
{$IFNDEF DEBUG_CRIT_SEC}  // Быстрый вариант
  FCriticalSection.Leave;
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  CheckLockType(AFuncName, TLockType.ltCritSec);

  FCriticalSection.Leave;

  LogExitResult(AFuncName, 'TCriticalSection');
{$ENDIF DEBUG_CRIT_SEC}
end;

function TMyCriticalSection.TryEnter(const AFuncName: string): Boolean;
// Однократная(!) попытка входа. Вернёт True, если было свободно и вошли.
begin
  Result := FCriticalSection.TryEnter;
{$IFDEF DEBUG_CRIT_SEC}  // Быстрый вариант
  if Result then
  begin // Время входа засекать нет смысла (либо сразу вошли, либо мнет), поэтому просто передаём GetTickCount64
    LogEnterResult(GetTickCount64, AFuncName, 'TCriticalSection');
    FLastFuncName := AFuncName; // Запомним, какая сволочь заняла крит.секцию!
    AddLockType(TLockType.ltCritSec); // Запомним тип блокировки!
  end;
{$ENDIF DEBUG_CRIT_SEC}
end;

procedure TMyCriticalSection.LockObj(const AFuncName: string);
{$IFNDEF FPC}
var
  StartTime: UInt64;
  ShowedError: Boolean;
{$ENDIF FPC}
begin
{$IFNDEF DEBUG_CRIT_SEC}  // Быстрый вариант
  //
{$IFDEF FPC} // TMonitor отсуствует в FPC, поэтому используем обычные крит.секции
  Enter(AFuncName);
{$ELSE FPC} // В Delphi TMonitor работает в 3 раза быстрее крит.секций
  // Пробуем войти в TMonitor секцию (всегда через цикл!)
  StartTime := GetTickCount64;
  ShowedError := False;
  while not TMonitor.Enter(FProtectedObj, FDeadTimeMS) do
    CheckEnterTimeAndLogDeadLock(ShowedError, StartTime, AFuncName);
{$ENDIF FPC}
  //
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой

  // Проверим, на сколько внимательно программисты читали описание класса!
  CheckAssignedProtectedObj(AFuncName);

{$IFDEF FPC} // TMonitor отсуствует в FPC, поэтому используем обычные крит.секции
  Enter(AFuncName);
{$ELSE FPC} // В Delphi TMonitor работает в 3 раза быстрее крит.секций
  // Пробуем войти в TMonitor секцию (всегда через цикл!)
  StartTime := GetTickCount64;
  ShowedError := False;
  while not TMonitor.Enter(FProtectedObj, FDeadTimeMS) do
    CheckEnterTimeAndLogDeadLock(ShowedError, StartTime, AFuncName);

  LogEnterResult(StartTime, AFuncName, 'TMonitor');
{$ENDIF FPC}
  AddLockType(TLockType.ltObj); // Запомним тип блокировки!
{$ENDIF DEBUG_CRIT_SEC}

  FLastFuncName := AFuncName; // Запомним, какая сволочь заняла крит.секцию! (нужно всегда для LogDeadLock)
end;

procedure TMyCriticalSection.UnLockObj(const AFuncName: string);
begin
{$IFNDEF DEBUG_CRIT_SEC}  // Быстрый вариант
  //
{$IFDEF FPC} // TMonitor отсуствует в FPC, поэтому используем обычные крит.секции
  Leave(AFuncName);
{$ELSE FPC} // В Delphi TMonitor работает в 3 раза быстрее крит.секций
  TMonitor.Exit(FProtectedObj);
{$ENDIF FPC}
  //
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  CheckLockType(AFuncName, TLockType.ltObj); // Проверим тип блокировки

  CheckAssignedProtectedObj(AFuncName); // Проверим, на сколько внимательно программисты читали описание класса!

{$IFDEF FPC} // TMonitor отсуствует в FPC, поэтому используем обычные крит.секции
  Leave(AFuncName);
{$ELSE FPC} // В Delphi TMonitor работает в 3 раза быстрее крит.секций
  TMonitor.Exit(FProtectedObj);
  LogExitResult(AFuncName, 'TMonitor');
{$ENDIF FPC}
{$ENDIF DEBUG_CRIT_SEC}
end;

{$IFNDEF FPC}
procedure TMyCriticalSection.LockForRead(const AFuncName: string);
{$IFDEF DEBUG_CRIT_SEC}
var
  StartTime: UInt64;
  ShowedError: Boolean;
{$ENDIF DEBUG_CRIT_SEC}
begin
{$IFNDEF DEBUG_CRIT_SEC}   // Быстрый вариант
  FSynchronizer.BeginRead;
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  StartTime := GetTickCount64;
  ShowedError := False;

  while not FSynchronizer.TryBeginRead do
    CheckEnterTimeAndLogDeadLock(ShowedError, StartTime, AFuncName);

  LogEnterResult(StartTime, AFuncName, 'TSynchronizer');
  AddLockType(TLockType.ltRead); // Запомним тип блокировки!
{$ENDIF DEBUG_CRIT_SEC}

  // НЕ пишем FLastFuncName здесь!
  // LockForRead допускает одновременный вход нескольких потоков,
  // поэтому конкурентная запись в FLastFuncName (UnicodeString, ref-counted)
  // вызывает race condition и утечку строк.
  // FLastFuncName используется только для диагностики deadlock,
  // а при чтении deadlock невозможен — запись не имеет смысла.
end;

procedure TMyCriticalSection.UnLockAfterRead(const AFuncName: string);
begin
{$IFNDEF DEBUG_CRIT_SEC} // Быстрый вариант
  FSynchronizer.EndRead;

{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  CheckLockType(AFuncName, TLockType.ltRead); // Проверим тип блокировки

  FSynchronizer.EndRead;

  LogExitResult(AFuncName, 'TSynchronizer');
{$ENDIF DEBUG_CRIT_SEC}
end;

procedure TMyCriticalSection.LockForWrite(const AFuncName: string);
{$IFDEF DEBUG_CRIT_SEC}
var
  StartTime: UInt64;
  ShowedError: Boolean;
{$ENDIF DEBUG_CRIT_SEC}
begin
{$IFNDEF DEBUG_CRIT_SEC} // Быстрый вариант
  FSynchronizer.BeginWrite(AFuncName);
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  StartTime := GetTickCount64;
  ShowedError := False;

  while not FSynchronizer.TryBeginWrite(AFuncName) do
    CheckEnterTimeAndLogDeadLock(ShowedError, StartTime, AFuncName);

  LogEnterResult(StartTime, AFuncName, 'TSynchronizer');
  AddLockType(TLockType.ltWrite); // Запомним тип блокировки!
{$ENDIF DEBUG_CRIT_SEC}

  FLastFuncName := AFuncName; // Запомним, какая сволочь заняла крит.секцию! (нужно всегда для LogDeadLock)
end;

procedure TMyCriticalSection.UnLockAfterWrite(const AFuncName: string);
begin
{$IFNDEF DEBUG_CRIT_SEC} // Быстрый вариант
  FSynchronizer.EndWrite(AFuncName);
{$ELSE DEBUG_CRIT_SEC}  // Медленный, но с отладкой
  CheckLockType(AFuncName, TLockType.ltWrite); // Проверим тип блокировки

  FSynchronizer.EndWrite(AFuncName);

  LogExitResult(AFuncName, 'TSynchronizer');
{$ENDIF DEBUG_CRIT_SEC}
end;
{$ENDIF FPC}

{$IFDEF DEBUG_CRIT_SEC}

procedure TMyCriticalSection.AddLockType(const LockType: TLockType);
// Запоминает тип блокировки
begin
  if Assigned(FLockTypeStack) then
  begin
    FStackCritSec.Enter; // Обеспечим атомарность выполнения функции
    try
      FLockTypeStack.Push(LockType); // Запомним тип блокировки!
    finally
      FStackCritSec.Leave;
    end;
  end;
end;

// ============================= Поднимаем ошибки ==============================

procedure TMyCriticalSection.CheckLockType(const AFuncName: string; const LockType: TLockType);
var
  ALock: TLockType;
begin
  if Assigned(FLockTypeStack) then
  begin
    FStackCritSec.Enter; // Обеспечим атомарность выполнения функции
    try
      if FLockTypeStack.Count = 0 then
        raise Exception.Create('TMyCriticalSection: Попытка разблокировки без предварительной блокировки! ' +
          'LockType = ' + LockTypeToString(LockType) + ', FuncName = ' + AFuncName);
      ALock := FLockTypeStack.Pop; // Извлекаем самый новый элемент из стека
    finally
      FStackCritSec.Leave;
    end;

    if ALock <> LockType then
      raise Exception.Create('TMyCriticalSection: Неправильный тип раблокировки ' + LockTypeToString(LockType) +
        ' при блокировке ' + LockTypeToString(ALock) + ' в ' + AFuncName);
  end;
end;

procedure TMyCriticalSection.CheckAssignedProtectedObj(const AFuncName: string);
begin
  // Проверим, на сколько внимательно программисты читали описание класса!
  if not Assigned(FProtectedObj) then
    raise Exception.Create
      ('Неправильное использование TMyCriticalSection! В конструктор не передан Объект для работы через TMonitor!' +
      sLineBreak + 'ProtectedObjName = ' + FProtectedObjName + ', FuncName = ' + AFuncName);
end;
{$ENDIF DEBUG_CRIT_SEC}
// ============================= Логирование ===================================

procedure TMyCriticalSection.LogCritSec( { const } Mes: string);
// Логирование Критических секций
begin
  Mes := 'TMyCriticalSection ' + Mes;

  // УСПД или просто FPC
{$IFDEF FPC} // Вариант для FPC
{$IFNDEF USPD_TEST}
  SaveCriticalSectionDebug(Mes);
{$ENDIF USPD_TEST}
{$ELSE FPC}
  // Ресурс или просто Delphi
{$IFDEF OLDRESURS} // Вариант для Ресурса
  SaveToFile(Mes);
{$ELSE OLDRESURS} // Delphi, но без Ресурса
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Mes));
{$ENDIF MSWINDOWS}
{$ENDIF OLDRESURS}
{$ENDIF FPC}
end;

procedure TMyCriticalSection.LogDebug( { const } Mes: string);
// Логирование Рядовых событий
begin
  Mes := 'TMyCriticalSection ' + Mes;

  // УСПД или просто FPC
{$IFDEF FPC} // Вариант для FPC
{$IFNDEF USPD_TEST}
  SaveDebugDebug(Mes);
{$ENDIF USPD_TEST}
{$ELSE FPC}
  // Ресурс или просто Delphi
{$IFDEF OLDRESURS} // Вариант для Ресурса
  SaveToFile(Mes);
{$ELSE OLDRESURS} // Delphi, но без Ресурса
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Mes));
{$ENDIF MSWINDOWS}
{$ENDIF OLDRESURS}
{$ENDIF FPC}
end;

procedure TMyCriticalSection.LogWarning( { const } Mes: string);
// Логирование Тревожных событий
begin
  Mes := 'TMyCriticalSection ' + Mes;

  // УСПД или просто FPC
{$IFDEF FPC} // Вариант для FPC
{$IFNDEF USPD_TEST}
  SaveWarningDebug(Mes);
{$ENDIF USPD_TEST}
{$ELSE FPC}
  // Ресурс или просто Delphi
{$IFDEF OLDRESURS} // Вариант для Ресурса
  SaveToFile(Mes);
{$ELSE OLDRESURS} // Delphi, но без Ресурса
{$IFDEF MSWINDOWS}
  OutputDebugString(PChar(Mes));
{$ENDIF MSWINDOWS}
{$ENDIF OLDRESURS}
{$ENDIF FPC}
end;

{$IFDEF DEBUG_CRIT_SEC}

function TMyCriticalSection.LockTypeToString(lt: TLockType): string;
begin
  Result := GetEnumName(TypeInfo(TLockType), Ord(lt));
end;
{$ENDIF DEBUG_CRIT_SEC}

// Логрование входов\выходов - используется только в Дебаге
procedure TMyCriticalSection.LogEnterResult(const StartTime: UInt64; const AFuncName, AMethodName: string);
var
  Mes: string;
begin
  if GetTickCount64 - StartTime > FDeadTimeMS then
  begin
    Mes := '"' + FProtectedObjName + '.' + AFuncName + '" ждала вход в "' + AMethodName + '" ' +
      (GetTickCount64 - StartTime).ToString + ' мс, т.к. она была занята методом "' + FLastFuncName + '"!';
    LogDebug(Mes)
  end
  else if FFullLog then
  begin
    Mes := '"' + FProtectedObjName + '.' + AFuncName + '" вошла в "' + AMethodName + '"';
    LogCritSec(Mes);
  end;
end;

procedure TMyCriticalSection.LogExitResult(const AFuncName, AMethodName: string);
var
  Mes: string;
begin
  if FFullLog then
  begin
    Mes := '"' + FProtectedObjName + '.' + AFuncName + '" вышла из "' + AMethodName + '"';
    LogCritSec(Mes);
  end;
end;

// ========== Контроль попытки входа и логирование зависания ===================

procedure TMyCriticalSection.LogDeadLock(const AFuncName: string);
var
  Mes: string;
begin
  Mes := 'DEAD LOCK!!! "' + FProtectedObjName + '.' + AFuncName +
    '" не может войти в крит. секцию, т.к. она занята методом "' + FLastFuncName + '"!';
  LogWarning(Mes)
end;

procedure TMyCriticalSection.CheckEnterTimeAndLogDeadLock(var ShowedError: Boolean; const StartTime: UInt64;
  const AFuncName: string);
// Контроль попытки входа и логирование зависания
begin
  // Если за 4 интервала смерти функция не вошла - поднимаем тревогу !!!
  if not ShowedError and (GetTickCount64 - StartTime >= Int64(FDeadTimeMS) * 4) then
  begin
    ShowedError := True;
    LogDeadLock(AFuncName);
  end;
  Sleep(Random(10)); // Ждём пока освободится случайное время, чтобы потоки могли "разойтись"...
end;

{ TMyCriticalSectionWithEnterCount }

procedure TMyCriticalSectionWithEnterCount.Enter(const AFuncName: string);
begin
  inherited;
  AtomicIncrement(FEnterCount); // Число входов в крит. секцию
end;

function TMyCriticalSectionWithEnterCount.GetEnterCount: Integer;
begin
  // Атамарное чтение (в FPC нет TInterlocked.Read)
  Result := TInterlocked.CompareExchange(FEnterCount, 0, 0);
end;

procedure TMyCriticalSectionWithEnterCount.Leave(const AFuncName: string);
begin
  inherited;
  AtomicDecrement(FEnterCount); // Число входов в крит. секцию
end;

procedure TMyCriticalSectionWithEnterCount.LockObj(const AFuncName: string);
begin
  inherited;
  AtomicIncrement(FEnterCount); // Число входов в крит. секцию
end;

procedure TMyCriticalSectionWithEnterCount.UnLockObj(const AFuncName: string);
begin
  inherited;
  AtomicDecrement(FEnterCount); // Число входов в крит. секцию
end;

{$IFNDEF FPC}
procedure TMyCriticalSectionWithEnterCount.LockForRead(const AFuncName: string);
begin
  inherited;
  AtomicIncrement(FEnterCount); // Число входов в крит. секцию
end;

procedure TMyCriticalSectionWithEnterCount.LockForWrite(const AFuncName: string);
begin
  inherited;
  AtomicIncrement(FEnterCount); // Число входов в крит. секцию
end;

procedure TMyCriticalSectionWithEnterCount.UnLockAfterRead(const AFuncName: string);
begin
  inherited;
  AtomicDecrement(FEnterCount); // Число входов в крит. секцию
end;

procedure TMyCriticalSectionWithEnterCount.UnLockAfterWrite(const AFuncName: string);
begin
  inherited;
  AtomicDecrement(FEnterCount); // Число входов в крит. секцию
end;
{$ENDIF FPC}

end.
