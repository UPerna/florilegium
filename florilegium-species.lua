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
M.version = "1.3"                 -- the release; florilegium.lua checks that every file has the same

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
  attachment = W("petiolate", 7, "sessile", 2, "clasping", 1),
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
}
local PLAN = {}
for i, p in ipairs(M.PLANS) do PLAN[p.name] = p p.index = i end

-- a trait's distribution for a plan: the plan's own, else its clade's, else everyone's
function M.dist(plan, trait)
  local p = PLAN[plan]
  if trait == "clade" then return C(p.clade) end
  return p.d[trait] or (p.clade == "monocot" and MONOCOT or EUDICOT)[trait] or COMMON[trait]
end

-- the plans a role may draw, as a W over plan names (in M.PLANS order); a role may also
-- name one plan ("rose"), for a specimen of that plan
function M.roleplans(role)
  if PLAN[role] then return W(role, PLAN[role].w) end
  local t = {}
  for _, p in ipairs(M.PLANS) do
    if role == "any" or p.roles[role] then t[#t + 1] = p.name t[#t + 1] = p.w end
  end
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
function M.sample(seed, role, log)
  local rng = ink.pgfrng(seed)
  for _ = 1, M.WARM do rng.step() end
  local sp = { seed = seed, role = role or "any" }
  sp.plan = draw(M.roleplans(sp.role), rng, sp)
  if log then log("plan", sp.plan) end
  for i = 2, #M.TRAITS do
    local t = M.TRAITS[i]
    sp[t] = draw(M.dist(sp.plan, t), rng, sp)
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
  return v
end

-- ---------------------------------------------------------------- in words
local NUM = { "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
  "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen", "twenty", "twenty-one" }
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
  local c, n, f = COLOR[sp.color], sp.merosity, sp.form
  local parts = sp.clade == "monocot" and 2 * n or n     -- a monocot's parts come in two whorls of n
  if f == "head" then return a_(c) .. " daisy head of " .. n_(n) .. " rays"
  elseif f == "lily" then
    local shape = sp.reflex < -40 and "swept-back" or sp.cup > 0.6 and "trumpet" or sp.cup < 0.3 and "starry" or "cupped"
    local cor = sp.corona ~= "none" and (" around a " .. sp.corona) or ""
    return a_(c) .. " lily of " .. n_(2 * n) .. " " .. shape .. " tepals" .. cor
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

-- one sentence: what it looks like, how it flowers, who it is for, its leaves, its fruit
function M.describe(sp)
  local s = flower_words(sp) .. " " .. INFLO[sp.inflo] .. ", " .. FOR[sp.syndrome] .. "; "
    .. leaf_words(sp) .. (sp.tendrils == 1 and ", climbing by tendrils" or "") .. "; then " .. FRUIT[sp.fruit] .. "."
  return s:sub(1, 1):upper() .. s:sub(2)
end

-- ---------------------------------------------------------------- a document's plants
-- a pool of eight species for a document (docseed: \florilegiumseed, or 0), each with a
-- role, no body plan twice; ink.rng streams, Lua only (TikZ draws species by seed)
local SLOTS = { "hero", "hero", "spray", "spray", "monocot", "any", "any", "any" }
local pools = {}
function M.pool(docseed)
  docseed = docseed or 0
  if pools[docseed] then return pools[docseed] end
  local rng = ink.rng(docseed * 104729 + 307)
  local pool, used = {}, {}
  for i, role in ipairs(SLOTS) do
    local sp
    repeat sp = M.sample(1 + floor(rng.u() * 2147483645), role) until not used[sp.plan]
    used[sp.plan] = true
    sp.slot = i
    pool[i] = sp
  end
  pools[docseed] = pool
  return pool
end

-- the four that grow on one page (rng: the page's species stream): a hero, a spray,
-- the monocot, and one more; in that order (main stems 1, 2, 3, then the footer)
function M.community(pool, rng)
  local hero = pool[1 + floor(rng.u() * 2)]
  local spray = pool[3 + floor(rng.u() * 2)]
  local mono = pool[5]
  local rest = {}
  for _, sp in ipairs(pool) do if sp ~= hero and sp ~= spray and sp ~= mono then rest[#rest + 1] = sp end end
  local extra = rest[1 + floor(rng.u() * #rest)]
  return { hero, spray, mono, extra }
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
-- appended to out
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
    return "\\flo@BY{" .. d[2] .. "}{" .. name .. "}"
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
  for _, p in ipairs(M.PLANS) do roles[#roles + 1] = p.name end
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
  return concat(out, "\n") .. "\n"
end

return M
