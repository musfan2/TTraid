{
  Модальная форма для создания и редактирования торгового ордера.
  Поддерживает режим создания (пустая форма) и редактирования (заполнение из TOrderRecord).
  Валидация полей перед сохранением.

  Requirements: 4.1, 4.2, 4.3, 4.4, 4.5, 4.6
}

unit UOrderForm;

interface

uses
  SysUtils, Classes, Types, UITypes,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Dialogs,
  FMX.StdCtrls, FMX.Edit, FMX.ListBox, FMX.Layouts,
  FMX.Controls.Presentation, FMX.EditBox, FMX.SpinBox,
  UOrderManager;

type
  TOrderForm = class(TForm)
    LayoutMain: TLayout;
    LabelInstrument: TLabel;
    EditInstrument: TEdit;
    LabelDirection: TLabel;
    ComboDirection: TComboBox;
    LabelQuantity: TLabel;
    SpinQuantity: TSpinBox;
    LabelOrderType: TLabel;
    ComboOrderType: TComboBox;
    LabelTargetPrice: TLabel;
    EditTargetPrice: TEdit;
    LayoutButtons: TLayout;
    BtnSave: TButton;
    BtnCancel: TButton;
    procedure ComboOrderTypeChange(Sender: TObject);
    procedure BtnSaveClick(Sender: TObject);
    procedure BtnCancelClick(Sender: TObject);
  private
    FOrderId: Integer;
    FExchangeOrderId: string;
    FCurrentPrice: Double;
    FStatus: TOrderStatus;

    procedure UpdateTargetPriceVisibility;
    function Validate: Boolean;
  public
    /// <summary>Заполнить поля формы из существующего ордера (режим редактирования)</summary>
    procedure SetOrder(const AOrder: TOrderRecord);
    /// <summary>Считать поля формы в TOrderRecord</summary>
    function GetOrder: TOrderRecord;
  end;

implementation

{$R *.fmx}

uses
  Math;

{ TOrderForm }

procedure TOrderForm.ComboOrderTypeChange(Sender: TObject);
begin
  UpdateTargetPriceVisibility;
end;

procedure TOrderForm.UpdateTargetPriceVisibility;
var
  isLimitOrder: Boolean;
begin
  // Лимитный ордер — индекс 1 в ComboOrderType (Рыночный=0, Лимитный=1, По лучшей цене=2)
  isLimitOrder := (ComboOrderType.ItemIndex = 1);
  LabelTargetPrice.Visible := isLimitOrder;
  EditTargetPrice.Visible := isLimitOrder;
end;

function TOrderForm.Validate: Boolean;
var
  priceStr: string;
  priceValue: Double;
begin
  Result := False;

  // Проверка: инструмент не должен быть пустым (Req 4.5)
  if Trim(EditInstrument.Text) = '' then
  begin
    MessageDlg('Укажите инструмент (FIGI или тикер).',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    EditInstrument.SetFocus;
    Exit;
  end;

  // Проверка: количество лотов >= 1 (Req 4.4)
  if SpinQuantity.Value < 1 then
  begin
    MessageDlg('Количество лотов должно быть не менее 1.',
      TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
    SpinQuantity.SetFocus;
    Exit;
  end;

  // Проверка: для лимитных ордеров целевая цена обязательна и > 0 (Req 4.3)
  if ComboOrderType.ItemIndex = 1 then
  begin
    priceStr := Trim(EditTargetPrice.Text);
    if priceStr = '' then
    begin
      MessageDlg('Для лимитного ордера укажите целевую цену.',
        TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
      EditTargetPrice.SetFocus;
      Exit;
    end;

    // Заменяем запятую на точку для корректного парсинга
    priceStr := StringReplace(priceStr, ',', '.', [rfReplaceAll]);
    if not TryStrToFloat(priceStr, priceValue, TFormatSettings.Invariant) then
    begin
      MessageDlg('Некорректный формат цены. Введите числовое значение.',
        TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
      EditTargetPrice.SetFocus;
      Exit;
    end;

    if priceValue <= 0 then
    begin
      MessageDlg('Целевая цена должна быть больше 0.',
        TMsgDlgType.mtWarning, [TMsgDlgBtn.mbOK], 0);
      EditTargetPrice.SetFocus;
      Exit;
    end;
  end;

  Result := True;
end;

procedure TOrderForm.BtnSaveClick(Sender: TObject);
begin
  if Validate then
    ModalResult := mrOk;
end;

procedure TOrderForm.BtnCancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TOrderForm.SetOrder(const AOrder: TOrderRecord);
begin
  // Сохраняем поля, которые не редактируются на форме
  FOrderId := AOrder.Id;
  FExchangeOrderId := AOrder.ExchangeOrderId;
  FCurrentPrice := AOrder.CurrentPrice;
  FStatus := AOrder.Status;

  // Заполняем визуальные поля
  EditInstrument.Text := AOrder.InstrumentId;
  ComboDirection.ItemIndex := Ord(AOrder.Direction);
  SpinQuantity.Value := Max(AOrder.Quantity, 1);
  ComboOrderType.ItemIndex := Ord(AOrder.OrderType);

  // Целевая цена
  if AOrder.TargetPrice > 0 then
    EditTargetPrice.Text := FloatToStr(AOrder.TargetPrice, TFormatSettings.Invariant)
  else
    EditTargetPrice.Text := '';

  // Обновляем видимость поля цены
  UpdateTargetPriceVisibility;
end;

function TOrderForm.GetOrder: TOrderRecord;
var
  priceStr: string;
  priceValue: Double;
begin
  Result := Default(TOrderRecord);

  // Восстанавливаем сохранённые поля
  Result.Id := FOrderId;
  Result.ExchangeOrderId := FExchangeOrderId;
  Result.CurrentPrice := FCurrentPrice;
  Result.Status := FStatus;

  // Считываем визуальные поля
  Result.InstrumentId := Trim(EditInstrument.Text);
  Result.Ticker := Result.InstrumentId; // Тикер = инструмент (упрощение для MVP)

  if ComboDirection.ItemIndex >= 0 then
    Result.Direction := TOrderDirection(ComboDirection.ItemIndex)
  else
    Result.Direction := odBuy;

  Result.Quantity := Trunc(SpinQuantity.Value);

  if ComboOrderType.ItemIndex >= 0 then
    Result.OrderType := TOrderType(ComboOrderType.ItemIndex)
  else
    Result.OrderType := otMarket;

  // Целевая цена — только для лимитных ордеров
  Result.TargetPrice := 0;
  if ComboOrderType.ItemIndex = 1 then
  begin
    priceStr := Trim(EditTargetPrice.Text);
    priceStr := StringReplace(priceStr, ',', '.', [rfReplaceAll]);
    if TryStrToFloat(priceStr, priceValue, TFormatSettings.Invariant) then
      Result.TargetPrice := priceValue;
  end;
end;

end.
