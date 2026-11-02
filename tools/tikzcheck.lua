-- TikZ and Lua must find the same species for the same seed. This compiles
-- tools/tikzcheck.tex (the pure-TikZ library draws species FROM..TO and writes their
-- choices), samples the same seeds with florilegium-species.lua, and compares them:
-- every choice exactly, every real-valued trait within 1e-4 (pgfmath keeps five decimals).
--   texlua tools/tikzcheck.lua [FROM TO [ENGINE]]    (from the repo root; default 1 1000 lualatex)
--   tools/in-docker texlua tools/tikzcheck.lua 1 1000 pdflatex
package.path = "./?.lua;" .. package.path
local species = require("florilegium-species")
local fmt = string.format
local from, to = tonumber(arg[1]) or 1, tonumber(arg[2]) or 1000
local engine = arg[3] or "lualatex"
local job = "tikzcheck-" .. engine

os.execute("mkdir -p build")
local cmd = fmt([[%s -interaction=batchmode -output-directory=build -jobname=%s "\def\tikzcheckfrom{%d}\def\tikzcheckto{%d}\input{tools/tikzcheck.tex}" >/dev/null]],
  engine, job, from, to)
local t0 = os.time()
local ok = os.execute(cmd)
if not ok then error("tikzcheck: " .. engine .. " failed, see build/" .. job .. ".log") end
local secs = os.time() - t0

local tex = {}
for line in io.lines("build/" .. job .. ".choices") do tex[#tex + 1] = line end
assert(#tex == to - from + 1, fmt("tikzcheck: %d species from TeX, expected %d", #tex, to - from + 1))

local function fields(line)
  local t = {}
  for k, v in line:gmatch("(%w+)=(%S+)") do t[#t + 1] = { k, v } end
  return t
end

local bad, worst = 0, 0
for i, line in ipairs(tex) do
  local seed = from + i - 1
  local lua = { { "seed", tostring(seed) } }
  species.sample(seed, "any", function(t, v)
    lua[#lua + 1] = { t, math.type(v) == "float" and fmt("%.5f", v) or tostring(v) }
  end)
  local got = fields(line)
  local why
  if #got ~= #lua then why = fmt("%d traits from TeX, %d from Lua", #got, #lua) end
  for j = 1, math.min(#got, #lua) do
    if why then break end
    local k, a, b = got[j][1], got[j][2], lua[j][2]
    if k ~= lua[j][1] then why = fmt("trait %d is %s in TeX, %s in Lua", j, k, lua[j][1])
    elseif a ~= b then
      local x, y = tonumber(a), tonumber(b)
      local real = x and y and (b:find("%.") ~= nil)
      if real and math.abs(x - y) <= 1e-4 then worst = math.max(worst, math.abs(x - y))
      else why = fmt("%s: TeX %s, Lua %s", k, a, b) end
    end
  end
  if why then
    bad = bad + 1
    if bad <= 10 then print(fmt("seed %d: %s", seed, why)) end
  end
end
print(fmt("%s: %d species in %d s, %d differ; largest difference in a real trait %.1e", engine, #tex, secs, bad, worst))
os.exit(bad == 0 and 0 or 1)
