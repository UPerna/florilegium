-- The native organs (florilegium-native.lua) against today's (florilegium-organs.lua's pgf
-- code, painted by ink): the same organ drawn both ways under the same transform, and the
-- two content streams compared token by token.
--   texlua tools/nativecheck.lua [DOCSEEDS [TOL]]     (from the repo root; default 12 0.1)
--   texlua tools/nativecheck.lua pages [N [TOL]]     (whole grown pages, seeds 1..N; default 20)
--   texlua tools/nativecheck.lua forms [TOL]         (species until every flower trait's value is seen)
--   texlua tools/nativecheck.lua ferns               (ferns until every fern trait's value is seen)
--   texlua tools/nativecheck.lua visitors [TOL]      (visitors until every value of their traits is seen)
-- For the first DOCSEEDS documents' pools (8 species each): blooms of three sizes, open and
-- past their best, a ghost, the inflorescence at two scales. Each organ is one of
--   same      the same operators, every number within TOL bp
--   shade     the same operators, a color one step of the ramp or an opacity one hundredth
--             apart (pgfmath's rounding and a double's on either side of a hundredth)
--   close     the same operators, numbers within 1 bp: where pgfmath is coarser than a double
--             (a fern's pinna is as wide as the difference of two of its pow()s, good to 1e-4)
--   tipped    a choice went the other way: the operators differ (listed, to be looked at)
-- and the times both ways are printed, with how much of the old time the new one takes.
package.path = "./?.lua;" .. package.path
local fmt = string.format
local data = {}
tex = { sprint = function() end }
luatexbase = { registernumber = function() return 0 end }
node = { new = function() return {} end, write = function(n) data[#data + 1] = n.data end }

local ink = require("florilegium-ink")
local species = require("florilegium-species")
local O = require("florilegium-organs")

local ndoc = tonumber(arg[1]) or 12
local tol = tonumber(arg[2]) or 0.1
local CM = ink.CM

local function draw(kind, sp, z, o)
  ink.set_transform({ CM, 0, 0, CM, 10 * CM, 10 * CM })
  data = {}
  ink.layer(5)
  O.draw(kind, sp, z, o)
  ink.flush()
  return table.concat(data)
end

local function tokens(s)
  local t = {}
  for w in s:gmatch("%S+") do t[#t + 1] = w end
  return t
end
-- "same", "shade" or "tipped", the largest difference in a coordinate, and a reason
local function compare(a, b)
  if a == b then return "same", 0 end
  local ta, tb = tokens(a), tokens(b)
  if #ta ~= #tb then return "tipped", 0, fmt("%d tokens before, %d now", #ta, #tb) end
  local worst, shade, at = 0, false, nil
  for i = 1, #ta do
    local x, y = ta[i], tb[i]
    if x ~= y then
      local u, v = tonumber(x), tonumber(y)
      if u and v then
        local nxt = ta[i + 1] or ""
        local color = nxt == "rg" or nxt == "RG" or (ta[i + 2] or "") == "rg" or (ta[i + 2] or "") == "RG"
          or (ta[i + 3] or "") == "rg" or (ta[i + 3] or "") == "RG"
        if color then
          -- one step of the ramp moves a channel by about 0.01; more is a different color
          if math.abs(u - v) > 0.04 then return "tipped", worst, fmt("token %d: color %s before, %s now", i, x, y) end
          shade = true
        elseif nxt == "w" then
          if math.abs(u - v) > 0.011 then return "tipped", worst, fmt("token %d: line width %s before, %s now", i, x, y) end
        else
          local d = math.abs(u - v)
          if d > worst then worst, at = d, i end
        end
      elseif x:match("^/flo[am]%d+$") and y:match("^/flo[am]%d+$") and x:sub(1, 5) == y:sub(1, 5)
        and math.abs(tonumber(x:sub(6)) - tonumber(y:sub(6))) <= 1 then
        shade = true                                -- an opacity one hundredth apart
      else
        return "tipped", worst, fmt("token %d: '%s' before, '%s' now", i, x, y)
      end
    end
  end
  if worst > 1 + 1e-9 then return "tipped", worst, fmt("a number differs by %.2f bp (token %d)", worst, at) end
  if worst > tol + 1e-9 then return "close", worst end
  return shade and "shade" or "same", worst
end

-- whole pages: texlua tools/nativecheck.lua pages [N [TOL]] (N grown pages, seeds 1..N, the
-- odd ones with the text ending early, so the garden spills under it)
if arg[1] == "pages" then
  local svg = require("florilegium-svg")
  local n = tonumber(arg[2]) or 20
  tol = tonumber(arg[3]) or 0.1
  local function page(seed, on)
    O.native(on)
    local _, _, x = svg.page({ seed = seed, textend = seed % 2 == 1 and "150mm" or nil })
    return table.concat(x.streams, "\n")
  end
  local count, worst, tb, tn = { same = 0, shade = 0, close = 0, tipped = 0 }, 0, 0, 0
  for seed = 1, n do
    local t0 = os.clock()
    local a = page(seed, false)
    local t1 = os.clock()
    local b = page(seed, true)
    tb, tn = tb + t1 - t0, tn + os.clock() - t1
    local how, w, why = compare(a, b)
    count[how] = count[how] + 1
    if (how == "same" or how == "shade") and w > worst then worst = w end
    print(fmt("seed %3d  %-6s %s", seed, how, why or fmt("within %.2f bp", w)))
  end
  O.native(false)
  print(fmt("%d pages: %d the same (numbers within %.2f bp), %d a shade apart, %d close (within 1 bp), %d tipped; %.2f s a page before, %.2f now",
    n, count.same, worst, count.shade, count.close, count.tipped, tb / n, tn / n))
  return
end

-- the cases
local cases = {}
local function case(name, kind, sp, z, o) cases[#cases + 1] = { name = name, kind = kind, sp = sp, z = z, o = o } end
local z = 12345
local function nextz() z = (z * 69621) % 2147483647 return z end
-- forms: species chosen until every value of the flower's traits has been seen, each drawn
-- as a bud, open at three sizes (a floret, a blossom, a flower), past its best and in fruit,
-- held to either side, and as a ghost
if arg[1] == "forms" then
  ndoc = 0
  tol = tonumber(arg[2]) or 0.1
  local seen, TR = {}, { "form", "orient", "fruit", "corona", "guides", "color", "apex", "stamens", "petalshape",
    "merovar", "clade", "inflo" }
  local roles = { "any", "hero", "spray", "monocot" }
  local LTR = { "compound", "leafshape", "leafbase", "leafapex", "leafmargin", "venation", "attachment", "stipules",
    "hairy", "tendrils", "turns", "leaflets" }
  for i = 1, 4000 do
    local role = roles[i % 4 + 1]
    local sp = species.sample(i, role)
    local new = false
    for _, t in ipairs(TR) do
      local key = t .. "=" .. tostring(sp[t])
      if not seen[key] then seen[key] = true new = true end
    end
    local key = "fo=" .. sp.form .. "/" .. sp.orient
    if not seen[key] then seen[key] = true new = true end
    if new then
      local s = { seed = i, role = role }
      local name = fmt("seed %d %s %s/%s/%s", i, role, sp.form, sp.orient, sp.fruit)
      for _, c in ipairs({ { 0.2, 1.2 }, { 0.7, 0.2 }, { 0.7, 0.6 }, { 0.7, 1.5 }, { 1.08, 1.6 }, { 1.3, 1.2 } }) do
        case(name .. fmt(" bloom %.1f at %.2f", c[2], c[1]), "bloom", s, nextz(), { d = c[2], stage = c[1] })
      end
      case(name .. " ghost", "ghost", s, nextz(), { d = 2.2 })
      for _, c in ipairs({ { 1, 0.55, 0 }, { 1.6, 0.1, 0 }, { 0.6, 0.8, 0.2 }, { 1.2, 1, 0 } }) do
        case(name .. fmt(" unit %.1f at %.2f", c[1], c[2]), "unit", s, nextz(), { k = c[1], season = c[2], late = c[3] })
      end
    end
    -- the leaves: every value of the leaf's traits, at three sizes, in spring and autumn,
    -- copper, foreshortened and sheathing
    local lnew = false
    for _, t in ipairs(LTR) do
      local lkey = t .. "=" .. tostring(sp[t])
      if not seen[lkey] then seen[lkey] = true lnew = true end
    end
    if (lnew or new) and sp.compound ~= "frond" then
      local s = { seed = i, role = role }
      local name = fmt("seed %d %s %s/%s/%s/%s", i, role, sp.compound, sp.leafshape, sp.leafmargin, sp.venation)
      for _, c in ipairs({ { 0.5, 0.55, 0.5 }, { 1.2, 0.55, 0.5 }, { 2.4, 0.6, 0.5 }, { 1.6, 0.2, 0.5 }, { 1.6, 1, 0.01 } }) do
        case(name .. fmt(" leaf %.1f at %.2f", c[1], c[2]), "leaf", s, nextz(), { len = c[1], bend = 0.15, lc = c[3], season = c[2] })
      end
      case(name .. " leaf sheathing", "leaf", s, nextz(), { len = 1.8, bend = -0.2, lc = 0.5, season = 0.6, fore = 0.75,
        sheath = { -25, 0.1 } })
    end
  end
end
if arg[1] == "forms" then                      -- a fern's "inflorescence": the blossoms fallback
  for doc = 0, 3 do
    local f = species.fern(doc)
    case(fmt("fern %d blossoms", doc), "unit", { seed = f.seed, role = "fern" }, nextz(), { k = 1, season = 0.5, late = 0 })
  end
end
-- ferns: every value of the fern's traits; fronds open and unrolling, fertile, seen from
-- beneath, in autumn, and as a leaf
if arg[1] == "forms" or arg[1] == "ferns" then
  local seen = {}
  local FT = { "division", "pinnae", "outline", "sori", "dimorphic", "leafapex", "leafmargin", "leafshape", "hairy",
    "turns" }
  for i = 1, 3000 do
    local sp = species.sample(i, "fern")
    local new = false
    for _, t in ipairs(FT) do
      local key = t .. "=" .. tostring(sp[t])
      if not seen[key] then seen[key] = true new = true end
    end
    if new then
      local s = { seed = i, role = "fern" }
      local name = fmt("fern %d %s/%s/%s/%s", i, sp.division, sp.outline, sp.sori, sp.leafmargin)
      for _, c in ipairs({ { 4.5, 1, 30, false, false, 0.6 }, { 2.4, 1, -45, false, true, 0.7 },
        { 3.2, 0.55, 20, false, false, 0.4 }, { 1.4, 0.1, -10, false, false, 0.15 }, { 3.6, 1, 8, true, false, 0.8 },
        { 3, 1, 25, false, false, 0.97 } }) do
        case(name .. fmt(" frond %.1f unrolled %.2f%s%s", c[1], c[2], c[4] and " fertile" or "", c[5] and " under" or ""),
          "frond", s, nextz(), { len = c[1], unroll = c[2], arch = c[3], fertile = c[4], under = c[5], lc = 0.01, season = c[6] })
      end
      case(name .. " leaf", "leaf", s, nextz(), { len = 2.6, bend = 0.1, lc = 0.5, season = 0.6 })
    end
  end
end
if arg[1] == "ferns" then ndoc, tol = 0, tonumber(arg[2]) or 0.1 end
-- visitors: sampled for each role in turn (the pollinators', the leaf's, the stem's, the
-- perch's, any, and each kind by name) until every value of every trait that takes whole
-- or named values has been seen on every kind that has it; each drawn at four sizes, from
-- one too small for detail to a large one (a dragonfly's net of veins)
if arg[1] == "visitors" then
  ndoc, tol = 0, tonumber(arg[2]) or 0.1
  local roles = {}
  for r in pairs(species.VROLES) do roles[#roles + 1] = r end
  table.sort(roles)
  for _, k in ipairs(species.VKINDS) do roles[#roles + 1] = k.name end
  local seen, nv, VSP = {}, 0, { seed = 0, role = "visitor" }
  for i = 1, 6000 do
    local role = roles[i % #roles + 1]
    local v = species.vsample(i, role)
    local new = false
    for _, t in ipairs(species.VTRAITS) do
      if math.type(v[t]) ~= "float" then
        local key = v.kind .. " " .. t .. "=" .. tostring(v[t])
        if not seen[key] then seen[key] = true new = true end
      end
    end
    if new then
      nv = nv + 1
      local name = fmt("visitor %d %s %s/%s/%s", i, role, v.kind, v.pose, v.ground)
      for _, cm in ipairs({ 0.2, 0.6, 1.2, 2.5 }) do
        case(name .. fmt(" %.1f cm", cm), "visitor", VSP, 0, { seed = i, role = role, size = cm })
      end
    end
  end
  local nk = 0
  for _ in pairs(seen) do nk = nk + 1 end
  print(fmt("%d visitors for %d values of their traits", nv, nk))
end
for doc = 0, ndoc - 1 do
  for i, sp in ipairs(species.pool(doc)) do
    local s = { seed = sp.seed, role = sp.role }
    local name = fmt("doc %d #%d %s/%s/%s", doc, i, sp.plan, sp.form, sp.inflo)
    for _, d in ipairs({ 0.5, 1.2, 2.4 }) do
      case(name .. fmt(" bloom %.1f", d), "bloom", s, nextz(), { d = d, stage = 0.7 })
    end
    case(name .. " bloom past", "bloom", s, nextz(), { d = 1.6, stage = 1.08 })
    case(name .. " ghost", "ghost", s, nextz(), { d = 2.2 })
    case(name .. " unit 1", "unit", s, nextz(), { k = 1, season = 0.5, late = 0 })
    case(name .. " unit 0.5", "unit", s, nextz(), { k = 0.5, season = 0.6, late = 0.1 })
    case(name .. " unit in bud", "unit", s, nextz(), { k = 1.4, season = 0.1, late = 0 })
    case(name .. " unit in fruit", "unit", s, nextz(), { k = 1.2, season = 1, late = 0 })
    case(name .. " budding", "budding", s, nextz(), { k = 1 })
    for _, c in ipairs({ { 0.6, 0.55 }, { 1.4, 0.55 }, { 2.2, 0.3 }, { 1.8, 0.97 } }) do
      case(name .. fmt(" leaf %.1f", c[1]), "leaf", s, nextz(), { len = c[1], bend = 0.12, lc = 0.02, season = c[2] })
    end
    case(name .. " leaf sheath", "leaf", s, nextz(), { len = 1.6, bend = -0.1, lc = 0.5, season = 0.6, fore = 0.8,
      sheath = { 30, 0.12 } })
    case(name .. " tendril", "tendril", s, nextz(), { size = 0.4 })
  end
end

-- both ways: today's path, then florilegium-native.lua's own organs where it has them
-- (FLORILEGIUM_NATIVE's hooks for the rest)
local NV = require("florilegium-native")
local function native(kind, sp, seed, o)
  ink.set_transform({ CM, 0, 0, CM, 10 * CM, 10 * CM })
  data = {}
  ink.layer(5)
  if not NV.draw(kind, sp, seed, o) then O.draw(kind, sp, seed, o) end
  ink.flush()
  return table.concat(data)
end
local before, now = {}, {}
O.native(false)
local t0 = os.clock()
for i, c in ipairs(cases) do before[i] = draw(c.kind, c.sp, c.z, c.o) end
local t1 = os.clock()
O.native(true)
for i, c in ipairs(cases) do now[i] = native(c.kind, c.sp, c.z, c.o) end
local t2 = os.clock()
O.native(false)

local count, worst, bytes = { same = 0, shade = 0, close = 0, tipped = 0 }, 0, { 0, 0 }
for i, c in ipairs(cases) do
  local how, w, why = compare(before[i], now[i])
  count[how] = count[how] + 1
  if (how == "same" or how == "shade") and w > worst then worst = w end
  bytes[1], bytes[2] = bytes[1] + #before[i], bytes[2] + #now[i]
  if how == "tipped" then print(fmt("tipped  %-58s %s (z %d)", c.name, why, c.z)) end
end
print(fmt("%d organs: %d the same (numbers within %.2f bp), %d a shade apart, %d close (within 1 bp), %d tipped",
  #cases, count.same, worst, count.shade, count.close, count.tipped))
print(fmt("bytes: %.1f MB before, %.1f MB now", bytes[1] / 1e6, bytes[2] / 1e6))
print(fmt("time: %.2f s before, %.2f s now (%.0f%%)", t1 - t0, t2 - t1, 100 * (t2 - t1) / (t1 - t0)))
