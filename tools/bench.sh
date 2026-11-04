#!/bin/sh
# Time an earlier release's margin against this one's, and the TikZ library's engines, on
# this machine, and print the results as a Markdown table (for a release's notes).
#   make bench RUN=tools/in-docker     (puts v1.3 from its tag in build/bench/v1.3 first)
#   sh tools/bench.sh OLD [RUNS]       OLD: an earlier release's files; RUNS: default 3
# A time is the median of RUNS runs; the pure-TikZ ones run once (each takes minutes). The
# margin rows build tools/bench.tex with each release's package beside it, and the same text
# with nomargin; the garden's share of a page is the difference over the pages. The TikZ
# rows build tools/bench-tikz.tex (one strip of three plants) in pure TikZ under pdfLaTeX
# and LuaLaTeX and with the Lua engine. It prints two Markdown tables: what is procedural
# in each release and what draws it, then times and sizes side by side.
# Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
set -e
old=${1:?usage: tools/bench.sh OLD-RELEASE-DIR [RUNS]}
runs=${2:-3}
B=build/bench
export SOURCE_DATE_EPOCH=0 FORCE_SOURCE_DATE=1   # the same PDF bytes on every run

now() { date +%s.%N; }
# run DIR RUNS COMMAND...: run COMMAND in DIR (output to /dev/null), print the median seconds
run() {
  dir=$1 n=$2
  shift 2
  ts=""
  i=0
  while [ "$i" -lt "$n" ]; do
    t0=$(now)
    if ! (cd "$dir" && "$@" >/dev/null 2>&1); then echo "bench: failed in $dir: $*" >&2; exit 1; fi
    t1=$(now)
    ts="$ts $(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%.3f", b - a }')"
    i=$((i + 1))
  done
  echo "$ts" | tr ' ' '\n' | grep . | sort -n | awk '{ a[NR] = $1 } END { print a[int((NR + 1) / 2)] }'
}
# pages and bytes of a PDF, from the log's "Output written on x.pdf (N pages, M bytes)."
written() { sed -n 's/^Output written on .* (\([0-9]*\) pages\{0,1\}, \([0-9]*\) bytes).*/\1 \2/p' "$1" | tail -1; }
mb() { awk -v b="$1" 'BEGIN { if (b >= 1e6) printf "%.1f MB", b / 1e6; else printf "%.0f KB", b / 1e3 }'; }

mkdir -p "$B/new"
cp florilegium.sty florilegium*.lua tikzlibraryflorilegium*.tex tools/bench.tex tools/bench-tikz.tex "$B/new/"
cp tools/bench.tex "$old/"
LUALATEX="lualatex -interaction=batchmode"

# ---- the margin: each release's grown page, and the text alone
margin() {   # DIR -> "seconds-garden seconds-text pages bytes-garden bytes-text"
  tg=$(run "$1" "$runs" $LUALATEX -jobname=bench "\def\florilegiumseed{7}\input{bench.tex}") || exit 1
  tt=$(run "$1" "$runs" $LUALATEX -jobname=bench-text "\def\florilegiumseed{7}\def\benchoptions{,nomargin}\input{bench.tex}") || exit 1
  set -- "$1" $(written "$1/bench.log") $(written "$1/bench-text.log")
  echo "$tg $tt $2 $3 $5"
}
# (assigned first: `set -- $(...)` would hide a failed build, since set itself succeeds)
r=$(margin "$old") || exit 1
set -- $r
o_tg=$1 o_tt=$2 o_p=$3 o_bg=$4 o_bt=$5
r=$(margin "$B/new") || exit 1
set -- $r
n_tg=$1 n_tt=$2 n_p=$3 n_bg=$4 n_bt=$5

# ---- the TikZ library: one strip, pure TikZ under pdfLaTeX and LuaLaTeX, then the Lua engine
t_pdf=$(run "$B/new" 1 env extra_mem_top=10000000 pdflatex -interaction=batchmode -jobname=strip-pdftex "\def\benchengine{tikz}\input{bench-tikz.tex}")
set -- $(written "$B/new/strip-pdftex.log")
p_pdf=$2
mem=$(sed -n 's/^ *\([0-9]*\) words of memory out of.*/\1/p' "$B/new/strip-pdftex.log" | tail -1)
t_tikz=$(run "$B/new" 1 $LUALATEX -jobname=strip "\def\benchengine{tikz}\input{bench-tikz.tex}")
set -- $(written "$B/new/strip.log")
p_tikz=$2
mv "$B/new/strip.pdf" "$B/new/strip-tikz.pdf"
t_lua=$(run "$B/new" "$runs" $LUALATEX -jobname=strip "\def\benchengine{lua}\input{bench-tikz.tex}")
set -- $(written "$B/new/strip.log")
p_lua=$2

# ---- the tables: what each release draws and with what, then times and sizes side by side
cpu=$(awk -F': ' '/model name/ { print $2; exit }' /proc/cpuinfo)
per() { awk -v a="$1" -v b="$2" -v p="$3" 'BEGIN { printf "%.2f s", (a - b) / p }'; }
perb() { mb "$(awk -v a="$1" -v b="$2" -v p="$3" 'BEGIN { print (a - b) / p }')"; }
oname=$(sed -n 's/.*\\ProvidesPackage{florilegium}\[[^]]* v\([0-9.]*\).*/v\1/p' "$old/florilegium.sty")
nname=$(sed -n 's/.*\\ProvidesPackage{florilegium}\[[^]]* v\([0-9.]*\).*/v\1/p' florilegium.sty)
[ "$nname" = "$oname" ] && nname="this tree"
echo "**What is procedural, and what draws it.** Nothing is an image; every shape is computed from"
echo "a seed. *Hand-designed kinds* are a fixed set of shapes written by hand (a flower, a lily, a"
echo "leaf, a butterfly ...) whose sizes and details are random. *Species* are sampled from genomes:"
echo "a plant's form, clusters, leaves and colors, and an animal's kind and markings, so each"
echo "document's seed grows plants of its own."
echo
echo "| what | release | where things go | the plants and animals | drawn by |"
echo "|---|---|---|---|---|"
echo "| grown margin | $oname | **procedural**, grown into the free space | hand-designed kinds | Lua (LuaLaTeX) |"
echo "| grown margin | $nname | **procedural**, grown into the free space | **procedural** species from genomes | Lua (LuaLaTeX) |"
echo "| authored page | both | placed by hand | hand-designed kinds | Lua (LuaLaTeX) |"
echo "| geometric theme | both | **procedural**, grown | hand-designed kinds, cut flat | Lua (LuaLaTeX) |"
echo "| math theme | both | **procedural**, packed into the free space | figures computed from their mathematics, and TeX's equations | Lua and TeX (LuaLaTeX) |"
echo "| ornaments and initials | both | set in the text; an initial's vine grown round its letter | hand-designed kinds | Lua (LuaLaTeX) |"
echo "| TikZ pics (\\usetikzlibrary{florilegium}) | $nname | **procedural**, each pic grows its own plants | **procedural** species from genomes | pure TikZ (pdfLaTeX or LuaLaTeX), or Lua (LuaLaTeX's default) |"
echo "| SVG without TeX, and the playground | both | as that release's margin | as that release's margin | any Lua 5.3/5.4, a browser |"
echo "| PostScript (postscript/florilegium.ps) | both | **procedural**, grown | hand-designed kinds (v1.3's garden) | PostScript |"
echo
echo "**Time and size** (tools/bench.tex: $n_p pages of text with a grown margin, seed 7; tools/bench-tikz.tex: one strip of"
echo "three plants on one root, 21 cm tall)"
echo
echo "| | $oname | $nname |"
echo "|---|---|---|"
printf '| the text alone, no margin (LuaLaTeX) | %.1f s, %s | %.1f s, %s |\n' "$o_tt" "$(mb "$o_bt")" "$n_tt" "$(mb "$n_bt")"
printf '| with the grown margin (LuaLaTeX) | %.1f s, %s | %.1f s, %s |\n' "$o_tg" "$(mb "$o_bg")" "$n_tg" "$(mb "$n_bg")"
printf '| what the margin adds to a page | %s, %s | %s, %s |\n' "$(per "$o_tg" "$o_tt" "$o_p")" "$(perb "$o_bg" "$o_bt" "$o_p")" "$(per "$n_tg" "$n_tt" "$n_p")" "$(perb "$n_bg" "$n_bt" "$n_p")"
printf '| TikZ strip, pdfLaTeX, pure TikZ | not in %s | %.0f s, %s, %s words of main memory |\n' "$oname" "$t_pdf" "$(mb "$p_pdf")" "$mem"
printf '| TikZ strip, LuaLaTeX, pure TikZ (engine=tikz) | not in %s | %.0f s, %s |\n' "$oname" "$t_tikz" "$(mb "$p_tikz")"
printf '| TikZ strip, LuaLaTeX, Lua engine (the default) | not in %s | %.1f s, %s |\n' "$oname" "$t_lua" "$(mb "$p_lua")"
echo
echo "Timed on $cpu with $(lualatex --version | head -1 | sed 's/^This is //') and"
echo "$(pdflatex --version | head -1). A time is the median of $runs runs (pure TikZ: one run). What the margin"
echo "adds is the difference from the same text without one (option nomargin), per page. The Lua"
echo "engine draws the same plants as pure TikZ, within a fraction of a point (tools/tikzcheck.lua draw)."
