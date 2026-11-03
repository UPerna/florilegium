-- florilegium-native.lua -- the species' organs in plain Lua, drawn straight to ink.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- The TikZ library (tikzlibraryflorilegium.code.tex) draws a species' plant in pgfmath;
-- florilegium-organs.lua replays it in Lua to the scaled point and writes the pgf code it
-- would run. Here the same organs are computed in ordinary floating point and painted with
-- ink as they are computed: the same steps, the same random draws from pgf's generator in
-- the same order, so the same seed gives the same organ, its numbers within a small
-- fraction of a point of the library's. (Where pgfmath's rounding and a double's would
-- fall on different sides of a threshold, a choice can tip; such cases are rare, and the
-- comparison in tools/nativecheck.lua lists them.)
--
-- Some of the library's habits are kept on purpose, because its look was made with them:
-- they are marked "as the library does" where they would otherwise look like slips.
--
-- Lengths are in the organ's own units (a petal is 1 long), angles in degrees, colors
-- points of ink's ramp: tone(t) as \flo@vtone, in the accent's ramp while pen.accent is set.

local ink = require("florilegium-ink")

local M = {}
M.version = "1.3"                 -- the release; florilegium.lua checks that every file has the same

local floor, sqrt, abs, min, max = math.floor, math.sqrt, math.abs, math.min, math.max
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
-- \flo@chance: rnd < p, with p as TeX holds the constant (a whole number of sp)
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
-- and each speck to two of its corners, so only the first blotch spans the petal
local function mottle(x0, y0, x1, y1, n, size, dark, light, nspk, drift)
  local xa, xb = x0, x1
  for _ = 1, n do
    local mx, my = range(xa, xb), range(y0, y1)
    local mr = size * range(0.5, 1.4)
    local ms = mr * range(0.5, 1)
    local pts = blob(mx, my, mr, ms, 0.35, 7)
    if drift then xa, xb = pts[6][1], pts[1][1] end
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
      local mx, my = range(xa, xb), range(y0, y1)
      local mr = size * range(0.03, 0.08)
      local ma = range(0, 180)
      local sc, ss = mr * cos(ma), mr * sin(ma)
      moveto(mx + sc, my + ss) lineto(mx - 0.6 * ss, my + 0.6 * sc)
      lineto(mx - sc, my - ss) lineto(mx + 0.6 * ss, my - 0.6 * sc) close()
      if drift then xa, xb = mx + sc, mx - 0.6 * ss end
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
  local fine = o.u > 0.45
  local g = fbm()
  local notch = 0
  if not pointed and chance(o.notchp) then notch = range(0.03, 0.06) * o.notchk end
  -- a petal under 1.2 mm is tiny: a coarser outline, no heart, mottle or pooled rim (specks
  -- no printer resolves at that size), and at most five streaks
  local tiny = o.u < 0.12
  local bn = o.u > 0.5 and 28 or (tiny and 8 or 18)
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
  -- the disc florets on Vogel's spiral
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
-- \flo@vstreak: a ribbon along the points, widths w0 to w1, thin at its start
local function streak(pts, w0, w1, color, op)
  local nr, n = normals(pts), #pts
  local s, acc = { 0 }, 0
  for i = 2, n do
    local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
    acc = acc + sqrt(dx * dx + dy * dy)
    s[i] = acc
  end
  local out = {}
  for i = 1, n do
    local u = acc > 0 and s[i] / acc or 0
    local w = (w0 + (w1 - w0) * u) * (u < 0.12 and 0.4 + 5 * u or 1) / 2
    local p, q = pts[i], nr[i]
    out[i] = { p[1] + q[1] * w, p[2] + q[2] * w }
    out[2 * n + 1 - i] = { p[1] - q[1] * w, p[2] - q[2] * w }
  end
  smooth(out, true) fill(color, op)
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
  if o.u > 0.25 then
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
  local a, b, c, w, L, tt, sep = 0.1, 0.24, 1.3, 0, 0.85, 0.14, true
  local f = range(0.06, 0.12)
  local n = floor(S.merosity / 2 + 1.5)
  local bd = sym(0.08)
  if form == "urceolate" then a, b, w, L, tt, f = 0.09, 0, 0.25, 0.8, 0.08, 0.07 end
  if form == "tubular" then a, b, c, L, tt, f = 0.07, 0.07, 1.5, 0.95, 0.08, 0.05 end
  if form == "funnelform" then a, b, c, L, tt, f = 0.05, 0.4, 2.4, 0.85, 0.1, 0.1 end
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
    ink.poly({ { 0, -0.1 }, { 0.25 * bd, 0.5 * L }, { 1.21 * bd, 1.1 * L }, { xc, 1.1 * L }, { xc, -0.1 } }, true)
    fill(col, 0.28, true)
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
    if fm == "lily" then vw = "lily" end
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
  local nr, n = normals(pts), #pts
  local s, acc = { 0 }, 0
  for i = 2, n do
    local dx, dy = pts[i][1] - pts[i - 1][1], pts[i][2] - pts[i - 1][2]
    acc = acc + sqrt(dx * dx + dy * dy)
    s[i] = acc
  end
  local out = {}
  for i = 1, n do
    local h = (w0 + (w1 - w0) * s[i] / acc) / 2
    local p, q = pts[i], nr[i]
    out[i] = { p[1] + q[1] * h, p[2] + q[2] * h }
    out[2 * n + 1 - i] = { p[1] - q[1] * h, p[2] - q[2] * h }
  end
  smooth(out, true) fill(c, 1)
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
    curl(xa, ya, L, 0.018, 0.15, h, -side, floor(max(6, n * 0.7)), fd, st)
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
-- \flo@corymbunit: stalks of falling length, the flowers level at the top; fd the flowers' size
local function corymb(len, fd, st)
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
      stem(tassel, w, we, t0)
      local c = tone(0.16)
      for k = 2, 15 do
        local s2 = k % 2 == 1 and 1 or -1
        local s = w * 0.5 * (1 - 0.6 * (k - 1) / 15)
        local px, py, nx, ny = tassel[k][1], tassel[k][2], nr[k][1], nr[k][2]
        local xb, yb = px + nx * s2 * s, py + ny * s2 * s
        local xc, yc = px + ny * 0.6 * s, py - nx * 0.6 * s
        moveto(xb, yb) curveto(xc, yc, xc, yc, px, py) stroke(c, 0.3, 0.7, true)
        circle(xb, yb, range(0.008, 0.014)) fill(c, 0.9)
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
local BELOW = { raceme = true, spike = true, catkin = true }
function M.lateness(s, h) return BELOW[s.inflo] and 0.4 * h or 0.4 * (1 - h) end

-- a species given by seed and role only is sampled (once)
local species = require("florilegium-species")
local sampled = {}
local function full(s)
  if s.plan then return s end
  local key = s.seed .. "/" .. s.role
  if not sampled[key] then sampled[key] = species.sample(s.seed, s.role) end
  return sampled[key]
end
-- One organ of species s (a table from florilegium-species, or just its seed and role),
-- drawn from pgf seed z at the origin with its axis along +y, in cm, under ink's current
-- transform. o by kind:
--   unit     k (scale), season, late: the inflorescence
--   budding  k: buds on stalks       tendril  size     bloom  d (diameter cm), stage
--   ghost    d: a plain pale flower of the species, as the garden's ghost
-- Returns false for a kind not yet drawn here (leaf, frond, visitor).
local DRAWN = { unit = true, budding = true, tendril = true, bloom = true, ghost = true }
function M.draw(kind, s, z, o)
  if not DRAWN[kind] then return false end
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
  else                                            -- the ghost: a plain rotate flower, pale
    pen.lift = 0.62
    local tq = stone()
    local g = {}
    for k, v in pairs(S) do g[k] = v end
    g.form = "rotate"
    if g.merosity > 6 then g.merosity = 5 end
    S = g
    ink.scale(o.d)
    M.sflower(o.d * 28.45276, { tone = tq, notchp = 0.4, notchk = 1 })
  end
  ink.pop()
  return true
end

return M
