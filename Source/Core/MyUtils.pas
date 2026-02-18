{
  Утилитные функции общего назначения для Core-модулей.
  Содержит функции, которые используются в нескольких Core-модулях
  и не привязаны к конкретному классу.

  DoctorS, 2024-2025.
}

unit MyUtils;

interface

{ Проверяет, выполняется ли код в главном потоке приложения }
function IsUnderMainThread: Boolean;

{ Обработка сообщений приложения. Вызывает Application.ProcessMessages,
  но только если код выполняется в главном потоке }
procedure ApplicationProcessMessages;

{ Ожидание завершения загрузки программы (заглушка для совместимости) }
procedure WaitProgramLoading;

implementation

uses
  Classes,
  FMX.Forms;

function IsUnderMainThread: Boolean;
begin
  Result := TThread.Current.ThreadID = MainThreadID;
end;

procedure ApplicationProcessMessages;
begin
  if IsUnderMainThread and Assigned(Application) then
    Application.ProcessMessages;
end;

procedure WaitProgramLoading;
begin
  // Заглушка: в новом проекте загрузка мгновенная
end;

end.
