"""Compare real LuaLaTeX/XeLaTeX documents, paths, text, metadata and stale rebuilds."""
import argparse
import hashlib
import os
import re
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops, ImageStat
from build import build, ROOT
from visualcheck import colored, page_box

FONTS = r"\usepackage[T1]{fontenc}\renewcommand\rmdefault{cmr}"
GEOMETRY = r"\usepackage[a4paper,left=68mm,right=22mm,top=32mm,bottom=30mm]{geometry}"
# Capture only complete illustration streams, excluding invisible text and the
# Xe driver canvas translation. This reaches the real host paths in both engines.
CAPTURE = r"""\ifLuaTeX\directlua{
 local ink=require('ink');local original=ink.backend.literal
 local file=assert(io.open('paths.bin','wb'))
 ink.backend.literal=function(s,mode)
  if mode==nil and s:sub(1,1)=='q' then file:write(string.len(s),string.char(10),s,string.char(10));file:flush() end
  return original(s,mode) end
 florilegium.close_capture=function() file:close();ink.backend.literal=original end}
 \AddToHook{enddocument/afterlastpage}{\directlua{florilegium.close_capture()}}\fi"""


def signature(path):
    digest = hashlib.sha256()
    size = 0
    if path.exists():
        with path.open("rb") as file:
            for data in iter(lambda: file.read(65536), b""):
                digest.update(data)
                size += len(data)
    return size, digest.hexdigest()


def raster(pdf):
    prefix = pdf.with_suffix("")
    result = subprocess.run(["pdftoppm", "-png", "-r", "65", str(pdf), str(prefix)], capture_output=True, text=True)
    if result.returncode:
        raise AssertionError(f"PDF rendering failed: {pdf}\n{result.stderr}")
    images = []
    for path in sorted(pdf.parent.glob(prefix.name + "-[0-9]*.png")):
        with Image.open(path) as im:
            images.append(im.convert("RGB"))
    return images


def main(require_outlines=False):
    (ROOT / "build").mkdir(exist_ok=True)
    folder = Path(tempfile.mkdtemp(prefix="engine-check-", dir=ROOT / "build"))
    print("enginecheck outputs:", folder, flush=True)
    cases = {
        "primitives": (r"\documentclass{article}" + FONTS + GEOMETRY
          + r"\usepackage[grown,nomargin,sections]{florilegium}" + CAPTURE
          + r"\florilegiuminitialfont{no-such-font.otf}\begin{document}\section{Heading}"
            r"\begin{tikzpicture}\florilegiumdraw{flower}{1}\begin{scope}[shift={(3,0)},rotate=23]"
            r"\florilegiumdraw{leaf}{1.4}\end{scope}\end{tikzpicture}\florilegiumdivider"
            r"\florilegiumsetup{color-mode=mono}\begin{tikzpicture}\florilegiumdraw{butterfly}{1}\end{tikzpicture}"
            r"\florilegiuminitial{E}very letter remains searchable.\newpage"
            r"\florilegiumsetup{color-mode=color}\begin{tikzpicture}\florilegiumdraw{rosette}{1}\end{tikzpicture}\end{document}"),
        "book": (r"\documentclass[twoside]{article}" + FONTS
          + r"\usepackage[a4paper,inner=22mm,outer=68mm,bindingoffset=4mm]{geometry}"
            r"\usepackage[grown,side=outer,style=quiet,pagenumber,variation=spread,seed=7,sections,aging]{florilegium}" + CAPTURE
          + r"\hoffset=5mm\voffset=-3mm\pagestyle{empty}\pagenumbering{roman}\setcounter{page}{14}"
            r"\begin{document}\section{Quiet page}\begin{florilegiumprotect}[3mm]Protected contents.\end{florilegiumprotect}"
            r"\florilegiumreserve[2mm]{1cm}{10cm}{3cm}{4cm}Text with a bloom.\florilegiumbloom\clearpage"
            r"\florilegiumsetup{color-mode=mono}\section{Monochrome page}Text.\clearpage"
            r"\pagenumbering{arabic}\setcounter{page}{38}\florilegiumsetup{style=chapter,color-mode=color}"
            r"\section{Chapter treatment}Text.\florilegiumdivider\clearpage\section{Facing treatment}Text."
            r"\begin{figure}[p]\noindent\hspace*{-55mm}\begin{minipage}{30mm}"
            r"\begin{florilegiumprotect}[4mm]\fbox{\parbox[c][30mm][c]{24mm}{Deferred protected box.}}"
            r"\end{florilegiumprotect}\end{minipage}\end{figure}"
            r"\clearpage\end{document}"),
        "authored": (r"\documentclass{article}" + FONTS + GEOMETRY
          + r"\def\florilegiumseed{7}\usepackage{florilegium}" + CAPTURE
          + r"\begin{document}An authored garden.\end{document}"),
        "koma": (r"\documentclass{scrbook}" + FONTS
          + r"\usepackage[a4paper,inner=22mm,outer=68mm]{geometry}"
            r"\usepackage[grown,side=outer,style=quiet,sections]{florilegium}\usepackage{hyperref}"
          + CAPTURE + r"\begin{document}\tableofcontents\chapter[Short]{Chapter title}\section{Section title\label{inside}}"
            r"\nameref{inside}.\end{document}"),
        "initial": (r"\documentclass{article}" + FONTS + GEOMETRY
          + r"\usepackage[nomargin]{florilegium}" + CAPTURE
          + r"\begin{document}\florilegiuminitial{E}very outline is part of the garden.\end{document}"),
        "fallback-label": (r"\documentclass{article}" + FONTS + GEOMETRY
          + r"\usepackage[grown,style=quiet,pagenumber]{florilegium}" + CAPTURE
          + r"\renewcommand\thepage{A-1}\begin{document}A nonnumeric page label retains its normal footer.\end{document}"),
        "animation": (r"\documentclass{article}" + FONTS + GEOMETRY
          + r"\usepackage[grown,style=quiet]{florilegium}" + CAPTURE
          + r"\pagestyle{empty}\begin{document}\setcounter{page}{4}\florilegiumframe{1}{2}Animation frame."
            r"\clearpage\setcounter{page}{4}\florilegiumframe{2}{2}Animation frame.\end{document}"),
        "assets": (r"\documentclass{article}" + FONTS
          + r"\usepackage[nomargin]{florilegium}\florilegiumdeclareasset{flower}{examples/assets/flower.pdf}"
          + CAPTURE + r"\begin{document}Reusable vector assets.\par"
            r"\florilegiumuseasset[width=20mm]{flower}\florilegiumuseasset[width=20mm]{flower}\end{document}"),
    }
    for after in (False, True):
        core = r"\usepackage[grown,sections,style=quiet]{florilegium}"
        title = r"\usepackage{titlesec}"
        cases[f"titlesec-{after}"] = (r"\documentclass{article}" + FONTS + GEOMETRY
          + (core + title if after else title + core) + r"\usepackage{hyperref}" + CAPTURE
          + r"\begin{document}\tableofcontents\section[Short]{Heading\label{inside}}"
            r"\subsection{Subheading}\nameref{inside}.\section*{Starred}\end{document}")
    old_capture = os.environ.get("FLORILEGIUM_CAPTURE")
    try:
        for name, source in cases.items():
            path = folder / (name + ".tex")
            path.write_text(source)
            artifacts, captures, protected_regions = [], [], []
            for engine in ("lua", "xe"):
                print("BUILD", name, engine, flush=True)
                out = folder / name / engine
                out.mkdir(parents=True, exist_ok=True)
                capture = out / "paths.bin"
                capture.unlink(missing_ok=True)
                os.environ["FLORILEGIUM_CAPTURE"] = capture.name
                pdf = build(path, engine, out)
                artifacts.append(pdf)
                captures.append(signature(capture))
                text = subprocess.check_output(["pdftotext", str(pdf), "-"], text=True)
                if name in ("primitives", "initial"):
                    assert "Every" in text, f"{name}/{engine}: initial is not searchable"
                if name == "book":
                    assert all(label in text.split() for label in ("xiv", "xv", "38", "39", "40")), "Page label missing from PDF text"
                    bbox = subprocess.check_output(["pdftotext", "-bbox", str(pdf), "-"], text=True)
                    labels = [n for n in ET.fromstring(bbox).iter() if n.tag.endswith("word") and n.text in ("xiv", "xv", "38", "39", "40")]
                    assert len(labels) == 5
                    for label in labels:
                        left = float(label.attrib["xMin"]) * 2.54 / 72
                        assert (left < 7 if label.text in ("xiv", "38", "40") else left > 14), "Search label is on the wrong physical side"
                    if engine == "xe":
                        records = pdf.with_suffix(".flo").read_text()
                        match = re.search(r'MARK\{n=5,kind="reserve_box",arg=\{w=(\d+),h=(\d+)', records)
                        assert match and int(match[1]) > 1000000 and int(match[2]) > 1000000, "Deferred float lost its page or dimensions"
                    word = next(n for n in ET.fromstring(bbox).iter() if n.tag.endswith("word") and n.text == "Deferred")
                    x, y = float(word.attrib["xMin"]), float(word.attrib["yMin"])
                    mm = 72 / 25.4
                    protected_regions.append(tuple(round(v * 65 / 72) for v in (x-0.2*mm,y-5*mm,x+23.5*mm,y+16*mm)))
                if name == "fallback-label":
                    assert "A-1" in text, "Unsupported botanical label lost its ordinary footer"
                for ext in (".aux", ".out", ".toc"):
                    metadata = pdf.with_suffix(ext)
                    if metadata.exists():
                        data = metadata.read_text()
                        assert "headmark" not in data and "headingmark" not in data, "Heading marker leaked into metadata"
            a, b = map(raster, artifacts)
            assert len(a) == len(b), f"Page count differs: {name}"
            errors = []
            for left, right in zip(a, b):
                assert left.size == right.size
                errors.append(sum(ImageStat.Stat(ImageChops.difference(left, right)).mean) / 3)
            assert max(errors) < 0.6, f"{name}: renderer pixels differ {errors}"
            if name == "book":
                for index, pages in enumerate((a, b)):
                    assert colored(pages[0], page_box(1, 10, 4, 14)) == 0, "Physical reservation shifted on an offset page"
                    mono = pages[1]
                    assert ImageChops.difference(mono.getchannel("R"), mono.getchannel("G")).getbbox() is None
                    assert ImageChops.difference(mono.getchannel("G"), mono.getchannel("B")).getbbox() is None
                    assert colored(pages[4], protected_regions[index]) == 0, "Ornament entered the deferred protected box"
            if name in ("primitives", "authored", "initial", "animation", "assets"):
                assert captures[0] == captures[1], f"{name}: native and external vector paths differ"
            if name == "animation":
                log = artifacts[1].with_name("animation.render-1.log").read_text()
                assert log.count("florilegium: recorded") == 1, "Xe rebuilt a matching animation recording"
            if name == "assets":
                assert colored(a[0], (0, 0, *a[0].size)) > 100, "Reusable PDF assets were not drawn"
            if name == "initial" and require_outlines:
                assert captures[0][0] > 0, "Decorated initial was not exercised"
                meta = artifacts[1].with_name("initial-flo.tex").read_text()
                assert "initialstatus" in meta and "{1}{1}" in meta, "Xe font outline reader fell back"
            print("PASS", name, "pages", len(a), "mean pixel errors", [round(e, 4) for e in errors], flush=True)
        # A second build in the same directory must replace stale drawing data.
        path = folder / "changed source.tex"
        base = r"\documentclass{article}" + FONTS + r"\usepackage[nomargin]{florilegium}\begin{document}\begin{tikzpicture}\florilegiumdraw{MOTIF}{1}\end{tikzpicture}\end{document}"
        path.write_text(base.replace("MOTIF", "flower"))
        out = folder / "output with spaces"
        first = raster(build(path, "xe", out))[0]
        path.write_text(base.replace("MOTIF", "butterfly"))
        second = raster(build(path, "xe", out))[0]
        assert ImageChops.difference(first, second).getbbox(), "Stale drawing survived a rebuild"
        for name, option, body in (
            ("density", "grown,density=2", "Text."),
            ("reservation", "grown", r"\florilegiumreserve{0pt}{0pt}{-1cm}{1cm}Text."),
            ("font", "nomargin,initial-fallback=error", r"\florilegiuminitialfont{missing.otf}\florilegiuminitial{E}very"),
            ("unused-config", "grown,nomargin,density=2", "Text."),
            ("unused-reservation", "grown,nomargin", r"\florilegiumreserve{0pt}{0pt}{-1cm}{1cm}Text."),
            ("padding", "grown,nomargin", r"\begin{florilegiumprotect}[-1mm]Text.\end{florilegiumprotect}"),
        ):
            path = folder / ("invalid-" + name + ".tex")
            path.write_text(r"\documentclass{article}" + FONTS + GEOMETRY + rf"\usepackage[{option}]{{florilegium}}\begin{{document}}" + body + r"\end{document}")
            try:
                build(path, "xe", folder / ("invalid-" + name))
            except RuntimeError:
                pass
            else:
                raise AssertionError("Xe accepted invalid " + name)
        print("enginecheck: 10 dual-engine documents, vector/text/metadata/mono/offset parity, cached animation, PDF assets, stale rebuilds and 6 rejected inputs passed")
    finally:
        if old_capture is None:
            os.environ.pop("FLORILEGIUM_CAPTURE", None)
        else:
            os.environ["FLORILEGIUM_CAPTURE"] = old_capture


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--require-outlines", action="store_true")
    main(parser.parse_args().require_outlines)
