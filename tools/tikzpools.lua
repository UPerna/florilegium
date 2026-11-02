-- Twenty documents' pools of species, drawn by the pure-TikZ library and by Lua, in
-- words: build/pools.md. Every sentence is describe() of the TikZ choices; a line is
-- marked if Lua's species for the same seed and role reads differently.
--   texlua tools/tikzpools.lua [K [ENGINE]]       (from the repo root; default 20 lualatex)
package.path = "./?.lua;" .. package.path
local species = require("florilegium-species")
local fmt = string.format
local K, engine = tonumber(arg[1]) or 20, arg[2] or "lualatex"

os.execute("mkdir -p build")
local pairs_, lua = {}, {}
for doc = 1, K do
  for _, sp in ipairs(species.pool(doc)) do
    pairs_[#pairs_ + 1] = fmt("%d %s", sp.seed, sp.role)
    lua[#lua + 1] = { doc = doc, sp = sp }
  end
end
local f = assert(io.open("build/tikzpools.txt", "w"))
f:write(table.concat(pairs_, "\n"), "\n")
f:close()
local ok = os.execute(fmt([[%s -interaction=batchmode -output-directory=build -jobname=tikzpools "\def\tikzchecklist{build/tikzpools.txt}\input{tools/tikzcheck.tex}" >/dev/null]], engine))
assert(ok, "tikzpools: " .. engine .. " failed, see build/tikzpools.log")

local out, same, i = { fmt("# Species pools, %d documents (drawn by TikZ, %s)", K, engine), "" }, 0, 0
local doc
for line in io.lines("build/tikzpools.choices") do
  i = i + 1
  local sp = {}
  for k, v in line:gmatch("(%w+)=(%S+)") do sp[k] = tonumber(v) or v end
  local tex, l = species.describe(sp), lua[i]
  if l.doc ~= doc then
    doc = l.doc
    out[#out + 1] = fmt("\n## Document seed %d\n", doc)
  end
  local mark = tex == species.describe(l.sp) and "" or "  **(Lua reads differently)**"
  if mark == "" then same = same + 1 end
  out[#out + 1] = fmt("- *%s, %s:* %s%s", l.sp.role, sp.plan, tex, mark)
end
local g = assert(io.open("build/pools.md", "w"))
g:write(table.concat(out, "\n"), "\n")
g:close()
print(fmt("%d species; TikZ and Lua read the same for %d; build/pools.md", i, same))
