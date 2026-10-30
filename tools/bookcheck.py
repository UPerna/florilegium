"""Real LaTeX checks for book sides, reserved content, headings and font fallback."""
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
BUILD=ROOT/"build/book-check"
COMMON=r"\renewcommand\rmdefault{cmr}\renewcommand\sfdefault{cmss}\renewcommand\ttdefault{cmtt}"


def main():
    BUILD.mkdir(parents=True,exist_ok=True)
    cases={
      "book-sides":r"""\documentclass[twoside]{article}\usepackage[inner=22mm,outer=68mm,bindingoffset=5mm]{geometry}
        \usepackage[grown,side=outer,style=quiet]{florilegium}\hoffset=3mm\voffset=4mm
        \begin{document}\directlua{local g=florilegium.geometry(0.15,'outer');assert(g.mirror);assert(g.textleft>6)}Odd.
        \clearpage\directlua{local g=florilegium.geometry(0.15,'outer');assert(not g.mirror);assert(g.textleft>6)}Even.\end{document}""",
      "reserve-float":r"""\documentclass{article}\usepackage[left=68mm,right=22mm]{geometry}
        \usepackage[grown,style=quiet]{florilegium}\directlua{local draw=require('grow').page;seen={};require('grow').page=function(g)
        seen[tex.count['c@page']]=g.reserves;return draw(g) end}
        \begin{document}First page.\begin{figure}[p]\begin{florilegiumprotect}[4mm]
        \fbox{A protected figure travels with its float.}\end{florilegiumprotect}\end{figure}
        \clearpage\directlua{assert(seen[1] and next(seen[1])==nil)
        assert(seen[2] and next(seen[2])~=nil)}\end{document}""",
      "initial-fallback":r"""\documentclass{article}\usepackage[nomargin]{florilegium}
        \florilegiuminitialfont{no-such-font.otf}\begin{document}\florilegiuminitial{E}very letter is searchable.\end{document}""",
      "reserved-page":r"""\documentclass{article}\usepackage[left=68mm,right=22mm]{geometry}\usepackage[grown,style=chapter]{florilegium}
        \begin{document}\florilegiumreserve{1cm}{10cm}{3cm}{4cm}An intentional blank region.\florilegiumtextend\end{document}""",
    }
    for cls in ("article","scrartcl","scrbook"):
      for titlesec in ((False,True) if cls=="article" else (False,)):
        for after in ((False,True) if titlesec else (False,)):
          package=r"\usepackage{titlesec}" if titlesec else ""
          core=r"\usepackage[left=68mm,right=22mm]{geometry}\usepackage[grown,sections,style=quiet]{florilegium}"
          opening=r"\chapter[Short chapter]{Long chapter}" if cls=="scrbook" else ""
          cases[f"headings-{cls}-{titlesec}-{after}"]=(rf"\documentclass{{{cls}}}"+(core+package if after else package+core)
            +r"\usepackage{hyperref}\begin{document}\tableofcontents"+opening+r"\section[Short]{Long heading\label{inside}}\label{outside}Text.\subsection{Subheading}Text.\section*{Unnumbered}Text.\nameref{inside}, \nameref{outside}.\end{document}")
    for name,source in cases.items():
      # Set fonts after the class so incomplete local luaotfload installations can use Computer Modern.
      at=source.index("}")+1
      source=source[:at]+COMMON+source[at:]
      path=BUILD/(name+".tex");path.write_text(source)
      for run in range(2 if name.startswith("headings") else 1):
        result=subprocess.run(["lualatex","-no-shell-escape","-interaction=nonstopmode","-halt-on-error",
                               f"-output-directory={BUILD}",str(path)],cwd=ROOT,capture_output=True,text=True)
        path.with_suffix(".build.log").write_text(result.stdout+result.stderr)
        if result.returncode:raise AssertionError(f"{name} failed; see {path.with_suffix('.build.log')}")
      toc=path.with_suffix(".toc")
      if toc.exists(): assert "headmark" not in toc.read_text() and "florilegium" not in toc.read_text()
      if name.startswith("headings"):
        for extension in (".aux",".out"):
          data=path.with_suffix(extension).read_text()
          assert "headmark" not in data and "florilegium" not in data
      print("PASS",name)
    text=subprocess.check_output(["pdftotext",str(BUILD/"initial-fallback.pdf"),"-"],text=True)
    assert "Every letter is searchable" in " ".join(text.split())
    print(f"bookcheck: {len(cases)} cases passed; fallback initial remains searchable")


if __name__=="__main__":main()
