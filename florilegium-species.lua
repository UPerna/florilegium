-- florilegium-species.lua -- species for florilegium: a plant sampled from a genome.
-- Copyright (c) 2026 Kevin Raymond. MIT License: see LICENSE or florilegium.sty.
--
-- A species is a table of traits drawn in a fixed order: the body plan first (which
-- fixes the clade, monocot or eudicot), then the pollination syndrome, then the
-- flower, its cluster, the leaf, the stem and the fruit. Each body plan gives every
-- trait a distribution, so the hard rules of botany hold by construction: a lily
-- has its parts in threes, a pea flower is two-sided, a cross of petals has four.
--
-- The same tables drive the TikZ library (tikzlibraryflorilegium.code.tex): M.tex()
-- writes them as TeX (tools/tikztables.lua), and both sides draw from pgf's generator
-- (ink.pgfrng), so one seed gives one species in either. Every choice is an integer
-- draw (pgf's random(a,b)), and a real-valued trait is the very number pgfmath computes
-- (florilegium-pgfmath.lua), so the organs that compare one (a stage from the phenology)
-- choose as the TikZ library does.
--
-- The botany follows the trait tables in Florilegium Genomes (2026, the author's
-- research notes): body plans and their bundles, the hard rules (e.g. variable petal
-- number only in radially symmetric flowers, after Damerval & Nadot 2007), and the
-- pollination syndromes of the U.S. Forest Service (public domain).

local ink = require("florilegium-ink")
local pm = require("florilegium-pgfmath")
local M = {}
M.version = "2.0.0"                 -- the release; florilegium.lua checks that every file has the same

local floor, fmt, concat = math.floor, string.format, table.concat

-- ---------------------------------------------------------------- distributions
-- W(v1, w1, v2, w2, ...) a weighted choice (integer weights); I(a, b) an integer;
-- R(a, b) a real number (drawing only); C(v) a constant (no draw); BY(trait, map)
-- the distribution in map[value of an earlier trait], or map._ ; maps may nest.
local function W(...) return { "w", ... } end
local function I(a, b) return { "i", a, b } end
local function R(a, b) return { "r", a, b } end
local function C(v) return { "c", v } end
local function BY(key, map) return { "by", key, map } end

-- the order of the draws; every species draws them in this order
M.TRAITS = {
  "plan", "clade", "syndrome", "color", "form", "symmetry", "fused", "merosity", "merovar",
  "petalshape", "petalaspect", "apex", "petalmargin", "petalamp", "claw", "reflex", "overlap", "cup",
  "guides", "guidecount", "picotee", "corona", "spurs", "stamens", "orient",
  "inflo", "count", "rays", "depth", "openorder", "siderule", "coil", "size",
  "compound", "leaflets", "leafshape", "leafaspect", "leafmargin", "teeth", "dissection",
  "leafapex", "leafbase", "venation", "attachment", "stipules", "arrangement",
  "curl", "twist", "taper", "turns", "habit", "section", "hairy", "tendrils", "fruit", "phenology",
  -- a fern's own, last, so that the flowering plans (constants here: no draws) are as they were
  "division", "pinnae", "outline", "stipe", "sori", "dimorphic",
}

-- ---------------------------------------------------------------- defaults
-- for every plan, then for each clade; a plan overrides any of them
local COMMON = {
  syndrome = W("bee", 4, "butterfly", 2, "moth", 2, "bird", 1, "beetle", 1, "fly", 1),
  color = BY("syndrome", {
    bee = W("blue", 6, "violet", 3, "white", 3, "yellow", 2),
    butterfly = W("violet", 4, "pink", 3, "blue", 2, "red", 1, "orange", 1),
    moth = W("white", 6, "pink", 2, "yellow", 1),
    bird = W("red", 5, "orange", 3, "pink", 1),
    beetle = W("white", 5, "green", 2, "pink", 1),
    fly = W("white", 5, "yellow", 3, "violet", 1),
    wind = C("green"),
  }),
  symmetry = BY("form", { bilabiate = C("bilateral"), papilionaceous = C("bilateral"), orchid = C("bilateral"),
    _ = C("radial") }),
  fused = BY("form", { campanulate = C(1), urceolate = C(1), tubular = C(1), funnelform = C(1), salverform = C(1),
    bilabiate = C(1), rotate = W(0, 2, 1, 1), _ = C(0) }),
  merovar = C(0),
  petalshape = W("orbicular", 2, "obovate", 5, "spatulate", 2, "oblong", 2, "lanceolate", 2, "linear", 1),
  petalaspect = R(1.1, 2.2),
  apex = W("rounded", 12, "acute", 4, "acuminate", 2, "emarginate", 4, "bifid", 1, "fringed", 1),
  petalmargin = W("entire", 14, "undulate", 6, "crenate", 2, "fimbriate", 1, "laciniate", 1),
  petalamp = R(0.01, 0.06),
  claw = R(0, 0.1),
  reflex = R(-10, 30),
  overlap = R(0, 0.3),
  cup = R(0.2, 0.8),
  guides = BY("syndrome", {
    bee = W("lines", 6, "dots", 1, "eye", 1, "none", 2),
    butterfly = W("lines", 2, "eye", 1, "none", 3),
    fly = W("none", 3, "dots", 1),
    _ = C("none"),
  }),
  guidecount = I(2, 6),
  picotee = W(0, 9, 1, 1),
  corona = C("none"),
  spurs = C("none"),
  stamens = BY("syndrome", { bird = W("exserted", 3, "included", 1), moth = W("exserted", 2, "included", 1),
    _ = W("included", 3, "exserted", 1) }),
  orient = BY("form", {
    campanulate = W("nodding", 4, "horizontal", 1), urceolate = C("nodding"), tubular = W("horizontal", 1, "nodding", 1),
    bilabiate = C("horizontal"), papilionaceous = C("horizontal"), orchid = C("horizontal"), iris = C("erect"),
    head = C("erect"), rotate = W("erect", 3, "horizontal", 2), salverform = W("erect", 1, "horizontal", 1),
    _ = W("erect", 2, "horizontal", 2, "nodding", 1),
  }),
  count = BY("inflo", {
    solitary = C(1), raceme = I(5, 14), spike = I(10, 30), panicle = I(12, 30), corymb = I(8, 20),
    umbel = I(5, 14), cumbel = I(5, 12), dichasium = I(3, 15), monochasium = I(6, 16), head = I(15, 30),
    catkin = I(30, 80), thyrse = I(12, 30),
  }),
  rays = BY("inflo", { cumbel = I(8, 20), _ = C(0) }),
  depth = BY("inflo", { panicle = I(1, 2), dichasium = I(1, 3), thyrse = I(1, 2), _ = C(0) }),
  openorder = BY("inflo", {
    raceme = C("base"), spike = C("base"), panicle = C("base"), catkin = C("base"), thyrse = C("base"),
    corymb = C("outside"), head = C("outside"), umbel = W("outside", 3, "center", 1), cumbel = W("outside", 3, "center", 1),
    dichasium = C("center"), monochasium = C("center"), solitary = C("none"),
  }),
  siderule = BY("inflo", { monochasium = W("same", 2, "alternate", 1), _ = C("none") }),
  coil = R(0.4, 1.0),
  compound = W("simple", 8, "pinnate", 2, "palmate", 1, "trifoliate", 1),
  leaflets = BY("compound", { pinnate = I(2, 7), bipinnate = I(3, 8), palmate = I(5, 9), trifoliate = C(3), _ = C(1) }),
  leafaspect = BY("leafshape", {
    linear = R(8, 20), lanceolate = R(3.5, 6), elliptic = R(1.8, 3), ovate = R(1.4, 2.4), obovate = R(1.6, 2.6),
    oblong = R(2.2, 3.5), cordate = R(1.1, 1.6), orbicular = R(0.9, 1.15), reniform = R(0.6, 0.9),
    deltoid = R(1, 1.4), sagittate = R(1.5, 2.5), hastate = R(1.5, 2.5),
  }),
  teeth = BY("leafmargin", { serrate = I(10, 28), doubly = I(10, 22), dentate = I(6, 16), crenate = I(6, 14),
    lobed = I(3, 7), pinnatifid = I(4, 9), palmatelobed = I(3, 7), _ = C(0) }),
  dissection = BY("leafmargin", { entire = C(0), undulate = R(0, 0.05), serrate = R(0.04, 0.12),
    doubly = R(0.06, 0.14), dentate = R(0.06, 0.16), crenate = R(0.05, 0.12), lobed = R(0.3, 0.6),
    pinnatifid = R(0.6, 0.92), palmatelobed = R(0.35, 0.65) }),
  leafbase = BY("leafshape", { cordate = C("cordate"), reniform = C("cordate"), sagittate = C("auriculate"),
    hastate = C("auriculate"), _ = W("cuneate", 5, "rounded", 3, "truncate", 1, "oblique", 1) }),
  stipules = W("none", 4, "small", 1),
  curl = R(-0.3, 0.4),
  twist = R(0, 50),
  taper = R(0.4, 0.9),
  turns = W(0, 1, 1, 1),
  habit = W("erect", 6, "sprawling", 2, "climbing", 1),
  section = C("round"),
  hairy = W(0, 3, 1, 1),
  tendrils = C(0),
  phenology = R(-0.15, 0.15),
  division = C(0), pinnae = C(0), outline = C("none"), stipe = C(0), sori = C("none"), dimorphic = C(0),
}

local EUDICOT = {
  merosity = W(5, 70, 4, 22, 6, 5, 3, 3),
  -- leaflets of a compound leaf are oval or narrow, never heart- or arrow-shaped
  leafshape = BY("compound", {
    simple = W("lanceolate", 3, "elliptic", 3, "ovate", 4, "obovate", 1, "oblong", 1, "cordate", 2,
      "orbicular", 1, "reniform", 1, "deltoid", 1, "sagittate", 1, "hastate", 1),
    _ = W("elliptic", 4, "ovate", 3, "lanceolate", 2, "obovate", 1) }),
  leafmargin = W("entire", 4, "serrate", 5, "doubly", 1, "dentate", 2, "crenate", 2, "undulate", 1,
    "lobed", 2, "pinnatifid", 1, "palmatelobed", 1),
  leafapex = W("acute", 6, "acuminate", 3, "obtuse", 2, "rounded", 2, "emarginate", 1, "mucronate", 1),
  venation = BY("leafmargin", { palmatelobed = C("palmate"),
    _ = BY("leafshape", { orbicular = W("palmate", 2, "pinnate", 1), reniform = C("palmate"),
      cordate = W("palmate", 1, "pinnate", 1), _ = W("pinnate", 7, "arcuate", 2) }) }),
  -- a blade with basal lobes sits on a stalk (or clasps the stem), never flat on it; one
  -- draw either way, so the traits after it stay as they were
  attachment = BY("leafshape", { cordate = W("petiolate", 4, "clasping", 1), reniform = W("petiolate", 4, "clasping", 1),
    sagittate = W("petiolate", 4, "clasping", 1), hastate = W("petiolate", 4, "clasping", 1),
    _ = W("petiolate", 7, "sessile", 2, "clasping", 1) }),
  arrangement = W("alternate", 6, "opposite", 3, "whorled", 1),
}

local MONOCOT = {
  merosity = W(3, 98, 4, 2),
  compound = C("simple"),
  leafshape = W("linear", 6, "lanceolate", 3, "elliptic", 1),
  leafmargin = C("entire"),
  leafapex = W("acute", 6, "acuminate", 3),
  venation = C("parallel"),
  attachment = W("sheathing", 5, "sessile", 2, "clasping", 1),
  arrangement = W("alternate", 2, "distichous", 2, "rosette", 1),
  hairy = W(0, 9, 1, 1),
}

-- a fern bears no flowers: every flower trait is a constant (no draw); its fronds are
-- leaves of their own kind (compound "frond"), from a crown at the root
local FERN = {
  syndrome = C("none"), color = C("green"), form = C("none"), symmetry = C("none"), fused = C(0),
  merosity = C(0), petalshape = C("none"), petalaspect = C(1), apex = C("none"), petalmargin = C("none"),
  petalamp = C(0), claw = C(0), reflex = C(0), overlap = C(0), cup = C(0), guides = C("none"), guidecount = C(0),
  picotee = C(0), spurs = C("none"), stamens = C("none"), orient = C("erect"), inflo = C("none"), count = C(0),
  rays = C(0), depth = C(0), openorder = C("none"), siderule = C("none"), coil = C(0), size = C(0),
  compound = C("frond"), leaflets = C(0), leafaspect = C(1), teeth = C(0), dissection = C(0),
  leafbase = C("truncate"), venation = C("forked"), attachment = C("none"), stipules = C("none"),
  arrangement = C("crown"), twist = C(0), taper = C(1), habit = C("erect"), tendrils = C(0), fruit = C("spores"),
}
local CLADE = { monocot = MONOCOT, eudicot = EUDICOT, fern = FERN }

-- ---------------------------------------------------------------- body plans
-- w: weight in a pool; roles: which places on a page it can fill (hero: a big flower
-- at a stem's top; spray: small flowers that fill branches; monocot: the strap-leaved
-- plant). Report section 5b; sizes are the real flower (or head) diameter in mm.
M.PLANS = {
  { name = "lily", clade = "monocot", w = 8, roles = { hero = 1, monocot = 1 }, d = {
    syndrome = W("bee", 3, "butterfly", 3, "moth", 3, "bird", 1),
    form = C("lily"), merosity = C(3),
    petalshape = W("lanceolate", 4, "oblong", 2, "obovate", 1), petalaspect = R(2.5, 4.5),
    apex = W("acute", 4, "acuminate", 2, "rounded", 1), reflex = R(-80, 20), cup = R(0, 1),
    guides = W("dots", 3, "lines", 2, "none", 2),
    stamens = W("exserted", 4, "included", 1),
    inflo = W("solitary", 4, "raceme", 3, "umbel", 1),
    size = R(40, 90),
    leafshape = W("linear", 3, "lanceolate", 3, "elliptic", 1),
    arrangement = W("alternate", 3, "whorled", 1),
    fruit = C("capsule"),
  } },
  { name = "iris", clade = "monocot", w = 6, roles = { hero = 1, monocot = 1 }, d = {
    syndrome = W("bee", 8, "moth", 1, "bird", 1),
    form = W("iris", 5, "orchid", 3), merosity = C(3),
    petalshape = W("obovate", 3, "spatulate", 3, "oblong", 1), petalaspect = R(1.6, 3), claw = R(0.2, 0.45),
    guides = BY("syndrome", { bee = W("lines", 4, "blotch", 2, "dots", 1), _ = W("none", 2, "lines", 1) }),
    inflo = W("solitary", 4, "raceme", 3),
    size = R(40, 80),
    leafshape = BY("form", { iris = C("linear"), _ = W("elliptic", 2, "lanceolate", 2) }),
    arrangement = BY("form", { iris = C("distichous"), _ = W("rosette", 1, "alternate", 1) }),
    fruit = C("capsule"),
  } },
  { name = "rose", clade = "eudicot", w = 10, roles = { hero = 1 }, d = {
    syndrome = W("bee", 5, "beetle", 3, "fly", 1),
    form = W("rosaceous", 8, "rotate", 2), fused = C(0),
    merosity = W(5, 85, 4, 5, 6, 10), merovar = W(0, 4, 1, 1),
    petalshape = W("orbicular", 3, "obovate", 4), petalaspect = R(0.9, 1.5), claw = R(0, 0.05),
    overlap = R(0.1, 0.4),
    stamens = C("included"),
    inflo = W("solitary", 5, "corymb", 3),
    size = R(30, 70),
    compound = W("pinnate", 6, "simple", 2),
    leafmargin = W("serrate", 7, "doubly", 2),
    stipules = W("small", 1, "leafy", 1),
    arrangement = C("alternate"),
    section = W("round", 1, "prickly", 1),
    fruit = W("hip", 4, "pome", 1, "drupe", 1),
  } },
  { name = "mustard", clade = "eudicot", w = 8, roles = { spray = 1 }, d = {
    syndrome = W("bee", 4, "fly", 3, "butterfly", 3),
    form = C("cruciform"), merosity = C(4),
    petalshape = W("obovate", 3, "orbicular", 1, "spatulate", 1), apex = W("rounded", 3, "emarginate", 2),
    claw = R(0.3, 0.5),
    inflo = C("raceme"),
    size = R(8, 20),
    compound = C("simple"),
    leafmargin = W("entire", 2, "dentate", 2, "lobed", 3, "pinnatifid", 3),
    arrangement = W("alternate", 2, "rosette", 1),
    fruit = W("silique", 3, "silicle", 2),
  } },
  { name = "pea", clade = "eudicot", w = 8, roles = { spray = 1 }, d = {
    syndrome = W("bee", 9, "bird", 1),
    form = C("papilionaceous"), merosity = C(5),
    guides = W("lines", 3, "none", 1),
    inflo = W("raceme", 6, "head", 1, "solitary", 1),
    size = R(10, 22),
    compound = W("pinnate", 6, "trifoliate", 3),
    leafshape = W("elliptic", 3, "ovate", 2, "obovate", 2, "oblong", 1),
    leafmargin = W("entire", 5, "serrate", 1),
    stipules = W("leafy", 3, "small", 1),
    arrangement = C("alternate"),
    habit = W("climbing", 4, "erect", 2),
    tendrils = BY("compound", { pinnate = W(1, 3, 0, 1), _ = C(0) }),
    fruit = C("legume"),
  } },
  { name = "mint", clade = "eudicot", w = 8, roles = { spray = 1 }, d = {
    syndrome = W("bee", 8, "bird", 2),
    form = C("bilabiate"), merosity = C(5),
    guides = W("dots", 2, "lines", 2, "none", 1),
    inflo = W("spike", 4, "raceme", 2),
    size = R(8, 18),
    compound = C("simple"),
    leafshape = W("ovate", 3, "lanceolate", 2, "cordate", 1, "elliptic", 1),
    leafmargin = W("serrate", 5, "crenate", 3, "dentate", 2),
    attachment = W("petiolate", 2, "sessile", 1),
    arrangement = C("opposite"),
    section = C("square"),
    fruit = C("nutlets"),
  } },
  { name = "daisy", clade = "eudicot", w = 10, roles = { hero = 1, spray = 1 }, d = {
    syndrome = W("butterfly", 4, "fly", 3, "bee", 3),
    form = C("head"), merosity = I(8, 21),
    petalshape = W("linear", 4, "oblong", 3, "spatulate", 2), petalaspect = R(3, 6),
    apex = W("rounded", 3, "emarginate", 2, "bifid", 1, "acute", 1),
    guides = C("none"),
    inflo = W("solitary", 6, "corymb", 3),
    size = R(15, 45),
    compound = C("simple"),
    leafmargin = W("lobed", 3, "pinnatifid", 3, "dentate", 2, "serrate", 2, "entire", 1),
    arrangement = W("alternate", 4, "rosette", 2, "opposite", 1),
    fruit = W("pappus", 3, "achene", 2),
  } },
  { name = "umbellifer", clade = "eudicot", w = 8, roles = { spray = 1 }, d = {
    syndrome = W("fly", 5, "beetle", 3, "bee", 1),
    form = C("rotate"), fused = C(0), merosity = C(5),
    color = W("white", 6, "yellow", 2, "pink", 1),
    guides = C("none"),
    inflo = C("cumbel"),
    size = R(2, 4.5),
    compound = W("bipinnate", 5, "pinnate", 3),
    leafmargin = W("dentate", 3, "lobed", 2, "pinnatifid", 2),
    attachment = C("sheathing"),
    arrangement = C("alternate"),
    section = C("ribbed"),
    fruit = C("schizocarp"),
  } },
  { name = "heath", clade = "eudicot", w = 6, roles = { spray = 1 }, d = {
    syndrome = W("bee", 7, "bird", 2, "moth", 1),
    form = W("campanulate", 5, "urceolate", 5), merosity = W(5, 3, 4, 2),
    inflo = W("raceme", 6, "solitary", 2),
    size = R(5, 12),
    compound = C("simple"),
    leafshape = W("linear", 3, "elliptic", 2), leafmargin = C("entire"),
    arrangement = W("alternate", 2, "whorled", 2, "opposite", 1),
    fruit = W("berry", 3, "capsule", 1),
  } },
  { name = "borage", clade = "eudicot", w = 8, roles = { spray = 1 }, d = {
    syndrome = W("bee", 9, "butterfly", 1),
    form = W("rotate", 5, "salverform", 5), fused = C(1), merosity = C(5),
    guides = C("eye"),
    inflo = C("monochasium"),
    size = R(6, 20),
    compound = C("simple"),
    leafshape = W("lanceolate", 3, "elliptic", 2, "oblong", 1), leafmargin = C("entire"),
    arrangement = C("alternate"),
    hairy = C(1),
    fruit = C("nutlets"),
  } },
  { name = "catkin", clade = "eudicot", w = 3, roles = { spray = 1 }, d = {
    syndrome = C("wind"),
    form = C("none"), merosity = C(0),
    guides = C("none"), stamens = C("exserted"), orient = C("nodding"),
    inflo = C("catkin"),
    size = R(1, 2),
    compound = C("simple"),
    leafmargin = W("serrate", 4, "doubly", 2, "crenate", 1),
    arrangement = C("alternate"),
    habit = C("woody"),
    fruit = W("nut", 2, "samara", 1),
  } },
  { name = "columbine", clade = "eudicot", w = 5, roles = { hero = 1 }, d = {
    syndrome = W("bee", 4, "moth", 2, "bird", 3),
    form = C("spurred"), merosity = C(5), spurs = C("all"),
    petalshape = W("obovate", 2, "oblong", 2), stamens = W("exserted", 3, "included", 1),
    orient = W("nodding", 2, "horizontal", 1),
    inflo = W("solitary", 3, "panicle", 2, "raceme", 1),
    size = R(25, 50),
    compound = C("trifoliate"),
    leafshape = W("obovate", 2, "orbicular", 1), leafmargin = C("lobed"),
    arrangement = W("alternate", 1, "rosette", 1),
    fruit = C("follicle"),
  } },
  { name = "eudicot", clade = "eudicot", w = 10, roles = { hero = 1, spray = 1 }, d = {
    form = W("rotate", 4, "rosaceous", 3, "campanulate", 2, "funnelform", 2, "salverform", 2, "tubular", 1),
    merovar = BY("form", { rotate = W(0, 4, 1, 1), rosaceous = W(0, 4, 1, 1), _ = C(0) }),
    inflo = W("solitary", 3, "raceme", 2, "dichasium", 2, "corymb", 1, "panicle", 1, "umbel", 1, "thyrse", 1),
    size = BY("inflo", { solitary = R(25, 60), _ = R(8, 25) }),
    fruit = W("capsule", 4, "berry", 2, "follicle", 1, "samara", 1),
  } },
  { name = "monocot", clade = "monocot", w = 4, roles = { hero = 1, monocot = 1 }, d = {
    syndrome = W("bee", 3, "moth", 2, "butterfly", 2, "bird", 1),
    form = W("lily", 3, "rotate", 2, "tubular", 1, "campanulate", 1),
    corona = BY("form", { lily = W("none", 6, "cup", 2, "trumpet", 1), _ = C("none") }),
    inflo = W("solitary", 2, "raceme", 3, "spike", 2, "umbel", 2),
    size = BY("inflo", { solitary = R(30, 70), _ = R(8, 25) }),
    leafmargin = W("entire", 19, "undulate", 1),
    venation = W("parallel", 9, "arcuate", 1),
    fruit = W("capsule", 4, "berry", 1),
  } },
  -- a fern (report section 4d): fronds divided once to three times (pinnae, pinnules, their
  -- lobes), in an outline, on a bare stipe; spores in sori under the pinnae; in a dimorphic
  -- fern the fertile fronds are narrow and beaded. Only the role "fern" draws it (apart):
  -- a page's ferns grow at the root beside its four flowering plants. Leaf traits: the
  -- pinna's (or pinnule's) taper, tip and edge; curl: how far the fronds arch over
  { name = "fern", clade = "fern", w = 1, roles = {}, apart = true, d = {
    leafshape = W("lanceolate", 3, "oblong", 2), leafapex = W("acute", 3, "obtuse", 2, "rounded", 1),
    leafmargin = W("entire", 3, "crenate", 3, "serrate", 2),
    curl = R(0, 0.6), turns = W(0, 1, 1, 1), hairy = W(0, 1, 1, 1),
    division = W(1, 5, 2, 4, 3, 2),
    pinnae = BY("division", { ["1"] = I(14, 26), ["2"] = I(10, 16), _ = I(8, 13) }),
    outline = BY("division", { ["1"] = W("lanceolate", 4, "oblong", 3, "ovate", 1),
      _ = W("lanceolate", 4, "ovate", 2, "deltoid", 3, "oblong", 1) }),
    stipe = R(0.12, 0.4),
    sori = W("dots", 5, "lines", 2, "marginal", 2, "none", 1),
    dimorphic = W(0, 4, 1, 1),
  } },
}
local PLAN = {}
for i, p in ipairs(M.PLANS) do PLAN[p.name] = p p.index = i end

-- a trait's distribution for a plan: the plan's own, else its clade's, else everyone's
function M.dist(plan, trait)
  local p = PLAN[plan]
  if trait == "clade" then return C(p.clade) end
  return p.d[trait] or CLADE[p.clade][trait] or COMMON[trait]
end

-- the plans a role may draw, as a W over plan names (in M.PLANS order); a role may also
-- name one plan ("rose", "fern"), for a specimen of that plan. A role's own name comes
-- first: "monocot" is the role (lily, iris or the generic monocot), not the plan of that
-- name. "any" draws every flowering plan (not a plan set apart, the fern).
M.ROLES = { hero = true, spray = true, monocot = true, any = true }
function M.roleplans(role)
  if PLAN[role] and not M.ROLES[role] then return W(role, PLAN[role].w) end
  local t = {}
  for _, p in ipairs(M.PLANS) do
    if (role == "any" and not p.apart) or p.roles[role] then t[#t + 1] = p.name t[#t + 1] = p.w end
  end
  assert(#t > 0, "florilegium: no plant for the role " .. tostring(role))
  return W(table.unpack(t))
end

-- ---------------------------------------------------------------- sampling
-- one draw from a distribution; rng is an ink.pgfrng; sp holds the traits drawn so far
local function draw(d, rng, sp)
  local kind = d[1]
  if kind == "c" then return d[2]
  elseif kind == "i" then return rng.random(d[2], d[3])
  elseif kind == "r" then
    -- as \flo@R{a}{b-a} computes it: \pgfmathparse{a+(b-a)*rnd}, to the scaled point
    local a, w = pm.sp(tostring(d[2])), pm.sp(tostring(d[3] - d[2]))
    return pm.add(a, pm.mulf(w, math.floor(rng.rnd() * 65536 + 0.5))) / 65536
  elseif kind == "w" then
    local total = 0
    for i = 3, #d, 2 do total = total + d[i] end
    local k = rng.random(1, total)
    for i = 2, #d, 2 do
      k = k - d[i + 1]
      if k <= 0 then return d[i] end
    end
  elseif kind == "by" then
    local v = sp[d[2]]
    local sub = d[3][tostring(v)] or d[3]._
    assert(sub, "florilegium: no distribution for " .. d[2] .. " = " .. tostring(v))
    return draw(sub, rng, sp)
  end
  error("florilegium: unknown distribution " .. tostring(kind))
end

-- a species from a pgf seed (1 .. 2^31-2) for a role ("hero", "spray", "monocot",
-- "any"); log, if given, is a function(trait, value) called after every draw. Returns the
-- species and the generator, left where \florilegiumspecies leaves pgf's (organs go on
-- from there). A real-valued trait is the number pgfmath computes, a multiple of 2^-16.
-- Lehmer's generator answers seeds 1, 2, 3 ... with nearly proportional first values,
-- so the first two are thrown away (TikZ: \pgfmathgeneratepseudorandomnumber twice).
M.WARM = 2
-- fix, if given, is a table of traits fixed (M.fixes): each still takes its draw, then its
-- value is the fixed one, and a trait that depends on it (BY) follows it; a fixed plan
-- picks its own distributions. The traits drawn before a fixed one are as they would have
-- been; those after it too, unless a trait that depends on it draws differently (a
-- constant takes no draw, a range one), which moves every later draw along
function M.sample(seed, role, log, fix)
  fix = fix or {}
  local rng = ink.pgfrng(seed)
  for _ = 1, M.WARM do rng.step() end
  local sp = { seed = seed, role = role or "any" }
  sp.plan = draw(M.roleplans(sp.role), rng, sp)
  if fix.plan ~= nil then sp.plan = fix.plan end
  if log then log("plan", sp.plan) end
  for i = 2, #M.TRAITS do
    local t = M.TRAITS[i]
    sp[t] = draw(M.dist(sp.plan, t), rng, sp)
    if fix[t] ~= nil then sp[t] = fix[t] end
    if log then log(t, sp[t]) end
  end
  return sp, rng
end

-- ---------------------------------------------------------------- the rules
-- report section 5c; a species that breaks one is a bug in the tables
local FUSED = { campanulate = 1, urceolate = 1, tubular = 1, funnelform = 1, salverform = 1, bilabiate = 1 }
local SIDEWAYS = { bilabiate = 1, papilionaceous = 1, orchid = 1 }
function M.violations(sp)
  local v = {}
  local function check(ok, what) if not ok then v[#v + 1] = what end end
  local mono = sp.clade == "monocot"
  check(not mono or sp.merosity == 3 or sp.merosity == 6 or sp.merosity == 4, "monocot with parts not in threes")
  check(not mono or sp.merosity ~= 5, "monocot with five parts")
  check(not mono or sp.leafmargin == "entire" or sp.leafmargin == "undulate", "monocot with a toothed leaf")
  check(not SIDEWAYS[sp.form] or (sp.symmetry == "bilateral" and sp.orient == "horizontal"), "two-sided form not two-sided")
  check(sp.form ~= "papilionaceous" or (sp.merosity == 5 and sp.fruit == "legume"), "pea flower without five parts and a pod")
  check(not FUSED[sp.form] or sp.fused == 1, "fused form with free petals")
  check((sp.form ~= "rosaceous" and sp.form ~= "cruciform") or sp.fused == 0, "rose or cross form with fused petals")
  check(sp.form ~= "cruciform" or sp.merosity == 4, "cross of petals without four")
  check(sp.inflo ~= "catkin" or (sp.form == "none" and sp.syndrome == "wind"), "catkin with petals or a visitor")
  check(sp.syndrome ~= "wind" or sp.inflo == "catkin", "wind flower outside a catkin")
  check((sp.inflo ~= "cumbel" and sp.form ~= "head") or sp.form == "head" or sp.size <= 5, "umbel flowers too big")
  check(sp.merovar == 0 or sp.symmetry == "radial", "variable petal number in a two-sided flower")
  check(sp.spurs ~= "one" or sp.symmetry == "bilateral", "one spur on a radial flower")
  check(sp.tendrils == 0 or sp.compound == "pinnate", "tendrils without a pinnate leaf")
  local fern = sp.clade == "fern"
  check(fern == (sp.division > 0), "a flowering plant with fronds, or a fern without")
  check(fern or (sp.pinnae == 0 and sp.sori == "none" and sp.dimorphic == 0), "a frond's traits on a flowering plant")
  check(not fern or (sp.form == "none" and sp.inflo == "none" and sp.compound == "frond"), "a fern with flowers")
  check(not fern or (sp.pinnae >= 8 and sp.stipe > 0 and sp.outline ~= "none"), "a frond without pinnae or stipe")
  return v
end

-- ---------------------------------------------------------------- in words
local NUM = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
  "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "twenty-one",
  "twenty-two", "twenty-three", "twenty-four", "twenty-five", "twenty-six" }
local COLOR = { blue = "blue", violet = "violet", pink = "pink", red = "red", orange = "orange", yellow = "yellow",
  white = "white", green = "green" }
local FOR = { bee = "for bees", butterfly = "for butterflies", moth = "for moths at dusk", bird = "for birds",
  beetle = "for beetles", fly = "for flies and hoverflies", wind = "pollinated by the wind" }
local INFLO = {
  solitary = "alone on its stalk", raceme = "along a raceme", spike = "in a dense spike",
  panicle = "in branched panicles", corymb = "in a flat-topped cluster", umbel = "in an umbel",
  cumbel = "in a compound umbel", dichasium = "in forked cymes", monochasium = "in a coiled cyme that uncurls",
  head = "in a round head", catkin = "in hanging catkins", thyrse = "in a crowded thyrse",
}
local MARGIN = { entire = "smooth-edged", undulate = "wavy", serrate = "toothed", doubly = "doubly toothed",
  dentate = "coarsely toothed", crenate = "scalloped", lobed = "lobed", pinnatifid = "deeply cut",
  palmatelobed = "hand-lobed" }
local SHAPE = { linear = "strap-shaped", lanceolate = "narrow", elliptic = "oval", ovate = "egg-shaped",
  obovate = "spoon-shaped", oblong = "oblong", cordate = "heart-shaped", orbicular = "round",
  reniform = "kidney-shaped", deltoid = "triangular", sagittate = "arrow-shaped", hastate = "spear-shaped" }
local ARRANGE = { alternate = "", opposite = ", in pairs", whorled = ", in whorls", rosette = ", in a rosette at the foot",
  distichous = ", in two flat ranks" }
local FRUIT = { capsule = "capsules", berry = "berries", hip = "hips", pome = "small apples", drupe = "stone fruit",
  legume = "pods", silique = "long thin pods", silicle = "round flat pods", nutlets = "nutlets",
  pappus = "seeds with parachutes", achene = "small dry seeds", schizocarp = "paired ribbed seeds",
  follicle = "pods that split down one side", samara = "winged seeds", nut = "nuts" }

local function n_(k) return NUM[k] or fmt("%d", k) end
local function a_(word) return (word:match("^[aeiou]") and "an " or "a ") .. word end

local function flower_words(sp)
  local n, f = sp.merosity, sp.form
  local c = (sp.orient == "nodding" and f ~= "none" and "nodding " or "") .. COLOR[sp.color]
  local parts = sp.clade == "monocot" and 2 * n or n     -- a monocot's parts come in two whorls of n
  if f == "head" then return a_(c) .. " daisy head of " .. n_(n) .. " rays"
  elseif f == "lily" and sp.corona ~= "none" then        -- the narcissus' corona, short or long
    return a_(c) .. (sp.corona == "cup" and " narcissus of " or " daffodil of ") .. n_(2 * n) .. " tepals around a "
      .. (sp.corona == "cup" and "short cup" or "long trumpet")
  elseif f == "lily" then
    local shape = sp.reflex < -40 and "swept-back" or sp.cup > 0.6 and "trumpet" or sp.cup < 0.3 and "starry" or "cupped"
    return a_(c) .. " lily of " .. n_(2 * n) .. " " .. shape .. " tepals"
  elseif f == "iris" then return a_(c) .. " iris of three falls and three standards"
  elseif f == "orchid" then return a_(c) .. " orchid with a broad lip"
  elseif f == "papilionaceous" then return a_(c) .. " pea flower"
  elseif f == "bilabiate" then return a_(c) .. " two-lipped flower"
  elseif f == "cruciform" then return a_(c) .. " cross of four petals"
  elseif f == "spurred" then return a_(c) .. " flower with " .. n_(n) .. " spurs"
  elseif f == "campanulate" then return a_(c) .. " bell of " .. n_(parts) .. " lobes"
  elseif f == "urceolate" then return a_(c) .. " urn"
  elseif f == "tubular" then return a_(c) .. " tube"
  elseif f == "funnelform" then return a_(c) .. " trumpet"
  elseif f == "salverform" then return a_(c) .. " flat-faced tube of " .. n_(parts) .. " lobes"
  elseif f == "none" then return "tiny petal-less flowers"
  end
  local some = sp.merovar > 0 and "mostly " or ""
  if f == "rotate" and sp.fused == 1 then return a_(c) .. " wheel of " .. some .. n_(parts) .. " lobes" end
  return a_(some .. n_(parts) .. "-petalled " .. c) .. (f == "rosaceous" and " rose" or " wheel")
end

local function leaf_words(sp)
  local m, s = MARGIN[sp.leafmargin], SHAPE[sp.leafshape]
  local leaf
  if sp.compound == "pinnate" then leaf = "leaves of " .. n_(sp.leaflets) .. " pairs of " .. m .. " leaflets"
  elseif sp.compound == "bipinnate" then leaf = "finely twice-divided leaves"
  elseif sp.compound == "palmate" then leaf = "hand-shaped leaves of " .. n_(sp.leaflets) .. " " .. m .. " leaflets"
  elseif sp.compound == "trifoliate" then leaf = "leaves in threes of " .. m .. " leaflets"
  else leaf = (sp.hairy == 1 and "hairy, " or "") .. m .. ", " .. s .. " leaves" end
  if sp.venation == "parallel" then leaf = leaf .. " with parallel veins"
  elseif sp.venation == "palmate" then leaf = leaf .. " veined from the base" end
  return leaf .. ARRANGE[sp.arrangement]
end

-- a fern in words: its fronds, their pinnae, their stalk, where its spores are
local DIVIDED = { "once-divided", "twice-divided", "thrice-divided" }
local OUTLINE = { lanceolate = "lance-shaped", oblong = "narrow, parallel-sided", ovate = "egg-shaped",
  deltoid = "triangular" }
local SORI = { dots = "in round dots", lines = "in lines", marginal = "along the edges" }
local function fern_words(sp)
  local part = sp.division == 1 and MARGIN[sp.leafmargin] .. " pinnae"
    or "pinnae cut into " .. (sp.division == 3 and "lobed " or "") .. "pinnules"
  local s = "a fern of " .. DIVIDED[sp.division] .. ", " .. OUTLINE[sp.outline] .. " fronds of " .. n_(sp.pinnae)
    .. " pairs of " .. part .. " on " .. (sp.hairy == 1 and "a scaly" or "a bare") .. " stalk, unrolling from fiddleheads in spring"
  if sp.dimorphic == 1 then s = s .. "; the fertile fronds narrow and beaded" end
  s = s .. (sp.sori == "none" and "; its spores hidden" or "; spores " .. SORI[sp.sori] .. " beneath")
  return s .. (sp.turns == 1 and ", the fronds turning copper in autumn." or ".")
end

-- one sentence: what it looks like, how it flowers, who it is for, its leaves, its fruit
function M.describe(sp)
  if sp.clade == "fern" then local s = fern_words(sp) return s:sub(1, 1):upper() .. s:sub(2) end
  local s = flower_words(sp) .. " " .. INFLO[sp.inflo] .. ", " .. FOR[sp.syndrome] .. "; "
    .. leaf_words(sp) .. (sp.tendrils == 1 and ", climbing by tendrils" or "") .. "; then " .. FRUIT[sp.fruit] .. "."
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- ---------------------------------------------------------------- a document's plants
-- showy: flowers that can carry a page, one at a time or in a loose cluster, not a
-- raceme, spike, catkin or compound umbel of small ones (those make a page's sprays),
-- and painted in the ink: red and orange take the copper, which the margin keeps sparing
local SPRAYS = { cumbel = true, raceme = true, spike = true, panicle = true, thyrse = true, catkin = true, monochasium = true }
function M.showy(sp) return not SPRAYS[sp.inflo] and sp.color ~= "red" and sp.color ~= "orange" end

-- a pool of eight species for a document (docseed: \florilegiumseed, or 0), each with a
-- role, no body plan twice, both heroes showy; ink.rng streams, Lua only (TikZ draws
-- species by seed)
local SLOTS = { "hero", "hero", "spray", "spray", "monocot", "any", "any", "any" }
local pools = {}
function M.pool(docseed)
  docseed = docseed or 0
  if pools[docseed] then return pools[docseed] end
  local rng = ink.rng(docseed * 104729 + 307)
  local pool, used = {}, {}
  for i, role in ipairs(SLOTS) do
    local sp
    local tries = 0
    repeat
      sp = M.sample(1 + floor(rng.u() * 2147483645), role)
      tries = tries + 1
      assert(tries < 10000, "florilegium-species: no body plan left for the role " .. role)
    until not used[sp.plan] and (role ~= "hero" or M.showy(sp))
    used[sp.plan] = true
    sp.slot = i
    pool[i] = sp
  end
  pools[docseed] = pool
  return pool
end

-- the document's fern (docseed as for the pool): from a stream of its own, so the pool is
-- as it was; the pages that have ferns all have this one
local ferns = {}
function M.fern(docseed)
  docseed = docseed or 0
  if not ferns[docseed] then
    local rng = ink.rng(docseed * 104729 + 401)
    ferns[docseed] = M.sample(1 + floor(rng.u() * 2147483645), "fern")
  end
  return ferns[docseed]
end

-- the four that grow on one page (rng: the page's species stream), in the order of
-- the stems they grow on: the hero (main stem 1), a second showy plant (2: the other
-- hero, or a showy one of the rest), the monocot (3) and a spray (the footer)
function M.community(pool, rng)
  local hero = pool[1 + floor(rng.u() * 2)]
  local spray = pool[3 + floor(rng.u() * 2)]
  local mono = pool[5]
  local showy = {}
  for _, sp in ipairs(pool) do
    if sp ~= hero and sp ~= spray and sp ~= mono and M.showy(sp) then showy[#showy + 1] = sp end
  end
  local second = showy[1 + floor(rng.u() * #showy)]   -- never empty: the other hero is showy
  return { hero, second, mono, spray }
end

-- ---------------------------------------------------------------- visitors
-- A visitor is sampled as a plant is, from a genome of its own: its kind first (a
-- butterfly, a bumblebee, a damselfly ...), which fixes its group, then the traits the
-- report gives that kind (section 6), each a constant where the kind has no such thing.
-- size is the real animal's in mm (a wingspan for butterflies and moths, a body length
-- for the others, a shell's width for a snail); ground the wash it is painted in (the
-- ink, pale, dark or the copper, which takes orange, red and yellow); pose how it is seen.
-- The order of the draws; every visitor draws them in this order
M.VTRAITS = {
  "kind", "group", "size", "tone", "ground", "pose",
  -- wings of butterflies and moths: tip, edge, tails; the pattern systems of the nymphalid
  -- groundplan (bands near the body, a central band or spots with a discal spot, a border
  -- band, spots or eyespots with their rings and the arcs outside them, lunules at the edge;
  -- after Schwanwitsch 1924 and Süffert 1927), veins; the feelers
  "apex", "wingedge", "tails", "basal", "central", "discal", "border", "eyes", "rings", "parafocal",
  "lunules", "veins", "antenna",
  -- bees and hoverflies: abdomen bands, hair, pollen carried, width for length, a pale tail
  "bands", "hair", "pollen", "build", "paletail",
  -- dragonflies and damselflies: tinted wings, the dark spot near each tip
  "tint", "stigma",
  -- beetles and ladybirds: the wing cases' pattern and spots
  "pattern", "spots", "spotsize",
  -- caterpillars: stripes, hair tufts, a tail horn
  "stripes", "tufts", "horn",
  -- snails: whorls, how fast the coil widens, spire height for width, handedness, bands,
  -- a flared lip, how far the foot is out
  "whorls", "expansion", "spire", "hand", "shellbands", "lip", "extension",
  -- birds: the bill, a crest, the tail for the body's length
  "bill", "crest", "tail",
  -- snails' shells (the shells report, part A): the mouth's height for its width (Raup's S),
  -- how deep the suture runs, the sculpture and its ribs a whorl, a coil whose whorls part,
  -- and a snail withdrawn into its shell. Last, so no other visitor draws differently
  "aperture", "suture", "sculpture", "ribs", "opencoil", "withdrawn",
}
-- what a kind does not have: every trait a constant (no draw)
local VNONE = {
  pose = C("none"), apex = C("none"), wingedge = C("none"), tails = C(0), basal = C(0), central = C("none"),
  discal = C(0), border = C("none"), eyes = C(0), rings = C(0), parafocal = C(0), lunules = C(0), veins = C(0),
  antenna = C("none"), bands = C(0), hair = C(0), pollen = C(0), build = C(0), paletail = C(0), tint = C("none"),
  stigma = C(0), pattern = C("none"), spots = C(0), spotsize = C(0), stripes = C("none"), tufts = C(0), horn = C(0),
  whorls = C(0), expansion = C(0), spire = C(0), hand = C("none"), shellbands = C(0), lip = C(0), extension = C(0),
  bill = C("none"), crest = C(0), tail = C(0),
  aperture = C(0), suture = C(0), sculpture = C("none"), ribs = C(0), opencoil = C(0), withdrawn = C(0),
}
-- the wings of butterflies and moths: the groundplan's border system decides the spots
local BORDER_EYES = BY("border", { eyes = I(1, 6), spots = I(3, 7), _ = C(0) })
local BORDER_RINGS = BY("border", { eyes = I(1, 3), _ = C(0) })
local BORDER_ARCS = BY("border", { eyes = W(1, 1, 0, 1), _ = C(0) })
-- kinds: group; w, the weight among all kinds; roles, the weight in each role (a flower's
-- pollinator: bee, butterfly, moth, bird, beetle, fly; off the flowers: leaf, stem, perch)
M.VKINDS = {
  { name = "butterfly", group = "lepidoptera", w = 6, roles = { butterfly = 1 }, d = {
    size = R(30, 70), tone = R(0.26, 0.4), ground = W("ink", 5, "copper", 3, "pale", 2, "dark", 1),
    pose = W("open", 3, "closed", 2),
    apex = W("rounded", 4, "angular", 3, "falcate", 1), wingedge = W("smooth", 5, "scalloped", 3, "toothed", 1),
    tails = W(0, 7, 1, 2, 2, 1), basal = W(0, 1, 1, 1), central = W("none", 3, "band", 2, "spots", 1),
    discal = W(0, 1, 1, 1), border = W("eyes", 3, "spots", 2, "band", 1, "none", 2),
    eyes = BORDER_EYES, rings = BORDER_RINGS, parafocal = BORDER_ARCS, lunules = I(0, 2), veins = W(1, 3, 0, 1),
    antenna = C("clubbed"),
  } },
  { name = "moth", group = "lepidoptera", w = 3, roles = { moth = 3 }, d = {
    size = R(25, 60), tone = R(0.3, 0.5), ground = W("pale", 4, "dark", 3, "ink", 2, "copper", 1),
    pose = W("tent", 3, "flat", 2),
    apex = W("rounded", 3, "angular", 2), wingedge = W("smooth", 4, "scalloped", 1),
    basal = W(0, 1, 1, 1), central = W("band", 3, "spots", 1, "none", 1), discal = W(1, 3, 0, 1),
    border = W("band", 2, "spots", 2, "eyes", 1, "none", 1),
    eyes = BORDER_EYES, rings = BORDER_RINGS, parafocal = BORDER_ARCS, lunules = I(0, 2), veins = W(0, 2, 1, 1),
    antenna = W("thread", 3, "feathery", 2), hair = R(0.3, 0.8),
  } },
  -- a hawkmoth hovers at a long tube on narrow swept wings
  { name = "hawkmoth", group = "lepidoptera", w = 1, roles = { moth = 1 }, d = {
    size = R(40, 90), tone = R(0.3, 0.48), ground = W("dark", 2, "pale", 1, "copper", 1), pose = C("hover"),
    apex = C("pointed"), wingedge = C("smooth"), basal = W(0, 1, 1, 1), central = W("band", 2, "none", 1),
    discal = W(1, 1, 0, 1), border = W("band", 2, "none", 1), lunules = I(0, 1), veins = W(0, 2, 1, 1),
    antenna = C("thread"), bands = I(3, 6), hair = R(0.4, 0.8),
  } },
  { name = "honeybee", group = "bee", w = 3, roles = { bee = 3 }, d = {
    size = R(12, 15), tone = R(0.3, 0.42), ground = W("ink", 3, "copper", 1), pose = W("visit", 2, "fly", 1),
    antenna = C("elbowed"), bands = I(4, 6), hair = R(0.2, 0.4), pollen = W(1, 1, 0, 1), build = R(0.4, 0.45),
  } },
  { name = "bumblebee", group = "bee", w = 3, roles = { bee = 3 }, d = {
    size = R(14, 23), tone = R(0.28, 0.4), ground = W("ink", 3, "copper", 2), pose = W("visit", 2, "fly", 1),
    antenna = C("elbowed"), bands = I(1, 4), hair = R(0.7, 1), pollen = W(1, 1, 0, 1), build = R(0.5, 0.6),
    paletail = W(1, 2, 0, 1),
  } },
  { name = "solitarybee", group = "bee", w = 2, roles = { bee = 2 }, d = {
    size = R(6, 14), tone = R(0.34, 0.5), ground = W("dark", 3, "ink", 2, "copper", 1), pose = W("visit", 2, "fly", 1),
    antenna = C("elbowed"), bands = I(0, 3), hair = R(0.1, 0.4), pollen = W(1, 1, 0, 2), build = R(0.28, 0.34),
  } },
  { name = "hoverfly", group = "fly", w = 3, roles = { fly = 1 }, d = {
    size = R(8, 15), tone = R(0.3, 0.42), ground = W("ink", 3, "copper", 2), pose = W("hover", 2, "rest", 3),
    antenna = C("short"), bands = I(3, 4), hair = R(0, 0.3), build = R(0.3, 0.45),
  } },
  { name = "dragonfly", group = "odonate", w = 2, roles = { stem = 2 }, d = {
    size = R(40, 75), tone = R(0.28, 0.42), ground = W("ink", 4, "copper", 1, "dark", 1), pose = C("cross"),
    bands = I(0, 8), tint = W("clear", 4, "tinted", 1), stigma = W(1, 4, 0, 1),
  } },
  { name = "damselfly", group = "odonate", w = 2, roles = { stem = 2 }, d = {
    size = R(28, 45), tone = R(0.28, 0.42), ground = W("ink", 4, "copper", 1), pose = W("folded", 3, "spread", 1),
    bands = I(0, 8), tint = W("clear", 3, "tinted", 2), stigma = W(1, 3, 0, 1),
  } },
  { name = "beetle", group = "beetle", w = 2, roles = { beetle = 2 }, d = {
    size = R(6, 20), tone = R(0.3, 0.5), ground = W("dark", 3, "ink", 2, "copper", 1), pose = C("walk"),
    antenna = W("thread", 3, "clubbed", 1, "comb", 1), build = R(0.45, 0.7),
    pattern = W("plain", 3, "stripes", 2, "spots", 2), spots = BY("pattern", { spots = I(2, 8), _ = C(0) }),
    spotsize = BY("pattern", { spots = R(0.08, 0.16), _ = C(0) }),
  } },
  { name = "ladybird", group = "beetle", w = 2, roles = { beetle = 1, stem = 1 }, d = {
    size = R(4, 9), tone = R(0.3, 0.45), ground = W("copper", 5, "dark", 1), pose = C("walk"),
    antenna = C("clubbed"), build = R(0.8, 0.9), pattern = C("spots"),
    spots = W(2, 2, 7, 4, 10, 1, 14, 1, 22, 1, 0, 1), spotsize = R(0.08, 0.2),
  } },
  { name = "caterpillar", group = "larva", w = 2, roles = { leaf = 1 }, d = {
    size = R(20, 45), tone = R(0.28, 0.45), ground = W("ink", 3, "pale", 1, "copper", 1),
    pose = W("straight", 3, "loop", 2, "curl", 2), build = R(0.1, 0.15),
    stripes = W("none", 2, "side", 2, "back", 1), tufts = W(0, 3, 1, 1), horn = W(0, 3, 1, 1),
  } },
  -- most snail species coil to the right (dextral); report section 6d
  { name = "snail", group = "snail", w = 2, roles = { leaf = 1 }, d = {
    size = R(12, 30), tone = R(0.28, 0.42), ground = W("ink", 3, "pale", 1, "copper", 1), pose = C("glide"),
    whorls = R(3.5, 6), expansion = R(1.6, 3.2), spire = R(0.1, 1.2), hand = W("dextral", 19, "sinistral", 1),
    shellbands = W(0, 3, 5, 2, 1, 1, 2, 1, 3, 1), lip = W(0, 1, 1, 1), extension = R(0.4, 1),
    -- about half of land snails are smooth; ribs 12-24 a whorl; an open coil is rare (report A2)
    aperture = R(0.85, 1.3), suture = R(0.15, 0.8), sculpture = W("smooth", 5, "ribs", 3, "cords", 2),
    ribs = BY("sculpture", { ribs = I(12, 24), _ = C(0) }), opencoil = W(0, 99, 1, 1), withdrawn = W(0, 7, 1, 3),
  } },
  -- a perching bird with a seed-eater's short conical bill, or a nectar bird (a
  -- hummingbird or a sunbird) with a long thin one, hovering or perched at the flower
  { name = "bird", group = "bird", w = 1, roles = { perch = 1 }, d = {
    size = R(90, 140), tone = R(0.28, 0.42), ground = W("ink", 3, "dark", 1, "copper", 1), pose = C("perch"),
    bill = C("conical"), crest = W(0, 4, 1, 1), tail = R(0.3, 0.5),
  } },
  { name = "hummingbird", group = "bird", w = 1, roles = { bird = 1 }, d = {
    size = R(70, 110), tone = R(0.28, 0.42), ground = W("ink", 3, "copper", 2), pose = W("hover", 2, "perch", 1),
    bill = W("curved", 2, "straight", 1), crest = W(0, 5, 1, 1), tail = R(0.3, 0.45),
  } },
}
local VKIND = {}
for i, k in ipairs(M.VKINDS) do VKIND[k.name] = k k.index = i end
M.VROLES = { bee = true, butterfly = true, moth = true, bird = true, beetle = true, fly = true, leaf = true,
  stem = true, perch = true, any = true }

function M.vdist(kind, trait)
  local k = VKIND[kind]
  if trait == "group" then return C(k.group) end
  return k.d[trait] or VNONE[trait]
end
-- the kinds a role may draw, as a W over kind names (in M.VKINDS order); a role may
-- also name one kind ("ladybird"); "any" draws every kind by its weight
function M.vrolekinds(role)
  if VKIND[role] and not M.VROLES[role] then return W(role, VKIND[role].w) end
  local t = {}
  for _, k in ipairs(M.VKINDS) do
    local w = role == "any" and k.w or k.roles[role]
    if w then t[#t + 1] = k.name t[#t + 1] = w end
  end
  assert(#t > 0, "florilegium: no visitor for the role " .. tostring(role))
  return W(table.unpack(t))
end
-- a visitor from a pgf seed for a role, as M.sample draws a plant
function M.vsample(seed, role, log, fix)
  fix = fix or {}
  local rng = ink.pgfrng(seed)
  for _ = 1, M.WARM do rng.step() end
  local v = { seed = seed, role = role or "any" }
  v.kind = draw(M.vrolekinds(v.role), rng, v)
  if fix.kind ~= nil then v.kind = fix.kind end
  if log then log("kind", v.kind) end
  for i = 2, #M.VTRAITS do
    local t = M.VTRAITS[i]
    v[t] = draw(M.vdist(v.kind, t), rng, v)
    if fix[t] ~= nil then v[t] = fix[t] end
    if log then log(t, v[t]) end
  end
  return v, rng
end

-- ---------------------------------------------------------------- a genome of your own
-- Some traits fixed, the rest sampled (board #5109): "compound=palmate, leaflets=7". The
-- values a trait may take are those some plan (or kind) can draw: one of its names, or a
-- whole number or a real number within the range the genome draws from. clade and group
-- follow from the plan and the kind and are not fixed themselves.
local function collect(d, acc)
  local k = d[1]
  local function num(lo, hi, real)
    acc.lo = acc.lo and math.min(acc.lo, lo) or lo
    acc.hi = acc.hi and math.max(acc.hi, hi) or hi
    acc.real = acc.real or real
  end
  local function one(v)
    if type(v) == "number" then num(v, v, math.type(v) == "float") else acc.names[v] = true end
  end
  if k == "c" then one(d[2])
  elseif k == "i" then num(d[2], d[3], false)
  elseif k == "r" then num(d[2], d[3], true)
  elseif k == "w" then for i = 2, #d, 2 do one(d[i]) end
  elseif k == "by" then for _, sub in pairs(d[3]) do collect(sub, acc) end
  end
end
local VALUES = {}
-- trait -> { names = {name = true}, lo, hi, real }: what fixing it may give, for plants
-- (visitor false) or visitors
function M.values(visitor)
  local key = visitor and "v" or "p"
  if VALUES[key] then return VALUES[key] end
  local out = {}
  local traits, first = visitor and M.VTRAITS or M.TRAITS, visitor and "kind" or "plan"
  for i, t in ipairs(traits) do
    local acc = { names = {} }
    if i == 1 then
      for _, x in ipairs(visitor and M.VKINDS or M.PLANS) do acc.names[x.name] = true end
    else
      for _, x in ipairs(visitor and M.VKINDS or M.PLANS) do
        collect(visitor and M.vdist(x.name, t) or M.dist(x.name, t), acc)
      end
    end
    out[t] = acc
  end
  out[visitor and "group" or "clade"] = nil
  assert(out[first])
  VALUES[key] = out
  return out
end
-- "trait=value, ..." as a table of fixed traits, each value as the sampler holds it (a name,
-- a whole number, or a real number to the scaled point, as TeX reads it); an unknown trait
-- or a value the genome cannot draw is an error
function M.fixes(text, visitor)
  local fix, vals = {}, M.values(visitor)
  for item in tostring(text or ""):gmatch("[^,]+") do
    local t, v = item:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if not t then
      if item:match("%S") then error("florilegium: not trait=value: '" .. item .. "'", 0) end
    else
      local ok = vals[t]
      if not ok then error("florilegium: " .. (visitor and "a visitor" or "a species") .. " has no trait '" .. t .. "'", 0) end
      local n = tonumber(v)
      if ok.names[v] then fix[t] = v
      elseif n and ok.lo and n >= ok.lo and n <= ok.hi and (ok.real or math.tointeger(n)) then
        fix[t] = ok.real and pm.sp(v) / 65536 or math.tointeger(n)
      else
        local names = {}
        for name in pairs(ok.names) do names[#names + 1] = name end
        table.sort(names)
        local range = ok.lo and fmt("%s from %s to %s", ok.real and "a number" or "a whole number", ok.lo, ok.hi) or nil
        error(fmt("florilegium: %s=%s cannot be drawn; %s is %s", t, v, t,
          concat(names, ", ") .. (#names > 0 and range and ", or " or "") .. (range or "")), 0)
      end
    end
  end
  return fix
end
-- the visitor rules; a visitor that breaks one is a bug in the tables
local WINGED = { lepidoptera = 1 }
function M.vviolations(v)
  local out = {}
  local function check(ok, what) if not ok then out[#out + 1] = what end end
  local lep = WINGED[v.group]
  check(lep or (v.apex == "none" and v.border == "none" and v.tails == 0), "wing pattern on a visitor without scaled wings")
  check(v.kind == "butterfly" or v.tails == 0, "tails on a visitor other than a butterfly")
  check(v.kind ~= "butterfly" or v.antenna == "clubbed", "a butterfly without clubbed feelers")
  check(v.group ~= "lepidoptera" or v.kind == "butterfly" or v.antenna ~= "clubbed", "a moth with clubbed feelers")
  check(v.border == "eyes" or v.rings == 0, "eyespot rings without eyespots")
  check(v.kind ~= "ladybird" or v.pattern == "spots", "a ladybird without its spots")
  check(v.group == "beetle" or v.pattern == "none", "wing cases on a visitor that is no beetle")
  check((v.group == "snail") == (v.whorls > 0), "a shell on something not a snail, or a snail without one")
  check(v.group == "snail" or (v.aperture == 0 and v.sculpture == "none" and v.withdrawn == 0 and v.opencoil == 0),
    "a shell's mouth, sculpture or coil on something not a snail")
  check((v.sculpture == "ribs") == (v.ribs > 0), "ribs counted on a shell that is not ribbed, or a ribbed one without")
  check((v.group == "bird") == (v.bill ~= "none"), "a bill on something not a bird, or a bird without one")
  check(v.kind ~= "bird" or v.bill == "conical", "a perching seed-eater with a nectar bill")
  check(v.kind ~= "hummingbird" or v.bill ~= "conical", "a nectar bird with a seed-eater's bill")
  check(v.group ~= "odonate" or v.tint ~= "none", "a dragonfly or damselfly without its wings' tint")
  check(v.size > 0, "a visitor of no size")
  return out
end
-- a visitor in words, after "a" or "an": "butterfly with scalloped wings and a row of eyespots"
-- the ground in the words of the animal's own colors (the copper paints warm ones)
local GROUNDW = {
  lepidoptera = { ink = "blue ", pale = "white ", dark = "brown ", copper = "orange " },
  bee = { ink = "", dark = "dark ", copper = "golden " }, fly = { ink = "", copper = "yellow-banded " },
  odonate = { ink = "blue ", dark = "dark ", copper = "red " }, beetle = { ink = "blue ", dark = "black ", copper = "red " },
  larva = { ink = "", pale = "pale ", copper = "orange " }, snail = { ink = "", pale = "pale ", copper = "brown " },
  bird = { ink = "", dark = "dark ", copper = "russet " },
}
local KINDW = { butterfly = "butterfly", moth = "moth", hawkmoth = "hawkmoth", honeybee = "honeybee",
  bumblebee = "bumblebee", solitarybee = "solitary bee", hoverfly = "hoverfly", dragonfly = "dragonfly",
  damselfly = "damselfly", beetle = "beetle", ladybird = "ladybird", caterpillar = "caterpillar", snail = "snail",
  bird = "small bird", hummingbird = "nectar bird" }
function M.vdescribe(v)
  local k = v.kind
  local before, with, after = "", {}, ""
  local ground = GROUNDW[v.group][v.ground]
  if v.group == "lepidoptera" and k ~= "butterfly" and v.ground == "ink" then ground = "" end   -- a blue moth is rare
  if v.group == "lepidoptera" then
    if v.wingedge ~= "smooth" then with[#with + 1] = v.wingedge .. " wings" end
    if v.apex == "falcate" then with[#with + 1] = "hooked wingtips" end
    if v.tails > 0 then with[#with + 1] = v.tails == 1 and "a tail on each hind wing" or "thread tails" end
    if v.border == "eyes" then with[#with + 1] = "a row of eyespots"
    elseif v.border == "spots" then with[#with + 1] = "a row of spots along the edge" end
    if v.antenna == "feathery" then with[#with + 1] = "feathery feelers" end
    if v.pose == "closed" then after = ", resting with its wings closed"
    elseif v.pose == "tent" then after = ", resting with its wings folded like a tent"
    elseif v.pose == "hover" then before = "hovering " end
  elseif v.group == "bee" or v.group == "fly" then
    if v.pollen == 1 then with[#with + 1] = "pollen on its legs" end
    if v.paletail == 1 then with[#with + 1] = "a pale tail" end
    if v.pose == "hover" then after = ", hanging in the air" elseif v.pose == "fly" then after = ", in flight" end
  elseif v.group == "odonate" then
    if v.tint == "tinted" then with[#with + 1] = "tinted wings" end
    if v.pose == "folded" then after = ", its wings folded along its body" end
  elseif k == "ladybird" then
    ground = v.ground == "copper" and "red " or "black "
    if v.spots > 0 then with[#with + 1] = n_(v.spots) .. (v.ground == "copper" and " black spots" or " red spots")
    else ground = "plain " .. ground end
  elseif k == "beetle" then
    if v.pattern == "stripes" then with[#with + 1] = "striped wing cases"
    elseif v.pattern == "spots" then with[#with + 1] = "spotted wing cases" end
  elseif k == "caterpillar" then
    before = v.pose == "loop" and "looping " or v.pose == "curl" and "curled " or ""
    if v.stripes ~= "none" then with[#with + 1] = "stripes" end
    if v.tufts == 1 then with[#with + 1] = "tufts of hair" end
    if v.horn == 1 then with[#with + 1] = "a horn at its tail" end
  elseif k == "snail" then
    local adj = {}
    if v.spire >= 1 then adj[#adj + 1] = "high-spired" elseif v.spire <= 0.25 then adj[#adj + 1] = "flat" end
    if v.shellbands > 0 then adj[#adj + 1] = "banded" end
    if v.sculpture == "ribs" then adj[#adj + 1] = "ribbed" elseif v.sculpture == "cords" then adj[#adj + 1] = "corded" end
    local shell = v.opencoil == 1 and "open-coiled shell" or "shell"
    if #adj > 0 then shell = concat(adj, ", ") .. " " .. shell end
    with[#with + 1] = (shell:match("^[aeiou]") and "an " or "a ") .. shell
    if v.hand == "sinistral" then with[#with + 1] = "a coil to the left" end
    if v.withdrawn == 1 then after = ", withdrawn into it" end
  elseif v.group == "bird" then
    with[#with + 1] = v.bill == "conical" and "a short seed-eater's bill" or "a long thin bill"
    if v.crest == 1 then with[#with + 1] = "a crest" end
    if v.pose == "hover" then before = "hovering " end
  end
  local s = before .. ground .. KINDW[k]
  if #with == 1 then s = s .. " with " .. with[1]
  elseif #with > 1 then s = s .. " with " .. concat(with, ", ", 1, #with - 1) .. " and " .. with[#with] end
  return s .. after
end

-- ---------------------------------------------------------------- as TeX
-- the tables for tikzlibraryflorilegium.code.tex: one macro per plan that draws its
-- traits in M.TRAITS order, and one per role that draws a plan
local function key(v) return tostring(v) end
local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end
-- the TeX for a distribution; a BY map's entries become macros \flo@d@<name>@<value>,
-- appended to out; a visitor's (vtex) looks up the earlier trait among the visitor's
local vtex = false
local function tex_dist(d, name, out)
  local kind = d[1]
  if kind == "c" then return "\\flo@C{" .. key(d[2]) .. "}"
  elseif kind == "i" then return fmt("\\flo@I{%d}{%d}", d[2], d[3])
  elseif kind == "r" then return "\\flo@R{" .. key(d[2]) .. "}{" .. key(d[3] - d[2]) .. "}"
  elseif kind == "w" then
    local parts, total = {}, 0
    for i = 2, #d, 2 do total = total + d[i + 1] parts[#parts + 1] = "{" .. key(d[i]) .. "}{" .. total .. "}" end
    return "\\flo@W{" .. total .. "}{" .. concat(parts) .. "}"
  elseif kind == "by" then
    for _, k in ipairs(sorted_keys(d[3])) do
      local sub = name .. "@" .. k
      local code = tex_dist(d[3][k], sub, out)
      out[#out + 1] = "\\expandafter\\def\\csname flo@d@" .. sub .. "\\endcsname{" .. code .. "}"
    end
    return (vtex and "\\flo@VBY{" or "\\flo@BY{") .. d[2] .. "}{" .. name .. "}"
  end
  error("florilegium: unknown distribution " .. tostring(kind))
end
function M.tex()
  local out = {
    "%% tikzlibraryflorilegium.tables.code.tex -- generated by tools/tikztables.lua from",
    "%% florilegium-species.lua; do not edit. Copyright (c) 2026 Kevin Raymond. MIT License.",
    "\\def\\flo@traits{" .. concat(M.TRAITS, ",") .. "}",
  }
  local roles = { "hero", "spray", "monocot", "any" }
  for _, p in ipairs(M.PLANS) do if not M.ROLES[p.name] then roles[#roles + 1] = p.name end end
  for _, role in ipairs(roles) do
    out[#out + 1] = "\\expandafter\\def\\csname flo@role@" .. role .. "\\endcsname{"
      .. tex_dist(M.roleplans(role), "role", out) .. "}"
  end
  for _, p in ipairs(M.PLANS) do
    local body = {}
    for i = 2, #M.TRAITS do
      local t = M.TRAITS[i]
      body[#body + 1] = "\\flo@T{" .. t .. "}{" .. tex_dist(M.dist(p.name, t), p.name .. "@" .. t, out) .. "}"
    end
    out[#out + 1] = "\\expandafter\\def\\csname flo@plan@" .. p.name .. "\\endcsname{%\n  "
      .. concat(body, "%\n  ") .. "}"
  end
  -- the visitors: \flo@vrole@<role> draws a kind, \flo@vkind@<kind> its traits, into a
  -- namespace of their own (\flo@VT, \flo@VBY), since visitors and plants share trait names
  vtex = true
  out[#out + 1] = "\\def\\flo@vtraits{" .. concat(M.VTRAITS, ",") .. "}"
  local vroles = { "bee", "butterfly", "moth", "bird", "beetle", "fly", "leaf", "stem", "perch", "any" }
  for _, k in ipairs(M.VKINDS) do vroles[#vroles + 1] = k.name end
  for _, role in ipairs(vroles) do
    out[#out + 1] = "\\expandafter\\def\\csname flo@vrole@" .. role .. "\\endcsname{"
      .. tex_dist(M.vrolekinds(role), "vrole", out) .. "}"
  end
  for _, k in ipairs(M.VKINDS) do
    local body = {}
    for i = 2, #M.VTRAITS do
      local t = M.VTRAITS[i]
      body[#body + 1] = "\\flo@VT{" .. t .. "}{" .. tex_dist(M.vdist(k.name, t), "vis@" .. k.name .. "@" .. t, out) .. "}"
    end
    out[#out + 1] = "\\expandafter\\def\\csname flo@vkind@" .. k.name .. "\\endcsname{%\n  "
      .. concat(body, "%\n  ") .. "}"
  end
  vtex = false
  -- what a fixed trait may be (\florilegiumspecies[...], \florilegiumvisitor[...]): its
  -- names, the range of a number (empty if none), 1 if that number is real
  for _, vis in ipairs({ false, true }) do
    local vals = M.values(vis)
    for _, t in ipairs(vis and M.VTRAITS or M.TRAITS) do
      local ok = vals[t]
      if ok then
        local names = {}
        for name in pairs(ok.names) do names[#names + 1] = name end
        table.sort(names)
        out[#out + 1] = fmt("\\expandafter\\def\\csname flo@%sok@%s\\endcsname{{%s}{%s}{%s}{%d}}", vis and "v" or "", t,
          concat(names, ","), ok.lo and key(ok.lo) or "", ok.hi and key(ok.hi) or "", ok.real and 1 or 0)
      end
    end
  end
  return concat(out, "\n") .. "\n"
end

-- ---------------------------------------------------------------- the traits, as Markdown
-- docs/traits.md: every trait in the order it is drawn and what it may be fixed to
function M.traitsdoc()
  local out = {
    "# Traits",
    "",
    "The traits a species and a visitor are sampled with, in the order they are drawn, and what",
    "each may be fixed to: one of the names listed, or a number in the range given (a whole",
    "number where it says so). Fix them with `\\florilegiumspecies[...]`, `\\florilegiumvisitor[...]`",
    "or a pic's `traits` key; [the TikZ library](tikz.md#a-genome-of-your-own) shows how. `clade` and",
    "`group` follow from the plan and the kind and are not fixed themselves.",
    "",
    "This page is written by `tools/tikztables.lua` from `florilegium-species.lua`.",
  }
  for _, vis in ipairs({ false, true }) do
    local vals = M.values(vis)
    out[#out + 1] = ""
    out[#out + 1] = vis and "## A visitor" or "## A species"
    out[#out + 1] = ""
    out[#out + 1] = "| trait | what it may be |"
    out[#out + 1] = "|---|---|"
    for _, t in ipairs(vis and M.VTRAITS or M.TRAITS) do
      local ok = vals[t]
      if ok then
        local names = {}
        for name in pairs(ok.names) do names[#names + 1] = "`" .. name .. "`" end
        table.sort(names)
        local range = ok.lo and fmt("%s from %g to %g", ok.real and "a number" or "a whole number", ok.lo, ok.hi)
        local what = concat(names, ", ")
        if range then what = what ~= "" and what .. ", or " .. range or range end
        out[#out + 1] = fmt("| `%s` | %s |", t, what)
      end
    end
  end
  return concat(out, "\n") .. "\n"
end

return M
