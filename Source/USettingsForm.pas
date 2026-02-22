{
  Форма настроек приложения.
  Вкладка "Прокси" — глобальные настройки прокси (по умолчанию выключены).
  Вкладка "Профили" — управление профилями подключения (имя, токен, интервал).
  Вызывается из главного меню: Файл → Настройки.
}

unit USettingsForm;

interface

uses
  System.SysUtils, System.Classes, System.UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs, FMX.DialogService,
  FMX.StdCtrls, FMX.Edit, FMX.ListBox, FMX.Layouts,
  FMX.Controls.Presentation, FMX.EditBox, FMX.SpinBox,
  FMX.TabControl,
  USettingsManager;

type
  TSettingsForm = class(TForm)
    TabControlSettings: TTabControl;
    TabProxy: TTabItem;
    TabProfiles: TTabItem;

    { Прокси }
    CheckProxyEnabled: TCheckBox;
    LabelProxyHost: TLabel;
    EditProxyHost: TEdit;
    LabelProxyPort: TLabel;
    SpinProxyPort: TSpinBox;
    LabelProxyUser: TLabel;
    EditProxyUser: TEdit;
    LabelProxyPass: TLabel;
    EditProxyPass: TEdit;

    { Профили }
    ListProfiles: TListBox;
    LayoutProfileButtons: TLayout;
    BtnAddProfile: TButton;
    BtnDeleteProfile: TButton;
    LayoutProfileEdit: TLayout;
    LabelProfName: TLabel;
    EditProfName: TEdit;
    LabelProfToken: TLabel;
    EditProfToken: TEdit;
    LabelProfPollInterval: TLabel;
    SpinProfPollInterval: TSpinBox;
    LabelProfPollSec: TLabel;

    { Кнопки диалога }
    LayoutDialogButtons: TLayout;
    BtnOK: TButton;
    BtnCancel: TButton;

    procedure CheckProxyEnabledChange(Sender: TObject);
    procedure ListProfilesChange(Sender: TObject);
    procedure BtnAddProfileClick(Sender: TObject);
    procedure BtnDeleteProfileClick(Sender: TObject);
    procedure BtnOKClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
  private
    FSettings: TAppSettings;
    FCurrentProfileIndex: Integer;

    procedure UpdateProxyControls;
    procedure SaveCurrentProfileToArray;
    procedure LoadProfileToUI(const AIndex: Integer);
    procedure RefreshProfileList;
  public
    procedure SetSettings(const ASettings: TAppSettings);
    function GetSettings: TAppSettings;
  end;

implementation

{$R *.fmx}

{ TSettingsForm }

procedure TSettingsForm.SetSettings(const ASettings: TAppSettings);
begin
  FSettings := ASettings;
  FCurrentProfileIndex := -1;

  // Прокси
  CheckProxyEnabled.IsChecked := FSettings.Proxy.Enabled;
  EditProxyHost.Text := FSettings.Proxy.Host;
  SpinProxyPort.Value := FSettings.Proxy.Port;
  EditProxyUser.Text := FSettings.Proxy.User;
  EditProxyPass.Text := FSettings.Proxy.Pass;
  UpdateProxyControls;

  // Профили
  RefreshProfileList;
  if Length(FSettings.Profiles) > 0 then
  begin
    ListProfiles.ItemIndex := 0;
    LoadProfileToUI(0);
  end;
end;

function TSettingsForm.GetSettings: TAppSettings;
begin
  // Сохраняем текущий редактируемый профиль
  SaveCurrentProfileToArray;

  // Прокси
  FSettings.Proxy.Enabled := CheckProxyEnabled.IsChecked;
  FSettings.Proxy.Host := EditProxyHost.Text;
  FSettings.Proxy.Port := Trunc(SpinProxyPort.Value);
  FSettings.Proxy.User := EditProxyUser.Text;
  FSettings.Proxy.Pass := EditProxyPass.Text;

  Result := FSettings;
end;

procedure TSettingsForm.UpdateProxyControls;
var
  isEnabled: Boolean;
begin
  isEnabled := CheckProxyEnabled.IsChecked;
  EditProxyHost.Enabled := isEnabled;
  SpinProxyPort.Enabled := isEnabled;
  EditProxyUser.Enabled := isEnabled;
  EditProxyPass.Enabled := isEnabled;
end;

procedure TSettingsForm.CheckProxyEnabledChange(Sender: TObject);
begin
  UpdateProxyControls;
end;

procedure TSettingsForm.RefreshProfileList;
var
  I: Integer;
begin
  ListProfiles.Items.Clear;
  for I := 0 to High(FSettings.Profiles) do
    ListProfiles.Items.Add(FSettings.Profiles[I].Name);
end;

procedure TSettingsForm.SaveCurrentProfileToArray;
begin
  if (FCurrentProfileIndex < 0) or (FCurrentProfileIndex > High(FSettings.Profiles)) then
    Exit;

  FSettings.Profiles[FCurrentProfileIndex].Name := EditProfName.Text;
  FSettings.Profiles[FCurrentProfileIndex].Token := EditProfToken.Text;
  FSettings.Profiles[FCurrentProfileIndex].PollIntervalSec := Trunc(SpinProfPollInterval.Value);

  // Обновляем имя в списке
  if FCurrentProfileIndex < ListProfiles.Items.Count then
    ListProfiles.Items[FCurrentProfileIndex] := EditProfName.Text;
end;

procedure TSettingsForm.LoadProfileToUI(const AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FSettings.Profiles)) then
  begin
    EditProfName.Text := '';
    EditProfToken.Text := '';
    SpinProfPollInterval.Value := 60;
    FCurrentProfileIndex := -1;
    Exit;
  end;

  FCurrentProfileIndex := AIndex;
  EditProfName.Text := FSettings.Profiles[AIndex].Name;
  EditProfToken.Text := FSettings.Profiles[AIndex].Token;
  SpinProfPollInterval.Value := FSettings.Profiles[AIndex].PollIntervalSec;
end;

procedure TSettingsForm.ListProfilesChange(Sender: TObject);
begin
  // Сохраняем предыдущий профиль перед переключением
  SaveCurrentProfileToArray;
  LoadProfileToUI(ListProfiles.ItemIndex);
end;

procedure TSettingsForm.BtnAddProfileClick(Sender: TObject);
var
  newProfile: TConnectionProfile;
  newIndex: Integer;
begin
  newProfile.Name := 'Профиль ' + (Length(FSettings.Profiles) + 1).ToString;
  newProfile.Token := '';
  newProfile.AccountId := '';
  newProfile.PollIntervalSec := 60;

  // Сохраняем текущий перед добавлением
  SaveCurrentProfileToArray;

  newIndex := Length(FSettings.Profiles);
  SetLength(FSettings.Profiles, newIndex + 1);
  FSettings.Profiles[newIndex] := newProfile;

  RefreshProfileList;
  ListProfiles.ItemIndex := newIndex;
  LoadProfileToUI(newIndex);
end;

procedure TSettingsForm.BtnDeleteProfileClick(Sender: TObject);
var
  idx, I: Integer;
begin
  idx := ListProfiles.ItemIndex;
  if idx < 0 then
    Exit;

  // Нельзя удалить последний профиль
  if Length(FSettings.Profiles) <= 1 then
  begin
    TDialogService.MessageDialog('Нельзя удалить единственный профиль.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  // Сдвигаем массив
  for I := idx to High(FSettings.Profiles) - 1 do
    FSettings.Profiles[I] := FSettings.Profiles[I + 1];
  SetLength(FSettings.Profiles, Length(FSettings.Profiles) - 1);

  FCurrentProfileIndex := -1;
  RefreshProfileList;

  if idx >= ListProfiles.Items.Count then
    idx := ListProfiles.Items.Count - 1;
  ListProfiles.ItemIndex := idx;
  LoadProfileToUI(idx);
end;

procedure TSettingsForm.BtnOKClick(Sender: TObject);
begin
  SaveCurrentProfileToArray;
  ModalResult := mrOk;
end;

procedure TSettingsForm.BtnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

end.
