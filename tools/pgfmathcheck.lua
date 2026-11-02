-- florilegium-pgfmath.lua must compute what pgfmath computes, to the scaled point. This
-- writes random pgfmath expressions (the operators and functions the TikZ library uses,
-- over the ranges it uses them), has TeX evaluate them (tools/pgfmathcheck.tex) and Lua
-- (M.compile), and compares the results exactly. A third of them hold variables: Lua
-- compiles "@v1*@v2 ..." over values, TeX reads the values' digits in their place, as it
-- reads a macro's, so that a negative value parses as TeX parses it.
--   texlua tools/pgfmathcheck.lua [N [SEED [ENGINE]]]   (from the repo root; default 20000 1 lualatex)
--   tools/in-docker texlua tools/pgfmathcheck.lua 50000 7
package.path = "./?.lua;" .. package.path
local pm = require("florilegium-pgfmath")
local ink = require("florilegium-ink")
local fmt = string.format
local N, SEED = tonumber(arg[1]) or 20000, tonumber(arg[2]) or 1
local engine = arg[3] or "lualatex"
local rng = ink.rng(SEED)

-- a number as the library writes them: up to five decimals, sometimes more (constants)
local function num(lo, hi, dec)
  local v = lo + (hi - lo) * rng.u()
  dec = dec or (rng.u() < 0.8 and 5 or rng.int(0, 10))
  local s = fmt("%." .. dec .. "f", v)
  if s:match("^%-0%.?0*$") then s = s:sub(2) end
  return s
end
local VARS                                       -- when set, leaves may be variables
local function leaf()
  if VARS and rng.u() < 0.5 then
    local k = #VARS + 1
    local r = rng.u()
    local v = r < 0.4 and num(-1, 1) or r < 0.8 and num(-30, 30) or num(-400, 400)
    VARS[k] = pm.sp(v)
    return "@v" .. k
  end
  local r = rng.u()
  if r < 0.25 then return num(0, 1) elseif r < 0.45 then return num(-1, 1)
  elseif r < 0.65 then return num(-30, 30) elseif r < 0.8 then return num(-400, 400)
  elseif r < 0.9 then return tostring(rng.int(0, 30)) else return num(0, 0.05, 5) end
end
local UN = { "sin", "cos", "abs", "floor", "round", "int", "sqrtabs", "neg", "atan" }
local BI = { "+", "-", "*", "/", "atan2", "veclen", "min", "max", "mod", "pow", "<", ">", "==", "&&", "?" }
local function expr(depth)
  if depth <= 0 or rng.u() < 0.25 then return leaf() end
  if rng.u() < 0.35 then
    local f, a = UN[rng.int(1, #UN)], expr(depth - 1)
    if f == "sqrtabs" then return "sqrt(abs(" .. a .. "))" end
    if f == "neg" then return "-" .. a end
    if f == "atan" then return "atan(" .. a .. ")" end
    return f .. "(" .. a .. ")"
  end
  local op, a, b = BI[rng.int(1, #BI)], expr(depth - 1), expr(depth - 1)
  if op == "atan2" or op == "veclen" or op == "min" or op == "max" then return op .. "(" .. a .. "," .. b .. ")"
  elseif op == "mod" then return "mod(" .. a .. "," .. num(1, 360, 0) .. ")"
  elseif op == "pow" then return "pow(abs(" .. a .. ")+0.01," .. num(0, 3, rng.int(0, 2)) .. ")"
  elseif op == "?" then return "(" .. a .. ">" .. b .. " ? " .. leaf() .. " : " .. expr(depth - 1) .. ")"
  elseif op == "&&" then return "(" .. a .. "<1 && " .. b .. ">0 ? 1 : 0)"
  end
  if rng.u() < 0.5 then return "(" .. a .. op .. b .. ")" end
  return a .. op .. b
end

-- dense single-function cases, where the algorithms branch
local cases = {}
local function add(e)
  local ok, v = pcall(function() return pm.compile(e)({}, {}) end)
  if ok and v > -16000 * 65536 and v < 16000 * 65536 then cases[#cases + 1] = { e, v } end
end
for _ = 1, N // 10 do
  add(fmt("%s/%s", num(-300, 300), num(-50, 50)))
  add(fmt("%s/%s", num(-2, 2), num(-1, 1)))
  add(fmt("%s*%s", num(-300, 300), num(-3, 3)))
  add(fmt("sin(%s)", num(-2000, 2000)))
  add(fmt("cos(%s)", num(-2000, 2000)))
  add(fmt("atan2(%s,%s)", num(-5, 5), num(-5, 5)))
  add(fmt("veclen(%s,%s)", num(-200, 200), num(-200, 200)))
  add(fmt("sqrt(%s)", num(0, rng.u() < 0.5 and 2 or 3000)))
  add(fmt("pow(%s,%s)", num(0, 1.5), num(0.1, 3)))
  add(fmt("pow(%s,%s)", num(0, 9), tostring(rng.int(0, 4))))
end
while #cases < N * 2 // 3 do add(expr(4)) end
-- with variables: the TeX text has each value's digits in place of @v<k>; half of them
-- chains of products and quotients, where a negative value regroups what follows it
local OPS = { "*", "*", "/", "+", "-" }
local function chain()
  local t = { leaf() }
  for _ = 1, rng.int(2, 5) do t[#t + 1] = OPS[rng.int(1, #OPS)] t[#t + 1] = leaf() end
  return table.concat(t)
end
while #cases < N do
  VARS = {}
  local e = rng.u() < 0.5 and expr(4) or chain()
  local R = {}
  for k, v in ipairs(VARS) do R["v" .. k] = v end
  local ok, v = pcall(function() return pm.compile(e)(R, {}) end)
  if ok and v > -16000 * 65536 and v < 16000 * 65536 then
    local text = e:gsub("@v(%d+)", function(k) return pm.str(VARS[tonumber(k)]) end)
    cases[#cases + 1] = { text, v }
  end
  VARS = nil
end

os.execute("mkdir -p build")
local f = assert(io.open("build/pgfmathcheck.in", "w"))
for _, c in ipairs(cases) do f:write(c[1], "\n") end
f:close()
local cmd = fmt([[%s -interaction=batchmode -output-directory=build tools/pgfmathcheck.tex >/dev/null]], engine)
local t0 = os.time()
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
