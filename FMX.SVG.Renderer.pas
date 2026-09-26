unit FMX.SVG.Renderer;

interface

uses
  System.SysUtils, System.Classes, System.Types, System.UITypes, FMX.Types,
  FMX.Graphics, FMX.SVG.Parser, FMX.SVG.Types;

type
  TSvgRenderer = class
  private
    FDocument: TSvgDocument;
    FBitmap: TBitmap;
    FRenderScale: Single;
    function GetContentMatrix: TSvgMatrix;
    procedure RenderMidMarkers(const Canvas: TCanvas; Element: TSvgElement; const ViewMatrix: TSvgMatrix);
    procedure RenderMarker(const Canvas: TCanvas; Marker: TSvgMarker; const Position: TPointF; Angle, Scale: Single);
    procedure RenderEndpointMarker(const Canvas: TCanvas; Element: TSvgElement;
      const ViewMatrix: TSvgMatrix; const MarkerID: string; const FromPoint,
      ToPoint: TPointF; IsStart: Boolean);
    procedure RenderElement(const Canvas: TCanvas; Element: TSvgElement; const ViewMatrix: TSvgMatrix);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Rasterize(ADocument: TSvgDocument; AWidth, AHeight, ARenderScale: Single);
    property Bitmap: TBitmap read FBitmap;
  end;

implementation

uses
  System.Math;

function AlphaColorWithOpacity(Color: TAlphaColor; Opacity: Single): TAlphaColor;
begin
  var A := Round(TAlphaColorRec(Color).A * EnsureRange(Opacity, 0, 1));
  Result := (Color and $00FFFFFF) or (TAlphaColor(A) shl 24);
end;

procedure TSvgRenderer.RenderMarker(const Canvas: TCanvas; Marker: TSvgMarker;
  const Position: TPointF; Angle, Scale: Single);
begin
  if not Marker.Style.Visible then
    Exit;

  var Path := TPathData.Create;
  try
    var Matrix := TSvgMatrix.Translation(Position.X, Position.Y) *
      TSvgMatrix.Rotation(Angle) * TSvgMatrix.Scaling(Scale, Scale) *
      TSvgMatrix.Translation(-Marker.RefX, -Marker.RefY) * Marker.Matrix;
    Marker.Path.AppendTo(Path, Matrix);
    var Opacity := EnsureRange(Marker.Style.Opacity, 0, 1);
    if Marker.Style.Fill.Enabled then
    begin
      Canvas.Fill.Kind := TBrushKind.Solid;
      Canvas.Fill.Color := AlphaColorWithOpacity(Marker.Style.Fill.Color, Marker.Style.FillOpacity);
      Canvas.FillPath(Path, Opacity);
    end;
    if Marker.Style.Stroke.Enabled and (Marker.Style.StrokeWidth > 0) then
    begin
      var Stroke := TStrokeBrush.Create(TBrushKind.Solid, TAlphaColorRec.Null);
      try
        Stroke.Color := AlphaColorWithOpacity(Marker.Style.Stroke.Color, Marker.Style.StrokeOpacity);
        Stroke.Thickness := Marker.Style.StrokeWidth * Scale;
        Stroke.Cap := Marker.Style.StrokeCap;
        Stroke.Join := Marker.Style.StrokeJoin;
        Canvas.DrawPath(Path, Opacity, Stroke);
      finally
        Stroke.Free;
      end;
    end;
  finally
    Path.Free;
  end;
end;

procedure TSvgRenderer.RenderEndpointMarker(const Canvas: TCanvas;
  Element: TSvgElement; const ViewMatrix: TSvgMatrix; const MarkerID: string;
  const FromPoint, ToPoint: TPointF; IsStart: Boolean);
begin
  if MarkerID.IsEmpty then
    Exit;

  var Marker: TSvgMarker;
  if not FDocument.Markers.TryGetValue(MarkerID, Marker) then
    Exit;

  var Matrix := ViewMatrix * Element.Matrix;
  var A := Matrix.TransformPoint(FromPoint);
  var B := Matrix.TransformPoint(ToPoint);
  var DX := B.X - A.X;
  var DY := B.Y - A.Y;
  if Hypot(DX, DY) <= 0.0001 then
    Exit;

  var Angle: Single;
  if SameText(Marker.Orient, 'auto') or SameText(Marker.Orient, 'auto-start-reverse') then
  begin
    Angle := ArcTan2(DY, DX);
    if IsStart and SameText(Marker.Orient, 'auto-start-reverse') then
      Angle := Angle + Pi;
  end
  else
    Angle := DegToRad(StrToFloatDef(Marker.Orient.Replace(',', '.'), 0, TFormatSettings.Invariant));

  var MarkerScale := 1.0;
  if Marker.UnitsStrokeWidth then
    MarkerScale := Element.Style.StrokeWidth * Sqrt(Sqr(Matrix.A) + Sqr(Matrix.B));
  if IsStart then
    RenderMarker(Canvas, Marker, A, Angle, MarkerScale)
  else
    RenderMarker(Canvas, Marker, B, Angle, MarkerScale);
end;

procedure TSvgRenderer.RenderMidMarkers(const Canvas: TCanvas; Element: TSvgElement;
  const ViewMatrix: TSvgMatrix);
begin
  if Element.MarkerStartID.IsEmpty and Element.MarkerMidID.IsEmpty and
    Element.MarkerEndID.IsEmpty then
    Exit;

  var Matrix := ViewMatrix * Element.Matrix;
  var HasIncoming := False;
  var Current, PreviousTangentPoint: TPointF;
  for var Command in Element.Path.Commands do
  begin
    case Command.Command of
      spMoveTo:
        begin
          if HasIncoming then
            RenderEndpointMarker(Canvas, Element, ViewMatrix, Element.MarkerEndID,
              PreviousTangentPoint, Current, False);
          Current := Command.P1;
          HasIncoming := False;
        end;
      spLineTo, spCurveTo:
        begin
          var Next: TPointF;
          if Command.Command = spLineTo then
            Next := Command.P1
          else
            Next := Command.P3;
          var OutgoingTangentPoint := Next;
          if Command.Command = spCurveTo then
          begin
            OutgoingTangentPoint := Command.P1;
            if (Abs(OutgoingTangentPoint.X - Current.X) < 0.0001) and
              (Abs(OutgoingTangentPoint.Y - Current.Y) < 0.0001) then
              OutgoingTangentPoint := Next;
          end;
          if not HasIncoming then
            RenderEndpointMarker(Canvas, Element, ViewMatrix, Element.MarkerStartID,
              Current, OutgoingTangentPoint, True);
          if HasIncoming then
          begin
            var A := Matrix.TransformPoint(PreviousTangentPoint);
            var B := Matrix.TransformPoint(Current);
            var C := Matrix.TransformPoint(OutgoingTangentPoint);
            var InX := B.X - A.X;
            var InY := B.Y - A.Y;
            var OutX := C.X - B.X;
            var OutY := C.Y - B.Y;
            var InLength := Hypot(InX, InY);
            var OutLength := Hypot(OutX, OutY);
            if (InLength > 0.0001) and (OutLength > 0.0001) then
            begin
              InX := InX / InLength;
              InY := InY / InLength;
              OutX := OutX / OutLength;
              OutY := OutY / OutLength;
              var Angle: Single;
              var Marker: TSvgMarker;
              if FDocument.Markers.TryGetValue(Element.MarkerMidID, Marker) then
              begin
                if SameText(Marker.Orient, 'auto') or SameText(Marker.Orient, 'auto-start-reverse') then
                  Angle := ArcTan2(InY + OutY, InX + OutX)
                else
                  Angle := DegToRad(StrToFloatDef(Marker.Orient.Replace(',', '.'), 0, TFormatSettings.Invariant));
                var MarkerScale := 1.0;
                if Marker.UnitsStrokeWidth then
                  MarkerScale := Element.Style.StrokeWidth *
                    Sqrt(Sqr(Matrix.A) + Sqr(Matrix.B));
                RenderMarker(Canvas, Marker, B, Angle, MarkerScale);
              end;
            end;
          end;
          if Command.Command = spCurveTo then
          begin
            PreviousTangentPoint := Command.P2;
            if (Abs(PreviousTangentPoint.X - Next.X) < 0.0001) and
              (Abs(PreviousTangentPoint.Y - Next.Y) < 0.0001) then
              PreviousTangentPoint := Current;
          end
          else
            PreviousTangentPoint := Current;
          Current := Next;
          HasIncoming := True;
        end;
      spClose:
        begin
          if HasIncoming then
            RenderEndpointMarker(Canvas, Element, ViewMatrix, Element.MarkerEndID,
              PreviousTangentPoint, Current, False);
          HasIncoming := False;
        end;
    end;
  end;
  if HasIncoming then
    RenderEndpointMarker(Canvas, Element, ViewMatrix, Element.MarkerEndID,
      PreviousTangentPoint, Current, False);
end;

constructor TSvgRenderer.Create;
begin
  inherited;
  FBitmap := TBitmap.Create(1, 1);
end;

destructor TSvgRenderer.Destroy;
begin
  FBitmap.Free;
  inherited;
end;

function TSvgRenderer.GetContentMatrix: TSvgMatrix;
begin
  Result := TSvgMatrix.Identity;
  var ViewportWidth := FBitmap.Width;
  var ViewportHeight := FBitmap.Height;
  if FDocument.HasViewBox then
  begin
    var VB := FDocument.ViewBox;
    if (VB.Width <= 0) or (VB.Height <= 0) then
      Exit;
    var SX := ViewportWidth / VB.Width;
    var SY := ViewportHeight / VB.Height;
    var S := Min(SX, SY);
    Result := TSvgMatrix.Translation((ViewportWidth - VB.Width * S) / 2 - VB.Left * S, (ViewportHeight - VB.Height * S) / 2 - VB.Top * S) * TSvgMatrix.Scaling(S, S);
    Exit;
  end;
  var ScaleX := FRenderScale;
  var ScaleY := FRenderScale;
  if FDocument.Width > 0 then
    ScaleX := ViewportWidth / FDocument.Width;
  if FDocument.Height > 0 then
    ScaleY := ViewportHeight / FDocument.Height;
  Result := TSvgMatrix.Scaling(ScaleX, ScaleY);
end;

procedure TSvgRenderer.RenderElement(const Canvas: TCanvas; Element: TSvgElement; const ViewMatrix: TSvgMatrix);
begin
  if not Element.Style.Visible then
    Exit;
  if Element.Name = 'text' then
  begin
    if Element.Text.IsEmpty or not Element.Style.Fill.Enabled then
      Exit;
    var TextMatrix := ViewMatrix * Element.Matrix;
    var Position := TextMatrix.TransformPoint(Element.TextPosition);
    var TextScale := Sqrt(Sqr(TextMatrix.A) + Sqr(TextMatrix.B));
    if TextScale <= 0 then
      TextScale := 1;
    var FontSize := Element.FontSize * TextScale;
    Canvas.Font.Family := Element.FontFamily;
    Canvas.Font.Size := FontSize;
    Canvas.Fill.Kind := TBrushKind.Solid;
    Canvas.Fill.Color := AlphaColorWithOpacity(Element.Style.Fill.Color, Element.Style.FillOpacity);
    var Align := TTextAlign.Leading;
    var TextRect: TRectF;
    if Element.TextAnchor = 'middle' then
    begin
      Align := TTextAlign.Center;
      TextRect := RectF(Position.X - 5000, Position.Y - FontSize, Position.X + 5000, Position.Y + FontSize);
    end
    else if Element.TextAnchor = 'end' then
    begin
      Align := TTextAlign.Trailing;
      TextRect := RectF(Position.X - 10000, Position.Y - FontSize, Position.X, Position.Y + FontSize);
    end
    else
      TextRect := RectF(Position.X, Position.Y - FontSize, Position.X + 10000, Position.Y + FontSize);
    Canvas.FillText(TextRect, Element.Text, False, EnsureRange(Element.Style.Opacity, 0, 1), [], Align, TTextAlign.Trailing);
    Exit;
  end;
  var Path := TPathData.Create;
  try
    Element.Path.AppendTo(Path, ViewMatrix * Element.Matrix);
    var Opacity := EnsureRange(Element.Style.Opacity, 0, 1);
    if Element.Style.Fill.Enabled then
    begin
      var Brush := TBrush.Create(TBrushKind.Solid, TAlphaColorRec.Null);
      try
        var Definition: TSvgGradient;
        if not Element.Style.Fill.GradientID.IsEmpty and FDocument.Gradients.TryGetValue(Element.Style.Fill.GradientID, Definition) then
        begin
          var Bounds := Path.GetBounds;
          Brush.Kind := TBrushKind.Gradient;
          if Definition.Kind = sgRadial then
          begin
            Brush.Gradient.Style := TGradientStyle.Radial;
            if Definition.UnitsUserSpace then
            begin
              var GradientMatrix := ViewMatrix * Element.Matrix * Definition.Matrix;
              var P := GradientMatrix.TransformPoint(PointF(Definition.X1, Definition.Y1));
              Brush.Gradient.RadialTransform.RotationCenter.Point := PointF((P.X - Bounds.Left) / Bounds.Width, (P.Y - Bounds.Top) / Bounds.Height);
              Brush.Gradient.RadialTransform.RotationAngle := RadToDeg(ArcTan2(GradientMatrix.B, GradientMatrix.A));
              Brush.Gradient.RadialTransform.Scale.X := Sqrt(Sqr(GradientMatrix.A) + Sqr(GradientMatrix.B)) / Max(Bounds.Width / 2, 0.0001);
              Brush.Gradient.RadialTransform.Scale.Y := Sqrt(Sqr(GradientMatrix.C) + Sqr(GradientMatrix.D)) / Max(Bounds.Height / 2, 0.0001);
            end
            else
            begin
              Brush.Gradient.RadialTransform.RotationCenter.Point := Definition.Matrix.TransformPoint(PointF(Definition.X1, Definition.Y1));
              Brush.Gradient.RadialTransform.RotationAngle := 0;
              Brush.Gradient.RadialTransform.Scale.X := 1;
              Brush.Gradient.RadialTransform.Scale.Y := 1;
            end;
          end
          else
          begin
            Brush.Gradient.Style := TGradientStyle.Linear;
            if Definition.UnitsUserSpace then
            begin
              var StartPoint := (ViewMatrix * Element.Matrix * Definition.Matrix).TransformPoint(PointF(Definition.X1, Definition.Y1));
              var StopPoint := (ViewMatrix * Element.Matrix * Definition.Matrix).TransformPoint(PointF(Definition.X2, Definition.Y2));
              Brush.Gradient.StartPosition.Point := PointF((StartPoint.X - Bounds.Left) / Bounds.Width, (StartPoint.Y - Bounds.Top) / Bounds.Height);
              Brush.Gradient.StopPosition.Point := PointF((StopPoint.X - Bounds.Left) / Bounds.Width, (StopPoint.Y - Bounds.Top) / Bounds.Height);
            end
            else
            begin
              Brush.Gradient.StartPosition.Point := Definition.Matrix.TransformPoint(PointF(Definition.X1, Definition.Y1));
              Brush.Gradient.StopPosition.Point := Definition.Matrix.TransformPoint(PointF(Definition.X2, Definition.Y2));
            end;
          end;
          Brush.Gradient.Points.Clear;
          if (Definition.Kind = sgLinear) and not Definition.UnitsUserSpace and
            (Definition.Spread <> sgsPad) then
          begin
            var DX := Definition.X2 - Definition.X1;
            var DY := Definition.Y2 - Definition.Y1;
            var LengthSquared := Sqr(DX) + Sqr(DY);
            if LengthSquared > 0.000001 then
            begin
              var MinT := Min(Min((-Definition.X1 * DX - Definition.Y1 * DY) / LengthSquared,
                ((1 - Definition.X1) * DX - Definition.Y1 * DY) / LengthSquared),
                Min((-Definition.X1 * DX + (1 - Definition.Y1) * DY) / LengthSquared,
                ((1 - Definition.X1) * DX + (1 - Definition.Y1) * DY) / LengthSquared));
              var MaxT := Max(Max((-Definition.X1 * DX - Definition.Y1 * DY) / LengthSquared,
                ((1 - Definition.X1) * DX - Definition.Y1 * DY) / LengthSquared),
                Max((-Definition.X1 * DX + (1 - Definition.Y1) * DY) / LengthSquared,
                ((1 - Definition.X1) * DX + (1 - Definition.Y1) * DY) / LengthSquared));
              var Range := MaxT - MinT;
              Brush.Gradient.StartPosition.Point := Definition.Matrix.TransformPoint(
                PointF(Definition.X1 + DX * MinT, Definition.Y1 + DY * MinT));
              Brush.Gradient.StopPosition.Point := Definition.Matrix.TransformPoint(
                PointF(Definition.X1 + DX * MaxT, Definition.Y1 + DY * MaxT));
              for var Cycle := Floor(MinT) to Ceil(MaxT) do
                for var I := 0 to Definition.Gradient.Points.Count - 1 do
                begin
                  var SourceIndex := I;
                  var Position := Definition.Gradient.Points[I].Offset;
                  if (Definition.Spread = sgsReflect) and Odd(Cycle) then
                  begin
                    SourceIndex := Definition.Gradient.Points.Count - 1 - I;
                    Position := 1 - Definition.Gradient.Points[SourceIndex].Offset;
                  end;
                  var Target := TGradientPoint(Brush.Gradient.Points.Add);
                  Target.Offset := (Cycle + Position - MinT) / Range;
                  Target.Color := AlphaColorWithOpacity(
                    Definition.Gradient.Points[SourceIndex].Color, Element.Style.FillOpacity);
                end;
            end;
          end;
          if Brush.Gradient.Points.Count = 0 then
            for var I := 0 to Definition.Gradient.Points.Count - 1 do
            begin
              var SourceIndex := I;
              if Definition.Kind = sgRadial then
                SourceIndex := Definition.Gradient.Points.Count - 1 - I;
              var Source := Definition.Gradient.Points[SourceIndex];
              var Target := TGradientPoint(Brush.Gradient.Points.Add);
              if Definition.Kind = sgRadial then
                Target.Offset := 1 - Source.Offset
              else
                Target.Offset := Source.Offset;
              Target.Color := AlphaColorWithOpacity(Source.Color, Element.Style.FillOpacity);
            end;
          Canvas.FillPath(Path, Opacity, Brush);
        end
        else if Element.Style.Fill.GradientID.IsEmpty then
        begin
          Brush.Color := AlphaColorWithOpacity(Element.Style.Fill.Color, Element.Style.FillOpacity);
          Canvas.FillPath(Path, Opacity, Brush);
        end;
      finally
        Brush.Free;
      end;
    end;
    if Element.Style.Stroke.Enabled and (Element.Style.StrokeWidth > 0) then
    begin
      var Stroke := TStrokeBrush.Create(TBrushKind.Solid, TAlphaColorRec.Null);
      try
        Stroke.Color := AlphaColorWithOpacity(Element.Style.Stroke.Color, Element.Style.StrokeOpacity);
        Stroke.Thickness := Element.Style.StrokeWidth;
        Stroke.Cap := Element.Style.StrokeCap;
        Stroke.Join := Element.Style.StrokeJoin;
        if Length(Element.Style.DashArray) > 0 then
        begin
          var DashArray: TArray<Single>;
          SetLength(DashArray, Length(Element.Style.DashArray));
          for var I := 0 to High(DashArray) do
            DashArray[I] := Element.Style.DashArray[I] / Stroke.Thickness;
          Stroke.SetCustomDash(DashArray, Element.Style.DashOffset / Stroke.Thickness);
        end;
        Canvas.DrawPath(Path, Opacity, Stroke);
      finally
        Stroke.Free;
      end;
    end;
    RenderMidMarkers(Canvas, Element, ViewMatrix);
  finally
    Path.Free;
  end;
end;

procedure TSvgRenderer.Rasterize(ADocument: TSvgDocument; AWidth, AHeight, ARenderScale: Single);
begin
  FDocument := ADocument;
  FRenderScale := ARenderScale;
  FBitmap.SetSize(Max(1, Ceil(AWidth * ARenderScale)), Max(1, Ceil(AHeight * ARenderScale)));
  FBitmap.Canvas.BeginScene;
  try
    FBitmap.Canvas.Clear(TAlphaColorRec.Null);
    var Matrix := GetContentMatrix;
    for var Element in FDocument.Elements do
      RenderElement(FBitmap.Canvas, Element, Matrix);
  finally
    FBitmap.Canvas.EndScene;
  end;
end;

end.

