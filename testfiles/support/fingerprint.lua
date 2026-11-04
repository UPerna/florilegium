-- fingerprint.lua -- for l3build's tests (testfiles/*.lvt): logs a fingerprint of each page as
-- it is shipped out, so that the saved log (.tlg) changes when a drawing does. Per page: the
-- md5 and size of every literal florilegium wrote (florilegium-ink.lua's start "q 1 J 1 j"),
-- what the grown composition counted, and the math theme's captions. M.try runs a function
-- and logs what it says, with this release's number written "this release", so that a
-- version bump leaves the saved logs alone (versions.lvt).
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
local WHATSIT, LITERAL = node.id("whatsit"), node.subtype("pdf_literal")
local HLIST, VLIST = node.id("hlist"), node.id("vlist")

local function literals(head, out)
  for n in node.traverse(head) do
    if (n.id == HLIST or n.id == VLIST) and n.head then
      literals(n.head, out)
    elseif n.id == WHATSIT and n.subtype == LITERAL and n.data:sub(1, 9) == "q 1 J 1 j" then
      out[#out + 1] = n.data
    end
  end
  return out
end

local function sorted(t)
  local keys = {}
  for k in pairs(t) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

local function log(s) texio.write_nl("log", s) end
local M = {}
local FLO = require("florilegium")     -- the package's own module (a TikZ-only test loads no .sty)
local RELEASE = FLO.version

function M.try(label, fn)
  local ok, err = pcall(fn)
  local msg, this = ok and "no error" or tostring(err), "release " .. RELEASE
  local at = msg:find(this, 1, true)
  while at do
    msg = msg:sub(1, at - 1) .. "this release" .. msg:sub(at + #this)
    at = msg:find(this, 1, true)
  end
  log(label .. ": " .. msg)
end

local page = 0
luatexbase.add_to_callback("pre_shipout_filter", function(head)
  page = page + 1
  local found = literals(head, {})
  log(("florilegium test: page %d, %d drawings"):format(page, #found))
  for i, s in ipairs(found) do log(("  %d. md5 %s, %d bytes"):format(i, md5.sumhexa(s), #s)) end
  local stats = FLO.last_stats
  if stats and stats.counts then
    local parts = {}
    for _, k in ipairs(sorted(stats.counts)) do parts[#parts + 1] = k .. " " .. stats.counts[k] end
    log("  grew: " .. table.concat(parts, ", "))
  end
  for _, c in ipairs(FLO.last_captions or {}) do
    log(("  caption at (%.2f, %.2f): %s"):format(c[1] or c.x, c[2] or c.y, c[3] or c.text))
  end
  FLO.last_stats, FLO.last_captions = nil, nil
  return true
end, "florilegium test fingerprint")

return M
