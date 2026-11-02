"""Render the four-page design guide and a readable close-up of its folios."""
from pathlib import Path
import subprocess
from PIL import Image, ImageDraw, ImageFont
from build import build, ROOT


def main():
    pdf = build(ROOT / "folio-demo.tex", "lua", ROOT / "build/folio-guide")
    subprocess.run(["pdftoppm", "-r", "70", "-png", str(pdf), str(pdf.with_suffix(""))], check=True, capture_output=True)
    pages = []
    for path in sorted(pdf.parent.glob("folio-demo-[0-9]*.png")):
        with Image.open(path) as im:
            pages.append(im.convert("RGB"))
    assert len(pages) == 4
    w, h = pages[0].size
    sheet = Image.new("RGB", (2*w+36, 2*h+84), "#ecebe8")
    draw = ImageDraw.Draw(sheet)
    labels = ("XIV / quiet / monochrome", "XV / upright right-hand folio",
              "38 / chapter / shared spread seed", "39 / upright right-hand folio")
    for i, page in enumerate(pages):
        x, y = 12+(i%2)*(w+12), 30+(i//2)*(h+36)
        sheet.paste(page, (x,y));draw.text((x,y-18), labels[i], fill="#303030")
    sheet.save(ROOT / "gallery/folio-guide.png")
    # Physical outer-margin foot, in the original reading direction.
    crops = []
    for i, page in enumerate(pages):
        region = (0, h-int(h*0.22), int(w*0.34), h) if i%2==0 else (int(w*0.66),h-int(h*0.22),w,h)
        crops.append(page.crop(region))
    cw, ch = crops[0].size
    detail = Image.new("RGB", (4*cw+60,ch+44), "#ecebe8")
    draw = ImageDraw.Draw(detail)
    for i, crop in enumerate(crops):
        detail.paste(crop,(12+i*(cw+12),30));draw.text((12+i*(cw+12),10),labels[i].split(" /")[0],fill="#303030")
    detail.save(ROOT / "gallery/folio-labels.png")
    print("foliopreview: saved gallery/folio-guide.png and gallery/folio-labels.png")


if __name__ == "__main__":
    main()
