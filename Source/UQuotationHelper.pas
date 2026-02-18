unit UQuotationHelper;

interface

uses
  System.JSON, System.SysUtils;

type
  /// <summary>
  /// Формат цены T-Invest API: целая часть (units) + дробная (nano, 9 знаков).
  /// Пример: 250.50 → Units = 250, Nano = 500000000
  /// </summary>
  TQuotation = record
    Units: Int64;
    Nano: Int32;
  end;

  /// <summary>
  /// Утилитный класс для конвертации между десятичными ценами и форматом Quotation API.
  /// </summary>
  TQuotationHelper = class
  public
    /// <summary>
    /// Конвертирует десятичное число в формат Quotation.
    /// Формула: Units = Trunc(Value), Nano = Round(Frac(Value) * 1e9)
    /// </summary>
    class function FromDouble(const AValue: Double): TQuotation; static;

    /// <summary>
    /// Конвертирует формат Quotation обратно в десятичное число.
    /// Формула: Value = Units + Nano / 1e9
    /// </summary>
    class function ToDouble(const AQuotation: TQuotation): Double; static;

    /// <summary>
    /// Формирует JSON-строку в формате API: {"units":"<units>","nano":<nano>}
    /// units — строка, nano — число (как в T-Invest API)
    /// </summary>
    class function ToJson(const AQuotation: TQuotation): string; static;

    /// <summary>
    /// Парсит TJSONObject в TQuotation.
    /// Ожидает поля "units" (строка или число) и "nano" (число).
    /// </summary>
    class function FromJson(const AJsonObj: TJSONObject): TQuotation; static;
  end;

implementation

{ TQuotationHelper }

class function TQuotationHelper.FromDouble(const AValue: Double): TQuotation;
var
  truncated: Double;
  fracPart: Double;
begin
  // Trunc отсекает дробную часть в сторону нуля
  truncated := Int(AValue);
  Result.Units := Trunc(truncated);

  // Дробная часть: разница между значением и целой частью
  fracPart := AValue - truncated;

  // Округляем nano до целого (9 знаков после запятой)
  Result.Nano := Round(fracPart * 1e9);
end;

class function TQuotationHelper.ToDouble(const AQuotation: TQuotation): Double;
begin
  Result := AQuotation.Units + AQuotation.Nano / 1e9;
end;

class function TQuotationHelper.ToJson(const AQuotation: TQuotation): string;
begin
  // Формат API: units — строка, nano — число
  Result := Format('{"units":"%d","nano":%d}', [AQuotation.Units, AQuotation.Nano]);
end;

class function TQuotationHelper.FromJson(const AJsonObj: TJSONObject): TQuotation;
var
  unitsValue: TJSONValue;
  nanoValue: TJSONValue;
begin
  Result.Units := 0;
  Result.Nano := 0;

  if not Assigned(AJsonObj) then
    Exit;

  // units может быть строкой или числом в JSON
  unitsValue := AJsonObj.GetValue('units');
  if Assigned(unitsValue) then
  begin
    if unitsValue is TJSONString then
      Result.Units := StrToInt64Def(unitsValue.Value, 0)
    else
      Result.Units := unitsValue.AsType<Int64>;
  end;

  // nano — всегда число
  nanoValue := AJsonObj.GetValue('nano');
  if Assigned(nanoValue) then
    Result.Nano := nanoValue.AsType<Int32>;
end;

end.
