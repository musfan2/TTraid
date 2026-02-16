program TTraid;

uses
  System.StartUpCopy,
  FMX.Forms,
  UMainForm in 'Source\UMainForm.pas' {MainForm};

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
