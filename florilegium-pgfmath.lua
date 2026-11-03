-- florilegium-pgfmath.lua -- the part of pgfmath's arithmetic the species need, replayed exactly.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- The TikZ library (tikzlibraryflorilegium.code.tex) computes every drawing with pgfmath,
-- in TeX's fixed point: a number is a whole count of scaled points (1/65536 pt), every
-- operation rounds or truncates the way TeX and pgf do. florilegium-species.lua samples
-- the same species in Lua, and for the same seed it must make the same choices: a
-- real-valued trait is pgfmath's own number, to the scaled point, since a threshold that
-- one side reads as 0.29999 and the other as 0.30001 sends the plant elsewhere. And
-- florilegium-native.lua, which draws in doubles, takes from here the few numbers that TeX
-- holds on a threshold (a leaf's size on the page, a pic's counts). So this file does what
-- pgfmath does for those, step for step, on integers: TeX's decimal reading
-- (round_decimals) and printing (print_scaled), a factor times a dimension (xn_over_d),
-- \divide, and pgf's own algorithms for divide, reciprocal, ln, exp and pow, with pgf's
-- constants.
--
-- Not part of pgf. pgfmath is Mark Wibrow's (pgfmathfunctions.*.code.tex, "Copyright 2019
-- by Mark Wibrow", building on code by Till Tantau); its ln follows an algorithm due to
-- Rouben Rostamian with coefficients contributed by Alain Matthes, as pgfmath credits them.
-- This file is a reimplementation of part of pgfmath 3.1.10's arithmetic in Lua, made to
-- give the same results, and differs from it in this: the TeX macros are rewritten as Lua
-- functions on integers, and an overflow raises a Lua error where TeX reports one and goes
-- on (tools/pgfmathcheck.lua tests that the results agree). It replaces and changes no
-- file of pgf. pgf's authors do not support it: report problems with it to florilegium.
-- pgf itself, unmodified, is at https://ctan.org/pkg/pgf and
-- https://github.com/pgf-tikz/pgf. pgf is distributed under the LaTeX Project Public
-- License 1.3c or the GNU GPL 2; this file takes it under the LPPL, whose clause 10 lets a
-- derived work carry another license (here MIT) if it keeps the conditions of clause 6,
-- which this paragraph states. Keep it with any copy.
--
-- Values in and out are integers in sp: M.sp(text) reads a number, M.str(v) prints one,
-- M.mulf(x, y) is y as a factor times x, M.add, M.div (pgfmath's a/b), M.int (the integer
-- part, in sp) and M.pow.

local M = {}
M.version = "1.3"                 -- the release; florilegium.lua checks that every file has the same

local UNITY = 65536
local MAXDIMEN = 1073741823       -- 16383.99998pt
local concat, tonumber, tostring = table.concat, tonumber, tostring

local function check(v)
  if v > MAXDIMEN or v < -MAXDIMEN then error("florilegium-pgfmath: dimension too large (" .. v .. "sp)", 2) end
  return v
end

-- ---------------------------------------------------------------- TeX's numbers
-- round_decimals (tex.web 102): up to 17 digits after the point, to the nearest 2^-16
local function round_decimals(d)
  local a = 0
  for k = math.min(#d, 17), 1, -1 do a = (a + (d:byte(k) - 48) * 131072) // 10 end
  return (a + 1) // 2
end

-- a number as TeX reads "<text>pt": signs, integer part, fraction; in sp
local SPCACHE = {}
function M.sp(text)
  local v = SPCACHE[text]
  if v then return v end
  local signs, int, frac = text:match("^%s*([-+%s]*)(%d*)[.,]?(%d*)%s*$")
  if not signs or int .. frac == "" then error("florilegium-pgfmath: not a number: '" .. text .. "'", 2) end
  local _, nminus = signs:gsub("-", "")
  local i = tonumber(int ~= "" and int or "0")
  if i >= 16384 then error("florilegium-pgfmath: dimension too large: " .. text, 2) end
  v = i * UNITY + (frac ~= "" and round_decimals(frac) or 0)
  if nminus % 2 == 1 then v = -v end
  SPCACHE[text] = check(v)
  return v
end

-- print_scaled (tex.web 103): the shortest decimal that reads back to the same sp,
-- as \the gives it without "pt". Remembered: a page asks for the same values again and
-- again (nine calls in ten), so the table is emptied when it grows large
local STRCACHE, nstr = {}, 0
local function print_scaled(s)
  local out = {}
  if s < 0 then out[1] = "-" s = -s end
  out[#out + 1] = tostring(s // UNITY)
  out[#out + 1] = "."
  s = 10 * (s % UNITY) + 5
  local delta = 10
  repeat
    if delta > UNITY then s = s + 32768 - 50000 end
    out[#out + 1] = string.char(48 + s // UNITY)
    s = 10 * (s % UNITY)
    delta = delta * 10
  until s <= delta
  return concat(out)
end
function M.str(s)
  local v = STRCACHE[s]
  if v then return v end
  if nstr >= 200000 then STRCACHE, nstr = {}, 0 end
  v = print_scaled(s)
  STRCACHE[s], nstr = v, nstr + 1
  return v
end
local str, sp = M.str, M.sp

-- the integer part of \the<dimen> as a count reads it (toward zero), and the rest
local function ipart(x) if x >= 0 then return x // UNITY else return -((-x) // UNITY) end end
local function fpart(x) if x < 0 then x = -x end return x % UNITY end

-- <factor><dimen> (tex.web 455): integer part times x, plus xn_over_d(x, f, 2^16);
-- the factor's sign last
local function mulf(x, y)
  local neg = y < 0
  if neg then y = -y end
  local f = y % UNITY
  local r = (y // UNITY) * x
  if x >= 0 then r = r + (x * f) // UNITY else r = r - ((-x) * f) // UNITY end
  if neg then r = -r end
  if r > MAXDIMEN or r < -MAXDIMEN then return check(r) end   -- (check's error, from here)
  return r
end
M.mulf = mulf

-- \divide<dimen or count> by n: toward zero
local function divn(x, n)
  if n == 0 then error("florilegium-pgfmath: arithmetic overflow (divide by 0)", 2) end
  if n < 0 then x, n = -x, -n end
  if x >= 0 then return x // n else return -((-x) // n) end
end

-- ---------------------------------------------------------------- add, divide
function M.add(a, b) local r = a + b if r > MAXDIMEN or r < -MAXDIMEN then return check(r) end return r end

-- \pgfmathreciprocal@: from the digits of the number as written
function M.recip(x)
  if x == 0 then error("florilegium-pgfmath: reciprocal of 0", 2) end
  local I, D = str(x):match("^(-?%d+)%.(%d*)$")
  D = (D .. "0000000"):sub(1, 5)
  if tonumber(D) == 0 then return divn(UNITY, tonumber(I)) end
  local ca, cb
  if tonumber(I) > 100 then
    ca = tonumber(I .. D:sub(1, 3))
    cb = divn(1000000000, ca)
    ca = divn(cb, 10000)
    local r = check(ca * UNITY)
    cb = cb + ca * -10000
    return check(r + divn(check(cb * UNITY), 1000000))
  end
  ca = tonumber(I .. D)
  cb = divn(1000000000, ca)
  ca = divn(cb, 10000)
  local r = check(ca * UNITY)
  cb = cb + ca * -10000
  local y = check(cb * UNITY)
  for _ = 1, 4 do y = mulf(y, 6554) end           -- \pgfmath@y.1\pgfmath@y (.1 reads as 6554sp)
  return check(r + y)
end
local recip = M.recip

-- \pgfmathdivide@dimenbyten: the decimal point moved one digit left, in the text
local function byten(y)
  local I, D = str(y):match("^(%d+)%.(%d+)$")
  local i = tonumber(I)
  local a = i // 10
  return sp(a .. "." .. (i - 10 * a) .. D)
end

-- \pgfmathdivide@advance@last@digit: one more in the last of up to five decimals
local BUMP = { [0] = UNITY, sp("0.1"), sp("0.01"), sp("0.001"), sp("0.0001"), sp("0.00001") }
local function bump(res)
  local dec = res:match("%.(%d*)$")
  local y = sp(res) + BUMP[math.min(#dec, 5)]
  local s = str(y)
  return (s:gsub("%.0$", "."))                  -- \pgfmath@tonumber@notrailingzero
end

local SMALLNUM = sp("0.00002")
function M.div(a, b)
  if b == 0 then error("florilegium-pgfmath: division by 0", 2) end
  if fpart(b) == 0 then return divn(a, ipart(b)) end
  local signs, x, y = 0, a, b
  if x < 0 then signs = signs + 1 x = -x end
  if y < 0 then signs = signs + 1 y = -y end
  if y < UNITY then
    local r = recip(y)
    if signs == 1 then r = -r end
    return mulf(x, r)
  end
  local res, period = "0", true
  while x > SMALLNUM and y > SMALLNUM do        -- \pgfmath@small@number
    if y > x then
      if period then res = res .. "." period = false end
      y = byten(y)
      if y > x then res = res .. "0" end
    else
      local q = x // y
      x = x - q * y
      if not period and q > 9 then
        res = bump(res)
        q = q - 10
        if q ~= 0 then res = res .. q end
      else
        res = res .. q
      end
    end
  end
  local v = sp(res)
  if signs == 1 then v = -v end
  return v
end

function M.int(a) return ipart(a) * UNITY end   -- the text before the point

-- ---------------------------------------------------------------- ln, exp, pow
-- ln: Rouben Rostamian's algorithm, Alain Matthes's coefficients (as pgfmath credits them)
local LN = { sp("0.04300521312"), sp("-.4025153233"), sp("1.589480044"), sp("-3.489886985"),
  sp("5.047861502"), sp("-2.787927935"), sp("0.6931471806") }
local P2 = {}
for k = 1, 13 do P2[k] = 1 << k end
local SMALL = { sp("0.0078125"), sp("0.125"), sp("0.5"), sp("0.03125"), sp("0.0625"), sp("0.015625"),
  sp("0.00048828125"), sp("0.001953125"), sp("0.00390625"), sp("0.0009765625"),
  sp("0.0001220703125"), sp("0.0002441406256") }
function M.ln(x)
  if x <= 0 then error("florilegium-pgfmath: ln of " .. str(x), 2) end
  local c = 0
  local pt = UNITY
  if x > 2 * pt then
    if x < 128 * pt then
      if x < 8 * pt then
        if x < 4 * pt then c = 1 else c = 2 end
      elseif x < 32 * pt then
        if x < 16 * pt then c = 3 else c = 4 end
      else
        if x < 64 * pt then c = 5 else c = 6 end
      end
    elseif x < 2048 * pt then
      if x < 512 * pt then
        if x < 256 * pt then c = 7 else c = 8 end
      else
        if x < 1024 * pt then c = 9 else c = 10 end
      end
    else
      if x < 8192 * pt then
        if x < 4096 * pt then c = 11 else c = 12 end
      else c = 13 end
    end
    x = divn(x, P2[c])
  elseif x < pt then
    if x > SMALL[1] then
      if x > SMALL[2] then
        if x > SMALL[3] then c = -1 else c = -2 end
      elseif x > SMALL[4] then
        if x > SMALL[5] then c = -3 else c = -4 end
      else
        if x > SMALL[6] then c = -5 else c = -6 end
      end
    elseif x > SMALL[7] then
      if x > SMALL[8] then
        if x > SMALL[9] then c = -7 else c = -8 end
      else
        if x > SMALL[10] then c = -9 else c = -10 end
      end
    else
      if x > SMALL[11] then
        if x > SMALL[12] then c = -11 else c = -12 end
      else c = -13 end
    end
    x = check(x * P2[-c])
  end
  local t = x
  x = mulf(x, LN[1])
  x = x + LN[2]
  x = mulf(x, t)
  x = x + LN[3]
  x = mulf(x, t)
  x = x + LN[4]
  x = mulf(x, t)
  x = x + LN[5]
  x = mulf(x, t)
  x = x + LN[6]
  x = x + c * UNITY
  return mulf(x, LN[7])
end

function M.exp(v)
  if v < -9 * UNITY then return 1 end
  local xc = v < 0 and -v or v
  local x, xa = UNITY, UNITY
  local xb, k = x, 1
  while true do
    xa = divn(xa, k)
    xa = mulf(xa, xc)
    x = check(x + xa)
    if x == xb then break end
    xb = x
    k = k + 1
  end
  if v < 0 then x = recip(x) end
  return x
end

function M.pow(a, b)
  if a == 0 then return b == 0 and UNITY or 0 end
  local c, f = ipart(b), fpart(b)
  local xa = a
  if c < 0 then c = -c xa = recip(a) end
  if f == 0 then
    local x = UNITY
    while c > 0 do
      if c % 2 == 1 then x = mulf(xa, x) end
      if c > 1 then xa = mulf(xa, xa) end
      c = c // 2
    end
    return x
  end
  return M.exp(mulf(M.ln(a), b))
end

return M
