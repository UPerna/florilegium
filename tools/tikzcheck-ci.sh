#!/bin/sh
# CI's tikz job: the TikZ library's pure-TikZ side on every core, in latex-action's TeX Live
# (which runs this file as its "compiler"). Locally, from the repository's root, with
# pdflatex, lualatex and pdftoppm on the path:
#   sh tools/tikzcheck-ci.sh
# Both at once, so that the cores stay busy while page 1, the longest run, finishes:
# 1. Every page of specimen-tikz.tex under pdfLaTeX, each page a run of its own
#    (tools/specimen-page.tex), page 1 at full priority and the rest niced. A page fails on
#    any TeX error (main memory included: extra_mem_top as specimen-tikz.tex asks), and on the
#    library's warning that pgf's number scanner has changed, since its string-pool patch is
#    then not applied and a long pure-TikZ run under pdfLaTeX fills the pool (pgf 3.1.12 did,
#    board #5114). A leak that would fill the pool only over all eight pages in one run does
#    not show here.
# 2. tools/tikzcheck.lua draw quick, niced: about 240 pics drawn in pure TikZ and by the Lua
#    engine and compared, each build in as many runs at once as there are cores.
# Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
set -eu
export extra_mem_top=20000000
out=build/specimen
rm -rf "$out"
mkdir -p "$out"
pages=$(( $(grep -c '^\\newpage' specimen-tikz.tex) + 1 ))
t0=$(date +%s)
pids=""
p=1
while [ "$p" -le "$pages" ]; do
  if [ "$p" -eq 1 ]; then nice=""; else nice="nice -n 5"; fi
  $nice pdflatex -interaction=nonstopmode -halt-on-error -output-directory="$out" -jobname="page-$p" \
    "\\def\\specimenpage{$p}\\input{tools/specimen-page.tex}" >/dev/null 2>&1 &
  pids="$pids $!"
  p=$((p + 1))
done
nice -n 5 texlua tools/tikzcheck.lua draw quick > build/tikzcheck-draw.out 2>&1 &
draw=$!
status=0
p=1
for pid in $pids; do
  log="$out/page-$p.log"
  if ! wait "$pid"; then
    echo "FAIL  page $p of specimen-tikz.tex under pdfLaTeX ($log):"
    grep -A12 '^!' "$log" | head -24
    status=1
  elif grep -q "number scanner is not in a form" "$log"; then
    echo "FAIL  page $p of specimen-tikz.tex: the TikZ library could not patch pgf's number scanner"
    status=1
  else
    echo "ok    page $p of specimen-tikz.tex under pdfLaTeX, $(grep -o '[0-9]* words of memory out of [0-9]*' "$log" | head -1)"
  fi
  p=$((p + 1))
done
echo "      $pages pages in $(( $(date +%s) - t0 )) s"
wait "$draw" || status=1
cat build/tikzcheck-draw.out
echo "      all in $(( $(date +%s) - t0 )) s"
exit "$status"
