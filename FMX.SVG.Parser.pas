unit FMX.SVG.Parser;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.Math, System.UITypes,
  System.Variants, System.Generics.Collections, Xml.XMLDoc, Xml.XMLIntf,
  FMX.Graphics, FMX.SVG.Types;

type
  TSvgNumberParser = record
  private
    FText: string;
    FPos: Integer;
    procedure SkipSeparators;
  public
    class function Create(const S: string): TSvgNumberParser; static;
    function ReadNumber(out Value: Single): Boolean;
    function ReadFlag(out Value: Integer): Boolean;
    function Position: Integer;
    function Finished: Boolean;
  end;

  TSvgPathParser = class
  private
    FText: string;
    FPos: Integer;
    FPath: TSvgPath;
    FCurrent, FStart, FLastCubicControl, FLastQuadraticControl: TPointF;
    FLastCommand: Char;
    function IsCommandChar(C: Char): Boolean;
    function SkipSeparators: Boolean;
    function ReadNumber(out Value: Single): Boolean;
    function ReadFlag(out Value: Integer): Boolean;
    function ReadPoint(out P: TPointF): Boolean;
    function HasNumber: Boolean;
    procedure ParseMove(Relative: Boolean);
    procedure ParseLine(Relative: Boolean);
    procedure ParseHorizontal(Relative: Boolean);
    procedure ParseVertical(Relative: Boolean);
    procedure ParseCubic(Relative: Boolean);
    procedure ParseSmoothCubic(Relative: Boolean);
    procedure ParseQuadratic(Relative: Boolean);
    procedure ParseSmoothQuadratic(Relative: Boolean);
    procedure ParseArc(Relative: Boolean);
    procedure ParseClose;
    function ReflectCubicControl: TPointF;
    function ReflectQuadraticControl: TPointF;
    procedure AddArc(const P0, P1: TPointF; RX, RY, Rotation: Single; LargeArc, Sweep: Boolean);
  public
    constructor Create(APath: TSvgPath);
    procedure Parse(const S: string);
  end;

  TSvgDocument = class
  private
    FElements: TObjectList<TSvgElement>;
    FClipPaths: TObjectDictionary<string, TSvgPath>;
    FGradients: TObjectDictionary<string, TSvgGradient>;
    FPatterns: TObjectDictionary<string, TSvgPattern>;
    FMarkers: TObjectDictionary<string, TSvgMarker>;
    FSymbols: TObjectDictionary<string, TSvgSymbol>;
    FClassStyles: TStringList;
    FWidth, FHeight: Single;
    FWidthLength, FHeightLength: TSvgLength;
    FViewBox: TRectF;
    FHasViewBox: Boolean;
    procedure ParseNode(const Node: IXMLNode; const ParentMatrix: TSvgMatrix; const ParentStyle: TSvgStyle);
    procedure ParseShape(const Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle; const Dest: TObjectList<TSvgElement>);
    function ParseStyle(const Node: IXMLNode; const Parent: TSvgStyle): TSvgStyle;
    procedure ApplyStyleDeclaration(const Declaration: string; var Style: TSvgStyle);
    procedure ParseCss(const Text: string);
    function ParseTransform(const S: string): TSvgMatrix;
    procedure ParsePath(Node: IXMLNode; Element: TSvgElement);
    procedure ParseRect(Node: IXMLNode; Element: TSvgElement);
    procedure ParseCircle(Node: IXMLNode; Element: TSvgElement);
    procedure ParseEllipse(Node: IXMLNode; Element: TSvgElement);
    procedure ParseLine(Node: IXMLNode; Element: TSvgElement);
    procedure ParsePoly(Node: IXMLNode; Element: TSvgElement; Closed: Boolean);
    procedure ParseText(Node: IXMLNode; Element: TSvgElement);
    procedure ApplyTextStyleDeclaration(const Declaration: string; Element: TSvgElement);
    procedure ApplyTextStyle(const Node: IXMLNode; Element: TSvgElement);
    function TextContent(const Node: IXMLNode): string;
    procedure ParseClipPath(Node: IXMLNode; const Matrix: TSvgMatrix);
    procedure ParseLinearGradient(Node: IXMLNode);
    procedure ParseRadialGradient(Node: IXMLNode);
    procedure ParsePattern(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
    procedure ParseMarker(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
    procedure ParseSymbol(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
    procedure ParseUse(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
    function Attr(const Node: IXMLNode; const Name: string; const Default: string = ''): string;
    function LengthAttr(const Node: IXMLNode; const Name: string; Reference: Single; Default: Single = 0): Single;
    function ParseFloat(const S: string; Default: Single = 0): Single;
    function ParseColor(const S: string; Default: TAlphaColor): TAlphaColor;
    function StyleAttr(const Node: IXMLNode; const Name: string; const Default: string = ''): string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure LoadFromString(const S: string);
    property Elements: TObjectList<TSvgElement> read FElements;
    property ClipPaths: TObjectDictionary<string, TSvgPath> read FClipPaths;
    property Gradients: TObjectDictionary<string, TSvgGradient> read FGradients;
    property Patterns: TObjectDictionary<string, TSvgPattern> read FPatterns;
    property Markers: TObjectDictionary<string, TSvgMarker> read FMarkers;
    property Symbols: TObjectDictionary<string, TSvgSymbol> read FSymbols;
    property Width: Single read FWidth;
    property Height: Single read FHeight;
    property WidthLength: TSvgLength read FWidthLength;
    property HeightLength: TSvgLength read FHeightLength;
    property ViewBox: TRectF read FViewBox;
    property HasViewBox: Boolean read FHasViewBox;
  end;

implementation

uses
  System.StrUtils;

const
  SVG_EPS = 0.00001;
  SVG_KAPPA = 0.5522847498307936;

function InvariantFloat(const S: string; Default: Single = 0): Single;
begin
  var T := Trim(S);
  if T.IsEmpty then
    Exit(Default);

  T := T.Replace(',', '.');
  Result := StrToFloatDef(T, Default, TFormatSettings.Invariant);
end;

function ContainsString(const Values: TArray<string>; const Value: string): Boolean;
begin
  for var S in Values do
    if SameText(S, Value) then
      Exit(True);

  Result := False;
end;

function AlphaColorWithOpacity(Color: TAlphaColor; Opacity: Single): TAlphaColor;
begin
  var A := Round(TAlphaColorRec(Color).A * EnsureRange(Opacity, 0, 1));
  Result := (Color and $00FFFFFF) or (TAlphaColor(A) shl 24);
end;

function GradientIDFromPaint(const Value: string): string;
begin
  var Paint := Value.Trim;
  if not Paint.StartsWith('url(') or not Paint.EndsWith(')') then
    Exit('');

  Result := Paint.Substring(4, Paint.Length - 5).Trim;
  if Result.StartsWith('#') then
    Result := Result.Substring(1)
  else
    Result := '';
end;

{ TSvgNumberParser }

class function TSvgNumberParser.Create(const S: string): TSvgNumberParser;
begin
  Result.FText := S;
  Result.FPos := 1;
end;

procedure TSvgNumberParser.SkipSeparators;
begin
  while FPos <= FText.Length do
  begin
    if CharInSet(FText[FPos], [' ', #9, #10, #13, ',']) then
      Inc(FPos)
    else
      Break;
  end;
end;

function TSvgNumberParser.ReadNumber(out Value: Single): Boolean;
begin
  Result := False;
  SkipSeparators;
  if FPos > FText.Length then
    Exit;
  var Start := FPos;
  if CharInSet(FText[FPos], ['+', '-']) then
    Inc(FPos);
  var HasDigits := False;
  while (FPos <= FText.Length) and CharInSet(FText[FPos], ['0'..'9']) do
  begin
    HasDigits := True;
    Inc(FPos);
  end;
  if (FPos <= FText.Length) and (FText[FPos] = '.') then
  begin
    Inc(FPos);
    while (FPos <= FText.Length) and CharInSet(FText[FPos], ['0'..'9']) do
    begin
      HasDigits := True;
      Inc(FPos);
    end;
  end;
  if HasDigits and (FPos <= FText.Length) and CharInSet(FText[FPos], ['e', 'E']) then
  begin
    var ExpPos := FPos;
    Inc(FPos);
    if (FPos <= FText.Length) and CharInSet(FText[FPos], ['+', '-']) then
      Inc(FPos);
    var ExpDigits := False;
    while (FPos <= FText.Length) and CharInSet(FText[FPos], ['0'..'9']) do
    begin
      ExpDigits := True;
      Inc(FPos);
    end;
    if not ExpDigits then
      FPos := ExpPos;
  end;
  if not HasDigits then
  begin
    FPos := Start;
    Exit;
  end;
  Value := InvariantFloat(FText.Substring(Start - 1, FPos - Start));
  Result := True;
end;

function TSvgNumberParser.ReadFlag(out Value: Integer): Boolean;
begin
  SkipSeparators;
  Result := False;
  if FPos > FText.Length then
    Exit;
  if FText[FPos] = '0' then
  begin
    Value := 0;
    Inc(FPos);
    Exit(True);
  end;
  if FText[FPos] = '1' then
  begin
    Value := 1;
    Inc(FPos);
    Exit(True);
  end;
end;

function TSvgNumberParser.Position: Integer;
begin
  Result := FPos;
end;

function TSvgNumberParser.Finished: Boolean;
begin
  SkipSeparators;
  Result := FPos > FText.Length;
end;

{ TSvgPathParser }

constructor TSvgPathParser.Create(APath: TSvgPath);
begin
  inherited Create;
  FPath := APath;
end;

function TSvgPathParser.IsCommandChar(C: Char): Boolean;
begin
  Result := CharInSet(C, ['M', 'm', 'L', 'l', 'H', 'h', 'V', 'v', 'C', 'c', 'S', 's', 'Q', 'q', 'T', 't', 'A', 'a', 'Z', 'z']);
end;

function TSvgPathParser.SkipSeparators: Boolean;
begin
  while FPos <= FText.Length do
  begin
    if CharInSet(FText[FPos], [' ', #9, #10, #13, ',']) then
      Inc(FPos)
    else
      Break;
  end;
  Result := FPos <= FText.Length;
end;

function TSvgPathParser.HasNumber: Boolean;
begin
  SkipSeparators;
  Result := (FPos <= FText.Length) and not IsCommandChar(FText[FPos]);
end;

function TSvgPathParser.ReadNumber(out Value: Single): Boolean;
begin
  var Parser := TSvgNumberParser.Create(FText.Substring(FPos - 1));
  Result := Parser.ReadNumber(Value);
  if Result then
    FPos := FPos + Parser.Position - 1;
end;

function TSvgPathParser.ReadFlag(out Value: Integer): Boolean;
begin
  var Parser := TSvgNumberParser.Create(FText.Substring(FPos - 1));
  Result := Parser.ReadFlag(Value);
  if Result then
    FPos := FPos + Parser.Position - 1;
end;

function TSvgPathParser.ReadPoint(out P: TPointF): Boolean;
begin
  Result := ReadNumber(P.X) and ReadNumber(P.Y);
end;

function TSvgPathParser.ReflectCubicControl: TPointF;
begin
  if CharInSet(FLastCommand, ['C', 'c', 'S', 's']) then
    Result := PointF(2 * FCurrent.X - FLastCubicControl.X, 2 * FCurrent.Y - FLastCubicControl.Y)
  else
    Result := FCurrent;
end;

function TSvgPathParser.ReflectQuadraticControl: TPointF;
begin
  if CharInSet(FLastCommand, ['Q', 'q', 'T', 't']) then
    Result := PointF(2 * FCurrent.X - FLastQuadraticControl.X, 2 * FCurrent.Y - FLastQuadraticControl.Y)
  else
    Result := FCurrent;
end;

procedure TSvgPathParser.ParseMove(Relative: Boolean);
begin
  var First := True;
  while HasNumber do
  begin
    var P: TPointF;
    if not ReadPoint(P) then
      Break;

    if Relative then
      P := P + FCurrent;
    if First then
    begin
      FPath.MoveTo(P);
      FStart := P;
      First := False;
      if Relative then
        FLastCommand := 'm'
      else
        FLastCommand := 'M';
    end
    else
    begin
      FPath.LineTo(P);
      if Relative then
        FLastCommand := 'l'
      else
        FLastCommand := 'L';
    end;
    FCurrent := P;
  end;
end;

procedure TSvgPathParser.ParseLine(Relative: Boolean);
begin
  while HasNumber do
  begin
    var P: TPointF;
    if not ReadPoint(P) then
      Break;

    if Relative then
      P := P + FCurrent;
    FPath.LineTo(P);
    FCurrent := P;
    if Relative then
      FLastCommand := 'l'
    else
      FLastCommand := 'L';
  end;
end;

procedure TSvgPathParser.ParseHorizontal(Relative: Boolean);
begin
  while HasNumber do
  begin
    var X: Single;
    if not ReadNumber(X) then
      Break;

    if Relative then
      X := X + FCurrent.X;
    FCurrent.X := X;
    FPath.LineTo(FCurrent);
    if Relative then
      FLastCommand := 'h'
    else
      FLastCommand := 'H';
  end;
end;

procedure TSvgPathParser.ParseVertical(Relative: Boolean);
begin
  while HasNumber do
  begin
    var Y: Single;
    if not ReadNumber(Y) then
      Break;

    if Relative then
      Y := Y + FCurrent.Y;
    FCurrent.Y := Y;
    FPath.LineTo(FCurrent);
    if Relative then
      FLastCommand := 'v'
    else
      FLastCommand := 'V';
  end;
end;

procedure TSvgPathParser.ParseCubic(Relative: Boolean);
begin
  while HasNumber do
  begin
    var P1, P2, P3: TPointF;
    if not ReadPoint(P1) then
      Break;
    if not ReadPoint(P2) then
      Break;
    if not ReadPoint(P3) then
      Break;

    if Relative then
    begin
      P1 := P1 + FCurrent;
      P2 := P2 + FCurrent;
      P3 := P3 + FCurrent;
    end;
    FPath.CurveTo(P1, P2, P3);
    FCurrent := P3;
    FLastCubicControl := P2;
    if Relative then
      FLastCommand := 'c'
    else
      FLastCommand := 'C';
  end;
end;

procedure TSvgPathParser.ParseSmoothCubic(Relative: Boolean);
begin
  while HasNumber do
  begin
    var P1 := ReflectCubicControl;
    var P2, P3: TPointF;
    if not ReadPoint(P2) then
      Break;
    if not ReadPoint(P3) then
      Break;

    if Relative then
    begin
      P2 := P2 + FCurrent;
      P3 := P3 + FCurrent;
    end;
    FPath.CurveTo(P1, P2, P3);
    FCurrent := P3;
    FLastCubicControl := P2;
    if Relative then
      FLastCommand := 's'
    else
      FLastCommand := 'S';
  end;
end;

procedure TSvgPathParser.ParseQuadratic(Relative: Boolean);
begin
  while HasNumber do
  begin
    var Q, P: TPointF;
    if not ReadPoint(Q) then
      Break;
    if not ReadPoint(P) then
      Break;

    if Relative then
    begin
      Q := Q + FCurrent;
      P := P + FCurrent;
    end;
    var C1 := PointF(FCurrent.X + (2 / 3) * (Q.X - FCurrent.X), FCurrent.Y + (2 / 3) * (Q.Y - FCurrent.Y));
    var C2 := PointF(P.X + (2 / 3) * (Q.X - P.X), P.Y + (2 / 3) * (Q.Y - P.Y));
    FPath.CurveTo(C1, C2, P);
    FLastQuadraticControl := Q;
    FCurrent := P;
    if Relative then
      FLastCommand := 'q'
    else
      FLastCommand := 'Q';
  end;
end;

procedure TSvgPathParser.ParseSmoothQuadratic(Relative: Boolean);
begin
  while HasNumber do
  begin
    var Q := ReflectQuadraticControl;
    var P: TPointF;
    if not ReadPoint(P) then
      Break;

    if Relative then
      P := P + FCurrent;
    var C1 := PointF(FCurrent.X + (2 / 3) * (Q.X - FCurrent.X), FCurrent.Y + (2 / 3) * (Q.Y - FCurrent.Y));
    var C2 := PointF(P.X + (2 / 3) * (Q.X - P.X), P.Y + (2 / 3) * (Q.Y - P.Y));
    FPath.CurveTo(C1, C2, P);
    FLastQuadraticControl := Q;
    FCurrent := P;
    if Relative then
      FLastCommand := 't'
    else
      FLastCommand := 'T';
  end;
end;

procedure TSvgPathParser.AddArc(const P0, P1: TPointF; RX, RY, Rotation: Single; LargeArc, Sweep: Boolean);
begin
  RX := Abs(RX);
  RY := Abs(RY);
  if (RX < SVG_EPS) or (RY < SVG_EPS) then
  begin
    FPath.LineTo(P1);
    FCurrent := P1;
    Exit;
  end;
  if SameValue(P0.X, P1.X, SVG_EPS) and SameValue(P0.Y, P1.Y, SVG_EPS) then
    Exit;

  var Phi := DegToRad(Rotation);
  var CosPhi := Cos(Phi);
  var SinPhi := Sin(Phi);
  var DX := (P0.X - P1.X) / 2;
  var DY := (P0.Y - P1.Y) / 2;
  var X1p := CosPhi * DX + SinPhi * DY;
  var Y1p := -SinPhi * DX + CosPhi * DY;
  var Lambda := Sqr(X1p / RX) + Sqr(Y1p / RY);
  if Lambda > 1 then
  begin
    var Scale := Sqrt(Lambda);
    RX := RX * Scale;
    RY := RY * Scale;
  end;
  var RX2 := Sqr(RX);
  var RY2 := Sqr(RY);
  var X1p2 := Sqr(X1p);
  var Y1p2 := Sqr(Y1p);
  var Denominator := RX2 * Y1p2 + RY2 * X1p2;
  var Numerator := RX2 * RY2 - Denominator;
  if Numerator < 0 then
    Numerator := 0;
  var Coeff := Sqrt(Numerator / Max(Denominator, SVG_EPS));
  if LargeArc = Sweep then
    Coeff := -Coeff;
  var Cxp := Coeff * (RX * Y1p / RY);
  var Cyp := Coeff * (-RY * X1p / RX);
  var CX := CosPhi * Cxp - SinPhi * Cyp + (P0.X + P1.X) / 2;
  var CY := SinPhi * Cxp + CosPhi * Cyp + (P0.Y + P1.Y) / 2;
  var Ux := (X1p - Cxp) / RX;
  var Uy := (Y1p - Cyp) / RY;
  var Vx := (-X1p - Cxp) / RX;
  var Vy := (-Y1p - Cyp) / RY;
  var Theta1 := ArcTan2(Uy, Ux);
  var Delta := ArcTan2(Ux * Vy - Uy * Vx, Ux * Vx + Uy * Vy);
  if (not Sweep) and (Delta > 0) then
    Delta := Delta - 2 * Pi
  else if Sweep and (Delta < 0) then
    Delta := Delta + 2 * Pi;
  var Segments := Ceil(Abs(Delta) / (Pi / 2));
  if Segments <= 0 then
  begin
    FCurrent := P1;
    Exit;
  end;
  var DeltaSegment := Delta / Segments;
  for var i := 0 to Segments - 1 do
  begin
    var T1 := Theta1 + i * DeltaSegment;
    var T2 := T1 + DeltaSegment;
    var Alpha := (4 / 3) * Tan((T2 - T1) / 4);
    var Cos1 := Cos(T1);
    var Sin1 := Sin(T1);
    var Cos2 := Cos(T2);
    var Sin2 := Sin(T2);
    var PStart := PointF(CX + CosPhi * RX * Cos1 - SinPhi * RY * Sin1, CY + SinPhi * RX * Cos1 + CosPhi * RY * Sin1);
    var PEnd := PointF(CX + CosPhi * RX * Cos2 - SinPhi * RY * Sin2, CY + SinPhi * RX * Cos2 + CosPhi * RY * Sin2);
    var C1 := PointF(PStart.X + Alpha * (-CosPhi * RX * Sin1 - SinPhi * RY * Cos1), PStart.Y + Alpha * (-SinPhi * RX * Sin1 + CosPhi * RY * Cos1));
    var C2 := PointF(PEnd.X - Alpha * (-CosPhi * RX * Sin2 - SinPhi * RY * Cos2), PEnd.Y - Alpha * (-SinPhi * RX * Sin2 + CosPhi * RY * Cos2));
    FPath.CurveTo(C1, C2, PEnd);
  end;
  FCurrent := P1;
end;

procedure TSvgPathParser.ParseArc(Relative: Boolean);
begin
  while HasNumber do
  begin
    var RX, RY, Rotation: Single;
    var LargeArc, Sweep: Integer;
    var P: TPointF;
    if not ReadNumber(RX) then
      Break;
    if not ReadNumber(RY) then
      Break;
    if not ReadNumber(Rotation) then
      Break;
    if not ReadFlag(LargeArc) then
      Break;
    if not ReadFlag(Sweep) then
      Break;
    if not ReadPoint(P) then
      Break;

    if Relative then
      P := P + FCurrent;
    AddArc(FCurrent, P, RX, RY, Rotation, LargeArc <> 0, Sweep <> 0);
    if Relative then
      FLastCommand := 'a'
    else
      FLastCommand := 'A';
  end;
end;

procedure TSvgPathParser.ParseClose;
begin
  FPath.ClosePath;
  FCurrent := FStart;
  FLastCommand := 'Z';
end;

procedure TSvgPathParser.Parse(const S: string);
begin
  FPath.Clear;
  FText := S;
  FPos := 1;
  FCurrent := PointF(0, 0);
  FStart := PointF(0, 0);
  FLastCommand := #0;
  FLastCubicControl := FCurrent;
  FLastQuadraticControl := FCurrent;
  while FPos <= FText.Length do
  begin
    SkipSeparators;
    if FPos > FText.Length then
      Break;

    var Command := FText[FPos];
    if IsCommandChar(Command) then
    begin
      Inc(FPos);
    end
    else if FLastCommand = #0 then
    begin
      Inc(FPos);
      Continue;
    end
    else if CharInSet(FLastCommand, ['Z', 'z']) then
    begin
      Inc(FPos);
      Continue;
    end
    else
      Command := FLastCommand;
    case Command of
      'M':
        ParseMove(False);
      'm':
        ParseMove(True);
      'L':
        ParseLine(False);
      'l':
        ParseLine(True);
      'H':
        ParseHorizontal(False);
      'h':
        ParseHorizontal(True);
      'V':
        ParseVertical(False);
      'v':
        ParseVertical(True);
      'C':
        ParseCubic(False);
      'c':
        ParseCubic(True);
      'S':
        ParseSmoothCubic(False);
      's':
        ParseSmoothCubic(True);
      'Q':
        ParseQuadratic(False);
      'q':
        ParseQuadratic(True);
      'T':
        ParseSmoothQuadratic(False);
      't':
        ParseSmoothQuadratic(True);
      'A':
        ParseArc(False);
      'a':
        ParseArc(True);
      'Z', 'z':
        ParseClose;
    end;
  end;
end;

{ TSvgDocument }

constructor TSvgDocument.Create;
begin
  inherited;
  FElements := TObjectList<TSvgElement>.Create(True);
  FClipPaths := TObjectDictionary<string, TSvgPath>.Create([doOwnsValues]);
  FGradients := TObjectDictionary<string, TSvgGradient>.Create([doOwnsValues]);
  FPatterns := TObjectDictionary<string, TSvgPattern>.Create([doOwnsValues]);
  FMarkers := TObjectDictionary<string, TSvgMarker>.Create([doOwnsValues]);
  FSymbols := TObjectDictionary<string, TSvgSymbol>.Create([doOwnsValues]);
  FClassStyles := TStringList.Create;
  FClassStyles.NameValueSeparator := #1;
end;

destructor TSvgDocument.Destroy;
begin
  FClipPaths.Free;
  FGradients.Free;
  FPatterns.Free;
  FMarkers.Free;
  FSymbols.Free;
  FClassStyles.Free;
  FElements.Free;
  inherited;
end;

procedure TSvgDocument.Clear;
begin
  FElements.Clear;
  FClipPaths.Clear;
  FGradients.Clear;
  FPatterns.Clear;
  FMarkers.Clear;
  FSymbols.Clear;
  FClassStyles.Clear;
  FWidth := 0;
  FHeight := 0;
  FWidthLength.Value := 0;
  FWidthLength.units := sluNumber;
  FHeightLength.Value := 0;
  FHeightLength.units := sluNumber;
  FViewBox := TRectF.Empty;
  FHasViewBox := False;
end;

function TSvgDocument.ParseFloat(const S: string; Default: Single): Single;
begin
  var V := S.Trim.Replace(',', '.');
  if V.IsEmpty then
    Exit(Default);

  Result := InvariantFloat(V, Default);
end;

function TSvgDocument.Attr(const Node: IXMLNode; const Name: string; const Default: string): string;
begin
  if Node.HasAttribute(Name) then
    Result := Node.Attributes[Name]
  else
    Result := Default;
end;

function TSvgDocument.StyleAttr(const Node: IXMLNode; const Name: string; const Default: string): string;
begin
  Result := Attr(Node, Name, Default);
  var Style := Attr(Node, 'style');
  for var Declaration in Style.Split([';']) do
  begin
    var Separator := Declaration.IndexOf(':');
    if (Separator >= 0) and SameText(Declaration.Substring(0, Separator).Trim, Name) then
      Exit(Declaration.Substring(Separator + 1).Trim);
  end;
end;

function TSvgDocument.LengthAttr(const Node: IXMLNode; const Name: string; Reference: Single; Default: Single): Single;
begin
  var S := Attr(Node, Name);
  if S.IsEmpty then
    Exit(Default);

  Result := TSvgLength.Parse(S, Default).Resolve(Reference, 16);
end;

function TSvgDocument.ParseColor(const S: string; Default: TAlphaColor): TAlphaColor;
begin
  var V := S.Trim.ToLower;
  if V.IsEmpty then
    Exit(Default);
  if V = 'none' then
    Exit(0);

  if V.StartsWith('#') then
  begin
    var Hex := V.Substring(1);
    try
      var R, G, B, A: Integer;
      if Hex.Length = 3 then
      begin
        R := StrToInt('$' + Hex.Substring(0, 1)) * 17;
        G := StrToInt('$' + Hex.Substring(1, 1)) * 17;
        B := StrToInt('$' + Hex.Substring(2, 1)) * 17;
        A := 255;
      end
      else if Hex.Length = 6 then
      begin
        R := StrToInt('$' + Hex.Substring(0, 2));
        G := StrToInt('$' + Hex.Substring(2, 2));
        B := StrToInt('$' + Hex.Substring(4, 2));
        A := 255;
      end
      else if Hex.Length = 8 then
      begin
        R := StrToInt('$' + Hex.Substring(0, 2));
        G := StrToInt('$' + Hex.Substring(2, 2));
        B := StrToInt('$' + Hex.Substring(4, 2));
        A := StrToInt('$' + Hex.Substring(6, 2));
      end
      else
        Exit(Default);
      Exit(TAlphaColor(A) shl 24 or TAlphaColor(R) shl 16 or TAlphaColor(G) shl 8 or TAlphaColor(B));
    except
      Exit(Default);
    end;
  end;
  if V = 'black' then
    Exit(TAlphaColorRec.Black);
  if V = 'white' then
    Exit(TAlphaColorRec.White);
  if V = 'red' then
    Exit(TAlphaColorRec.Red);
  if V = 'green' then
    Exit(TAlphaColorRec.Green);
  if V = 'blue' then
    Exit(TAlphaColorRec.Blue);
  if V = 'yellow' then
    Exit(TAlphaColorRec.Yellow);
  if V = 'gray' then
    Exit(TAlphaColorRec.Gray);
  Result := Default;
end;

procedure TSvgDocument.ApplyStyleDeclaration(const Declaration: string; var Style: TSvgStyle);
begin
  for var Item in Declaration.Split([';']) do
  begin
    var P := Item.IndexOf(':');
    if P < 0 then
      Continue;

    var Name := Item.Substring(0, P).Trim.ToLower;
    var Value := Item.Substring(P + 1).Trim;
    if Name = 'fill' then
    begin
      Style.Fill.Enabled := not SameText(Value, 'none');
      Style.Fill.GradientID := GradientIDFromPaint(Value);
      Style.Fill.PatternID := Style.Fill.GradientID;
      if Style.Fill.Enabled and Style.Fill.GradientID.IsEmpty then
        Style.Fill.Color := ParseColor(Value, Style.Fill.Color);
    end
    else if Name = 'stroke' then
    begin
      Style.Stroke.Enabled := not SameText(Value, 'none');
      Style.Stroke.GradientID := GradientIDFromPaint(Value);
      if Style.Stroke.Enabled and Style.Stroke.GradientID.IsEmpty then
        Style.Stroke.Color := ParseColor(Value, Style.Stroke.Color);
    end
    else if Name = 'stroke-width' then
      Style.StrokeWidth := TSvgLength.Parse(Value, Style.StrokeWidth).Resolve(FWidth, 16)
    else if Name = 'opacity' then
      Style.Opacity := EnsureRange(ParseFloat(Value, 1), 0, 1)
    else if Name = 'fill-opacity' then
      Style.FillOpacity := EnsureRange(ParseFloat(Value, 1), 0, 1)
    else if Name = 'stroke-opacity' then
      Style.StrokeOpacity := EnsureRange(ParseFloat(Value, 1), 0, 1)
    else if Name = 'fill-rule' then
      if SameText(Value, 'evenodd') then
        Style.FillRule := sffEvenOdd
      else
        Style.FillRule := sffNonZero
    else if Name = 'display' then
      Style.Visible := not SameText(Value, 'none')
    else if Name = 'visibility' then
      Style.Visible := not SameText(Value, 'hidden')
    else if Name = 'stroke-linecap' then
      if SameText(Value, 'round') then
        Style.StrokeCap := TStrokeCap.Round
      else
        Style.StrokeCap := TStrokeCap.Flat
    else if Name = 'stroke-linejoin' then
      if SameText(Value, 'round') then
        Style.StrokeJoin := TStrokeJoin.Round
      else if SameText(Value, 'bevel') then
        Style.StrokeJoin := TStrokeJoin.Bevel
      else
        Style.StrokeJoin := TStrokeJoin.Miter
    else if Name = 'stroke-dashoffset' then
      Style.DashOffset := ParseFloat(Value)
    else if Name = 'stroke-dasharray' then
    begin
      var Numbers := TSvgNumberParser.Create(Value);
      var Number: Single;
      Style.DashArray := nil;
      while Numbers.ReadNumber(Number) do
        Style.DashArray := Style.DashArray + [Number];
    end
    else if Name = 'font-family' then
      Style.FontFamily := Value.Trim(['''', '"'])
    else if Name = 'font-size' then
      Style.FontSize := TSvgLength.Parse(Value, Style.FontSize).Resolve(16, Style.FontSize)
    else if Name = 'font-weight' then
    begin
      if SameText(Value, 'bold') or (ParseFloat(Value, 400) >= 600) then
        Include(Style.FontStyle, TFontStyle.fsBold)
      else
        Exclude(Style.FontStyle, TFontStyle.fsBold);
    end
    else if Name = 'font-style' then
    begin
      if SameText(Value, 'italic') or SameText(Value, 'oblique') then
        Include(Style.FontStyle, TFontStyle.fsItalic)
      else
        Exclude(Style.FontStyle, TFontStyle.fsItalic);
    end
    else if Name = 'text-decoration' then
    begin
      if Value.ToLower.Contains('underline') then
        Include(Style.FontStyle, TFontStyle.fsUnderline)
      else
        Exclude(Style.FontStyle, TFontStyle.fsUnderline);
      if Value.ToLower.Contains('line-through') then
        Include(Style.FontStyle, TFontStyle.fsStrikeOut)
      else
        Exclude(Style.FontStyle, TFontStyle.fsStrikeOut);
    end
    else if Name = 'text-anchor' then
      Style.TextAnchor := Value.ToLower;
  end;
end;

procedure TSvgDocument.ParseCss(const Text: string);
begin
  var Remaining := Text;
  while not Remaining.IsEmpty do
  begin
    var OpenBrace := Remaining.IndexOf('{');
    var CloseBrace := Remaining.IndexOf('}');
    if (OpenBrace < 0) or (CloseBrace < OpenBrace) then
      Exit;

    var Selector := Remaining.Substring(0, OpenBrace).Trim;
    var Declaration := Remaining.Substring(OpenBrace + 1, CloseBrace - OpenBrace - 1).Trim;
    for var Part in Selector.Split([',']) do
    begin
      var ClassName := Part.Trim;
      if ClassName.StartsWith('.') then
        FClassStyles.Values[ClassName.Substring(1)] := Declaration;
    end;
    Remaining := Remaining.Substring(CloseBrace + 1);
  end;
end;

function TSvgDocument.ParseStyle(const Node: IXMLNode; const Parent: TSvgStyle): TSvgStyle;
begin
  Result := Parent;
  for var ClassName in Attr(Node, 'class').Split([' ']) do
    if not ClassName.Trim.IsEmpty and (FClassStyles.Values[ClassName.Trim] <> '') then
      ApplyStyleDeclaration(FClassStyles.Values[ClassName.Trim], Result);
  var S := Attr(Node, 'display');
  if SameText(S.Trim, 'none') then
    Result.Visible := False;
  S := Attr(Node, 'visibility');
  if SameText(S.Trim, 'hidden') then
    Result.Visible := False;
  S := Attr(Node, 'fill');
  if not S.IsEmpty then
  begin
    Result.Fill.Enabled := not SameText(S.Trim, 'none');
    Result.Fill.GradientID := GradientIDFromPaint(S);
    Result.Fill.PatternID := Result.Fill.GradientID;
    if Result.Fill.Enabled and Result.Fill.GradientID.IsEmpty then
      Result.Fill.Color := ParseColor(S, Result.Fill.Color);
  end;
  S := Attr(Node, 'stroke');
  if not S.IsEmpty then
  begin
    Result.Stroke.Enabled := not SameText(S.Trim, 'none');
    Result.Stroke.GradientID := GradientIDFromPaint(S);
    if Result.Stroke.Enabled and Result.Stroke.GradientID.IsEmpty then
      Result.Stroke.Color := ParseColor(S, Result.Stroke.Color);
  end;
  S := Attr(Node, 'stroke-width');
  if not S.IsEmpty then
    Result.StrokeWidth := TSvgLength.Parse(S, Result.StrokeWidth).Resolve(FWidth, 16);
  S := Attr(Node, 'opacity');
  if not S.IsEmpty then
    Result.Opacity := EnsureRange(ParseFloat(S, 1), 0, 1);
  S := Attr(Node, 'fill-opacity');
  if not S.IsEmpty then
    Result.FillOpacity := EnsureRange(ParseFloat(S, 1), 0, 1);
  S := Attr(Node, 'stroke-opacity');
  if not S.IsEmpty then
    Result.StrokeOpacity := EnsureRange(ParseFloat(S, 1), 0, 1);
  S := Attr(Node, 'fill-rule');
  if SameText(S.Trim, 'evenodd') then
    Result.FillRule := sffEvenOdd
  else if SameText(S.Trim, 'nonzero') then
    Result.FillRule := sffNonZero;
  S := Attr(Node, 'stroke-linecap');
  if not S.IsEmpty then
    ApplyStyleDeclaration('stroke-linecap:' + S, Result);
  S := Attr(Node, 'stroke-linejoin');
  if not S.IsEmpty then
    ApplyStyleDeclaration('stroke-linejoin:' + S, Result);
  S := Attr(Node, 'stroke-dasharray');
  if not S.IsEmpty then
    ApplyStyleDeclaration('stroke-dasharray:' + S, Result);
  S := Attr(Node, 'stroke-dashoffset');
  if not S.IsEmpty then
    ApplyStyleDeclaration('stroke-dashoffset:' + S, Result);
  for var Name in ['font-family', 'font-size', 'font-weight', 'font-style', 'text-decoration', 'text-anchor'] do
  begin
    S := Attr(Node, Name);
    if not S.IsEmpty then
      ApplyStyleDeclaration(Name + ':' + S, Result);
  end;
  S := Attr(Node, 'style');
  if not S.IsEmpty then
  begin
    for var Declaration in S.Split([';']) do
    begin
      var P := Declaration.IndexOf(':');
      if P < 0 then
        Continue;

      var Name := Declaration.Substring(0, P).Trim.ToLower;
      var Value := Declaration.Substring(P + 1).Trim;
      if Name = 'fill' then
      begin
        Result.Fill.Enabled := not SameText(Value, 'none');
        Result.Fill.GradientID := GradientIDFromPaint(Value);
        Result.Fill.PatternID := Result.Fill.GradientID;
        if Result.Fill.Enabled and Result.Fill.GradientID.IsEmpty then
          Result.Fill.Color := ParseColor(Value, Result.Fill.Color);
      end
      else if Name = 'stroke' then
      begin
        Result.Stroke.Enabled := not SameText(Value, 'none');
        Result.Stroke.GradientID := GradientIDFromPaint(Value);
        if Result.Stroke.Enabled and Result.Stroke.GradientID.IsEmpty then
          Result.Stroke.Color := ParseColor(Value, Result.Stroke.Color);
      end
      else if Name = 'stroke-width' then
      begin
        Result.StrokeWidth := TSvgLength.Parse(Value, Result.StrokeWidth).Resolve(FWidth, 16);
      end
      else if Name = 'opacity' then
      begin
        Result.Opacity := EnsureRange(ParseFloat(Value, 1), 0, 1);
      end
      else if Name = 'fill-opacity' then
      begin
        Result.FillOpacity := EnsureRange(ParseFloat(Value, 1), 0, 1);
      end
      else if Name = 'stroke-opacity' then
      begin
        Result.StrokeOpacity := EnsureRange(ParseFloat(Value, 1), 0, 1);
      end
      else if Name = 'fill-rule' then
      begin
        if SameText(Value, 'evenodd') then
          Result.FillRule := sffEvenOdd
        else
          Result.FillRule := sffNonZero;
      end
      else if Name = 'display' then
      begin
        Result.Visible := not SameText(Value, 'none');
      end
      else if Name = 'visibility' then
      begin
        Result.Visible := not SameText(Value, 'hidden');
      end;
    end;
    ApplyStyleDeclaration(S, Result);
  end;
end;

function TSvgDocument.ParseTransform(const S: string): TSvgMatrix;
begin
  Result := TSvgMatrix.Identity;
  var P := 1;
  while P <= S.Length do
  begin
    while (P <= S.Length) and CharInSet(S[P], [' ', ',', #9, #10, #13]) do
      Inc(P);
    if P > S.Length then
      Break;

    var Start := P;
    while (P <= S.Length) and CharInSet(S[P], ['A'..'Z', 'a'..'z']) do
      Inc(P);
    var Name := S.Substring(Start - 1, P - Start).Trim.ToLower;
    while (P <= S.Length) and (S[P] <> '(') do
      Inc(P);
    if P > S.Length then
      Break;

    Inc(P);
    var ArgStart := P;
    var Depth := 1;
    while (P <= S.Length) and (Depth > 0) do
    begin
      if S[P] = '(' then
        Inc(Depth)
      else if S[P] = ')' then
        Dec(Depth);
      if Depth > 0 then
        Inc(P);
    end;
    var Args := S.Substring(ArgStart - 1, P - ArgStart);
    if (P <= S.Length) and (S[P] = ')') then
      Inc(P);

    var Parser := TSvgNumberParser.Create(Args);
    var Values: TArray<Single>;
    var Value: Single;
    while Parser.ReadNumber(Value) do
      Values := Values + [Value];
    var M := TSvgMatrix.Identity;
    if Name = 'translate' then
    begin
      if Length(Values) >= 1 then
      begin
        var X := Values[0];
        var Y := 0.0;
        if Length(Values) >= 2 then
          Y := Values[1];
        M := TSvgMatrix.Translation(X, Y);
      end;
    end
    else if Name = 'scale' then
    begin
      if Length(Values) >= 1 then
      begin
        var X := Values[0];
        var Y := X;
        if Length(Values) >= 2 then
          Y := Values[1];
        M := TSvgMatrix.Scaling(X, Y);
      end;
    end
    else if Name = 'rotate' then
    begin
      if Length(Values) >= 1 then
      begin
        var A := DegToRad(Values[0]);
        if Length(Values) >= 3 then
        begin
          var X := Values[1];
          var Y := Values[2];
          M :=
            TSvgMatrix.Translation(X, Y) *
            TSvgMatrix.Rotation(A) *
            TSvgMatrix.Translation(-X, -Y);
        end
        else
          M := TSvgMatrix.Rotation(A);
      end;
    end
    else if Name = 'skewx' then
    begin
      if Length(Values) >= 1 then
        M := TSvgMatrix.SkewX(DegToRad(Values[0]));
    end
    else if Name = 'skewy' then
    begin
      if Length(Values) >= 1 then
        M := TSvgMatrix.SkewY(DegToRad(Values[0]));
    end
    else if Name = 'matrix' then
    begin
      if Length(Values) >= 6 then
        M := TSvgMatrix.FromSvg(Values[0], Values[1], Values[2], Values[3], Values[4], Values[5]);
    end;
    Result := Result * M;
  end;
end;

procedure TSvgDocument.ParsePath(Node: IXMLNode; Element: TSvgElement);
begin
  var Parser := TSvgPathParser.Create(Element.Path);
  try
    Parser.Parse(Attr(Node, 'd'));
  finally
    Parser.Free;
  end;
end;

procedure TSvgDocument.ParseRect(Node: IXMLNode; Element: TSvgElement);
begin
  var X := LengthAttr(Node, 'x', FWidth);
  var Y := LengthAttr(Node, 'y', FHeight);
  var W := LengthAttr(Node, 'width', FWidth);
  var H := LengthAttr(Node, 'height', FHeight);
  if (W <= 0) or (H <= 0) then
    Exit;

  var RX := LengthAttr(Node, 'rx', W);
  var RY := LengthAttr(Node, 'ry', H);
  if RX <= 0 then
    RX := RY;
  if RY <= 0 then
    RY := RX;
  RX := Min(RX, W / 2);
  RY := Min(RY, H / 2);
  if (RX <= 0) or (RY <= 0) then
  begin
    Element.Path.MoveTo(PointF(X, Y));
    Element.Path.LineTo(PointF(X + W, Y));
    Element.Path.LineTo(PointF(X + W, Y + H));
    Element.Path.LineTo(PointF(X, Y + H));
    Element.Path.ClosePath;
    Exit;
  end;

  var K := SVG_KAPPA;
  Element.Path.MoveTo(PointF(X + RX, Y));
  Element.Path.LineTo(PointF(X + W - RX, Y));
  Element.Path.CurveTo(
    PointF(X + W - RX + K * RX, Y),
    PointF(X + W, Y + RY - K * RY),
    PointF(X + W, Y + RY)
  );
  Element.Path.LineTo(PointF(X + W, Y + H - RY));
  Element.Path.CurveTo(
    PointF(X + W, Y + H - RY + K * RY),
    PointF(X + W - RX + K * RX, Y + H),
    PointF(X + W - RX, Y + H)
  );
  Element.Path.LineTo(PointF(X + RX, Y + H));
  Element.Path.CurveTo(
    PointF(X + RX - K * RX, Y + H),
    PointF(X, Y + H - RY + K * RY),
    PointF(X, Y + H - RY)
  );
  Element.Path.LineTo(PointF(X, Y + RY));
  Element.Path.CurveTo(
    PointF(X, Y + RY - K * RY),
    PointF(X + RX - K * RX, Y),
    PointF(X + RX, Y)
  );
  Element.Path.ClosePath;
end;

procedure TSvgDocument.ParseCircle(Node: IXMLNode; Element: TSvgElement);
begin
  var CX := LengthAttr(Node, 'cx', FWidth);
  var CY := LengthAttr(Node, 'cy', FHeight);
  var R := LengthAttr(Node, 'r', Min(FWidth, FHeight));
  if R <= 0 then
    Exit;

  var K := SVG_KAPPA;
  Element.Path.MoveTo(PointF(CX + R, CY));
  Element.Path.CurveTo(
    PointF(CX + R, CY + K * R),
    PointF(CX + K * R, CY + R),
    PointF(CX, CY + R)
  );
  Element.Path.CurveTo(
    PointF(CX - K * R, CY + R),
    PointF(CX - R, CY + K * R),
    PointF(CX - R, CY)
  );
  Element.Path.CurveTo(
    PointF(CX - R, CY - K * R),
    PointF(CX - K * R, CY - R),
    PointF(CX, CY - R)
  );
  Element.Path.CurveTo(
    PointF(CX + K * R, CY - R),
    PointF(CX + R, CY - K * R),
    PointF(CX + R, CY)
  );
  Element.Path.ClosePath;
end;

procedure TSvgDocument.ParseEllipse(Node: IXMLNode; Element: TSvgElement);
begin
  var CX := LengthAttr(Node, 'cx', FWidth);
  var CY := LengthAttr(Node, 'cy', FHeight);
  var RX := LengthAttr(Node, 'rx', FWidth);
  var RY := LengthAttr(Node, 'ry', FHeight);
  if (RX <= 0) or (RY <= 0) then
    Exit;

  var K := SVG_KAPPA;
  Element.Path.MoveTo(PointF(CX + RX, CY));
  Element.Path.CurveTo(
    PointF(CX + RX, CY + K * RY),
    PointF(CX + K * RX, CY + RY),
    PointF(CX, CY + RY)
  );
  Element.Path.CurveTo(
    PointF(CX - K * RX, CY + RY),
    PointF(CX - RX, CY + K * RY),
    PointF(CX - RX, CY)
  );
  Element.Path.CurveTo(
    PointF(CX - RX, CY - K * RY),
    PointF(CX - K * RX, CY - RY),
    PointF(CX, CY - RY)
  );
  Element.Path.CurveTo(
    PointF(CX + K * RX, CY - RY),
    PointF(CX + RX, CY - K * RY),
    PointF(CX + RX, CY)
  );
  Element.Path.ClosePath;
end;

procedure TSvgDocument.ParseLine(Node: IXMLNode; Element: TSvgElement);
begin
  Element.Path.MoveTo(
    PointF(
      LengthAttr(Node, 'x1', FWidth),
      LengthAttr(Node, 'y1', FHeight)
    )
  );
  Element.Path.LineTo(
    PointF(
      LengthAttr(Node, 'x2', FWidth),
      LengthAttr(Node, 'y2', FHeight)
    )
  );
end;

procedure TSvgDocument.ParsePoly(Node: IXMLNode; Element: TSvgElement; Closed: Boolean);
begin
  var Parser := TSvgNumberParser.Create(Attr(Node, 'points'));
  var i := 0;
  var X, Y: Single;
  while Parser.ReadNumber(X) do
  begin
    if not Parser.ReadNumber(Y) then
      Break;

    var P := PointF(X, Y);
    if i = 0 then
      Element.Path.MoveTo(P)
    else
      Element.Path.LineTo(P);
    Inc(i);
  end;
  if Closed and (i > 0) then
    Element.Path.ClosePath;
end;

function TSvgDocument.TextContent(const Node: IXMLNode): string;
begin
  { IXMLNode.Text for an element may already contain the concatenated text of
    all descendants. Reading it while also traversing children duplicates text
    in mixed <text> / <tspan> content. Only text and CDATA nodes own text. }
  if Node.NodeType in [ntText, ntCData] then
    Exit(VarToStr(Node.NodeValue));

  for var i := 0 to Node.ChildNodes.Count - 1 do
    Result := Result + TextContent(Node.ChildNodes[i]);
end;

procedure TSvgDocument.ApplyTextStyleDeclaration(const Declaration: string; Element: TSvgElement);
begin
  for var Item in Declaration.Split([';']) do
  begin
    var Separator := Item.IndexOf(':');
    if Separator < 0 then
      Continue;

    var Name := Item.Substring(0, Separator).Trim.ToLower;
    var Value := Item.Substring(Separator + 1).Trim;
    if Name = 'font-family' then
      Element.FontFamily := Value.Trim(['''', '"'])
    else if Name = 'font-size' then
      Element.FontSize := TSvgLength.Parse(Value, Element.FontSize).Resolve(16, Element.FontSize)
    else if Name = 'font-weight' then
    begin
      if SameText(Value, 'bold') or (ParseFloat(Value, 400) >= 600) then
        Include(Element.FontStyle, TFontStyle.fsBold)
      else
        Exclude(Element.FontStyle, TFontStyle.fsBold);
    end
    else if Name = 'font-style' then
    begin
      if SameText(Value, 'italic') or SameText(Value, 'oblique') then
        Include(Element.FontStyle, TFontStyle.fsItalic)
      else
        Exclude(Element.FontStyle, TFontStyle.fsItalic);
    end
    else if Name = 'text-decoration' then
    begin
      if Value.ToLower.Contains('underline') then
        Include(Element.FontStyle, TFontStyle.fsUnderline)
      else
        Exclude(Element.FontStyle, TFontStyle.fsUnderline);
      if Value.ToLower.Contains('line-through') then
        Include(Element.FontStyle, TFontStyle.fsStrikeOut)
      else
        Exclude(Element.FontStyle, TFontStyle.fsStrikeOut);
    end;
  end;
end;

procedure TSvgDocument.ApplyTextStyle(const Node: IXMLNode; Element: TSvgElement);
begin
  { CSS class rules are applied before the element's inline attributes. }
  for var ClassName in Attr(Node, 'class').Split([' ']) do
    if not ClassName.Trim.IsEmpty and (FClassStyles.Values[ClassName.Trim] <> '') then
      ApplyTextStyleDeclaration(FClassStyles.Values[ClassName.Trim], Element);

  ApplyTextStyleDeclaration(Attr(Node, 'style'), Element);
  for var Name in ['font-family', 'font-size', 'font-weight', 'font-style', 'text-decoration'] do
    if Node.HasAttribute(Name) then
      ApplyTextStyleDeclaration(Name + ':' + Attr(Node, Name), Element);
end;

procedure TSvgDocument.ParseText(Node: IXMLNode; Element: TSvgElement);
begin
  Element.Text := TextContent(Node).Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
  while Element.Text.Contains('  ') do
    Element.Text := Element.Text.Replace('  ', ' ');
  Element.Text := Element.Text.Trim;
  Element.TextPosition := PointF(LengthAttr(Node, 'x', FWidth), LengthAttr(Node, 'y', FHeight));
  Element.FontFamily := Element.Style.FontFamily;
  Element.FontSize := Element.Style.FontSize;
  Element.FontStyle := Element.Style.FontStyle;
  ApplyTextStyle(Node, Element);
  Element.TextAnchor := Element.Style.TextAnchor;

  var HasTSpan := False;
  for var i := 0 to Node.ChildNodes.Count - 1 do
    HasTSpan := HasTSpan or SameText(Node.ChildNodes[i].NodeName, 'tspan');
  if not HasTSpan then
    Exit;

  Element.TextRuns.Clear;
  var PendingSpace := False;
  var ParsedText := '';
  for var i := 0 to Node.ChildNodes.Count - 1 do
  begin
    var Child := Node.ChildNodes[i];
    var RawText := TextContent(Child).Replace(#13, ' ').Replace(#10, ' ').Replace(#9, ' ');
    while RawText.Contains('  ') do
      RawText := RawText.Replace('  ', ' ');
    { Some XML DOM providers return each mixed-content child as the complete
      text accumulated up to that child. Keep only its not-yet-parsed suffix. }
    var ComparableText := RawText.Trim;
    if not ParsedText.IsEmpty and ComparableText.StartsWith(ParsedText) then
      RawText := ComparableText.Substring(ParsedText.Length);
    if RawText.Trim.IsEmpty then
    begin
      PendingSpace := PendingSpace or not RawText.IsEmpty;
      Continue;
    end;

    var Run := TSvgTextRun.Create;
    Run.Text := RawText.Trim;
    if (Element.TextRuns.Count > 0) and
      (PendingSpace or RawText.StartsWith(' ')) then
      Run.Text := ' ' + Run.Text;
    Run.Style := Element.Style;
    Run.FontFamily := Element.FontFamily;
    Run.FontSize := Element.FontSize;
    Run.FontStyle := Element.FontStyle;
    if SameText(Child.NodeName, 'tspan') then
    begin
      Run.Style := ParseStyle(Child, Run.Style);
      var ParentFontFamily := Element.FontFamily;
      var ParentFontSize := Element.FontSize;
      var ParentFontStyle := Element.FontStyle;
      Element.FontFamily := Run.Style.FontFamily;
      Element.FontSize := Run.Style.FontSize;
      Element.FontStyle := Run.Style.FontStyle;
      ApplyTextStyle(Child, Element);
      Run.FontFamily := Element.FontFamily;
      Run.FontSize := Element.FontSize;
      Run.FontStyle := Element.FontStyle;
      { A tspan style must not leak to its siblings or to the parent text. }
      Element.FontFamily := ParentFontFamily;
      Element.FontSize := ParentFontSize;
      Element.FontStyle := ParentFontStyle;
    end;
    Element.TextRuns.Add(Run);
    if Run.Text.StartsWith(' ') then
      ParsedText := ParsedText + ' ';
    ParsedText := ParsedText + Run.Text.Trim;
    PendingSpace := RawText.EndsWith(' ');
  end;
  Element.Text := '';
end;

procedure TSvgDocument.ParseShape(const Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle; const Dest: TObjectList<TSvgElement>);
begin
  var Name := Node.NodeName.ToLower;
  if Name = 'clippath' then
  begin
    ParseClipPath(Node, Matrix);
    Exit;
  end;
  if (Name <> 'path') and not ContainsString(['rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'text'], Name) then
    Exit;

  var Element := TSvgElement.Create;
  Element.Name := Name;
  Element.Matrix := Matrix;
  Element.Style := Style;
  Element.ClipID := Attr(Node, 'clip-path');
  Element.MarkerStartID := GradientIDFromPaint(Attr(Node, 'marker-start'));
  Element.MarkerMidID := GradientIDFromPaint(Attr(Node, 'marker-mid'));
  Element.MarkerEndID := GradientIDFromPaint(Attr(Node, 'marker-end'));
  if Name = 'path' then
    ParsePath(Node, Element)
  else if Name = 'rect' then
    ParseRect(Node, Element)
  else if Name = 'circle' then
    ParseCircle(Node, Element)
  else if Name = 'ellipse' then
    ParseEllipse(Node, Element)
  else if Name = 'line' then
    ParseLine(Node, Element)
  else if Name = 'polyline' then
    ParsePoly(Node, Element, False)
  else if Name = 'polygon' then
    ParsePoly(Node, Element, True);
  if Name = 'text' then
    ParseText(Node, Element);
  Dest.Add(Element);
end;

procedure TSvgDocument.ParseMarker(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;

  var Marker := TSvgMarker.Create;
  try
    Marker.Width := LengthAttr(Node, 'markerWidth', FWidth, 3);
    Marker.Height := LengthAttr(Node, 'markerHeight', FHeight, 3);
    Marker.RefX := LengthAttr(Node, 'refX', Marker.Width);
    Marker.RefY := LengthAttr(Node, 'refY', Marker.Height);
    Marker.Orient := Attr(Node, 'orient', '0').Trim.ToLower;
    Marker.UnitsStrokeWidth := not SameText(Attr(Node, 'markerUnits', 'strokeWidth'), 'userSpaceOnUse');

    for var i := 0 to Node.ChildNodes.Count - 1 do
    begin
      var Child := Node.ChildNodes[i];
      var Element := TSvgElement.Create;
      try
        var Name := Child.NodeName.ToLower;
        Element.Name := Name;
        Element.Matrix := Matrix * ParseTransform(Attr(Child, 'transform'));
        Element.Style := ParseStyle(Child, Style);
        if Name = 'path' then
          ParsePath(Child, Element)
        else if Name = 'rect' then
          ParseRect(Child, Element)
        else if Name = 'circle' then
          ParseCircle(Child, Element)
        else if Name = 'ellipse' then
          ParseEllipse(Child, Element)
        else if Name = 'line' then
          ParseLine(Child, Element)
        else if Name = 'polyline' then
          ParsePoly(Child, Element, False)
        else if Name = 'polygon' then
          ParsePoly(Child, Element, True)
        else
          Continue;

        if Marker.Path.Commands.Count = 0 then
        begin
          for var Command in Element.Path.Commands do
            Marker.Path.Commands.Add(Command);
          Marker.Style := Element.Style;
          Marker.Matrix := Element.Matrix;
        end;
      finally
        Element.Free;
      end;
    end;
    if Marker.Path.Commands.Count > 0 then
    begin
      FMarkers.AddOrSetValue(ID, Marker);
      Marker := nil;
    end;
  finally
    Marker.Free;
  end;
end;

procedure TSvgDocument.ParseSymbol(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;

  var Symbol := TSvgSymbol.Create;
  try
    var ViewBoxText := Attr(Node, 'viewBox');
    if not ViewBoxText.IsEmpty then
    begin
      var Numbers := TSvgNumberParser.Create(ViewBoxText);
      var X, Y, W, H: Single;
      if Numbers.ReadNumber(X) and Numbers.ReadNumber(Y) and
        Numbers.ReadNumber(W) and Numbers.ReadNumber(H) and (W > 0) and (H > 0) then
      begin
        Symbol.ViewBox := RectF(X, Y, X + W, Y + H);
        Symbol.HasViewBox := True;
      end;
    end;

    for var i := 0 to Node.ChildNodes.Count - 1 do
    begin
      var Child := Node.ChildNodes[i];
      var Element := TSvgElement.Create;
      try
        var Name := Child.NodeName.ToLower;
        Element.Name := Name;
        Element.Matrix := Matrix * ParseTransform(Attr(Child, 'transform'));
        Element.Style := ParseStyle(Child, Style);
        if Name = 'path' then
          ParsePath(Child, Element)
        else if Name = 'rect' then
          ParseRect(Child, Element)
        else if Name = 'circle' then
          ParseCircle(Child, Element)
        else if Name = 'ellipse' then
          ParseEllipse(Child, Element)
        else if Name = 'line' then
          ParseLine(Child, Element)
        else if Name = 'polyline' then
          ParsePoly(Child, Element, False)
        else if Name = 'polygon' then
          ParsePoly(Child, Element, True)
        else
          Continue;

        if Symbol.Path.Commands.Count = 0 then
        begin
          for var Command in Element.Path.Commands do
            Symbol.Path.Commands.Add(Command);
          Symbol.Style := Element.Style;
          Symbol.Matrix := Element.Matrix;
        end;
      finally
        Element.Free;
      end;
    end;
    if Symbol.Path.Commands.Count > 0 then
    begin
      FSymbols.AddOrSetValue(ID, Symbol);
      Symbol := nil;
    end;
  finally
    Symbol.Free;
  end;
end;

procedure TSvgDocument.ParseUse(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
begin
  var Reference := Attr(Node, 'href').Trim;
  if not Reference.StartsWith('#') then
    Exit;
  Reference := Reference.Substring(1);
  var Symbol: TSvgSymbol;
  if not FSymbols.TryGetValue(Reference, Symbol) then
    Exit;

  var Element := TSvgElement.Create;
  Element.Name := 'use';
  Element.Style := Symbol.Style;
  Element.Matrix := Matrix * TSvgMatrix.Translation(
    LengthAttr(Node, 'x', FWidth), LengthAttr(Node, 'y', FHeight));
  if Symbol.HasViewBox then
  begin
    var Width := LengthAttr(Node, 'width', FWidth, Symbol.ViewBox.Width);
    var Height := LengthAttr(Node, 'height', FHeight, Symbol.ViewBox.Height);
    if (Width <= 0) or (Height <= 0) then
    begin
      Element.Free;
      Exit;
    end;
    Element.Matrix := Element.Matrix * TSvgMatrix.Scaling(
      Width / Symbol.ViewBox.Width, Height / Symbol.ViewBox.Height) *
      TSvgMatrix.Translation(-Symbol.ViewBox.Left, -Symbol.ViewBox.Top);
  end;
  Element.Matrix := Element.Matrix * Symbol.Matrix;
  for var Command in Symbol.Path.Commands do
    Element.Path.Commands.Add(Command);
  FElements.Add(Element);
end;

procedure TSvgDocument.ParseClipPath(Node: IXMLNode; const Matrix: TSvgMatrix);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;
  var Path := TSvgPath.Create;
  try
    for var i := 0 to Node.ChildNodes.Count - 1 do
    begin
      var Child := Node.ChildNodes[i];
      var Temp := TSvgElement.Create;
      try
        var Name := Child.NodeName.ToLower;
        if Name = 'path' then
          ParsePath(Child, Temp)
        else if Name = 'rect' then
          ParseRect(Child, Temp)
        else if Name = 'circle' then
          ParseCircle(Child, Temp)
        else if Name = 'ellipse' then
          ParseEllipse(Child, Temp)
        else
          Continue;

        for var Command in Temp.Path.Commands do
          Path.Commands.Add(Command);
      finally
        Temp.Free;
      end;
    end;
    FClipPaths.AddOrSetValue(ID, Path);
    Path := nil;
  finally
    Path.Free;
  end;
end;

procedure TSvgDocument.ParseLinearGradient(Node: IXMLNode);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;

  var Definition := TSvgGradient.Create;
  try
    Definition.UnitsUserSpace := SameText(Attr(Node, 'gradientUnits'), 'userSpaceOnUse');
    if SameText(Attr(Node, 'spreadMethod'), 'repeat') then
      Definition.Spread := sgsRepeat
    else if SameText(Attr(Node, 'spreadMethod'), 'reflect') then
      Definition.Spread := sgsReflect;
    var UnitWidth := 1.0;
    var UnitHeight := 1.0;
    if Definition.UnitsUserSpace then
    begin
      UnitWidth := FWidth;
      UnitHeight := FHeight;
    end;
    Definition.X1 := TSvgLength.Parse(Attr(Node, 'x1', '0%')).Resolve(UnitWidth, 16);
    Definition.Y1 := TSvgLength.Parse(Attr(Node, 'y1', '0%')).Resolve(UnitHeight, 16);
    Definition.X2 := TSvgLength.Parse(Attr(Node, 'x2', '100%')).Resolve(UnitWidth, 16);
    Definition.Y2 := TSvgLength.Parse(Attr(Node, 'y2', '0%')).Resolve(UnitHeight, 16);
    Definition.Matrix := ParseTransform(Attr(Node, 'gradientTransform'));
    for var i := 0 to Node.ChildNodes.Count - 1 do
    begin
      var Stop := Node.ChildNodes[i];
      if not SameText(Stop.NodeName, 'stop') then
        Continue;

      var Offset := EnsureRange(TSvgLength.Parse(StyleAttr(Stop, 'offset', '0')).Resolve(1, 16), 0, 1);
      var Color := ParseColor(StyleAttr(Stop, 'stop-color', 'black'), TAlphaColorRec.Black);
      var Opacity := EnsureRange(ParseFloat(StyleAttr(Stop, 'stop-opacity', '1'), 1), 0, 1);
      var Point := TGradientPoint(Definition.Gradient.Points.Add);
      Point.Offset := Offset;
      Point.Color := AlphaColorWithOpacity(Color, Opacity);
    end;
    if Definition.Gradient.Points.Count > 0 then
    begin
      FGradients.AddOrSetValue(ID, Definition);
      Definition := nil;
    end;
  finally
    Definition.Free;
  end;
end;

procedure TSvgDocument.ParseRadialGradient(Node: IXMLNode);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;

  var Definition := TSvgGradient.Create;
  try
    Definition.Kind := sgRadial;
    Definition.UnitsUserSpace := SameText(Attr(Node, 'gradientUnits'), 'userSpaceOnUse');
    if SameText(Attr(Node, 'spreadMethod'), 'repeat') then
      Definition.Spread := sgsRepeat
    else if SameText(Attr(Node, 'spreadMethod'), 'reflect') then
      Definition.Spread := sgsReflect;
    var UnitWidth := 1.0;
    var UnitHeight := 1.0;
    if Definition.UnitsUserSpace then
    begin
      UnitWidth := FWidth;
      UnitHeight := FHeight;
    end;
    Definition.X1 := TSvgLength.Parse(Attr(Node, 'cx', '50%')).Resolve(UnitWidth, 16);
    Definition.Y1 := TSvgLength.Parse(Attr(Node, 'cy', '50%')).Resolve(UnitHeight, 16);
    Definition.X2 := TSvgLength.Parse(Attr(Node, 'fx', Attr(Node, 'cx', '50%'))).Resolve(UnitWidth, 16);
    Definition.Y2 := TSvgLength.Parse(Attr(Node, 'fy', Attr(Node, 'cy', '50%'))).Resolve(UnitHeight, 16);
    Definition.Radius := TSvgLength.Parse(Attr(Node, 'r', '50%')).Resolve(Min(UnitWidth, UnitHeight), 16);
    Definition.Matrix := ParseTransform(Attr(Node, 'gradientTransform'));
    for var i := 0 to Node.ChildNodes.Count - 1 do
    begin
      var Stop := Node.ChildNodes[i];
      if not SameText(Stop.NodeName, 'stop') then
        Continue;

      var Offset := EnsureRange(TSvgLength.Parse(StyleAttr(Stop, 'offset', '0')).Resolve(1, 16), 0, 1);
      var Color := ParseColor(StyleAttr(Stop, 'stop-color', 'black'), TAlphaColorRec.Black);
      var Opacity := EnsureRange(ParseFloat(StyleAttr(Stop, 'stop-opacity', '1'), 1), 0, 1);
      var Point := TGradientPoint(Definition.Gradient.Points.Add);
      Point.Offset := Offset;
      Point.Color := AlphaColorWithOpacity(Color, Opacity);
    end;
    if Definition.Gradient.Points.Count > 0 then
    begin
      FGradients.AddOrSetValue(ID, Definition);
      Definition := nil;
    end;
  finally
    Definition.Free;
  end;
end;

procedure TSvgDocument.ParsePattern(Node: IXMLNode; const Matrix: TSvgMatrix; const Style: TSvgStyle);
begin
  var ID := Attr(Node, 'id');
  if ID.IsEmpty then
    Exit;

  var Definition := TSvgPattern.Create;
  try
    Definition.UnitsUserSpace := SameText(Attr(Node, 'patternUnits'), 'userSpaceOnUse');
    var ReferenceWidth := FWidth;
    var ReferenceHeight := FHeight;
    if not Definition.UnitsUserSpace then
    begin
      ReferenceWidth := 1;
      ReferenceHeight := 1;
    end;
    Definition.Width := LengthAttr(Node, 'width', ReferenceWidth);
    Definition.Height := LengthAttr(Node, 'height', ReferenceHeight);
    if (Definition.Width <= 0) or (Definition.Height <= 0) then
      Exit;
    Definition.Matrix := Matrix * ParseTransform(Attr(Node, 'patternTransform'));
    var SavedWidth := FWidth;
    var SavedHeight := FHeight;
    if not Definition.UnitsUserSpace then
    begin
      // Pattern content in objectBoundingBox units is normalized to 0..1.
      FWidth := 1;
      FHeight := 1;
    end;
    try
      for var i := 0 to Node.ChildNodes.Count - 1 do
      begin
        var Child := Node.ChildNodes[i];
        var ChildStyle := ParseStyle(Child, Style);
        var ChildMatrix := ParseTransform(Attr(Child, 'transform'));
        ParseShape(Child, ChildMatrix, ChildStyle, Definition.Elements);
      end;
    finally
      FWidth := SavedWidth;
      FHeight := SavedHeight;
    end;
    if Definition.Elements.Count > 0 then
    begin
      FPatterns.AddOrSetValue(ID, Definition);
      Definition := nil;
    end;
  finally
    Definition.Free;
  end;
end;

procedure TSvgDocument.ParseNode(const Node: IXMLNode; const ParentMatrix: TSvgMatrix; const ParentStyle: TSvgStyle);
begin
  var Style := ParseStyle(Node, ParentStyle);
  var Matrix := ParentMatrix * ParseTransform(Attr(Node, 'transform'));
  var Name := Node.NodeName.ToLower;
  if Name = 'lineargradient' then
  begin
    ParseLinearGradient(Node);
    Exit;
  end;
  if Name = 'radialgradient' then
  begin
    ParseRadialGradient(Node);
    Exit;
  end;
  if Name = 'pattern' then
  begin
    ParsePattern(Node, Matrix, Style);
    Exit;
  end;
  if Name = 'marker' then
  begin
    ParseMarker(Node, Matrix, Style);
    Exit;
  end;
  if Name = 'symbol' then
  begin
    ParseSymbol(Node, Matrix, Style);
    Exit;
  end;
  if Name = 'use' then
  begin
    ParseUse(Node, Matrix, Style);
    Exit;
  end;
  if Name = 'style' then
  begin
    ParseCss(Node.Text);
    Exit;
  end;
  if Name = 'defs' then
  begin
    for var i := 0 to Node.ChildNodes.Count - 1 do
      if SameText(Node.ChildNodes[i].NodeName, 'clippath') or
        SameText(Node.ChildNodes[i].NodeName, 'lineargradient') or
        SameText(Node.ChildNodes[i].NodeName, 'radialgradient') or
        SameText(Node.ChildNodes[i].NodeName, 'pattern') or
        SameText(Node.ChildNodes[i].NodeName, 'marker') or
        SameText(Node.ChildNodes[i].NodeName, 'symbol') then
        ParseNode(Node.ChildNodes[i], Matrix, Style);
    Exit;
  end;
  if (Name = 'svg') or (Name = 'g') then
  begin
    if Name = 'svg' then
    begin
      FWidthLength := TSvgLength.Parse(Attr(Node, 'width'), 0);
      FHeightLength := TSvgLength.Parse(Attr(Node, 'height'), 0);
      FWidth := FWidthLength.Resolve(0, 16);
      FHeight := FHeightLength.Resolve(0, 16);
      var ViewBox := Attr(Node, 'viewBox');
      if not ViewBox.IsEmpty then
      begin
        var Parser := TSvgNumberParser.Create(ViewBox);
        var X, Y, W, H: Single;
        if Parser.ReadNumber(X) and Parser.ReadNumber(Y) and Parser.ReadNumber(W) and Parser.ReadNumber(H) then
        begin
          if (W > 0) and (H > 0) then
          begin
            FViewBox := RectF(X, Y, X + W, Y + H);
            FHasViewBox := True;
          end;
        end;
      end;
    end;
    for var i := 0 to Node.ChildNodes.Count - 1 do
      ParseNode(Node.ChildNodes[i], Matrix, Style);
    Exit;
  end;
  ParseShape(Node, Matrix, Style, FElements);
end;

procedure TSvgDocument.LoadFromString(const S: string);
begin
  Clear;
  if S.Trim.IsEmpty then
    Exit;

  var Xml: IXMLDocument := TXMLDocument.Create(nil);
  Xml.LoadFromXML(S);
  if Xml.DocumentElement = nil then
    Exit;

  ParseNode(Xml.DocumentElement, TSvgMatrix.Identity, TSvgStyle.Default);
end;

end.

