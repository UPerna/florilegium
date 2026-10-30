"""Check vector export and compare repeated inline drawings with reused PDF Forms."""
from pathlib import Path
import json
import subprocess
import xml.etree.ElementTree as ET
from PIL import Image, ImageChops, ImageStat
from exportasset import ROOT, export, picture


def compile_tex(name, source):
    path = ROOT / "build/assets" / f"{name}.tex"
    path.write_text(source)
    result = subprocess.run(["lualatex", "-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error",
                             f"-output-directory={path.parent}", str(path)], cwd=ROOT, capture_output=True, text=True)
    path.with_suffix(".build.log").write_text(result.stdout + result.stderr)
    if result.returncode: raise AssertionError(f"Compile failed: {path}")
    return path.with_suffix(".pdf")


def render(path):
    stem = path.with_suffix("")
    subprocess.run(["pdftoppm", "-png", "-r", "90", "-singlefile", str(path), str(stem)], check=True, capture_output=True)
    with Image.open(stem.with_suffix(".png")) as image: return image.convert("RGB")


def main():
    folder = ROOT / "build/assets"
    pdf, svg = export("flower", 7, 1.2, "2456C4", folder / "flower")
    tree = ET.parse(svg)
    assert sum(n.tag.endswith("path") for n in tree.iter()) > 10
    assert not any(n.tag.endswith("image") for n in tree.iter())
    preamble = (r"\documentclass{article}\renewcommand\rmdefault{cmr}"
                r"\usepackage[margin=1cm]{geometry}\usepackage[nomargin]{florilegium}\pagestyle{empty}"
                r"\setlength\parindent{0pt}\florilegiumdeclareasset{flower}{build/assets/flower.pdf}"
                r"\begin{document}")
    inline = (r"\resizebox{18mm}{!}{\directlua{florilegium.seed(1,7)}" + picture("flower", 1.2) + "}")
    reused = r"\florilegiumuseasset[width=18mm]{flower}"
    paths = []
    for name, item in (("inline", inline), ("reused", reused)):
        rows = [r"\noindent " + (item + r"\hspace{2mm}")*8 + r"\par" for _ in range(6)]
        paths.append(compile_tex(name, preamble + "\n".join(rows) + r"\end{document}"))
    assert paths[1].stat().st_size < paths[0].stat().st_size * 0.5, "Form reuse did not materially reduce this repeated-asset PDF"
    a,b = map(render,paths)
    assert a.size == b.size
    mean = sum(ImageStat.Stat(ImageChops.difference(a,b)).mean)/3
    assert mean < 1, f"Reused asset rendering differs: mean pixel error {mean}"
    # Round-trip the exported SVG to PNG independently of the PDF renderer.
    subprocess.run(["inkscape",str(svg),"--export-type=png",f"--export-filename={folder/'flower-svg.png'}",
                    "--export-width=300","--export-height=300"],check=True,capture_output=True)
    with Image.open(folder/"flower-svg.png") as im:
        alpha=im.convert("RGBA").getchannel("A")
        assert alpha.getbbox() is not None and alpha.getextrema()[0]==0,"SVG lacks transparent background"
    report={"inline_bytes":paths[0].stat().st_size,"reused_bytes":paths[1].stat().st_size,
            "reduction_percent":round(100*(1-paths[1].stat().st_size/paths[0].stat().st_size),1),
            "mean_pixel_error":round(mean,4),"svg_paths":sum(n.tag.endswith("path") for n in tree.iter())}
    (folder/"reuse-report.json").write_text(json.dumps(report,indent=2))
    print("exportcheck:",json.dumps(report))


if __name__ == "__main__": main()
