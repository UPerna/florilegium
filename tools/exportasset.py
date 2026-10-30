"""Export a seeded motif to transparent vector PDF and plain SVG.

Example: python3 tools/exportasset.py flower --seed 7 --output build/assets/flower
Requires LuaLaTeX and Inkscape 1.x. No shell escape or raster tracing is used.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MOTIFS = ("flower", "lily", "leaf", "leaflet", "butterfly", "bee", "hedera", "rosette", "bud", "seedhead")


def picture(motif, size):
    return (r"\begin{tikzpicture}\path[use as bounding box](-3,-3) rectangle (3,3);"
            + rf"\florilegiumdraw{{{motif}}}{{{size}}}" + r"\end{tikzpicture}")


def export(motif, seed, size, ink, output):
    if motif not in MOTIFS or not 0.1 <= size <= 2 or not 0 <= seed < 2**31 or not re.fullmatch(r"[0-9A-Fa-f]{6}", ink):
        raise ValueError("Invalid motif, size (0.1..2), seed (0..2^31-1), or six-digit ink color")
    for executable in ("lualatex", "inkscape"):
        if shutil.which(executable) is None:
            raise RuntimeError(f"{executable} is required for vector export")
    output = Path(output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    source = (r"\documentclass{article}\renewcommand\rmdefault{cmr}"
              r"\usepackage[paperwidth=6cm,paperheight=6cm,margin=0pt,noheadfoot]{geometry}"
              r"\usepackage[nomargin]{florilegium}\pagestyle{empty}\setlength\parindent{0pt}"
              + rf"\definecolor{{ink}}{{HTML}}{{{ink}}}"
              + r"\begin{document}\noindent" + rf"\directlua{{florilegium.seed(1,{seed})}}"
              + picture(motif, size) + r"\end{document}")
    texfile = output.with_suffix(".tex")
    texfile.write_text(source)
    result = subprocess.run(
        ["lualatex", "-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error",
         f"-output-directory={output.parent}", str(texfile)], cwd=ROOT, capture_output=True, text=True)
    output.with_suffix(".build.log").write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f"LuaLaTeX failed; see {output.with_suffix('.build.log')}")
    pdf, svg = output.with_suffix(".pdf"), output.with_suffix(".svg")
    result = subprocess.run(
        ["inkscape", str(pdf), "--export-type=svg", "--export-plain-svg",
         f"--export-filename={svg}"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode or not svg.exists():
        raise RuntimeError("Inkscape SVG conversion failed: " + result.stderr)
    tree = ET.parse(svg)
    if any(node.tag.rsplit("}", 1)[-1] == "image" for node in tree.iter()):
        raise RuntimeError("SVG conversion introduced a raster image; refusing to call this vector export")
    return pdf, svg


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("motif", choices=MOTIFS)
    parser.add_argument("--seed", type=int, default=7)
    parser.add_argument("--size", type=float, default=1.2)
    parser.add_argument("--ink", default="2456C4")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    prefix = args.output or ROOT / "build/assets" / args.motif
    try:
        for path in export(args.motif, args.seed, args.size, args.ink, prefix): print(path)
    except (RuntimeError, ValueError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
