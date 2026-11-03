-- florilegium-pgfmath.lua must compute what pgfmath computes, to the scaled point, for what
-- the species use it for. This writes random pgfmath expressions of the kinds Lua replays
-- (a product, a quotient, a sum, int, pow; a real trait as \flo@R draws it; the few numbers
-- florilegium-native.lua takes from TeX: a length in pt and back, a leaflet's size on the
-- page, a pic's counts), over the ranges the library uses them, has TeX evaluate them
-- (tools/pgfmathcheck.tex) and Lua compute them with the module's functions, and compares
-- the results exactly.
--   texlua tools/pgfmathcheck.lua [N [SEED [ENGINE]]]   (from the repo root; default 20000 1 lualatex)
--   tools/in-docker texlua tools/pgfmathcheck.lua 50000 7
package.path = "./?.lua;" .. package.path
local pm = require("florilegium-pgfmath")
local ink = require("florilegium-ink")
local fmt = string.format
local N, SEED = tonumber(arg[1]) or 20000, tonumber(arg[2]) or 1
local engine = arg[3] or "lualatex"
local rng = ink.rng(SEED)
local sp, mulf, div, add, int, pow = pm.sp, pm.mulf, pm.div, pm.add, pm.int, pm.pow
local CM, HALFCM = sp("28.45276"), sp("56.90552")

-- a number as the library writes them: up to five decimals, sometimes more (constants)
local function num(lo, hi, dec)
  local v = lo + (hi - lo) * rng.u()
  dec = dec or (rng.u() < 0.8 and 5 or rng.int(0, 10))
  local s = fmt("%." .. dec .. "f", v)
  if s:match("^%-0%.?0*$") then s = s:sub(2) end
  return s
end
-- a number over the ranges the library's arithmetic sees
local function any()
  local r = rng.u()
  if r < 0.25 then return num(0, 1) elseif r < 0.45 then return num(-1, 1)
  elseif r < 0.65 then return num(-30, 30) elseif r < 0.8 then return num(-400, 400)
  elseif r < 0.9 then return tostring(rng.int(0, 30)) else return num(0, 0.05, 5) end
end
local function nonzero() local s repeat s = any() until sp(s) ~= 0 return s end

-- each case: the expression TeX parses and the function that computes it in Lua
local KINDS = {
  function() local a, b = any(), any() return fmt("%s*%s", a, b), function() return mulf(sp(a), sp(b)) end end,
  function() local a, b = any(), nonzero() return fmt("%s/%s", a, b), function() return div(sp(a), sp(b)) end end,
  function() local a, b = num(-2, 2), num(-1, 1) return fmt("%s/%s", a, b),
    function() if sp(b) == 0 then error("zero") end return div(sp(a), sp(b)) end end,
  function() local a, b = any(), any() return fmt("%s+%s", a, b), function() return add(sp(a), sp(b)) end end,
  function() local a = any() return fmt("int(%s)", a), function() return int(sp(a)) end end,
  function() local a, b = num(0.01, 1.5), num(0.1, 3) return fmt("pow(%s,%s)", a, b), function() return pow(sp(a), sp(b)) end end,
  function() local a, b = num(0.01, 9), tostring(rng.int(-3, 4)) return fmt("pow(%s,%s)", a, b),
    function() return pow(sp(a), sp(b)) end end,
  -- a pinna's place along a frond (florilegium-native.lua: ppow)
  function() local a = num(0, 1) return fmt("pow(%s,0.85)", a), function() return pow(sp(a), sp("0.85")) end end,
  -- \flo@R{a}{w}: a + w*rnd, the draw as its digits
  function()
    local a, w, r = any(), num(0, 60), rng.int(0, 65536)
    return fmt("%s+%s*%s", a, w, pm.str(r)), function() return add(sp(a), mulf(sp(w), r)) end
  end,
  -- a length in cm to pt and back (a leaf's size on the page), a pic's length in cm, half
  -- a wingspan, a leaflet's size on the page
  function() local x = num(0, 30) return fmt("(%s*28.45276)/28.45276", x), function() return div(mulf(sp(x), CM), CM) end end,
  function() local x = num(0, 600) return fmt("%s/28.45276", x), function() return div(sp(x), CM) end end,
  function() local x = num(0, 600) return fmt("%s/56.90552", x), function() return div(sp(x), HALFCM) end end,
  function() local x, k = num(0, 300), num(0, 1.2) return fmt("%s*%s/28.45276", x, k),
    function() return div(mulf(sp(x), sp(k)), CM) end end,
  function() local x, k = num(0, 300), num(-1.2, 0) return fmt("%s*%s/28.45276", x, k),
    function() return mulf(sp(x), -div(-sp(k), CM)) end end,
  -- a pic's counts from its height in cm
  function() local x = num(0, 40) return fmt("int(%s/0.25+1)", x), function() return int(add(div(sp(x), sp("0.25")), 65536)) end end,
  function() local x = num(0, 40) return fmt("int(%s/0.6)", x), function() return int(div(sp(x), sp("0.6"))) end end,
  function() local x = num(0, 40) return fmt("int(%s/2)", x), function() return int(div(sp(x), 131072)) end end,
}
local cases = {}
while #cases < N do
  local text, f = KINDS[rng.int(1, #KINDS)]()
  local ok, v = pcall(f)
  if ok and v > -16000 * 65536 and v < 16000 * 65536 then cases[#cases + 1] = { text, v } end
end

os.execute("mkdir -p build")
local f = assert(io.open("build/pgfmathcheck.in", "w"))
for _, c in ipairs(cases) do f:write(c[1], "\n") end
f:close()
local cmd = fmt([[%s -interaction=batchmode -output-directory=build tools/pgfmathcheck.tex >/dev/null]], engine)
local t0 = os.time()
os.remove("build/pgfmathcheck.out")
os.execute(cmd)
if not io.open("build/pgfmathcheck.out") then error("pgfmathcheck: " .. engine .. " failed, see build/pgfmathcheck.log") end
local secs = os.time() - t0

local bad, i = 0, 0
for line in io.lines("build/pgfmathcheck.out") do
  i = i + 1
  local c = cases[i]
  local tv = pm.sp(line)
  if tv ~= c[2] then
    bad = bad + 1
    if bad <= 15 then print(fmt("%s\n  TeX %s, Lua %s (%d sp)", c[1], line, pm.str(c[2]), c[2] - tv)) end
  end
end
assert(i == #cases, fmt("pgfmathcheck: %d results from TeX, %d cases", i, #cases))
print(fmt("pgfmathcheck (%s): %d expressions in %d s, %d differ", engine, #cases, secs, bad))
os.exit(bad == 0 and 0 or 1)
