unit SVGTest.Main;

interface

uses
  System.SysUtils, System.Types, System.UITypes, System.Classes, System.Variants,
  FMX.Types, FMX.Controls, FMX.Forms, FMX.Graphics, FMX.Dialogs, FMX.Memo.Types,
  FMX.Controls.Presentation, FMX.ScrollBox, FMX.Memo, FMX.SVG, FMX.Layouts,
  FMX.Objects;

type
  TFormMain = class(TForm)
    MemoSVG: TMemo;
    LayoutSVG: TLayout;
    Rectangle1: TRectangle;
    procedure FormCreate(Sender: TObject);
    procedure MemoSVGChange(Sender: TObject);
  private
    FSVG: TSVGRender;
  public
    { Public declarations }
  end;

var
  FormMain: TFormMain;

implementation

{$R *.fmx}

procedure TFormMain.FormCreate(Sender: TObject);
begin
  FSVG := TSVGRender.Create(Self);
  FSVG.Parent := LayoutSVG;
  FSVG.Align := TAlignLayout.Client;
end;

procedure TFormMain.MemoSVGChange(Sender: TObject);
begin
  try
    FSVG.SVG := MemoSVG.Text;
  except
    //
  end;
end;

end.

