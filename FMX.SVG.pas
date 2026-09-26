unit FMX.SVG;

interface

uses
  FMX.SVG.Types, FMX.SVG.Parser, FMX.SVG.Renderer, FMX.SVG.Control;

type
  TSvgMatrix = FMX.SVG.Types.TSvgMatrix;

  TSvgLengthUnit = FMX.SVG.Types.TSvgLengthUnit;

  TSvgLength = FMX.SVG.Types.TSvgLength;

  TSvgPathCommandType = FMX.SVG.Types.TSvgPathCommandType;

  TSvgPathCommand = FMX.SVG.Types.TSvgPathCommand;

  TSvgPath = FMX.SVG.Types.TSvgPath;

  TSvgFillRule = FMX.SVG.Types.TSvgFillRule;

  TSvgPaint = FMX.SVG.Types.TSvgPaint;

  TSvgGradient = FMX.SVG.Types.TSvgGradient;

  TSvgStyle = FMX.SVG.Types.TSvgStyle;

  TSvgElement = FMX.SVG.Types.TSvgElement;

  TSvgNumberParser = FMX.SVG.Parser.TSvgNumberParser;

  TSvgPathParser = FMX.SVG.Parser.TSvgPathParser;

  TSvgDocument = FMX.SVG.Parser.TSvgDocument;

  TSvgRenderer = FMX.SVG.Renderer.TSvgRenderer;

  TSVGRender = FMX.SVG.Control.TSVGRender;

procedure Register;

implementation

procedure Register;
begin
  FMX.SVG.Control.Register;
end;

end.

