-- florilegium-pgfmath.lua -- pgfmath's arithmetic, replayed exactly, for the species hybrid.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- The TikZ library (tikzlibraryflorilegium.code.tex) computes every drawing with pgfmath,
-- in TeX's fixed point: a number is a whole count of scaled points (1/65536 pt), every
-- operation rounds or truncates the way TeX and pgf do, and pgf's functions are tables,
-- polynomials and digit loops. florilegium-organs.lua draws the same plants in Lua, and
-- for the same seed it must make the same choices: a threshold that one side reads as
-- 0.29999 and the other as 0.30001 sends the plant elsewhere. So this file does what
-- pgfmath does, step for step, on integers: TeX's decimal reading (round_decimals) and
-- printing (print_scaled), a factor times a dimension (xn_over_d), \divide, and pgf's own
-- algorithms for divide, reciprocal, sqrt, ln, exp, pow, sin, cos, atan, atan2 and
-- veclen, with pgf's constants and its two lookup tables.
--
-- Not part of pgf. pgfmath is Mark Wibrow's (pgfmathfunctions.*.code.tex, "Copyright 2019
-- by Mark Wibrow", building on code by Till Tantau); its ln follows an algorithm due to
-- Rouben Rostamian with coefficients contributed by Alain Matthes, as pgfmath credits them.
-- This file is a reimplementation of pgfmath 3.1.10's arithmetic in Lua, made to give the
-- same results, and differs from it in this: the TeX macros are rewritten as Lua functions
-- on integers, expressions are compiled to Lua instead of evaluated in TeX, and an
-- overflow raises a Lua error where TeX reports one and goes on (tools/pgfmathcheck.lua
-- tests that the results agree). It replaces and changes no file of pgf. pgf's authors do
-- not support it: report problems with it to florilegium. pgf itself, unmodified, is at
-- https://ctan.org/pkg/pgf and https://github.com/pgf-tikz/pgf. pgf is distributed under
-- the LaTeX Project Public License 1.3c or the GNU GPL 2; this file takes it under the
-- LPPL, whose clause 10 lets a derived work carry another license (here MIT) if it keeps
-- the conditions of clause 6, which this paragraph states. Keep it with any copy.
--
-- M.compile(expr) turns a pgfmath expression into a Lua function with pgfmath's operator
-- precedences, so that organs can be written with the TikZ library's own expressions:
--   @name   the macro \flo@name (a number in sp, from the store R)
--   #name   the count register \flo@name, as \the\flo@name (an integer)
--   $name   the species trait \flo@get{name}
--   %1 ..   an argument of the caller (A[1] ..), already a number in sp
--   rnd, rand  pgf's random numbers, from M.rng (an ink.pgfrng)
-- Values in and out are integers in sp; comparisons give 65536 (1) or 0.

local M = {}
M.version = "1.3"                 -- the release; florilegium.lua checks that every file has the same

local UNITY = 65536
local MAXDIMEN = 1073741823       -- 16383.99998pt
local fmt, concat, tonumber, tostring = string.format, table.concat, tonumber, tostring

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
-- as \the gives it without "pt"
function M.str(s)
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
  return check(r)
end
M.mulf = mulf

-- \divide<dimen or count> by n: toward zero
local function divn(x, n)
  if n == 0 then error("florilegium-pgfmath: arithmetic overflow (divide by 0)", 2) end
  if n < 0 then x, n = -x, -n end
  if x >= 0 then return x // n else return -((-x) // n) end
end
M.divn = divn

-- ---------------------------------------------------------------- the four operations
function M.add(a, b) return check(a + b) end
function M.sub(a, b) return check(a - b) end
function M.neg(a) return -a end
function M.mul(a, b) return mulf(a, b) end        -- \pgfmath@x=<#2>\pgfmath@x, #1 in \pgfmath@x

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

function M.mod(a, b)                            -- \pgfmathmod@: a - b*trunc(a/b), in sp
  return check(a - b * divn(a, b))
end
function M.abs(a) return a < 0 and -a or a end
function M.floor(a)
  local c = ipart(a)
  if a < 0 and fpart(a) > 0 then c = c - 1 end
  return check(c * UNITY)
end
function M.round(a)
  local c, f = ipart(a), fpart(a)
  if f >= UNITY // 2 then c = a < 0 and c - 1 or c + 1 end
  return check(c * UNITY)
end
function M.int(a) return ipart(a) * UNITY end   -- the text before the point
function M.max(...)
  local x = -16383 * UNITY
  for i = 1, select("#", ...) do local v = select(i, ...) if v > x then x = v end end
  return x
end
function M.min(...)
  local x = 16383 * UNITY
  for i = 1, select("#", ...) do local v = select(i, ...) if v < x then x = v end end
  return x
end

-- ---------------------------------------------------------------- sqrt, ln, exp, pow
-- \pgfmathsqrt@: digit by digit to five decimals, i.e. floor(sqrt(x) * 10^5) of the
-- number as written
function M.sqrt(x)
  if x < 0 then error("florilegium-pgfmath: sqrt of a negative number", 2) end
  local I, D = str(x):match("^(%d+)%.(%d+)$")
  local n = tonumber(I) * 10000000000 + tonumber((D .. "00000"):sub(1, 5)) * 100000
  local r = math.floor(math.sqrt(n))
  while r * r > n do r = r - 1 end
  while (r + 1) * (r + 1) <= n do r = r + 1 end
  return sp(fmt("%d.%05d", r // 100000, r % 100000))
end

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

-- ---------------------------------------------------------------- trigonometry (degrees)
-- pgf's tables: cos at whole degrees 0..180 and atan(k/1000) in degrees, k = 0..1000,
-- five decimals each (pgfmathfunctions.trigonometric.code.tex), here as differences
local function table_of(deltas)
  local t, v, k = {}, 0, 0
  for d in deltas:gmatch("%-?%d+") do
    v = v + tonumber(d)
    local s = v < 0 and "-" or ""
    local a = v < 0 and -v or v
    t[k] = sp(fmt("%s%d.%05d", s, a // 100000, a % 100000))
    k = k + 1
  end
  return t
end
local COS = table_of([[
100000 -15 -46 -76 -107 -137 -167 -197 -228 -258 -288 -318 -348 -378 -407 -437 -467 -496 -524
-554 -583 -611 -640 -668 -695 -724 -752 -778 -806 -833 -859 -886 -912 -938 -963 -989 -1013
-1038 -1063 -1086 -1111 -1133 -1157 -1179 -1201 -1223 -1245 -1266 -1287 -1307 -1327 -1347 -1366
-1384 -1403 -1421 -1439 -1455 -1472 -1488 -1504 -1519 -1534 -1548 -1562 -1575 -1588 -1601 -1612
-1624 -1635 -1645 -1655 -1665 -1673 -1682 -1690 -1697 -1704 -1710 -1716 -1722 -1726 -1730 -1734
-1737 -1740 -1742 -1744 -1745 -1745 -1745 -1745 -1744 -1742 -1740 -1737 -1734 -1730 -1726 -1722
-1716 -1710 -1704 -1697 -1690 -1682 -1673 -1665 -1655 -1645 -1635 -1624 -1612 -1601 -1588 -1575
-1562 -1548 -1534 -1519 -1504 -1488 -1472 -1455 -1439 -1421 -1403 -1384 -1366 -1347 -1327 -1307
-1287 -1266 -1245 -1223 -1201 -1179 -1157 -1133 -1111 -1086 -1063 -1038 -1013 -989 -963 -938
-912 -886 -859 -833 -806 -778 -752 -724 -695 -668 -640 -611 -583 -554 -524 -496 -467 -437 -407
-378 -348 -318 -288 -258 -228 -197 -167 -137 -107 -76 -46 -15]])
local ATAN = table_of([[
0 5729 5730 5729 5730 5729 5730 5729 5729 5729 5729 5729 5729 5729 5728 5729 5728 5728 5728
5727 5728 5727 5727 5727 5726 5726 5726 5726 5725 5725 5724 5725 5724 5723 5723 5723 5722 5722
5722 5721 5721 5720 5719 5720 5718 5719 5717 5718 5716 5716 5716 5715 5714 5714 5714 5712 5712
5711 5711 5710 5710 5708 5708 5708 5706 5706 5705 5704 5704 5703 5702 5701 5701 5699 5699 5698
5697 5696 5696 5694 5694 5692 5692 5691 5690 5689 5688 5687 5686 5685 5684 5683 5682 5681 5680
5679 5678 5676 5676 5674 5674 5672 5671 5670 5669 5668 5666 5666 5664 5663 5661 5661 5659 5658
5657 5655 5654 5653 5652 5650 5649 5647 5647 5645 5643 5642 5641 5639 5638 5637 5635 5633 5633
5630 5630 5627 5627 5624 5624 5621 5621 5618 5617 5616 5614 5612 5611 5609 5608 5606 5604 5603
5601 5599 5598 5596 5594 5593 5591 5589 5587 5586 5584 5582 5580 5579 5577 5575 5573 5572 5569
5568 5566 5564 5562 5560 5558 5557 5555 5552 5551 5549 5547 5544 5543 5541 5539 5537 5535 5533
5531 5529 5527 5525 5523 5520 5519 5517 5514 5513 5510 5508 5506 5504 5502 5499 5498 5495 5493
5491 5488 5487 5484 5482 5480 5478 5475 5473 5471 5468 5466 5464 5462 5459 5457 5455 5452 5450
5448 5445 5443 5441 5438 5435 5434 5431 5428 5426 5424 5421 5419 5416 5414 5411 5409 5407 5404
5401 5399 5396 5394 5391 5389 5386 5384 5381 5378 5376 5373 5371 5368 5366 5362 5361 5357 5355
5353 5349 5347 5344 5342 5339 5336 5334 5331 5328 5325 5323 5320 5317 5314 5312 5309 5306 5303
5301 5297 5295 5293 5289 5286 5284 5281 5278 5275 5272 5270 5267 5263 5261 5258 5255 5252 5249
5247 5243 5241 5237 5235 5231 5229 5226 5223 5220 5216 5214 5211 5208 5205 5202 5199 5196 5192
5190 5187 5184 5180 5178 5175 5171 5169 5165 5162 5159 5156 5153 5150 5147 5144 5140 5138 5134
5131 5128 5125 5122 5119 5115 5112 5109 5106 5103 5099 5097 5093 5090 5086 5084 5080 5077 5074
5071 5067 5064 5061 5058 5054 5051 5048 5045 5041 5038 5035 5031 5028 5025 5022 5018 5015 5011
5009 5005 5001 4999 4994 4992 4988 4985 4982 4978 4975 4971 4968 4965 4962 4958 4954 4951 4948
4945 4940 4938 4934 4931 4927 4924 4921 4917 4914 4910 4906 4904 4900 4896 4893 4890 4886 4882
4879 4876 4872 4869 4865 4862 4858 4855 4851 4848 4844 4841 4837 4834 4830 4827 4823 4820 4816
4812 4809 4806 4802 4798 4795 4792 4788 4784 4781 4777 4774 4770 4766 4763 4759 4756 4752 4749
4745 4742 4738 4734 4731 4727 4723 4720 4717 4712 4709 4706 4702 4698 4695 4691 4688 4683 4681
4676 4673 4670 4666 4662 4658 4655 4651 4648 4644 4640 4637 4633 4629 4626 4622 4618 4615 4611
4608 4604 4600 4596 4593 4589 4586 4581 4579 4574 4571 4567 4564 4559 4557 4552 4549 4545 4541
4538 4534 4530 4527 4523 4519 4516 4512 4508 4504 4501 4497 4494 4490 4486 4482 4479 4475 4471
4467 4464 4460 4457 4452 4449 4446 4441 4438 4434 4431 4427 4423 4419 4416 4411 4409 4404 4401
4397 4393 4390 4386 4382 4378 4375 4371 4368 4363 4360 4356 4353 4348 4345 4342 4337 4334 4330
4327 4322 4319 4315 4312 4308 4304 4300 4297 4293 4289 4285 4282 4278 4274 4271 4267 4263 4259
4256 4252 4248 4245 4241 4237 4233 4230 4226 4222 4218 4215 4211 4208 4203 4200 4196 4193 4189
4185 4181 4178 4174 4170 4166 4163 4159 4155 4152 4148 4144 4141 4137 4133 4129 4126 4122 4118
4115 4111 4107 4103 4100 4096 4093 4088 4085 4082 4077 4074 4070 4067 4063 4059 4055 4052 4048
4045 4040 4037 4034 4029 4026 4023 4018 4015 4011 4008 4004 4000 3997 3993 3989 3985 3982 3979
3974 3971 3967 3964 3960 3956 3953 3949 3945 3942 3938 3934 3931 3927 3923 3920 3916 3912 3909
3905 3902 3898 3894 3891 3887 3883 3880 3876 3872 3869 3866 3861 3858 3855 3850 3848 3843 3840
3836 3833 3829 3826 3822 3818 3815 3811 3807 3804 3800 3797 3793 3790 3786 3782 3779 3775 3772
3768 3764 3761 3758 3754 3750 3746 3743 3740 3736 3732 3729 3725 3722 3718 3715 3711 3708 3704
3700 3697 3693 3690 3687 3682 3680 3675 3673 3668 3665 3662 3658 3655 3651 3648 3644 3640 3637
3634 3630 3627 3623 3619 3616 3613 3609 3606 3602 3599 3595 3592 3588 3585 3581 3578 3574 3571
3568 3564 3560 3557 3554 3550 3547 3543 3540 3537 3533 3529 3526 3523 3519 3516 3512 3510 3505
3502 3499 3495 3492 3489 3485 3482 3478 3475 3472 3468 3464 3462 3458 3454 3452 3447 3445 3441
3438 3434 3431 3428 3424 3421 3418 3414 3411 3407 3404 3401 3398 3394 3391 3387 3384 3381 3378
3374 3371 3367 3365 3360 3358 3354 3351 3348 3345 3341 3337 3335 3331 3328 3325 3321 3318 3315
3312 3308 3305 3302 3298 3296 3292 3288 3286 3282 3279 3276 3272 3270 3266 3262 3260 3256 3253
3250 3247 3244 3240 3237 3234 3230 3228 3224 3221 3218 3214 3212 3208 3205 3202 3199 3195 3193
3189 3186 3183 3180 3176 3173 3171 3167 3164 3161 3157 3155 3151 3148 3145 3142 3139 3136 3133
3129 3126 3124 3120 3117 3114 3111 3107 3105 3102 3098 3096 3092 3089 3086 3083 3080 3077 3074
3071 3068 3064 3062 3058 3056 3052 3050 3046 3044 3040 3037 3034 3032 3028 3025 3022 3019 3016
3013 3011 3007 3004 3001 2998 2995 2992 2989 2986 2984 2980 2977 2974 2971 2969 2965 2962 2960
2956 2954 2950 2948 2945 2941 2939 2936 2933 2930 2927 2924 2921 2918 2916 2912 2910 2906 2904
2901 2898 2895 2892 2889 2887 2883 2881 2877 2875 2872 2869 2867]])

-- \pgfmathcos@ on a number reduced to 0..180: the table, linear in between
local function costab(x)
  local c, f = ipart(x), fpart(x)
  if f == 0 then return COS[c] end
  local r = mulf(UNITY - f, COS[c])
  c = c + 1
  if c == 181 then c = 179 end
  return check(r + mulf(f, COS[c]))
end
local function reduce(x)
  x = check(x - divn(ipart(x), 360) * 360 * UNITY)
  if x < 0 then x = -x end
  if x >= 180 * UNITY then x = 360 * UNITY - x end
  return x
end
function M.cos(x) return costab(reduce(x)) end
function M.sin(x) return costab(reduce(check(x - 90 * UNITY))) end

function M.atan(x)
  local xa = x
  if x < 0 then x = -x end
  local xb = x
  if x > UNITY then x = recip(x) end
  -- \pgfmath@multiply@thousand: the decimal point three digits right, in the text
  local I, D = str(x):match("^(%d+)%.(%d+)$")
  D = D .. "000"
  x = sp(I .. D:sub(1, 3) .. "." .. D:sub(4))
  -- \pgfmath@table@lookup: entry, plus the fraction of the step to the next
  local k, f = ipart(x), fpart(x)
  x = ATAN[k]
  if k + 1 < 1001 then x = check(x + mulf(ATAN[k + 1] - x, f)) end
  if xb > UNITY then x = 90 * UNITY - x end
  if xa < 0 then x = -x end
  return x
end

local THOUSANDTH = sp("0.001")
function M.atan2(y, x)
  local ay = y < 0 and -y or y
  if ay < THOUSANDTH then
    if x < 0 then return 180 * UNITY elseif x > 0 then return 0
    elseif y < 0 then return -90 * UNITY else return 90 * UNITY end
  end
  local ax = x < 0 and -x or x
  local r
  if ay > ax then
    r = 90 * UNITY - M.atan(M.div(x, ay))
  else
    r = M.atan(M.div(ay, x))
    if x < 0 then r = r + 180 * UNITY end
  end
  if y < 0 then r = -r end
  return r
end

local VL = { sp("-0.01019210944"), sp("0.04453994279"), sp("-0.1195159052"), sp("0.4993615349"), sp("1.000012594") }
function M.veclen(x, y)
  if x < 0 then x = -x end
  if y < 0 then y = -y end
  if x == 0 then return y end
  if y == 0 then return x end
  if x > y then x, y = y, x end
  local c = 1
  if y > 10000 * UNITY then c = 1500 elseif y > 1000 * UNITY then c = 150 elseif y > 100 * UNITY then c = 50 end
  x, y = divn(x, c), divn(y, c)
  x = mulf(x, recip(y))
  local xa = mulf(x, x)
  local t = xa
  x = mulf(xa, VL[1])
  x = x + VL[2]
  x = mulf(x, t)
  x = x + VL[3]
  x = mulf(x, t)
  x = x + VL[4]
  x = mulf(x, t)
  x = x + VL[5]
  x = mulf(x, y)
  return check(x * c)
end

-- ---------------------------------------------------------------- comparisons, logic
function M.gt(a, b) return a > b and UNITY or 0 end
function M.lt(a, b) return a < b and UNITY or 0 end
function M.eq(a, b) return a == b and UNITY or 0 end
function M.ge(a, b) return a >= b and UNITY or 0 end
function M.le(a, b) return a <= b and UNITY or 0 end
function M.ne(a, b) return a ~= b and UNITY or 0 end
function M.band(a, b) return (a ~= 0 and b ~= 0) and UNITY or 0 end
function M.bor(a, b) return (a ~= 0 or b ~= 0) and UNITY or 0 end
function M.bnot(a) return a == 0 and UNITY or 0 end
function M.tern(c, a, b) if c == 0 then return b end return a end

-- ---------------------------------------------------------------- random numbers
-- set M.rng to an ink.pgfrng before evaluating rnd or rand; its rnd/rand give doubles
-- that are exact multiples of 2^-16
function M.rnd() return math.floor(M.rng.rnd() * UNITY + 0.5) end
function M.rand() return math.floor(M.rng.rand() * UNITY + 0.5) end

-- ---------------------------------------------------------------- expressions
-- pgfmath parses with an operator stack (pgfmathparser.code.tex): an operator pops every
-- operator of equal or higher precedence, so all are left-associative; unary minus has
-- the precedence of + and -, so -a*b is -(a*b); "c ? a : b" with ? at 100 and : at 101.
local PREC = { ["?"] = 100, ["||"] = 200, ["&&"] = 200, ["<"] = 250, [">"] = 250, ["=="] = 250,
  ["<="] = 250, [">="] = 250, ["!="] = 250, ["+"] = 500, ["-"] = 500, ["*"] = 700, ["/"] = 700, ["^"] = 900 }
local BIN = { ["||"] = "bor", ["&&"] = "band", ["<"] = "lt", [">"] = "gt", ["=="] = "eq", ["<="] = "le",
  [">="] = "ge", ["!="] = "ne", ["+"] = "add", ["-"] = "sub", ["*"] = "mul", ["/"] = "div", ["^"] = "pow" }
local FUN = { sin = 1, cos = 1, atan = 1, atan2 = 1, veclen = 1, sqrt = 1, pow = 1, ln = 1, exp = 1,
  abs = 1, floor = 1, round = 1, int = 1, min = 1, max = 1, mod = 1, rnd = 1, rand = 1 }

local function tokens(s)
  local t, i, n = {}, 1, #s
  while i <= n do
    local c = s:sub(i, i)
    if c:match("%s") then i = i + 1
    elseif c:match("[%d.]") then
      local num = s:match("^[%d.]+", i)
      t[#t + 1] = { "num", num } i = i + #num
    elseif c == "@" or c == "#" or c == "$" then
      local name = s:match("^[%w@]+", i + 1)
      assert(name, "florilegium-pgfmath: a name after " .. c .. " in '" .. s .. "'")
      t[#t + 1] = { c, name } i = i + 1 + #name
    elseif c == "%" then
      local k = s:match("^%d+", i + 1)
      t[#t + 1] = { "%", tonumber(k) } i = i + 1 + #k
    elseif c:match("%a") then
      local name = s:match("^%a[%w]*", i)
      t[#t + 1] = { "fun", name } i = i + #name
    else
      local two = s:sub(i, i + 1)
      if PREC[two] then t[#t + 1] = { "op", two } i = i + 2
      else t[#t + 1] = { "op", c } i = i + 1 end
    end
  end
  return t
end

-- the Lua code of a variable's value
local function varcode(x)
  if x[1] == "@" then return fmt("R[%q]", x[2])
  elseif x[1] == "$" then return fmt("R[%q]", "v@" .. x[2])
  elseif x[1] == "#" then return fmt("(R[%q]*65536)", "#" .. x[2])
  elseif x[1] == "%" then return fmt("A[%d]", x[2]) end
end

-- The Lua for expression s when the variables that bit k of signs marks are negative.
-- TeX expands macros before pgfmath parses, so a negative value arrives as "-" and its
-- digits: an operand, unary minus, that takes in the products after it. With \flo@w at
-- -0.27, "0.03*\flo@w*(\flo@v)" is 0.03*(-(0.27*v)), not (0.03*-0.27)*v, and the two
-- round apart. So the parse depends on the signs of the values, as it does in TeX.
local function parser(s, signs)
  local t, p, nvar = tokens(s), 1, 0
  local function peek() return t[p] end
  local function take(kind, v)
    local x = t[p]
    if not x or x[1] ~= kind or (v and x[2] ~= v) then
      error("florilegium-pgfmath: expected " .. (v or kind) .. " in '" .. s .. "'", 0)
    end
    p = p + 1
    return x
  end
  local expr
  local function operand()
    local x = t[p]
    if not x then error("florilegium-pgfmath: an operand is missing in '" .. s .. "'", 0) end
    p = p + 1
    if x[1] == "op" and x[2] == "-" then return "neg(" .. expr(501) .. ")"
    elseif x[1] == "op" and x[2] == "+" then return operand()
    elseif x[1] == "op" and x[2] == "!" then return "bnot(" .. expr(976) .. ")"
    elseif x[1] == "op" and x[2] == "(" then
      local e = expr(11)
      take("op", ")")
      return e
    elseif x[1] == "num" then return tostring(sp(x[2]))
    elseif x[1] == "fun" then
      local name = x[2]
      if not FUN[name] then error("florilegium-pgfmath: unknown function " .. name .. " in '" .. s .. "'", 0) end
      if name == "rnd" or name == "rand" then return name .. "()" end
      take("op", "(")
      local args = { expr(11) }
      while peek() and peek()[1] == "op" and peek()[2] == "," do p = p + 1 args[#args + 1] = expr(11) end
      take("op", ")")
      return name .. "(" .. concat(args, ",") .. ")"
    end
    local code = varcode(x)
    if code then
      nvar = nvar + 1
      if signs & (1 << (nvar - 1)) ~= 0 then return "neg(" .. expr(501, "(-" .. code .. ")") .. ")" end
      return code
    end
    error("florilegium-pgfmath: unexpected '" .. tostring(x[2]) .. "' in '" .. s .. "'", 0)
  end
  function expr(minprec, left)
    left = left or operand()
    while true do
      local x = peek()
      if not x or x[1] ~= "op" then break end
      local prec = PREC[x[2]]
      if not prec or prec < minprec then break end
      p = p + 1
      if x[2] == "?" then
        local a = expr(102)
        take("op", ":")
        local b = expr(102)
        left = "tern(" .. left .. "," .. a .. "," .. b .. ")"
      else
        left = BIN[x[2]] .. "(" .. left .. "," .. expr(prec + 1) .. ")"
      end
    end
    return left
  end
  local code = expr(0)
  if p <= #t then error("florilegium-pgfmath: trailing '" .. tostring(t[p][2]) .. "' in '" .. s .. "'", 0) end
  return code
end

local ENV = setmetatable({}, { __index = function(_, k) return M[k] end })
local CACHE = {}
-- A function(R, A) for expression s: it reads the signs of the variables, then runs the
-- variant compiled for them (each compiled once, when first met)
function M.compile(s)
  local f = CACHE[s]
  if f then return f end
  local vars = {}
  for _, x in ipairs(tokens(s)) do vars[#vars + 1] = varcode(x) end
  local function build(signs)
    return assert(load("local R, A = ... return " .. parser(s, signs), "=pgfmath: " .. s, "t", ENV))
  end
  if #vars == 0 then f = build(0)
  else
    local code = { "local VARIANTS, BUILD = ... return function(R, A) local k = 0" }
    for i, c in ipairs(vars) do code[#code + 1] = fmt("if %s < 0 then k = k | %d end", c, 1 << (i - 1)) end
    code[#code + 1] = "local f = VARIANTS[k] if not f then f = BUILD(k) VARIANTS[k] = f end return f(R, A) end"
    f = assert(load(concat(code, "\n"), "=pgfmath: " .. s, "t", ENV))({}, build)
  end
  CACHE[s] = f
  return f
end
M.lua = parser                                  -- the Lua for an expression and signs (tests)

return M
