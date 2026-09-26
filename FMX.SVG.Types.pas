unit FMX.SVG.Types;

interface

uses
  System.SysUtils, System.Types, System.Math, System.UITypes,
  System.Generics.Collections, FMX.Graphics;

type
  TSvgMatrix = record
    A, B, C, D, E, F: Single;
    class function Identity: TSvgMatrix; static;
    class function Translation(X, Y: Single): TSvgMatrix; static;
    class function Scaling(X, Y: Single): TSvgMatrix; static;
    class function Rotation(Radians: Single): TSvgMatrix; static;
    class function SkewX(Radians: Single): TSvgMatrix; static;
    class function SkewY(Radians: Single): TSvgMatrix; static;
    class function FromSvg(A, B, C, D, E, F: Single): TSvgMatrix; static;
    class operator Multiply(const L, R: TSvgMatrix): TSvgMatrix;
    function TransformPoint(const P: TPointF): TPointF;
  end;

  TSvgLengthUnit = (sluNumber, sluPx, sluPercent, sluEm, sluEx, sluPt, sluPc, sluCm, sluMm, sluIn);

  TSvgLength = record
    Value: Single;
    units: TSvgLengthUnit;
    class function Parse(const S: string; Default: Single = 0): TSvgLength; static;
    function Resolve(Reference, FontSize: Single): Single;
  end;

  TSvgPathCommandType = (spMoveTo, spLineTo, spCurveTo, spClose);

  TSvgPathCommand = record
    Command: TSvgPathCommandType;
    P1, P2, P3: TPointF;
    class function Create(Command: TSvgPathCommandType; P1, P2, P3: TPointF): TSvgPathCommand; static;
  end;

  TSvgPath = class
  private
    FCommands: TList<TSvgPathCommand>;
    FCurrent, FStart: TPointF;
    procedure AddCommand(Command: TSvgPathCommandType; const P1, P2, P3: TPointF);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure MoveTo(const P: TPointF);
    procedure LineTo(const P: TPointF);
    procedure CurveTo(const P1, P2, P3: TPointF);
    procedure ClosePath;
    procedure TransformTo(const Matrix: TSvgMatrix; Dest: TPathData);
    procedure AppendTo(Dest: TPathData; const Matrix: TSvgMatrix);
    property Commands: TList<TSvgPathCommand> read FCommands;
  end;

  TSvgFillRule = (sffNonZero, sffEvenOdd);

  TSvgGradientKind = (sgLinear, sgRadial);
  TSvgGradientSpread = (sgsPad, sgsRepeat, sgsReflect);

  TSvgPaint = record
    Enabled: Boolean;
    Color: TAlphaColor;
    GradientID, PatternID: string;
  end;

  TSvgGradient = class
  public
    Kind: TSvgGradientKind;
    Spread: TSvgGradientSpread;
    UnitsUserSpace: Boolean;
    X1, Y1, X2, Y2, Radius: Single;
    Matrix: TSvgMatrix;
    Gradient: TGradient;
    constructor Create;
    destructor Destroy; override;
  end;

  TSvgStyle = record
    Fill, Stroke: TSvgPaint;
    StrokeWidth, Opacity, FillOpacity, StrokeOpacity, DashOffset: Single;
    DashArray: TArray<Single>;
    StrokeCap: TStrokeCap;
    StrokeJoin: TStrokeJoin;
    FillRule: TSvgFillRule;
    Visible: Boolean;
    class function Default: TSvgStyle; static;
  end;

  TSvgElement = class
  public
    Name: string;
    Path: TSvgPath;
    Matrix: TSvgMatrix;
    Style: TSvgStyle;
    ClipID, MarkerStartID, MarkerMidID, MarkerEndID: string;
    Text: string;
    TextPosition: TPointF;
    FontFamily: string;
    FontSize: Single;
    TextAnchor: string;
    constructor Create;
    destructor Destroy; override;
  end;

  TSvgPattern = class
  public
    Width, Height: Single;
    UnitsUserSpace: Boolean;
    Matrix: TSvgMatrix;
    Elements: TObjectList<TSvgElement>;
    constructor Create;
    destructor Destroy; override;
  end;

  TSvgMarker = class
  public
    Width, Height, RefX, RefY: Single;
    Orient: string;
    UnitsStrokeWidth: Boolean;
    Path: TSvgPath;
    Style: TSvgStyle;
    Matrix: TSvgMatrix;
    constructor Create;
    destructor Destroy; override;
  end;

  TSvgSymbol = class
  public
    Path: TSvgPath;
    Style: TSvgStyle;
    Matrix: TSvgMatrix;
    ViewBox: TRectF;
    HasViewBox: Boolean;
    constructor Create;
    destructor Destroy; override;
  end;

implementation

function InvariantFloat(const S: string; Default: Single = 0): Single;
begin
  var T := Trim(S);
  if T.IsEmpty then
    Exit(Default);

  T := T.Replace(',', '.');
  Result := StrToFloatDef(T, Default, TFormatSettings.Invariant);
end;

{ TSvgMatrix }

class function TSvgMatrix.Identity: TSvgMatrix;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

class function TSvgMatrix.Translation(X, Y: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.E := X;
  Result.F := Y;
end;

class function TSvgMatrix.Scaling(X, Y: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.A := X;
  Result.D := Y;
end;

class function TSvgMatrix.Rotation(Radians: Single): TSvgMatrix;
begin
  var SinA := Sin(Radians);
  var CosA := Cos(Radians);
  Result.A := CosA;
  Result.B := SinA;
  Result.C := -SinA;
  Result.D := CosA;
  Result.E := 0;
  Result.F := 0;
end;

class function TSvgMatrix.SkewX(Radians: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.C := Tan(Radians);
end;

class function TSvgMatrix.SkewY(Radians: Single): TSvgMatrix;
begin
  Result := Identity;
  Result.B := Tan(Radians);
end;

class function TSvgMatrix.FromSvg(A, B, C, D, E, F: Single): TSvgMatrix;
begin
  Result.A := A;
  Result.B := B;
  Result.C := C;
  Result.D := D;
  Result.E := E;
  Result.F := F;
end;

class operator TSvgMatrix.Multiply(const L, R: TSvgMatrix): TSvgMatrix;
begin
  Result.A := L.A * R.A + L.C * R.B;
  Result.B := L.B * R.A + L.D * R.B;
  Result.C := L.A * R.C + L.C * R.D;
  Result.D := L.B * R.C + L.D * R.D;
  Result.E := L.A * R.E + L.C * R.F + L.E;
  Result.F := L.B * R.E + L.D * R.F + L.F;
end;

function TSvgMatrix.TransformPoint(const P: TPointF): TPointF;
begin
  Result.X := A * P.X + C * P.Y + E;
  Result.Y := B * P.X + D * P.Y + F;
end;

{ TSvgLength }

class function TSvgLength.Parse(const S: string; Default: Single): TSvgLength;
begin
  Result.Value := Default;
  Result.units := sluNumber;
  var V := S.Trim;
  if V.IsEmpty then
    Exit;

  var P := 1;
  if CharInSet(V[P], ['+', '-']) then
    Inc(P);
  var HasDigits := False;
  while (P <= V.Length) and CharInSet(V[P], ['0'..'9']) do
  begin
    HasDigits := True;
    Inc(P);
  end;
  if (P <= V.Length) and (V[P] = '.') then
  begin
    Inc(P);
    while (P <= V.Length) and CharInSet(V[P], ['0'..'9']) do
    begin
      HasDigits := True;
      Inc(P);
    end;
  end;
  if HasDigits and (P <= V.Length) and CharInSet(V[P], ['e', 'E']) then
  begin
    var ExpPos := P;
    Inc(P);
    if (P <= V.Length) and CharInSet(V[P], ['+', '-']) then
      Inc(P);
    var ExpDigits := False;
    while (P <= V.Length) and CharInSet(V[P], ['0'..'9']) do
    begin
      ExpDigits := True;
      Inc(P);
    end;
    if not ExpDigits then
      P := ExpPos;
  end;
  if not HasDigits then
    Exit;

  Result.Value := InvariantFloat(V.Substring(0, P - 1), Default);
  var UnitName := V.Substring(P - 1).Trim.ToLower;
  if UnitName.IsEmpty then
    Result.units := sluNumber
  else if UnitName = 'px' then
    Result.units := sluPx
  else if UnitName = '%' then
    Result.units := sluPercent
  else if UnitName = 'em' then
    Result.units := sluEm
  else if UnitName = 'ex' then
    Result.units := sluEx
  else if UnitName = 'pt' then
    Result.units := sluPt
  else if UnitName = 'pc' then
    Result.units := sluPc
  else if UnitName = 'cm' then
    Result.units := sluCm
  else if UnitName = 'mm' then
    Result.units := sluMm
  else if UnitName = 'in' then
    Result.units := sluIn
  else
  begin
    Result.Value := Default;
    Result.units := sluNumber;
  end;
end;

function TSvgLength.Resolve(Reference, FontSize: Single): Single;
begin
  case units of
    sluNumber, sluPx:
      Result := Value;
    sluPercent:
      Result := Reference * Value / 100;
    sluEm:
      Result := FontSize * Value;
    sluEx:
      Result := FontSize * 0.5 * Value;
    sluPt:
      Result := Value * 96 / 72;
    sluPc:
      Result := Value * 96 / 6;
    sluCm:
      Result := Value * 96 / 2.54;
    sluMm:
      Result := Value * 96 / 25.4;
    sluIn:
      Result := Value * 96;
  else
    Result := Value;
  end;
end;

{ TSvgPathCommand }

class function TSvgPathCommand.Create(Command: TSvgPathCommandType; P1, P2, P3: TPointF): TSvgPathCommand;
begin
  Result.Command := Command;
  Result.P1 := P1;
  Result.P2 := P2;
  Result.P3 := P3;
end;

{ TSvgPath }

constructor TSvgPath.Create;
begin
  inherited;
  FCommands := TList<TSvgPathCommand>.Create;
end;

destructor TSvgPath.Destroy;
begin
  FCommands.Free;
  inherited;
end;

procedure TSvgPath.Clear;
begin
  FCommands.Clear;
  FCurrent := PointF(0, 0);
  FStart := PointF(0, 0);
end;

procedure TSvgPath.AddCommand(Command: TSvgPathCommandType; const P1, P2, P3: TPointF);
begin
  FCommands.Add(TSvgPathCommand.Create(Command, P1, P2, P3));
end;

procedure TSvgPath.MoveTo(const P: TPointF);
begin
  AddCommand(spMoveTo, P, PointF(0, 0), PointF(0, 0));
  FCurrent := P;
  FStart := P;
end;

procedure TSvgPath.LineTo(const P: TPointF);
begin
  AddCommand(spLineTo, P, PointF(0, 0), PointF(0, 0));
  FCurrent := P;
end;

procedure TSvgPath.CurveTo(const P1, P2, P3: TPointF);
begin
  AddCommand(spCurveTo, P1, P2, P3);
  FCurrent := P3;
end;

procedure TSvgPath.ClosePath;
begin
  AddCommand(spClose, PointF(0, 0), PointF(0, 0), PointF(0, 0));
  FCurrent := FStart;
end;

procedure TSvgPath.AppendTo(Dest: TPathData; const Matrix: TSvgMatrix);
begin
  for var Command in FCommands do
    case Command.Command of
      spMoveTo:
        Dest.MoveTo(Matrix.TransformPoint(Command.P1));
      spLineTo:
        Dest.LineTo(Matrix.TransformPoint(Command.P1));
      spCurveTo:
        Dest.CurveTo(
          Matrix.TransformPoint(Command.P1),
          Matrix.TransformPoint(Command.P2),
          Matrix.TransformPoint(Command.P3)
        );
      spClose:
        Dest.ClosePath;
    end;
end;

procedure TSvgPath.TransformTo(const Matrix: TSvgMatrix; Dest: TPathData);
begin
  Dest.Clear;
  AppendTo(Dest, Matrix);
end;

{ TSvgStyle }

constructor TSvgGradient.Create;
begin
  inherited;
  X1 := 0;
  Y1 := 0;
  X2 := 1;
  Y2 := 0;
  Radius := 0.5;
  Kind := sgLinear;
  Spread := sgsPad;
  UnitsUserSpace := False;
  Matrix := TSvgMatrix.Identity;
  Gradient := TGradient.Create;
  Gradient.Points.Clear;
end;

destructor TSvgGradient.Destroy;
begin
  Gradient.Free;
  inherited;
end;

class function TSvgStyle.Default: TSvgStyle;
begin
  Result.Visible := True;
  Result.Opacity := 1;
  Result.FillOpacity := 1;
  Result.StrokeOpacity := 1;
  Result.StrokeWidth := 1;
  Result.FillRule := sffNonZero;
  Result.Fill.Enabled := True;
  Result.Fill.Color := TAlphaColorRec.Black;
  Result.Fill.GradientID := '';
  Result.Fill.PatternID := '';
  Result.Stroke.Enabled := False;
  Result.Stroke.Color := TAlphaColorRec.Black;
  Result.Stroke.GradientID := '';
  Result.Stroke.PatternID := '';
  Result.StrokeCap := TStrokeCap.Flat;
  Result.StrokeJoin := TStrokeJoin.Miter;
  Result.DashOffset := 0;
  Result.DashArray := nil;
end;

{ TSvgElement }

constructor TSvgElement.Create;
begin
  inherited;
  Path := TSvgPath.Create;
  Matrix := TSvgMatrix.Identity;
  Style := TSvgStyle.Default;
  FontSize := 12;
  TextAnchor := 'start';
end;

destructor TSvgElement.Destroy;
begin
  Path.Free;
  inherited;
end;

{ TSvgPattern }

constructor TSvgPattern.Create;
begin
  inherited;
  Width := 0;
  Height := 0;
  UnitsUserSpace := False;
  Matrix := TSvgMatrix.Identity;
  Elements := TObjectList<TSvgElement>.Create(True);
end;

destructor TSvgPattern.Destroy;
begin
  Elements.Free;
  inherited;
end;

{ TSvgMarker }

constructor TSvgMarker.Create;
begin
  inherited;
  Width := 3;
  Height := 3;
  RefX := 0;
  RefY := 0;
  Orient := '0';
  UnitsStrokeWidth := True;
  Path := TSvgPath.Create;
  Style := TSvgStyle.Default;
  Matrix := TSvgMatrix.Identity;
end;

destructor TSvgMarker.Destroy;
begin
  Path.Free;
  inherited;
end;

{ TSvgSymbol }

constructor TSvgSymbol.Create;
begin
  inherited;
  Path := TSvgPath.Create;
  Style := TSvgStyle.Default;
  Matrix := TSvgMatrix.Identity;
  ViewBox := TRectF.Empty;
  HasViewBox := False;
end;

destructor TSvgSymbol.Destroy;
begin
  Path.Free;
  inherited;
end;

end.
