program SVGTest;

uses
  System.StartUpCopy,
  FMX.Forms,
  SVGTest.Main in 'SVGTest.Main.pas' {FormMain},
  FMX.SVG.Cache in '..\FMX.SVG.Cache.pas',
  FMX.SVG in '..\FMX.SVG.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TFormMain, FormMain);
  Application.Run;
end.
