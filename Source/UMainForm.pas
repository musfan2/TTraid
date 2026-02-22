{
  Главная форма приложения "Кормилец" (торговый робот).
  Поддерживает несколько профилей подключения (вкладки).
  Каждая вкладка — независимый TApiClient, TOrderManager, TTimerThread.
  Настройки прокси и профилей — через меню Файл → Настройки.
  Сохранение геометрии окна в INI.

  Все фоновые операции выполняются через TMyTaskAutoFree.
  Обновление GUI из фоновых потоков — только через TThread.Synchronize.
  Глобальный флаг ProgramClosing из MyFlag.pas — для контроля завершения.

  Requirements: 1.1, 1.4, 1.5, 2.1, 2.2, 2.3, 2.4, 2.5, 3.1, 3.2, 3.3, 3.4,
                5.4, 6.1, 7.1, 10.3, 11.1, 11.2, 11.4
}

unit UMainForm;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes,
  System.JSON, System.DateUtils, System.Generics.Collections,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.DialogService,
  FMX.StdCtrls, FMX.Edit, FMX.ListBox, FMX.Layouts, FMX.Memo,
  FMX.Controls.Presentation, FMX.EditBox, FMX.SpinBox, FMX.Grid,
  FMX.Grid.Style, FMX.ScrollBox, FMX.TabControl, FMX.Menus,
  // Core-модули проекта
  MyFlag, MyTask, MyThread,
  // Модули приложения
  ULogManager, USettingsManager, UOrderManager, UApiClient, UQuotationHelper,
  FMX.Memo.Types, System.Rtti;

type
  /// <summary>Контейнер данных одной вкладки профиля</summary>
  TProfileTab = class
  public
    ProfileIndex: Integer;
    TabItem: TTabItem;
    ApiClient: TApiClient;
    OrderManager: TOrderManager;
    Scheduler: TTimerThread;
    PricePollTask: TTimerTask;
    OrderSyncTask: TTimerTask;
    // UI-компоненты (создаются программно)
    LayoutTop: TLayout;
    BtnCheckConnection: TButton;
    LabelAccount: TLabel;
    ComboAccounts: TComboBox;
    GroupBoxOrders: TGroupBox;
    GridOrders: TStringGrid;
    LayoutOrderButtons: TLayout;
    BtnAddOrder: TButton;
    BtnDeleteOrder: TButton;
    BtnActivateOrder: TButton;
    BtnCancelOrder: TButton;
    constructor Create;
    destructor Destroy; override;
  end;

  TMainForm = class(TForm)
    { Меню }
    MenuBar: TMenuBar;
    MenuFile: TMenuItem;
    MenuSettings: TMenuItem;
    MenuSep1: TMenuItem;
    MenuExit: TMenuItem;
    MenuRobot: TMenuItem;
    MenuStart: TMenuItem;
    MenuStop: TMenuItem;
    MenuHelp: TMenuItem;
    MenuAbout: TMenuItem;

    { Вкладки профилей }
    TabControlProfiles: TTabControl;

    { Панель лога (низ) }
    PanelBottom: TLayout;
    GroupBoxLog: TGroupBox;
    MemoLog: TMemo;
    LayoutLogControls: TLayout;
    BtnStart: TButton;
    BtnStop: TButton;
    LabelStatus: TLabel;

    { Обработчики событий формы }
    procedure FormCreate(Sender: TObject);
    procedure FormClose(Sender: TObject; var Action: TCloseAction);

    { Обработчики меню }
    procedure MenuSettingsClick(Sender: TObject);
    procedure MenuExitClick(Sender: TObject);
    procedure MenuStartClick(Sender: TObject);
    procedure MenuStopClick(Sender: TObject);
    procedure MenuAboutClick(Sender: TObject);

    { Обработчик переключения вкладок }
    procedure TabControlProfilesChange(Sender: TObject);
  private
    FLogManager: TLogManager;
    FSettingsManager: TSettingsManager;
    FProfileTabs: TObjectList<TProfileTab>;

    { Создание/пересоздание вкладок профилей }
    procedure RebuildProfileTabs;
    procedure CreateProfileTab(const AProfileIndex: Integer;
      const AProfile: TConnectionProfile);
    procedure DestroyAllProfileTabs;

    { Применение прокси к API-клиенту }
    procedure ApplyProxyToClient(const AClient: TApiClient);

    { UI-компоненты вкладки — создание программно }
    procedure BuildTabUI(const ATab: TProfileTab);

    { Обработчики кнопок внутри вкладки }
    procedure OnBtnCheckConnectionClick(Sender: TObject);
    procedure OnBtnAddOrderClick(Sender: TObject);
    procedure OnBtnDeleteOrderClick(Sender: TObject);
    procedure OnBtnActivateOrderClick(Sender: TObject);
    procedure OnBtnCancelOrderClick(Sender: TObject);
    procedure OnGridOrdersCellDblClick(const AColumn: TColumn; const ARow: Integer);

    { Фоновые задачи }
    procedure PollPrices(const ATab: TProfileTab);
    procedure SyncOrders(const ATab: TProfileTab);

    { Обновление таблицы ордеров }
    procedure RefreshOrderGrid(const ATab: TProfileTab);

    { Callback для TLogManager.OnLogEntry }
    procedure OnLogEntry(const AEntry: TLogEntry);

    { Геометрия окна }
    procedure LoadWindowGeometry;
    procedure SaveWindowGeometry;

    { Получить TProfileTab по UI-компоненту (Sender) }
    function FindTabBySender(const ASender: TObject): TProfileTab;
    function GetActiveProfileTab: TProfileTab;

    { Вспомогательные функции для отображения }
    class function StatusToStr(const AStatus: TOrderStatus): string; static;
    class function DirectionToStr(const ADirection: TOrderDirection): string; static;
    class function OrderTypeToStr(const AOrderType: TOrderType): string; static;
    class function FormatPrice(const APrice: Double): string; static;
  public
    { Public declarations }
  end;

var
  MainForm: TMainForm;

implementation

{$R *.fmx}

uses
  UOrderForm, USettingsForm;

const
  // Строковые представления статусов ордеров
  STATUS_STRINGS: array[TOrderStatus] of string = (
    'Новый',                // osNew
    'Ожидает',              // osPending
    'Исполнен',             // osFilled
    'Отклонён',             // osRejected
    'Отменён',              // osCancelled
    'Неизвестен'            // osUnknown
  );

  // Строковые представления направлений
  DIRECTION_STRINGS: array[TOrderDirection] of string = (
    'Покупка',              // odBuy
    'Продажа'               // odSell
  );

  // Строковые представления типов ордеров
  ORDER_TYPE_STRINGS: array[TOrderType] of string = (
    'Рыночный',             // otMarket
    'Лимитный',             // otLimit
    'По лучшей цене'        // otBestPrice
  );

  // Максимум строк в MemoLog
  MAX_LOG_LINES = 500;

{ TProfileTab }

constructor TProfileTab.Create;
begin
  inherited Create;
  ProfileIndex := -1;
  TabItem := nil;
  ApiClient := nil;
  OrderManager := nil;
  Scheduler := nil;
  PricePollTask := nil;
  OrderSyncTask := nil;
end;

destructor TProfileTab.Destroy;
begin
  // Останавливаем планировщик
  if Assigned(Scheduler) then
  begin
    Scheduler.Enabled := False;
    TMyThread.TerminateAndFree<TTimerThread>(Scheduler);
  end;
  // PricePollTask и OrderSyncTask освобождаются планировщиком

  FreeAndNil(ApiClient);
  FreeAndNil(OrderManager);
  // TabItem освобождается владельцем (TabControl)
  inherited Destroy;
end;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  // 1. Создаём менеджер лога
  FLogManager := TLogManager.Create(500);
  TLogManager.Instance := FLogManager;

  // 2. Создаём менеджер настроек
  FSettingsManager := TSettingsManager.Create('settings.ini');

  // 3. Список вкладок профилей
  FProfileTabs := TObjectList<TProfileTab>.Create(True);

  // 4. Подписываемся на события лога
  FLogManager.OnLogEntry := OnLogEntry;

  // 5. Восстанавливаем геометрию окна
  LoadWindowGeometry;

  // 6. Создаём вкладки профилей
  RebuildProfileTabs;

  // 7. Сбрасываем флаг загрузки
  ProgramLoading := False;

  FLogManager.LogInfo('Приложение запущено');
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // 1. Флаг закрытия
  ProgramClosing := True;

  // 2. Сохраняем геометрию окна
  SaveWindowGeometry;

  // 3. Уничтожаем все вкладки (останавливает планировщики, освобождает ресурсы)
  DestroyAllProfileTabs;

  // 4. Отписываемся от лога
  TLogManager.Instance := nil;
  if Assigned(FLogManager) then
    FLogManager.OnLogEntry := nil;

  // 5. Освобождаем в обратном порядке
  FreeAndNil(FProfileTabs);
  FreeAndNil(FSettingsManager);
  FreeAndNil(FLogManager);
end;

{ --- Геометрия окна --- }

procedure TMainForm.LoadWindowGeometry;
var
  settings: TAppSettings;
begin
  if not Assigned(FSettingsManager) then
    Exit;

  settings := FSettingsManager.GetSettings;

  if settings.Window.Maximized then
  begin
    WindowState := TWindowState.wsMaximized;
    Exit;
  end;

  if settings.Window.Width > 0 then
    ClientWidth := settings.Window.Width;
  if settings.Window.Height > 0 then
    ClientHeight := settings.Window.Height;
  if (settings.Window.Left >= 0) and (settings.Window.Top >= 0) then
  begin
    Position := TFormPosition.Designed;
    Left := settings.Window.Left;
    Top := settings.Window.Top;
  end;
end;

procedure TMainForm.SaveWindowGeometry;
var
  settings: TAppSettings;
begin
  if not Assigned(FSettingsManager) then
    Exit;

  settings := FSettingsManager.GetSettings;

  settings.Window.Maximized := (WindowState = TWindowState.wsMaximized);
  if not settings.Window.Maximized then
  begin
    settings.Window.Left := Round(Left);
    settings.Window.Top := Round(Top);
    settings.Window.Width := Round(ClientWidth);
    settings.Window.Height := Round(ClientHeight);
  end;

  FSettingsManager.SetSettings(settings);
end;

{ --- Меню --- }

procedure TMainForm.MenuSettingsClick(Sender: TObject);
var
  settingsForm: TSettingsForm;
  settings: TAppSettings;
begin
  settingsForm := TSettingsForm.Create(Self);
  try
    settings := FSettingsManager.GetSettings;
    settingsForm.SetSettings(settings);

    if settingsForm.ShowModal = mrOk then
    begin
      settings := settingsForm.GetSettings;
      FSettingsManager.SetSettings(settings);

      // Пересоздаём вкладки профилей
      RebuildProfileTabs;

      if Assigned(FLogManager) then
        FLogManager.LogInfo('Настройки сохранены');
    end;
  finally
    FreeAndNil(settingsForm);
  end;
end;

procedure TMainForm.MenuExitClick(Sender: TObject);
begin
  Close;
end;

procedure TMainForm.MenuStartClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FProfileTabs.Count - 1 do
  begin
    if Assigned(FProfileTabs[I].Scheduler) then
      FProfileTabs[I].Scheduler.Enabled := True;
  end;

  LabelStatus.Text := 'Запущен';
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Lime;
  BtnStart.Enabled := False;
  BtnStop.Enabled := True;
  MenuStart.Enabled := False;
  MenuStop.Enabled := True;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Робот запущен');
end;

procedure TMainForm.MenuStopClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to FProfileTabs.Count - 1 do
  begin
    if Assigned(FProfileTabs[I].Scheduler) then
      FProfileTabs[I].Scheduler.Enabled := False;
  end;

  LabelStatus.Text := 'Остановлен';
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Silver;
  BtnStart.Enabled := True;
  BtnStop.Enabled := False;
  MenuStart.Enabled := True;
  MenuStop.Enabled := False;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Робот остановлен');
end;

procedure TMainForm.MenuAboutClick(Sender: TObject);
begin
  TDialogService.MessageDialog(
    'Кормилец — торговый робот' + sLineBreak +
    'T-Invest API' + sLineBreak +
    'Версия 1.0',
    TMsgDlgType.mtInformation, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
end;

procedure TMainForm.TabControlProfilesChange(Sender: TObject);
begin
  // Можно обновить статусбар или другие элементы при переключении вкладки
end;

{ --- Создание/пересоздание вкладок профилей --- }

procedure TMainForm.DestroyAllProfileTabs;
var
  I: Integer;
begin
  if not Assigned(FProfileTabs) then
    Exit;

  // Сначала останавливаем все планировщики
  for I := 0 to FProfileTabs.Count - 1 do
  begin
    if Assigned(FProfileTabs[I].Scheduler) then
      FProfileTabs[I].Scheduler.Enabled := False;
  end;

  // Удаляем вкладки из TabControl
  TabControlProfiles.BeginUpdate;
  try
    while TabControlProfiles.TabCount > 0 do
      TabControlProfiles.Tabs[0].Free;
  finally
    TabControlProfiles.EndUpdate;
  end;

  // Очищаем список (TObjectList освободит объекты)
  FProfileTabs.Clear;
end;

procedure TMainForm.RebuildProfileTabs;
var
  settings: TAppSettings;
  I: Integer;
begin
  DestroyAllProfileTabs;

  settings := FSettingsManager.GetSettings;

  TabControlProfiles.BeginUpdate;
  try
    for I := 0 to High(settings.Profiles) do
      CreateProfileTab(I, settings.Profiles[I]);

    // Активируем сохранённую вкладку
    if (settings.ActiveProfileIndex >= 0) and
       (settings.ActiveProfileIndex < TabControlProfiles.TabCount) then
      TabControlProfiles.TabIndex := settings.ActiveProfileIndex
    else if TabControlProfiles.TabCount > 0 then
      TabControlProfiles.TabIndex := 0;
  finally
    TabControlProfiles.EndUpdate;
  end;
end;

procedure TMainForm.CreateProfileTab(const AProfileIndex: Integer;
  const AProfile: TConnectionProfile);
var
  profileTab: TProfileTab;
  ordersIniPath: string;
begin
  profileTab := TProfileTab.Create;
  profileTab.ProfileIndex := AProfileIndex;

  // Создаём TTabItem
  profileTab.TabItem := TTabItem.Create(TabControlProfiles);
  profileTab.TabItem.Text := AProfile.Name;
  profileTab.TabItem.Tag := AProfileIndex;
  TabControlProfiles.AddObject(profileTab.TabItem);

  // API-клиент
  profileTab.ApiClient := TApiClient.Create(FLogManager);
  profileTab.ApiClient.SetToken(AProfile.Token);
  ApplyProxyToClient(profileTab.ApiClient);

  // Менеджер ордеров (каждый профиль — свой файл)
  if AProfileIndex = 0 then
    ordersIniPath := 'orders.ini'
  else
    ordersIniPath := 'orders_' + AProfileIndex.ToString + '.ini';
  profileTab.OrderManager := TOrderManager.Create(ordersIniPath);

  // Планировщик
  profileTab.Scheduler := TTimerThread.Create('Scheduler_' + AProfileIndex.ToString);

  profileTab.PricePollTask := TTimerTask.Create(profileTab.Scheduler,
    5, AProfile.PollIntervalSec,
    procedure(const ATask: TAbstractTimerTask)
    begin
      PollPrices(profileTab);
    end);

  profileTab.OrderSyncTask := TTimerTask.Create(profileTab.Scheduler,
    10, AProfile.PollIntervalSec,
    procedure(const ATask: TAbstractTimerTask)
    begin
      SyncOrders(profileTab);
    end);

  profileTab.Scheduler.Enabled := False;

  // Создаём UI-компоненты программно
  BuildTabUI(profileTab);

  // Загружаем ордера в таблицу
  RefreshOrderGrid(profileTab);

  // Восстанавливаем AccountId в ComboAccounts
  if AProfile.AccountId <> '' then
  begin
    profileTab.ComboAccounts.Items.Clear;
    profileTab.ComboAccounts.Items.Add(AProfile.AccountId);
    profileTab.ComboAccounts.ItemIndex := 0;
  end;

  FProfileTabs.Add(profileTab);
end;

procedure TMainForm.ApplyProxyToClient(const AClient: TApiClient);
var
  settings: TAppSettings;
begin
  if not Assigned(FSettingsManager) or not Assigned(AClient) then
    Exit;

  settings := FSettingsManager.GetSettings;

  if settings.Proxy.Enabled then
    AClient.SetProxy(settings.Proxy.Host, settings.Proxy.Port,
      settings.Proxy.User, settings.Proxy.Pass)
  else
    AClient.SetProxy('', 0, '', '');
end;

{ --- Построение UI внутри вкладки --- }

procedure TMainForm.BuildTabUI(const ATab: TProfileTab);
var
  layoutCenter: TLayout;
  colStatus, colInstrument, colDirection, colQuantity,
  colTargetPrice, colCurrentPrice, colOrderType: TStringColumn;
begin
  // Верхняя панель: кнопка проверки + ComboAccounts
  ATab.LayoutTop := TLayout.Create(ATab.TabItem);
  ATab.LayoutTop.Parent := ATab.TabItem;
  ATab.LayoutTop.Align := TAlignLayout.Top;
  ATab.LayoutTop.Height := 40;

  ATab.BtnCheckConnection := TButton.Create(ATab.LayoutTop);
  ATab.BtnCheckConnection.Parent := ATab.LayoutTop;
  ATab.BtnCheckConnection.Text := 'Проверить подключение';
  ATab.BtnCheckConnection.Position.X := 8;
  ATab.BtnCheckConnection.Position.Y := 5;
  ATab.BtnCheckConnection.Width := 180;
  ATab.BtnCheckConnection.Height := 28;
  ATab.BtnCheckConnection.Tag := ATab.ProfileIndex;
  ATab.BtnCheckConnection.OnClick := OnBtnCheckConnectionClick;

  ATab.LabelAccount := TLabel.Create(ATab.LayoutTop);
  ATab.LabelAccount.Parent := ATab.LayoutTop;
  ATab.LabelAccount.Text := 'Счёт:';
  ATab.LabelAccount.Position.X := 200;
  ATab.LabelAccount.Position.Y := 8;
  ATab.LabelAccount.Width := 45;

  ATab.ComboAccounts := TComboBox.Create(ATab.LayoutTop);
  ATab.ComboAccounts.Parent := ATab.LayoutTop;
  ATab.ComboAccounts.Position.X := 250;
  ATab.ComboAccounts.Position.Y := 5;
  ATab.ComboAccounts.Width := 300;
  ATab.ComboAccounts.Height := 28;

  // Центральная часть: таблица ордеров
  layoutCenter := TLayout.Create(ATab.TabItem);
  layoutCenter.Parent := ATab.TabItem;
  layoutCenter.Align := TAlignLayout.Client;

  ATab.GroupBoxOrders := TGroupBox.Create(layoutCenter);
  ATab.GroupBoxOrders.Parent := layoutCenter;
  ATab.GroupBoxOrders.Align := TAlignLayout.Client;
  ATab.GroupBoxOrders.Margins.Left := 4;
  ATab.GroupBoxOrders.Margins.Top := 4;
  ATab.GroupBoxOrders.Margins.Right := 4;
  ATab.GroupBoxOrders.Margins.Bottom := 4;
  ATab.GroupBoxOrders.Text := 'Ордера';

  ATab.GridOrders := TStringGrid.Create(ATab.GroupBoxOrders);
  ATab.GridOrders.Parent := ATab.GroupBoxOrders;
  ATab.GridOrders.Align := TAlignLayout.Client;
  ATab.GridOrders.Margins.Left := 8;
  ATab.GridOrders.Margins.Top := 4;
  ATab.GridOrders.Margins.Right := 8;
  ATab.GridOrders.Margins.Bottom := 40;
  ATab.GridOrders.RowHeight := 24;
  ATab.GridOrders.Tag := ATab.ProfileIndex;
  ATab.GridOrders.OnCellDblClick := OnGridOrdersCellDblClick;

  // Колонки
  colStatus := TStringColumn.Create(ATab.GridOrders);
  colStatus.Parent := ATab.GridOrders;
  colStatus.Header := 'Статус';

  colInstrument := TStringColumn.Create(ATab.GridOrders);
  colInstrument.Parent := ATab.GridOrders;
  colInstrument.Header := 'Инструмент';
  colInstrument.Width := 140;

  colDirection := TStringColumn.Create(ATab.GridOrders);
  colDirection.Parent := ATab.GridOrders;
  colDirection.Header := 'Направление';

  colQuantity := TStringColumn.Create(ATab.GridOrders);
  colQuantity.Parent := ATab.GridOrders;
  colQuantity.Header := 'Кол-во';
  colQuantity.Width := 70;

  colTargetPrice := TStringColumn.Create(ATab.GridOrders);
  colTargetPrice.Parent := ATab.GridOrders;
  colTargetPrice.Header := 'Целевая цена';
  colTargetPrice.Width := 120;

  colCurrentPrice := TStringColumn.Create(ATab.GridOrders);
  colCurrentPrice.Parent := ATab.GridOrders;
  colCurrentPrice.Header := 'Текущая цена';
  colCurrentPrice.Width := 120;

  colOrderType := TStringColumn.Create(ATab.GridOrders);
  colOrderType.Parent := ATab.GridOrders;
  colOrderType.Header := 'Тип';
  colOrderType.Width := 110;

  // Кнопки ордеров
  ATab.LayoutOrderButtons := TLayout.Create(ATab.GroupBoxOrders);
  ATab.LayoutOrderButtons.Parent := ATab.GroupBoxOrders;
  ATab.LayoutOrderButtons.Align := TAlignLayout.Bottom;
  ATab.LayoutOrderButtons.Height := 36;

  ATab.BtnAddOrder := TButton.Create(ATab.LayoutOrderButtons);
  ATab.BtnAddOrder.Parent := ATab.LayoutOrderButtons;
  ATab.BtnAddOrder.Text := 'Добавить';
  ATab.BtnAddOrder.Position.X := 8;
  ATab.BtnAddOrder.Position.Y := 2;
  ATab.BtnAddOrder.Width := 100;
  ATab.BtnAddOrder.Height := 30;
  ATab.BtnAddOrder.Tag := ATab.ProfileIndex;
  ATab.BtnAddOrder.OnClick := OnBtnAddOrderClick;

  ATab.BtnDeleteOrder := TButton.Create(ATab.LayoutOrderButtons);
  ATab.BtnDeleteOrder.Parent := ATab.LayoutOrderButtons;
  ATab.BtnDeleteOrder.Text := 'Удалить';
  ATab.BtnDeleteOrder.Position.X := 116;
  ATab.BtnDeleteOrder.Position.Y := 2;
  ATab.BtnDeleteOrder.Width := 100;
  ATab.BtnDeleteOrder.Height := 30;
  ATab.BtnDeleteOrder.Tag := ATab.ProfileIndex;
  ATab.BtnDeleteOrder.OnClick := OnBtnDeleteOrderClick;

  ATab.BtnActivateOrder := TButton.Create(ATab.LayoutOrderButtons);
  ATab.BtnActivateOrder.Parent := ATab.LayoutOrderButtons;
  ATab.BtnActivateOrder.Text := 'Активировать';
  ATab.BtnActivateOrder.Position.X := 224;
  ATab.BtnActivateOrder.Position.Y := 2;
  ATab.BtnActivateOrder.Width := 120;
  ATab.BtnActivateOrder.Height := 30;
  ATab.BtnActivateOrder.Tag := ATab.ProfileIndex;
  ATab.BtnActivateOrder.OnClick := OnBtnActivateOrderClick;

  ATab.BtnCancelOrder := TButton.Create(ATab.LayoutOrderButtons);
  ATab.BtnCancelOrder.Parent := ATab.LayoutOrderButtons;
  ATab.BtnCancelOrder.Text := 'Отменить';
  ATab.BtnCancelOrder.Position.X := 352;
  ATab.BtnCancelOrder.Position.Y := 2;
  ATab.BtnCancelOrder.Width := 100;
  ATab.BtnCancelOrder.Height := 30;
  ATab.BtnCancelOrder.Tag := ATab.ProfileIndex;
  ATab.BtnCancelOrder.OnClick := OnBtnCancelOrderClick;
end;

{ --- Поиск TProfileTab по Sender --- }

function TMainForm.FindTabBySender(const ASender: TObject): TProfileTab;
var
  tagIndex, I: Integer;
begin
  Result := nil;
  if not Assigned(ASender) then
    Exit;

  tagIndex := (ASender as TControl).Tag;
  for I := 0 to FProfileTabs.Count - 1 do
  begin
    if FProfileTabs[I].ProfileIndex = tagIndex then
    begin
      Result := FProfileTabs[I];
      Exit;
    end;
  end;
end;

function TMainForm.GetActiveProfileTab: TProfileTab;
var
  I: Integer;
begin
  Result := nil;
  if not Assigned(FProfileTabs) or (TabControlProfiles.TabIndex < 0) then
    Exit;

  for I := 0 to FProfileTabs.Count - 1 do
  begin
    if FProfileTabs[I].ProfileIndex = TabControlProfiles.TabIndex then
    begin
      Result := FProfileTabs[I];
      Exit;
    end;
  end;
end;

{ --- Обработчики кнопок внутри вкладки --- }

procedure TMainForm.OnBtnCheckConnectionClick(Sender: TObject);
var
  profileTab: TProfileTab;
begin
  profileTab := FindTabBySender(Sender);
  if not Assigned(profileTab) or not Assigned(profileTab.ApiClient) then
    Exit;

  profileTab.BtnCheckConnection.Enabled := False;
  profileTab.BtnCheckConnection.Text := 'Проверка...';

  TMyTaskAutoFree('TMainForm.CheckConnection',
    procedure
    var
      response: string;
      statusCode: Integer;
      success: Boolean;
    begin
      success := False;
      response := '';
      statusCode := -1;

      if Assigned(profileTab.ApiClient) and not ProgramClosing then
        success := profileTab.ApiClient.GetAccounts(response, statusCode);

      TThread.Synchronize(nil,
        procedure
        var
          jsonObj: TJSONObject;
          accountsArr: TJSONArray;
          accountObj: TJSONObject;
          accountId, accountName, accountType: string;
          I: Integer;
        begin
          if ProgramClosing then
            Exit;

          profileTab.BtnCheckConnection.Enabled := True;
          profileTab.BtnCheckConnection.Text := 'Проверить подключение';

          if success and (statusCode = 200) then
          begin
            profileTab.ComboAccounts.Items.Clear;
            jsonObj := nil;
            try
              jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
              if Assigned(jsonObj) then
              begin
                accountsArr := jsonObj.GetValue<TJSONArray>('accounts');
                if Assigned(accountsArr) then
                begin
                  for I := 0 to accountsArr.Count - 1 do
                  begin
                    accountObj := accountsArr.Items[I] as TJSONObject;
                    accountId := accountObj.GetValue<string>('id');
                    accountName := accountObj.GetValue<string>('name');
                    accountType := accountObj.GetValue<string>('type');
                    profileTab.ComboAccounts.Items.Add(accountId + ' - ' +
                      accountName + ' (' + accountType + ')');
                  end;
                end;
              end;
            finally
              FreeAndNil(jsonObj);
            end;

            if profileTab.ComboAccounts.Items.Count > 0 then
              profileTab.ComboAccounts.ItemIndex := 0;

            if Assigned(FLogManager) then
              FLogManager.LogInfo('Подключение успешно, счетов: ' +
                profileTab.ComboAccounts.Items.Count.ToString);
          end
          else
          begin
            if statusCode = 401 then
              TDialogService.MessageDialog('Токен недействителен или отсутствует.',
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil)
            else if statusCode = -1 then
              TDialogService.MessageDialog('Нет связи с сервером. Проверьте настройки прокси.',
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil)
            else
              TDialogService.MessageDialog('Ошибка подключения. Код: ' + statusCode.ToString,
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
          end;
        end);
    end);
end;

procedure TMainForm.OnBtnAddOrderClick(Sender: TObject);
var
  profileTab: TProfileTab;
  orderForm: TOrderForm;
  newOrder: TOrderRecord;
begin
  profileTab := FindTabBySender(Sender);
  if not Assigned(profileTab) or not Assigned(profileTab.OrderManager) then
    Exit;

  orderForm := TOrderForm.Create(Self);
  try
    if orderForm.ShowModal = mrOk then
    begin
      newOrder := orderForm.GetOrder;
      newOrder.Status := osNew;
      profileTab.OrderManager.AddOrder(newOrder);
      RefreshOrderGrid(profileTab);

      if Assigned(FLogManager) then
        FLogManager.LogInfo('Ордер добавлен: ' + newOrder.InstrumentId);
    end;
  finally
    FreeAndNil(orderForm);
  end;
end;

procedure TMainForm.OnBtnDeleteOrderClick(Sender: TObject);
var
  profileTab: TProfileTab;
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
begin
  profileTab := FindTabBySender(Sender);
  if not Assigned(profileTab) or not Assigned(profileTab.OrderManager) then
    Exit;

  selectedRow := profileTab.GridOrders.Selected;
  if selectedRow < 0 then
  begin
    TDialogService.MessageDialog('Выберите ордер для удаления.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  orders := profileTab.OrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  TDialogService.MessageDialog('Удалить ордер "' + orders[selectedRow].InstrumentId + '"?',
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], TMsgDlgBtn.mbNo, 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
      begin
        if Assigned(profileTab.OrderManager) then
          profileTab.OrderManager.DeleteOrder(orders[selectedRow].Id);
        RefreshOrderGrid(profileTab);

        if Assigned(FLogManager) then
          FLogManager.LogInfo('Ордер удалён: ' + orders[selectedRow].InstrumentId);
      end;
    end);
end;

procedure TMainForm.OnBtnActivateOrderClick(Sender: TObject);
var
  profileTab: TProfileTab;
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
  order: TOrderRecord;
  settings: TAppSettings;
  profile: TConnectionProfile;
begin
  profileTab := FindTabBySender(Sender);
  if not Assigned(profileTab) or not Assigned(profileTab.OrderManager) or
     not Assigned(profileTab.ApiClient) then
    Exit;

  selectedRow := profileTab.GridOrders.Selected;
  if selectedRow < 0 then
  begin
    TDialogService.MessageDialog('Выберите ордер для активации.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  orders := profileTab.OrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  order := orders[selectedRow];

  // Получаем AccountId из профиля
  settings := FSettingsManager.GetSettings;
  if (profileTab.ProfileIndex >= 0) and
     (profileTab.ProfileIndex < Length(settings.Profiles)) then
    profile := settings.Profiles[profileTab.ProfileIndex]
  else
  begin
    TDialogService.MessageDialog('Профиль не найден.',
      TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  if profile.AccountId = '' then
  begin
    // Пробуем взять из ComboAccounts
    if profileTab.ComboAccounts.ItemIndex >= 0 then
    begin
      var
      selectedAccount := profileTab.ComboAccounts.Items[profileTab.ComboAccounts.ItemIndex];
      if Pos(' ', selectedAccount) > 0 then
        profile.AccountId := Copy(selectedAccount, 1, Pos(' ', selectedAccount) - 1)
      else
        profile.AccountId := selectedAccount;

      // Сохраняем AccountId в настройки
      settings.Profiles[profileTab.ProfileIndex].AccountId := profile.AccountId;
      FSettingsManager.SetSettings(settings);
    end
    else
    begin
      TDialogService.MessageDialog('Не выбран счёт. Проверьте подключение.',
        TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
      Exit;
    end;
  end;

  profileTab.OrderManager.UpdateStatus(order.Id, osPending);
  RefreshOrderGrid(profileTab);

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Активация ордера: ' + order.InstrumentId +
      ', направление = ' + DirectionToStr(order.Direction) +
      ', кол-во = ' + order.Quantity.ToString);

  TMyTaskAutoFree('TMainForm.ActivateOrder',
    procedure
    var
      response: string;
      statusCode: Integer;
      success: Boolean;
      jsonObj: TJSONObject;
      apiOrderId, apiStatus: string;
      mappedStatus: TOrderStatus;
      ErrorLine: Integer;
    begin
      ErrorLine := 0;
      try
        ErrorLine := 10;
        if ProgramClosing then
          Exit;

        ErrorLine := 20;
        success := profileTab.ApiClient.PostOrder(profile.AccountId,
          order.InstrumentId, order.Quantity, order.Direction,
          order.OrderType, order.TargetPrice, response, statusCode);

        ErrorLine := 30;
        if success and (statusCode = 200) then
        begin
          jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
          if Assigned(jsonObj) then
          try
            apiOrderId := jsonObj.GetValue<string>('orderId');
            apiStatus := jsonObj.GetValue<string>('executionReportStatus');
            mappedStatus := TOrderManager.MapApiStatus(apiStatus);
            profileTab.OrderManager.UpdateStatus(order.Id, mappedStatus, apiOrderId);

            if Assigned(FLogManager) then
              FLogManager.LogInfo(Format('Заявка выставлена: orderId = %s, статус = %s',
                [apiOrderId, apiStatus]));
          finally
            FreeAndNil(jsonObj);
          end;
        end
        else
        begin
          ErrorLine := 40;
          profileTab.OrderManager.UpdateStatus(order.Id, osRejected);

          if Assigned(FLogManager) then
            FLogManager.LogError(Format('Ошибка выставления заявки: status = %d, response = %s',
              [statusCode, response]));
        end;

        ErrorLine := 50;
        if not ProgramClosing then
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              if not ProgramClosing then
                RefreshOrderGrid(profileTab);
            end);
        end;
      except
        on E: Exception do
        begin
          if Assigned(FLogManager) then
            FLogManager.LogError(Format('ActivateOrder ошибка в строке %d: %s',
              [ErrorLine, E.Message]));
        end;
      end;
    end);
end;

procedure TMainForm.OnBtnCancelOrderClick(Sender: TObject);
var
  profileTab: TProfileTab;
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
  order: TOrderRecord;
  settings: TAppSettings;
  accountId: string;
begin
  profileTab := FindTabBySender(Sender);
  if not Assigned(profileTab) or not Assigned(profileTab.OrderManager) or
     not Assigned(profileTab.ApiClient) then
    Exit;

  selectedRow := profileTab.GridOrders.Selected;
  if selectedRow < 0 then
  begin
    TDialogService.MessageDialog('Выберите ордер для отмены.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  orders := profileTab.OrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  order := orders[selectedRow];

  if order.ExchangeOrderId = '' then
  begin
    TDialogService.MessageDialog('Ордер не был выставлен на бирже. Нечего отменять.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  settings := FSettingsManager.GetSettings;
  if (profileTab.ProfileIndex >= 0) and
     (profileTab.ProfileIndex < Length(settings.Profiles)) then
    accountId := settings.Profiles[profileTab.ProfileIndex].AccountId
  else
    accountId := '';

  if accountId = '' then
  begin
    TDialogService.MessageDialog('Не выбран счёт. Проверьте подключение.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
    Exit;
  end;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Отмена заявки: orderId = ' + order.ExchangeOrderId);

  TMyTaskAutoFree('TMainForm.CancelOrder',
    procedure
    var
      response: string;
      statusCode: Integer;
      success: Boolean;
      ErrorLine: Integer;
    begin
      ErrorLine := 0;
      try
        ErrorLine := 10;
        if ProgramClosing then
          Exit;

        ErrorLine := 20;
        success := profileTab.ApiClient.CancelOrder(accountId,
          order.ExchangeOrderId, response, statusCode);

        ErrorLine := 30;
        if success and (statusCode = 200) then
        begin
          profileTab.OrderManager.UpdateStatus(order.Id, osCancelled);

          if Assigned(FLogManager) then
            FLogManager.LogInfo('Заявка отменена: orderId = ' + order.ExchangeOrderId);
        end
        else
        begin
          ErrorLine := 40;
          if Assigned(FLogManager) then
            FLogManager.LogError(Format('Ошибка отмены заявки: status = %d, response = %s',
              [statusCode, response]));

          if not ProgramClosing then
          begin
            TThread.Synchronize(nil,
              procedure
              begin
                if not ProgramClosing then
                  TDialogService.MessageDialog('Ошибка отмены заявки. Код: ' + statusCode.ToString,
                    TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], TMsgDlgBtn.mbOK, 0, nil);
              end);
          end;
        end;

        ErrorLine := 50;
        if not ProgramClosing then
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              if not ProgramClosing then
                RefreshOrderGrid(profileTab);
            end);
        end;
      except
        on E: Exception do
        begin
          if Assigned(FLogManager) then
            FLogManager.LogError(Format('CancelOrder ошибка в строке %d: %s',
              [ErrorLine, E.Message]));
        end;
      end;
    end);
end;

procedure TMainForm.OnGridOrdersCellDblClick(const AColumn: TColumn; const ARow: Integer);
var
  profileTab: TProfileTab;
  orders: TArray<TOrderRecord>;
  orderForm: TOrderForm;
  editedOrder: TOrderRecord;
begin
  profileTab := GetActiveProfileTab;
  if not Assigned(profileTab) or not Assigned(profileTab.OrderManager) then
    Exit;

  orders := profileTab.OrderManager.GetAllOrders;
  if (ARow < 0) or (ARow > High(orders)) then
    Exit;

  orderForm := TOrderForm.Create(Self);
  try
    orderForm.SetOrder(orders[ARow]);

    if orderForm.ShowModal = mrOk then
    begin
      editedOrder := orderForm.GetOrder;
      profileTab.OrderManager.UpdateOrder(editedOrder);
      RefreshOrderGrid(profileTab);

      if Assigned(FLogManager) then
        FLogManager.LogInfo('Ордер обновлён: ' + editedOrder.InstrumentId);
    end;
  finally
    FreeAndNil(orderForm);
  end;
end;

{ --- Обновление таблицы ордеров --- }

procedure TMainForm.RefreshOrderGrid(const ATab: TProfileTab);
var
  orders: TArray<TOrderRecord>;
  I: Integer;
begin
  if not Assigned(ATab) or not Assigned(ATab.OrderManager) or
     not Assigned(ATab.GridOrders) then
    Exit;

  orders := ATab.OrderManager.GetAllOrders;

  ATab.GridOrders.RowCount := Length(orders);

  for I := 0 to High(orders) do
  begin
    ATab.GridOrders.Cells[0, I] := StatusToStr(orders[I].Status);
    ATab.GridOrders.Cells[1, I] := orders[I].Ticker;
    if orders[I].Ticker = '' then
      ATab.GridOrders.Cells[1, I] := orders[I].InstrumentId;
    ATab.GridOrders.Cells[2, I] := DirectionToStr(orders[I].Direction);
    ATab.GridOrders.Cells[3, I] := orders[I].Quantity.ToString;
    ATab.GridOrders.Cells[4, I] := FormatPrice(orders[I].TargetPrice);
    ATab.GridOrders.Cells[5, I] := FormatPrice(orders[I].CurrentPrice);
    ATab.GridOrders.Cells[6, I] := OrderTypeToStr(orders[I].OrderType);
  end;
end;

{ --- Панель лога --- }

procedure TMainForm.OnLogEntry(const AEntry: TLogEntry);
begin
  TThread.Synchronize(nil,
    procedure
    var
      logLine: string;
    begin
      if ProgramClosing then
        Exit;

      if not Assigned(MemoLog) then
        Exit;

      logLine := FormatDateTime('[hh:nn:ss]', AEntry.Timestamp) +
        ' [' + AEntry.Level + '] ' + AEntry.Message;

      MemoLog.Lines.Add(logLine);

      while MemoLog.Lines.Count > MAX_LOG_LINES do
        MemoLog.Lines.Delete(0);

      MemoLog.GoToTextEnd;
    end);
end;

{ --- Фоновые задачи планировщика --- }

procedure TMainForm.PollPrices(const ATab: TProfileTab);
var
  orders: TArray<TOrderRecord>;
  uniqueIds: TArray<string>;
  response: string;
  statusCode: Integer;
  jsonObj: TJSONObject;
  pricesArr: TJSONArray;
  priceItem: TJSONObject;
  priceObj: TJSONObject;
  instrumentUid: string;
  quotation: TQuotation;
  priceDouble: Double;
  I, J: Integer;
  found: Boolean;
  ErrorLine: Integer;
begin
  ErrorLine := 0;
  try
    ErrorLine := 10;
    if ProgramClosing then
      Exit;
    if not Assigned(ATab) or not Assigned(ATab.OrderManager) or
       not Assigned(ATab.ApiClient) then
      Exit;

    ErrorLine := 20;
    orders := ATab.OrderManager.GetAllOrders;
    if Length(orders) = 0 then
      Exit;

    ErrorLine := 30;
    SetLength(uniqueIds, 0);
    for I := 0 to High(orders) do
    begin
      if orders[I].InstrumentId = '' then
        Continue;
      found := False;
      for J := 0 to High(uniqueIds) do
      begin
        if uniqueIds[J] = orders[I].InstrumentId then
        begin
          found := True;
          Break;
        end;
      end;
      if not found then
      begin
        SetLength(uniqueIds, Length(uniqueIds) + 1);
        uniqueIds[High(uniqueIds)] := orders[I].InstrumentId;
      end;
    end;

    if Length(uniqueIds) = 0 then
      Exit;

    ErrorLine := 40;
    if not ATab.ApiClient.GetLastPrices(uniqueIds, response, statusCode) then
      Exit;

    if statusCode <> 200 then
      Exit;

    ErrorLine := 50;
    jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
    if not Assigned(jsonObj) then
      Exit;
    try
      ErrorLine := 60;
      pricesArr := jsonObj.GetValue<TJSONArray>('lastPrices');
      if not Assigned(pricesArr) then
        Exit;

      ErrorLine := 70;
      for I := 0 to pricesArr.Count - 1 do
      begin
        if ProgramClosing then
          Exit;

        priceItem := pricesArr.Items[I] as TJSONObject;
        instrumentUid := priceItem.GetValue<string>('instrumentUid');

        priceObj := priceItem.GetValue<TJSONObject>('price');
        if Assigned(priceObj) then
        begin
          quotation := TQuotationHelper.FromJson(priceObj);
          priceDouble := TQuotationHelper.ToDouble(quotation);
          ATab.OrderManager.UpdatePrice(instrumentUid, priceDouble);
        end;
      end;
    finally
      FreeAndNil(jsonObj);
    end;

    ErrorLine := 80;
    if not ProgramClosing then
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          if not ProgramClosing then
            RefreshOrderGrid(ATab);
        end);
    end;
  except
    on E: Exception do
    begin
      if Assigned(FLogManager) then
        FLogManager.LogError(Format('PollPrices ошибка в строке %d: %s',
          [ErrorLine, E.Message]));
    end;
  end;
end;

procedure TMainForm.SyncOrders(const ATab: TProfileTab);
var
  settings: TAppSettings;
  accountId: string;
  response: string;
  statusCode: Integer;
  jsonObj: TJSONObject;
  ordersArr: TJSONArray;
  apiOrderObj: TJSONObject;
  apiOrderId, apiStatus: string;
  localOrders: TArray<TOrderRecord>;
  mappedStatus: TOrderStatus;
  I, J: Integer;
  ErrorLine: Integer;
begin
  ErrorLine := 0;
  try
    ErrorLine := 10;
    if ProgramClosing then
      Exit;
    if not Assigned(ATab) or not Assigned(ATab.ApiClient) or
       not Assigned(ATab.OrderManager) or not Assigned(FSettingsManager) then
      Exit;

    ErrorLine := 20;
    settings := FSettingsManager.GetSettings;
    if (ATab.ProfileIndex < 0) or (ATab.ProfileIndex >= Length(settings.Profiles)) then
      Exit;
    accountId := settings.Profiles[ATab.ProfileIndex].AccountId;
    if accountId = '' then
      Exit;

    ErrorLine := 30;
    if not ATab.ApiClient.GetOrders(accountId, response, statusCode) then
      Exit;

    if statusCode <> 200 then
      Exit;

    ErrorLine := 40;
    jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
    if not Assigned(jsonObj) then
      Exit;
    try
      ErrorLine := 50;
      ordersArr := jsonObj.GetValue<TJSONArray>('orders');
      if not Assigned(ordersArr) then
        Exit;

      ErrorLine := 60;
      localOrders := ATab.OrderManager.GetAllOrders;

      ErrorLine := 70;
      for I := 0 to ordersArr.Count - 1 do
      begin
        if ProgramClosing then
          Exit;

        apiOrderObj := ordersArr.Items[I] as TJSONObject;
        apiOrderId := apiOrderObj.GetValue<string>('orderId');
        apiStatus := apiOrderObj.GetValue<string>('executionReportStatus');

        mappedStatus := TOrderManager.MapApiStatus(apiStatus);

        for J := 0 to High(localOrders) do
        begin
          if localOrders[J].ExchangeOrderId = apiOrderId then
          begin
            ATab.OrderManager.UpdateStatus(localOrders[J].Id, mappedStatus);
            Break;
          end;
        end;
      end;
    finally
      FreeAndNil(jsonObj);
    end;

    ErrorLine := 80;
    if not ProgramClosing then
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          if not ProgramClosing then
            RefreshOrderGrid(ATab);
        end);
    end;
  except
    on E: Exception do
    begin
      if Assigned(FLogManager) then
        FLogManager.LogError(Format('SyncOrders ошибка в строке %d: %s',
          [ErrorLine, E.Message]));
    end;
  end;
end;

{ --- Вспомогательные функции --- }

class function TMainForm.StatusToStr(const AStatus: TOrderStatus): string;
begin
  Result := STATUS_STRINGS[AStatus];
end;

class function TMainForm.DirectionToStr(const ADirection: TOrderDirection): string;
begin
  Result := DIRECTION_STRINGS[ADirection];
end;

class function TMainForm.OrderTypeToStr(const AOrderType: TOrderType): string;
begin
  Result := ORDER_TYPE_STRINGS[AOrderType];
end;

class function TMainForm.FormatPrice(const APrice: Double): string;
begin
  if APrice = 0 then
    Result := '-'
  else
    Result := FormatFloat('0.00', APrice);
end;

end.
