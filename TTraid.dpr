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
  UOrderForm in 'Source\UOrderForm.pas' {OrderForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
