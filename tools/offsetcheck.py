"""Check physical reservations in rendered PDFs, independently of Lua geometry."""
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image
from visualcheck import colored, page_box

ROOT = Path(__file__).resolve().parents[1]


def main():
    folder = ROOT / "build/offset-check"
    folder.mkdir(parents=True, exist_ok=True)
    cases = [(side, page, h, v) for side in ("left", "right", "outer", "inner")
             for page, h, v in ((1, 10, 7), (2, -10, -7))]
    for side, page, h, v in cases:
        # Flood the drawing layer: a reservation must clear the requested physical
        # rectangle regardless of the procedural layout, parity or mirror.
        wide = (side == "left" or side == "outer" and page % 2 == 0
                or side == "inner" and page % 2 == 1)
        margins = "left=68mm,right=22mm" if wide == (page % 2 == 1) else "left=22mm,right=68mm"
        source = (r"\documentclass[a4paper,twoside]{article}\renewcommand\rmdefault{cmr}"
                  + rf"\usepackage[{margins}]{{geometry}}\usepackage[grown,side={side},style=quiet]{{florilegium}}"
                  + rf"\hoffset={h}mm\voffset={v}mm\setcounter{{page}}{{{page}}}"
                  + r"\directlua{require('grow').page=function(g) local ink=require('ink');"
                    r"for _,r in ipairs(g.reserves) do texio.write_nl('offset reserve: '..table.concat(r,',')) end;"
                    r"ink.set_transform({ink.CM,0,0,ink.CM,0,0});ink.layer(5);"
                    r"ink.flood({0.1,0.3,0.8},0,0,g.pw,g.ph);ink.flush() end}"
                    r"\begin{document}\florilegiumreserve[0pt]{1cm}{10cm}{3cm}{5cm}"
                    r"\begin{florilegiumprotect}[1mm]Protected content stays clear.\end{florilegiumprotect}"
                    r"\end{document}")
        stem = folder / f"{side}-{page}"
        stem.with_suffix(".tex").write_text(source)
        result = subprocess.run(["lualatex", "-no-shell-escape", "-halt-on-error", "-interaction=nonstopmode",
                                 f"-output-directory={folder}", str(stem.with_suffix('.tex'))],
                                cwd=ROOT, capture_output=True, text=True)
        stem.with_suffix(".build.log").write_text(result.stdout + result.stderr)
        assert result.returncode == 0, f"Compile failed: {stem}"
        subprocess.run(["pdftoppm", "-r", "65", "-png", "-singlefile", str(stem.with_suffix('.pdf')), str(stem)],
                       check=True, capture_output=True)
        bbox = subprocess.check_output(["pdftotext", "-bbox", str(stem.with_suffix('.pdf')), "-"], text=True)
        stem.with_suffix(".bbox.html").write_text(bbox)
        words = [n for n in ET.fromstring(bbox).iter() if n.tag.endswith("word") and n.text == "Protected"]
        assert len(words) == 1
        w = words[0].attrib
        # Text bbox is measured by Poppler from the actual PDF, not our Lua model.
        scale = 65 / 72
        text_box = tuple(round(float(w[k]) * scale) for k in ("xMin", "yMin", "xMax", "yMax"))
        with Image.open(stem.with_suffix(".png")) as im:
            count = colored(im, page_box(1, 10, 4, 15))
            assert count == 0, f"{side}/{page}: {count} colored pixels entered the physical reservation"
            assert colored(im, page_box(0.3, 11, 0.8, 14)) > 50, "Control area was not painted"
            content_count = colored(im, text_box)
            assert content_count == 0, f"{side}/{page}: {content_count} colored pixels in measured text box {text_box}; see {stem}"
        print("PASS", side, page, f"offsets {h}/{v}mm")
    print(f"offsetcheck: {len(cases)} rendered physical and content-relative reservations passed")


if __name__ == "__main__":
    main()
