{
  API-клиент для работы с T-Invest REST API.
  Все HTTP-взаимодействия с биржей проходят через этот модуль.
  Использует TMyHttpClient.HttpsClientPost для HTTPS-запросов.
  Настройка прокси и авторизации — через TMyHttpClient.OnConfigureClient callback.
  Все методы потокобезопасны и могут вызываться из фоновых потоков.

  Requirements: 2.1, 5.1, 6.1, 6.2, 6.6, 7.1, 8.1
}

unit UApiClient;

interface

uses
  System.SysUtils, System.JSON, System.Net.HttpClientComponent, System.Net.URLClient,
  // Core-модули проекта
  MyCriticalSection, MyHttpClient,
  // Модули приложения
  ULogManager, UOrderManager, UQuotationHelper;

type
  TApiClient = class
  private
    FBaseUrl: string;
    FToken: string;
    FProxyHost: string;
    FProxyPort: Integer;
    FProxyUser: string;
    FProxyPass: string;
    FLogManager: TLogManager;
    FCritSection: TMyCriticalSection;

    /// <summary>
    /// Callback для TMyHttpClient.OnConfigureClient.
    /// Настраивает прокси и заголовок Authorization на клиенте перед запросом.
    /// </summary>
    procedure ConfigureClient(const AClient: TNetHTTPClient);

    /// <summary>
    /// Выполняет HTTPS POST запрос к указанному endpoint API.
    /// Устанавливает OnConfigureClient, выполняет запрос, логирует результат.
    /// </summary>
    function DoPost(const AEndpoint, ARequestBody: string;
      out AResponse: string; out AStatusCode: Integer): Boolean;

    /// <summary>
    /// Генерирует уникальный idempotency-ключ в формате GUID без фигурных скобок.
    /// </summary>
    function GenerateIdempotencyKey: string;
  public
    constructor Create(const ALogManager: TLogManager);
    destructor Destroy; override;

    /// <summary>
    /// Установить API-токен для авторизации.
    /// </summary>
    procedure SetToken(const AToken: string);

    /// <summary>
    /// Установить параметры прокси-сервера.
    /// </summary>
    procedure SetProxy(const AHost: string; const APort: Integer;
      const AUser, APass: string);

    /// <summary>
    /// Получить список счетов пользователя (Требование 2.1).
    /// POST /tinkoff.public.invest.api.contract.v1.UsersService/GetAccounts
    /// </summary>
    function GetAccounts(out AResponse: string; out AStatusCode: Integer): Boolean;

    /// <summary>
    /// Получить последние цены по списку инструментов (Требование 5.1).
    /// POST /tinkoff.public.invest.api.contract.v1.MarketDataService/GetLastPrices
    /// </summary>
    function GetLastPrices(const AInstrumentIds: TArray<string>;
      out AResponse: string; out AStatusCode: Integer): Boolean;

    /// <summary>
    /// Выставить торговую заявку на бирже (Требование 6.1).
    /// POST /tinkoff.public.invest.api.contract.v1.OrdersService/PostOrder
    /// Генерирует уникальный idempotency-ключ (orderId) в формате GUID.
    /// </summary>
    function PostOrder(const AAccountId, AInstrumentId: string;
      const AQuantity: Integer; const ADirection: TOrderDirection;
      const AOrderType: TOrderType; const APrice: Double;
      out AResponse: string; out AStatusCode: Integer): Boolean;

    /// <summary>
    /// Отменить ранее выставленную заявку (Требование 7.1).
    /// POST /tinkoff.public.invest.api.contract.v1.OrdersService/CancelOrder
    /// </summary>
    function CancelOrder(const AAccountId, AOrderId: string;
      out AResponse: string; out AStatusCode: Integer): Boolean;

    /// <summary>
    /// Получить список активных заявок по счёту (Требование 8.1).
    /// POST /tinkoff.public.invest.api.contract.v1.OrdersService/GetOrders
    /// </summary>
    function GetOrders(const AAccountId: string;
      out AResponse: string; out AStatusCode: Integer): Boolean;
  end;

implementation

const
  // Базовый URL T-Invest REST API
  DEFAULT_BASE_URL = 'https://invest-public-api.tinkoff.ru/rest';

  // Endpoints API
  ENDPOINT_GET_ACCOUNTS   = '/tinkoff.public.invest.api.contract.v1.UsersService/GetAccounts';
  ENDPOINT_GET_LAST_PRICES = '/tinkoff.public.invest.api.contract.v1.MarketDataService/GetLastPrices';
  ENDPOINT_POST_ORDER     = '/tinkoff.public.invest.api.contract.v1.OrdersService/PostOrder';
  ENDPOINT_CANCEL_ORDER   = '/tinkoff.public.invest.api.contract.v1.OrdersService/CancelOrder';
  ENDPOINT_GET_ORDERS     = '/tinkoff.public.invest.api.contract.v1.OrdersService/GetOrders';

  // Маппинг TOrderDirection → строка API
  ORDER_DIRECTION_STRINGS: array[TOrderDirection] of string = (
    'ORDER_DIRECTION_BUY',   // odBuy
    'ORDER_DIRECTION_SELL'   // odSell
  );

  // Маппинг TOrderType → строка API
  ORDER_TYPE_STRINGS: array[TOrderType] of string = (
    'ORDER_TYPE_MARKET',     // otMarket
    'ORDER_TYPE_LIMIT',      // otLimit
    'ORDER_TYPE_BESTPRICE'   // otBestPrice
  );

{ TApiClient }

constructor TApiClient.Create(const ALogManager: TLogManager);
begin
  inherited Create;
  FBaseUrl := DEFAULT_BASE_URL;
  FToken := '';
  FProxyHost := '';
  FProxyPort := 0;
  FProxyUser := '';
  FProxyPass := '';
  FLogManager := ALogManager;
  FCritSection := TMyCriticalSection.Create('TApiClient.FCritSection');
end;

destructor TApiClient.Destroy;
begin
  // Освобождаем в обратном порядке создания
  FreeAndNil(FCritSection);
  // FLogManager — внешняя ссылка, не освобождаем
  inherited Destroy;
end;

procedure TApiClient.SetToken(const AToken: string);
begin
  FCritSection.Enter('SetToken');
  try
    FToken := AToken;
  finally
    FCritSection.Leave('SetToken');
  end;
end;

procedure TApiClient.SetProxy(const AHost: string; const APort: Integer;
  const AUser, APass: string);
begin
  FCritSection.Enter('SetProxy');
  try
    FProxyHost := AHost;
    FProxyPort := APort;
    FProxyUser := AUser;
    FProxyPass := APass;
  finally
    FCritSection.Leave('SetProxy');
  end;
end;

procedure TApiClient.ConfigureClient(const AClient: TNetHTTPClient);
var
  proxySettings: TProxySettings;
begin
  // Этот callback вызывается из DoPost, где FCritSection уже захвачена текущим потоком.
  // Поэтому безопасно читать поля напрямую без повторного входа в крит.секцию.

  // Устанавливаем заголовок авторизации
  if FToken <> '' then
    AClient.CustomHeaders['Authorization'] := 'Bearer ' + FToken;

  // Настраиваем прокси, если задан
  if FProxyHost <> '' then
  begin
    proxySettings.Host := FProxyHost;
    proxySettings.Port := FProxyPort;
    proxySettings.UserName := FProxyUser;
    proxySettings.Password := FProxyPass;
    AClient.ProxySettings := proxySettings;
  end;
end;

function TApiClient.DoPost(const AEndpoint, ARequestBody: string;
  out AResponse: string; out AStatusCode: Integer): Boolean;
var
  url: string;
  ErrorLine: Integer;
begin
  ErrorLine := 0;
  Result := False;
  AResponse := '';
  AStatusCode := -1;
  url := FBaseUrl + AEndpoint;

  try
    ErrorLine := 10;
    // Логируем запрос
    if Assigned(FLogManager) then
      FLogManager.LogInfo(Format('API запрос: endpoint = %s', [AEndpoint]));

    ErrorLine := 20;
    // Устанавливаем callback для настройки клиента (прокси + авторизация).
    // OnConfigureClient — class var, поэтому защищаем установку и вызов крит.секцией.
    // HttpsClientPost создаёт клиент → вызывает OnConfigureClient → выполняет POST → уничтожает клиент.
    FCritSection.Enter('DoPost');
    try
      TMyHttpClient.OnConfigureClient := ConfigureClient;

      ErrorLine := 30;
      Result := TMyHttpClient.HttpsClientPost(url, ARequestBody,
        AResponse, AStatusCode);
    finally
      FCritSection.Leave('DoPost');
    end;

    ErrorLine := 40;
    // Логируем результат
    if Assigned(FLogManager) then
    begin
      if Result and (AStatusCode = 200) then
        FLogManager.LogInfo(Format('API ответ: endpoint = %s, status = %d',
          [AEndpoint, AStatusCode]))
      else
        FLogManager.LogError(Format('API ошибка: endpoint = %s, status = %d, response = %s',
          [AEndpoint, AStatusCode, AResponse]));
    end;
  except
    on E: Exception do
    begin
      AResponse := Format('Исключение в строке %d: %s', [ErrorLine, E.Message]);
      AStatusCode := -1;
      Result := False;
      if Assigned(FLogManager) then
        FLogManager.LogError(Format('API исключение: endpoint = %s, error = %s',
          [AEndpoint, AResponse]));
    end;
  end;
end;

function TApiClient.GenerateIdempotencyKey: string;
var
  guid: TGUID;
begin
  guid := TGUID.NewGuid;
  // Убираем фигурные скобки из GUID: {XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX} → XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
  Result := guid.ToString.Trim(['{', '}']);
end;

function TApiClient.GetAccounts(out AResponse: string; out AStatusCode: Integer): Boolean;
begin
  Result := DoPost(ENDPOINT_GET_ACCOUNTS, '{}', AResponse, AStatusCode);
end;

function TApiClient.GetLastPrices(const AInstrumentIds: TArray<string>;
  out AResponse: string; out AStatusCode: Integer): Boolean;
var
  jsonObj: TJSONObject;
  jsonArr: TJSONArray;
  I: Integer;
begin
  jsonObj := TJSONObject.Create;
  try
    jsonArr := TJSONArray.Create;
    for I := Low(AInstrumentIds) to High(AInstrumentIds) do
      jsonArr.Add(AInstrumentIds[I]);
    jsonObj.AddPair('instrumentId', jsonArr);

    Result := DoPost(ENDPOINT_GET_LAST_PRICES, jsonObj.ToJSON, AResponse, AStatusCode);
  finally
    FreeAndNil(jsonObj);
  end;
end;

function TApiClient.PostOrder(const AAccountId, AInstrumentId: string;
  const AQuantity: Integer; const ADirection: TOrderDirection;
  const AOrderType: TOrderType; const APrice: Double;
  out AResponse: string; out AStatusCode: Integer): Boolean;
var
  jsonObj: TJSONObject;
  priceObj: TJSONObject;
  quotation: TQuotation;
  idempotencyKey: string;
begin
  idempotencyKey := GenerateIdempotencyKey;

  jsonObj := TJSONObject.Create;
  try
    jsonObj.AddPair('instrumentId', AInstrumentId);
    jsonObj.AddPair('quantity', AQuantity.ToString);
    jsonObj.AddPair('direction', ORDER_DIRECTION_STRINGS[ADirection]);
    jsonObj.AddPair('accountId', AAccountId);
    jsonObj.AddPair('orderType', ORDER_TYPE_STRINGS[AOrderType]);
    jsonObj.AddPair('orderId', idempotencyKey);

    // Цена указывается только для лимитных ордеров
    if AOrderType = otLimit then
    begin
      quotation := TQuotationHelper.FromDouble(APrice);
      priceObj := TJSONObject.Create;
      priceObj.AddPair('units', quotation.Units.ToString);
      priceObj.AddPair('nano', TJSONNumber.Create(quotation.Nano));
      jsonObj.AddPair('price', priceObj);
    end;

    if Assigned(FLogManager) then
      FLogManager.LogInfo(Format('PostOrder: instrument = %s, direction = %s, quantity = %d, type = %s, orderId = %s',
        [AInstrumentId, ORDER_DIRECTION_STRINGS[ADirection], AQuantity,
         ORDER_TYPE_STRINGS[AOrderType], idempotencyKey]));

    Result := DoPost(ENDPOINT_POST_ORDER, jsonObj.ToJSON, AResponse, AStatusCode);
  finally
    FreeAndNil(jsonObj);
  end;
end;

function TApiClient.CancelOrder(const AAccountId, AOrderId: string;
  out AResponse: string; out AStatusCode: Integer): Boolean;
var
  jsonObj: TJSONObject;
begin
  jsonObj := TJSONObject.Create;
  try
    jsonObj.AddPair('accountId', AAccountId);
    jsonObj.AddPair('orderId', AOrderId);

    if Assigned(FLogManager) then
      FLogManager.LogInfo(Format('CancelOrder: accountId = %s, orderId = %s',
        [AAccountId, AOrderId]));

    Result := DoPost(ENDPOINT_CANCEL_ORDER, jsonObj.ToJSON, AResponse, AStatusCode);
  finally
    FreeAndNil(jsonObj);
  end;
end;

function TApiClient.GetOrders(const AAccountId: string;
  out AResponse: string; out AStatusCode: Integer): Boolean;
var
  jsonObj: TJSONObject;
begin
  jsonObj := TJSONObject.Create;
  try
    jsonObj.AddPair('accountId', AAccountId);

    Result := DoPost(ENDPOINT_GET_ORDERS, jsonObj.ToJSON, AResponse, AStatusCode);
  finally
    FreeAndNil(jsonObj);
  end;
end;

end.
