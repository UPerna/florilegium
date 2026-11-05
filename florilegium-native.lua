-- florilegium-native.lua -- the species' organs in plain Lua, drawn straight to ink.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- The TikZ library (tikzlibraryflorilegium.code.tex) draws a species' plant in pgfmath.
-- Here the same organs are computed in ordinary floating point and painted with ink as
-- they are computed: the same steps, the same random draws from pgf's generator in the
-- same order, so the same seed gives the same organ, its numbers within a small fraction
-- of a point of the library's. (Where pgfmath's rounding and a double's would fall on
-- different sides of a threshold, a choice can tip; such cases are rare, and the
-- comparison of the two engines' drawings, tools/tikzcheck.lua draw, lists them.) A few
-- numbers that sit on a threshold are TeX's own, from florilegium-pgfmath.lua.
--
-- Some of the library's habits are kept on purpose, because its look was made with them:
-- they are marked "as the library does" where they would otherwise look like slips.
--
-- Lengths are in the organ's own units (a petal is 1 long), angles in degrees, colors
-- points of ink's ramp: tone(t) as \flo@vtone, in the accent's ramp while pen.accent is set.
-- M.draw draws the margin's organs (in cm), M.pic the TikZ library's pics (in pt).

local ink = require("florilegium-ink")
local pm = require("florilegium-pgfmath")

local M = {}
M.version = "2.0.0"                 -- the release; florilegium.lua checks that every file has the same

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
local CM = pm.sp("28.45276")      -- pt in a cm as TeX holds it, in sp (TeX's arithmetic below)
local RAD = math.pi / 180
local function sin(a) return math.sin(a * RAD) end          -- degrees, as pgfmath takes them
local function cos(a) return math.cos(a * RAD) end
local moveto, lineto, curveto, close, circle = ink.moveto, ink.lineto, ink.curveto, ink.close, ink.circle
local fill, stroke, smooth = ink.fill, ink.stroke, ink.smooth

-- ---------------------------------------------------------------- random numbers
-- pgf's generator (ink.pgfrng): rnd in [0,1] and rand in [-1,1] are whole scaled points,
-- so a draw is the library's draw exactly; only what is computed from it is a double
local G
function M.use(rng) G = rng end
local function range(a, b) return a + (b - a) * G.rnd() end                -- \flo@range
local function sym(a) return a * G.rand() end                              -- \flo@sym
local function int(a, b) return G.random(a, b) end                         -- \pgfmathrandominteger
-- a constant as TeX holds it (a whole number of sp), for comparing a number TeX also holds
-- exactly (an organ's length is one): 0.6 is 0.600006, and a 0.6 cm leaf is not above it
local function K(x) return floor(x * 65536 + 0.5) / 65536 end
-- \flo@chance: rnd < p, with p as TeX holds the constant
local function chance(p) return G.rnd() * 65536 < floor(p * 65536 + 0.5) end
-- \numexpr's division of integers: rounded, halves away from zero
local function nediv(a, b)
  local q = (2 * abs(a) + abs(b)) // (2 * abs(b))
  return ((a < 0) ~= (b < 0)) and -q or q
end

-- ---------------------------------------------------------------- the pen
-- lift: \flo@lift (a ghost's or a fading flower's paleness, 0..1); accent: the accent's
-- ramp (\flo@rampname = flo@aramp). Colors are looked up once per organ.
local pen = { lift = 0, accent = false }
M.pen = pen
local ramps = { [false] = {}, [true] = {} }
function M.fresh() ramps = { [false] = {}, [true] = {} } end              -- ink's colors may have changed
local function ramp(accent, ti)
  local r = ramps[accent]
  local c = r[ti]
  if not c then
    if accent then ink.in_accent(function() c = ink.tone(ti / 100) end) else c = ink.tone(ti / 100) end
    r[ti] = c
  end
  return c
end
-- \flo@vtone
local function tone(t)
  local l = pen.lift
  if l ~= 0 then t = t + (1 - t) * l end
  return ramp(pen.accent, max(0, min(100, floor(t * 100 + 0.5))))
end
-- \flo@vaccent: the accent toward white (k > 0) or black (k < 0)
local function accent(k) return ink.accent(k) end
local WHITE = ink.white

-- ---------------------------------------------------------------- the species
-- the plant being drawn: a table from florilegium-species (its traits by name)
local S
function M.species(sp) S = sp end

-- ---------------------------------------------------------------- paths
-- \flo@vtaper: a closed tapered stroke along one cubic, widths wa at its start, wb at its end
local function nrm(dx, dy)
  local l = sqrt(dx * dx + dy * dy)
  if l < 1.5e-5 then return 0, 0 end                                       -- under 1 sp: none
  return -dy / l, dx / l
end
local function taper(x0, y0, x1, y1, x2, y2, x3, y3, wa, wb)
  local ax, ay = nrm(x1 - x0, y1 - y0)
  local bx, by = nrm(x2 - x0, y2 - y0)
  local cx, cy = nrm(x3 - x1, y3 - y1)
  local dx, dy = nrm(x3 - x2, y3 - y2)
  local ha, hb, hc, hd = wa / 2, (2 * wa + wb) / 6, (wa + 2 * wb) / 6, wb / 2
  moveto(x0 + ax * ha, y0 + ay * ha)
  curveto(x1 + bx * hb, y1 + by * hb, x2 + cx * hc, y2 + cy * hc, x3 + dx * hd, y3 + dy * hd)
  lineto(x3 - dx * hd, y3 - dy * hd)
  curveto(x2 - cx * hc, y2 - cy * hc, x1 - bx * hb, y1 - by * hb, x0 - ax * ha, y0 - ay * ha)
  close()
end
-- \flo@vblob: n points around (x, y), radii rx ry, roughness k (a closed smooth curve's points)
local function blob(x, y, rx, ry, k, n)
  local ph, pi, rot = range(0, 360), range(0, 360), range(0, 360)
  local cr, sr = cos(rot), sin(rot)
  local pts = {}
  for i = 0, n - 1 do
    local a = 360 * i / n
    local s = sym(1)
    local b = 1 + k * (0.6 * sin(2 * a + ph) + 0.4 * sin(3 * a + pi)) + k * 0.5 * s
    local px, py = rx * b * cos(a), ry * b * sin(a)
    pts[i + 1] = { x + px * cr - py * sr, y + px * sr + py * cr }
  end
  return pts
end
-- \flo@vmottle: blotches and specks over (x0,y0)-(x1,y1), inside the clip. With `drift`
-- the x range moves, as the library's does: it passes the range by the names \flo@xa and
-- \flo@xb, which each blotch's curve (\flo@smoothprep) sets to its sixth and first points
-- and each speck to two of its corners, so only the first blotch spans the petal. With
-- drift "xy" the top moves too: the strap leaf passes it as \flo@yb, which the curve sets
-- to its first point's y and a speck to its second corner's
local function mottle(x0, y0, x1, y1, n, size, dark, light, nspk, drift)
  local xa, xb, yb = x0, x1, y1
  for _ = 1, n do
    local mx, my = range(xa, xb), range(y0, yb)
    local mr = size * range(0.5, 1.4)
    local ms = mr * range(0.5, 1)
    local pts = blob(mx, my, mr, ms, 0.35, 7)
    if drift then xa, xb = pts[6][1], pts[1][1] end
    if drift == "xy" then yb = pts[1][2] end
    if chance(0.6) then
      local c = tone(dark + sym(0.06))
      smooth(pts, true) fill(c, range(0.10, 0.22), true)
    else
      local c = tone(light + sym(0.06))
      smooth(pts, true) fill(c, range(0.12, 0.26), false)
    end
  end
  if nspk > 0 then
    for _ = 1, nspk do
      local mx, my = range(xa, xb), range(y0, yb)
      local mr = size * range(0.03, 0.08)
      local ma = range(0, 180)
      local sc, ss = mr * cos(ma), mr * sin(ma)
      moveto(mx + sc, my + ss) lineto(mx - 0.6 * ss, my + 0.6 * sc)
      lineto(mx - sc, my - ss) lineto(mx + 0.6 * ss, my - 0.6 * sc) close()
      if drift then xa, xb = mx + sc, mx - 0.6 * ss end
      if drift == "xy" then yb = my + 0.6 * sc end
    end
    local c = tone(dark - 0.08)
    fill(c, range(0.3, 0.5), true)
  end
end

-- ---------------------------------------------------------------- the petal (flora.petal)
-- the half-width at v of a petal pW wide, pointed or round (\flo@vhalf)
local function half(pointed, pW, v)
  if pointed then
    if v > 0 then return pW * 2 * max(0, sin(180 * v ^ 0.8)) ^ 0.85 * (1 - 0.3 * v) end
    return 0
  end
  if v < 0.62 then
    if v > 0 then return pW * (0.16 + 0.84 * sin(90 * v / 0.62) ^ 1.3) end
    return pW * 0.16
  end
  return pW * sqrt(max(0, 1 - ((v - 0.62) / 0.38) ^ 2))
end
-- three tables of 256 noise gradients (\flo@vfbm), and their sum at x (\flo@vwave)
local function fbm()
  local g = {}
  for k = 1, 3 do
    local t = {}
    for i = 0, 255 do t[i] = G.rand() end
    g[k] = t
  end
  return g
end
local function wave(g, x)
  local v, a, f = 0, 1, 1
  for k = 1, 3 do
    local wx = x * f + 17 * k
    local i = floor(wx)
    local r = wx - i
    local t = g[k]
    local ga, gb = t[i % 256], t[(i + 1) % 256]
    v = v + a * 2 * (ga * r + (gb * (r - 1) - ga * r) * r * r * (3 - 2 * r))
    a, f = a * 0.5, f * 2
  end
  return v
end
-- the outline's points: base, the left side up, the tip, the right side down
local function petal_outline(pointed, pW, bend, notch, g, bn)
  local pts = {}
  local k = pointed and 0.012 or 0.03
  for i = 0, bn do
    local v = i / bn
    local va, vb = max(0, i - 1) / bn, min(bn, i + 1) / bn
    local nx, ny = nrm(bend * (vb * vb - va * va), vb - va)
    local h = half(pointed, pW, v)
    local e1, e2 = k * wave(g, v * 6) * v, k * wave(g, v * 6 + 40) * v
    if notch > 0 and v > 0.9 then
      local d = notch * (v - 0.9) * 10 * (1 - (v - 0.9) * 10)
      e1, e2 = e1 - d, e2 - d
    end
    local ea, eb = max(0, h + e1), max(0, h + e2)
    local cx = bend * v * v
    pts[i + 1] = { cx + nx * ea, v + ny * ea }
    if i > 0 and i < bn then pts[2 * bn + 1 - i] = { cx - nx * eb, v - ny * eb } end
  end
  return pts
end
-- \flo@vpetal: along +y, length 1. o: pointed, W (width; nil draws one), bend (nil draws
-- one), tone, ns (white streaks; nil draws a count), heart, u (cm per unit: the level of
-- detail), notchp and notchk (a round petal's notch: chance and depth)
function M.petal(o)
  local pointed = o.pointed
  local pW = o.W or (pointed and range(0.15, 0.2) or range(0.40, 0.48))
  local bend = o.bend or sym(0.08)
  local tz = o.tone
  local fine = K(o.u) > K(0.45)                 -- u as TeX holds it, in whole sp (\ifdim)
  local g = fbm()
  local notch = 0
  if not pointed and chance(o.notchp) then notch = range(0.03, 0.06) * o.notchk end
  -- a petal under 1.2 mm is tiny: a coarser outline, no heart, mottle or pooled rim (specks
  -- no printer resolves at that size), and at most five streaks
  local tiny = K(o.u) < K(0.12)
  local bn = K(o.u) > K(0.5) and 28 or (tiny and 8 or 18)
  local outline = petal_outline(pointed, pW, bend, notch, g, bn)
  smooth(outline, true) ink.clip()
  ink.poly({ { -1, -0.1 }, { 1, -0.1 }, { 1, 1.2 }, { -1, 1.2 } }, true) fill(tone(tz), 1)
  if o.heart and not tiny then
    for k = 1, 8 do
      smooth(blob(0, 0, pW * (0.25 + 0.1 * k), 0.06 + 0.065 * k, 0.28, 9), true) fill(WHITE, 0.1)
    end
  end
  local msz = pointed and 0.06 or 0.12
  if fine then mottle(-pW * 1.2, 0.12, pW * 1.2, 1.05, 15, msz, tz - 0.2, tz + 0.2, 12, true)
  elseif not tiny then mottle(-pW * 1.2, 0.12, pW * 1.2, 1.05, 6, msz, tz - 0.2, tz + 0.2, 0, true) end
  -- darker brush strokes running out from the base
  if fine then
    for _ = 1, int(5, 8) do
      local f, va, vb = sym(0.95), range(0.15, 0.4), range(0.7, 1.0)
      local xa = f * half(pointed, pW, va) * 0.8 + bend * va * va
      local xb = f * half(pointed, pW, vb) * 0.9 + bend * vb * vb
      local twa = range(0.03, 0.07)
      local c = tone(tz - 0.25)
      taper(xa, va, xa + (xb - xa) * 0.3, va + (vb - va) * 0.35, xb * 0.95, va + (vb - va) * 0.7, xb, vb, twa, 0.005)
      fill(c, range(0.12, 0.25), true)
    end
  end
  -- pooling: the outline restroked wide and soft
  if not tiny then smooth(outline, true) stroke(tone(0.08), 1.6 * o.u, 0.3, true) end
  -- white streaks lifted out, fanning from the base
  local ns = o.ns or (pointed and int(3, 5) or int(9, 13))
  if tiny and ns > 5 then ns = 5 end
  for k = 1, ns do
    local f = (k - 0.5) / ns * 2 - 1 + sym(0.05)
    local len = (pointed and range(0.4, 0.85) or range(0.35, 0.8)) * (1 - 0.35 * f * f)
    if pointed and k == nediv(ns, 2) then f, len = 0, range(0.8, 0.92) end
    local xb = f * half(pointed, pW, len) * 0.85 + bend * len * len
    local mx = f * half(pointed, pW, len * 0.5) * 0.6 + sym(0.02) + bend * len * len * 0.3
    local twa = (pointed and 0.6 or 1) * range(0.022, 0.045)
    local op = range(0.55, 0.9)
    taper(f * 0.03, 0, mx * 0.5, len * 0.3, mx, len * 0.6, xb, len, twa, 0.002)
    fill(WHITE, op)
  end
  -- a few fine dark veins, following the petal
  if fine then
    for _ = 1, int(4, 7) do
      local f, va, vb = sym(0.85), range(0.2, 0.35), range(0.75, 0.95)
      local xa = f * half(pointed, pW, va) * 0.7 + bend * va * va
      local xb = f * half(pointed, pW, vb) * 0.9 + bend * vb * vb
      local b = ink.bezier3(xa, va, xa + (xb - xa) * 0.2, va + (vb - va) * 0.4, xb * 0.97, va + (vb - va) * 0.75, xb, vb)
      local pts = {}
      for i = 0, 5 do pts[i + 1] = { b(i / 5) } end
      local c = tone(0.1)
      smooth(pts, false) stroke(c, 0.15, range(0.18, 0.32), true)
    end
  end
  ink.unclip()
end

-- ---------------------------------------------------------------- the heart and the flower
-- \flo@vheart: the center of a flower of n petals
function M.heart(n)
  for k = 1, 2 * n do
    local a = (k - 0.5) * 360 / (2 * n) + sym(8)
    local len = range(0.24, 0.36)
    ink.push() ink.rotate(a)
    taper(0, 0, 0.01, 0.1, -0.01, 0.2, 0, len, 0.06, 0.004) fill(WHITE, 0.85)
    ink.pop()
  end
  circle(0, 0, 0.13) fill(WHITE, 0.9)
  local c, d = tone(0.1), tone(0.05)
  for _ = 1, 14 do
    local a, r = range(0, 360), range(0.05, 0.12)
    local dx, dy = r * cos(a), r * sin(a)
    moveto(0, 0) lineto(dx, dy) stroke(c, 0.2, 0.7, false)
    circle(dx, dy, 0.008) fill(d, 0.9)
  end
  circle(0, 0, 0.042) fill(accent(-0.15), 1)
  circle(0, 0, 0.022) fill(accent(0.3), 1)
end
-- \flo@vflower: n broad petals seen from the front, petal length 1; u its cm per unit.
-- o: pointed, tone (nil draws one), W, ns (nil: the petal draws them), notchp, notchk
function M.flower(u, n, o)
  local spin = range(0, 72)
  local tq = o.tone
  if not tq then if chance(0.25) then tq = range(0.2, 0.28) else tq = range(0.3, 0.46) end end
  local p = { pointed = o.pointed, W = o.W, ns = o.ns, heart = true, u = u, notchp = o.notchp, notchk = o.notchk }
  for i = 0, n - 1 do
    local a = spin + i * 360 / n + sym(6)
    local js = range(0.9, 1.06)
    p.tone = tq + sym(0.04)
    ink.push() ink.rotate(a) ink.scale(js) ink.translate(0, 0.04)
    M.petal(p)
    ink.pop()
  end
  ink.push() ink.rotate(spin) M.heart(n) ink.pop()
end
-- \flo@sdaisy: a daisy head of `rays` rays, diameter 1; d its diameter in pt.
-- o: tone (nil draws one), notchp, notchk
function M.daisy(d, rays, o)
  local spin = range(0, 360)
  local tq = o.tone or range(0.3, 0.46)
  local p = { pointed = false, W = min(0.17, 1.6 / rays), ns = 2, heart = false, u = d * 0.36 / 28.45276,
    notchp = o.notchp, notchk = o.notchk }
  for k = 1, rays do
    local a = spin + k * 360 / rays + sym(4) - 90
    local js = range(0.9, 1.05)
    p.tone = tq + sym(0.04)
    ink.push() ink.rotate(a) ink.translate(0, 0.1) ink.scale(0.4) ink.scale(js)
    M.petal(p)
    ink.pop()
  end
  local was = pen.accent
  pen.accent = true
  circle(0, 0, 0.105) fill(tone(0.3), 1)
  -- the disc florets on Vogel's spiral (H. Vogel, Mathematical Biosciences 44, 1979):
  -- floret k at radius c*sqrt(k/n), turned k times 137.508 degrees
  local nd = floor(min(90, max(24, d * 1.2)))
  local c = tone(0.68)
  for k = 1, nd do
    local r, a = 0.095 * sqrt(k / nd), 137.508 * k
    circle(r * cos(a), r * sin(a), 0.004 + 0.006 * sqrt(k / nd))
  end
  fill(c, 0.9)
  pen.accent = was
end
-- \flo@vfloret: a floret of n petals, radius 1; r its radius in cm. o: star (nil draws it), tone
function M.floret(r, n, o)
  local star = o.star
  if star == nil then star = chance(0.5) end
  if r < 0.07 then
    -- a star or a round flower as one polygon
    local ph = range(0, 360)
    local pts = {}
    for k = 0, 2 * n - 1 do
      local a = ph + k * 180 / n
      local q = k % 2 == 1 and (star and 0.32 or 0.62) or 1
      pts[k + 1] = { q * cos(a), q * sin(a) }
    end
    local c = tone(o.tone or range(0.22, 0.42))
    ink.poly(pts, true) fill(c, 1)
    ink.poly({ { 0.2, 0 }, { 0, 0.2 }, { -0.2, 0 }, { 0, -0.2 } }, true) fill(tone(0.05), 1)
  else
    local ph = range(0, 360)
    local shape, tk
    if star then shape, tk = { { 0, 0 }, { 0.45, 0.156 }, { 1, 0 }, { 0.45, -0.156 } }, 0.5
    else shape, tk = { { 0, 0 }, { 0.3, 0.42 }, { 0.85, 0.336 }, { 1, 0 }, { 0.85, -0.336 }, { 0.3, -0.42 } }, 1 end
    for k = 0, n - 1 do
      local a = ph + k * 360 / n + sym(8.6)
      local len = range(0.85, 1.1)
      local c, s = cos(a), sin(a)
      local pts = {}
      for i, p in ipairs(shape) do pts[i] = { len * (p[1] * c - p[2] * s), len * (p[1] * s + p[2] * c) } end
      smooth(pts, true, tk)
    end
    fill(tone(o.tone or range(0.22, 0.42)), 1)
    if r > 0.05 then circle(0, 0, 0.35) fill(WHITE, 0.75) end
    circle(0, 0, 0.16) fill(tone(0.05), 1)
  end
end
-- \flo@vblossom: flora.blossom, n round petals, radius 1; r its radius in cm. o: tone
function M.blossom(r, n, o)
  local spin = range(0, 72)
  local tq = o.tone or range(0.30, 0.45)
  for k = 0, n - 1 do
    local a = spin + k * 360 / n + sym(8)
    local js = range(0.9, 1.08)
    local pW = range(0.36, 0.44)
    ink.push() ink.rotate(a) ink.scale(js)
    -- the outline: up the left side, down the right
    local pts = {}
    for i = 0, 18 do pts[i + 1] = { -half(false, pW, i / 18), i / 18 } end
    for i = 17, 1, -1 do pts[#pts + 1] = { half(false, pW, i / 18), i / 18 } end
    local c = tone(tq + sym(0.05))
    smooth(pts, true) fill(c, 1)
    smooth(pts, true) ink.clip()
    local mx, my = sym(0.2), range(0.5, 0.9)
    local b = blob(mx, my, 0.35, 0.3, 0.3, 8)
    smooth(b, true) fill(tone(tq - 0.2), 0.3, true)
    taper(0, 0, 0.02, 0.2, -0.02, 0.4, sym(0.05), 0.55, 0.12, 0.01) fill(WHITE, 0.7)
    smooth(pts, true) stroke(tone(0.08), 1.2 * r, 0.25, true)
    ink.unclip()
    ink.pop()
  end
  circle(0, 0, 0.22) fill(WHITE, 0.85)
  circle(0, 0, 0.09) fill(tone(0.08), 1)
end
-- \flo@vboss: the rose family's ring of stamens, face on; exserted: longer filaments
function M.boss(exserted)
  local bl = exserted and 0.04 or 0
  local n = int(36, 52)
  local ph = range(0, 360)
  local fx, fy, ax, ay, ar = {}, {}, {}, {}, {}
  for k = 1, n do
    local a = ph + 360 / n * k + sym(4)
    local r = range(0.09, 0.17) + bl
    fx[k], fy[k] = 0.035 * cos(a), 0.035 * sin(a)
    ax[k], ay[k] = r * cos(a), r * sin(a)
    ar[k] = range(0.007, 0.011)
  end
  for k = 1, n do moveto(fx[k], fy[k]) lineto(ax[k], ay[k]) end
  stroke(tone(0.14), 0.2, 0.8, false)
  local was = pen.accent
  pen.accent = true
  for k = 1, n do circle(ax[k], ay[k], ar[k]) end
  fill(tone(0.42), 1)
  circle(0, 0, 0.045) fill(tone(0.66), 1)
  pen.accent = was
  circle(0.014, 0.009, 0.009) circle(-0.012, 0.013, 0.009) circle(-0.002, -0.015, 0.009)
  fill(tone(0.2), 0.9)
end

-- ================================================================ M8f2: the rest of the flower
-- ---------------------------------------------------------------- helpers
local function xscale(s) ink.scale(s, 1) end
local function yscale(s) ink.scale(1, s) end
-- \flo@upright: +y up on the page, the scale and the handedness kept
local function upright()
  local t = ink.get_transform()
  local p, q = sqrt(t[1] * t[1] + t[2] * t[2]), sqrt(t[3] * t[3] + t[4] * t[4])
  local s = sqrt(p) * sqrt(q)
  ink.set_transform({ (t[1] / p) * (t[4] / q) - (t[2] / p) * (t[3] / q) < 0 and -s or s, 0, 0, s, t[5], t[6] })
end
-- \flo@normals: the left normals of a polyline by central differences (one under 1 sp is
-- left unnormalized, as the library leaves it)
local function normals(pts)
  local n, out = #pts, {}
  for i = 1, n do
    local a, b = pts[i == 1 and 1 or i - 1], pts[i == n and n or i + 1]
    local dx, dy = b[1] - a[1], b[2] - a[2]
    local l = sqrt(dx * dx + dy * dy)
    if l < 1.5e-5 then l = 1 end
    out[i] = { -dy / l, dx / l }
  end
  return out
end
-- a blade around a spine (\flo@sides, \flo@bladeassemble): w(i, v) the half-width at point i;
-- the outline goes up the left side and down the right, the tip and the base once each
local function blade(spine, w)
  local nr, n = normals(spine), #spine - 1
  local left, right = {}, {}
  for i = 1, n + 1 do
    local h = w(i, (i - 1) / n)
    local p, q = spine[i], nr[i]
    left[i] = { p[1] + q[1] * h, p[2] + q[2] * h }
    right[i] = { p[1] - q[1] * h, p[2] - q[2] * h }
  end
  local out = left
  for i = n, 2, -1 do out[#out + 1] = right[i] end
  return out, nr
end
-- the closed outline of a band along the points, up one side and back down the other:
-- halfw(s, acc) the half-width at a point s along them, acc their whole length (taken as 1
-- when every point is the same one, so s / acc is 0, not 0 / 0)
local function ribbonpts(pts, halfw)
  local nr, n = normals(pts), #pts
  local s, acc = { 0 }, 0
  for i = 2, n do
    local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
    acc = acc + sqrt(dx * dx + dy * dy)
    s[i] = acc
  end
  if acc == 0 then acc = 1 end
  local out = {}
  for i = 1, n do
    local h, p, q = halfw(s[i], acc), pts[i], nr[i]
    out[i] = { p[1] + q[1] * h, p[2] + q[2] * h }
    out[2 * n + 1 - i] = { p[1] - q[1] * h, p[2] - q[2] * h }
  end
  return out
end
-- \flo@feribbon, and \flo@vstem's filled band: a ribbon along the points, widths w0 to w1,
-- in color c
local function ribbon(pts, w0, w1, c)
  smooth(ribbonpts(pts, function(s, acc) return (w0 + (w1 - w0) * s / acc) / 2 end), true) fill(c, 1)
end
-- \flo@vstreak: a ribbon along the points, widths w0 to w1, thin at its start
local function streak(pts, w0, w1, color, op)
  smooth(ribbonpts(pts, function(s, acc)
    local u = s / acc
    return (w0 + (w1 - w0) * u) * (u < 0.12 and 0.4 + 5 * u or 1) / 2
  end), true) fill(color, op)
end
-- the six points of a cubic (\flo@vbezier), for an open smooth curve (\flo@openpath)
local function bezier6(x0, y0, x1, y1, x2, y2, x3, y3)
  local b, pts = ink.bezier3(x0, y0, x1, y1, x2, y2, x3, y3), {}
  for i = 0, 5 do pts[i + 1] = { b(i / 5) } end
  return pts
end

-- ---------------------------------------------------------------- the leaflet (flora.leaflet)
-- \flo@vleaflet: along +y, length 1. o: W (nil draws one), tone (nil draws one), u (cm per unit)
function M.leaflet(o)
  local lW = o.W or range(0.16, 0.24)
  local bend = sym(0.2)
  local lt = o.tone or range(0.2, 0.34)
  local spine = {}
  for i = 0, 18 do local v = i / 18 spine[i + 1] = { bend * v * v, v } end
  local outline, nr = blade(spine, function(_, v)
    if v > 0 and v < 1 then return lW * 2.2 * v ^ 0.5 * (1 - v) ^ 0.9 end
    return 0
  end)
  smooth(outline, true) fill(tone(lt), 1)
  if o.u > K(0.25) then
    smooth(outline, true) ink.clip()
    -- the darker half: the midrib out, then back along a line one unit to one side
    local sd = chance(0.5) and 1 or -1
    moveto(spine[1][1], spine[1][2])
    for i = 2, 19 do lineto(spine[i][1], spine[i][2]) end
    for i = 19, 1, -1 do lineto(spine[i][1] + sd * nr[i][1], spine[i][2] + sd * nr[i][2]) end
    close()
    fill(tone(0.08), 0.3, true)
    local mid = {}
    for i = 0, 10 do local v = i / 10 mid[i + 1] = { bend * v * v, v } end
    streak(mid, 0.03, 0.003, WHITE, 0.65)
    smooth(outline, true) stroke(tone(0.06), 1.3 * o.u, 0.3, true)
    ink.unclip()
  end
end

-- ---------------------------------------------------------------- the bud and the fruit
-- \flo@vbud: a teardrop and three sepals, base at the origin, +y, length 1; u its cm per
-- unit, tq its tone (nil draws one)
function M.bud(u, tq)
  local bend = sym(0.1)
  local spine = {}
  for i = 0, 18 do local v = i / 18 spine[i + 1] = { bend * v * v, v } end
  local outline = blade(spine, function(_, v)
    if v > 0 then return max(0, 0.3 * max(0, sin(180 * v ^ 0.6)) ^ 0.8) end
    return 0
  end)
  tq = tq or range(0.3, 0.42)
  smooth(outline, true) fill(tone(tq), 1)
  smooth(outline, true) ink.clip()
  mottle(-0.3, 0, 0.3, 1, 5, 0.1, tq - 0.2, tq + 0.2, 0, false)
  taper(-0.08, 0.05, -0.1, 0.35, -0.05, 0.65, bend * 0.8, 0.95, 0.06, 0.005) fill(WHITE, 0.7)
  smooth(outline, true) stroke(tone(0.06), 1.4 * u, 0.3, true)
  ink.unclip()
  -- the sepals: three small blades, one path
  for i = 0, 2 do
    local k = i - 1
    local a = k * 24 + sym(6)
    local sy = k == 0 and 0.22 or 0.32
    local sp = {}
    for j = 0, 8 do local v = j / 8 sp[j + 1] = { -k * 0.4 * v * v, v } end
    local pts = blade(sp, function(_, v) if v > 0 then return max(0, sin(180 * v ^ 0.6)) end return 0 end)
    local ca, sa = cos(a), sin(a)
    for j, p in ipairs(pts) do
      local x, y = 0.06 * p[1], sy * p[2]
      pts[j] = { k * 0.05 + x * ca - y * sa, -0.02 + x * sa + y * ca }
    end
    smooth(pts, true)
  end
  fill(tone(0.14), 0.9)
end
-- \flo@vclock: a seed clock (flora.seedhead), radius 1 around the origin
local function clock()
  local n, gone = int(18, 26), range(0, 360)
  for k = 1, n do
    local a = 360 * (k + sym(0.3)) / n
    local t = G.rnd()
    local kept = not (abs((a - gone + 540) % 360 - 180) < 30 and t < 0.7)
    local L = range(0.72, 0.86)
    if kept then
      local xb, yb = L * cos(a), L * sin(a)
      moveto(0.1 * cos(a), 0.1 * sin(a)) lineto(xb, yb)
      for j = -2, 2 do
        local b = a + 18 * j
        moveto(xb, yb) lineto(xb + 0.16 * cos(b), yb + 0.16 * sin(b))
      end
    end
  end
  stroke(tone(0.16), 0.22, 0.85, false)
  circle(0, 0, 0.13) fill(tone(0.12), 1)
end
-- \flo@fruit: the species' fruit along +y, length 1; fu its cm per unit
function M.fruit(fu)
  local fr = S.fruit
  if fr == "hip" then
    local was = pen.accent
    pen.accent = true
    ink.push() ink.translate(0, 1) ink.rotate(180) M.bud(fu, 0.36) ink.pop()
    pen.accent = was
  elseif fr == "capsule" then
    M.bud(fu, 0.38)
    taper(-0.06, 0.15, -0.1, 0.4, -0.08, 0.7, -0.02, 0.95, 0.025, 0.004) fill(WHITE, 0.55)
    taper(0.06, 0.15, 0.1, 0.4, 0.08, 0.7, 0.02, 0.95, 0.025, 0.004) fill(WHITE, 0.4)
  elseif fr == "pappus" then
    ink.push() ink.translate(0, 0.5) clock() ink.pop()
  elseif fr == "silique" then
    M.leaflet({ W = 0.07, tone = range(0.3, 0.4), u = fu })
  elseif fr == "silicle" then
    ink.push() ink.scale(0.6) M.leaflet({ W = 0.32, tone = range(0.42, 0.52), u = fu }) ink.pop()
  elseif fr == "schizocarp" then
    ink.push() ink.scale(0.7) ink.rotate(12) M.leaflet({ W = 0.18, u = fu }) ink.pop()
    ink.push() ink.scale(0.7) ink.rotate(-12) M.leaflet({ W = 0.18, u = fu }) ink.pop()
  else
    ink.push() ink.scale(0.55) M.leaflet({ W = 0.22, tone = range(0.12, 0.2), u = fu }) ink.pop()
  end
end

-- ---------------------------------------------------------------- the lily and its corona
-- \flo@vlily: six pointed tepals seen from above at a tilt, petal length 1; u its cm per
-- unit, tq its tone (nil draws one). Returns the tilt (the corona is drawn in it)
local function lily(u, tq)
  local tilt, spin = range(0.45, 0.62), range(0, 60)
  tq = tq or range(0.30, 0.38)
  local O = {}
  for k = 1, 6 do O[k] = spin + (k - 1) * 60 + sym(8) end
  -- the far tepals first (a bubble sort on sin, as the library sorts them)
  for k = 1, 5 do
    for j = 1, 6 - k do
      if sin(O[j + 1]) > sin(O[j]) then O[j], O[j + 1] = O[j + 1], O[j] end
    end
  end
  for k = 1, 6 do
    local a = O[k]
    local back = sin(a)
    local js, lw = range(0.88, 1.05), range(0.11, 0.14)
    local tp = tq + 0.1 * back * -0.8 + sym(0.03)
    local sg = chance(0.5) and 1 or -1
    local pbend = sg * range(0.04, 0.14)
    local pns = int(3, 4)
    ink.push() yscale(tilt) ink.rotate(a - 90) ink.scale(js)
    M.petal({ pointed = true, W = lw, bend = pbend, ns = pns, heart = false, tone = tp, u = u })
    ink.pop()
  end
  for k = 1, 4 do
    local t = 0.05 + 0.05 * k
    smooth(blob(0, 0, t, t * tilt, 0.2, 9), true) fill(WHITE, 0.22)
  end
  for k = 1, 6 do
    local a = (k - 3.5) * 16 + sym(6)
    local len = range(0.3, 0.48)
    local ex, ey = len * sin(a), len * cos(a)
    smooth(bezier6(0, 0, ex * 0.2, ey * 0.5, ex * 0.8, ey * 0.85, ex, ey), false) stroke(tone(0.12), 0.25, 0.85, false)
    local t = -a + sym(30)
    ink.push() ink.translate(ex, ey) ink.rotate(t)
    smooth(blob(0, 0, 0.022, 0.04, 0.1, 6), true) fill(tone(0.05), 1)
    ink.pop()
    if chance(0.5) then
      local xa = ex + sym(0.03)
      local ya = ey + range(0.02, 0.05)
      circle(xa, ya, 0.008) fill(accent(0), 1)
    end
  end
  circle(0, 0, 0.035) fill(accent(-0.2), 1)
  return tilt
end
-- \flo@vturkscap: a lily whose tepals sweep back (reflex under -40), held sideways or nodding,
-- seen from the side and a little from below: from the center at the origin six tepals
-- leave a little forward (+y, the way the flower faces), then curl back toward the stalk,
-- the more the further the species' reflex; the far ones first, darker, then the stamens
-- hanging out of the flower, then the near ones; the species' dots on them. Tepal length
-- about 1; u its cm per unit, tq its tone (nil draws one)
local function turkscap(u, tq)
  local q = tq or range(0.30, 0.38)
  local spin, beta = range(0, 60), range(18, 32)
  local cb, sb = cos(beta), sin(beta)
  local curl = 60 - 1.6 * S.reflex                -- 124 to 188 degrees
  local A, J, W, C, Q, O = {}, {}, {}, {}, {}, {}
  for k = 1, 6 do
    A[k] = spin + (k - 1) * 60 + sym(8)
    J[k] = range(0.88, 1.05)
    W[k] = range(0.13, 0.17)
    C[k] = curl * range(0.85, 1.1)
    Q[k] = q + 0.08 * sin(A[k]) + sym(0.03)
    O[k] = k
  end
  for k = 1, 5 do                               -- the far tepals first
    for j = 1, 6 - k do
      if sin(A[O[j + 1]]) < sin(A[O[j]]) then O[j], O[j + 1] = O[j + 1], O[j] end
    end
  end
  local function tepal(t)
    local ca, sa = cos(A[t]), sin(A[t])
    local x, y, z = 0, 0, 0
    local P, H = { { 0, 0, 0 } }, { 0 }
    for i = 1, 10 do
      local f = -15 + C[t] * ((i - 0.5) / 10) ^ 1.3
      local r, b = cos(f) * J[t] / 10, -sin(f) * J[t] / 10
      x, y, z = x + r * ca, y + b, z + r * sa
      P[i + 1] = { x, y, z }
      H[i + 1] = i < 10 and W[t] * J[t] * sin(180 * (i / 10) ^ 0.55) ^ 0.9 or 0
    end
    local function at(i, h)                     -- spine point i moved h across, on the page
      local p = P[i]
      local px, py, pz = p[1] - h * sa, p[2], p[3] + h * ca
      return { px, py * cb - pz * sb }
    end
    local out, mid = {}, {}
    for i = 1, 11 do out[i] = at(i, H[i]) end
    for i = 10, 2, -1 do out[#out + 1] = at(i, -H[i]) end
    for i = 2, 10 do mid[i - 1] = at(i, 0) end
    smooth(out, true) fill(tone(Q[t]), 1)
    if u > 0.15 then
      smooth(out, true) ink.clip()
      streak(mid, 0.03, 0.004, WHITE, 0.5)
      if S.guides ~= "none" then
        for _ = 1, 5 do
          local i, o = int(2, 5), sym(0.6)
          local c = at(i, o * H[i])
          circle(c[1], c[2], range(0.012, 0.022))
        end
        fill(tone(0.06), 0.8, true)
      end
      smooth(out, true) stroke(tone(0.06), 1.3 * u, 0.3, true)
      ink.unclip()
    end
    smooth(out, true) stroke(tone(0.08), 0.18, 0.35, false)
  end
  local k = 1
  while k <= 6 and sin(A[O[k]]) < 0 do tepal(O[k]) k = k + 1 end
  for j = 1, 6 do                               -- the stamens and their anthers
    local a = (j - 3.5) * 12 + sym(5)
    local len = range(0.5, 0.75)
    local ex, ey = len * sin(a), len * cos(a)
    smooth(bezier6(0, 0, ex * 0.2, ey * 0.5, ex * 0.8, ey * 0.85, ex, ey), false) stroke(tone(0.12), 0.25, 0.85, false)
    local t = -a + sym(30)
    ink.push() ink.translate(ex, ey) ink.rotate(t)
    smooth(blob(0, 0, 0.022, 0.045, 0.1, 6), true) fill(accent(-0.1), 1)
    ink.pop()
  end
  circle(0, 0, 0.05) fill(tone(0.1), 1)
  while k <= 6 do tepal(O[k]) k = k + 1 end
end
-- \flo@vcorona: a lily's cup or trumpet, in the lily's frame (its tilt) after its star;
-- tq the flower's tone (nil: the corona draws one)
local function corona(u, tilt, tq)
  local h, b, R
  if S.corona == "trumpet" then h, b, R = range(0.4, 0.6), 0.1, range(0.24, 0.32)
  else h, b, R = range(0.12, 0.2), 0.14, range(0.2, 0.28) end
  local q = tq and tq - 0.08 or range(0.24, 0.32)
  local cn, cp = int(9, 14), range(0, 360)
  local function rim(a) local r = 1 + 0.09 * sin(cn * a + cp) return R * r * cos(a), h + R * r * tilt * sin(a) end
  local pts = {}
  for k = 0, 4 do local a = 180 + 45 * k pts[k + 1] = { b * cos(a), b * tilt * sin(a) } end
  for k = 1, 3 do local v = k / 4 pts[k + 5] = { b + (R - b) * v ^ 1.6, h * v } end
  for k = 0, 6 do pts[k + 9] = { rim(-30 * k) } end
  for k = 1, 3 do local v = 1 - k / 4 pts[k + 15] = { -b - (R - b) * v ^ 1.6, h * v } end
  smooth(pts, true, 0.9) fill(tone(q), 1)
  if u > 0.12 then
    smooth(pts, true, 0.9) ink.clip()
    for k = -2, 2 do
      local f = k / 2.6
      local xa, xd = f * b, f * R + sym(0.02)
      taper(xa, -0.02, 0.7 * xa + 0.3 * xd, 0.4 * h, 0.3 * xa + 0.7 * xd, 0.75 * h, xd, h, 0.025, 0.008)
      if k % 2 ~= 0 then fill(tone(0.08), 0.25, true) else fill(WHITE, 0.5) end
    end
    ink.unclip()
  end
  local ring = {}
  for k = 1, 16 do ring[k] = { rim(22.5 * k) } end
  smooth(ring, true) fill(tone(q + 0.12), 1)
  local t = 0.55 * R
  smooth(blob(0, h - 0.15 * R * tilt, t, t * tilt, 0.15, 8), true) fill(tone(q - 0.12), 0.6, true)
  local c = tone(0.08)
  smooth(ring, true) stroke(c, 0.2, 0.6, false)
  smooth(pts, true, 0.9) stroke(c, 0.2, 0.35, false)
end

-- ---------------------------------------------------------------- irises, orchids, columbines
-- \flo@ivpart: a part at angle a, length l: a haft for the fraction c of it, then flora's
-- petal (o: pointed, W, bend, tone, heart, ns, notchp; u the flower's cm per unit)
local function ivpart(a, l, c, u, o)
  ink.push() ink.rotate(a - 90) ink.scale(l)
  if c > 0 then
    local col = tone(o.tone)
    local t = c * 0.5
    taper(0, 0, 0, t, 0, t, 0, c + 0.01, 0.3 * o.W, 0.34 * o.W * (1 - c)) fill(col, 1)
    taper(0, 0.02, 0, t, 0, t, 0, c * 0.95, 0.02, 0.004) fill(WHITE, 0.6)
    ink.translate(0, c) ink.scale(1 - c)
  end
  o.notchk, o.u = 1.6, u * l * (1 - c)
  M.petal(o)
  ink.pop()
end
local function part(pointed, W, bend, tq, heart, ns, notchp)
  return { pointed = pointed, W = W, bend = bend, tone = tq, heart = heart, ns = ns, notchp = notchp }
end
-- \flo@viris: an iris three-quarters from the front, diameter 1; d its diameter in pt
local function iris(d, tq)
  local u = d / 28.45276
  local q = tq or range(0.28, 0.38)
  local cf = 0.7 * min(0.45, S.claw)
  local c = 0.55 * cf
  -- the standards: the back one, then two either side
  local a = 90 + sym(6)
  local len, b = range(0.46, 0.52), sym(0.06)
  ivpart(a, len, c, u, part(false, 0.27, b, q + 0.04, false, 5, 0.5))
  for k = 0, 1 do
    local sg = k == 0 and -1 or 1
    a = -90 + sg * range(20, 45)
    len = range(0.52, 0.6)
    b = sg * range(0.15, 0.3)
    local tp = q + sym(0.03)
    ivpart(a, len, cf, u, part(false, 0.34, b, tp, false, nil, 0.3))
    len = range(0.26, 0.32)
    ivpart(a, len, 0, u, part(false, 0.24, 0, q + 0.18, false, 3, 0.9))
  end
  c = 0.55 * cf
  for k = 0, 1 do
    local sg = k == 0 and -1 or 1
    a = 90 - sg * range(8, 28)
    len = range(0.48, 0.56)
    b = -sg * range(0.15, 0.3)
    local tp = q + 0.02 + sym(0.03)
    ivpart(a, len, c, u, part(false, 0.27, b, tp, false, 5, 0.5))
  end
  -- the front fall, its signal and beard, and its crest
  a = -90 + sym(6)
  len, b = range(0.56, 0.64), sym(0.08)
  ivpart(a, len, cf, u, part(false, 0.36, b, q, false, nil, 0.3))
  if u * len > 0.15 then
    ink.push() ink.rotate(a - 90) ink.scale(len)
    local g = S.guides
    if g == "lines" then
      local col = tone(0.06)
      for k = -2, 2 do
        local f = k * 0.07 + sym(0.03)
        local ya = range(0.25, 0.38)
        taper(f, 0.4, 0.6 * f, 0.35 * ya + 0.4, 1.1 * f, 0.7 * ya + 0.4, 1.4 * f, ya + 0.4, 0.035, 0.004)
        fill(col, 0.45, true)
      end
    end
    if g == "blotch" then
      smooth(blob(0, 0.62, 0.16, 0.12, 0.25, 9), true) fill(WHITE, 0.7)
      smooth(blob(0, 0.62, 0.07, 0.05, 0.3, 7), true) fill(tone(0.06), 0.5, true)
    end
    if g == "dots" then
      for _ = 1, 9 do
        local x, y = sym(0.16), range(0.45, 0.8)
        circle(x, y, range(0.012, 0.024))
      end
      fill(tone(0.06), 0.7, true)
    end
    for k = 1, 14 do
      local x = sym(0.035)
      circle(x, 0.38 + 0.024 * k, range(0.012, 0.022))
    end
    fill(accent(0.1), 0.9)
    ink.pop()
  end
  len = range(0.26, 0.32)
  ivpart(a, len, 0, u, part(false, 0.24, 0, q + 0.18, false, 3, 0.9))
end
-- \flo@vorchid: an orchid face on, diameter 1, upright; u its cm per unit
local function orchid(u, tq)
  local q = tq or range(0.28, 0.38)
  for k = 0, 1 do                               -- the lateral sepals
    local sg = k == 0 and -1 or 1
    local a = -90 + sg * range(45, 60)
    local len, b = range(0.42, 0.5), sym(0.08)
    ivpart(a, len, 0, u, part(true, 0.12, b, q + 0.02 + sym(0.03), false, 3, 0))
  end
  local a = 90 + sym(6)                         -- the dorsal sepal
  local len, b = range(0.4, 0.48), sym(0.08)
  ivpart(a, len, 0, u, part(true, 0.13, b, q + 0.02, false, 3, 0))
  for k = 0, 1 do                               -- the petals
    local sg = k == 0 and -1 or 1
    a = 90 - sg * range(45, 65)
    len = range(0.36, 0.44)
    b = sg * range(0, 0.12)
    ivpart(a, len, 0, u, part(false, 0.2, b, q + sym(0.03), false, 5, 0.3))
  end
  local tp = q - 0.06
  for k = 0, 1 do                               -- the lip's side lobes
    local sg = k == 0 and -1 or 1
    a = -90 + sg * range(40, 55)
    len = range(0.18, 0.24)
    ivpart(a, len, 0, u, part(false, 0.35, 0, tp, false, 3, 0))
  end
  a = -90 + sym(6)                              -- the lip
  len, b = range(0.44, 0.54), sym(0.06)
  ivpart(a, len, 0, u, part(false, 0.38, b, tp, true, 5, 0.85))
  if u * len > 0.15 then
    ink.push() ink.rotate(a - 90) ink.scale(len)
    local g = S.guides
    if g == "lines" then
      local col = tone(0.06)
      for k = -2, 2 do
        local f = k * 0.09 + sym(0.03)
        local ya = range(0.35, 0.5)
        taper(f, 0.12, 0.7 * f, 0.35 * ya + 0.12, 1.2 * f, 0.7 * ya + 0.12, 1.5 * f, ya + 0.12, 0.035, 0.004)
        fill(col, 0.45, true)
      end
    end
    if g == "blotch" then
      smooth(blob(0, 0.4, 0.2, 0.15, 0.3, 9), true) fill(WHITE, 0.65)
      for _ = 1, 8 do
        local x, y = sym(0.14), range(0.3, 0.5)
        circle(x, y, range(0.015, 0.03))
      end
      fill(tone(0.06), 0.7, true)
    end
    if g == "dots" then
      for _ = 1, 11 do
        local x, y = sym(0.24), range(0.2, 0.75)
        circle(x, y, range(0.014, 0.028))
      end
      fill(tone(0.06), 0.7, true)
    end
    ink.pop()
  end
  local col = blob(0, 0.05, 0.05, 0.085, 0.15, 8)     -- the column
  smooth(col, true) fill(WHITE, 0.85)
  smooth(col, true) stroke(tone(0.1), 0.2, 0.5, false)
  circle(0, 0.11, 0.022) fill(tone(0.06), 1)
end

-- ---------------------------------------------------------------- tubes, cups and lips
-- \flo@vtube: a bell, urn, tube or funnel in profile (flora.bell generalized), length about
-- 1; u its cm per unit; form the species' unless given (salvertube, liptube, aqcup: the
-- tube under a salver's face, a two-lipped flower's tube, a columbine's cup); tq the tone
-- (nil draws one); lp: a two-lipped flower's length and bend
local function tube(u, form, tq, lp)
  form = form or S.form
  local a, b, c, w, e, h, L, tt, sep = 0.1, 0.24, 1.3, 0, 0, 0, 0.85, 0.14, true
  local f = range(0.06, 0.12)
  local n = floor(S.merosity / 2 + 1.5)
  if n == 1 then n = 0 end                      -- no parts (merosity 0): a rim without lobes
  local bd = sym(0.08)
  if form == "campanulate" then a, b, h, e, f = 0.06, 0, 0.26, 0.07, 0.35 * f end   -- a shoulder, then the rim flares
  if form == "urceolate" then a, b, w, L, tt, f = 0.09, 0, 0.25, 0.8, 0.08, 0.07 end
  if form == "tubular" then a, b, c, w, e, L, tt, f, bd = 0.07, 0.07, 1.5, 0.025, 0.035, 0.95, 0.08, 0.05, 1.8 * bd end
  if form == "funnelform" then a, b, c, L, tt, f = 0.05, 0.4, 2.4, 0.85, 0.1, 0.1 end
  if form == "lilytube" then a, b, c, L, tt, f, n = 0.045, 0.32, 2.8, 0.95, 0.16, 0.08, 4 end   -- a trumpet lily's
  if form == "salvertube" then a, b, c, L, n = 0.035, 0.02, 1, 0.55, 0 end
  if form == "liptube" then a, b, c, L, n, bd, sep = 0.04, 0.06, 1.6, lp.L, 0, lp.b, false end
  if form == "aqcup" then a, b, c, L, tt, sep = 0.12, 0.04, 1, 0.32, 0.08, false end
  local tk = 0.7
  if S.apex == "rounded" or S.apex == "emarginate" then tk, tt = 1, 0.7 * tt end
  local g, wob = nil, 0
  if u > 0.45 then g, wob = fbm(), 0.015 end
  local function rad(v)                         -- \flo@turad: the radius at v
    local r = a
    if v > 0 then
      if b > 0 then r = r + b * v ^ c end
      if w > 0 then r = r + w * sin(180 * min(1, v / 0.92) ^ 0.85) end
      if h > 0 then r = r + h * (1 - (1 - v) ^ 2.5) end
      if e > 0 then r = r + e * v ^ 6 end
    end
    return r
  end
  local pts = {}
  for k = 0, 10 do
    local v = k / 10
    local x = rad(v) + bd * v * v
    if wob > 0 then x = x + wob * wave(g, v * 6) * v end
    pts[k + 1] = { x, L * v }
  end
  local Rr = rad(1) + f
  if n > 0 then                                 -- the lobes of the rim
    for k = 1, n do
      local v = 1 - 2 * (k - 1) / (n - 1)
      local x = Rr * v + bd + sym(0.03)
      local y = L + tt * (1 - 0.55 * v * v) + sym(0.02)
      pts[#pts + 1] = { x, y }
      if k < n then
        x = Rr * 0.85 * (v - 1 / (n - 1)) + bd
        pts[#pts + 1] = { x, L + 0.025 + sym(0.015) }
      end
    end
  end
  for k = 0, 10 do
    local v = (10 - k) / 10
    local x = bd * v * v - rad(v)
    if wob > 0 then x = x + wob * wave(g, v * 6 + 40) * v end
    pts[#pts + 1] = { x, L * v }
  end
  local q = tq or range(0.3, 0.4)
  smooth(pts, true, tk) fill(tone(q), 1)
  if u > 0.15 then
    smooth(pts, true, tk) ink.clip()
    if u > 0.45 then mottle(-0.5, 0, 0.5, L + 0.2, 10, 0.12, q - 0.2, q + 0.2, 10, false)
    else mottle(-0.5, 0, 0.5, L + 0.2, 5, 0.12, q - 0.2, q + 0.2, 0, false) end
    local sd = chance(0.5) and 1 or -1           -- the shaded side
    local xc = 2 * sd
    local col = tone(0.12)
    for _, s in ipairs({ { 0.12, 0.2 }, { 0.6, 0.16 } }) do   -- the shade's edge follows the body's curve
      local sp = { { sd * s[1] * a, -0.1 } }
      for k = 0, 10 do
        local v = k / 10
        sp[#sp + 1] = { sd * s[1] * rad(v) + bd * v * v, L * v }
      end
      sp[#sp + 1] = { sd * s[1] * Rr + bd, L + tt + 0.1 }
      sp[#sp + 1] = { xc, L + tt + 0.1 }
      sp[#sp + 1] = { xc, -0.1 }
      ink.poly(sp, true) fill(col, s[2], true)
    end
    for k = -2, 2 do                            -- streaks down the tube, dark and light
      local fk = k / 2.5
      local xa, ya = fk * rad(0.05) * 0.9 + bd * 0.0025, 0.05 * L
      local xb, yb = fk * rad(0.4) * 0.9 + bd * 0.16, 0.4 * L
      local xc2, yc = fk * rad(0.75) * 0.9 + bd * 0.5625, 0.75 * L
      local xd = fk * Rr * 0.95 + bd + sym(0.03)
      taper(xa, ya, xb, yb, xc2, yc, xd, L + 0.06, 0.02, 0.012)
      if k % 2 ~= 0 then fill(tone(0.08), 0.3, true) else fill(WHITE, 0.55) end
    end
    smooth(pts, true, tk) stroke(tone(0.06), 1.5 * u, 0.3, true)
    ink.unclip()
  end
  smooth(pts, true, tk) stroke(tone(0.08), 0.18, 0.35, false)
  if S.stamens == "exserted" and n > 0 then
    for k = -1, 1 do
      local xa, ya = k * 0.02 + 0.36 * bd, 0.6 * L
      local xb = k * 0.08 + 1.2 * bd + sym(0.02)
      local yb = L + range(0.18, 0.32)
      moveto(xa, ya) lineto(xb, yb) stroke(tone(0.12), 0.25, 0.85, false)
      circle(xb, yb, 0.018) fill(tone(0.05), 1)
    end
  end
  if sep then                                   -- the sepals
    local col = tone(0.1)
    for k = -1, 1 do
      local xd = k * (a + 0.07) + sym(0.03)
      taper(k * 0.04, -0.03, k * 0.07, 0.06, 0.9 * xd, 0.14, xd, 0.22, 0.07, 0.004) fill(col, 0.95)
    end
    circle(0, -0.02, 0.05) fill(tone(0.08), 1)
  end
end
-- \flo@vcup: a calyx in profile, about 0.27 long times k; u its cm per unit
local function cup(u, k)
  local pts = { { 0.03, -0.03 }, { 0.068, 0.08 * k }, { 0.085, 0.17 * k } }
  pts[4] = { 0.11, 0.25 * k + sym(0.02) }
  pts[5] = { 0.055, 0.2 * k }
  pts[6] = { 0.013, 0.27 * k + sym(0.02) }
  pts[7] = { -0.03, 0.2 * k }
  pts[8] = { -0.08, 0.26 * k + sym(0.02) }
  pts[9], pts[10], pts[11] = { -0.085, 0.15 * k }, { -0.064, 0.06 * k }, { -0.03, -0.03 }
  smooth(pts, true, 0.7) fill(tone(0.12), 0.95)
  if u > 0.15 then
    taper(0.034, 0.01, 0.055, 0.08 * k, 0.068, 0.14 * k, 0.085, 0.22 * k, 0.03, 0.004) fill(WHITE, 0.4)
    smooth(pts, true, 0.7) stroke(tone(0.06), 0.18, 0.4, false)
  end
  circle(0, -0.02, 0.045) fill(tone(0.08), 1)
end
-- \flo@vpea: a pea flower in profile, the standard on the +x side; u its cm per unit,
-- F the flower's knobs (tone, notchp, notchk)
local function pea(u, F)
  local q = F.tone or range(0.3, 0.4)
  local a, l, w = range(8, 28), range(0.55, 0.7), range(0.75, 0.95)
  -- the standard, broad and notched, with dark guide lines
  ink.push() ink.translate(0.04, 0.2) ink.rotate(-90 - a) ink.scale(l) xscale(w)
  M.petal({ pointed = false, W = 0.5, heart = true, notchp = 0.8, notchk = 1.4, tone = q, u = u * l })
  if S.guides ~= "none" and u * l > 0.12 then
    local col = tone(0.06)
    for k = -2, 2 do
      local f = k * 0.1 + sym(0.03)
      local len = range(0.3, 0.45) * (1 - 1.5 * f * f)
      taper(0.2 * f, 0.05, 0.6 * f, 0.35 * len + 0.05, 0.9 * f, 0.7 * len + 0.05, 1.1 * f, len + 0.05, 0.04, 0.004)
      fill(col, 0.45, true)
    end
  end
  ink.pop()
  -- the keel, a paler pointed boat
  local k, t = range(0.58, 0.68), range(8, 16)
  ink.push() ink.translate(-0.03, 0.2) ink.rotate(t) ink.scale(k)
  M.petal({ pointed = true, W = 0.12, bend = range(0.22, 0.32), heart = false, tone = q + 0.12, u = u * k,
    notchp = F.notchp, notchk = F.notchk })
  ink.pop()
  -- the near wing
  local n = range(0.44, 0.52)
  t = range(0, 8)
  ink.push() ink.translate(0.02, 0.21) ink.rotate(t) ink.scale(n)
  M.petal({ pointed = false, W = 0.26, bend = range(0, 0.08), notchp = 0, notchk = F.notchk, ns = 3, heart = false,
    tone = q - 0.03, u = u * n })
  ink.pop()
  cup(u, 0.9)
end
-- \flo@vlips: a two-lipped flower in profile, the hood on the +x side; u its cm per unit
local function lips(u, tq)
  local q = tq or range(0.3, 0.4)
  local L, lb = range(0.55, 0.68), sym(0.06)
  -- the lower lip, broad and drooping, with the species' dots or lines
  local a, l = range(35, 55), range(0.3, 0.4)
  ink.push() ink.translate(lb - 0.05, L - 0.03) ink.rotate(a) ink.scale(l)
  M.petal({ pointed = false, W = 0.42, bend = range(-0.25, -0.1), notchp = 0.6, notchk = 1.4, ns = 5, heart = false,
    tone = q + 0.05, u = u * l })
  if u * l > 0.1 then
    local g = S.guides
    if g == "dots" then
      for _ = 1, 7 do
        local x, y = sym(0.22), range(0.12, 0.55)
        circle(x, y, range(0.025, 0.045))
      end
      fill(tone(0.06), 0.7, true)
    end
    if g == "lines" then
      local col = tone(0.06)
      for k = -1, 1 do
        local f = k * 0.12 + sym(0.03)
        local len = range(0.35, 0.5)
        taper(0, 0.05, 0.5 * f, 0.35 * len + 0.05, 0.8 * f, 0.7 * len + 0.05, f, len + 0.05, 0.035, 0.004)
        fill(col, 0.5, true)
      end
    end
  end
  ink.pop()
  -- the hood, rising steeply and curling forward
  a, l = range(-80, -68), range(0.36, 0.44)
  ink.push() ink.translate(lb + 0.05, L - 0.04) ink.rotate(a) ink.scale(l)
  M.petal({ pointed = false, W = 0.26, bend = range(-1.1, -0.85), notchp = 0.4, notchk = 1, ns = 3, heart = false,
    tone = q, u = u * l })
  ink.pop()
  if S.stamens == "exserted" then
    for k = 0, 1 do
      local xa, ya = lb + 0.02, L
      local xb = xa + range(0.1, 0.2) + 0.04 * k
      local yb = ya + range(0.3, 0.42) - 0.05 * k
      moveto(xa, ya) lineto(xb, yb) stroke(tone(0.12), 0.25, 0.85, false)
      circle(xb, yb, 0.018) fill(tone(0.05), 1)
    end
  end
  tube(u, "liptube", tq, { L = L, b = lb })
  cup(u, 1.1)
end
-- \flo@vaquilegia: a columbine in profile; u its cm per unit
local function aquilegia(u, tq)
  local q = tq or range(0.3, 0.4)
  for k = 0, 1 do                               -- the back sepals
    local sg = k == 0 and -1 or 1
    local a = 90 - sg * range(105, 135)
    local len, b = range(0.32, 0.4), sym(0.08)
    ink.push() ink.translate(0, 0.12)
    ivpart(a, len, 0, u, part(true, 0.14, b, q - 0.04, false, 3, 0))
    ink.pop()
  end
  local h = range(0, 0.16)
  for k = -1, 1 do                              -- the spurs, each with its knob
    local len = range(0.38, 0.58)
    local t = sym(0.03)
    local xa, xb, yb = k * 0.08, k * 0.16 + t, 0.16 - 0.4 * len
    local xc, yc = k * 0.14 + t, 0.16 - 0.8 * len
    local xd, yd = k * (0.16 - h) + t, 0.16 - len
    local tp = k == 0 and q - 0.06 or q
    local col = tone(tp)
    taper(xa, 0.16, xb, yb, xc, yc, xd, yd, 0.12, 0.024) fill(col, 1)
    if u > 0.15 then taper(xa + 0.025, 0.14, xb + 0.018, yb, xc + 0.01, yc, xd, yd, 0.018, 0.024) fill(WHITE, 0.35) end
    circle(xd, yd, 0.03) fill(tone(tp - 0.12), 1)
  end
  for k = 0, 1 do                               -- the front sepals
    local sg = k == 0 and -1 or 1
    local a = 90 - sg * range(45, 70)
    local len, b = range(0.3, 0.38), sym(0.08)
    local tp = q + sym(0.03)
    ink.push() ink.translate(0, 0.12)
    ivpart(a, len, 0, u, part(true, 0.14, b, tp, false, 3, 0))
    ink.pop()
  end
  ink.push() ink.translate(0, 0.08) tube(u, "aqcup", q + 0.1) ink.pop()
end
-- \flo@vcalyx: a nodding flower's calyx, seen from below
local function calyx()
  local n = floor(max(3, min(6, S.merosity)))
  local a0 = range(0, 360)
  local col = tone(0.1)
  for k = 1, n do
    local a = a0 + 360 * k / n + sym(8)
    local t = range(0.26, 0.34)
    local xa, ya = t * cos(a), t * sin(a)
    taper(0, 0, 0.4 * xa - 0.06 * ya, 0.4 * ya + 0.06 * xa, 0.75 * xa - 0.04 * ya, 0.75 * ya + 0.04 * xa, xa, ya, 0.08, 0.004)
    fill(col, 0.95)
  end
  circle(0, 0, 0.05) fill(tone(0.08), 1)
end

-- ---------------------------------------------------------------- the species' flower
-- \flo@stone: the flower's tone from its color (nil: the organs draw their own), and the
-- accent's ramp for red and orange
local STONE = { violet = { 0.18, 0.26 }, pink = { 0.34, 0.42 }, white = { 0.46, 0.54 },
  yellow = { 0.4, 0.48 }, green = { 0.38, 0.46 }, red = { 0.3, 0.4, true }, orange = { 0.42, 0.52, true } }
local function stone()
  local s = STONE[S.color]
  pen.accent = false
  if not s then return nil end
  if s[3] then pen.accent = true end
  return range(s[1], s[2])
end
-- \flo@sflower: the species' flower face on, diameter 1; d its diameter in pt. F: tone
-- (nil: each organ draws one), notchp, notchk (a round petal's notch)
function M.sflower(d, F)
  local form, nn = S.form, S.merosity
  if S.merovar == 1 then
    local t = int(1, 10)
    if t == 1 then nn = nn - 1 end
    if t > 7 then nn = nn + 1 end
  end
  local pointed = S.petalshape == "lanceolate" or S.petalshape == "linear"
  if form == "head" then
    M.daisy(d, S.merosity, F)
  elseif form == "lily" then
    ink.push() ink.scale(0.48)
    local u = d * 0.48 / 28.45276
    local tilt = lily(u, F.tone)
    if S.corona ~= "none" then corona(u, tilt, F.tone) end
    ink.pop()
  elseif form == "iris" and d >= 8 then
    iris(d, F.tone)
  elseif d < 22 then
    local fp = floor(max(4, min(6, nn)))
    ink.push() ink.scale(0.5)
    if d < 8 then M.floret(d * 0.5 / 28.45276, fp, { star = pointed, tone = F.tone })
    else M.blossom(d * 0.5 / 28.45276, fp, { tone = F.tone }) end
    ink.pop()
  else
    local np = S.clade == "monocot" and 2 * nn or nn
    local W
    if not pointed then W = form == "cruciform" and 0.3 or max(0.28, min(0.5, 0.66 / S.petalaspect)) end
    local ns
    if S.guides == "none" and not pointed then ns = 5 end
    local notchp, notchk = F.notchp, F.notchk
    if form == "rosaceous" then ns, notchp, notchk = 3, 0.85, 1.6 end
    ink.push() ink.scale(0.45)
    M.flower(d * 0.45 / 28.45276, np, { pointed = pointed, tone = F.tone, W = W, ns = ns, notchp = notchp, notchk = notchk })
    ink.pop()
    if form == "rosaceous" then M.boss(S.stamens == "exserted") end
  end
end
-- \flo@vsalver: a salver's slender tube with its face tilted on top
local function salver(d, F)
  tube(d, "salvertube", F.tone)
  local t = range(0.3, 0.45)
  ink.push() ink.translate(0, 0.55) yscale(t) ink.rotate(sym(30))
  M.sflower(d * 28.45276, F)
  ink.pop()
end
-- \flo@bview: how the flower is seen, from its form and orientation, and its turn. o: side
-- (1 left, -1 right; nil draws one), fan (a head's flowers, already pointing out)
local TUBES = { campanulate = true, urceolate = true, tubular = true, funnelform = true }
local function bview(o)
  local orient, fm = S.orient, S.form
  local vw
  if orient == "erect" then vw = "face"
  else
    vw = orient == "nodding" and "back" or "tilt"
    if fm == "lily" then
      vw = "lily"
      if S.reflex < -40 then vw = "turk" elseif S.cup > K(0.6) then vw = "trumpet" end
    end
    if fm == "salverform" then vw = "salver" end
  end
  if TUBES[fm] then vw = "tube" end
  if fm == "papilionaceous" then vw = "pea" end
  if fm == "bilabiate" then vw = "lips" end
  if fm == "orchid" then vw = "orchid" end
  if orient ~= "erect" and fm == "spurred" then vw = "spur" end
  local turn = 0
  if orient == "erect" then
    if vw == "tube" then turn = sym(15) end
  else
    local side = o.side
    if side == nil then side = chance(0.5) and 1 or -1 end
    local t
    if o.fan then t = range(5, 25)
    elseif orient == "nodding" then t = range(100, 140) else t = range(50, 80) end
    turn = side * t
  end
  return vw, turn
end
-- \flo@bloom: the species' flower d cm across at a stage: a bud below 0.3, the fruit above
-- 1.15, past its best above 1; seen as bview says. o: side, fan (see bview)
function M.bloom(d, st, o)
  local was = pen.accent
  local tq = stone()
  local vw, turn = bview(o)
  if st < 0.3 then
    local k = 0.55 * d
    ink.push()
    if vw ~= "face" then ink.rotate(turn) end
    ink.scale(k) M.bud(k, tq)
    ink.pop()
  elseif st > 1.15 then
    local fu = 0.35 * d
    ink.push() ink.scale(fu) M.fruit(fu) ink.pop()
  else
    local t = sym(30)
    local bd = d * min(1, 0.55 + (st - 0.3) * 0.9)
    if st > 1 then bd = bd * (1 - 0.8 * (st - 1)) end
    local lift = pen.lift
    local F = { tone = tq, notchp = o.notchp or 0.4, notchk = o.notchk or 1 }
    ink.push()
    if vw ~= "face" then ink.rotate(turn) end
    if st > 1 then pen.lift = 1 - (1 - pen.lift) * (1 - 3 * (st - 1)) end
    if vw == "tube" then
      ink.scale(0.8 * bd) tube(0.8 * bd, nil, tq)
    elseif vw == "trumpet" then
      ink.scale(0.62 * bd) tube(0.62 * bd, "lilytube", tq)
    elseif vw == "turk" then
      ink.scale(0.42 * bd) turkscap(0.42 * bd, tq)
    elseif vw == "salver" then
      ink.scale(bd) salver(bd, F)
    elseif vw == "pea" then
      ink.scale(0.8 * bd)
      if turn < 0 then xscale(-1) end
      pea(0.8 * bd, F)
    elseif vw == "lips" then
      ink.scale(bd)
      if turn < 0 then xscale(-1) end
      lips(bd, tq)
    elseif vw == "orchid" then
      upright() ink.rotate(0.4 * t) xscale(range(0.75, 0.95))
      ink.scale(bd) orchid(bd, tq)
    elseif vw == "spur" then
      ink.scale(0.75 * bd) aquilegia(0.75 * bd, tq)
    else
      local ys = 1
      if vw == "tilt" then ys = range(0.5, 0.7) end
      if vw == "back" then ys = range(0.55, 0.75) pen.lift = 1 - (1 - pen.lift) * 0.85 end
      if ys < 1 then ink.translate(0, 0.12 * bd) yscale(ys) end
      local isiris = S.form == "iris"
      if isiris then upright() t = 0.6 * t end
      ink.rotate(t)
      if isiris then xscale(range(0.72, 1)) end
      ink.scale(bd)
      M.sflower(bd * 28.45276, F)
      if vw == "back" then calyx() end
    end
    pen.lift = lift
    ink.pop()
  end
  pen.accent = was
end

-- ================================================================ M8f3: clusters and stages
-- ---------------------------------------------------------------- stems
-- \flo@vstem: a filled ribbon along the points (cm), widths w0 to w1, or a stroke under 0.7 bp
local function stem(pts, w0, w1, t)
  local w = (w0 + w1) / 2 * 28.3465
  local c = tone(t)
  if w < 0.7 then smooth(pts, false) stroke(c, w, 1, false) return end
  ribbon(pts, w0, w1, c)
end
local function line(x1, y1, x2, y2, c, w, op) moveto(x1, y1) lineto(x2, y2) stroke(c, w, op, false) end
-- \flo@hair: a pedicel
local function hair(x1, y1, x2, y2) line(x1, y1, x2, y2, tone(0.12), 0.25, 0.9) end
-- \pgfpathellipse: center, first and second axis
local KAPPA = 0.55228475
local function ellipse(cx, cy, ax, ay, bx, by)
  local k = KAPPA
  moveto(cx + ax, cy + ay)
  curveto(cx + ax + k * bx, cy + ay + k * by, cx + bx + k * ax, cy + by + k * ay, cx + bx, cy + by)
  curveto(cx + bx - k * ax, cy + by - k * ay, cx - ax + k * bx, cy - ay + k * by, cx - ax, cy - ay)
  curveto(cx - ax - k * bx, cy - ay - k * by, cx - bx - k * ax, cy - by - k * ay, cx - bx, cy - by)
  curveto(cx - bx + k * ax, cy - by + k * ay, cx + ax - k * bx, cy + ay - k * by, cx + ax, cy + ay)
  close()
end
local function atan2(y, x) return math.atan(y, x) / RAD end
-- \flo@walk: n steps from (x, y), heading h turning by dh in all, len long; the n+1 points
local function walk(x, y, h, dh, len, n)
  local pts, ds = { { x, y } }, len / n
  for k = 1, n do
    local a = h + dh * (k - 0.5) / n
    x, y = x + ds * cos(a), y + ds * sin(a)
    pts[k + 1] = { x, y }
  end
  return pts, x, y
end
-- an axis of `steps` steps bending away to one side, as flora's cyme bends (raceme, curl)
local function bent(len, steps, h, side, turn)
  local pts, x, y, ds = { { 0, 0 } }, 0, 0, len / steps
  for k = 1, steps do
    local v = (k - 0.5) / steps
    local a = h + side * turn * v * v * sqrt(sqrt(v))
    x, y = x + ds * cos(a), y + ds * sin(a)
    pts[k + 1] = { x, y }
  end
  return pts
end
-- \flo@fdiam: the flower's diameter in a cluster at scale k
local function fdiam(k) return min(2.8, 0.7 + 0.032 * S.size) * k end

-- ---------------------------------------------------------------- the flowers of a cluster
-- a cluster collects its flowers (\flo@fadd) and draws them after its stalks (\flo@fdraw);
-- \flo@fat: a dot below stage -0.25, else the bloom, its side from its angle
local FAN = false                               -- \flo@bfan: a head's flowers point out already
local function flowers() return {} end
local function fadd(list, x, y, a, d, st) list[#list + 1] = { x, y, a, d, st } end
local function fdraw(list)
  for _, f in ipairs(list) do
    local x, y, a, d, st = f[1], f[2], f[3], f[4], f[5]
    ink.push() ink.translate(x, y) ink.rotate(a)
    if st < -0.25 then circle(0, 0, 0.3 * d) fill(tone(0.2), 1)
    else M.bloom(d, st, { side = a < 0 and -1 or 1, fan = FAN }) end
    ink.pop()
  end
end
-- a flower on a pedicel from (px, py) to (qx, qy): a dot when f > lim, the bloom otherwise
local function pedicel(px, py, qx, qy, s, st, sg, f, lim, dot)
  ink.push() ink.translate(qx, qy) ink.rotate(atan2(qy - py, qx - px) - 90)
  if f > lim then circle(0, 0, dot * s) fill(tone(0.2), 1)
  else M.bloom(s, st, { side = sg }) end
  ink.pop()
end
-- a stalk from the origin to (x, y) (\flo@blossoms, \flo@budding)
local function stalkto(dd, x, y)
  moveto(0, 0) curveto(0, 0.4 * dd, 0.6 * x, 0.7 * y, x, y) stroke(tone(0.1), 0.35, 1, false)
end

-- ---------------------------------------------------------------- single flowers and buds
-- \flo@blossoms: two to five flowers on curved stalks, a bud at the fork
local function blossoms(d, st)
  local center = S.openorder == "center"
  local n = int(2, 4)
  if S.count > 9 then n = n + 1 end
  for k = 1, n do
    local f = k - (n + 1) / 2
    local a = f * 38 + sym(10)
    local dd = d * range(0.55, 0.95)
    if k > 1 then dd = dd * range(0.85, 1.1) end
    local x, y = dd * sin(a), dd * cos(a)
    stalkto(dd, x, y)
    local m = max(1, (n - 1) / 2)
    local t = center and st - 0.3 * abs(f) / m or st - 0.3 * (1 - abs(f) / m)
    local s = d * range(0.8, 1.05)
    ink.push() ink.translate(x, y) M.bloom(s, t, { side = a < 0 and 1 or -1 }) ink.pop()
  end
  if chance(0.6) then
    local t, s = sym(50), 0.45 * d
    local was = pen.accent
    ink.push() ink.rotate(t) ink.scale(s)
    M.bud(s, stone())
    ink.pop()
    pen.accent = was
  end
end
-- \flo@budding: two to four buds on stalks; d the flowers' diameter
function M.budding(d)
  local was = pen.accent
  local n = int(2, 4)
  local tq = stone()
  for k = 1, n do
    local a = (k - (n + 1) / 2) * 34 + sym(10)
    local dd = d * range(0.5, 0.85)
    local x, y = dd * sin(a), dd * cos(a)
    stalkto(dd, x, y)
    local s = d * range(0.45, 0.6)
    ink.push() ink.translate(x, y) ink.rotate(-0.6 * a) ink.scale(s) M.bud(s, tq) ink.pop()
  end
  pen.accent = was
end

-- ---------------------------------------------------------------- umbels and racemes
-- \flo@umbelunit: a compound umbel, rays fanning upward to umbellets of starry florets
local function cumbel(reach, st)
  local tq = stone()
  local nr = floor(max(8, min(13, S.count + 3)))
  local ns = floor(max(5, min(8, S.rays / 2)))
  local lo, hi = 0.25, 0.42
  if tq then lo, hi = min(0.5, tq - 0.05), min(0.62, tq + 0.05) end
  for g = 1, nr do
    local a = 90 + (g - (nr + 1) / 2) * (110 / nr) + sym(4)
    local L = reach * range(0.78, 1) * (1 - 0.15 * abs(a - 90) / 55)
    local ex, ey = L * cos(a), L * sin(a)
    moveto(0, 0) curveto(0.15 * ex, 0.5 * ey, 0.6 * ex, 0.95 * ey, ex, ey) stroke(tone(0.12), 0.25, 0.9, false)
    for h = 1, ns do
      local b = a + (h - (ns + 1) / 2) * 16 + sym(5)
      local l = reach * range(0.12, 0.2)
      local fx, fy = ex + l * cos(b), ey + l * sin(b)
      line(ex, ey, fx, fy, tone(0.14), 0.18, 0.85)
      local r = reach * range(0.035, 0.05)
      local t = range(lo, hi)
      ink.push() ink.translate(fx, fy)
      if st > 1.15 then                       -- the fruit: a pair of seeds
        ink.rotate(b - 90) ink.scale(r)
        ellipse(-0.35, 0.9, 0.32, 0, 0, 0.9) ellipse(0.35, 0.9, 0.32, 0, 0, 0.9)
        fill(tone(0.16), 1)
      elseif st < 0.3 then circle(0, 0, 0.45 * r) fill(tone(0.2), 1)
      else ink.scale(r) M.floret(r, 5, { star = true, tone = t }) end
      ink.pop()
    end
  end
  for g = -1, 1 do                               -- the bracts
    local a = g * 40 + sym(10) + 180
    local s = reach * range(0.15, 0.22)
    ink.push() ink.rotate(a) ink.scale(s) M.leaflet({ W = 0.06, u = s }) ink.pop()
  end
end
-- \flo@racemeunit: flowers along a bending axis, the lowest oldest; ped the pedicel's length
local function raceme(len, ped, bend, st)
  local side = chance(0.5) and 1 or -1
  local turn = bend * range(0.75, 1.25)
  local h = 90 + sym(8)
  local pts = bent(len, 24, h, side, turn)
  local nr = normals(pts)
  stem(pts, 0.03, 0.006, 0.1)
  stone()
  local fd = min(1.0, 0.5 + 0.03 * S.size) * 0.8
  if bend > 150 then fd = min(0.32, fd) end
  local n = floor(min(S.count, int(8, 12)))
  for g = 1, n do
    local v = g / n
    local f = 0.1 + 0.88 * sqrt(v) * sqrt(sqrt(v))
    local ri = floor(max(2, min(25, floor(f * 24 + 1.5))))
    local sg = g % 2 == 1 and -1 or 1
    local px, py, nx, ny = pts[ri][1], pts[ri][2], nr[ri][1], nr[ri][2]
    local stalk = (ped * (1 - f) + 0.03 * f) * range(0.8, 1.2)
    local qx, qy = px + (nx * sg * 0.75 + ny * 0.65) * stalk, py + (ny * sg * 0.75 - nx * 0.65) * stalk
    if stalk > 0.03 then hair(px, py, qx, qy) end
    local s = fd * (1 - 0.5 * f) * range(0.85, 1.15)
    pedicel(px, py, qx, qy, s, st + 0.35 - 1.1 * f, sg, f, 0.86, 0.18)
  end
end

-- ---------------------------------------------------------------- cymes and the rest
-- \flo@curl: a coiled cyme from (x, y), its flowers outside the coil or alternating
local function curl(x, y, len, w, late, h, side, n, fd, st)
  local turn = (100 + 170 * S.coil) * range(0.85, 1.15)
  local pts = bent(len, 36, h, side, turn)
  for _, p in ipairs(pts) do p[1], p[2] = p[1] + x, p[2] + y end
  local nr = normals(pts)
  stem(pts, w, 0.006, 0.1)
  local same = S.siderule == "same"
  for g = 1, n do
    local v = g / n
    local f = 0.18 + 0.82 * sqrt(v) * sqrt(sqrt(v))
    local ri = floor(max(2, min(37, floor(f * 36 + 1.5))))
    local sg
    if same then sg = -side elseif g % 2 == 1 then sg = -1 else sg = 1 end
    local px, py, nx, ny = pts[ri][1], pts[ri][2], nr[ri][1], nr[ri][2]
    local stalk = (0.1 - 0.08 * f) * range(0.7, 1.2)
    local qx, qy = px + nx * sg * stalk, py + ny * sg * stalk
    if stalk > 0.03 then hair(px, py, qx, qy) end
    local s = fd * (1 - 0.74 * f) * range(0.85, 1.15)
    pedicel(px, py, qx, qy, s, st + 0.55 - f - late, sg, f, 0.8, 0.3)
  end
  return pts
end
-- \flo@curlunit: flora's cyme as the species' coiled cyme, sometimes forked
local function monochasium(len, st)
  stone()
  local side = chance(0.5) and 1 or -1
  local h = 90 + sym(10)
  local fd = min(0.4, 0.17 + 0.014 * S.size)
  local n = floor(max(9, min(17, S.count + 2)))
  local pts = curl(0, 0, len, 0.026, 0, h, side, n, fd, st)
  if chance(0.6) then
    local ci = floor(37 * range(0.25, 0.4))
    local xa, ya, xb, yb = pts[ci][1], pts[ci][2], pts[ci + 1][1], pts[ci + 1][2]
    h = atan2(yb - ya, xb - xa) - side * range(30, 50)
    local L = len * range(0.45, 0.65)
    curl(xa, ya, L, 0.018, 0.15, h, -side, floor(max(6, n * K(0.7))), fd, st)   -- 0.7 as TeX holds it: 10 flowers, then 6
  end
end
-- \flo@forkunit: flora's sprig as the species' forked cyme, a flower in every fork
local function dichasium(len, st)
  stone()
  local list = flowers()
  local depth = floor(min(3, S.depth + 1))
  local fd = min(0.45, 0.16 + 0.012 * S.size)
  local B = { { x = 0, y = 0, h = 90 + sym(8), l = len * 0.4, w = 0.024, v = 0 } }
  local i = 1
  while i <= #B do
    local b = B[i]
    local h, l, w, v = b.h, b.l, b.w, b.v
    local db = sym(20)
    local pts, x, y = walk(b.x, b.y, h, db, l, 6)
    local we = 0.72 * w
    stem(pts, w, we, 0.1)
    h = h + db
    local t = st - 0.3 * v + sym(0.05)
    local s = fd * (1 - 0.1 * v) * range(0.85, 1.1)
    if v < depth then
      if v < 2 and chance(0.4) then             -- a leaflet at the fork
        local sg = chance(0.5) and 1 or -1
        local a = h - 90 + sg * range(40, 70)
        local ls = l * range(0.35, 0.55)
        ink.push() ink.translate(x, y) ink.rotate(a) ink.scale(ls) M.leaflet({ W = 0.14, u = ls }) ink.pop()
      end
      local k = chance(0.2) and 3 or 2
      for j = 1, k do
        local a
        if k == 2 then
          a = range(16, 34)
          if j == 1 then a = -a end
        else a = (j - 2) * range(22, 36) end
        B[#B + 1] = { x = x, y = y, h = h + a, l = l * range(0.62, 0.8), w = we, v = v + 1 }
      end
      local xa, ya = x + 0.22 * l * cos(h), y + 0.22 * l * sin(h)
      hair(x, y, xa, ya)
      fadd(list, xa, ya, h - 90, s, t)
    else
      fadd(list, x, y, h - 90, s, t)
    end
    i = i + 1
  end
  fdraw(list)
end
-- \flo@axis: a raceme-like axis; \flo@axisat: its point, normal and heading at fraction f
local function axis(len, bend, w)
  local side = chance(0.5) and 1 or -1
  local turn = bend * range(0.75, 1.25)
  local pts = bent(len, 24, 90 + sym(8), side, turn)
  local nr = normals(pts)
  stem(pts, w, 0.006, 0.1)
  return pts, nr
end
local function axisat(pts, nr, f)
  local i = floor(max(2, min(25, floor(f * 24 + 1.5))))
  local nx, ny = nr[i][1], nr[i][2]
  return pts[i][1], pts[i][2], nx, ny, atan2(-nx, ny)
end
-- \flo@panicleunit: branches up an axis, each with a flower at its end and a few on hairs
local function panicle(len, st)
  stone()
  local list = flowers()
  local fd = min(0.34, 0.15 + 0.01 * S.size)
  local A, AN = axis(len, 30, 0.026)
  local m = floor(max(3, min(7, S.count / 4 + 1)))
  local sg = chance(0.5) and 1 or -1
  for g = 1, m do
    local f = 0.1 + 0.66 * (g - 1) / max(1, m - 1) + sym(0.03)
    local px, py, _, _, ah = axisat(A, AN, f)
    sg = -sg
    local ang = range(40, 58)
    local h = ah + sg * ang
    local l = len * 0.42 * (1 - 0.7 * f) * range(0.8, 1.2)
    local db = -sg * 0.55 * ang
    local pts, x, y = walk(px, py, h, db, l, 8)
    local nr = normals(pts)
    fadd(list, x, y, h + db - 90, fd * (1 - 0.3 * f), st + 0.2 - 0.9 * f)
    local k = int(1, 3)
    if S.depth == 2 and f < 0.45 then k = k + 1 end
    for j = 1, k do
      local v = 0.3 + 0.5 * (j - 1) / max(1, k - 1)
      local q = floor(1 + floor(v * 8 + 0.5))
      local s2 = j % 2 == 1 and 1 or -1
      local xa, ya, nx, ny = pts[q][1], pts[q][2], nr[q][1], nr[q][2]
      local t = range(0.1, 0.18)
      local xb, yb = xa + (nx * s2 * 0.8 + ny * 0.6) * t, ya + (ny * s2 * 0.8 - nx * 0.6) * t
      hair(xa, ya, xb, yb)
      fadd(list, xb, yb, atan2(yb - ya, xb - xa) - 90, fd * (0.9 - 0.3 * f), st + 0.3 - 0.9 * f - 0.25 * (1 - v))
    end
    stem(pts, 0.012, 0.005, 0.12)
  end
  local _, _, _, _, ah = axisat(A, AN, 1)
  fadd(list, A[25][1], A[25][2], ah - 90, 0.6 * fd, st - 0.6)
  fdraw(list)
end
-- \flo@thyrseunit: little forked cymes in pairs up an axis
local function thyrse(len, st)
  stone()
  local list = flowers()
  local fd = min(0.42, 0.15 + 0.012 * S.size)
  local A, AN = axis(len, 20, 0.028)
  local m = floor(max(6, min(11, S.count / 2.5)))
  for g = 1, m do
    local f = 0.08 + 0.84 * (g - 1) / max(1, m - 1)
    local px, py, _, _, ah = axisat(A, AN, f)
    for n = 0, 1 do
      local sg = n == 0 and 1 or -1
      local h = ah + sg * range(45, 65)
      local l = len * 0.17 * (1 - 0.75 * f) * range(0.8, 1.2)
      local xa, ya = px + l * cos(h), py + l * sin(h)
      hair(px, py, xa, ya)
      local t, s = st + 0.3 - 1.0 * f, fd * (1 - 0.4 * f)
      if f < 0.8 then
        for j = 0, 1 do
          local a = h + (j == 0 and 1 or -1) * range(30, 50)
          local xb, yb = xa + 0.55 * l * cos(a), ya + 0.55 * l * sin(a)
          hair(xa, ya, xb, yb)
          fadd(list, xb, yb, a - 90, 0.85 * s, t - 0.2)
        end
      end
      fadd(list, xa + 0.15 * l * cos(h), ya + 0.15 * l * sin(h), h - 90, s, t)
    end
  end
  local _, _, _, _, ah = axisat(A, AN, 1)
  fadd(list, A[25][1], A[25][2], ah - 90, 0.6 * fd, st - 0.75)
  fdraw(list)
end
-- \flo@corymbunit: stalks of falling length, the flowers level at the top; fd the flowers' size;
-- none at length 0 (its width divides)
local function corymb(len, fd, st)
  if len == 0 then return end
  stone()
  local list = flowers()
  local cfd = min(0.6, 0.3 * fd)
  local m = floor(max(3, min(9, min(S.count, 2.6 / cfd))))
  local W, top, ca = len * 0.7, len * 0.92, len * 0.5
  local t = sym(0.06)
  moveto(0, 0) curveto(t, 0.35 * ca, t, 0.7 * ca, 0, ca) stroke(tone(0.1), 0.5, 1, false)
  local sg = chance(0.5) and 1 or -1
  for g = 1, m do
    local v = (g - 1) / max(1, m - 1)
    sg = -sg
    local ya = ca * (0.12 + 0.88 * v)
    local xb = sg * W * (1 - 0.85 * v) * range(0.75, 1)
    local yb = top - 0.32 * xb * xb / W + sym(0.08)
    moveto(0, ya) curveto(0.55 * xb, ya + 0.25 * (yb - ya), 0.95 * xb, yb - 0.45 * (yb - ya), xb, yb)
    stroke(tone(0.12), 0.3, 0.9, false)
    local s = cfd * range(0.85, 1.1)
    fadd(list, xb, yb, -20 * xb / W, s, st - 0.35 * v)
  end
  local c = tone(0.12)
  local xb = sym(0.04)
  line(0, ca, xb, top, c, 0.3, 0.9)
  fadd(list, xb, top, 0, 0.9 * cfd, st - 0.42)
  fdraw(list)
end
-- \flo@spikeunit: flowers close along an axis, in threes
local function spike(len, st)
  stone()
  local list = flowers()
  local fd = min(0.5, 0.2 + 0.014 * S.size)
  local A, AN = axis(len, 14, 0.03)
  local m = floor(max(14, min(30, S.count + 4)))
  for g = 1, m do
    local f = 0.06 + 0.92 * (g - 1) / max(1, m - 1) + sym(0.01)
    local px, py, nx, ny, ah = axisat(A, AN, f)
    local s = fd * (1 - 0.45 * f) * range(0.85, 1.1)
    local t = st + 0.35 - 1.2 * f
    local k = g % 3
    if k == 0 then fadd(list, px, py, ah - 90 + sym(10), s, t)
    else
      local sg = k == 1 and 1 or -1
      local a = ah - 90 + sg * range(30, 55)
      fadd(list, px + nx * sg * 0.42 * s, py + ny * sg * 0.42 * s, a, s, t)
    end
  end
  fdraw(list)
end
-- \flo@umbelsunit: a simple umbel, its rays opening from the middle or the edge
local function umbel(len, st)
  stone()
  local list = flowers()
  local center = S.openorder == "center"
  local fd = min(0.8, 0.24 + 0.02 * S.size)
  local m = floor(max(4, min(12, S.count)))
  local ang = range(50, 75)
  for g = 1, m do
    local k = g % 2 == 1 and nediv(g + 1, 2) or m + 1 - nediv(g, 2)
    local f = (k - (m + 1) / 2) / max(1, (m - 1) / 2)
    local a = 90 + f * ang + sym(5)
    local R = len * range(0.88, 1.05) * (1 - 0.12 * abs(f))
    local xb, yb = R * cos(a), R * sin(a)
    moveto(0, 0) curveto(0.15 * xb, 0.5 * yb, 0.6 * xb, 0.95 * yb, xb, yb) stroke(tone(0.12), 0.25, 0.9, false)
    local t = center and st - 0.35 * abs(f) or st - 0.35 * (1 - abs(f))
    t = t + sym(0.05)
    local s = fd * range(0.85, 1.1)
    fadd(list, xb, yb, a - 90, s, t)
  end
  for g = -1, 1 do                               -- the bracts
    local a = g * 40 + sym(10) + 180
    local s = len * range(0.12, 0.18)
    ink.push() ink.rotate(a) ink.scale(s) M.leaflet({ W = 0.06, u = s }) ink.pop()
  end
  fdraw(list)
end
-- \flo@headunit: a head of flowers on Vogel's spiral at the top of a stalk
local function head(len, st)
  stone()
  local list = flowers()
  local A, AN = axis(len, 18, 0.024)
  local px, py, nx, ny = axisat(A, AN, 1)
  local r = (0.26 + 0.006 * S.count) * range(0.9, 1.1)
  local cx, cy = px + 0.75 * r * ny, py - 0.75 * r * nx
  local m = floor(max(18, min(34, S.count + 6)))
  for g = 1, m do
    local k = m + 1 - g
    local v, a = sqrt(k / m), 137.508 * k
    local x, y = cx + 0.8 * r * v * cos(a), cy + 0.72 * r * v * sin(a)
    local s = r * 0.65 * (0.7 + 0.3 * v) * range(0.9, 1.1)
    fadd(list, x, y, a - 90, s, st - 0.45 * (1 - v))
  end
  FAN = true
  fdraw(list)
  FAN = false
end
-- \flo@catkinunit: hanging tassels from a twig, fruit in autumn
local function catkin(len, st)
  local tq = stone()
  local h, db = 90 + sym(10), sym(15)
  local A = walk(0, 0, h, db, len, 6)
  stem(A, 0.028, 0.016, 0.1)
  local m = int(2, 4)
  local w = 0.11 + 0.02 * S.size
  local we, t0 = 0.4 * w, tq or 0.4
  for g = 1, m do
    local xa, ya = A[8 - g][1], A[8 - g][2]
    local sg = g % 2 == 1 and 1 or -1
    local hd = h + db + sg * range(40, 80)
    if st > 1.15 then
      local xb, yb = xa + 0.25 * cos(hd), ya + 0.25 * sin(hd)
      hair(xa, ya, xb, yb)
      ink.push() ink.translate(xb, yb) ink.rotate(hd - 90) ink.scale(0.3) M.fruit(0.3) ink.pop()
    else
      local tg = sg == 1 and 270 or -90
      local L = len * 2.2 * range(0.7, 1.1) * min(1, 0.45 + 0.6 * st)
      local ph, r = sym(180), hd - tg
      local pts, x, y, ds = { { xa, ya } }, xa, ya, L / 18
      for k = 1, 18 do
        local v = (k - 0.5) / 18
        local a = tg + r * (1 - min(1, v * 3)) + 7 * sin(360 * v + ph)
        x, y = x + ds * cos(a), y + ds * sin(a)
        pts[k + 1] = { x, y }
      end
      smooth({ pts[1], pts[2], pts[3], pts[4], pts[5] }, false) stroke(tone(0.1), 0.4, 1, false)
      local tassel = {}
      for k = 4, 19 do tassel[k - 3] = pts[k] end
      local nr = normals(tassel)
      stem(tassel, 0.3 * we, 0.1 * we, 0.12)         -- the axis, under its scales
      -- scales on either side by turns, each leaning down and out over the next, lit on one
      -- side and shaded on the other, an anther at its tip; the paper shows between them
      local ca, cb, c = tone(t0 + 0.06), tone(t0 - 0.06), tone(0.16)
      for k = 2, 16 do
        local s2 = k % 2 == 1 and 1 or -1
        local s = w * 0.5 * (1 - 0.55 * (k - 1) / 15)
        local px, py, nx, ny = tassel[k][1], tassel[k][2], nr[k][1], nr[k][2]
        local dx, dy = 0.91 * ny + 0.42 * s2 * nx, 0.42 * s2 * ny - 0.91 * nx
        local cx, cy = px + s2 * 0.35 * s * nx, py + s2 * 0.35 * s * ny
        local l = min(1.04 * s, max(0.75 * s, 1.1 * ds))   -- over the next on its side, if it can
        ellipse(cx, cy, l * dx, l * dy, -0.65 * s * dy, 0.65 * s * dx)
        fill(s2 == 1 and ca or cb, 0.95)
        circle(cx + l * dx, cy + l * dy, range(0.008, 0.014)) fill(c, 0.9)
      end
    end
  end
end

-- ---------------------------------------------------------------- the inflorescence
-- \flo@unitdraw: the species' inflorescence at scale k, at the origin along +y; st the
-- stage of its oldest flower
function M.unit(k, st)
  local was = pen.accent
  local fd = fdiam(k)
  local f = S.inflo
  if f == "solitary" then M.bloom(fd, st, {})
  elseif f == "cumbel" then cumbel(range(0.95, 1.35) * k, st)
  else
    local L = range(1.5, 2.3) * k
    if f == "raceme" then raceme(L, 0.3, 40, st)
    elseif f == "spike" then spike(L, st)
    elseif f == "panicle" then panicle(L, st)
    elseif f == "thyrse" then thyrse(L, st)
    elseif f == "monochasium" then monochasium(L, st)
    elseif f == "catkin" then catkin(0.3 * L, st)
    elseif f == "dichasium" then dichasium(0.8 * L, st)
    elseif f == "corymb" then corymb(0.75 * L, fd, st)
    elseif f == "umbel" then umbel(0.55 * L, st)
    elseif f == "head" then head(0.35 * L, st)
    else blossoms(0.85 * fd, st) end
  end
  pen.accent = was
end

-- ---------------------------------------------------------------- tendrils
-- \flo@vcurl: a tendril, each its own (run, side, turns, tightness): 45 points
local function vcurl(size)
  local hand = chance(0.5) and 1 or -1
  local d = size * range(0.2, 0.9) / 8
  local db = sym(4)
  local t = G.rnd()
  local T = hand * (4 + 21 * t * sqrt(t))
  local r = size * range(0.18, 0.35)
  local q = range(0.12, 0.45)
  local a, x, y = 90, 0, 0
  local pts = { { 0, 0 } }
  for k = 1, 8 do
    a = a + db
    x, y = x + d * cos(a), y + d * sin(a)
    pts[k + 1] = { x, y }
  end
  for k = 1, 36 do
    a = a + T
    local s = r * q ^ (k / 36) * abs(T) * 0.0174533
    x, y = x + s * cos(a), y + s * sin(a)
    pts[k + 9] = { x, y }
  end
  return pts
end
M.vcurl = vcurl
-- \flo@vtendril: a climber's tendril on a stalk of its own
function M.tendril(size)
  stem(vcurl(1.6 * size), 0.022, 0.004, 0.12)
end

-- ================================================================ M8f4: leaves
-- ---------------------------------------------------------------- the monocot's strap
-- \flo@vstrap: a parallel-veined leaf in flora's manner, along +y, length 1; lW its half
-- width's scale, bend (nil draws one), u its cm per unit. A leaf a centimeter long or more
-- may arch over (#5077), its spine turning by T degrees toward its bend, more toward the
-- tip (the species' curl makes it likelier); some of those twist past spine point ka,
-- turning edge on, and show their paler underside beyond it (its twist makes it likelier)
local function strap(lW, bend, u)
  local b = sym(0.25)
  if bend then b = bend end
  local lt = range(0.24, 0.34)
  local T, ka = 0, 25
  if u > K(1) and chance(max(0.1, min(0.65, 0.3 + S.curl))) then
    T = range(30, 85) * min(1, 0.07 / lW)       -- a broad blade arches less, and twists seldom
    if b < 0 then T = -T end
    if chance((0.3 + 0.01 * S.twist) * max(0, min(1, (0.1 - lW) / 0.05))) then ka = int(13, 17) end
  end
  local vt = ka < 25 and (ka - 1.5) / 24 or 2   -- the twist's middle, edge on over 0.3 of the length
  local spine = {}
  if T == 0 then
    for i = 0, 24 do local v = i / 24 spine[i + 1] = { b * v * v, v } end
  else
    local x, y = 0, 0
    spine[1] = { 0, 0 }
    for i = 1, 24 do
      local a = T * ((i - 0.5) / 24) ^ 2
      x, y = x + sin(a), y + cos(a)
      spine[i + 1] = { x / 24, y / 24 }
    end
  end
  local function hw(v)
    if v <= 0 or v >= 1 then return 0 end
    local h = lW * 2.2 * v ^ 0.25 * (1 - v) ^ 0.6
    local t = (v - vt + 0.15) / 0.3              -- beyond it, the underside turned a little away
    if t >= 1 then return 0.8 * h end
    if t > 0 then h = h * max(0.12, (t > 0.5 and 0.8 or 1) * abs(cos(180 * t * t * (3 - 2 * t)))) end
    return h
  end
  local nr = normals(spine)
  local function piece(i0, i1)                  -- the outline over spine points i0..i1
    local left, right = {}, {}
    for i = i0, i1 do
      local h, p, q = hw((i - 1) / 24), spine[i], nr[i]
      left[#left + 1] = { p[1] + q[1] * h, p[2] + q[2] * h }
      right[#right + 1] = { p[1] - q[1] * h, p[2] - q[2] * h }
    end
    local out, n = left, #right
    if hw((i1 - 1) / 24) > 0 then out[#out + 1] = right[n] end
    for k = n - 1, 2, -1 do out[#out + 1] = right[k] end
    if hw((i0 - 1) / 24) > 0 then out[#out + 1] = right[1] end
    return out
  end
  local outline = piece(1, ka)
  smooth(outline, true) fill(tone(lt), 1)
  smooth(outline, true) ink.clip()
  local sd = chance(0.5) and 1 or -1
  local x0, x1, y1 = -lW * 2.5, lW * 2.5, 1
  if T == 0 then
    for i = 0, 12 do
      local v = i / 12
      if i == 0 then moveto(b * v * v, v) else lineto(b * v * v, v) end
    end
    lineto(sd * 2, 1) lineto(sd * 2, 0) close()
  else                                          -- the darker half follows the spine's turn
    for i = 1, ka do
      if i == 1 then moveto(0, 0) else lineto(spine[i][1], spine[i][2]) end
    end
    for i = ka, 1, -1 do
      local h, p, q = sd * (1.3 * hw((i - 1) / 24) + 0.01), spine[i], nr[i]
      lineto(p[1] + q[1] * h, p[2] + q[2] * h)
    end
    close()
    local xa, xb, yb = 0, 0, 0
    for i = 1, 25 do
      local p = spine[i]
      xa, xb, yb = min(xa, p[1]), max(xb, p[1]), max(yb, p[2])
    end
    x0, x1, y1 = xa - lW * 2.5, xb + lW * 2.5, yb + lW
  end
  fill(tone(0.12), 0.28, true)
  mottle(x0, 0, x1, y1, 10, 0.07, lt - 0.2, lt + 0.22, 8, "xy")
  smooth(outline, true) stroke(tone(0.06), 1.3 * u, 0.22, true)
  -- the midrib in white, and faint parallel veins either side
  local mid = {}
  if T == 0 then
    for i = 0, 10 do local v = 0.02 + 0.93 * i / 10 mid[i + 1] = { b * v * v, v } end
  else
    for i = 1, 24 do mid[i] = spine[i] end
  end
  streak(mid, 0.016, 0.002, WHITE, 0.7)
  for k = 1, 4 do
    local f = (k < 3 and k - 3 or k - 2) * 0.38
    local pts = {}
    if T == 0 then
      for i = 0, 10 do
        local v = 0.05 + 0.85 * i / 10
        pts[i + 1] = { b * v * v + f * hw(v), v }
      end
    else
      for i = 1, 11 do
        local p, q, h = spine[2 * i], nr[2 * i], f * hw((2 * i - 1) / 24)
        pts[i] = { p[1] + q[1] * h, p[2] + q[2] * h }
      end
    end
    streak(pts, 0.007, 0.001, WHITE, range(0.18, 0.32))
  end
  ink.unclip()
  if ka < 25 then                               -- past the twist, the underside
    local under = piece(ka, 25)
    smooth(under, true) fill(tone(min(0.64, lt + 0.26)), 1)
    smooth(under, true) ink.clip()
    local sp = {}
    for i = ka, 24 do sp[#sp + 1] = spine[i] end
    streak(sp, 0.014, 0.002, WHITE, 0.6)
    smooth(under, true) stroke(tone(0.06), 1.3 * u, 0.3, true)
    ink.unclip()
  end
end

-- ---------------------------------------------------------------- the species' blade
-- \flo@sshape: the outline's numbers, the base first, then the shape (which may fix the
-- base), then the apex: lvm the widest point, lkb/lka the base's and apex's superellipse
-- exponents, ldrop basal lobes, lhl outward lobes, lobl an oblique base, lacu a drip tip,
-- ltip a notch or a point, lround a round tip whatever the apex
local LBASE = {
  cuneate = function(s) s.kb = 1.15 end,
  rounded = function(s) s.kb = 2 end,
  truncate = function(s) s.kb = 3.5 end,
  cordate = function(s) s.kb, s.drop = 2, 1 end,
  auriculate = function(s) s.kb = 1.5 end,
  oblique = function(s) s.kb, s.obl = 1.8, 0.08 end,
}
local LSHAPE = {
  linear = function(s) s.vm, s.kb = 0.45, max(s.kb, 2.2) end,
  lanceolate = function(s) s.vm = 0.3 end,
  elliptic = function(s) s.vm = 0.5 end,
  ovate = function(s) s.vm = 0.3 end,
  obovate = function(s) s.vm = 0.68 end,
  oblong = function(s) s.vm, s.kb = 0.5, max(s.kb, 2.4) end,
  orbicular = function(s) s.vm, s.kb, s.round = 0.5, 2, true end,
  cordate = function(s) s.vm = 0.3 end,
  reniform = function(s) s.vm, s.kb, s.drop, s.round = 0.42, 2, 0.8, true end,
  deltoid = function(s) s.vm, s.kb = 0.1, 3.5 end,
  sagittate = function(s) s.vm, s.kb, s.drop = 0.32, 1.8, 2 end,
  hastate = function(s) s.vm, s.kb, s.hl, s.drop = 0.38, 1.7, 1.05, 0.2 end,
}
local LAPEX = {
  acute = function(s) s.ka = 1.25 end,
  acuminate = function(s) s.ka, s.acu = 1.5, true end,
  obtuse = function(s) s.ka = 2 end,
  rounded = function(s) s.ka = 2.6 end,
  emarginate = function(s) s.ka, s.tip = 2.6, -1 end,
  mucronate = function(s) s.ka, s.tip = 2.3, 1 end,
}
local function sshape(leaflet)
  local s = { W = max(0.035, min(0.6, 0.5 / S.leafaspect)), vm = 0.35, drop = 0, hl = 0, obl = 0, acu = false, tip = 0,
    round = false }
  LBASE[S.leafbase](s) LSHAPE[S.leafshape](s) LAPEX[S.leafapex](s)
  if s.round then s.ka, s.acu = max(s.ka, 2.2), false end
  if not leaflet and S.attachment == "clasping" and s.drop == 0 then s.drop, s.kb = 0.7, max(s.kb, 2) end
  return s
end
-- \flo@shw: the blade's half-width at v along the spine, and the drop below it
local function shw(s, v)
  local h, dy
  if v < s.vm then
    local t = (s.vm - v) / s.vm
    h = t > 0.9995 and 0 or s.W * (1 - t ^ s.kb) ^ (1 / s.kb)
    dy = s.drop * s.W * sin(180 * (1 - t)) * t
  else
    local t = (v - s.vm) / (1 - s.vm)
    h = t > 0.9995 and 0 or s.W * (1 - t ^ s.ka) ^ (1 / s.ka)
    if s.acu and t > 0.2 then
      t = min(1, (t - 0.2) / 0.65)
      h = h * (1 - 0.7 * t * t * (3 - 2 * t))
    end
    dy = 0
  end
  if s.hl > 0 then
    local t = max(0, 1 - abs(v - 0.11) / 0.11)
    if t > 0 then h = max(h, s.hl * s.W * t) end
  end
  return h, dy
end
-- \flo@smargin: the body's margin samples { v, profile, left scale, right scale }, and
-- the teeth's depth and the outline's tension
local LMARGIN = {
  undulate = function(m) m.k = 1 end,
  serrate = function(m) m.k, m.tk, m.td = 2, 0.5, 1.2 end,
  doubly = function(m) m.k, m.tk, m.td = 2, 0.5, 1.3 end,
  dentate = function(m) m.k, m.tk, m.td = 2, 0.5, 1.3 end,
  crenate = function(m) m.k, m.td = 2, 1.5 end,
}
local TOOTH = {                   -- each point's phase (plus the tooth's jitter where true) and profile
  serrate = { { 0, 0 }, { 0.75, 1, true } },
  doubly = { { 0, 0 }, { 0.38, 0.55 }, { 0.52, 0.3 }, { 0.82, 1, true } },
  dentate = { { 0, 0 }, { 0.5, 1, true } },
  crenate = { { 0, 0 }, { 0.2, 0.72 }, { 0.5, 1, true }, { 0.8, 0.72 } },
}
local function smargin(s, depth, bn, u, over)
  local m = { k = 0, tk = 0.8, dep = 0, td = 1 }
  local name = S.leafmargin
  if over then name = over end
  if depth <= 0 and LMARGIN[name] then LMARGIN[name](m) end
  if m.k == 2 and S.teeth < 1 then m.k, m.tk = 0, 0.8 end    -- a toothed margin with no teeth: smooth
  local ms = {}
  if m.k < 2 then
    local n
    if m.k == 1 then n, m.dep = int(3, 5), (0.05 + S.dissection) * s.W * 2.4 end
    for k = 0, bn do
      local v = 0.5 - 0.5 * cos(180 * k / bn)
      ms[#ms + 1] = { v, m.k == 1 and 0.5 + 0.5 * sin(360 * n * v) or 1, 1, 1 }
    end
  else
    if over then m.dep = min(0.25, S.dissection) * s.W * m.td
    else m.dep = S.dissection * s.W * m.td end
    local tn = floor(min(S.teeth, max(4, floor(4 + 8 * u + 0.5))))
    local tw = 0.81 / tn
    for k = 0, 4 do ms[#ms + 1] = { 0.12 * (1 - cos(90 * k / 5)), 1, 1, 1 } end
    for k = 1, tn do
      local jl, jr, jp = range(0.65, 1.35), range(0.65, 1.35), sym(0.06)
      local vo = 0.12 + tw * (k - 1)
      for _, p in ipairs(TOOTH[name]) do ms[#ms + 1] = { vo + tw * (p[1] + (p[3] and jp or 0)), p[2], jl, jr } end
    end
    ms[#ms + 1] = { 0.93, 0, 1, 1 }
    for k = 1, 5 do ms[#ms + 1] = { 0.93 + 0.07 * sin(90 * k / 5), 1, 1, 1 } end
  end
  return ms, m
end
-- \flo@sblade: the blade along +y, length 1, in flora.leaf's hand with the species' outline.
-- o: bend (nil draws one), lobes, depth, tone (nil draws one), u (cm per unit), leaflet,
-- over (a leaflet's margin in place of the species')
local function sblade(s, o)
  local lbend = o.bend or sym(0.25)
  local lobes, depth = o.lobes, o.depth
  local lt = o.tone or range(0.26, 0.38)
  local u = o.u
  local fine, bn = false, 24
  if u > K(0.6) then fine, bn = true, 36 end
  -- a leaflet's level of detail: under 1.4 cm a coarser edge, no mottle or side veins,
  -- under 4 mm a flat shape
  local lod = 2
  if o.leaflet and u < K(1.4) then
    lod, fine, bn = 1, false, 16
    if u < K(0.4) then lod, bn = 0, 12 end
  end
  local bodyw, ent = 1, true
  if depth > 0 then bodyw, ent = 1 - 0.75 * depth, false end
  -- the spine, along a curled tip's circle beyond hv
  local hk, hv, hl, hth, hp, ht, hn, hr = false
  local function spine0(v) return lbend * v * v - 0.3 * lbend * v, v end
  local function spine(v)
    if hk and v > hv then
      local a = (v - hv) / hl * hth
      local sa, ca = sin(a), 1 - cos(a)
      return hp[1] + hr * (sa * ht[1] + ca * hn[1]), hp[2] + hr * (sa * ht[2] + ca * hn[2])
    end
    return spine0(v)
  end
  local function tangent(v)
    local ax, ay = spine(max(0, v - 0.01))
    local bx, by = spine(min(1, v + 0.01))
    local dx, dy = bx - ax, by - ay
    local l = sqrt(dx * dx + dy * dy)
    return dx / l, dy / l
  end
  -- a curled tip, on an unlobed leaf drawn in full 8 mm long or more, hairless unless broad
  if lod == 2 and ent and (S.hairy == 0 or s.W >= K(0.15)) and u > K(0.8) then
    if chance(min(0.55, max(0, S.curl + 0.25))) then
      hl = range(0.25, 0.4)
      hv = 1 - hl
      local h = shw(s, hv)
      hth = min(range(120, 190), hl / (1.8 * max(0.01, h)) * 57.29578)
      if hth > 45 then
        hk = true
        local hs = lbend < 0 and -1 or 1
        hp = { spine0(hv) }
        local tx = 2 * lbend * hv - 0.3 * lbend
        local l = sqrt(tx * tx + 1)
        ht = { tx / l, 1 / l }
        hn = { hs * ht[2], -hs * ht[1] }
        hr = hl / hth * 57.29578
      end
    end
  end
  -- the body along its margin's samples
  local ms, m = smargin(s, depth, bn, u, o.over)
  local mn = #ms
  local pts = {}
  for i = 1, mn do pts[i] = { spine(ms[i][1]) } end
  local nr = normals(pts)
  local left, right = {}, {}
  for i = 1, mn do
    local v, sdd = ms[i][1], ms[i][2]
    local h, dy = shw(s, v)
    local cut = m.dep * min(1, h / (0.45 * s.W)) * (1 - sdd)
    -- a curled tip narrows as it turns edge-on, the more the species' leaves twist
    local hwf = 1
    if hk and v > hv then
      local t = min(1, (v - hv) / hl)
      hwf = 1 - (0.25 + 0.008 * S.twist) * min(1, hth / 150) * t * t * (3 - 2 * t)
    end
    local p, q = pts[i], nr[i]
    local e = max(0, h * bodyw - cut * ms[i][3]) * hwf
    left[i] = { p[1] + q[1] * e, p[2] + q[2] * e - dy }
    if s.obl > 0 then h, dy = shw(s, max(0, (v - s.obl) / (1 - s.obl))) end
    e = max(0, h * bodyw - cut * ms[i][4]) * hwf
    right[i] = { p[1] - q[1] * e, p[2] - q[2] * e - dy }
  end
  -- the tip: notched (emarginate) or a short point (mucronate)
  if s.tip < 0 then left[mn][2] = left[mn][2] - 0.25 * s.W end
  if s.tip > 0 then left[mn][2] = left[mn][2] + 0.04 end
  local outline = {}
  for i = 1, mn do outline[i] = left[i] end
  for i = mn - 1, 2, -1 do outline[#outline + 1] = right[i] end
  local shapes = { outline }
  local tks = { m.tk }
  -- a hairy leaf's fringe
  if S.hairy == 1 and fine then
    local on = normals(outline)
    local c = tone(0.1)
    for i = 1, #outline, 2 do
      local h = range(0.008, 0.02)
      local p, q = outline[i], on[i]
      moveto(p[1], p[2]) lineto(p[1] + q[1] * h, p[2] + q[2] * h)
    end
    stroke(c, 0.15, 0.55, false)
  end
  -- the lobes, grown out of the body along the spine
  local veins = {}
  if depth > 0 then
    local pal = S.leafmargin == "palmatelobed"
    local wf, nl = 1, lobes
    if pal then wf, nl = 1.3, floor(max(1, floor(lobes / 2))) end
    for kc = 0, 1 do
      local side = kc == 0 and -1 or 1
      for ka = 1, nl do
        local lv, L, ang, reach
        if pal then
          lv = 0.04 + 0.025 * ka
        else
          lv = 0.1 + 0.72 * (ka - (side > 0 and 0.25 or 0.75)) / lobes
        end
        local lx, ly = spine(lv)
        local tx, ty = tangent(lv)
        if pal then
          L = 0.8 * (1 - 0.3 * (ka - 1) / nl) * range(0.9, 1.1)
          ang = range(30, 40) + 45 * (ka - 1) / max(1, nl - 1)
        else
          reach = shw(s, min(0.95, lv + 0.08)) * range(0.95, 1.15)
          ang = range(38, 58)
        end
        local c, sn = cos(ang), sin(ang) * side
        local dx, dy = tx * c - ty * sn, tx * sn + ty * c
        if not pal then L = reach / sin(ang) * 0.95 end
        local lb = sym(0.25) - side * 0.15
        local function at(t) return lx + dx * L * t - dy * lb * L * t * t, ly + dy * L * t + dx * lb * L * t * t end
        local lp = {}
        for k = 0, 11 do lp[k + 1] = { at(k / 11) } end
        local ln = normals(lp)
        local ll, lr = {}, {}
        for k = 0, 11 do
          local v = k / 11
          local e = 0
          if v > 0.2 then
            local t = (v * 1.4 + ka) * 9
            e = 0.006 * (1 - abs(2 * (t - floor(t)) - 1)) * L * 4
          end
          local g = v > 0 and max(0, sin(180 * v ^ 0.62)) ^ 0.75 or 0
          local wa = max(0, L * range(0.26, 0.3) * wf * g + e)
          local wb = max(0, L * range(0.26, 0.3) * wf * g + e)
          local p, q = lp[k + 1], ln[k + 1]
          ll[k + 1] = { p[1] + q[1] * wa, p[2] + q[2] * wa }
          lr[k + 1] = { p[1] - q[1] * wb, p[2] - q[2] * wb }
        end
        local mx, my = at(0.45)
        local ex, ey = at(0.92)
        veins[#veins + 1] = { lx, ly, mx, my, ex, ey }
        local lo = {}
        for k = 1, 12 do lo[k] = ll[k] end
        for k = 11, 2, -1 do lo[#lo + 1] = lr[k] end
        shapes[#shapes + 1] = lo
        tks[#tks + 1] = 0.8
      end
    end
  end
  local function trace() for i, sh in ipairs(shapes) do smooth(sh, true, tks[i]) end end
  trace() fill(tone(lt), 1)
  if lod == 0 then return end
  trace() ink.clip()
  -- the darker half
  local sd = chance(0.5) and 1 or -1
  for k = 0, 30 do
    local x, y = spine(k / 30)
    if k == 0 then moveto(x, y) else lineto(x, y) end
  end
  lineto(sd * 2, 1) lineto(sd * 2, -0.3) lineto(0, -0.3) close()
  fill(tone(0.12), 0.28, true)
  if lod == 2 then
    if fine then mottle(-s.W * 2.5, -0.2, s.W * 2.5, 1, 13, 0.11, lt - 0.2, lt + 0.22, 12, true)
    else mottle(-s.W * 2.5, -0.2, s.W * 2.5, 1, 6, 0.11, lt - 0.2, lt + 0.22, 0, true) end
  end
  trace() stroke(tone(0.06), 1.3 * u, 0.22, true)
  -- midrib and veins in white
  local mid = {}
  for k = 0, 10 do mid[k + 1] = { spine(k / 10) } end
  streak(mid, 0.03, 0.003, WHITE, 0.78)
  for _, v in ipairs(veins) do
    local op = range(0.5, 0.75)
    taper(v[1], v[2], v[3], v[4], v[3] + (v[5] - v[3]) * 0.5, v[4] + (v[6] - v[4]) * 0.5, v[5], v[6], 0.017, 0.002)
    fill(WHITE, op)
  end
  -- veins: pinnate, arcuate (curving up toward the tip) or palmate (two each side from the base)
  if #veins == 0 and lod == 2 then
    local vn = S.venation
    local ka0, arc = 1, vn == "arcuate"
    if vn == "palmate" then
      ka0 = 5
      local lx, ly = spine(0.03)
      local tx, ty = tangent(0.03)
      for kc = 0, 3 do
        local side = kc < 2 and -1 or 1
        local t, bl = 32, 1.5
        if kc % 2 == 1 then t, bl = 64, 1.1 end
        local ang = range(t - 5, t + 5)
        local c, sn = cos(ang), sin(ang) * side
        local dx, dy = tx * c - ty * sn, tx * sn + ty * c
        local L = s.W * bl * range(0.85, 1)
        local op = range(0.45, 0.7)
        taper(lx, ly, lx + dx * L * 0.4, ly + dy * L * 0.4, lx + dx * L * 0.75 + tx * L * 0.25, ly + dy * L * 0.75 + ty * L * 0.25,
          lx + dx * L * 0.9 + tx * L * 0.6, ly + dy * L * 0.9 + ty * L * 0.6, 0.016, 0.002)
        fill(WHITE, op)
      end
    end
    for ka = ka0, 9 do
      local v = (ka - 0.3) / 10 * 0.9
      local sg = ka % 2 == 1 and -1 or 1
      local lx, ly = spine(v)
      local tx, ty = tangent(v)
      local nx, ny = -ty * sg, tx * sg
      local L = shw(s, v) * bodyw * range(0.75, 0.95)
      local a, b, c, d, e, f
      if arc then
        a, b = lx + nx * L * 0.3 + tx * L * 0.12, ly + ny * L * 0.3 + ty * L * 0.12
        c, d = lx + nx * L * 0.62 + tx * L * 0.55, ly + ny * L * 0.62 + ty * L * 0.55
        e, f = lx + nx * L * 0.72 + tx * L * 1.15, ly + ny * L * 0.72 + ty * L * 1.15
      else
        a, b = lx + nx * L * 0.4, ly + ny * L * 0.4
        c, d = lx + nx * L * 0.75 + tx * L * 0.3, ly + ny * L * 0.75 + ty * L * 0.3
        e, f = lx + nx * L * 0.95 + tx * L * 0.6, ly + ny * L * 0.95 + ty * L * 0.6
      end
      local op = range(0.45, 0.7)
      taper(lx, ly, a, b, c, d, e, f, 0.014, 0.002) fill(WHITE, op)
    end
  end
  ink.unclip()
  if ent then smooth(outline, true, m.tk) stroke(tone(0.05), 0.18, 0.4, false) end
  -- the curl's underside: the blade from just past its middle to the tip, paler
  if hk and hth > 95 then
    local hva = hv + 0.45 * hl
    local ka = 0
    for i = 1, mn do if ka == 0 and ms[i][1] > hva then ka = i end end
    if ka > 1 and ka < mn then
      local under = {}
      for i = ka, mn do under[#under + 1] = left[i] end
      for i = mn - 1, ka, -1 do under[#under + 1] = right[i] end
      smooth(under, true, m.tk) fill(tone(min(0.64, lt + 0.26)), 1)
      smooth(under, true, m.tk) ink.clip()
      local sp = {}
      for k = 0, 10 do sp[k + 1] = { spine(hva + (1 - hva) * k / 10) } end
      streak(sp, 0.02, 0.003, WHITE, 0.6)
      smooth(under, true, m.tk) stroke(tone(0.06), 1.3 * u, 0.3, true)
      ink.unclip()
    end
  end
end
-- \flo@sleaf: stipules, a petiolate leaf's stalk, then the blade. o: bend, lobes, depth, u
local function sleaf(o)
  local s = sshape(false)
  local lsc = min(1, 0.3 / s.W)
  if S.leafmargin == "palmatelobed" then lsc = min(1, 0.3 / max(s.W, 0.55)) end
  local u = o.u
  ink.push()
  if lsc < 1 then ink.scale(lsc) u = u * lsc end
  if S.stipules ~= "none" and u > K(0.8) then
    for kc = 0, 1 do
      local t = range(40, 65)
      if kc == 1 then t = -t end
      local ts = range(0.1, 0.15)
      ink.push() ink.translate(0, 0.01) ink.rotate(t) ink.scale(ts)
      M.leaflet({ W = 0.3, tone = 0.3, u = u * ts })
      ink.pop()
    end
  end
  local lpf = S.attachment == "petiolate" and range(0.1, 0.2) or 0
  if lpf > 0 then
    local c = tone(0.16)
    taper(0, 0, 0, lpf / 3, 0, 2 * lpf / 3, 0, lpf + 0.01, 0.024, 0.014) fill(c, 1)
  end
  ink.push()
  if lpf > 0 then ink.translate(0, lpf) ink.scale(1 - lpf) u = u * (1 - lpf) end
  sblade(s, { bend = o.bend, lobes = o.lobes, depth = o.depth, u = u })
  ink.pop()
  ink.pop()
end
-- \flo@sleaflet: a leaflet in the species' hand, no stalk or stipules, two or three lobes a
-- side; +y, length 1; lt its tone, u its length on the page in cm
local LOBED = { lobed = true, pinnatifid = true, palmatelobed = true }
local function sleaflet(lt, u)
  local depth, lobes, over = 0, 3, nil
  local lm = S.leafmargin
  if LOBED[lm] then
    -- under 7 mm, scallops instead of lobes (a pinnatifid leaflet's: deep teeth)
    if u < K(0.7) then over = lm == "pinnatifid" and "dentate" or "crenate"
    else depth, lobes = min(0.85, max(0.3, S.dissection)), floor(max(2, min(3, S.teeth))) end
  end
  local s = sshape(true)
  local lsc = min(1, 0.3 / s.W)
  if lm == "palmatelobed" then lsc = min(1, 0.3 / max(s.W, 0.55)) end
  ink.push()
  if lsc < 1 then ink.scale(lsc) u = u * lsc end
  sblade(s, { tone = lt, depth = depth, lobes = lobes, u = u, leaflet = true, over = over })
  ink.pop()
end

-- ---------------------------------------------------------------- compound leaves
-- the rachis and stalks are stroked with the pen compoundleaf sets: RP.c, RP.w (bp)
local RP = {}
local function rachis(y0, y1) moveto(0, y0) lineto(0, y1) stroke(RP.c, RP.w, 1, false) end
-- a leaflet's length on the page in cm, k of a leaf lpt pt long; for a pic's leaf (RP.pt, its
-- length in sp as TeX holds it) as pgfmath finds it: a 1 cm leaf's leaflets of 0.4 are 4 mm,
-- the threshold of their level of detail, and TeX's product can land either side of it.
-- pgfmath's lpt*k/28.45276 (a negative k, as TeX expands it, takes in the quotient)
function RP.u(lpt, k)
  if RP.pt then
    local a, b = floor(lpt * 65536 + 0.5), floor(k * 65536 + 0.5)
    if b < 0 then return pm.mulf(a, -pm.div(-b, CM)) / 65536 end
    return pm.div(pm.mulf(a, b), CM) / 65536
  end
  return lpt * k / 28.45276
end
-- \flo@pinnate: pairs sized to peak mid-rachis, then a terminal leaflet or a tendril;
-- lpt the leaf's length in pt, n pairs, pl the longest leaflet, lt the tone, tend tendrils
local function pinnate(lpt, n, pl, lt, tend)
  local plw = max(0.035, min(0.6, 0.5 / S.leafaspect))
  local pend, gap, pmax, pterm
  if tend then
    pend, gap = 0.92, 0.68 / max(1, n - 1)
    pmax = min(pl, 0.45 * gap / plw)
  else
    pmax = min(pl, 0.3465 / (max(1, n - 1) * plw + 0.495))
    pterm = min(pl, 1.1 * pmax)
    pend = 1 - pterm
    gap = (pend - 0.23) / max(1, n - 1)
  end
  rachis(0, pend)
  for j = 1, n do
    local v = 0.2 + gap * (j - 1)
    local ll = pmax * (0.72 + 0.28 * sin(180 * (j - 0.5) / n))
    for k = 0, 1 do
      local ang = range(50, 68) - 14 * (j - 1) / n
      local dv = sym(0.015)
      ink.push() ink.translate(0, v + dv) ink.rotate(k == 0 and ang or -ang) ink.scale(ll)
      sleaflet(range(lt - 0.07, lt + 0.07), RP.u(lpt, ll))
      ink.pop()
    end
  end
  if tend then
    local c, w = tone(0.22), 0.25 * 72 / 72.27
    local tn = chance(0.4) and 2 or 1
    for q = 1, tn do
      ink.push() ink.translate(0, pend)
      local t
      if tn == 1 then t = sym(15)
      else
        t = range(10, 30)
        if q == 2 then t = -t end
      end
      ink.rotate(t)
      smooth(vcurl(range(0.35, 0.55)), false) stroke(c, w, 1, false)
      ink.pop()
    end
  else
    ink.push() ink.translate(0, pend) ink.scale(pterm)
    sleaflet(lt, RP.u(lpt, pterm))
    ink.pop()
  end
end
-- \flo@bipinnate: pinnae that are themselves odd-pinnate, and a terminal pinna
local function bipinnate(lpt, lt)
  local bk = floor(min(3, max(2, (S.leaflets + 1) / 3)))
  local bl = floor(min(7, max(3, S.leaflets)))
  lt = lt + 0.06
  rachis(0, 0.7)
  for m = 1, bk do
    local v = 0.16 + 0.44 * (m - 1) / max(1, bk - 1)
    local s = 0.48 * (1 - 0.5 * (m - 1) / bk)
    local n = floor(max(2, bl - m + 1))
    for p = 0, 1 do
      local ang = range(48, 64) - 12 * (m - 1) / bk
      ink.push() ink.translate(0, v) ink.rotate(p == 0 and ang or -ang) ink.scale(s)
      pinnate(lpt * s, n, 0.4, lt, false)
      ink.pop()
    end
  end
  ink.push() ink.translate(0, 0.66) ink.scale(0.34)
  pinnate(lpt * 0.34, floor(max(2, bl - bk)), 0.4, lt, false)
  ink.pop()
end
-- \flo@palmate: leaflets from a petiole's tip, the center one the largest, from the outside in
local function palmate(lpt, n, lt)
  local pp = range(0.3, 0.38)
  rachis(0, pp)
  local hs = min(135, 20 * n - 10)
  for q = 1, n do
    local j = q % 2 == 1 and (q + 1) // 2 or n + 1 - q // 2
    local f = (j - (n + 1) / 2) / max(1, (n - 1) / 2)
    local ang = -f * hs + sym(6)
    local ll = (1 - pp) * (1 - 0.45 * f * f)
    ink.push() ink.translate(0, pp) ink.rotate(ang) ink.scale(ll)
    sleaflet(range(lt - 0.06, lt + 0.06), lpt * ll / 28.45276)
    ink.pop()
  end
end
-- \flo@trifoliate: two side leaflets and a larger end one on a short stalk
local function trifoliate(lpt, lt)
  local pp, ps = range(0.3, 0.4), range(0, 0.1)
  rachis(0, pp + ps)
  for n = 0, 2 do
    local ang, ll, pv
    if n < 2 then
      ang = range(48, 68)
      if n == 1 then ang = -ang end
      ll, pv = 0.8 * (1 - pp), pp
    else ang, ll, pv = 0, 1 - pp - ps, pp + ps end
    ink.push() ink.translate(0, pv) ink.rotate(ang) ink.scale(ll)
    sleaflet(range(lt - 0.06, lt + 0.06), lpt * ll / 28.45276)
    ink.pop()
  end
end
-- the compound branch of \flo@leaf: stipules, the pen for rachis and stalks, the leaf
local function compoundleaf(lpt)
  local lt = range(0.24, 0.4)
  if S.stipules ~= "none" then
    local a, b, W = 0.05, 0.08, 0.3
    if S.stipules == "leafy" then a, b, W = 0.1, 0.16, 0.36 end
    for kc = 0, 1 do
      local t = range(55, 80)
      if kc == 1 then t = -t end
      local ts = range(a, b)
      ink.push() ink.translate(0, 0.01) ink.rotate(t) ink.scale(ts)
      M.leaflet({ W = W, tone = 0.3, u = lpt * ts / 28.45276 })
      ink.pop()
    end
  end
  RP.c, RP.w = tone(0.07), max(0.25, 0.006 * lpt)
  local cp = S.compound
  if cp == "pinnate" then pinnate(lpt, floor(min(7, S.leaflets)), 0.4, lt, S.tendrils == 1) end
  if cp == "bipinnate" then bipinnate(lpt, lt) end
  if cp == "palmate" then palmate(lpt, S.leaflets, lt) end
  if cp == "trifoliate" then trifoliate(lpt, lt) end
end

-- ================================================================ M8f5: ferns
-- the rachis (\flo@feribbon) is drawn by ribbon, above
-- the frond's outline (\flo@feol@): bm the widest pinna's place, lo the foot, kx the tip's
-- exponent, wr the longest pinna; the pinna's tip (\flo@feap@); its teeth (\flo@fem@)
local FOL = { lanceolate = { 0.3, 0.45, 0.8, 0.26 }, oblong = { 0.12, 0.7, 0.35, 0.2 },
  ovate = { 0.2, 0.75, 0.9, 0.32 }, deltoid = { 0.04, 0.9, 1.3, 0.42 } }
local FAP = { acute = { 1.6, 0.9 }, obtuse = { 3, 0.6 }, rounded = { 5, 0.45 } }
local FMG = { entire = 0, crenate = 0.2, serrate = 0.26 }
-- the shape's left half, its first n segments, then back down the midrib (\flo@fehalf)
local function fehalf(pts, n, fb, tk)
  local k = (tk or 1) / 6
  local m = #pts
  local function at(i) return pts[(i - 1) % m + 1] end
  moveto(pts[1][1], pts[1][2])
  for i = 1, n do
    local p0, p1, p2, p3 = at(i - 1), at(i), at(i + 1), at(i + 2)
    curveto(p1[1] + (p2[1] - p0[1]) * k, p1[2] + (p2[2] - p0[2]) * k, p2[1] - (p3[1] - p1[1]) * k, p2[2] - (p3[2] - p1[2]) * k,
      p2[1], p2[2])
  end
  for i = 1, 8 do local v = 1 - i / 8 lineto(fb * v * v, v) end
  close()
end
-- the frond being drawn: its pinna's numbers (\flo@fe...); FE.tex while a pic draws (M.pic)
local FE = {}
-- where along the frond its pinnae stand, and how wide each may be, come from pow(x, 0.85),
-- the width from the difference of two of them. pgfmath's pow is good to about 1e-4, and in
-- that difference its error grows fifty times, so a pinna drawn from doubles would be up to
-- 1% wider or narrower than the library's (0.6 bp on a large frond). These two use
-- pgfmath's own pow; everything else is a double. A pic's frond (FE.tex), 10 cm long where
-- the margin's is 4, also takes its spine's 32 steps as TeX truncates them (32 sp short at
-- the tip, 0.2 bp) and its pinnae's lengths from pgfmath's pow (2% off at some numbers)
local function ppow(x, y) return pm.pow(floor(x * 65536 + 0.5), floor(y * 65536 + 0.5)) / 65536 end
-- \flo@fesori: sori under a pinna (its outline pts)
local function fesori(pts)
  local c, sr = accent(-0.35), S.sori
  if sr == "marginal" then smooth(pts, true) stroke(c, min(0.5, 0.3 * FE.pcm), 0.75, false) end
  if sr == "dots" then
    local n = floor(min(7, 2 + 4 * FE.pcm))
    for k = 1, n do
      local v = 0.14 + 0.66 * (k - 1) / max(1, n - 1)
      local x, w, r = FE.fb * v * v, 0.5 * FE.W * (1 - 0.5 * v), 0.3 * FE.W * (1 - 0.4 * v)
      circle(x - w, v, r) circle(x + w, v, r)
    end
    fill(c, 0.9)
  end
  if sr == "lines" then
    local n = floor(min(6, 2 + 3 * FE.pcm))
    for k = 1, n do
      local v = 0.12 + 0.62 * (k - 1) / max(1, n - 1)
      local x, w = FE.fb * v * v, 0.7 * FE.W * (1 - 0.5 * v)
      moveto(x - 0.15 * w, v) lineto(x - w, v + 0.6 * w) moveto(x + 0.15 * w, v) lineto(x + w, v + 0.6 * w)
    end
    stroke(c, 0.45, 0.85, false)
  end
end
-- \flo@fepinna: a pinna along +y, length 1, FE.W its half-width
local function fepinna()
  FE.fb = range(0.05, 0.16)
  local t = FE.tone + sym(0.03)
  local n, tk = 10, 0
  if FE.pcm < 0.3 then n = 6 end
  if FE.pcm > 0.6 and FE.td > 0 then tk, n = FE.td, 2 * floor(min(9, 3 + 4 * FE.pcm)) end
  local cs = 0
  if tk > 0 and S.leafmargin == "serrate" then cs = 0.35 / n end
  local spine = {}
  for k = 0, n do
    local v = k / n
    if k % 2 == 1 and k < n then v = v + cs end
    spine[k + 1] = { FE.fb * v * v, v }
  end
  local pts = blade(spine, function(i)
    local v = spine[i][2]
    if v > 0 and v < 1 then
      local w = FE.W * min(1, v / 0.12) ^ 0.45 * max(0.0001, 1 - v ^ FE.kp) ^ FE.kq * (1 - FE.nar * v)
      if (i - 1) % 2 == 0 then w = w * (1 - tk) end
      return w
    end
    return 0
  end)
  smooth(pts, true) fill(tone(t), 1)
  if FE.pcm > 0.2 then fehalf(pts, n, FE.fb) fill(tone(0.08), 0.28, true) end
  if FE.pcm > 0.35 then
    taper(0, 0, 0, 0.2733, FE.fb * 0.82 * 0.82 / 3, 0.5467, FE.fb * 0.82 * 0.82, 0.82, 0.03, 0.004) fill(WHITE, 0.6)
  end
  if FE.under and FE.pcm > 0.35 then fesori(pts) end
end
-- \flo@fecomb: a pinna cut into pinnules, along +y, length 1
local function fecomb()
  FE.fb = range(0.04, 0.12)
  local fb = FE.fb
  local t = FE.tone + sym(0.03)
  local n = floor(max(3, min(9, FE.pcm / 0.15)))
  local d = 0.9 / n
  local s = 0.35 * d
  local L = { { 0, 0 } }                         -- the left side, up to the tip
  local function cpt(x, v) L[#L + 1] = { fb * v * v - x, v } end
  for k = 1, n do
    local v = 0.05 + d * (k - 0.5)
    local l = FE.W * (1 - 0.72 * v ^ 1.5) * range(0.9, 1.06)
    if FE.div > 2 then
      cpt(0.12 * FE.W, v - 0.5 * d) cpt(0.5 * l, v - 0.4 * d + 0.3 * s)
      cpt(0.62 * l, v - 0.2 * d + 0.55 * s) cpt(l, v + s)
      cpt(0.66 * l, v + 0.24 * d + 0.7 * s) cpt(0.52 * l, v + 0.38 * d + 0.5 * s)
    else
      cpt(0.12 * FE.W, v - 0.5 * d) cpt(0.58 * l, v - 0.36 * d + 0.5 * s)
      cpt(l, v + s) cpt(0.62 * l, v + 0.36 * d + 0.6 * s)
    end
  end
  local h = #L
  local pts = {}
  for i = 1, h do pts[i] = L[i] end
  pts[h + 1] = { fb, 1 }
  for k = 2, h do                                -- the right side, mirrored across the midrib
    local p = L[h + 2 - k]
    pts[h + k] = { 2 * fb * p[2] * p[2] - p[1], p[2] }
  end
  smooth(pts, true) fill(tone(t), 1)
  fehalf(pts, h, fb) fill(tone(0.08), 0.28, true)
  taper(0, 0, 0, 0.3, fb * 0.9 * 0.9 / 3, 0.6, fb * 0.9 * 0.9, 0.9, 0.025, 0.004) fill(WHITE, 0.55)
  if FE.under then
    local c, sr = accent(-0.35), S.sori
    if sr == "marginal" then smooth(pts, true) stroke(c, min(0.4, 0.22 * FE.pcm), 0.75, false)
    else
      for k = 1, n do
        local v = 0.05 + d * (k - 0.5)
        local l = FE.W * (1 - 0.72 * v ^ 1.5)
        local ya = v + 0.35 * s
        local x = fb * ya * ya
        if sr == "dots" then
          local r = 0.16 * min(d, l)
          circle(x - 0.45 * l, ya, r) circle(x + 0.45 * l, ya, r)
        elseif sr == "lines" then
          local yb = ya + 0.6 * s
          moveto(x - 0.45 * l, ya) lineto(x - 0.7 * l, yb) moveto(x + 0.45 * l, ya) lineto(x + 0.7 * l, yb)
        end
      end
      if sr == "dots" then fill(c, 0.9) elseif sr == "lines" then stroke(c, 0.45, 0.85, false) else ink.discard() end
    end
  end
end
-- \flo@febeads: a fertile pinna, a row of beads along +y, length 1
local function febeads()
  local fb = range(0.02, 0.08)
  local n = floor(max(2, min(7, 2 + 5 * FE.pcm)))
  local c = tone(0.12)
  moveto(0, 0) curveto(0, 0.3, fb * 0.9 * 0.9 / 3, 0.6, fb * 0.9 * 0.9, 0.9) stroke(c, 0.3, 0.8, false)
  local beads = {}
  for k = 1, n do
    local v = 0.95 * (k - 0.3) / n
    beads[k] = { fb * v * v, v, 0.6 / n * (1 - 0.4 * v) * range(0.85, 1.1) }
  end
  for _, b in ipairs(beads) do circle(b[1], b[2], b[3]) end
  fill(tone(0.32 + sym(0.04)), 1)
  for _, b in ipairs(beads) do circle(b[1], b[2], b[3]) end
  stroke(tone(0.08), 0.25, 0.45, true)
end
-- \flo@frond: a fern's frond along +y, length 1; cm its length on the page. o: unroll (0..1),
-- arch (degrees; nil draws one), fertile, under (its underside shown)
function M.frond(cm, o)
  local arch = o.arch
  if arch == nil then arch = sym(1) * (20 + 70 * S.curl) end
  local un = o.unroll
  if un >= K(0.97) then un = 1 end
  local was = pen.accent
  if o.fertile then pen.accent = true end
  local st, np, div = S.stipe, S.pinnae, S.division
  local ol, ap = FOL[S.outline], FAP[S.leafapex]
  FE.td, FE.kp, FE.kq, FE.div = FMG[S.leafmargin], ap[1], ap[2], div
  FE.nar = S.leafshape == "lanceolate" and 0.3 or 0
  FE.under = o.under
  local fo = st + (1 - st) * (un < 1 and 0.3 + 0.7 * un or 1)
  -- the spine, arching; then, unrolling, the crozier
  local P = { { 0, 0 } }
  local x, y = 0, 0
  for k = 1, 32 do
    local a = 90 + arch * (fo * (k - 0.5) / 32) ^ 1.5
    if FE.tex then                               -- a pic's frond: each step as TeX truncates it
      local step = floor(floor(fo * 65536 + 0.5) / 32)
      local dx, dy = step * cos(a), step * sin(a)
      x = x + (dx < 0 and -floor(-dx) or floor(dx)) / 65536
      y = y + (dy < 0 and -floor(-dy) or floor(dy)) / 65536
    else x, y = x + fo / 32 * cos(a), y + fo / 32 * sin(a) end
    P[k + 1] = { x, y }
  end
  local sg, cr = 1, 0
  if un < 1 then
    if arch < 0 then sg = -1 end
    local cT = 100 + 440 * (1 - un)
    cr = 0.65 * (1 - fo) / (cT * 0.0174533 * 0.541)
    local a = 90 + arch * fo ^ 1.5
    for k = 1, 24 do
      a = a + sg * cT / 24
      local t = cr * 0.25 ^ ((k - 0.5) / 24) * cT / 24 * 0.0174533
      x, y = x + t * cos(a), y + t * sin(a)
      P[k + 33] = { x, y }
    end
  end
  local function at(t)                           -- where a pinna leaves the rachis
    local i = floor(t)
    local f = t - i
    local a, b = P[i + 1], P[i + 2]
    return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f
  end
  local pm_ = (1 - st) * ol[4] * range(0.9, 1.1)
  if o.fertile then pm_ = 0.45 * pm_ end
  FE.tone = range(0.24, 0.34)
  if o.under then FE.tone = FE.tone + 0.14 end
  for g = 1, np do
    for e = 0, 1 do
      local b = 0.93 * ppow((g - 0.5 + 0.42 * e) / np, 0.85)
      local s = st + (1 - st) * b
      local ee
      if b < ol[1] then ee = ol[2] + (1 - ol[2]) * sin(90 * b / ol[1])
      else
        ee = max(0.0001, cos(90 * (b - ol[1]) / (1 - ol[1])))
        if FE.tex then ee = ppow(ee, ol[3]) else ee = ee ^ ol[3] end
      end
      if un < 1 then ee = ee * max(0, min(1, 0.3 + 0.7 * (fo - s) / 0.15)) end
      local l = pm_ * ee * range(0.92, 1.06)
      local al = 70 - 30 * b + sym(4)
      FE.pcm = l * cm
      if s < fo - 0.004 and FE.pcm > 0.08 then
        local t = 0.93 * (1 - st) * (ppow((g + 0.5) / np, 0.85) - ppow((g - 0.5) / np, 0.85))
        FE.W = min(0.22, 0.34 * t * sin(al) / l)
        local px, py = at(s / fo * 32)
        local a = 90 + arch * s ^ 1.5
        ink.push() ink.translate(px, py)
        ink.rotate(e == 0 and a + al - 90 or a - al - 90)
        if e == 1 then xscale(-1) end
        ink.scale(l)
        if o.fertile then febeads()
        elseif div > 1 then if FE.pcm > 0.45 then fecomb() else fepinna() end
        else fepinna() end
        ink.pop()
      end
    end
  end
  if un >= 1 and not o.fertile then              -- the pinna-like tip
    local s, l = st + 0.91 * (1 - st), 0.1 * (1 - st)
    local px, py = at(s * 32)
    local a = 90 + arch * s ^ 1.5
    FE.W, FE.pcm = 0.13, l * cm
    ink.push() ink.translate(px, py) ink.rotate(a - 90) ink.scale(l) fepinna() ink.pop()
  end
  local spine = {}
  for k = 1, 33 do spine[k] = P[k] end
  ribbon(spine, 0.012, 0.0025 + 0.006 * (1 - un), tone(0.1))
  if S.hairy == 1 then                           -- scales on the stipe
    for k = 2, 32 do
      if fo * (k - 1) / 32 < 0.9 * st and k % 2 == 0 then
        local dx, dy = P[k + 1][1] - P[k][1], P[k + 1][2] - P[k][2]
        local nx, ny = nrm(dx, dy)
        local t = k % 4 == 0 and 1 or -1
        local ts = range(0.012, 0.02)
        local xa, ya = P[k][1] + t * nx * 0.005, P[k][2] + t * ny * 0.005
        moveto(xa, ya) lineto(xa + t * nx * ts + dx * 12 * ts, ya + t * ny * ts + dy * 12 * ts)
      end
    end
    stroke(accent(-0.3), 0.35, 0.85, false)
  end
  if un < 1 then                                 -- the crozier: ribbon, scalloped lobes, a pale line
    local c = {}
    for k = 1, 25 do c[k] = P[k + 32] end
    local nr = normals(c)
    local lobes = {}
    for k = 2, 24 do
      local r = cr * 0.25 ^ ((k - 1) / 24)
      lobes[#lobes + 1] = { c[k][1] - sg * nr[k][1] * 0.33 * r, c[k][2] - sg * nr[k][2] * 0.33 * r, (k % 2 == 1 and 0.15 or 0.21) * r }
    end
    ribbon(c, 0.56 * cr, 0.16 * cr, tone(0.27))
    for _, b in ipairs(lobes) do circle(b[1], b[2], b[3]) end
    fill(tone(0.2), 1)
    for _, b in ipairs(lobes) do circle(b[1], b[2], b[3]) end
    stroke(tone(0.06), 0.25, 0.35, true)
    local pale = {}
    for k = 1, 22 do pale[k] = P[k + 32] end
    streak(pale, 0.14 * cr, 0.002, WHITE, 0.5)
  end
  pen.accent = was
end

-- ---------------------------------------------------------------- the leaf
-- the leaf's size on the page in cm (\flo@vl@u) as TeX finds it: its length (cm, held in sp)
-- times 28.45276 and divided back, both in pgfmath, which can lose a scaled point. Only this
-- one number is TeX's own: it decides a leaf's teeth and detail, and the layout gives some
-- leaves round lengths (19/16 cm) that sit exactly on those thresholds
local function leafu(len)
  return pm.div(pm.mulf(floor(len * 65536 + 0.5), CM), CM) / 65536    -- (len*28.45276)/28.45276
end
-- \flo@leaf: the species' leaf along +y, length 1; len its length in cm, bend its bend, from a
-- sheath's top where it has one (sheath: its direction from the leaf's, degrees, and width);
-- pt, the pic's: the length in pt (sp) instead, as \flo@leaf takes it there
function M.leaf(len, bend, sheath, pt)
  if sheath and S.attachment == "sheathing" then
    local l = range(0.14, 0.22)
    local x, y = -l * sin(sheath[1]), l * cos(sheath[1])
    local w = sheath[2]
    taper(0, 0, x / 3, y / 3, 2 * x / 3, 2 * y / 3, x, y, w, 0.8 * w) fill(tone(0.34), 1)
    taper(0, 0, x / 3, y / 3, 2 * x / 3, 2 * y / 3, x, y, w, 0.8 * w) stroke(tone(0.08), 0.2, 0.6, false)
    ink.push() ink.translate(x, y) M.leaf(len, bend, nil, pt) ink.pop()
    return
  end
  local u, lpt
  if pt then u, lpt = pm.div(pt, CM) / 65536, pt / 65536 else u, lpt = leafu(len), len * 28.45276 end
  local cp = S.compound
  if cp == "simple" then
    if S.venation == "parallel" then strap(max(0.025, min(0.12, 0.42 / S.leafaspect)), bend, u)
    else
      local depth, lobes = 0, 3
      if LOBED[S.leafmargin] then depth, lobes = min(0.85, max(0.3, S.dissection)), floor(max(2, min(6, S.teeth))) end
      sleaf({ bend = bend, lobes = lobes, depth = depth, u = u })
    end
  elseif cp == "frond" then
    M.frond(u, { unroll = 1, fertile = false, under = false })
  else
    RP.pt = pt
    compoundleaf(lpt)
    RP.pt = nil
  end
end

-- ================================================================ M8f5: visitors
-- The animals that come to the plants (\florilegiumvisitor, \flo@visitor): butterflies and
-- moths, bees and hoverflies, dragonflies and damselflies, beetles and ladybirds, a
-- caterpillar on its leaf, a snail, a bird. Their helpers sit in a function of their own,
-- whose locals count afresh (the main chunk is near Lua's limit of 200).
local visitor = (function()
  local species = require("florilegium-species")
  local X                                   -- the visitor's traits as TeX holds them (\flo@x@<trait>)
  local fine = false                        -- \flo@fine: large enough on the page for detail
  -- a tone from the ink's ramp, on a copper visitor too; white() is \flo@bgwhite's paint
  local function plain(t)
    local was = pen.accent
    pen.accent = false
    local c = tone(t)
    pen.accent = was
    return c
  end
  local function white() return plain(0.93) end
  -- \flo@lgseg: a straight tapered stroke from (x0, y0) to (x1, y1), widths wa to wb
  local function seg(x0, y0, x1, y1, wa, wb)
    local dx, dy = x1 - x0, y1 - y0
    taper(x0, y0, x0 + dx / 3, y0 + dy / 3, x0 + dx * 2 / 3, y0 + dy * 2 / 3, x1, y1, wa, wb)
  end
  -- \flo@bgell: an ellipse along the axes
  local function ell(cx, cy, rx, ry) ellipse(cx, cy, rx, 0, 0, ry) end
  -- \flo@bgband: a band across from y hi down to lo, its middle bowed toward the tail
  local function band(hi, lo, bow)
    local ya, yb = hi - bow, lo - bow
    moveto(-0.5, hi) curveto(-0.17, ya, 0.17, ya, 0.5, hi)
    lineto(0.5, lo) curveto(0.17, yb, -0.17, yb, -0.5, lo) close()
  end
  -- \flo@vlegs: the legs of a side, drawn to the right, from table t (per leg its root, knee,
  -- foot and the end of its tarsus), in color c; LGP holds \flo@lg...: the scale x, the
  -- height y, ex out from the middle, the jitter j, ph the feet raised (the middle pair
  -- lowered), the width w
  local LG = {
    o = { { 0.025, 0.03, 0.06, 0.06, 0.07, 0.11, 0.065, 0.15 }, { 0.03, 0, 0.075, 0.02, 0.095, 0.07, 0.095, 0.1 },
      { 0.03, -0.03, 0.085, -0.03, 0.11, 0.01, 0.115, 0.045 } },
    b = { { 0.06, 0.08, -0.06, 0.13, 0.02, 0.27, 0.04, 0.34 }, { 0.08, -0.04, 0, -0.02, 0.1, -0.1, 0.15, -0.14 },
      { 0.08, -0.12, -0.02, -0.24, 0.06, -0.42, 0.08, -0.5 } },
  }
  local LGP = {}
  local function vlegs(t, c)
    local x, y, ex, j = LGP.x, LGP.y, LGP.ex, LGP.j
    local legs = {}
    for i = 1, 3 do
      local p = LG[t][i]
      local lift = i == 2 and -LGP.ph or LGP.ph
      local kx = p[3] * x + ex + sym(j)
      local ky = y + p[4] * x + sym(j)
      local fx = p[5] * x + ex + sym(j)
      local fy = y + p[6] * x + lift + sym(j)
      legs[i] = { p[1] * x, y + p[2] * x, kx, ky, fx, fy, fx + (p[7] - p[5]) * x, fy + (p[8] - p[6]) * x }
    end
    local w = LGP.w
    for i = 1, 3 do
      local q = legs[i]
      seg(q[1], q[2], q[3], q[4], w, w * 0.8)
      seg(q[3], q[4], q[5], q[6], w * 0.75, w * 0.45)
      seg(q[5], q[6], q[7], q[8], w * 0.4, w * 0.2)
    end
    fill(c, 1)
  end

  -- ---------------------------------------------------------------- butterflies and moths
  local WG = {}                             -- the one being drawn (\flo@wg...)
  -- the wings' points, forewing and hindwing; an apex other than a rounded one moves some
  local WSHAPE = {
    fw = { { 0.05, 0.1 }, { 0.3, 0.45 }, { 0.65, 0.68 }, { 0.92, 0.66 }, { 1, 0.5 }, { 0.88, 0.25 }, { 0.55, 0.05 },
      { 0.15, -0.02 } },
    hw = { { 0.06, -0.02 }, { 0.45, -0.02 }, { 0.72, -0.22 }, { 0.7, -0.5 }, { 0.5, -0.72 }, { 0.25, -0.7 }, { 0.08, -0.35 } },
  }
  local APEX = {
    rounded = {},
    angular = { { "fw", 3, 0.66, 0.7 }, { "fw", 4, 1, 0.72 }, { "fw", 5, 0.98, 0.52 } },
    falcate = { { "fw", 3, 0.66, 0.72 }, { "fw", 4, 1.04, 0.78 }, { "fw", 5, 0.9, 0.55 } },
    pointed = { { "fw", 1, 0.05, 0.08 }, { "fw", 2, 0.35, 0.36 }, { "fw", 3, 0.72, 0.42 }, { "fw", 4, 1, 0.38 },
      { "fw", 5, 0.97, 0.28 }, { "fw", 6, 0.7, 0.16 }, { "fw", 7, 0.38, 0.04 }, { "fw", 8, 0.12, -0.02 },
      { "hw", 2, 0.4, -0.02 }, { "hw", 3, 0.55, -0.12 }, { "hw", 4, 0.52, -0.28 }, { "hw", 5, 0.38, -0.38 },
      { "hw", 6, 0.2, -0.36 }, { "hw", 7, 0.07, -0.2 } },
  }
  -- \flo@wgshape, \flo@wgjit: the wings' points, each moved a little
  local function wgshape()
    for _, w in ipairs({ "fw", "hw" }) do
      local t = {}
      for i, p in ipairs(WSHAPE[w]) do t[i] = { p[1], p[2] } end
      WG[w] = t
    end
    for _, p in ipairs(APEX[X.apex] or APEX.rounded) do WG[p[1]][p[2]] = { p[3], p[4] } end
    for _, w in ipairs({ "fw", "hw" }) do
      for _, p in ipairs(WG[w]) do
        p[1] = p[1] + sym(0.03)
        p[2] = p[2] + sym(0.03)
      end
    end
  end
  local TAIL = { { -0.05, -0.04 }, { -0.06, -0.19 }, { -0.1, -0.25 }, { -0.15, -0.2 }, { -0.13, -0.04 } }
  -- \flo@wgoutline: a wing's outline through its n points, a swallowtail's tail after point
  -- WG.tail, the edge between points m0 and m1 scalloped by WG.dep
  local function wgoutline(w, n, m0, m1)
    local p, pts = WG[w], {}
    for a = 1, n do
      pts[#pts + 1] = { p[a][1], p[a][2] }
      if WG.tail == a then
        local hx, hy = WG.hw[5][1], WG.hw[5][2]
        for _, q in ipairs(TAIL) do pts[#pts + 1] = { hx + q[1], hy + q[2] } end
      end
      if WG.dep > 0 and a < m1 and a > m0 - 1 then
        local b = a + 1
        for j = 1, 3 do
          local t = j / 4
          local x, y = p[a][1] + (p[b][1] - p[a][1]) * t, p[a][2] + (p[b][2] - p[a][2]) * t
          if j % 2 == 1 then x, y = x * (1 - WG.dep), y * (1 - WG.dep) end
          pts[#pts + 1] = { x, y }
        end
      end
    end
    return pts
  end
  -- \flo@wgat: the point a fraction s along the edge from point m0 to m1, drawn in by f
  local function wgat(w, m0, m1, s, f)
    local m = m1 - m0
    local q = s * m
    local k = min(m - 1, floor(q))
    local r = q - k
    local a, b = WG[w][m0 + k], WG[w][m0 + k + 1]
    return (a[1] + (b[1] - a[1]) * r) * f, (a[2] + (b[2] - a[2]) * r) * f
  end
  -- \flo@wgeye: an eyespot at (x, y), radius r: its rings, pupil and the arcs outside it
  local function wgeye(x, y, r)
    circle(x, y, r) fill(tone(0.08), 0.85)
    if X.rings > 1 then circle(x, y, r * 0.68) fill(WHITE, 0.85) end
    circle(x, y, r * (X.rings > 2 and 0.46 or 0.34)) fill(accent(0), 1)
    if X.rings > 2 then
      circle(x, y, r * 0.22) fill(tone(0.06), 1)
      circle(x + r * 0.1, y + r * 0.1, r * 0.08) fill(WHITE, 0.9)
    end
    if X.parafocal == 1 then
      local a, wr = atan2(y, x), r * 1.5
      taper(x + wr * cos(a - 55), y + wr * sin(a - 55), x + wr * 1.15 * cos(a - 20), y + wr * 1.15 * sin(a - 20),
        x + wr * 1.15 * cos(a + 20), y + wr * 1.15 * sin(a + 20), x + wr * cos(a + 55), y + wr * sin(a + 55), r * 0.22, r * 0.22)
      fill(tone(0.08), 0.6, true)
    end
  end
  local BASE = { fw = { 0.12, 0.12 }, hw = { 0.12, -0.12 } }
  local ROOTY, SPOTR = { fw = 0.04, hw = -0.04 }, { fw = 0.03, hw = 0.034 }
  -- \flo@wgpaint: a wing (w: fw or hw, its n points, its edge's spots from point m0 to m1):
  -- the ground, then in its clip the groundplan's pattern systems and the veins
  local function wgpaint(w, n, m0, m1)
    local o, t, cj, cw = WG["o" .. w], WG.t, WG.cj, WG.cw
    smooth(o, true) fill(tone(t), WG.op)
    if WG.blur then return end
    smooth(o, true) ink.clip()
    if fine then mottle(-1.2, -1.2, 1.2, 1.2, 9, 0.14, t - 0.2, t + 0.2, 8)
    else mottle(-1.2, -1.2, 1.2, 1.2, 4, 0.14, t - 0.2, t + 0.2, 0) end
    if X.basal == 1 then
      local b = blob(BASE[w][1], BASE[w][2], 0.2, 0.15, 0.3, 9)
      smooth(b, true) fill(tone(t - 0.18), 0.45, true)
    end
    if X.central == "band" then
      if w == "fw" then taper(0.5, 0.66, 0.47 + cj, 0.45, 0.42 + cj, 0.25, 0.36, 0.04, cw, cw * 0.8)
      else taper(0.42, -0.02, 0.37 + cj, -0.2, 0.28 + cj, -0.38, 0.14, -0.55, cw, cw * 0.8) end
      fill(tone(t - 0.2), 0.6, true)
    end
    if X.central == "spots" then
      local xa, xb, ya, yb
      if w == "fw" then xa, xb, ya, yb = 0.47 + cj, 0.42 + cj, 0.45, 0.25 else xa, xb, ya, yb = 0.37 + cj, 0.28 + cj, -0.2, -0.38 end
      circle(xa, ya, 0.045) circle(xb, yb, 0.045) circle((xa + xb) / 2, (ya + yb) / 2, 0.04)
      fill(tone(t - 0.22), 0.65, true)
    end
    if X.discal == 1 then
      if w == "fw" then ell(0.47 + cj * 0.5, 0.42, 0.03, 0.045) else ell(0.34 + cj * 0.5, -0.27, 0.03, 0.045) end
      fill(tone(t - 0.25), 0.75, true)
    end
    local border = X.border
    if border == "band" then smooth(o, true) stroke(tone(t - 0.22), 6.8 * WG.u, 0.55, true) end
    smooth(o, true) stroke(tone(0.05), 7.37 * WG.u, 0.55, true)
    if border == "spots" then
      local c = tone(0.06)
      for b = 1, X.eyes do
        local x, y = wgat(w, m0, m1, (b - 0.5) / X.eyes, 0.86)
        circle(x, y, SPOTR[w]) fill(c, 0.8)
      end
    end
    if border == "eyes" then
      for b = 1, WG["ne" .. w] do
        local x, y = wgat(w, m0, m1, WG["es" .. w] + (b - 1) * WG["ed" .. w], 0.78)
        wgeye(x, y, WG["er" .. w])
      end
    end
    -- lunules: white arcs along the edge, a row or two
    if X.lunules > 0 then
      local nc = 2 * (m1 - m0)
      for k = 1, X.lunules do
        local f = 0.95 - 0.07 * (k - 1)
        for b = 1, nc do
          local xc, yc = wgat(w, m0, m1, (b - 0.85) / nc, f)
          local xd, yd = wgat(w, m0, m1, (b - 0.15) / nc, f)
          taper(xc, yc, (xc + (xd - xc) / 3) * 0.96, (yc + (yd - yc) / 3) * 0.96,
            (xc + (xd - xc) * 2 / 3) * 0.96, (yc + (yd - yc) * 2 / 3) * 0.96, xd, yd, 0.03, 0.008)
          fill(WHITE, 0.55)
        end
      end
    end
    -- the veins lifted out white from the wing's root, and on a wing with no border a dot
    -- at each vein's end
    if X.veins == 1 then
      local rx, ry = 0.04, ROOTY[w]
      for b = 1, n do
        local p = WG[w][b]
        local f = range(0.7, 0.88)
        local xd, yd = rx + (p[1] - rx) * f, ry + (p[2] - ry) * f
        local pts = { { rx, ry }, { rx + (xd - rx) * 0.3, ry + (yd - ry) * 0.4 }, { rx + (xd - rx) * 0.7, ry + (yd - ry) * 0.75 },
          { xd, yd } }
        streak(pts, 0.035, 0.004, WHITE, range(0.35, 0.6))
        if border == "none" and fine and b > 1 and b < n then
          circle(rx + (p[1] - rx) * 0.9, ry + (p[2] - ry) * 0.9, range(0.025, 0.04)) fill(WHITE, 0.8)
        end
      end
    end
    ink.unclip()
    -- two thread tails off the hindwing
    if X.tails == 2 and w == "hw" then
      local xb, yb = WG.hw[5][1], WG.hw[5][2]
      taper(xb - 0.05, yb - 0.02, xb - 0.04, yb - 0.1, xb - 0.025, yb - 0.18, xb - 0.02, yb - 0.26, 0.022, 0.006)
      taper(xb - 0.14, yb, xb - 0.14, yb - 0.08, xb - 0.135, yb - 0.14, xb - 0.13, yb - 0.2, 0.022, 0.006)
      fill(tone(0.08), 0.9)
    end
  end
  -- \flo@wgwing: a wing turned by rot about its root
  local function wgwing(w, rot, n, m0, m1)
    ink.push() ink.translate(0.04, 0) ink.rotate(rot) ink.translate(-0.04, 0)
    wgpaint(w, n, m0, m1)
    ink.pop()
  end
  -- \flo@wgbody: the abdomen and its bands, the thorax and its hair, the head, the feelers,
  -- the legs of a butterfly seen from the side, a highlight
  local function wgbody()
    local aw, al, tw = WG.aw, WG.al, WG.tw
    local pts = {}
    for b = 0, 10 do
      local v = b / 10
      local h, y = aw * sin(180 * v ^ 0.7), -al + al * v
      pts[b + 1] = { -h, y }
      if b > 0 and b < 10 then pts[21 - b] = { h, y } end
    end
    smooth(pts, true) fill(tone(0.06), 1)
    for b = 1, X.bands do
      local y = -al * b / (X.bands + 1)
      taper(-aw * 0.9, y, -aw * 0.3, y, aw * 0.3, y, aw * 0.9, y, 0.03, 0.03) fill(WHITE, 0.45)
    end
    ell(0, 0.08, tw, 0.13) fill(tone(0.04), 1)
    if X.hair > 0 then
      local c = tone(0.12)
      for _ = 1, floor(4 + 12 * X.hair) do
        local a, t = range(0, 360), range(0.03, 0.06)
        seg(tw * cos(a), 0.08 + 0.13 * sin(a), (tw + t) * cos(a), 0.08 + (0.13 + t) * sin(a), 0.022, 0.003)
        fill(c, 0.7)
      end
    end
    circle(0, 0.27, WG.hr) fill(tone(0.04), 1)
    local lw = max(0.3, 0.5 * WG.u)
    local ant = X.antenna
    for b = 1, 2 do
      local sx = (WG.sides == 1 or b == 2) and 1 or -1
      local ex, ey
      if ant == "clubbed" then ex, ey = range(0.22, 0.3), range(0.78, 0.9)
      elseif ant == "feathery" then ex, ey = range(0.24, 0.32), range(0.62, 0.72)
      else ex, ey = range(0.26, 0.36), range(0.72, 0.88) end       -- a thread, and any other kind's feeler
      if WG.sides == 1 and b == 2 then ex, ey = ex * 0.8, ey * 0.95 end
      ex = sx * ex
      local xa, xb, xc, yc = sx * 0.02, sx * 0.05, ex * 0.6, ey * 0.9
      local c = tone(0.08)
      moveto(xa, 0.31) curveto(xb, 0.5, xc, yc, ex, ey) stroke(c, lw, 1, false)
      if ant == "clubbed" then circle(ex, ey, 0.025) fill(tone(0.06), 1) end
      if ant == "feathery" then
        -- barbs across the feeler's curve, shorter toward its tip
        for k = 3, 9 do
          local v = k / 10
          local f = 1 - v
          local x = f * f * f * xa + 3 * f * f * v * xb + 3 * f * v * v * xc + v * v * v * ex
          local y = f * f * f * 0.31 + 3 * f * f * v * 0.5 + 3 * f * v * v * yc + v * v * v * ey
          local nx, ny = nrm(3 * f * f * (xb - xa) + 6 * f * v * (xc - xb) + 3 * v * v * (ex - xc),
            3 * f * f * 0.19 + 6 * f * v * (yc - 0.5) + 3 * v * v * (ey - yc))
          local r = 0.05 * (1.1 - v)
          moveto(x + nx * r, y + ny * r) lineto(x - nx * r, y - ny * r)
        end
        stroke(c, 0.5 * lw, 1, false)
      end
    end
    if WG.sides == 1 then
      for b = 0, 2 do
        local y = 0.16 - 0.08 * b
        moveto(-0.03, y) lineto(-0.12, y + 0.03) lineto(-0.2, y - 0.12)
      end
      stroke(tone(0.08), lw, 1, false)
    end
    if fine and X.kind == "butterfly" then
      local t = al / 0.62
      streak({ { -0.015, -0.55 * t }, { -0.02, -0.35 * t }, { -0.02, -0.1 * t }, { -0.01, 0 } }, 0.015, 0.004, WHITE, 0.45)
    end
  end
  -- \flo@lepid: a butterfly or moth, wingspan 2; u its wingspan on the page / 2 (cm),
  -- as TeX finds it (\flo@wgu)
  local function lepid(u)
    WG.u = u
    fine = u > K(0.3)
    local kind, pose, ground = X.kind, X.pose, X.ground
    local t = X.tone
    if ground == "pale" then t = min(0.78, t + 0.32) end
    if ground == "dark" then t = t - 0.12 end
    if ground == "copper" then pen.accent = true end
    -- seen from the side (wings closed over the back), spread flat, in a moth's tent, or
    -- hovering with its wings a blur at both ends of their beat
    local sides, xs, rf, rh, pass = 2, 1, 0, 0, 1
    WG.op, WG.blur = 1, false
    if pose == "closed" then sides, rf, rh, t = 1, 18, 18, min(0.8, t + 0.12) end
    if pose == "flat" then rf, rh = -18, -10 end
    if pose == "tent" then rf, rh, xs = -58, -38, 0.8 end
    if pose == "hover" then WG.op, WG.blur, pass = 0.3, true, 2 end
    WG.t, WG.sides = t, sides
    WG.aw, WG.al, WG.tw, WG.hr = 0.05, 0.62, 0.075, 0.06
    if kind == "moth" then WG.aw, WG.tw, WG.hr = 0.075, 0.095, 0.07 end
    if kind == "hawkmoth" then WG.aw, WG.al, WG.tw, WG.hr = 0.075, 0.85, 0.09, 0.07 end
    if sides == 1 then WG.aw = WG.aw * 0.8 end
    wgshape()
    WG.dep = X.wingedge == "scalloped" and 0.045 or X.wingedge == "toothed" and 0.09 or 0
    WG.tail = 0
    WG.ofw = wgoutline("fw", 8, 4, 6)
    if X.tails == 1 then WG.tail = 5 end
    WG.ohw = wgoutline("hw", 7, 3, 6)
    WG.cw, WG.cj = range(0.07, 0.11), sym(0.04)
    -- eyespots: a row on the hindwing, one near the forewing's tip when there are three or more
    WG.nehw, WG.nefw = X.eyes, X.eyes > 2 and 1 or 0
    if X.eyes > 0 then WG.erhw, WG.eshw, WG.edhw = min(0.1, 0.34 / X.eyes), 0.5 / X.eyes, 1 / X.eyes end
    WG.erfw, WG.esfw, WG.edfw = 0.065, 0.22, 0
    if sides == 1 then ink.rotate(90) end
    for a = 1, sides do
      ink.push()
      if a == 2 then xscale(-1) end
      if xs < 1 then xscale(xs) end
      for d = 1, pass do
        if pass == 2 then
          rf = d == 1 and 14 or -14
          rh = rf
        end
        if sides == 1 then wgwing("fw", rf, 8, 4, 6) wgwing("hw", rh, 7, 3, 6)
        else wgwing("hw", rh, 7, 3, 6) wgwing("fw", rf, 8, 4, 6) end
      end
      ink.pop()
    end
    wgbody()
  end

  -- ---------------------------------------------------------------- bees and hoverflies
  local BG = {}                             -- the one being drawn (\flo@bg...)
  -- \flo@bgpale: the pale bands on a part (where: t the thorax, a the abdomen) in color c, and a
  -- bumblebee's white tail
  local function bgpale(where, c)
    for b = 1, X.bands do
      if BG.bp[b] == where then band(BG.bh[b], BG.bl[b], 0.02) fill(c, 0.95) end
    end
    if where == "a" and X.paletail == 1 then band(BG.tl, -2, 0.02) fill(white(), 1) end
  end
  -- \flo@bgcolorat: the hair's color at height y on a part: 1 dark, 2 pale, 3 white
  local function bgcolorat(y, where)
    local c = 1
    if BG.kind == "bumblebee" then
      for d = 1, X.bands do
        if BG.bp[d] == where and y < BG.bh[d] and y > BG.bl[d] then c = 2 end
      end
      if where == "a" and X.paletail == 1 and y < BG.tl then c = 3 end
    end
    return c
  end
  -- \flo@bgfur: n hairs round the ellipse at (0, cy), half-width rx, ra above and rb below
  local function bgfur(cy, rx, n, ra, rb, where)
    local hairs = { {}, {}, {} }
    local hl = 0.5 + X.hair
    for _ = 1, n do
      local a, t, b = range(0, 360), range(0.02, 0.045), sym(25)
      t = t * hl + 0.014
      local v = sin(a)
      local r = (v < 0 and rb or ra) - 0.014
      local xa, ya = (rx - 0.014) * cos(a), cy + r * v
      local h = hairs[bgcolorat(ya, where)]
      h[#h + 1] = { xa, ya, xa + t * cos(a + b), ya + t * sin(a + b) }
    end
    local function paint(t, c, op)
      if #t == 0 then return end
      for _, h in ipairs(t) do seg(h[1], h[2], h[3], h[4], 0.013, 0.003) end
      fill(c, op)
    end
    paint(hairs[1], tone(BG.fd), 0.8)
    paint(hairs[2], tone(BG.pt), 0.9)
    paint(hairs[3], white(), 0.9)
  end
  -- \flo@bgabdomen: the abdomen's outline, a squared egg
  local function bgabdomen()
    local pts = {}
    for a = 1, 16 do
      local wa = 22.5 * a - 11.25
      local t, v = cos(wa), sin(wa)
      pts[a] = { BG.rx * (t < 0 and -1 or 1) * abs(t) ^ BG.sq, BG.ay + BG.ry * v * (v < 0 and BG.egg or 1) }
    end
    return pts
  end
  -- \flo@bgpaintab: the abdomen, its pattern (\flo@bgab@<kind>), mottle, rim and highlight
  local function bgpaintab()
    local ab, kind = BG.ab, BG.kind
    smooth(ab, true) fill(tone(BG.abt), 1)
    smooth(ab, true) ink.clip()
    if kind == "honeybee" then
      local gap = BG.la / (X.bands + 0.6)
      local bt = 0.42 * gap
      for b = 1, X.bands do
        local ya = BG.at - gap * (b + 0.15) + bt / 2
        band(ya, ya - bt, 0.03)
      end
      fill(tone(0.05), 0.88)
    elseif kind == "bumblebee" then bgpale("a", tone(BG.pt))
    elseif kind == "solitarybee" then
      for b = 1, X.bands do
        local ya = BG.at - BG.la * (0.12 + 0.17 * b)
        band(ya, ya - 0.035, 0.025)
      end
      fill(WHITE, 0.6)                      -- with no bands, an empty path, as the library paints it
    else                                    -- a hoverfly's bands, broken in the middle
      local gap = BG.la / (X.bands + 0.5)
      local c = BG.ground == "copper" and accent(0.1) or tone(min(0.86, BG.t + 0.4))
      for b = 1, X.bands do
        local y = BG.at - gap * (b - 0.2)
        local wa = (b == 1 and 0.3 or 0.42) * gap
        for s = -1, 1, 2 do
          local x = s * BG.rx
          taper(s * 0.03, y + 0.01, x * 0.4, y + 0.03, x * 0.75, y, x * 1.05, y - 0.04, wa, 0.15 * gap)
        end
      end
      fill(c, 0.92)
    end
    if fine then mottle(-BG.rx, BG.at - BG.la, BG.rx, BG.at, 4, 0.06, BG.abt - 0.18, BG.abt + 0.17, BG.spk) end
    smooth(ab, true) stroke(tone(0.05), 3.4 * BG.u, BG.rim, true)
    local t, v, ay = BG.rx / 0.19, BG.ry / 0.3, BG.ay
    streak({ { -0.1 * t, ay - 0.18 * v }, { -0.13 * t, ay - 0.05 * v }, { -0.12 * t, ay + 0.08 * v }, { -0.08 * t, ay + 0.2 * v } },
      0.04, 0.008, WHITE, 0.5)
    ink.unclip()
  end
  -- \flo@bgthorax
  local function bgthorax()
    local th = blob(0, BG.ty, BG.tr, BG.tr * 0.93, 0.1, 12)
    smooth(th, true) fill(tone(BG.tt), 1)
    smooth(th, true) ink.clip()
    if BG.kind == "bumblebee" then bgpale("t", tone(BG.pt)) end
    if fine then mottle(-BG.tr, BG.ty - BG.tr, BG.tr, BG.ty + BG.tr, 3, 0.05, BG.tt - 0.04, BG.tt + 0.24, 6) end
    ink.unclip()
  end
  -- \flo@bghead: the head and its eyes
  local function bghead()
    ell(0, BG.hy, BG.hx, BG.hr) fill(tone(BG.ht), 1)
    local ya = BG.hy + 0.008
    local xa, xb, yb
    if BG.kind == "hoverfly" then xa, xb, yb = 0.055, 0.068, 0.08 else xa, xb, yb = BG.hx - 0.022, 0.028, 0.05 end
    ell(-xa, ya, xb, yb) ell(xa, ya, xb, yb) fill(tone(0.02), 1)
    if fine then
      local xc, yc = xa - 0.3 * xb, ya + 0.35 * yb
      circle(-xc, yc, 0.011) circle(xc, yc, 0.011) fill(WHITE, 0.7)
    end
  end
  -- \flo@bgfeelers: a bee's elbowed feelers, a hoverfly's short ones
  local function bgfeelers()
    local c, hy = tone(0.06), BG.hy
    if BG.kind == "hoverfly" then
      local ya, yb, yc = hy + 0.07, hy + 0.11, hy + 0.14
      moveto(-0.02, ya) lineto(-0.035, yb) moveto(0.02, ya) lineto(0.035, yb) stroke(c, BG.w, 1, false)
      circle(-0.035, yb, 0.014) circle(0.035, yb, 0.014) fill(c, 1)
      if fine then moveto(-0.035, yb) lineto(-0.075, yc) moveto(0.035, yb) lineto(0.075, yc) stroke(c, 0.5 * BG.w, 1, false) end
    else
      local ya = hy + 0.05
      for b = 1, 2 do
        local sx = b == 1 and -1 or 1
        local xb, yb, xc, yc = range(0.05, 0.08), range(0.11, 0.15), range(0.11, 0.17), range(0.17, 0.23)
        moveto(sx * 0.03, ya) lineto(sx * xb, hy + yb) lineto(sx * xc, hy + yc)
      end
      stroke(c, BG.w, 1, false)
    end
  end
  -- the legs of a side: root, knee and foot, spread on a flower (v) or hanging in flight (f)
  local BGL = {
    v = { { 0.05, 0.06, 0.17, 0.1, 0.2, 0.22 }, { 0.06, 0, 0.23, -0.03, 0.3, -0.15 }, { 0.06, -0.06, 0.28, -0.16, 0.32, -0.42 } },
    f = { { 0.05, 0.04, 0.13, 0, 0.15, -0.1 }, { 0.06, 0, 0.17, -0.08, 0.18, -0.24 }, { 0.06, -0.05, 0.21, -0.16, 0.22, -0.44 } },
  }
  -- \flo@bglegs: the legs of a side, and the pollen on the hind leg
  local function bglegs()
    local legs, lx, ty = {}, BG.lx, BG.ty
    for i = 1, 3 do
      local p = BGL[BG.lp][i]
      local kx = p[3] * lx + sym(0.02)
      local ky = ty + p[4] + sym(0.02)
      local fx = p[5] * lx + sym(0.025)
      legs[i] = { p[1] * lx, ty + p[2], kx, ky, fx, ty + p[6] + sym(0.025) }
    end
    local fw = BG.fw
    for i = 1, 3 do
      local q = legs[i]
      seg(q[1], q[2], q[3], q[4], fw, fw * 0.8)
      seg(q[3], q[4], q[5], q[6], fw * 0.8, fw * 0.35)
    end
    fill(tone(0.08), 1)
    if X.pollen == 1 then
      local q, pr = legs[3], BG.pr
      local da, db = q[5] - q[3], q[6] - q[4]
      local nx, ny = nrm(da, db)
      local xa, ya = q[3] + 0.45 * da, q[4] + 0.45 * db
      local xb, yb, xc, yc = ny * 0.065 * pr, -nx * 0.065 * pr, nx * 0.042 * pr, ny * 0.042 * pr
      ellipse(xa, ya, xb, yb, xc, yc) fill(accent(0), 1)
      if fine then circle(xa + 0.35 * xc - 0.25 * xb, ya + 0.35 * yc - 0.25 * yb, 0.012) fill(WHITE, 0.6) end
    end
  end
  -- \flo@bgwingshape: a wing's outline, a teardrop l long and w wide each way
  local BGW = { { 0.02, 0 }, { 0.15, 0.55 }, { 0.45, 0.95 }, { 0.8, 0.85 }, { 1, 0.25 }, { 0.92, -0.45 }, { 0.6, -0.8 },
    { 0.25, -0.55 } }
  local function bgwingshape(l, w)
    local pts = {}
    for i, p in ipairs(BGW) do
      local x = p[1] * l + sym(0.012)
      pts[i] = { x, p[2] * w + sym(0.012) }
    end
    return pts
  end
  -- the veins of a forewing (f), a hindwing (h) and a hoverfly's wing (v), in its length and width
  local BGV = {
    f = { { { 0.03, 0.3 }, { 0.35, 0.72 }, { 0.62, 0.78 } }, { { 0.03, 0.05 }, { 0.3, 0.2 }, { 0.62, 0.25 }, { 0.85, 0.32 } },
      { { 0.05, -0.15 }, { 0.35, -0.25 }, { 0.6, -0.3 } }, { { 0.62, 0.78 }, { 0.62, 0.25 }, { 0.6, -0.3 } } },
    h = { { { 0.03, 0.05 }, { 0.55, 0.15 } } },
    v = { { { 0.03, 0.35 }, { 0.5, 0.8 }, { 0.85, 0.62 } }, { { 0.03, 0 }, { 0.5, 0.1 }, { 0.78, 0.22 }, { 0.92, 0.05 } },
      { { 0.05, -0.2 }, { 0.45, -0.32 }, { 0.72, -0.28 }, { 0.86, -0.08 } }, { { 0.5, 0.8 }, { 0.5, 0.1 }, { 0.45, -0.32 } } },
  }
  -- \flo@bgwing: a wing at (x, y) turned by rot, a pale film; with its rim, and its veins
  -- (wl long, ww wide) when the bee is large enough
  local function bgwing(pts, x, y, rot, op, rim, veins, wl, ww)
    local was = pen.accent
    pen.accent = false
    ink.push() ink.translate(x, y) ink.rotate(rot)
    smooth(pts, true) fill(tone(0.85), op)
    if rim then
      smooth(pts, true) stroke(tone(0.15), BG.lw, 0.75, false)
      if fine then
        for _, l in ipairs(BGV[veins]) do
          moveto(l[1][1] * wl, l[1][2] * ww)
          for i = 2, #l do lineto(l[i][1] * wl, l[i][2] * ww) end
        end
        stroke(tone(0.2), BG.vw, 0.6, false)
      end
    end
    ink.pop()
    pen.accent = was
  end
  -- \flo@bgwings: the wings of a side, at rest or three times over in their beat
  local function bgwings()
    local wf = bgwingshape(BG.Fl, BG.Fw)
    local wh = BG.Hl > 0 and bgwingshape(BG.Hl, BG.Hw)
    local yf, yh = BG.ty + 0.05, BG.ty - 0.01
    if BG.blur then
      for b = 1, 3 do
        if wh then bgwing(wh, 0.06, yh, BG.ah + (b - 2) * BG.dl, 0.16, false) end
        bgwing(wf, 0.06, yf, BG.af + (b - 2) * BG.dl, 0.16, false)
      end
    else
      if wh then bgwing(wh, 0.06, yh, BG.ah, 0.55, true, "h", BG.Hl, BG.Hw) end
      bgwing(wf, 0.06, yf, BG.af, 0.55, true, BG.vn, BG.Fl, BG.Fw)
    end
  end
  -- \flo@bgtrail: flora's flight path, dotted, looping away behind
  local function bgtrail()
    local tc, tn = range(0.16, 0.22), range(1, 1.3)
    local sx = chance(0.5) and 1 or -1
    local w, gap = max(0.6, 1.1 * BG.u), max(2.2, 3.2 * BG.u)
    for b = 0, 40 do
      local a = b / 40 * tn * 360
      local x, y = sx * 0.32 * sin(a), BG.tip - 0.06 - tc * a * 0.0174533 + 0.192 * (cos(a) - 1)
      if b == 0 then moveto(x, y) else lineto(x, y) end
    end
    stroke(tone(0.18), w, 0.7, false, string.format("[%.2f %.2f] %.2f", 0, gap, 0))
  end
  -- \flo@bee: a bee or a hoverfly, length 1; u its length on the page in cm, as TeX finds it
  local function bee(u)
    BG.u = u
    fine = u > K(0.25)
    local kind, pose = X.kind, X.pose
    BG.kind, BG.ground = kind, X.ground
    BG.t, BG.pt = X.tone, 0.74
    if X.ground == "dark" then BG.t = BG.t - 0.12 end
    if X.ground == "pale" then BG.t = min(0.78, BG.t + 0.32) end    -- fixed: paler, as a butterfly's
    if X.ground == "copper" then pen.accent = true BG.pt = 0.6 end
    local t = BG.t
    BG.rx, BG.ry, BG.sq, BG.egg = 0.48 * X.build, 0.3, 1, 1.12
    BG.tr, BG.hx, BG.hr = 0.13, 0.09, 0.075
    BG.Fl, BG.Fw, BG.Hl, BG.Hw, BG.vn = 0.52, 0.12, 0.38, 0.08, "f"
    BG.fw, BG.pr = 0.032, 1
    BG.abt, BG.tt, BG.ht, BG.fd = t, 0.06, 0.04, t
    BG.spk, BG.rim = 4, 0.4
    if kind == "honeybee" then BG.tt = max(0.06, t - 0.24) end
    if kind == "bumblebee" then
      BG.egg, BG.tr, BG.hx, BG.Fl, BG.Fw = 1, 0.16, 0.1, 0.48, 0.11
      BG.Hl, BG.fw, BG.pr, BG.abt, BG.tt = 0.34, 0.036, 1.2, 0.06, 0.05
      BG.fd, BG.spk, BG.rim = 0.08, 14, 0.15
    end
    if kind == "solitarybee" then
      BG.ry, BG.tr, BG.hx, BG.pr = 0.32, 0.11, 0.08, 0.9
      BG.abt = max(0.05, t - 0.24)
    end
    if kind == "hoverfly" then
      BG.rx, BG.sq, BG.egg, BG.tr, BG.hx = 0.42 * X.build, 0.8, 1.2, 0.12, 0.13
      BG.hr, BG.Fl, BG.Hl, BG.vn, BG.fw = 0.085, 0.62, 0, "v", 0.022
      BG.abt, BG.tt, BG.ht, BG.fd = 0.08, 0.08, 0.1, 0.25
    end
    local ty, tr, ry = 0.15, BG.tr, BG.ry
    local at = ty - tr + 0.09
    local la = ry * (1 + 0.98 * BG.egg)
    BG.ty, BG.hy, BG.at, BG.ay, BG.la, BG.tip = ty, ty + tr + 0.04, at, at - ry, la, at - la
    BG.lx = 0.6 + 2 * BG.rx
    -- the bands' parts and their tops and bottoms; a bumblebee's white tail from tl down
    BG.bp = { "t", "a", "t", "a" }
    BG.bh = { ty + tr + 0.03, at - 0.3 * la, ty - 0.5 * tr, at + 0.03 }
    BG.bl = { ty + 0.4 * tr, at - 0.5 * la, ty - tr - 0.03, at - 0.17 * la }
    BG.tl = at - 0.7 * la
    BG.w, BG.lw, BG.vw = max(0.25, 0.45 * u), max(0.2, 0.35 * u), max(0.15, 0.25 * u)
    BG.lp, BG.blur, BG.af, BG.ah, BG.dl = "v", false, -70, -78, 0
    if pose == "fly" then BG.lp, BG.blur, BG.af, BG.ah, BG.dl = "f", true, 14, -4, 16 end
    if pose == "rest" then BG.af = -45 end
    if pose == "hover" then BG.lp, BG.blur, BG.af, BG.dl = "f", true, 10, 22 end
    if pose == "fly" then bgtrail() end
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) end
      bglegs()
      ink.pop()
    end
    BG.ab = bgabdomen()
    bgpaintab()
    if kind ~= "hoverfly" and kind ~= "bumblebee" then             -- the sting
      local ya, yb = BG.tip + 0.04, BG.tip - 0.05
      moveto(-0.022, ya) lineto(0, yb) lineto(0.022, ya) close() fill(tone(0.05), 1)
    end
    if kind == "bumblebee" then bgfur(BG.ay, BG.rx, floor(24 + 60 * X.hair), ry, ry * BG.egg, "a") end
    bgthorax()
    local rb = BG.tr * 0.93
    bgfur(ty, BG.tr, floor(6 + 40 * X.hair), rb, rb, "t")
    bghead() bgfeelers()
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) end
      bgwings()
      ink.pop()
    end
  end

  -- ---------------------------------------------------------------- dragonflies and damselflies
  local OD = {}                             -- the one being drawn (\flo@od...)
  -- the wings' outlines (along, across in units of the width) and their long veins (across
  -- at the root, middle and tip; 0 and 5 outside the wing)
  local ODW = {
    f = { { 0.01, 0.35 }, { 0.12, 0.75 }, { 0.45, 0.95 }, { 0.8, 0.9 }, { 0.97, 0.55 }, { 1, 0.1 }, { 0.93, -0.45 }, { 0.7, -0.75 },
      { 0.35, -0.85 }, { 0.08, -0.6 } },
    h = { { 0.01, 0.35 }, { 0.15, 0.8 }, { 0.5, 0.95 }, { 0.85, 0.85 }, { 1, 0.3 }, { 0.96, -0.35 }, { 0.75, -0.75 }, { 0.45, -1 },
      { 0.2, -1.45 }, { 0.04, -0.8 } },
    d = { { 0, 0.1 }, { 0.2, 0.2 }, { 0.45, 0.8 }, { 0.78, 0.98 }, { 0.98, 0.6 }, { 1, 0 }, { 0.94, -0.6 }, { 0.75, -0.9 },
      { 0.45, -0.6 }, { 0.2, -0.2 } },
  }
  local ODV = {
    f = { [0] = { 1.3, 1.3, 1.3 }, { 0.45, 0.72, 0.5 }, { 0.15, 0.3, 0.05 }, { -0.1, -0.3, -0.45 }, { -0.3, -0.7, -0.8 },
      { -1.6, -1.6, -1.6 } },
    h = { [0] = { 1.3, 1.3, 1.3 }, { 0.45, 0.72, 0.5 }, { 0.15, 0.3, 0.05 }, { -0.1, -0.35, -0.45 }, { -0.4, -0.9, -0.8 },
      { -1.6, -1.6, -1.6 } },
    d = { [0] = { 1.3, 1.3, 1.3 }, { 0.06, 0.6, 0.4 }, { 0.02, 0.2, 0 }, { -0.02, -0.25, -0.4 }, { -0.06, -0.5, -0.7 },
      { -1.6, -1.6, -1.6 } },
  }
  -- \flo@odvat: long vein k across the wing at u along it
  local function odvat(k, u)
    local v = ODV[OD.wk][k]
    if u < 0.5 then return v[1] + (v[2] - v[1]) * 2 * u end
    return v[2] + (v[3] - v[2]) * (2 * u - 1)
  end
  -- \flo@odwingshape
  local function odwingshape(t, l, w)
    local pts = {}
    for i, p in ipairs(ODW[t]) do
      local x = p[1] * l + sym(0.008)
      pts[i] = { x, p[2] * w + sym(0.008) }
    end
    return pts
  end
  -- \flo@odwing: a wing at (x, y) turned by rot: the film, a tint, the stigma, the long veins
  -- and on a large one the net between them, the rim
  local function odwing(pts, x, y, rot)
    local wl, ww, was = OD.wl, OD.ww, pen.accent
    ink.push() ink.translate(x, y) ink.rotate(rot)
    pen.accent = false
    smooth(pts, true) fill(tone(OD.wt), OD.wo)
    pen.accent = was
    smooth(pts, true) ink.clip()
    if X.tint == "tinted" then ell(0.1 * wl, -0.2 * ww, 0.2 * wl, 1.2 * ww) fill(tone(0.45), 0.3) end
    if X.stigma == 1 then
      local xa, xb, ya, yb = 0.83 * wl, 0.91 * wl, 1.3 * ww, 0.55 * ww
      moveto(xa, ya) lineto(xb, ya) lineto(xb, yb) lineto(xa, yb) close() fill(tone(0.06), 0.9)
    end
    if fine then
      pen.accent = false
      for c = 1, 4 do
        local v = ODV[OD.wk][c]
        moveto(0, v[1] * ww) lineto(0.5 * wl, v[2] * ww) lineto(wl, v[3] * ww)
      end
      stroke(tone(0.15), OD.vw, 0.6, false)
      if OD.net then
        for c = 1, 5 do
          for d = 1, 22 do
            local u = (d - 0.5 + sym(0.3)) / 22 * 0.96 + 0.02
            local ya, yb = odvat(c - 1, u) * ww, odvat(c, u) * ww
            moveto(u * wl, ya) lineto((u + sym(0.01)) * wl, yb)
          end
        end
        stroke(tone(0.2), OD.nw, 0.45, false)
      end
      pen.accent = was
    end
    ink.unclip()
    if fine then
      pen.accent = false
      smooth(pts, true) stroke(tone(0.15), OD.lw, 0.7, false)
      pen.accent = was
    end
    ink.pop()
  end
  -- \flo@odwings: the hindwing and forewing of a side
  local function odwings()
    local wh = odwingshape(OD.hk, OD.Hl, OD.Hw)
    local wf = odwingshape(OD.fk, OD.Fl, OD.Fw)
    OD.wk, OD.wl, OD.ww = OD.hk, OD.Hl, OD.Hw
    odwing(wh, OD.rx, OD.ty - OD.hd, OD.ah)
    OD.wk, OD.wl, OD.ww = OD.fk, OD.Fl, OD.Fw
    odwing(wf, OD.rx, OD.ty + OD.fd, OD.af)
  end
  -- \flo@odabdomen: long and thin, swollen at its root
  local function odabdomen()
    local pts = {}
    for a = 0, 11 do
      local v = a / 11
      local h = OD.aw * (1 + OD.bul * math.exp(-min(9, v * v / 0.012))) * min(1, (1.04 - v) * 5)
      local y = OD.at + (OD.tip - OD.at) * v
      pts[a + 1] = { h, y }
      pts[24 - a] = { -h, y }
    end
    return pts
  end
  -- \flo@odseg: the end of segment e down the abdomen, as a fraction of its length
  local function odseg(e) if e < 1 then return 0 end return (e / 10) ^ 1.12 end
  -- \flo@odpaintab: the abdomen, dark bands on its last segments, the joints, a highlight,
  -- the rim and the claspers
  local function odpaintab()
    local ab, at, tip = OD.ab, OD.at, OD.tip
    smooth(ab, true) fill(tone(OD.t), 1)
    smooth(ab, true) ink.clip()
    if X.bands > 0 then
      for b = 1, X.bands do
        local n = 10 - X.bands + b
        local sa, sv = odseg(n - 1), odseg(n)
        band(at + (tip - at) * (sa + 0.6 * (sv - sa)), at + (tip - at) * sv - 0.01, 0.004)
      end
      fill(tone(0.04), 0.85)
    end
    if fine then
      for b = 1, 9 do
        local y = at + (tip - at) * odseg(b)
        moveto(-0.1, y) lineto(0.1, y)
      end
      stroke(tone(0.05), OD.jw, 0.5, false)
      local t, aw = tip - at, OD.aw
      streak({ { -0.4 * aw, at + 0.06 * t }, { -0.45 * aw, at + 0.3 * t }, { -0.45 * aw, at + 0.6 * t }, { -0.35 * aw, at + 0.85 * t } },
        0.5 * aw, 0.004, WHITE, 0.45)
    end
    smooth(ab, true) stroke(tone(0.05), 1.4 * OD.u, 0.35, true)
    ink.unclip()
    if fine then
      local ya, yb, xa, xb = tip + 0.012, tip - 0.022, 0.5 * OD.aw, 0.9 * OD.aw
      moveto(-xa, ya) lineto(-xb, yb) moveto(xa, ya) lineto(xb, yb) stroke(tone(0.05), OD.jw, 1, false)
    end
  end
  -- \flo@odthorax
  local function odthorax()
    local th = blob(0, OD.ty, OD.tr, OD.th, 0.06, 10)
    smooth(th, true) fill(tone(OD.tt), 1)
    smooth(th, true) ink.clip()
    if fine then
      for s = -1, 1, 2 do
        seg(s * 0.3 * OD.tr, OD.ty + 0.75 * OD.th, s * 0.6 * OD.tr, OD.ty - 0.45 * OD.th, 0.3 * OD.tr, 0.12 * OD.tr)
      end
      fill(WHITE, 0.35)
    end
    smooth(th, true) stroke(tone(0.05), 1.2 * OD.u, 0.4, true)
    ink.unclip()
  end
  -- \flo@odhead: the head and its great eyes
  local function odhead()
    ell(0, OD.hy, OD.hx, OD.hr) fill(tone(0.06), 1)
    local ya, ex, er = OD.hy + OD.ey, OD.ex, OD.er
    ell(-ex, ya, er, er) ell(ex, ya, er, er) fill(tone(OD.et), 1)
    if fine then
      local xa, yb, r = ex - 0.35 * er, ya + 0.4 * er, 0.22 * er
      circle(-xa, yb, r) circle(xa, yb, r) fill(WHITE, 0.7)
    end
  end
  -- \flo@odo: a dragonfly or a damselfly, length 1; u its length on the page in cm
  local function odo(u)
    OD.u = u
    fine, OD.net = u > K(0.4), u > K(1.5)
    local kind = X.kind
    local t = X.tone
    if X.ground == "dark" then t = t - 0.12 end
    if X.ground == "copper" then pen.accent = true end
    OD.t, OD.tt, OD.et = t, max(0.05, t - 0.08), max(0.06, t - 0.1)
    if X.tint == "tinted" then OD.wt, OD.wo = 0.7, 0.42 else OD.wt, OD.wo = 0.88, 0.28 end
    OD.aw, OD.bul, OD.at, OD.tip = 0.032, 0.7, 0.16, -0.62
    OD.ty, OD.tr, OD.th = 0.235, 0.066, 0.08
    OD.hy, OD.hx, OD.hr, OD.ex, OD.ey, OD.er = 0.34, 0.075, 0.048, 0.038, 0.006, 0.046
    OD.fk, OD.hk, OD.Fl, OD.Fw, OD.Hl, OD.Hw = "f", "h", 0.62, 0.065, 0.6, 0.075
    OD.rx, OD.fd, OD.hd, OD.af, OD.ah = 0.02, 0.03, 0.035, 8, -6
    LGP.x, LGP.w = 1, 0.014
    if kind == "damselfly" then
      OD.aw, OD.bul, OD.at, OD.tip = 0.016, 0.5, 0.2, -0.66
      OD.ty, OD.tr, OD.th = 0.26, 0.04, 0.058
      OD.hy, OD.hx, OD.hr, OD.ex, OD.ey, OD.er = 0.34, 0.075, 0.028, 0.058, 0, 0.026
      OD.fk, OD.hk, OD.Fl, OD.Fw, OD.Hl, OD.Hw = "d", "d", 0.5, 0.06, 0.48, 0.06
      OD.rx, OD.fd, OD.hd, OD.af, OD.ah = 0.012, 0.02, 0.02, -84, -88
      LGP.x, LGP.w = 0.75, 0.01
      -- its wings spread, or folded along the abdomen and seen edge on
      if X.pose == "spread" then OD.af, OD.ah = -38, -50 else OD.Fw, OD.Hw = 0.032, 0.032 end
    end
    OD.lw, OD.vw, OD.nw, OD.jw = max(0.18, 0.3 * u), max(0.12, 0.22 * u), max(0.08, 0.1 * u), max(0.1, 0.18 * u)
    LGP.y, LGP.ex, LGP.j, LGP.ph = OD.ty, 0, 0.006, 0
    local c = tone(0.06)
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) end
      vlegs("o", c)
      ink.pop()
    end
    OD.ab = odabdomen()
    odpaintab() odthorax() odhead()
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) end
      odwings()
      ink.pop()
    end
  end

  -- ---------------------------------------------------------------- beetles and ladybirds
  local BT = {}                             -- the one being drawn (\flo@bt...)
  -- \flo@btelytra: the wing cases' outline
  local function btelytra()
    local pts = {}
    for a = 1, 16 do
      local wa = 22.5 * a - 11.25
      local t, v = cos(wa), sin(wa)
      pts[a] = { BT.ew * (t < 0 and -1 or 1) * abs(t) ^ BT.sq, BT.ey + v * (v < 0 and BT.rb or BT.rt) }
    end
    return pts
  end
  -- \flo@btshield: the shield behind the head, pb wide at its back, pf at its front, pl long
  local function btshield(pb, pf, pl)
    local sa = BT.et - BT.so
    local sb = BT.et + pl
    local sl = sb - sa
    BT.sa, BT.sl = sa, sl
    local p = {}
    p[1], p[10] = { 0.55 * pb, sa - 0.01 }, { -0.55 * pb, sa - 0.01 }
    p[2], p[9] = { pb, sa }, { -pb, sa }
    p[3], p[8] = { BT.sw * pb, sa + 0.45 * sl }, { -BT.sw * pb, sa + 0.45 * sl }
    p[4], p[7] = { pf, sb - 0.15 * sl }, { -pf, sb - 0.15 * sl }
    p[5], p[6] = { 0.5 * pf, sb }, { -0.5 * pf, sb }
    return p
  end
  -- \flo@bthw: the wing cases' half-width at y
  local function bthw(y)
    local t = (y - BT.ey) / (y > BT.ey and BT.rt or BT.rb)
    return BT.ew * sqrt(max(0, 1 - t * t))
  end
  -- \flo@btstripes: four stripes down the wing cases, in color c
  local function btstripes(c)
    local t = BT.et - BT.tip
    for b = 1, 4 do
      local x = (b < 3 and 1 or -1) * (b % 2 == 1 and 0.36 or 0.72) * BT.ew
      taper(x, BT.et - 0.03, x * 1.04, BT.et - 0.35 * t, x * 0.9, BT.et - 0.7 * t, x * 0.35, BT.tip + 0.06, 0.045, 0.012)
    end
    fill(c, 0.8)
  end
  -- \flo@btspot: a spot at (x, y), about r across
  local function btspot(x, y, r, c)
    local sr = r * range(0.85, 1.1)
    smooth(blob(x, y, sr, sr * 0.92, 0.1, 8), true) fill(c, 0.95)
  end
  -- \flo@btspots: the spots in pairs, in rows of one to three a side, an odd one on the seam
  local function btspots(c)
    local m = X.spots // 2
    local r = X.spotsize * BT.ew * 1.6 / sqrt(max(1, m))
    local cols = m < 4 and 1 or m < 8 and 2 or 3
    local rows = (m + cols - 1) // cols
    local top, tip = BT.et - BT.so, BT.tip
    if X.spots - 2 * m > 0 then btspot(0, top - 0.6 * r, 1.15 * r, c) end
    for b = 1, m do
      local row = (b - 1) // cols
      local col = b - 1 - cols * row
      local v = (row + 0.5) / rows + sym(0.04)
      local u
      if cols == 1 then u = m == 1 and 0.5 or (row == 1 and 0.4 or 0.62)
      elseif cols == 2 then
        u = col == 0 and 0.33 or 0.7
        if b == m and col == 0 then u = 0.5 end
      else u = 0.2 + 0.3 * col end
      u = u + sym(0.05)
      local y = top - 0.04 - v * (top - tip - 0.08)
      local x = u * bthw(y)
      btspot(x, y, r, c) btspot(-x, y, r, c)
    end
  end
  -- \flo@btmark: the pattern's color
  local function btmark()
    if BT.ground == "dark" then
      if BT.kind == "ladybird" then return accent(0) end
      return tone(0.8)
    end
    return tone(0.04)
  end
  -- \flo@btpaintel: the wing cases, their pattern, mottle, rim, highlights and seam
  local function btpaintel()
    local el = BT.el
    smooth(el, true) fill(tone(BT.t), 1)
    smooth(el, true) ink.clip()
    if X.pattern == "stripes" then btstripes(btmark()) end
    if X.pattern == "spots" then btspots(btmark()) end
    if fine then mottle(-BT.ew, BT.tip, BT.ew, BT.et, 3, 0.08, BT.t - 0.06, BT.t + 0.2, 0) end
    smooth(el, true) stroke(tone(0.04), 2.6 * BT.u, 0.35, true)
    if fine then
      local ln, top, ew = (BT.et - BT.tip) * BT.gl, BT.et - BT.so, BT.ew
      for b = 1, 2 do
        local sx, op = b == 1 and -1 or 1, b == 1 and 0.55 or 0.3
        streak({ { sx * 0.5 * ew, top - 0.06 * ln }, { sx * 0.56 * ew, top - 0.23 * ln }, { sx * 0.54 * ew, top - 0.43 * ln },
          { sx * 0.45 * ew, top - 0.6 * ln } }, 0.14 * ew, 0.01, WHITE, op)
      end
    end
    ink.unclip()
    moveto(0, BT.et) lineto(0, BT.tip) stroke(tone(0.04), BT.w, 0.8, false)
  end
  -- \flo@btfeeler: a feeler, threadlike, clubbed or combed, in color c (another kind's,
  -- fixed, as a thread)
  local function btfeeler(c)
    local ant, fs = X.antenna, BT.fs
    local xa, ya = 0.35 * BT.hx, BT.hy + 0.6 * BT.hr
    local xb, yb, xc, yc
    if ant == "clubbed" then xb, yb, xc, yc = range(0.06, 0.08), range(0.06, 0.08), range(0.1, 0.13), range(0.12, 0.15)
    elseif ant == "comb" then xb, yb, xc, yc = range(0.08, 0.1), range(0.08, 0.1), range(0.16, 0.2), range(0.18, 0.22)
    else xb, yb, xc, yc = range(0.1, 0.14), range(0.1, 0.14), range(0.2, 0.28), range(0.24, 0.32) end   -- a thread, and any other kind's feeler
    xb, yb, xc, yc = xa + xb * fs, ya + yb * fs, xa + xc * fs, ya + yc * fs
    moveto(xa, ya) lineto(xb, yb) lineto(xc, yc) stroke(c, BT.w, 1, false)
    local da, db = xc - xb, yc - yb
    if ant == "clubbed" then
      local nx, ny = nrm(da, db)
      ellipse(xc, yc, ny * 0.034 * fs, -nx * 0.034 * fs, nx * 0.02 * fs, ny * 0.02 * fs) fill(c, 1)
    end
    if ant == "comb" and fine then
      local nx, ny = nrm(da, db)
      for k = 1, 6 do
        local v = k / 6
        local xd, yd = xb + v * da, yb + v * db
        moveto(xd, yd) lineto(xd - nx * 0.035 * fs, yd - ny * 0.035 * fs)
      end
      stroke(c, 0.6 * BT.w, 1, false)
    end
  end
  -- \flo@bthead: the head; a ladybird's white cheeks, or a beetle's eyes and jaws
  local function bthead()
    local hx, hy, hr = BT.hx, BT.hy, BT.hr
    ell(0, hy, hx, hr) fill(tone(BT.ht), 1)
    if BT.kind == "ladybird" then
      if fine then
        local xa, ya, r = 0.45 * hx, hy + 0.3 * hr, 0.22 * hx
        circle(-xa, ya, r) circle(xa, ya, r) fill(white(), 0.9)
      end
    else
      local xa, ya, xb, yb = 0.82 * hx, hy + 0.1 * hr, 0.24 * hx, 0.42 * hr
      ell(-xa, ya, xb, yb) ell(xa, ya, xb, yb) fill(tone(0.02), 1)
      if fine then
        for s = -1, 1, 2 do
          taper(s * 0.4 * hx, hy + 0.8 * hr, s * 0.5 * hx, hy + 1.25 * hr, s * 0.3 * hx, hy + 1.55 * hr, s * 0.08 * hx,
            hy + 1.6 * hr, 0.3 * hx, 0.004)
        end
        fill(tone(0.05), 1)
      end
    end
  end
  -- \flo@btpaintpn: the shield, a ladybird's white patches, a highlight, the rim
  local function btpaintpn()
    local pn, pb, sa, sl = BT.pn, BT.pb, BT.sa, BT.sl
    smooth(pn, true) fill(tone(BT.pt), 1)
    smooth(pn, true) ink.clip()
    if BT.kind == "ladybird" then
      local xa, ya, xb, yb = 0.72 * pb, sa + 0.62 * sl, 0.3 * pb, 0.4 * sl
      ell(-xa, ya, xb, yb) ell(xa, ya, xb, yb) fill(white(), 0.95)
    end
    if fine then
      streak({ { -0.55 * pb, sa + 0.3 * sl }, { -0.4 * pb, sa + 0.62 * sl }, { -0.2 * pb, sa + 0.8 * sl } }, 0.12 * sl, 0.006, WHITE, 0.4)
    end
    smooth(pn, true) stroke(tone(0.03), 2 * BT.u, 0.35, true)
    ink.unclip()
  end
  -- \flo@beetle: a beetle or a ladybird, length 1; u its length on the page in cm
  local function beetle(u)
    BT.u = u
    fine = u > K(0.25)
    local kind = X.kind
    BT.kind, BT.ground = kind, X.ground
    local t = X.tone
    if X.ground == "dark" then
      t = max(0.04, t - 0.22)
      if kind == "ladybird" then t = 0.06 end
    end
    if X.ground == "copper" then pen.accent = true end
    BT.t = t
    local ew = 0.5 * X.build
    BT.ew, BT.et, BT.tip, BT.rt, BT.sq = ew, 0.14, -0.56, 0.12, 0.7
    BT.pb, BT.pf, BT.pl, BT.so, BT.sw = 0.88 * ew, 0.62 * ew, 0.17, 0.012, 1.02
    BT.hx, BT.hr, BT.hy, BT.fs, BT.gl = 0.36 * ew, 0.065, 0.36, 1, 1
    BT.pt, BT.ht = max(0.04, t - 0.06), max(0.04, t - 0.1)
    LGP.w, LGP.j, LGP.x, LGP.ex = 0.03, 0.015, 1, ew
    local ly = 0
    if kind == "ladybird" then
      BT.et, BT.tip, BT.rt, BT.sq = 0.22, -0.5, 0.36, 1
      BT.pb, BT.pf, BT.pl, BT.so, BT.sw = 0.6 * ew, 0.4 * ew, 0.05, 0.075, 0.92
      BT.hx, BT.hr, BT.hy, BT.fs, BT.gl = 0.3 * ew, 0.055, 0.27, 0.45, 0.55
      BT.pt, BT.ht = 0.04, 0.04
      LGP.w, LGP.j, LGP.x, LGP.ex = 0.032, 0.01, 0.7, 0.8 * ew
      ly = 0.12
    end
    BT.ey = BT.et - BT.rt
    BT.rb = BT.ey - BT.tip
    BT.w = max(0.25, 0.4 * u)
    LGP.y = BT.et - ly
    local c = tone(0.05)
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) LGP.ph = -0.04 else LGP.ph = 0.04 end
      vlegs("b", c)
      ink.pop()
    end
    for a = 1, 2 do
      ink.push()
      if a == 2 then xscale(-1) end
      btfeeler(c)
      ink.pop()
    end
    bthead()
    BT.el = btelytra()
    btpaintel()
    BT.pn = btshield(BT.pb, BT.pf, BT.pl)
    btpaintpn()
    if kind ~= "ladybird" then                                    -- the scutellum
      local ya, yb = BT.et + 0.004, BT.et - 0.05
      moveto(-0.035, ya) lineto(0.035, ya) lineto(0, yb) close() fill(tone(BT.pt), 1)
    end
  end

  -- ---------------------------------------------------------------- caterpillars
  local CT = {}                             -- the one being drawn (\flo@ct...) and its leaf (\flo@hf...)
  -- \flo@hfw: the host leaf's half-width at v along it, and its midrib's x there
  local function hfw(v) return CT.hW * sin(180 * v ^ 0.8) ^ 0.85, CT.hb * v * v end
  -- \flo@hfoutline: the leaf, with the bites taken from its edge
  local function hfoutline()
    local pts = { { 0, 0 } }
    pts[25] = { CT.hb, CT.hL }
    for a = 1, 23 do
      local v = a / 24
      local h, x = hfw(v)
      local y = v * CT.hL
      local xa = x + h
      for b = 1, CT.nb do
        local t, r = abs(y - CT.by[b]), CT.br[b]
        if t < r then xa = min(xa, CT.bx[b] - sqrt(max(0, r * r - t * t))) end
      end
      pts[a + 1] = { xa, y }
      pts[49 - a] = { x - h, y }
    end
    return pts
  end
  -- \flo@hfpaint: the leaf: its stalk, its darker half, mottle, the midrib and side veins, rim
  local function hfpaint()
    local l, hL, was = CT.l, CT.hL, pen.accent
    pen.accent = false
    taper(0, -0.14, 0, -0.09, 0, -0.05, 0, 0.02, 0.028, 0.02) fill(tone(0.2), 1)
    smooth(l, true) fill(tone(CT.hft), 1)
    smooth(l, true) ink.clip()
    local c = tone(CT.hft - 0.12)
    moveto(-1, 0) lineto(0, 0)
    for a = 1, 8 do
      local v = a / 8
      local _, x = hfw(v)
      lineto(x, v * hL)
    end
    lineto(-1, hL) close() fill(c, 0.35, true)
    if fine then
      mottle(-CT.hW, 0, CT.hW, hL, 6, 0.12, CT.hft - 0.16, CT.hft + 0.18, 8)
      local _, xb = hfw(0.33)
      local _, xc = hfw(0.67)
      local _, xd = hfw(0.97)
      taper(0, 0, xb, 0.33 * hL, xc, 0.67 * hL, xd, 0.97 * hL, 0.022, 0.004) fill(WHITE, 0.5)
      for a = 1, 10 do
        local sx = a % 2 == 1 and 1 or -1
        local v = 0.1 + 0.15 * ((a - 1) // 2)
        local h, x = hfw(v)
        local y = v * hL
        local xd2, yd = x + sx * 0.85 * h, y + 0.09 * hL
        taper(x, y, x + (xd2 - x) * 0.4, y + (yd - y) * 0.15, x + (xd2 - x) * 0.75, y + (yd - y) * 0.55, xd2, yd, 0.014, 0.002)
      end
      fill(WHITE, 0.4)
    end
    smooth(l, true) stroke(tone(0.06), 0.9 * CT.u, 0.4, true)
    ink.unclip()
    pen.accent = was
  end
  -- \flo@ctangle: the body's heading at s along it: looping, curled or wavering
  local function ctangle(s)
    if CT.pose == "loop" then return 105 * cos(180 * s) end
    if CT.pose == "curl" then return 150 - 300 * s end
    return CT.wa * sin(540 * s + CT.ph)
  end
  -- \flo@ctspine: the body's 27 points, their headings, normals and half-widths
  local function ctspine()
    local x, y, a, nx, ny, w = { [0] = 0 }, { [0] = 0 }, {}, {}, {}, {}
    for k = 0, 26 do
      local v = k / 26
      if k > 0 then
        local h = ctangle((k - 0.5) / 26)
        x[k], y[k] = x[k - 1] + cos(h) / 26, y[k - 1] + sin(h) / 26
      end
      local h = ctangle(v)
      a[k], nx[k], ny[k] = h, -sin(h), cos(h)
      w[k] = CT.W * (0.7 + 0.3 * sin(180 * min(1, 1.6 * v))) * (v > 0.92 and 1 - (v - 0.92) * 2.5 or 1)
    end
    CT.x, CT.y, CT.a, CT.nx, CT.ny, CT.w = x, y, a, nx, ny, w
  end
  -- \flo@ctat: the point f half-widths across the body at point k, and g along it
  local function ctat(k, f, g)
    local w, nx, ny = CT.w[k], CT.nx[k], CT.ny[k]
    return CT.x[k] + f * w * nx + g * w * ny, CT.y[k] + f * w * ny - g * w * nx
  end
  -- \flo@ctoutline
  local function ctoutline()
    local pts = {}
    for a = 0, 26 do
      pts[a + 1] = { ctat(a, -1, 0) }
      pts[54 - a] = { ctat(a, 1, 0) }
    end
    pts[55] = { ctat(0, 0, -0.7) }
    return pts
  end
  -- \flo@ctleg: a leg at point k, from a to b half-widths out, g along, widths wa to wb
  local function ctleg(k, a, b, g, wa, wb)
    local x0, y0 = ctat(k, -a, 0)
    local x1, y1 = ctat(k, -b, g)
    seg(x0, y0, x1, y1, wa, wb)
  end
  -- \flo@ctline: the points from a to b by step, f half-widths across
  local function ctline(a, b, step, f)
    local pts = {}
    for i = 0, (b - a) // step do pts[i + 1] = { ctat(a + step * i, f, 0) } end
    return pts
  end
  local CTPRO = { 1, 9, 11, 13, 15 }
  -- \flo@ctbody: the prolegs and true legs, the body, its darker side, stripes, segments,
  -- mottle, highlight and rim
  local function ctbody()
    local W, t = CT.W, CT.t
    local c = tone(max(0.05, t - 0.08))
    for a = 1, 5 do
      if not (CT.pose == "loop" and a > 2) then ctleg(CTPRO[a], 0.5, 1.45, -0.1, 0.9 * W, 0.65 * W) end
    end
    fill(c, 1)
    c = tone(0.08)
    for a = 0, 2 do ctleg(21 + 2 * a, 0.6, 1.55, 0.35, 0.35 * W, 0.06 * W) end
    fill(c, 1)
    local b = ctoutline()
    smooth(b, true) fill(tone(t), 1)
    smooth(b, true) ink.clip()
    c = tone(t - 0.12)
    for a = 0, 26 do
      local x, y = ctat(a, 0, 0)
      if a == 0 then moveto(x, y) else lineto(x, y) end
    end
    for a = 0, 26 do lineto(ctat(26 - a, -1.4, 0)) end
    close() fill(c, 0.35, true)
    if X.stripes == "side" then
      streak(ctline(1, 25, 2, -0.2), 0.45 * W, 0.3 * W, WHITE, 0.6)
      if fine then
        c = tone(0.04)
        for a = 1, 9 do
          local x, y = ctat(1 + 2 * a, 0.08, 0)
          ell(x, y, 0.09 * W, 0.13 * W)
        end
        fill(c, 0.85)
      end
    end
    if X.stripes == "back" then streak(ctline(1, 25, 2, 0.72), 0.42 * W, 0.3 * W, tone(0.05), 0.7) end
    if fine then
      for a = 1, 12 do moveto(ctat(2 * a, -1.3, 0)) lineto(ctat(2 * a, 1.3, 0)) end
      stroke(tone(0.05), CT.jw, 0.4, true)
      mottle(-0.2, -0.4, 1.1, 0.8, 5, 0.05, t - 0.14, t + 0.18, 10)
      streak(ctline(2, 24, 2, 0.45), 0.3 * W, 0.004, WHITE, 0.4)
    end
    smooth(b, true) stroke(tone(0.05), 0.9 * CT.u, 0.6, true)
    ink.unclip()
  end
  -- \flo@cthead: the head at the front end, its eye, a highlight, the jaw
  local function cthead()
    local W = CT.W
    local hx, hy = ctat(26, 0, 0.5)
    local nx, ny = CT.nx[26], CT.ny[26]
    local xb, yb, xc, yc = ny * 0.92 * W, -nx * 0.92 * W, nx * 0.85 * W, ny * 0.85 * W
    ellipse(hx, hy, xb, yb, xc, yc) fill(tone(CT.ht), 1)
    if fine then
      circle(hx + 0.35 * xb + 0.15 * xc, hy + 0.35 * yb + 0.15 * yc, 0.13 * W) fill(tone(0.02), 1)
      circle(hx - 0.25 * xb + 0.45 * xc, hy - 0.25 * yb + 0.45 * yc, 0.1 * W) fill(WHITE, 0.6)
      seg(hx + 0.8 * xb - 0.45 * xc, hy + 0.8 * yb - 0.45 * yc, hx + 1.2 * xb - 0.75 * xc, hy + 1.2 * yb - 0.75 * yc, 0.25 * W, 0.05 * W)
      fill(tone(0.04), 1)
    end
  end
  -- \flo@cthorn: a hawkmoth caterpillar's tail horn
  local function cthorn()
    local xe, ye = ctat(5, 0.8, 0)
    local xd, yd = ctat(5, 2.4, -1.6)
    local xb, yb = ctat(5, 1.7, 0)
    local xc, yc = ctat(5, 2.4, -0.7)
    taper(xe, ye, xb, yb, xc, yc, xd, yd, 0.5 * CT.W, 0.05 * CT.W) fill(tone(0.08), 1)
  end
  -- \flo@cthair: a hair at point k, len half-widths long, g along, turned deg from square
  local function cthair(k, len, g, deg)
    local W = CT.W
    local x, y = ctat(k, 0.85, g)
    local t = CT.a[k] + 90 + deg
    seg(x, y, x + len * W * cos(t), y + len * W * sin(t), 0.1 * W, 0.02 * W)
  end
  -- \flo@cttufts: four white tufts along the back, dark pencils at both ends
  local function cttufts()
    local c = white()
    for a = 1, 4 do
      for b = 1, 9 do
        local l, g = range(1.2, 1.8), range(-0.25, 0.25)
        cthair(9 + 2 * a, l, g, (b - 5) * 8)
      end
    end
    fill(c, 0.9)
    c = tone(0.08)
    for a = 1, 5 do
      cthair(24, range(2.4, 3), 0, a * 6 - 48)
      cthair(2, range(2, 2.6), 0, a * 6 + 12)
    end
    fill(c, 0.9)
  end
  -- \flo@caterpillar: a caterpillar on its host leaf, length 1; u its length on the page in cm
  local function caterpillar(u)
    CT.u = u
    fine = u > K(0.25)
    CT.pose = X.pose
    local t = X.tone
    if X.ground == "pale" then t = min(0.6, t + 0.22) end
    CT.t, CT.W = t, X.build / 2
    CT.ht, CT.jw = max(0.05, t - 0.16), max(0.1, 0.16 * u)
    CT.wa, CT.ph = range(3, 7), range(0, 360)
    ctspine()
    -- the leaf, and where on it the caterpillar sits, eating from its edge
    CT.hL, CT.hW, CT.hb, CT.hft = 1.5, 0.36, sym(0.12), 0.66
    local h, x = hfw(0.1)
    local ox, oy = x + h, 0.1 * CT.hL
    h, x = hfw(0.62)
    local a = atan2(0.62 * CT.hL - oy, x + h - ox)
    -- straight or looping, the body is mirrored across its axis (y to -y, after the turn),
    -- so its legs hold the edge and its back is turned away from the leaf, tail to head
    -- along the edge; curled, it lies on the leaf from its tail, its legs turned in
    local curled = CT.pose == "curl"
    local rot, hy = a, oy + CT.x[26] * sin(a) + CT.y[26] * cos(a)
    if not curled then
      rot = a + atan2(CT.y[26], CT.x[26])
      hy = oy + CT.x[26] * sin(rot) - CT.y[26] * cos(rot)
    end
    CT.nb = chance(0.5) and 3 or 2
    CT.br, CT.by, CT.bx = {}, {}, {}
    local y = min(0.86 * CT.hL, max(0.3 * CT.hL, hy + 0.04))
    for b = 1, CT.nb do
      CT.br[b], CT.by[b] = range(0.07, 0.11), y
      local hh, xx = hfw(y / CT.hL)
      CT.bx[b] = xx + hh + 0.3 * CT.br[b]
      y = y + range(0.15, 0.22)
      if y > K(1.38) then y = K(1.38) end
    end
    CT.l = hfoutline()
    hfpaint()
    if X.ground == "copper" then pen.accent = true end
    ink.push() ink.translate(ox, oy) ink.rotate(rot)
    if not curled then ink.scale(1, -1) end
    ctbody() cthead()
    if X.horn == 1 then cthorn() end
    if X.tufts == 1 then cttufts() end
    ink.pop()
  end

  -- ---------------------------------------------------------------- snails
  local GS = {}                             -- the one being drawn (\flo@gs...)
  local GSBODY = { { 0, -0.78 }, { -0.01, -0.3 }, { 0, 0.3 }, { 0.04, 0.58 }, { 0.12, 0.7 }, { 0.22, 0.66 }, { 0.24, 0.5 },
    { 0.2, 0.32 }, { 0.17, 0 }, { 0.12, -0.45 }, { 0.05, -0.7 } }
  -- \flo@gsbody: the foot, longer the farther it is out
  local function gsbody()
    local pts = {}
    for i, p in ipairs(GSBODY) do
      local x = p[1] * (1 + sym(0.08))
      pts[i] = { x, p[2] * (p[2] < 0 and 0.5 + 0.5 * GS.x or 0.75 + 0.3 * GS.x) }
    end
    local tb = range(0.5, 0.6)
    GS.tb = tb
    smooth(pts, true) fill(tone(tb), 1)
    smooth(pts, true) ink.clip()
    if fine then mottle(-0.1, -0.8, 0.3, 0.8, 5, 0.1, tb - 0.25, tb + 0.15, 10) end
    moveto(-0.05, -0.8) lineto(-0.05, 0.7) lineto(0.04, 0.7) lineto(0.04, -0.8) close() fill(tone(0.15), 0.35, true)
    smooth(pts, true) stroke(tone(0.08), 0.1 * GS.u * 28.3465, 0.4, true)
    ink.unclip()
  end
  -- \flo@gsfeeler: a feeler from (x0, y0) toward (x1, y1), w wide; its tip
  local function gsfeeler(x0, y0, x1, y1, w)
    local ya, t = y0 * (0.75 + 0.3 * GS.x), 0.55 + 0.5 * GS.x
    local xd, yd = x0 + (x1 - x0) * t, ya + (y1 - y0) * t
    moveto(x0, ya) curveto(x0 + 0.02, ya + 0.12, xd - 0.04, yd - 0.1, xd, yd) stroke(tone(0.12), w, 1, false)
    return xd, yd
  end
  -- \flo@gsfeelers: two long feelers with eyes, one short
  local function gsfeelers()
    local w, v = max(0.35, 0.3 * GS.u), max(0.28, 0.24 * GS.u)
    local x, y = gsfeeler(0.17, 0.66, 0.36, 1.02, w)
    circle(x, y, 0.028) fill(tone(0.05), 1)
    x, y = gsfeeler(0.1, 0.7, 0.18, 1.04, w)
    circle(x, y, 0.028) fill(tone(0.05), 1)
    gsfeeler(0.05, 0.68, 0, 0.84, v)
  end
  -- \flo@gsshell: the shell as Raup's coiled tube (the shells report, part A, steps 1-8). A
  -- ring 1 across the coil and S along it, y0 out from the coiling axis and x0 along it,
  -- sweeps through the whorls, W times larger a turn; seen from the spire's side, the axis
  -- tilted al toward the viewer, a ring shows as an ellipse whose two extremes across the
  -- coil are the whorl's edges there. The whorls are painted from the mouth in, each older one
  -- over the one after it, so its outer edge is the suture on the next. The spire leans back
  -- and the mouth faces the foot.
  local GSTEP = 18                          -- rings a whorl
  -- \flo@gsring: at growth angle th (0 the mouth) the ring's center and the offset from it to
  -- the whorl's outer edge (the inner edge is the other way), with the edge's wobble
  local function gsring(th)
    local lam = GS.W ^ (th / 360)
    local a = th + GS.ph
    local c, s = cos(a), sin(a)
    local u0, v0 = GS.y0 * c, GS.y0 * s * GS.ca - GS.x0 * GS.sa
    local tx, ty = GS.k * u0 - GS.y0 * s, GS.k * v0 + GS.y0 * c * GS.ca
    local l = sqrt(tx * tx + ty * ty)
    local p, q = (ty * c - tx * s * GS.ca) / l, -tx * GS.S * GS.sa / l
    local h = sqrt(p * p + q * q)
    local w = lam * (1 + 0.025 * sin(3 * a + GS.w1) + 0.018 * sin(5 * a + GS.w2)) / h
    return lam * u0, lam * v0, w * c * p, w * (s * GS.ca * p + GS.S * GS.sa * q), tx, ty, p / h, q / h
  end
  -- \flo@gswhorl: whorl j (1 the body whorl, ending at the mouth): its outer edge O, inner edge
  -- I, the outer edge of the whorl before it, which shows on this one as the suture (S), and
  -- the light on it (L, the outward normal toward the upper left of the page)
  local function gswhorl(j)
    local t0, t1 = max(-360 * GS.n, -360 * j), -360 * (j - 1)
    local O, I, U, L = {}, {}, {}, {}
    for b = 0, GSTEP do
      local th = t0 + (t1 - t0) * b / GSTEP
      local cx, cy, ex, ey, tx, ty = gsring(th)
      O[b + 1], I[b + 1] = { cx + ex, cy + ey }, { cx - ex, cy - ey }
      local sx, sy, fx, fy = gsring(th - 360)
      U[b + 1] = { sx + fx, sy + fy }
      local l = sqrt(tx * tx + ty * ty)
      L[b + 1] = (ty * GS.lx - tx * GS.ly) / l
    end
    return { O = O, I = I, S = U, L = L, t0 = t0, t1 = t1 }
  end
  -- the points f of the way from the suture to the outer edge, from b0 to b1
  local function gsacross(w, f, b0, b1)
    local pts = {}
    for b = b0, b1 do
      local o, q = w.O[b], w.S[b]
      pts[#pts + 1] = { q[1] + f * (o[1] - q[1]), q[2] + f * (o[2] - q[2]) }
    end
    return pts
  end
  local function gsshell()
    local W, n = X.expansion, X.whorls
    local D = X.opencoil == 1 and 1.15 / W or 0.03
    GS.W, GS.n, GS.S = W, n, X.aperture
    GS.y0 = (1 + D) / (1 - D)
    GS.x0 = 3 * X.spire / W * GS.y0           -- Raup's T: a fast-widening coil stands lower
    GS.k = math.log(W) / 6.28319
    local al = range(34, 50)
    GS.ca, GS.sa = cos(al), sin(al)
    GS.ph = -35
    GS.w1, GS.w2 = range(0, 360), range(0, 360)
    -- the light from the upper left of the page, in the shell's frame (turned by 130 degrees)
    GS.lx, GS.ly = cos(265), sin(265)
    local J = math.ceil(n)
    local whorls = {}
    for j = 1, J do whorls[j] = gswhorl(j) end
    -- the mouth: the ring at th = 0, an ellipse c + a1 cos f + a2 sin f (\flo@gsmouth); the
    -- body whorl's outer edge ends at f = fs, and its far side runs on in the direction of growth
    local mcx, mcy, _, _, mtx, mty, cp, sp = gsring(0)
    local a1x, a1y, a2y = cos(GS.ph), sin(GS.ph) * GS.ca, GS.S * GS.sa
    local function ring(f, k) return { mcx + k * cos(f) * a1x, mcy + k * (cos(f) * a1y + sin(f) * a2y) } end
    local fs = atan2(sp, cp)
    local dir = ((-a1x * sp) * mtx + (-a1y * sp + a2y * cp) * mty > 0) and 30 or -30
    local mouth = {}
    for b = 0, 11 do mouth[b + 1] = ring(30 * b, 1) end
    -- the frame: the spire toward -40 degrees on the page; the coil 0.98 across (a tall spire
    -- reaches farther, up to 1.4), centered where the shell has always been
    local x0, x1, y0, y1, u0, u1, v0, v1 = 1e9, -1e9, 1e9, -1e9, 1e9, -1e9, 1e9, -1e9
    local function bound(p)
      local x, y = p[1] * cos(-130) - p[2] * sin(-130), p[1] * sin(-130) + p[2] * cos(-130)
      x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
      u0, u1, v0, v1 = min(u0, p[1]), max(u1, p[1]), min(v0, p[2]), max(v1, p[2])
    end
    for j = 1, J do for _, p in ipairs(whorls[j].O) do bound(p) end end
    for _, p in ipairs(mouth) do bound(p) end
    local sc = 0.98 / max(u1 - u0, 0.7 * (v1 - v0))
    ink.push()
    ink.translate(0.4 - (x0 + x1) / 2 * sc, -0.03 - (y0 + y1) / 2 * sc)
    ink.rotate(-130) ink.scale(sc)
    local u = GS.u * sc                        -- cm on the page per unit of the shell's frame
    local lw = 0.06 * GS.u * 28.3465
    local tn = GS.tn
    for j = 1, J do
      local w = whorls[j]
      local poly = {}
      for b = 1, GSTEP + 1 do poly[b] = w.O[b] end
      if j == 1 then
        for b = 1, 5 do poly[#poly + 1] = ring(fs + dir * b, 1) end      -- the mouth's far side
      end
      for b = GSTEP + 1, 1, -1 do poly[#poly + 1] = w.I[b] end
      local size = (GS.y0 + 1) * GS.W ^ (-(j - 1)) * u          -- the whorl across, in cm
      local t = tn + sym(0.03)
      if size > K(0.02) then
        smooth(poly, true) fill(tone(t), 1)
        smooth(poly, true) ink.clip()
        local big = size > K(0.12)
        if big then
          -- a few blotches; the shadow under the suture; the light on the shoulder
          local bx0, bx1, by0, by1 = 1e9, -1e9, 1e9, -1e9
          for _, p in ipairs(poly) do bx0, bx1, by0, by1 = min(bx0, p[1]), max(bx1, p[1]), min(by0, p[2]), max(by1, p[2]) end
          if j <= 2 then mottle(bx0, by0, bx1, by1, fine and 4 or 2, 0.2 * (bx1 - bx0), t - 0.16, t + 0.2, fine and 6 or 0) end
          local sw = 0.0
          for b = 1, GSTEP + 1 do
            local o, q = w.O[b], w.S[b]
            sw = sw + sqrt((o[1] - q[1]) ^ 2 + (o[2] - q[2]) ^ 2)
          end
          sw = sw / (GSTEP + 1)                                     -- the band's visible width
          streak(w.S, sw * (0.15 + 0.3 * X.suture), sw * (0.15 + 0.3 * X.suture), tone(0.08), 0.12 + 0.2 * X.suture)
          local b0, b1 = nil, nil
          for b = 1, GSTEP + 1 do
            if w.L[b] > K(0.15) then b0 = b0 or b b1 = b end
          end
          if j <= 3 and b0 and b1 - b0 >= 3 then
            streak(gsacross(w, 0.62, b0, b1), sw * 0.06, sw * 0.24, WHITE, j == 1 and 0.6 or 0.42)
          end
          -- color bands along the body whorl and the one before it
          if j <= 2 and X.shellbands > 0 then
            for a = 1, X.shellbands do
              streak(gsacross(w, 0.15 + 0.7 * a / (X.shellbands + 1), 1, GSTEP + 1), 0.003, sw * 0.7 / (X.shellbands + 1), tone(0.06), 0.38)
            end
          end
          -- sculpture: ribs across the whorl where they stand 0.5 mm apart, or cords along it
          if X.sculpture == "ribs" and X.ribs > 0 and size * 3.14159 / X.ribs > K(0.05) then
            local nr = j < J and X.ribs or floor(X.ribs * (w.t1 - w.t0) / 360 + 0.5)
            for r = 1, nr do
              local bb = 1 + nediv(GSTEP * (2 * r - 1), 2 * nr)
              local o, q = w.O[bb], w.S[bb]
              moveto(q[1], q[2]) lineto(o[1], o[2]) stroke(tone(0.05), 0.25 * lw, 0.3, true)
            end
          elseif X.sculpture == "cords" and size > K(0.25) then
            for a = 1, 3 do
              smooth(gsacross(w, a / 4, 1, GSTEP + 1), false) stroke(tone(0.05), 0.3 * lw, 0.35, true)
            end
          end
          -- growth lines near the mouth, parallel to its lip
          if j == 1 and fine then
            for g = 1, 3 do
              local bb = GSTEP + 1 - g - (chance(0.375) and 1 or 0)
              local o, q = w.O[bb], w.S[bb]
              moveto(q[1], q[2]) lineto(o[1], o[2]) stroke(tone(0.1), 0.3 * lw, 0.18, true)
            end
          end
        end
        smooth(w.O, false) stroke(tone(0.05), lw, 0.55, true)
        ink.unclip()
      end
      if j == 1 then
        -- the mouth: the snail's body in it, or the pale seal of one withdrawn; the lip
        local inner = {}
        for b = 1, 12 do inner[b] = { mcx + 0.7 * (mouth[b][1] - mcx), mcy + 0.7 * (mouth[b][2] - mcy) } end
        smooth(inner, true)
        if X.withdrawn == 1 then fill(plain(0.9), 0.95) else fill(plain(GS.tb - 0.18), 1) end
        smooth(inner, true) stroke(tone(0.05), 0.7 * lw, 0.55, true)
        if X.lip == 1 then
          local lip = {}
          for b = 0, 6 do lip[b + 1] = ring(fs + dir * b, 0.9) end
          streak(lip, 0.03, 0.06, WHITE, 0.8)
        end
      end
    end
    ink.pop()
  end
  -- \flo@snail: a snail, its shell 1 wide; u the shell's width on the page in cm. A snail
  -- withdrawn into its shell shows no foot and no feelers
  local function snail(u)
    GS.u = u
    fine = u > K(0.25)
    GS.x = X.extension
    local tn = X.tone - 0.06
    if X.ground == "pale" then tn = min(0.72, tn + 0.25) end
    GS.tn = tn
    GS.tb = 0.55
    ink.push()
    if X.hand == "sinistral" then xscale(-1) end
    local was = pen.accent
    pen.accent = false
    if X.withdrawn == 0 then gsbody() gsfeelers() end
    pen.accent = was
    if X.ground == "copper" then pen.accent = true end
    gsshell()
    ink.pop()
  end

  -- ---------------------------------------------------------------- birds
  local AV = {}                             -- the one being drawn (\flo@av...)
  local AVF = { 0.12, 0.35, 0.6, 0.82, 0.95 }
  -- \flo@avfeather: a tail feather len long, along +y
  local function avfeather(len)
    local pts = { { 0, 0 } }
    pts[7] = { 0, len }
    for b = 1, 5 do
      local v = AVF[b]
      local x = 0.055 * sin(180 * v ^ 0.4) ^ 0.6
      pts[b + 1], pts[13 - b] = { x, v * len }, { -x, v * len }
    end
    return pts
  end
  local AVBODY = { { 0.37, 0.56 }, { 0.3, 0.665 }, { 0.15, 0.64 }, { -0.03, 0.54 }, { -0.22, 0.4 }, { -0.31, 0.3 }, { -0.27, 0.22 },
    { -0.08, 0.12 }, { 0.12, 0.12 }, { 0.27, 0.27 }, { 0.35, 0.42 } }
  -- \flo@avbody: the tail's four feathers fanned, the body, its breast, mottle, a nectar
  -- bird's bright throat or a seed-eater's streaks, the cap, the rim
  local function avbody()
    AV.lw = max(0.3, 0.3 * AV.u)
    for a = 1, 4 do
      local len = range(X.tail - 0.03, X.tail + 0.03)
      local ang = range(-150, -140) + AV.fan * a - 90
      ink.push() ink.translate(-0.26, 0.28) ink.rotate(ang)
      local f = avfeather(len)
      smooth(f, true) fill(tone(0.12 + 0.05 * a), 1)
      smooth(f, true) stroke(tone(0.05), AV.lw, 0.5, false)
      ink.pop()
    end
    local b = {}
    for i, p in ipairs(AVBODY) do
      local x = p[1] + sym(0.012)
      b[i] = { x, p[2] + sym(0.012) }
    end
    local t = AV.t
    smooth(b, true) fill(tone(t), 1)
    smooth(b, true) ink.clip()
    for a = 1, 4 do smooth(blob(0.17, 0.27, 0.08 + 0.04 * a, 0.06 + 0.03 * a, 0.2, 9), true) fill(WHITE, 0.2) end
    if fine then mottle(-0.35, 0.1, 0.4, 0.7, 10, 0.07, t - 0.2, t + 0.2, 10)
    else mottle(-0.35, 0.1, 0.4, 0.7, 4, 0.07, t - 0.2, t + 0.2, 0) end
    if X.kind == "hummingbird" then
      smooth(blob(0.3, 0.47, 0.075, 0.05, 0.15, 8), true) fill(accent(0), 0.85)
      if fine then smooth(blob(0.31, 0.49, 0.03, 0.016, 0.2, 7), true) fill(WHITE, 0.5) end
    elseif fine then
      for _ = 1, 14 do
        local x, y, a = range(0.08, 0.3), range(0.16, 0.42), range(-20, 20)
        ellipse(x, y, 0.012 * cos(a), 0.012 * sin(a), -0.022 * sin(a), 0.022 * cos(a))
      end
      fill(tone(0.1), 0.7)
    end
    smooth(blob(0.24, 0.66, 0.15, 0.08, 0.1, 9), true) fill(tone(0.08), 0.6, true)
    smooth(b, true) stroke(tone(0.05), 0.07 * AV.u * 28.3465, 0.5, true)
    ink.unclip()
  end
  local AVWING = { { 0.17, 0.47 }, { 0.04, 0.52 }, { -0.12, 0.45 }, { -0.28, 0.33 }, { -0.44, 0.22 }, { -0.35, 0.23 },
    { -0.38, 0.19 }, { -0.26, 0.21 }, { -0.28, 0.17 }, { -0.12, 0.23 }, { 0.05, 0.31 }, { 0.15, 0.4 } }
  -- \flo@avwing: the folded wing, mottled, its flight feathers lifted out
  local function avwing()
    local tw = AV.t - 0.1
    smooth(AVWING, true, 0.8) fill(tone(tw), 1)
    smooth(AVWING, true, 0.8) ink.clip()
    mottle(-0.45, 0.15, 0.2, 0.6, fine and 6 or 3, 0.07, tw - 0.15, tw + 0.2, 0)
    for a = 1, 5 do
      local y = 0.28 + 0.04 * a
      local op = range(0.45, 0.7)
      taper(0.12, y + 0.05, 0, y + 0.03, -0.15, y - 0.03, -0.3 - 0.02 * a, y - 0.1 - 0.01 * a, 0.025, 0.003) fill(WHITE, op)
    end
    smooth(AVWING, true, 0.8) stroke(tone(0.04), 0.06 * AV.u * 28.3465, 0.5, true)
    ink.unclip()
  end
  local AVHOVER = { { 0, 0.02 }, { 0.12, 0.07 }, { 0.32, 0.085 }, { 0.5, 0.05 }, { 0.56, 0 }, { 0.48, -0.03 }, { 0.28, -0.045 },
    { 0.08, -0.03 } }
  -- \flo@avhover: a hovering bird's wing, a blur in three places
  local function avhover()
    local tw = AV.t - 0.1
    for a = 1, 3 do
      ink.push() ink.translate(0.06, 0.5) ink.rotate(70 + 25 * a)
      if a == 2 then
        smooth(AVHOVER, true) fill(tone(tw), 0.4)
        smooth(AVHOVER, true) stroke(tone(0.05), AV.lw, 0.4, false)
      else smooth(AVHOVER, true) fill(tone(tw), 0.18) end
      ink.pop()
    end
  end
  -- \flo@avcrest
  local function avcrest()
    for a = 1, 4 do
      local len = range(0.08, 0.12)
      local x, y, t = 0.26 - 0.04 * a, 0.65 - 0.01 * a, 140 + 8 * a
      seg(x, y, x + len * cos(t), y + len * sin(t), 0.03, 0.004)
    end
    fill(tone(0.1), 1)
  end
  -- \flo@avbill: a seed-eater's cone, a nectar bird's straight or curved one
  local function avbill()
    local b, c = X.bill, tone(0.05)
    if b == "conical" then
      moveto(0.355, 0.585) lineto(0.47, 0.545) lineto(0.36, 0.51) close() fill(c, 1)
      moveto(0.36, 0.548) lineto(0.45, 0.546) stroke(WHITE, 0.2, 0.6, false)
    end
    if b == "straight" then moveto(0.35, 0.575) lineto(0.69, 0.55) lineto(0.352, 0.538) close() fill(c, 1) end
    if b == "curved" then taper(0.35, 0.556, 0.46, 0.562, 0.58, 0.535, 0.66, 0.475, 0.036, 0.006) fill(c, 1) end
  end
  -- \flo@bird: a bird, length 1; u its length on the page in cm
  local function bird(u)
    AV.u = u
    fine = u > K(0.3)
    local t = X.tone
    if X.ground == "dark" then t = t - 0.12 end
    if X.ground == "copper" then pen.accent = true end
    AV.t, AV.fan = t, 7
    local hover = X.pose == "hover"
    ink.push()
    if hover then
      AV.fan = 14
      ink.translate(0.05, 0.35) ink.rotate(22) ink.translate(-0.05, -0.35)
    end
    avbody()
    if X.crest == 1 then avcrest() end
    if hover then avhover() else avwing() end
    avbill()
    circle(0.285, 0.585, 0.03) fill(WHITE, 0.95)
    circle(0.29, 0.585, 0.018) fill(tone(0.03), 1)
    circle(0.284, 0.592, 0.006) fill(WHITE, 1)
    if not hover then                                             -- the feet on the perch
      moveto(0.02, 0.14) lineto(0, 0) moveto(-0.05, 0) lineto(0.05, 0.005)
      moveto(0.1, 0.14) lineto(0.08, 0) moveto(0.03, 0) lineto(0.13, 0.005)
      stroke(tone(0.06), max(0.4, 0.3 * u), 1, false)
    end
    ink.pop()
  end

  -- ---------------------------------------------------------------- the visitor
  -- \flo@visitor as the margin's organ: the size in cm (the wingspan of a butterfly or
  -- moth), as TeX holds it; the visitor's unit on the page in cm is found as TeX finds it
  -- (the size in pt, then divided back), since it decides the level of detail. With pic
  -- (the pic's \flo@visitor), o.size is in pt already, in sp, the drawing in pt, and
  -- o.draw (if given) is the drawing's seed, as \flo@vispicsetup takes it
  local DRAW = { bee = bee, fly = bee, odonate = odo, beetle = beetle, larva = caterpillar, snail = snail, bird = bird }
  local HALFCM = pm.sp("56.90552")              -- half a wingspan: pt in two cm, as TeX holds it
  local sampled = {}
  return function(o, pic)
    local role = o.role or "any"
    local key = string.format("%d/%s/%s", o.seed, role, o.traits or "")
    X = sampled[key]
    if not X then
      -- \florilegiumvisitor: its traits (some fixed), the reals held to the scaled point
      X = {}
      for k, v in pairs(species.vsample(o.seed, role, nil, o.traits and species.fixes(o.traits, true))) do
        X[k] = math.type(v) == "float" and K(v) or v
      end
      sampled[key] = X
    end
    local d = pic and o.draw or (o.seed == 2147483646 and 1 or o.seed + 1)   -- drawn from seed + 1
    G = ink.pgfrng(1) G.load(d) G.step() G.step()
    local pt, k = o.size, o.size / 65536
    if not pic then pt, k = pm.mulf(floor(o.size * 65536 + 0.5), CM), o.size end    -- size*28.45276
    if X.group == "lepidoptera" then
      ink.scale(k / 2)
      lepid(pm.div(pt, HALFCM) / 65536)                                            -- (pt)/56.90552
    else
      ink.scale(k)
      DRAW[X.group](pm.div(pt, CM) / 65536)                                        -- (pt)/28.45276
    end
  end
end)()

-- ================================================================ organs
-- the layout's questions, in cm: the disc an inflorescence at scale k fills (its center's
-- offset along the axis, its radius, its kind), and how much later than the top one at
-- height h (0..1) opens
local KIND = { solitary = "solitary", cumbel = "umbel", umbel = "umbel", corymb = "umbel", dichasium = "umbel",
  raceme = "raceme", spike = "raceme", panicle = "raceme", thyrse = "raceme", monochasium = "raceme",
  head = "head", catkin = "catkin" }
function M.unitdisc(s, k)
  local kind = KIND[s.inflo] or "blossoms"
  local fd = min(2.8, 0.7 + 0.032 * s.size) * k
  if kind == "umbel" then return 0.69 * k, 0.86 * k, kind end
  if kind == "raceme" then return 0.95 * k, 0.75 * k, kind end
  if kind == "blossoms" then return 0.5 * fd, 0.8 * fd, kind end
  if kind == "head" then return 0.8 * k, 0.5 * k, kind end
  if kind == "catkin" then return 0.2 * k, 0.9 * k, kind end
  return 0, 0.5 * fd, kind
end
-- whether its flowers are seen in profile (bells, urns, tubes, trumpets, pea and two-lipped
-- flowers, a columbine held sideways): they reach out from the stalk, not round it
function M.profile(s)
  local fm = s.form
  return TUBES[fm] or fm == "papilionaceous" or fm == "bilabiate" or fm == "spurred" and s.orient ~= "erect" or false
end
local BELOW = { raceme = true, spike = true, catkin = true }
function M.lateness(s, h) return BELOW[s.inflo] and 0.4 * h or 0.4 * (1 - h) end

-- a species given by seed and role only (and traits fixed, "compound=palmate, ...") is
-- sampled (once)
local species = require("florilegium-species")
local sampled = {}
local function full(s)
  if s.plan then return s end
  local key = s.seed .. "/" .. s.role .. "/" .. (s.traits or "")
  if not sampled[key] then sampled[key] = species.sample(s.seed, s.role, nil, s.traits and species.fixes(s.traits)) end
  return sampled[key]
end
-- One organ of species s (a table from florilegium-species, or just its seed and role),
-- drawn from pgf seed z at the origin with its axis along +y, in cm, under ink's current
-- transform. o by kind:
--   unit     k (scale), season, late: the inflorescence
--   budding  k: buds on stalks       tendril  size     bloom  d (diameter cm), stage
--   ghost    d: a plain pale flower of the species, as the garden's ghost
--   leaf     len (cm), bend, lc (0..1, the autumn draw), season, fore (a foreshortening),
--            sheath ({direction from the leaf's in degrees, width in the leaf's units})
--   frond    len (cm), unroll (0..1), arch (degrees), fertile, under, lc, season: a fern's
--   visitor  seed, role, size (cm; a wingspan for butterflies and moths): the visitor
--            \florilegiumvisitor{seed}{role} samples, drawn from seed + 1 (s and z unused)
-- Returns false for a kind not drawn here.
local DRAWN = { unit = true, budding = true, tendril = true, bloom = true, ghost = true, leaf = true, frond = true,
  visitor = true }
-- the organ's numbers as TeX holds them, in whole scaled points (K): a length the layout
-- caps at 19/16 cm then gives the library's count of teeth, not one less
local function held(o)
  local h = {}
  for k, v in pairs(o) do
    if type(v) == "number" then h[k] = K(v)
    elseif type(v) == "table" then h[k] = { K(v[1]), K(v[2]) }
    else h[k] = v end
  end
  return h
end
-- a ghost: a plain rotate flower of the species, d cm across (no more than five petals),
-- in the pale the caller set; the margin's ghost and the plants pic's
local function ghostflower(d)
  local tq = stone()
  local g = {}
  for k, v in pairs(S) do g[k] = v end
  g.form = "rotate"
  if g.merosity > 6 then g.merosity = 5 end
  S = g
  ink.scale(d)
  M.sflower(d * 28.45276, { tone = tq, notchp = 0.4, notchk = 1 })
end
function M.draw(kind, s, z, o)
  if not DRAWN[kind] then return false end
  o = held(o)
  if kind == "visitor" then
    M.fresh()
    pen.lift, pen.accent = 0, false
    ink.push() visitor(o) ink.pop()
    pen.accent = false
    return true
  end
  S = full(s)
  G = ink.pgfrng(z) G.step() G.step()             -- \flo@drawseed
  M.fresh()
  pen.lift, pen.accent = 0, false
  ink.push()
  if kind == "unit" then
    local st = 1.2 * o.season - o.late + sym(0.08) + S.phenology
    M.unit(o.k, st)
  elseif kind == "budding" then
    M.budding(min(1.1, fdiam(o.k)))
  elseif kind == "tendril" then
    ink.rotate(90) M.tendril(o.size)
  elseif kind == "bloom" then
    M.bloom(o.d, o.stage, {})
  elseif kind == "leaf" or kind == "frond" then
    ink.scale(o.len)
    if o.fore then yscale(o.fore) end
    -- autumn turns some leaves copper; a spring leaf is young and pale
    if S.turns == 1 and o.lc < max(0, o.season - 0.9) then pen.accent = true end
    if o.season < 0.5 then pen.lift = 0.3 * (1 - o.season / 0.5) end
    if kind == "leaf" then M.leaf(o.len, o.bend, o.sheath)
    else M.frond(leafu(o.len), { unroll = o.unroll, arch = o.arch, fertile = o.fertile, under = o.under }) end
  else                                            -- the ghost: a plain rotate flower, pale
    pen.lift = 0.62
    ghostflower(o.d)
  end
  ink.pop()
  return true
end

-- ================================================================ M8f7: the pics
-- The TikZ library's pics, drawn here as its TikZ code draws them: v1.3's leaf
-- (\flo@vleaf), a fern's crown (\flo@ferncrown), the garden of v1.3's plants (\flo@garden)
-- and the pics that wrap them and the organs above. In a function of its own, whose locals
-- count afresh (the main chunk's 200).
local pic = (function()
  -- \flo@calc{x/28.45276}: a pic's length in pt (sp) in cm, as TeX divides it
  local function sizecm(pt) return pm.div(pt, CM) / 65536 end
  -- a count TeX takes from a length the user gives (a 6 cm plant's \flo@pH, held in sp),
  -- which sits on the count's thresholds: int(x/d + a), d and a in sp, as pgfmath finds it
  local function texint(x, d, a)
    return pm.int(pm.add(pm.div(floor(x * 65536 + 0.5), d), a or 0)) // 65536
  end
  local function drawseed(z) G = ink.pgfrng(1) G.load(z) G.step() G.step() end   -- \flo@drawseed

  -- ---------------------------------------------------------------- one stream per organ
  local HALF = 1073741823
  -- \flo@seedorgan: the layout's generator a step on; the organ's own seed from there
  local function seedorgan()
    G.step()
    local z = G.save()
    return z > HALF and z - HALF or z + HALF
  end
  -- \flo@organ: f drawn from seed z in a group of its own (the pen as it was after it), the
  -- layout's generator where it was
  local function organ(z, f)
    local saved, lift, acc = G.save(), pen.lift, pen.accent
    G.load(z) G.step() G.step()
    ink.push() f() ink.pop()
    pen.lift, pen.accent = lift, acc
    G.load(saved)
  end
  -- \flo@autumnleaf: copper in autumn (lc the leaf's draw), young and pale in spring
  local function autumnleaf(lc, season)
    if S.turns == 1 and lc < max(0, season - K(0.9)) then pen.accent = true end
    if season < K(0.5) then pen.lift = 0.3 * (1 - season / 0.5) end
  end

  -- ---------------------------------------------------------------- v1.3's leaf
  -- \flo@vleaf: flora.leaf along +y, length 1, its width, bend, lobes, their depth and its
  -- tone all drawn; u its cm per unit
  local function vleaf(u)
    local lW = range(0.20, 0.27)
    local lbend = sym(0.25)
    local lobes = int(3, 5)
    local depth = range(0.3, 0.7)
    local lt = range(0.26, 0.38)
    local fine, bn = false, 24
    if u > K(0.6) then fine, bn = true, 36 end
    local bodyw, ent = 1, true
    if depth > 0 then bodyw, ent = 1 - 0.75 * depth, false end
    local function spine(v) return lbend * v * v - 0.3 * lbend * v, v end              -- \flo@lspine
    -- \flo@lenv, in pgfmath's own pow, as the fronds' pinnae are placed: it is 2% off near
    -- 1 - v = 0.13, where it sets a top lobe's reach (0.3 bp on a 4 cm leaf)
    local function env(v)
      if v > 0 and v < 1 then return lW * 2.3 * ppow(v, 0.55) * ppow(1 - v, 0.95) end
      return 0
    end
    local function teeth(v) return 0.006 * (1 - abs(2 * (v * 9 - floor(v * 9)) - 1)) end   -- \flo@lteeth
    local function tangent(v)                                                         -- \flo@ltan
      local ax, ay = spine(max(0, v - 0.01))
      local bx, by = spine(min(1, v + 0.01))
      local dx, dy = bx - ax, by - ay
      local l = sqrt(dx * dx + dy * dy)
      return dx / l, dy / l
    end
    -- the body: a blade along the spine, toothed when it has no lobes
    local ps = {}
    for k = 0, bn do ps[k + 1] = { spine(k / bn) } end
    local body = blade(ps, function(_, v) return max(0, env(v) * bodyw + (ent and teeth(v * 3) or 0)) end)
    local shapes, veins = { body }, {}
    -- the lobes, grown out of the body along the spine
    if depth > 0 then
      for kc = 0, 1 do
        local side = kc == 0 and -1 or 1
        for ka = 1, lobes do
          local lv = 0.1 + 0.72 * (ka - (side > 0 and 0.25 or 0.75)) / lobes
          local lx, ly = spine(lv)
          local tx, ty = tangent(lv)
          local reach = env(min(0.95, lv + 0.08)) * range(0.95, 1.15)
          local ang = range(38, 58)
          local c, sn = cos(ang), sin(ang) * side
          local dx, dy = tx * c - ty * sn, tx * sn + ty * c
          local L = reach / sin(ang) * 0.95
          local lb = sym(0.25) - side * 0.15
          local function at(t) return lx + dx * L * t - dy * lb * L * t * t, ly + dy * L * t + dx * lb * L * t * t end
          local lp = {}
          for k = 0, 11 do lp[k + 1] = { at(k / 11) } end
          local ln = normals(lp)
          local ll, lr = {}, {}
          for k = 0, 11 do
            local v = k / 11
            local e = v > 0.2 and teeth(v * 1.4 + ka) * L * 4 or 0
            local g = v > 0 and max(0, sin(180 * v ^ 0.62)) ^ 0.75 or 0
            local wa = max(0, L * range(0.26, 0.3) * g + e)
            local wb = max(0, L * range(0.26, 0.3) * g + e)
            local p, q = lp[k + 1], ln[k + 1]
            ll[k + 1] = { p[1] + q[1] * wa, p[2] + q[2] * wa }
            lr[k + 1] = { p[1] - q[1] * wb, p[2] - q[2] * wb }
          end
          -- the lobe's vein: the base, the middle and the end of its spine
          local mx, my = at(0.45)
          local ex, ey = at(0.92)
          veins[#veins + 1] = { lx, ly, mx, my, ex, ey }
          for k = 11, 2, -1 do ll[#ll + 1] = lr[k] end
          shapes[#shapes + 1] = ll
        end
      end
    end
    local function trace() for _, s in ipairs(shapes) do smooth(s, true, 0.8) end end
    trace() fill(tone(lt), 1)
    trace() ink.clip()
    -- the darker half
    local sd = chance(0.5) and 1 or -1
    for k = 0, 30 do
      local x, y = spine(k / 30)
      if k == 0 then moveto(x, y) else lineto(x, y) end
    end
    lineto(sd * 2, 1) lineto(sd * 2, 0) close()
    fill(tone(0.12), 0.28, true)
    if fine then mottle(-lW * 2.5, 0, lW * 2.5, 1, 13, 0.11, lt - 0.2, lt + 0.22, 12, true)
    else mottle(-lW * 2.5, 0, lW * 2.5, 1, 6, 0.11, lt - 0.2, lt + 0.22, 0, true) end
    trace() stroke(tone(0.06), 1.3 * u, 0.22, true)
    -- midrib and veins in white
    local mid = {}
    for k = 0, 10 do mid[k + 1] = { spine(k / 10) } end
    streak(mid, 0.03, 0.003, WHITE, 0.78)
    for _, v in ipairs(veins) do
      local op = range(0.5, 0.75)
      taper(v[1], v[2], v[3], v[4], v[3] + (v[5] - v[3]) * 0.5, v[4] + (v[6] - v[4]) * 0.5, v[5], v[6], 0.017, 0.002)
      fill(WHITE, op)
    end
    if #veins == 0 then
      for ka = 1, 9 do
        local v = (ka - 0.3) / 10 * 0.9
        local sg = ka % 2 == 1 and -1 or 1
        local lx, ly = spine(v)
        local tx, ty = tangent(v)
        local nx, ny = -ty * sg, tx * sg
        local L = env(v) * bodyw * range(0.75, 0.95)
        local op = range(0.45, 0.7)
        taper(lx, ly, lx + nx * L * 0.4, ly + ny * L * 0.4, lx + nx * L * 0.75 + tx * L * 0.3, ly + ny * L * 0.75 + ty * L * 0.3,
          lx + nx * L * 0.95 + tx * L * 0.6, ly + ny * L * 0.95 + ty * L * 0.6, 0.014, 0.002)
        fill(WHITE, op)
      end
    end
    ink.unclip()
    if ent then smooth(body, true, 0.8) stroke(tone(0.05), 0.18, 0.4, false) end
  end

  -- ---------------------------------------------------------------- a fern's crown
  -- \flo@ferncrown: three to five fronds from a crown at the origin, the longest gH cm, and a
  -- dimorphic fern's fertile one from late spring; in cm
  local function ferncrown(gH, season)
    ink.scale(28.45276)
    local nf = int(3, 5)
    for ga = 1, nf do
      local f = (ga - (nf + 1) / 2) / ((nf - 1) / 2)
      local la = 90 - 44 * f + sym(8)
      local ac = (f < 0 and 1 or -1) * (20 + 70 * S.curl) * range(0.8, 1.2) * (0.4 + 0.6 * abs(f))
      local ll = gH * (1 - 0.22 * abs(f)) * range(0.85, 1)
      local un = max(0, min(1, (season - 0.1 - S.phenology - range(0, 0.3)) / 0.4))
      local uf = chance(0.4)
      local lc = G.rnd()
      organ(seedorgan(), function()
        local under = false
        if un >= K(0.97) then under = uf end
        ink.translate(0.06 * f, 0) ink.rotate(la - 90) ink.scale(ll)
        autumnleaf(lc, season)
        M.frond(leafu(ll), { unroll = un, arch = ac, fertile = false, under = under })
      end)
    end
    if S.dimorphic == 1 and season > K(0.55) then
      local la = 90 + sym(6)
      local ac = sym(12)
      local ll = gH * range(0.55, 0.7)
      organ(seedorgan(), function()
        ink.rotate(la - 90) ink.scale(ll)
        M.frond(leafu(ll), { unroll = 1, arch = ac, fertile = true, under = false })
      end)
    end
  end

  -- ---------------------------------------------------------------- the garden
  -- its macros (R.pH is \flo@pH ...), shared as TeX shares them; the 5 mm cells taken on
  -- this layer's walk, and the layer
  local R, ROOM, layer
  local LSTEM, LLEAF, LAIRY, LBLOOM = 2, 3, 4, 5
  local function at(l) return layer == l end
  -- \flo@room: the 5 mm cells whose centers lie in the disc, marked (mark) or counted: how
  -- many are taken, of how many
  local function room(mark, x, y, r)
    local ox, oy, o = floor(x * 10 + 1000), floor(y * 10 + 1000), floor(max(3, r * 10))
    local n, t = 0, 0
    for i = nediv(ox - o - 2, 5), nediv(ox + o - 2, 5) do
      for j = nediv(oy - o - 2, 5), nediv(oy + o - 2, 5) do
        local dx, dy = 5 * i + 2 - ox, 5 * j + 2 - oy
        if dx * dx + dy * dy <= o * o then
          local key = i * 65536 + j
          if mark then ROOM[key] = true
          else
            t = t + 1
            if ROOM[key] then n = n + 1 end
          end
        end
      end
    end
    return n, t
  end
  -- \flo@takenat: the share of the disc's cells taken, divided as TeX divides
  local function takenat(x, y, r)
    local n, t = room(false, x, y, r)
    if t == 0 then return 0 end
    return (n * 65536 // t) / 65536
  end
  -- \flo@stemx: the main stem's x at height h
  local function stemx(h)
    local sb = min(1, max(0, h / 3))
    return R.root + sb * sb * (3 - 2 * sb) * (R.pc - R.root + R.pA * (0.62 * sin(360 * h / R.plam + R.pph)
      + 0.38 * sin(766.8 * h / R.plam + R.pps)))
  end
  -- \flo@stemtan: its tangent at h, and its x
  local function stemtan(h)
    local xa, xb = stemx(h + 0.05), stemx(h - 0.05)
    local t = sqrt((xa - xb) * (xa - xb) + 0.01)
    return (xa - xb) / t, 0.1 / t, stemx(h)
  end
  -- \flo@drawstem, \flo@markstem
  local function drawstem()
    local n = max(2, texint(R.pH, pm.sp("0.25"), 65536))   -- two points at least, under 2.5 mm
    local pts = {}
    for k = 1, n do
      local y = R.pH * (k - 1) / (n - 1)
      pts[k] = { stemx(y), y }
    end
    stem(pts, R.pw, 0.028, 0.07)
  end
  local function markstem()
    for k = 1, texint(R.pH, pm.sp("0.6")) do
      local y = 0.6 * k - 0.3
      room(true, stemx(y), y, 0.2)
    end
  end
  -- \flo@unit: the species' inflorescence at (x, y) along ax, scale k, late later than the
  -- top one: its room marked on every walk, drawn on its layer
  local function unit(x, y, ax, k, late)
    local uo, udr, kind = M.unitdisc(S, k)
    room(true, x + uo * cos(ax), y + uo * sin(ax), 0.85 * udr)
    local st = 1.2 * R.season - late + sym(0.08) + S.phenology
    local z = seedorgan()
    if at((kind == "umbel" or kind == "raceme") and LAIRY or LBLOOM) then
      organ(z, function() ink.translate(x, y) ink.rotate(ax - 90) M.unit(k, st) end)
    end
  end
  -- \flo@plantsetup: plant ga's place, stem, species and generator; \flo@stemload
  local function plantsetup(ga)
    R.root, R.pc = (ga - 2) * 0.25, (ga - 2) * 0.35
    if R.Np == 1 then R.root, R.pc = 0, 0 end
    R.pw = ga == 1 and 0.085 or 0.065
    R.pH = R.H[ga]
    S = full({ seed = R.s[ga], role = R.r[ga], traits = R.traits })
    G.load(R.w[ga])
  end
  local function stemload(ga) local f = R.f[ga] R.pph, R.pps, R.plam = f[1], f[2], f[3] end
  -- \flo@passstem: the stem's wave, its room, the stem, the top inflorescence
  local function passstem(ga)
    R.pph = range(0, 360) R.pps = range(0, 360) R.plam = range(5, 8)
    R.f[ga] = { R.pph, R.pps, R.plam }
    markstem()
    if at(LSTEM) then drawstem() end
    local top = M.lateness(S, 1)
    local tx, ty, sx = stemtan(R.pH)
    unit(sx, R.pH, atan2(ty, tx), K(1.15), top)
  end
  -- \flo@leafcof: a broad leaf's length factor
  local function leafcof()
    if S.compound == "simple" then R.leafc = min(1.45, max(1, sqrt(S.leafaspect / 2.2))) else R.leafc = K(1.35) end
  end
  -- \flo@nodeat: the stem at height R.ny: x, tangent, its angle, width, height on the plant
  local function nodeat()
    R.nyy = R.ny R.u = R.nyy / R.pH
    R.ntx, R.nty, R.nx = stemtan(R.nyy)
    R.ta = atan2(R.nty, R.ntx)
    R.nw = R.pw + (0.028 - R.pw) * R.u
  end
  -- \flo@placeleaf: a leaf at R.la degrees, R.lf cm, or shorter where its room is taken
  -- (three tries), or none; z its seed
  local function placeleaf(x, y, z)
    local ok = false
    for _ = 1, 3 do
      if not ok then
        local mx, my = x + cos(R.la) * R.lf * R.fore * 0.55, y + sin(R.la) * R.lf * R.fore * 0.55
        if takenat(mx, my, 0.24 * R.lf) < K(0.2) then ok = true else R.lf = 0.75 * R.lf end
      end
    end
    if R.lf < K(0.45) then ok = false end
    if ok then
      for d = 1, 3 do
        local t = (0.05 + 0.25 * d) * R.lf * R.fore
        room(true, x + cos(R.la) * t, y + sin(R.la) * t, 0.2 * R.lf)
      end
      if at(LLEAF) then
        local la, lf, fore, lc, bend = R.la, R.lf, R.fore, R.lc, R.sbend
        local sheath = R.lsd and { R.lsd, 1.8 * R.nw / lf }
        organ(z, function()
          ink.translate(x, y) ink.rotate(la - 90) ink.scale(lf)
          if fore < 1 then yscale(fore) end
          autumnleaf(lc, R.season)
          M.leaf(lf, bend, sheath)
        end)
      end
    end
    R.fore, R.lsd = 1, nil
  end
  -- \flo@nodeleaves: the leaves at a node (one, a pair or a whorl of three), the node kept
  local function nodeleaves(ga)
    nodeat()
    R.side = -R.side
    R.nd[ga][R.Ge] = { R.nyy, R.side }
    for b = 1, R.per do
      local ls = b == 2 and -R.side or R.side
      local t = range(35, 60)
      if b == 3 then t = range(8, 20) end
      -- decussate: every other opposite pair close to the stem, foreshortened
      if R.per == 2 and R.Ge % 2 == 0 then t, R.fore = 0.55 * t, K(0.55) end
      R.la = R.ta + ls * t
      R.lsd = R.ta - R.la
      R.lf = 2.6 * (1 - (1 - S.taper) * R.u) * range(0.85, 1.1) * R.leafk * R.leafc * (b == 3 and 0.7 or 1)
      R.sbend = ls * range(0.05, 0.3)
      R.lc = G.rnd()
      placeleaf(R.nx, R.nyy, seedorgan())
    end
  end
  -- \flo@nodes, \flo@rosette, \flo@eudicotleaves, \flo@monocotleaves, \flo@passleaves
  local function nodes(ga)
    while R.ny < R.nlast do
      R.Ge = R.Ge + 1 nodeleaves(ga)
      R.ny = R.ny + range(1.2, 1.9) * R.gap
    end
  end
  local function rosette()
    local nb = int(3, 5)
    for b = 1, nb do
      local f = (b - (nb + 1) / 2) / max(1, (nb - 1) / 2)
      R.la = 90 - 62 * f + sym(8)
      R.lf = range(1.6, 2.3)
      R.sbend = (f < 0 and 1 or -1) * range(0.05, 0.3)
      R.lf = R.lf * R.leafc
      R.lc = G.rnd()
      placeleaf(R.root, K(0.1), seedorgan())
    end
  end
  local function eudicotleaves(ga)
    local arr = S.arrangement
    R.per, R.gap, R.leafk = 1, 1, 1
    if arr == "opposite" then R.per, R.gap = 2, K(1.3) end
    if arr == "whorled" then R.per, R.gap = 3, K(1.4) end
    if arr == "rosette" then rosette() R.gap, R.leafk = K(1.6), K(0.4) end
    R.ny = range(0.7, 1.3)
    R.side = chance(0.5) and 1 or -1
    R.nlast = R.pH - 1.6
    nodes(ga)
  end
  local function monocotleaves(ga)
    local nb = int(3, 5)
    for b = 1, nb do
      local f = (b - (nb + 1) / 2) / max(1, (nb - 1) / 2)
      R.la = 90 - 24 * f + sym(5)
      R.lf = min(7, R.pH * range(0.3, 0.46)) * (1 - 0.25 * abs(f))
      R.sbend = (f < 0 and -1 or 1) * range(0.1, 0.35)
      R.lc = G.rnd()
      local z = seedorgan()
      placeleaf(R.root + 0.12 * f, 0, z)
    end
    R.side = chance(0.5) and 1 or -1
    R.per, R.leafk = 1, K(0.75)
    R.ny = range(0.22, 0.3) * R.pH R.Ge = R.Ge + 1 nodeleaves(ga)
    R.ny = range(0.42, 0.52) * R.pH R.Ge = R.Ge + 1 nodeleaves(ga)
  end
  local function passleaves(ga)
    stemload(ga) R.Ge = 0 leafcof()
    R.nd[ga] = R.nd[ga] or {}
    local cl, arr = S.clade, S.arrangement
    if cl == "monocot" and (arr == "alternate" or arr == "whorled") then cl = "leafy" end
    if cl == "monocot" then monocotleaves(ga) else eudicotleaves(ga) end
    R.ndn[ga] = R.Ge
  end
  -- \flo@cubicstem: a branch along the cubic B, widths w0 to w1 (cm), a stroke under 0.7 bp
  local function cubicstem(B, w0, w1)
    local w = (w0 + w1) / 2 * 28.3465
    local c = tone(0.07)
    if w < K(0.7) then
      moveto(B[1], B[2]) curveto(B[3], B[4], B[5], B[6], B[7], B[8]) stroke(c, w, 1, false)
    else
      taper(B[1], B[2], B[3], B[4], B[5], B[6], B[7], B[8], w0, w1) fill(c, 1)
    end
  end
  -- \flo@branchto: the branch from the node to (R.bx, R.by) (\flo@branchpath, flora's
  -- branch_path), a leaflet or two along it, what it carries
  local function branchto()
    local x0, y0, x1, y1 = R.nx, R.nyy, R.bx, R.by
    local dx, dy = x1 - x0, y1 - y0
    local d = sqrt(dx * dx + dy * dy)
    local s = R.ntx * dx + R.nty * dy < -0.3 * d and -1 or 1
    local tx, ty = s * R.ntx, s * R.nty
    local turn = range(28, 48)
    turn = (tx * dy - ty * dx > 0 and 1 or -1) * turn
    local ox, oy = tx * cos(turn) - ty * sin(turn), tx * sin(turn) + ty * cos(turn)
    local B = { x0, y0, x0 + ox * d * 0.45, y0 + oy * d * 0.45, x1 - R.ax * d * 0.4, y1 - R.ay * d * 0.4, x1, y1 }
    local function cubicat(t)                   -- \flo@cubicat: the point at t, and the angle there
      local u = 1 - t
      local a, b, c, e = u * u * u, 3 * u * u * t, 3 * u * t * t, t * t * t
      local cx = a * B[1] + b * B[3] + c * B[5] + e * B[7]
      local cy = a * B[2] + b * B[4] + c * B[6] + e * B[8]
      a, b, c = u * u, 2 * u * t, t * t
      local ddx = a * (B[3] - B[1]) + b * (B[5] - B[3]) + c * (B[7] - B[5])
      local ddy = a * (B[4] - B[2]) + b * (B[6] - B[4]) + c * (B[8] - B[6])
      return cx, cy, atan2(ddy, ddx)
    end
    for k = 1, 3 do
      local cx, cy = cubicat(0.25 * k)
      room(true, cx, cy, 0.15)
    end
    local w = min(0.7 * R.nw, 0.05)
    local wb = max(0.012, 0.45 * w)
    if at(LSTEM) then cubicstem(B, w, wb) end
    if d > K(1.2) then
      local nl = d > K(2.2) and 2 or 1
      for gb = 1, nl do
        local cx, cy, ca = cubicat(0.25 + 0.3 * gb / nl)
        local la = ca + (gb == 1 and -1 or 1) * R.side * range(40, 60) - 90
        R.lf = range(0.45, 0.75)
        local z = seedorgan()
        if at(LLEAF) then
          local lf = R.lf
          organ(z, function() ink.translate(cx, cy) ink.rotate(la) ink.scale(lf) M.leaflet({ u = lf }) end)
        end
      end
    end
    local what, bx, by, a = R.what, R.bx, R.by, R.a
    if what == 1 then unit(bx, by, a, R.usc, R.ulate) return end
    room(true, R.bdx, R.bdy, 0.85 * R.bdr)
    if what == 2 then
      local z = seedorgan()
      if at(LBLOOM) then
        organ(z, function() ink.translate(bx, by) ink.rotate(a - 90) M.budding(min(1.1, fdiam(K(0.6)))) end)
      end
    elseif what == 3 then
      local z = seedorgan()
      if at(LAIRY) then organ(z, function() ink.translate(bx, by) ink.rotate(a) M.tendril(range(0.3, 0.5)) end) end
    else
      R.sbend = R.side * range(0.05, 0.3) R.lc = G.rnd()
      local z = seedorgan()
      if at(LLEAF) then
        local lf, bend, lc = R.lf, R.sbend, R.lc
        organ(z, function()
          ink.translate(bx, by) ink.rotate(a - 90) ink.scale(lf)
          autumnleaf(lc, R.season)
          M.leaf(lf, bend)
        end)
      end
    end
  end
  -- \flo@branch: what the branch carries, then the freest of three places for it
  local function branch()
    local late = M.lateness(S, R.u)
    local mk = G.rnd()
    local climb = S.habit == "climbing" or S.tendrils == 1
    if R.filling then mk = mk * 1.25 - 0.25 end
    if mk < 0 then R.what = 4 leafcof() R.lf = range(K(1.1), 2) * R.leafc
    elseif mk < K(0.6) then R.what = 1 R.usc = range(0.7, 0.9) R.ulate = late
    elseif mk < K(0.82) then R.what = 2
    elseif climb then R.what = 3
    else R.what, R.usc, R.ulate = 1, K(0.6), late + 0.1 end
    local best = 2
    for _ = 1, 3 do
      local cd = range(1.4, 3.2) * (1 - 0.25 * R.u)
      local cg = 90 + R.side * range(25, 75)
      local cbx = max(R.pxmin, min(R.pxmax, R.nx - cd * cos(cg)))
      local cby = R.nyy + cd * sin(cg)
      local cax, cay = cbx - R.nx, cby - R.nyy
      local t = sqrt(cax * cax + cay * cay)
      cax, cay = cax / t, cay / t + 0.6
      t = sqrt(cax * cax + cay * cay)
      cax, cay = cax / t, cay / t
      local caa = atan2(cay, cax)
      local what, udx, udy, udr = R.what
      if what == 1 then
        local uo, r = M.unitdisc(S, R.usc)
        udx, udy, udr = cbx + uo * cos(caa), cby + uo * sin(caa), r
      elseif what == 2 then udx, udy, udr = cbx + 0.35 * cax, cby + 0.35 * cay, 0.5
      elseif what == 3 then udx, udy, udr = cbx, cby, 0.35
      else udx, udy, udr = cbx + 0.5 * R.lf * cax, cby + 0.5 * R.lf * cay, 0.32 * R.lf end
      local taken = takenat(udx, udy, udr)
      if taken < best then
        best = taken
        R.bx, R.by, R.ax, R.ay, R.a = cbx, cby, cax, cay, caa
        R.bdx, R.bdy, R.bdr = udx, udy, udr
      end
    end
    if best < K(0.3) then branchto() end
  end
  -- \flo@passbranches: a branch at a node now and then; \flo@passfill: then anywhere
  local function passbranches(ga)
    stemload(ga)
    for e = 1, R.ndn[ga] do
      local nd = R.nd[ga][e]
      R.ny, R.side = nd[1], nd[2]
      nodeat()
      if G.rnd() < K(e == 1 and 0.35 or 0.85) then branch() end
    end
  end
  local function passfill(ga)
    stemload(ga) R.filling = true
    for _ = 1, R.ftries do
      R.ny = range(0.12, 0.93) * R.pH
      R.side = chance(0.5) and 1 or -1
      nodeat() branch()
    end
    R.filling = false
  end
  -- \flo@garden: plants (seed, role) from one root, gH cm high, reaching about gW, walked
  -- once per layer; a pale ghost flower behind them
  local function garden(plants, gH, gW, ghost, season, traits)
    local np = #plants
    if np == 0 then return end                  -- plants names no plant (TeX's error)
    ink.scale(28.45276)
    R = { season = season, Np = np, H = {}, z = {}, w = {}, f = {}, nd = {}, ndn = {}, s = {}, r = {}, fore = 1,
      filling = false, traits = traits }
    for k, p in ipairs(plants) do R.s[k], R.r[k] = p[1], p[2] end
    drawseed(R.s[1])
    for ga = 1, np do
      local t = 1
      if ga == 2 then t = range(0.6, 0.72) elseif ga == 3 then t = range(0.36, 0.48) elseif ga > 3 then t = range(0.5, 0.58) end
      R.H[ga] = gH * t
      R.z[ga] = seedorgan()
    end
    local gx = gW * (range(0.35, 0.65) - 0.5)
    local gy = gH * range(0.15, 0.3)
    local gdiam = range(2.6, 3.2)
    local gos = seedorgan()
    R.pxmin, R.pxmax = -gW / 2 + 0.7, gW / 2 - 0.7
    R.pA = np == 1 and 0.5 or 0.2 * gW
    for l = 1, 5 do
      layer, ROOM = l, {}
      for ga = 1, np do R.w[ga] = R.z[ga] end
      if ghost then
        room(true, gx, gy, 0.25 * gdiam)
        if l == 1 then
          -- a plain flower of the first plant's species, as v1.3's ghosts are
          S = full({ seed = R.s[1], role = R.r[1], traits = R.traits })
          organ(gos, function()
            pen.lift = K(0.62)
            ink.translate(gx, gy)
            ghostflower(gdiam)
          end)
        end
      end
      for ga = 1, np do plantsetup(ga) passstem(ga) R.w[ga] = G.save() end
      for ga = 1, np do plantsetup(ga) passleaves(ga) R.w[ga] = G.save() end
      for ga = 1, np do plantsetup(ga) passbranches(ga) R.w[ga] = G.save() end
      for _ = 1, 3 do
        for ga = 1, np do
          plantsetup(ga) R.ftries = texint(R.pH, 131072) passfill(ga) R.w[ga] = G.save()
        end
      end
    end
  end

  -- ---------------------------------------------------------------- the pics
  -- \flo@picsetup: the species, then the drawing's own stream (o.draw, or the seed + 1)
  local function setup(o, role)
    S = full({ seed = o.seed, role = role or o.role or "any", traits = o.traits })
    drawseed(o.draw or (o.seed == 2147483646 and 1 or o.seed + 1))
  end
  return function(kind, o)
    local season = (o.season or 49152) / 65536            -- 0.75 if not given
    if kind == "flower" then
      setup(o) ink.scale(o.size / 65536)
      local tq = stone()
      M.sflower(o.size / 65536, { tone = tq, notchp = 0.4, notchk = 1 })
    elseif kind == "leaf" then
      setup(o) ink.scale(o.size / 65536) M.leaf(nil, nil, nil, o.size)
    elseif kind == "v13 flower" then
      setup(o) ink.scale(o.size / 65536)
      M.flower(sizecm(o.size), 5, { pointed = false, notchp = 0.4, notchk = 1 })
    elseif kind == "v13 leaf" then
      setup(o) ink.scale(o.size / 65536) vleaf(sizecm(o.size))
    elseif kind == "inflorescence" then
      setup(o) ink.scale(28.45276)
      M.unit(o.scale / 65536, 1.2 * season + sym(0.08) + S.phenology)
    elseif kind == "plant" then
      setup(o)
      if S.clade == "fern" then ferncrown(sizecm(o.size), season)
      else garden({ { o.seed, o.role or "any" } }, sizecm(o.size), sizecm(o.width), false, season, o.traits) end
    elseif kind == "fern" then
      setup(o, "fern") ferncrown(sizecm(o.size), season)
    elseif kind == "visitor" then
      visitor(o, true)
    elseif kind == "plants" then
      garden(o.plants, sizecm(o.size), sizecm(o.width), o.ghost ~= false, season, o.traits)
    else
      error("florilegium-native: no pic " .. tostring(kind))
    end
  end
end)()
-- A pic of the TikZ library (\pic {florilegium <kind>={...}}), drawn with ink at the origin
-- under ink's current transform, in pt: kind flower, leaf, v13 flower, v13 leaf,
-- inflorescence, plant, plants, fern or visitor; o as M.tikz builds it
-- (seed, role, draw; size and width in sp of pt; season and scale in sp; ghost; plants =
-- { {seed, role}, ... })
function M.pic(kind, o)
  M.fresh()
  pen.lift, pen.accent = 0, false
  FE.tex = true
  ink.push()
  local ok, err = pcall(pic, kind, o)
  ink.pop()
  FE.tex = nil
  pen.lift, pen.accent = 0, false
  if not ok then error(err, 0) end
end

-- ================================================================ the TikZ library's pics
-- \flo@luapic: a pic of the TikZ library (engine=lua) drawn here, straight into the picture.
-- ink follows pgf's current transformation (a pic's units are pt), the colors are the
-- document's ink and accent, and pgf learns the drawing's extent for the picture's size.
-- TeX has read the keys as the TikZ code reads them (\flo@luapic): the seeds are whole
-- numbers, the season and the scale pgfmath's results, read here into sp
-- the library and these files are found one by one (a set in ~/texmf, newer files beside
-- the document), so the first pic checks that they come from one release
local checked = false
local function check(lib)
  checked = true
  local v = lib and lib:match("v(%d[%d.]*)")
  if not v then return end
  for _, m in ipairs({ { "florilegium-native", M.version }, { "florilegium-pgfmath", pm.version },
    { "florilegium-species", species.version }, { "florilegium-ink", ink.version } }) do
    if m[2] ~= v then
      error(string.format("florilegium: %s.lua is from %s, tikzlibraryflorilegium.code.tex from release %s. "
        .. "Copy the library and every florilegium*.lua from one release.", m[1],
        m[2] and ("release " .. m[2]) or "an earlier release", v), 0)
    end
  end
end
local function rgb(s)
  local r, g, b = s:match("^%s*([%d.]+)%s*,%s*([%d.]+)%s*,%s*([%d.]+)")
  return tonumber(r), tonumber(g), tonumber(b)
end
-- kind: flower, leaf, v13 flower, v13 leaf, inflorescence, plant, plants, fern, visitor;
-- seed and draw (or "") whole numbers, size and width in sp, season and scale decimals,
-- plants "seed/role,seed/role,", ghost "true" or "false"; inkrgb, accrgb "r,g,b"; lib the
-- library's \ProvidesFile line
function M.tikz(kind, seed, role, draw, size, width, season, plants, ghost, scale, inkrgb, accrgb, lib, traits)
  if not checked then check(lib) end
  local o = { role = role, size = size, width = width, season = pm.sp(season), ghost = ghost == "true",
    scale = pm.sp(scale), seed = math.tointeger(tonumber(seed)) }
  if draw ~= "" then o.draw = math.tointeger(tonumber(draw)) end
  if kind == "plants" then
    o.plants = {}
    for s, r in plants:gmatch("([^/,]+)/([^,]*),") do o.plants[#o.plants + 1] = { math.tointeger(tonumber(s)), r } end
  end
  if traits and traits:match("%S") then
    -- a trait the genome lacks, a value it cannot draw, or one the plant's kind cannot (a
    -- fern's on a flowering plant, M.refused, which sampling raises): TeX's error, once,
    -- and the pic as sampled, as the library's \flo@fixset and \flo@planfixcheck do
    local ok, fix = pcall(species.fixes, traits, kind == "visitor")
    local err = not ok and fix or nil
    if ok and kind ~= "visitor" then
      for _, p in ipairs(o.plants or { { o.seed, role } }) do
        local drawn, e = pcall(species.sample, p[1], p[2], nil, fix)
        if not drawn then ok, err = false, e break end
        -- the fern pic draws a fern (\flo@fernpic)
        if kind == "fern" and e.clade ~= "fern" then
          ok, err = false, string.format("florilegium: the fern pic draws a fern, and plan=%s is a flowering plant's", e.plan)
          break
        end
      end
    end
    if ok then o.traits = traits else tex.error(err) end
  end
  ink.set_ink(rgb(inkrgb))
  ink.set_accent(rgb(accrgb))
  local k, bp = 72 / 72.27, 72 / 72.27 / 65536
  ink.set_transform({ tonumber(token.get_macro("pgf@pt@aa")) * k, tonumber(token.get_macro("pgf@pt@ab")) * k,
    tonumber(token.get_macro("pgf@pt@ba")) * k, tonumber(token.get_macro("pgf@pt@bb")) * k,
    tex.dimen["pgf@pt@x"] * bp, tex.dimen["pgf@pt@y"] * bp })
  local lift, pale, layer = ink.set_lift(0), ink.set_pale(0), ink.layer(5)
  ink.track(true)
  -- a pic that fails leaves ink as it found it, so the next pic or margin page draws in its
  -- own layer and pale, and what it drew is dropped (a clip it opened may still be open);
  -- then TeX reports the error
  local ok, err = pcall(M.pic, kind, o)
  if not ok then ink.drop() end
  local box = ink.track(false)
  ink.flush()
  ink.set_lift(lift) ink.set_pale(pale) ink.layer(layer)
  if not ok then error(err, 0) end
  if box and box[1] <= box[3] then
    local f = 72.27 / 72
    local cct = luatexbase and luatexbase.registernumber and luatexbase.registernumber("catcodetable@atletter")
    local s = string.format("\\pgf@protocolsizes{%.4fpt}{%.4fpt}\\pgf@protocolsizes{%.4fpt}{%.4fpt}",
      box[1] * f, box[2] * f, box[3] * f, box[4] * f)
    if cct then tex.sprint(cct, s) else tex.sprint(s) end
  end
end

return M
