-- Write tikzlibraryflorilegium.tables.code.tex from the tables in florilegium-species.lua,
-- and docs/traits.md, the traits and what each may be fixed to.
--   texlua tools/tikztables.lua          (from the repo root)
package.path = "./?.lua;" .. package.path
local f = assert(io.open("tikzlibraryflorilegium.tables.code.tex", "w"))
f:write(require("florilegium-species").tex())
f:close()
local g = assert(io.open("docs/traits.md", "w"))
g:write(require("florilegium-species").traitsdoc())
g:close()
