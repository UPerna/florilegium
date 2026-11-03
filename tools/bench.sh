#!/bin/sh
# Time an earlier release's margin against this one's, and the TikZ library's engines, on
# this machine, and print the results as a Markdown table (for a release's notes).
#   make bench RUN=tools/in-docker     (puts v1.3 from its tag in build/bench/v1.3 first)
#   sh tools/bench.sh OLD [RUNS]       OLD: an earlier release's files; RUNS: default 3
# A time is the median of RUNS runs; the pure-TikZ ones run once (each takes minutes). The
# margin rows build tools/bench.tex with each release's package beside it, and the same text
# with nomargin; the garden's share of a page is the difference over the pages. The TikZ
# rows build tools/bench-tikz.tex (one strip of three plants) in pure TikZ under pdfLaTeX
# and LuaLaTeX and with the Lua engine, and compare the two LuaLaTeX PDFs byte for byte.
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
  tg=$(run "$1" "$runs" $LUALATEX -jobname=bench "\def\florilegiumseed{7}\input{bench.tex}")
  tt=$(run "$1" "$runs" $LUALATEX -jobname=bench-text "\def\florilegiumseed{7}\def\benchoptions{,nomargin}\input{bench.tex}")
  set -- "$1" $(written "$1/bench.log") $(written "$1/bench-text.log")
  echo "$tg $tt $2 $3 $5"
}
set -- $(margin "$old")
o_tg=$1 o_tt=$2 o_p=$3 o_bg=$4 o_bt=$5
set -- $(margin "$B/new")
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
if cmp -s "$B/new/strip.pdf" "$B/new/strip-tikz.pdf"; then same="the same PDF as pure TikZ's, byte for byte"
else same="**not** the same PDF as pure TikZ's"; fi

# ---- the table
cpu=$(awk -F': ' '/model name/ { print $2; exit }' /proc/cpuinfo)
per() { awk -v a="$1" -v b="$2" -v p="$3" 'BEGIN { printf "%.2f s", (a - b) / p }'; }
perb() { mb "$(awk -v a="$1" -v b="$2" -v p="$3" 'BEGIN { print (a - b) / p }')"; }
oname=$(sed -n 's/.*\\ProvidesPackage{florilegium}\[[^]]* v\([0-9.]*\).*/v\1/p' "$old/florilegium.sty")
nname=$(sed -n 's/.*\\ProvidesPackage{florilegium}\[[^]]* v\([0-9.]*\).*/v\1/p' florilegium.sty)
olabel="$oname's" nlabel="$nname's"
[ "$nname" = "$oname" ] && nlabel="this tree's"
echo "Timed on $cpu with $(lualatex --version | head -1 | sed 's/^This is //') and"
echo "$(pdflatex --version | head -1); a time is the median of $runs runs (pure TikZ: one). A page's"
echo "share is what the garden adds to the same text set without one (option nomargin)."
echo
echo "| what | engine | time | PDF |"
echo "|---|---|---|---|"
printf '| tools/bench.tex: %s pages of text, no garden | LuaLaTeX | %.1f s | %s |\n' "$n_p" "$n_tt" "$(mb "$n_bt")"
printf '| the same with %s grown margin | LuaLaTeX | %.1f s (%s a page) | %s (%s a page) |\n' "$olabel" "$o_tg" "$(per "$o_tg" "$o_tt" "$o_p")" "$(mb "$o_bg")" "$(perb "$o_bg" "$o_bt" "$o_p")"
printf '| the same with %s grown margin | LuaLaTeX | %.1f s (%s a page) | %s (%s a page) |\n' "$nlabel" "$n_tg" "$(per "$n_tg" "$n_tt" "$n_p")" "$(mb "$n_bg")" "$(perb "$n_bg" "$n_bt" "$n_p")"
printf '| tools/bench-tikz.tex: three plants on one root, 21 cm | pdfLaTeX, pure TikZ | %.0f s | %s (%s words of main memory) |\n' "$t_pdf" "$(mb "$p_pdf")" "$mem"
printf '| the same | LuaLaTeX, pure TikZ | %.0f s | %s |\n' "$t_tikz" "$(mb "$p_tikz")"
printf '| the same | LuaLaTeX, engine=lua | %.1f s | %s, %s |\n' "$t_lua" "$(mb "$p_lua")" "$same"
