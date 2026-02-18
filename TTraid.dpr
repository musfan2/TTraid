program TTraid;

uses
  System.StartUpCopy,
  FMX.Forms,
  UMainForm in 'Source\UMainForm.pas' {MainForm},
  UQuotationHelper in 'Source\UQuotationHelper.pas',
  ULogManager in 'Source\ULogManager.pas',
  USettingsManager in 'Source\USettingsManager.pas',
  UOrderManager in 'Source\UOrderManager.pas',
  UApiClient in 'Source\UApiClient.pas',
  UOrderForm in 'Source\UOrderForm.pas' {OrderForm},
  MyCriticalSection in 'Source\Core\MyCriticalSection.pas',
  MyFlag in 'Source\Core\MyFlag.pas',
  MyHttpClient in 'Source\Core\MyHttpClient.pas',
  MyIniFile in 'Source\Core\MyIniFile.pas',
  MyTask in 'Source\Core\MyTask.pas',
  MyThread in 'Source\Core\MyThread.pas',
  MyThreadList in 'Source\Core\MyThreadList.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
