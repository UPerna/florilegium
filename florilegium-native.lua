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

return M
