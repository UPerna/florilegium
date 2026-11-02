package.path="./?.lua;"..package.path
tex={sprint=function() end};luatexbase={registernumber=function() return 0 end}
kpse={find_file=function(file) return file end}
local initial,ink=require("initial"),require("ink")
fonts=nil
local ok,err=initial.draw(ink.rng(7),2,"E",{font="missing-reader.otf"})
assert(not ok and err:match("outline reader is unavailable"))
fonts={handlers={otf={readers={loadshapes=function() error("bad font") end}}}}
ok,err=initial.draw(ink.rng(7),2,"E",{font="reader-error.otf"})
assert(not ok and err:match("cannot read initial font"))
fonts.handlers.otf.readers.loadshapes=function() return {glyphs={}} end
ok,err=initial.draw(ink.rng(7),2,"E",{font="missing-glyph.otf"})
assert(not ok and err:match("no outline"))
fonts.handlers.otf.readers.loadshapes=function() return {glyphs={{unicode=69,segments={{0,0,'m'}}}}} end
ok,err=initial.draw(ink.rng(7),2,"E",{font="missing-bounds.otf"})
assert(not ok and err:match("no usable outline bounds"))
print("initialcheck: missing reader, unreadable font, missing glyph and malformed bounds handled")
