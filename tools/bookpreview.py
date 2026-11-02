"""Render book-demo.tex as a facing-page preview, even page on the left."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw

ROOT=Path(__file__).resolve().parents[1]


def main():
    (ROOT/"build").mkdir(exist_ok=True)
    for _ in range(2):
        result=subprocess.run(["lualatex","-no-shell-escape","-interaction=nonstopmode","-halt-on-error",
                               "-output-directory=build","book-demo.tex"],cwd=ROOT,capture_output=True,text=True)
        (ROOT/"build/book-demo.build.log").write_text(result.stdout+result.stderr)
        if result.returncode:raise SystemExit("book-demo failed; see build/book-demo.build.log")
    subprocess.run(["pdftoppm","-png","-r","65","build/book-demo.pdf","build/book-demo"],cwd=ROOT,check=True,capture_output=True)
    paths=[ROOT/"build/book-demo-2.png",ROOT/"build/book-demo-1.png"]
    panels=[]
    for path,label in zip(paths,("Even page / quiet / protected callout","Odd page / chapter / outer margin")):
        with Image.open(path) as im:
            panel=Image.new("RGB",(im.width+20,im.height+45),"#ececea")
            panel.paste(im.convert("RGB"),(10,35));ImageDraw.Draw(panel).text((12,12),label,fill="#242424")
            panels.append(panel)
    sheet=Image.new("RGB",(sum(p.width for p in panels),max(p.height for p in panels)),"#ececea")
    x=0
    for panel in panels:sheet.paste(panel,(x,0));x+=panel.width
    sheet.save(ROOT/"gallery/book-layouts.png")
    print("saved gallery/book-layouts.png")


if __name__=="__main__":main()
