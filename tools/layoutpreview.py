"""Build matched examples and a contact sheet: python3 tools/layoutpreview.py."""
from pathlib import Path
import subprocess

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = (
    ("full", "Full / original", "density=full"),
    ("balanced", "Balanced / 0.6", "density=balanced"),
    ("airy", "Airy / 0.3", "density=airy"),
    ("whitespace", "Airy / reserved whitespace", "density=airy,spill=false,footer=false,text-gap=6mm"),
)


def main():
    (ROOT / "build").mkdir(exist_ok=True)
    (ROOT / "gallery").mkdir(exist_ok=True)
    panels = []
    for name, label, options in VARIANTS:
        job = f"build/layout-{name}"
        result = subprocess.run(
            ["lualatex", "-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error",
             f"-jobname={job}", rf"\def\layoutoptions{{{options}}}\input{{layout-demo.tex}}"],
            cwd=ROOT, capture_output=True, text=True,
        )
        (ROOT / f"{job}.build.log").write_text(result.stdout + result.stderr)
        if result.returncode:
            raise SystemExit(f"Compilation failed; see {job}.build.log")
        subprocess.run(
            ["pdftoppm", "-png", "-r", "60", "-singlefile", f"{job}.pdf", job],
            cwd=ROOT, check=True, capture_output=True,
        )
        with Image.open(ROOT / f"{job}.png") as source:
            panel = Image.new("RGB", (source.width + 24, source.height + 52), "#ececea")
            panel.paste(source.convert("RGB"), (12, 40))
            ImageDraw.Draw(panel).text((14, 14), label, fill="#242424")
            panels.append(panel)
        print(f"built {job}.pdf")
    width, height = panels[0].size
    sheet = Image.new("RGB", (width * 2, height * 2), "#ececea")
    for i, panel in enumerate(panels):
        sheet.paste(panel, ((i % 2) * width, (i // 2) * height))
    sheet.save(ROOT / "gallery/layout-controls.png")
    print("saved gallery/layout-controls.png")


if __name__ == "__main__":
    main()
