-- Run from the repository root: texlua tools/layoutcheck.lua
-- The default fingerprints were captured from upstream commit 138f9f260373
-- before the layout controls were introduced. They cover PDF path bytes,
-- excluding changing PDF metadata and document text.
tex = { sprint = function() end }
luatexbase = { registernumber = function() return 0 end }
local out
node = { new = function() return {} end, write = function(n) out = n.data end }
package.path = "./?.lua;" .. package.path
local grow, settings, md5 = require("grow"), require("layout"), require("md5")
local checks = 0
local function check(ok, message)
  assert(ok, message)
  checks = checks + 1
end
local function page(seed, spill, options, age, marks)
  local g = { pw = 21, ph = 29.7, textleft = 6.8, textright = 18.8,
    ytop = 25.4, ybot = 3, colright = 6.4, headrule = 26.1, footy = 1.9,
    seed = seed, spill = spill, spilly = 19, layout = options, age = age, marks = marks }
  local stats = grow.page(g)
  return out, stats
end

local baseline = {
  { seed = 1, spill = 0, hash = "7c09afc6521ea233306388c03f90b427" },
  { seed = 6, spill = 1, hash = "1d482075fcfea4213d430e3ff5069945" },
  { seed = 7, spill = 1, age = 0.95,
    marks = { { kind = "heading", arg = 1, y = 20 }, { kind = "bloom", arg = "", y = 9 } },
    hash = "4285f0e7740b0e7cccf61dd3d9287b53" },
}
for _, c in ipairs(baseline) do
  local bytes = page(c.seed, c.spill, nil, c.age, c.marks)
  check(md5.sumhexa(bytes) == c.hash, "default drawing changed for seed " .. c.seed)
end
local full, full_stats = page(1, 0)
check(page(1, 0, { density = "full" }) == full, "full preset differs from default")
check(page(1, 1, { spill = false }) == full, "spill=false did not preserve the final-page whitespace")
local balanced, balanced_stats = page(1, 0, { density = "balanced" })
local airy, airy_stats = page(1, 0, { density = "airy" })
check(#balanced < #full and #airy < #balanced, "density did not reduce drawn detail for the reference seed")
check(balanced_stats.branches < full_stats.branches and airy_stats.branches < balanced_stats.branches,
  "lower density did not leave more branch space")
check(airy_stats.fills == 0, "airy density still fills small holes")
check(page(1, 0, { density = 0.3 }) == airy, "numeric and named densities disagree")
local repeat_airy = page(1, 0, { density = "airy" })
check(repeat_airy == airy, "drawing is not deterministic")
local without_footer, footer_stats = page(1, 0, { footer = false })
check(footer_stats.cells < full_stats.cells and without_footer ~= full, "footer=false did not remove the footer region")
check(select(2, page(1, 0, { density = 0.2 })).branches <= 7, "minimum density exceeded its branch budget")

for _, options in ipairs({
  { density = "unknown" }, { density = 0 }, { density = 1.1 }, { density = 0/0 },
  { density = math.huge }, { text_gap = -1 }, { text_gap = math.huge },
  { spill = "yes" }, { footer = 0 }, { header = "off" }, { unknown = true },
}) do
  check(not pcall(settings.resolve, options), "invalid layout control was accepted")
end
local original = { density = "airy", spill = "false", header = false }
local resolved = settings.resolve(original)
check(original.density == "airy" and original.spill == "false", "input settings were mutated")
check(resolved.density == 0.3 and not resolved.spill and not resolved.header, "settings were not resolved")
check(settings.resolve().spill and settings.resolve().footer, "one resolution changed the defaults")
print(string.format("\nlayoutcheck: %d checks passed", checks))
