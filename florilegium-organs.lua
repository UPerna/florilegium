-- florilegium-organs.lua -- the species' plants in Lua: tikzlibraryflorilegium.code.tex,
-- transcribed. The hybrid: Lua computes, TikZ draws.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- Every macro of the TikZ library that draws has its twin here, with the same random
-- draws in the same order and the same pgfmath expressions, which florilegium-pgfmath.lua
-- evaluates as pgfmath does, to the scaled point. The output is the pgf basic-layer code
-- the library would have run (\pgfpathmoveto, \pgfpathcurveto, \pgfusepath,
-- \begin{pgfscope} ...), as text for TeX, so the same seed gives the same picture,
-- command for command, in a fraction of the time.
--
-- TeX's rules are kept where the drawing depends on them, because the library's look was
-- made under them: every macro and count register lives in a store whose assignments a
-- group (a pgfscope) undoes; helpers write their temporaries there as the macros do,
-- since a later line may read one (a mottle blotch takes its range from \flo@xa, which
-- the blob before it overwrote); arguments that TeX expands late are read late; loop
-- bounds are read again on every pass; a count register two loops share is shared.
-- Names below follow the macros: V.xa is \flo@xa, V["#kb"] the count \flo@kb,
-- V["v@size"] the trait \flo@get{size}; E"..." is a pgfmath expression over them.

local pm = require("florilegium-pgfmath")
local ink = require("florilegium-ink")
local species = require("florilegium-species")

local M = {}
M.version = "1.3"                 -- the release; florilegium.lua checks that every file has the same

local sp, str, compile = pm.sp, pm.str, pm.compile
local add, sub, mulf = pm.add, pm.sub, pm.mulf
local U = 65536                   -- 1pt
local concat = table.concat

-- ---------------------------------------------------------------- TeX's state
local R = {}                      -- the store: macros, count registers, traits
local NIL, DEAD = {}, {}
local level, saves = 0, {}
-- an assignment, undone at the end of the current group (TeX's save stack)
local function setv(t, k, v)
  if level > 0 then
    local s = saves[level]
    local o = t[k]
    s[#s + 1] = t s[#s + 1] = k s[#s + 1] = (o == nil) and NIL or o
  end
  t[k] = v
end
local V = setmetatable({}, { __index = R, __newindex = function(_, k, v) setv(R, k, v) end })
local function begingroup() level = level + 1 saves[level] = {} end
local function endgroup()
  local s = saves[level]
  for i = #s - 2, 1, -3 do
    local o = s[i + 2]
    if o == NIL then o = nil end
    s[i][s[i + 1]] = o
  end
  saves[level] = nil
  level = level - 1
end
-- \xdef: no group end undoes it
local function gset(k, v)
  for l = 1, level do
    local s = saves[l]
    for i = 1, #s, 3 do if s[i] == R and s[i + 1] == k then s[i] = DEAD end end
  end
  R[k] = v
end

-- arrays of macros (\flo@X<i>, \flo@A<i> ...), assigned through setv as well
local X, Y, A, B, C, D = {}, {}, {}, {}, {}, {}
local NX, NY, RX, RY, QX, QY, S = {}, {}, {}, {}, {}, {}, {}
local G = { {}, {}, {} }          -- \flo@G<k>@<i>, the noise gradients
local T = { TX = {}, TY = {}, MX = {}, MY = {}, MU = {}, MV = {},   -- the rarer ones (Lua's
  AX = {}, AY = {}, AN = {}, AM = {}, O = {}, VEIN = {}, Z = {} }     -- 200 locals)
local KEPT = {}                   -- \flo@<name>@N, @X<i> ... (\flo@keep)
local ROOM = {}                   -- \flo@rm<roomid>@<i>@<j>
local PP = {}                     -- \flo@pp@... of a garden (some global)

local function E(s, a) return compile(s)(R, a) end
local function I(k) return R[k] // U end                     -- a macro holding an integer
local function arg(a) if type(a) == "string" then return R[a] end return a end   -- read late
local function K(s) return sp(s) end

-- \numexpr's division: rounded, halves away from zero
local function nediv(a, b)
  local neg = (a < 0) ~= (b < 0)
  if a < 0 then a = -a end
  if b < 0 then b = -b end
  local q = (2 * a + b) // (2 * b)
  return neg and -q or q
end

-- \flo@loop{name}\count{from}{to}{body}: the bound is read again on every pass, and the
-- count is a register like any other (an inner loop on the same one moves it)
local function loop(c, from, to, body)
  V[c] = from
  if type(to) == "function" then
    while R[c] <= to() do body() V[c] = R[c] + 1 end
  else
    while R[c] <= to do body() V[c] = R[c] + 1 end
  end
end

-- ---------------------------------------------------------------- random numbers
-- pgf's generator; its state, \pgfmath@rnd@z, is global
local rng = ink.pgfrng(1)
pm.rng = rng
local rnd, rand = pm.rnd, pm.rand
local function range(a, b) return add(a, mulf(sub(b, a), rnd())) end     -- #2+(#3-(#2))*rnd
local function sym(a) return mulf(a, rand()) end                         -- (#2)*rand
local function int(a, b) return rng.random(a, b) * U end                 -- \pgfmathrandominteger
local function chance(p) return rnd() < p end                            -- \flo@chance
local function drawseed(n) rng.load(n) rng.step() rng.step() end         -- \flo@drawseed

-- ---------------------------------------------------------------- output
local OUT
local function out(s) OUT[#OUT + 1] = s end
local function P(x, y) return "\\pgfqpoint{" .. str(x) .. "pt}{" .. str(y) .. "pt}" end
local function moveto(x, y) out("\\pgfpathmoveto{" .. P(x, y) .. "}") end
local function lineto(x, y) out("\\pgfpathlineto{" .. P(x, y) .. "}") end
local function curveto(a, b, c, d, e, f)
  out("\\pgfpathcurveto{" .. P(a, b) .. "}{" .. P(c, d) .. "}{" .. P(e, f) .. "}")
end
local function closepath() out("\\pgfpathclose") end
local function usepath(k) out("\\pgfusepath{" .. k .. "}") end
local function circle(x, y, r) out("\\pgfpathcircle{" .. P(x, y) .. "}{" .. str(r) .. "pt}") end
local function scope(f) out("\\begin{pgfscope}") begingroup() f() endgroup() out("\\end{pgfscope}") end
local function shift(x, y) out("\\pgftransformshift{" .. P(x, y) .. "}") end
local function rotate(a) out("\\pgftransformrotate{" .. str(a) .. "}") end
local function scale(s) out("\\pgftransformscale{" .. str(s) .. "}") end
local function yscale(s) out("\\pgftransformyscale{" .. str(s) .. "}") end

-- \flo@put
local function put(i, x, y) setv(X, i, x) setv(Y, i, y) end

-- ================================================================ paths
-- \flo@smoothprep: controls of the closed Catmull-Rom curve through points 1..n
local function smoothprep(n)
  V.N = n * U
  loop("#i", 1, function() return I("N") end, function()
    local N, i = I("N"), R["#i"]
    V.ia = (i == 1 and N or i - 1) * U
    V.ib = (i == N and 1 or i + 1) * U
    local ib = I("ib")
    V.ic = (ib == N and 1 or ib + 1) * U
    local ia, ic = I("ia"), I("ic")
    V.xi = X[i] V.yi = Y[i]
    V.xa = X[ia] V.ya = Y[ia]
    V.xb = X[ib] V.yb = Y[ib]
    V.xc = X[ic] V.yc = Y[ic]
    V.t = E"@xi+(@xb-(@xa))/6" setv(A, i, R.t)
    V.t = E"@yi+(@yb-(@ya))/6" setv(B, i, R.t)
    V.t = E"@xb-(@xc-(@xi))/6" setv(C, i, R.t)
    V.t = E"@yb-(@yc-(@yi))/6" setv(D, i, R.t)
  end)
end
-- \flo@smoothpath
local function smoothpath()
  moveto(X[1], Y[1])
  loop("#i", 1, function() return I("N") end, function()
    local i, N = R["#i"], I("N")
    V.ib = (i == N and 1 or i + 1) * U
    local ib = I("ib")
    curveto(A[i], B[i], C[i], D[i], X[ib], Y[ib])
  end)
  closepath()
end

-- ================================================================ v1.3's hand
-- \flo@vtone{name}{t}
local function vtone(name, t)
  local ti
  if R.lift == 0 then ti = E("max(0,min(100,floor((%1)*100+0.5)))", { t })
  else ti = E("max(0,min(100,floor(((%1)+(1-(%1))*@lift)*100+0.5)))", { t }) end
  V.ti = pm.int(ti)
  out("\\colorlet{" .. name .. "}{" .. R.rampname .. "@" .. I("ti") .. "}")
end
-- \flo@tone{name}{t}{flo@ink or flo@accent}
local function tone(name, t, which)
  if which == "flo@accent" then
    V.savedramp = R.rampname V.rampname = "flo@aramp"
    vtone(name, t)
    V.rampname = R.savedramp
  else vtone(name, t) end
end
-- \flo@vaccent{name}{k}
local function vaccent(name, k)
  if k < 0 then out("\\colorlet{" .. name .. "}{flo@accent!" .. str(E("100*(1+(%1))", { k })) .. "!black}")
  else out("\\colorlet{" .. name .. "}{flo@accent!" .. str(E("100*(1-(%1))", { k })) .. "!white}") end
end
-- \flo@vfill{color}{opacity}{multiply}{path}, \flo@vstroke{color}{width bp}{opacity}{multiply}{path}
local function vfill(c, op, mult, path)
  out("\\begin{pgfscope}") begingroup()
  out("\\pgfsetfillcolor{" .. c .. "}")
  V.opq = E("round((%1)*100)/100", { op })
  out("\\pgfsetfillopacity{" .. str(R.opq) .. "}")
  if mult == 1 then out("\\pgfsetblendmode{multiply}") end
  path()
  out("\\pgfusepath{fill}")
  endgroup() out("\\end{pgfscope}")
end
local function vstroke(c, w, op, mult, path)
  out("\\begin{pgfscope}") begingroup()
  out("\\pgfsetstrokecolor{" .. c .. "}")
  out("\\pgfsetlinewidth{" .. str(w) .. "bp}")
  V.opq = E("round((%1)*100)/100", { op })
  out("\\pgfsetstrokeopacity{" .. str(R.opq) .. "}")
  if mult == 1 then out("\\pgfsetblendmode{multiply}") end
  path()
  out("\\pgfusepath{stroke}")
  endgroup() out("\\end{pgfscope}")
end

-- ---------------------------------------------------------------- noise
-- \flo@vfbm: three tables of 256 gradients
local function vfbm()
  loop("#kc", 1, 3, function()
    local g = G[R["#kc"]]
    loop("#kb", 0, 255, function() setv(g, R["#kb"], rand()) end)
  end)
end
-- \flo@vwave#1 -> \flo@wv
local function vwave(x)
  V.wv = 0 V.wa = U V.wf = U
  loop("#kc", 1, 3, function()
    V.wx = E("(%1)*@wf+17*#kc", { x })
    V.wi = pm.int(E"floor(@wx)")
    V.wr = E"@wx-@wi"
    local g, wi = G[R["#kc"]], I("wi")
    V.ga = g[wi - 256 * nediv(wi - 128, 256)]
    V.gb = g[wi + 1 - 256 * nediv(wi - 127, 256)]
    V.wn = E"2*(@ga*@wr+(@gb*(@wr-1)-@ga*@wr)*@wr*@wr*(3-2*@wr))"
    V.wv = E"@wv+@wa*@wn" V.wa = E"@wa*0.5" V.wf = E"@wf*2"
  end)
end

-- ---------------------------------------------------------------- geometry
-- \flo@nrm#1#2#3#4: the left normal of (a,b) into the macros named nx, ny
local function nrm(a, b, nx, ny)
  V.nl = pm.veclen(a, b)
  if R.nl < K"0.00002" then V[nx] = 0 V[ny] = 0
  else V[nx] = E("-(%2)/@nl", { a, b }) V[ny] = E("(%1)/@nl", { a, b }) end
end
-- \flo@vtaper: a closed tapered stroke along one cubic, widths \flo@twa to \flo@twb
local function vtaper(p1, p2, p3, p4, p5, p6, p7, p8)
  local a = { p1, p2, p3, p4, p5, p6, p7, p8 }
  V.da = E("%3-(%1)", a) V.db = E("%4-(%2)", a) nrm(R.da, R.db, "nax", "nay")
  V.da = E("%5-(%1)", a) V.db = E("%6-(%2)", a) nrm(R.da, R.db, "nbx", "nby")
  V.da = E("%7-(%3)", a) V.db = E("%8-(%4)", a) nrm(R.da, R.db, "ncx", "ncy")
  V.da = E("%7-(%5)", a) V.db = E("%8-(%6)", a) nrm(R.da, R.db, "ndx", "ndy")
  V.ha = E"@twa/2" V.hb = E"(2*@twa+@twb)/6"
  V.hc = E"(@twa+2*@twb)/6" V.hd = E"@twb/2"
  V.pa = E("%1+@nax*@ha", a) V.pb = E("%2+@nay*@ha", a)
  V.pc = E("%3+@nbx*@hb", a) V.pd = E("%4+@nby*@hb", a)
  V.pe = E("%5+@ncx*@hc", a) V.pf = E("%6+@ncy*@hc", a)
  V.pg = E("%7+@ndx*@hd", a) V.ph = E("%8+@ndy*@hd", a)
  moveto(R.pa, R.pb) curveto(R.pc, R.pd, R.pe, R.pf, R.pg, R.ph)
  V.pg = E("%7-@ndx*@hd", a) V.ph = E("%8-@ndy*@hd", a) lineto(R.pg, R.ph)
  V.pe = E("%5-@ncx*@hc", a) V.pf = E("%6-@ncy*@hc", a)
  V.pc = E("%3-@nbx*@hb", a) V.pd = E("%4-@nby*@hb", a)
  V.pa = E("%1-@nax*@ha", a) V.pb = E("%2-@nay*@ha", a)
  curveto(R.pe, R.pf, R.pc, R.pd, R.pa, R.pb) closepath()
end
-- \flo@vblob: n points around (x,y), radii rx ry, roughness k, into X/Y 1..n
local function vblob(x, y, rx, ry, k, n)
  V.bph = range(0, 360 * U) V.bpi = range(0, 360 * U) V.brot = range(0, 360 * U)
  local a = { x, y, rx, ry, k, n * U }
  loop("#kb", 0, n - 1, function()
    V.ba = E("360*#kb/(%6)", a) V.bs = sym(U)
    V.bk = E("1+(%5)*(0.6*sin(2*@ba+@bph)+0.4*sin(3*@ba+@bpi))+(%5)*0.5*@bs", a)
    V.bpx = E("(%3)*@bk*cos(@ba)", a) V.bpy = E("(%4)*@bk*sin(@ba)", a)
    V.bx = E("(%1)+@bpx*cos(@brot)-@bpy*sin(@brot)", a)
    V.by = E("(%2)+@bpx*sin(@brot)+@bpy*cos(@brot)", a)
    put(R["#kb"] + 1, R.bx, R.by)
  end)
  smoothprep(n)
end
-- \flo@vmottle: blotches and specks over (x0,y0)-(x1,y1) inside the clip; x0 and x1 may
-- be macro names, read at each use as TeX expands them
local function vmottle(x0, y0, x1, y1, n, size, dark, light, nspk)
  loop("#ka", 1, n, function()
    V.mx = range(arg(x0), arg(x1)) V.my = range(arg(y0), arg(y1))
    V.t = range(K"0.5", K"1.4") V.mr = E("(%1)*@t", { size })
    V.t = range(K"0.5", U) V.ms = E"@mr*@t"
    vblob(R.mx, R.my, R.mr, R.ms, K"0.35", 7)
    if chance(K"0.6") then
      V.t = sym(K"0.06") vtone("flo@c", E("%1+@t", { dark })) V.op = range(K"0.10", K"0.22")
      vfill("flo@c", R.op, 1, smoothpath)
    else
      V.t = sym(K"0.06") vtone("flo@c", E("%1+@t", { light })) V.op = range(K"0.12", K"0.26")
      vfill("flo@c", R.op, 0, smoothpath)
    end
  end)
  if nspk > 0 then
    local spk = {}
    loop("#ka", 1, nspk, function()
      V.mx = range(arg(x0), arg(x1)) V.my = range(arg(y0), arg(y1))
      V.t = range(K"0.03", K"0.08") V.mr = E("(%1)*@t", { size })
      V.ma = range(0, 180 * U)
      V.sc = E"@mr*cos(@ma)" V.ss = E"@mr*sin(@ma)"
      V.xa = E"@mx+@sc" V.ya = E"@my+@ss"
      V.xb = E"@mx-0.6*@ss" V.yb = E"@my+0.6*@sc"
      V.xc = E"@mx-@sc" V.yc = E"@my-@ss"
      V.xd = E"@mx+0.6*@ss" V.yd = E"@my-0.6*@sc"
      spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.ya) .. "}\\pgfpathlineto{" .. P(R.xb, R.yb)
        .. "}\\pgfpathlineto{" .. P(R.xc, R.yc) .. "}\\pgfpathlineto{" .. P(R.xd, R.yd) .. "}\\pgfpathclose"
    end)
    vtone("flo@c", E("%1-0.08", { dark })) V.op = range(K"0.3", K"0.5")
    vfill("flo@c", R.op, 1, function() out(concat(spk)) end)
  end
end

-- ---------------------------------------------------------------- the petal (flora.petal)
-- \flo@vhalf#1 -> \flo@h
local function vhalf(v)
  if R["vp@pointed"] == U then
    if v > 0 then V.h = E("@pW*2*pow(max(0,sin(180*pow(%1,0.8))),0.85)*(1-0.3*(%1))", { v }) else V.h = 0 end
  else
    if v < K"0.62" then
      if v > 0 then V.h = E("@pW*(0.16+0.84*pow(sin(90*(%1)/0.62),1.3))", { v }) else V.h = E"@pW*0.16" end
    else V.h = E("@pW*sqrt(max(0,1-pow(((%1)-0.62)/0.38,2)))", { v }) end
  end
end
-- \flo@vedge#1#2 -> \flo@e
local function vedge(v, side)
  if side == 1 then V.t = E("(%1)*6", { v }) else V.t = E("(%1)*6+40", { v }) end
  vwave(R.t)
  V.e = E("(@vp@pointed==1 ? 0.012 : 0.03)*@wv*(%1)", { v })
  if R.notch > 0 and v > K"0.9" then V.e = E("@e-@notch*((%1)-0.9)*10*(1-((%1)-0.9)*10)", { v }) end
end
-- \flo@keepoutline, \flo@outlinepath
local function keepoutline()
  local n = I("N")
  V.KN = n * U
  local k = { X = {}, Y = {}, A = {}, B = {}, C = {}, D = {} }
  for i = 1, n do k.X[i], k.Y[i], k.A[i], k.B[i], k.C[i], k.D[i] = X[i], Y[i], A[i], B[i], C[i], D[i] end
  V.KO = k
  if n >= 1 then V["#kb"] = n + 1 V.t = n * U else V["#kb"] = 1 end
end
local function outlinepath()
  local k = R.KO
  moveto(k.X[1], k.Y[1])
  loop("#i", 1, function() return I("KN") end, function()
    local i, n = R["#i"], I("KN")
    V.ib = (i == n and 1 or i + 1) * U
    local ib = I("ib")
    curveto(k.A[i], k.B[i], k.C[i], k.D[i], k.X[ib], k.Y[ib])
  end)
  closepath()
end
-- \flo@vbezier: ink.bezier3 sampled at 6 points into X/Y; \flo@openpath the open curve
local function vbezier(...)
  local a = { ... }
  loop("#kb", 0, 5, function()
    V.v = E"#kb/5" V.t = E"1-@v"
    V.bx = E("@t*@t*@t*(%1)+3*@t*@t*@v*(%3)+3*@t*@v*@v*(%5)+@v*@v*@v*(%7)", a)
    V.by = E("@t*@t*@t*(%2)+3*@t*@t*@v*(%4)+3*@t*@v*@v*(%6)+@v*@v*@v*(%8)", a)
    put(R["#kb"] + 1, R.bx, R.by)
  end)
end
local function openpath()
  moveto(X[1], Y[1])
  loop("#i", 1, 5, function()
    local i = R["#i"]
    V.ia = (i == 1 and 1 or i - 1) * U V.ib = (i + 1) * U
    V.ic = (i == 5 and 6 or i + 2) * U
    local ia, ib, ic = I("ia"), I("ib"), I("ic")
    V.pa = E("%1+(%2-%3)/6", { X[i], X[ib], X[ia] }) V.pb = E("%1+(%2-%3)/6", { Y[i], Y[ib], Y[ia] })
    V.pc = E("%1-(%2-%3)/6", { X[ib], X[ic], X[i] }) V.pd = E("%1-(%2-%3)/6", { Y[ib], Y[ic], Y[i] })
    curveto(R.pa, R.pb, R.pc, R.pd, X[ib], Y[ib])
  end)
end

-- \flo@vpetal: along +y, length 1, from \flo@vp@pointed, @W, @bend, @tone, @ns, @heart, @u
local function vpetal()
  if R["vp@W"] == "" then
    if R["vp@pointed"] == U then V.pW = range(K"0.15", K"0.2") else V.pW = range(K"0.40", K"0.48") end
  else V.pW = R["vp@W"] end
  if R["vp@bend"] == "" then V.bend = sym(K"0.08") else V.bend = R["vp@bend"] end
  V.tz = R["vp@tone"]
  if R["vp@u"] > K"0.45" then V.fine = U else V.fine = 0 end
  vfbm()
  V.notch = 0
  if R["vp@pointed"] == 0 then
    if chance(R["vp@notchp"]) then V.notch = range(K"0.03", K"0.06") V.notch = E"@notch*@vp@notchk" end
  end
  if R["vp@u"] > K"0.5" then V.bn = 28 * U else V.bn = 18 * U end
  loop("#kb", 0, function() return I("bn") end, function()
    V.v = E"#kb/@bn"
    V.va = E"max(0,#kb-1)/@bn" V.vb = E"min(@bn,#kb+1)/@bn"
    V.da = E"@bend*(@vb*@vb-@va*@va)" V.db = E"@vb-@va"
    nrm(R.da, R.db, "nx", "ny")
    vhalf(R.v)
    vedge(R.v, 1) V.ea = E"max(0,@h+@e)"
    vedge(R.v, -1) V.eb = E"max(0,@h+@e)"
    V.cx = E"@bend*@v*@v"
    V.xl = E"@cx+@nx*@ea" V.yl = E"@v+@ny*@ea"
    local kb, bn = R["#kb"], I("bn")
    put(kb + 1, R.xl, R.yl)
    if kb > 0 and kb < bn then
      V.xr = E"@cx-@nx*@eb" V.yr = E"@v-@ny*@eb"
      put(2 * bn + 1 - kb, R.xr, R.yr)
    end
  end)
  smoothprep(2 * I("bn"))
  keepoutline()
  scope(function()
    outlinepath() usepath("clip")
    vtone("flo@c", R.tz)
    vfill("flo@c", U, 0, function()
      out("\\pgfpathrectanglecorners{" .. P(K"-1", K"-0.1") .. "}{" .. P(U, K"1.2") .. "}")
    end)
    if R["vp@heart"] == U then
      loop("#ka", 1, 8, function()
        V.t = E"@pW*(0.25+0.1*#ka)" V.ms = E"0.06+0.065*#ka"
        vblob(0, 0, R.t, R.ms, K"0.28", 9) vfill("white", K"0.1", 0, smoothpath)
      end)
    end
    V.xa = E"-@pW*1.2" V.xb = E"@pW*1.2"
    V.ta = E"@tz-0.2" V.tb = E"@tz+0.2"
    if R["vp@pointed"] == U then V.msz = K"0.06" else V.msz = K"0.12" end
    if R.fine == U then vmottle("xa", K"0.12", "xb", K"1.05", 15, R.msz, R.ta, R.tb, 12)
    else vmottle("xa", K"0.12", "xb", K"1.05", 6, R.msz, R.ta, R.tb, 0) end
    -- darker brush strokes running out from the base
    if R.fine == U then
      V.nk = int(5, 8)
      loop("#ka", 1, function() return I("nk") end, function()
        V.f = sym(K"0.95") V.va = range(K"0.15", K"0.4") V.vb = range(K"0.7", K"1.0")
        vhalf(R.va) V.xa = E"@f*@h*0.8+@bend*@va*@va"
        vhalf(R.vb) V.xb = E"@f*@h*0.9+@bend*@vb*@vb"
        V.twa = range(K"0.03", K"0.07") V.twb = K"0.005"
        V.c = E"@xa+(@xb-@xa)*0.3" V.d = E"@va+(@vb-@va)*0.35"
        V.cc = E"@xb*0.95" V.dd = E"@va+(@vb-@va)*0.7"
        vtone("flo@c", E"@tz-0.25") V.op = range(K"0.12", K"0.25")
        vfill("flo@c", R.op, 1, function() vtaper(R.xa, R.va, R.c, R.d, R.cc, R.dd, R.xb, R.vb) end)
      end)
    end
    -- pooling: the outline restroked wide and soft
    vtone("flo@c", K"0.08") V.t = E"1.6*@vp@u" vstroke("flo@c", R.t, K"0.3", 1, outlinepath)
    -- white streaks lifted out, fanning from the base
    if R["vp@ns"] == "" then
      if R["vp@pointed"] == U then V.ns = int(3, 5) else V.ns = int(9, 13) end
    else V.ns = R["vp@ns"] end
    loop("#ka", 1, function() return I("ns") end, function()
      V.t = sym(K"0.05") V.f = E"(#ka-0.5)/@ns*2-1+@t"
      if R["vp@pointed"] == U then V.t = range(K"0.4", K"0.85") else V.t = range(K"0.35", K"0.8") end
      V.len = E"@t*(1-0.35*@f*@f)"
      if R["vp@pointed"] == U and R["#ka"] == nediv(I("ns"), 2) then
        V.f = 0 V.len = range(K"0.8", K"0.92")
      end
      vhalf(R.len) V.xb = E"@f*@h*0.85+@bend*@len*@len"
      V.t = E"@len*0.5" vhalf(R.t) V.g = sym(K"0.02")
      V.mx = E"@f*@h*0.6+@g+@bend*@len*@len*0.3"
      if R["vp@pointed"] == U then V.g = K"0.6" else V.g = U end
      V.t = range(K"0.022", K"0.045") V.twa = E"@g*@t" V.twb = K"0.002"
      V.xa = E"@f*0.03" V.c = E"@mx*0.5" V.d = E"@len*0.3"
      V.dd = E"@len*0.6" V.op = range(K"0.55", K"0.9")
      vfill("white", R.op, 0, function() vtaper(R.xa, 0, R.c, R.d, R.mx, R.dd, R.xb, R.len) end)
    end)
    -- a few fine dark veins, following the petal
    if R.fine == U then
      V.nk = int(4, 7)
      loop("#ka", 1, function() return I("nk") end, function()
        V.f = sym(K"0.85") V.va = range(K"0.2", K"0.35") V.vb = range(K"0.75", K"0.95")
        vhalf(R.va) V.xa = E"@f*@h*0.7+@bend*@va*@va"
        vhalf(R.vb) V.xb = E"@f*@h*0.9+@bend*@vb*@vb"
        V.c = E"@xa+(@xb-@xa)*0.2" V.d = E"@va+(@vb-@va)*0.4"
        V.cc = E"@xb*0.97" V.dd = E"@va+(@vb-@va)*0.75"
        vbezier(R.xa, R.va, R.c, R.d, R.cc, R.dd, R.xb, R.vb)
        vtone("flo@c", K"0.1") V.op = range(K"0.18", K"0.32") vstroke("flo@c", K"0.15", R.op, 1, openpath)
      end)
    end
  end)
end

-- ---------------------------------------------------------------- the heart and the flower
-- \flo@vheart{n}
local function vheart(n)
  local a = { n }
  loop("#ka", 1, function() return 2 * (n // U) end, function()
    V.t = sym(8 * U) V.a = E("(#ka-0.5)*360/(2*(%1))+@t", a)
    V.len = range(K"0.24", K"0.36") V.twa = K"0.06" V.twb = K"0.004"
    scope(function()
      rotate(R.a)
      vfill("white", K"0.85", 0, function() vtaper(0, 0, K"0.01", K"0.1", K"-0.01", K"0.2", 0, R.len) end)
    end)
  end)
  vfill("white", K"0.9", 0, function() circle(0, 0, K"0.13") end)
  vtone("flo@c", K"0.1") vtone("flo@d", K"0.05")
  loop("#ka", 1, 14, function()
    V.a = range(0, 360 * U) V.r = range(K"0.05", K"0.12")
    V.dx = E"@r*cos(@a)" V.dy = E"@r*sin(@a)"
    vstroke("flo@c", K"0.2", K"0.7", 0, function() moveto(0, 0) lineto(R.dx, R.dy) end)
    vfill("flo@d", K"0.9", 0, function() circle(R.dx, R.dy, K"0.008") end)
  end)
  vaccent("flo@c", K"-0.15") vfill("flo@c", U, 0, function() circle(0, 0, K"0.042") end)
  vaccent("flo@c", K"0.3") vfill("flo@c", U, 0, function() circle(0, 0, K"0.022") end)
end
-- \flo@vflower{u}{n}: n broad petals seen from the front, petal length 1
local function vflower(u, n)
  V.vu = u
  if R["vf@pointed"] ~= nil then V["vp@pointed"] = R["vf@pointed"] else V["vp@pointed"] = 0 end
  V.spin = range(0, 72 * U)
  if R["vf@tone"] == "" then
    if chance(K"0.25") then V.tq = range(K"0.2", K"0.28") else V.tq = range(K"0.3", K"0.46") end
  else V.tq = R["vf@tone"] end
  V.np = n
  loop("#n", 0, function() return I("np") - 1 end, function()
    V.t = sym(6 * U) V.a = E"@spin+#n*360/@np+@t"
    V.js = range(K"0.9", K"1.06") V.t = sym(K"0.04") V.tp = E"@tq+@t"
    scope(function()
      rotate(R.a) scale(R.js) shift(0, K"0.04")
      if R["vf@W"] ~= nil then V["vp@W"] = R["vf@W"] else V["vp@W"] = "" end
      if R["vf@ns"] ~= nil then V["vp@ns"] = R["vf@ns"] else V["vp@ns"] = "" end
      V["vp@bend"] = "" V["vp@heart"] = U V["vp@tone"] = R.tp V["vp@u"] = R.vu
      vpetal()
    end)
  end)
  scope(function() rotate(R.spin) vheart(R.np) end)
end

-- ---------------------------------------------------------------- shapes kept by name
-- \flo@smoothprepT{n}{tension}
local function smoothprepT(n, tk)
  V.N = n * U V.tk = tk
  loop("#i", 1, function() return I("N") end, function()
    local N, i = I("N"), R["#i"]
    V.ia = (i == 1 and N or i - 1) * U
    V.ib = (i == N and 1 or i + 1) * U
    local ib = I("ib")
    V.ic = (ib == N and 1 or ib + 1) * U
    local ia, ic = I("ia"), I("ic")
    V.xi = X[i] V.yi = Y[i]
    V.t = E("@xi+(%1-(%2))*@tk/6", { X[ib], X[ia] }) setv(A, i, R.t)
    V.t = E("@yi+(%1-(%2))*@tk/6", { Y[ib], Y[ia] }) setv(B, i, R.t)
    V.t = E("%1-(%2-(@xi))*@tk/6", { X[ib], X[ic] }) setv(C, i, R.t)
    V.t = E("%1-(%2-(@yi))*@tk/6", { Y[ib], Y[ic] }) setv(D, i, R.t)
  end)
end
-- \flo@keep{name}, \flo@kept{name}
local function keep(name)
  local n = I("N")
  local k = { N = n, X = {}, Y = {}, A = {}, B = {}, C = {}, D = {} }
  for i = 1, n do k.X[i], k.Y[i], k.A[i], k.B[i], k.C[i], k.D[i] = X[i], Y[i], A[i], B[i], C[i], D[i] end
  setv(KEPT, name, k)
  if n >= 1 then V["#kb"] = n + 1 V.t = n * U else V["#kb"] = 1 end
end
local function kept(name)
  local k = KEPT[name]
  V.kn = k.N * U
  moveto(k.X[1], k.Y[1])
  loop("#i", 1, function() return I("kn") end, function()
    local i, n = R["#i"], I("kn")
    V.ib = (i == n and 1 or i + 1) * U
    local ib = I("ib")
    curveto(k.A[i], k.B[i], k.C[i], k.D[i], k.X[ib], k.Y[ib])
  end)
  closepath()
end
-- \flo@normals{n}: normals by central differences over X/Y 1..n into NX/NY
local function normals(n)
  loop("#kb", 1, n, function()
    local kb = R["#kb"]
    V.ia = (kb == 1 and 1 or kb - 1) * U
    V.ib = (kb == n and n or kb + 1) * U
    local ia, ib = I("ia"), I("ib")
    V.da = E("%1-(%2)", { X[ib], X[ia] }) V.db = E("%1-(%2)", { Y[ib], Y[ia] })
    V.nl = pm.veclen(R.da, R.db)
    if R.nl < K"0.00002" then V.nl = U end
    V.t = E"-(@db)/@nl" setv(NX, kb, R.t)
    V.t = E"(@da)/@nl" setv(NY, kb, R.t)
  end)
end
-- the arc lengths along X/Y 1..n into S, the total in \flo@acc (\flo@vstem, \flo@vstreak)
local function arclengths(n)
  V.acc = 0 setv(S, 1, 0)
  loop("#kb", 2, n, function()
    local kb = R["#kb"]
    V.ia = (kb - 1) * U
    V.acc = E("@acc+veclen(%1-(%2),%3-(%4))", { X[kb], X[kb - 1], Y[kb], Y[kb - 1] })
    setv(S, kb, R.acc)
  end)
end
-- points of the two sides into X/Y 1..2n (left out, right back) and the closed curve
local function ribbonsides(n)
  loop("#kb", 1, n, function()
    local kb = R["#kb"]
    put(kb, RX[kb], RY[kb])
    put(2 * n + 1 - kb, QX[kb], QY[kb])
  end)
end
local function sides(kb, w)        -- RX/RY, QX/QY at point kb, half-width w (a macro name)
  V.xl = E("%1+%2*@" .. w, { X[kb], NX[kb] }) V.yl = E("%1+%2*@" .. w, { Y[kb], NY[kb] })
  V.xr = E("%1-%2*@" .. w, { X[kb], NX[kb] }) V.yr = E("%1-%2*@" .. w, { Y[kb], NY[kb] })
  setv(RX, kb, R.xl) setv(RY, kb, R.yl)
  setv(QX, kb, R.xr) setv(QY, kb, R.yr)
end
-- \flo@vstreak{n}{w0}{w1}{color}{opacity}
local function vstreak(n, w0, w1, color, op)
  normals(n)
  arclengths(n)
  local a = { w0, w1 }
  loop("#kb", 1, n, function()
    local kb = R["#kb"]
    V.u = E("@acc>0 ? %3/@acc : 0", { w0, w1, S[kb] })
    V.w = E("((%1)+((%2)-(%1))*@u)*(@u<0.12 ? 0.4+5*@u : 1)/2", a)
    sides(kb, "w")
  end)
  ribbonsides(n)
  smoothprep(2 * n) vfill(color, op, 0, smoothpath)
end
-- \flo@bladeassemble{n}: RX/RY 1..n+1 (left, base to tip), QX/QY n..2 (right, back)
local function bladeassemble(n)
  loop("#kb", 1, n + 1, function() local kb = R["#kb"] put(kb, RX[kb], RY[kb]) end)
  loop("#kb", 2, n, function() local kb = R["#kb"] put(2 * n + 2 - kb, QX[kb], QY[kb]) end)
end

-- ---------------------------------------------------------------- the leaf (flora.leaf)
local function lspine(v)                 -- \flo@lspine#1 -> \flo@sx, \flo@sy
  V.sx = E("@lbend*(%1)*(%1)-0.3*@lbend*(%1)", { v }) V.sy = v
end
local function ltan(v)                   -- \flo@ltan#1 -> \flo@tx, \flo@ty
  V.t = E("max(0,(%1)-0.01)", { v }) lspine(R.t) V.ta = R.sx V.tb = R.sy
  V.t = E("min(1,(%1)+0.01)", { v }) lspine(R.t)
  V.da = E"@sx-(@ta)" V.db = E"@sy-(@tb)"
  V.nl = pm.veclen(R.da, R.db)
  V.tx = E"@da/@nl" V.ty = E"@db/@nl"
end
local function lenv(v)                   -- \flo@lenv#1 -> \flo@env
  if v > 0 and v < U then V.env = E("@lW*2.3*pow(%1,0.55)*pow(1-(%1),0.95)", { v }) else V.env = 0 end
end
local function lteeth(v)                 -- \flo@lteeth#1 -> \flo@th
  V.th = E("0.006*(1-abs(2*((%1)*9-floor((%1)*9))-1))", { v })
end
local function leaftrace()               -- every shape of the leaf as one path
  loop("#j", 1, function() return I("nshapes") end, function() kept("ls" .. R["#j"]) end)
end
local function lobepoint(t)              -- a point on the lobe's spine at t (\flo@lx, \flo@ldx ...)
  local a = { t }
  return E("@lx+@ldx*@lL*%1-@ldy*@lb*@lL*%1*%1", a), E("@ly+@ldy*@lL*%1+@ldx*@lb*@lL*%1*%1", a)
end
local function vleaf()
  if R["vl@W"] == "" then V.lW = range(K"0.20", K"0.27") else V.lW = R["vl@W"] end
  if R["vl@bend"] == "" then V.lbend = sym(K"0.25") else V.lbend = R["vl@bend"] end
  if R["vl@lobes"] == "" then V.llobes = int(3, 5) else V.llobes = R["vl@lobes"] end
  if R["vl@depth"] == "" then V.ldepth = range(K"0.3", K"0.7") else V.ldepth = R["vl@depth"] end
  if R["vl@tone"] == "" then V.lt = range(K"0.26", K"0.38") else V.lt = R["vl@tone"] end
  if R["vl@u"] > K"0.6" then V.fine = U V.bn = 36 * U else V.fine = 0 V.bn = 24 * U end
  if R.ldepth > 0 then V.bodyw = E"1-0.75*@ldepth" V.lent = 0 else V.bodyw = U V.lent = U end
  -- the body: a blade along the spine, toothed when it has no lobes
  local bn = I("bn")
  loop("#kb", 0, bn, function()
    V.v = E"#kb/@bn" lspine(R.v) put(R["#kb"] + 1, R.sx, R.sy)
  end)
  normals(bn + 1)
  loop("#kb", 0, bn, function()
    V.v = E"#kb/@bn" lenv(R.v) V.h = E"@env*@bodyw"
    V.t = E"@v*3" lteeth(R.t) V.e = E"max(0,@h+@lent*@th)"
    V.q = (R["#kb"] + 1) * U
    sides(I("q"), "e")
  end)
  bladeassemble(bn) smoothprepT(2 * bn, K"0.8") keep("ls1")
  V.nshapes = U V.nveins = 0
  -- the lobes, grown out of the body along the spine
  if R.ldepth > 0 then
    loop("#kc", 0, 1, function()
      if R["#kc"] == 0 then V.side = -U else V.side = U end
      loop("#ka", 1, function() return I("llobes") end, function()
        V.lv = E"0.1+0.72*(#ka-(@side>0 ? 0.25 : 0.75))/@llobes"
        lspine(R.lv) V.lx = R.sx V.ly = R.sy ltan(R.lv)
        V.t = E"min(0.95,@lv+0.08)" lenv(R.t) V.t = range(K"0.95", K"1.15") V.reach = E"@env*@t"
        V.lang = range(38 * U, 58 * U)
        V.c = E"cos(@lang)" V.sn = E"sin(@lang)*@side"
        V.ldx = E"@tx*@c-@ty*@sn" V.ldy = E"@tx*@sn+@ty*@c"
        V.lL = E"@reach/sin(@lang)*0.95"
        V.t = sym(K"0.25") V.lb = E"@t-@side*0.15"
        loop("#kb", 0, 11, function()
          V.v = E"#kb/11"
          local x, y = lobepoint(R.v)
          V.sx = x V.sy = y
          put(R["#kb"] + 1, R.sx, R.sy)
        end)
        normals(12)
        loop("#kb", 0, 11, function()
          V.v = E"#kb/11" V.q = (R["#kb"] + 1) * U
          if R.v > K"0.2" then V.t = E"@v*1.4+#ka" lteeth(R.t) V.e = E"@th*@lL*4" else V.e = 0 end
          if R.v > 0 then V.g = E"pow(max(0,sin(180*pow(@v,0.62))),0.75)" else V.g = 0 end
          V.t = range(K"0.26", K"0.3") V.wa = E"max(0,@lL*@t*@g+@e)"
          V.t = range(K"0.26", K"0.3") V.wb = E"max(0,@lL*@t*@g+@e)"
          local q = I("q")
          V.xl = E("%1+%2*@wa", { X[q], NX[q] }) V.yl = E("%1+%2*@wa", { Y[q], NY[q] })
          V.xr = E("%1-%2*@wb", { X[q], NX[q] }) V.yr = E("%1-%2*@wb", { Y[q], NY[q] })
          setv(RX, q, R.xl) setv(RY, q, R.yl) setv(QX, q, R.xr) setv(QY, q, R.yr)
        end)
        -- the lobe's vein: base, middle (t 0.45) and end (t 0.92) of its spine
        V.nveins = R.nveins + U
        V.t = K"0.45"
        local mx, my = lobepoint(R.t)
        V.mx = mx V.my = my
        V.t = K"0.92"
        local ex, ey = lobepoint(R.t)
        V.ex = ex V.ey = ey
        setv(T.VEIN, I("nveins"), { R.lx, R.ly, R.mx, R.my, R.ex, R.ey })
        bladeassemble(11) smoothprepT(22, K"0.8")
        V.nshapes = R.nshapes + U keep("ls" .. I("nshapes"))
      end)
    end)
  end
  vtone("flo@c", R.lt) vfill("flo@c", U, 0, leaftrace)
  scope(function()
    leaftrace() usepath("clip")
    -- the darker half
    if chance(K"0.5") then V.sd = U else V.sd = -U end
    V.hp = ""
    loop("#kb", 0, 30, function()
      V.v = E"#kb/30" lspine(R.v)
      if R["#kb"] == 0 then moveto(R.sx, R.sy) else lineto(R.sx, R.sy) end
    end)
    V.t = E"@sd*2" lineto(R.t, U) lineto(R.t, 0) closepath()
    scope(function()
      vtone("flo@c", K"0.12") out("\\pgfsetfillcolor{flo@c}\\pgfsetfillopacity{0.28}\\pgfsetblendmode{multiply}")
      usepath("fill")
    end)
    V.xa = E"-@lW*2.5" V.xb = E"@lW*2.5" V.ta = E"@lt-0.2" V.tb = E"@lt+0.22"
    if R.fine == U then vmottle("xa", 0, "xb", U, 13, K"0.11", R.ta, R.tb, 12)
    else vmottle("xa", 0, "xb", U, 6, K"0.11", R.ta, R.tb, 0) end
    vtone("flo@c", K"0.06") V.t = E"1.3*@vl@u" vstroke("flo@c", R.t, K"0.22", 1, leaftrace)
    -- midrib and veins in white
    loop("#kb", 0, 10, function() V.v = E"#kb/10" lspine(R.v) put(R["#kb"] + 1, R.sx, R.sy) end)
    vstreak(11, K"0.03", K"0.003", "white", K"0.78")
    loop("#ka", 1, function() return I("nveins") end, function()
      local v = T.VEIN[R["#ka"]]
      V.va = v[1] V.vb = v[2] V.mx = v[3] V.my = v[4] V.ex = v[5] V.ey = v[6]
      V.c = E"@mx+(@ex-@mx)*0.5" V.d = E"@my+(@ey-@my)*0.5"
      V.twa = K"0.017" V.twb = K"0.002" V.op = range(K"0.5", K"0.75")
      vfill("white", R.op, 0, function() vtaper(R.va, R.vb, R.mx, R.my, R.c, R.d, R.ex, R.ey) end)
    end)
    if R.nveins == 0 then
      loop("#ka", 1, 9, function()
        V.v = E"(#ka-0.3)/10*0.9"
        if R["#ka"] % 2 == 1 then V.sg = -U else V.sg = U end
        lspine(R.v) V.lx = R.sx V.ly = R.sy ltan(R.v)
        V.nx = E"-@ty*@sg" V.ny = E"@tx*@sg"
        lenv(R.v) V.t = range(K"0.75", K"0.95") V.lL = E"@env*@bodyw*@t"
        V.pa = E"@lx+@nx*@lL*0.4" V.pb = E"@ly+@ny*@lL*0.4"
        V.pc = E"@lx+@nx*@lL*0.75+@tx*@lL*0.3" V.pd = E"@ly+@ny*@lL*0.75+@ty*@lL*0.3"
        V.pe = E"@lx+@nx*@lL*0.95+@tx*@lL*0.6" V.pf = E"@ly+@ny*@lL*0.95+@ty*@lL*0.6"
        V.qa = R.pa V.qb = R.pb V.qc = R.pc V.qd = R.pd V.qe = R.pe V.qf = R.pf
        V.twa = K"0.014" V.twb = K"0.002" V.op = range(K"0.45", K"0.7")
        vfill("white", R.op, 0, function() vtaper(R.lx, R.ly, R.qa, R.qb, R.qc, R.qd, R.qe, R.qf) end)
      end)
    end
  end)
  if R.lent == U then vtone("flo@c", K"0.05") vstroke("flo@c", K"0.18", K"0.4", 0, function() kept("ls1") end) end
end

-- ---------------------------------------------------------------- leaflet, strap, lily, floret, bud
-- the darker half of a blade folded along its rib, filled in a scope (flora.leaf)
local function darkhalf(t, op)
  scope(function()
    vtone("flo@c", t) out("\\pgfsetfillcolor{flo@c}\\pgfsetfillopacity{" .. op .. "}\\pgfsetblendmode{multiply}")
    usepath("fill")
  end)
end
-- \flo@vleaflet: flora.leaflet, +y, length 1
local function vleaflet()
  if R["vl@W"] == "" then V.lW = range(K"0.16", K"0.24") else V.lW = R["vl@W"] end
  V.lbend = sym(K"0.2")
  if R["vl@tone"] == "" then V.lt = range(K"0.2", K"0.34") else V.lt = R["vl@tone"] end
  loop("#kb", 0, 18, function() V.v = E"#kb/18" V.sx = E"@lbend*@v*@v" put(R["#kb"] + 1, R.sx, R.v) end)
  normals(19)
  loop("#kb", 0, 18, function()
    V.v = E"#kb/18" V.q = (R["#kb"] + 1) * U
    if R.v > 0 and R.v < U then V.w = E"@lW*2.2*pow(@v,0.5)*pow(1-@v,0.9)" else V.w = 0 end
    sides(I("q"), "w")
  end)
  for kb = 1, 19 do setv(T.MX, kb, X[kb]) setv(T.MY, kb, Y[kb]) setv(T.MU, kb, NX[kb]) setv(T.MV, kb, NY[kb]) end
  V["#kb"] = 20
  bladeassemble(18) smoothprep(36) keep("lf")
  vtone("flo@c", R.lt) vfill("flo@c", U, 0, function() kept("lf") end)
  if R["vl@u"] > K"0.25" then
    scope(function()
      kept("lf") usepath("clip")
      if chance(K"0.5") then V.sd = U else V.sd = -U end
      moveto(T.MX[1], T.MY[1])
      loop("#kb", 2, 19, function() lineto(T.MX[R["#kb"]], T.MY[R["#kb"]]) end)
      loop("#kb", 1, 19, function()
        V.q = (20 - R["#kb"]) * U
        local q = I("q")
        V.xl = E("%1+@sd*%2", { T.MX[q], T.MU[q] }) V.yl = E("%1+@sd*%2", { T.MY[q], T.MV[q] })
        lineto(R.xl, R.yl)
      end)
      closepath()
      darkhalf(K"0.08", "0.3")
      loop("#kb", 0, 10, function() V.v = E"#kb/10" V.sx = E"@lbend*@v*@v" put(R["#kb"] + 1, R.sx, R.v) end)
      vstreak(11, K"0.03", K"0.003", "white", K"0.65")
      vtone("flo@c", K"0.06") V.t = E"1.3*@vl@u" vstroke("flo@c", R.t, K"0.3", 1, function() kept("lf") end)
    end)
  end
end
-- \flo@vstrap: a monocot's strap leaf, +y, length 1 (\flo@lW set before)
local function vstrap()
  V.lbend = sym(K"0.25")
  if R.sbend ~= nil then V.lbend = R.sbend end
  V.lt = range(K"0.24", K"0.34")
  loop("#kb", 0, 24, function() V.v = E"#kb/24" V.sx = E"@lbend*@v*@v" put(R["#kb"] + 1, R.sx, R.v) end)
  normals(25)
  loop("#kb", 0, 24, function()
    V.v = E"#kb/24" V.q = (R["#kb"] + 1) * U
    if R.v > 0 and R.v < U then V.w = E"@lW*2.2*pow(@v,0.25)*pow(1-@v,0.6)" else V.w = 0 end
    sides(I("q"), "w")
  end)
  bladeassemble(24) smoothprep(48) keep("st")
  vtone("flo@c", R.lt) vfill("flo@c", U, 0, function() kept("st") end)
  scope(function()
    kept("st") usepath("clip")
    if chance(K"0.5") then V.sd = U else V.sd = -U end
    loop("#kb", 0, 12, function()
      V.v = E"#kb/12" V.sx = E"@lbend*@v*@v"
      if R["#kb"] == 0 then moveto(R.sx, R.v) else lineto(R.sx, R.v) end
    end)
    V.t = E"@sd*2" lineto(R.t, U) lineto(R.t, 0) closepath()
    darkhalf(K"0.12", "0.28")
    V.xa = E"-@lW*2.5" V.xb = E"@lW*2.5" V.ta = E"@lt-0.2" V.tb = E"@lt+0.22"
    vmottle("xa", 0, "xb", U, 10, K"0.07", R.ta, R.tb, 8)
    vtone("flo@c", K"0.06") V.t = E"1.3*@vl@u" vstroke("flo@c", R.t, K"0.22", 1, function() kept("st") end)
    -- the midrib in white, and faint parallel veins either side
    loop("#kb", 0, 10, function()
      V.v = E"0.02+0.93*#kb/10" V.sx = E"@lbend*@v*@v" put(R["#kb"] + 1, R.sx, R.v)
    end)
    vstreak(11, K"0.016", K"0.002", "white", K"0.7")
    loop("#ka", 1, 4, function()
      V.f = E"(#ka<3 ? #ka-3 : #ka-2)*0.38"
      loop("#kb", 0, 10, function()
        V.v = E"0.05+0.85*#kb/10"
        V.w = E"@f*@lW*2.2*pow(@v,0.25)*pow(1-@v,0.6)"
        V.sx = E"@lbend*@v*@v+@w" put(R["#kb"] + 1, R.sx, R.v)
      end)
      V.op = range(K"0.18", K"0.32") vstreak(11, K"0.007", K"0.001", "white", R.op)
    end)
  end)
end
-- \flo@vlily{u}: a star lily at a tilt, six pointed petals, back ones first
local function vlily(u)
  V.vu = u
  V.tilt = range(K"0.45", K"0.62") V.spin = range(0, 60 * U)
  if R["vf@tone"] == "" then V.tq = range(K"0.30", K"0.38") else V.tq = R["vf@tone"] end
  loop("#ka", 1, 6, function() V.t = sym(8 * U) V.a = E"@spin+(#ka-1)*60+@t" setv(T.O, R["#ka"], R.a) end)
  loop("#ka", 1, 5, function()
    loop("#kb", 1, function() return 6 - R["#ka"] end, function()
      local kb = R["#kb"]
      V.ia = T.O[kb] V.ib = T.O[kb + 1]
      V.t = E"sin(@ib)>sin(@ia) ? 1 : 0"
      if R.t == U then setv(T.O, kb, R.ib) setv(T.O, kb + 1, R.ia) end
    end)
  end)
  loop("#kc", 1, 6, function()
    V.a = T.O[R["#kc"]] V.back = E"sin(@a)"
    V.js = range(K"0.88", K"1.05")
    V.lw = range(K"0.11", K"0.14") V.t = sym(K"0.03") V.tp = E"@tq+0.1*@back*-0.8+@t"
    if chance(K"0.5") then V.sg = U else V.sg = -U end
    V.t = range(K"0.04", K"0.14") V.pbend = E"@sg*@t"
    V.pns = int(3, 4)
    scope(function()
      yscale(R.tilt) V.t = E"@a-90" rotate(R.t) scale(R.js)
      V["vp@pointed"] = U V["vp@W"] = R.lw V["vp@bend"] = R.pbend V["vp@ns"] = R.pns
      V["vp@heart"] = 0 V["vp@tone"] = R.tp V["vp@u"] = R.vu
      vpetal()
    end)
  end)
  loop("#ka", 1, 4, function()
    V.t = E"0.05+0.05*#ka" V.ms = E"@t*@tilt"
    vblob(0, 0, R.t, R.ms, K"0.2", 9) vfill("white", K"0.22", 0, smoothpath)
  end)
  loop("#ka", 1, 6, function()
    V.t = sym(6 * U) V.a = E"(#ka-3.5)*16+@t" V.len = range(K"0.3", K"0.48")
    V.ex = E"@len*sin(@a)" V.ey = E"@len*cos(@a)"
    V.c = E"@ex*0.2" V.d = E"@ey*0.5" V.cc = E"@ex*0.8" V.dd = E"@ey*0.85"
    vbezier(0, 0, R.c, R.d, R.cc, R.dd, R.ex, R.ey)
    vtone("flo@c", K"0.12") vstroke("flo@c", K"0.25", K"0.85", 0, openpath)
    V.t = sym(30 * U) V.t = E"-@a+@t"
    scope(function()
      shift(R.ex, R.ey) rotate(R.t)
      vblob(0, 0, K"0.022", K"0.04", K"0.1", 6) vtone("flo@c", K"0.05") vfill("flo@c", U, 0, smoothpath)
    end)
    if chance(K"0.5") then
      V.t = sym(K"0.03") V.xa = E"@ex+@t" V.t = range(K"0.02", K"0.05") V.ya = E"@ey+@t"
      vaccent("flo@c", 0) vfill("flo@c", U, 0, function() circle(R.xa, R.ya, K"0.008") end)
    end
  end)
  vaccent("flo@c", K"-0.2") vfill("flo@c", U, 0, function() circle(0, 0, K"0.035") end)
end
-- \flo@vfloret{r}{n}: a small flower of n petals, radius 1; r its radius in cm
local function vfloret(r, n)
  if R["vf@star"] == "" then
    if chance(K"0.5") then V.star = U else V.star = 0 end
  else V.star = R["vf@star"] end
  V.fn = n
  if r < K"0.07" then
    V.ph = range(0, 360 * U)
    loop("#kb", 0, function() return 2 * I("fn") - 1 end, function()
      V.a = E"@ph+#kb*180/@fn"
      if R["#kb"] % 2 == 1 then V.r = E"@star==1 ? 0.32 : 0.62" else V.r = U end
      V.xa = E"@r*cos(@a)" V.ya = E"@r*sin(@a)"
      put(R["#kb"] + 1, R.xa, R.ya)
    end)
    if R["vf@tone"] == "" then V.tq = range(K"0.22", K"0.42") else V.tq = R["vf@tone"] end
    vtone("flo@c", R.tq)
    vfill("flo@c", U, 0, function()
      moveto(X[1], Y[1])
      loop("#kb", 2, function() return 2 * I("fn") end, function() lineto(X[R["#kb"]], Y[R["#kb"]]) end)
      closepath()
    end)
    vtone("flo@c", K"0.05")
    vfill("flo@c", U, 0, function()
      moveto(K"0.2", 0) lineto(0, K"0.2") lineto(-K"0.2", 0) lineto(0, -K"0.2") closepath()
    end)
  else
    V.ph = range(0, 360 * U)
    local spk = {}
    loop("#ka", 0, function() return I("fn") - 1 end, function()
      V.t = sym(K"8.6") V.a = E"@ph+#ka*360/@fn+@t" V.len = range(K"0.85", K"1.1")
      V.c = E"cos(@a)" V.sn = E"sin(@a)"
      if R.star == U then
        put(1, 0, 0) put(2, K"0.45", K"0.156") put(3, U, 0) put(4, K"0.45", K"-0.156") V.np = 4 * U V.tk = K"0.5"
      else
        put(1, 0, 0) put(2, K"0.3", K"0.42") put(3, K"0.85", K"0.336") put(4, U, 0)
        put(5, K"0.85", K"-0.336") put(6, K"0.3", K"-0.42")
        V.np = 6 * U V.tk = U
      end
      loop("#kb", 1, function() return I("np") end, function()
        local kb = R["#kb"]
        V.xa = E("@len*(%1*@c-%2*@sn)", { X[kb], Y[kb] })
        V.ya = E("@len*(%1*@sn+%2*@c)", { X[kb], Y[kb] })
        setv(T.TX, kb, R.xa) setv(T.TY, kb, R.ya)
      end)
      loop("#kb", 1, function() return I("np") end, function() local kb = R["#kb"] put(kb, T.TX[kb], T.TY[kb]) end)
      smoothprepT(I("np"), R.tk)
      spk[#spk + 1] = "\\pgfpathmoveto{" .. P(X[1], Y[1]) .. "}"
      loop("#i", 1, function() return I("np") end, function()
        local i, np = R["#i"], I("np")
        V.ib = (i == np and 1 or i + 1) * U
        local ib = I("ib")
        spk[#spk + 1] = "\\pgfpathcurveto{" .. P(A[i], B[i]) .. "}{" .. P(C[i], D[i]) .. "}{" .. P(X[ib], Y[ib]) .. "}"
      end)
      spk[#spk + 1] = "\\pgfpathclose"
    end)
    if R["vf@tone"] == "" then V.tq = range(K"0.22", K"0.42") else V.tq = R["vf@tone"] end
    vtone("flo@c", R.tq) vfill("flo@c", U, 0, function() out(concat(spk)) end)
    if r > K"0.05" then vfill("white", K"0.75", 0, function() circle(0, 0, K"0.35") end) end
    vtone("flo@c", K"0.05") vfill("flo@c", U, 0, function() circle(0, 0, K"0.16") end)
  end
end
-- \flo@vbud{u}: a teardrop and three sepals, base at the origin, +y, length 1
local function vbud(u)
  V.bend = sym(K"0.1")
  loop("#kb", 0, 18, function() V.v = E"#kb/18" V.sx = E"@bend*@v*@v" put(R["#kb"] + 1, R.sx, R.v) end)
  normals(19)
  loop("#kb", 0, 18, function()
    V.v = E"#kb/18" V.q = (R["#kb"] + 1) * U
    if R.v > 0 then V.w = E"0.3*pow(max(0,sin(180*pow(@v,0.6))),0.8)" else V.w = 0 end
    if R.w < 0 then V.w = 0 end
    sides(I("q"), "w")
  end)
  bladeassemble(18) smoothprep(36) keep("bd")
  if R["vf@tone"] == "" then V.tq = range(K"0.3", K"0.42") else V.tq = R["vf@tone"] end
  vtone("flo@c", R.tq) vfill("flo@c", U, 0, function() kept("bd") end)
  scope(function()
    kept("bd") usepath("clip")
    V.ta = E"@tq-0.2" V.tb = E"@tq+0.2" vmottle(K"-0.3", 0, K"0.3", U, 5, K"0.1", R.ta, R.tb, 0)
    V.twa = K"0.06" V.twb = K"0.005" V.t = E"@bend*0.8"
    vfill("white", K"0.7", 0, function() vtaper(K"-0.08", K"0.05", K"-0.1", K"0.35", K"-0.05", K"0.65", R.t, K"0.95") end)
    vtone("flo@c", K"0.06") V.t = E("1.4*(%1)", { u }) vstroke("flo@c", R.t, K"0.3", 1, function() kept("bd") end)
  end)
  -- the sepals: three small blades, transformed here so that they fill as one path
  local spk = {}
  loop("#ka", 0, 2, function()
    V.k = (R["#ka"] - 1) * U V.t = sym(6 * U) V.a = E"@k*24+@t"
    if R.k == 0 then V.sy = K"0.22" else V.sy = K"0.32" end
    loop("#kb", 0, 8, function() V.v = E"#kb/8" V.sx = E"-@k*0.4*@v*@v" put(R["#kb"] + 1, R.sx, R.v) end)
    normals(9)
    loop("#kb", 0, 8, function()
      V.v = E"#kb/8" V.q = (R["#kb"] + 1) * U
      if R.v > 0 then V.w = E"sin(180*pow(@v,0.6))" else V.w = 0 end
      if R.w < 0 then V.w = 0 end
      sides(I("q"), "w")
    end)
    bladeassemble(8)
    loop("#kb", 1, 16, function()
      local kb = R["#kb"]
      V.xa = E("0.06*%1", { X[kb] }) V.ya = E("@sy*%1", { Y[kb] })
      V.xb = E"@k*0.05+@xa*cos(@a)-@ya*sin(@a)" V.yb = E"-0.02+@xa*sin(@a)+@ya*cos(@a)"
      put(kb, R.xb, R.yb)
    end)
    smoothprep(16)
    spk[#spk + 1] = "\\pgfpathmoveto{" .. P(X[1], Y[1]) .. "}"
    loop("#i", 1, 16, function()
      local i = R["#i"]
      V.ib = (i == 16 and 1 or i + 1) * U
      local ib = I("ib")
      spk[#spk + 1] = "\\pgfpathcurveto{" .. P(A[i], B[i]) .. "}{" .. P(C[i], D[i]) .. "}{" .. P(X[ib], Y[ib]) .. "}"
    end)
    spk[#spk + 1] = "\\pgfpathclose"
  end)
  vtone("flo@c", K"0.14") vfill("flo@c", K"0.9", 0, function() out(concat(spk)) end)
end

-- ================================================================ the species, in v1.3's hand
local function tr(name) return R["v@" .. name] end
-- \flo@stone: the flower's tone from its color group
local STONE = { violet = { "0.18", "0.26" }, pink = { "0.34", "0.42" }, white = { "0.46", "0.54" },
  yellow = { "0.4", "0.48" }, green = { "0.38", "0.46" }, red = { "0.3", "0.4", true }, orange = { "0.42", "0.52", true } }
local function stone()
  V.col = tr("color") V.rampname = "flo@ramp" V["vf@tone"] = ""
  local s = STONE[R.col]
  if s then
    if s[3] then V.rampname = "flo@aramp" end
    V["vf@tone"] = range(K(s[1]), K(s[2]))
  end
end
local vblossom, vboss
-- \flo@sdaisy{d}: a daisy head, diameter 1
local function sdaisy(d)
  V.nr = tr("merosity") V.spin = range(0, 360 * U)
  if R["vf@tone"] == "" then V.tq = range(K"0.3", K"0.46") else V.tq = R["vf@tone"] end
  V.vu = E("(%1)*0.36/28.45276", { d })
  loop("#ka", 1, function() return I("nr") end, function()
    V.t = sym(4 * U) V.a = E"@spin+#ka*360/@nr+@t-90"
    V.js = range(K"0.9", K"1.05") V.t = sym(K"0.04") V.tp = E"@tq+@t"
    V.lw = E"min(0.17,1.6/@nr)"
    scope(function()
      rotate(R.a) shift(0, K"0.1") scale(K"0.4") scale(R.js)
      V["vp@pointed"] = 0 V["vp@W"] = R.lw V["vp@bend"] = "" V["vp@ns"] = 2 * U V["vp@heart"] = 0
      V["vp@tone"] = R.tp V["vp@u"] = R.vu vpetal()
    end)
  end)
  V.savedramp = R.rampname V.rampname = "flo@aramp"
  vtone("flo@c", K"0.3") vfill("flo@c", U, 0, function() circle(0, 0, K"0.105") end)
  V.nd = E("int(min(90,max(24,(%1)*1.2)))", { d })
  vtone("flo@c", K"0.68")
  local spk = {}
  loop("#ka", 1, function() return I("nd") end, function()
    V.r = E"0.095*sqrt(#ka/@nd)" V.a = E"137.508*#ka"
    V.dx = E"@r*cos(@a)" V.dy = E"@r*sin(@a)"
    V.dr = E"0.004+0.006*sqrt(#ka/@nd)"
    spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.dx, R.dy) .. "}{" .. str(R.dr) .. "pt}"
  end)
  vfill("flo@c", K"0.9", 0, function() out(concat(spk)) end)
  V.rampname = R.savedramp
end
-- \flo@sflower{d}: the species' flower face on, diameter 1; d its diameter in pt
local function sflower(d)
  V.sfd = d V.form = tr("form") V.nn = tr("merosity")
  if tr("merovar") == U then
    V.t = int(1, 10)
    if R.t == U then V.nn = R.nn - U end
    if R.t > 7 * U then V.nn = R.nn + U end
  end
  V.ps = tr("petalshape") V["vf@pointed"] = 0
  if R.ps == "lanceolate" or R.ps == "linear" then V["vf@pointed"] = U end
  if R.form == "head" then sdaisy(R.sfd)
  elseif R.form == "lily" then
    scope(function()
      scale(K"0.48") V.oarg = E"(@sfd)*0.48/28.45276" vlily(R.oarg)
      V.t = tr("corona") V.tmp = "none"
      if R.t ~= R.tmp then T.vcorona(R.oarg) end
    end)
  else
    V.tmp = "iris" V.ivon = 0
    if R.form == R.tmp and R.sfd >= 8 * U then V.ivon = U end
    if R.ivon == U then T.viris(R.sfd)
    elseif R.sfd < (22 * U) then
      V.t = E"max(4,min(6,@nn))" V.fp = pm.int(R.t)
      if R.sfd < (8 * U) then
        V["vf@star"] = R["vf@pointed"]
        scope(function() scale(K"0.5") V.oarg = E"(@sfd)*0.5/28.45276" vfloret(R.oarg, R.fp) end)
      else
        scope(function() scale(K"0.5") V.oarg = E"(@sfd)*0.5/28.45276" vblossom(R.oarg, R.fp) end)
      end
    else
      if tr("clade") == "monocot" then V.np = 2 * R.nn else V.np = R.nn end
      if R["vf@pointed"] == U then V["vf@W"] = nil
      else
        V["vf@W"] = E"max(0.28,min(0.5,0.66/$petalaspect))"
        if R.form == "cruciform" then V["vf@W"] = K"0.3" end
      end
      if tr("guides") == "none" then
        if R["vf@pointed"] == 0 then V["vf@ns"] = 5 * U else V["vf@ns"] = nil end
      else V["vf@ns"] = nil end
      if R.form == "rosaceous" then V["vf@ns"] = 3 * U V["vp@notchp"] = K"0.85" V["vp@notchk"] = K"1.6" end
      scope(function() scale(K"0.45") V.vs = E"(@sfd)*0.45/28.45276" vflower(R.vs, R.np) end)
      if R.form == "rosaceous" then vboss() end
    end
  end
end
-- \flo@vboss: the rose family's ring of stamens, face on
function vboss()
  if tr("stamens") == "exserted" then V.bl = K"0.04" else V.bl = 0 end
  V.bn = int(36, 52) V.bph = range(0, 360 * U)
  local spk, spa = {}, {}
  loop("#Gc", 1, function() return I("bn") end, function()
    V.t = sym(4 * U) V.a = E"@bph+360/@bn*#Gc+@t"
    V.t = range(K"0.09", K"0.17") V.r = E"@t+@bl"
    V.xa = E"0.035*cos(@a)" V.ya = E"0.035*sin(@a)"
    V.xb = E"@r*cos(@a)" V.yb = E"@r*sin(@a)"
    spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.ya) .. "}\\pgfpathlineto{" .. P(R.xb, R.yb) .. "}"
    V.t = range(K"0.007", K"0.011")
    spa[#spa + 1] = "\\pgfpathcircle{" .. P(R.xb, R.yb) .. "}{" .. str(R.t) .. "pt}"
  end)
  vtone("flo@c", K"0.14") vstroke("flo@c", K"0.2", K"0.8", 0, function() out(concat(spk)) end)
  V.savedramp = R.rampname V.rampname = "flo@aramp"
  vtone("flo@c", K"0.42") vfill("flo@c", U, 0, function() out(concat(spa)) end)
  vtone("flo@c", K"0.66") vfill("flo@c", U, 0, function() circle(0, 0, K"0.045") end)
  V.rampname = R.savedramp
  vtone("flo@c", K"0.2") vfill("flo@c", K"0.9", 0, function()
    circle(K"0.014", K"0.009", K"0.009") circle(K"-0.012", K"0.013", K"0.009") circle(K"-0.002", K"-0.015", K"0.009")
  end)
end
-- \flo@blade{halfwidth}{length pt}{tone}: a leaflet of a compound leaf
local function blade(w, len, t)
  V["vl@W"] = w V["vl@tone"] = t V["vl@u"] = E("(%1)/28.45276", { len }) vleaflet()
end
-- \flo@pinnate{leaf pt}{pairs}{leaflet length}: the leaf pt may be a macro name (read late)
local function pinnate(lpt, pairs, pl)
  moveto(0, 0) lineto(0, U) usepath("stroke")
  V.pk = pairs V.pl = pl
  loop("#j", 1, function() return I("pk") end, function()
    V.v = E"0.22+0.66*(#j-1)/max(1,@pk-1)"
    V.ll = E"@pl*(1-0.3*(#j-1)/max(1,@pk))"
    loop("#n", 0, 1, function()
      V.ang = range(45 * U, 65 * U) V.dv = sym(K"0.02")
      scope(function()
        V.t = E"@v+@dv" shift(0, R.t)
        if R["#n"] == 0 then rotate(R.ang) else rotate(-R.ang) end
        scale(R.ll) V.t = E("(%1)*@ll", { arg(lpt) })
        V.tp = range(E"@lt-0.07", E"@lt+0.07")
        blade(R.hw, R.t, R.tp)
      end)
    end)
  end)
  if tr("tendrils") == U then
    tone("flo@c", K"0.22", "flo@ink") out("\\pgfsetstrokecolor{flo@c}\\pgfsetlinewidth{0.25pt}")
    if chance(K"0.4") then V.tdn = 2 * U else V.tdn = U end
    loop("#q", 1, function() return I("tdn") end, function()
      scope(function()
        shift(0, U)
        if R.tdn == U then V.t = sym(15 * U)
        else
          V.t = range(10 * U, 30 * U)
          if R["#q"] == 2 then V.t = E"-@t" end
        end
        rotate(R.t)
        V.t = range(K"0.35", K"0.55") T.vcurl(R.t) T.smoothopen(45) usepath("stroke")
      end)
    end)
  else
    scope(function()
      shift(0, U) scale(R.pl) V.t = E("(%1)*@pl", { arg(lpt) })
      blade(R.hw, R.t, R.lt)
    end)
  end
end
-- \flo@bipinnate{leaf pt}: pinnae that are themselves pinnate
local function bipinnate(lpt)
  moveto(0, 0) lineto(0, U) usepath("stroke")
  V.bk = E"int(min(4,$leaflets))" V.bl = int(2, 4) V.lt = E"@lt+0.08"
  loop("#m", 1, function() return I("bk") end, function()
    V.bv = E"0.15+0.75*(#m-1)/max(1,@bk-1)"
    V.bs = E"0.45*(1-0.55*(#m-1)/max(1,@bk))"
    loop("#p", 0, 1, function()
      V.bang = range(40 * U, 60 * U)
      scope(function()
        shift(0, R.bv)
        if R["#p"] == 0 then rotate(R.bang) else rotate(-R.bang) end
        scale(R.bs) V.t = E("(%1)*@bs", { lpt })
        pinnate("t", R.bl, K"0.42")
      end)
    end)
  end)
end
-- \flo@palmate{leaf pt}{n}: leaflets from the tip of a petiole (length 0.35)
local function palmate(lpt, n)
  moveto(0, 0) lineto(0, K"0.35") usepath("stroke")
  V.pk = n
  loop("#j", 1, function() return I("pk") end, function()
    V.f = E"(#j-(@pk+1)/2)/max(1,(@pk-1)/2)"
    V.dv = sym(6 * U)
    V.ang = E"-@f*(@pk>3 ? 95 : 55)+@dv" V.ll = E"0.65*(1-0.3*abs(@f))"
    scope(function()
      shift(0, K"0.35") rotate(R.ang) scale(R.ll)
      V.t = E("(%1)*@ll", { lpt }) blade(R.hw, R.t, R.lt)
    end)
  end)
end
-- \flo@leaf{length pt}: the species' leaf along +y, length 1
local function leaf(len)
  V.lfpt = len V.cp = tr("compound") V.ve = tr("venation")
  V["vl@u"] = E"(@lfpt)/28.45276"
  if R.cp == "simple" then
    if R.ve == "parallel" then
      V.lW = E"max(0.025,min(0.12,0.42/$leafaspect))" vstrap()
    else
      V["vl@W"] = E"max(0.07,min(0.4,0.52/$leafaspect))"
      if R.sbend ~= nil then V["vl@bend"] = R.sbend else V["vl@bend"] = "" end
      V["vl@tone"] = ""
      V.lm = tr("leafmargin") V["vl@depth"] = 0 V["vl@lobes"] = 3 * U
      local lobed = R.lm == "lobed" or R.lm == "pinnatifid" or R.lm == "palmatelobed"
      if lobed then
        V["vl@depth"] = E"min(0.85,max(0.3,$dissection))"
        V.t = E"max(2,min(6,$teeth))" V["vl@lobes"] = pm.int(R.t)
      end
      vleaf()
    end
  else
    V.lt = range(K"0.24", K"0.4")
    V.hw = E"0.5/min(4,max(1.6,$leafaspect))"
    tone("flo@c", K"0.07", "flo@ink") out("\\pgfsetstrokecolor{flo@c}")
    V.lw = E"max(0.25,0.006*(@lfpt))"
    out("\\pgfsetlinewidth{" .. str(R.lw) .. "bp}\\pgfsetroundcap")
    if R.cp == "pinnate" then V.t = E"int(min(5,$leaflets))" pinnate(R.lfpt, R.t, K"0.36") end
    if R.cp == "bipinnate" then bipinnate(R.lfpt) end
    if R.cp == "palmate" then V.hw = E"0.5/max(2.6,$leafaspect)" palmate(R.lfpt, tr("leaflets")) end
    if R.cp == "trifoliate" then palmate(R.lfpt, 3 * U) end
  end
end
-- \flo@vblossom{r}{n}: flora.blossom, n round petals, radius 1; r its radius in cm
function vblossom(r, n)
  V.bnp = n V.spin = range(0, 72 * U)
  if R["vf@tone"] == "" then V.tq = range(K"0.30", K"0.45") else V.tq = R["vf@tone"] end
  loop("#ka", 0, function() return I("bnp") - 1 end, function()
    V.t = sym(8 * U) V.a = E"@spin+#ka*360/@bnp+@t" V.js = range(K"0.9", K"1.08")
    V.pW = range(K"0.36", K"0.44")
    scope(function()
      rotate(R.a) scale(R.js)
      V["vp@pointed"] = 0
      loop("#kb", 0, 18, function()
        V.v = E"#kb/18" vhalf(R.v) V.q = (R["#kb"] + 1) * U
        local q = I("q")
        V.xl = E"-@h" setv(RX, q, R.xl) setv(RY, q, R.v) setv(QX, q, R.h) setv(QY, q, R.v)
      end)
      bladeassemble(18) smoothprep(36) keep("bl")
      V.t = sym(K"0.05") vtone("flo@c", E"@tq+@t") vfill("flo@c", U, 0, function() kept("bl") end)
      scope(function()
        kept("bl") usepath("clip")
        V.mx = sym(K"0.2") V.my = range(K"0.5", K"0.9")
        vblob(R.mx, R.my, K"0.35", K"0.3", K"0.3", 8) vtone("flo@c", E"@tq-0.2") vfill("flo@c", K"0.3", 1, smoothpath)
        V.twa = K"0.12" V.twb = K"0.01" V.t = sym(K"0.05")
        vfill("white", K"0.7", 0, function() vtaper(0, 0, K"0.02", K"0.2", K"-0.02", K"0.4", R.t, K"0.55") end)
        vtone("flo@c", K"0.08") V.t = E("1.2*(%1)", { r }) vstroke("flo@c", R.t, K"0.25", 1, function() kept("bl") end)
      end)
    end)
  end)
  vfill("white", K"0.85", 0, function() circle(0, 0, K"0.22") end)
  vtone("flo@c", K"0.08") vfill("flo@c", U, 0, function() circle(0, 0, K"0.09") end)
end

-- ---------------------------------------------------------------- fruit
-- \flo@vclock: a seed clock (flora.seedhead), radius 1 around the origin
local function vclock()
  V.cn = int(18, 26) V.gone = range(0, 360 * U)
  local spk = {}
  loop("#Gc", 1, function() return I("cn") end, function()
    V.t = sym(K"0.3") V.a = E"360*(#Gc+@t)/@cn"
    V.t = rnd() V.t = E"abs(mod(@a-@gone+540,360)-180)<30 && @t<0.7 ? 0 : 1"
    V.L = range(K"0.72", K"0.86")
    if R.t > K"0.5" then
      V.xa = E"0.1*cos(@a)" V.ya = E"0.1*sin(@a)" V.xb = E"@L*cos(@a)" V.yb = E"@L*sin(@a)"
      spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.ya) .. "}\\pgfpathlineto{" .. P(R.xb, R.yb) .. "}"
      loop("#Gd", -2, 2, function()
        V.b = E"@a+18*#Gd"
        V.xa = E"@xb+0.16*cos(@b)" V.ya = E"@yb+0.16*sin(@b)"
        spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xb, R.yb) .. "}\\pgfpathlineto{" .. P(R.xa, R.ya) .. "}"
      end)
    end
  end)
  vtone("flo@c", K"0.16") vstroke("flo@c", K"0.22", K"0.85", 0, function() out(concat(spk)) end)
  vtone("flo@c", K"0.12") vfill("flo@c", U, 0, function() circle(0, 0, K"0.13") end)
end
-- \flo@fruit: the species' fruit along +y, length 1; \flo@fu its cm per unit
local function fruit()
  V.fr = tr("fruit") V["vf@tone"] = ""
  local fr = R.fr
  if fr == "hip" then
    scope(function()
      V.rampname = "flo@aramp" V["vf@tone"] = K"0.36"
      shift(0, U) rotate(180 * U) vbud(R.fu)
    end)
  elseif fr == "capsule" then
    scope(function()
      V["vf@tone"] = K"0.38" vbud(R.fu)
      V.twa = K"0.025" V.twb = K"0.004"
      vfill("white", K"0.55", 0, function() vtaper(K"-0.06", K"0.15", K"-0.1", K"0.4", K"-0.08", K"0.7", K"-0.02", K"0.95") end)
      vfill("white", K"0.4", 0, function() vtaper(K"0.06", K"0.15", K"0.1", K"0.4", K"0.08", K"0.7", K"0.02", K"0.95") end)
    end)
  elseif fr == "pappus" then
    scope(function() shift(0, K"0.5") vclock() end)
  else
    V["vl@tone"] = "" V["vl@u"] = R.fu
    if fr == "silique" then
      V["vl@W"] = K"0.07" V["vl@tone"] = range(K"0.3", K"0.4") vleaflet()
    elseif fr == "silicle" then
      scope(function() scale(K"0.6") V["vl@W"] = K"0.32" V["vl@tone"] = range(K"0.42", K"0.52") vleaflet() end)
    elseif fr == "schizocarp" then
      scope(function() scale(K"0.7") rotate(12 * U) V["vl@W"] = K"0.18" vleaflet() end)
      scope(function() scale(K"0.7") rotate(-12 * U) V["vl@W"] = K"0.18" vleaflet() end)
    else
      scope(function() scale(K"0.55") V["vl@W"] = K"0.22" V["vl@tone"] = range(K"0.12", K"0.2") vleaflet() end)
    end
  end
end

-- ================================================================ plants in v1.3's manner
-- the layers, numbered as in florilegium-grow.lua; a garden is walked once per layer and
-- draws only that layer's parts on each walk
local LSTEM, LLEAF, LAIRY, LBLOOM = 2, 3, 4, 5
local function at(l) return I("layer") == l end

-- ---------------------------------------------------------------- one stream per organ
local HALF = 1073741823
local function seedorgan()                                   -- \flo@seedorgan -> \flo@os
  rng.step()
  local z = rng.save()
  V.os = (z > HALF) and z - HALF or z + HALF                 -- an integer, as \numexpr gives it
end
local function drawstate(z) rng.load(z) rng.step() rng.step() end
local function organ(f)                                      -- \flo@organ{...}
  V.savez = rng.save()
  drawstate(R.os)
  scope(f)
  rng.load(R.savez)
end

-- ---------------------------------------------------------------- stems (flora.stem)
-- \flo@smoothopen{n}: an open Catmull-Rom curve through X/Y 1..n
local function smoothopen(n)
  V.N = n * U
  moveto(X[1], Y[1])
  loop("#i", 1, function() return I("N") - 1 end, function()
    local i, N = R["#i"], I("N")
    V.ia = (i == 1 and 1 or i - 1) * U V.ib = (i + 1) * U
    local ib = I("ib")
    V.ic = (ib == N and N or ib + 1) * U
    local ia, ic = I("ia"), I("ic")
    V.ca = E("%1+(%2-(%3))/6", { X[i], X[ib], X[ia] }) V.cb = E("%1+(%2-(%3))/6", { Y[i], Y[ib], Y[ia] })
    V.cc = E("%1-(%2-(%3))/6", { X[ib], X[ic], X[i] }) V.cd = E("%1-(%2-(%3))/6", { Y[ib], Y[ic], Y[i] })
    curveto(R.ca, R.cb, R.cc, R.cd, X[ib], Y[ib])
  end)
end
-- \flo@vcurl{size}: a tendril, each its own (run, side, turns, tightness), into X/Y 1..45.
-- It and smoothopen sit in T, which pinnate (above) can reach: Lua's 200 locals
T.smoothopen = smoothopen
function T.vcurl(size)
  V.tds = size
  if chance(K"0.5") then V.tdh = U else V.tdh = -U end
  V.t = range(K"0.2", K"0.9") V.tdd = E"@tds*@t/8" V.tdb = sym(4 * U)
  V.t = rnd() V.tdT = E"@tdh*(4+21*@t*sqrt(@t))"
  V.t = range(K"0.18", K"0.35") V.tdr = E"@tds*@t" V.tdq = range(K"0.12", K"0.45")
  V.tda = 90 * U V.tdx = 0 V.tdy = 0 put(1, 0, 0)
  loop("#Gt", 1, 8, function()
    V.tda = E"@tda+@tdb"
    V.tdx = E"@tdx+@tdd*cos(@tda)" V.tdy = E"@tdy+@tdd*sin(@tda)"
    put(R["#Gt"] + 1, R.tdx, R.tdy)
  end)
  loop("#Gt", 1, 36, function()
    V.tda = E"@tda+@tdT"
    V.t = E"@tdr*pow(@tdq,#Gt/36)*abs(@tdT)*0.0174533"
    V.tdx = E"@tdx+@t*cos(@tda)" V.tdy = E"@tdy+@t*sin(@tda)"
    put(R["#Gt"] + 9, R.tdx, R.tdy)
  end)
end
-- \flo@vstem{n}{w0}{w1}{tone}: a filled ribbon along X/Y 1..n (cm), or a stroke under 0.7 bp
local function vstem(n, w0, w1, t)
  V.sn = n * U
  V.t = E("((%1)+(%2))/2*28.3465", { w0, w1 })
  vtone("flo@c", t)
  if R.t < K"0.7" then
    vstroke("flo@c", R.t, U, 0, function() smoothopen(I("sn")) end)
  else
    local sn = I("sn")
    normals(sn)
    arclengths(sn)
    loop("#kb", 1, sn, function()
      local kb = R["#kb"]
      V.w = E("((%1)+((%2)-(%1))*%3/@acc)/2", { w0, w1, S[kb] })
      sides(kb, "w")
    end)
    ribbonsides(sn)
    smoothprep(2 * sn) vfill("flo@c", U, 0, smoothpath)
  end
end
-- \flo@cubicstem{w0}{w1}: along \flo@bxa.. \flo@byd, tone 0.07; not in a group, as in TeX
local function cubicstem(w0, w1)
  V.t = E("((%1)+(%2))/2*28.3465", { w0, w1 }) vtone("flo@c", K"0.07")
  if R.t < K"0.7" then
    vstroke("flo@c", R.t, U, 0, function()
      moveto(R.bxa, R.bya) curveto(R.bxb, R.byb, R.bxc, R.byc, R.bxd, R.byd)
    end)
  else
    V.twa = w0 V.twb = w1
    vfill("flo@c", U, 0, function() vtaper(R.bxa, R.bya, R.bxb, R.byb, R.bxc, R.byc, R.bxd, R.byd) end)
  end
end

-- ---------------------------------------------------------------- branches (flora.branch_path)
local function branchpath(x0, y0, tx, ty, x1, y1, ax, ay)
  local a = { x0, y0, tx, ty, x1, y1, ax, ay }
  V.dx = E("(%5)-(%1)", a) V.dy = E("(%6)-(%2)", a) V.d = pm.veclen(R.dx, R.dy)
  V.t = E("(%3)*@dx+(%4)*@dy<-0.3*@d ? -1 : 1", a)
  V.tx = E("@t*(%3)", a) V.ty = E("@t*(%4)", a)
  V.turn = range(28 * U, 48 * U)
  V.turn = E"(@tx*@dy-@ty*@dx>0 ? 1 : -1)*@turn"
  V.ox = E"@tx*cos(@turn)-@ty*sin(@turn)"
  V.oy = E"@tx*sin(@turn)+@ty*cos(@turn)"
  V.bxa = x0 V.bya = y0 V.bxd = x1 V.byd = y1
  V.bxb = E("(%1)+@ox*@d*0.45", a) V.byb = E("(%2)+@oy*@d*0.45", a)
  V.bxc = E("(%5)-(%7)*@d*0.4", a) V.byc = E("(%6)-(%8)*@d*0.4", a)
end
local function cubicat(t)                                    -- -> \flo@cx, \flo@cy, \flo@ca
  V.cu = E("1-(%1)", { t }) V.cv = t
  V.cwa = E"@cu*@cu*@cu" V.cwb = E"3*@cu*@cu*@cv"
  V.cwc = E"3*@cu*@cv*@cv" V.cwd = E"@cv*@cv*@cv"
  V.cx = E"@cwa*@bxa+@cwb*@bxb+@cwc*@bxc+@cwd*@bxd"
  V.cy = E"@cwa*@bya+@cwb*@byb+@cwc*@byc+@cwd*@byd"
  V.cwa = E"@cu*@cu" V.cwb = E"2*@cu*@cv" V.cwc = E"@cv*@cv"
  V.dx = E"@cwa*(@bxb-@bxa)+@cwb*(@bxc-@bxb)+@cwc*(@bxd-@bxc)"
  V.dy = E"@cwa*(@byb-@bya)+@cwb*(@byc-@byb)+@cwc*(@byd-@byc)"
  V.ca = pm.atan2(R.dy, R.dx)
end

-- ---------------------------------------------------------------- flowers, buds, clusters
-- ---------------------------------------------------------------- views
-- \flo@bview, \flo@vcalyx, \flo@vtube, \flo@turad, \flo@vsalver, in a block of their own
-- (Lua's 200 locals)
local VW = {}
do
  function VW.bview()
    V["or"] = tr("orient") V.fm = tr("form") V.bturn = 0
    if R["or"] == "erect" then V.vw = "face"
    else
      if R["or"] == "nodding" then V.vw = "back" else V.vw = "tilt" end
      V.tmp = "lily" if R.fm == R.tmp then V.vw = "lily" end
      V.tmp = "salverform" if R.fm == R.tmp then V.vw = "salver" end
    end
    V.tmp = "campanulate" if R.fm == R.tmp then V.vw = "tube" end
    V.tmp = "urceolate" if R.fm == R.tmp then V.vw = "tube" end
    V.tmp = "tubular" if R.fm == R.tmp then V.vw = "tube" end
    V.tmp = "funnelform" if R.fm == R.tmp then V.vw = "tube" end
    V.tmp = "papilionaceous" if R.fm == R.tmp then V.vw = "pea" end
    V.tmp = "bilabiate" if R.fm == R.tmp then V.vw = "lips" end
    V.tmp = "orchid" if R.fm == R.tmp then V.vw = "orchid" end
    if R["or"] ~= "erect" then V.tmp = "spurred" if R.fm == R.tmp then V.vw = "spur" end end
    if R["or"] == "erect" then
      if R.vw == "tube" then V.bturn = sym(15 * U) end
    else
      if R.bside == "" then
        if chance(K"0.5") then V.bsd = U else V.bsd = -U end
      else V.bsd = R.bside end
      if R.bfan == U then V.t = range(5 * U, 25 * U)
      elseif R["or"] == "nodding" then V.t = range(100 * U, 140 * U) else V.t = range(50 * U, 80 * U) end
      V.bturn = E"@bsd*@t"
    end
  end
  function VW.vcalyx()
    V.bcn = E"int(max(3,min(6,$merosity)))" V.bca = range(0, 360 * U)
    V.twa = K"0.08" V.twb = K"0.004" vtone("flo@c", K"0.1")
    loop("#ka", 1, function() return I("bcn") end, function()
      V.t = sym(8 * U) V.a = E"@bca+360*#ka/@bcn+@t"
      V.t = range(K"0.26", K"0.34")
      V.xa = E"@t*cos(@a)" V.ya = E"@t*sin(@a)"
      V.xb = E"0.4*@xa-0.06*@ya" V.yb = E"0.4*@ya+0.06*@xa"
      V.xc = E"0.75*@xa-0.04*@ya" V.yc = E"0.75*@ya+0.04*@xa"
      vfill("flo@c", K"0.95", 0, function() vtaper(0, 0, R.xb, R.yb, R.xc, R.yc, R.xa, R.ya) end)
    end)
    vtone("flo@c", K"0.08") vfill("flo@c", U, 0, function() circle(0, 0, K"0.05") end)
  end
  local function turad(v)
    V.tur = R.tua
    if v > 0 then
      if R.tub > 0 then V.tur = E("@tur+@tub*pow(%1,@tuc)", { v }) end
      if R.tuw > 0 then V.tur = E("@tur+@tuw*sin(180*pow(min(1,(%1)/0.92),0.85))", { v }) end
    end
  end
  function VW.vtube(u, form)
    V.tufm = form
    if R.tufm == "" then V.tufm = tr("form") end
    V.tua = K"0.1" V.tub = K"0.24" V.tuc = K"1.3" V.tuw = 0 V.tuL = K"0.85" V.tut = K"0.14" V.tusep = U
    V.tuf = range(K"0.06", K"0.12") V.tun = E"int($merosity/2+1.5)" V.tubd = sym(K"0.08")
    V.tmp = "urceolate"
    if R.tufm == R.tmp then V.tua = K"0.09" V.tub = 0 V.tuw = K"0.25" V.tuL = K"0.8" V.tut = K"0.08" V.tuf = K"0.07" end
    V.tmp = "tubular"
    if R.tufm == R.tmp then V.tua = K"0.07" V.tub = K"0.07" V.tuc = K"1.5" V.tuL = K"0.95" V.tut = K"0.08" V.tuf = K"0.05" end
    V.tmp = "funnelform"
    if R.tufm == R.tmp then V.tua = K"0.05" V.tub = K"0.4" V.tuc = K"2.4" V.tuL = K"0.85" V.tut = K"0.1" V.tuf = K"0.1" end
    V.tmp = "salvertube"
    if R.tufm == R.tmp then V.tua = K"0.035" V.tub = K"0.02" V.tuc = U V.tuL = K"0.55" V.tun = 0 end
    V.tmp = "liptube"
    if R.tufm == R.tmp then
      V.tua = K"0.04" V.tub = K"0.06" V.tuc = K"1.6" V.tuL = R.lpL V.tun = 0 V.tubd = R.lpb
      V.tusep = 0
    end
    V.tmp = "aqcup"
    if R.tufm == R.tmp then V.tua = K"0.12" V.tub = K"0.04" V.tuc = U V.tuL = K"0.32" V.tut = K"0.08" V.tusep = 0 end
    V.t = tr("apex") V.tutk = K"0.7"
    V.tmp = "rounded" if R.t == R.tmp then V.tutk = U V.tut = E"0.7*@tut" end
    V.tmp = "emarginate" if R.t == R.tmp then V.tutk = U V.tut = E"0.7*@tut" end
    if u > K"0.45" then vfbm() V.tuwob = K"0.015" else V.tuwob = 0 end
    loop("#kb", 0, 10, function()
      V.v = E"#kb/10" turad(R.v) V.tuy = E"@tuL*@v"
      V.xa = E"@tur+@tubd*@v*@v"
      if R.tuwob > 0 then V.tuwx = E"@v*6" vwave(R.tuwx) V.xa = E"@xa+@tuwob*@wv*@v" end
      put(R["#kb"] + 1, R.xa, R.tuy)
    end)
    V.tuR = E"@tur+@tuf" V.tuk = 11 * U
    if I("tun") > 0 then
      loop("#kc", 1, function() return I("tun") end, function()
        V.v = E"1-2*(#kc-1)/(@tun-1)"
        V.t = sym(K"0.03") V.xa = E"@tuR*@v+@tubd+@t"
        V.t = sym(K"0.02") V.ya = E"@tuL+@tut*(1-0.55*@v*@v)+@t"
        V.tuk = R.tuk + U put(I("tuk"), R.xa, R.ya)
        if R["#kc"] < I("tun") then
          V.xa = E"@tuR*0.85*(@v-1/(@tun-1))+@tubd"
          V.t = sym(K"0.015") V.ya = E"@tuL+0.025+@t"
          V.tuk = R.tuk + U put(I("tuk"), R.xa, R.ya)
        end
      end)
    end
    loop("#kb", 0, 10, function()
      V.v = E"(10-#kb)/10" turad(R.v) V.tuy = E"@tuL*@v" V.tur = E"@tubd*@v*@v-@tur"
      if R.tuwob > 0 then V.tuwx = E"@v*6+40" vwave(R.tuwx) V.tur = E"@tur+@tuwob*@wv*@v" end
      V.tuk = R.tuk + U put(I("tuk"), R.tur, R.tuy)
    end)
    smoothprepT(I("tuk"), R.tutk) keep("tb")
    if R["vf@tone"] == "" then V.tuq = range(K"0.3", K"0.4") else V.tuq = R["vf@tone"] end
    vtone("flo@c", R.tuq) vfill("flo@c", U, 0, function() kept("tb") end)
    if u > K"0.15" then
      scope(function()
        kept("tb") usepath("clip")
        V.tuqa = E"@tuq-0.2" V.tuqb = E"@tuq+0.2" V.tuy = E"@tuL+0.2"
        if u > K"0.45" then vmottle(K"-0.5", 0, K"0.5", "tuy", 10, K"0.12", R.tuqa, R.tuqb, 10)
        else vmottle(K"-0.5", 0, K"0.5", "tuy", 5, K"0.12", R.tuqa, R.tuqb, 0) end
        if chance(K"0.5") then V.sd = U else V.sd = -U end
        V.xa = E"0.25*@tubd" V.ya = E"0.5*@tuL" V.xb = E"1.21*@tubd" V.yb = E"1.1*@tuL"
        V.xc = E"2*@sd" vtone("flo@c", K"0.12")
        vfill("flo@c", K"0.28", 1, function()
          moveto(0, K"-0.1") lineto(R.xa, R.ya) lineto(R.xb, R.yb) lineto(R.xc, R.yb) lineto(R.xc, K"-0.1") closepath()
        end)
        V.twa = K"0.02" V.twb = K"0.012"
        loop("#ka", -2, 2, function()
          V.f = E"#ka/2.5"
          turad(K"0.05") V.xa = E"@f*@tur*0.9+@tubd*0.0025" V.ya = E"0.05*@tuL"
          turad(K"0.4") V.xb = E"@f*@tur*0.9+@tubd*0.16" V.yb = E"0.4*@tuL"
          turad(K"0.75") V.xc = E"@f*@tur*0.9+@tubd*0.5625" V.yc = E"0.75*@tuL"
          V.t = sym(K"0.03") V.xd = E"@f*@tuR*0.95+@tubd+@t" V.yd = E"@tuL+0.06"
          local function path() vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end
          if R["#ka"] % 2 ~= 0 then vtone("flo@c", K"0.08") vfill("flo@c", K"0.3", 1, path)
          else vfill("white", K"0.55", 0, path) end
        end)
        vtone("flo@c", K"0.06") V.t = E("1.5*(%1)", { u })
        vstroke("flo@c", R.t, K"0.3", 1, function() kept("tb") end)
      end)
    end
    vtone("flo@c", K"0.08") vstroke("flo@c", K"0.18", K"0.35", 0, function() kept("tb") end)
    V.t = tr("stamens") V.tmp = "exserted"
    if R.t == R.tmp and I("tun") > 0 then
      loop("#ka", -1, 1, function()
        V.xa = E"#ka*0.02+0.36*@tubd" V.ya = E"0.6*@tuL"
        V.t = sym(K"0.02") V.xb = E"#ka*0.08+1.2*@tubd+@t"
        V.t = range(K"0.18", K"0.32") V.yb = E"@tuL+@t"
        vtone("flo@c", K"0.12") vstroke("flo@c", K"0.25", K"0.85", 0, function() moveto(R.xa, R.ya) lineto(R.xb, R.yb) end)
        vtone("flo@c", K"0.05") vfill("flo@c", U, 0, function() circle(R.xb, R.yb, K"0.018") end)
      end)
    end
    if R.tusep == U then
      V.twa = K"0.07" V.twb = K"0.004" vtone("flo@c", K"0.1")
      loop("#ka", -1, 1, function()
        V.t = sym(K"0.03")
        V.xa = E"#ka*0.04" V.xb = E"#ka*0.07"
        V.xd = E"#ka*(@tua+0.07)+@t" V.xc = E"0.9*@xd"
        vfill("flo@c", K"0.95", 0, function() vtaper(R.xa, K"-0.03", R.xb, K"0.06", R.xc, K"0.14", R.xd, K"0.22") end)
      end)
      vtone("flo@c", K"0.08") vfill("flo@c", U, 0, function() circle(0, K"-0.02", K"0.05") end)
    end
  end
  function VW.vsalver(d)
    V.sva = d VW.vtube(R.sva, "salvertube")
    V.t = range(K"0.3", K"0.45")
    scope(function()
      shift(0, K"0.55") yscale(R.t) V.t = sym(30 * U) rotate(R.t)
      V.t = E"@sva*28.45276" sflower(R.t)
    end)
  end
  local function xscale(s) out("\\pgftransformxscale{" .. str(s) .. "}") end
  VW.xscale = xscale
  -- \flo@vcup{u}{k}: a calyx in profile, about 0.27 long times k
  function VW.vcup(u, k)
    V.cuy = k
    V.ya = E"0.08*@cuy" V.yb = E"0.17*@cuy" V.yc = E"0.2*@cuy"
    put(1, K"0.03", K"-0.03") put(2, K"0.068", R.ya) put(3, K"0.085", R.yb)
    V.t = sym(K"0.02") V.yd = E"0.25*@cuy+@t" put(4, K"0.11", R.yd)
    put(5, K"0.055", R.yc)
    V.t = sym(K"0.02") V.yd = E"0.27*@cuy+@t" put(6, K"0.013", R.yd)
    put(7, K"-0.03", R.yc)
    V.t = sym(K"0.02") V.yd = E"0.26*@cuy+@t" put(8, K"-0.08", R.yd)
    V.yd = E"0.15*@cuy" put(9, K"-0.085", R.yd) V.yd = E"0.06*@cuy" put(10, K"-0.064", R.yd)
    put(11, K"-0.03", K"-0.03")
    smoothprepT(11, K"0.7") keep("cup")
    vtone("flo@c", K"0.12") vfill("flo@c", K"0.95", 0, function() kept("cup") end)
    if u > K"0.15" then
      V.twa = K"0.03" V.twb = K"0.004" V.yb = E"0.08*@cuy" V.yc = E"0.14*@cuy" V.yd = E"0.22*@cuy"
      vfill("white", K"0.4", 0, function() vtaper(K"0.034", K"0.01", K"0.055", R.yb, K"0.068", R.yc, K"0.085", R.yd) end)
      vtone("flo@c", K"0.06") vstroke("flo@c", K"0.18", K"0.4", 0, function() kept("cup") end)
    end
    vtone("flo@c", K"0.08") vfill("flo@c", U, 0, function() circle(0, K"-0.02", K"0.045") end)
  end
  -- \flo@vpea{u}: a pea flower in profile, the standard on the +x side
  function VW.vpea(u)
    V.pvu = u
    if R["vf@tone"] == "" then V.pvq = range(K"0.3", K"0.4") else V.pvq = R["vf@tone"] end
    V["vp@ns"] = "" V["vp@heart"] = 0
    V.pva = range(8 * U, 28 * U) V.pvl = range(K"0.55", K"0.7") V.pvw = range(K"0.75", K"0.95")
    scope(function()
      shift(K"0.04", K"0.2") V.t = E"-90-@pva" rotate(R.t)
      scale(R.pvl) xscale(R.pvw)
      V["vp@pointed"] = 0 V["vp@W"] = K"0.5" V["vp@bend"] = "" V["vp@heart"] = U
      V["vp@notchp"] = K"0.8" V["vp@notchk"] = K"1.4" V["vp@tone"] = R.pvq
      V["vp@u"] = E"@pvu*@pvl" vpetal()
      V.t = tr("guides") V.tmp = "none"
      if R.t ~= R.tmp and R["vp@u"] > K"0.12" then
        vtone("flo@c", K"0.06") V.twb = K"0.004"
        loop("#ka", -2, 2, function()
          V.t = sym(K"0.03") V.f = E"#ka*0.1+@t" V.len = range(K"0.3", K"0.45")
          V.len = E"@len*(1-1.5*@f*@f)" V.twa = K"0.04"
          V.xa = E"0.2*@f" V.xb = E"0.6*@f" V.xc = E"0.9*@f" V.xd = E"1.1*@f"
          V.yb = E"0.35*@len+0.05" V.yc = E"0.7*@len+0.05" V.yd = E"@len+0.05"
          vfill("flo@c", K"0.45", 1, function() vtaper(R.xa, K"0.05", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
        end)
      end
    end)
    V.pvk = range(K"0.58", K"0.68") V.t = range(8 * U, 16 * U)
    scope(function()
      shift(K"-0.03", K"0.2") rotate(R.t) scale(R.pvk)
      V["vp@pointed"] = U V["vp@W"] = K"0.12" V["vp@bend"] = range(K"0.22", K"0.32")
      V["vp@tone"] = E"@pvq+0.12" V["vp@u"] = E"@pvu*@pvk" vpetal()
    end)
    V.pvn = range(K"0.44", K"0.52") V.t = range(0, 8 * U)
    scope(function()
      shift(K"0.02", K"0.21") rotate(R.t) scale(R.pvn)
      V["vp@pointed"] = 0 V["vp@W"] = K"0.26" V["vp@bend"] = range(0, K"0.08") V["vp@notchp"] = 0 V["vp@ns"] = 3 * U
      V["vp@tone"] = E"@pvq-0.03" V["vp@u"] = E"@pvu*@pvn" vpetal()
    end)
    VW.vcup(R.pvu, K"0.9")
  end
  -- \flo@vlips{u}: a two-lipped flower in profile, the hood on the +x side
  function VW.vlips(u)
    V.lpu = u
    if R["vf@tone"] == "" then V.lpq = range(K"0.3", K"0.4") else V.lpq = R["vf@tone"] end
    V.lpL = range(K"0.55", K"0.68") V.lpb = sym(K"0.06")
    V["vp@ns"] = "" V["vp@heart"] = 0 V["vp@pointed"] = 0
    V.lpa = range(35 * U, 55 * U) V.lpl = range(K"0.3", K"0.4")
    scope(function()
      V.xa = E"@lpb-0.05" V.ya = E"@lpL-0.03" shift(R.xa, R.ya)
      rotate(R.lpa) scale(R.lpl)
      V["vp@W"] = K"0.42" V["vp@bend"] = range(K"-0.25", K"-0.1") V["vp@notchp"] = K"0.6" V["vp@notchk"] = K"1.4"
      V["vp@ns"] = 5 * U
      V["vp@tone"] = E"@lpq+0.05" V["vp@u"] = E"@lpu*@lpl" vpetal()
      V.t = tr("guides")
      if R["vp@u"] > K"0.1" then
        V.tmp = "dots"
        if R.t == R.tmp then
          local spk = {}
          loop("#ka", 1, 7, function()
            V.xa = sym(K"0.22") V.ya = range(K"0.12", K"0.55") V.r = range(K"0.025", K"0.045")
            spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.xa, R.ya) .. "}{" .. str(R.r) .. "pt}"
          end)
          vtone("flo@c", K"0.06") vfill("flo@c", K"0.7", 1, function() out(concat(spk)) end)
        end
        V.tmp = "lines"
        if R.t == R.tmp then
          vtone("flo@c", K"0.06") V.twa = K"0.035" V.twb = K"0.004"
          loop("#ka", -1, 1, function()
            V.t = sym(K"0.03") V.f = E"#ka*0.12+@t" V.len = range(K"0.35", K"0.5")
            V.xb = E"0.5*@f" V.xc = E"0.8*@f" V.xd = E"@f"
            V.yb = E"0.35*@len+0.05" V.yc = E"0.7*@len+0.05" V.yd = E"@len+0.05"
            vfill("flo@c", K"0.5", 1, function() vtaper(0, K"0.05", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
          end)
        end
      end
    end)
    V.lpa = range(-80 * U, -68 * U) V.lph = range(K"0.36", K"0.44")
    scope(function()
      V.xa = E"@lpb+0.05" V.ya = E"@lpL-0.04" shift(R.xa, R.ya)
      rotate(R.lpa) scale(R.lph)
      V["vp@W"] = K"0.26" V["vp@bend"] = range(K"-1.1", K"-0.85") V["vp@notchp"] = K"0.4" V["vp@notchk"] = U
      V["vp@ns"] = 3 * U
      V["vp@tone"] = R.lpq V["vp@u"] = E"@lpu*@lph" vpetal()
    end)
    V.t = tr("stamens") V.tmp = "exserted"
    if R.t == R.tmp then
      loop("#ka", 0, 1, function()
        V.xa = E"@lpb+0.02" V.ya = E"@lpL"
        V.t = range(K"0.1", K"0.2") V.xb = E"@xa+@t+0.04*#ka"
        V.t = range(K"0.3", K"0.42") V.yb = E"@ya+@t-0.05*#ka"
        vtone("flo@c", K"0.12") vstroke("flo@c", K"0.25", K"0.85", 0, function() moveto(R.xa, R.ya) lineto(R.xb, R.yb) end)
        vtone("flo@c", K"0.05") vfill("flo@c", U, 0, function() circle(R.xb, R.yb, K"0.018") end)
      end)
    end
    VW.vtube(R.lpu, "liptube") VW.vcup(R.lpu, K"1.1")
  end
  -- \flo@ivpart{dir}{len}{W}{bend}{tone}{heart}{ns}{notchp}{u}: a part of an iris, an
  -- orchid or a columbine: a haft for \flo@ivc of it, then flora's petal (pointed when
  -- \flo@ivpt is 1)
  local function ivpart(a, l, w, b, t, h, n, p, u)
    V.iva = a V.ivl = l V.ivw = w V.ivb = b V.ivt = t V.ivh = h V.ivn = n V.ivp = p V.ivu = u
    scope(function()
      V.t = E"@iva-90" rotate(R.t) scale(R.ivl)
      if R.ivc > 0 then
        V.twa = E"0.3*@ivw" V.twb = E"0.34*@ivw*(1-@ivc)"
        vtone("flo@c", R.ivt) V.t = E"@ivc*0.5" V.ya = E"@ivc+0.01"
        vfill("flo@c", U, 0, function() vtaper(0, 0, 0, R.t, 0, R.t, 0, R.ya) end)
        V.twa = K"0.02" V.twb = K"0.004" V.ya = E"@ivc*0.95"
        vfill("white", K"0.6", 0, function() vtaper(0, K"0.02", 0, R.t, 0, R.t, 0, R.ya) end)
        shift(0, R.ivc) V.t = E"1-@ivc" scale(R.t)
      end
      V["vp@pointed"] = R.ivpt V["vp@W"] = R.ivw V["vp@bend"] = R.ivb V["vp@ns"] = R.ivn
      V["vp@heart"] = R.ivh V["vp@tone"] = R.ivt V["vp@notchp"] = R.ivp V["vp@notchk"] = K"1.6"
      V["vp@u"] = E"@ivu*@ivl*(1-@ivc)" vpetal()
    end)
  end
  -- dark dots (or the beard's copper hairs) into a list of circles: n of them at x sym(sx),
  -- y range(y0, y1) or y0 + dy k, radius range(r0, r1)
  local function circles(spk, x, y, r)
    spk[#spk + 1] = "\\pgfpathcircle{" .. P(x, y) .. "}{" .. str(r) .. "pt}"
  end
  -- \flo@viris{d}: an iris three-quarters from the front, diameter 1; d its diameter in pt
  function VW.viris(d)
    V.ivs = E("(%1)/28.45276", { d })
    if R["vf@tone"] == "" then V.ivq = range(K"0.28", K"0.38") else V.ivq = R["vf@tone"] end
    V.ivcf = E"0.7*min(0.45,$claw)" V.ivc = E"0.55*@ivcf"
    V.t = sym(6 * U) V.a = E"90+@t" V.len = range(K"0.46", K"0.52") V.b = sym(K"0.06")
    V.tp = E"@ivq+0.04" ivpart(R.a, R.len, K"0.27", R.b, R.tp, 0, 5 * U, K"0.5", R.ivs)
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(20 * U, 45 * U) V.a = E"-90+@sg*@t"
      V.len = range(K"0.52", K"0.6") V.b = range(K"0.15", K"0.3") V.b = E"@sg*@b"
      V.t = sym(K"0.03") V.tp = E"@ivq+@t"
      V.ivc = R.ivcf ivpart(R.a, R.len, K"0.34", R.b, R.tp, 0, "", K"0.3", R.ivs)
      V.ivc = 0 V.len = range(K"0.26", K"0.32") V.tp = E"@ivq+0.18"
      ivpart(R.a, R.len, K"0.24", 0, R.tp, 0, 3 * U, K"0.9", R.ivs)
    end)
    V.ivc = E"0.55*@ivcf"
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(8 * U, 28 * U) V.a = E"90-@sg*@t"
      V.len = range(K"0.48", K"0.56") V.b = range(K"0.15", K"0.3") V.b = E"-@sg*@b"
      V.t = sym(K"0.03") V.tp = E"@ivq+0.02+@t"
      ivpart(R.a, R.len, K"0.27", R.b, R.tp, 0, 5 * U, K"0.5", R.ivs)
    end)
    V.t = sym(6 * U) V.a = E"-90+@t" V.len = range(K"0.56", K"0.64") V.b = sym(K"0.08")
    V.ivc = R.ivcf ivpart(R.a, R.len, K"0.36", R.b, R.ivq, 0, "", K"0.3", R.ivs) V.ivc = 0
    V.t = E"@ivs*@len"
    if R.t > K"0.15" then
      scope(function()
        V.t = E"@a-90" rotate(R.t) scale(R.len)
        V.g = tr("guides")
        V.tmp = "lines"
        if R.g == R.tmp then
          vtone("flo@c", K"0.06") V.twb = K"0.004" V.twa = K"0.035"
          loop("#kb", -2, 2, function()
            V.t = sym(K"0.03") V.f = E"#kb*0.07+@t" V.ya = range(K"0.25", K"0.38")
            V.xb = E"0.6*@f" V.xc = E"1.1*@f" V.xd = E"1.4*@f"
            V.yb = E"0.35*@ya+0.4" V.yc = E"0.7*@ya+0.4" V.yd = E"@ya+0.4"
            vfill("flo@c", K"0.45", 1, function() vtaper(R.f, K"0.4", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
          end)
        end
        V.tmp = "blotch"
        if R.g == R.tmp then
          vblob(0, K"0.62", K"0.16", K"0.12", K"0.25", 9) vfill("white", K"0.7", 0, smoothpath)
          vblob(0, K"0.62", K"0.07", K"0.05", K"0.3", 7) vtone("flo@c", K"0.06") vfill("flo@c", K"0.5", 1, smoothpath)
        end
        V.tmp = "dots"
        if R.g == R.tmp then
          local spk = {}
          loop("#kb", 1, 9, function()
            V.xa = sym(K"0.16") V.ya = range(K"0.45", K"0.8") V.r = range(K"0.012", K"0.024")
            circles(spk, R.xa, R.ya, R.r)
          end)
          vtone("flo@c", K"0.06") vfill("flo@c", K"0.7", 1, function() out(concat(spk)) end)
        end
        local spk = {}
        loop("#kb", 1, 14, function()
          V.xa = sym(K"0.035") V.ya = E"0.38+0.024*#kb" V.r = range(K"0.012", K"0.022")
          circles(spk, R.xa, R.ya, R.r)
        end)
        vaccent("flo@c", K"0.1") vfill("flo@c", K"0.9", 0, function() out(concat(spk)) end)
      end)
    end
    V.len = range(K"0.26", K"0.32") V.tp = E"@ivq+0.18"
    ivpart(R.a, R.len, K"0.24", 0, R.tp, 0, 3 * U, K"0.9", R.ivs)
  end
  T.viris = VW.viris
  -- \flo@vorchid{u}: an orchid face on, diameter 1, upright
  function VW.vorchid(u)
    V.ocu = u V.ivc = 0
    if R["vf@tone"] == "" then V.ocq = range(K"0.28", K"0.38") else V.ocq = R["vf@tone"] end
    V.ivpt = U
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(45 * U, 60 * U) V.a = E"-90+@sg*@t" V.len = range(K"0.42", K"0.5")
      V.b = sym(K"0.08") V.t = sym(K"0.03") V.tp = E"@ocq+0.02+@t"
      ivpart(R.a, R.len, K"0.12", R.b, R.tp, 0, 3 * U, 0, R.ocu)
    end)
    V.t = sym(6 * U) V.a = E"90+@t" V.len = range(K"0.4", K"0.48") V.b = sym(K"0.08")
    V.tp = E"@ocq+0.02" ivpart(R.a, R.len, K"0.13", R.b, R.tp, 0, 3 * U, 0, R.ocu)
    V.ivpt = 0
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(45 * U, 65 * U) V.a = E"90-@sg*@t" V.len = range(K"0.36", K"0.44")
      V.b = range(0, K"0.12") V.b = E"@sg*@b" V.t = sym(K"0.03") V.tp = E"@ocq+@t"
      ivpart(R.a, R.len, K"0.2", R.b, R.tp, 0, 5 * U, K"0.3", R.ocu)
    end)
    V.tp = E"@ocq-0.06"
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(40 * U, 55 * U) V.a = E"-90+@sg*@t" V.len = range(K"0.18", K"0.24")
      ivpart(R.a, R.len, K"0.35", 0, R.tp, 0, 3 * U, 0, R.ocu)
    end)
    V.t = sym(6 * U) V.a = E"-90+@t" V.len = range(K"0.44", K"0.54") V.b = sym(K"0.06")
    ivpart(R.a, R.len, K"0.38", R.b, R.tp, U, 5 * U, K"0.85", R.ocu)
    V.t = E"@ocu*@len"
    if R.t > K"0.15" then
      scope(function()
        V.t = E"@a-90" rotate(R.t) scale(R.len)
        V.g = tr("guides")
        V.tmp = "lines"
        if R.g == R.tmp then
          vtone("flo@c", K"0.06") V.twb = K"0.004" V.twa = K"0.035"
          loop("#kb", -2, 2, function()
            V.t = sym(K"0.03") V.f = E"#kb*0.09+@t" V.ya = range(K"0.35", K"0.5")
            V.xb = E"0.7*@f" V.xc = E"1.2*@f" V.xd = E"1.5*@f"
            V.yb = E"0.35*@ya+0.12" V.yc = E"0.7*@ya+0.12" V.yd = E"@ya+0.12"
            vfill("flo@c", K"0.45", 1, function() vtaper(R.f, K"0.12", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
          end)
        end
        V.tmp = "blotch"
        if R.g == R.tmp then
          vblob(0, K"0.4", K"0.2", K"0.15", K"0.3", 9) vfill("white", K"0.65", 0, smoothpath)
          local spk = {}
          loop("#kb", 1, 8, function()
            V.xa = sym(K"0.14") V.ya = range(K"0.3", K"0.5") V.r = range(K"0.015", K"0.03")
            circles(spk, R.xa, R.ya, R.r)
          end)
          vtone("flo@c", K"0.06") vfill("flo@c", K"0.7", 1, function() out(concat(spk)) end)
        end
        V.tmp = "dots"
        if R.g == R.tmp then
          local spk = {}
          loop("#kb", 1, 11, function()
            V.xa = sym(K"0.24") V.ya = range(K"0.2", K"0.75") V.r = range(K"0.014", K"0.028")
            circles(spk, R.xa, R.ya, R.r)
          end)
          vtone("flo@c", K"0.06") vfill("flo@c", K"0.7", 1, function() out(concat(spk)) end)
        end
      end)
    end
    vblob(0, K"0.05", K"0.05", K"0.085", K"0.15", 8) vfill("white", K"0.85", 0, smoothpath)
    vtone("flo@c", K"0.1") vstroke("flo@c", K"0.2", K"0.5", 0, smoothpath)
    vtone("flo@c", K"0.06") vfill("flo@c", U, 0, function() circle(0, K"0.11", K"0.022") end)
  end
  -- \flo@vcorona{u}: a lily's cup or trumpet, in \flo@vlily's frame after its star
  function VW.vcorona(u)
    V.cqu = u V.cqf = tr("corona") V.tmp = "trumpet"
    if R.cqf == R.tmp then V.cqh = range(K"0.4", K"0.6") V.cqb = K"0.1" V.cqR = range(K"0.24", K"0.32")
    else V.cqh = range(K"0.12", K"0.2") V.cqb = K"0.14" V.cqR = range(K"0.2", K"0.28") end
    if R["vf@tone"] == "" then V.cqq = range(K"0.24", K"0.32") else V.cqq = E"@vf@tone-0.08" end
    V.cqn = int(9, 14) V.cqp = range(0, 360 * U)
    loop("#kb", 0, 4, function()
      V.a = E"180+45*#kb"
      V.xa = E"@cqb*cos(@a)" V.ya = E"@cqb*@tilt*sin(@a)"
      put(R["#kb"] + 1, R.xa, R.ya)
    end)
    loop("#kb", 1, 3, function()
      V.v = E"#kb/4" V.xa = E"@cqb+(@cqR-@cqb)*pow(@v,1.6)" V.ya = E"@cqh*@v"
      put(R["#kb"] + 5, R.xa, R.ya)
    end)
    loop("#kb", 0, 6, function()
      V.a = E"-30*#kb" V.r = E"1+0.09*sin(@cqn*@a+@cqp)"
      V.xa = E"@cqR*@r*cos(@a)" V.ya = E"@cqh+@cqR*@r*@tilt*sin(@a)"
      put(R["#kb"] + 9, R.xa, R.ya)
    end)
    loop("#kb", 1, 3, function()
      V.v = E"1-#kb/4" V.xa = E"-@cqb-(@cqR-@cqb)*pow(@v,1.6)" V.ya = E"@cqh*@v"
      put(R["#kb"] + 15, R.xa, R.ya)
    end)
    smoothprepT(18, K"0.9") keep("cqo")
    vtone("flo@c", R.cqq) vfill("flo@c", U, 0, function() kept("cqo") end)
    if u > K"0.12" then
      scope(function()
        kept("cqo") usepath("clip")
        V.twa = K"0.025" V.twb = K"0.008"
        loop("#ka", -2, 2, function()
          V.f = E"#ka/2.6" V.t = sym(K"0.02")
          V.xa = E"@f*@cqb" V.xd = E"@f*@cqR+@t" V.ya = E"-0.02" V.yd = E"@cqh"
          V.xb = E"0.7*@xa+0.3*@xd" V.yb = E"0.4*@cqh" V.xc = E"0.3*@xa+0.7*@xd" V.yc = E"0.75*@cqh"
          local function path() vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end
          if R["#ka"] % 2 ~= 0 then vtone("flo@c", K"0.08") vfill("flo@c", K"0.25", 1, path)
          else vfill("white", K"0.5", 0, path) end
        end)
      end)
    end
    loop("#kb", 1, 16, function()
      V.a = E"22.5*#kb" V.r = E"1+0.09*sin(@cqn*@a+@cqp)"
      V.xa = E"@cqR*@r*cos(@a)" V.ya = E"@cqh+@cqR*@r*@tilt*sin(@a)"
      put(R["#kb"], R.xa, R.ya)
    end)
    smoothprepT(16, U) keep("cqr")
    V.t = E"@cqq+0.12" vtone("flo@c", R.t) vfill("flo@c", U, 0, function() kept("cqr") end)
    V.t = E"0.55*@cqR" V.ya = E"@cqh-0.15*@cqR*@tilt" V.r = E"@t*@tilt"
    vblob(0, R.ya, R.t, R.r, K"0.15", 8) V.t = E"@cqq-0.12" vtone("flo@c", R.t) vfill("flo@c", K"0.6", 1, smoothpath)
    vtone("flo@c", K"0.08") vstroke("flo@c", K"0.2", K"0.6", 0, function() kept("cqr") end)
    vstroke("flo@c", K"0.2", K"0.35", 0, function() kept("cqo") end)
  end
  T.vcorona = VW.vcorona
  -- \flo@vaquilegia{u}: a columbine in profile
  function VW.vaquilegia(u)
    V.aqu = u
    if R["vf@tone"] == "" then V.aqq = range(K"0.3", K"0.4") else V.aqq = R["vf@tone"] end
    V.ivc = 0 V.ivpt = U
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(105 * U, 135 * U) V.a = E"90-@sg*@t" V.len = range(K"0.32", K"0.4")
      V.b = sym(K"0.08") V.tp = E"@aqq-0.04"
      scope(function() shift(0, K"0.12") ivpart(R.a, R.len, K"0.14", R.b, R.tp, 0, 3 * U, 0, R.aqu) end)
    end)
    V.aqh = range(0, K"0.16") V.twb = K"0.024"
    loop("#ka", -1, 1, function()
      V.len = range(K"0.38", K"0.58") V.t = sym(K"0.03")
      V.xa = E"#ka*0.08" V.xb = E"#ka*0.16+@t" V.yb = E"0.16-0.4*@len"
      V.xc = E"#ka*0.14+@t" V.yc = E"0.16-0.8*@len"
      V.xd = E"#ka*(0.16-@aqh)+@t" V.yd = E"0.16-@len"
      if R["#ka"] == 0 then V.tp = E"@aqq-0.06" else V.tp = R.aqq end
      V.twa = K"0.12" vtone("flo@c", R.tp)
      vfill("flo@c", U, 0, function() vtaper(R.xa, K"0.16", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
      if u > K"0.15" then
        V.twa = K"0.018" V.xa = E"@xa+0.025" V.xb = E"@xb+0.018" V.xc = E"@xc+0.01"
        vfill("white", K"0.35", 0, function() vtaper(R.xa, K"0.14", R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
      end
      V.t = E"@tp-0.12" vtone("flo@c", R.t) vfill("flo@c", U, 0, function() circle(R.xd, R.yd, K"0.03") end)
    end)
    loop("#ka", 0, 1, function()
      if R["#ka"] == 0 then V.sg = -U else V.sg = U end
      V.t = range(45 * U, 70 * U) V.a = E"90-@sg*@t" V.len = range(K"0.3", K"0.38")
      V.b = sym(K"0.08") V.t = sym(K"0.03") V.tp = E"@aqq+@t"
      scope(function() shift(0, K"0.12") ivpart(R.a, R.len, K"0.14", R.b, R.tp, 0, 3 * U, 0, R.aqu) end)
    end)
    V.ivpt = 0
    scope(function() shift(0, K"0.08") V["vf@tone"] = E"@aqq+0.1" VW.vtube(R.aqu, "aqcup") end)
  end
end
-- \flo@bloom{diameter cm}{stage}: a bud below 0.3, the fruit above 1.15, past its best
-- above 1; seen as \flo@bview says
local function bloom(d, st)
  V.bd = d V.bst = st stone() VW.bview()
  if R.bst < K"0.3" then
    V.oarg = E"0.55*@bd"
    scope(function()
      if R.vw ~= "face" then rotate(R.bturn) end
      scale(R.oarg) vbud(R.oarg)
    end)
  elseif R.bst > K"1.15" then
    V.fu = E"0.35*@bd"
    scope(function() scale(R.fu) fruit() end)
  else
    V.t = sym(30 * U) V.bd = E"@bd*min(1,0.55+(@bst-0.3)*0.9)"
    if R.bst > U then V.bd = E"@bd*(1-0.8*(@bst-1))" end
    scope(function()
      if R.vw ~= "face" then rotate(R.bturn) end
      if R.bst > U then V.lift = E"1-(1-@lift)*(1-3*(@bst-1))" end
      if R.vw == "tube" then
        V.oarg = E"0.8*@bd" scale(R.oarg) VW.vtube(R.oarg, "")
      elseif R.vw == "salver" then
        scale(R.bd) VW.vsalver(R.bd)
      elseif R.vw == "pea" then
        V.oarg = E"0.8*@bd" scale(R.oarg)
        if R.bturn < 0 then VW.xscale(-U) end
        VW.vpea(R.oarg)
      elseif R.vw == "lips" then
        V.oarg = R.bd scale(R.oarg)
        if R.bturn < 0 then VW.xscale(-U) end
        VW.vlips(R.oarg)
      elseif R.vw == "orchid" then
        out("\\flo@upright") V.oarg = E"0.4*@t" rotate(R.oarg)
        V.oarg = range(K"0.75", K"0.95") VW.xscale(R.oarg)
        scale(R.bd) VW.vorchid(R.bd)
      elseif R.vw == "spur" then
        V.oarg = E"0.75*@bd" scale(R.oarg) VW.vaquilegia(R.oarg)
      else
        V.ys = U
        if R.vw == "tilt" then V.ys = range(K"0.5", K"0.7") end
        if R.vw == "back" then V.ys = range(K"0.55", K"0.75") V.lift = E"1-(1-@lift)*0.85" end
        if R.ys < U then V.oarg = E"0.12*@bd" shift(0, R.oarg) yscale(R.ys) end
        V.tmp = "iris"
        if R.fm == R.tmp then out("\\flo@upright") V.t = E"0.6*@t" end
        rotate(R.t)
        if R.fm == R.tmp then V.oarg = range(K"0.72", U) VW.xscale(R.oarg) end
        scale(R.bd)
        V.t = E"@bd*28.45276" sflower(R.t)
        if R.vw == "back" then VW.vcalyx() end
      end
    end)
  end
end
local function fdiam(k) V.fd = E("min(2.8,0.7+0.032*$size)*(%1)", { k }) end
-- a stalk from the origin to (\flo@xx,\flo@yy) (\flo@blossoms, \flo@budding)
local function stalkto()
  vtone("flo@c", K"0.1")
  vstroke("flo@c", K"0.35", U, 0, function() moveto(0, 0) curveto(0, R.ya, R.xb, R.yb, R.xx, R.yy) end)
end
-- \flo@blossoms{diameter}{stage}: two to five flowers on curved stalks, a bud at the fork
local function blossoms(d, st)
  V.bfd = d V.bst = st V.oo = tr("openorder")
  V.bn = int(2, 4)
  if tr("count") > 9 * U then V.bn = R.bn + U end
  loop("#Gc", 1, function() return I("bn") end, function()
    V.f = E"#Gc-(@bn+1)/2"
    V.t = sym(10 * U) V.a = E"@f*38+@t"
    V.t = range(K"0.55", K"0.95") V.dd = E"@bfd*@t"
    if R["#Gc"] > 1 then V.t = range(K"0.85", K"1.1") V.dd = E"@dd*@t" end
    V.xx = E"@dd*sin(@a)" V.yy = E"@dd*cos(@a)"
    V.ya = E"0.4*@dd" V.xb = E"0.6*@xx" V.yb = E"0.7*@yy"
    stalkto()
    if R.oo == "center" then V.t = E"@bst-0.3*abs(@f)/max(1,(@bn-1)/2)"
    else V.t = E"@bst-0.3*(1-abs(@f)/max(1,(@bn-1)/2))" end
    V.s = range(K"0.8", K"1.05") V.s = E"@bfd*@s"
    scope(function()
      shift(R.xx, R.yy)
      if R.a < 0 then V.bside = U else V.bside = -U end
      bloom(R.s, R.t)
    end)
  end)
  if chance(K"0.6") then
    V.t = sym(50 * U) V.s = E"0.45*@bfd"
    V.oarg = R.s
    scope(function() rotate(R.t) scale(R.oarg) stone() vbud(R.oarg) end)
  end
end
-- \flo@budding{diameter}: two to four buds on stalks
local function budding(d)
  V.bfd = d V.bn = int(2, 4) stone()
  loop("#Gc", 1, function() return I("bn") end, function()
    V.t = sym(10 * U) V.a = E"(#Gc-(@bn+1)/2)*34+@t"
    V.t = range(K"0.5", K"0.85") V.dd = E"@bfd*@t"
    V.xx = E"@dd*sin(@a)" V.yy = E"@dd*cos(@a)"
    V.ya = E"0.4*@dd" V.xb = E"0.6*@xx" V.yb = E"0.7*@yy"
    stalkto()
    V.s = range(K"0.45", K"0.6") V.s = E"@bfd*@s" V.t = E"-0.6*@a"
    V.oarg = R.s
    scope(function() shift(R.xx, R.yy) rotate(R.t) scale(R.oarg) vbud(R.oarg) end)
  end)
end
-- \flo@umbelunit{reach}{stage}: rays fanning upward, umbellets of starry florets, bracts
local function umbelunit(reach, st)
  V.R = reach V.bst = st stone()
  V.nr = E"int(max(8,min(13,$count+3)))"
  V.ns = E"int(max(5,min(8,$rays/2)))"
  if R["vf@tone"] == "" then V.tlo = K"0.25" V.thi = K"0.42"
  else V.tlo = E"min(0.5,@vf@tone-0.05)" V.thi = E"min(0.62,@vf@tone+0.05)" end
  loop("#Gc", 1, function() return I("nr") end, function()
    V.t = sym(4 * U) V.a = E"90+(#Gc-(@nr+1)/2)*(110/@nr)+@t"
    V.t = range(K"0.78", U) V.L = E"@R*@t*(1-0.15*abs(@a-90)/55)"
    V.ex = E"@L*cos(@a)" V.ey = E"@L*sin(@a)"
    V.xa = E"0.15*@ex" V.ya = E"0.5*@ey" V.xb = E"0.6*@ex" V.yb = E"0.95*@ey"
    vtone("flo@c", K"0.12")
    vstroke("flo@c", K"0.25", K"0.9", 0, function() moveto(0, 0) curveto(R.xa, R.ya, R.xb, R.yb, R.ex, R.ey) end)
    loop("#Gd", 1, function() return I("ns") end, function()
      V.t = sym(5 * U) V.b = E"@a+(#Gd-(@ns+1)/2)*16+@t"
      V.t = range(K"0.12", K"0.2") V.l = E"@R*@t"
      V.fx = E"@ex+@l*cos(@b)" V.fy = E"@ey+@l*sin(@b)"
      vtone("flo@c", K"0.14")
      vstroke("flo@c", K"0.18", K"0.85", 0, function() moveto(R.ex, R.ey) lineto(R.fx, R.fy) end)
      V.t = range(K"0.035", K"0.05") V.r = E"@R*@t"
      V.t = range(R.tlo, R.thi)
      scope(function()
        shift(R.fx, R.fy)
        if R.bst > K"1.15" then
          V.t = E"@b-90" rotate(R.t) scale(R.r)
          vtone("flo@c", K"0.16")
          vfill("flo@c", U, 0, function()
            out("\\pgfpathellipse{" .. P(K"-0.35", K"0.9") .. "}{" .. P(K"0.32", 0) .. "}{" .. P(0, K"0.9") .. "}")
            out("\\pgfpathellipse{" .. P(K"0.35", K"0.9") .. "}{" .. P(K"0.32", 0) .. "}{" .. P(0, K"0.9") .. "}")
          end)
        elseif R.bst < K"0.3" then
          vtone("flo@c", K"0.2") V.t = E"0.45*@r" vfill("flo@c", U, 0, function() circle(0, 0, R.t) end)
        else
          V["vf@tone"] = R.t V["vf@star"] = U V.oarg = R.r scale(R.oarg) vfloret(R.oarg, 5 * U)
        end
      end)
    end)
  end)
  loop("#Gc", -1, 1, function()
    V.t = sym(10 * U) V.a = E"#Gc*40+@t+180" V.s = range(K"0.15", K"0.22") V.s = E"@R*@s"
    scope(function()
      rotate(R.a) scale(R.s)
      V["vl@W"] = K"0.06" V["vl@tone"] = "" V["vl@u"] = R.s vleaflet()
    end)
  end)
end
-- \flo@racemeunit{axis cm}{pedicel cm}{bend degrees}: flowers along a bending axis
local function racemeunit(len, ped, bend)
  V.bst = R.ust V.L = len V.ped = ped
  if chance(K"0.5") then V.side = U else V.side = -U end
  V.t = range(K"0.75", K"1.25") V.turn = E("(%1)*@t", { bend })
  V.t = sym(8 * U) V.h = E"90+@t"
  put(1, 0, 0) V.xx = 0 V.yy = 0 V.ds = E"@L/24"
  loop("#Gc", 1, 24, function()
    V.v = E"(#Gc-0.5)/24"
    V.a = E"@h+@side*@turn*@v*@v*sqrt(sqrt(@v))"
    V.xx = E"@xx+@ds*cos(@a)" V.yy = E"@yy+@ds*sin(@a)"
    put(R["#Gc"] + 1, R.xx, R.yy)
  end)
  normals(25)
  for g = 1, 25 do setv(T.AX, g, X[g]) setv(T.AY, g, Y[g]) setv(T.AN, g, NX[g]) setv(T.AM, g, NY[g]) end
  V["#Gc"] = 26
  vstem(25, K"0.03", K"0.006", K"0.1")
  stone()
  V.rfd = E"min(1.0,0.5+0.03*$size)*0.8"
  if bend > 150 * U then V.rfd = E"min(0.32,@rfd)" end
  V.t = int(8, 12) V.rn = E"int(min($count,@t))"
  loop("#Gc", 1, function() return I("rn") end, function()
    V.v = E"#Gc/@rn" V.f = E"0.1+0.88*sqrt(@v)*sqrt(sqrt(@v))"
    V.ri = E"int(max(2,min(25,floor(@f*24+1.5))))"
    if R["#Gc"] % 2 == 1 then V.sg = -U else V.sg = U end
    local ri = I("ri")
    V.px = T.AX[ri] V.py = T.AY[ri] V.pnx = T.AN[ri] V.pny = T.AM[ri]
    V.t = range(K"0.8", K"1.2") V.stalk = E"(@ped*(1-@f)+0.03*@f)*@t"
    V.qx = E"@px+(@pnx*@sg*0.75+@pny*0.65)*@stalk"
    V.qy = E"@py+(@pny*@sg*0.75-@pnx*0.65)*@stalk"
    if R.stalk > K"0.03" then
      vtone("flo@c", K"0.12")
      vstroke("flo@c", K"0.25", K"0.9", 0, function() moveto(R.px, R.py) lineto(R.qx, R.qy) end)
    end
    V.t = E"@bst+0.35-1.1*@f"
    V.s = range(K"0.85", K"1.15") V.s = E"@rfd*(1-0.5*@f)*@s"
    V.a = E"atan2(@qy-@py,@qx-@px)-90"
    scope(function()
      shift(R.qx, R.qy) rotate(R.a)
      if R.f > K"0.86" then
        V.t = E"0.18*@s" vtone("flo@c", K"0.2") vfill("flo@c", U, 0, function() circle(0, 0, R.t) end)
      else V.bside = R.sg bloom(R.s, R.t) end
    end)
  end)
end
-- ---------------------------------------------------------------- clusters
-- in a block of their own (Lua's 200 locals): CL.curl, CL.fork ... draw them
local CL = {}
do
  -- \flo@curlunit{axis cm}: flora's cyme as the species' coiled cyme; \flo@curl{x}{y}{len}{w}{late}
  local curl
  local function curlunit(len)
    V.bst = R.ust stone()
    if chance(K"0.5") then V.side = U else V.side = -U end
    V.t = sym(10 * U) V.h = E"90+@t"
    V.cfd = E"min(0.4,0.17+0.014*$size)"
    V.ccn = E"int(max(9,min(17,$count+2)))"
    curl(0, 0, len, K"0.026", 0)
    if chance(K"0.6") then
      V.t = range(K"0.25", K"0.4") V.ci = E"int(37*@t)"
      local ci = I("ci")
      V.xa = T.AX[ci] V.ya = T.AY[ci]
      V.t = (ci + 1) * U
      V.xb = T.AX[ci + 1] V.yb = T.AY[ci + 1]
      V.t = range(30 * U, 50 * U) V.h = E"atan2(@yb-@ya,@xb-@xa)-@side*@t"
      V.t = range(K"0.45", K"0.65") V.L = E("(%1)*@t", { len })
      V.side = E"-@side" V.ccn = E"int(max(6,@ccn*0.7))"
      curl(R.xa, R.ya, R.L, K"0.018", K"0.15")
    end
  end
  function curl(x, y, len, w, late)
    V.xx = x V.yy = y V.cL = len V.clate = late
    V.t = range(K"0.85", K"1.15") V.turn = E"(100+170*$coil)*@t"
    put(1, R.xx, R.yy) V.ds = E"@cL/36"
    loop("#Gc", 1, 36, function()
      V.v = E"(#Gc-0.5)/36"
      V.a = E"@h+@side*@turn*@v*@v*sqrt(sqrt(@v))"
      V.xx = E"@xx+@ds*cos(@a)" V.yy = E"@yy+@ds*sin(@a)"
      put(R["#Gc"] + 1, R.xx, R.yy)
    end)
    normals(37)
    for g = 1, 37 do setv(T.AX, g, X[g]) setv(T.AY, g, Y[g]) setv(T.AN, g, NX[g]) setv(T.AM, g, NY[g]) end
    V["#Gc"] = 38
    vstem(37, w, K"0.006", K"0.1")
    V.csr = tr("siderule")
    loop("#Gc", 1, function() return I("ccn") end, function()
      V.v = E"#Gc/@ccn" V.f = E"0.18+0.82*sqrt(@v)*sqrt(sqrt(@v))"
      V.ri = E"int(max(2,min(37,floor(@f*36+1.5))))"
      if R.csr == "same" then V.sg = E"-@side" elseif R["#Gc"] % 2 == 1 then V.sg = -U else V.sg = U end
      local ri = I("ri")
      V.px = T.AX[ri] V.py = T.AY[ri] V.pnx = T.AN[ri] V.pny = T.AM[ri]
      V.t = range(K"0.7", K"1.2") V.stalk = E"(0.1-0.08*@f)*@t"
      V.qx = E"@px+@pnx*@sg*@stalk" V.qy = E"@py+@pny*@sg*@stalk"
      if R.stalk > K"0.03" then
        vtone("flo@c", K"0.12")
        vstroke("flo@c", K"0.25", K"0.9", 0, function() moveto(R.px, R.py) lineto(R.qx, R.qy) end)
      end
      V.s = range(K"0.85", K"1.15") V.s = E"@cfd*(1-0.74*@f)*@s"
      V.t = E"@bst+0.55-@f-@clate"
      V.a = E"atan2(@qy-@py,@qx-@px)-90"
      scope(function()
        shift(R.qx, R.qy) rotate(R.a)
        if R.f > K"0.8" then
          V.t = E"0.3*@s" vtone("flo@c", K"0.2") vfill("flo@c", U, 0, function() circle(0, 0, R.t) end)
        else V.bside = R.sg bloom(R.s, R.t) end
      end)
    end)
  end
  CL.curl = curlunit
  -- \flo@zset, \flo@z: the named lists of the clusters (\flo@Z<name>@<i>)
  local function zset(n, i, v) setv(T.Z, n .. "@" .. i, v) end
  local function z(n, i) return T.Z[n .. "@" .. i] end
  -- \flo@fat{x}{y}{angle}{diameter}{stage}
  local function fat(x, y, a, d, st)
    scope(function()
      shift(x, y) rotate(a)
      if st < K"-0.25" then
        V.t = E("0.3*(%1)", { d }) vtone("flo@c", K"0.2") vfill("flo@c", U, 0, function() circle(0, 0, R.t) end)
      else
        if a < 0 then V.bside = -U else V.bside = U end
        bloom(d, st)
      end
    end)
  end
  -- \flo@fadd, \flo@fdraw
  local function fadd(x, y, a, d, st)
    V.fnum = R.fnum + U
    local n = I("fnum")
    zset("fx", n, x) zset("fy", n, y) zset("fa", n, a) zset("fs", n, d) zset("ft", n, st)
  end
  local function fdraw()
    loop("#Gc", 1, function() return I("fnum") end, function()
      local g = R["#Gc"]
      fat(z("fx", g), z("fy", g), z("fa", g), z("fs", g), z("ft", g))
    end)
  end
  -- \flo@hair{x1}{y1}{x2}{y2}
  local function hair(x1, y1, x2, y2)
    vtone("flo@c", K"0.12")
    vstroke("flo@c", K"0.25", K"0.9", 0, function() moveto(x1, y1) lineto(x2, y2) end)
  end
  -- \flo@axis{len}{bend}{width}
  local function axis(len, bend, w)
    if chance(K"0.5") then V.side = U else V.side = -U end
    V.t = range(K"0.75", K"1.25") V.turn = E("(%1)*@t", { bend })
    V.t = sym(8 * U) V.h = E"90+@t"
    put(1, 0, 0) V.xx = 0 V.yy = 0 V.ds = E("(%1)/24", { len })
    loop("#Gc", 1, 24, function()
      V.v = E"(#Gc-0.5)/24"
      V.a = E"@h+@side*@turn*@v*@v*sqrt(sqrt(@v))"
      V.xx = E"@xx+@ds*cos(@a)" V.yy = E"@yy+@ds*sin(@a)"
      put(R["#Gc"] + 1, R.xx, R.yy)
    end)
    normals(25)
    for g = 1, 25 do setv(T.AX, g, X[g]) setv(T.AY, g, Y[g]) setv(T.AN, g, NX[g]) setv(T.AM, g, NY[g]) end
    V["#Gc"] = 26
    vstem(25, w, K"0.006", K"0.1")
  end
  -- \flo@axisat
  local function axisat()
    V.ri = E"int(max(2,min(25,floor(@clf*24+1.5))))"
    local ri = I("ri")
    V.px = T.AX[ri] V.py = T.AY[ri] V.pnx = T.AN[ri] V.pny = T.AM[ri]
    V.ah = E"atan2(-@pnx,@pny)"
  end
  -- \flo@walk{x}{y}{heading}{turn}{len}{n}
  local function walk(x, y, h, dh, len, n)
    V.xx = x V.yy = y put(1, R.xx, R.yy) V.ds = E("(%1)/(%2)", { len, n * U })
    loop("#Gc", 1, n, function()
      V.a = E("(%1)+(%2)*(#Gc-0.5)/(%3)", { h, dh, n * U })
      V.xx = E"@xx+@ds*cos(@a)" V.yy = E"@yy+@ds*sin(@a)"
      put(R["#Gc"] + 1, R.xx, R.yy)
    end)
  end
  -- \flo@forkunit{reach}: flora's sprig as the species' forked cyme
  local function forkunit(len)
    V.bst = R.ust stone() V.fnum = 0
    V.cld = E"int(min(3,$depth+1))"
    V.clfd = E"min(0.45,0.16+0.012*$size)"
    V.t = sym(8 * U) V.t = E"90+@t" V.s = E("(%1)*0.4", { len })
    zset("bx", 1, 0) zset("by", 1, 0) zset("bh", 1, R.t) zset("bl", 1, R.s)
    zset("bw", 1, K"0.024") zset("bv", 1, 0) V.cln = U
    loop("#Gd", 1, function() return I("cln") end, function()
      local g = R["#Gd"]
      V.clh = z("bh", g) V.cll = z("bl", g) V.clw = z("bw", g) V.clv = z("bv", g)
      V.clb = sym(20 * U)
      walk(z("bx", g), z("by", g), R.clh, R.clb, R.cll, 6)
      V.clx = R.xx V.cly = R.yy
      V.clwe = E"0.72*@clw" vstem(7, R.clw, R.clwe, K"0.1")
      V.clh = E"@clh+@clb"
      V.t = sym(K"0.05") V.clt = E"@bst-0.3*@clv+@t"
      V.t = range(K"0.85", K"1.1") V.cls = E"@clfd*(1-0.1*@clv)*@t"
      V.t = E"@clh-90"
      if I("clv") < I("cld") then
        if I("clv") < 2 and chance(K"0.4") then
          if chance(K"0.5") then V.sg = U else V.sg = -U end
          V.a = range(40 * U, 70 * U) V.a = E"@clh-90+@sg*@a"
          V.s = range(K"0.35", K"0.55") V.s = E"@cll*@s"
          scope(function()
            shift(R.clx, R.cly) rotate(R.a) scale(R.s)
            V["vl@W"] = K"0.14" V["vl@tone"] = "" V["vl@u"] = R.s vleaflet()
          end)
        end
        if chance(K"0.2") then V.clk = 3 * U else V.clk = 2 * U end
        loop("#n", 1, function() return I("clk") end, function()
          if I("clk") == 2 then
            V.a = range(16 * U, 34 * U)
            if R["#n"] == 1 then V.a = E"-@a" end
          else
            V.a = range(22 * U, 36 * U) V.a = E"(#n-2)*@a"
          end
          V.cln = R.cln + U
          local c = I("cln")
          zset("bx", c, R.clx) zset("by", c, R.cly)
          V.t = E"@clh+@a" zset("bh", c, R.t)
          V.t = range(K"0.62", K"0.8") V.t = E"@cll*@t" zset("bl", c, R.t)
          zset("bw", c, R.clwe)
          zset("bv", c, R.clv + U)
        end)
        V.xa = E"@clx+0.22*@cll*cos(@clh)" V.ya = E"@cly+0.22*@cll*sin(@clh)"
        hair(R.clx, R.cly, R.xa, R.ya)
        V.t = E"@clh-90" fadd(R.xa, R.ya, R.t, R.cls, R.clt)
      else
        fadd(R.clx, R.cly, R.t, R.cls, R.clt)
      end
    end)
    fdraw()
  end
  -- \flo@panicleunit{axis cm}
  local function panicleunit(len)
    V.bst = R.ust V.clL = len stone() V.fnum = 0
    V.clfd = E"min(0.34,0.15+0.01*$size)"
    axis(R.clL, 30 * U, K"0.026")
    V.clm = E"int(max(3,min(7,$count/4+1)))"
    if chance(K"0.5") then V.clsg = U else V.clsg = -U end
    loop("#Gd", 1, function() return I("clm") end, function()
      V.t = sym(K"0.03") V.clf = E"0.1+0.66*(#Gd-1)/max(1,@clm-1)+@t"
      axisat() V.clsg = E"-@clsg"
      V.clang = range(40 * U, 58 * U) V.clh = E"@ah+@clsg*@clang"
      V.t = range(K"0.8", K"1.2") V.cll = E"@clL*0.42*(1-0.7*@clf)*@t"
      V.clb = E"-@clsg*0.55*@clang"
      walk(R.px, R.py, R.clh, R.clb, R.cll, 8) normals(9)
      V.t = E"@bst+0.2-0.9*@clf" V.cls = E"@clfd*(1-0.3*@clf)"
      V.a = E"@clh+@clb-90" fadd(R.xx, R.yy, R.a, R.cls, R.t)
      V.clk = int(1, 3)
      if tr("depth") == 2 * U and R.clf < K"0.45" then V.clk = R.clk + U end
      loop("#n", 1, function() return I("clk") end, function()
        V.v = E"0.3+0.5*(#n-1)/max(1,@clk-1)"
        V.clq = E"int(1+floor(@v*8+0.5))"
        if R["#n"] % 2 == 1 then V.sg = U else V.sg = -U end
        local q = I("clq")
        V.xa = X[q] V.ya = Y[q] V.clnx = NX[q] V.clny = NY[q]
        V.t = range(K"0.1", K"0.18")
        V.xb = E"@xa+(@clnx*@sg*0.8+@clny*0.6)*@t"
        V.yb = E"@ya+(@clny*@sg*0.8-@clnx*0.6)*@t"
        hair(R.xa, R.ya, R.xb, R.yb)
        V.t = E"@bst+0.3-0.9*@clf-0.25*(1-@v)"
        V.s = E"@clfd*(0.9-0.3*@clf)"
        V.a = E"atan2(@yb-@ya,@xb-@xa)-90"
        fadd(R.xb, R.yb, R.a, R.s, R.t)
      end)
      vstem(9, K"0.012", K"0.005", K"0.12")
    end)
    V.xa = T.AX[25] V.ya = T.AY[25]
    V.clf = U axisat() V.a = E"@ah-90"
    V.t = E"@bst-0.6" V.s = E"0.6*@clfd" fadd(R.xa, R.ya, R.a, R.s, R.t)
    fdraw()
  end
  -- \flo@thyrseunit{axis cm}
  local function thyrseunit(len)
    V.bst = R.ust V.clL = len stone() V.fnum = 0
    V.clfd = E"min(0.42,0.15+0.012*$size)"
    axis(R.clL, 20 * U, K"0.028")
    V.clm = E"int(max(6,min(11,$count/2.5)))"
    loop("#Gd", 1, function() return I("clm") end, function()
      V.clf = E"0.08+0.84*(#Gd-1)/max(1,@clm-1)"
      axisat()
      loop("#n", 0, 1, function()
        if R["#n"] == 0 then V.sg = U else V.sg = -U end
        V.clang = range(45 * U, 65 * U) V.clh = E"@ah+@sg*@clang"
        V.t = range(K"0.8", K"1.2") V.cll = E"@clL*0.17*(1-0.75*@clf)*@t"
        V.xa = E"@px+@cll*cos(@clh)" V.ya = E"@py+@cll*sin(@clh)"
        hair(R.px, R.py, R.xa, R.ya)
        V.clt = E"@bst+0.3-1.0*@clf" V.cls = E"@clfd*(1-0.4*@clf)"
        if R.clf < K"0.8" then
          loop("#m", 0, 1, function()
            if R["#m"] == 0 then V.t = U else V.t = -U end
            V.a = range(30 * U, 50 * U) V.a = E"@clh+@t*@a"
            V.xb = E"@xa+0.55*@cll*cos(@a)" V.yb = E"@ya+0.55*@cll*sin(@a)"
            hair(R.xa, R.ya, R.xb, R.yb)
            V.t = E"@clt-0.2" V.s = E"0.85*@cls" V.a = E"@a-90"
            fadd(R.xb, R.yb, R.a, R.s, R.t)
          end)
        end
        V.xa = E"@xa+0.15*@cll*cos(@clh)" V.ya = E"@ya+0.15*@cll*sin(@clh)"
        V.a = E"@clh-90" fadd(R.xa, R.ya, R.a, R.cls, R.clt)
      end)
    end)
    V.xa = T.AX[25] V.ya = T.AY[25]
    V.clf = U axisat() V.a = E"@ah-90"
    V.t = E"@bst-0.75" V.s = E"0.6*@clfd" fadd(R.xa, R.ya, R.a, R.s, R.t)
    fdraw()
  end
  -- \flo@corymbunit{height cm}
  local function corymbunit(len)
    V.bst = R.ust V.clL = len stone() V.fnum = 0
    V.clfd = E"min(0.6,0.3*@fd)"
    V.clm = E"int(max(3,min(9,min($count,2.6/@clfd))))"
    V.clW = E"@clL*0.7" V.cltop = E"@clL*0.92" V.cla = E"@clL*0.5"
    V.t = sym(K"0.06") V.yc = E"0.35*@cla" V.yd = E"0.7*@cla"
    vtone("flo@c", K"0.1")
    vstroke("flo@c", K"0.5", U, 0, function() moveto(0, 0) curveto(R.t, R.yc, R.t, R.yd, 0, R.cla) end)
    if chance(K"0.5") then V.clsg = U else V.clsg = -U end
    loop("#Gd", 1, function() return I("clm") end, function()
      V.v = E"(#Gd-1)/max(1,@clm-1)"
      V.clsg = E"-@clsg"
      V.ya = E"@cla*(0.12+0.88*@v)"
      V.t = range(K"0.75", U) V.xb = E"@clsg*@clW*(1-0.85*@v)*@t"
      V.t = sym(K"0.08") V.yb = E"@cltop-0.32*@xb*@xb/@clW+@t"
      V.xc = E"0.55*@xb" V.yc = E"@ya+0.25*(@yb-@ya)"
      V.xd = E"0.95*@xb" V.yd = E"@yb-0.45*(@yb-@ya)"
      vtone("flo@c", K"0.12")
      vstroke("flo@c", K"0.3", K"0.9", 0, function() moveto(0, R.ya) curveto(R.xc, R.yc, R.xd, R.yd, R.xb, R.yb) end)
      V.t = E"@bst-0.35*@v" V.s = range(K"0.85", K"1.1") V.s = E"@clfd*@s"
      V.a = E"-20*@xb/@clW" fadd(R.xb, R.yb, R.a, R.s, R.t)
    end)
    vtone("flo@c", K"0.12") V.xb = sym(K"0.04")
    vstroke("flo@c", K"0.3", K"0.9", 0, function() moveto(0, R.cla) lineto(R.xb, R.cltop) end)
    V.t = E"@bst-0.42" V.s = E"0.9*@clfd" V.a = 0
    fadd(R.xb, R.cltop, R.a, R.s, R.t)
    fdraw()
  end
  -- \flo@spikeunit{axis cm}
  local function spikeunit(len)
    V.bst = R.ust stone() V.fnum = 0
    V.clfd = E"min(0.5,0.2+0.014*$size)"
    axis(len, 14 * U, K"0.03")
    V.clm = E"int(max(14,min(30,$count+4)))"
    loop("#Gd", 1, function() return I("clm") end, function()
      V.t = sym(K"0.01") V.clf = E"0.06+0.92*(#Gd-1)/max(1,@clm-1)+@t"
      axisat()
      V.t = range(K"0.85", K"1.1") V.s = E"@clfd*(1-0.45*@clf)*@t"
      V.t = E"@bst+0.35-1.2*@clf"
      V.clk = E"int(mod(#Gd,3))"
      if I("clk") == 0 then
        V.a = sym(10 * U) V.a = E"@ah-90+@a"
        fadd(R.px, R.py, R.a, R.s, R.t)
      else
        if I("clk") == 1 then V.sg = U else V.sg = -U end
        V.a = range(30 * U, 55 * U) V.a = E"@ah-90+@sg*@a"
        V.xa = E"@px+@pnx*@sg*0.42*@s" V.ya = E"@py+@pny*@sg*0.42*@s"
        fadd(R.xa, R.ya, R.a, R.s, R.t)
      end
    end)
    fdraw()
  end
  -- \flo@umbelsunit{ray cm}: a simple umbel
  local function umbelsunit(len)
    V.bst = R.ust V.clL = len stone() V.fnum = 0 V.oo = tr("openorder")
    V.clfd = E"min(0.8,0.24+0.02*$size)"
    V.clm = E"int(max(4,min(12,$count)))"
    V.clang = range(50 * U, 75 * U)
    loop("#Gd", 1, function() return I("clm") end, function()
      local g = R["#Gd"]
      if g % 2 == 1 then V.clk = nediv(g + 1, 2) * U else V.clk = (I("clm") + 1 - nediv(g, 2)) * U end
      V.clf = E"(@clk-(@clm+1)/2)/max(1,(@clm-1)/2)"
      V.t = sym(5 * U) V.a = E"90+@clf*@clang+@t"
      V.t = range(K"0.88", K"1.05") V.clR = E"@clL*@t*(1-0.12*abs(@clf))"
      V.xb = E"@clR*cos(@a)" V.yb = E"@clR*sin(@a)"
      V.xc = E"0.15*@xb" V.yc = E"0.5*@yb" V.xd = E"0.6*@xb" V.yd = E"0.95*@yb"
      vtone("flo@c", K"0.12")
      vstroke("flo@c", K"0.25", K"0.9", 0, function() moveto(0, 0) curveto(R.xc, R.yc, R.xd, R.yd, R.xb, R.yb) end)
      V.tmp = "center"
      if R.oo == R.tmp then V.t = E"@bst-0.35*abs(@clf)" else V.t = E"@bst-0.35*(1-abs(@clf))" end
      V.s = sym(K"0.05") V.t = E"@t+@s"
      V.s = range(K"0.85", K"1.1") V.s = E"@clfd*@s" V.a = E"@a-90"
      fadd(R.xb, R.yb, R.a, R.s, R.t)
    end)
    loop("#Gd", -1, 1, function()
      V.t = sym(10 * U) V.a = E"#Gd*40+@t+180" V.s = range(K"0.12", K"0.18") V.s = E"@clL*@s"
      scope(function()
        rotate(R.a) scale(R.s)
        V["vl@W"] = K"0.06" V["vl@tone"] = "" V["vl@u"] = R.s vleaflet()
      end)
    end)
    fdraw()
  end
  -- \flo@headunit{stalk cm}
  local function headunit(len)
    V.bst = R.ust V.clL = len stone() V.fnum = 0 V.bfan = U
    axis(R.clL, 18 * U, K"0.024")
    V.clf = U axisat()
    V.t = range(K"0.9", K"1.1") V.clr = E"(0.26+0.006*$count)*@t"
    V.clx = E"@px+0.75*@clr*@pny" V.cly = E"@py-0.75*@clr*@pnx"
    V.clm = E"int(max(18,min(34,$count+6)))"
    loop("#Gd", 1, function() return I("clm") end, function()
      V.clk = (I("clm") + 1 - R["#Gd"]) * U
      V.v = E"sqrt(@clk/@clm)" V.a = E"137.508*@clk"
      V.xa = E"@clx+0.8*@clr*@v*cos(@a)" V.ya = E"@cly+0.72*@clr*@v*sin(@a)"
      V.t = range(K"0.9", K"1.1") V.s = E"@clr*0.65*(0.7+0.3*@v)*@t"
      V.t = E"@bst-0.45*(1-@v)" V.a = E"@a-90"
      fadd(R.xa, R.ya, R.a, R.s, R.t)
    end)
    fdraw() V.bfan = 0
  end
  -- \flo@catkinunit{twig cm}
  local function catkinunit(len)
    V.bst = R.ust V.clL = len stone()
    V.t = sym(10 * U) V.clh = E"90+@t" V.clb = sym(15 * U)
    walk(0, 0, R.clh, R.clb, R.clL, 6)
    for g = 1, 7 do setv(T.AX, g, X[g]) setv(T.AY, g, Y[g]) end
    V["#Gc"] = 8
    vstem(7, K"0.028", K"0.016", K"0.1")
    V.clm = int(2, 4)
    V.clw = E"0.11+0.02*$size" V.clwe = E"0.4*@clw"
    if R["vf@tone"] == "" then V.clt = K"0.4" else V.clt = R["vf@tone"] end
    loop("#Gd", 1, function() return I("clm") end, function()
      V.clq = (8 - R["#Gd"]) * U
      local q = I("clq")
      V.xa = T.AX[q] V.ya = T.AY[q]
      if R["#Gd"] % 2 == 1 then V.sg = U else V.sg = -U end
      V.t = range(40 * U, 80 * U) V.clhd = E"@clh+@clb+@sg*@t"
      if R.bst > K"1.15" then
        V.xb = E"@xa+0.25*cos(@clhd)" V.yb = E"@ya+0.25*sin(@clhd)"
        hair(R.xa, R.ya, R.xb, R.yb)
        V.fu = K"0.3" V.a = E"@clhd-90"
        scope(function() shift(R.xb, R.yb) rotate(R.a) scale(R.fu) fruit() end)
      else
        if R.sg == U then V.cltg = 270 * U else V.cltg = -90 * U end
        V.t = range(K"0.7", K"1.1") V.cll = E"@clL*2.2*@t*min(1,0.45+0.6*@bst)"
        V.clph = sym(180 * U) V.clr = E"@clhd-@cltg"
        put(1, R.xa, R.ya) V.xx = R.xa V.yy = R.ya V.ds = E"@cll/18"
        loop("#Gc", 1, 18, function()
          V.v = E"(#Gc-0.5)/18"
          V.a = E"@cltg+@clr*(1-min(1,@v*3))+7*sin(360*@v+@clph)"
          V.xx = E"@xx+@ds*cos(@a)" V.yy = E"@yy+@ds*sin(@a)"
          put(R["#Gc"] + 1, R.xx, R.yy)
        end)
        vtone("flo@c", K"0.1") vstroke("flo@c", K"0.4", U, 0, function() smoothopen(5) end)
        loop("#Gc", 4, 19, function()
          V.clq = (R["#Gc"] - 3) * U
          zset("cx", I("clq"), X[R["#Gc"]]) zset("cy", I("clq"), Y[R["#Gc"]])
        end)
        loop("#Gc", 1, 16, function() put(R["#Gc"], z("cx", R["#Gc"]), z("cy", R["#Gc"])) end)
        normals(16)
        loop("#Gc", 1, 16, function()
          zset("cn", R["#Gc"], NX[R["#Gc"]]) zset("cm", R["#Gc"], NY[R["#Gc"]])
        end)
        vstem(16, R.clw, R.clwe, R.clt)
        vtone("flo@c", K"0.16")
        loop("#Gc", 2, 15, function()
          local g = R["#Gc"]
          if g % 2 == 1 then V.sg = U else V.sg = -U end
          V.v = E"(#Gc-1)/15" V.s = E"@clw*0.5*(1-0.6*@v)"
          V.xa = z("cx", g) V.ya = z("cy", g) V.clnx = z("cn", g) V.clny = z("cm", g)
          V.xb = E"@xa+@clnx*@sg*@s" V.yb = E"@ya+@clny*@sg*@s"
          V.xc = E"@xa+@clny*0.6*@s" V.yc = E"@ya-@clnx*0.6*@s"
          vstroke("flo@c", K"0.3", K"0.7", 1, function() moveto(R.xb, R.yb) curveto(R.xc, R.yc, R.xc, R.yc, R.xa, R.ya) end)
          V.t = range(K"0.008", K"0.014")
          vfill("flo@c", K"0.9", 0, function() circle(R.xb, R.yb, R.t) end)
        end)
      end
    end)
  end
  CL.fork, CL.panicle, CL.thyrse, CL.corymb = forkunit, panicleunit, thyrseunit, corymbunit
  CL.spike, CL.umbel, CL.head, CL.catkin = spikeunit, umbelsunit, headunit, catkinunit
end
-- \flo@vtendril{size}: a tapered logarithmic spiral from the origin
local function vtendril(size)
  V.t = E("1.6*(%1)", { size }) T.vcurl(R.t)
  vstem(45, K"0.022", K"0.004", K"0.12")
end

-- ---------------------------------------------------------------- room
-- \flo@room{1 mark, 0 count}{x}{y}{r}: the 5 mm cells whose centers lie in the disc
local function room(mark, x, y, r)
  V.ox = pm.int(E("(%1)*10+1000", { x })) V.oy = pm.int(E("(%1)*10+1000", { y }))
  V["or"] = pm.int(E("max(3,(%1)*10)", { r }))
  V["#On"] = 0 V["#Ot"] = 0
  local ox, oy, o = I("ox"), I("oy"), I("or")
  local id = R.roomid
  loop("#Oi", nediv(ox - o - 2, 5), nediv(ox + o - 2, 5), function()
    loop("#Oj", nediv(oy - o - 2, 5), nediv(oy + o - 2, 5), function()
      local i, j = R["#Oi"], R["#Oj"]
      local dx, dy = 5 * i + 2 - ox, 5 * j + 2 - oy
      if dx * dx + dy * dy <= o * o then
        local key = id .. "@" .. i .. "@" .. j
        if mark == 1 then setv(ROOM, key, true)
        else
          V["#Ot"] = R["#Ot"] + 1
          if ROOM[key] then V["#On"] = R["#On"] + 1 end
        end
      end
    end)
  end)
end
local function takenat(x, y, r)                              -- -> \flo@taken
  room(0, x, y, r)
  if R["#Ot"] == 0 then V.taken = 0 else V.taken = pm.div(R["#On"] * U, R["#Ot"] * U) end
end

-- ---------------------------------------------------------------- the inflorescence in place
local KIND = { solitary = "solitary", cumbel = "umbel", umbel = "umbel", corymb = "umbel", dichasium = "umbel",
  raceme = "raceme", spike = "raceme", panicle = "raceme", thyrse = "raceme", monochasium = "raceme",
  head = "head", catkin = "catkin" }
local function kindof()
  V["if"] = tr("inflo") V.kind = KIND[R["if"]] or "blossoms"
end
local function unitdisc(x, y, axis, k)
  kindof() fdiam(k) V.uo = 0 V.udr = E"0.5*@fd"
  if R.kind == "umbel" then V.uo = E("0.69*(%1)", { k }) V.udr = E("0.86*(%1)", { k }) end
  if R.kind == "raceme" then V.uo = E("0.95*(%1)", { k }) V.udr = E("0.75*(%1)", { k }) end
  if R.kind == "blossoms" then V.uo = E"0.5*@fd" V.udr = E"0.8*@fd" end
  if R.kind == "head" then V.uo = E("0.8*(%1)", { k }) V.udr = E("0.5*(%1)", { k }) end
  if R.kind == "catkin" then V.uo = E("0.2*(%1)", { k }) V.udr = E("0.9*(%1)", { k }) end
  V.udx = E("(%1)+@uo*cos(%2)", { x, axis }) V.udy = E("(%1)+@uo*sin(%2)", { y, axis })
end
local function unitdraw(k)
  fdiam(k)
  local f = R["if"]
  if f == "solitary" then bloom(R.fd, R.ust)
  elseif f == "cumbel" then
    V.t = range(K"0.95", K"1.35") V.t = E("@t*(%1)", { k }) umbelunit(R.t, R.ust)
  else
    V.t = range(K"1.5", K"2.3") V.L = E("@t*(%1)", { k })
    if f == "raceme" then racemeunit(R.L, K"0.3", 40 * U)
    elseif f == "spike" then CL.spike(R.L)
    elseif f == "panicle" then CL.panicle(R.L)
    elseif f == "thyrse" then CL.thyrse(R.L)
    elseif f == "monochasium" then CL.curl(R.L)
    elseif f == "catkin" then V.L = E"0.3*@L" CL.catkin(R.L)
    elseif f == "dichasium" then V.L = E"0.8*@L" CL.fork(R.L)
    elseif f == "corymb" then V.L = E"0.75*@L" CL.corymb(R.L)
    elseif f == "umbel" then V.L = E"0.55*@L" CL.umbel(R.L)
    elseif f == "head" then V.L = E"0.35*@L" CL.head(R.L)
    else V.fd = E"0.85*@fd" blossoms(R.fd, R.ust) end
  end
end
-- \flo@unit{x}{y}{axis}{size}{later}: the species' inflorescence, its room marked
local function unit(x, y, axis, k, late)
  V.ux = x V.uy = y V.uax = axis V.ua = E("(%1)-90", { axis }) V.uk = k V.ulate = late
  unitdisc(R.ux, R.uy, R.uax, R.uk) V.t = E"0.85*@udr" room(1, R.udx, R.udy, R.t)
  V.t = sym(K"0.08") V.ust = E"1.2*@season-@ulate+@t+$phenology"
  seedorgan()
  if R.kind == "umbel" or R.kind == "raceme" then V.ul = 4 * U else V.ul = 5 * U end
  if at(I("ul")) then
    organ(function() shift(R.ux, R.uy) rotate(R.ua) unitdraw(R.uk) end)
  end
end
-- \flo@lateness{height on the plant} -> \flo@late
local BELOW = { raceme = true, spike = true, catkin = true }
local function lateness(h)
  V["if"] = tr("inflo") V.below = BELOW[R["if"]] and U or 0
  if R.below == U then V.late = E("0.4*(%1)", { h }) else V.late = E("0.4*(1-(%1))", { h }) end
end
local function autumnleaf()
  if tr("turns") == U then
    V.t = E"max(0,@season-0.9)"
    if R.lc < R.t then V.rampname = "flo@aramp" end
  end
  if R.season < K"0.5" then V.lift = E"0.3*(1-@season/0.5)" end
end

-- ---------------------------------------------------------------- the main stem
local function stemx(h)                                      -- -> \flo@sx
  local a = { h }
  V.sb = E("min(1,max(0,(%1)/3))", a)
  V.sx = E("@root+@sb*@sb*(3-2*@sb)*(@pc-@root+@pA*(0.62*sin(360*(%1)/@plam+@pph)+0.38*sin(766.8*(%1)/@plam+@pps)))", a)
end
local function stemtan(h)                                    -- -> \flo@tx, \flo@ty, \flo@sx
  stemx(E("(%1)+0.05", { h })) V.sxa = R.sx stemx(E("(%1)-0.05", { h }))
  V.t = E"veclen(@sxa-@sx,0.1)"
  V.tx = E"(@sxa-@sx)/@t" V.ty = E"0.1/@t"
  stemx(h)
end
local function drawstem()
  V.sn = pm.int(E"@pH/0.25+1")
  loop("#Gd", 1, function() return I("sn") end, function()
    V.t = E"@pH*(#Gd-1)/(@sn-1)" stemx(R.t)
    put(R["#Gd"], R.sx, R.t)
  end)
  vstem(I("sn"), R.pw, K"0.028", K"0.07")
end
local function markstem()
  V.msn = pm.int(E"@pH/0.6")
  loop("#Gd", 1, function() return I("msn") end, function()
    V.my = E"0.6*#Gd-0.3" stemx(R.my) room(1, R.sx, R.my, K"0.2")
  end)
end

-- ---------------------------------------------------------------- a plant, in passes
local florilegiumspecies
local function plantsetup()
  local ga = R["#Ga"]
  V.root = E"(#Ga-2)*0.25" V.pc = E"(#Ga-2)*0.35"
  if R["#Np"] == 1 then V.root = 0 V.pc = 0 end
  if ga == 1 then V.pw = K"0.085" else V.pw = K"0.065" end
  V.pH = R["pp@H" .. ga]
  florilegiumspecies(R["pp@s" .. ga], R["pp@r" .. ga])
  rng.load(R["pp@w" .. ga])
end
local function plantsave() gset("pp@w" .. R["#Ga"], rng.save()) end
local function passstem()
  V.pph = range(0, 360 * U) V.pps = range(0, 360 * U) V.plam = range(5 * U, 8 * U)
  V["pp@f" .. R["#Ga"]] = { R.pph, R.pps, R.plam }
  markstem()
  if at(LSTEM) then scope(drawstem) end
  lateness(U) V.topoff = R.late
  stemtan(R.pH) V.a = pm.atan2(R.ty, R.tx)
  unit(R.sx, R.pH, R.a, K"1.15", R.topoff)
end
local function stemload()
  local f = R["pp@f" .. R["#Ga"]]
  V.pph = f[1] V.pps = f[2] V.plam = f[3]
end
local function leafcof()
  V.t = tr("compound")
  if R.t == "simple" then V.leafc = U else V.leafc = K"1.35" end
end
local function nodeat()
  V.nyy = R.ny V.u = E"@nyy/@pH"
  stemtan(R.nyy) V.nx = R.sx V.ntx = R.tx V.nty = R.ty
  V.ta = pm.atan2(R.nty, R.ntx)
  V.nw = E"@pw+(0.028-@pw)*@u"
end
-- \flo@placeleaf{x}{y}: a leaf at \flo@la degrees, \flo@lf cm, or shorter where its room
-- is taken (three tries), or none; its stream \flo@os
local function placeleaf(x, y)
  V.lx = x V.ly = y V.ok = 0
  loop("#Gd", 1, 3, function()
    if R.ok == 0 then
      V.mx = E"@lx+cos(@la)*@lf*0.55" V.my = E"@ly+sin(@la)*@lf*0.55"
      V.t = E"0.24*@lf" takenat(R.mx, R.my, R.t)
      if R.taken < K"0.2" then V.ok = U else V.lf = E"0.75*@lf" end
    end
  end)
  if R.lf < K"0.45" then V.ok = 0 end
  if R.ok == U then
    loop("#Gd", 1, 3, function()
      V.t = E"(0.05+0.25*#Gd)*@lf"
      V.mx = E"@lx+cos(@la)*@t" V.my = E"@ly+sin(@la)*@t"
      V.t = E"0.2*@lf" room(1, R.mx, R.my, R.t)
    end)
    if at(LLEAF) then
      organ(function()
        shift(R.lx, R.ly) V.t = E"@la-90" rotate(R.t)
        scale(R.lf) autumnleaf()
        V.t = E"@lf*28.45276" leaf(R.t)
      end)
    end
  end
end
local function nodeleaves()
  nodeat()
  V.side = E"-1*(@side)"
  V["nd@" .. R["#Ga"] .. "@" .. R["#Ge"]] = { R.nyy, R.side }
  loop("#Gb", 1, function() return I("per") end, function()
    if R["#Gb"] == 2 then V.ls = E"-1*(@side)" else V.ls = R.side end
    V.t = range(35 * U, 60 * U)
    if R["#Gb"] == 3 then V.t = range(8 * U, 20 * U) end
    V.la = E"@ta+@ls*@t"
    V.t = range(K"0.85", K"1.1") V.lf = E"(2.6-1.2*@u)*@t*@leafk*@leafc*(#Gb==3 ? 0.7 : 1)"
    V.t = range(K"0.05", K"0.3") V.sbend = E"@ls*@t"
    V.lc = rnd()
    seedorgan()
    placeleaf(R.nx, R.nyy)
  end)
end
local function nodes()
  while R.ny < R.nlast do
    V["#Ge"] = R["#Ge"] + 1 nodeleaves()
    V.t = range(K"1.2", K"1.9") V.ny = E"@ny+@t*@gap"
  end
end
local function rosette()
  V.nb = int(3, 5)
  loop("#Gb", 1, function() return I("nb") end, function()
    V.f = E"(#Gb-(@nb+1)/2)/max(1,(@nb-1)/2)"
    V.t = sym(8 * U) V.la = E"90-62*@f+@t"
    V.lf = range(K"1.6", K"2.3") V.t = range(K"0.05", K"0.3") V.sbend = E"(@f<0 ? 1 : -1)*@t"
    V.lc = rnd() seedorgan() placeleaf(R.root, K"0.1")
  end)
end
local function eudicotleaves()
  V.arr = tr("arrangement") V.per = U V.gap = U V.leafk = U
  if R.arr == "opposite" then V.per = 2 * U V.gap = K"1.3" end
  if R.arr == "whorled" then V.per = 3 * U V.gap = K"1.4" end
  if R.arr == "rosette" then rosette() V.gap = K"1.6" V.leafk = K"0.4" end
  V.ny = range(K"0.7", K"1.3")
  if chance(K"0.5") then V.side = U else V.side = -U end
  V.nlast = E"@pH-1.6"
  nodes()
end
local function monocotleaves()
  V.nb = int(3, 5)
  loop("#Gb", 1, function() return I("nb") end, function()
    V.f = E"(#Gb-(@nb+1)/2)/max(1,(@nb-1)/2)"
    V.t = sym(5 * U) V.la = E"90-24*@f+@t"
    V.t = range(K"0.3", K"0.46") V.lf = E"min(7,@pH*@t)*(1-0.25*abs(@f))"
    V.t = range(K"0.1", K"0.35") V.sbend = E"(@f<0 ? -1 : 1)*@t"
    V.lc = rnd() seedorgan() V.t = E"@root+0.12*@f" placeleaf(R.t, 0)
  end)
  if chance(K"0.5") then V.side = U else V.side = -U end
  V.per = U V.leafk = K"0.75"
  V.ny = range(K"0.22", K"0.3") V.ny = E"@ny*@pH" V["#Ge"] = R["#Ge"] + 1 nodeleaves()
  V.ny = range(K"0.42", K"0.52") V.ny = E"@ny*@pH" V["#Ge"] = R["#Ge"] + 1 nodeleaves()
end
local function passleaves()
  stemload() V["#Ge"] = 0 leafcof()
  V.cl = tr("clade")
  if R.cl == "monocot" then monocotleaves() else eudicotleaves() end
  V["nd@n" .. R["#Ga"]] = R["#Ge"]
end
-- \flo@branchto: the branch to (\flo@bx,\flo@by), a leaflet or two along it, what it carries
local function branchto()
  branchpath(R.nx, R.nyy, R.ntx, R.nty, R.bx, R.by, R.ax, R.ay)
  loop("#Gd", 1, 3, function() V.t = E"0.25*#Gd" cubicat(R.t) room(1, R.cx, R.cy, K"0.15") end)
  V.w = E"min(0.7*@nw,0.05)" V.wb = E"max(0.012,0.45*@w)"
  if at(LSTEM) then cubicstem(R.w, R.wb) end
  if R.d > K"1.2" then
    if R.d > K"2.2" then V.nl = 2 * U else V.nl = U end
    loop("#Gb", 1, function() return I("nl") end, function()
      V.t = E"0.25+0.3*#Gb/@nl" cubicat(R.t)
      V.t = range(40 * U, 60 * U) V.la = E"@ca+(#Gb==1 ? -1 : 1)*@side*@t-90"
      V.lf = range(K"0.45", K"0.75")
      seedorgan()
      if at(LLEAF) then
        organ(function()
          shift(R.cx, R.cy) rotate(R.la) scale(R.lf)
          V["vl@W"] = "" V["vl@tone"] = "" V["vl@u"] = R.lf vleaflet()
        end)
      end
    end)
  end
  local what = I("what")
  if what == 1 then
    unit(R.bx, R.by, R.a, R.usc, R.ulate)
  elseif what == 2 then
    V.t = E"0.85*@bdr" room(1, R.bdx, R.bdy, R.t)
    seedorgan()
    if at(LBLOOM) then
      organ(function()
        shift(R.bx, R.by) V.t = E"@a-90" rotate(R.t)
        fdiam(K"0.6") V.fd = E"min(1.1,@fd)" budding(R.fd)
      end)
    end
  elseif what == 3 then
    V.t = E"0.85*@bdr" room(1, R.bdx, R.bdy, R.t)
    seedorgan()
    if at(LAIRY) then
      organ(function()
        shift(R.bx, R.by) V.t = R.a rotate(R.t)
        V.oarg = range(K"0.3", K"0.5") vtendril(R.oarg)
      end)
    end
  elseif what == 4 then
    V.t = E"0.85*@bdr" room(1, R.bdx, R.bdy, R.t)
    V.t = range(K"0.05", K"0.3") V.sbend = E"@side*@t" V.lc = rnd()
    seedorgan()
    if at(LLEAF) then
      organ(function()
        shift(R.bx, R.by) V.t = E"@a-90" rotate(R.t)
        scale(R.lf) autumnleaf()
        V.t = E"@lf*28.45276" leaf(R.t)
      end)
    end
  end
end
-- \flo@branch: what the branch carries, then the freest of three places for it
local function branch()
  lateness(R.u) V.mk = rnd()
  V.hb = tr("habit")
  if R.hb == "climbing" then V.climb = U else V.climb = tr("tendrils") end
  if R.filling == U then V.mk = E"@mk*1.25-0.25" end
  if R.mk < 0 then V.what = 4 * U leafcof() V.lf = range(K"1.1", (2 * U)) V.lf = E"@lf*@leafc"
  elseif R.mk < K"0.6" then V.what = U V.usc = range(K"0.7", K"0.9") V.ulate = R.late
  elseif R.mk < K"0.82" then V.what = 2 * U
  elseif R.climb == U then V.what = 3 * U
  else V.what = U V.usc = K"0.6" V.ulate = E"@late+0.1" end
  V.best = (2 * U)
  loop("#Gd", 1, 3, function()
    V.t = range(K"1.4", K"3.2") V.cd = E"@t*(1-0.25*@u)"
    V.t = range(25 * U, 75 * U) V.cg = E"90+@side*@t"
    V.cbx = E"max(@pxmin,min(@pxmax,@nx-@cd*cos(@cg)))"
    V.cby = E"@nyy+@cd*sin(@cg)"
    V.cax = E"@cbx-@nx" V.cay = E"@cby-@nyy" V.t = pm.veclen(R.cax, R.cay)
    V.cax = E"@cax/@t" V.cay = E"@cay/@t+0.6" V.t = pm.veclen(R.cax, R.cay)
    V.cax = E"@cax/@t" V.cay = E"@cay/@t" V.caa = pm.atan2(R.cay, R.cax)
    local what = I("what")
    if what == 1 then unitdisc(R.cbx, R.cby, R.caa, R.usc)
    elseif what == 2 then V.udx = E"@cbx+0.35*@cax" V.udy = E"@cby+0.35*@cay" V.udr = K"0.5"
    elseif what == 3 then V.udx = R.cbx V.udy = R.cby V.udr = K"0.35"
    elseif what == 4 then
      V.udx = E"@cbx+0.5*@lf*@cax" V.udy = E"@cby+0.5*@lf*@cay" V.udr = E"0.32*@lf"
    end
    takenat(R.udx, R.udy, R.udr)
    if R.taken < R.best then
      V.best = R.taken V.bx = R.cbx V.by = R.cby
      V.ax = R.cax V.ay = R.cay V.a = R.caa
      V.bdx = R.udx V.bdy = R.udy V.bdr = R.udr
    end
  end)
  if R.best < K"0.3" then branchto() end
end
local function passbranches()
  stemload()
  V.nnodes = R["nd@n" .. R["#Ga"]] * U
  loop("#Ge", 1, function() return I("nnodes") end, function()
    local nd = R["nd@" .. R["#Ga"] .. "@" .. R["#Ge"]]
    V.ny = nd[1] V.side = nd[2]
    nodeat()
    V.t = rnd() V.t = E"@t<(#Ge==1 ? 0.35 : 0.85) ? 1 : 0"
    if R.t > K"0.5" then branch() end
  end)
end
local function passfill()
  stemload() V.filling = U
  loop("#Ge", 1, function() return I("ftries") end, function()
    V.ny = range(K"0.12", K"0.93") V.ny = E"@ny*@pH"
    if chance(K"0.5") then V.side = U else V.side = -U end
    nodeat() branch()
  end)
  V.filling = 0
end

-- ---------------------------------------------------------------- the species
-- \florilegiumspecies{seed}{role}: the traits into the store, the generator where the
-- sampler left it
local function traitval(v)
  if type(v) ~= "number" then return v end
  if math.type(v) == "integer" then return v * U end
  return math.floor(v * U + 0.5)
end
function florilegiumspecies(seed, role)
  local s, r = species.sample(seed, role)
  rng.load(r.save())
  V["v@seed"] = seed V["v@role"] = role V["v@plan"] = s.plan
  for i = 2, #species.TRAITS do
    local t = species.TRAITS[i]
    V["v@" .. t] = traitval(s[t])
  end
end

-- ---------------------------------------------------------------- the garden
-- \flo@garden: the plants pp 1..Np from one root, walked once per layer
local function garden()
  out("\\pgfsetroundcap\\pgfsetroundjoin")
  scale(K"28.45276")
  V.season = R["o@season"]
  M.gardens = (M.gardens or 0) + 1
  drawseed(R["pp@s1"])
  local np = R["#Np"]
  loop("#Ga", 1, function() return R["#Np"] end, function()
    local ga = R["#Ga"]
    if ga == 1 then V.t = U
    elseif ga == 2 then V.t = range(K"0.6", K"0.72")
    elseif ga == 3 then V.t = range(K"0.36", K"0.48")
    else V.t = range(K"0.5", K"0.58") end
    V.t = E"@gH*@t" V["pp@H" .. ga] = R.t
    seedorgan() V["pp@z" .. ga] = R.os
  end)
  V.gx = range(K"0.35", K"0.65") V.gx = E"@gW*(@gx-0.5)"
  V.gy = range(K"0.15", K"0.3") V.gy = E"@gH*@gy" V.gdiam = range(K"2.6", K"3.2")
  seedorgan() V.gos = R.os
  V.pxmin = E"-@gW/2+0.7" V.pxmax = E"@gW/2-0.7"
  if np == 1 then V.pA = K"0.5" else V.pA = E"0.2*@gW" end
  loop("#Gc", 1, 5, function()
    V.layer = R["#Gc"] * U V.roomid = M.gardens .. "." .. R["#Gc"]
    loop("#Ga", 1, function() return R["#Np"] end, function()
      V["pp@w" .. R["#Ga"]] = R["pp@z" .. R["#Ga"]]
    end)
    if R.gghost == "true" then
      V.t = E"0.25*@gdiam" room(1, R.gx, R.gy, R.t)
      if R["#Gc"] == 1 then
        florilegiumspecies(R["pp@s1"], R["pp@r1"]) V.os = R.gos
        -- a plain flower of the species, as v1.3's ghosts are: no daisy disk, no lily
        organ(function()
          V.lift = K"0.62" shift(R.gx, R.gy) stone()
          V["v@form"] = "rotate"
          if tr("merosity") > 6 * U then V["v@merosity"] = 5 * U end
          scale(R.gdiam) V.t = E"@gdiam*28.45276" sflower(R.t)
        end)
      end
    end
    loop("#Ga", 1, function() return R["#Np"] end, function() plantsetup() passstem() plantsave() end)
    loop("#Ga", 1, function() return R["#Np"] end, function() plantsetup() passleaves() plantsave() end)
    loop("#Ga", 1, function() return R["#Np"] end, function() plantsetup() passbranches() plantsave() end)
    loop("#Gb", 1, 3, function()
      loop("#Ga", 1, function() return R["#Np"] end, function()
        plantsetup() V.ftries = pm.int(E"@pH/2") passfill() plantsave()
      end)
    end)
  end)
end

-- ---------------------------------------------------------------- pics
-- a fresh state, as at the start of a pic (its group undoes what the last one did)
local function reset()
  for k in pairs(R) do R[k] = nil end
  level, saves = 0, {}
  for _, t in ipairs({ X, Y, A, B, C, D, NX, NY, RX, RY, QX, QY, S, T.TX, T.TY, T.MX, T.MY, T.MU, T.MV,
    T.AX, T.AY, T.AN, T.AM, T.O, T.VEIN, T.Z, KEPT, ROOM, G[1], G[2], G[3] }) do
    for k in pairs(t) do t[k] = nil end
  end
  R.lift = 0 R.zero = 0 R["vp@notchp"] = K"0.4" R["vp@notchk"] = U
  R["vf@star"] = "" R["vf@tone"] = "" R.rampname = "flo@ramp" R.layer = 0 R.filling = 0 R.bside = "" R.bfan = 0 R.ivc = 0 R.ivpt = 0
  OUT = {}
end
-- \flo@picsetup: the species, then the drawing's own stream (draw=, or the seed + 1)
local function picsetup(o)
  florilegiumspecies(o.seed, o.role or "any")
  local d = o.draw or (o.seed == 2147483646 and 1 or o.seed + 1)
  drawseed(d)
end
local function sizecm(pt) return pm.div(pt, K"28.45276") end

-- The pics of the TikZ library, as the pgf code they run. Lengths in sp, as TeX holds
-- them. o: seed, role, draw (optional), size; for an inflorescence, scale and season (sp);
-- for plants, plants = { {seed, role}, ... },
-- width, season (sp), ghost (boolean). Returns a list of strings.
function M.pic(kind, o)
  reset()
  if kind == "flower" then
    picsetup(o) scale(o.size) stone() sflower(o.size)
  elseif kind == "leaf" then
    picsetup(o) scale(o.size) leaf(o.size)
  elseif kind == "v13 flower" then
    picsetup(o) scale(o.size) V["vf@tone"] = "" V.vs = sizecm(o.size) vflower(R.vs, 5 * U)
  elseif kind == "v13 leaf" then
    picsetup(o) scale(o.size)
    V["vl@W"] = "" V["vl@bend"] = "" V["vl@lobes"] = "" V["vl@depth"] = "" V["vl@tone"] = ""
    V["vl@u"] = sizecm(o.size) vleaf()
  elseif kind == "inflorescence" then
    picsetup(o)
    out("\\pgfsetroundcap\\pgfsetroundjoin") scale(K"28.45276")
    kindof() V.season = o.season V.ulate = 0
    V.t = sym(K"0.08") V.ust = E"1.2*@season-@ulate+@t+$phenology"
    unitdraw(o.scale)
  elseif kind == "plant" then
    picsetup(o)
    V["#Np"] = 1 V["pp@s1"] = o.seed V["pp@r1"] = o.role or "any"
    V.gH = sizecm(o.size) V.gghost = "false"
    V.gW = sizecm(o.width) V["o@season"] = o.season or K"0.75"
    garden()
  elseif kind == "plants" then
    V["#Np"] = #o.plants
    for k, p in ipairs(o.plants) do V["pp@s" .. k] = p[1] V["pp@r" .. k] = p[2] end
    V.gH = sizecm(o.size) V.gW = sizecm(o.width) V.gghost = o.ghost == false and "false" or "true"
    V["o@season"] = o.season or K"0.75"
    garden()
  else
    error("florilegium-organs: no pic " .. tostring(kind))
  end
  assert(level == 0, "florilegium-organs: a group left open")
  return OUT
end

do
-- a number the TikZ library would read with pgfmath (a seed, a season)
local function value(text)
  local ok, v = pcall(pm.sp, text)
  if ok then return v end
  return compile(text)({}, {})
end
-- The library and these files are found one by one (a set in ~/texmf, newer files beside
-- the document), so the first pic checks that they come from one release.
local checked = false
local function check(lib)
  checked = true
  local v = lib and lib:match("v(%d[%d.]*)")
  if not v then return end
  for _, m in ipairs({ { "florilegium-organs", M.version }, { "florilegium-pgfmath", pm.version },
    { "florilegium-species", species.version }, { "florilegium-ink", ink.version } }) do
    if m[2] ~= v then
      error(string.format("florilegium: %s.lua is from %s, tikzlibraryflorilegium.code.tex from release %s. "
        .. "Copy the library and every florilegium*.lua from one release.", m[1],
        m[2] and ("release " .. m[2]) or "an earlier release", v), 0)
    end
  end
end
-- \flo@luapic: the pic with the keys as TeX holds them (lengths in sp), written into the
-- picture as partial lines (no spaces between commands); lib the library's \ProvidesFile
function M.tex(kind, seed, role, draw, size, width, season, plants, ghost, scale, lib)
  if not checked then check(lib) end
  local o = { role = role, size = size, width = width, season = value(season), ghost = ghost ~= "false",
    scale = value(scale) }
  o.seed = pm.int(value(seed)) // U
  if draw ~= "" then o.draw = pm.int(value(draw)) // U end
  if kind == "plants" then
    o.plants = {}
    for item in plants:gmatch("[^,]+") do
      local s, r = item:match("^%s*(.-)%s*/%s*(.-)%s*$")
      o.plants[#o.plants + 1] = { pm.int(value(s)) // U, r }
    end
  end
  -- with @ a letter (LaTeX's catcode table), as the library's own code reads: \flo@upright
  local cct = luatexbase and luatexbase.registernumber and luatexbase.registernumber("catcodetable@atletter")
  if cct then tex.sprint(cct, M.pic(kind, o)) else tex.sprint(M.pic(kind, o)) end
end
end

-- ================================================================ the margin
-- florilegium-grow.lua grows a species page in Lua and paints it with ink, as it paints
-- everything else: one transform stack, one color ramp (the document's ink, intensity,
-- copper headings), one output for the PDF and for florilegium-svg.lua. An organ is
-- computed exactly as its pic (the pgf code above), then read back and painted, so a
-- margin's plants are the pics' plants to ink's precision (0.1 bp), not to the byte.

-- \flo@unitdisc in Lua's numbers, for the layout (no TikZ twin): the disc an
-- inflorescence at scale k fills, as the offset of its center along the axis and its
-- radius, in cm; and its kind (solitary, blossoms, umbel, raceme)
function M.unitdisc(s, k)
  local kind = KIND[s.inflo] or "blossoms"
  local fd = math.min(2.8, 0.7 + 0.032 * s.size) * k
  if kind == "umbel" then return 0.69 * k, 0.86 * k, kind end
  if kind == "raceme" then return 0.95 * k, 0.75 * k, kind end
  if kind == "blossoms" then return 0.5 * fd, 0.8 * fd, kind end
  if kind == "head" then return 0.8 * k, 0.5 * k, kind end
  if kind == "catkin" then return 0.2 * k, 0.9 * k, kind end
  return 0, 0.5 * fd, kind
end
-- \flo@lateness: how much later than the top an inflorescence at height h (0..1) opens
function M.lateness(s, h) return BELOW[s.inflo] and 0.4 * h or 0.4 * (1 - h) end

local function fx(x) return math.floor(x * U + 0.5) end      -- a Lua number as TeX holds it
-- one organ of species s (a table from florilegium-species: seed, role), from pgf seed z,
-- at the origin with its axis along +y, in cm. o by kind:
--   unit     k (scale), season, late: the inflorescence (\flo@unit without its room)
--   budding  k: buds on stalks       tendril  size     bloom  d (diameter cm), stage
--   leaf     len (cm), bend, lc (0..1, the autumn draw), season
--   ghost    d: a plain pale flower of the species, as the garden's ghost
local function organ(kind, s, z, o)
  reset()
  florilegiumspecies(s.seed, s.role)
  drawseed(z)
  local function body()
    if kind == "unit" then
      kindof() V.season = fx(o.season) V.ulate = fx(o.late)
      V.t = sym(K"0.08") V.ust = E"1.2*@season-@ulate+@t+$phenology"
      unitdraw(fx(o.k))
    elseif kind == "budding" then
      fdiam(fx(o.k)) V.fd = E"min(1.1,@fd)" budding(R.fd)
    elseif kind == "tendril" then
      rotate(90 * U) vtendril(fx(o.size))
    elseif kind == "bloom" then
      bloom(fx(o.d), fx(o.stage))
    elseif kind == "leaf" then
      V.lf = fx(o.len) V.sbend = fx(o.bend) V.lc = fx(o.lc) V.season = fx(o.season)
      scale(R.lf) autumnleaf()
      V.t = E"@lf*28.45276" leaf(R.t)
    elseif kind == "ghost" then
      V.gdiam = fx(o.d) V.lift = K"0.62" stone()
      V["v@form"] = "rotate"
      if tr("merosity") > 6 * U then V["v@merosity"] = 5 * U end
      scale(R.gdiam) V.t = E"@gdiam*28.45276" sflower(R.t)
    else
      error("florilegium-organs: no organ " .. tostring(kind))
    end
  end
  scope(body)
  assert(level == 0, "florilegium-organs: a group left open")
  return concat(OUT)
end
M.organ = organ                   -- the code itself, for tests

-- the pgf code read back and painted with ink, under ink's current transform: a point
-- (pt in the code) is a cm; line widths stay absolute
local KAPPA, PT_BP = 0.55228475, 72 / 72.27
local BLACK = { 0, 0, 0 }
local function paint(code)
  code = code:gsub("\\pgfqpoint{(%-?[%d.]+)pt}{(%-?[%d.]+)pt}", "%1 %2")
  local st = { fill = BLACK, fop = 1, stroke = BLACK, sop = 1, w = 0.4 * PT_BP, mult = false, colors = {}, clips = 0 }
  local stack, aramp = {}, {}
  local function color(spec)
    local c = st.colors[spec]
    if c then return c end
    local n = spec:match("^flo@ramp@(%d+)$")
    if n then return ink.tone(tonumber(n) / 100) end
    n = spec:match("^flo@aramp@(%d+)$")
    if n then
      c = aramp[n]
      if not c then ink.in_accent(function() c = ink.tone(tonumber(n) / 100) end) aramp[n] = c end
      return c
    end
    local p, mix = spec:match("^flo@accent!([%d.]+)!(%a+)$")
    if p then
      local k = 1 - tonumber(p) / 100
      return ink.accent(mix == "black" and -k or k)
    end
    if spec == "white" then return ink.white end
    if spec == "black" then return BLACK end
    error("florilegium-organs: no color '" .. spec .. "'")
  end
  local function nums(a)
    local t = {}
    for v in a:gmatch("%-?[%d.]+") do t[#t + 1] = tonumber(v) end
    return t
  end
  for name, a in code:gmatch("\\([%a@]+)([^\\]*)") do
    if name == "pgfpathcurveto" then
      local v = nums(a) ink.curveto(v[1], v[2], v[3], v[4], v[5], v[6])
    elseif name == "pgfpathlineto" then
      local v = nums(a) ink.lineto(v[1], v[2])
    elseif name == "pgfpathmoveto" then
      local v = nums(a) ink.moveto(v[1], v[2])
    elseif name == "pgfpathclose" then ink.close()
    elseif name == "begin" then
      ink.push()
      local c = {}
      for k, v in pairs(st.colors) do c[k] = v end
      stack[#stack + 1] = st
      st = { fill = st.fill, fop = st.fop, stroke = st.stroke, sop = st.sop, w = st.w, mult = st.mult, colors = c, clips = 0 }
    elseif name == "end" then
      for _ = 1, st.clips do ink.unclip() end
      st = table.remove(stack)
      ink.pop()
    elseif name == "colorlet" then
      local k, spec = a:match("^{([^}]*)}{([^}]*)}")
      st.colors[k] = color(spec)
    elseif name == "pgfusepath" then
      local how = a:match("{([^}]*)}")
      if how == "fill" then ink.fill(st.fill, st.fop, st.mult)
      elseif how == "stroke" then ink.stroke(st.stroke, st.w, st.sop, st.mult)
      elseif how == "clip" then ink.clip() st.clips = st.clips + 1
      else error("florilegium-organs: no path use '" .. tostring(how) .. "'") end
    elseif name == "pgfsetfillcolor" then st.fill = color(a:match("{([^}]*)}"))
    elseif name == "pgfsetstrokecolor" then st.stroke = color(a:match("{([^}]*)}"))
    elseif name == "pgfsetfillopacity" then st.fop = nums(a)[1]
    elseif name == "pgfsetstrokeopacity" then st.sop = nums(a)[1]
    elseif name == "pgfsetblendmode" then st.mult = a:match("{([^}]*)}") == "multiply"
    elseif name == "pgfsetlinewidth" then
      local v, unit = a:match("{(%-?[%d.]+)(%a%a)}")
      st.w = tonumber(v) * (unit == "pt" and PT_BP or 1)
    elseif name == "pgftransformshift" then local v = nums(a) ink.translate(v[1], v[2])
    elseif name == "pgftransformrotate" then ink.rotate(nums(a)[1])
    elseif name == "pgftransformscale" then ink.scale(nums(a)[1])
    elseif name == "pgftransformyscale" then ink.scale(1, nums(a)[1])
    elseif name == "pgftransformxscale" then ink.scale(nums(a)[1], 1)
    elseif name == "flo@upright" then                      -- \flo@upright: +y up on the page
      local t = ink.get_transform()
      local p, q = math.sqrt(t[1] * t[1] + t[2] * t[2]), math.sqrt(t[3] * t[3] + t[4] * t[4])
      local s = math.sqrt(p) * math.sqrt(q)
      ink.set_transform({ (t[1] / p) * (t[4] / q) - (t[2] / p) * (t[3] / q) < 0 and -s or s, 0, 0, s, t[5], t[6] })
    elseif name == "pgfpathcircle" then
      local v = nums(a) ink.circle(v[1], v[2], v[3])
    elseif name == "pgfpathellipse" then
      local v = nums(a)                                      -- center, first axis, second axis
      local cx, cy, ax, ay, bx, by, k = v[1], v[2], v[3], v[4], v[5], v[6], KAPPA
      ink.moveto(cx + ax, cy + ay)
      ink.curveto(cx + ax + k * bx, cy + ay + k * by, cx + bx + k * ax, cy + by + k * ay, cx + bx, cy + by)
      ink.curveto(cx + bx - k * ax, cy + by - k * ay, cx - ax + k * bx, cy - ay + k * by, cx - ax, cy - ay)
      ink.curveto(cx - ax - k * bx, cy - ay - k * by, cx - bx - k * ax, cy - by - k * ay, cx - bx, cy - by)
      ink.curveto(cx - bx + k * ax, cy - by + k * ay, cx + ax - k * bx, cy + ay - k * by, cx + ax, cy + ay)
      ink.close()
    elseif name == "pgfpathrectanglecorners" then
      local v = nums(a)
      ink.poly({ { v[1], v[2] }, { v[3], v[2] }, { v[3], v[4] }, { v[1], v[4] } }, true)
    elseif name == "pgfsetroundcap" or name == "pgfsetroundjoin" then  -- ink's caps and joins are round
    else
      error("florilegium-organs: ink cannot paint \\" .. name)
    end
  end
  assert(#stack == 0, "florilegium-organs: a scope left open")
end

-- draw an organ (see organ() above) with ink. With M.keep set (the growth animation
-- paints every motif several times), each organ's code is computed once per page.
M.keep = false
local kept_code = {}
function M.forget() kept_code = {} end
function M.draw(kind, s, z, o)
  local code
  if M.keep then
    local key = table.concat({ kind, s.seed, s.role, z, tostring(o.k), tostring(o.season), tostring(o.late), tostring(o.size),
      tostring(o.d), tostring(o.stage), tostring(o.len), tostring(o.bend), tostring(o.lc) }, " ")
    code = kept_code[key]
    if not code then code = organ(kind, s, z, o) kept_code[key] = code end
  else
    code = organ(kind, s, z, o)
  end
  paint(code)
end

return M
