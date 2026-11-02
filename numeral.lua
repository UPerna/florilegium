-- Adapted from K1o0n/florilegium, commit 72ebc0f (MIT).
-- numeral.lua -- the page number as stems (option pagenumber, grown only).
--
-- Each digit is one or two strokes through a few control points in a unit box
-- (height 1, baseline 0), written the way a plant would grow them: every
-- stroke starts at its root and ends free. The first stroke's root sits on the
-- baseline, where the digit grows out of the footer stem; a second stroke
-- (the tails of 3, 5, 9, the bowl of 6) starts at that same root. A free end
-- curls into a small spiral (spin +1 turns left, -1 right) or carries a leaflet.
-- grow.lua maps the unit box onto the page so that y = 0 follows the footer
-- stem, draws the strokes as tapered stems and keeps the digits clear.

local M = {}

local sqrt, cos, sin, atan, pi, max, min = math.sqrt, math.cos, math.sin, math.atan, math.pi, math.max, math.min

local TAIL = { { 0, 0 }, { -0.14, 0.03 }, { -0.22, 0.12 } }    -- relative to the root
local function tail(rx) local t = {} for i, p in ipairs(TAIL) do t[i] = { rx + p[1], p[2] } end return t end

M.glyphs = {
  ["0"] = { w = 0.6, strokes = {
    { { 0.30, 0.00 }, { 0.47, 0.04 }, { 0.57, 0.22 }, { 0.60, 0.50 }, { 0.54, 0.80 }, { 0.40, 0.97 }, { 0.24, 0.98 },
      { 0.10, 0.84 }, { 0.02, 0.56 }, { 0.04, 0.26 }, { 0.10, 0.10 }, { 0.20, 0.06 }, curl = 1 } } },
  ["1"] = { w = 0.42, strokes = {
    { { 0.24, 0.00 }, { 0.245, 0.35 }, { 0.25, 0.70 }, { 0.255, 0.93 }, { 0.22, 1.00 }, { 0.13, 0.94 }, { 0.05, 0.85 }, leaf = true } } },
  ["2"] = { w = 0.6, strokes = {
    { { 0.60, 0.00 }, { 0.38, 0.00 }, { 0.16, 0.00 }, { 0.05, 0.02 }, { 0.06, 0.09 }, { 0.20, 0.24 }, { 0.40, 0.42 },
      { 0.53, 0.60 }, { 0.55, 0.78 }, { 0.46, 0.94 }, { 0.30, 0.99 }, { 0.15, 0.94 }, { 0.06, 0.82 }, curl = 1 } } },
  ["3"] = { w = 0.58, strokes = {
    { { 0.27, 0.00 }, { 0.45, 0.04 }, { 0.56, 0.18 }, { 0.55, 0.36 }, { 0.43, 0.49 }, { 0.24, 0.53 }, { 0.40, 0.58 },
      { 0.51, 0.70 }, { 0.50, 0.86 }, { 0.38, 0.97 }, { 0.22, 0.98 }, { 0.09, 0.90 }, curl = 1 },
    { curl = -1, tail = 0.27 } } },
  ["4"] = { w = 0.62, strokes = {
    { { 0.46, 0.00 }, { 0.46, 0.30 }, { 0.465, 0.65 }, { 0.47, 0.95 }, { 0.44, 1.00 }, { 0.36, 0.92 }, { 0.20, 0.68 },
      { 0.06, 0.42 }, { 0.04, 0.34 }, { 0.12, 0.32 }, { 0.35, 0.32 }, { 0.62, 0.33 }, leaf = true } } },
  ["5"] = { w = 0.58, strokes = {
    { { 0.27, 0.00 }, { 0.45, 0.04 }, { 0.56, 0.18 }, { 0.56, 0.36 }, { 0.45, 0.51 }, { 0.28, 0.56 }, { 0.14, 0.52 },
      { 0.10, 0.60 }, { 0.11, 0.80 }, { 0.12, 0.98 }, { 0.32, 0.99 }, { 0.56, 1.00 }, curl = -1 },
    { curl = -1, tail = 0.27 } } },
  ["6"] = { w = 0.58, strokes = {
    { { 0.30, 0.00 }, { 0.14, 0.05 }, { 0.05, 0.25 }, { 0.06, 0.55 }, { 0.16, 0.82 }, { 0.32, 0.97 }, { 0.48, 0.97 }, curl = -1 },
    { { 0.30, 0.00 }, { 0.46, 0.04 }, { 0.56, 0.20 }, { 0.54, 0.40 }, { 0.40, 0.53 }, { 0.22, 0.52 }, { 0.09, 0.42 } } } },
  ["7"] = { w = 0.6, strokes = {
    { { 0.22, 0.00 }, { 0.28, 0.25 }, { 0.40, 0.55 }, { 0.52, 0.80 }, { 0.60, 0.97 }, { 0.54, 1.00 }, { 0.36, 0.99 },
      { 0.18, 0.99 }, { 0.05, 0.97 }, curl = 1 } } },
  ["8"] = { w = 0.58, strokes = {
    { { 0.29, 0.00 }, { 0.46, 0.04 }, { 0.56, 0.18 }, { 0.53, 0.36 }, { 0.40, 0.47 }, { 0.29, 0.53 }, { 0.15, 0.61 },
      { 0.09, 0.76 }, { 0.15, 0.93 }, { 0.29, 0.99 }, { 0.44, 0.93 }, { 0.50, 0.77 }, { 0.43, 0.62 }, { 0.29, 0.53 },
      { 0.14, 0.44 }, { 0.04, 0.27 }, { 0.07, 0.10 }, { 0.17, 0.03 }, curl = 1 } } },
  ["9"] = { w = 0.58, strokes = {
    { { 0.24, 0.00 }, { 0.38, 0.04 }, { 0.49, 0.20 }, { 0.55, 0.45 }, { 0.55, 0.70 }, { 0.47, 0.90 }, { 0.30, 0.99 },
      { 0.14, 0.92 }, { 0.06, 0.74 }, { 0.11, 0.56 }, { 0.27, 0.48 }, { 0.44, 0.53 }, { 0.54, 0.62 } },
    { curl = -1, tail = 0.24 } } },
}
for _, gl in pairs(M.glyphs) do
  for _, st in ipairs(gl.strokes) do
    if st.tail then for i, p in ipairs(tail(st.tail)) do st[i] = p end end
  end
end

M.GAP = 0.1      -- between digits, in units of the height
M.SLANT = 0.05   -- a slight forward lean
M.NIB = 40       -- angle (degrees) of the broad nib: strokes along it are hairlines

-- Roman strokes share the same planted baseline and calligraphic treatment.
M.glyphs.I = {w=0.3,strokes={{{0.15,0},{0.15,0.45},{0.15,1},leaf=true}}}
M.glyphs.V = {w=0.7,strokes={{{0.35,0},{0.18,0.5},{0.02,1},curl=-1},{{0.35,0},{0.52,0.5},{0.68,1},leaf=true}}}
M.glyphs.X = {w=0.65,strokes={{{0.02,0},{0.32,0.5},{0.63,1},curl=-1},{{0.63,0},{0.32,0.5},{0.02,1},leaf=true}}}
M.glyphs.L = {w=0.6,strokes={{{0.04,0},{0.04,0.5},{0.04,1},leaf=true},{{0.04,0},{0.3,0},{0.6,0},curl=1}}}
M.glyphs.C = {w=0.62,strokes={{{0.53,0.02},{0.25,0},{0.04,0.25},{0.04,0.75},{0.25,1},{0.6,0.96},curl=-1}}}
M.glyphs.D = {w=0.65,strokes={{{0.04,0},{0.04,0.5},{0.04,1},leaf=true},{{0.04,0},{0.4,0.03},{0.64,0.3},{0.64,0.7},{0.4,0.97},{0.04,1}}}}
M.glyphs.M = {w=0.85,strokes={{{0.02,0},{0.02,0.5},{0.02,1},{0.42,0.35},{0.83,1},leaf=true},{{0.83,0},{0.83,0.5},{0.83,1},curl=-1}}}

function M.normalize(label)
  if type(label)~="string" or #label==0 or #label>16 then return nil end
  if label:match("^%d+$") then return #label<=6 and label or nil end
  if label:match("^[ivxlcdmIVXLCDM]+$") then return label:upper() end
  return nil
end

-- the width of a label in units of the height, or nil if it is not a number
function M.width(label)
  label=M.normalize(label)
  if not label then return nil end
  local w = 0
  for i = 1, #label do w = w + M.glyphs[label:sub(i, i)].w end
  return w + M.GAP * (#label - 1) + M.SLANT
end

-- a spiral that continues a polyline from its last point, turning left
-- (spin = 1) or right (-1) with radius r and the given number of turns
function M.curl(pts, spin, r, turns)
  local n = #pts
  local p, q = pts[n], pts[n - 1]
  local dx, dy = p[1] - q[1], p[2] - q[2]
  local L = sqrt(dx * dx + dy * dy)
  dx, dy = dx / L, dy / L
  local cx, cy = p[1] - spin * dy * r, p[2] + spin * dx * r
  local a0 = atan(p[2] - cy, p[1] - cx)
  local steps = 28
  for i = 1, steps do
    local u = i / steps
    local a = a0 + spin * u * turns * 2 * pi
    local rr = r * (1 - 0.82 * u) ^ 1.25
    pts[#pts + 1] = { cx + rr * cos(a), cy + rr * sin(a) }
  end
  return pts
end

return M
