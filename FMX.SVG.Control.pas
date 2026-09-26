unit FMX.SVG.Control;

interface

uses
  System.Classes, System.Math, System.Types, FMX.Types, FMX.Controls,
  FMX.Graphics, FMX.SVG.Parser, FMX.SVG.Renderer;

type
  TSVGRender = class(TControl)
  private
    FSVG: string;
    FDocument: TSvgDocument;
    FRenderer: TSvgRenderer;
    FDocumentDirty, FBitmapDirty: Boolean;
    FRenderScale: Single;
    procedure SetSVG(const Value: string);
    procedure SetRenderScale(const Value: Single);
    procedure EnsureDocument;
  protected
    procedure Paint; override;
    procedure Resize; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Reload;
  published
    property SVG: string read FSVG write SetSVG;
    property RenderScale: Single read FRenderScale write SetRenderScale;
    property Align;
    property Anchors;
    property CanFocus;
    property Enabled;
    property HitTest;
    property Locked;
    property Opacity;
    property Position;
    property RotationAngle;
    property RotationCenter;
    property Scale;
    property Visible;
    property Width;
    property Height;
  end;

procedure Register;

implementation

constructor TSVGRender.Create(AOwner: TComponent);
begin
  inherited;
  FDocument := TSvgDocument.Create;
  FRenderer := TSvgRenderer.Create;
  FRenderScale := 1;
  FDocumentDirty := True;
  FBitmapDirty := True;
  CanFocus := False;
end;

destructor TSVGRender.Destroy;
begin
  FRenderer.Free;
  FDocument.Free;
  inherited;
end;

procedure TSVGRender.SetSVG(const Value: string);
begin
  if FSVG = Value then
    Exit;
  FSVG := Value;
  FDocumentDirty := True;
  FBitmapDirty := True;
  Repaint;
end;

procedure TSVGRender.SetRenderScale(const Value: Single);
begin
  var V := Max(Value, 0.01);
  if SameValue(FRenderScale, V, 0.0001) then
    Exit;
  FRenderScale := V;
  FBitmapDirty := True;
  Repaint;
end;

procedure TSVGRender.Reload;
begin
  FDocumentDirty := True;
  FBitmapDirty := True;
  Repaint;
end;

procedure TSVGRender.Resize;
begin
  inherited;
  FBitmapDirty := True;
end;

procedure TSVGRender.EnsureDocument;
begin
  if not FDocumentDirty then
    Exit;
  FDocument.LoadFromString(FSVG);
  FDocumentDirty := False;
end;

procedure TSVGRender.Paint;
begin
  inherited;
  EnsureDocument;
  if FBitmapDirty then
  begin
    FRenderer.Rasterize(FDocument, Width, Height, FRenderScale);
    FBitmapDirty := False;
  end;
  if (FRenderer.Bitmap.Width > 0) and (FRenderer.Bitmap.Height > 0) then
    Canvas.DrawBitmap(
      FRenderer.Bitmap,
      RectF(0, 0, FRenderer.Bitmap.Width, FRenderer.Bitmap.Height),
      LocalRect,
      AbsoluteOpacity);
end;

procedure Register;
begin
  RegisterFmxClasses([TSVGRender]);
end;

end.

