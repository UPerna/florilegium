"""Raster checks for physical margin placement and guaranteed reserved whitespace."""
from pathlib import Path
import subprocess
from PIL import Image
from bookpreview import main as build_preview

ROOT=Path(__file__).resolve().parents[1]
SCALE=65/2.54


def colored(image,box):
    crop=image.crop(box).convert("RGB")
    pixels=crop.get_flattened_data() if hasattr(crop,"get_flattened_data") else crop.getdata()
    return sum(max(p)-min(p)>15 for p in pixels)


def page_box(x0,y0,x1,y1):
    # PDF lower-left cm to interior raster pixels; omit the antialiased boundary.
    return (round(x0*SCALE)+2,round((29.7-y1)*SCALE)+2,
            round(x1*SCALE)-2,round((29.7-y0)*SCALE)-2)


def main():
    build_preview()
    with Image.open(ROOT/"build/book-demo-1.png") as image:
        assert colored(image,page_box(14.5,4,20.8,25))>100
        assert colored(image,page_box(0.2,4,14.1,25))==0,"odd-page ornament entered the inner/text side"
    with Image.open(ROOT/"build/book-demo-2.png") as image:
        assert colored(image,page_box(0.2,4,6.5,25))>100
        assert colored(image,page_box(6.9,4,20.8,25))==0,"even-page ornament entered the inner/text side"
        assert colored(image,page_box(0.9,10.9,4.5,14.7))==0,"ornament entered the protected callout"
    for name,reservations,rect in (
      ("overlap",r"\florilegiumreserve[0pt]{0cm}{14cm}{21cm}{3cm}\florilegiumreserve[0pt]{0cm}{15cm}{21cm}{3cm}",(0.1,14.1,20.9,17.9)),
      ("whole-page",r"\florilegiumreserve[0pt]{0cm}{0cm}{21cm}{29.7cm}",(0.1,0.1,20.9,29.6)),
    ):
        source=(r"\documentclass[a4paper]{article}\renewcommand\rmdefault{cmr}"
                r"\usepackage[left=68mm,right=22mm]{geometry}\usepackage[grown,density=airy]{florilegium}"
                r"\begin{document}"+reservations+r"The content remains visible.\end{document}")
        prefix=ROOT/"build"/("visual-"+name);tex=prefix.with_suffix(".tex");tex.write_text(source)
        result=subprocess.run(["lualatex","-no-shell-escape","-interaction=nonstopmode","-halt-on-error",
                               "-output-directory=build",str(tex)],cwd=ROOT,capture_output=True,text=True)
        prefix.with_suffix(".build.log").write_text(result.stdout+result.stderr)
        assert result.returncode==0,f"compile failed: {name}"
        subprocess.run(["pdftoppm","-png","-r","65","-singlefile",str(prefix.with_suffix('.pdf')),str(prefix)],check=True,capture_output=True)
        with Image.open(prefix.with_suffix(".png")) as image:
            assert colored(image,page_box(*rect))==0,f"ornament entered reservation: {name}"
        text=subprocess.check_output(["pdftotext",str(prefix.with_suffix('.pdf')),"-"],text=True)
        assert "The content remains visible" in " ".join(text.split())
    print("visualcheck: book-side placement, protected callout, overlapping barriers and full-page reservation passed")


if __name__=="__main__":main()
