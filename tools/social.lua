-- tools/social.lua -- the GitHub social image (gallery/social.png), drawn by tools/social.tex.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- "florilegium" grown as one vine. The letters' skeleton is the Hershey Script Simplex font
-- (tools/hershey/), set upright, its x-height enlarged and its letters widened so the word
-- reads at a glance. One even vine comes in from the left edge, writes the word and goes out
-- to the right, with a thinner strand twisting round it, a little bark, and nodes that put out
-- spurs and tendrils; leaves grow outside the letters' bodies, and the TikZ library's species
-- flowers and a butterfly go where this file says. Everything but the letters is drawn pale,
-- so the word stands out; make social then prints the page as a cyanotype (the ink white, the
-- paper Delft blue).
--
-- The Hershey Fonts were originally created by Dr. A. V. Hershey while working at the U. S.
-- National Bureau of Standards. The format of the font data in tools/hershey/scripts.jhf was
-- originally created by James Hurt, Cognition, Inc., 900 Technology Park Drive, Billerica,
-- MA 01821. See tools/hershey/README.md.

local ink = require("florilegium-ink")
local flora = require("florilegium-flora")
local M = {}
local sqrt, cos, sin, atan, abs, min, max, pi, floor = math.sqrt, math.cos, math.sin, math.atan, math.abs, math.min, math.max, math.pi, math.floor
local rad = pi / 180
local tone, white = ink.tone, ink.white
local function lerp(a, b, t) return a + (b - a) * t end
local function dist(a, b) local dx, dy = a[1] - b[1], a[2] - b[2] return sqrt(dx * dx + dy * dy) end

-- ---------------------------------------------------------------- the font
-- Each entry: the glyph number (5 columns), the count of coordinate pairs (3), then the pairs,
-- the glyph's left and right bounds first. A coordinate is its character's code minus 'R';
-- " R" lifts the pen; y grows downward. The file lists ASCII 32 to 126 in order.
local function load_jhf(path)
  local f = assert(io.open(path, "rb"))
  local lines = {}
  for l in f:read("a"):gmatch("[^\n]+") do lines[#lines + 1] = l:gsub("\r", "") end
  f:close()
  local R, glyphs, i = string.byte("R"), {}, 1
  while i <= #lines do
    local n = tonumber(lines[i]:sub(6, 8))
    local data = lines[i]:sub(9)
    while #data < 2 * n and i < #lines do i = i + 1 data = data .. lines[i] end
    local g = { lb = data:byte(1) - R, rb = data:byte(2) - R, strokes = {} }
    local cur
    for k = 1, n - 1 do
      local a, b = data:sub(2 * k + 1, 2 * k + 1), data:sub(2 * k + 2, 2 * k + 2)
      if a == " " and b == "R" then cur = nil
      else
        if not cur then cur = {} g.strokes[#g.strokes + 1] = cur end
        cur[#cur + 1] = { a:byte() - R, b:byte() - R }
      end
    end
    glyphs[#glyphs + 1] = g
    i = i + 1
  end
  return glyphs
end

-- In font units with y up, the baseline is at -9, the x-height at 0, ascenders reach 12 and
-- descenders -21. The word is set upright, x' = (x - slant (y + 9)) xscale, and the x-height
-- band is stretched by xk (above it shifted up, below it kept).
local LO, HI = -9, 0
local function warp(o)
  local slant, xs, xk = o.slant, o.xscale, o.xk
  return function(x, y)
    local yy
    if y < LO then yy = y elseif y <= HI then yy = LO + (y - LO) * xk else yy = LO + (HI - LO) * xk + (y - HI) end
    return (x - slant * (y - LO)) * xs, yy
  end, LO + (HI - LO) * xk
end

-- the word's strokes, those that meet joined into one; the i's dots (tiny closed strokes)
-- come back on their own
local function word_strokes(glyphs, word, W)
  local pen, out, dots = 0, {}, {}
  for c in word:gmatch(".") do
    local g = glyphs[c:byte() - 31]
    for _, s in ipairs(g.strokes) do
      local t, x0, x1, y0, y1 = {}, math.huge, -math.huge, math.huge, -math.huge
      for _, p in ipairs(s) do
        local x, y = pen + p[1] - g.lb, -p[2]
        x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
        t[#t + 1] = { x, y }
      end
      if #t <= 6 and x1 - x0 < 2.5 and y1 - y0 < 2.5 then dots[#dots + 1] = { (x0 + x1) / 2, (y0 + y1) / 2 }
      else out[#out + 1] = t end
    end
    pen = pen + g.rb - g.lb
  end
  local joined = true
  while joined do
    joined = false
    for a = 1, #out do
      for b = 1, #out do
        if a ~= b and dist(out[a][#out[a]], out[b][1]) < 0.6 then
          for k = 2, #out[b] do out[a][#out[a] + 1] = out[b][k] end
          table.remove(out, b) joined = true break
        end
      end
      if joined then break end
    end
  end
  for _, s in ipairs(out) do for i, p in ipairs(s) do s[i] = { W(p[1], p[2]) } end end
  for i, d in ipairs(dots) do dots[i] = { W(d[1], d[2]) } end
  return out, dots
end

-- the current pgf transform as ink's, as florilegium.lua's sync_transform does
local function sync_transform()
  local C, bp = ink.CM, 72 / 72.27 / 65536
  ink.set_transform({
    tonumber(token.get_macro("pgf@pt@aa")) * C, tonumber(token.get_macro("pgf@pt@ab")) * C,
    tonumber(token.get_macro("pgf@pt@ba")) * C, tonumber(token.get_macro("pgf@pt@bb")) * C,
    tex.dimen["pgf@pt@x"] * bp, tex.dimen["pgf@pt@y"] * bp })
end

-- a polyline resampled every ds (cm), and its unit tangent at a point
local function resample(pts, ds)
  local out, acc = { pts[1] }, 0
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    local L = dist(a, b)
    local t = ds - acc
    while t <= L do
      out[#out + 1] = { lerp(a[1], b[1], t / L), lerp(a[2], b[2], t / L) }
      t = t + ds
    end
    acc = L - (t - ds)
  end
  if dist(out[#out], pts[#pts]) > ds * 0.3 then out[#out + 1] = pts[#pts] end
  return out
end
local function tangent(pts, i)
  local a, b = pts[max(1, i - 1)], pts[min(#pts, i + 1)]
  local tx, ty = b[1] - a[1], b[2] - a[2]
  local L = sqrt(tx * tx + ty * ty)
  if L < 1e-9 then return 1, 0 end
  return tx / L, ty / L
end

local DEFAULTS = {
  word = "florilegium", seed = 7,
  slant = 0.3, xscale = 1.38, xk = 1.6,        -- upright, wider, a larger x-height
  width = 0.76, middle = 0.55,                 -- the word's width and its center's height, of the page
  vine = 1.0, twist = 5.5, strand = 0.1,       -- the vine's width (font units), the strand's period and tone
  bark = 0.15, spurs = 0.45, leaves = 1,       -- how often
  pale = 0.6,                                  -- everything but the letters, 0..1
  sparkles = { { 0.12, 0.78, 2.2 }, { 0.62, 0.84, 1.6 }, { 0.86, 0.36, 2.0 } },
}

-- W, H: the page in cm; o.jhf: the font file; any key of DEFAULTS
function M.draw(W, H, o)
  for k, v in pairs(DEFAULTS) do if o[k] == nil then o[k] = v end end
  M.o = o
  sync_transform()
  local rng = ink.rng(o.seed)
  local Wp, xtop = warp(o)
  local strokes, fdots = word_strokes(load_jhf(o.jhf), o.word, Wp)
  local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
  for _, s in ipairs(strokes) do for _, p in ipairs(s) do
    x0, x1, y0, y1 = min(x0, p[1]), max(x1, p[1]), min(y0, p[2]), max(y1, p[2]) end end
  local k = o.width * W / (x1 - x0)
  local ox, oy = (W - k * (x1 + x0)) / 2, H * o.middle - k * (y1 + y0) / 2
  local u = k                                       -- cm per font unit
  local yb, yx = oy + k * LO, oy + k * xtop         -- the baseline and the x-height, cm
  M.unit = u
  for si, s in ipairs(strokes) do
    local q = {}
    for _, p in ipairs(s) do q[#q + 1] = { ox + k * p[1], oy + k * p[2] } end
    strokes[si] = ink.catmull(q, 5)
  end
  table.sort(strokes, function(a, b) return a[1][1] < b[1][1] end)
  -- the vine comes in from the left edge into the first letter, and goes out from the last
  -- to the right edge, dipping a little and lifting at the end
  local first, last = strokes[1], strokes[#strokes]
  do
    local s0, tx, ty = first[1], tangent(first, 2)
    local e = { -0.5, s0[2] - 0.6 * u }
    local inn = ink.sample(ink.bezier3(e[1], e[2], s0[1] * 0.45, e[2] - 0.8 * u, s0[1] - tx * 3 * u, s0[2] - ty * 3 * u, s0[1], s0[2]), 40)
    table.remove(inn)
    for i = #inn, 1, -1 do table.insert(first, 1, inn[i]) end
    local e1 = last[#last]
    local ux, uy = tangent(last, #last - 1)
    local out = ink.sample(ink.bezier3(e1[1], e1[2], e1[1] + ux * 3 * u, e1[2] + uy * 3 * u,
      lerp(e1[1], W, 0.6), e1[2] - 1.6 * u, W + 0.5, e1[2] - 0.4 * u), 40)
    for i = 2, #out do last[#last + 1] = out[i] end
  end
  local paths = {}
  for si, s in ipairs(strokes) do paths[si] = resample(s, 0.12 * u) end
  local all = {}
  for si, s in ipairs(paths) do for i, p in ipairs(s) do all[#all + 1] = { p[1], p[2], si, i } end end
  -- is (x, y) at least r from the vine, apart from the stretch around point i0 of path own
  local function clear(x, y, own, i0, r)
    for _, p in ipairs(all) do
      if not (p[3] == own and abs(p[4] - i0) < 40) then
        local dx, dy = p[1] - x, p[2] - y
        if dx * dx + dy * dy < r * r then return false end
      end
    end
    return y > H * 0.06 and y < H * 0.94
  end

  local wv = o.vine * u                             -- the vine's width, cm
  local DARK = tone(0.06)

  -- the paper and a double frame
  local m = 0.035 * H
  ink.layer(1)
  ink.flood({ 1, 0.992, 0.973 }, 0, 0, W, H)
  ink.poly({ { m, m }, { W - m, m }, { W - m, H - m }, { m, H - m } }, true) ink.stroke(tone(lerp(0.12, 1, o.pale)), 0.9)
  local m2 = m * 1.35
  ink.poly({ { m2, m2 }, { W - m2, m2 }, { W - m2, H - m2 }, { m2, H - m2 } }, true) ink.stroke(tone(lerp(0.2, 1, o.pale)), 0.35, 0.8)

  -- the vine: the strand behind it, the stem, bark, nodes with spurs, the strand in front
  local function strand_runs(pts, front)
    local runs, cur, s = {}, nil, 0
    local lam, r = o.twist * u, 0.42 * wv
    for i, p in ipairs(pts) do
      if i > 1 then s = s + dist(p, pts[i - 1]) end
      local ph = 2 * pi * s / lam
      local tx, ty = tangent(pts, i)
      if (cos(ph) > 0) == front then
        if not cur then cur = {} runs[#runs + 1] = cur end
        cur[#cur + 1] = { p[1] - ty * r * sin(ph), p[2] + tx * r * sin(ph) }
      else cur = nil end
    end
    return runs
  end
  local function strands(front)
    for _, pts in ipairs(paths) do
      for _, run in ipairs(strand_runs(pts, front)) do
        if #run > 2 then flora.stem(run, 0.3 * wv, 0.3 * wv, tone(o.strand)) end
      end
    end
  end
  ink.layer(2)
  strands(false)
  ink.layer(3)
  for i, pts in ipairs(paths) do
    flora.stem(pts, i == 1 and 1.12 * wv or wv, i == #paths and 0.7 * wv or wv, DARK)
  end
  for _, pts in ipairs(paths) do                    -- bark: a few short pale streaks
    for i = 3, #pts - 3, 7 do
      if rng.chance(o.bark) then
        local tx, ty = tangent(pts, i)
        local off = rng.sym(0.22 * wv)
        local x, y = pts[i][1] - ty * off, pts[i][2] + tx * off
        local L = rng.range(0.6, 1.3) * u
        ink.taper(x, y, x + tx * L / 3, y + ty * L / 3, x + tx * 2 * L / 3, y + ty * 2 * L / 3, x + tx * L, y + ty * L, 0.07 * wv, 0.015 * wv)
        ink.fill(white, rng.range(0.15, 0.3))
      end
    end
  end
  ink.layer(4)
  local nodes = 0
  for si, pts in ipairs(paths) do
    local i, side = floor(rng.range(20, 40)), rng.chance(0.5) and 1 or -1
    while i < #pts - 10 do
      local p = pts[i]
      local tx, ty = tangent(pts, i)
      local a = atan(ty, tx)
      local ring = {}                               -- the node: a swelling of the stem
      for kk = 0, 11 do
        local t = kk / 12 * 2 * pi
        local ex, ey = 0.75 * wv * cos(t), 0.6 * wv * sin(t)
        ring[#ring + 1] = { p[1] + ex * cos(a) - ey * sin(a), p[2] + ex * sin(a) + ey * cos(a) }
      end
      ink.smooth(ring, true) ink.fill(DARK)
      nodes = nodes + 1
      side = -side
      local sa = a + side * rng.range(45, 70) * rad
      if rng.chance(o.spurs) then
        local L = rng.range(1.2, 2.6) * u
        local ok = true
        for _, f in ipairs({ 0.4, 0.8, 1.0 }) do
          if not clear(p[1] + cos(sa) * L * f, p[2] + sin(sa) * L * f, si, i, 0.9 * wv) then ok = false break end
        end
        if ok then
          local was = ink.set_pale(o.pale)        -- spurs and tendrils recede with the leaves
          local TW = tone(0.06)
          if rng.chance(0.3) then                   -- a tendril: out, then a tightening curl
            local c, x, y, h = { { p[1], p[2] } }, p[1], p[2], sa
            local turn = side * rng.range(0.11, 0.16)
            for kk = 1, 34 do
              h = h + turn * kk / 17
              x, y = x + 0.14 * u * cos(h), y + 0.14 * u * sin(h)
              c[#c + 1] = { x, y }
            end
            flora.stem(c, 0.28 * wv, 0.06 * wv, TW)
          else                                      -- a spur: a short tapered stub
            local ca = sa - side * 0.25
            ink.taper(p[1], p[2], p[1] + cos(ca) * L * 0.35, p[2] + sin(ca) * L * 0.35, p[1] + cos(sa) * L * 0.7, p[2] + sin(sa) * L * 0.7,
              p[1] + cos(sa) * L, p[2] + sin(sa) * L, 0.5 * wv, 0.04 * wv)
            ink.fill(TW)
          end
          ink.set_pale(was)
        end
      end
      i = i + floor(rng.range(45, 75))
    end
  end
  ink.layer(5)
  strands(true)

  -- leaves, outside the letters' bodies (their tips above the x-height or below the
  -- baseline), and copper sparkles, pale
  local was = ink.set_pale(o.pale)
  ink.layer(6)
  local leaves = 0
  for si, pts in ipairs(paths) do
    local acc, side, run = u * rng.range(3, 5), rng.chance(0.5) and 1 or -1, 0
    for i = 3, #pts - 3 do
      run = run + dist(pts[i], pts[i - 1])
      if run >= acc then
        acc = run + u * rng.range(2.4, 4.0) / o.leaves
        side = -side
        local tx, ty = tangent(pts, i)
        local a = atan(ty, tx) / rad + side * rng.range(38, 62)
        local L = u * (rng.chance(0.25) and rng.range(5.5, 7.5) or rng.range(3.4, 5.4))
        local tipx, tipy = pts[i][1] + L * cos(a * rad), pts[i][2] + L * sin(a * rad)
        local ok = tipy > yx + 0.6 * u or tipy < yb - 0.6 * u or tipx < ox + k * x0 or tipx > ox + k * x1
        for _, f in ipairs(ok and { 0.3, 0.6, 0.95 } or {}) do
          if not clear(pts[i][1] + L * f * cos(a * rad), pts[i][2] + L * f * sin(a * rad), si, i, u * 1.0 + L * 0.12) then ok = false break end
        end
        if ok then
          leaves = leaves + 1
          ink.push() ink.translate(pts[i][1], pts[i][2]) ink.rotate(a - 90) ink.scale(L)
          flora.leaflet(rng, { bend = -side * 0.25 })
          ink.pop()
        end
      end
    end
  end
  ink.layer(7)
  for _, sp in ipairs(o.sparkles) do
    ink.push() ink.translate(sp[1] * W, sp[2] * H)
    ink.in_accent(function() flora.sparkle(rng, sp[3] * u) end)
    ink.pop()
  end
  ink.set_pale(was)

  -- where the pics go: the ascenders' peaks, the i's dots, the descenders' bottoms
  local peaks, lows, spots = {}, {}, {}
  for _, s in ipairs(strokes) do
    for i = 2, #s - 1 do
      local y = s[i][2]
      if y > yx + 6 * u and y >= s[i - 1][2] and y >= s[i + 1][2] then peaks[#peaks + 1] = s[i] end
      if y < yb - 8 * u and y <= s[i - 1][2] and y <= s[i + 1][2] then lows[#lows + 1] = s[i] end
    end
  end
  table.sort(peaks, function(a, b) return a[1] < b[1] end)
  table.sort(lows, function(a, b) return a[1] < b[1] end)
  for _, p in ipairs(peaks) do spots[#spots + 1] = { p[1], p[2], "top" } end
  for _, d in ipairs(fdots) do spots[#spots + 1] = { ox + k * d[1], oy + k * d[2], "dot" } end
  for _, p in ipairs(lows) do spots[#spots + 1] = { p[1], p[2], "low" } end
  ink.flush()
  M.spots = spots
  M.box = { ox + k * x0, oy + k * y0, ox + k * x1, oy + k * y1 }
  texio.write_nl(string.format("social: %d paths, %d nodes, %d leaves, %d spots", #paths, nodes, leaves, #spots))
end

-- The pics set ink's pale and lift to 0 for themselves (florilegium-native.lua, M.tikz). While
-- the pale ones draw, pale is held at no less than v; while the i's dots draw, lift is held
-- at v < 0, which pulls every tone toward the darkest (ink.tone: t + (1 - t) lift) and leaves
-- the white highlights white, so the dots are as dark as the letters.
local real_set_pale, real_set_lift
function M.pale(v)
  real_set_pale = real_set_pale or ink.set_pale
  ink.set_pale = function(x) return real_set_pale(max(x, v)) end
end
function M.unpale()
  if real_set_pale then ink.set_pale = real_set_pale real_set_pale = nil end
  ink.set_pale(0)
end
function M.dark(v)
  real_set_lift = real_set_lift or ink.set_lift
  ink.set_lift = function() return real_set_lift(v) end
end
function M.undark()
  if real_set_lift then ink.set_lift = real_set_lift real_set_lift = nil end
  ink.set_lift(0)
end

-- the pics, as TikZ, at the spots M.draw found. o.tops: per peak, left to right, {seed, size}
-- (a hero flower, size in font units) or {seed, scale, "stalk", role, angle} (an
-- inflorescence rising from the stroke's end); o.lows: seeds for the descenders' flowers;
-- o.dark: the dots' lift
function M.pics(o)
  local u = M.unit
  local out, dots = {}, {}
  local tops = o.tops or { { 7, 13 }, { 12, 1.5, "stalk", "spray", -14 }, { 26, 11 } }
  local lowseeds = o.lows or { 40, 44 }
  local nt, nd, nl = 0, 0, 0
  for _, s in ipairs(M.spots) do
    local x, y = s[1], s[2]
    if s[3] == "top" then
      nt = nt + 1
      local t = tops[nt] or { nt, 10 }
      if t[3] == "stalk" then
        out[#out + 1] = string.format("\\pic[rotate=%.1f] at (%.3f,%.3f) {florilegium inflorescence={seed=%d, role=%s, scale=%.3f}};", t[5] or -8, x, y - u * 0.3, t[1], t[4] or "spray", t[2])
      else
        out[#out + 1] = string.format("\\pic at (%.3f,%.3f) {florilegium flower={seed=%d, role=hero, size=%.3fcm}};", x, y + u * t[2] * 0.22, t[1], u * t[2])
      end
    elseif s[3] == "dot" then
      nd = nd + 1
      dots[#dots + 1] = string.format("\\pic at (%.3f,%.3f) {florilegium flower={seed=%d, role=spray, size=%.3fcm}};", x, y + u * 0.8, (o.dotseed or 31) + nd, u * 4.5)
    else
      nl = nl + 1
      out[#out + 1] = string.format("\\pic at (%.3f,%.3f) {florilegium flower={seed=%d, role=spray, size=%.3fcm}};", x, y - u * 1.2, lowseeds[nl] or 40 + nl, u * 6.5)
    end
  end
  out[#out + 1] = string.format("\\pic at (%.3f,%.3f) {florilegium visitor={seed=%d, role=butterfly, size=%.3fcm}};",
    M.box[3] - (M.box[3] - M.box[1]) * 0.1, M.box[4] + u * 4, o.butterfly or 5, u * 11)
  tex.sprint("\\directlua{social.pale(" .. M.o.pale .. ")} " .. table.concat(out, " ") .. " \\directlua{social.unpale()} " ..
    "\\directlua{social.dark(" .. (o.dark or -0.7) .. ")} " .. table.concat(dots, " ") .. " \\directlua{social.undark()}")
end

return M
