{

  Удобная обёртка для работы с TNetHTTPClient.
  Автоматически подтягивает настройки прокси из Ресурса.
  Можно использовать как готовые классовые методы для быстрой отправки запроса, так и создать полноценный TNetHTTPClient для более сложной работы.
  Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient (они сами настраивают прокси).

  DoctorS, 2024-2025.
}

unit MyHttpClient;

interface

uses
  System.Classes, System.SysUtils, System.Net.HttpClientComponent, System.Net.HttpClient, System.Net.URLClient;

type

  // Удобная обёртка для работы с TNetHTTPClient
  TMyHttpClient = class(TNetHTTPClient)
  type
    THttpMethod = (hmPost, hmPatch, hmGet);
  private

    // Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient (они сами настраивают прокси)
    constructor Create(AOwner: TComponent); reintroduce;

    // Самая главная функция, которая всё делает =)
    function HttpClientCore(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean; const HttpMethod: THttpMethod; const ContentType: string): Boolean;

  public
    // === Классовые методы можно вызывать без создания экземпляра класса! =====

    // Создание экземпляра для работы по HTTP с настройкой прокси(!) и заданием ContentType
    class function CreateHTTPClient(const ContentType: string = 'application/json'): TMyHttpClient;
    // Создание экземпляра для работы по HTTPS с настройкой прокси(!). Позволяет указать параметры шифрования (оставь по умолчанию, если не уверен!)
    class function CreateHTTPSClient(const ContentType: string = 'application/json';
      const SecureProtocols: THTTPSecureProtocols = [THTTPSecureProtocol.TLS12, THTTPSecureProtocol.TLS13]): TMyHttpClient;

    // Классовые методы БЕЗ шифрования (HTTP) - можно вызывать без создания экземпляра класса!
    // При необходимости можно расширить список HTTP-методов (Put, Update и т.д.) по аналогии
    class function HttpClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
    class function HttpClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
    class function HttpClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;

    // Классовые методы С шифрованием (HTTPS) - можно вызывать без создания экземпляра класса!
    // При необходимости можно расширить список HTTPS-методов (Put, Update и т.д.) по аналогии
    class function HttpsClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
    class function HttpsClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
    class function HttpsClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
      const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
  end;

implementation

uses SharedConstants, Options, SysFunc, JsonExchangeConst;

{ TMyHttpClient }

constructor TMyHttpClient.Create(AOwner: TComponent);
// Штатный конструктор TNetHTTPClient под запретом! Используйте CreateHTTPClient и CreateHTTPSClient (они сами настраивают прокси)
begin
  inherited;
end;

class function TMyHttpClient.CreateHTTPClient(const ContentType: string = 'application/json'): TMyHttpClient;
// Создадим TNetHTTPClient и настроим прокси
var
  ProxySettings: TProxySettings;
begin
  Result := TMyHttpClient.Create(nil);
  Result.ConnectionTimeout := 10000;
  Result.SendTimeout := 2000;
  Result.ResponseTimeout := 15000;
  Result.SecureProtocols := [];
  try
    // Устанавливаем заголовок Content-Type для запросов
    Result.ContentType := ContentType;

    // Конфигурация прокси-сервера, если он включен
    if CommonOptions.Proxy_Enabled then
    begin
      ProxySettings.Host := CommonOptions.ProxyServer;
      ProxySettings.Port := CommonOptions.ProxyPort;

      if CommonOptions.ProxyAuthEnabled then
      begin
        ProxySettings.UserName := CommonOptions.ProxyUsername;
        ProxySettings.Password := CommonOptions.ProxyPassword;
      end
      else
      begin
        ProxySettings.UserName := '';
        ProxySettings.Password := '';
      end;

      Result.ProxySettings := ProxySettings;
    end;

    // Дополнительные настройки при необходимости
    // Например, установка пользовательских заголовков
    // Result.CustomHeaders['Custom-Header'] := 'HeaderValue';
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

function TMyHttpClient.HttpClientCore(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean; const HttpMethod: THttpMethod; const ContentType: string): Boolean;
// Отправляет запрос и получает ответ
var
  QuestionStream: TStringStream;
  Response: IHTTPResponse;
begin
  Result := False;
  StatusCode := INVALID_VALUE;
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
      else raise Exception.Create('TMyHttpClient.HttpClientCore: не поддерживаемый метод!');
      end;

      // Прочитаем ответ (он может быть даже если код ошибки 403 - такое в API вирт. ключа)
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
        StatusCode := Response.StatusCode; // Получение кода состояния HTTP
      end
      else
      begin
        Answer := '';
        StatusCode := INVALID_VALUE; // ответа нет
      end;
    end;
    on E: ENetHTTPException do
    begin
      if ShowErrMes then
        ShowErrorMessage('Нет связи с сервером! Проверьте настройки сети и прокси.', GetAllOpers);
      Exit(False);
    end;
    on E: Exception do
    begin // Общие исключения
      if ShowErrMes then
        ShowErrorMessage('Неизвестная ошибка: ' + E.Message, GetAllOpers);
      Exit(False);
    end;
  end;
end;

// Методы без шифрования (HTTP)

class function TMyHttpClient.HttpClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Post запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, Question, Answer, StatusCode, ShowErrMes, THttpMethod.hmPost, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

class function TMyHttpClient.HttpClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Patch запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, Question, Answer, StatusCode, ShowErrMes, THttpMethod.hmPatch, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

class function TMyHttpClient.HttpClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Get запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, '', Answer, StatusCode, ShowErrMes, THttpMethod.hmGet, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

// Методы c шифрованием (HTTPS)

class function TMyHttpClient.HttpsClientPost(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Post запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPSClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, Question, Answer, StatusCode, ShowErrMes, THttpMethod.hmPost, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

class function TMyHttpClient.HttpsClientPatch(const URL, Question: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Patch запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPSClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, Question, Answer, StatusCode, ShowErrMes, THttpMethod.hmPatch, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

class function TMyHttpClient.HttpsClientGet(const URL: string; out Answer: string; out StatusCode: Integer;
  const ShowErrMes: Boolean = True; const ContentType: string = 'application/json'): Boolean;
// Отправляет Get запрос и получает ответ
var
  MyHttpClient: TMyHttpClient;
begin
  MyHttpClient := TMyHttpClient.CreateHTTPSClient;
  try
    Result := MyHttpClient.HttpClientCore(URL, '', Answer, StatusCode, ShowErrMes, THttpMethod.hmGet, ContentType);
  finally
    FreeAndNil(MyHttpClient);
  end;
end;

end.
