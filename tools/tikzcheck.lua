-- TikZ and Lua must find the same species for the same seed, and draw the same plant.
--
-- Choices: compiles tools/tikzcheck.tex (the pure-TikZ library draws species FROM..TO and
-- writes their choices), samples the same seeds with florilegium-species.lua, and compares
-- them, every choice and every real-valued trait exactly (both are pgfmath's numbers).
--   texlua tools/tikzcheck.lua [FROM TO [ENGINE]]   (from the repo root; default 1 1000 lualatex)
--   tools/in-docker texlua tools/tikzcheck.lua 1 1000 pdflatex
--
-- Drawings: builds tools/tikzcheck-draw.tex twice under LuaLaTeX, once with the pure-TikZ
-- library and once with the hybrid (engine=lua: florilegium-organs.lua computes, TikZ
-- draws), uncompressed, and compares each page's content stream: the same operators in
-- the same order and every number within 0.05 bp; the streams are expected to be equal.
--   texlua tools/tikzcheck.lua draw [quick|full]      (quick: one flower, one leaf and one
--   inflorescence of every body plan, one inflorescence of every kind and of every view,
--   the v1.3 pics, a plant in three seasons; full: also two strips of three plants, as specimen-tikz.tex
--   draws them, several minutes in pure TikZ)
package.path = "./?.lua;" .. package.path
local fmt = string.format
os.execute("mkdir -p build")

-- ================================================================ drawings
local function streams(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a")
  f:close()
  local t = {}
  for s in d:gmatch("stream\r?\n(.-)endstream") do t[#t + 1] = s end
  return t
end
-- the tokens of two streams: same operators, numbers within tol; returns nil or a reason
local function compare(a, b, tol)
  if a == b then return nil, 0 end
  local ta, tb = {}, {}
  for w in a:gmatch("%S+") do ta[#ta + 1] = w end
  for w in b:gmatch("%S+") do tb[#tb + 1] = w end
  if #ta ~= #tb then return fmt("%d tokens in TikZ, %d in Lua", #ta, #tb), 0 end
  local worst, n = 0, 0
  for i = 1, #ta do
    local x, y = ta[i], tb[i]
    if x ~= y then
      local u, v = tonumber(x), tonumber(y)
      if not (u and v) then return fmt("token %d: '%s' in TikZ, '%s' in Lua", i, x, y), worst end
      n = n + 1
      worst = math.max(worst, math.abs(u - v))
    end
  end
  if worst > tol then return fmt("%d numbers differ, by up to %.4f bp", n, worst), worst end
  return nil, worst
end

if arg[1] == "draw" then
  local full = arg[2] == "full"
  local species = require("florilegium-species")
  local pics = {}
  local function pic(spec) pics[#pics + 1] = spec end
  for i, p in ipairs(species.PLANS) do
    pic(fmt("florilegium flower={seed=%d, role=%s, size=2.6cm}", 10 + 7 * i, p.name))
    pic(fmt("florilegium leaf={seed=%d, role=%s, size=3.4cm}", 11 + 7 * i, p.name))
    pic(fmt("florilegium inflorescence={seed=%d, role=%s, scale=1, season=0.85}", 12 + 7 * i, p.name))
  end
  -- an inflorescence of every kind (the first seed that has it), a few also in bud and in fruit
  local SEASONS = { monochasium = { "0.3", "1.3" }, dichasium = { "1.3" }, catkin = { "0.3", "1.3" }, umbel = { "0.3" },
    spike = { "1.3" } }
  for _, kind in ipairs({ "solitary", "raceme", "spike", "panicle", "corymb", "umbel", "cumbel", "dichasium",
    "monochasium", "head", "catkin", "thyrse" }) do
    local seed = 1
    while species.sample(seed, "any").inflo ~= kind do seed = seed + 1 end
    for _, season in ipairs({ "0.85", table.unpack(SEASONS[kind] or {}) }) do
      pic(fmt("florilegium inflorescence={seed=%d, role=any, scale=1.2, season=%s}", seed, season))
    end
  end
  -- every view of a flower: each form drawn in profile, a flat-faced tube held sideways,
  -- flowers at a tilt and from behind, a nodding lily, pea flowers (with guides, and in a
  -- head) and two-lipped flowers (with dots, with lines and stamens that stand out):
  -- form, orient, guides, stamens, inflorescence
  for _, v in ipairs({ { "campanulate" }, { "urceolate" }, { "tubular" }, { "funnelform" }, { "salverform", "horizontal" },
    { "rotate", "horizontal" }, { "rosaceous", "nodding" }, { "lily", "nodding" },
    { "papilionaceous", nil, "lines" }, { "papilionaceous", nil, nil, nil, "head" },
    { "bilabiate", nil, "dots" }, { "bilabiate", nil, "lines", "exserted" } }) do
    local seed = 1
    while true do
      local sp = species.sample(seed, "any")
      if sp.form == v[1] and (not v[2] or sp.orient == v[2]) and (not v[3] or sp.guides == v[3])
        and (not v[4] or sp.stamens == v[4]) and (not v[5] or sp.inflo == v[5]) then break end
      seed = seed + 1
    end
    pic(fmt("florilegium inflorescence={seed=%d, role=any, scale=1, season=0.75}", seed))
  end
  pic("florilegium v13 flower={seed=7, size=1.9cm}")
  pic("florilegium v13 leaf={seed=7, size=4cm}")
  for _, s in ipairs({ "0.15", "0.75", "1.3" }) do
    pic(fmt("florilegium plant={seed=17, role=rose, size=8.5cm, width=5.2cm, season=%s}", s))
  end
  if full then
    pic("florilegium plants={plants={3/rose,17/umbellifer,29/mustard}, size=21cm, width=6cm}")
    pic("florilegium plants={plants={3/daisy,17/lily,29/rose}, size=21cm, width=6cm}")
  end
  local f = assert(io.open("build/tikzcheck-draw.pics", "w"))
  for _, p in ipairs(pics) do f:write("\\begin{tikzpicture}\\pic {", p, "};\\end{tikzpicture}\\newpage\n") end
  f:close()
  local res = {}
  for _, engine in ipairs({ "tikz", "lua" }) do
    local job = "tikzcheck-draw-" .. engine
    os.remove("build/" .. job .. ".pdf")
    local t0 = os.time()
    os.execute(fmt([[lualatex -interaction=batchmode -output-directory=build -jobname=%s "\def\tikzcheckengine{%s}\input{tools/tikzcheck-draw.tex}" >/dev/null]],
      job, engine))
    local pdf = io.open("build/" .. job .. ".pdf", "rb")
    if not pdf then error("tikzcheck: the " .. engine .. " build failed, see build/" .. job .. ".log") end
    local size = pdf:seek("end")
    pdf:close()
    res[engine] = { secs = os.time() - t0, size = size, streams = streams("build/" .. job .. ".pdf") }
  end
  local a, b = res.tikz.streams, res.lua.streams
  assert(#a == #pics and #b == #pics, fmt("tikzcheck: %d pics, %d and %d pages", #pics, #a, #b))
  local bad, same, worst = 0, 0, 0
  for i = 1, #pics do
    local why, w = compare(a[i], b[i], 0.05)
    worst = math.max(worst, w)
    if a[i] == b[i] then same = same + 1 end
    if why then bad = bad + 1 print(fmt("page %d (%s): %s", i, pics[i], why)) end
  end
  print(fmt("tikzcheck draw: %d pics, %d streams identical, %d differ beyond 0.05 bp (largest difference %.4f bp)",
    #pics, same, bad, worst))
  print(fmt("  pure TikZ %d s, %d bytes; hybrid %d s, %d bytes", res.tikz.secs, res.tikz.size, res.lua.secs, res.lua.size))
  os.exit(bad == 0 and 0 or 1)
end

-- ================================================================ choices
local species = require("florilegium-species")
local pm = require("florilegium-pgfmath")
local from, to = tonumber(arg[1]) or 1, tonumber(arg[2]) or 1000
local engine = arg[3] or "lualatex"
local job = "tikzcheck-" .. engine

local cmd = fmt([[%s -interaction=batchmode -output-directory=build -jobname=%s "\def\tikzcheckfrom{%d}\def\tikzcheckto{%d}\input{tools/tikzcheck.tex}" >/dev/null]],
  engine, job, from, to)
local t0 = os.time()
os.remove("build/" .. job .. ".choices")
os.execute(cmd)
if not io.open("build/" .. job .. ".choices") then error("tikzcheck: " .. engine .. " failed, see build/" .. job .. ".log") end
local secs = os.time() - t0

local tex = {}
for line in io.lines("build/" .. job .. ".choices") do tex[#tex + 1] = line end
assert(#tex == to - from + 1, fmt("tikzcheck: %d species from TeX, expected %d", #tex, to - from + 1))

local function fields(line)
  local t = {}
  for k, v in line:gmatch("(%w+)=(%S+)") do t[#t + 1] = { k, v } end
  return t
end

local bad = 0
for i, line in ipairs(tex) do
  local seed = from + i - 1
  local lua = { { "seed", tostring(seed) } }
  species.sample(seed, "any", function(t, v)
    lua[#lua + 1] = { t, math.type(v) == "float" and pm.str(math.floor(v * 65536 + 0.5)) or tostring(v) }
  end)
  local got = fields(line)
  local why
  if #got ~= #lua then why = fmt("%d traits from TeX, %d from Lua", #got, #lua) end
  for j = 1, math.min(#got, #lua) do
    if why then break end
    local k, a, b = got[j][1], got[j][2], lua[j][2]
    if k ~= lua[j][1] then why = fmt("trait %d is %s in TeX, %s in Lua", j, k, lua[j][1])
    elseif a ~= b and not (b:find("%.") and tonumber(a) and pm.sp(a) == pm.sp(b)) then
      why = fmt("%s: TeX %s, Lua %s", k, a, b)
    end
  end
  if why then
    bad = bad + 1
    if bad <= 10 then print(fmt("seed %d: %s", seed, why)) end
  end
end
print(fmt("%s: %d species in %d s, %d differ", engine, #tex, secs, bad))
os.exit(bad == 0 and 0 or 1)
