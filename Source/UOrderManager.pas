{
  Менеджер ордеров (торговых заявок).
  Управление списком ордеров, их персистентностью в INI-файле и статусами.
  Потокобезопасное хранение через TMyThreadList<TOrderRecord>.
  Сериализация/десериализация через TMySaveIniFile с SavePeriodSec = 5.

  Requirements: 3.4, 3.5, 3.6, 6.3, 6.4, 6.5, 7.2, 12.1, 12.2
}

unit UOrderManager;

interface

uses
  SysUtils, System.Types,
  // Core-модули проекта
  MyThreadList, MyIniFile;

type
  TOrderDirection = (odBuy, odSell);
  TOrderType = (otMarket, otLimit, otBestPrice);
  TOrderStatus = (osNew, osPending, osFilled, osRejected, osCancelled, osUnknown);

  TOrderRecord = record
    Id: Integer;                // Локальный ID
    InstrumentId: string;       // FIGI или instrument_uid
    Ticker: string;             // Тикер для отображения
    Direction: TOrderDirection;
    Quantity: Integer;          // Количество лотов
    OrderType: TOrderType;
    TargetPrice: Double;        // Целевая цена (для лимитных)
    CurrentPrice: Double;       // Текущая рыночная цена
    Status: TOrderStatus;
    ExchangeOrderId: string;    // Биржевой ID заявки (из ответа API)
  end;

  TOrderManager = class
  private
    FOrders: TMyThreadList<TOrderRecord>;
    FIniFile: TMySaveIniFile;
    FNextId: Integer;

    procedure SaveToIni;
    procedure LoadFromIni;
  public
    constructor Create(const AIniPath: string);
    destructor Destroy; override;

    function AddOrder(const AOrder: TOrderRecord): Integer;
    procedure UpdateOrder(const AOrder: TOrderRecord);
    procedure DeleteOrder(const AId: Integer);
    function GetOrder(const AId: Integer): TOrderRecord;
    function GetAllOrders: TArray<TOrderRecord>;
    procedure UpdatePrice(const AInstrumentId: string; const APrice: Double);
    procedure UpdateStatus(const AId: Integer; const AStatus: TOrderStatus;
      const AExchangeOrderId: string = '');

    // Сериализация (Требование 12)
    class procedure OrderToIniSection(const AIniFile: TMySaveIniFile;
      const ASection: string; const AOrder: TOrderRecord);
    class function IniSectionToOrder(const AIniFile: TMySaveIniFile;
      const ASection: string): TOrderRecord;

    // Маппинг статусов API → TOrderStatus
    class function MapApiStatus(const AApiStatus: string): TOrderStatus;
  end;

implementation

uses
  Generics.Collections;

const
  SECTION_GENERAL = 'General';
  KEY_NEXT_ID     = 'NextId';

  // Ключи полей ордера в INI
  KEY_INSTRUMENT_ID    = 'InstrumentId';
  KEY_TICKER           = 'Ticker';
  KEY_DIRECTION        = 'Direction';
  KEY_QUANTITY         = 'Quantity';
  KEY_ORDER_TYPE       = 'OrderType';
  KEY_TARGET_PRICE     = 'TargetPrice';
  KEY_CURRENT_PRICE    = 'CurrentPrice';
  KEY_STATUS           = 'Status';
  KEY_EXCHANGE_ORDER_ID = 'ExchangeOrderId';

  // Префикс секции ордера
  ORDER_SECTION_PREFIX = 'Order_';

  // Статусы API T-Invest
  API_STATUS_FILL           = 'EXECUTION_REPORT_STATUS_FILL';
  API_STATUS_NEW            = 'EXECUTION_REPORT_STATUS_NEW';
  API_STATUS_REJECTED       = 'EXECUTION_REPORT_STATUS_REJECTED';
  API_STATUS_CANCELLED      = 'EXECUTION_REPORT_STATUS_CANCELLED';
  API_STATUS_PARTIALLYFILL  = 'EXECUTION_REPORT_STATUS_PARTIALLYFILL';

{ TOrderManager }

constructor TOrderManager.Create(const AIniPath: string);
begin
  inherited Create;
  // Потокобезопасный список ордеров, разрешаем дубликаты (разные ордера могут иметь одинаковые поля)
  FOrders := TMyThreadList<TOrderRecord>.Create('TOrderManager.FOrders');
  FOrders.Duplicates := dupAccept;
  // INI-файл с автосохранением каждые 5 секунд для продолжительной работы
  FIniFile := TMySaveIniFile.Create(AIniPath, 5);
  FNextId := 1;
  // Загружаем ордера из INI при создании
  LoadFromIni;
end;

destructor TOrderManager.Destroy;
begin
  // Принудительно сохраняем перед уничтожением
  SaveToIni;
  FIniFile.SaveFile;
  // Освобождаем в обратном порядке создания
  FreeAndNil(FIniFile);
  FreeAndNil(FOrders);
  inherited Destroy;
end;

procedure TOrderManager.SaveToIni;
var
  List: TList<TOrderRecord>;
  I: Integer;
  sectionName: string;
  order: TOrderRecord;
begin
  // Записываем NextId
  FIniFile.WriteInteger(SECTION_GENERAL, KEY_NEXT_ID, FNextId);

  // Удаляем все старые секции Order_*
  // Перебираем от 1 до FNextId-1 (максимально возможные ID)
  for I := 1 to FNextId - 1 do
  begin
    sectionName := ORDER_SECTION_PREFIX + I.ToString;
    if FIniFile.SectionExists(sectionName) then
      FIniFile.EraseSection(sectionName);
  end;

  // Записываем все текущие ордера
  List := FOrders.LockForRead('SaveToIni');
  try
    if Assigned(List) then
    begin
      for I := 0 to List.Count - 1 do
      begin
        order := List[I];
        sectionName := ORDER_SECTION_PREFIX + order.Id.ToString;
        OrderToIniSection(FIniFile, sectionName, order);
      end;
    end;
  finally
    FOrders.UnlockAfterRead('SaveToIni');
  end;
end;

procedure TOrderManager.LoadFromIni;
var
  List: TList<TOrderRecord>;
  I: Integer;
  sectionName: string;
  order: TOrderRecord;
begin
  FNextId := FIniFile.ReadInteger(SECTION_GENERAL, KEY_NEXT_ID, 1);

  List := FOrders.LockForWrite('LoadFromIni');
  try
    if Assigned(List) then
    begin
      List.Clear;
      // Перебираем секции Order_1 .. Order_(FNextId-1)
      for I := 1 to FNextId - 1 do
      begin
        sectionName := ORDER_SECTION_PREFIX + I.ToString;
        if FIniFile.SectionExists(sectionName) then
        begin
          order := IniSectionToOrder(FIniFile, sectionName);
          order.Id := I;
          List.Add(order);
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterWrite('LoadFromIni');
  end;
end;

function TOrderManager.AddOrder(const AOrder: TOrderRecord): Integer;
var
  List: TList<TOrderRecord>;
  newOrder: TOrderRecord;
begin
  newOrder := AOrder;
  newOrder.Id := FNextId;
  Inc(FNextId);

  List := FOrders.LockForWrite('AddOrder');
  try
    if Assigned(List) then
      List.Add(newOrder);
  finally
    FOrders.UnlockAfterWrite('AddOrder');
  end;

  Result := newOrder.Id;
  SaveToIni;
end;

procedure TOrderManager.UpdateOrder(const AOrder: TOrderRecord);
var
  List: TList<TOrderRecord>;
  I: Integer;
  found: Boolean;
begin
  found := False;

  List := FOrders.LockForWrite('UpdateOrder');
  try
    if Assigned(List) then
    begin
      for I := 0 to List.Count - 1 do
      begin
        if List[I].Id = AOrder.Id then
        begin
          List[I] := AOrder;
          found := True;
          Break;
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterWrite('UpdateOrder');
  end;

  if found then
    SaveToIni;
end;

procedure TOrderManager.DeleteOrder(const AId: Integer);
var
  List: TList<TOrderRecord>;
  I: Integer;
  found: Boolean;
begin
  found := False;

  List := FOrders.LockForWrite('DeleteOrder');
  try
    if Assigned(List) then
    begin
      for I := List.Count - 1 downto 0 do
      begin
        if List[I].Id = AId then
        begin
          List.Delete(I);
          found := True;
          Break;
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterWrite('DeleteOrder');
  end;

  if found then
    SaveToIni;
end;

function TOrderManager.GetOrder(const AId: Integer): TOrderRecord;
var
  List: TList<TOrderRecord>;
  I: Integer;
begin
  Result := Default(TOrderRecord);

  List := FOrders.LockForRead('GetOrder');
  try
    if Assigned(List) then
    begin
      for I := 0 to List.Count - 1 do
      begin
        if List[I].Id = AId then
        begin
          Result := List[I];
          Break;
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterRead('GetOrder');
  end;
end;

function TOrderManager.GetAllOrders: TArray<TOrderRecord>;
var
  List: TList<TOrderRecord>;
  I: Integer;
begin
  List := FOrders.LockForRead('GetAllOrders');
  try
    if Assigned(List) then
    begin
      SetLength(Result, List.Count);
      for I := 0 to List.Count - 1 do
        Result[I] := List[I];
    end
    else
      SetLength(Result, 0);
  finally
    FOrders.UnlockAfterRead('GetAllOrders');
  end;
end;

procedure TOrderManager.UpdatePrice(const AInstrumentId: string; const APrice: Double);
var
  List: TList<TOrderRecord>;
  I: Integer;
  order: TOrderRecord;
  changed: Boolean;
begin
  changed := False;

  List := FOrders.LockForWrite('UpdatePrice');
  try
    if Assigned(List) then
    begin
      for I := 0 to List.Count - 1 do
      begin
        if List[I].InstrumentId = AInstrumentId then
        begin
          order := List[I];
          order.CurrentPrice := APrice;
          List[I] := order;
          changed := True;
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterWrite('UpdatePrice');
  end;

  if changed then
    SaveToIni;
end;

procedure TOrderManager.UpdateStatus(const AId: Integer; const AStatus: TOrderStatus;
  const AExchangeOrderId: string = '');
var
  List: TList<TOrderRecord>;
  I: Integer;
  order: TOrderRecord;
  found: Boolean;
begin
  found := False;

  List := FOrders.LockForWrite('UpdateStatus');
  try
    if Assigned(List) then
    begin
      for I := 0 to List.Count - 1 do
      begin
        if List[I].Id = AId then
        begin
          order := List[I];
          order.Status := AStatus;
          if AExchangeOrderId <> '' then
            order.ExchangeOrderId := AExchangeOrderId;
          List[I] := order;
          found := True;
          Break;
        end;
      end;
    end;
  finally
    FOrders.UnlockAfterWrite('UpdateStatus');
  end;

  if found then
    SaveToIni;
end;

class procedure TOrderManager.OrderToIniSection(const AIniFile: TMySaveIniFile;
  const ASection: string; const AOrder: TOrderRecord);
begin
  AIniFile.WriteString(ASection, KEY_INSTRUMENT_ID, AOrder.InstrumentId);
  AIniFile.WriteString(ASection, KEY_TICKER, AOrder.Ticker);
  AIniFile.WriteInteger(ASection, KEY_DIRECTION, Ord(AOrder.Direction));
  AIniFile.WriteInteger(ASection, KEY_QUANTITY, AOrder.Quantity);
  AIniFile.WriteInteger(ASection, KEY_ORDER_TYPE, Ord(AOrder.OrderType));
  AIniFile.WriteFloat(ASection, KEY_TARGET_PRICE, AOrder.TargetPrice);
  AIniFile.WriteFloat(ASection, KEY_CURRENT_PRICE, AOrder.CurrentPrice);
  AIniFile.WriteInteger(ASection, KEY_STATUS, Ord(AOrder.Status));
  AIniFile.WriteString(ASection, KEY_EXCHANGE_ORDER_ID, AOrder.ExchangeOrderId);
end;

class function TOrderManager.IniSectionToOrder(const AIniFile: TMySaveIniFile;
  const ASection: string): TOrderRecord;
var
  dirVal, typeVal, statusVal: Integer;
begin
  Result := Default(TOrderRecord);
  Result.InstrumentId := AIniFile.ReadString(ASection, KEY_INSTRUMENT_ID, '');
  Result.Ticker := AIniFile.ReadString(ASection, KEY_TICKER, '');

  dirVal := AIniFile.ReadInteger(ASection, KEY_DIRECTION, 0);
  if (dirVal >= Ord(Low(TOrderDirection))) and (dirVal <= Ord(High(TOrderDirection))) then
    Result.Direction := TOrderDirection(dirVal)
  else
    Result.Direction := odBuy;

  Result.Quantity := AIniFile.ReadInteger(ASection, KEY_QUANTITY, 0);

  typeVal := AIniFile.ReadInteger(ASection, KEY_ORDER_TYPE, 0);
  if (typeVal >= Ord(Low(TOrderType))) and (typeVal <= Ord(High(TOrderType))) then
    Result.OrderType := TOrderType(typeVal)
  else
    Result.OrderType := otMarket;

  Result.TargetPrice := AIniFile.ReadFloat(ASection, KEY_TARGET_PRICE, 0.0);
  Result.CurrentPrice := AIniFile.ReadFloat(ASection, KEY_CURRENT_PRICE, 0.0);

  statusVal := AIniFile.ReadInteger(ASection, KEY_STATUS, 0);
  if (statusVal >= Ord(Low(TOrderStatus))) and (statusVal <= Ord(High(TOrderStatus))) then
    Result.Status := TOrderStatus(statusVal)
  else
    Result.Status := osUnknown;

  Result.ExchangeOrderId := AIniFile.ReadString(ASection, KEY_EXCHANGE_ORDER_ID, '');
end;

class function TOrderManager.MapApiStatus(const AApiStatus: string): TOrderStatus;
begin
  if AApiStatus = API_STATUS_FILL then
    Result := osFilled
  else if AApiStatus = API_STATUS_NEW then
    Result := osPending
  else if AApiStatus = API_STATUS_REJECTED then
    Result := osRejected
  else if AApiStatus = API_STATUS_CANCELLED then
    Result := osCancelled
  else if AApiStatus = API_STATUS_PARTIALLYFILL then
    Result := osPending
  else
    Result := osUnknown;
end;

end.
