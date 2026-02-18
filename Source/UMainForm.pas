{
  Главная форма приложения "Кормилец" (торговый робот).
  Содержит панель настроек подключения, таблицу ордеров, панель лога
  и кнопки управления роботом (Старт/Стоп).

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
  System.JSON, System.DateUtils,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs,
  FMX.StdCtrls, FMX.Edit, FMX.ListBox, FMX.Layouts, FMX.Memo,
  FMX.Controls.Presentation, FMX.EditBox, FMX.SpinBox, FMX.Grid,
  FMX.Grid.Style, FMX.ScrollBox,
  // Core-модули проекта
  MyFlag, MyTask, MyThread,
  // Модули приложения
  ULogManager, USettingsManager, UOrderManager, UApiClient, UQuotationHelper,
  FMX.Memo.Types, System.Rtti;

type
  TMainForm = class(TForm)
    { Панель настроек (верх) }
    PanelTop: TLayout;
    GroupBoxSettings: TGroupBox;
    LabelToken: TLabel;
    EditToken: TEdit;
    BtnShowToken: TButton;
    LabelProxyHost: TLabel;
    EditProxyHost: TEdit;
    LabelProxyPort: TLabel;
    SpinProxyPort: TSpinBox;
    LabelProxyUser: TLabel;
    EditProxyUser: TEdit;
    LabelProxyPass: TLabel;
    EditProxyPass: TEdit;
    BtnCheckConnection: TButton;
    LabelAccount: TLabel;
    ComboAccounts: TComboBox;
    LabelPollInterval: TLabel;
    SpinPollInterval: TSpinBox;
    BtnSaveSettings: TButton;

    { Таблица ордеров (центр) }
    PanelCenter: TLayout;
    GroupBoxOrders: TGroupBox;
    GridOrders: TStringGrid;
    ColStatus: TStringColumn;
    ColInstrument: TStringColumn;
    ColDirection: TStringColumn;
    ColQuantity: TStringColumn;
    ColTargetPrice: TStringColumn;
    ColCurrentPrice: TStringColumn;
    ColOrderType: TStringColumn;
    LayoutOrderButtons: TLayout;
    BtnAddOrder: TButton;
    BtnDeleteOrder: TButton;
    BtnActivateOrder: TButton;
    BtnCancelOrder: TButton;

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

    { Обработчики кнопок настроек }
    procedure BtnShowTokenClick(Sender: TObject);
    procedure BtnCheckConnectionClick(Sender: TObject);
    procedure BtnSaveSettingsClick(Sender: TObject);

    { Обработчики кнопок ордеров }
    procedure BtnAddOrderClick(Sender: TObject);
    procedure BtnDeleteOrderClick(Sender: TObject);
    procedure BtnActivateOrderClick(Sender: TObject);
    procedure BtnCancelOrderClick(Sender: TObject);
    procedure GridOrdersCellDblClick(const AColumn: TColumn; const ARow: Integer);

    { Обработчики кнопок Старт/Стоп }
    procedure BtnStartClick(Sender: TObject);
    procedure BtnStopClick(Sender: TObject);
  private
    FLogManager: TLogManager;
    FSettingsManager: TSettingsManager;
    FOrderManager: TOrderManager;
    FApiClient: TApiClient;
    FScheduler: TTimerThread;
    FPricePollTask: TTimerTask;
    FOrderSyncTask: TTimerTask;

    { Загрузка/применение настроек }
    procedure LoadSettingsToUI;
    procedure ApplySettingsToApiClient;

    { Фоновые задачи планировщика }
    procedure PollPrices;
    procedure SyncOrders;

    { Обновление таблицы ордеров }
    procedure RefreshOrderGrid;

    { Callback для TLogManager.OnLogEntry }
    procedure OnLogEntry(const AEntry: TLogEntry);

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
  UOrderForm;


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

  // Максимум строк в MemoLog (чтобы не переполнять память)
  MAX_LOG_LINES = 500;

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
var
  settings: TAppSettings;
begin
  // 1. Создаём менеджер лога
  FLogManager := TLogManager.Create(500);

  // 1.1. Регистрируем глобальный экземпляр для Core-модулей
  TLogManager.Instance := FLogManager;

  // 2. Создаём менеджер настроек
  FSettingsManager := TSettingsManager.Create('settings.ini');

  // 3. Создаём менеджер ордеров
  FOrderManager := TOrderManager.Create('orders.ini');

  // 4. Создаём API-клиент
  FApiClient := TApiClient.Create(FLogManager);

  // 5. Загружаем настройки и применяем к API-клиенту
  settings := FSettingsManager.GetSettings;
  LoadSettingsToUI;
  ApplySettingsToApiClient;

  // 6. Загружаем ордера в таблицу
  RefreshOrderGrid;

  // 7. Подписываемся на события лога
  FLogManager.OnLogEntry := OnLogEntry;

  // 8. Сбрасываем флаг загрузки — инициализация завершена
  ProgramLoading := False;

  // 9. Создаём планировщик (TTimerThread)
  settings := FSettingsManager.GetSettings;

  FScheduler := TTimerThread.Create('MainScheduler');

  // Задача опроса цен (начальная задержка 5 сек, повтор каждые PollIntervalSec сек)
  FPricePollTask := TTimerTask.Create(FScheduler, 5, settings.PollIntervalSec,
    procedure(const ATask: TAbstractTimerTask)
    begin
      PollPrices;
    end);

  // Задача синхронизации заявок (начальная задержка 10 сек, повтор каждые PollIntervalSec сек)
  FOrderSyncTask := TTimerTask.Create(FScheduler, 10, settings.PollIntervalSec,
    procedure(const ATask: TAbstractTimerTask)
    begin
      SyncOrders;
    end);

  // Планировщик создан, но не запущен — пользователь нажмёт "Старт"
  FScheduler.Enabled := False;

  FLogManager.LogInfo('Приложение запущено');
end;

procedure TMainForm.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // 1. Устанавливаем флаг закрытия для фоновых потоков
  ProgramClosing := True;

  // 2. Останавливаем и освобождаем планировщик
  if Assigned(FScheduler) then
  begin
    FScheduler.Enabled := False;
    TMyThread.TerminateAndFree<TTimerThread>(FScheduler);
  end;
  // FPricePollTask и FOrderSyncTask освобождаются планировщиком (OwnerFree = True)

  // 3. Отписываемся от событий лога и убираем глобальный экземпляр
  TLogManager.Instance := nil;
  if Assigned(FLogManager) then
    FLogManager.OnLogEntry := nil;

  // 4. Освобождаем в обратном порядке создания
  FreeAndNil(FApiClient);
  FreeAndNil(FOrderManager);
  FreeAndNil(FSettingsManager);
  FreeAndNil(FLogManager);
end;

{ --- Настройки подключения --- }

procedure TMainForm.LoadSettingsToUI;
var
  settings: TAppSettings;
begin
  if not Assigned(FSettingsManager) then
    Exit;

  settings := FSettingsManager.GetSettings;

  EditToken.Text := settings.Token;
  EditProxyHost.Text := settings.ProxyHost;
  SpinProxyPort.Value := settings.ProxyPort;
  EditProxyUser.Text := settings.ProxyUser;
  EditProxyPass.Text := settings.ProxyPass;
  SpinPollInterval.Value := settings.PollIntervalSec;

  // Если есть сохранённый AccountId, пытаемся выбрать его в ComboBox
  if settings.AccountId <> '' then
  begin
    ComboAccounts.Items.Clear;
    ComboAccounts.Items.Add(settings.AccountId);
    ComboAccounts.ItemIndex := 0;
  end;
end;

procedure TMainForm.ApplySettingsToApiClient;
var
  settings: TAppSettings;
begin
  if not Assigned(FApiClient) or not Assigned(FSettingsManager) then
    Exit;

  settings := FSettingsManager.GetSettings;
  FApiClient.SetToken(settings.Token);
  FApiClient.SetProxy(settings.ProxyHost, settings.ProxyPort,
    settings.ProxyUser, settings.ProxyPass);
end;

procedure TMainForm.BtnShowTokenClick(Sender: TObject);
begin
  // Переключаем видимость токена (Req 1.4)
  EditToken.Password := not EditToken.Password;

  if EditToken.Password then
    BtnShowToken.Text := 'Показать токен'
  else
    BtnShowToken.Text := 'Скрыть токен';
end;

procedure TMainForm.BtnCheckConnectionClick(Sender: TObject);
begin
  // Применяем текущие настройки из UI перед проверкой
  if Assigned(FApiClient) then
  begin
    FApiClient.SetToken(EditToken.Text);
    FApiClient.SetProxy(EditProxyHost.Text, Trunc(SpinProxyPort.Value),
      EditProxyUser.Text, EditProxyPass.Text);
  end;

  BtnCheckConnection.Enabled := False;
  BtnCheckConnection.Text := 'Проверка...';

  // Запускаем проверку подключения в фоновом потоке (Req 2.1)
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

      if Assigned(FApiClient) and not ProgramClosing then
        success := FApiClient.GetAccounts(response, statusCode);

      // Обновляем GUI через Synchronize
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

          BtnCheckConnection.Enabled := True;
          BtnCheckConnection.Text := 'Проверить подключение';

          if success and (statusCode = 200) then
          begin
            // Парсим список счетов (Req 2.2)
            ComboAccounts.Items.Clear;
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
                    ComboAccounts.Items.Add(accountId + ' - ' + accountName +
                      ' (' + accountType + ')');
                  end;
                end;
              end;
            finally
              FreeAndNil(jsonObj);
            end;

            if ComboAccounts.Items.Count > 0 then
              ComboAccounts.ItemIndex := 0;

            if Assigned(FLogManager) then
              FLogManager.LogInfo('Подключение успешно, счетов: ' +
                ComboAccounts.Items.Count.ToString);
          end
          else
          begin
            // Обработка ошибок (Req 2.3, 2.4)
            if statusCode = 401 then
              MessageDlg('Токен недействителен или отсутствует.',
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0)
            else if statusCode = -1 then
              MessageDlg('Нет связи с сервером. Проверьте настройки прокси.',
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0)
            else
              MessageDlg('Ошибка подключения. Код: ' + statusCode.ToString,
                TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
          end;
        end);
    end);
end;

procedure TMainForm.BtnSaveSettingsClick(Sender: TObject);
var
  settings: TAppSettings;
  selectedAccount: string;
begin
  // Считываем настройки из UI
  settings.Token := EditToken.Text;
  settings.ProxyHost := EditProxyHost.Text;
  settings.ProxyPort := Trunc(SpinProxyPort.Value);
  settings.ProxyUser := EditProxyUser.Text;
  settings.ProxyPass := EditProxyPass.Text;
  settings.PollIntervalSec := Trunc(SpinPollInterval.Value);

  // Извлекаем AccountId из выбранного элемента ComboBox
  if ComboAccounts.ItemIndex >= 0 then
  begin
    selectedAccount := ComboAccounts.Items[ComboAccounts.ItemIndex];
    // Формат: "ID - Name (Type)", извлекаем ID до первого пробела
    if Pos(' ', selectedAccount) > 0 then
      settings.AccountId := Copy(selectedAccount, 1, Pos(' ', selectedAccount) - 1)
    else
      settings.AccountId := selectedAccount;
  end
  else
    settings.AccountId := '';

  // Сохраняем через менеджер настроек
  if Assigned(FSettingsManager) then
    FSettingsManager.SetSettings(settings);

  // Применяем к API-клиенту без перезапуска (Req 1.5)
  ApplySettingsToApiClient;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Настройки сохранены');
end;


{ --- Таблица ордеров --- }

procedure TMainForm.RefreshOrderGrid;
var
  orders: TArray<TOrderRecord>;
  I: Integer;
begin
  if not Assigned(FOrderManager) then
    Exit;

  orders := FOrderManager.GetAllOrders;

  GridOrders.RowCount := Length(orders);

  for I := 0 to High(orders) do
  begin
    GridOrders.Cells[0, I] := StatusToStr(orders[I].Status);
    GridOrders.Cells[1, I] := orders[I].Ticker;
    if orders[I].Ticker = '' then
      GridOrders.Cells[1, I] := orders[I].InstrumentId;
    GridOrders.Cells[2, I] := DirectionToStr(orders[I].Direction);
    GridOrders.Cells[3, I] := orders[I].Quantity.ToString;
    GridOrders.Cells[4, I] := FormatPrice(orders[I].TargetPrice);
    GridOrders.Cells[5, I] := FormatPrice(orders[I].CurrentPrice);
    GridOrders.Cells[6, I] := OrderTypeToStr(orders[I].OrderType);
  end;
end;

procedure TMainForm.BtnAddOrderClick(Sender: TObject);
var
  orderForm: TOrderForm;
  newOrder: TOrderRecord;
begin
  // Открываем форму создания ордера (Req 3.2)
  orderForm := TOrderForm.Create(Self);
  try
    if orderForm.ShowModal = mrOk then
    begin
      newOrder := orderForm.GetOrder;
      newOrder.Status := osNew;

      if Assigned(FOrderManager) then
        FOrderManager.AddOrder(newOrder);

      RefreshOrderGrid;

      if Assigned(FLogManager) then
        FLogManager.LogInfo('Ордер добавлен: ' + newOrder.InstrumentId);
    end;
  finally
    FreeAndNil(orderForm);
  end;
end;

procedure TMainForm.BtnDeleteOrderClick(Sender: TObject);
var
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
begin
  selectedRow := GridOrders.Selected;
  if selectedRow < 0 then
  begin
    MessageDlg('Выберите ордер для удаления.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  if not Assigned(FOrderManager) then
    Exit;

  orders := FOrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  // Подтверждение удаления (Req 3.4)
  MessageDlg('Удалить ордер "' + orders[selectedRow].InstrumentId + '"?',
    TMsgDlgType.mtConfirmation, [TMsgDlgBtn.mbYes, TMsgDlgBtn.mbNo], 0,
    procedure(const AResult: TModalResult)
    begin
      if AResult = mrYes then
      begin
        if Assigned(FOrderManager) then
          FOrderManager.DeleteOrder(orders[selectedRow].Id);

        RefreshOrderGrid;

        if Assigned(FLogManager) then
          FLogManager.LogInfo('Ордер удалён: ' + orders[selectedRow].InstrumentId);
      end;
    end);
end;

procedure TMainForm.BtnActivateOrderClick(Sender: TObject);
var
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
  order: TOrderRecord;
  settings: TAppSettings;
begin
  selectedRow := GridOrders.Selected;
  if selectedRow < 0 then
  begin
    MessageDlg('Выберите ордер для активации.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  if not Assigned(FOrderManager) or not Assigned(FApiClient) or
     not Assigned(FSettingsManager) then
    Exit;

  orders := FOrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  order := orders[selectedRow];
  settings := FSettingsManager.GetSettings;

  if settings.AccountId = '' then
  begin
    MessageDlg('Не выбран счёт. Сохраните настройки подключения.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  // Обновляем статус на "Ожидает" перед отправкой
  FOrderManager.UpdateStatus(order.Id, osPending);
  RefreshOrderGrid;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Активация ордера: ' + order.InstrumentId +
      ', направление = ' + DirectionToStr(order.Direction) +
      ', кол-во = ' + order.Quantity.ToString);

  // Запускаем отправку заявки в фоновом потоке
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
        success := FApiClient.PostOrder(settings.AccountId, order.InstrumentId,
          order.Quantity, order.Direction, order.OrderType, order.TargetPrice,
          response, statusCode);

        ErrorLine := 30;
        if success and (statusCode = 200) then
        begin
          // Парсим ответ для получения orderId и статуса
          jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
          if Assigned(jsonObj) then
          try
            apiOrderId := jsonObj.GetValue<string>('orderId');
            apiStatus := jsonObj.GetValue<string>('executionReportStatus');
            mappedStatus := TOrderManager.MapApiStatus(apiStatus);

            FOrderManager.UpdateStatus(order.Id, mappedStatus, apiOrderId);

            if Assigned(FLogManager) then
              FLogManager.LogInfo(Format('Заявка выставлена: orderId = %s, статус = %s',
                [apiOrderId, apiStatus]));
          finally
            FreeAndNil(jsonObj);
          end;
        end
        else
        begin
          // Ошибка — возвращаем статус "Отклонён"
          ErrorLine := 40;
          FOrderManager.UpdateStatus(order.Id, osRejected);

          if Assigned(FLogManager) then
            FLogManager.LogError(Format('Ошибка выставления заявки: status = %d, response = %s',
              [statusCode, response]));
        end;

        // Обновляем GUI
        ErrorLine := 50;
        if not ProgramClosing then
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              if not ProgramClosing then
                RefreshOrderGrid;
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

procedure TMainForm.BtnCancelOrderClick(Sender: TObject);
var
  selectedRow: Integer;
  orders: TArray<TOrderRecord>;
  order: TOrderRecord;
  settings: TAppSettings;
begin
  selectedRow := GridOrders.Selected;
  if selectedRow < 0 then
  begin
    MessageDlg('Выберите ордер для отмены.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  if not Assigned(FOrderManager) or not Assigned(FApiClient) or
     not Assigned(FSettingsManager) then
    Exit;

  orders := FOrderManager.GetAllOrders;
  if selectedRow > High(orders) then
    Exit;

  order := orders[selectedRow];

  // Проверяем, что у ордера есть биржевой ID (заявка была выставлена)
  if order.ExchangeOrderId = '' then
  begin
    MessageDlg('Ордер не был выставлен на бирже. Нечего отменять.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  settings := FSettingsManager.GetSettings;

  if settings.AccountId = '' then
  begin
    MessageDlg('Не выбран счёт. Сохраните настройки подключения.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    Exit;
  end;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Отмена заявки: orderId = ' + order.ExchangeOrderId);

  // Запускаем отмену заявки в фоновом потоке
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
        success := FApiClient.CancelOrder(settings.AccountId,
          order.ExchangeOrderId, response, statusCode);

        ErrorLine := 30;
        if success and (statusCode = 200) then
        begin
          FOrderManager.UpdateStatus(order.Id, osCancelled);

          if Assigned(FLogManager) then
            FLogManager.LogInfo('Заявка отменена: orderId = ' + order.ExchangeOrderId);
        end
        else
        begin
          // Ошибка отмены — логируем, статус не меняем (Req 7.3)
          ErrorLine := 40;
          if Assigned(FLogManager) then
            FLogManager.LogError(Format('Ошибка отмены заявки: status = %d, response = %s',
              [statusCode, response]));

          // Показываем ошибку пользователю
          if not ProgramClosing then
          begin
            TThread.Synchronize(nil,
              procedure
              begin
                if not ProgramClosing then
                  MessageDlg('Ошибка отмены заявки. Код: ' + statusCode.ToString,
                    TMsgDlgType.mtError, [TMsgDlgBtn.mbOK], 0);
              end);
          end;
        end;

        // Обновляем GUI
        ErrorLine := 50;
        if not ProgramClosing then
        begin
          TThread.Synchronize(nil,
            procedure
            begin
              if not ProgramClosing then
                RefreshOrderGrid;
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

procedure TMainForm.GridOrdersCellDblClick(const AColumn: TColumn; const ARow: Integer);
var
  orders: TArray<TOrderRecord>;
  orderForm: TOrderForm;
  editedOrder: TOrderRecord;
begin
  if not Assigned(FOrderManager) then
    Exit;

  orders := FOrderManager.GetAllOrders;
  if (ARow < 0) or (ARow > High(orders)) then
    Exit;

  // Открываем форму редактирования ордера (Req 3.3)
  orderForm := TOrderForm.Create(Self);
  try
    orderForm.SetOrder(orders[ARow]);

    if orderForm.ShowModal = mrOk then
    begin
      editedOrder := orderForm.GetOrder;
      FOrderManager.UpdateOrder(editedOrder);
      RefreshOrderGrid;

      if Assigned(FLogManager) then
        FLogManager.LogInfo('Ордер обновлён: ' + editedOrder.InstrumentId);
    end;
  finally
    FreeAndNil(orderForm);
  end;
end;

{ --- Панель лога и Старт/Стоп --- }

procedure TMainForm.OnLogEntry(const AEntry: TLogEntry);
begin
  // Обновляем MemoLog через Synchronize (Req 10.3)
  TThread.Synchronize(nil,
    procedure
    var
      logLine: string;
    begin
      if ProgramClosing then
        Exit;

      if not Assigned(MemoLog) then
        Exit;

      // Формат: [HH:NN:SS] [LEVEL] Message
      logLine := FormatDateTime('[hh:nn:ss]', AEntry.Timestamp) +
        ' [' + AEntry.Level + '] ' + AEntry.Message;

      MemoLog.Lines.Add(logLine);

      // Ограничиваем размер лога в интерфейсе (Req 10.4)
      while MemoLog.Lines.Count > MAX_LOG_LINES do
        MemoLog.Lines.Delete(0);

      // Прокручиваем к последней строке
      MemoLog.GoToTextEnd;
    end);
end;

procedure TMainForm.BtnStartClick(Sender: TObject);
begin
  if Assigned(FScheduler) then
    FScheduler.Enabled := True;

  LabelStatus.Text := 'Запущен';
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Lime;

  BtnStart.Enabled := False;
  BtnStop.Enabled := True;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Робот запущен');
end;

procedure TMainForm.BtnStopClick(Sender: TObject);
begin
  if Assigned(FScheduler) then
    FScheduler.Enabled := False;

  LabelStatus.Text := 'Остановлен';
  LabelStatus.TextSettings.FontColor := TAlphaColorRec.Silver;

  BtnStart.Enabled := True;
  BtnStop.Enabled := False;

  if Assigned(FLogManager) then
    FLogManager.LogInfo('Робот остановлен');
end;

{ --- Фоновые задачи планировщика --- }

procedure TMainForm.PollPrices;
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
    if not Assigned(FOrderManager) or not Assigned(FApiClient) then
      Exit;

    // Получаем все ордера и собираем уникальные InstrumentId
    ErrorLine := 20;
    orders := FOrderManager.GetAllOrders;
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

    // Запрашиваем цены через API
    ErrorLine := 40;
    if not FApiClient.GetLastPrices(uniqueIds, response, statusCode) then
      Exit;

    if statusCode <> 200 then
      Exit;

    // Парсим JSON-ответ
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
          FOrderManager.UpdatePrice(instrumentUid, priceDouble);
        end;
      end;
    finally
      FreeAndNil(jsonObj);
    end;

    // Обновляем таблицу в GUI-потоке
    ErrorLine := 80;
    if not ProgramClosing then
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          if not ProgramClosing then
            RefreshOrderGrid;
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

procedure TMainForm.SyncOrders;
var
  settings: TAppSettings;
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
    if not Assigned(FSettingsManager) or not Assigned(FApiClient) or
       not Assigned(FOrderManager) then
      Exit;

    // Получаем AccountId из настроек
    ErrorLine := 20;
    settings := FSettingsManager.GetSettings;
    if settings.AccountId = '' then
      Exit;

    // Запрашиваем активные заявки через API
    ErrorLine := 30;
    if not FApiClient.GetOrders(settings.AccountId, response, statusCode) then
      Exit;

    if statusCode <> 200 then
      Exit;

    // Парсим JSON-ответ
    ErrorLine := 40;
    jsonObj := TJSONObject.ParseJSONValue(response) as TJSONObject;
    if not Assigned(jsonObj) then
      Exit;
    try
      ErrorLine := 50;
      ordersArr := jsonObj.GetValue<TJSONArray>('orders');
      if not Assigned(ordersArr) then
        Exit;

      // Получаем локальные ордера для сопоставления
      ErrorLine := 60;
      localOrders := FOrderManager.GetAllOrders;

      ErrorLine := 70;
      for I := 0 to ordersArr.Count - 1 do
      begin
        if ProgramClosing then
          Exit;

        apiOrderObj := ordersArr.Items[I] as TJSONObject;
        apiOrderId := apiOrderObj.GetValue<string>('orderId');
        apiStatus := apiOrderObj.GetValue<string>('executionReportStatus');

        mappedStatus := TOrderManager.MapApiStatus(apiStatus);

        // Ищем локальный ордер по ExchangeOrderId
        for J := 0 to High(localOrders) do
        begin
          if localOrders[J].ExchangeOrderId = apiOrderId then
          begin
            FOrderManager.UpdateStatus(localOrders[J].Id, mappedStatus);
            Break;
          end;
        end;
      end;
    finally
      FreeAndNil(jsonObj);
    end;

    // Обновляем таблицу в GUI-потоке
    ErrorLine := 80;
    if not ProgramClosing then
    begin
      TThread.Synchronize(nil,
        procedure
        begin
          if not ProgramClosing then
            RefreshOrderGrid;
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
