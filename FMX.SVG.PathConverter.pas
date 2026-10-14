unit FMX.SVG.PathConverter;

interface

uses
  System.SysUtils, System.Types, System.Math, System.Classes,
  System.Math.Vectors, System.Generics.Collections, Xml.XMLDoc, Xml.XMLIntf,
  FMX.Types, FMX.Graphics;

function ConvertSVGToPath(const SVG: string): string;

implementation

type
  TMatrix = record
    A, B, C, D, E, F: Single;

    class function Identity: TMatrix; static;
    class function Translation(const X, Y: Single): TMatrix; static;
    class function Scaling(const X, Y: Single): TMatrix; static;
    class function Rotation(const Angle: Single): TMatrix; static;
    class function SkewX(const Angle: Single): TMatrix; static;
    class function SkewY(const Angle: Single): TMatrix; static;

    class function Create(const A, B, C, D, E, F: Single): TMatrix; static;

    class operator Multiply(const L, R: TMatrix): TMatrix;

    function TransformPoint(const P: TPointF): TPointF;
  end;

  TFloatArray = array of Single;

  TPathParser = class
  private
    FData: TPathData;
    FMatrix: TMatrix;
    FSource: string;
    FPos: Integer;
    FLength: Integer;
    FCurrent: TPointF;
    FStartPoint: TPointF;
    FLastCubicControl: TPointF;
    FHasLastCubicControl: Boolean;
    FLastQuadControl: TPointF;
    FHasLastQuadControl: Boolean;
    procedure SkipSeparators;
    function PeekChar: Char;
    function ReadCommand: Char;
    function ReadNumber(out Value: Single): Boolean;
    function IsCommandChar(C: Char): Boolean;
    function TransformPoint(const P: TPointF): TPointF;
    procedure MoveTo(const P: TPointF);
    procedure LineTo(const P: TPointF);
    procedure CurveTo(const C1, C2, P: TPointF);
    procedure ClosePath;
    procedure ArcTo(const P1: TPointF; RX, RY, Rotation: Single; LargeArc, Sweep: Boolean; const P2: TPointF);
    procedure ParsePathData;
    procedure ParseCommand(Cmd: Char);
  public
    constructor Create(const Matrix: TMatrix);
    destructor Destroy; override;
    function Parse(const S: string): string;
  end;

  TSvgConverter = class
  private
    FPath: TPathData;
    procedure ParseNode(const Node: IXMLNode; const ParentMatrix: TMatrix);
    procedure ParsePath(const Node: IXMLNode; const Matrix: TMatrix);
    procedure ParseRect(const Node: IXMLNode; const Matrix: TMatrix);
    procedure ParseCircle(const Node: IXMLNode; const Matrix: TMatrix);
    procedure ParseEllipse(const Node: IXMLNode; const Matrix: TMatrix);
    procedure ParseLine(const Node: IXMLNode; const Matrix: TMatrix);
    procedure ParsePoly(const Node: IXMLNode; const Matrix: TMatrix; Closed: Boolean);
    function Attr(const Node: IXMLNode; const Name: string; Default: Single = 0): Single;
    function AttrString(const Node: IXMLNode; const Name: string; const Default: string = ''): string;
    function ParseTransform(const S: string): TMatrix;
    procedure AddRoundedRect(X, Y, W, H, RX, RY: Single; const Matrix: TMatrix);
    procedure AddEllipse(CX, CY, RX, RY: Single; const Matrix: TMatrix);
  public
    constructor Create;
    destructor Destroy; override;
    function Convert(const SVG: string): string;
  end;

function ConvertSVGToPath(const SVG: string): string;
var
  Converter: TSvgConverter;
begin
  Converter := TSvgConverter.Create;
  try
    Result := Converter.Convert(SVG);
  finally
    Converter.Free;
  end;
end;

function InvariantFloat(const S: string; Default: Single = 0): Single;
var
  T: string;
begin
  T := Trim(S);
  if T = '' then
    Exit(Default);
  T := StringReplace(T, ',', '.', [rfReplaceAll]);
  Result := StrToFloatDef(T, Default, TFormatSettings.Invariant);
end;

function GetAttributeFloat(const Node: IXMLNode; const Name: string; Default: Single): Single;
begin
  if not Node.HasAttribute(Name) then
    Exit(Default);

  try
    Result := InvariantFloat(Node.Attributes[Name]);
  except
    Result := 0;
  end;
end;

function GetAttributeString(const Node: IXMLNode; const Name: string; const Default: string): string;
begin
  if Node.HasAttribute(Name) then
    Result := Node.Attributes[Name]
  else
    Result := Default;
end;

function MatrixIdentity: TMatrix;
begin
  Result := TMatrix.Identity;
end;

{ TPathParser }

constructor TPathParser.Create(const Matrix: TMatrix);
begin
  inherited Create;

  FData := TPathData.Create;
  FMatrix := Matrix;

  FCurrent := TPointF.Zero;
  FStartPoint := TPointF.Zero;

  FLastCubicControl := TPointF.Zero;
  FLastQuadControl := TPointF.Zero;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;
end;

destructor TPathParser.Destroy;
begin
  FData.Free;
  inherited;
end;

function TPathParser.TransformPoint(const P: TPointF): TPointF;
begin
  Result := FMatrix.TransformPoint(P);
end;

procedure TPathParser.MoveTo(const P: TPointF);
begin
  FData.MoveTo(TransformPoint(P));

  FCurrent := P;
  FStartPoint := P;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;
end;

procedure TPathParser.LineTo(const P: TPointF);
begin
  FData.LineTo(TransformPoint(P));

  FCurrent := P;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;
end;

procedure TPathParser.CurveTo(const C1, C2, P: TPointF);
begin
  FData.CurveTo(
    TransformPoint(C1),
    TransformPoint(C2),
    TransformPoint(P)
  );

  FCurrent := P;

  FLastCubicControl := C2;
  FHasLastCubicControl := True;

  FHasLastQuadControl := False;
end;

procedure TPathParser.ClosePath;
begin
  FData.ClosePath;

  FCurrent := FStartPoint;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;
end;

procedure TPathParser.SkipSeparators;
begin
  while FPos <= FLength do
  begin
    if CharInSet(
      FSource[FPos],
      [' ', #9, #10, #13, ',']
    ) then
      Inc(FPos)
    else
      Break;
  end;
end;

function TPathParser.PeekChar: Char;
begin
  if FPos <= FLength then
    Result := FSource[FPos]
  else
    Result := #0;
end;

function TPathParser.IsCommandChar(C: Char): Boolean;
begin
  Result := CharInSet(
    C,
    [
      'M', 'm',
      'L', 'l',
      'H', 'h',
      'V', 'v',
      'C', 'c',
      'S', 's',
      'Q', 'q',
      'T', 't',
      'A', 'a',
      'Z', 'z'
    ]
  );
end;

function TPathParser.ReadCommand: Char;
begin
  SkipSeparators;

  if (FPos <= FLength) and IsCommandChar(FSource[FPos]) then
  begin
    Result := FSource[FPos];
    Inc(FPos);
  end
  else
    Result := #0;
end;

function TPathParser.ReadNumber(out Value: Single): Boolean;
var
  Start: Integer;
  HasDigits: Boolean;
  S: string;
begin
  SkipSeparators;

  Result := False;
  Value := 0;

  if FPos > FLength then
    Exit;

  Start := FPos;

  if CharInSet(FSource[FPos], ['+', '-']) then
    Inc(FPos);

  HasDigits := False;

  while (FPos <= FLength) and CharInSet(FSource[FPos], ['0'..'9']) do
  begin
    HasDigits := True;
    Inc(FPos);
  end;

  if (FPos <= FLength) and (FSource[FPos] = '.') then
  begin
    Inc(FPos);

    while (FPos <= FLength) and CharInSet(FSource[FPos], ['0'..'9']) do
    begin
      HasDigits := True;
      Inc(FPos);
    end;
  end;

  if not HasDigits then
  begin
    FPos := Start;
    Exit;
  end;

  if (FPos <= FLength) and CharInSet(FSource[FPos], ['e', 'E']) then
  begin
    Inc(FPos);
    if (FPos <= FLength) and CharInSet(FSource[FPos], ['+', '-']) then
      Inc(FPos);
    while (FPos <= FLength) and CharInSet(FSource[FPos], ['0'..'9']) do
      Inc(FPos);
  end;

  S := Copy(FSource, Start, FPos - Start);
  Value := InvariantFloat(S);
  Result := True;
end;

procedure TPathParser.ArcTo(const P1: TPointF; RX, RY, Rotation: Single; LargeArc, Sweep: Boolean; const P2: TPointF);
const
  Epsilon = 1E-6;
var
  Phi: Single;
  CosPhi, SinPhi: Single;
  X1p, Y1p: Single;
  Lambda: Single;
  Rx2, Ry2: Single;
  Numerator: Single;
  Denominator: Single;
  Coeff: Single;
  Cxp, Cyp: Single;
  Cx, Cy: Single;
  Theta1: Single;
  DeltaTheta: Single;
  Segments: Integer;
  I: Integer;
  T1, T2: Single;
  Alpha: Single;
  C1, C2: TPointF;

  function VectorAngle(UX, UY, VX, VY: Single): Single;
  var
    Dot, Len: Single;
  begin
    Dot := UX * VX + UY * VY;
    Len := Sqrt((UX * UX + UY * UY) * (VX * VX + VY * VY));

    if Len < Epsilon then
      Exit(0);

    Dot := EnsureRange(Dot / Len, -1, 1);

    Result := ArcCos(Dot);

    if UX * VY - UY * VX < 0 then
      Result := -Result;
  end;

  function EllipsePoint(Theta: Single): TPointF;
  var
    C, S: Single;
    X, Y: Single;
  begin
    C := Cos(Theta);
    S := Sin(Theta);

    X := RX * C;
    Y := RY * S;

    Result.X :=
      Cx + CosPhi * X - SinPhi * Y;

    Result.Y :=
      Cy + SinPhi * X + CosPhi * Y;
  end;

  procedure AddSegment(A0, A1: Single);
  var
    P0, P3: TPointF;
    D0X, D0Y: Single;
    D1X, D1Y: Single;
  begin
    Alpha := (4 / 3) * Tan((A1 - A0) / 4);

    P0 := EllipsePoint(A0);
    P3 := EllipsePoint(A1);

    D0X := -RX * Sin(A0);
    D0Y := RY * Cos(A0);

    C1.X := P0.X + Alpha * (CosPhi * D0X - SinPhi * D0Y);
    C1.Y := P0.Y + Alpha * (SinPhi * D0X + CosPhi * D0Y);

    D1X := -RX * Sin(A1);
    D1Y := RY * Cos(A1);

    C2.X := P3.X - Alpha * (CosPhi * D1X - SinPhi * D1Y);
    C2.Y := P3.Y - Alpha * (SinPhi * D1X + CosPhi * D1Y);

    CurveTo(C1, C2, P3);
  end;

begin
  { Degenerate cases }

  if SameValue(P1.X, P2.X, Epsilon) and SameValue(P1.Y, P2.Y, Epsilon) then
    Exit;

  RX := Abs(RX);
  RY := Abs(RY);

  if (RX < Epsilon) or (RY < Epsilon) then
  begin
    LineTo(P2);
    Exit;
  end;

  Phi := DegToRad(Rotation);

  CosPhi := Cos(Phi);
  SinPhi := Sin(Phi);

  { Transform start/end into ellipse coordinate system }

  X1p :=
    CosPhi * (P1.X - P2.X) / 2 +
    SinPhi * (P1.Y - P2.Y) / 2;

  Y1p :=
    -SinPhi * (P1.X - P2.X) / 2 +
    CosPhi * (P1.Y - P2.Y) / 2;

  { Correct radii if the ellipse is too small }

  Lambda := (X1p * X1p) / (RX * RX) + (Y1p * Y1p) / (RY * RY);

  if Lambda > 1 then
  begin
    Lambda := Sqrt(Lambda);

    RX := RX * Lambda;
    RY := RY * Lambda;
  end;

  Rx2 := RX * RX;
  Ry2 := RY * RY;

  Numerator := Rx2 * Ry2 - Rx2 * Y1p * Y1p - Ry2 * X1p * X1p;
  Denominator := Rx2 * Y1p * Y1p + Ry2 * X1p * X1p;

  if Abs(Denominator) < Epsilon then
  begin
    LineTo(P2);
    Exit;
  end;

  Numerator := Max(0, Numerator);
  Coeff := Sqrt(Numerator / Denominator);

  if LargeArc = Sweep then
    Coeff := -Coeff;

  Cxp := Coeff * (RX * Y1p / RY);
  Cyp := Coeff * (-RY * X1p / RX);

  { Center in original coordinate system }

  Cx := CosPhi * Cxp - SinPhi * Cyp + (P1.X + P2.X) / 2;
  Cy := SinPhi * Cxp + CosPhi * Cyp + (P1.Y + P2.Y) / 2;

  Theta1 := VectorAngle(1, 0, (X1p - Cxp) / RX, (Y1p - Cyp) / RY);
  DeltaTheta := VectorAngle((X1p - Cxp) / RX, (Y1p - Cyp) / RY, (-X1p - Cxp) / RX, (-Y1p - Cyp) / RY);

  if (not Sweep) and (DeltaTheta > 0) then
    DeltaTheta := DeltaTheta - 2 * Pi
  else if Sweep and (DeltaTheta < 0) then
    DeltaTheta := DeltaTheta + 2 * Pi;

  Segments := Ceil(Abs(DeltaTheta) / (Pi / 2));

  if Segments < 1 then
    Segments := 1;

  for I := 0 to Segments - 1 do
  begin
    T1 := Theta1 + DeltaTheta * I / Segments;
    T2 := Theta1 + DeltaTheta * (I + 1) / Segments;
    AddSegment(T1, T2);
  end;
end;

procedure TPathParser.ParseCommand(Cmd: Char);
var
  Rel: Boolean;
  X, Y: Single;
  X1, Y1: Single;
  X2, Y2: Single;
  RX, RY: Single;
  Rot: Single;
  LargeArcFlag, SweepFlag: Single;
  P: TPointF;
  C1, C2: TPointF;
begin
  Rel := Cmd = LowerCase(Cmd)[1];

  case UpCase(Cmd) of

    'M':
      begin
        if not ReadNumber(X) then
          Exit;

        if not ReadNumber(Y) then
          Exit;

        if Rel then
        begin
          X := X + FCurrent.X;
          Y := Y + FCurrent.Y;
        end;

        MoveTo(TPointF.Create(X, Y));

        { Subsequent coordinate pairs after M are implicit L }

        while True do
        begin
          if not ReadNumber(X) then
            Break;

          if not ReadNumber(Y) then
            Break;

          if Rel then
          begin
            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          LineTo(TPointF.Create(X, Y));
        end;
      end;
    'L':
      begin
        while True do
        begin
          if not ReadNumber(X) then
            Break;

          if not ReadNumber(Y) then
            Break;

          if Rel then
          begin
            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          LineTo(TPointF.Create(X, Y));
        end;
      end;
    'H':
      begin
        while True do
        begin
          if not ReadNumber(X) then
            Break;

          if Rel then
            X := X + FCurrent.X;

          LineTo(TPointF.Create(X, FCurrent.Y));
        end;
      end;
    'V':
      begin
        while True do
        begin
          if not ReadNumber(Y) then
            Break;

          if Rel then
            Y := Y + FCurrent.Y;

          LineTo(TPointF.Create(FCurrent.X, Y));
        end;
      end;
    'C':
      begin
        while True do
        begin
          if not ReadNumber(X1) then
            Break;
          if not ReadNumber(Y1) then
            Break;
          if not ReadNumber(X2) then
            Break;
          if not ReadNumber(Y2) then
            Break;
          if not ReadNumber(X) then
            Break;
          if not ReadNumber(Y) then
            Break;

          if Rel then
          begin
            X1 := X1 + FCurrent.X;
            Y1 := Y1 + FCurrent.Y;

            X2 := X2 + FCurrent.X;
            Y2 := Y2 + FCurrent.Y;

            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          C1 := TPointF.Create(X1, Y1);
          C2 := TPointF.Create(X2, Y2);
          P := TPointF.Create(X, Y);

          CurveTo(C1, C2, P);
        end;
      end;
    'S':
      begin
        while True do
        begin
          if not ReadNumber(X2) then
            Break;
          if not ReadNumber(Y2) then
            Break;
          if not ReadNumber(X) then
            Break;
          if not ReadNumber(Y) then
            Break;

          if FHasLastCubicControl then
          begin
            C1.X := 2 * FCurrent.X - FLastCubicControl.X;
            C1.Y := 2 * FCurrent.Y - FLastCubicControl.Y;
          end
          else
            C1 := FCurrent;

          if Rel then
          begin
            X2 := X2 + FCurrent.X;
            Y2 := Y2 + FCurrent.Y;

            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          C2 := TPointF.Create(X2, Y2);
          P := TPointF.Create(X, Y);

          CurveTo(C1, C2, P);
        end;
      end;
    'Q':
      begin
        while True do
        begin
          if not ReadNumber(X1) then
            Break;
          if not ReadNumber(Y1) then
            Break;
          if not ReadNumber(X) then
            Break;
          if not ReadNumber(Y) then
            Break;

          if Rel then
          begin
            X1 := X1 + FCurrent.X;
            Y1 := Y1 + FCurrent.Y;

            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          P := TPointF.Create(X, Y);
          C1.X := FCurrent.X + (2 / 3) * (X1 - FCurrent.X);
          C1.Y := FCurrent.Y + (2 / 3) * (Y1 - FCurrent.Y);
          C2.X := P.X + (2 / 3) * (X1 - P.X);
          C2.Y := P.Y + (2 / 3) * (Y1 - P.Y);
          CurveTo(C1, C2, P);

          FLastQuadControl := TPointF.Create(X1, Y1);

          FHasLastQuadControl := True;

          { CurveTo сбрасывает quadratic state }

          FHasLastQuadControl := True;
        end;
      end;
    'T':
      begin
        while True do
        begin
          if not ReadNumber(X) then
            Break;

          if not ReadNumber(Y) then
            Break;

          if FHasLastQuadControl then
          begin
            X1 := 2 * FCurrent.X - FLastQuadControl.X;
            Y1 := 2 * FCurrent.Y - FLastQuadControl.Y;
          end
          else
          begin
            X1 := FCurrent.X;
            Y1 := FCurrent.Y;
          end;

          if Rel then
          begin
            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          P := TPointF.Create(X, Y);

          C1.X := FCurrent.X + (2 / 3) * (X1 - FCurrent.X);
          C1.Y := FCurrent.Y + (2 / 3) * (Y1 - FCurrent.Y);
          C2.X := P.X + (2 / 3) * (X1 - P.X);
          C2.Y := P.Y + (2 / 3) * (Y1 - P.Y);

          CurveTo(C1, C2, P);

          FLastQuadControl := TPointF.Create(X1, Y1);

          FHasLastQuadControl := True;
        end;
      end;
    'A':
      begin
        while True do
        begin
          if not ReadNumber(RX) then
            Break;

          if not ReadNumber(RY) then
            Break;

          if not ReadNumber(Rot) then
            Break;

          if not ReadNumber(LargeArcFlag) then
            Break;

          if not ReadNumber(SweepFlag) then
            Break;

          if not ReadNumber(X) then
            Break;

          if not ReadNumber(Y) then
            Break;

          if Rel then
          begin
            X := X + FCurrent.X;
            Y := Y + FCurrent.Y;
          end;

          P := TPointF.Create(X, Y);

          ArcTo(FCurrent, RX, RY, Rot, not SameValue(LargeArcFlag, 0), not SameValue(SweepFlag, 0), P);

          FHasLastCubicControl := False;
          FHasLastQuadControl := False;
        end;
      end;
    'Z':
      begin
        ClosePath;
      end;
  end;
end;

procedure TPathParser.ParsePathData;
var
  Cmd: Char;
  LastCmd: Char;
begin
  LastCmd := #0;

  while FPos <= FLength do
  begin
    SkipSeparators;

    if FPos > FLength then
      Break;

    if IsCommandChar(PeekChar) then
      Cmd := ReadCommand
    else
      Cmd := LastCmd;

    if Cmd = #0 then
      Break;

    ParseCommand(Cmd);

    LastCmd := Cmd;
  end;
end;

function TPathParser.Parse(const S: string): string;
begin
  FSource := S;
  FLength := Length(S);
  FPos := 1;

  FCurrent := TPointF.Zero;
  FStartPoint := TPointF.Zero;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;

  ParsePathData;

  Result := FData.Data;
end;

constructor TSvgConverter.Create;
begin
  inherited;

  FPath := TPathData.Create;
end;

destructor TSvgConverter.Destroy;
begin
  FPath.Free;

  inherited;
end;

function TSvgConverter.Attr(const Node: IXMLNode; const Name: string; Default: Single): Single;
begin
  Result := GetAttributeFloat(Node, Name, Default);
end;

function TSvgConverter.AttrString(const Node: IXMLNode; const Name: string; const Default: string): string;
begin
  Result := GetAttributeString(Node, Name, Default);
end;

function TSvgConverter.ParseTransform(const S: string): TMatrix;
var
  P: Integer;

  function ReadWord: string;
  var
    Start: Integer;
  begin
    while (P <= Length(S)) and CharInSet(S[P], [' ', #9, #10, #13, ',']) do
      Inc(P);
    Start := P;
    while (P <= Length(S)) and not CharInSet(S[P], [' ', #9, #10, #13, ',', '(']) do
      Inc(P);

    Result := Copy(S, Start, P - Start);
  end;

  function ReadArguments: TFloatArray;
  var
    Start: Integer;
    Level: Integer;
    Text: string;
    Parts: TArray<string>;
    I: Integer;
  begin
    Result := [];
    while (P <= Length(S)) and (S[P] <> '(') do
      Inc(P);

    if P > Length(S) then
      Exit;

    Inc(P);

    Start := P;
    Level := 1;

    while (P <= Length(S)) and (Level > 0) do
    begin
      if S[P] = '(' then
        Inc(Level)
      else if S[P] = ')' then
      begin
        Dec(Level);

        if Level = 0 then
          Break;
      end;

      Inc(P);
    end;

    Text := Copy(S, Start, P - Start);

    if P <= Length(S) then
      Inc(P);

    Text := StringReplace(Text, ',', ' ', [rfReplaceAll]);
    Text := StringReplace(Text, #9, ' ', [rfReplaceAll]);
    Text := StringReplace(Text, #10, ' ', [rfReplaceAll]);
    Text := StringReplace(Text, #13, ' ', [rfReplaceAll]);

    while Pos('  ', Text) > 0 do
      Text := StringReplace(Text, '  ', ' ', [rfReplaceAll]);

    Text := Trim(Text);

    if Text = '' then
      Exit;

    Parts := Text.Split([' ']);

    SetLength(Result, Length(Parts));

    for I := 0 to High(Parts) do
      Result[I] :=
        InvariantFloat(Parts[I]);
  end;

var
  Name: string;
  V: TFloatArray;
  M: TMatrix;
begin
  Result := MatrixIdentity;

  P := 1;

  while P <= Length(S) do
  begin
    Name := LowerCase(ReadWord);

    if Name = '' then
      Break;

    V := ReadArguments;

    M := MatrixIdentity;

    if Name = 'translate' then
    begin
      if Length(V) >= 1 then
      begin
        if Length(V) >= 2 then
          M := TMatrix.Translation(V[0], V[1])
        else
          M := TMatrix.Translation(V[0], 0);
      end;
    end
    else if Name = 'scale' then
    begin
      if Length(V) >= 1 then
      begin
        if Length(V) >= 2 then
          M := TMatrix.Scaling(V[0], V[1])
        else
          M := TMatrix.Scaling(V[0], V[0]);
      end;
    end
    else if Name = 'rotate' then
    begin
      if Length(V) >= 1 then
      begin
        M := TMatrix.Rotation(DegToRad(V[0]));

        if Length(V) >= 3 then
        begin
          M := TMatrix.Translation(V[1], V[2]) * M * TMatrix.Translation(-V[1], -V[2]);
        end;
      end;
    end
    else if Name = 'matrix' then
    begin
      if Length(V) >= 6 then
      begin
        M := TMatrix.Create(V[0], V[1], V[2], V[3], V[4], V[5]);
      end;
    end
    else if Name = 'skewx' then
    begin
      if Length(V) >= 1 then
      begin
        M := TMatrix.Create(1, 0, Tan(DegToRad(V[0])), 1, 0, 0);
      end;
    end
    else if Name = 'skewy' then
    begin
      if Length(V) >= 1 then
      begin
        M := TMatrix.Create(1, Tan(DegToRad(V[0])), 0, 1, 0, 0);
      end;
    end;

    Result := Result * M;
  end;
end;

type
  TSharedPathParser = class(TPathParser)
  private
    FExternalData: TPathData;
  public
    constructor Create(const Matrix: TMatrix; Data: TPathData);
    function ParseShared(const S: string): string;
  end;

constructor TSharedPathParser.Create(const Matrix: TMatrix; Data: TPathData);
begin
  inherited Create(Matrix);
  FExternalData := Data;
  FData := Data;
end;

function TSharedPathParser.ParseShared(const S: string): string;
begin
  FSource := S;
  FLength := Length(S);
  FPos := 1;

  FCurrent := TPointF.Zero;
  FStartPoint := TPointF.Zero;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;

  ParsePathData;

  Result := FExternalData.Data;
end;

type
  TSharedPathParserFixed = class(TPathParser)
  private
    FExternalData: TPathData;
  public
    constructor Create(const Matrix: TMatrix; Data: TPathData);
    destructor Destroy; override;
    procedure ParseShared(const S: string);
  end;

constructor TSharedPathParserFixed.Create(const Matrix: TMatrix; Data: TPathData);
begin
  inherited Create(Matrix);

  FExternalData := Data;

  FData.Free;
  FData := FExternalData;
end;

destructor TSharedPathParserFixed.Destroy;
begin
  FData := nil;
  inherited;
end;

procedure TSharedPathParserFixed.ParseShared(const S: string);
begin
  FSource := S;
  FLength := Length(S);
  FPos := 1;

  FCurrent := TPointF.Zero;
  FStartPoint := TPointF.Zero;

  FHasLastCubicControl := False;
  FHasLastQuadControl := False;

  ParsePathData;
end;

procedure TSvgConverter.ParsePath(const Node: IXMLNode; const Matrix: TMatrix);
var
  Parser: TSharedPathParserFixed;
  S: string;
begin
  S := AttrString(Node, 'd');

  if S = '' then
    Exit;

  Parser := TSharedPathParserFixed.Create(Matrix, FPath);
  try
    Parser.ParseShared(S);
  finally
    Parser.Free;
  end;
end;

procedure TSvgConverter.AddEllipse(CX, CY, RX, RY: Single; const Matrix: TMatrix);
const
  Kappa = 0.5522847498307936;
var
  P0, P1, P2, P3: TPointF;
begin
  if (RX <= 0) or (RY <= 0) then
    Exit;

  P0 := TPointF.Create(CX + RX, CY);
  P1 := TPointF.Create(CX, CY + RY);
  P2 := TPointF.Create(CX - RX, CY);
  P3 := TPointF.Create(CX, CY - RY);

  FPath.MoveTo(Matrix.TransformPoint(P0));

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(CX + RX, CY + Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(CX + Kappa * RX, CY + RY)),
    Matrix.TransformPoint(P1)
  );

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(CX - Kappa * RX, CY + RY)),
    Matrix.TransformPoint(TPointF.Create(CX - RX, CY + Kappa * RY)),
    Matrix.TransformPoint(P2)
  );

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(CX - RX, CY - Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(CX - Kappa * RX, CY - RY)),
    Matrix.TransformPoint(P3)
  );

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(CX + Kappa * RX, CY - RY)),
    Matrix.TransformPoint(TPointF.Create(CX + RX, CY - Kappa * RY)),
    Matrix.TransformPoint(P0)
  );

  FPath.ClosePath;
end;

procedure TSvgConverter.AddRoundedRect(X, Y, W, H, RX, RY: Single; const Matrix: TMatrix);
const
  Kappa = 0.5522847498307936;
var
  X2, Y2: Single;
begin
  if (W <= 0) or (H <= 0) then
    Exit;

  if (RX <= 0) and (RY <= 0) then
  begin
    FPath.MoveTo(Matrix.TransformPoint(TPointF.Create(X, Y)));
    FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X + W, Y)));
    FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X + W, Y + H)));
    FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X, Y + H)));
    FPath.ClosePath;
    Exit;
  end;

  if RX <= 0 then
    RX := RY;

  if RY <= 0 then
    RY := RX;

  RX := Min(RX, W / 2);
  RY := Min(RY, H / 2);

  X2 := X + W;
  Y2 := Y + H;

  { Start: top-left after corner }

  FPath.MoveTo(Matrix.TransformPoint(TPointF.Create(X + RX, Y)));

  { Top }

  FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X2 - RX, Y)));

  { Top-right }

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(X2 - RX + Kappa * RX, Y)),
    Matrix.TransformPoint(TPointF.Create(X2, Y + RY - Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(X2, Y + RY))
  );

  { Right }

  FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X2, Y2 - RY)));

  { Bottom-right }

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(X2, Y2 - RY + Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(X2 - RX + Kappa * RX, Y2)),
    Matrix.TransformPoint(
      TPointF.Create(X2 - RX, Y2))
  );

  { Bottom }

  FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X + RX, Y2)));

  { Bottom-left }

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(X + RX - Kappa * RX, Y2)),
    Matrix.TransformPoint(TPointF.Create(X, Y2 - RY + Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(X, Y2 - RY))
  );

  { Left }

  FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X, Y + RY)));

  { Top-left }

  FPath.CurveTo(
    Matrix.TransformPoint(TPointF.Create(X, Y + RY - Kappa * RY)),
    Matrix.TransformPoint(TPointF.Create(X + RX - Kappa * RX, Y)),
    Matrix.TransformPoint(TPointF.Create(X + RX, Y))
  );

  FPath.ClosePath;
end;

procedure TSvgConverter.ParseRect(const Node: IXMLNode; const Matrix: TMatrix);
var
  X, Y, W, H: Single;
  RX, RY: Single;
begin
  X := Attr(Node, 'x');
  Y := Attr(Node, 'y');
  W := Attr(Node, 'width');
  H := Attr(Node, 'height');

  RX := Attr(Node, 'rx');
  RY := Attr(Node, 'ry');

  AddRoundedRect(X, Y, W, H, RX, RY, Matrix);
end;

procedure TSvgConverter.ParseCircle(const Node: IXMLNode; const Matrix: TMatrix);
begin
  AddEllipse(Attr(Node, 'cx'), Attr(Node, 'cy'), Attr(Node, 'r'), Attr(Node, 'r'), Matrix);
end;

procedure TSvgConverter.ParseEllipse(const Node: IXMLNode; const Matrix: TMatrix);
begin
  AddEllipse(Attr(Node, 'cx'), Attr(Node, 'cy'), Attr(Node, 'rx'), Attr(Node, 'ry'), Matrix);
end;

procedure TSvgConverter.ParseLine(const Node: IXMLNode; const Matrix: TMatrix);
begin
  FPath.MoveTo(Matrix.TransformPoint(TPointF.Create(Attr(Node, 'x1'), Attr(Node, 'y1'))));
  FPath.LineTo(Matrix.TransformPoint(TPointF.Create(Attr(Node, 'x2'), Attr(Node, 'y2'))));
end;

procedure TSvgConverter.ParsePoly(const Node: IXMLNode; const Matrix: TMatrix; Closed: Boolean);
var
  S: string;
  I: Integer;
  X, Y: Single;
  Parser: TPathParser;
begin
  S := AttrString(Node, 'points');

  if Trim(S) = '' then
    Exit;

  { Используем маленький специализированный scanner,
    потому что SVG допускает:
      10,20 30,40
      10 20 30 40
      10,20,30,40
  }

  S := StringReplace(S, ',', ' ', [rfReplaceAll]);
  S := StringReplace(S, #9, ' ', [rfReplaceAll]);
  S := StringReplace(S, #10, ' ', [rfReplaceAll]);
  S := StringReplace(S, #13, ' ', [rfReplaceAll]);
  Parser := TPathParser.Create(Matrix);
  try
    { Для poly используем временный Data через path-like
      строку. Преобразуем pairs в M/L. }

    I := 1;

    while I <= Length(S) do
    begin
      while (I <= Length(S)) and (S[I] = ' ') do
        Inc(I);

      if I > Length(S) then
        Break;

      { Получение X }

      var Start := I;

      while (I <= Length(S)) and (S[I] <> ' ') do
        Inc(I);

      X := InvariantFloat(Copy(S, Start, I - Start));

      while (I <= Length(S)) and (S[I] = ' ') do
        Inc(I);

      if I > Length(S) then
        Break;

      Start := I;

      while (I <= Length(S)) and (S[I] <> ' ') do
        Inc(I);

      Y := InvariantFloat(Copy(S, Start, I - Start));

      if FPath.IsEmpty then
        FPath.MoveTo(Matrix.TransformPoint(TPointF.Create(X, Y)))
      else
        FPath.LineTo(Matrix.TransformPoint(TPointF.Create(X, Y)));
    end;

    if Closed then
      FPath.ClosePath;
  finally
    Parser.Free;
  end;
end;

procedure TSvgConverter.ParseNode(const Node: IXMLNode; const ParentMatrix: TMatrix);
var
  Matrix: TMatrix;
  Transform: string;
  Name: string;
  I: Integer;
begin
  Matrix := ParentMatrix;

  Transform := AttrString(Node, 'transform');

  if Transform <> '' then
    Matrix := Matrix * ParseTransform(Transform);

  Name := LowerCase(Node.NodeName);

  if Name = 'path' then
    ParsePath(Node, Matrix)
  else if Name = 'rect' then
    ParseRect(Node, Matrix)
  else if Name = 'circle' then
    ParseCircle(Node, Matrix)
  else if Name = 'ellipse' then
    ParseEllipse(Node, Matrix)
  else if Name = 'line' then
    ParseLine(Node, Matrix)
  else if Name = 'polyline' then
    ParsePoly(Node, Matrix, False)
  else if Name = 'polygon' then
    ParsePoly(Node, Matrix, True);

  { Дети наследуют transform группы }

  for I := 0 to Node.ChildNodes.Count - 1 do
  begin
    if Node.ChildNodes[I].NodeType = ntElement then
      ParseNode(Node.ChildNodes[I], Matrix);
  end;
end;

function TSvgConverter.Convert(const SVG: string): string;
var
  Xml: IXMLDocument;
  Root: IXMLNode;
begin
  FPath.Clear;

  Xml := TXMLDocument.Create(nil);
  Xml.LoadFromXML(SVG);
  Root := Xml.DocumentElement;
  if Assigned(Root) then
    ParseNode(Root, MatrixIdentity);
  Result := FPath.Data;
end;

{ TSvgMatrix }

class function TMatrix.Identity: TMatrix;
begin
  Result.A := 1;
  Result.B := 0;
  Result.C := 0;
  Result.D := 1;
  Result.E := 0;
  Result.F := 0;
end;

class function TMatrix.Translation(const X, Y: Single): TMatrix;
begin
  Result := Identity;
  Result.E := X;
  Result.F := Y;
end;

class function TMatrix.Scaling(const X, Y: Single): TMatrix;
begin
  Result := Identity;
  Result.A := X;
  Result.D := Y;
end;

class function TMatrix.Rotation(const Angle: Single): TMatrix;
var
  S, C: Single;
begin
  S := Sin(Angle);
  C := Cos(Angle);

  Result.A := C;
  Result.B := S;
  Result.C := -S;
  Result.D := C;
  Result.E := 0;
  Result.F := 0;
end;

class function TMatrix.SkewX(const Angle: Single): TMatrix;
begin
  Result := Identity;
  Result.C := Tan(Angle);
end;

class function TMatrix.SkewY(const Angle: Single): TMatrix;
begin
  Result := Identity;
  Result.B := Tan(Angle);
end;

class function TMatrix.Create(const A, B, C, D, E, F: Single): TMatrix;
begin
  Result.A := A;
  Result.B := B;
  Result.C := C;
  Result.D := D;
  Result.E := E;
  Result.F := F;
end;

function TMatrix.TransformPoint(const P: TPointF): TPointF;
begin
  Result.X := A * P.X + C * P.Y + E;
  Result.Y := B * P.X + D * P.Y + F;
end;

class operator TMatrix.Multiply(const L, R: TMatrix): TMatrix;
begin
  Result.A := L.A * R.A + L.C * R.B;
  Result.B := L.B * R.A + L.D * R.B;

  Result.C := L.A * R.C + L.C * R.D;
  Result.D := L.B * R.C + L.D * R.D;

  Result.E := L.A * R.E + L.C * R.F + L.E;
  Result.F := L.B * R.E + L.D * R.F + L.F;
end;

end.

