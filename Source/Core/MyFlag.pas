{ *****************************************************************************

  Модуль MyFlag.pas содержит record TMyFlag для потокобезопасной работы с флагами (заменяет Boolean).

  Можно использовать, как обычный Boolean.
  Но в высококонкурентной среде безопасней работать через свойство IsSet: ProgramLoading.IsSet

  Copyright (C) 2025 АО "НВП Болид"
  Сектор АУР

  Разработчик: Петухов Сергей
  Создан: 12.05.2025

  **************************************************************************** }

unit MyFlag;

interface

type

  // TMyFlag для потокобезопасной работы с флагами (заменяет Boolean)
  TMyFlag = record
  strict private
    FValue: Integer;
    function GetValue: Boolean;
    procedure SetValue(const Value: Boolean);
  public
    class function GetTrue: TMyFlag; static;
    class function GetFalse: TMyFlag; static;

    // Позволяет задать или прочитать значение флага.
    // Это самый потокобезопасный способ работы с флагом !!!
    property IsSet: Boolean read GetValue write SetValue;

    // Превратит в строку True или False
    function ToString: string;

    // Позволяют работать с IsSet, обращаясь просто к имени экземпляра
    // Это не потокобезопасно! Лучше использовать IsSet в ответственных местах. Пример: ProgramLoading.IsSet
    class operator Implicit(const AValue: TMyFlag): Boolean;
    class operator Implicit(const AValue: Boolean): TMyFlag;

    // Операторы AND, OR, XOR, NOT
    class operator LogicalAnd(const ALeft, ARight: TMyFlag): TMyFlag;
    class operator LogicalOr(const ALeft, ARight: TMyFlag): TMyFlag;
    class operator LogicalXor(const ALeft, ARight: TMyFlag): TMyFlag;
    class operator LogicalNot(const AValue: TMyFlag): TMyFlag;
  end;

implementation

uses SyncObjs, StrUtils;

{ TMyFlag }

class function TMyFlag.GetFalse: TMyFlag;
begin
  Result := False;
end;

class function TMyFlag.GetTrue: TMyFlag;
begin
  Result := True;
end;

function TMyFlag.GetValue: Boolean;
// Если значение = 0, значит False, иначе - True
begin
  Result := TInterlocked.CompareExchange(FValue, 0, 0) <> 0; // Универсальный, но чуть более медленный вариант
end;

procedure TMyFlag.SetValue(const Value: Boolean);
begin
  // Ord вернет 1, если Value = True
  TInterlocked.Exchange(FValue, Ord(Value))
end;

function TMyFlag.ToString: string;
// Превратит в строку True или False
begin
  Result := IfThen(IsSet, 'True', 'False');
end;

class operator TMyFlag.Implicit(const AValue: Boolean): TMyFlag;
// Позволяют работать с IsSet обращаясь просто к имени экземпляра; Ord вернет 1, если True и 0, если False
begin
  // Используем атомарную запись для защиты от NRVO-оптимизации компилятора
  TInterlocked.Exchange(Result.FValue, Ord(AValue));
end;

class operator TMyFlag.Implicit(const AValue: TMyFlag): Boolean;
// Позволяют работать с IsSet обращаясь просто к имени экземпляра
begin
  Result := AValue.IsSet;
end;

class operator TMyFlag.LogicalOr(const ALeft, ARight: TMyFlag): TMyFlag;
// Логическое ИЛИ (OR); Ord вернет 1, если True и 0, если False
begin
  // Используем атомарную запись для защиты от NRVO-оптимизации компилятора
  TInterlocked.Exchange(Result.FValue, Ord(ALeft.IsSet or ARight.IsSet));
end;

class operator TMyFlag.LogicalAnd(const ALeft, ARight: TMyFlag): TMyFlag;
// Логическое И (AND); Ord вернет 1, если True и 0, если False
begin
  TInterlocked.Exchange(Result.FValue, Ord(ALeft.IsSet and ARight.IsSet));
end;

class operator TMyFlag.LogicalXor(const ALeft, ARight: TMyFlag): TMyFlag;
// Перегрузка оператора XOR; Ord вернет 1, если True и 0, если False
begin
  TInterlocked.Exchange(Result.FValue, Ord(ALeft.IsSet xor ARight.IsSet));
end;

class operator TMyFlag.LogicalNot(const AValue: TMyFlag): TMyFlag;
// Оператор отрицания NOT; Ord вернет 1, если True и 0, если False
begin
  TInterlocked.Exchange(Result.FValue, Ord(not AValue.IsSet));
end;

end.
