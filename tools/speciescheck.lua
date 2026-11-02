-- Check the species tables without TeX: every sampled species keeps the rules of
-- florilegium-species.lua, the body plans and traits are spread as intended, and the
-- generated TikZ tables are current.
--   texlua tools/speciescheck.lua [N]          (from the repo root; N species and N/10 ferns, default 10000)
--   texlua tools/speciescheck.lua --pools K     K documents' pools, in words
--   texlua tools/speciescheck.lua --log a b     choice logs of seeds a..b, role any (for tikzcheck)
package.path = "./?.lua;" .. package.path
local species = require("florilegium-species")
local fmt = string.format

local function value(v)                      -- a logged value as TeX writes it: integers bare, reals to 5 places
  if math.type(v) == "float" then return fmt("%.5f", v) end
  return tostring(v)
end

if arg[1] == "--log" then
  for seed = tonumber(arg[2]), tonumber(arg[3]) do
    local line = { fmt("seed=%d", seed) }
    species.sample(seed, "any", function(t, v) line[#line + 1] = t .. "=" .. value(v) end)
    print(table.concat(line, " "))
  end
  return
end

if arg[1] == "--pools" then
  for doc = 1, tonumber(arg[2] or 3) do
    print(fmt("Document seed %d:", doc))
    for _, sp in ipairs(species.pool(doc)) do
      print(fmt("  %-8s %-10s %s", sp.role, sp.plan, species.describe(sp)))
    end
    print()
  end
  return
end

local N = tonumber(arg[1]) or 10000
local roles = { "hero", "spray", "monocot", "any" }
local bad, hist = 0, {}
local function count(t, v) hist[t] = hist[t] or {} hist[t][v] = (hist[t][v] or 0) + 1 end
for seed = 1, N do
  local role = roles[1 + seed % 4]
  local sp = species.sample(seed, role)
  local v = species.violations(sp)
  if #v > 0 then
    bad = bad + 1
    if bad <= 10 then print(fmt("seed %d (%s, %s): %s", seed, role, sp.plan, table.concat(v, "; "))) end
  end
  for _, t in ipairs({ "plan", "syndrome", "form", "merosity", "inflo", "compound", "leafmargin", "venation", "arrangement", "fruit" }) do
    count(t, sp[t])
  end
  -- the same seed must give the same species again
  local again = species.sample(seed, role)
  for _, t in ipairs(species.TRAITS) do
    if again[t] ~= sp[t] then error(fmt("seed %d: %s differs on a second draw", seed, t)) end
  end
  species.describe(sp)
end
-- ferns (only the role fern draws them), one for every ten flowering plants
local NF = math.max(1, N // 10)
for seed = 1, NF do
  local sp = species.sample(seed, "fern")
  local v = species.violations(sp)
  if sp.plan ~= "fern" then v[#v + 1] = "the role fern drew " .. sp.plan end
  if #v > 0 then
    bad = bad + 1
    if bad <= 10 then print(fmt("seed %d (fern): %s", seed, table.concat(v, "; "))) end
  end
  for _, t in ipairs({ "division", "pinnae", "outline", "sori", "dimorphic" }) do count("fern " .. t, sp[t]) end
  species.describe(sp)
end
for _, t in ipairs({ "plan", "syndrome", "form", "merosity", "inflo", "compound", "leafmargin", "venation", "arrangement", "fruit",
  "fern division", "fern pinnae", "fern outline", "fern sori", "fern dimorphic" }) do
  local ks = {}
  for k in pairs(hist[t]) do ks[#ks + 1] = k end
  table.sort(ks, function(a, b) return hist[t][a] > hist[t][b] or (hist[t][a] == hist[t][b] and tostring(a) < tostring(b)) end)
  local parts = {}
  local n = t:match("^fern ") and NF or N
  for _, k in ipairs(ks) do parts[#parts + 1] = fmt("%s %.1f%%", tostring(k), 100 * hist[t][k] / n) end
  print(fmt("%-15s %s", t, table.concat(parts, ", ")))
end

-- the generated TeX must match the tables
local f = io.open("tikzlibraryflorilegium.tables.code.tex")
local stale = not f or f:read("a") ~= species.tex()
if f then f:close() end
if stale then print("tikzlibraryflorilegium.tables.code.tex is stale: texlua tools/tikztables.lua") end

print(fmt("%d species and %d ferns, %d broke a rule", N, NF, bad))
os.exit((bad == 0 and not stale) and 0 or 1)
