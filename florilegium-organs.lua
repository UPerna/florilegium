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
local level, saves, saved = 0, {}, {}
-- an assignment, undone at the end of the current group (TeX's save stack). As in TeX, a
-- name is saved once per group, with the value it had before the group's first assignment
-- (saved[level][t][k] marks it); later assignments in the group need no entry
local function setv(t, k, v)
  if level > 0 then
    local m = saved[level]
    local mt = m[t]
    if not mt then mt = {} m[t] = mt end
    if not mt[k] then
      mt[k] = true
      local s = saves[level]
      local o = t[k]
      s[#s + 1] = t s[#s + 1] = k s[#s + 1] = (o == nil) and NIL or o
    end
  end
  t[k] = v
end
local V = setmetatable({}, { __index = R, __newindex = function(_, k, v) setv(R, k, v) end })
local function begingroup() level = level + 1 saves[level] = {} saved[level] = {} end
local function endgroup()
  local s = saves[level]
  for i = #s - 2, 1, -3 do
    local o = s[i + 2]
    if o == NIL then o = nil end
    s[i][s[i + 1]] = o
  end
  saves[level], saved[level] = nil, nil
  level = level - 1
end
-- \xdef: no group end undoes it (and a later local assignment in a group saves the new
-- value again, so its entries go and its marks with them)
local function gset(k, v)
  for l = 1, level do
    local mt = saved[l][R]
    if mt and mt[k] then
      mt[k] = nil
      local s = saves[l]
      for i = 1, #s, 3 do if s[i] == R and s[i + 1] == k then s[i] = DEAD end end
    end
  end
  R[k] = v
end

-- arrays of macros (\flo@X<i>, \flo@A<i> ...), assigned through setv as well
local X, Y, A, B, C, D = {}, {}, {}, {}, {}, {}
local NX, NY, RX, RY, QX, QY, S = {}, {}, {}, {}, {}, {}, {}
local G = { {}, {}, {} }          -- \flo@G<k>@<i>, the noise gradients
local T = { TX = {}, TY = {}, MX = {}, MY = {}, MU = {}, MV = {},   -- the rarer ones (Lua's
  AX = {}, AY = {}, AN = {}, AM = {}, O = {}, VEIN = {}, Z = {}, FX = {}, FY = {} }   -- 200 locals)
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
-- (M8f1 prototype) with M.stream set, each piece of code is painted as it is written
local function out(s) local st = M.stream if st then st(s) else OUT[#OUT + 1] = s end end
-- (M8f1 prototype) with M.nv set (florilegium-native.lua), the petals and the face-on
-- flowers are drawn by it instead: the same draws, in floats, straight to ink
function M.nvpen()
  local nv = M.nv
  nv.pen.lift = R.lift / U nv.pen.accent = R.rampname == "flo@aramp"
  -- the species, sampled again (once) from its seed and role; the ghost's changes kept
  local key = R["v@seed"] .. "/" .. R["v@role"]
  local s = M.nvcache[key]
  if not s then s = species.sample(R["v@seed"], R["v@role"]) M.nvcache[key] = s end
  if R["v@form"] ~= s.form or R["v@merosity"] ~= s.merosity * U then
    local c = {}
    for k, v in pairs(s) do c[k] = v end
    c.form, c.merosity = R["v@form"], R["v@merosity"] // U
    s = c
  end
  nv.species(s)
  return nv
end
M.nvcache = {}
function M.nvval(v, whole) if v == nil or v == "" then return nil end if whole then return v // U end return v / U end
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
  if M.stream then
    local val = M.nvval
    return M.nvpen().petal({ pointed = R["vp@pointed"] == U, W = val(R["vp@W"]), bend = val(R["vp@bend"]),
      tone = R["vp@tone"] / U, ns = val(R["vp@ns"], true), heart = R["vp@heart"] == U, u = R["vp@u"] / U,
      notchp = R["vp@notchp"] / U, notchk = R["vp@notchk"] / U })
  end
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
  -- a petal under 1.2 mm (vp@u in cm) is tiny: a coarser outline, no heart, mottle or
  -- pooled rim (specks no printer resolves at that size), and at most five streaks
  if R["vp@u"] < K"0.12" then V.tiny = U else V.tiny = 0 end
  if R["vp@u"] > K"0.5" then V.bn = 28 * U elseif R.tiny == U then V.bn = 8 * U else V.bn = 18 * U end
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
    if R["vp@heart"] == U and R.tiny == 0 then
      loop("#ka", 1, 8, function()
        V.t = E"@pW*(0.25+0.1*#ka)" V.ms = E"0.06+0.065*#ka"
        vblob(0, 0, R.t, R.ms, K"0.28", 9) vfill("white", K"0.1", 0, smoothpath)
      end)
    end
    V.xa = E"-@pW*1.2" V.xb = E"@pW*1.2"
    V.ta = E"@tz-0.2" V.tb = E"@tz+0.2"
    if R["vp@pointed"] == U then V.msz = K"0.06" else V.msz = K"0.12" end
    if R.fine == U then vmottle("xa", K"0.12", "xb", K"1.05", 15, R.msz, R.ta, R.tb, 12)
    elseif R.tiny == 0 then vmottle("xa", K"0.12", "xb", K"1.05", 6, R.msz, R.ta, R.tb, 0) end
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
    if R.tiny == 0 then vtone("flo@c", K"0.08") V.t = E"1.6*@vp@u" vstroke("flo@c", R.t, K"0.3", 1, outlinepath) end
    -- white streaks lifted out, fanning from the base
    if R["vp@ns"] == "" then
      if R["vp@pointed"] == U then V.ns = int(3, 5) else V.ns = int(9, 13) end
    else V.ns = R["vp@ns"] end
    if R.tiny == U and R.ns > 5 * U then V.ns = 5 * U end
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
  if M.stream then
    local val = M.nvval
    return M.nvpen().flower(u / U, n // U, { pointed = R["vf@pointed"] == U, tone = val(R["vf@tone"]),
      W = val(R["vf@W"]), ns = val(R["vf@ns"], true), notchp = R["vp@notchp"] / U, notchk = R["vp@notchk"] / U })
  end
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
local function lspine_(v)                -- \flo@lspine@#1 -> \flo@sx, \flo@sy
  V.sx = E("@lbend*(%1)*(%1)-0.3*@lbend*(%1)", { v }) V.sy = v
end
local function lspine(v)                 -- \flo@lspine#1: along a curled tip's circle beyond \flo@hv
  if R.hk == U and v > R.hv then
    V.hph = E("((%1)-@hv)/@hl*@hth", { v })
    V.sx = E"@hpx+@hr*(sin(@hph)*@htx+(1-cos(@hph))*@hnx)"
    V.sy = E"@hpy+@hr*(sin(@hph)*@hty+(1-cos(@hph))*@hny)"
  else lspine_(v) end
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
  if M.stream then
    local star = R["vf@star"]
    if star == "" then star = nil else star = star == U end
    return M.nvpen().floret(r / U, n // U, { star = star, tone = M.nvval(R["vf@tone"]) })
  end
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
  if M.stream then return M.nvpen().bud(u / U, M.nvval(R["vf@tone"])) end
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
  if M.stream then
    return M.nvpen().daisy(d / U, tr("merosity") // U, { tone = M.nvval(R["vf@tone"]),
      notchp = R["vp@notchp"] / U, notchk = R["vp@notchk"] / U })
  end
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
  if M.stream then
    return M.nvpen().sflower(d / U, { tone = M.nvval(R["vf@tone"]), notchp = R["vp@notchp"] / U, notchk = R["vp@notchk"] / U })
  end
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
  if M.stream then return M.nvpen().boss(tr("stamens") == "exserted") end
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
-- ---------------------------------------------------------------- the species' leaf
-- in a block of its own: the main chunk is near Lua's 200 locals
local sleaf, compoundleaf
do
-- \flo@sshape: the outline's numbers, the base first, then the shape (which may fix the
-- base), then the apex (\flo@lb@..., \flo@ls@..., \flo@la@...)
local LBASE = {
  cuneate = function() V.lkb = K"1.15" end,
  rounded = function() V.lkb = 2 * U end,
  truncate = function() V.lkb = K"3.5" end,
  cordate = function() V.lkb = 2 * U V.ldrop = U end,
  auriculate = function() V.lkb = K"1.5" end,
  oblique = function() V.lkb = K"1.8" V.lobl = K"0.08" end,
}
local LSHAPE = {
  linear = function() V.lvm = K"0.45" V.lkb = E"max(@lkb,2.2)" end,
  lanceolate = function() V.lvm = K"0.3" end,
  elliptic = function() V.lvm = K"0.5" end,
  ovate = function() V.lvm = K"0.3" end,
  obovate = function() V.lvm = K"0.68" end,
  oblong = function() V.lvm = K"0.5" V.lkb = E"max(@lkb,2.4)" end,
  orbicular = function() V.lvm = K"0.5" V.lkb = 2 * U V.lround = U end,
  cordate = function() V.lvm = K"0.3" end,
  reniform = function() V.lvm = K"0.42" V.lkb = 2 * U V.ldrop = K"0.8" V.lround = U end,
  deltoid = function() V.lvm = K"0.1" V.lkb = K"3.5" end,
  sagittate = function() V.lvm = K"0.32" V.lkb = K"1.8" V.ldrop = 2 * U end,
  hastate = function() V.lvm = K"0.38" V.lkb = K"1.7" V.lhl = K"1.05" V.ldrop = K"0.2" end,
}
local LAPEX = {
  acute = function() V.lka = K"1.25" end,
  acuminate = function() V.lka = K"1.5" V.lacu = U end,
  obtuse = function() V.lka = 2 * U end,
  rounded = function() V.lka = K"2.6" end,
  emarginate = function() V.lka = K"2.6" V.ltip = -U end,
  mucronate = function() V.lka = K"2.3" V.ltip = U end,
}
-- \flo@sshape@ (a leaflet's: no attachment)
local function sshape_()
  V.lW = E"max(0.035,min(0.6,0.5/$leafaspect))"
  V.lvm = K"0.35" V.ldrop = 0 V.lhl = 0 V.lobl = 0 V.lacu = 0 V.ltip = 0 V.lround = 0
  LBASE[tr("leafbase")]() LSHAPE[tr("leafshape")]() LAPEX[tr("leafapex")]()
  -- a round or kidney-shaped blade keeps a round tip whatever its apex
  if R.lround == U then V.lka = E"max(@lka,2.2)" V.lacu = 0 end
end
local function sshape()
  sshape_()
  if tr("attachment") == "clasping" and R.ldrop == 0 then V.ldrop = K"0.7" V.lkb = E"max(@lkb,2)" end
end
-- \flo@shw#1: the blade's half-width \flo@h at v along the spine, and the drop \flo@dy
local function shw(v)
  V.shv = v
  if R.shv < R.lvm then
    V.t = E"(@lvm-(@shv))/@lvm"
    if R.t > K"0.9995" then V.h = 0 else V.h = E"@lW*pow(1-pow(@t,@lkb),1/@lkb)" end
    V.dy = E"@ldrop*@lW*sin(180*(1-@t))*@t"
  else
    V.t = E"((@shv)-@lvm)/(1-@lvm)"
    if R.t > K"0.9995" then V.h = 0 else V.h = E"@lW*pow(1-pow(@t,@lka),1/@lka)" end
    if R.lacu == U and R.t > K"0.2" then
      V.t = E"min(1,(@t-0.2)/0.65)" V.h = E"@h*(1-0.7*@t*@t*(3-2*@t))"
    end
    V.dy = 0
  end
  if R.lhl > 0 then
    V.t = E"max(0,1-abs((@shv)-0.11)/0.11)"
    if R.t > 0 then V.h = E"max(@h,@lhl*@lW*@t)" end
  end
end
local function slenv(v) shw(v) V.env = R.h end
-- \flo@smargin: the body's margin samples {v, profile, left scale, right scale} in MS[1..MS.n]
local MS = { n = 0 }
local function sadd(v, d, jl, jr) MS.n = MS.n + 1 MS[MS.n] = { v, d, jl, jr } end
local LMARGIN = {
  undulate = function() V.lmk = U end,
  serrate = function() V.lmk = 2 * U V.ltk = K"0.5" V.ltd = K"1.2" end,
  doubly = function() V.lmk = 2 * U V.ltk = K"0.5" V.ltd = K"1.3" end,
  dentate = function() V.lmk = 2 * U V.ltk = K"0.5" V.ltd = K"1.3" end,
  crenate = function() V.lmk = 2 * U V.ltd = K"1.5" end,
}
local TOOTH = {                   -- \flo@lt@...: each point's phase and profile
  serrate = { { "0", 0 }, { "0.75+@jp", U } },
  doubly = { { "0", 0 }, { "0.38", K"0.55" }, { "0.52", K"0.3" }, { "0.82+@jp", U } },
  dentate = { { "0", 0 }, { "0.5+@jp", U } },
  crenate = { { "0", 0 }, { "0.2", K"0.72" }, { "0.5+@jp", U }, { "0.8", K"0.72" } },
}
local function smargin()
  V.lmk = 0 MS.n = 0 V.ltk = K"0.8" V.ldep = 0 V.lmn = tr("leafmargin")
  if R.lmover and R.lmover ~= "" then V.lmn = R.lmover end
  if R.ldepth <= 0 and LMARGIN[R.lmn] then LMARGIN[R.lmn]() end
  if R.lmk < 2 * U then
    if R.lmk == U then V.lwn = int(3, 5) V.ldep = E"(0.05+$dissection)*@lW*2.4" end
    loop("#kb", 0, I("bn"), function()
      V.v = E"0.5-0.5*cos(180*#kb/@bn)"
      if R.lmk == U then V.t = E"0.5+0.5*sin(360*@lwn*@v)" else V.t = U end
      sadd(R.v, R.t, U, U)
    end)
  else
    if R.lmover and R.lmover ~= "" then V.ldep = E"min(0.25,$dissection)*@lW*@ltd"
    else V.ldep = E"$dissection*@lW*@ltd" end
    V.t = E"min($teeth,max(4,round(4+8*@vl@u)))" V.ltn = pm.int(R.t)
    V.tw = E"0.81/@ltn"
    loop("#kb", 0, 4, function() V.v = E"0.12*(1-cos(90*#kb/5))" sadd(R.v, U, U, U) end)
    loop("#ka", 1, I("ltn"), function()
      V.jl = range(K"0.65", K"1.35") V.jr = range(K"0.65", K"1.35") V.jp = sym(K"0.06")
      V.tvo = E"0.12+@tw*(#ka-1)"
      for _, pt in ipairs(TOOTH[R.lmn]) do V.t = E("@tvo+@tw*(" .. pt[1] .. ")") sadd(R.t, pt[2], R.jl, R.jr) end
    end)
    sadd(K"0.93", 0, U, U)
    loop("#kb", 1, 5, function() V.v = E"0.93+0.07*sin(90*#kb/5)" sadd(R.v, U, U, U) end)
  end
  V.mn = MS.n * U
end
-- \flo@sblade: the blade along +y, length 1 (\flo@vleaf with the species' outline)
-- \flo@hookset: a curled tip, its spine turning \flo@hth degrees along a circle beyond
-- \flo@hv toward the side the leaf bends, as tight as the blade allows; none under 35
local function hookset()
  V.hl = range(K"0.25", K"0.4") V.hv = E"1-@hl" shw(R.hv)
  V.t = range(120 * U, 190 * U) V.hth = E"min(@t,@hl/(1.8*max(0.01,@h))*57.29578)"
  if R.hth > 45 * U then
    V.hk = U
    if R.lbend < 0 then V.hs = -U else V.hs = U end
    lspine_(R.hv) V.hpx = R.sx V.hpy = R.sy
    V.htx = E"2*@lbend*@hv-0.3*@lbend" V.t = E"veclen(@htx,1)"
    V.htx = E"@htx/@t" V.hty = E"1/@t"
    V.hnx = E"@hs*@hty" V.hny = E"-@hs*@htx"
    V.hr = E"@hl/@hth*57.29578"
  end
end
-- \flo@hookunder: the curl's underside, the blade from just past its middle to the tip,
-- drawn again from the same margin samples, paler
local function hookunder()
  V.hva = E"@hv+0.45*@hl" V.hka = 0
  local mn = MS.n
  loop("#kb", 1, mn, function()
    if R.hka == 0 and MS[R["#kb"]][1] > R.hva then V.hka = R["#kb"] * U end
  end)
  local ka = I("hka")
  if ka > 1 and ka < mn then
    V.hun = 0
    loop("#kb", ka, mn, function() V.hun = R.hun + U put(I("hun"), RX[R["#kb"]], RY[R["#kb"]]) end)
    loop("#kb", 1, mn - ka, function()
      V.hun = R.hun + U V.q = (mn - R["#kb"]) * U
      put(I("hun"), QX[I("q")], QY[I("q")])
    end)
    smoothprepT(I("hun"), R.ltk) keep("lsu")
    V.t = E"min(0.64,@lt+0.26)" vtone("flo@c", R.t) vfill("flo@c", U, 0, function() kept("lsu") end)
    scope(function()
      kept("lsu") usepath("clip")
      loop("#kb", 0, 10, function()
        V.v = E"@hva+(1-@hva)*#kb/10" lspine(R.v) put(R["#kb"] + 1, R.sx, R.sy)
      end)
      vstreak(11, K"0.02", K"0.003", "white", K"0.6")
      vtone("flo@c", K"0.06") V.t = E"1.3*@vl@u" vstroke("flo@c", R.t, K"0.3", 1, function() kept("lsu") end)
    end)
  end
end
local function sblade()
  if R["vl@bend"] == "" then V.lbend = sym(K"0.25") else V.lbend = R["vl@bend"] end
  V.llobes = R["vl@lobes"] V.ldepth = R["vl@depth"]
  if R["vl@tone"] == "" then V.lt = range(K"0.26", K"0.38") else V.lt = R["vl@tone"] end
  if R["vl@u"] > K"0.6" then V.fine = U V.bn = 36 * U else V.fine = 0 V.bn = 24 * U end
  -- a leaflet's level of detail: under 1.4 cm a coarser edge, no mottle or side veins,
  -- under 4 mm a flat shape
  V.lod = 2 * U
  if R.lleaflet == U and R["vl@u"] < K"1.4" then
    V.lod = U V.fine = 0 V.bn = 16 * U
    if R["vl@u"] < K"0.4" then V.lod = 0 V.bn = 12 * U end
  end
  if R.ldepth > 0 then V.bodyw = E"1-0.75*@ldepth" V.lent = 0 else V.bodyw = U V.lent = U end
  -- a curled tip, on an unlobed leaf drawn in full 8 mm long or more, hairless unless broad
  V.hk = 0
  if R.lod == 2 * U and R.lent == U and (tr("hairy") == 0 or R.lW >= K"0.15") and R["vl@u"] > K"0.8" then
    V.t = E"min(0.55,max(0,$curl+0.25))"
    if chance(R.t) then hookset() end
  end
  -- the body along its margin's samples
  smargin()
  local mn = MS.n
  loop("#kb", 1, mn, function() V.v = MS[R["#kb"]][1] lspine(R.v) put(R["#kb"], R.sx, R.sy) end)
  normals(mn)
  loop("#kb", 1, mn, function()
    local q = R["#kb"]
    local m = MS[q]
    V.q = q * U V.v = m[1] V.sdd = m[2]
    shw(R.v) V.cut = E"@ldep*min(1,@h/(0.45*@lW))*(1-@sdd)"
    -- a curled tip narrows as it turns edge-on, the more the species' leaves twist
    V.hwf = U
    if R.hk == U and R.v > R.hv then
      V.hwt = E"min(1,(@v-@hv)/@hl)" V.hwf = E"1-(0.25+0.008*$twist)*min(1,@hth/150)*@hwt*@hwt*(3-2*@hwt)"
    end
    V.e = E("max(0,@h*@bodyw-@cut*%1)*@hwf", { m[3] })
    V.xl = E("%1+%2*@e", { X[q], NX[q] }) V.yl = E("%1+%2*@e-@dy", { Y[q], NY[q] })
    if R.lobl > 0 then V.vo = E"max(0,(@v-@lobl)/(1-@lobl))" shw(R.vo) end
    V.e = E("max(0,@h*@bodyw-@cut*%1)*@hwf", { m[4] })
    V.xr = E("%1-%2*@e", { X[q], NX[q] }) V.yr = E("%1-%2*@e-@dy", { Y[q], NY[q] })
    setv(RX, q, R.xl) setv(RY, q, R.yl) setv(QX, q, R.xr) setv(QY, q, R.yr)
  end)
  -- the tip: notched (emarginate) or a short point (mucronate)
  V.q = mn * U
  if R.ltip < 0 then V.t = E("%1-0.25*@lW", { RY[mn] }) setv(RY, mn, R.t) end
  if R.ltip > 0 then V.t = E("%1+0.04", { RY[mn] }) setv(RY, mn, R.t) end
  V.mnm = (mn - 1) * U bladeassemble(mn - 1)
  smoothprepT(2 * mn - 2, R.ltk) keep("ls1")
  -- a hairy leaf's fringe
  if tr("hairy") == U and R.fine == U then
    local hn = 2 * mn - 2
    V.hn = hn * U normals(hn)
    vtone("flo@c", K"0.1")
    vstroke("flo@c", K"0.15", K"0.55", 0, function()
      loop("#kb", 1, hn, function()
        local kb = R["#kb"]
        if kb % 2 == 1 then
          V.hl = range(K"0.008", K"0.02")
          V.xl = E("%1+%2*@hl", { X[kb], NX[kb] }) V.yl = E("%1+%2*@hl", { Y[kb], NY[kb] })
          moveto(X[kb], Y[kb]) lineto(R.xl, R.yl)
        end
      end)
    end)
  end
  V.nshapes = U V.nveins = 0
  -- the lobes, grown out of the body along the spine
  if R.ldepth > 0 then
    -- a palmately lobed leaf's lobes fan out from its base
    if R.lmn == "palmatelobed" then V.lpal = U V.lwf = K"1.3" V.lnl = pm.int(E"max(1,floor(@llobes/2))")
    else V.lpal = 0 V.lwf = U V.lnl = R.llobes end
    loop("#kc", 0, 1, function()
      if R["#kc"] == 0 then V.side = -U else V.side = U end
      loop("#ka", 1, function() return I("lnl") end, function()
        if R.lpal == U then
          V.lv = E"0.04+0.025*#ka"
          lspine(R.lv) V.lx = R.sx V.ly = R.sy ltan(R.lv)
          V.t = range(K"0.9", K"1.1") V.lL = E"0.8*(1-0.3*(#ka-1)/@lnl)*@t"
          V.lang = range(30 * U, 40 * U) V.lang = E"@lang+45*(#ka-1)/max(1,@lnl-1)"
        else
          V.lv = E"0.1+0.72*(#ka-(@side>0 ? 0.25 : 0.75))/@llobes"
          lspine(R.lv) V.lx = R.sx V.ly = R.sy ltan(R.lv)
          V.t = E"min(0.95,@lv+0.08)" slenv(R.t) V.t = range(K"0.95", K"1.15") V.reach = E"@env*@t"
          V.lang = range(38 * U, 58 * U)
        end
        V.c = E"cos(@lang)" V.sn = E"sin(@lang)*@side"
        V.ldx = E"@tx*@c-@ty*@sn" V.ldy = E"@tx*@sn+@ty*@c"
        if R.lpal == 0 then V.lL = E"@reach/sin(@lang)*0.95" end
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
          V.t = range(K"0.26", K"0.3") V.wa = E"max(0,@lL*@t*@lwf*@g+@e)"
          V.t = range(K"0.26", K"0.3") V.wb = E"max(0,@lL*@t*@lwf*@g+@e)"
          local q = I("q")
          V.xl = E("%1+%2*@wa", { X[q], NX[q] }) V.yl = E("%1+%2*@wa", { Y[q], NY[q] })
          V.xr = E("%1-%2*@wb", { X[q], NX[q] }) V.yr = E("%1-%2*@wb", { Y[q], NY[q] })
          setv(RX, q, R.xl) setv(RY, q, R.yl) setv(QX, q, R.xr) setv(QY, q, R.yr)
        end)
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
  if R.lod == 0 then return end
  scope(function()
    leaftrace() usepath("clip")
    -- the darker half
    if chance(K"0.5") then V.sd = U else V.sd = -U end
    loop("#kb", 0, 30, function()
      V.v = E"#kb/30" lspine(R.v)
      if R["#kb"] == 0 then moveto(R.sx, R.sy) else lineto(R.sx, R.sy) end
    end)
    V.t = E"@sd*2" lineto(R.t, U) lineto(R.t, K"-0.3") lineto(0, K"-0.3") closepath()
    scope(function()
      vtone("flo@c", K"0.12") out("\\pgfsetfillcolor{flo@c}\\pgfsetfillopacity{0.28}\\pgfsetblendmode{multiply}")
      usepath("fill")
    end)
    V.xa = E"-@lW*2.5" V.xb = E"@lW*2.5" V.ta = E"@lt-0.2" V.tb = E"@lt+0.22"
    if R.lod == 2 * U then
      if R.fine == U then vmottle("xa", K"-0.2", "xb", U, 13, K"0.11", R.ta, R.tb, 12)
      else vmottle("xa", K"-0.2", "xb", U, 6, K"0.11", R.ta, R.tb, 0) end
    end
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
    -- veins: pinnate, arcuate (curving up toward the tip) or palmate (two each side from the base)
    if R.nveins == 0 and R.lod == 2 * U then
      V.vn = tr("venation") V.vka = U V.varc = 0
      if R.vn == "arcuate" then V.varc = U end
      if R.vn == "palmate" then
        V.vka = 5 * U
        lspine(K"0.03") V.lx = R.sx V.ly = R.sy ltan(K"0.03")
        loop("#kc", 0, 3, function()
          local kc = R["#kc"]
          if kc < 2 then V.side = -U else V.side = U end
          if kc % 2 == 1 then V.t = 64 * U V.vbl = K"1.1" else V.t = 32 * U V.vbl = K"1.5" end
          V.lang = range(E"@t-5", E"@t+5")
          V.c = E"cos(@lang)" V.sn = E"sin(@lang)*@side"
          V.ldx = E"@tx*@c-@ty*@sn" V.ldy = E"@tx*@sn+@ty*@c"
          V.t = range(K"0.85", U) V.lL = E"@lW*@vbl*@t"
          V.pa = E"@lx+@ldx*@lL*0.4" V.pb = E"@ly+@ldy*@lL*0.4"
          V.pc = E"@lx+@ldx*@lL*0.75+@tx*@lL*0.25" V.pd = E"@ly+@ldy*@lL*0.75+@ty*@lL*0.25"
          V.pe = E"@lx+@ldx*@lL*0.9+@tx*@lL*0.6" V.pf = E"@ly+@ldy*@lL*0.9+@ty*@lL*0.6"
          V.qa = R.pa V.qb = R.pb V.qc = R.pc V.qd = R.pd V.qe = R.pe V.qf = R.pf
          V.twa = K"0.016" V.twb = K"0.002" V.op = range(K"0.45", K"0.7")
          vfill("white", R.op, 0, function() vtaper(R.lx, R.ly, R.qa, R.qb, R.qc, R.qd, R.qe, R.qf) end)
        end)
      end
      loop("#ka", I("vka"), 9, function()
        V.v = E"(#ka-0.3)/10*0.9"
        if R["#ka"] % 2 == 1 then V.sg = -U else V.sg = U end
        lspine(R.v) V.lx = R.sx V.ly = R.sy ltan(R.v)
        V.nx = E"-@ty*@sg" V.ny = E"@tx*@sg"
        slenv(R.v) V.t = range(K"0.75", K"0.95") V.lL = E"@env*@bodyw*@t"
        if R.varc == U then
          V.pa = E"@lx+@nx*@lL*0.3+@tx*@lL*0.12" V.pb = E"@ly+@ny*@lL*0.3+@ty*@lL*0.12"
          V.pc = E"@lx+@nx*@lL*0.62+@tx*@lL*0.55" V.pd = E"@ly+@ny*@lL*0.62+@ty*@lL*0.55"
          V.pe = E"@lx+@nx*@lL*0.72+@tx*@lL*1.15" V.pf = E"@ly+@ny*@lL*0.72+@ty*@lL*1.15"
        else
          V.pa = E"@lx+@nx*@lL*0.4" V.pb = E"@ly+@ny*@lL*0.4"
          V.pc = E"@lx+@nx*@lL*0.75+@tx*@lL*0.3" V.pd = E"@ly+@ny*@lL*0.75+@ty*@lL*0.3"
          V.pe = E"@lx+@nx*@lL*0.95+@tx*@lL*0.6" V.pf = E"@ly+@ny*@lL*0.95+@ty*@lL*0.6"
        end
        V.qa = R.pa V.qb = R.pb V.qc = R.pc V.qd = R.pd V.qe = R.pe V.qf = R.pf
        V.twa = K"0.014" V.twb = K"0.002" V.op = range(K"0.45", K"0.7")
        vfill("white", R.op, 0, function() vtaper(R.lx, R.ly, R.qa, R.qb, R.qc, R.qd, R.qe, R.qf) end)
      end)
    end
  end)
  if R.lent == U then vtone("flo@c", K"0.05") vstroke("flo@c", K"0.18", K"0.4", 0, function() kept("ls1") end) end
  if R.hk == U and R.hth > 95 * U then hookunder() end
end
-- \flo@sleaf: stipules, a petiolate leaf's stalk, then the blade
function sleaf()
  sshape()
  -- a broad blade is drawn shorter, to stay within a leaf's room
  V.lsc = E"min(1,0.3/@lW)"
  if tr("leafmargin") == "palmatelobed" then V.lsc = E"min(1,0.3/max(@lW,0.55))" end
  scope(function()
  if R.lsc < U then scale(R.lsc) V["vl@u"] = E"@vl@u*@lsc" end
  if tr("stipules") ~= "none" and R["vl@u"] > K"0.8" then
    loop("#kc", 0, 1, function()
      V.t = range(40 * U, 65 * U)
      if R["#kc"] == 1 then V.t = E"-@t" end
      V.ts = range(K"0.1", K"0.15")
      scope(function()
        shift(0, K"0.01") rotate(R.t) scale(R.ts)
        V["vl@W"] = K"0.3" V["vl@tone"] = K"0.3" V["vl@u"] = E"@vl@u*@ts" vleaflet()
      end)
    end)
  end
  if tr("attachment") == "petiolate" then V.lpf = range(K"0.1", K"0.2") else V.lpf = 0 end
  if R.lpf > 0 then
    vtone("flo@c", K"0.16") V.twa = K"0.024" V.twb = K"0.014"
    V.lpe = E"@lpf+0.01" V.ta = E"@lpf/3" V.tb = E"2*@lpf/3"
    vfill("flo@c", U, 0, function() vtaper(0, 0, 0, R.ta, 0, R.tb, 0, R.lpe) end)
  end
  scope(function()
    if R.lpf > 0 then
      shift(0, R.lpf) V.t = E"1-@lpf" scale(R.t) V["vl@u"] = E"@vl@u*@t"
    end
    sblade()
  end)
  end)
end

-- \flo@sleaflet{tone}: a leaflet in the species' hand, no stalk or stipules, two or three
-- lobes a side; +y, length 1, \flo@vl@u its length on the page in cm
local function sleaflet(lt)
  V["vl@bend"] = "" V["vl@tone"] = lt V["vl@depth"] = 0 V["vl@lobes"] = 3 * U
  V.lm = tr("leafmargin") V.lmover = ""
  if R.lm == "lobed" or R.lm == "pinnatifid" or R.lm == "palmatelobed" then
    -- under 7 mm, scallops instead of lobes (a pinnatifid leaflet's: deep teeth)
    if R["vl@u"] < K"0.7" then
      V["vl@depth"] = 0 V.lmover = "crenate"
      if R.lm == "pinnatifid" then V.lmover = "dentate" end
    else
      V["vl@depth"] = E"min(0.85,max(0.3,$dissection))"
      V.t = E"max(2,min(3,$teeth))" V["vl@lobes"] = pm.int(R.t)
    end
  end
  sshape_()
  V.lsc = E"min(1,0.3/@lW)"
  if R.lm == "palmatelobed" then V.lsc = E"min(1,0.3/max(@lW,0.55))" end
  scope(function()
    if R.lsc < U then scale(R.lsc) V["vl@u"] = E"@vl@u*@lsc" end
    V.lleaflet = U sblade()
  end)
end
-- \flo@pinnate{leaf pt}{pairs}{longest leaflet}: pairs sized to peak mid-rachis, then a
-- terminal leaflet or (\flo@ptend) a tendril
local function pinnate(lpt, pairs, pl)
  V.plpt = lpt V.pk = pairs V.pl = pl
  V.plw = E"max(0.035,min(0.6,0.5/$leafaspect))"
  if R.ptend == U then
    V.pend = K"0.92" V.pgap = E"0.68/max(1,@pk-1)"
    V.pmax = E"min(@pl,0.45*@pgap/@plw)"
  else
    V.pmax = E"min(@pl,0.3465/(max(1,@pk-1)*@plw+0.495))"
    V.pterm = E"min(@pl,1.1*@pmax)" V.pend = E"1-@pterm"
    V.pgap = E"(@pend-0.23)/max(1,@pk-1)"
  end
  moveto(0, 0) lineto(0, R.pend) usepath("stroke")
  loop("#j", 1, function() return I("pk") end, function()
    V.v = E"0.2+@pgap*(#j-1)"
    V.ll = E"@pmax*(0.72+0.28*sin(180*(#j-0.5)/@pk))"
    loop("#n", 0, 1, function()
      V.ang = range(50 * U, 68 * U) V.ang = E"@ang-14*(#j-1)/@pk" V.dv = sym(K"0.015")
      scope(function()
        V.t = E"@v+@dv" shift(0, R.t)
        if R["#n"] == 0 then rotate(R.ang) else rotate(-R.ang) end
        scale(R.ll) V["vl@u"] = E"@plpt*@ll/28.45276"
        V.tp = range(E"@lt-0.07", E"@lt+0.07") sleaflet(R.tp)
      end)
    end)
  end)
  if R.ptend == U then
    tone("flo@c", K"0.22", "flo@ink") out("\\pgfsetstrokecolor{flo@c}\\pgfsetlinewidth{0.25pt}")
    if chance(K"0.4") then V.tdn = 2 * U else V.tdn = U end
    loop("#q", 1, function() return I("tdn") end, function()
      scope(function()
        shift(0, R.pend)
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
      shift(0, R.pend) scale(R.pterm) V["vl@u"] = E"@plpt*@pterm/28.45276"
      sleaflet(R.lt)
    end)
  end
end
-- \flo@bipinnate{leaf pt}: pinnae that are themselves odd-pinnate, and a terminal pinna
local function bipinnate(lpt)
  V.bpt = lpt V.ptend = 0
  V.bk = E"int(min(3,max(2,($leaflets+1)/3)))" V.bl = E"int(min(7,max(3,$leaflets)))"
  V.lt = E"@lt+0.06"
  moveto(0, 0) lineto(0, K"0.7") usepath("stroke")
  loop("#m", 1, function() return I("bk") end, function()
    V.bv = E"0.16+0.44*(#m-1)/max(1,@bk-1)"
    V.bs = E"0.48*(1-0.5*(#m-1)/@bk)"
    V.bpn = E"int(max(2,@bl-#m+1))"
    loop("#p", 0, 1, function()
      V.bang = range(48 * U, 64 * U) V.bang = E"@bang-12*(#m-1)/@bk"
      scope(function()
        shift(0, R.bv)
        if R["#p"] == 0 then rotate(R.bang) else rotate(-R.bang) end
        scale(R.bs) V.t = E"@bpt*@bs"
        pinnate(R.t, R.bpn, K"0.4")
      end)
    end)
  end)
  scope(function()
    shift(0, K"0.66") scale(K"0.34") V.t = E"@bpt*0.34"
    V.bpn = E"int(max(2,@bl-@bk))" pinnate(R.t, R.bpn, K"0.4")
  end)
end
-- \flo@palmate{leaf pt}{n}: leaflets from a petiole's tip, the center one the largest,
-- drawn from the outside in
local function palmate(lpt, n)
  V.plpt = lpt V.pk = n V.pp = range(K"0.3", K"0.38")
  moveto(0, 0) lineto(0, R.pp) usepath("stroke")
  V.hs = E"min(135,20*@pk-10)"
  loop("#n", 1, function() return I("pk") end, function()
    local q = R["#n"]
    if q % 2 == 1 then V.pj = ((q + 1) // 2) * U else V.pj = (I("pk") + 1 - q // 2) * U end
    V.f = E"(@pj-(@pk+1)/2)/max(1,(@pk-1)/2)"
    V.dv = sym(6 * U) V.ang = E"-@f*@hs+@dv" V.ll = E"(1-@pp)*(1-0.45*@f*@f)"
    scope(function()
      shift(0, R.pp) rotate(R.ang) scale(R.ll)
      V["vl@u"] = E"@plpt*@ll/28.45276"
      V.tp = range(E"@lt-0.06", E"@lt+0.06") sleaflet(R.tp)
    end)
  end)
end
-- \flo@trifoliate{leaf pt}: two side leaflets and a larger end one on a short stalk
local function trifoliate(lpt)
  V.plpt = lpt V.pp = range(K"0.3", K"0.4") V.pst = range(0, K"0.1")
  V.t = E"@pp+@pst" moveto(0, 0) lineto(0, R.t) usepath("stroke")
  loop("#n", 0, 2, function()
    if R["#n"] < 2 then
      V.ang = range(48 * U, 68 * U)
      if R["#n"] == 1 then V.ang = E"-@ang" end
      V.ll = E"0.8*(1-@pp)" V.pv = R.pp
    else
      V.ang = 0 V.ll = E"1-@pp-@pst" V.pv = E"@pp+@pst"
    end
    scope(function()
      shift(0, R.pv) rotate(R.ang) scale(R.ll)
      V["vl@u"] = E"@plpt*@ll/28.45276"
      V.tp = range(E"@lt-0.06", E"@lt+0.06") sleaflet(R.tp)
    end)
  end)
end
-- the compound branch of \flo@leaf: stipules, the stroke for rachis and stalks, the leaf
function compoundleaf()
  V.lt = range(K"0.24", K"0.4")
  if tr("stipules") ~= "none" then
    if tr("stipules") == "leafy" then V.sta = K"0.1" V.stb = K"0.16" V["vl@W"] = K"0.36"
    else V.sta = K"0.05" V.stb = K"0.08" V["vl@W"] = K"0.3" end
    loop("#kc", 0, 1, function()
      V.t = range(55 * U, 80 * U)
      if R["#kc"] == 1 then V.t = E"-@t" end
      V.ts = range(R.sta, R.stb)
      scope(function()
        shift(0, K"0.01") rotate(R.t) scale(R.ts)
        V["vl@tone"] = K"0.3" V["vl@u"] = E"@lfpt*@ts/28.45276" vleaflet()
      end)
    end)
  end
  tone("flo@c", K"0.07", "flo@ink") out("\\pgfsetstrokecolor{flo@c}")
  V.lw = E"max(0.25,0.006*(@lfpt))"
  out("\\pgfsetlinewidth{" .. str(R.lw) .. "bp}\\pgfsetroundcap")
  V.ptend = tr("tendrils")
  if R.cp == "pinnate" then V.t = E"int(min(7,$leaflets))" pinnate(R.lfpt, R.t, K"0.4") end
  if R.cp == "bipinnate" then bipinnate(R.lfpt) end
  if R.cp == "palmate" then palmate(R.lfpt, tr("leaflets")) end
  if R.cp == "trifoliate" then trifoliate(R.lfpt) end
end
end

-- \flo@sheath: a sheathing leaf's base along the stem (\flo@lsd degrees from the leaf's
-- axis, \flo@lsw wide, in the leaf's units); its top \flo@shx,\flo@shy
local function sheath()
  V.shl = range(K"0.14", K"0.22")
  V.shx = E"-@shl*sin(@lsd)" V.shy = E"@shl*cos(@lsd)"
  V.twa = R.lsw V.twb = E"0.8*@lsw"
  V.xa = E"@shx/3" V.ya = E"@shy/3" V.xb = E"2*@shx/3" V.yb = E"2*@shy/3"
  vtone("flo@c", K"0.34") vfill("flo@c", U, 0, function() vtaper(0, 0, R.xa, R.ya, R.xb, R.yb, R.shx, R.shy) end)
  vtone("flo@c", K"0.08") vstroke("flo@c", K"0.2", K"0.6", 0, function() vtaper(0, 0, R.xa, R.ya, R.xb, R.yb, R.shx, R.shy) end)
  V.shd = U
end
-- \flo@leaf{length pt}: the species' leaf along +y, length 1, from a sheath's top where it has one
local leaf_
local function leaf(len)
  V.shd = 0
  if R.lsd ~= "" and tr("attachment") == "sheathing" then sheath() end
  if R.shd == U then scope(function() shift(R.shx, R.shy) leaf_(len) end) else leaf_(len) end
end
function leaf_(len)
  V.lfpt = len V.cp = tr("compound") V.ve = tr("venation")
  V["vl@u"] = E"(@lfpt)/28.45276"
  if R.cp == "simple" then
    if R.ve == "parallel" then
      V.lW = E"max(0.025,min(0.12,0.42/$leafaspect))" vstrap()
    else
      if R.sbend ~= nil then V["vl@bend"] = R.sbend else V["vl@bend"] = "" end
      V["vl@tone"] = ""
      V.lm = tr("leafmargin") V["vl@depth"] = 0 V["vl@lobes"] = 3 * U
      local lobed = R.lm == "lobed" or R.lm == "pinnatifid" or R.lm == "palmatelobed"
      if lobed then
        V["vl@depth"] = E"min(0.85,max(0.3,$dissection))"
        V.t = E"max(2,min(6,$teeth))" V["vl@lobes"] = pm.int(R.t)
      end
      sleaf()
    end
  elseif R.cp == "frond" then
    T.frond(R.lfpt)
  else
    compoundleaf()
  end
end
-- \flo@vblossom{r}{n}: flora.blossom, n round petals, radius 1; r its radius in cm
function vblossom(r, n)
  if M.stream then return M.nvpen().blossom(r / U, n // U, { tone = M.nvval(R["vf@tone"]) }) end
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
  if M.stream then return M.nvpen().fruit(R.fu / U) end
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
  if M.stream then
    return M.nvpen().bloom(d / U, st / U, { side = M.nvval(R.bside), fan = R.bfan == U,
      notchp = R["vp@notchp"] / U, notchk = R["vp@notchk"] / U })
  end
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
  if M.stream then return M.nvpen().budding(d / U) end
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
  if M.stream then return M.nvpen().tendril(size / U) end
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
  if M.stream then return M.nvpen().unit(k / U, R.ust / U) end
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

-- ---------------------------------------------------------------- ferns
-- \flo@frond{length pt}: a fern's frond along +y, length 1 (stipe, rachis, pinnae in the
-- outline, combs of pinnules, the crozier while it unrolls, scales, sori, beads), and
-- \flo@ferncrown: three to five fronds and a fertile one from a crown. In T (Lua's 200
-- locals); the spine in T.FX/T.FY (\flo@feX<k>/\flo@feY<k>)
do
  local function feput(i, x, y) setv(T.FX, i, x) setv(T.FY, i, y) end
  local function xscale(s) out("\\pgftransformxscale{" .. str(s) .. "}") end
  local function pts(spk) return function() out(concat(spk)) end end
  local OL = {                      -- \flo@feol@<outline>
    lanceolate = function() V.febm = K"0.3" V.felo = K"0.45" V.fekx = K"0.8" V.fewr = K"0.26" end,
    oblong = function() V.febm = K"0.12" V.felo = K"0.7" V.fekx = K"0.35" V.fewr = K"0.2" end,
    ovate = function() V.febm = K"0.2" V.felo = K"0.75" V.fekx = K"0.9" V.fewr = K"0.32" end,
    deltoid = function() V.febm = K"0.04" V.felo = K"0.9" V.fekx = K"1.3" V.fewr = K"0.42" end,
  }
  local AP = {                      -- \flo@feap@<apex>
    acute = function() V.fekp = K"1.6" V.fekq = K"0.9" end,
    obtuse = function() V.fekp = 3 * U V.fekq = K"0.6" end,
    rounded = function() V.fekp = 5 * U V.fekq = K"0.45" end,
  }
  local MG = { entire = 0, crenate = K"0.2", serrate = K"0.26" }   -- \flo@fem@<margin>: \flo@fetd
  -- \flo@feribbon{n}{w0}{w1}: a filled ribbon along X/Y 1..n, in flo@c
  local function feribbon(n, w0, w1)
    V.sn = n * U
    normals(n)
    arclengths(n)
    loop("#kb", 1, n, function()
      local kb = R["#kb"]
      V.w = E("((%1)+((%2)-(%1))*%3/@acc)/2", { w0, w1, S[kb] })
      sides(kb, "w")
    end)
    ribbonsides(n)
    smoothprep(2 * n) vfill("flo@c", U, 0, smoothpath)
  end
  -- \flo@fehalf{name}{n}: the left half of a kept shape, then down the midrib
  local function fehalf(name, n)
    local k = KEPT[name]
    V.kn = k.N * U V.fehn = n * U
    moveto(k.X[1], k.Y[1])
    loop("#i", 1, function() return I("fehn") end, function()
      local i = R["#i"]
      V.ib = (i + 1) * U
      curveto(k.A[i], k.B[i], k.C[i], k.D[i], k.X[i + 1], k.Y[i + 1])
    end)
    loop("#i", 1, 8, function() V.v = E"1-#i/8" V.sx = E"@fefb*@v*@v" lineto(R.sx, R.v) end)
    closepath()
  end
  -- \flo@fesori{name}: under a pinna
  local function fesori(name)
    V.fesr = tr("sori") vaccent("flo@c", K"-0.35")
    if R.fesr == "marginal" then
      V.t = E"min(0.5,0.3*@fepcm)" vstroke("flo@c", R.t, K"0.75", 0, function() kept(name) end)
    end
    if R.fesr == "dots" then
      local spk = {}
      V.t = E"int(min(7,2+4*@fepcm))" V.fend = pm.int(R.t)
      loop("#kb", 1, function() return I("fend") end, function()
        V.v = E"0.14+0.66*(#kb-1)/max(1,@fend-1)" V.sx = E"@fefb*@v*@v"
        V.w = E"0.5*@feW*(1-0.5*@v)" V.t = E"0.3*@feW*(1-0.4*@v)"
        V.xa = E"@sx-@w" V.xb = E"@sx+@w"
        spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.xa, R.v) .. "}{" .. str(R.t) .. "pt}\\pgfpathcircle{"
          .. P(R.xb, R.v) .. "}{" .. str(R.t) .. "pt}"
      end)
      vfill("flo@c", K"0.9", 0, pts(spk))
    end
    if R.fesr == "lines" then
      local spk = {}
      V.t = E"int(min(6,2+3*@fepcm))" V.fend = pm.int(R.t)
      loop("#kb", 1, function() return I("fend") end, function()
        V.v = E"0.12+0.62*(#kb-1)/max(1,@fend-1)" V.sx = E"@fefb*@v*@v"
        V.w = E"0.7*@feW*(1-0.5*@v)"
        V.xa = E"@sx-0.15*@w" V.xb = E"@sx-@w" V.ya = E"@v+0.6*@w"
        V.xc = E"@sx+0.15*@w" V.xd = E"@sx+@w"
        spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.v) .. "}\\pgfpathlineto{" .. P(R.xb, R.ya)
          .. "}\\pgfpathmoveto{" .. P(R.xc, R.v) .. "}\\pgfpathlineto{" .. P(R.xd, R.ya) .. "}"
      end)
      vstroke("flo@c", K"0.45", K"0.85", 0, pts(spk))
    end
  end
  -- \flo@fepinna: a pinna along +y, length 1, \flo@feW its half-width
  local function fepinna()
    V.fefb = range(K"0.05", K"0.16") V.t = sym(K"0.03") V.fet = E"@fetone+@t"
    V.fenp = 10 * U V.fetk = 0
    if R.fepcm < K"0.3" then V.fenp = 6 * U end
    if R.fepcm > K"0.6" and R.fetd > 0 then
      V.fetk = R.fetd V.fenp = E"2*int(min(9,3+4*@fepcm))" V.fenp = pm.int(R.fenp)
    end
    V.fecs = 0 V.tmp = "serrate" V.t = tr("leafmargin")
    if R.fetk > 0 and R.t == R.tmp then V.fecs = E"0.35/@fenp" end
    loop("#kb", 0, function() return I("fenp") end, function()
      local kb = R["#kb"]
      V.v = E"#kb/@fenp"
      if kb % 2 == 1 and kb < I("fenp") then V.v = E"@v+@fecs" end
      V.sx = E"@fefb*@v*@v" put(kb + 1, R.sx, R.v)
    end)
    normals(I("fenp") + 1)
    loop("#kb", 0, function() return I("fenp") end, function()
      V.q = (R["#kb"] + 1) * U
      local q = I("q")
      V.v = Y[q]
      if R.v > 0 and R.v < U then
        V.w = E"@feW*pow(min(1,@v/0.12),0.45)*pow(max(0.0001,1-pow(@v,@fekp)),@fekq)*(1-@fenar*@v)"
        if R["#kb"] % 2 == 0 then V.w = E"@w*(1-@fetk)" end
      else V.w = 0 end
      sides(q, "w")
    end)
    bladeassemble(I("fenp")) smoothprep(2 * I("fenp")) keep("fep")
    vtone("flo@c", R.fet) vfill("flo@c", U, 0, function() kept("fep") end)
    if R.fepcm > K"0.2" then vtone("flo@c", K"0.08") vfill("flo@c", K"0.28", 1, function() fehalf("fep", I("fenp")) end) end
    if R.fepcm > K"0.35" then
      V.twa = K"0.03" V.twb = K"0.004"
      V.xb = E"@fefb*0.82*0.82/3" V.xc = E"@fefb*0.82*0.82"
      vfill("white", K"0.6", 0, function() vtaper(0, 0, 0, K"0.2733", R.xb, K"0.5467", R.xc, K"0.82") end)
    end
    if R.feund == U and R.fepcm > K"0.35" then fesori("fep") end
  end
  -- \flo@fecpt{x expr}{v expr}: a comb's point, left of the midrib
  local function fecpt(x, v)
    V.fecp = R.fecp + U V.t = E(v)
    V.xl = E("@fefb*@t*@t-(" .. x .. ")")
    setv(RX, I("fecp"), R.xl) setv(RY, I("fecp"), R.t)
  end
  -- \flo@fesorc: the sori of a comb
  local function fesorc()
    V.fesr = tr("sori") vaccent("flo@c", K"-0.35")
    if R.fesr == "marginal" then
      V.t = E"min(0.4,0.22*@fepcm)" vstroke("flo@c", R.t, K"0.75", 0, function() kept("fec") end)
    else
      local spk = {}
      loop("#kb", 1, function() return I("fecn") end, function()
        V.v = E"0.05+@fecd*(#kb-0.5)" V.fecl = E"@feW*(1-0.72*pow(@v,1.5))"
        V.ya = E"@v+0.35*@fecs" V.sx = E"@fefb*@ya*@ya"
        V.xa = E"@sx-0.45*@fecl" V.xb = E"@sx+0.45*@fecl"
        if R.fesr == "dots" then
          V.t = E"0.16*min(@fecd,@fecl)"
          spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.xa, R.ya) .. "}{" .. str(R.t) .. "pt}\\pgfpathcircle{"
            .. P(R.xb, R.ya) .. "}{" .. str(R.t) .. "pt}"
        else
          V.xc = E"@sx-0.7*@fecl" V.xd = E"@sx+0.7*@fecl" V.yb = E"@ya+0.6*@fecs"
          spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.ya) .. "}\\pgfpathlineto{" .. P(R.xc, R.yb)
            .. "}\\pgfpathmoveto{" .. P(R.xb, R.ya) .. "}\\pgfpathlineto{" .. P(R.xd, R.yb) .. "}"
        end
      end)
      if R.fesr == "dots" then vfill("flo@c", K"0.9", 0, pts(spk))
      elseif R.fesr == "lines" then vstroke("flo@c", K"0.45", K"0.85", 0, pts(spk)) end
    end
  end
  -- \flo@fecomb: a pinna cut into pinnules, along +y, length 1
  local function fecomb()
    V.fefb = range(K"0.04", K"0.12") V.t = sym(K"0.03") V.fet = E"@fetone+@t"
    V.t = E"int(max(3,min(9,@fepcm/0.15)))" V.fecn = pm.int(R.t)
    V.fecd = E"0.9/@fecn" V.fecs = E"0.35*@fecd"
    V.fecp = U setv(RX, 1, 0) setv(RY, 1, 0)
    loop("#kb", 1, function() return I("fecn") end, function()
      V.v = E"0.05+@fecd*(#kb-0.5)" V.t = range(K"0.9", K"1.06")
      V.fecl = E"@feW*(1-0.72*pow(@v,1.5))*@t"
      if R.fediv > 2 * U then
        fecpt("0.12*@feW", "@v-0.5*@fecd") fecpt("0.5*@fecl", "@v-0.4*@fecd+0.3*@fecs")
        fecpt("0.62*@fecl", "@v-0.2*@fecd+0.55*@fecs") fecpt("@fecl", "@v+@fecs")
        fecpt("0.66*@fecl", "@v+0.24*@fecd+0.7*@fecs") fecpt("0.52*@fecl", "@v+0.38*@fecd+0.5*@fecs")
      else
        fecpt("0.12*@feW", "@v-0.5*@fecd") fecpt("0.58*@fecl", "@v-0.36*@fecd+0.5*@fecs")
        fecpt("@fecl", "@v+@fecs") fecpt("0.62*@fecl", "@v+0.36*@fecd+0.6*@fecs")
      end
    end)
    V.fech = R.fecp V.fecp = R.fecp + U
    setv(RX, I("fecp"), R.fefb) setv(RY, I("fecp"), U)
    loop("#kb", 2, function() return I("fech") end, function()
      local kb = R["#kb"]
      V.q = (I("fech") + 2 - kb) * U V.ia = (I("fecp") + kb - 1) * U
      local q = I("q")
      V.t = E("%1", { RY[q] }) V.xl = E("2*@fefb*@t*@t-(%1)", { RX[q] })
      setv(RX, I("ia"), R.xl) setv(RY, I("ia"), R.t)
    end)
    V.fecp = 2 * R.fech
    loop("#kb", 1, function() return I("fecp") end, function() put(R["#kb"], RX[R["#kb"]], RY[R["#kb"]]) end)
    smoothprep(I("fecp")) keep("fec")
    vtone("flo@c", R.fet) vfill("flo@c", U, 0, function() kept("fec") end)
    vtone("flo@c", K"0.08") vfill("flo@c", K"0.28", 1, function() fehalf("fec", I("fech")) end)
    V.twa = K"0.025" V.twb = K"0.004"
    V.xb = E"@fefb*0.9*0.9/3" V.xc = E"@fefb*0.9*0.9"
    vfill("white", K"0.55", 0, function() vtaper(0, 0, 0, K"0.3", R.xb, K"0.6", R.xc, K"0.9") end)
    if R.feund == U then fesorc() end
  end
  -- \flo@febeads: a fertile pinna, a row of beads along +y, length 1
  local function febeads()
    V.fefb = range(K"0.02", K"0.08") V.t = E"int(max(2,min(7,2+5*@fepcm)))" V.fend = pm.int(R.t)
    vtone("flo@c", K"0.12") V.xb = E"@fefb*0.9*0.9/3" V.xc = E"@fefb*0.9*0.9"
    vstroke("flo@c", K"0.3", K"0.8", 0, function() moveto(0, 0) curveto(0, K"0.3", R.xb, K"0.6", R.xc, K"0.9") end)
    local spk = {}
    loop("#kb", 1, function() return I("fend") end, function()
      V.v = E"0.95*(#kb-0.3)/@fend" V.sx = E"@fefb*@v*@v"
      V.t = range(K"0.85", K"1.1") V.t = E"0.6/@fend*(1-0.4*@v)*@t"
      spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.sx, R.v) .. "}{" .. str(R.t) .. "pt}"
    end)
    V.t = sym(K"0.04") vtone("flo@c", E"0.32+@t") vfill("flo@c", U, 0, pts(spk))
    vtone("flo@c", K"0.08") vstroke("flo@c", K"0.25", K"0.45", 1, pts(spk))
  end
  -- where a pinna (or the tip) leaves the rachis at \flo@fes: \flo@fpx, \flo@fpy
  local function rachisat()
    V.fei = pm.int(R.t) V.fef = E"@t-@fei"
    V.fia = (I("fei") + 1) * U V.fib = (I("fei") + 2) * U
    local ia, ib = I("fia"), I("fib")
    V.fpx = E("%1+(%2-(%1))*@fef", { T.FX[ia], T.FX[ib] })
    V.fpy = E("%1+(%2-(%1))*@fef", { T.FY[ia], T.FY[ib] })
  end
  -- \flo@frond{length pt}
  function T.frond(len)
    V.fept = len V.fecm = E("(%1)/28.45276", { len })
    if R.fearch == "" then V.t = sym(U) V.fearch = E"@t*(20+70*$curl)" end
    if R.feun >= K"0.97" then V.feun = U end
    if R.fefert == U then V.rampname = "flo@aramp" end
    V.fest = tr("stipe") V.fen = tr("pinnae") V.fediv = tr("division")
    OL[tr("outline")]() AP[tr("leafapex")]() V.fetd = MG[tr("leafmargin")]
    V.fesh = tr("leafshape") V.tmp = "lanceolate"
    if R.fesh == R.tmp then V.fenar = K"0.3" else V.fenar = 0 end
    V.feo = E"@fest+(1-@fest)*(@feun<1 ? 0.3+0.7*@feun : 1)"
    V.fex = 0 V.fey = 0 feput(1, 0, 0)
    loop("#kb", 1, 32, function()
      V.t = E"@feo*(#kb-0.5)/32" V.fea = E"90+@fearch*pow(@t,1.5)"
      V.fex = E"@fex+@feo/32*cos(@fea)" V.fey = E"@fey+@feo/32*sin(@fea)"
      feput(R["#kb"] + 1, R.fex, R.fey)
    end)
    if R.feun < U then
      if R.fearch < 0 then V.fesg = -U else V.fesg = U end
      V.fecT = E"100+440*(1-@feun)"
      V.fecr = E"0.65*(1-@feo)/(@fecT*0.0174533*0.541)"
      V.fea = E"90+@fearch*pow(@feo,1.5)"
      loop("#kb", 1, 24, function()
        V.fea = E"@fea+@fesg*@fecT/24"
        V.t = E"@fecr*pow(0.25,(#kb-0.5)/24)*@fecT/24*0.0174533"
        V.fex = E"@fex+@t*cos(@fea)" V.fey = E"@fey+@t*sin(@fea)"
        feput(R["#kb"] + 33, R.fex, R.fey)
      end)
    end
    V.t = range(K"0.9", K"1.1") V.fepm = E"(1-@fest)*@fewr*@t"
    if R.fefert == U then V.fepm = E"0.45*@fepm" end
    V.fetone = range(K"0.24", K"0.34")
    if R.feund == U then V.fetone = E"@fetone+0.14" end
    loop("#Gd", 1, function() return I("fen") end, function()
      loop("#Ge", 0, 1, function()
        V.feb = E"0.93*pow((#Gd-0.5+0.42*#Ge)/@fen,0.85)"
        V.fes = E"@fest+(1-@fest)*@feb"
        if R.feb < R.febm then V.fee = E"@felo+(1-@felo)*sin(90*@feb/@febm)"
        else V.fee = E"pow(max(0.0001,cos(90*(@feb-@febm)/(1-@febm))),@fekx)" end
        if R.feun < U then V.fee = E"@fee*max(0,min(1,0.3+0.7*(@feo-@fes)/0.15))" end
        V.t = range(K"0.92", K"1.06") V.fel = E"@fepm*@fee*@t"
        V.t = sym(4 * U) V.fal = E"70-30*@feb+@t"
        V.fepcm = E"@fel*@fecm"
        V.t = E"@fes<@feo-0.004 && @fepcm>0.08 ? 1 : 0"
        if R.t > K"0.5" then
          V.t = E"0.93*(1-@fest)*(pow((#Gd+0.5)/@fen,0.85)-pow((#Gd-0.5)/@fen,0.85))"
          V.feW = E"min(0.22,0.34*@t*sin(@fal)/@fel)"
          V.t = E"@fes/@feo*32" rachisat()
          V.fea = E"90+@fearch*pow(@fes,1.5)"
          scope(function()
            shift(R.fpx, R.fpy)
            if R["#Ge"] == 0 then V.t = E"@fea+@fal-90" else V.t = E"@fea-@fal-90" end
            rotate(R.t)
            if R["#Ge"] == 1 then xscale(-U) end
            scale(R.fel)
            if R.fefert == U then febeads()
            elseif R.fediv > U then if R.fepcm > K"0.45" then fecomb() else fepinna() end
            else fepinna() end
          end)
        end
      end)
    end)
    if R.feun >= U and R.fefert == 0 then
      V.fes = E"@fest+0.91*(1-@fest)" V.fel = E"0.1*(1-@fest)"
      V.t = E"@fes*32" rachisat()
      V.fea = E"90+@fearch*pow(@fes,1.5)" V.feW = K"0.13" V.fepcm = E"@fel*@fecm"
      scope(function() shift(R.fpx, R.fpy) V.t = E"@fea-90" rotate(R.t) scale(R.fel) fepinna() end)
    end
    loop("#kb", 1, 33, function() put(R["#kb"], T.FX[R["#kb"]], T.FY[R["#kb"]]) end)
    V.fewb = E"0.0025+0.006*(1-@feun)" vtone("flo@c", K"0.1") feribbon(33, K"0.012", R.fewb)
    if tr("hairy") == U then
      local spk = {}
      loop("#kb", 2, 32, function()
        V.t = E"@feo*(#kb-1)/32<0.9*@fest && mod(#kb,2)==0 ? 1 : 0"
        if R.t > K"0.5" then
          local kb = R["#kb"]
          V.fia = (kb + 1) * U
          V.da = E("%1-(%2)", { T.FX[kb + 1], T.FX[kb] }) V.db = E("%1-(%2)", { T.FY[kb + 1], T.FY[kb] })
          nrm(R.da, R.db, "nax", "nay")
          V.t = E"mod(#kb,4)==0 ? 1 : -1" V.ts = range(K"0.012", K"0.02")
          V.xa = E("%1+@t*@nax*0.005", { T.FX[kb] }) V.ya = E("%1+@t*@nay*0.005", { T.FY[kb] })
          V.xb = E"@xa+@t*@nax*@ts+@da*12*@ts" V.yb = E"@ya+@t*@nay*@ts+@db*12*@ts"
          spk[#spk + 1] = "\\pgfpathmoveto{" .. P(R.xa, R.ya) .. "}\\pgfpathlineto{" .. P(R.xb, R.yb) .. "}"
        end
      end)
      vaccent("flo@c", K"-0.3") vstroke("flo@c", K"0.35", K"0.85", 0, pts(spk))
    end
    if R.feun < U then
      loop("#kb", 1, 25, function() put(R["#kb"], T.FX[R["#kb"] + 32], T.FY[R["#kb"] + 32]) end)
      normals(25)
      local spk = {}
      loop("#kb", 2, 24, function()
        local kb = R["#kb"]
        V.r = E"@fecr*pow(0.25,(#kb-1)/24)"
        V.xa = E("%1-@fesg*%2*0.33*@r", { X[kb], NX[kb] })
        V.ya = E("%1-@fesg*%2*0.33*@r", { Y[kb], NY[kb] })
        V.t = E(kb % 2 == 1 and "(0.15)*@r" or "(0.21)*@r")
        spk[#spk + 1] = "\\pgfpathcircle{" .. P(R.xa, R.ya) .. "}{" .. str(R.t) .. "pt}"
      end)
      V.fewa = E"0.56*@fecr" V.fewb = E"0.16*@fecr"
      vtone("flo@c", K"0.27") feribbon(25, R.fewa, R.fewb)
      vtone("flo@c", K"0.2") vfill("flo@c", U, 0, pts(spk))
      vtone("flo@c", K"0.06") vstroke("flo@c", K"0.25", K"0.35", 1, pts(spk))
      loop("#kb", 1, 22, function() put(R["#kb"], T.FX[R["#kb"] + 32], T.FY[R["#kb"] + 32]) end)
      V.fewa = E"0.14*@fecr" vstreak(22, R.fewa, K"0.002", "white", K"0.5")
    end
  end
  -- \flo@ferncrown: three to five fronds from a crown at the origin (cm), \flo@gH the longest
  function T.ferncrown()
    out("\\pgfsetroundcap\\pgfsetroundjoin") scale(K"28.45276")
    V.season = R["o@season"] V.fenf = int(3, 5)
    loop("#Ga", 1, function() return I("fenf") end, function()
      V.f = E"(#Ga-(@fenf+1)/2)/((@fenf-1)/2)"
      V.t = sym(8 * U) V.fela = E"90-44*@f+@t"
      V.t = range(K"0.8", K"1.2") V.feac = E"(@f<0 ? 1 : -1)*(20+70*$curl)*@t*(0.4+0.6*abs(@f))"
      V.t = range(K"0.85", U) V.fell = E"@gH*(1-0.22*abs(@f))*@t"
      V.t = range(0, K"0.3") V.feuu = E"max(0,min(1,(@season-0.1-$phenology-@t)/0.4))"
      if chance(K"0.4") then V.feuf = U else V.feuf = 0 end
      V.lc = rnd() V.fexx = E"0.06*@f"
      seedorgan()
      organ(function()
        V.feun = R.feuu V.fearch = R.feac
        if R.feun < K"0.97" then V.feund = 0 else V.feund = R.feuf end
        shift(R.fexx, 0) V.t = E"@fela-90" rotate(R.t)
        scale(R.fell) autumnleaf()
        V.t = E"@fell*28.45276" T.frond(R.t)
      end)
    end)
    if tr("dimorphic") == U and R.season > K"0.55" then
      V.t = sym(6 * U) V.fela = E"90+@t" V.feac = sym(12 * U)
      V.t = range(K"0.55", K"0.7") V.fell = E"@gH*@t"
      seedorgan()
      organ(function()
        V.fefert = U V.fearch = R.feac V.feun = U
        V.t = E"@fela-90" rotate(R.t) scale(R.fell)
        V.t = E"@fell*28.45276" T.frond(R.t)
      end)
    end
  end
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
  if R.t == "simple" then V.leafc = E"min(1.45,max(1,sqrt($leafaspect/2.2)))" else V.leafc = K"1.35" end
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
      V.mx = E"@lx+cos(@la)*@lf*@fore*0.55" V.my = E"@ly+sin(@la)*@lf*@fore*0.55"
      V.t = E"0.24*@lf" takenat(R.mx, R.my, R.t)
      if R.taken < K"0.2" then V.ok = U else V.lf = E"0.75*@lf" end
    end
  end)
  if R.lf < K"0.45" then V.ok = 0 end
  if R.ok == U then
    loop("#Gd", 1, 3, function()
      V.t = E"(0.05+0.25*#Gd)*@lf*@fore"
      V.mx = E"@lx+cos(@la)*@t" V.my = E"@ly+sin(@la)*@t"
      V.t = E"0.2*@lf" room(1, R.mx, R.my, R.t)
    end)
    if at(LLEAF) then
      organ(function()
        shift(R.lx, R.ly) V.t = E"@la-90" rotate(R.t)
        scale(R.lf)
        if R.fore < U then yscale(R.fore) end
        autumnleaf()
        if R.lsd ~= "" then V.lsw = E"1.8*@nw/@lf" end
        V.t = E"@lf*28.45276" leaf(R.t)
      end)
    end
  end
  V.fore = U V.lsd = ""
end
local function nodeleaves()
  nodeat()
  V.side = E"-1*(@side)"
  V["nd@" .. R["#Ga"] .. "@" .. R["#Ge"]] = { R.nyy, R.side }
  loop("#Gb", 1, function() return I("per") end, function()
    if R["#Gb"] == 2 then V.ls = E"-1*(@side)" else V.ls = R.side end
    V.t = range(35 * U, 60 * U)
    if R["#Gb"] == 3 then V.t = range(8 * U, 20 * U) end
    -- decussate: every other opposite pair close to the stem, foreshortened
    if I("per") == 2 and R["#Ge"] % 2 == 0 then V.t = E"0.55*@t" V.fore = K"0.55" end
    V.la = E"@ta+@ls*@t" V.lsd = E"@ta-@la"
    V.t = range(K"0.85", K"1.1") V.lf = E"2.6*(1-(1-$taper)*@u)*@t*@leafk*@leafc*(#Gb==3 ? 0.7 : 1)"
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
    V.lf = E"@lf*@leafc"
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
  if R.cl == "monocot" then
    V.arr = tr("arrangement")
    if R.arr == "alternate" then V.cl = "leafy" end
    if R.arr == "whorled" then V.cl = "leafy" end
  end
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

-- ================================================================ visitors
do
local L = {}
-- \florilegiumvisitor{seed}{role}: the visitor's traits into the store (\flo@x@<trait>),
-- the generator where the TikZ library leaves pgf's (in a block: the main chunk is at
-- Lua's limit of 200 locals)
function L.florilegiumvisitor(seed, role)
  local v, r = species.vsample(seed, role)
  rng.load(r.save())
  V["x@seed"] = seed V["x@role"] = role V["x@kind"] = v.kind
  for i = 2, #species.VTRAITS do
    local t = species.VTRAITS[i]
    V["x@" .. t] = traitval(v[t])
  end
end
function L.xtr(name) return R["x@" .. name] end
function L.xscale(s) out("\\pgftransformxscale{" .. str(s) .. "}") end
function L.pellipse(cx, cy, ax, ay, bx, by)
  out("\\pgfpathellipse{" .. P(cx, cy) .. "}{" .. P(ax, ay) .. "}{" .. P(bx, by) .. "}")
end
-- butterflies and moths: \flo@lepid and its helpers (\flo@wg...)
function L.wx(w, i) return R["wg" .. w .. "X" .. i] end
function L.wy(w, i) return R["wg" .. w .. "Y" .. i] end
function L.wput(w, i, x, y) V["wg" .. w .. "X" .. i] = x V["wg" .. w .. "Y" .. i] = y end
L.SHAPE = {
  fw = { { "0.05", "0.1" }, { "0.3", "0.45" }, { "0.65", "0.68" }, { "0.92", "0.66" }, { "1", "0.5" },
    { "0.88", "0.25" }, { "0.55", "0.05" }, { "0.15", "-0.02" } },
  hw = { { "0.06", "-0.02" }, { "0.45", "-0.02" }, { "0.72", "-0.22" }, { "0.7", "-0.5" }, { "0.5", "-0.72" },
    { "0.25", "-0.7" }, { "0.08", "-0.35" } },
}
L.APEX = {
  rounded = {},
  angular = { { "fw", 3, "0.66", "0.7" }, { "fw", 4, "1", "0.72" }, { "fw", 5, "0.98", "0.52" } },
  falcate = { { "fw", 3, "0.66", "0.72" }, { "fw", 4, "1.04", "0.78" }, { "fw", 5, "0.9", "0.55" } },
  pointed = { { "fw", 1, "0.05", "0.08" }, { "fw", 2, "0.35", "0.36" }, { "fw", 3, "0.72", "0.42" },
    { "fw", 4, "1", "0.38" }, { "fw", 5, "0.97", "0.28" }, { "fw", 6, "0.7", "0.16" },
    { "fw", 7, "0.38", "0.04" }, { "fw", 8, "0.12", "-0.02" },
    { "hw", 2, "0.4", "-0.02" }, { "hw", 3, "0.55", "-0.12" }, { "hw", 4, "0.52", "-0.28" },
    { "hw", 5, "0.38", "-0.38" }, { "hw", 6, "0.2", "-0.36" }, { "hw", 7, "0.07", "-0.2" } },
}
function L.wgshape()
  for _, w in ipairs({ "fw", "hw" }) do
    for i, p in ipairs(L.SHAPE[w]) do L.wput(w, i, K(p[1]), K(p[2])) end
  end
  for _, p in ipairs(L.APEX[L.xtr("apex")]) do L.wput(p[1], p[2], K(p[3]), K(p[4])) end
end
function L.wgjit(w, n)
  loop("#Wa", 1, n, function()
    local i = R["#Wa"]
    V.t = sym(K"0.03") V.xa = E("%1+@t", { L.wx(w, i) })
    V.t = sym(K"0.03") V.ya = E("%1+@t", { L.wy(w, i) })
    L.wput(w, i, R.xa, R.ya)
  end)
end
L.TAIL = { { "-0.05", "-0.04" }, { "-0.06", "-0.19" }, { "-0.1", "-0.25" }, { "-0.15", "-0.2" }, { "-0.13", "-0.04" } }
function L.wgtailpts()
  V.xb = L.wx("hw", 5) V.yb = L.wy("hw", 5)
  loop("#Wb", 1, 5, function()
    local k = R["#Wb"]
    V.xa = E("@xb+%1", { K(L.TAIL[k][1]) })
    V.ya = E("@yb+%1", { K(L.TAIL[k][2]) })
    V["#Wc"] = R["#Wc"] + 1 put(R["#Wc"], R.xa, R.ya)
  end)
end
function L.wgoutline(w, n, m0, m1)
  V["#Wc"] = 0
  loop("#Wa", 1, n, function()
    local a = R["#Wa"]
    V["#Wc"] = R["#Wc"] + 1 put(R["#Wc"], L.wx(w, a), L.wy(w, a))
    if I("wgtail") == a then L.wgtailpts() end
    if R.wgdep > 0 and a < m1 and a > m0 - 1 then
      V.wgn = (a + 1) * U
      local b = a + 1
      loop("#Wb", 1, 3, function()
        V.t = E"#Wb/4"
        V.xa = E("%1+(%2-(%1))*@t", { L.wx(w, a), L.wx(w, b) })
        V.ya = E("%1+(%2-(%1))*@t", { L.wy(w, a), L.wy(w, b) })
        if R["#Wb"] % 2 == 1 then V.xa = E"@xa*(1-@wgdep)" V.ya = E"@ya*(1-@wgdep)" end
        V["#Wc"] = R["#Wc"] + 1 put(R["#Wc"], R.xa, R.ya)
      end)
    end
  end)
  smoothprep(R["#Wc"])
end
function L.wgat(w, m0, m1, s, f)
  V.wm = (m1 - m0) * U
  V.wq = E("(%1)*@wm", { s }) V.wk = pm.int(E"min(@wm-1,floor(@wq))")
  V.wf = E"@wq-@wk"
  V.wi = (m0 + I("wk")) * U V.wj = (m0 + I("wk") + 1) * U
  local i, j = I("wi"), I("wj")
  V.wx = E("(%1+(%2-(%1))*@wf)*(%3)", { L.wx(w, i), L.wx(w, j), f })
  V.wy = E("(%1+(%2-(%1))*@wf)*(%3)", { L.wy(w, i), L.wy(w, j), f })
end
function L.wgeye(x, y, r)
  vtone("flo@c", K"0.08") vfill("flo@c", K"0.85", 0, function() circle(x, y, r) end)
  if L.xtr("rings") > U then V.t = E("(%1)*0.68", { r }) vfill("white", K"0.85", 0, function() circle(x, y, R.t) end) end
  V.t = E("(%1)*(@x@rings>2 ? 0.46 : 0.34)", { r })
  vaccent("flo@c", 0) vfill("flo@c", U, 0, function() circle(x, y, R.t) end)
  if L.xtr("rings") > 2 * U then
    V.t = E("(%1)*0.22", { r }) vtone("flo@c", K"0.06") vfill("flo@c", U, 0, function() circle(x, y, R.t) end)
    V.xa = E("%1+(%2)*0.1", { x, r }) V.ya = E("%1+(%2)*0.1", { y, r }) V.t = E("(%1)*0.08", { r })
    vfill("white", K"0.9", 0, function() circle(R.xa, R.ya, R.t) end)
  end
  if L.xtr("parafocal") == U then
    local a = { x, y, r }
    V.wa = E("atan2(%2,%1)", a) V.wr = E("(%3)*1.5", a)
    V.xa = E("%1+@wr*cos(@wa-55)", a) V.ya = E("%2+@wr*sin(@wa-55)", a)
    V.xb = E("%1+@wr*1.15*cos(@wa-20)", a) V.yb = E("%2+@wr*1.15*sin(@wa-20)", a)
    V.xc = E("%1+@wr*1.15*cos(@wa+20)", a) V.yc = E("%2+@wr*1.15*sin(@wa+20)", a)
    V.xd = E("%1+@wr*cos(@wa+55)", a) V.yd = E("%2+@wr*sin(@wa+55)", a)
    V.twa = E("(%3)*0.22", a) V.twb = E("(%3)*0.22", a)
    vtone("flo@c", K"0.08")
    vfill("flo@c", K"0.6", 1, function() vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
  end
end
L.BASE = { fw = { "0.12", "0.12" }, hw = { "0.12", "-0.12" } }
L.ROOTY = { fw = "0.04", hw = "-0.04" }
L.SPOTR = { fw = "0.03", hw = "0.034" }
L.BAND = {
  fw = function()
    V.xa = E"0.47+@wgcj" V.xb = E"0.42+@wgcj"
    vtaper(K"0.5", K"0.66", R.xa, K"0.45", R.xb, K"0.25", K"0.36", K"0.04")
  end,
  hw = function()
    V.xa = E"0.37+@wgcj" V.xb = E"0.28+@wgcj"
    vtaper(K"0.42", K"-0.02", R.xa, K"-0.2", R.xb, K"-0.38", K"0.14", K"-0.55")
  end,
}
L.SPOTS = {
  fw = function() V.xa = E"0.47+@wgcj" V.xb = E"0.42+@wgcj" V.ya = K"0.45" V.yb = K"0.25" end,
  hw = function() V.xa = E"0.37+@wgcj" V.xb = E"0.28+@wgcj" V.ya = K"-0.2" V.yb = K"-0.38" end,
}
L.DISCAL = {
  fw = function() V.xa = E"0.47+@wgcj*0.5" V.ya = K"0.42" end,
  hw = function() V.xa = E"0.34+@wgcj*0.5" V.ya = K"-0.27" end,
}
function L.wgpaint(w, n, m0, m1)
  vtone("flo@c", R.wgt) vfill("flo@c", R.wgop, 0, function() kept("wg" .. w) end)
  if R.wgblur ~= 0 then return end
  scope(function()
    kept("wg" .. w) usepath("clip")
    V.ta = E"@wgt-0.2" V.tb = E"@wgt+0.2"
    if R.fine == U then vmottle(K"-1.2", K"-1.2", K"1.2", K"1.2", 9, K"0.14", R.ta, R.tb, 8)
    else vmottle(K"-1.2", K"-1.2", K"1.2", K"1.2", 4, K"0.14", R.ta, R.tb, 0) end
    if L.xtr("basal") == U then
      vblob(K(L.BASE[w][1]), K(L.BASE[w][2]), K"0.2", K"0.15", K"0.3", 9)
      V.t = E"@wgt-0.18" vtone("flo@c", R.t) vfill("flo@c", K"0.45", 1, smoothpath)
    end
    V.wgsys = L.xtr("central")
    if R.wgsys == "band" then
      V.twa = R.wgcw V.twb = E"@wgcw*0.8"
      V.t = E"@wgt-0.2" vtone("flo@c", R.t)
      vfill("flo@c", K"0.6", 1, L.BAND[w])
    end
    if R.wgsys == "spots" then
      L.SPOTS[w]()
      V.xc = E"(@xa+@xb)/2" V.yc = E"(@ya+@yb)/2"
      V.t = E"@wgt-0.22" vtone("flo@c", R.t)
      vfill("flo@c", K"0.65", 1, function()
        circle(R.xa, R.ya, K"0.045") circle(R.xb, R.yb, K"0.045") circle(R.xc, R.yc, K"0.04")
      end)
    end
    if L.xtr("discal") == U then
      L.DISCAL[w]()
      V.t = E"@wgt-0.25" vtone("flo@c", R.t)
      vfill("flo@c", K"0.75", 1, function() L.pellipse(R.xa, R.ya, K"0.03", 0, 0, K"0.045") end)
    end
    V.wgsys = L.xtr("border")
    if R.wgsys == "band" then
      V.t = E"6.8*@wgu" V.ta = E"@wgt-0.22" vtone("flo@c", R.ta)
      vstroke("flo@c", R.t, K"0.55", 1, function() kept("wg" .. w) end)
    end
    vtone("flo@c", K"0.05") V.t = E"7.37*@wgu" vstroke("flo@c", R.t, K"0.55", 1, function() kept("wg" .. w) end)
    if R.wgsys == "spots" then
      vtone("flo@c", K"0.06")
      loop("#Wb", 1, function() return L.xtr("eyes") // U end, function()
        V.t = E"(#Wb-0.5)/@x@eyes" L.wgat(w, m0, m1, R.t, K"0.86")
        vfill("flo@c", K"0.8", 0, function() circle(R.wx, R.wy, K(L.SPOTR[w])) end)
      end)
    end
    if R.wgsys == "eyes" then
      loop("#Wb", 1, function() return I("wgne@" .. w) end, function()
        V.t = E("%1+(#Wb-1)*%2", { R["wges@" .. w], R["wged@" .. w] })
        L.wgat(w, m0, m1, R.t, K"0.78")
        L.wgeye(R.wx, R.wy, R["wger@" .. w])
      end)
    end
    if L.xtr("lunules") > 0 then
      V.wgnc = 2 * (m1 - m0) * U
      loop("#Wc", 1, function() return L.xtr("lunules") // U end, function()
        V.wgf = E"0.95-0.07*(#Wc-1)"
        loop("#Wb", 1, function() return I("wgnc") end, function()
          V.t = E"(#Wb-0.85)/@wgnc" L.wgat(w, m0, m1, R.t, R.wgf)
          V.xc = R.wx V.yc = R.wy
          V.t = E"(#Wb-0.15)/@wgnc" L.wgat(w, m0, m1, R.t, R.wgf)
          V.xa = E"@xc+(@wx-@xc)/3" V.ya = E"@yc+(@wy-@yc)/3"
          V.xb = E"@xc+(@wx-@xc)*2/3" V.yb = E"@yc+(@wy-@yc)*2/3"
          V.xa = E"@xa*0.96" V.ya = E"@ya*0.96" V.xb = E"@xb*0.96" V.yb = E"@yb*0.96"
          V.twa = K"0.03" V.twb = K"0.008"
          vfill("white", K"0.55", 0, function() vtaper(R.xc, R.yc, R.xa, R.ya, R.xb, R.yb, R.wx, R.wy) end)
        end)
      end)
    end
    if L.xtr("veins") == U then
      V.wgrx = K"0.04" V.wgry = K(L.ROOTY[w])
      loop("#Wb", 1, n, function()
        local b = R["#Wb"]
        V.f = range(K"0.7", K"0.88")
        V.xd = E("@wgrx+(%1-@wgrx)*@f", { L.wx(w, b) })
        V.yd = E("@wgry+(%1-(@wgry))*@f", { L.wy(w, b) })
        put(1, R.wgrx, R.wgry)
        V.xa = E"@wgrx+(@xd-@wgrx)*0.3" V.ya = E"@wgry+(@yd-(@wgry))*0.4" put(2, R.xa, R.ya)
        V.xa = E"@wgrx+(@xd-@wgrx)*0.7" V.ya = E"@wgry+(@yd-(@wgry))*0.75" put(3, R.xa, R.ya)
        put(4, R.xd, R.yd)
        V.op = range(K"0.35", K"0.6") vstreak(4, K"0.035", K"0.004", "white", R.op)
        if R.wgsys == "none" and R.fine == U and b > 1 and b < n then
          V.xa = E("@wgrx+(%1-@wgrx)*0.9", { L.wx(w, b) })
          V.ya = E("@wgry+(%1-(@wgry))*0.9", { L.wy(w, b) })
          V.t = range(K"0.025", K"0.04") vfill("white", K"0.8", 0, function() circle(R.xa, R.ya, R.t) end)
        end
      end)
    end
  end)
  if L.xtr("tails") == 2 * U and w == "hw" then
    V.xb = L.wx("hw", 5) V.yb = L.wy("hw", 5)
    V.twa = K"0.022" V.twb = K"0.006" vtone("flo@c", K"0.08")
    vfill("flo@c", K"0.9", 0, function()
      V.xa = E"@xb-0.05" V.ya = E"@yb-0.02" V.xd = E"@xb-0.02" V.yd = E"@yb-0.26"
      V.xc = E"@xb-0.04" V.yc = E"@yb-0.1" V.xe = E"@xb-0.025" V.ye = E"@yb-0.18"
      vtaper(R.xa, R.ya, R.xc, R.yc, R.xe, R.ye, R.xd, R.yd)
      V.xa = E"@xb-0.14" V.xd = E"@xb-0.13" V.yd = E"@yb-0.2"
      V.xc = E"@xb-0.14" V.yc = E"@yb-0.08" V.xe = E"@xb-0.135" V.ye = E"@yb-0.14"
      vtaper(R.xa, R.yb, R.xc, R.yc, R.xe, R.ye, R.xd, R.yd)
    end)
  end
end
function L.wgbody()
  loop("#Wb", 0, 10, function()
    local b = R["#Wb"]
    V.v = E"#Wb/10" V.h = E"@wgaw*sin(180*pow(@v,0.7))"
    V.ya = E"-@wgal+@wgal*@v" V.xa = E"-@h"
    put(b + 1, R.xa, R.ya)
    if b > 0 and b < 10 then put(21 - b, R.h, R.ya) end
  end)
  smoothprep(20) vtone("flo@c", K"0.06") vfill("flo@c", U, 0, smoothpath)
  if L.xtr("bands") > 0 then
    V.twa = K"0.03" V.twb = K"0.03"
    loop("#Wb", 1, function() return L.xtr("bands") // U end, function()
      V.ya = E"-@wgal*#Wb/(@x@bands+1)" V.xa = E"@wgaw*0.9" V.xb = E"-@wgaw*0.9"
      V.xc = E"@wgaw*0.3" V.xd = E"-@wgaw*0.3"
      vfill("white", K"0.45", 0, function() vtaper(R.xb, R.ya, R.xd, R.ya, R.xc, R.ya, R.xa, R.ya) end)
    end)
  end
  vtone("flo@c", K"0.04") vfill("flo@c", U, 0, function() L.pellipse(0, K"0.08", R.wgtw, 0, 0, K"0.13") end)
  if L.xtr("hair") > 0 then
    V.wgnh = pm.int(E"4+12*@x@hair") vtone("flo@c", K"0.12")
    V.twa = K"0.022" V.twb = K"0.003"
    loop("#Wb", 1, function() return I("wgnh") end, function()
      V.wa = range(0, 360 * U) V.t = range(K"0.03", K"0.06")
      V.xa = E"@wgtw*cos(@wa)" V.ya = E"0.08+0.13*sin(@wa)"
      V.xd = E"(@wgtw+@t)*cos(@wa)" V.yd = E"0.08+(0.13+@t)*sin(@wa)"
      V.xb = E"@xa+(@xd-@xa)/3" V.yb = E"@ya+(@yd-@ya)/3"
      V.xc = E"@xa+(@xd-@xa)*2/3" V.yc = E"@ya+(@yd-@ya)*2/3"
      vfill("flo@c", K"0.7", 0, function() vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
    end)
  end
  vtone("flo@c", K"0.04") vfill("flo@c", U, 0, function() circle(0, K"0.27", R.wghr) end)
  V.wgw = E"max(0.3,0.5*@wgu)"
  loop("#Wb", 1, 2, function()
    local b = R["#Wb"]
    if R.wgsides == U then V.sx = U elseif b == 1 then V.sx = -U else V.sx = U end
    V.t = L.xtr("antenna")
    if R.t == "clubbed" then V.ex = range(K"0.22", K"0.3") V.ey = range(K"0.78", K"0.9") end
    if R.t == "thread" then V.ex = range(K"0.26", K"0.36") V.ey = range(K"0.72", K"0.88") end
    if R.t == "feathery" then V.ex = range(K"0.24", K"0.32") V.ey = range(K"0.62", K"0.72") end
    if R.wgsides == U and b == 2 then V.ex = E"@ex*0.8" V.ey = E"@ey*0.95" end
    V.ex = E"@sx*@ex" V.xa = E"@sx*0.02" V.xb = E"@sx*0.05"
    V.xc = E"@ex*0.6" V.yc = E"@ey*0.9"
    vtone("flo@c", K"0.08")
    vstroke("flo@c", R.wgw, U, 0, function() moveto(R.xa, K"0.31") curveto(R.xb, K"0.5", R.xc, R.yc, R.ex, R.ey) end)
    if R.t == "clubbed" then
      vtone("flo@c", K"0.06") vfill("flo@c", U, 0, function() circle(R.ex, R.ey, K"0.025") end)
    end
    if R.t == "feathery" then
      V.t = E"0.5*@wgw"
      vstroke("flo@c", R.t, U, 0, function()
        loop("#Wc", 3, 9, function()
          V.v = E"#Wc/10" V.wf = E"1-@v"
          V.wx = E"@wf*@wf*@wf*@xa+3*@wf*@wf*@v*@xb+3*@wf*@v*@v*@xc+@v*@v*@v*@ex"
          V.wy = E"@wf*@wf*@wf*0.31+3*@wf*@wf*@v*0.5+3*@wf*@v*@v*@yc+@v*@v*@v*@ey"
          V.da = E"3*@wf*@wf*(@xb-@xa)+6*@wf*@v*(@xc-@xb)+3*@v*@v*(@ex-@xc)"
          V.db = E"3*@wf*@wf*0.19+6*@wf*@v*(@yc-0.5)+3*@v*@v*(@ey-@yc)"
          nrm(R.da, R.db, "nx", "ny") V.wr = E"0.05*(1.1-@v)"
          V.xd = E"@wx+@nx*@wr" V.yd = E"@wy+@ny*@wr"
          V.xe = E"@wx-@nx*@wr" V.ye = E"@wy-@ny*@wr"
          moveto(R.xd, R.yd) lineto(R.xe, R.ye)
        end)
      end)
    end
  end)
  if R.wgsides == U then
    vtone("flo@c", K"0.08")
    vstroke("flo@c", R.wgw, U, 0, function()
      loop("#Wb", 0, 2, function()
        V.ya = E"0.16-0.08*#Wb" V.yb = E"@ya+0.03" V.yc = E"@ya-0.12"
        moveto(K"-0.03", R.ya) lineto(K"-0.12", R.yb) lineto(K"-0.2", R.yc)
      end)
    end)
  end
  if R.fine == U and R.wgk == "butterfly" then
    V.t = E"@wgal/0.62"
    V.ya = E"-0.55*@t" put(1, K"-0.015", R.ya) V.ya = E"-0.35*@t" put(2, K"-0.02", R.ya)
    V.ya = E"-0.1*@t" put(3, K"-0.02", R.ya) put(4, K"-0.01", 0)
    vstreak(4, K"0.015", K"0.004", "white", K"0.45")
  end
end
function L.wgwing(w, rot, n, m0, m1)
  scope(function()
    shift(K"0.04", 0) rotate(rot) shift(K"-0.04", 0)
    L.wgpaint(w, n, m0, m1)
  end)
end
-- \flo@lepid: a butterfly or moth, size its wingspan on the page in pt (sp)
function T.lepid(size)
  V.wgu = E("(%1)/56.90552", { size })
  if R.wgu > K"0.3" then V.fine = U else V.fine = 0 end
  V.wgk = L.xtr("kind") V.wgpose = L.xtr("pose") V.wgground = L.xtr("ground")
  V.wgt = L.xtr("tone")
  if R.wgground == "pale" then V.wgt = E"min(0.78,@wgt+0.32)" end
  if R.wgground == "dark" then V.wgt = E"@wgt-0.12" end
  if R.wgground == "copper" then V.rampname = "flo@aramp" end
  V.wgsides = 2 * U V.wgop = U V.wgblur = 0 V.wgxs = U
  V.wgrf = 0 V.wgrh = 0 V.wgpass = U
  if R.wgpose == "closed" then V.wgsides = U V.wgrf = 18 * U V.wgrh = 18 * U V.wgt = E"min(0.8,@wgt+0.12)" end
  if R.wgpose == "flat" then V.wgrf = -18 * U V.wgrh = -10 * U end
  if R.wgpose == "tent" then V.wgrf = -58 * U V.wgrh = -38 * U V.wgxs = K"0.8" end
  if R.wgpose == "hover" then V.wgop = K"0.3" V.wgblur = U V.wgpass = 2 * U end
  V.wgaw = K"0.05" V.wgal = K"0.62" V.wgtw = K"0.075" V.wghr = K"0.06"
  if R.wgk == "moth" then V.wgaw = K"0.075" V.wgtw = K"0.095" V.wghr = K"0.07" end
  if R.wgk == "hawkmoth" then V.wgaw = K"0.075" V.wgal = K"0.85" V.wgtw = K"0.09" V.wghr = K"0.07" end
  if R.wgsides == U then V.wgaw = E"@wgaw*0.8" end
  L.wgshape() L.wgjit("fw", 8) L.wgjit("hw", 7)
  V.t = L.xtr("wingedge") V.wgdep = 0
  if R.t == "scalloped" then V.wgdep = K"0.045" end
  if R.t == "toothed" then V.wgdep = K"0.09" end
  V.wgtail = 0 L.wgoutline("fw", 8, 4, 6) keep("wgfw")
  if L.xtr("tails") == U then V.wgtail = 5 * U end
  L.wgoutline("hw", 7, 3, 6) keep("wghw")
  V.wgcw = range(K"0.07", K"0.11") V.wgcj = sym(K"0.04")
  V["wgne@hw"] = L.xtr("eyes") V["wgne@fw"] = 0
  if L.xtr("eyes") > 2 * U then V["wgne@fw"] = U end
  if I("wgne@hw") > 0 then
    V["wger@hw"] = E"min(0.1,0.34/@wgne@hw)" V["wges@hw"] = E"0.5/@wgne@hw"
    V["wged@hw"] = E"1/@wgne@hw"
  end
  V["wger@fw"] = K"0.065" V["wges@fw"] = K"0.22" V["wged@fw"] = 0
  if R.wgsides == U then rotate(90 * U) end
  loop("#Wa", 1, function() return I("wgsides") end, function()
    scope(function()
      if R["#Wa"] == 2 then L.xscale(-U) end
      if R.wgxs < U then L.xscale(R.wgxs) end
      loop("#Wd", 1, function() return I("wgpass") end, function()
        if R.wgpass == 2 * U then
          if R["#Wd"] == 1 then V.wgrf = 14 * U V.wgrh = 14 * U else V.wgrf = -14 * U V.wgrh = -14 * U end
        end
        if R.wgsides == U then
          L.wgwing("fw", R.wgrf, 8, 4, 6) L.wgwing("hw", R.wgrh, 7, 3, 6)
        else
          L.wgwing("hw", R.wgrh, 7, 3, 6) L.wgwing("fw", R.wgrf, 8, 4, 6)
        end
      end)
    end)
  end)
  L.wgbody()
end
-- bees and hoverflies: \flo@bee and its helpers (\flo@bg...)
function L.bgell(cx, cy, rx, ry) L.pellipse(cx, cy, rx, 0, 0, ry) end
-- \flo@bgband: a band from y hi down to lo, its middle bow nearer the tail
function L.bgband(hi, lo, bow)
  V.bya = E("%1-(%2)", { hi, bow }) V.byb = E("%1-(%2)", { lo, bow })
  moveto(K"-0.5", hi) curveto(K"-0.17", R.bya, K"0.17", R.bya, K"0.5", hi)
  lineto(K"0.5", lo) curveto(K"0.17", R.byb, K"-0.17", R.byb, K"-0.5", lo)
  closepath()
end
function L.bgabdomen()
  loop("#Wa", 1, 16, function()
    V.wa = E"22.5*#Wa-11.25" V.t = E"cos(@wa)" V.v = E"sin(@wa)"
    V.xa = E"@bgrx*(@t<0 ? -1 : 1)*pow(abs(@t),@bgsq)"
    V.ya = E"@bgay+@bgry*@v*(@v<0 ? @bgegg : 1)"
    put(R["#Wa"], R.xa, R.ya)
  end)
  smoothprep(16) keep("bgab")
end
function L.bgwhite()
  V.savedramp = R.rampname V.rampname = "flo@ramp" vtone("flo@c", K"0.93") V.rampname = R.savedramp
end
function L.bgpale(part)
  loop("#Wb", 1, function() return L.xtr("bands") // U end, function()
    local b = R["#Wb"]
    if R["bgbp" .. b] == part then
      vfill("flo@c", K"0.95", 0, function() L.bgband(R["bgbh" .. b], R["bgbl" .. b], K"0.02") end)
    end
  end)
  if part == "a" and L.xtr("paletail") == U then
    L.bgwhite() vfill("flo@c", U, 0, function() L.bgband(R.bgtl, K"-2", K"0.02") end)
  end
end
-- \flo@bgcolorat: the hair's color at height y on the part (0 dark, 1 pale, 2 white)
function L.bgcolorat(y, part)
  V.bgc = 0
  if R.bgk == "bumblebee" then
    loop("#Wd", 1, function() return L.xtr("bands") // U end, function()
      local d = R["#Wd"]
      if R["bgbp" .. d] == part and y < R["bgbh" .. d] and y > R["bgbl" .. d] then V.bgc = 1 end
    end)
    if part == "a" and L.xtr("paletail") == U and y < R.bgtl then V.bgc = 2 end
  end
end
-- \flo@bgfur: n hairs round the ellipse at (0,cy), half-width rx, ra above and rb below
function L.bgfur(cy, rx, n, ra, rb, part)
  local hairs = { {}, {}, {} }
  V.bghl = E"0.5+@x@hair"
  loop("#Wb", 1, n, function()
    V.wa = range(0, 360 * U) V.t = range(K"0.02", K"0.045") V.wb = sym(25 * U)
    V.t = E"@t*@bghl+0.014" V.v = E"sin(@wa)"
    V.wr = E("(@v<0 ? %2 : %1)-0.014", { ra, rb })
    V.xa = E("(%1-0.014)*cos(@wa)", { rx }) V.ya = E("%1+@wr*@v", { cy })
    V.xd = E"@xa+@t*cos(@wa+@wb)" V.yd = E"@ya+@t*sin(@wa+@wb)"
    V.xb = E"@xa+(@xd-@xa)/3" V.yb = E"@ya+(@yd-@ya)/3"
    V.xc = E"@xa+(@xd-@xa)*2/3" V.yc = E"@ya+(@yd-@ya)*2/3"
    local h = { R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd }
    L.bgcolorat(R.ya, part)
    local t = hairs[R.bgc + 1]
    t[#t + 1] = h
  end)
  V.twa = K"0.013" V.twb = K"0.003"
  local function fill(t) return function() for _, h in ipairs(t) do vtaper(table.unpack(h)) end end end
  if #hairs[1] > 0 then vtone("flo@c", R.bgfd) vfill("flo@c", K"0.8", 0, fill(hairs[1])) end
  if #hairs[2] > 0 then vtone("flo@c", R.bgpt) vfill("flo@c", K"0.9", 0, fill(hairs[2])) end
  if #hairs[3] > 0 then L.bgwhite() vfill("flo@c", K"0.9", 0, fill(hairs[3])) end
end
-- \flo@bgab@<kind>: the abdomen's pattern, in its clip
function L.bgbands(f)
  return function() loop("#Wb", 1, function() return L.xtr("bands") // U end, f) end
end
L.BGAB = {
  honeybee = function()
    V.bgsp = E"@bgla/(@x@bands+0.6)" V.bgbt = E"0.42*@bgsp"
    vtone("flo@c", K"0.05")
    vfill("flo@c", K"0.88", 0, L.bgbands(function()
      V.ya = E"@bgat-@bgsp*(#Wb+0.15)+@bgbt/2" V.yb = E"@ya-@bgbt"
      L.bgband(R.ya, R.yb, K"0.03")
    end))
  end,
  bumblebee = function() vtone("flo@c", R.bgpt) L.bgpale("a") end,
  solitarybee = function()
    vfill("white", K"0.6", 0, L.bgbands(function()
      V.ya = E"@bgat-@bgla*(0.12+0.17*#Wb)" V.yb = E"@ya-0.035"
      L.bgband(R.ya, R.yb, K"0.025")
    end))
  end,
  hoverfly = function()
    V.bgsp = E"@bgla/(@x@bands+0.5)"
    if R.bgground == "copper" then vaccent("flo@c", K"0.1")
    else V.t = E"min(0.86,@bgt+0.4)" vtone("flo@c", R.t) end
    vfill("flo@c", K"0.92", 0, L.bgbands(function()
      V.yd = E"@bgat-@bgsp*(#Wb-0.2)"
      V.twa = E"0.42*@bgsp" if R["#Wb"] == 1 then V.twa = E"0.3*@bgsp" end
      V.twb = E"0.15*@bgsp"
      loop("#Wc", 1, 2, function()
        if R["#Wc"] == 1 then V.sx = -U else V.sx = U end
        V.xa = E"@sx*0.03" V.ya = E"@yd+0.01"
        V.xb = E"@sx*@bgrx*0.4" V.yb = E"@yd+0.03"
        V.xc = E"@sx*@bgrx*0.75" V.yc = E"@yd"
        V.xe = E"@sx*@bgrx*1.05" V.ye = E"@yd-0.04"
        vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xe, R.ye)
      end)
    end))
  end,
}
function L.bgpaintab()
  vtone("flo@c", R.bgabt) vfill("flo@c", U, 0, function() kept("bgab") end)
  scope(function()
    kept("bgab") usepath("clip")
    L.BGAB[R.bgk]()
    if R.fine == U then
      V.bgxl = E"-@bgrx" V.bgyl = E"@bgat-@bgla"
      V.ta = E"@bgabt-0.18" V.tb = E"@bgabt+0.17"
      vmottle(R.bgxl, R.bgyl, R.bgrx, R.bgat, 4, K"0.06", R.ta, R.tb, I("bgspk"))
    end
    vtone("flo@c", K"0.05") V.t = E"3.4*@bgu" vstroke("flo@c", R.t, R.bgrim, 1, function() kept("bgab") end)
    V.t = E"@bgrx/0.19" V.v = E"@bgry/0.3"
    V.xa = E"-0.1*@t" V.ya = E"@bgay-0.18*@v" put(1, R.xa, R.ya)
    V.xa = E"-0.13*@t" V.ya = E"@bgay-0.05*@v" put(2, R.xa, R.ya)
    V.xa = E"-0.12*@t" V.ya = E"@bgay+0.08*@v" put(3, R.xa, R.ya)
    V.xa = E"-0.08*@t" V.ya = E"@bgay+0.2*@v" put(4, R.xa, R.ya)
    vstreak(4, K"0.04", K"0.008", "white", K"0.5")
  end)
end
function L.bgthorax()
  V.t = E"@bgtr*0.93" vblob(0, R.bgty, R.bgtr, R.t, K"0.1", 12) keep("bgth")
  vtone("flo@c", R.bgtt) vfill("flo@c", U, 0, function() kept("bgth") end)
  scope(function()
    kept("bgth") usepath("clip")
    if R.bgk == "bumblebee" then vtone("flo@c", R.bgpt) L.bgpale("t") end
    if R.fine == U then
      V.bgxl = E"-@bgtr" V.bgyl = E"@bgty-@bgtr" V.bgyh = E"@bgty+@bgtr"
      V.ta = E"@bgtt-0.04" V.tb = E"@bgtt+0.24"
      vmottle(R.bgxl, R.bgyl, R.bgtr, R.bgyh, 3, K"0.05", R.ta, R.tb, 6)
    end
  end)
end
function L.bghead()
  vtone("flo@c", R.bght) vfill("flo@c", U, 0, function() L.bgell(0, R.bghy, R.bghx, R.bghr) end)
  V.ya = E"@bghy+0.008"
  if R.bgk == "hoverfly" then V.xa = K"0.055" V.xb = K"0.068" V.yb = K"0.08"
  else V.xa = E"@bghx-0.022" V.xb = K"0.028" V.yb = K"0.05" end
  vtone("flo@c", K"0.02")
  vfill("flo@c", U, 0, function() L.bgell(-R.xa, R.ya, R.xb, R.yb) L.bgell(R.xa, R.ya, R.xb, R.yb) end)
  if R.fine == U then
    V.xc = E"@xa-0.3*@xb" V.yc = E"@ya+0.35*@yb"
    vfill("white", K"0.7", 0, function() circle(-R.xc, R.yc, K"0.011") circle(R.xc, R.yc, K"0.011") end)
  end
end
function L.bgfeelers()
  vtone("flo@c", K"0.06")
  if R.bgk == "hoverfly" then
    V.ya = E"@bghy+0.07" V.yb = E"@bghy+0.11" V.yc = E"@bghy+0.14"
    vstroke("flo@c", R.bgw, U, 0, function()
      moveto(K"-0.02", R.ya) lineto(K"-0.035", R.yb) moveto(K"0.02", R.ya) lineto(K"0.035", R.yb)
    end)
    vfill("flo@c", U, 0, function() circle(K"-0.035", R.yb, K"0.014") circle(K"0.035", R.yb, K"0.014") end)
    if R.fine == U then
      V.t = E"0.5*@bgw"
      vstroke("flo@c", R.t, U, 0, function()
        moveto(K"-0.035", R.yb) lineto(K"-0.075", R.yc) moveto(K"0.035", R.yb) lineto(K"0.075", R.yc)
      end)
    end
  else
    V.ya = E"@bghy+0.05"
    vstroke("flo@c", R.bgw, U, 0, function()
      loop("#Wb", 1, 2, function()
        if R["#Wb"] == 1 then V.sx = -U else V.sx = U end
        V.xb = range(K"0.05", K"0.08") V.yb = range(K"0.11", K"0.15")
        V.xc = range(K"0.11", K"0.17") V.yc = range(K"0.17", K"0.23")
        V.xa = E"@sx*0.03" V.xb = E"@sx*@xb" V.yb = E"@bghy+@yb"
        V.xc = E"@sx*@xc" V.yc = E"@bghy+@yc"
        moveto(R.xa, R.ya) lineto(R.xb, R.yb) lineto(R.xc, R.yc)
      end)
    end)
  end
end
-- the legs of a side: root, knee and foot, spread on a flower (v) or hanging in flight (f)
L.BGL = {
  v = { { "0.05", "0.06", "0.17", "0.1", "0.2", "0.22" }, { "0.06", "0", "0.23", "-0.03", "0.3", "-0.15" },
    { "0.06", "-0.06", "0.28", "-0.16", "0.32", "-0.42" } },
  f = { { "0.05", "0.04", "0.13", "0", "0.15", "-0.1" }, { "0.06", "0", "0.17", "-0.08", "0.18", "-0.24" },
    { "0.06", "-0.05", "0.21", "-0.16", "0.22", "-0.44" } },
}
function L.bglegpts(p)
  local i = R["#Wb"]
  V.t = E("(%1)*@bglx", { K(p[1]) }) V["bgLa" .. i] = R.t
  V.t = E("@bgty+(%1)", { K(p[2]) }) V["bgLb" .. i] = R.t
  V.v = sym(K"0.02") V.t = E("(%1)*@bglx+@v", { K(p[3]) }) V["bgLc" .. i] = R.t
  V.v = sym(K"0.02") V.t = E("@bgty+(%1)+@v", { K(p[4]) }) V["bgLd" .. i] = R.t
  V.v = sym(K"0.025") V.t = E("(%1)*@bglx+@v", { K(p[5]) }) V["bgLe" .. i] = R.t
  V.v = sym(K"0.025") V.t = E("@bgty+(%1)+@v", { K(p[6]) }) V["bgLf" .. i] = R.t
end
function L.bglegs()
  loop("#Wb", 1, 3, function() L.bglegpts(L.BGL[R.bglp][R["#Wb"]]) end)
  vtone("flo@c", K"0.08")
  vfill("flo@c", U, 0, function()
    loop("#Wb", 1, 3, function()
      local i = R["#Wb"]
      V.xa = R["bgLa" .. i] V.ya = R["bgLb" .. i]
      V.xd = R["bgLc" .. i] V.yd = R["bgLd" .. i]
      V.xe = R["bgLe" .. i] V.ye = R["bgLf" .. i]
      V.xb = E"@xa+(@xd-@xa)/3" V.yb = E"@ya+(@yd-@ya)/3"
      V.xc = E"@xa+(@xd-@xa)*2/3" V.yc = E"@ya+(@yd-@ya)*2/3"
      V.twa = R.bgfw V.twb = E"@bgfw*0.8"
      vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd)
      V.xb = E"@xd+(@xe-@xd)/3" V.yb = E"@yd+(@ye-@yd)/3"
      V.xc = E"@xd+(@xe-@xd)*2/3" V.yc = E"@yd+(@ye-@yd)*2/3"
      V.twa = E"@bgfw*0.8" V.twb = E"@bgfw*0.35"
      vtaper(R.xd, R.yd, R.xb, R.yb, R.xc, R.yc, R.xe, R.ye)
    end)
  end)
  if L.xtr("pollen") == U then
    V.da = E"@bgLe3-(@bgLc3)" V.db = E"@bgLf3-(@bgLd3)"
    nrm(R.da, R.db, "nx", "ny")
    V.xa = E"@bgLc3+0.45*@da" V.ya = E"@bgLd3+0.45*@db"
    V.xb = E"@ny*0.065*@bgpr" V.yb = E"-(@nx)*0.065*@bgpr"
    V.xc = E"@nx*0.042*@bgpr" V.yc = E"@ny*0.042*@bgpr"
    vaccent("flo@c", 0) vfill("flo@c", U, 0, function() L.pellipse(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc) end)
    if R.fine == U then
      V.xa = E"@xa+0.35*@xc-0.25*@xb" V.ya = E"@ya+0.35*@yc-0.25*@yb"
      vfill("white", K"0.6", 0, function() circle(R.xa, R.ya, K"0.012") end)
    end
  end
end
-- a wing's outline, a teardrop l long and w wide each way, kept as name
L.BGW = { { "0.02", "0" }, { "0.15", "0.55" }, { "0.45", "0.95" }, { "0.8", "0.85" }, { "1", "0.25" },
  { "0.92", "-0.45" }, { "0.6", "-0.8" }, { "0.25", "-0.55" } }
function L.bgwingshape(l, w, name)
  loop("#Wb", 1, 8, function()
    local p = L.BGW[R["#Wb"]]
    V.t = sym(K"0.012") V.xa = E("%1*(%2)+@t", { K(p[1]), l })
    V.t = sym(K"0.012") V.ya = E("%1*(%2)+@t", { K(p[2]), w })
    put(R["#Wb"], R.xa, R.ya)
  end)
  smoothprep(8) keep(name)
end
function L.bgvm(u, v) V.xa = E("(%1)*@bgwl", { K(u) }) V.ya = E("(%1)*@bgww", { K(v) }) moveto(R.xa, R.ya) end
function L.bgvl(u, v) V.xa = E("(%1)*@bgwl", { K(u) }) V.ya = E("(%1)*@bgww", { K(v) }) lineto(R.xa, R.ya) end
L.BGV = {
  f = function()
    L.bgvm("0.03", "0.3") L.bgvl("0.35", "0.72") L.bgvl("0.62", "0.78")
    L.bgvm("0.03", "0.05") L.bgvl("0.3", "0.2") L.bgvl("0.62", "0.25") L.bgvl("0.85", "0.32")
    L.bgvm("0.05", "-0.15") L.bgvl("0.35", "-0.25") L.bgvl("0.6", "-0.3")
    L.bgvm("0.62", "0.78") L.bgvl("0.62", "0.25") L.bgvl("0.6", "-0.3")
  end,
  h = function() L.bgvm("0.03", "0.05") L.bgvl("0.55", "0.15") end,
  v = function()
    L.bgvm("0.03", "0.35") L.bgvl("0.5", "0.8") L.bgvl("0.85", "0.62")
    L.bgvm("0.03", "0") L.bgvl("0.5", "0.1") L.bgvl("0.78", "0.22") L.bgvl("0.92", "0.05")
    L.bgvm("0.05", "-0.2") L.bgvl("0.45", "-0.32") L.bgvl("0.72", "-0.28") L.bgvl("0.86", "-0.08")
    L.bgvm("0.5", "0.8") L.bgvl("0.5", "0.1") L.bgvl("0.45", "-0.32")
  end,
}
function L.bgwing(name, x, y, rot, op, rim, veins)
  scope(function()
    V.rampname = "flo@ramp"
    shift(x, y) rotate(rot)
    vtone("flo@c", K"0.85") vfill("flo@c", op, 0, function() kept(name) end)
    if rim == 1 then
      vtone("flo@c", K"0.15") vstroke("flo@c", R.bglw, K"0.75", 0, function() kept(name) end)
      if R.fine == U then vtone("flo@c", K"0.2") vstroke("flo@c", R.bgvw, K"0.6", 0, L.BGV[veins]) end
    end
  end)
end
function L.bgwings()
  L.bgwingshape(R.bgFl, R.bgFw, "bgwf")
  if R.bgHl > 0 then L.bgwingshape(R.bgHl, R.bgHw, "bgwh") end
  V.bgyf = E"@bgty+0.05" V.bgyh = E"@bgty-0.01"
  if R.bgblur == U then
    loop("#Wb", 1, 3, function()
      if R.bgHl > 0 then V.t = E"@bgah+(#Wb-2)*@bgdl" L.bgwing("bgwh", K"0.06", R.bgyh, R.t, K"0.16", 0, "h") end
      V.t = E"@bgaf+(#Wb-2)*@bgdl" L.bgwing("bgwf", K"0.06", R.bgyf, R.t, K"0.16", 0, "f")
    end)
  else
    if R.bgHl > 0 then V.bgwl = R.bgHl V.bgww = R.bgHw L.bgwing("bgwh", K"0.06", R.bgyh, R.bgah, K"0.55", 1, "h") end
    V.bgwl = R.bgFl V.bgww = R.bgFw L.bgwing("bgwf", K"0.06", R.bgyf, R.bgaf, K"0.55", 1, R.bgvn)
  end
end
-- flora's flight path, dotted, looping away behind
function L.bgtrail()
  V.bgtc = range(K"0.16", K"0.22") V.bgtn = range(U, K"1.3")
  if chance(K"0.5") then V.sx = U else V.sx = -U end
  V.t = E"max(0.6,1.1*@bgu)" V.v = E"max(2.2,3.2*@bgu)"
  scope(function()
    out("\\pgfsetdash{{0bp}{" .. str(R.v) .. "bp}}{0bp}")
    vtone("flo@c", K"0.18")
    vstroke("flo@c", R.t, K"0.7", 0, function()
      loop("#Wb", 0, 40, function()
        V.wa = E"#Wb/40*@bgtn*360"
        V.xa = E"@sx*0.32*sin(@wa)"
        V.ya = E"@bgtip-0.06-@bgtc*@wa*0.0174533+0.192*(cos(@wa)-1)"
        if R["#Wb"] == 0 then moveto(R.xa, R.ya) else lineto(R.xa, R.ya) end
      end)
    end)
  end)
end
-- \flo@bee: a bee or a hoverfly, size its length on the page in pt (sp)
function L.bee(size)
  V.bgu = E("(%1)/28.45276", { size })
  if R.bgu > K"0.25" then V.fine = U else V.fine = 0 end
  V.bgk = L.xtr("kind") V.bgpose = L.xtr("pose") V.bgground = L.xtr("ground")
  V.bgt = L.xtr("tone") V.bgpt = K"0.74"
  if R.bgground == "dark" then V.bgt = E"@bgt-0.12" end
  if R.bgground == "copper" then V.rampname = "flo@aramp" V.bgpt = K"0.6" end
  V.bgrx = E"0.48*@x@build" V.bgry = K"0.3" V.bgsq = U V.bgegg = K"1.12"
  V.bgtr = K"0.13" V.bghx = K"0.09" V.bghr = K"0.075"
  V.bgFl = K"0.52" V.bgFw = K"0.12" V.bgHl = K"0.38" V.bgHw = K"0.08" V.bgvn = "f"
  V.bgfw = K"0.032" V.bgpr = U
  V.bgabt = R.bgt V.bgtt = K"0.06" V.bght = K"0.04" V.bgfd = R.bgt
  V.bgspk = 4 * U V.bgrim = K"0.4"
  if R.bgk == "honeybee" then V.bgtt = E"max(0.06,@bgt-0.24)" end
  if R.bgk == "bumblebee" then
    V.bgegg = U V.bgtr = K"0.16" V.bghx = K"0.1" V.bgFl = K"0.48" V.bgFw = K"0.11"
    V.bgHl = K"0.34" V.bgfw = K"0.036" V.bgpr = K"1.2" V.bgabt = K"0.06" V.bgtt = K"0.05"
    V.bgfd = K"0.08" V.bgspk = 14 * U V.bgrim = K"0.15"
  end
  if R.bgk == "solitarybee" then
    V.bgry = K"0.32" V.bgtr = K"0.11" V.bghx = K"0.08" V.bgpr = K"0.9"
    V.bgabt = E"max(0.05,@bgt-0.24)"
  end
  if R.bgk == "hoverfly" then
    V.bgrx = E"0.42*@x@build" V.bgsq = K"0.8" V.bgegg = K"1.2" V.bgtr = K"0.12" V.bghx = K"0.13"
    V.bghr = K"0.085" V.bgFl = K"0.62" V.bgHl = 0 V.bgvn = "v" V.bgfw = K"0.022"
    V.bgabt = K"0.08" V.bgtt = K"0.08" V.bght = K"0.1" V.bgfd = K"0.25"
  end
  V.bgty = K"0.15" V.bghy = E"@bgty+@bgtr+0.04"
  V.bgat = E"@bgty-@bgtr+0.09" V.bgay = E"@bgat-@bgry"
  V.bgla = E"@bgry*(1+0.98*@bgegg)" V.bgtip = E"@bgat-@bgla"
  V.bglx = E"0.6+2*@bgrx"
  V.bgbp1 = "t" V.bgbp2 = "a" V.bgbp3 = "t" V.bgbp4 = "a"
  V.bgbh1 = E"@bgty+@bgtr+0.03" V.bgbl1 = E"@bgty+0.4*@bgtr"
  V.bgbh2 = E"@bgat-0.3*@bgla" V.bgbl2 = E"@bgat-0.5*@bgla"
  V.bgbh3 = E"@bgty-0.5*@bgtr" V.bgbl3 = E"@bgty-@bgtr-0.03"
  V.bgbh4 = E"@bgat+0.03" V.bgbl4 = E"@bgat-0.17*@bgla"
  V.bgtl = E"@bgat-0.7*@bgla"
  V.bgw = E"max(0.25,0.45*@bgu)" V.bglw = E"max(0.2,0.35*@bgu)"
  V.bgvw = E"max(0.15,0.25*@bgu)"
  V.bglp = "v" V.bgblur = 0 V.bgaf = -70 * U V.bgah = -78 * U V.bgdl = 0
  if R.bgpose == "fly" then V.bglp = "f" V.bgblur = U V.bgaf = 14 * U V.bgah = -4 * U V.bgdl = 16 * U end
  if R.bgpose == "rest" then V.bgaf = -45 * U end
  if R.bgpose == "hover" then V.bglp = "f" V.bgblur = U V.bgaf = 10 * U V.bgdl = 22 * U end
  if R.bgpose == "fly" then L.bgtrail() end
  loop("#Wa", 1, 2, function()
    scope(function() if R["#Wa"] == 2 then L.xscale(-U) end L.bglegs() end)
  end)
  L.bgabdomen() L.bgpaintab()
  if R.bgk ~= "hoverfly" and R.bgk ~= "bumblebee" then
    V.ya = E"@bgtip+0.04" V.yb = E"@bgtip-0.05"
    vtone("flo@c", K"0.05")
    vfill("flo@c", U, 0, function() moveto(K"-0.022", R.ya) lineto(0, R.yb) lineto(K"0.022", R.ya) closepath() end)
  end
  if R.bgk == "bumblebee" then
    V.bgnf = pm.int(E"24+60*@x@hair") V.bgrb = E"@bgry*@bgegg"
    L.bgfur(R.bgay, R.bgrx, I("bgnf"), R.bgry, R.bgrb, "a")
  end
  L.bgthorax()
  V.bgnf = pm.int(E"6+40*@x@hair") V.bgrb = E"@bgtr*0.93"
  L.bgfur(R.bgty, R.bgtr, I("bgnf"), R.bgrb, R.bgrb, "t")
  L.bghead() L.bgfeelers()
  loop("#Wa", 1, 2, function()
    scope(function() if R["#Wa"] == 2 then L.xscale(-U) end L.bgwings() end)
  end)
end
-- \flo@vlegs: the legs of a side (drawn to the right) from table t: per leg its root,
-- knee, foot and the end of its tarsus; see the TeX
L.LG = {
  o = { { "0.025", "0.03", "0.06", "0.06", "0.07", "0.11", "0.065", "0.15" },
    { "0.03", "0", "0.075", "0.02", "0.095", "0.07", "0.095", "0.1" },
    { "0.03", "-0.03", "0.085", "-0.03", "0.11", "0.01", "0.115", "0.045" } },
  b = { { "0.06", "0.08", "-0.06", "0.13", "0.02", "0.27", "0.04", "0.34" },
    { "0.08", "-0.04", "0", "-0.02", "0.1", "-0.1", "0.15", "-0.14" },
    { "0.08", "-0.12", "-0.02", "-0.24", "0.06", "-0.42", "0.08", "-0.5" } },
}
function L.lgpts(p)
  local i = R["#Wb"]
  if i == 2 then V.lgp = E"-(@lgph)" else V.lgp = R.lgph end
  V.t = E("(%1)*@lgx", { K(p[1]) }) V["lg" .. i .. "a"] = R.t
  V.t = E("@lgy+(%1)*@lgx", { K(p[2]) }) V["lg" .. i .. "b"] = R.t
  V.v = sym(R.lgj) V.t = E("(%1)*@lgx+@lgex+@v", { K(p[3]) }) V["lg" .. i .. "c"] = R.t
  V.v = sym(R.lgj) V.t = E("@lgy+(%1)*@lgx+@v", { K(p[4]) }) V["lg" .. i .. "d"] = R.t
  V.v = sym(R.lgj) V.lgfx = E("(%1)*@lgx+@lgex+@v", { K(p[5]) }) V["lg" .. i .. "e"] = R.lgfx
  V.v = sym(R.lgj) V.lgfy = E("@lgy+(%1)*@lgx+@lgp+@v", { K(p[6]) }) V["lg" .. i .. "f"] = R.lgfy
  V.t = E("@lgfx+((%1)-(%2))*@lgx", { K(p[7]), K(p[5]) }) V["lg" .. i .. "g"] = R.t
  V.t = E("@lgfy+((%1)-(%2))*@lgx", { K(p[8]), K(p[6]) }) V["lg" .. i .. "h"] = R.t
end
function L.lgseg(x0, y0, x1, y1)
  local a = { x0, y0, x1, y1 }
  V.xb = E("%1+(%3-(%1))/3", a) V.yb = E("%2+(%4-(%2))/3", a)
  V.xc = E("%1+(%3-(%1))*2/3", a) V.yc = E("%2+(%4-(%2))*2/3", a)
  vtaper(x0, y0, R.xb, R.yb, R.xc, R.yc, x1, y1)
end
function L.vlegs(t)
  loop("#Wb", 1, 3, function() L.lgpts(L.LG[t][R["#Wb"]]) end)
  vfill("flo@c", U, 0, function()
    loop("#Wb", 1, 3, function()
      local i = R["#Wb"]
      V.lga = R["lg" .. i .. "a"] V.lgb = R["lg" .. i .. "b"] V.lgc = R["lg" .. i .. "c"] V.lgd = R["lg" .. i .. "d"]
      V.lge = R["lg" .. i .. "e"] V.lgf = R["lg" .. i .. "f"] V.lgg = R["lg" .. i .. "g"] V.lgh = R["lg" .. i .. "h"]
      V.twa = R.lgw V.twb = E"@lgw*0.8" L.lgseg(R.lga, R.lgb, R.lgc, R.lgd)
      V.twa = E"@lgw*0.75" V.twb = E"@lgw*0.45" L.lgseg(R.lgc, R.lgd, R.lge, R.lgf)
      V.twa = E"@lgw*0.4" V.twb = E"@lgw*0.2" L.lgseg(R.lge, R.lgf, R.lgg, R.lgh)
    end)
  end)
end
-- dragonflies and damselflies (\flo@odo): the wings' outlines (along, across in units of
-- the width) and long veins (across at the root, middle and tip; 0 and 5 outside)
L.ODW = {
  f = { { "0.01", "0.35" }, { "0.12", "0.75" }, { "0.45", "0.95" }, { "0.8", "0.9" }, { "0.97", "0.55" },
    { "1", "0.1" }, { "0.93", "-0.45" }, { "0.7", "-0.75" }, { "0.35", "-0.85" }, { "0.08", "-0.6" } },
  h = { { "0.01", "0.35" }, { "0.15", "0.8" }, { "0.5", "0.95" }, { "0.85", "0.85" }, { "1", "0.3" },
    { "0.96", "-0.35" }, { "0.75", "-0.75" }, { "0.45", "-1" }, { "0.2", "-1.45" }, { "0.04", "-0.8" } },
  d = { { "0", "0.1" }, { "0.2", "0.2" }, { "0.45", "0.8" }, { "0.78", "0.98" }, { "0.98", "0.6" },
    { "1", "0" }, { "0.94", "-0.6" }, { "0.75", "-0.9" }, { "0.45", "-0.6" }, { "0.2", "-0.2" } },
}
L.ODV = {
  f = { [0] = { "1.3", "1.3", "1.3" }, { "0.45", "0.72", "0.5" }, { "0.15", "0.3", "0.05" },
    { "-0.1", "-0.3", "-0.45" }, { "-0.3", "-0.7", "-0.8" }, { "-1.6", "-1.6", "-1.6" } },
  h = { [0] = { "1.3", "1.3", "1.3" }, { "0.45", "0.72", "0.5" }, { "0.15", "0.3", "0.05" },
    { "-0.1", "-0.35", "-0.45" }, { "-0.4", "-0.9", "-0.8" }, { "-1.6", "-1.6", "-1.6" } },
  d = { [0] = { "1.3", "1.3", "1.3" }, { "0.06", "0.6", "0.4" }, { "0.02", "0.2", "0" },
    { "-0.02", "-0.25", "-0.4" }, { "-0.06", "-0.5", "-0.7" }, { "-1.6", "-1.6", "-1.6" } },
}
function L.odvat(k, u)
  local v = L.ODV[R.odwk][k]
  V.odvv = E("(%4<0.5 ? %1+(%2-(%1))*2*%4 : %2+(%3-(%2))*(2*%4-1))", { K(v[1]), K(v[2]), K(v[3]), u })
end
function L.odwingshape(t, l, w, name)
  loop("#Wb", 1, 10, function()
    local p = L.ODW[t][R["#Wb"]]
    V.t = sym(K"0.008") V.xa = E("%1*(%2)+@t", { K(p[1]), l })
    V.t = sym(K"0.008") V.ya = E("%1*(%2)+@t", { K(p[2]), w })
    put(R["#Wb"], R.xa, R.ya)
  end)
  smoothprep(10) keep(name)
end
function L.odvein(v)
  V.ya = E("(%1)*@odww", { K(v[1]) }) moveto(0, R.ya)
  V.xa = E"0.5*@odwl" V.ya = E("(%1)*@odww", { K(v[2]) }) lineto(R.xa, R.ya)
  V.ya = E("(%1)*@odww", { K(v[3]) }) lineto(R.odwl, R.ya)
end
function L.odwing(name, x, y, rot)
  scope(function()
    shift(x, y) rotate(rot)
    scope(function()
      V.rampname = "flo@ramp"
      vtone("flo@c", R.odwt) vfill("flo@c", R.odwo, 0, function() kept(name) end)
    end)
    scope(function()
      kept(name) usepath("clip")
      if L.xtr("tint") == "tinted" then
        V.xa = E"0.1*@odwl" V.ya = E"-0.2*@odww" V.xb = E"0.2*@odwl" V.yb = E"1.2*@odww"
        vtone("flo@c", K"0.45") vfill("flo@c", K"0.3", 0, function() L.bgell(R.xa, R.ya, R.xb, R.yb) end)
      end
      if L.xtr("stigma") == U then
        V.xa = E"0.83*@odwl" V.xb = E"0.91*@odwl" V.ya = E"1.3*@odww" V.yb = E"0.55*@odww"
        vtone("flo@c", K"0.06")
        vfill("flo@c", K"0.9", 0, function()
          moveto(R.xa, R.ya) lineto(R.xb, R.ya) lineto(R.xb, R.yb) lineto(R.xa, R.yb) closepath()
        end)
      end
      if R.fine == U then
        scope(function()
          V.rampname = "flo@ramp" vtone("flo@c", K"0.15")
          vstroke("flo@c", R.odvw, K"0.6", 0, function()
            loop("#Wc", 1, 4, function() L.odvein(L.ODV[R.odwk][R["#Wc"]]) end)
          end)
          if R.odnet == U then
            vtone("flo@c", K"0.2")
            vstroke("flo@c", R.odnw, K"0.45", 0, function()
              loop("#Wc", 1, 5, function()
                loop("#Wd", 1, 22, function()
                  V.t = sym(K"0.3") V.u = E"(#Wd-0.5+@t)/22*0.96+0.02"
                  L.odvat(R["#Wc"] - 1, R.u) V.ya = E"@odvv*@odww"
                  L.odvat(R["#Wc"], R.u) V.yb = E"@odvv*@odww"
                  V.xa = E"@u*@odwl" V.t = sym(K"0.01") V.xb = E"(@u+@t)*@odwl"
                  moveto(R.xa, R.ya) lineto(R.xb, R.yb)
                end)
              end)
            end)
          end
        end)
      end
    end)
    if R.fine == U then
      scope(function()
        V.rampname = "flo@ramp"
        vtone("flo@c", K"0.15") vstroke("flo@c", R.odlw, K"0.7", 0, function() kept(name) end)
      end)
    end
  end)
end
function L.odwings()
  L.odwingshape(R.odhk, R.odHl, R.odHw, "odwh") L.odwingshape(R.odfk, R.odFl, R.odFw, "odwf")
  V.ya = E"@odty-@odhd" V.odwk = R.odhk V.odwl = R.odHl V.odww = R.odHw
  L.odwing("odwh", R.odrx, R.ya, R.odah)
  V.ya = E"@odty+@odfd" V.odwk = R.odfk V.odwl = R.odFl V.odww = R.odFw
  L.odwing("odwf", R.odrx, R.ya, R.odaf)
end
function L.odabdomen()
  loop("#Wa", 0, 11, function()
    V.v = E"#Wa/11"
    V.h = E"@odaw*(1+@odbul*exp(-min(9,@v*@v/0.012)))*min(1,(1.04-@v)*5)"
    V.ya = E"@odat+(@odtip-@odat)*@v" V.xa = E"-@h"
    put(R["#Wa"] + 1, R.h, R.ya) put(24 - R["#Wa"], R.xa, R.ya)
  end)
  smoothprep(24) keep("odab")
end
-- \flo@odseg{e}: the end of segment e down the abdomen
function L.odseg(e) V.odsv = E("(" .. e .. ")<1 ? 0 : pow((" .. e .. ")/10,1.12)") end
function L.odpaintab()
  vtone("flo@c", R.odt) vfill("flo@c", U, 0, function() kept("odab") end)
  scope(function()
    kept("odab") usepath("clip")
    if L.xtr("bands") > 0 then
      vtone("flo@c", K"0.04")
      vfill("flo@c", K"0.85", 0, function()
        loop("#Wb", 1, function() return L.xtr("bands") // U end, function()
          V.odsn = (10 - L.xtr("bands") // U + R["#Wb"]) * U
          L.odseg("@odsn-1") V.odsa = R.odsv L.odseg("@odsn")
          V.ya = E"@odat+(@odtip-@odat)*(@odsa+0.6*(@odsv-@odsa))"
          V.yb = E"@odat+(@odtip-@odat)*@odsv-0.01"
          L.bgband(R.ya, R.yb, K"0.004")
        end)
      end)
    end
    if R.fine == U then
      vtone("flo@c", K"0.05")
      vstroke("flo@c", R.odjw, K"0.5", 0, function()
        loop("#Wb", 1, 9, function()
          L.odseg("#Wb") V.ya = E"@odat+(@odtip-@odat)*@odsv"
          moveto(K"-0.1", R.ya) lineto(K"0.1", R.ya)
        end)
      end)
      V.t = E"@odtip-@odat"
      V.xa = E"-0.4*@odaw" V.ya = E"@odat+0.06*@t" put(1, R.xa, R.ya)
      V.xa = E"-0.45*@odaw" V.ya = E"@odat+0.3*@t" put(2, R.xa, R.ya)
      V.xa = E"-0.45*@odaw" V.ya = E"@odat+0.6*@t" put(3, R.xa, R.ya)
      V.xa = E"-0.35*@odaw" V.ya = E"@odat+0.85*@t" put(4, R.xa, R.ya)
      V.stw = E"0.5*@odaw" vstreak(4, R.stw, K"0.004", "white", K"0.45")
    end
    vtone("flo@c", K"0.05") V.t = E"1.4*@odu" vstroke("flo@c", R.t, K"0.35", 1, function() kept("odab") end)
  end)
  if R.fine == U then
    V.ya = E"@odtip+0.012" V.yb = E"@odtip-0.022"
    V.xa = E"0.5*@odaw" V.xb = E"0.9*@odaw"
    vtone("flo@c", K"0.05")
    vstroke("flo@c", R.odjw, U, 0, function()
      moveto(-R.xa, R.ya) lineto(-R.xb, R.yb) moveto(R.xa, R.ya) lineto(R.xb, R.yb)
    end)
  end
end
function L.odthorax()
  vblob(0, R.odty, R.odtr, R.odth, K"0.06", 10) keep("odth")
  vtone("flo@c", R.odtt) vfill("flo@c", U, 0, function() kept("odth") end)
  scope(function()
    kept("odth") usepath("clip")
    if R.fine == U then
      V.twa = E"0.3*@odtr" V.twb = E"0.12*@odtr"
      vfill("white", K"0.35", 0, function()
        loop("#Wb", 1, 2, function()
          if R["#Wb"] == 1 then V.sx = -U else V.sx = U end
          V.xa = E"@sx*0.3*@odtr" V.ya = E"@odty+0.75*@odth"
          V.xd = E"@sx*0.6*@odtr" V.yd = E"@odty-0.45*@odth"
          L.lgseg(R.xa, R.ya, R.xd, R.yd)
        end)
      end)
    end
    vtone("flo@c", K"0.05") V.t = E"1.2*@odu" vstroke("flo@c", R.t, K"0.4", 1, function() kept("odth") end)
  end)
end
function L.odhead()
  vtone("flo@c", K"0.06") vfill("flo@c", U, 0, function() L.bgell(0, R.odhy, R.odhx, R.odhr) end)
  V.ya = E"@odhy+@odey"
  vtone("flo@c", R.odet)
  vfill("flo@c", U, 0, function() L.bgell(-R.odex, R.ya, R.oder, R.oder) L.bgell(R.odex, R.ya, R.oder, R.oder) end)
  if R.fine == U then
    V.xa = E"@odex-0.35*@oder" V.yb = E"@ya+0.4*@oder" V.t = E"0.22*@oder"
    vfill("white", K"0.7", 0, function() circle(-R.xa, R.yb, R.t) circle(R.xa, R.yb, R.t) end)
  end
end
-- \flo@odo: a dragonfly or a damselfly, size its length on the page in pt (sp)
function L.odo(size)
  V.odu = E("(%1)/28.45276", { size })
  if R.odu > K"0.4" then V.fine = U else V.fine = 0 end
  if R.odu > K"1.5" then V.odnet = U else V.odnet = 0 end
  V.odk = L.xtr("kind") V.odpose = L.xtr("pose") V.odground = L.xtr("ground")
  V.odt = L.xtr("tone")
  if R.odground == "dark" then V.odt = E"@odt-0.12" end
  if R.odground == "copper" then V.rampname = "flo@aramp" end
  V.odtt = E"max(0.05,@odt-0.08)" V.odet = E"max(0.06,@odt-0.1)"
  if L.xtr("tint") == "tinted" then V.odwt = K"0.7" V.odwo = K"0.42" else V.odwt = K"0.88" V.odwo = K"0.28" end
  V.odaw = K"0.032" V.odbul = K"0.7" V.odat = K"0.16" V.odtip = K"-0.62"
  V.odty = K"0.235" V.odtr = K"0.066" V.odth = K"0.08"
  V.odhy = K"0.34" V.odhx = K"0.075" V.odhr = K"0.048" V.odex = K"0.038" V.odey = K"0.006" V.oder = K"0.046"
  V.odfk = "f" V.odhk = "h" V.odFl = K"0.62" V.odFw = K"0.065" V.odHl = K"0.6" V.odHw = K"0.075"
  V.odrx = K"0.02" V.odfd = K"0.03" V.odhd = K"0.035" V.odaf = 8 * U V.odah = -6 * U
  V.lgx = U V.lgw = K"0.014"
  if R.odk == "damselfly" then
    V.odaw = K"0.016" V.odbul = K"0.5" V.odat = K"0.2" V.odtip = K"-0.66"
    V.odty = K"0.26" V.odtr = K"0.04" V.odth = K"0.058"
    V.odhy = K"0.34" V.odhx = K"0.075" V.odhr = K"0.028" V.odex = K"0.058" V.odey = 0 V.oder = K"0.026"
    V.odfk = "d" V.odhk = "d" V.odFl = K"0.5" V.odFw = K"0.06" V.odHl = K"0.48" V.odHw = K"0.06"
    V.odrx = K"0.012" V.odfd = K"0.02" V.odhd = K"0.02" V.odaf = -84 * U V.odah = -88 * U
    V.lgx = K"0.75" V.lgw = K"0.01"
    if R.odpose == "spread" then V.odaf = -38 * U V.odah = -50 * U else V.odFw = K"0.032" V.odHw = K"0.032" end
  end
  V.odlw = E"max(0.18,0.3*@odu)" V.odvw = E"max(0.12,0.22*@odu)"
  V.odnw = E"max(0.08,0.1*@odu)" V.odjw = E"max(0.1,0.18*@odu)"
  V.lgy = R.odty V.lgex = 0 V.lgj = K"0.006" V.lgph = 0
  vtone("flo@c", K"0.06")
  loop("#Wa", 1, 2, function()
    scope(function() if R["#Wa"] == 2 then L.xscale(-U) end L.vlegs("o") end)
  end)
  L.odabdomen() L.odpaintab() L.odthorax() L.odhead()
  loop("#Wa", 1, 2, function()
    scope(function() if R["#Wa"] == 2 then L.xscale(-U) end L.odwings() end)
  end)
end
-- beetles and ladybirds (\flo@beetle)
function L.btelytra()
  loop("#Wa", 1, 16, function()
    V.wa = E"22.5*#Wa-11.25" V.t = E"cos(@wa)" V.v = E"sin(@wa)"
    V.xa = E"@btew*(@t<0 ? -1 : 1)*pow(abs(@t),@btsq)"
    V.ya = E"@btey+@v*(@v<0 ? @btrb : @btrt)"
    put(R["#Wa"], R.xa, R.ya)
  end)
  smoothprep(16) keep("btel")
end
function L.btshield(pb, pf, pl)
  local a = { pb, pf, pl }
  V.btsa = E"@btet-@btso" V.btsb = E("@btet+(%3)", a) V.btsl = E"@btsb-@btsa"
  V.xa = E("0.55*(%1)", a) V.xb = E"-@xa" V.ya = E"@btsa-0.01" put(1, R.xa, R.ya) put(10, R.xb, R.ya)
  V.xa = E("%1", a) V.xb = E"-@xa" put(2, R.xa, R.btsa) put(9, R.xb, R.btsa)
  V.xa = E("@btsw*(%1)", a) V.xb = E"-@xa" V.ya = E"@btsa+0.45*@btsl" put(3, R.xa, R.ya) put(8, R.xb, R.ya)
  V.xa = E("%2", a) V.xb = E"-@xa" V.ya = E"@btsb-0.15*@btsl" put(4, R.xa, R.ya) put(7, R.xb, R.ya)
  V.xa = E("0.5*(%2)", a) V.xb = E"-@xa" put(5, R.xa, R.btsb) put(6, R.xb, R.btsb)
  smoothprep(10) keep("btpn")
end
function L.bthw(y)
  V.t = E("(%1-@btey)/(%1>@btey ? @btrt : @btrb)", { y })
  V.h = E"@btew*sqrt(max(0,1-@t*@t))"
end
function L.btstripes()
  V.t = E"@btet-@bttip" V.twa = K"0.045" V.twb = K"0.012"
  vfill("flo@c", K"0.8", 0, function()
    loop("#Wb", 1, 4, function()
      if R["#Wb"] < 3 then V.sx = U else V.sx = -U end
      if R["#Wb"] % 2 == 1 then V.u = K"0.36" else V.u = K"0.72" end
      V.xa = E"@sx*@u*@btew" V.ya = E"@btet-0.03"
      V.xb = E"@xa*1.04" V.yb = E"@btet-0.35*@t"
      V.xc = E"@xa*0.9" V.yc = E"@btet-0.7*@t"
      V.xd = E"@xa*0.35" V.yd = E"@bttip+0.06"
      vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd)
    end)
  end)
end
function L.btspot(x, y, r)
  V.t = range(K"0.85", K"1.1") V.btsr = E("(%1)*@t", { r }) V.t = E"@btsr*0.92"
  vblob(x, y, R.btsr, R.t, K"0.1", 8) vfill("flo@c", K"0.95", 0, smoothpath)
end
function L.btspots()
  V.btm = pm.int(E"floor(@x@spots/2)")
  V.btr = E"@x@spotsize*@btew*1.6/sqrt(max(1,@btm))"
  if I("btm") < 4 then V.btc = U elseif I("btm") < 8 then V.btc = 2 * U else V.btc = 3 * U end
  V.btrows = pm.int(E"floor((@btm+@btc-1)/@btc)")
  V.t = E"@x@spots-2*@btm"
  if R.t > 0 then V.ya = E"@btet-@btso-0.6*@btr" V.v = E"1.15*@btr" L.btspot(0, R.ya, R.v) end
  loop("#Wb", 1, function() return I("btm") end, function()
    V.btrow = pm.int(E"floor((#Wb-1)/@btc)")
    V.btcol = pm.int(E"#Wb-1-@btc*@btrow")
    V.t = sym(K"0.04") V.v = E"(@btrow+0.5)/@btrows+@t"
    local c = I("btc")
    if c == 1 then V.u = E"@btm==1 ? 0.5 : (@btrow==1 ? 0.4 : 0.62)"
    elseif c == 2 then
      V.u = E"(@btcol==0 ? 0.33 : 0.7)"
      if R["#Wb"] == I("btm") and I("btcol") == 0 then V.u = K"0.5" end
    else V.u = E"0.2+0.3*@btcol" end
    V.t = sym(K"0.05") V.u = E"@u+@t"
    V.bty = E"@btet-@btso-0.04-@v*(@btet-@btso-@bttip-0.08)" L.bthw(R.bty)
    V.btx = E"@u*@h"
    L.btspot(R.btx, R.bty, R.btr) L.btspot(-R.btx, R.bty, R.btr)
  end)
end
function L.btmark()
  if R.btground == "dark" then
    if R.btk == "ladybird" then vaccent("flo@c", 0) else vtone("flo@c", K"0.8") end
  else vtone("flo@c", K"0.04") end
end
function L.btpaintel()
  vtone("flo@c", R.btt) vfill("flo@c", U, 0, function() kept("btel") end)
  scope(function()
    kept("btel") usepath("clip")
    V.btpat = L.xtr("pattern")
    if R.btpat == "stripes" then L.btmark() L.btstripes() end
    if R.btpat == "spots" then L.btmark() L.btspots() end
    if R.fine == U then
      V.btxl = E"-@btew" V.ta = E"@btt-0.06" V.tb = E"@btt+0.2"
      vmottle(R.btxl, R.bttip, R.btew, R.btet, 3, K"0.08", R.ta, R.tb, 0)
    end
    vtone("flo@c", K"0.04") V.t = E"2.6*@btu" vstroke("flo@c", R.t, K"0.35", 1, function() kept("btel") end)
    if R.fine == U then
      V.btln = E"(@btet-@bttip)*@btgl" V.stw = E"0.14*@btew"
      loop("#Wb", 1, 2, function()
        if R["#Wb"] == 1 then V.sx = -U V.sto = K"0.55" else V.sx = U V.sto = K"0.3" end
        V.xa = E"@sx*0.5*@btew" V.ya = E"@btet-@btso-0.06*@btln" put(1, R.xa, R.ya)
        V.xa = E"@sx*0.56*@btew" V.ya = E"@btet-@btso-0.23*@btln" put(2, R.xa, R.ya)
        V.xa = E"@sx*0.54*@btew" V.ya = E"@btet-@btso-0.43*@btln" put(3, R.xa, R.ya)
        V.xa = E"@sx*0.45*@btew" V.ya = E"@btet-@btso-0.6*@btln" put(4, R.xa, R.ya)
        vstreak(4, R.stw, K"0.01", "white", R.sto)
      end)
    end
  end)
  vtone("flo@c", K"0.04")
  vstroke("flo@c", R.btw, K"0.8", 0, function() moveto(0, R.btet) lineto(0, R.bttip) end)
end
function L.btfeeler()
  V.t = L.xtr("antenna")
  V.xa = E"0.35*@bthx" V.ya = E"@bthy+0.6*@bthr"
  if R.t == "thread" then V.xb = range(K"0.1", K"0.14") V.yb = range(K"0.1", K"0.14")
    V.xc = range(K"0.2", K"0.28") V.yc = range(K"0.24", K"0.32") end
  if R.t == "clubbed" then V.xb = range(K"0.06", K"0.08") V.yb = range(K"0.06", K"0.08")
    V.xc = range(K"0.1", K"0.13") V.yc = range(K"0.12", K"0.15") end
  if R.t == "comb" then V.xb = range(K"0.08", K"0.1") V.yb = range(K"0.08", K"0.1")
    V.xc = range(K"0.16", K"0.2") V.yc = range(K"0.18", K"0.22") end
  V.xb = E"@xa+@xb*@btfs" V.yb = E"@ya+@yb*@btfs"
  V.xc = E"@xa+@xc*@btfs" V.yc = E"@ya+@yc*@btfs"
  vstroke("flo@c", R.btw, U, 0, function() moveto(R.xa, R.ya) lineto(R.xb, R.yb) lineto(R.xc, R.yc) end)
  if R.t == "clubbed" then
    V.da = E"@xc-@xb" V.db = E"@yc-@yb" nrm(R.da, R.db, "nx", "ny")
    V.xd = E"@ny*0.034*@btfs" V.yd = E"-(@nx)*0.034*@btfs"
    V.xe = E"@nx*0.02*@btfs" V.ye = E"@ny*0.02*@btfs"
    vfill("flo@c", U, 0, function() L.pellipse(R.xc, R.yc, R.xd, R.yd, R.xe, R.ye) end)
  end
  if R.t == "comb" and R.fine == U then
    V.da = E"@xc-@xb" V.db = E"@yc-@yb" nrm(R.da, R.db, "nx", "ny")
    V.t = E"0.6*@btw"
    vstroke("flo@c", R.t, U, 0, function()
      loop("#Wc", 1, 6, function()
        V.v = E"#Wc/6"
        V.xd = E"@xb+@v*@da" V.yd = E"@yb+@v*@db"
        V.xe = E"@xd-@nx*0.035*@btfs" V.ye = E"@yd-@ny*0.035*@btfs"
        moveto(R.xd, R.yd) lineto(R.xe, R.ye)
      end)
    end)
  end
end
function L.bthead()
  vtone("flo@c", R.btht) vfill("flo@c", U, 0, function() L.bgell(0, R.bthy, R.bthx, R.bthr) end)
  if R.btk == "ladybird" then
    if R.fine == U then
      V.xa = E"0.45*@bthx" V.ya = E"@bthy+0.3*@bthr" V.t = E"0.22*@bthx"
      L.bgwhite() vfill("flo@c", K"0.9", 0, function() circle(-R.xa, R.ya, R.t) circle(R.xa, R.ya, R.t) end)
    end
  else
    V.xa = E"0.82*@bthx" V.ya = E"@bthy+0.1*@bthr" V.xb = E"0.24*@bthx" V.yb = E"0.42*@bthr"
    vtone("flo@c", K"0.02")
    vfill("flo@c", U, 0, function() L.bgell(-R.xa, R.ya, R.xb, R.yb) L.bgell(R.xa, R.ya, R.xb, R.yb) end)
    if R.fine == U then
      V.twa = E"0.3*@bthx" V.twb = K"0.004"
      vtone("flo@c", K"0.05")
      vfill("flo@c", U, 0, function()
        loop("#Wb", 1, 2, function()
          if R["#Wb"] == 1 then V.sx = -U else V.sx = U end
          V.xa = E"@sx*0.4*@bthx" V.ya = E"@bthy+0.8*@bthr"
          V.xb = E"@sx*0.5*@bthx" V.yb = E"@bthy+1.25*@bthr"
          V.xc = E"@sx*0.3*@bthx" V.yc = E"@bthy+1.55*@bthr"
          V.xd = E"@sx*0.08*@bthx" V.yd = E"@bthy+1.6*@bthr"
          vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd)
        end)
      end)
    end
  end
end
function L.btpaintpn()
  vtone("flo@c", R.btpt) vfill("flo@c", U, 0, function() kept("btpn") end)
  scope(function()
    kept("btpn") usepath("clip")
    if R.btk == "ladybird" then
      V.xa = E"0.72*@btpb" V.ya = E"@btsa+0.62*@btsl"
      V.xb = E"0.3*@btpb" V.yb = E"0.4*@btsl"
      L.bgwhite()
      vfill("flo@c", K"0.95", 0, function() L.bgell(-R.xa, R.ya, R.xb, R.yb) L.bgell(R.xa, R.ya, R.xb, R.yb) end)
    end
    if R.fine == U then
      V.xa = E"-0.55*@btpb" V.ya = E"@btsa+0.3*@btsl" put(1, R.xa, R.ya)
      V.xa = E"-0.4*@btpb" V.ya = E"@btsa+0.62*@btsl" put(2, R.xa, R.ya)
      V.xa = E"-0.2*@btpb" V.ya = E"@btsa+0.8*@btsl" put(3, R.xa, R.ya)
      V.stw = E"0.12*@btsl" vstreak(3, R.stw, K"0.006", "white", K"0.4")
    end
    vtone("flo@c", K"0.03") V.t = E"2*@btu" vstroke("flo@c", R.t, K"0.35", 1, function() kept("btpn") end)
  end)
end
-- \flo@beetle: a beetle or a ladybird, size its length on the page in pt (sp)
function L.beetle(size)
  V.btu = E("(%1)/28.45276", { size })
  if R.btu > K"0.25" then V.fine = U else V.fine = 0 end
  V.btk = L.xtr("kind") V.btground = L.xtr("ground")
  V.btt = L.xtr("tone")
  if R.btground == "dark" then
    V.btt = E"max(0.04,@btt-0.22)"
    if R.btk == "ladybird" then V.btt = K"0.06" end
  end
  if R.btground == "copper" then V.rampname = "flo@aramp" end
  V.btew = E"0.5*@x@build" V.btet = K"0.14" V.bttip = K"-0.56" V.btrt = K"0.12" V.btsq = K"0.7"
  V.btpb = E"0.88*@btew" V.btpf = E"0.62*@btew" V.btpl = K"0.17" V.btso = K"0.012" V.btsw = K"1.02"
  V.bthx = E"0.36*@btew" V.bthr = K"0.065" V.bthy = K"0.36" V.btfs = U V.btgl = U
  V.btpt = E"max(0.04,@btt-0.06)" V.btht = E"max(0.04,@btt-0.1)"
  V.lgw = K"0.03" V.lgj = K"0.015" V.lgx = U V.lgex = E"@btew" V.btly = 0
  if R.btk == "ladybird" then
    V.btet = K"0.22" V.bttip = K"-0.5" V.btrt = K"0.36" V.btsq = U
    V.btpb = E"0.6*@btew" V.btpf = E"0.4*@btew" V.btpl = K"0.05" V.btso = K"0.075" V.btsw = K"0.92"
    V.bthx = E"0.3*@btew" V.bthr = K"0.055" V.bthy = K"0.27" V.btfs = K"0.45" V.btgl = K"0.55"
    V.btpt = K"0.04" V.btht = K"0.04" V.lgw = K"0.032" V.lgj = K"0.01" V.lgx = K"0.7"
    V.lgex = E"0.8*@btew" V.btly = K"0.12"
  end
  V.btey = E"@btet-@btrt" V.btrb = E"@btey-@bttip"
  V.btw = E"max(0.25,0.4*@btu)"
  V.lgy = E"@btet-@btly"
  vtone("flo@c", K"0.05")
  loop("#Wa", 1, 2, function()
    scope(function()
      if R["#Wa"] == 2 then L.xscale(-U) V.lgph = K"-0.04" else V.lgph = K"0.04" end
      L.vlegs("b")
    end)
  end)
  vtone("flo@c", K"0.05")
  loop("#Wa", 1, 2, function()
    scope(function() if R["#Wa"] == 2 then L.xscale(-U) end L.btfeeler() end)
  end)
  L.bthead() L.btelytra() L.btpaintel()
  L.btshield(R.btpb, R.btpf, R.btpl) L.btpaintpn()
  if R.btk ~= "ladybird" then
    V.ya = E"@btet+0.004" V.yb = E"@btet-0.05"
    vtone("flo@c", R.btpt)
    vfill("flo@c", U, 0, function() moveto(K"-0.035", R.ya) lineto(K"0.035", R.ya) lineto(0, R.yb) closepath() end)
  end
end
-- caterpillars on their host leaf (\flo@caterpillar); see the TeX
function L.hfw(v)
  V.h = E("@hfW*pow(sin(180*pow(%1,0.8)),0.85)", { v }) V.hfx = E("@hfbend*(%1)*(%1)", { v })
end
function L.hfoutline()
  put(1, 0, 0) V.xa = E"@hfbend" put(25, R.xa, R.hfL)
  loop("#Wa", 1, 23, function()
    V.v = E"#Wa/24" L.hfw(R.v) V.ya = E"@v*@hfL"
    V.xa = E"@hfx+@h" V.xb = E"@hfx-@h"
    loop("#Wb", 1, function() return I("hfnb") end, function()
      local i = R["#Wb"]
      local br, bx = R["hfbr" .. i], R["hfbx" .. i]
      V.t = E("abs(@ya-%1)", { R["hfby" .. i] })
      V.xa = E("@t<%1 ? min(@xa,%2-sqrt(max(0,%1*%1-@t*@t))) : @xa", { br, bx })
    end)
    put(R["#Wa"] + 1, R.xa, R.ya) put(49 - R["#Wa"], R.xb, R.ya)
  end)
  smoothprep(48) keep("hfl")
end
function L.hfpaint()
  scope(function()
    V.rampname = "flo@ramp"
    vtone("flo@c", K"0.2") V.twa = K"0.028" V.twb = K"0.02"
    vfill("flo@c", U, 0, function() vtaper(0, K"-0.14", 0, K"-0.09", 0, K"-0.05", 0, K"0.02") end)
    vtone("flo@c", R.hft) vfill("flo@c", U, 0, function() kept("hfl") end)
    scope(function()
      kept("hfl") usepath("clip")
      V.t = E"@hft-0.12" vtone("flo@c", R.t)
      vfill("flo@c", K"0.35", 1, function()
        moveto(-U, 0) lineto(0, 0)
        loop("#Wa", 1, 8, function() V.v = E"#Wa/8" L.hfw(R.v) V.ya = E"@v*@hfL" lineto(R.hfx, R.ya) end)
        lineto(-U, R.hfL) closepath()
      end)
      if R.fine == U then
        V.hfxl = E"-@hfW" V.ta = E"@hft-0.16" V.tb = E"@hft+0.18"
        vmottle(R.hfxl, 0, R.hfW, R.hfL, 6, K"0.12", R.ta, R.tb, 8)
        V.twa = K"0.022" V.twb = K"0.004"
        vfill("white", K"0.5", 0, function()
          L.hfw(K"0.33") V.xb = E"@hfx" V.yb = E"0.33*@hfL"
          L.hfw(K"0.67") V.xc = E"@hfx" V.yc = E"0.67*@hfL"
          L.hfw(K"0.97") V.xd = E"@hfx" V.yd = E"0.97*@hfL"
          vtaper(0, 0, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd)
        end)
        V.twa = K"0.014" V.twb = K"0.002"
        vfill("white", K"0.4", 0, function()
          loop("#Wa", 1, 10, function()
            if R["#Wa"] % 2 == 1 then V.sx = U else V.sx = -U end
            V.v = E"0.1+0.15*floor((#Wa-1)/2)" L.hfw(R.v)
            V.xa = E"@hfx" V.ya = E"@v*@hfL"
            V.xd = E"@hfx+@sx*0.85*@h" V.yd = E"@ya+0.09*@hfL"
            V.xb = E"@xa+(@xd-@xa)*0.4" V.yb = E"@ya+(@yd-@ya)*0.15"
            V.xc = E"@xa+(@xd-@xa)*0.75" V.yc = E"@ya+(@yd-@ya)*0.55"
            vtaper(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd)
          end)
        end)
      end
      vtone("flo@c", K"0.06") V.t = E"0.9*@ctu" vstroke("flo@c", R.t, K"0.4", 1, function() kept("hfl") end)
    end)
  end)
end
function L.ctangle(s)
  if R.ctpose == "loop" then V.cta = E("105*cos(180*(%1))", { s })
  elseif R.ctpose == "curl" then V.cta = E("150-300*(%1)", { s })
  else V.cta = E("@ctwa*sin(540*(%1)+@ctph)", { s }) end
end
function L.ctspine()
  V.ctX0 = 0 V.ctY0 = 0
  loop("#Wa", 0, 26, function()
    local k = R["#Wa"]
    V.v = E"#Wa/26"
    if k > 0 then
      V.t = E"(#Wa-0.5)/26" L.ctangle(R.t)
      V.xa = E("%1+cos(@cta)/26", { R["ctX" .. (k - 1)] }) V.ya = E("%1+sin(@cta)/26", { R["ctY" .. (k - 1)] })
      V["ctX" .. k] = R.xa V["ctY" .. k] = R.ya
    end
    L.ctangle(R.v) V["ctA" .. k] = R.cta
    V.t = E"-sin(@cta)" V["ctNX" .. k] = R.t
    V.t = E"cos(@cta)" V["ctNY" .. k] = R.t
    V.t = E"@ctW*(0.7+0.3*sin(180*min(1,1.6*@v)))*(@v>0.92 ? 1-(@v-0.92)*2.5 : 1)" V["ctW" .. k] = R.t
  end)
end
function L.ctat(k, f, g)
  local x, y, w, nx, ny = R["ctX" .. k], R["ctY" .. k], R["ctW" .. k], R["ctNX" .. k], R["ctNY" .. k]
  V.xa = E("%1+(%2)*%3*%4+(%5)*%3*%6", { x, f, w, nx, g, ny })
  V.ya = E("%1+(%2)*%3*%4-(%5)*%3*%6", { y, f, w, ny, g, nx })
end
function L.ctoutline()
  loop("#Wa", 0, 26, function()
    L.ctat(R["#Wa"], -U, 0) put(R["#Wa"] + 1, R.xa, R.ya)
    L.ctat(R["#Wa"], U, 0) put(54 - R["#Wa"], R.xa, R.ya)
  end)
  L.ctat(0, 0, K"-0.7") put(55, R.xa, R.ya)
  smoothprep(55) keep("ctb")
end
function L.ctleg(k, a, b, g)
  L.ctat(k, -a, 0) V.ctlx = R.xa V.ctly = R.ya
  L.ctat(k, -b, g) V.xd = R.xa V.yd = R.ya
  L.lgseg(R.ctlx, R.ctly, R.xd, R.yd)
end
function L.ctline(a, b, step, f)
  V.ctn = 0
  loop("#Wb", 0, (b - a) // step, function()
    V.ctn = R.ctn + 1
    L.ctat(a + step * R["#Wb"], f, 0) put(R.ctn, R.xa, R.ya)
  end)
end
L.CTPRO = { 1, 9, 11, 13, 15 }
function L.ctbody()
  V.twa = E"0.9*@ctW" V.twb = E"0.65*@ctW"
  V.t = E"max(0.05,@ctt-0.08)" vtone("flo@c", R.t)
  vfill("flo@c", U, 0, function()
    loop("#Wa", 1, 5, function()
      local k = L.CTPRO[R["#Wa"]]
      if R.ctpose == "loop" and R["#Wa"] > 2 then k = nil end
      if k then L.ctleg(k, K"0.5", K"1.45", K"-0.1") end
    end)
  end)
  V.twa = E"0.35*@ctW" V.twb = E"0.06*@ctW"
  vtone("flo@c", K"0.08")
  vfill("flo@c", U, 0, function()
    loop("#Wa", 0, 2, function() L.ctleg(21 + 2 * R["#Wa"], K"0.6", K"1.55", K"0.35") end)
  end)
  L.ctoutline()
  vtone("flo@c", R.ctt) vfill("flo@c", U, 0, function() kept("ctb") end)
  scope(function()
    kept("ctb") usepath("clip")
    V.t = E"@ctt-0.12" vtone("flo@c", R.t)
    vfill("flo@c", K"0.35", 1, function()
      loop("#Wa", 0, 26, function()
        L.ctat(R["#Wa"], 0, 0)
        if R["#Wa"] == 0 then moveto(R.xa, R.ya) else lineto(R.xa, R.ya) end
      end)
      loop("#Wa", 0, 26, function() L.ctat(26 - R["#Wa"], K"-1.4", 0) lineto(R.xa, R.ya) end)
      closepath()
    end)
    V.t = L.xtr("stripes")
    if R.t == "side" then
      L.ctline(1, 25, 2, K"-0.2") V.stw = E"0.45*@ctW" V.sto = E"0.3*@ctW"
      vstreak(13, R.stw, R.sto, "white", K"0.6")
      if R.fine == U then
        V.ctsr = E"0.13*@ctW" V.ctsq = E"0.09*@ctW"
        vtone("flo@c", K"0.04")
        vfill("flo@c", K"0.85", 0, function()
          loop("#Wa", 1, 9, function()
            L.ctat(1 + 2 * R["#Wa"], K"0.08", 0) L.bgell(R.xa, R.ya, R.ctsq, R.ctsr)
          end)
        end)
      end
    end
    if R.t == "back" then
      L.ctline(1, 25, 2, K"0.72") V.stw = E"0.42*@ctW" V.sto = E"0.3*@ctW"
      vtone("flo@c", K"0.05") vstreak(13, R.stw, R.sto, "flo@c", K"0.7")
    end
    if R.fine == U then
      vtone("flo@c", K"0.05")
      vstroke("flo@c", R.ctjw, K"0.4", 1, function()
        loop("#Wa", 1, 12, function()
          L.ctat(2 * R["#Wa"], K"-1.3", 0) moveto(R.xa, R.ya)
          L.ctat(2 * R["#Wa"], K"1.3", 0) lineto(R.xa, R.ya)
        end)
      end)
      V.ctxl = K"-0.2" V.ctyl = K"-0.4" V.ctxh = K"1.1" V.ctyh = K"0.8"
      V.ta = E"@ctt-0.14" V.tb = E"@ctt+0.18"
      vmottle(R.ctxl, R.ctyl, R.ctxh, R.ctyh, 5, K"0.05", R.ta, R.tb, 10)
      L.ctline(2, 24, 2, K"0.45") V.stw = E"0.3*@ctW"
      vstreak(12, R.stw, K"0.004", "white", K"0.4")
    end
    vtone("flo@c", K"0.05") V.t = E"0.9*@ctu" vstroke("flo@c", R.t, K"0.6", 1, function() kept("ctb") end)
  end)
end
function L.cthead()
  L.ctat(26, 0, K"0.5") V.cthx = R.xa V.cthy = R.ya
  V.xb = E"@ctNY26*0.92*@ctW" V.yb = E"-@ctNX26*0.92*@ctW"
  V.xc = E"@ctNX26*0.85*@ctW" V.yc = E"@ctNY26*0.85*@ctW"
  vtone("flo@c", R.ctht)
  vfill("flo@c", U, 0, function() L.pellipse(R.cthx, R.cthy, R.xb, R.yb, R.xc, R.yc) end)
  if R.fine == U then
    V.xa = E"@cthx+0.35*@xb+0.15*@xc" V.ya = E"@cthy+0.35*@yb+0.15*@yc"
    V.t = E"0.13*@ctW" vtone("flo@c", K"0.02") vfill("flo@c", U, 0, function() circle(R.xa, R.ya, R.t) end)
    V.xa = E"@cthx-0.25*@xb+0.45*@xc" V.ya = E"@cthy-0.25*@yb+0.45*@yc"
    V.t = E"0.1*@ctW" vfill("white", K"0.6", 0, function() circle(R.xa, R.ya, R.t) end)
    V.xa = E"@cthx+0.8*@xb-0.45*@xc" V.ya = E"@cthy+0.8*@yb-0.45*@yc"
    V.xd = E"@cthx+1.2*@xb-0.75*@xc" V.yd = E"@cthy+1.2*@yb-0.75*@yc"
    V.twa = E"0.25*@ctW" V.twb = E"0.05*@ctW"
    vtone("flo@c", K"0.04") vfill("flo@c", U, 0, function() L.lgseg(R.xa, R.ya, R.xd, R.yd) end)
  end
end
function L.cthorn()
  L.ctat(5, K"0.8", 0) V.xe = R.xa V.ye = R.ya
  L.ctat(5, K"2.4", K"-1.6") V.xd = R.xa V.yd = R.ya
  L.ctat(5, K"1.7", 0) V.xb = R.xa V.yb = R.ya
  L.ctat(5, K"2.4", K"-0.7") V.xc = R.xa V.yc = R.ya
  V.twa = E"0.5*@ctW" V.twb = E"0.05*@ctW"
  vtone("flo@c", K"0.08")
  vfill("flo@c", U, 0, function() vtaper(R.xe, R.ye, R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
end
function L.cthair(k, len, g, deg)
  L.ctat(k, K"0.85", g) V.xe = R.xa V.ye = R.ya
  V.t = E("%1+90+(%2)", { R["ctA" .. k], deg })
  V.xd = E("@xe+(%1)*@ctW*cos(@t)", { len }) V.yd = E("@ye+(%1)*@ctW*sin(@t)", { len })
  L.lgseg(R.xe, R.ye, R.xd, R.yd)
end
function L.cttufts()
  V.twa = E"0.1*@ctW" V.twb = E"0.02*@ctW"
  L.bgwhite()
  vfill("flo@c", K"0.9", 0, function()
    loop("#Wa", 1, 4, function()
      loop("#Wb", 1, 9, function()
        V.ctl = range(K"1.2", K"1.8") V.ctg = range(K"-0.25", K"0.25")
        L.cthair(9 + 2 * R["#Wa"], R.ctl, R.ctg, E"(#Wb-5)*8")
      end)
    end)
  end)
  vtone("flo@c", K"0.08")
  vfill("flo@c", K"0.9", 0, function()
    loop("#Wa", 1, 5, function()
      V.ctl = range(K"2.4", K"3") L.cthair(24, R.ctl, 0, E"#Wa*6-48")
      V.ctl = range(K"2", K"2.6") L.cthair(2, R.ctl, 0, E"#Wa*6+12")
    end)
  end)
end
-- \flo@caterpillar: a caterpillar on its leaf, size its length on the page in pt (sp)
function L.caterpillar(size)
  V.ctu = E("(%1)/28.45276", { size })
  if R.ctu > K"0.25" then V.fine = U else V.fine = 0 end
  V.ctpose = L.xtr("pose") V.ctground = L.xtr("ground") V.ctt = L.xtr("tone")
  if R.ctground == "pale" then V.ctt = E"min(0.6,@ctt+0.22)" end
  V.ctW = E"@x@build/2" V.ctht = E"max(0.05,@ctt-0.16)"
  V.ctjw = E"max(0.1,0.16*@ctu)"
  V.ctwa = range(K"3", K"7") V.ctph = range(0, 360 * U) L.ctspine()
  V.hfL = K"1.5" V.hfW = K"0.36" V.hfbend = sym(K"0.12") V.hft = K"0.66"
  L.hfw(K"0.1") V.ctox = E"@hfx+@h" V.ctoy = E"0.1*@hfL"
  L.hfw(K"0.62") V.t = E"atan2(0.62*@hfL-@ctoy,@hfx+@h-@ctox)"
  if R.ctpose == "curl" then V.ctrot = R.t else V.ctrot = E"@t-atan2(@ctY26,@ctX26)" end
  V.cthy = E"@ctoy+@ctX26*sin(@ctrot)+@ctY26*cos(@ctrot)"
  if chance(K"0.5") then V.hfnb = 3 * U else V.hfnb = 2 * U end
  V.t = E"min(0.86*@hfL,max(0.3*@hfL,@cthy+0.04))"
  loop("#Wa", 1, function() return I("hfnb") end, function()
    local i = R["#Wa"]
    V.v = range(K"0.07", K"0.11") V["hfbr" .. i] = R.v
    V["hfby" .. i] = R.t
    V.v = E"@t/@hfL" L.hfw(R.v)
    V.v = E("@hfx+@h+0.3*%1", { R["hfbr" .. i] }) V["hfbx" .. i] = R.v
    V.v = range(K"0.15", K"0.22") V.t = E"@t+@v"
    if R.t > K"1.38" then V.t = K"1.38" end
  end)
  L.hfoutline() L.hfpaint()
  if R.ctground == "copper" then V.rampname = "flo@aramp" end
  scope(function()
    shift(R.ctox, R.ctoy) rotate(R.ctrot)
    L.ctbody() L.cthead()
    if L.xtr("horn") == U then L.cthorn() end
    if L.xtr("tufts") == U then L.cttufts() end
  end)
end
-- snails (\flo@snail)
function L.gsbodypt(i, x, y)
  V.t = sym(K"0.08") V.xa = E("(%1)*(1+@t)", { K(x) })
  V.ya = E("(%1)*((%1)<0 ? 0.5+0.5*@gsx : 0.75+0.3*@gsx)", { K(y) }) put(i, R.xa, R.ya)
end
function L.gsspiral(t, f)
  V.t = E("pow(@gsE,-(1-(%1))*@gsn)", { t })
  V.wa = E("180-(1-(%1))*@gsn*360", { t }) V.v = E"@gsH*(1-@t)"
  V.xa = E("@gscx+@v*cos(-40)+(%1)*0.95*@gsR*@t*cos(@wa)", { f })
  V.ya = E("@gscy+@v*sin(-40)+(%1)*0.95*@gsR*@t*sin(@wa)", { f })
end
function L.gsline(f, t0, n)
  loop("#Wb", 0, n - 1, function()
    V.gst = E("%1+(1-(%1))*#Wb/(%2-1)", { t0, n * U }) L.gsspiral(R.gst, f) put(R["#Wb"] + 1, R.xa, R.ya)
  end)
end
L.GSBODY = { { "0", "-0.78" }, { "-0.01", "-0.3" }, { "0", "0.3" }, { "0.04", "0.58" }, { "0.12", "0.7" },
  { "0.22", "0.66" }, { "0.24", "0.5" }, { "0.2", "0.32" }, { "0.17", "0" }, { "0.12", "-0.45" }, { "0.05", "-0.7" } }
function L.gsbody()
  for i, p in ipairs(L.GSBODY) do L.gsbodypt(i, p[1], p[2]) end
  smoothprep(11) keep("gsb")
  V.gstb = range(K"0.5", K"0.6")
  vtone("flo@c", R.gstb) vfill("flo@c", U, 0, function() kept("gsb") end)
  scope(function()
    kept("gsb") usepath("clip")
    if R.fine == U then
      V.ta = E"@gstb-0.25" V.tb = E"@gstb+0.15"
      vmottle(K"-0.1", K"-0.8", K"0.3", K"0.8", 5, K"0.1", R.ta, R.tb, 10)
    end
    vtone("flo@c", K"0.15")
    vfill("flo@c", K"0.35", 1, function()
      moveto(K"-0.05", K"-0.8") lineto(K"-0.05", K"0.7") lineto(K"0.04", K"0.7") lineto(K"0.04", K"-0.8") closepath()
    end)
    vtone("flo@c", K"0.08") V.t = E"0.1*@gsu*28.3465" vstroke("flo@c", R.t, K"0.4", 1, function() kept("gsb") end)
  end)
end
function L.gsfeeler(x0, y0, x1, y1, w)
  local a = { K(x0), K(y0), K(x1), K(y1) }
  V.ya = E("(%2)*(0.75+0.3*@gsx)", a) V.t = E"0.55+0.5*@gsx"
  V.xd = E("%1+((%3)-(%1))*@t", a) V.yd = E("@ya+((%4)-(%2))*@t", a)
  V.xb = E("%1+0.02", a) V.yb = E"@ya+0.12" V.xc = E"@xd-0.04" V.yc = E"@yd-0.1"
  vtone("flo@c", K"0.12")
  vstroke("flo@c", w, U, 0, function() moveto(K(x0), R.ya) curveto(R.xb, R.yb, R.xc, R.yc, R.xd, R.yd) end)
end
function L.gsfeelers()
  V.gsw = E"max(0.35,0.3*@gsu)" V.gsv = E"max(0.28,0.24*@gsu)"
  L.gsfeeler("0.17", "0.66", "0.36", "1.02", R.gsw)
  vtone("flo@c", K"0.05") vfill("flo@c", U, 0, function() circle(R.xd, R.yd, K"0.028") end)
  L.gsfeeler("0.1", "0.7", "0.18", "1.04", R.gsw)
  vtone("flo@c", K"0.05") vfill("flo@c", U, 0, function() circle(R.xd, R.yd, K"0.028") end)
  L.gsfeeler("0.05", "0.68", "0", "0.84", R.gsv)
end
function L.gsshell()
  V.gscx = K"0.36" V.gscy = 0 V.gsR = K"0.42"
  V.gsn = L.xtr("whorls") V.gsE = L.xtr("expansion")
  V.gsH = E"0.55*@x@spire*@gsR"
  V.gsm = pm.int(E"round(@gsn*16)+1")
  V.t = E"0.96*@gsR" vblob(R.gscx, R.gscy, R.gsR, R.t, K"0.03", 16)
  loop("#Wa", 1, 16, function()
    local i = R["#Wa"]
    V.da = E("%1-@gscx", { X[i] }) V.db = E("%1-@gscy", { Y[i] })
    V.t = E"1+@gsH/@gsR*pow(max(0,cos(atan2(@db,@da)+40)),3)"
    V.xa = E"@gscx+@da*@t" V.ya = E"@gscy+@db*@t"
    put(i, R.xa, R.ya)
  end)
  smoothprep(16) keep("gsd")
  vtone("flo@c", R.gstn) vfill("flo@c", U, 0, function() kept("gsd") end)
  scope(function()
    kept("gsd") usepath("clip")
    V.gsxl = E"@gscx-@gsR" V.gsyl = E"@gscy-1.6*@gsR"
    V.gsxh = E"@gscx+1.6*@gsR" V.gsyh = E"@gscy+@gsR"
    V.ta = E"@gstn-0.18" V.tb = E"@gstn+0.22"
    if R.fine == U then vmottle(R.gsxl, R.gsyl, R.gsxh, R.gsyh, 7, K"0.1", R.ta, R.tb, 10)
    else vmottle(R.gsxl, R.gsyl, R.gsxh, R.gsyh, 3, K"0.1", R.ta, R.tb, 0) end
    if L.xtr("shellbands") > 0 then
      vtone("flo@c", K"0.06") V.gsls = E"max(0,1-2.5/@gsn)"
      loop("#Wa", 1, function() return L.xtr("shellbands") // U end, function()
        V.gsf = E"1-#Wa/(@x@shellbands+1)*(1-1/@gsE)" L.gsline(R.gsf, R.gsls, 41)
        V.stw = E"0.32*@gsR/(@x@shellbands+1)"
        vstreak(41, K"0.003", R.stw, "flo@c", K"0.55")
      end)
    end
    V.t = E"0.07*@gsu*28.3465" vtone("flo@c", K"0.05")
    vstroke("flo@c", R.t, K"0.6", 1, function() L.gsline(K"0.84", 0, I("gsm")) T.smoothopen(I("gsm")) end)
    V.t = E"0.05*@gsu*28.3465"
    vstroke("white", R.t, K"0.75", 0, function() L.gsline(U, 0, I("gsm")) T.smoothopen(I("gsm")) end)
    if L.xtr("lip") == U then
      loop("#Wa", 0, 4, function()
        V.gst = E"1-(4-#Wa)*0.03/@gsn" L.gsspiral(R.gst, K"0.97") put(R["#Wa"] + 1, R.xa, R.ya)
      end)
      vstreak(5, K"0.03", K"0.08", "white", K"0.85")
    end
    vtone("flo@c", K"0.05") V.t = E"0.12*@gsu*28.3465" vstroke("flo@c", R.t, K"0.5", 1, function() kept("gsd") end)
  end)
end
-- \flo@snail: a snail, size its shell's width on the page in pt (sp)
function L.snail(size)
  V.gsu = E("(%1)/28.45276", { size })
  if R.gsu > K"0.25" then V.fine = U else V.fine = 0 end
  V.gsx = L.xtr("extension") V.gsground = L.xtr("ground")
  V.gstn = E"@x@tone-0.06"
  if R.gsground == "pale" then V.gstn = E"min(0.72,@gstn+0.25)" end
  scope(function()
    V.t = L.xtr("hand")
    if R.t == "sinistral" then L.xscale(-U) end
    scope(function() V.rampname = "flo@ramp" L.gsbody() L.gsfeelers() end)
    if R.gsground == "copper" then V.rampname = "flo@aramp" end
    L.gsshell()
  end)
end
-- birds (\flo@bird)
L.AVF = { "0.12", "0.35", "0.6", "0.82", "0.95" }
function L.avfeather(len)
  put(1, 0, 0) V.ya = E("%1", { len }) put(7, 0, R.ya)
  loop("#Wb", 1, 5, function()
    V.v = K(L.AVF[R["#Wb"]])
    V.xa = E"0.055*pow(sin(180*pow(@v,0.4)),0.6)" V.xb = E"-@xa" V.ya = E("@v*(%1)", { len })
    put(R["#Wb"] + 1, R.xa, R.ya) put(13 - R["#Wb"], R.xb, R.ya)
  end)
  smoothprep(12)
end
function L.avbodypt(i, x, y)
  V.t = sym(K"0.012") V.xa = E("%1+@t", { K(x) }) V.t = sym(K"0.012") V.ya = E("%1+@t", { K(y) })
  put(i, R.xa, R.ya)
end
L.AVBODY = { { "0.37", "0.56" }, { "0.3", "0.665" }, { "0.15", "0.64" }, { "-0.03", "0.54" }, { "-0.22", "0.4" },
  { "-0.31", "0.3" }, { "-0.27", "0.22" }, { "-0.08", "0.12" }, { "0.12", "0.12" }, { "0.27", "0.27" },
  { "0.35", "0.42" } }
function L.avbody()
  V.avlw = E"max(0.3,0.3*@avu)"
  loop("#Wa", 1, 4, function()
    V.t = E"@x@tail-0.03" V.v = E"@x@tail+0.03" V.avL = range(R.t, R.v)
    V.t = range(-150 * U, -140 * U) V.ava = E"@t+@avfan*#Wa-90"
    scope(function()
      shift(K"-0.26", K"0.28") rotate(R.ava)
      L.avfeather(R.avL) keep("avf")
      V.t = E"0.12+0.05*#Wa" vtone("flo@c", R.t) vfill("flo@c", U, 0, function() kept("avf") end)
      vtone("flo@c", K"0.05") vstroke("flo@c", R.avlw, K"0.5", 0, function() kept("avf") end)
    end)
  end)
  for i, p in ipairs(L.AVBODY) do L.avbodypt(i, p[1], p[2]) end
  smoothprep(11) keep("avb")
  vtone("flo@c", R.avt) vfill("flo@c", U, 0, function() kept("avb") end)
  scope(function()
    kept("avb") usepath("clip")
    loop("#Wa", 1, 4, function()
      V.xa = E"0.08+0.04*#Wa" V.ya = E"0.06+0.03*#Wa"
      vblob(K"0.17", K"0.27", R.xa, R.ya, K"0.2", 9) vfill("white", K"0.2", 0, smoothpath)
    end)
    V.ta = E"@avt-0.2" V.tb = E"@avt+0.2"
    if R.fine == U then vmottle(K"-0.35", K"0.1", K"0.4", K"0.7", 10, K"0.07", R.ta, R.tb, 10)
    else vmottle(K"-0.35", K"0.1", K"0.4", K"0.7", 4, K"0.07", R.ta, R.tb, 0) end
    if R.avk == "hummingbird" then
      vblob(K"0.3", K"0.47", K"0.075", K"0.05", K"0.15", 8) vaccent("flo@c", 0) vfill("flo@c", K"0.85", 0, smoothpath)
      if R.fine == U then
        vblob(K"0.31", K"0.49", K"0.03", K"0.016", K"0.2", 7) vfill("white", K"0.5", 0, smoothpath)
      end
    elseif R.fine == U then
      vtone("flo@c", K"0.1")
      vfill("flo@c", K"0.7", 0, function()
        loop("#Wa", 1, 14, function()
          V.xa = range(K"0.08", K"0.3") V.ya = range(K"0.16", K"0.42") V.t = range(-20 * U, 20 * U)
          V.xb = E"0.012*cos(@t)" V.yb = E"0.012*sin(@t)" V.xc = E"-0.022*sin(@t)" V.yc = E"0.022*cos(@t)"
          L.pellipse(R.xa, R.ya, R.xb, R.yb, R.xc, R.yc)
        end)
      end)
    end
    vblob(K"0.24", K"0.66", K"0.15", K"0.08", K"0.1", 9) vtone("flo@c", K"0.08") vfill("flo@c", K"0.6", 1, smoothpath)
    vtone("flo@c", K"0.05") V.t = E"0.07*@avu*28.3465" vstroke("flo@c", R.t, K"0.5", 1, function() kept("avb") end)
  end)
end
L.AVWING = { { "0.17", "0.47" }, { "0.04", "0.52" }, { "-0.12", "0.45" }, { "-0.28", "0.33" }, { "-0.44", "0.22" },
  { "-0.35", "0.23" }, { "-0.38", "0.19" }, { "-0.26", "0.21" }, { "-0.28", "0.17" }, { "-0.12", "0.23" },
  { "0.05", "0.31" }, { "0.15", "0.4" } }
function L.avwing()
  for i, p in ipairs(L.AVWING) do put(i, K(p[1]), K(p[2])) end
  smoothprepT(12, K"0.8") keep("avw")
  V.avtw = E"@avt-0.1"
  vtone("flo@c", R.avtw) vfill("flo@c", U, 0, function() kept("avw") end)
  scope(function()
    kept("avw") usepath("clip")
    V.ta = E"@avtw-0.15" V.tb = E"@avtw+0.2"
    vmottle(K"-0.45", K"0.15", K"0.2", K"0.6", R.fine == U and 6 or 3, K"0.07", R.ta, R.tb, 0)
    V.twa = K"0.025" V.twb = K"0.003"
    loop("#Wa", 1, 5, function()
      V.ya = E"0.28+0.04*#Wa"
      V.yb = E"@ya+0.05" V.yc = E"@ya+0.03" V.yd = E"@ya-0.03"
      V.xe = E"-0.3-0.02*#Wa" V.ye = E"@ya-0.1-0.01*#Wa"
      V.t = range(K"0.45", K"0.7")
      vfill("white", R.t, 0, function() vtaper(K"0.12", R.yb, 0, R.yc, K"-0.15", R.yd, R.xe, R.ye) end)
    end)
    vtone("flo@c", K"0.04") V.t = E"0.06*@avu*28.3465" vstroke("flo@c", R.t, K"0.5", 1, function() kept("avw") end)
  end)
end
L.AVHOVER = { { "0", "0.02" }, { "0.12", "0.07" }, { "0.32", "0.085" }, { "0.5", "0.05" }, { "0.56", "0" },
  { "0.48", "-0.03" }, { "0.28", "-0.045" }, { "0.08", "-0.03" } }
function L.avhover()
  for i, p in ipairs(L.AVHOVER) do put(i, K(p[1]), K(p[2])) end
  smoothprep(8) keep("avh") V.avtw = E"@avt-0.1"
  loop("#Wa", 1, 3, function()
    scope(function()
      V.t = E"70+25*#Wa" shift(K"0.06", K"0.5") rotate(R.t)
      vtone("flo@c", R.avtw)
      if R["#Wa"] == 2 then
        vfill("flo@c", K"0.4", 0, function() kept("avh") end)
        vtone("flo@c", K"0.05") vstroke("flo@c", R.avlw, K"0.4", 0, function() kept("avh") end)
      else vfill("flo@c", K"0.18", 0, function() kept("avh") end) end
    end)
  end)
end
function L.avcrest()
  V.twa = K"0.03" V.twb = K"0.004"
  vtone("flo@c", K"0.1")
  vfill("flo@c", U, 0, function()
    loop("#Wa", 1, 4, function()
      V.avL = range(K"0.08", K"0.12")
      V.xa = E"0.26-0.04*#Wa" V.ya = E"0.65-0.01*#Wa" V.t = E"140+8*#Wa"
      V.xd = E"@xa+@avL*cos(@t)" V.yd = E"@ya+@avL*sin(@t)"
      L.lgseg(R.xa, R.ya, R.xd, R.yd)
    end)
  end)
end
function L.avbill()
  V.t = L.xtr("bill") vtone("flo@c", K"0.05")
  if R.t == "conical" then
    vfill("flo@c", U, 0, function()
      moveto(K"0.355", K"0.585") lineto(K"0.47", K"0.545") lineto(K"0.36", K"0.51") closepath()
    end)
    vstroke("white", K"0.2", K"0.6", 0, function() moveto(K"0.36", K"0.548") lineto(K"0.45", K"0.546") end)
  end
  if R.t == "straight" then
    vfill("flo@c", U, 0, function()
      moveto(K"0.35", K"0.575") lineto(K"0.69", K"0.55") lineto(K"0.352", K"0.538") closepath()
    end)
  end
  if R.t == "curved" then
    V.twa = K"0.036" V.twb = K"0.006"
    vfill("flo@c", U, 0, function()
      vtaper(K"0.35", K"0.556", K"0.46", K"0.562", K"0.58", K"0.535", K"0.66", K"0.475")
    end)
  end
end
-- \flo@bird: a bird, size its length on the page in pt (sp)
function L.bird(size)
  V.avu = E("(%1)/28.45276", { size })
  if R.avu > K"0.3" then V.fine = U else V.fine = 0 end
  V.avk = L.xtr("kind") V.avpose = L.xtr("pose") V.avground = L.xtr("ground")
  V.avt = L.xtr("tone")
  if R.avground == "dark" then V.avt = E"@avt-0.12" end
  if R.avground == "copper" then V.rampname = "flo@aramp" end
  V.avfan = 7 * U
  scope(function()
    if R.avpose == "hover" then
      V.avfan = 14 * U
      shift(K"0.05", K"0.35") rotate(22 * U) shift(K"-0.05", K"-0.35")
    end
    L.avbody()
    if L.xtr("crest") == U then L.avcrest() end
    if R.avpose == "hover" then L.avhover() else L.avwing() end
    L.avbill()
    vfill("white", K"0.95", 0, function() circle(K"0.285", K"0.585", K"0.03") end)
    vtone("flo@c", K"0.03") vfill("flo@c", U, 0, function() circle(K"0.29", K"0.585", K"0.018") end)
    vfill("white", U, 0, function() circle(K"0.284", K"0.592", K"0.006") end)
    if R.avpose ~= "hover" then
      V.t = E"max(0.4,0.3*@avu)" vtone("flo@c", K"0.06")
      vstroke("flo@c", R.t, U, 0, function()
        moveto(K"0.02", K"0.14") lineto(0, 0) moveto(K"-0.05", 0) lineto(K"0.05", K"0.005")
        moveto(K"0.1", K"0.14") lineto(K"0.08", 0) moveto(K"0.03", 0) lineto(K"0.13", K"0.005")
      end)
    end
  end)
end
-- \flo@visitor: a visitor of the kind last drawn, size on the page in pt (sp); the
-- margin's organ scales by cm (sp) instead, as its code is read in cm
function T.visitor(size, cm)
  local u = cm or size
  V.vg = L.xtr("group")
  if R.vg == "lepidoptera" then V.t = E("(%1)/2", { u }) scale(R.t) T.lepid(size) end
  if R.vg == "bee" then scale(u) L.bee(size) end
  if R.vg == "fly" then scale(u) L.bee(size) end
  if R.vg == "odonate" then scale(u) L.odo(size) end
  if R.vg == "beetle" then scale(u) L.beetle(size) end
  if R.vg == "larva" then scale(u) L.caterpillar(size) end
  if R.vg == "snail" then scale(u) L.snail(size) end
  if R.vg == "bird" then scale(u) L.bird(size) end
end
function T.visitorsetup(o)
  L.florilegiumvisitor(o.seed, o.role or "any")
  drawseed(o.draw or (o.seed == 2147483646 and 1 or o.seed + 1))
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
  level, saves, saved = 0, {}, {}
  for _, t in ipairs({ X, Y, A, B, C, D, NX, NY, RX, RY, QX, QY, S, T.TX, T.TY, T.MX, T.MY, T.MU, T.MV,
    T.AX, T.AY, T.AN, T.AM, T.O, T.VEIN, T.Z, T.FX, T.FY, KEPT, ROOM, G[1], G[2], G[3] }) do
    for k in pairs(t) do t[k] = nil end
  end
  R.lift = 0 R.zero = 0 R["vp@notchp"] = K"0.4" R["vp@notchk"] = U
  R["vf@star"] = "" R["vf@tone"] = "" R.rampname = "flo@ramp" R.layer = 0 R.filling = 0 R.bside = "" R.bfan = 0 R.ivc = 0 R.ivpt = 0
  R.fore = U R.lsd = "" R.lleaflet = 0 R.lmover = "" R.hk = 0
  R.feun = U R.fefert = 0 R.feund = 0 R.fearch = ""
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
    V.gH = sizecm(o.size) V["o@season"] = o.season or K"0.75"
    if tr("clade") == "fern" then T.ferncrown() else
      V["#Np"] = 1 V["pp@s1"] = o.seed V["pp@r1"] = o.role or "any"
      V.gghost = "false" V.gW = sizecm(o.width)
      garden()
    end
  elseif kind == "fern" then
    o.role = "fern" picsetup(o)
    V.gH = sizecm(o.size) V["o@season"] = o.season or K"0.75"
    T.ferncrown()
  elseif kind == "visitor" then
    T.visitorsetup(o)
    out("\\pgfsetroundcap\\pgfsetroundjoin")
    T.visitor(o.size)
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
--   frond    len (cm), unroll (0..1), arch (degrees), fertile, under, lc, season: a fern's
--   ghost    d: a plain pale flower of the species, as the garden's ghost
--   visitor  seed, role, size (cm; a wingspan for butterflies and moths): the visitor that
--            \florilegiumvisitor{seed}{role} samples, drawn from seed + 1 as its pic is (s, z unused)
local function organ(kind, s, z, o)
  reset()
  if kind == "visitor" then
    scope(function()
      T.visitorsetup({ seed = o.seed, role = o.role })
      V.t = E("%1*28.45276", { fx(o.size) }) T.visitor(R.t, fx(o.size))
    end)
    assert(level == 0, "florilegium-organs: a group left open")
    return concat(OUT)
  end
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
      scale(R.lf)
      if o.fore then V.fore = fx(o.fore) yscale(R.fore) end
      autumnleaf()
      -- a sheath along the stem (o.sheath: its direction from the leaf's, degrees, and its
      -- width in the leaf's units)
      if o.sheath then V.lsd = fx(o.sheath[1]) V.lsw = fx(o.sheath[2]) end
      V.t = E"@lf*28.45276" leaf(R.t)
    elseif kind == "frond" then
      -- a fern's frond: len (cm), unroll (0..1), arch (degrees), fertile, under, lc, season
      V.lf = fx(o.len) V.lc = fx(o.lc) V.season = fx(o.season)
      scale(R.lf) autumnleaf()
      V.feun = fx(o.unroll) V.fearch = fx(o.arch) V.fefert = o.fertile and U or 0 V.feund = o.under and U or 0
      V.t = E"@lf*28.45276" T.frond(R.t)
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
-- (M8f1 prototype) the native petals and flowers on or off; FLORILEGIUM_NATIVE=1 turns them on
function M.native(on)
  if on then
    M.nv = require("florilegium-native")
    M.nv.use(rng)
  else M.nv = nil end
end
if os.getenv("FLORILEGIUM_NATIVE") == "1" then M.native(true) end

-- the pgf code read back and painted with ink, under ink's current transform: a point
-- (pt in the code) is a cm; line widths stay absolute
local KAPPA, PT_BP = 0.55228475, 72 / 72.27
local BLACK = { 0, 0, 0 }
-- (M8f1 prototype: a painter fed piece by piece, M.stream)
function M.painter()
  local st = { fill = BLACK, fop = 1, stroke = BLACK, sop = 1, w = 0.4 * PT_BP, mult = false, colors = {}, clips = 0,
    dash = nil }
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
  local function feed(code)
  code = code:gsub("\\pgfqpoint{(%-?[%d.]+)pt}{(%-?[%d.]+)pt}", "%1 %2")
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
      st = { fill = st.fill, fop = st.fop, stroke = st.stroke, sop = st.sop, w = st.w, mult = st.mult, colors = c, clips = 0,
        dash = st.dash }
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
      elseif how == "stroke" then ink.stroke(st.stroke, st.w, st.sop, st.mult, st.dash)
      elseif how == "clip" then ink.clip() st.clips = st.clips + 1
      else error("florilegium-organs: no path use '" .. tostring(how) .. "'") end
    elseif name == "pgfsetfillcolor" then st.fill = color(a:match("{([^}]*)}"))
    elseif name == "pgfsetstrokecolor" then st.stroke = color(a:match("{([^}]*)}"))
    elseif name == "pgfsetfillopacity" then st.fop = nums(a)[1]
    elseif name == "pgfsetstrokeopacity" then st.sop = nums(a)[1]
    elseif name == "pgfsetdash" then                       -- {{on}{off}}{phase}, in bp
      local v = nums(a) st.dash = string.format("[%.2f %.2f] %.2f", v[1], v[2], v[3])
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
  end
  return feed, function() assert(#stack == 0, "florilegium-organs: a scope left open") end
end
local function paint(code) local feed, done = M.painter() feed(code) done() end

-- draw an organ (see organ() above) with ink. With M.keep set (the growth animation
-- paints every motif several times), each organ's code is computed once per page.
M.keep = false
local kept_code = {}
function M.forget() kept_code = {} end
function M.draw(kind, s, z, o)
  if M.nv then                    -- (M8f1 prototype) painted as it is computed
    if M.nv.draw(kind, s, z, o) then return end   -- the organs it has of its own
    M.nv.fresh()
    local feed, done = M.painter()
    M.stream = feed
    local ok, err = pcall(organ, kind, s, z, o)
    M.stream = nil
    if not ok then error(err, 0) end
    done()
    return
  end
  local code
  if M.keep then
    local key = table.concat({ kind, s.seed, s.role, z, tostring(o.k), tostring(o.season), tostring(o.late), tostring(o.size),
      tostring(o.d), tostring(o.stage), tostring(o.len), tostring(o.bend), tostring(o.lc), tostring(o.fore),
      tostring(o.unroll), tostring(o.arch), tostring(o.fertile), tostring(o.under), tostring(o.seed), tostring(o.role),
      o.sheath and (o.sheath[1] .. "/" .. o.sheath[2]) or "" }, " ")
    code = kept_code[key]
    if not code then code = organ(kind, s, z, o) kept_code[key] = code end
  else
    code = organ(kind, s, z, o)
  end
  paint(code)
end

return M
