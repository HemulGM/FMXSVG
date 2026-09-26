program SVGTest;

uses
  System.StartUpCopy,
  FMX.Forms,
  SVGTest.Main in 'SVGTest.Main.pas' {FormMain},
  FMX.SVG.Cache in '..\FMX.SVG.Cache.pas',
  FMX.SVG.Control in '..\FMX.SVG.Control.pas',
  FMX.SVG.Parser in '..\FMX.SVG.Parser.pas',
  FMX.SVG in '..\FMX.SVG.pas',
  FMX.SVG.Renderer in '..\FMX.SVG.Renderer.pas',
  FMX.SVG.Types in '..\FMX.SVG.Types.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
