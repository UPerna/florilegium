-- .luacheckrc -- luacheck's settings for florilegium's Lua: make luacheck (RUN=tools/in-docker),
-- and CI's lua job. luacheck . checks every file listed here.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.

-- LuaTeX runs Lua 5.3 and the playground 5.4: keep to what both have
std = "lua53"
include_files = { "florilegium*.lua", "build.lua", "docs/*.lua", "tools/*.lua", "testfiles/support/*.lua" }

-- what LuaTeX provides
read_globals = { "tex", "texio", "node", "token", "kpse", "luatexbase", "fonts", "md5" }

-- Every primitive takes the arguments its frame asks for (rng, s, o), and a motif row's
-- draw, a figure's draw and a theme's replacements take the same ones as the others,
-- whether they use them or not.
unused_args = false

-- Lines run long where a table of numbers or a formula reads best on one line.
max_line_length = false

-- florilegium-svg.lua and the tools draw pages without TeX: they stand in for TeX's
-- globals (florilegium-svg.lua puts the real ones back afterwards)
local stubs = { "tex", "texio", "node", "luatexbase" }
files["florilegium-svg.lua"] = { globals = stubs }
files["tools/*.lua"] = { globals = stubs }

-- l3build reads its settings from the globals build.lua sets, which nothing in it reads
files["build.lua"] = { allow_defined_top = true, ignore = { "131" } }

