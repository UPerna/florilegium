-- Botanical page labels. Stroke design adapted from K1o0n/florilegium (MIT),
-- commit 72ebc0f; layout, Roman support and upright mirroring added here.
local ink, numeral = require("ink"), require("numeral")
local flora = require("flora")
local M = {}
local min, max, sqrt, atan, sin, abs = math.min, math.max, math.sqrt, math.atan, math.sin, math.abs
local rad = math.pi / 180
local function lerp(a,b,t) return a+(b-a)*t end
local function norm(x,y) local d=sqrt(x*x+y*y);return d>0 and x/d or 0,d>0 and y/d or 1 end
local function deg(x,y) return atan(y,x)/rad end

function M.layout(g, options, root, foot)
  if not options.page_number then return nil end
  local label = numeral.normalize(g.number)
  local W = label and numeral.width(label)
  if not W then return nil end
  local xmin, xr = max(root[1]+1.4,2.6), g.colright-0.25
  local H = min(3*options.number_scale,0.46*g.colright,(xr-xmin)/W)
  if H <= 0.9 then return nil end
  local baseline=(foot[2]+foot[4])/2-0.05
  if baseline<0.5 then return nil end
  local n = {H=H,label=label,x0=xmin+(xr-xmin-W*H)/2,ytop=baseline+H}
  if g.ph and n.ytop+0.6>g.ph then return nil end
  n.x1=n.x0+W*H
  for _,r in ipairs(g.reserves or {}) do
    if n.x1+0.5>=r[1] and n.x0-0.5<=r[3] and n.ytop+0.6>=r[2] and foot[2]-0.3<=r[4] then return nil end
  end
  return n
end

function M.draw(num, g, api)
  local stem, place, event = api.stem, api.place, api.event
  local add_stem_points, disc, footpts, L_LEAF = api.add_stem_points, api.disc, api.footpts, api.leaf_layer
    local nrng = ink.rng(g.seed * 7919 + 307)
    local function fy(x)
      if x <= footpts[1][1] then return footpts[1][2] end
      for i = 2, #footpts do
        local a, b = footpts[i - 1], footpts[i]
        if x <= b[1] then return lerp(a[2], b[2], (x - a[1]) / (b[1] - a[1])) end
      end
      return footpts[#footpts][2]
    end
    local H, x, ylo = num.H, num.x0, math.huge
    local function leaflet(ev, at, px, py, a, ls, bend)
      local sd = nrng.int(1, 0x3fffffff)
      event({ kind = "bloom", parent = ev, at = at, size = ls })
      place(L_LEAF, px, py, a, function() ink.scale(ls) flora.leaflet(ink.rng(sd), { bend = bend }) end)
    end
    for i = 1, #num.label do
      local gl = numeral.glyphs[num.label:sub(i, i)]
      local function map(p)
        local px = x + (p[1] + numeral.SLANT * p[2]) * H
        if g.mirror then px = num.x0 + num.x1 - px end
        local y0 = fy(px)
        ylo = min(ylo, y0)
        return { px, lerp(y0, num.ytop, p[2]) }
      end
      local c = map({ gl.w / 2, 0.5 })
      local ls0 = min(0.6, max(0.32, 0.19 * H))
      for k, st in ipairs(gl.strokes) do
        local ctrl = {}
        for j, p in ipairs(st) do ctrl[j] = map(j == 1 and p or { p[1] + nrng.sym(0.012), p[2] + nrng.sym(0.012) }) end
        local pts = ink.catmull(ctrl, 8)
        local nbody = #pts
        if st.curl then numeral.curl(pts, st.curl, (k == 1 and 0.075 or 0.06) * H, nrng.range(1.1, 1.4)) end
        local s, L = ink.arclen(pts)
        -- a broad nib: the taper of a stem, thicker where the stroke runs across
        -- the nib's angle and a hairline along it, so the digit reads as lettering
        local w0, w1 = k == 1 and 0.12 or 0.09, 0.045
        local wpt = {}
        for j = 1, #pts do
          local a, b = pts[max(1, j - 1)], pts[min(#pts, j + 1)]
          local th = atan(b[2] - a[2], (g.mirror and -1 or 1) * (b[1] - a[1])) - numeral.NIB * rad
          wpt[j] = lerp(w0, w1, (s[j] / L) ^ 1.6) * (0.32 + 0.68 * abs(sin(th)))
        end
        local function width(u)
          local at, lo, hi = u * L, 1, #s
          while hi - lo > 1 do local mid = (lo + hi) // 2 if s[mid] <= at then lo = mid else hi = mid end end
          return lerp(wpt[lo], wpt[hi], s[hi] > s[lo] and min(1, max(0, (at - s[lo]) / (s[hi] - s[lo]))) or 0)
        end
        local ev = event({ kind = "stem", phase = "stems", off = 0.45 + 0.12 * (i - 1) })
        stem(pts, width, nil, 0.16)
        -- the upper part of the digit can carry branches: what grows just above
        -- the number grows out of it (the box below keeps its inside clear)
        local run = {}
        for j = 1, nbody + 1 do
          local p = pts[j]
          if j <= nbody and p[2] > c[2] + 0.3 * H then run[#run + 1] = p
          elseif #run > 2 then add_stem_points(run, 0.05, 0.03, 2) run = {} else run = {} end
        end
        local function frame(at)
          local j = 2
          while j < #pts - 1 and s[j] < at do j = j + 1 end
          local tx, ty = norm(pts[j + 1][1] - pts[j - 1][1], pts[j + 1][2] - pts[j - 1][2])
          return j, tx, ty
        end
        if k == 1 then
          local nl = nrng.int(1, 2)
          for m = 1, nl do
            local u = nl == 1 and nrng.range(0.38, 0.6) or (m == 1 and nrng.range(0.22, 0.36) or nrng.range(0.55, 0.7))
            local j, tx, ty = frame(u * L)
            local p = pts[j]
            local side = (p[1] - c[1]) * -ty + (p[2] - c[2]) * tx >= 0 and 1 or -1
            leaflet(ev, s[j] / L, p[1], p[2], deg(tx, ty) + side * nrng.range(35, 50), ls0 * nrng.range(0.85, 1.05), -side * nrng.range(0.1, 0.25))
          end
        end
        if st.leaf then
          local p, q = pts[#pts], pts[#pts - 1]
          local tx, ty = norm(p[1] - q[1], p[2] - q[2])
          leaflet(ev, 1, p[1], p[2], deg(tx, ty), ls0 * 1.1, nrng.sym(0.15))
        end
      end
      x = x + (gl.w + numeral.GAP) * H
    end
    -- keep the digits legible: proxies over their box
    for bx = num.x0 - 0.1, num.x1 + 0.1, 0.25 do
      for by = ylo, num.ytop + 0.1, 0.25 do disc(bx, by, 0.2, 1) end
    end
  return {num.x0,ylo,num.x1,num.ytop}
end
return M
