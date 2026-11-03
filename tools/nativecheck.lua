-- The native organs (florilegium-native.lua) against today's (florilegium-organs.lua's pgf
-- code, painted by ink): the same organ drawn both ways under the same transform, and the
-- two content streams compared token by token.
--   texlua tools/nativecheck.lua [DOCSEEDS [TOL]]     (from the repo root; default 12 0.1)
--   texlua tools/nativecheck.lua pages [N [TOL]]     (whole grown pages, seeds 1..N; default 20)
--   texlua tools/nativecheck.lua forms [TOL]         (species until every flower trait's value is seen)
-- For the first DOCSEEDS documents' pools (8 species each): blooms of three sizes, open and
-- past their best, a ghost, the inflorescence at two scales. Each organ is one of
--   same      the same operators, every number within TOL bp
--   shade     the same operators, a color or an opacity one step apart (pgfmath's rounding
--             and a double's on either side of a hundredth)
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
        if color then shade = true
        elseif nxt == "w" then
          if math.abs(u - v) > 0.011 then return "tipped", worst, fmt("token %d: line width %s before, %s now", i, x, y) end
        else
          local d = math.abs(u - v)
          if d > worst then worst, at = d, i end
        end
      elseif x:match("^/flo[am]%d+$") and y:match("^/flo[am]%d+$") and x:sub(1, 5) == y:sub(1, 5) then
        shade = true
      else
        return "tipped", worst, fmt("token %d: '%s' before, '%s' now", i, x, y)
      end
    end
  end
  if worst > tol + 1e-9 then return "tipped", worst, fmt("a number differs by %.2f bp (token %d)", worst, at) end
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
  local count, worst, tb, tn = { same = 0, shade = 0, tipped = 0 }, 0, 0, 0
  for seed = 1, n do
    local t0 = os.clock()
    local a = page(seed, false)
    local t1 = os.clock()
    local b = page(seed, true)
    tb, tn = tb + t1 - t0, tn + os.clock() - t1
    local how, w, why = compare(a, b)
    count[how] = count[how] + 1
    if how ~= "tipped" and w > worst then worst = w end
    print(fmt("seed %3d  %-6s %s", seed, how, why or fmt("within %.2f bp", w)))
  end
  O.native(false)
  print(fmt("%d pages: %d the same (numbers within %.2f bp), %d a shade apart, %d tipped; %.2f s a page before, %.2f now",
    n, count.same, worst, count.shade, count.tipped, tb / n, tn / n))
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
    if new and sp.form ~= "none" then
      local s = { seed = i, role = role }
      local name = fmt("seed %d %s %s/%s/%s", i, role, sp.form, sp.orient, sp.fruit)
      for _, c in ipairs({ { 0.2, 1.2 }, { 0.7, 0.2 }, { 0.7, 0.6 }, { 0.7, 1.5 }, { 1.08, 1.6 }, { 1.3, 1.2 } }) do
        case(name .. fmt(" bloom %.1f at %.2f", c[2], c[1]), "bloom", s, nextz(), { d = c[2], stage = c[1] })
      end
      case(name .. " ghost", "ghost", s, nextz(), { d = 2.2 })
      case(name .. " unit 1", "unit", s, nextz(), { k = 1, season = 0.55, late = 0 })
    end
  end
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
  end
end

-- both ways
local before, now = {}, {}
O.native(false)
local t0 = os.clock()
for i, c in ipairs(cases) do before[i] = draw(c.kind, c.sp, c.z, c.o) end
local t1 = os.clock()
O.native(true)
for i, c in ipairs(cases) do now[i] = draw(c.kind, c.sp, c.z, c.o) end
local t2 = os.clock()
O.native(false)

local count, worst, bytes = { same = 0, shade = 0, tipped = 0 }, 0, { 0, 0 }
for i, c in ipairs(cases) do
  local how, w, why = compare(before[i], now[i])
  count[how] = count[how] + 1
  if how ~= "tipped" and w > worst then worst = w end
  bytes[1], bytes[2] = bytes[1] + #before[i], bytes[2] + #now[i]
  if how == "tipped" then print(fmt("tipped  %-58s %s", c.name, why)) end
end
print(fmt("%d organs: %d the same (numbers within %.2f bp), %d a shade apart, %d tipped",
  #cases, count.same, worst, count.shade, count.tipped))
print(fmt("bytes: %.1f MB before, %.1f MB now", bytes[1] / 1e6, bytes[2] / 1e6))
print(fmt("time: %.2f s before, %.2f s now (%.0f%%)", t1 - t0, t2 - t1, 100 * (t2 - t1) / (t1 - t0)))
