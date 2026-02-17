{
  Потокобезопасные TList<>, TObjectList<>, TDictionary<> и TObjectDictionary<> основанные на TMyCriticalSection.
  Позволяют читать данные без блокировки, а писать с блокировкой из разных потоков.
  Перед Чтением обязательно делаем LockForRead, после - UnlockAfterRead.
  Перед Записью (изменением) обязательно делаем LockForWrite, после - UnlockAfterWrite.
  Обязательно использование try  finally  чтобы не было DeadBlock!!!
  Классы имеют TEnumerator, что позволяет использовать цикл for in, НО ТОЛЬКО НА ЧТЕНИЕ!!
  В целом лучше всегда делать LockForRead\UnlockAfterRead или LockForWrite\UnlockAfterWrite чтобы было меньше ошибок!

  DoctorS, 2021-2024!
}

unit MyThreadList;

// Включение отладки наших листов в дебаге!
{$IFDEF DEBUG}
{$DEFINE DEBUG_MyThreadList} // Отладка наших листов по умолчанию только в дебаге!
{$ENDIF DEBUG}

interface

uses
  // Здесь не должно быть ClearFunctions, SysFunc и других зависимостей от Ресурса и УСПД!
  Generics.Defaults, Generics.Collections, Types, MyCriticalSection;

type

  // Определяем SizeInt для Delphi
  SizeInt = Integer;

  // Класс прослойка для скрытия базового конструтора без параметров
  THideConstructor = class
  strict private
{$WARNINGS OFF}  // Warning: Constructor should be public
{$HINTS OFF}  // H2219 Private symbol 'Create' declared but never used
    constructor Create; reintroduce; // Конструктор без параметров под запретом!
{$HINTS ON}
{$WARNINGS ON}
  end;

  { TMyThreadListCore } // Напрямую не использовать!!! Служебный класс

  // TMyThreadListCore служит для защиты FList и FMyCritSection от прямого доступа (strict private)
  TMyThreadListCore<T> = class
  strict private
    FList: TList<T>;
    FMyCritSection: TMyCriticalSection;
    // FLastLockName: string; // Имя последней заблокировавшей функции
  public
    constructor Create(const LogName: string); virtual;
    destructor Destroy; override;

    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

    function LockForRead(const FuncName: string): TList<T>; // inline; // не имеет смысла !!!
    procedure UnlockAfterRead(const FuncName: string); // inline; // не имеет смысла !!!
    function LockForWrite(const FuncName: string): TList<T>; // inline; // не имеет смысла !!!
    procedure UnlockAfterWrite(const FuncName: string); // inline; // не имеет смысла !!!
  end;

  { TMyThreadList } // Можно и нужно использовать

  TMyThreadList<T> = class(TMyThreadListCore<T>)
  public type
    TListBoolFunc = reference to function(const InItem: T): Boolean;
    TListProcedure = reference to procedure(const InItem: T);
  strict private
    FDuplicates: TDuplicates;
    FMaxElementCount: SizeInt;
    function GetCapacity: SizeInt;

    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

    procedure SetCapacity(const Value: SizeInt); // inline; // не имеет смысла !!!
    procedure SetMaxElementCount(const Value: SizeInt);
    procedure SetItem(const Index: SizeInt; const Value: T); // inline; // не имеет смысла !!!
    function GetItem(const Index: SizeInt): T; // inline; // не имеет смысла !!!
    function GetOnNotify: TCollectionNotifyEvent<T>;
    procedure SetOnNotify(const Value: TCollectionNotifyEvent<T>);
    // Если задано ограничение на число элементов - подрежем список снизу
    function TrimIfReachMaximum(const List: TList<T>): Boolean; // inline; // не имеет смысла !!!
  public
    constructor Create(const LogName: string; const MaxElementCount: SizeInt = -1); reintroduce;
    destructor Destroy; override;

    function Add(const Value: T): SizeInt; // inline; // не имеет смысла !!!
    procedure AddRange(const Values: array of T); overload;
    procedure AddRange(const Collection: IEnumerable<T>); overload;
    procedure AddRange(const Collection: TEnumerable<T>); overload;
    procedure Insert(const Index: SizeInt; const Value: T); inline;
    procedure InsertRange(const Index: SizeInt; const Values: array of T; Count: SizeInt); overload;
    procedure InsertRange(const Index: SizeInt; const Values: array of T); overload;
    procedure InsertRange(const Index: SizeInt; const Collection: IEnumerable<T>); overload;
    procedure InsertRange(const Index: SizeInt; const Collection: TEnumerable<T>); overload;

    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

    function Remove(const Value: T; const FuncName: string): SizeInt;
    procedure Delete(const Index: SizeInt); // inline; // не имеет смысла !!!
    procedure Clear; inline;
    function Count: SizeInt; // inline; // не имеет смысла !!!
    function Contains(const Item: T): Boolean; // inline; // не имеет смысла !!!
    function IndexOf(const Item: T): SizeInt; // inline; // не имеет смысла !!!
    function First: T; // inline; // не имеет смысла !!!
    function Last: T; // inline; // не имеет смысла !!!
    function FilterToList(const InPredicate: TListBoolFunc): TList<T>;
    function FilterToThreadList(const InPredicate: TListBoolFunc): TMyThreadList<T>;
    procedure ForEach(const InProcedure: TListProcedure);

    procedure Sort(const AComparer: IComparer<T>); overload;
    procedure Sort(const AComparer: IComparer<T>; Index, Count: SizeInt); overload;
    function BinarySearch(const Item: T; out FoundIndex: SizeInt): Boolean; overload;
    function BinarySearch(const Item: T; out FoundIndex: SizeInt; const AComparer: IComparer<T>): Boolean; overload;
    function BinarySearch(const Item: T; out FoundIndex: SizeInt; const AComparer: IComparer<T>; Index, Count: SizeInt)
      : Boolean; overload;
    function ToArray(const FuncName: string): TArray<T>; reintroduce; deprecated
      'Метод ToArray не потокобезопасен и под запретом!';
    property Capacity: SizeInt read GetCapacity write SetCapacity;
    property Duplicates: TDuplicates read FDuplicates write FDuplicates;
    property MaxElementCount: SizeInt read FMaxElementCount write SetMaxElementCount;
    property Items[const index: SizeInt]: T read GetItem write SetItem; default;
    property OnNotify: TCollectionNotifyEvent<T> read GetOnNotify write SetOnNotify;
  end;

  { TMyThreadObjectList } // Можно и нужно использовать

  TMyThreadObjectList<T: class> = class(TMyThreadList<T>)
  strict private
    FOwnsObjects: Boolean; // Освобождать объекты при удалении из списка?
  strict protected
    // Обработчик удаления объекта для его освобождения
    procedure Notify(Sender: TObject; const Item: T; Action: TCollectionNotification);
  public
    constructor Create(const LogName: string); overload;
    constructor Create(const LogName: string; AOwnsObjects: Boolean); overload;
    destructor Destroy; override;
    property OwnsObjects: Boolean read FOwnsObjects write FOwnsObjects;
  end;

  { TMyThreadQueue } // Можно и нужно использовать

  // Потокобезопасная очередь на основе нашего TMyThreadList
  // Похорошему нужно делать на основе System.Generics.Collections.TQueue - будет быстрее !
  TMyThreadQueue<T> = class(TMyThreadList<T>)
    // Add - Добавляет элемент в конец очереди С проверкой на дубликат (пропускает)
    function Add(const Value: T): SizeInt; reintroduce; // inline; // не имеет смысла !!!
    // Добавляет элемент в конец очереди без проверки на дубликат
    procedure Enqueue(const Value: T); // inline; // не имеет смысла !!!
    // Изымает первый элемент из очереди
    function Dequeue: T; // inline; // не имеет смысла !!!
    // Тоже самое, что и Dequeue
    function Extract: T; // inline; // не имеет смысла !!!
  end;

  { TMyThreadQueue } // Можно и нужно использовать

  // Потокобезопасная очередь из объектов на основе нашего TMyThreadObjectList
  // Похорошему нужно делать на основе System.Generics.Collections.TObjectQueue - будет быстрее !
  TMyThreadObjectQueue<T: class> = class(TMyThreadObjectList<T>)
    // Add - Добавляет элемент в конец очереди С проверкой на дубликат (пропускает)
    function Add(const Value: T): SizeInt; reintroduce; // inline; // не имеет смысла !!!
    // Добавляет элемент в конец очереди без проверки на дубликат
    procedure Enqueue(const Value: T); // inline; // не имеет смысла !!!
    // Изымает первый элемент из очереди
    function Dequeue: T; // inline; // не имеет смысла !!!
    // Тоже самое, что и Dequeue
    function Extract: T; // inline; // не имеет смысла !!!
  end;

  { TMyThreadDictionaryCore } // Напрямую не использовать!!! Служебный класс

  // TMyThreadListCore служит для защиты FDic, FReverseDic (в планах) и FMyCritSection от прямого доступа (strict private)
  TMyThreadDictionaryCore<K, V> = class(THideConstructor)
  strict private
    FDic: TDictionary<K, V>;
    FMyCritSection: TMyCriticalSection;
  private
    // Обратный словарь для быстрого поиска ключа по значению
    FReverseDic: TDictionary<V, K>; // В будущем нужно перенести в strict private
  public
    constructor Create(const LogName: string; const ACapacity: Integer; const AComparer: IEqualityComparer<K>;
      const UseReverseDictionary: Boolean);
    destructor Destroy; override;

    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

    function LockForRead(const FuncName: string): TDictionary<K, V>; // inline; // не имеет смысла !!!
    procedure UnlockAfterRead(const FuncName: string); // inline; // не имеет смысла !!!
    function LockForWrite(const FuncName: string): TDictionary<K, V>; // inline; // не имеет смысла !!!
    procedure UnlockAfterWrite(const FuncName: string); // inline; // не имеет смысла !!!
  end;

  { TMyThreadDictionary }  // Можно и нужно использовать

  TMyThreadDictionary<K, V> = class(TMyThreadDictionaryCore<K, V>)
  private type
    TMyPair = TPair<K, V>;
  strict private
    function GetCapacity: SizeInt;
    procedure SetCapacity(const Value: SizeInt);
    function GetItem(const Key: K): V;
    procedure SetItem(const Key: K; const Value: V);
    function GetOnKeyNotify: TCollectionNotifyEvent<K>;
    function GetOnValueNotify: TCollectionNotifyEvent<V>;
    procedure SetOnKeyNotify(FOnKeyNotify: TCollectionNotifyEvent<K>);
    procedure SetOnValueNotify(FOnValueNotify: TCollectionNotifyEvent<V>);
  public
    constructor Create(const LogName: string; const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const ACapacity: Integer;
      const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const AComparer: IEqualityComparer<K>;
      const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const ACapacity: Integer; const AComparer: IEqualityComparer<K>;
      const UseReverseDictionary: Boolean = False); overload;
    destructor Destroy; override;

    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html

    procedure Add(const Key: K; const Value: V); // inline; // не имеет смысла !!!
    procedure Remove(const Key: K); overload; // inline; // не имеет смысла !!!
    procedure Remove(const Value: V); overload; // inline; // не имеет смысла !!!
    function ExtractPair(const Key: K): TMyPair; overload; // inline; // не имеет смысла !!!
    function ExtractPair(const Value: V): TMyPair; overload; // inline; // не имеет смысла !!!
    procedure Clear;
    procedure TrimExcess;
    function TryGetValue(const Key: K; out Value: V): Boolean; // inline; // не имеет смысла !!!
    function TryGetKey(const Value: V; out Key: K): Boolean; // inline; // не имеет смысла !!!
    procedure AddOrSetValue(const Key: K; const Value: V); // inline; // не имеет смысла !!!
    function ContainsKey(const Key: K): Boolean; // inline; // не имеет смысла !!!
    function ContainsValue(const Value: V): Boolean; // inline; // не имеет смысла !!!
    function ToArray(const FuncName: string): TArray<TMyPair>; reintroduce; deprecated
      'Метод ToArray не потокобезопасен и под запретом!';
    function Count: SizeInt;
    function TryAdd(const Key: K; const Value: V): Boolean;
    function GrowThreshold: SizeInt;
    function Collisions: SizeInt;
    property Capacity: SizeInt read GetCapacity write SetCapacity;
    property Items[const Key: K]: V read GetItem write SetItem; default;
    property OnKeyNotify: TCollectionNotifyEvent<K> read GetOnKeyNotify write SetOnKeyNotify;
    property OnValueNotify: TCollectionNotifyEvent<V> read GetOnValueNotify write SetOnValueNotify;
  end;

  { TMyThreadObjectDictionary }   // Можно и нужно использовать

  TMyThreadObjectDictionary<K, V> = class(TMyThreadDictionary<K, V>)
  strict private
    FOwnerships: TDictionaryOwnerships; // Освобождать объекты при удалении из списка?
  strict protected
    // Обработчики удаления объекта для его освобождения
    procedure KeyNotify(Sender: TObject; const Item: K; Action: TCollectionNotification);
    procedure ValueNotify(Sender: TObject; const Item: V; Action: TCollectionNotification);
  public
    constructor Create(const LogName: string; const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const ACapacity: Integer;
      const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const Ownerships: TDictionaryOwnerships;
      const UseReverseDictionary: Boolean = False); overload;
    constructor Create(const LogName: string; const Ownerships: TDictionaryOwnerships; const ACapacity: Integer;
      const UseReverseDictionary: Boolean = False); overload;
  end;

implementation

uses // Здесь не должно быть ClearFunctions, SysFunc и других зависимостей от Ресурса и УСПД!
  Windows, RTLConsts,
  // То, что нужно всем!
  DateUtils, SysUtils;

{ Функции модуля }

// Пока нет =)

{ THideConstructor }

// Класс прослойка для скрытия базового конструтора без параметров
constructor THideConstructor.Create;
begin
  inherited;
end;

{$REGION 'TMyThreadListCore<T>'}
{ TMyThreadListCore<T> }

constructor TMyThreadListCore<T>.Create(const LogName: string);
begin
  FList := TList<T>.Create;
  FMyCritSection := TMyCriticalSection.Create(FList, 'TMyThreadList<' + LogName + '>');
end;

destructor TMyThreadListCore<T>.Destroy;
begin
  // Очень важен порядок!! Входить в секцию перед уничтожением не нужно!!
  FreeAndNil(FMyCritSection);
  FreeAndNil(FList);
  inherited;
end;

function TMyThreadListCore<T>.LockForRead(const FuncName: string): TList<T>;
var
  LogMes: string;
begin
  if Assigned(FList) and Assigned(FMyCritSection) then
  begin
    // Отдельная переменная LogMes убирает возможную утечку при многопотоке
    LogMes := ClassName + '.LockForRead.' + FuncName;
    FMyCritSection.LockForRead(LogMes);
    Result := FList;
  end
  else
    Result := nil;
end;

function TMyThreadListCore<T>.LockForWrite(const FuncName: string): TList<T>;
var
  LogMes: string;
begin
  if Assigned(FList) and Assigned(FMyCritSection) then
  begin
    // Отдельная переменная LogMes убирает возможную утечку при многопотоке
    LogMes := ClassName + '.LockForWrite.' + FuncName;
    FMyCritSection.LockForWrite(LogMes);
    Result := FList;
  end
  else
    Result := nil;
end;

procedure TMyThreadListCore<T>.UnlockAfterRead(const FuncName: string);
var
  LogMes: string;
begin
  if Assigned(FList) and Assigned(FMyCritSection) then
  begin
    // Отдельная переменная LogMes убирает возможную утечку при многопотоке
    LogMes := ClassName + '.UnlockAfterRead.' + FuncName;
    FMyCritSection.UnlockAfterRead(LogMes);
  end;
end;

procedure TMyThreadListCore<T>.UnlockAfterWrite(const FuncName: string);
var
  LogMes: string;
begin
  if Assigned(FList) and Assigned(FMyCritSection) then
  begin
    // Отдельная переменная LogMes убирает возможную утечку при многопотоке
    LogMes := ClassName + '.UnlockAfterWrite.' + FuncName;
    FMyCritSection.UnlockAfterWrite(LogMes);
  end;
end;

{$ENDREGION 'TMyThreadListCore<T>'}
{$REGION 'TMyThreadList<T>'}

constructor TMyThreadList<T>.Create(const LogName: string; const MaxElementCount: SizeInt = -1);
begin
  inherited Create(LogName);

  FDuplicates := dupIgnore; // Не менять, а то все сломается!
  FMaxElementCount := MaxElementCount;

  if MaxElementCount > 0 then
    if MaxElementCount > 1000 then
      Capacity := 1000
    else
      Capacity := MaxElementCount;
end;

destructor TMyThreadList<T>.Destroy;
begin

  inherited Destroy;
end;

function TMyThreadList<T>.GetCapacity: SizeInt;
var
  List: TList<T>;
begin
  Result := -1;
  List := LockForRead('GetCapacity');
  try
    if Assigned(List) then
      Result := List.Capacity;
  finally
    UnlockAfterRead('GetCapacity');
  end;
end;

procedure TMyThreadList<T>.SetCapacity(const Value: SizeInt);
var
  List: TList<T>;
begin
  List := LockForWrite('SetCapacity');
  try
    if Assigned(List) then
      List.Capacity := Value;
  finally
    UnlockAfterWrite('SetCapacity');
  end;
end;

function TMyThreadList<T>.Add(const Value: T): SizeInt;
var
  GetIndex: Boolean;
  List: TList<T>;
begin
  Result := -1;
  List := LockForWrite('Add');
  try
    if Assigned(List) then
    begin
      if (Duplicates = dupAccept) or (List.IndexOf(Value) = -1) then
        Result := List.Add(Value)
      else if Duplicates = dupError then
        raise EListError.CreateFmt(SDuplicateItem, [List.ItemValue(Value)]);
      // Если задано ограничение на число элементов - подрежем список с начала
      GetIndex := TrimIfReachMaximum(List);
      if GetIndex then // Нужно перезапросить индекс элемента, так как он изменился
        Result := List.IndexOf(Value);
    end;
  finally
    UnlockAfterWrite('Add');
  end;
end;

procedure TMyThreadList<T>.AddRange(const Values: array of T);
var
  List: TList<T>;
begin
  List := LockForWrite('AddRange 1');
  try
    if Assigned(List) then
    begin
      List.AddRange(Values);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('AddRange 1');
  end;
end;

procedure TMyThreadList<T>.AddRange(const Collection: IEnumerable<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('AddRange 2');
  try
    if Assigned(List) then
    begin
      List.AddRange(Collection);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('AddRange 2');
  end;
end;

procedure TMyThreadList<T>.AddRange(const Collection: TEnumerable<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('AddRange 3');
  try
    if Assigned(List) then
    begin
      List.AddRange(Collection);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('AddRange 3');
  end;
end;

procedure TMyThreadList<T>.SetMaxElementCount(const Value: SizeInt);
var
  List: TList<T>;
begin
  FMaxElementCount := Value;
  // Если задано ограничение на число элементов - подрежем список с начала
  List := LockForWrite('SetMaxElementCount');
  try
    if Assigned(List) then
      TrimIfReachMaximum(List);
  finally
    UnlockAfterWrite('SetMaxElementCount');
  end;
end;

function TMyThreadList<T>.GetOnNotify: TCollectionNotifyEvent<T>;
var
  List: TList<T>;
begin
  Result := nil;
  List := LockForRead('GetOnNotify');
  try
    if Assigned(List) then
      Result := List.OnNotify;
  finally
    UnlockAfterRead('GetOnNotify');
  end;
end;

function TMyThreadList<T>.ToArray(const FuncName: string): TArray<T>;
// Перегоняет в массив - под запретом! Потоконебезопасно!
var
  List: TList<T>;
begin
  Result := nil;
  List := LockForRead('ToArray.' + FuncName);
  try
    if Assigned(List) then
      Result := List.ToArray;
  finally
    UnlockAfterRead('ToArray.' + FuncName);
  end;
end;

function TMyThreadList<T>.TrimIfReachMaximum(const List: TList<T>): Boolean;
begin
  Result := False;
  if FMaxElementCount > 0 then
  begin
    Result := (List.Count - FMaxElementCount) > 0;
    if Result then
      List.DeleteRange(0, List.Count - FMaxElementCount);
  end;
end;

procedure TMyThreadList<T>.SetOnNotify(const Value: TCollectionNotifyEvent<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('SetOnNotify');
  try
    if Assigned(List) then
      List.OnNotify := Value;
  finally
    UnlockAfterWrite('SetOnNotify');
  end;
end;

function TMyThreadList<T>.Remove(const Value: T; const FuncName: string): SizeInt;
var
  List: TList<T>;
begin
  Result := -1;
  List := LockForWrite('Remove.' + FuncName);
  try
    if Assigned(List) then
      Result := List.Remove(Value);
  finally
    UnlockAfterWrite('Remove.' + FuncName);
  end;
end;

procedure TMyThreadList<T>.Delete(const Index: SizeInt);
var
  List: TList<T>;
begin
  List := LockForWrite('Delete');
  try
    if Assigned(List) then
      List.Delete(index);
  finally
    UnlockAfterWrite('Delete');
  end;
end;

procedure TMyThreadList<T>.Clear;
var
  List: TList<T>;
begin
  List := LockForWrite('Clear');
  try
    if Assigned(List) then
      List.Clear;
  finally
    UnlockAfterWrite('Clear');
  end;
end;

function TMyThreadList<T>.Contains(const Item: T): Boolean;
var
  List: TList<T>;
begin
  Result := False;
  List := LockForRead('Contains');
  try
    if Assigned(List) then
      Result := List.Contains(Item);
  finally
    UnlockAfterRead('Contains');
  end;
end;

function TMyThreadList<T>.Count: SizeInt;
var
  List: TList<T>;
begin
  Result := -1;
  List := LockForRead('Count');
  try
    if Assigned(List) then
      Result := List.Count;
  finally
    UnlockAfterRead('Count');
  end;
end;

function TMyThreadList<T>.GetItem(const Index: SizeInt): T;
var
  List: TList<T>;
begin
  Result := default (T);
  List := LockForRead('GetItem');
  try
    if Assigned(List) then
      Result := List[index];
  finally
    UnlockAfterRead('GetItem');
  end;
end;

procedure TMyThreadList<T>.SetItem(const Index: SizeInt; const Value: T);
var
  List: TList<T>;
begin
  List := LockForWrite('SetItem');
  try
    if Assigned(List) then
      List[index] := Value;
  finally
    UnlockAfterWrite('SetItem');
  end;
end;

function TMyThreadList<T>.IndexOf(const Item: T): SizeInt;
var
  List: TList<T>;
begin
  Result := -1;
  List := LockForRead('IndexOf');
  try
    if Assigned(List) then
      Result := List.IndexOf(Item);
  finally
    UnlockAfterRead('IndexOf');
  end;
end;

procedure TMyThreadList<T>.Insert(const Index: SizeInt; const Value: T);
var
  List: TList<T>;
begin
  List := LockForWrite('Insert');
  try
    if Assigned(List) then
    begin
      List.Insert(index, Value);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('Insert');
  end;
end;

procedure TMyThreadList<T>.InsertRange(const Index: SizeInt; const Values: array of T; Count: SizeInt);
var
  List: TList<T>;
begin
  List := LockForWrite('InsertRange 1');
  try
    if Assigned(List) then
    begin
      List.InsertRange(index, Values, Count);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('InsertRange 1');
  end;
end;

procedure TMyThreadList<T>.InsertRange(const Index: SizeInt; const Values: array of T);
var
  List: TList<T>;
begin
  List := LockForWrite('InsertRange 2');
  try
    if Assigned(List) then
    begin
      List.InsertRange(index, Values);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('InsertRange 2');
  end;
end;

procedure TMyThreadList<T>.InsertRange(const Index: SizeInt; const Collection: IEnumerable<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('InsertRange 3');
  try
    if Assigned(List) then
    begin
      List.InsertRange(index, Collection);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('InsertRange 3');
  end;
end;

procedure TMyThreadList<T>.InsertRange(const Index: SizeInt; const Collection: TEnumerable<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('InsertRange 4');
  try
    if Assigned(List) then
    begin
      List.InsertRange(index, Collection);
      TrimIfReachMaximum(List); // Если задано ограничение на число элементов - подрежем список с начала
    end;
  finally
    UnlockAfterWrite('InsertRange 4');
  end;
end;

function TMyThreadList<T>.FilterToList(const InPredicate: TListBoolFunc): TList<T>;
var
  List: TList<T>;
  Item: T;
begin
  Result := TList<T>.Create;
  List := LockForRead('Filter');
  try
    if Assigned(List) then
    begin
      Result.Capacity := List.Count;
      for Item in List do
        if Assigned(InPredicate) and InPredicate(Item) then
          Result.Add(Item);
    end;
  finally
    UnlockAfterRead('Filter');
  end;
end;

function TMyThreadList<T>.FilterToThreadList(const InPredicate: TListBoolFunc): TMyThreadList<T>;
var
  List: TList<T>;
  Item: T;
begin
  Result := TMyThreadList<T>.Create('FilterToThreadList', FMaxElementCount);
  List := LockForRead('FilterToThreadList');
  try
    if Assigned(List) then
    begin
      Result.Capacity := List.Count;
      for Item in List do
        if Assigned(InPredicate) and InPredicate(Item) then
          Result.Add(Item);
    end;
  finally
    UnlockAfterRead('FilterToThreadList');
  end;
end;

procedure TMyThreadList<T>.ForEach(const InProcedure: TListProcedure);
var
  List: TList<T>;
  Item: T;
begin
  List := LockForRead('ForEach');
  try
    if Assigned(List) then
      for Item in List do
        if Assigned(InProcedure) then
          InProcedure(Item);
  finally
    UnlockAfterRead('ForEach');
  end;
end;

function TMyThreadList<T>.First: T;
var
  List: TList<T>;
begin
  Result := default (T);
  List := LockForRead('First');
  try
    if Assigned(List) then
      Result := List.First;
  finally
    UnlockAfterRead('First');
  end;
end;

function TMyThreadList<T>.Last: T;
var
  List: TList<T>;
begin
  Result := default (T);
  List := LockForRead('Last');
  try
    if Assigned(List) then
      Result := List.Last;
  finally
    UnlockAfterRead('Last');
  end;
end;

procedure TMyThreadList<T>.Sort(const AComparer: IComparer<T>);
var
  List: TList<T>;
begin
  List := LockForWrite('Sort 1');
  try
    if Assigned(List) then
      List.Sort(AComparer);
  finally
    UnlockAfterWrite('Sort 1');
  end;
end;

procedure TMyThreadList<T>.Sort(const AComparer: IComparer<T>; Index, Count: SizeInt);
var
  List: TList<T>;
begin
  List := LockForWrite('Sort 2');
  try
    if Assigned(List) then
      List.Sort(AComparer, index, Count);
  finally
    UnlockAfterWrite('Sort 2');
  end;
end;

function TMyThreadList<T>.BinarySearch(const Item: T; out FoundIndex: SizeInt): Boolean;
var
  List: TList<T>;
begin
  Result := False;
  List := LockForWrite('BinarySearch 1'); // Из-за сортировки блокируем на запись
  try
    if Assigned(List) then
      Result := List.BinarySearch(Item, FoundIndex);
  finally
    UnlockAfterWrite('BinarySearch 1');
  end;
end;

function TMyThreadList<T>.BinarySearch(const Item: T; out FoundIndex: SizeInt; const AComparer: IComparer<T>): Boolean;
var
  List: TList<T>;
begin
  Result := False;
  List := LockForWrite('BinarySearch 2'); // Из-за сортировки блокируем на запись
  try
    if Assigned(List) then
      Result := List.BinarySearch(Item, FoundIndex, AComparer);
  finally
    UnlockAfterWrite('BinarySearch 2');
  end;
end;

function TMyThreadList<T>.BinarySearch(const Item: T; out FoundIndex: SizeInt; const AComparer: IComparer<T>;
  Index, Count: SizeInt): Boolean;
var
  List: TList<T>;
begin
  Result := False;
  List := LockForWrite('BinarySearch 3'); // Из-за сортировки блокируем на запись
  try
    if Assigned(List) then
      Result := List.BinarySearch(Item, FoundIndex, AComparer, index, Count);
  finally
    UnlockAfterWrite('BinarySearch 3');
  end;
end;

{$ENDREGION 'TMyThreadList<T>'}
{$REGION 'TMyThreadObjectList<T>'}

constructor TMyThreadObjectList<T>.Create(const LogName: string);
begin
  inherited Create(LogName);

  // Будет ли Список являться отвественным за ОСВОБОЖДЕНИЕ объектов?
  FOwnsObjects := True;

  // Присвоим обработчики удаления объектов
  OnNotify := Notify;
end;

constructor TMyThreadObjectList<T>.Create(const LogName: string; AOwnsObjects: Boolean);
begin
  inherited Create(LogName);

  // Будет ли Список являться отвественным за ОСВОБОЖДЕНИЕ объектов?
  FOwnsObjects := AOwnsObjects;

  // Присвоим обработчики удаления объектов
  OnNotify := Notify;
end;

destructor TMyThreadObjectList<T>.Destroy;
begin
  Clear; // Чтобы освободить объекты\элементы
  inherited;
end;

procedure TMyThreadObjectList<T>.Notify(Sender: TObject; const Item: T; Action: TCollectionNotification);
begin
  if OwnsObjects and (Action = cnRemoved) then
    Item.Free; // DisposeOf не совместим с FPC;
end;

{$ENDREGION 'TMyThreadObjectList<T>'}
{$REGION 'TMyThreadQueue<T>'}
{ TMyThreadQueue<T> }

procedure TMyThreadQueue<T>.Enqueue(const Value: T);
// Добавляет элемент в конец очереди без проверки на дубликат
begin
  inherited Add(Value);
end;

function TMyThreadQueue<T>.Extract: T;
// Тоже самое, что и Dequeue
begin
  Result := Dequeue;
end;

function TMyThreadQueue<T>.Add(const Value: T): SizeInt;
// Добавляет элемент в конец очереди c проверкой на дубликат (пропускает)
begin
  if not Contains(Value) then
    Result := inherited Add(Value)
  else
    Result := -1;
end;

function TMyThreadQueue<T>.Dequeue: T;
// Изымает первый элемент из очереди
var
  List: TList<T>; // В наследнике FList не доступен, поэтому работаем так
begin
  List := LockForWrite('Dequeue');
  try
    if Assigned(List) and (List.Count > 0) then
      Result := List.ExtractAt(0)
    else
      Result := default (T);
  finally
    UnlockAfterWrite('Dequeue');
  end;
end;

{$ENDREGION 'TMyThreadQueue<T>'}
{$REGION 'TMyThreadObjectQueue<T>'}
{ TMyThreadObjectQueue<T> }

function TMyThreadObjectQueue<T>.Add(const Value: T): SizeInt;
// Добавляет элемент в конец очереди c проверкой на дубликат (пропускает)
begin
  if not Contains(Value) then
    Result := inherited Add(Value)
  else
    Result := -1;
end;

function TMyThreadObjectQueue<T>.Dequeue: T;
// Изымает первый элемент из очереди
var
  List: TList<T>; // В наследнике FList не доступен, поэтому работаем так
begin
  List := LockForWrite('Dequeue');
  try
    if Assigned(List) and (List.Count > 0) then
      Result := List.ExtractAt(0)
    else
      Result := default (T);
  finally
    UnlockAfterWrite('Dequeue');
  end;
end;

procedure TMyThreadObjectQueue<T>.Enqueue(const Value: T);
// Добавляет элемент в конец очереди без проверки на дубликат
begin
  inherited Add(Value);
end;

function TMyThreadObjectQueue<T>.Extract: T;
// Тоже самое, что и Dequeue
begin
  Result := Dequeue;
end;

{$ENDREGION 'TMyThreadObjectQueue<T>'}
{$REGION 'TMyThreadDictionaryCore<K, V>'}
{ TMyThreadDictionaryCore<K, V> }

constructor TMyThreadDictionaryCore<K, V>.Create(const LogName: string; const ACapacity: Integer;
  const AComparer: IEqualityComparer<K>; const UseReverseDictionary: Boolean);
begin
  inherited Create;

  if Assigned(AComparer) then
    FDic := TDictionary<K, V>.Create(ACapacity, AComparer)
  else
    FDic := TDictionary<K, V>.Create(ACapacity);

  // Обратный словарь по умолчанию выключен
  // if UseReverseDictionary then
  // FReverseDic := TDictionary<V, K>.Create(ACapacity)
  // else
  FReverseDic := nil;

  FMyCritSection := TMyCriticalSection.Create(FDic, 'TMyThreadDictionary<' + LogName + '>');
end;

destructor TMyThreadDictionaryCore<K, V>.Destroy;
begin
  // Очень важен порядок!! Входить в секцию перед уничтожением не нужно!!
  FreeAndNil(FMyCritSection);
  FreeAndNil(FDic); // Строго после FMyCritSection т.к. она его защитзает
  FreeAndNil(FReverseDic);
  inherited Destroy;
end;

function TMyThreadDictionaryCore<K, V>.LockForRead(const FuncName: string): TDictionary<K, V>;
var
  LogMes: string;
begin
  if Assigned(FDic) and Assigned(FMyCritSection) then
  begin
    LogMes := ClassName + '.LockForRead.' + FuncName;
    FMyCritSection.LockForRead(LogMes);
    Result := FDic;
  end
  else
    Result := nil;
end;

function TMyThreadDictionaryCore<K, V>.LockForWrite(const FuncName: string): TDictionary<K, V>;
var
  LogMes: string;
begin
  if Assigned(FDic) and Assigned(FMyCritSection) then
  begin
    LogMes := ClassName + '.LockForWrite.' + FuncName;
    FMyCritSection.LockForWrite(LogMes);
    Result := FDic;
  end
  else
    Result := nil;
end;

procedure TMyThreadDictionaryCore<K, V>.UnlockAfterRead(const FuncName: string);
var
  LogMes: string;
begin
  if Assigned(FDic) and Assigned(FMyCritSection) then
  begin
    LogMes := ClassName + '.UnlockAfterRead.' + FuncName;
    FMyCritSection.UnlockAfterRead(LogMes);
  end;
end;

procedure TMyThreadDictionaryCore<K, V>.UnlockAfterWrite(const FuncName: string);
var
  LogMes: string;
begin
  if Assigned(FDic) and Assigned(FMyCritSection) then
  begin
    LogMes := ClassName + '.UnlockAfterWrite.' + FuncName;
    FMyCritSection.UnlockAfterWrite(LogMes);
  end;
end;

{$ENDREGION 'TMyThreadDictionaryCore<K, V>'}
{$REGION 'TMyThreadDictionary<K, V>'}

constructor TMyThreadDictionary<K, V>.Create(const LogName: string; const ACapacity: Integer;
  const AComparer: IEqualityComparer<K>; const UseReverseDictionary: Boolean = False);
begin
  inherited Create(LogName, ACapacity, AComparer, UseReverseDictionary);
end;

constructor TMyThreadDictionary<K, V>.Create(const LogName: string; const ACapacity: Integer;
  const UseReverseDictionary: Boolean = False);
begin
  inherited Create(LogName, ACapacity, nil, UseReverseDictionary);
end;

constructor TMyThreadDictionary<K, V>.Create(const LogName: string; const UseReverseDictionary: Boolean = False);
begin
  inherited Create(LogName, 10, nil, UseReverseDictionary);
end;

constructor TMyThreadDictionary<K, V>.Create(const LogName: string; const AComparer: IEqualityComparer<K>;
  const UseReverseDictionary: Boolean = False);
begin
  inherited Create(LogName, 10, AComparer, UseReverseDictionary);
end;

destructor TMyThreadDictionary<K, V>.Destroy;
begin
  inherited Destroy;
end;

procedure TMyThreadDictionary<K, V>.Add(const Key: K; const Value: V);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('Add');
  try
    if Assigned(Dic) then
    begin
      Dic.Add(Key, Value);
      if Assigned(FReverseDic) then
        FReverseDic.Add(Value, Key);
    end;
  finally
    UnlockAfterWrite('Add');
  end;
end;

procedure TMyThreadDictionary<K, V>.AddOrSetValue(const Key: K; const Value: V);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('AddOrSetValue');
  try
    if Assigned(Dic) then
    begin
      Dic.AddOrSetValue(Key, Value);
      if Assigned(FReverseDic) then
        FReverseDic.AddOrSetValue(Value, Key);
    end;
  finally
    UnlockAfterWrite('AddOrSetValue');
  end;
end;

procedure TMyThreadDictionary<K, V>.Clear;
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('Clear');
  try
    if Assigned(Dic) then
    begin
      if Assigned(FReverseDic) then
        FReverseDic.Clear;
      // Важен порядок! Dic.Clear может убить объекты, поэтому должен быть в конце
      Dic.Clear;
    end;
  finally
    UnlockAfterWrite('Clear');
  end;
end;
function TMyThreadDictionary<K, V>.Collisions: SizeInt;
var
  Dic: TDictionary<K, V>;
begin
  Result := -1;
  Dic := LockForRead('Collisions');
  try
    if Assigned(Dic) then
      Result := Dic.Collisions;
  finally
    UnlockAfterRead('Collisions');
  end;
end;

function TMyThreadDictionary<K, V>.ContainsKey(const Key: K): Boolean;
var
  Dic: TDictionary<K, V>;
begin
  Result := False;
  Dic := LockForRead('ContainsKey');
  try
    if Assigned(Dic) then
      Result := Dic.ContainsKey(Key);
  finally
    UnlockAfterRead('ContainsKey');
  end;
end;

function TMyThreadDictionary<K, V>.ContainsValue(const Value: V): Boolean;
var
  Dic: TDictionary<K, V>;
begin
  Result := False;
  Dic := LockForRead('ContainsValue');
  try // У FReverseDic ключи и значения поменяны местами, поэтому FReverseDic.ContainsKey вернет тоже, что и Dic.ContainsValue, но гораздо быстрее!!
    if Assigned(Dic) then
      if Assigned(FReverseDic) then
        Result := FReverseDic.ContainsKey(Value)
      else // Старый медленный вариант
        Result := Dic.ContainsValue(Value);
  finally
    UnlockAfterRead('ContainsValue');
  end;
end;

function TMyThreadDictionary<K, V>.TryGetValue(const Key: K; out Value: V): Boolean;
var
  Dic: TDictionary<K, V>;
begin
  Result := False;
  Dic := LockForRead('TryGetValue');
  try
    if Assigned(Dic) then
      Result := Dic.TryGetValue(Key, Value);
  finally
    UnlockAfterRead('TryGetValue');
  end;
end;

function TMyThreadDictionary<K, V>.TryGetKey(const Value: V; out Key: K): Boolean;
// Возвращает первый ключ, который соответствует переданному значению
var
  Dic: TDictionary<K, V>;
begin
  Result := False;
  Dic := LockForRead('TryGetKey');
  try // У FReverseDic ключи и значения поменяны местами, поэтому FReverseDic.TryGetValue вернет тоже, что и Dic.TryGetKey (которого нет), но гораздо быстрее!!
    if Assigned(Dic) then
      if Assigned(FReverseDic) then
        Result := FReverseDic.TryGetValue(Value, Key)
      else
        raise Exception.Create('Чтобы работал TryGetKey включи обратный словарь и гарантируй уникальность значений!');
  finally
    UnlockAfterRead('TryGetKey');
  end;
end;

function TMyThreadDictionary<K, V>.Count: SizeInt;
var
  Dic: TDictionary<K, V>;
begin
  Result := -1;
  Dic := LockForRead('Count');
  try
    if Assigned(Dic) then
      Result := Dic.Count;
  finally
    UnlockAfterRead('Count');
  end;
end;

function TMyThreadDictionary<K, V>.ExtractPair(const Key: K): TMyPair;
var
  Value: V;
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('ExtractPair');
  try
    // ExtractPair извлекает (удляет) пару из словаря, поэтому важно тоже самое сделать со обоими словарями!
    if Assigned(Dic) then
    begin
      if Assigned(FReverseDic) then
        if Dic.TryGetValue(Key, Value) then
          FReverseDic.ExtractPair(Value);
      // Важен порядок! Dic.ExtractPair может убить объект, поэтому должен быть в конце
      Result := Dic.ExtractPair(Key);
    end;
  finally
    UnlockAfterWrite('ExtractPair');
  end;
end;

function TMyThreadDictionary<K, V>.ExtractPair(const Value: V): TMyPair;
// Извлекает пару из обратного словаря
var
  Key: K;
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('ExtractPair');
  try
    if Assigned(Dic) then
      if Assigned(FReverseDic) then
      begin
        Key := FReverseDic.ExtractPair(Value).Value;
        // Важен порядок! Dic.ExtractPair может убить объект, поэтому должен быть в конце
        Result := Dic.ExtractPair(Key);
      end
      else
        raise Exception.Create
          ('Чтобы работал ExtractPair по Value включи обратный словарь и гарантируй уникальность значений!');
  finally
    UnlockAfterWrite('ExtractPair');
  end;
end;

function TMyThreadDictionary<K, V>.GetCapacity: SizeInt;
var
  Dic: TDictionary<K, V>;
begin
  Result := -1;
  Dic := LockForRead('GetCapacity');
  try
    if Assigned(Dic) then
      Result := Dic.Capacity;
  finally
    UnlockAfterRead('GetCapacity');
  end;
end;

function TMyThreadDictionary<K, V>.GetItem(const Key: K): V;
var
  Dic: TDictionary<K, V>;
begin
  Result := default (V);
  Dic := LockForRead('GetItem');
  try
    if Assigned(Dic) then
      Result := Dic.Items[Key];
  finally
    UnlockAfterRead('GetItem');
  end;
end;

function TMyThreadDictionary<K, V>.GrowThreshold: SizeInt;
var
  Dic: TDictionary<K, V>;
begin
  Result := -1;
  Dic := LockForRead('GrowThreshold');
  try
    if Assigned(Dic) then
      Result := Dic.GrowThreshold;
  finally
    UnlockAfterRead('GrowThreshold');
  end;
end;

procedure TMyThreadDictionary<K, V>.Remove(const Key: K);
var
  Value: V;
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('Remove');
  try
    if Assigned(Dic) then
    begin
      if Assigned(FReverseDic) then
        if Dic.TryGetValue(Key, Value) then
          FReverseDic.Remove(Value);
      // Важен порядок! Dic.Remove может убить объект, поэтому должен быть в конце
      Dic.Remove(Key);
    end;
  finally
    UnlockAfterWrite('Remove');
  end;
end;

procedure TMyThreadDictionary<K, V>.Remove(const Value: V);
var
  Key: K;
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('Remove 2');
  try
    if Assigned(Dic) then
      if Assigned(FReverseDic) then
      begin
        if FReverseDic.TryGetValue(Value, Key) then
        begin
          FReverseDic.Remove(Value);
          // Важен порядок! Dic.Remove может убить объект, поэтому должен быть в конце
          Dic.Remove(Key);
        end;
      end
      else
        raise Exception.Create('Чтобы работал Remove по Value включи обратный словарь и гарантируй уникальность значений!');
  finally
    UnlockAfterWrite('Remove 2');
  end;
end;

procedure TMyThreadDictionary<K, V>.SetCapacity(const Value: SizeInt);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('SetCapacity');
  try
    if Assigned(Dic) then
    begin
      Dic.Capacity := Value;
      if Assigned(FReverseDic) then
        FReverseDic.Capacity := Value;
    end;
  finally
    UnlockAfterWrite('SetCapacity');
  end;
end;

procedure TMyThreadDictionary<K, V>.SetItem(const Key: K; const Value: V);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('SetItem');
  try
    if Assigned(Dic) then
    begin
      Dic[Key] := Value;
      if Assigned(FReverseDic) then
        FReverseDic[Value] := Key;
    end;
  finally
    UnlockAfterWrite('SetItem');
  end;
end;

function TMyThreadDictionary<K, V>.GetOnKeyNotify: TCollectionNotifyEvent<K>;
var
  Dic: TDictionary<K, V>;
begin
  Result := nil;
  Dic := LockForRead('GetOnKeyNotify');
  try
    if Assigned(Dic) then
      Result := Dic.OnKeyNotify;
  finally
    UnlockAfterRead('GetOnKeyNotify');
  end;
end;

function TMyThreadDictionary<K, V>.GetOnValueNotify: TCollectionNotifyEvent<V>;
var
  Dic: TDictionary<K, V>;
begin
  Result := nil;
  Dic := LockForRead('GetOnValueNotify');
  try
    if Assigned(Dic) then
      Result := Dic.OnValueNotify;
  finally
    UnlockAfterRead('GetOnValueNotify');
  end;
end;

procedure TMyThreadDictionary<K, V>.SetOnKeyNotify(FOnKeyNotify: TCollectionNotifyEvent<K>);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('SetOnKeyNotify');
  try
    if Assigned(Dic) then
      Dic.OnKeyNotify := FOnKeyNotify;
  finally
    UnlockAfterWrite('SetOnKeyNotify');
  end;
end;

procedure TMyThreadDictionary<K, V>.SetOnValueNotify(FOnValueNotify: TCollectionNotifyEvent<V>);
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('SetOnValueNotify');
  try
    if Assigned(Dic) then
      Dic.OnValueNotify := FOnValueNotify;
  finally
    UnlockAfterWrite('SetOnValueNotify');
  end;
end;

function TMyThreadDictionary<K, V>.ToArray(const FuncName: string): TArray<TMyPair>;
// Перегоняет в массив - под запретом! Потоконебезопасно!
var
  Dic: TDictionary<K, V>;
begin
  Result := nil;
  Dic := LockForRead('ToArray.' + FuncName);
  try
    if Assigned(Dic) then
      Result := Dic.ToArray;
  finally
    UnlockAfterRead('ToArray.' + FuncName);
  end;
end;

procedure TMyThreadDictionary<K, V>.TrimExcess;
var
  Dic: TDictionary<K, V>;
begin
  Dic := LockForWrite('TrimExcess');
  try
    if Assigned(Dic) then
    begin
      if Assigned(FReverseDic) then
        FReverseDic.TrimExcess;
      Dic.TrimExcess;
    end;
  finally
    UnlockAfterWrite('TrimExcess');
  end;
end;
function TMyThreadDictionary<K, V>.TryAdd(const Key: K; const Value: V): Boolean;
var
  Dic: TDictionary<K, V>;
begin
  Result := False;
  Dic := LockForWrite('TryAdd');
  try
    if Assigned(Dic) then
    begin
      Result := Dic.TryAdd(Key, Value);
      if Assigned(FReverseDic) then
        Result := Result and FReverseDic.TryAdd(Value, Key);
    end;
  finally
    UnlockAfterWrite('TryAdd');
  end;
end;

{$ENDREGION 'TMyThreadDictionary<K, V>'}
{$REGION 'TMyThreadObjectDictionary<K, V>'}

constructor TMyThreadObjectDictionary<K, V>.Create(const LogName: string; const Ownerships: TDictionaryOwnerships;
  const ACapacity: Integer; const UseReverseDictionary: Boolean = False);
begin
  inherited Create(LogName, ACapacity, UseReverseDictionary);

  // Какие События будут срабатывать: при измении ключа и/или значения
  FOwnerships := Ownerships;

  // Присвоим обработчики удаления объектов
  OnKeyNotify := KeyNotify;
  OnValueNotify := ValueNotify;
end;

constructor TMyThreadObjectDictionary<K, V>.Create(const LogName: string; const Ownerships: TDictionaryOwnerships;
  const UseReverseDictionary: Boolean = False);
begin
  Create(LogName, Ownerships, 10, UseReverseDictionary);
end;

constructor TMyThreadObjectDictionary<K, V>.Create(const LogName: string; const ACapacity: Integer;
  const UseReverseDictionary: Boolean = False);
begin
  // События будут срабатывать при измении {и ключа} и значения
  Create(LogName, [doOwnsValues], ACapacity, UseReverseDictionary)
end;

constructor TMyThreadObjectDictionary<K, V>.Create(const LogName: string; const UseReverseDictionary: Boolean = False);
begin
  // События будут срабатывать при измении {и ключа} и значения
  Create(LogName, [doOwnsValues], 10, UseReverseDictionary)
end;

procedure TMyThreadObjectDictionary<K, V>.KeyNotify(Sender: TObject; const Item: K; Action: TCollectionNotification);
begin
  inherited;
  if (Action = cnRemoved) and (doOwnsKeys in FOwnerships) then
    PObject(@Item)^.Free;
end;

procedure TMyThreadObjectDictionary<K, V>.ValueNotify(Sender: TObject; const Item: V; Action: TCollectionNotification);
begin
  inherited;
  if (Action = cnRemoved) and (doOwnsValues in FOwnerships) then
    PObject(@Item)^.Free;
end;

{$ENDREGION 'TMyThreadObjectDictionary<K, V>'}

initialization

end.
