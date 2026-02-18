---
inclusion: fileMatch
fileMatchPattern: ['**/*.pas', '**/*.dpr', '**/*.dpk', '**/*.inc', '**/*.dfm', '**/*.fmx']
---

# Delphi — Стиль кода и паттерны (TTraid)

Код должен компилироваться в Delphi 11+. Платформа — Windows (FMX).

## Условная компиляция

```pascal
{$IFDEF MSWINDOWS}  // Windows
{$IFDEF DEBUG}      // Отладочная сборка
{$IFDEF RELEASE}    // Релизная сборка
```

Всегда указывай директиву после `{$ENDIF}`:
```pascal
{$IFDEF DEBUG}
  // отладочный код
{$ENDIF DEBUG}
```

## Именование

| Элемент | Формат | Пример |
|---------|--------|--------|
| Класс | `T` + PascalCase | `TOrderManager` |
| Интерфейс | `I` + PascalCase | `IApiClient` |
| Поле класса | `F` + PascalCase | `FAccountId` |
| Параметр | `A` или `In` + PascalCase | `AValue`, `InStream` |
| Локальная переменная | camelCase | `orderCount`, `isValid` |
| Константа | UPPER_CASE или PascalCase | `MAX_RETRY_COUNT` |

## Структура модуля

```pascal
unit UnitName;

interface

uses
  // 1. Системные модули
  SysUtils, Classes, SyncObjs,
  // 2. Core-модули проекта (ПРИОРИТЕТ!)
  MyCriticalSection, MyThread, MyFlag, MyThreadList, MyTask, MyIniFile, MyHttpClient;

type
  TMyClass = class
  strict private
    FField: Integer;
  public
    constructor Create;
    destructor Destroy; override;
  end;

implementation

uses
  // Модули только для implementation — избегай циклических зависимостей
  HelperModule;

end.
```

## Управление памятью — КРИТИЧНО

```pascal
// ПРАВИЛЬНО
FreeAndNil(FObject);
if Assigned(FObject) then FObject.DoSomething;

// НЕПРАВИЛЬНО — никогда так не делай
FObject.Free;  // Оставляет висячий указатель
FObject.DoSomething;  // Без проверки Assigned
```

Деструктор — освобождай в обратном порядке создания:
```pascal
destructor TMyClass.Destroy;
begin
  FreeAndNil(FChildObject);
  FreeAndNil(FCriticalSection);
  inherited Destroy;  // ПОСЛЕДНЕЙ строкой
end;
```

Ресурсы — всегда `try..finally`:
```pascal
Stream := TFileStream.Create(FileName, fmOpenRead);
try
  // работа со Stream
finally
  FreeAndNil(Stream);
end;
```

## Потоки — ТОЛЬКО TMyThread (не TThread!)

```pascal
procedure TWorkerThread.Execute;
var
  LastImAlive: TDateTime;
begin
  inherited;  // ПЕРВОЙ строкой — обязательно!
  LastImAlive := Now;

  while not Terminated do
  begin
    // Сигнал живости каждые 3 секунды для TThreadMonitor
    if SecondsBetween(Now, LastImAlive) > 3 then
    begin
      ImAlive;
      LastImAlive := Now;
    end;

    DoWork;
    DelayForThread(Self, 100);  // Вместо Sleep для контроля Terminated
  end;
end;
```

Завершение потока:
```pascal
TMyThread.TerminateAndFree<TWorkerThread>(FWorkerThread);
// После этого FWorkerThread = nil
```

## Задачи — ТОЛЬКО TMyTask (не TTask.Run!)

```pascal
// Самоубивающийся вариант без задержки
TMyTaskAutoFree('TOrderManager.SendOrder',
  procedure
  begin
    // код задачи
  end);

// С задержкой и контролем завершения программы
TMyTaskAutoFree('TOrderManager.RetryOrder', 2000, FProgramClosing,
  procedure
  begin
    // код задачи с задержкой 2 сек
  end);

// Не самоубивающийся (нужно дождаться результата)
var
Task := TMyTaskNotAutoFree('TOrderManager.CalcPosition',
  procedure
  begin
    // код задачи
  end);
try
  Task.WaitForFinish(FProgramClosing);
finally
  FreeAndNil(Task);
end;
```

## Межпоточные флаги — ТОЛЬКО TMyFlag (не Boolean!)

```pascal
var
  FProgramClosing: TMyFlag;  // Вместо Boolean

// Установка
FProgramClosing.IsSet := True;

// Проверка (потокобезопасно)
if FProgramClosing.IsSet then
  Exit;

// Можно использовать как Boolean (но IsSet безопаснее)
if FProgramClosing then
  Exit;
```

## Критические секции — ТОЛЬКО TMyCriticalSection

```pascal
// Вариант 1: защита куска кода
FCritSec := TMyCriticalSection.Create('TOrderManager.FOrders');
FCritSec.Enter('ProcessOrder');
try
  // защищённый код
finally
  FCritSec.Leave('ProcessOrder');
end;

// Вариант 2: защита объекта через TMonitor (в 3 раза быстрее!)
FCritSec := TMyCriticalSection.Create(FProtectedList, 'TOrderManager.FList');
FCritSec.LockObj('ProcessOrder');
try
  // защищённый код
finally
  FCritSec.UnLockObj('ProcessOrder');
end;

// Вариант 3: читают часто, пишут редко
FCritSec.LockForRead('GetOrderCount');
try
  Result := FOrders.Count;
finally
  FCritSec.UnLockAfterRead('GetOrderCount');
end;
```

## Потокобезопасные коллекции — ТОЛЬКО TMyThreadList и TMyThreadDictionary

```pascal
// Список
FOrders := TMyThreadList<TOrder>.Create('TOrderManager.FOrders');

var
List := FOrders.LockForRead('GetActiveOrders');
try
  for var Order in List do
    if Order.IsActive then
      ProcessOrder(Order);
finally
  FOrders.UnlockAfterRead('GetActiveOrders');
end;

// Словарь
FCache := TMyThreadDictionary<string, TInstrument>.Create('TInstrumentCache');

if FCache.TryGetValue(InstrumentId, Instrument) then
  Result := Instrument;
```

## HTTP-клиент — ТОЛЬКО TMyHttpClient (не TNetHTTPClient напрямую!)

```pascal
// Быстрый HTTPS POST без создания экземпляра (классовый метод)
var
  answer: string;
  statusCode: Integer;
begin
  if TMyHttpClient.HttpsClientPost(URL, RequestBody, answer, statusCode) then
    ProcessResponse(answer, statusCode);
end;

// Быстрый HTTPS GET
if TMyHttpClient.HttpsClientGet(URL, answer, statusCode) then
  ProcessResponse(answer, statusCode);

// Создание экземпляра для нескольких запросов подряд
var
Client := TMyHttpClient.CreateHTTPSClient;
try
  // Настройка прокси (опционально)
  Client.SetProxy('proxy.example.com', 8080);
  Client.SetProxyAuth('user', 'pass');

  // Добавление заголовков
  Client.CustomHeaders['Authorization'] := 'Bearer ' + Token;

  // Несколько запросов через один клиент
  Client.Post(URL1, Stream1);
  Client.Get(URL2);
finally
  FreeAndNil(Client);
end;

// Глобальная настройка клиента (прокси и т.д.) через callback
TMyHttpClient.OnConfigureClient := ConfigureHttpClient;

procedure TMainForm.ConfigureHttpClient(const AClient: TNetHTTPClient);
begin
  // Здесь можно настроить прокси, заголовки и т.д.
end;
```

## INI-файлы — ТОЛЬКО TMySaveIniFile

```pascal
// Быстрое чтение/запись (SavePeriodSec = 0 — сразу на диск)
var
Ini := TMySaveIniFile.Create('settings.ini', 0);
try
  Token := Ini.ReadString('Auth', 'Token', '');
finally
  FreeAndNil(Ini);
end;

// Продолжительная работа (SavePeriodSec = 5 — автосохранение каждые 5 сек)
FSettings := TMySaveIniFile.Create('settings.ini', 5);
```

## Потокобезопасность

Атомарные операции с Integer:
```pascal
// Чтение
Value := TInterlocked.CompareExchange(FCounter, 0, 0);
// Запись
TInterlocked.Exchange(FCounter, NewValue);
// Инкремент
TInterlocked.Increment(FCounter);
```

## Обработка ошибок — паттерн ErrorLine

```pascal
var
  ErrorLine: Integer;
begin
  ErrorLine := 0;
  try
    ErrorLine := 10; ValidateInput;
    ErrorLine := 20; ProcessData;
    ErrorLine := 30; SaveResult;
  except
    on E: Exception do
      SaveToFile(Format('Ошибка в строке %d: %s', [ErrorLine, E.Message]));
  end;
end;
```

## Замер времени — используй GetTickCount64

```pascal
var
  ST: UInt64;  // ST — стандартное имя для Start Time
begin
  ST := GetTickCount64;
  DoLongOperation;
  SaveToFile(Format('Выполнено за %d мс', [GetTickCount64 - ST]));
end;
```

## Современный синтаксис (Delphi 10.3+)

```pascal
// Inline-переменные — ВСЕГДА с переносом строки после var
var
Config := TConfig.Create;

var
List := FOrders.LockForRead('MethodName');

// for-in с inline-переменной
for var I := 0 to List.Count - 1 do
  ProcessItem(List[I]);

for var Item in List do
  ProcessItem(Item);
```

**НЕПРАВИЛЬНО** — inline-переменная в одну строку:
```pascal
var Config := TConfig.Create;  // НЕПРАВИЛЬНО!
var List := FOrders.LockForRead('MethodName');  // НЕПРАВИЛЬНО!
```

## Запрещённые практики

- `TThread` вместо `TMyThread` — нет мониторинга зависаний
- `TTask.Run` вместо `TMyTaskAutoFree` — нет контроля завершения
- `TCriticalSection` вместо `TMyCriticalSection` — нет диагностики deadlock
- `Boolean` для межпоточных флагов вместо `TMyFlag` — race condition
- `TThreadList` вместо `TMyThreadList` — нет диагностики
- `TIniFile` / `TMemIniFile` вместо `TMySaveIniFile` — нет потокобезопасности
- `TTimer` для фоновых задач вместо `TTimerThread` — блокирует GUI
- `TNetHTTPClient` напрямую вместо `TMyHttpClient` — нет единой настройки прокси
- `Obj.Free` без `FreeAndNil` — висячие указатели
- Обращение к объекту без `Assigned` — AV
- Глобальные переменные без синхронизации — race conditions
- `Sleep` в главном потоке GUI — зависание интерфейса
- `Now` для замера интервалов — используй `GetTickCount64`
- Пустые `except` блоки — скрывают ошибки
