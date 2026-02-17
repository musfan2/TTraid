{

  Удобная обёртка для работы с TNetHTTPClient.
  Можно использовать как готовые классовые методы для быстрой отправки запроса,
  так и создать полноценный TNetHTTPClient для более сложной работы.
  Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient.

  Настройка прокси — через SetProxy / SetProxyAuth перед вызовом запросов,
  либо через глобальный обработчик OnConfigureClient.

  DoctorS, 2024-2025.
}

unit MyHttpClient;

interface

uses
  System.Classes, System.SysUtils, System.Net.HttpClientComponent, System.Net.HttpClient, System.Net.URLClient;

type

  // Callback для настройки клиента перед запросом (прокси, заголовки и т.д.)
  TOnConfigureClient = procedure(const AClient: TNetHTTPClient) of object;

  // Удобная обёртка для работы с TNetHTTPClient
  TMyHttpClient = class(TNetHTTPClient)
  type
    THttpMethod = (hmPost, hmPatch, hmGet);
  private
    // Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient
    constructor Create(AOwner: TComponent); reintroduce;

    // Самая главная функция, которая всё делает =)
    function HttpClientCore(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const HttpMethod: THttpMethod; const ContentType: string): Boolean;

  public
    class var OnConfigureClient: TOnConfigureClient;

    // === Классовые методы можно вызывать без создания экземпляра класса! =====

    // Создание экземпляра для работы по HTTP с настройкой прокси(!) и заданием ContentType
    class function CreateHTTPClient(const ContentType: string = 'application/json'): TMyHttpClient;
    // Создание экземпляра для работы по HTTPS. Позволяет указать параметры шифрования
    class function CreateHTTPSClient(const ContentType: string = 'application/json';
      const SecureProtocols: THTTPSecureProtocols = [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13]): TMyHttpClient;

    // Настройка прокси на экземпляре
    procedure SetProxy(const AHost: string; const APort: Integer);
    procedure SetProxyAuth(const AUserName, APassword: string);

    // Классовые методы БЕЗ шифрования (HTTP)
    class function HttpClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;
    class function HttpClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;
    class function HttpClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;

    // Классовые методы С шифрованием (HTTPS)
    class function HttpsClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;
    class function HttpsClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;
    class function HttpsClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
      const ContentType: string = 'application/json'): Boolean;
  end;

implementation

const
  INVALID_STATUS_CODE = -1;

{ TMyHttpClient }

constructor TMyHttpClient.Create(AOwner: TComponent);
// Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient
begin
  inherited;
end;

class function TMyHttpClient.CreateHTTPClient(const ContentType: string = 'application/json'): TMyHttpClient;
// Создадим TNetHTTPClient и настроим через callback
begin
  Result := TMyHttpClient.Create(nil);
  Result.ConnectionTimeout := 10000;
  Result.SendTimeout := 2000;
  Result.ResponseTimeout := 15000;
  Result.SecureProtocols := [];
  try
    // Устанавливаем заголовок Content-Type для запросов
    Result.ContentType := ContentType;

    // Даём возможность вызывающему коду настроить клиент (прокси, заголовки и т.д.)
    if Assigned(OnConfigureClient) then
      OnConfigureClient(Result);
  except
    FreeAndNil(Result);
    raise;
  end;
end;

class function TMyHttpClient.CreateHTTPSClient(const ContentType: string = 'application/json';
  const SecureProtocols: THTTPSecureProtocols = [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13]): TMyHttpClient;
// Включим шифрование HTTPS
begin
  Result := TMyHttpClient.CreateHTTPClient(ContentType);
  Result.SecureProtocols := SecureProtocols;
end;

procedure TMyHttpClient.SetProxy(const AHost: string; const APort: Integer);
var
  Settings: TProxySettings;
begin
  Settings.Host := AHost;
  Settings.Port := APort;
  Settings.UserName := '';
  Settings.Password := '';
  ProxySettings := Settings;
end;

procedure TMyHttpClient.SetProxyAuth(const AUserName, APassword: string);
var
  Settings: TProxySettings;
begin
  Settings := ProxySettings;
  Settings.UserName := AUserName;
  Settings.Password := APassword;
  ProxySettings := Settings;
end;

function TMyHttpClient.HttpClientCore(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const HttpMethod: THttpMethod; const ContentType: string): Boolean;
// Отправляет запрос и получает ответ
var
  QuestionStream: TStringStream;
  Response: IHTTPResponse;
begin
  Result := False;
  StatusCode := INVALID_STATUS_CODE;
  try
    // Создаем поток TStringStream для отправки данных и получения ответа
    QuestionStream := TStringStream.Create(Question, TEncoding.UTF8);
    try
      // Устанавливаем заголовок Content-Type
      CustomHeaders['Content-Type'] := ContentType;

      // Выполняем запрос
      case HttpMethod of
        THttpMethod.hmPost: Response := Post(URL, QuestionStream);
        THttpMethod.hmPatch: Response := Patch(URL, QuestionStream);
        THttpMethod.hmGet: Response := Get(URL);
      else raise Exception.Create('TMyHttpClient.HttpClientCore: неподдерживаемый метод!');
      end;

      // Прочитаем ответ (он может быть даже если код ошибки 403)
      Answer := Response.ContentAsString(TEncoding.UTF8);
      StatusCode := Response.StatusCode;
    finally
      FreeAndNil(QuestionStream);
    end;
    Result := True;
  except
    on E: ENetHTTPClientException do
    begin
      // Штатные ошибки приходят здесь
      if Assigned(Response) then
      begin
        Answer := Response.StatusText;
        StatusCode := Response.StatusCode;
      end
      else
      begin
        Answer := E.Message;
        StatusCode := INVALID_STATUS_CODE;
      end;
    end;
    on E: ENetHTTPException do
    begin
      Answer := 'Нет связи с сервером: ' + E.Message;
      StatusCode := INVALID_STATUS_CODE;
    end;
    on E: Exception do
    begin
      Answer := 'Ошибка: ' + E.Message;
      StatusCode := INVALID_STATUS_CODE;
    end;
  end;
end;

// Методы без шифрования (HTTP)

class function TMyHttpClient.HttpClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, Question, Answer, StatusCode, THttpMethod.hmPost, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

class function TMyHttpClient.HttpClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, Question, Answer, StatusCode, THttpMethod.hmPatch, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

class function TMyHttpClient.HttpClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, '', Answer, StatusCode, THttpMethod.hmGet, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

// Методы c шифрованием (HTTPS)

class function TMyHttpClient.HttpsClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPSClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, Question, Answer, StatusCode, THttpMethod.hmPost, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

class function TMyHttpClient.HttpsClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPSClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, Question, Answer, StatusCode, THttpMethod.hmPatch, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

class function TMyHttpClient.HttpsClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
  const ContentType: string = 'application/json'): Boolean;
var
  Client: TMyHttpClient;
begin
  Client := TMyHttpClient.CreateHTTPSClient(ContentType);
  try
    Result := Client.HttpClientCore(URL, '', Answer, StatusCode, THttpMethod.hmGet, ContentType);
  finally
    FreeAndNil(Client);
  end;
end;

end.
