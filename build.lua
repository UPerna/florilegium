-- build.lua -- l3build's settings for florilegium: regression tests of the package as
-- LuaLaTeX loads it. Each test in testfiles/ typesets a few pages, and
-- testfiles/support/fingerprint.lua logs every drawing on them (the md5 and size of its PDF
-- operators) and what grew; l3build compares that log with the one saved beside the test
-- (.tlg), so a change that moves a single point of any drawing fails here.
--   l3build check                     every test       (make check RUN=tools/in-docker)
--   l3build check grown               one test
--   l3build save grown                record a test's log again, after an intended change,
--                                     and look at the pages before committing it
-- The logs were saved with the TeX Live 2023 of Ubuntu 24.04, which tools/Dockerfile and CI's
-- l3build job install. Another TeX Live may set the text differently and move a heading's
-- flower with it, so record and check with that one.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.

module = "florilegium"

-- the package and the TikZ library are plain files, nothing to unpack: each test runs with
-- these beside it
sourcefiles  = { "florilegium.sty", "florilegium*.lua", "tikzlibraryflorilegium*.code.tex" }
installfiles = { "florilegium.sty", "florilegium*.lua", "tikzlibraryflorilegium*.code.tex" }

-- l3build's folders go under the Makefile's build/, and `l3build clean` leaves the
-- root alone (by default it deletes every *.pdf there, the documents included)
builddir   = "./build/l3build"
cleanfiles = {}

-- LuaLaTeX only, one pass
checkengines = { "luatex" }
stdengine    = "luatex"
checkruns    = 1
