"""Exercise the public TeX options and setup command with actual LuaLaTeX runs."""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/layout-smoke"
PREAMBLE = r"""\documentclass{article}
\renewcommand\rmdefault{cmr}
\usepackage[a4paper,left=68mm,right=22mm,top=32mm,bottom=30mm]{geometry}
"""

# Each case is (name, package options, setup/assertions, expected error substring).
CASES = (
    ("package-options", "grown,density=airy,spill=false,footer=false,header=false,text-gap=6mm",
     r"""\directlua{assert(florilegium.layout.density==0.3)
       assert(not florilegium.layout.spill and not florilegium.layout.footer and not florilegium.layout.header)
       local g=florilegium.geometry(florilegium.layout.text_gap)
       assert(math.abs(g.textleft-g.colright-0.25-0.6)<0.00001)}""", None),
    ("setup-merge", "grown", r"""\florilegiumsetup{density=balanced,footer=false}
       \florilegiumsetup{density=0.3}
       \directlua{assert(florilegium.layout.density==0.3 and not florilegium.layout.footer)
       assert(florilegium.layout.spill and florilegium.layout.header)}""", None),
    ("minimum", "grown,density=0.2,text-gap=0pt", "", None),
    ("animation-setup", "grown", r"""\directlua{
       local grow= require('grow'); local ink=florilegium.ink
       local page,emit=grow.page,ink.emit; local calls=0
       grow.page=function(g) calls=calls+1; return {rec={},total=1} end
       ink.emit=function() end
       florilegium.configure('header',false); florilegium.frame(1,1,'')
       florilegium.grown(6,0,0); florilegium.grown(6,0,0); assert(calls==1)
       florilegium.configure('density','airy'); florilegium.grown(6,0,0); assert(calls==2)
       florilegium.configure('footer',false); florilegium.grown(6,0,0); assert(calls==3)
       grow.page,ink.emit=page,emit}""", None),
    ("density-range", "grown,density=1.1", "", "density must be"),
    ("density-name", "grown,density=busy", "", "density must be"),
    ("negative-gap", "grown,text-gap=-1mm", "", "text-gap must be"),
    ("wide-gap", "grown,text-gap=6cm", "", "less than 18 mm"),
    ("boolean", "grown,spill=yes", "", "spill must be true or false"),
    ("unknown-key", "grown,unknown=true", "", "do not know the key"),
    ("authored-options", "density=airy", "", "Layout controls require the grown option"),
    ("authored-setup", "", r"\florilegiumsetup{density=airy}", "Layout controls require the grown option"),
)


def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, options, setup, expected_error in CASES:
        path = BUILD / f"{name}.tex"
        path.write_text(PREAMBLE + rf"\usepackage[{options}]{{florilegium}}" + "\n" + setup
                        + r"\begin{document}Layout controls.\florilegiumtextend\end{document}")
        result = subprocess.run(
            ["lualatex", "-no-shell-escape", "-interaction=nonstopmode", "-halt-on-error",
             f"-output-directory={BUILD}", str(path)],
            cwd=ROOT, capture_output=True, text=True,
        )
        output = result.stdout + result.stderr
        (BUILD / f"{name}.build.log").write_text(output)
        ok = (result.returncode == 0 if expected_error is None
              else result.returncode != 0 and expected_error in output)
        print(f"{'PASS' if ok else 'FAIL'} {name}")
        if not ok:
            failures.append(name)
    if failures:
        raise SystemExit("Unexpected results: " + ", ".join(failures) + f"; see {BUILD}")
    print(f"layoutsmoke: {len(CASES)} cases passed")


if __name__ == "__main__":
    main()
