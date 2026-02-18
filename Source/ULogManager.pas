unit ULogManager;

interface

uses
  System.SysUtils, System.Types,
  // Core-модули проекта
  MyThreadList;

type
  /// <summary>
  /// Запись лога: время, уровень, сообщение.
  /// </summary>
  TLogEntry = record
    Timestamp: TDateTime;
    Level: string;       // 'INFO', 'ERROR', 'WARN'
    Message: string;
  end;

  /// <summary>
  /// Callback для уведомления GUI о новой записи лога.
  /// </summary>
  TOnLogEntry = procedure(const AEntry: TLogEntry) of object;

  /// <summary>
  /// Потокобезопасный менеджер лога с ограничением размера.
  /// Использует TMyThreadList для хранения записей.
  /// При превышении FMaxEntries автоматически удаляет старые записи.
  /// </summary>
  TLogManager = class
  private
    FEntries: TMyThreadList<TLogEntry>;
    FMaxEntries: Integer;
    FOnLogEntry: TOnLogEntry;
  public
    /// <summary>
    /// Глобальный экземпляр для использования из Core-модулей.
    /// Устанавливается приложением при создании менеджера лога.
    /// </summary>
    class var Instance: TLogManager;
    constructor Create(const AMaxEntries: Integer = 500);
    destructor Destroy; override;

    /// <summary>
    /// Добавить запись в лог с указанным уровнем и сообщением.
    /// </summary>
    procedure Log(const ALevel, AMessage: string);

    /// <summary>
    /// Добавить информационную запись (уровень 'INFO').
    /// </summary>
    procedure LogInfo(const AMessage: string);

    /// <summary>
    /// Добавить запись об ошибке (уровень 'ERROR').
    /// </summary>
    procedure LogError(const AMessage: string);

    /// <summary>
    /// Добавить предупреждение (уровень 'WARN').
    /// </summary>
    procedure LogWarning(const AMessage: string);

    /// <summary>
    /// Получить копию всех записей лога (потокобезопасно).
    /// </summary>
    function GetEntries: TArray<TLogEntry>;

    /// <summary>
    /// Событие, вызываемое при добавлении новой записи.
    /// Используется для уведомления GUI.
    /// </summary>
    property OnLogEntry: TOnLogEntry read FOnLogEntry write FOnLogEntry;
  end;

implementation

{ TLogManager }

constructor TLogManager.Create(const AMaxEntries: Integer = 500);
begin
  inherited Create;
  FMaxEntries := AMaxEntries;
  // TMyThreadList с MaxElementCount автоматически удаляет старые записи при превышении лимита
  FEntries := TMyThreadList<TLogEntry>.Create('TLogManager.FEntries', FMaxEntries);
  // Разрешаем дубликаты — записи лога могут повторяться
  FEntries.Duplicates := dupAccept;
end;

destructor TLogManager.Destroy;
begin
  FOnLogEntry := nil;
  FreeAndNil(FEntries);
  inherited Destroy;
end;

procedure TLogManager.Log(const ALevel, AMessage: string);
var
  entry: TLogEntry;
begin
  entry.Timestamp := Now;
  entry.Level := ALevel;
  entry.Message := AMessage;

  if Assigned(FEntries) then
    FEntries.Add(entry);

  // Уведомляем подписчика (GUI) о новой записи
  if Assigned(FOnLogEntry) then
    FOnLogEntry(entry);
end;

procedure TLogManager.LogInfo(const AMessage: string);
begin
  Log('INFO', AMessage);
end;

procedure TLogManager.LogError(const AMessage: string);
begin
  Log('ERROR', AMessage);
end;

procedure TLogManager.LogWarning(const AMessage: string);
begin
  Log('WARN', AMessage);
end;

function TLogManager.GetEntries: TArray<TLogEntry>;
var
  I: Integer;
begin
  Result := nil;

  if not Assigned(FEntries) then
    Exit;

  var
  List := FEntries.LockForRead('GetEntries');
  try
    if Assigned(List) then
    begin
      SetLength(Result, List.Count);
      for I := 0 to List.Count - 1 do
        Result[I] := List[I];
    end;
  finally
    FEntries.UnlockAfterRead('GetEntries');
  end;
end;

end.
