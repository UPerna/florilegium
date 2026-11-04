-- TikZ and Lua must find the same species for the same seed, and draw the same plant.
--
-- Choices: compiles tools/tikzcheck.tex (the pure-TikZ library draws species FROM..TO and
-- writes their choices), samples the same seeds with florilegium-species.lua, and compares
-- them, every choice and every real-valued trait exactly (both are pgfmath's numbers).
--   texlua tools/tikzcheck.lua [FROM TO [ENGINE [ROLE [TRAITS]]]]   (from the repo root; default 1 1000 lualatex any)
--   (ROLE v:<role>, e.g. v:any or v:stem: visitors of that role instead of plants; TRAITS,
--   e.g. "compound=palmate, leaflets=7": those traits fixed in every one, #5109)
--   tools/in-docker texlua tools/tikzcheck.lua 1 1000 pdflatex
--
-- Drawings: builds tools/tikzcheck-draw.tex twice under LuaLaTeX, once with the pure-TikZ
-- library and once with the Lua engine (engine=lua: florilegium-native.lua draws the same
-- steps in doubles, with ink), renders both with pdftoppm (gray, 150 dpi) and compares
-- every pic pixel by pixel, each from the center of its ink: a pixel differs where nothing within
-- a pixel of it in the other drawing is within 1/4 of its gray, both ways, and a pic passes
-- while under 1% of its inked pixels, or under 60, differ (the two draw the same plant within a fraction
-- of a point, so only a choice that went the other way shows), and while its ink is within 3.5%
-- as dark in both (a fill drawn lighter or not at all: each of its pixels is still near a gray
-- of the other drawing, but the whole is lighter).
--   texlua tools/tikzcheck.lua draw [quick|full|fern|visitors] [compare] (compare: the last
--   builds' PDFs again, without building them; quick: fronds of every division,
--   outline and edge, fern crowns in three seasons, then one flower, one leaf and one
--   inflorescence of every body plan, one inflorescence of every kind and of every view
--   (a lily's swept-back tepals and its trumpet too), strap leaves that arch and twist,
--   a pea's leaves and plant with tendrils, compound leaves of every kind, curled tips,
--   plants whose leaves come in crossed pairs or sheathe the stem, the v1.3 pics, a plant in three
--   seasons, butterflies and moths of every wing, pattern, ground, pose and feeler, bees
--   and hoverflies of every kind, ground and pose, dragonflies, damselflies, beetles and
--   ladybirds of every ground, pose, tint and pattern, caterpillars, snails and birds of
--   every pose, ground, shell and bill; full:
--   also two strips of three plants, as specimen-tikz.tex draws them, several minutes in
--   pure TikZ; fern: the ferns alone; visitors: the visitors alone)
package.path = "./?.lua;" .. package.path
local fmt = string.format
os.execute("mkdir -p build")

-- ================================================================ drawings
local function streams(path)
  local f = assert(io.open(path, "rb"))
  local d = f:read("a")
  f:close()
  local t = {}
  for s in d:gmatch("stream\r?\n(.-)endstream") do t[#t + 1] = s end
  return t
end
if arg[1] == "draw" then
  local reuse = arg[3] == "compare"           -- draw quick compare: the last builds' PDFs again
  local full, fernonly, visonly = arg[2] == "full", arg[2] == "fern", arg[2] == "visitors"
  local species = require("florilegium-species")
  local pics = {}
  local function pic(spec) pics[#pics + 1] = spec end
  -- ferns: fronds of every division, outline and edge, scaly and bare; crowns in spring,
  -- summer and autumn (fiddleheads, fronds unrolling, some turned over to show each kind of
  -- sori, copper in autumn), a dimorphic fern's fertile frond, a fern as a plant pic
  if not visonly then
  local function fern(want)
    local seed = 1
    while not want(species.sample(seed, "fern")) do seed = seed + 1 end
    return seed
  end
  for _, w in ipairs({
      function(f) return f.division == 1 and f.outline == "oblong" end,
      function(f) return f.division == 1 and f.leafmargin == "serrate" and f.hairy == 1 end,
      function(f) return f.division == 1 and f.leafmargin == "crenate" and f.leafapex == "rounded" end,
      function(f) return f.division == 2 and f.outline == "deltoid" end,
      function(f) return f.division == 2 and f.outline == "ovate" end,
      function(f) return f.division == 3 and f.outline == "lanceolate" end }) do
    pic(fmt("florilegium leaf={seed=%d, role=fern, size=7cm}", fern(w)))
  end
  for _, w in ipairs({
      function(f) return f.dimorphic == 1 and f.sori == "dots" and f.turns == 1 end,
      function(f) return f.division == 1 and f.sori == "lines" end,
      function(f) return f.division == 2 and f.sori == "marginal" end,
      function(f) return f.division == 3 and f.sori == "dots" end }) do
    local seed = fern(w)
    for _, season in ipairs({ "0.3", "0.75", "1.25" }) do
      pic(fmt("florilegium fern={seed=%d, size=6cm, season=%s}", seed, season))
    end
  end
  pic(fmt("florilegium plant={seed=%d, role=fern, size=5cm, season=0.6}", fern(function(f) return f.hairy == 1 end)))
  end
  if not fernonly and not visonly then
  for i, p in ipairs(species.PLANS) do
    if not p.apart then pic(fmt("florilegium flower={seed=%d, role=%s, size=2.6cm}", 10 + 7 * i, p.name)) end
    pic(fmt("florilegium leaf={seed=%d, role=%s, size=3.4cm}", 11 + 7 * i, p.name))
    if not p.apart then pic(fmt("florilegium inflorescence={seed=%d, role=%s, scale=1, season=0.85}", 12 + 7 * i, p.name)) end
  end
  -- an inflorescence of every kind (the first seed that has it), a few also in bud and in fruit
  local SEASONS = { monochasium = { "0.3", "1.3" }, dichasium = { "1.3" }, catkin = { "0.3", "1.3" }, umbel = { "0.3" },
    spike = { "1.3" } }
  for _, kind in ipairs({ "solitary", "raceme", "spike", "panicle", "corymb", "umbel", "cumbel", "dichasium",
    "monochasium", "head", "catkin", "thyrse" }) do
    local seed = 1
    while species.sample(seed, "any").inflo ~= kind do seed = seed + 1 end
    for _, season in ipairs({ "0.85", table.unpack(SEASONS[kind] or {}) }) do
      pic(fmt("florilegium inflorescence={seed=%d, role=any, scale=1.2, season=%s}", seed, season))
    end
  end
  -- every view of a flower: each form drawn in profile, a flat-faced tube held sideways,
  -- flowers at a tilt and from behind, a nodding lily, pea flowers (with guides, and in a
  -- head), two-lipped flowers (with dots, with lines and stamens that stand out), irises
  -- (each kind of guide), orchids (alone and in a raceme), a lily's cup and trumpet,
  -- columbines (nodding and sideways): form, orient, guides, stamens, inflorescence, corona
  for _, v in ipairs({ { "campanulate" }, { "urceolate" }, { "tubular" }, { "funnelform" }, { "salverform", "horizontal" },
    { "rotate", "horizontal" }, { "rosaceous", "nodding" }, { "lily", "nodding" },
    { "papilionaceous", nil, "lines" }, { "papilionaceous", nil, nil, nil, "head" },
    { "bilabiate", nil, "dots" }, { "bilabiate", nil, "lines", "exserted" },
    { "iris", nil, "lines", nil, "solitary" }, { "iris", nil, "blotch" }, { "iris", nil, "dots" },
    { "orchid", nil, nil, nil, "solitary" }, { "orchid", nil, nil, nil, "raceme" },
    { "lily", nil, nil, nil, nil, "cup" }, { "lily", nil, nil, nil, nil, "trumpet" },
    { "spurred", "nodding" }, { "spurred", "horizontal" } }) do
    local seed = 1
    while true do
      local sp = species.sample(seed, "any")
      if sp.form == v[1] and (not v[2] or sp.orient == v[2]) and (not v[3] or sp.guides == v[3])
        and (not v[4] or sp.stamens == v[4]) and (not v[5] or sp.inflo == v[5]) and (not v[6] or sp.corona == v[6]) then break end
      seed = seed + 1
    end
    pic(fmt("florilegium inflorescence={seed=%d, role=any, scale=1, season=0.75}", seed))
  end
  -- a lily held sideways or nodding with its tepals swept back (a Turk's cap), and one in a
  -- trumpet; strap leaves that arch over (lily 6 and 10) and twist to show their underside (8)
  for _, want in ipairs({ function(sp) return sp.reflex < -40 end,
      function(sp) return sp.reflex >= -40 and sp.cup > 0.6 end }) do
    local seed = 1
    while true do
      local sp = species.sample(seed, "any")
      if sp.form == "lily" and sp.orient ~= "erect" and want(sp) then break end
      seed = seed + 1
    end
    pic(fmt("florilegium inflorescence={seed=%d, role=any, scale=1, season=0.75}", seed))
  end
  for _, seed in ipairs({ 6, 8, 10 }) do pic(fmt("florilegium leaf={seed=%d, role=lily, size=4cm}", seed)) end
  -- a simple leaf of every shape, apex, base and attachment, one with stipules, a lobed
  -- spear-shaped one, every margin and venation and a hairy toothed one (the first seed that
  -- has each; one pic per seed)
  do
    local seen = {}
    local function simple(sp) return sp.compound == "simple" and sp.venation ~= "parallel" end
    local wants = {}
    for _, v in ipairs({ "lanceolate", "elliptic", "ovate", "obovate", "oblong", "orbicular", "cordate", "reniform",
      "deltoid", "sagittate", "hastate" }) do wants[#wants + 1] = function(sp) return sp.leafshape == v end end
    for _, v in ipairs({ "acute", "acuminate", "obtuse", "rounded", "emarginate", "mucronate" }) do
      wants[#wants + 1] = function(sp) return sp.leafapex == v end end
    for _, v in ipairs({ "cuneate", "rounded", "truncate", "cordate", "auriculate", "oblique" }) do
      wants[#wants + 1] = function(sp) return sp.leafbase == v end end
    for _, v in ipairs({ "petiolate", "sessile", "clasping" }) do
      wants[#wants + 1] = function(sp) return sp.attachment == v end end
    wants[#wants + 1] = function(sp) return sp.stipules ~= "none" end
    wants[#wants + 1] = function(sp) return sp.leafshape == "hastate" and sp.leafmargin == "lobed" end
    for _, v in ipairs({ "entire", "undulate", "serrate", "doubly", "dentate", "crenate", "lobed", "pinnatifid",
      "palmatelobed" }) do wants[#wants + 1] = function(sp) return sp.leafmargin == v end end
    for _, v in ipairs({ "pinnate", "arcuate", "palmate" }) do wants[#wants + 1] = function(sp) return sp.venation == v end end
    wants[#wants + 1] = function(sp) return sp.hairy == 1 and sp.leafmargin == "serrate" end
    for _, want in ipairs(wants) do
      local seed = 1
      while true do
        local sp = species.sample(seed, "any")
        if simple(sp) and want(sp) then break end
        seed = seed + 1
      end
      if not seen[seed] then
        seen[seed] = true
        pic(fmt("florilegium leaf={seed=%d, role=any, size=3.4cm}", seed))
      end
    end
  end
  -- tendrils, each its own: the leaves of a pea whose leaves end in them (three draws, one
  -- of them forked at least), and a climbing pea's plant with tendrils of its own
  do
    local seed = 1
    while true do
      local sp = species.sample(seed, "any")
      if sp.tendrils == 1 and sp.compound == "pinnate" and sp.habit == "climbing" then break end
      seed = seed + 1
    end
    for d = 1, 3 do pic(fmt("florilegium leaf={seed=%d, draw=%d, size=3.4cm}", seed, d)) end
    pic(fmt("florilegium plant={seed=%d, role=any, size=8.5cm, width=5.2cm, season=0.75}", seed))
  end
  -- compound leaves: pinnate with a terminal leaflet (many pairs, two pairs, leafy
  -- stipules, toothed or lobed leaflets), twice pinnate, palmate (many leaflets and few),
  -- trifoliate (one with lobed leaflets), and small ones whose leaflets are drawn simpler;
  -- then plants whose leaves come in crossed pairs (a mint) or sheathe the stem (a lily,
  -- an umbellifer)
  do
    local cwants = {
      { function(sp) return sp.compound == "pinnate" and sp.tendrils == 0 and sp.leaflets >= 6 end },
      { function(sp) return sp.compound == "pinnate" and sp.leaflets == 2 end },
      { function(sp) return sp.compound == "pinnate" and sp.stipules == "leafy" end },
      { function(sp) return sp.compound == "pinnate" and sp.leafmargin == "serrate" end },
      { function(sp) return sp.compound == "pinnate" and sp.leafmargin == "lobed" end },
      { function(sp) return sp.compound == "pinnate" end, "1.1cm" },
      { function(sp) return sp.compound == "bipinnate" end },
      { function(sp) return sp.compound == "bipinnate" and sp.leafmargin == "pinnatifid" end },
      { function(sp) return sp.compound == "bipinnate" end, "1.6cm" },
      { function(sp) return sp.compound == "palmate" and sp.leaflets >= 8 end },
      { function(sp) return sp.compound == "palmate" and sp.leaflets <= 6 end },
      { function(sp) return sp.compound == "trifoliate" end },
      { function(sp) return sp.compound == "trifoliate" and sp.leafmargin == "lobed" end },
      { function(sp) return sp.compound == "trifoliate" end, "0.9cm" },
    }
    local cseen = {}
    for _, w in ipairs(cwants) do
      local seed = 1
      while not w[1](species.sample(seed, "any")) do seed = seed + 1 end
      local size = w[2] or "3.4cm"
      if not cseen[seed .. size] then
        cseen[seed .. size] = true
        pic(fmt("florilegium leaf={seed=%d, role=any, size=%s}", seed, size))
      end
    end
    -- curled tips: narrow and broad leaves of species whose leaves curl, three draws each
    -- so that some curl and some do not
    for _, shape in ipairs({ "lanceolate", "elliptic", "ovate" }) do
      local seed = 1
      while true do
        local sp = species.sample(seed, "any")
        if sp.compound == "simple" and sp.venation ~= "parallel" and sp.leafshape == shape and sp.curl > 0.25 and sp.hairy == 0 and sp.leafmargin ~= "lobed"
          and sp.leafmargin ~= "pinnatifid" and sp.leafmargin ~= "palmatelobed" then break end
        seed = seed + 1
      end
      for d = 1, 3 do pic(fmt("florilegium leaf={seed=%d, draw=%d, role=any, size=3.4cm}", seed, seed + d)) end
    end
    for _, p in ipairs({ "5/mint", "17/lily", "17/umbellifer" }) do
      local seed, role = p:match("(%d+)/(%a+)")
      pic(fmt("florilegium plant={seed=%s, role=%s, size=8.5cm, width=5.2cm, season=0.75}", seed, role))
    end
  end
  pic("florilegium v13 flower={seed=7, size=1.9cm}")
  pic("florilegium v13 leaf={seed=7, size=4cm}")
  end
  if not fernonly then
  -- visitors: a butterfly or moth with each wing tip, edge and tail, each pattern system
  -- (central band or spots, base, discal spot, border band, spots, eyespots of one to three
  -- rings, arcs, lunules, no veins), each ground and pose, each kind of feeler, a hawkmoth;
  -- honeybees, bumblebees and solitary bees of each ground and pose, with and without pollen,
  -- bands and a pale tail; hoverflies resting and hovering; dragonflies of each ground and
  -- tint, with and without the stigma and rings; damselflies folded and spread; beetles
  -- plain, striped and spotted, of each ground and feeler; ladybirds red and black, with
  -- 0, 7, 14 and 22 spots; caterpillars of each pose, stripe, ground, with tufts or a horn;
  -- snails coiled either way, high- and low-spired, banded and plain, with and without a
  -- lip, ribbed, corded, open-coiled and withdrawn into the shell; seed-eaters with and without a crest, nectar birds hovering and perched with each
  -- bill; small ones, drawn simpler
  local vseen = {}
  for _, w in ipairs({
      { "butterfly", function(v) return v.apex == "rounded" and v.wingedge == "smooth" and v.pose == "open" end },
      { "butterfly", function(v) return v.apex == "angular" and v.tails == 1 end },
      { "butterfly", function(v) return v.apex == "falcate" and v.wingedge == "toothed" end },
      { "butterfly", function(v) return v.wingedge == "scalloped" and v.tails == 2 end },
      { "butterfly", function(v) return v.central == "band" and v.basal == 1 and v.discal == 1 end },
      { "butterfly", function(v) return v.central == "spots" and v.border == "band" end },
      { "butterfly", function(v) return v.border == "spots" and v.lunules == 2 end },
      { "butterfly", function(v) return v.border == "eyes" and v.rings == 1 and v.veins == 0 end },
      { "butterfly", function(v) return v.border == "eyes" and v.rings == 2 and v.parafocal == 1 end },
      { "butterfly", function(v) return v.border == "eyes" and v.rings == 3 and v.eyes >= 4 end },
      { "butterfly", function(v) return v.pose == "closed" and v.border == "eyes" end },
      { "butterfly", function(v) return v.ground == "copper" end },
      { "butterfly", function(v) return v.ground == "pale" end },
      { "moth", function(v) return v.kind == "moth" and v.pose == "tent" and v.antenna == "feathery" end },
      { "moth", function(v) return v.kind == "moth" and v.pose == "flat" and v.antenna == "thread" end },
      { "moth", function(v) return v.kind == "moth" and v.border == "eyes" end },
      { "moth", function(v) return v.kind == "hawkmoth" end },
      { "bee", function(v) return v.kind == "honeybee" and v.pose == "visit" and v.ground == "ink" end },
      { "bee", function(v) return v.kind == "honeybee" and v.pose == "fly" and v.ground == "copper" and v.pollen == 1 end },
      { "bee", function(v) return v.kind == "bumblebee" and v.bands == 1 and v.paletail == 1 and v.pose == "visit" end },
      { "bee", function(v) return v.kind == "bumblebee" and v.bands == 4 end },
      { "bee", function(v) return v.kind == "bumblebee" and v.paletail == 0 end },
      { "bee", function(v) return v.kind == "bumblebee" and v.ground == "copper" and v.pose == "fly" end },
      { "bee", function(v) return v.kind == "solitarybee" and v.ground == "dark" and v.pollen == 1 end },
      { "bee", function(v) return v.kind == "solitarybee" and v.bands == 0 end },
      { "bee", function(v) return v.kind == "solitarybee" and v.ground == "copper" end },
      { "fly", function(v) return v.pose == "rest" and v.ground == "copper" end },
      { "fly", function(v) return v.pose == "hover" and v.ground == "ink" end },
      { "fly", function(v) return v.pose == "rest" and v.bands == 4 end },
      { "dragonfly", function(v) return v.ground == "ink" and v.tint == "clear" and v.stigma == 1 and v.bands >= 6 end },
      { "dragonfly", function(v) return v.ground == "copper" and v.tint == "tinted" end },
      { "dragonfly", function(v) return v.ground == "dark" and v.stigma == 0 end },
      { "dragonfly", function(v) return v.bands == 0 end },
      { "damselfly", function(v) return v.pose == "folded" and v.tint == "clear" end },
      { "damselfly", function(v) return v.pose == "spread" and v.tint == "tinted" and v.stigma == 1 end },
      { "damselfly", function(v) return v.pose == "folded" and v.ground == "copper" end },
      { "beetle", function(v) return v.kind == "beetle" and v.pattern == "plain" and v.ground == "dark" end },
      { "beetle", function(v) return v.kind == "beetle" and v.pattern == "stripes" and v.ground == "ink" end },
      { "beetle", function(v) return v.kind == "beetle" and v.pattern == "stripes" and v.ground == "dark" end },
      { "beetle", function(v) return v.kind == "beetle" and v.pattern == "spots" and v.spots % 2 == 1 end },
      { "beetle", function(v) return v.kind == "beetle" and v.pattern == "spots" and v.spots >= 8 end },
      { "beetle", function(v) return v.kind == "beetle" and v.antenna == "comb" end },
      { "beetle", function(v) return v.kind == "beetle" and v.antenna == "clubbed" end },
      { "beetle", function(v) return v.kind == "beetle" and v.ground == "copper" end },
      { "ladybird", function(v) return v.ground == "copper" and v.spots == 7 end },
      { "ladybird", function(v) return v.ground == "dark" and v.spots > 0 end },
      { "ladybird", function(v) return v.spots == 22 end },
      { "ladybird", function(v) return v.spots == 14 end },
      { "ladybird", function(v) return v.spots == 0 end },
      { "caterpillar", function(v) return v.pose == "straight" and v.stripes == "side" and v.horn == 1 end },
      { "caterpillar", function(v) return v.pose == "loop" and v.stripes == "none" end },
      { "caterpillar", function(v) return v.pose == "curl" and v.tufts == 1 end },
      { "caterpillar", function(v) return v.stripes == "back" and v.tufts == 1 and v.horn == 0 end },
      { "caterpillar", function(v) return v.ground == "copper" and v.pose == "straight" end },
      { "caterpillar", function(v) return v.ground == "pale" and v.pose == "loop" end },
      { "snail", function(v) return v.hand == "sinistral" end },
      { "snail", function(v) return v.spire > 1 and v.shellbands == 5 and v.lip == 1 end },
      { "snail", function(v) return v.spire < 0.3 and v.shellbands == 0 end },
      { "snail", function(v) return v.ground == "copper" and v.shellbands > 0 end },
      { "snail", function(v) return v.ground == "pale" and v.expansion > 2.8 end },
      { "snail", function(v) return v.sculpture == "ribs" and v.withdrawn == 0 end },
      { "snail", function(v) return v.sculpture == "cords" and v.shellbands > 0 end },
      { "snail", function(v) return v.withdrawn == 1 and v.lip == 1 end },
      { "snail", function(v) return v.opencoil == 1 end },
      { "perch", function(v) return v.crest == 1 end },
      { "perch", function(v) return v.ground == "dark" end },
      { "perch", function(v) return v.ground == "copper" end },
      { "hummingbird", function(v) return v.pose == "hover" and v.bill == "curved" end },
      { "hummingbird", function(v) return v.pose == "perch" and v.bill == "straight" end },
      { "hummingbird", function(v) return v.pose == "hover" and v.ground == "copper" and v.crest == 1 end } }) do
    local seed = 1
    while vseen[w[1] .. seed] or not w[2](species.vsample(seed, w[1])) do seed = seed + 1 end
    vseen[w[1] .. seed] = true
    pic(fmt("florilegium visitor={seed=%d, role=%s, size=3cm}", seed, w[1]))
  end
  pic("florilegium visitor={seed=4, role=butterfly, size=0.9cm}")
  pic("florilegium visitor={seed=3, role=moth, size=0.5cm}")
  pic("florilegium visitor={seed=8, role=bee, size=0.22cm}")
  pic("florilegium visitor={seed=2, role=fly, size=0.6cm}")
  pic("florilegium visitor={seed=3, role=dragonfly, size=1.2cm}")
  pic("florilegium visitor={seed=5, role=damselfly, size=0.8cm}")
  pic("florilegium visitor={seed=4, role=beetle, size=0.22cm}")
  pic("florilegium visitor={seed=6, role=ladybird, size=0.2cm}")
  pic("florilegium visitor={seed=7, role=caterpillar, size=0.6cm}")
  pic("florilegium visitor={seed=9, role=snail, size=0.2cm}")
  pic("florilegium visitor={seed=8, role=snail, size=0.7cm}")
  pic("florilegium visitor={seed=11, role=hummingbird, size=0.25cm}")
  end
  if not fernonly and not visonly then
  for _, s in ipairs({ "0.15", "0.75", "1.3" }) do
    pic(fmt("florilegium plant={seed=17, role=rose, size=8.5cm, width=5.2cm, season=%s}", s))
  end
  if full then
    pic("florilegium plants={plants={3/rose,17/umbellifer,29/mustard}, size=21cm, width=6cm}")
    pic("florilegium plants={plants={3/daisy,17/lily,29/rose}, size=21cm, width=6cm}")
  end
  end
  local list = assert(io.open("build/tikzcheck-draw.pics", "w"))
  for _, p in ipairs(pics) do list:write("\\begin{tikzpicture}\\pic {", p, "};\\end{tikzpicture}\\newpage\n") end
  list:close()
  local res = {}
  for _, engine in ipairs({ "tikz", "lua" }) do
    local job = "tikzcheck-draw-" .. engine
    local t0 = os.time()
    if not reuse then
      os.remove("build/" .. job .. ".pdf")
      os.execute(fmt([[lualatex -interaction=batchmode -output-directory=build -jobname=%s "\def\tikzcheckengine{%s}\input{tools/tikzcheck-draw.tex}" >/dev/null]],
        job, engine))
    end
    local pdf = io.open("build/" .. job .. ".pdf", "rb")
    if not pdf then error("tikzcheck: the " .. engine .. " build failed, see build/" .. job .. ".log") end
    local size = pdf:seek("end")
    pdf:close()
    res[engine] = { secs = os.time() - t0, size = size, streams = streams("build/" .. job .. ".pdf") }
  end
  local a, b = res.tikz.streams, res.lua.streams
  assert(#a == #pics and #b == #pics, fmt("tikzcheck: %d pics, %d and %d pages", #pics, #a, #b))
  -- every page of both PDFs as a gray image (pdftoppm numbers them with as many digits as
  -- the last page needs)
  local function pgm(path)
    local f = assert(io.open(path, "rb"), "tikzcheck: no " .. path)
    local d = f:read("a")
    f:close()
    local w, h, at = d:match("^P5%s+(%d+)%s+(%d+)%s+%d+%s()")
    return tonumber(w), tonumber(h), d:sub(at)
  end
  for _, engine in ipairs({ "tikz", "lua" }) do
    os.execute(fmt("pdftoppm -gray -r 150 build/tikzcheck-draw-%s.pdf build/tikzcheck-draw-%s", engine, engine))
  end
  -- pics where pgfmath's rounding and a double's send a choice different ways, each looked
  -- at and the step found: reported, not counted
  local KNOWN = {
    ["florilegium plant={seed=54, role=any, size=8.5cm, width=5.2cm, season=0.75}"] =
      "a leaf's room disc 0.0002 cm either side of a cell's edge (pgfmath's five-digit veclen), so TeX grows one more branch",
  }
  local digits = #tostring(#pics)
  local bad, worst, wdark = 0, 0, 0
  -- a pic fails when its ink is this much darker or lighter, by at least 60 pixels' worth of a
  -- quarter gray: a hairline's pixels darken with where it falls on the grid (poppler draws it
  -- at least a pixel wide), which moves a pic of veins and stalks up to 3% either way
  local DARK, DARKMIN = 0.035, 60 * 64
  for i = 1, #pics do
    local n = fmt("%0" .. digits .. "d", i)
    local w, h, x = pgm("build/tikzcheck-draw-tikz-" .. n .. ".pgm")
    local w2, h2, y = pgm("build/tikzcheck-draw-lua-" .. n .. ".pgm")
    -- each drawing from the center of its ink: a pic whose box differs by a fraction of a
    -- point sits a pixel over on its page; and a pixel differs
    -- only where nothing within a pixel of it in the other drawing is near its gray, both
    -- ways, so a hairline drawn a fraction of a pixel aside is the same hairline
    local function corner(d)                         -- the center of the ink's darkness
      local sx, sy, sw = 0, 0, 0
      for k = 1, #d do
        local v = 255 - d:byte(k)
        if v > 5 then sx, sy, sw = sx + v * ((k - 1) % w), sy + v * ((k - 1) // w), sw + v end
      end
      if sw == 0 then return 0, 0, 0 end
      return math.floor(sx / sw + 0.5), math.floor(sy / sw + 0.5), sw
    end
    local inked, differ
    local dark = 0
    if w ~= w2 or h ~= h2 then differ, inked = 1, 1
    else
      local ax, ay, da = corner(x)
      local bx, by, db = corner(y)
      -- the ink's total darkness, which a fill drawn lighter, darker or not at all moves while
      -- every pixel stays near a gray of the other (a leaf's darker half, 28% multiplied in)
      dark = (da > 0 and math.abs(db - da) >= DARKMIN) and (db - da) / da or 0
      local function at(d, px, py)
        if px < 0 or px >= w or py < 0 or py >= h then return 255 end
        return d:byte(py * w + px + 1)
      end
      local function near(d, px, py, v)              -- a gray within 64 of v around (px, py)?
        for oy = -1, 1 do
          for ox = -1, 1 do
            if math.abs(at(d, px + ox, py + oy) - v) < 64 then return true end
          end
        end
        return false
      end
      local function count(dx, dy, step)             -- inked and differing pixels at an offset
        local ink, m = 0, 0
        for k = 1, #x, step do
          local px, py = (k - 1) % w, (k - 1) // w
          local p, q = x:byte(k), at(y, px + dx, py + dy)
          if p < 250 or q < 250 then
            ink = ink + 1
            if not near(y, px + dx, py + dy, p) or not near(x, px, py, q) then m = m + 1 end
          end
        end
        return ink, m
      end
      -- the offset, within two pixels of the centers', at which the drawings agree best
      local best, bdx, bdy = math.huge, bx - ax, by - ay
      for ddy = -2, 2 do
        for ddx = -2, 2 do
          local _, m = count(bx - ax + ddx, by - ay + ddy, 7)
          if m < best then best, bdx, bdy = m, bx - ax + ddx, by - ay + ddy end
        end
      end
      inked, differ = count(bdx, bdy, 1)
    end
    local share = inked > 0 and differ / inked or 0
    if share >= 0.01 and differ >= 60 or math.abs(dark) >= DARK then
      local what = fmt("page %d (%s): %d of its inked pixels differ, %.2f%%; Lua's ink %+.2f%% as dark", i, pics[i],
        differ, 100 * share, 100 * dark)
      if KNOWN[pics[i]] then print(what .. ", as known: " .. KNOWN[pics[i]])
      else bad = bad + 1 print(what) end
    end
    if not KNOWN[pics[i]] then worst, wdark = math.max(worst, share), math.max(wdark, math.abs(dark)) end
  end
  print(fmt("tikzcheck draw: %d pics, %d differ in 1%% or more of their inked pixels and 60 or more, or in their ink's darkness by %.1f%% "
    .. "(the largest share %.3f%%, darkness %.2f%%, but for the known)", #pics, bad, 100 * DARK, 100 * worst, 100 * wdark))
  print(fmt("  pure TikZ %d s, %d bytes; Lua %d s, %d bytes", res.tikz.secs, res.tikz.size, res.lua.secs, res.lua.size))
  os.exit(bad == 0 and 0 or 1)
end

-- ================================================================ choices
local species = require("florilegium-species")
local pm = require("florilegium-pgfmath")
local from, to = tonumber(arg[1]) or 1, tonumber(arg[2]) or 1000
local engine = arg[3] or "lualatex"
local role = arg[4] or "any"
local visitor = role:match("^v:(.+)")
if visitor then role = visitor end
local fixtext = arg[5]
local fix = fixtext and species.fixes(fixtext, visitor ~= nil)
local job = "tikzcheck-" .. engine

local cmd = fmt([[%s -interaction=batchmode -output-directory=build -jobname=%s "%s%s\def\tikzcheckfrom{%d}\def\tikzcheckto{%d}\def\tikzcheckrole{%s}\input{tools/tikzcheck.tex}" >/dev/null]],
  engine, job, visitor and "\\def\\tikzcheckvisitor{}" or "", fixtext and ("\\def\\tikzcheckfix{" .. fixtext .. "}") or "", from, to, role)
local t0 = os.time()
os.remove("build/" .. job .. ".choices")
os.execute(cmd)
if not io.open("build/" .. job .. ".choices") then error("tikzcheck: " .. engine .. " failed, see build/" .. job .. ".log") end
local secs = os.time() - t0

local tex = {}
for line in io.lines("build/" .. job .. ".choices") do tex[#tex + 1] = line end
assert(#tex == to - from + 1, fmt("tikzcheck: %d species from TeX, expected %d", #tex, to - from + 1))

local function fields(line)
  local t = {}
  for k, v in line:gmatch("(%w+)=(%S+)") do t[#t + 1] = { k, v } end
  return t
end

local bad = 0
for i, line in ipairs(tex) do
  local seed = from + i - 1
  local lua = { { "seed", tostring(seed) } }
  ;(visitor and species.vsample or species.sample)(seed, role, function(t, v)
    lua[#lua + 1] = { t, math.type(v) == "float" and pm.str(math.floor(v * 65536 + 0.5)) or tostring(v) }
  end, fix)
  local got = fields(line)
  local why
  if #got ~= #lua then why = fmt("%d traits from TeX, %d from Lua", #got, #lua) end
  for j = 1, math.min(#got, #lua) do
    if why then break end
    local k, a, b = got[j][1], got[j][2], lua[j][2]
    if k ~= lua[j][1] then why = fmt("trait %d is %s in TeX, %s in Lua", j, k, lua[j][1])
    elseif a ~= b and not (b:find("%.") and tonumber(a) and pm.sp(a) == pm.sp(b)) then
      why = fmt("%s: TeX %s, Lua %s", k, a, b)
    end
  end
  if why then
    bad = bad + 1
    if bad <= 10 then print(fmt("seed %d: %s", seed, why)) end
  end
end
print(fmt("%s: %d %s (role %s%s) in %d s, %d differ", engine, #tex, visitor and "visitors" or "species", role,
  fixtext and ", " .. fixtext or "", secs, bad))
os.exit(bad == 0 and 0 or 1)
