{
  Потокобезопасный объект для работы с INI-файлами.
  Чтобы не дергать накопитель, используется TMemIniFile.
  При создании можно указать интервал автосохранения на диск (в сек.), если есть изменения.
  Если Вы используете TMySaveIniFile для того, чтобы быстро прочитать\записать какой-то параметр,
  то очень важно в Create передать SavePeriod = 0, чтобы не создавался поток и все сразу писалось на диск.
  Однако, если TMySaveIniFile создается для продолжительной работы, то SavePeriod рекомендуется указать = 5.

  DoctorS, 2022-2024.
}

unit MyIniFile;

interface

// Здесь не должно быть ClearFunctions, SysFunc и других зависимостей от Ресурса и УСПД!
uses IniFiles, Classes, MyCriticalSection, MyThread;

type
  TMyIniFileThread = class;

  TMySaveIniFile = class
  strict private
    FIniFile: TMemIniFile;
    FIniPath: string;
    FNeedSave: Boolean; // FPC не умеет отслежтивать изменения - делаем это сами
    FMyIniFileThread: TMyIniFileThread;
    FCritSection: TMyCriticalSection;
  private
    // Про inline: https://pascal-study.blogspot.com/2011/04/blog-post_2596.html
    procedure LockForRead(const FuncName: string);
    procedure UnlockAfterRead(const FuncName: string);
    procedure LockForWrite(const FuncName: string);
    procedure UnlockAfterWrite(const FuncName: string);
  public
    // ПРОЧТИ !!!
    // Если Вы используете TMySaveIniFile для того, чтобы быстро прочитать\записать какой-то параметр,
    // то очень важно в Create передать SavePeriodSec = 0, чтобы не создавался поток и все сразу писалось на диск.
    // Однако, если TMySaveIniFile создается для продолжительной работы, то SavePeriodSec рекомендуется указать = 5.
    constructor Create(const IniPath: string; const SavePeriodSec: Integer);
    destructor Destroy; override;

    function FileExist: Boolean; // А есть файл на диске?
    function FilePath: string; // Путь к файлу

    procedure SaveFile; // Принудительная мгновенная запись в файл
    procedure AutoSaveFile; // Записывает файл только, если есть изменения
    procedure Reload; // Повторно загрузить файл с диска

    // Список методов можно расширять при необходимости
    function ReadString(const Section, Ident, Default: string): string;
    procedure WriteString(const Section, Ident, Value: string);
    function ReadInteger(const Section, Ident: string; Default: Integer): Integer;
    procedure WriteInteger(const Section, Ident: string; Value: Integer);
    function ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
    procedure WriteBool(const Section, Ident: string; Value: Boolean);
    function ReadDateTime(const Section, Name: string; Default: TDateTime): TDateTime;
    procedure WriteDateTime(const Section, Name: string; Value: TDateTime);
    function ReadFloat(const Section, Name: string; Default: Double): Double;
    procedure WriteFloat(const Section, Name: string; Value: Double);
    function SectionExists(const SectionName: string): Boolean;
    procedure EraseSection(const SectionName: string);
    procedure DeleteKey(const Section, Ident: string);
  end;

  // Сохраняет на диск переодически INI-файл
  TMyIniFileThread = class(TMyThread)
  private
    FMyIni: TMySaveIniFile;
    FSavePeriodSec: Integer;
  public
    constructor Create(const MyIni: TMySaveIniFile; const SavePeriodSec: Integer); overload;
    destructor Destroy; override;
    procedure Execute; override;
  end;

implementation

uses
  SysUtils;

{$REGION 'TMySaveIniFile'}

constructor TMySaveIniFile.Create(const IniPath: string; const SavePeriodSec: Integer);
var
  SL: TStringlist;
begin
  FNeedSave := False; // FPC не умеет отслежтивать изменения - делаем это сами
  if not FileExists(IniPath) then
  begin // Если файла нет - создадим его с нужной кодировкой перед открытием TMemIniFile!
    // Если кодировку указать в TMemIniFile.Create - будет глючить под Delphi (под FPC не пробовал)
    SL := TStringlist.Create;
    try
      SL.WriteBOM := True;
      SL.SaveToFile(IniPath, TEncoding.UTF8);
    finally
      FreeAndNil(SL);
    end;
  end;

  FIniPath := IniPath;
  try
    FIniFile := nil;
    FIniFile := TMemIniFile.Create(FIniPath);
  except
    on E: EEncodingError do
    begin // В случае проблем с кодировкой, пробуем открыть файлик, как ANSI
      try
        FreeAndNil(FIniFile);
        FIniFile := TMemIniFile.Create(FIniPath, TEncoding.ANSI);
      except
        FreeAndNil(FIniFile);
      end;
    end;
  end;

  if Assigned(FIniFile) then
  begin
    FIniFile.Encoding := TEncoding.UTF8;
    FCritSection := TMyCriticalSection.Create(FIniFile, 'TMySaveIniFile');
    if SavePeriodSec > 0 then
      FMyIniFileThread := TMyIniFileThread.Create(Self, SavePeriodSec)
    else
      FMyIniFileThread := nil;
  end
  else
    raise Exception.Create('Ошибка открытия файла настроек "' + IniPath + '"!');
end;

destructor TMySaveIniFile.Destroy;
begin
  TMyThread.TerminateAndFree(TThread(FMyIniFileThread));
  AutoSaveFile; // Сохраним, если нужно
  FreeAndNil(FCritSection); // ДО FreeAndNil(FIniFile)
  FreeAndNil(FIniFile);
  inherited;
end;

procedure TMySaveIniFile.LockForRead(const FuncName: string);
begin
  FCritSection.LockObj(FuncName);
end;

procedure TMySaveIniFile.LockForWrite(const FuncName: string);
begin
  FCritSection.LockObj(FuncName);
  // FNeedSave должен быть тут, а не в UnlockAfterWrite - иначе флаг всегда будет True
  FNeedSave := True; // FPC не умеет отслежтивать изменения - делаем это сами
end;

procedure TMySaveIniFile.UnlockAfterRead(const FuncName: string);
begin
  FCritSection.UnLockObj(FuncName);
end;

procedure TMySaveIniFile.UnlockAfterWrite(const FuncName: string);
begin
  FCritSection.UnLockObj(FuncName);

  if not Assigned(FMyIniFileThread) then
    AutoSaveFile; // Сохраним сразу, если нет потока отложенной записи
end;

procedure TMySaveIniFile.SaveFile;
// Принудительная мгновенная запись в файл
begin
  // Используем LockForRead вместо LockForWrite, чтобы не устанавливать FNeedSave := True
  // LockForWrite устанавливает FNeedSave := True, что приводит к рекурсивному вызову SaveFile
  FCritSection.LockObj('TMySaveIniFile.SaveFile');
  try
    FIniFile.UpdateFile;
    FNeedSave := False; // FPC не умеет отслежтивать изменения - делаем это сами
  finally
    FCritSection.UnLockObj('TMySaveIniFile.SaveFile');
  end;
end;

procedure TMySaveIniFile.AutoSaveFile;
// Записывает файл только, если есть изменения
begin
  if FNeedSave then
    SaveFile;
end;

function TMySaveIniFile.SectionExists(const SectionName: string): Boolean;
begin
  LockForRead('SectionExists');
  try
    Result := FIniFile.SectionExists(SectionName);
  finally
    UnlockAfterRead('SectionExists');
  end;
end;

procedure TMySaveIniFile.EraseSection(const SectionName: string);
begin
  LockForWrite('EraseSection');
  try
    FIniFile.EraseSection(SectionName);
  finally
    UnlockAfterWrite('EraseSection');
  end;
end;

procedure TMySaveIniFile.DeleteKey(const Section, Ident: string);
begin
  LockForWrite('DeleteKey');
  try
    FIniFile.DeleteKey(Section, Ident);
  finally
    UnlockAfterWrite('DeleteKey');
  end;
end;

function TMySaveIniFile.FileExist: Boolean;
begin
  Result := FileExists(FIniPath);
end;

function TMySaveIniFile.FilePath: string;
begin
  Result := FIniPath;
end;

function TMySaveIniFile.ReadBool(const Section, Ident: string; Default: Boolean): Boolean;
begin
  LockForRead('ReadBool');
  try
    Result := FIniFile.ReadBool(Section, Ident, default);
  finally
    UnlockAfterRead('ReadBool');
  end;
end;

function TMySaveIniFile.ReadDateTime(const Section, Name: string; Default: TDateTime): TDateTime;
begin
  LockForRead('ReadDateTime');
  try
    Result := FIniFile.ReadDateTime(Section, name, default);
  finally
    UnlockAfterRead('ReadDateTime');
  end;
end;

function TMySaveIniFile.ReadFloat(const Section, Name: string; Default: Double): Double;
begin
  LockForRead('ReadFloat');
  try
    Result := FIniFile.ReadFloat(Section, name, default);
  finally
    UnlockAfterRead('ReadFloat');
  end;
end;

function TMySaveIniFile.ReadInteger(const Section, Ident: string; Default: Integer): Integer;
begin
  LockForRead('ReadInteger');
  try
    Result := FIniFile.ReadInteger(Section, Ident, default);
  finally
    UnlockAfterRead('ReadInteger');
  end;
end;

function TMySaveIniFile.ReadString(const Section, Ident, Default: string): string;
begin
  LockForRead('ReadString');
  try
    Result := FIniFile.ReadString(Section, Ident, default);
  finally
    UnlockAfterRead('ReadString');
  end;
end;

procedure TMySaveIniFile.Reload;
// Заставим перезагрузить файлик: переоткрыв его ещё раз
begin
  // 1. Тормозим поток
  if Assigned(FMyIniFileThread) then
    FMyIniFileThread.Suspended := True;

  // 2. Грохнем старый TMemIniFile и создадим новый, чтобы он перечитал файл с диска
  // Все не сохранённый данные будут потеряны! Такова логика работы Reload !!!
  FreeAndNil(FIniFile);
  FIniFile := TMemIniFile.Create(FIniPath);
  FCritSection.UpdateProtectedObj(FIniFile, False); // Обновим FIniFile в FCritSection

  // 3. Зададим кодировку
  LockForWrite('Reload');
  try
    FIniFile.Encoding := TEncoding.UTF8;
  finally
    UnlockAfterWrite('Reload');
  end;

  // 4. Продолжаем работу потока, если он был
  if Assigned(FMyIniFileThread) then
    FMyIniFileThread.Suspended := False;
end;

procedure TMySaveIniFile.WriteBool(const Section, Ident: string; Value: Boolean);
begin
  LockForWrite('WriteBool');
  try
    FIniFile.WriteBool(Section, Ident, Value);
  finally
    UnlockAfterWrite('WriteBool');
  end;
end;

procedure TMySaveIniFile.WriteDateTime(const Section, Name: string; Value: TDateTime);
begin
  LockForWrite('WriteDateTime');
  try
    FIniFile.WriteDateTime(Section, name, Value);
  finally
    UnlockAfterWrite('WriteDateTime');
  end;
end;

procedure TMySaveIniFile.WriteFloat(const Section, Name: string; Value: Double);
begin
  LockForWrite('WriteFloat');
  try
    FIniFile.WriteFloat(Section, name, Value);
  finally
    UnlockAfterWrite('WriteFloat');
  end;
end;

procedure TMySaveIniFile.WriteInteger(const Section, Ident: string; Value: Integer);
begin
  LockForWrite('WriteInteger');
  try
    FIniFile.WriteInteger(Section, Ident, Value);
  finally
    UnlockAfterWrite('WriteInteger');
  end;
end;

procedure TMySaveIniFile.WriteString(const Section, Ident, Value: string);
begin
  LockForWrite('WriteString');
  try
    FIniFile.WriteString(Section, Ident, Value);
  finally
    UnlockAfterWrite('WriteString');
  end;
end;

{$ENDREGION 'TMySaveIniFile'}
{$REGION 'TMyIniFileThread'}

constructor TMyIniFileThread.Create(const MyIni: TMySaveIniFile; const SavePeriodSec: Integer);
begin
  FMyIni := MyIni;
  FSavePeriodSec := SavePeriodSec;
  FreeOnTerminate := False;
  inherited Create(False);
end;

destructor TMyIniFileThread.Destroy;
begin
  inherited;
end;

procedure TMyIniFileThread.Execute;
begin
  inherited; // Должно быть первой строчкой, чтобы сработал NameThread(ClassName) у TMyThread.Execute

  while not Terminated do
  begin
    ImAlive; // Первым делом говорим, что живы для TThreadMonitor

    DelayForThread(Self, FSavePeriodSec * 1000);

    // Записываем файл на диск на случай краха программы
    FMyIni.AutoSaveFile; // Проверка на Terminated, а то потеряем данные!
  end;
end;

{$ENDREGION 'TMyIniFileThread'}

end.
