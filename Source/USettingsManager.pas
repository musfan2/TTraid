{
  Менеджер настроек приложения.
  Загрузка/сохранение параметров подключения (токен, прокси, счёт, интервал опроса)
  через TMySaveIniFile в секцию [Connection].

  Потокобезопасный доступ к FSettings через TMyCriticalSection (LockForRead/LockForWrite).
  TMySaveIniFile создаётся с SavePeriodSec = 5 для продолжительной работы.

  Requirements: 1.1, 1.2, 1.3, 5.4
}

unit USettingsManager;

interface

uses
  SysUtils,
  // Core-модули проекта
  MyIniFile, MyCriticalSection;

type
  TAppSettings = record
    Token: string;
    ProxyHost: string;
    ProxyPort: Integer;
    ProxyUser: string;
    ProxyPass: string;
    AccountId: string;
    PollIntervalSec: Integer;  // 30..120
  end;

  TSettingsManager = class
  private
    FIniFile: TMySaveIniFile;
    FSettings: TAppSettings;
    FCritSection: TMyCriticalSection;
  public
    constructor Create(const AIniPath: string);
    destructor Destroy; override;

    procedure Load;
    procedure Save;
    function GetSettings: TAppSettings;
    procedure SetSettings(const ASettings: TAppSettings);
  end;

implementation

const
  SECTION_CONNECTION = 'Connection';

  KEY_TOKEN             = 'Token';
  KEY_PROXY_HOST        = 'ProxyHost';
  KEY_PROXY_PORT        = 'ProxyPort';
  KEY_PROXY_USER        = 'ProxyUser';
  KEY_PROXY_PASS        = 'ProxyPass';
  KEY_ACCOUNT_ID        = 'AccountId';
  KEY_POLL_INTERVAL_SEC = 'PollIntervalSec';

  DEFAULT_POLL_INTERVAL_SEC = 60;
  MIN_POLL_INTERVAL_SEC     = 30;
  MAX_POLL_INTERVAL_SEC     = 120;

{ TSettingsManager }

constructor TSettingsManager.Create(const AIniPath: string);
begin
  inherited Create;
  // Критическая секция для защиты FSettings от конкурентного доступа
  FCritSection := TMyCriticalSection.Create('TSettingsManager.FSettings');
  // INI-файл с автосохранением каждые 5 секунд для продолжительной работы
  FIniFile := TMySaveIniFile.Create(AIniPath, 5);
  // Загружаем настройки при создании
  Load;
end;

destructor TSettingsManager.Destroy;
begin
  // Освобождаем в обратном порядке создания
  FreeAndNil(FIniFile);
  FreeAndNil(FCritSection);
  inherited Destroy;
end;

procedure TSettingsManager.Load;
var
  pollInterval: Integer;
begin
  FCritSection.LockForWrite('TSettingsManager.Load');
  try
    FSettings.Token := FIniFile.ReadString(SECTION_CONNECTION, KEY_TOKEN, '');
    FSettings.ProxyHost := FIniFile.ReadString(SECTION_CONNECTION, KEY_PROXY_HOST, '');
    FSettings.ProxyPort := FIniFile.ReadInteger(SECTION_CONNECTION, KEY_PROXY_PORT, 0);
    FSettings.ProxyUser := FIniFile.ReadString(SECTION_CONNECTION, KEY_PROXY_USER, '');
    FSettings.ProxyPass := FIniFile.ReadString(SECTION_CONNECTION, KEY_PROXY_PASS, '');
    FSettings.AccountId := FIniFile.ReadString(SECTION_CONNECTION, KEY_ACCOUNT_ID, '');

    // Валидация интервала опроса: 30..120 секунд
    pollInterval := FIniFile.ReadInteger(SECTION_CONNECTION, KEY_POLL_INTERVAL_SEC,
      DEFAULT_POLL_INTERVAL_SEC);
    if pollInterval < MIN_POLL_INTERVAL_SEC then
      pollInterval := MIN_POLL_INTERVAL_SEC
    else if pollInterval > MAX_POLL_INTERVAL_SEC then
      pollInterval := MAX_POLL_INTERVAL_SEC;
    FSettings.PollIntervalSec := pollInterval;
  finally
    FCritSection.UnLockAfterWrite('TSettingsManager.Load');
  end;
end;

procedure TSettingsManager.Save;
begin
  FCritSection.LockForRead('TSettingsManager.Save');
  try
    FIniFile.WriteString(SECTION_CONNECTION, KEY_TOKEN, FSettings.Token);
    FIniFile.WriteString(SECTION_CONNECTION, KEY_PROXY_HOST, FSettings.ProxyHost);
    FIniFile.WriteInteger(SECTION_CONNECTION, KEY_PROXY_PORT, FSettings.ProxyPort);
    FIniFile.WriteString(SECTION_CONNECTION, KEY_PROXY_USER, FSettings.ProxyUser);
    FIniFile.WriteString(SECTION_CONNECTION, KEY_PROXY_PASS, FSettings.ProxyPass);
    FIniFile.WriteString(SECTION_CONNECTION, KEY_ACCOUNT_ID, FSettings.AccountId);
    FIniFile.WriteInteger(SECTION_CONNECTION, KEY_POLL_INTERVAL_SEC, FSettings.PollIntervalSec);
  finally
    FCritSection.UnLockAfterRead('TSettingsManager.Save');
  end;
end;

function TSettingsManager.GetSettings: TAppSettings;
begin
  FCritSection.LockForRead('TSettingsManager.GetSettings');
  try
    Result := FSettings;
  finally
    FCritSection.UnLockAfterRead('TSettingsManager.GetSettings');
  end;
end;

procedure TSettingsManager.SetSettings(const ASettings: TAppSettings);
begin
  FCritSection.LockForWrite('TSettingsManager.SetSettings');
  try
    FSettings := ASettings;

    // Валидация интервала опроса: 30..120 секунд
    if FSettings.PollIntervalSec < MIN_POLL_INTERVAL_SEC then
      FSettings.PollIntervalSec := MIN_POLL_INTERVAL_SEC
    else if FSettings.PollIntervalSec > MAX_POLL_INTERVAL_SEC then
      FSettings.PollIntervalSec := MAX_POLL_INTERVAL_SEC;
  finally
    FCritSection.UnLockAfterWrite('TSettingsManager.SetSettings');
  end;

  // Сохраняем в INI-файл после обновления настроек
  Save;
end;

end.
