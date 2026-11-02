-- Write tikzlibraryflorilegium.tables.code.tex from the tables in florilegium-species.lua.
--   texlua tools/tikztables.lua          (from the repo root)
package.path = "./?.lua;" .. package.path
local f = assert(io.open("tikzlibraryflorilegium.tables.code.tex", "w"))
f:write(require("florilegium-species").tex())
f:close()
