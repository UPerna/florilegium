# florilegium — handoff notes

Procedurally generated Delft-blue floral page margins for LuaLaTeX. All geometry is
computed in Lua and written as raw PDF path operators; TeX does no arithmetic. Two
documents share one package: an **authored** composition (hand-placed stems, leaves and
branch targets, parameters sampled) and a **grown** one (layout computed by a greedy
space-filling loop). Same primitives, same motif table. No images, no assets. The grown
margin also reads the text (flowers at headings and marked lines, seasons over the
document), pages get visitors, and paragraphs can open with a decorated initial;
`showcase.tex` demonstrates all of it. A theme swaps primitives by name
(`florilegium-theme-geometric.lua`: the same plant cut from flat, straight-edged shapes) or replaces
the whole composition (`florilegium-theme-math.lua`: figures, TeX symbols and equations cascading down
the margin and along the bottom, from `florilegium-figures.lua`); `density` (down to a single vine at
0.05) and `intensity` turn any margin down; `\florilegiumornament` sets one primitive in the text (issue #4). The garden grows in
the wider side margin, mirrored when that is the right one (two-sided documents);
`spread.tex` shows that and a theme. `florilegium-svg.lua` draws the same page without TeX, as SVG (byte for
byte the same drawing as LuaLaTeX's), and `web/` runs it in the browser: the playground,
published to GitHub Pages.

## Files

| file | what |
|---|---|
| `florilegium.sty` | thin TeX layer: options `authored` (default) / `grown`, `nomargin`, `novisitors`, `sections`, `aging`, `species` (`florilegium.use_species()`: loads and checks the species modules), and key=value `theme=<name>`, `density=<0..1>`, `intensity=<0..1>` (via `\DeclareOption*` and `\florilegium@set@<key>`); colors `ink` and `accent`; `\florilegiumdraw`, `\florilegiumtextend`, `\florilegiumbloom`, `\florilegiumage`, `\florilegiumtheme`, `\florilegiumornament` (pgfkeys `size ink accent angle seed`), `\florilegiuminitial`, `\florilegiuminitialfont`, `\florilegiumframe`; `\if@twoside` to Lua at each shipout; the shipout hook. LuaLaTeX only. |
| `florilegium.lua` | glue: page geometry from TeX dimens (odd/even side margin, mirror when the right margin is wider), colors, page seed, the TikZ transform (`\pgf@pt@aa..bb`, `\pgf@pt@x/y`), primitive dispatch (through the current theme), inline ornaments (`ORNAMENT` placement table), captions a composition returns (TikZ `\node`s, mirrored x mapped back), density/intensity (`ink.set_pale` around the margin), the header; `M.species` and `M.docseed` (set by `M.seed`: `\florilegiumseed` or 0) into `g.species`/`g.docseed`, also in the animation's cache key; text marks (whatsits) and the walk of `\ShipoutBox` that finds them (headings, blooms, theme changes); age; animation frames; the initial's placement and its invisible letter. |
| `florilegium-ink.lua` | drawing core: mulberry32 rng, 1-D gradient noise/fbm, OKLCH tone ramp, affine transform stack (`page_transform(mirror)` = layout cm → page bp, reflected for a right margin), `set_pale` (option intensity: tones and accents toward white, detail unchanged), path building (`smooth` = Catmull-Rom as Béziers, `taper`, `ribbon`, `blade`, `blob`), fill/stroke/clip with ExtGState opacity + multiply, numbered layers, `flush()` into one `pdf_literal` node. |
| `florilegium-flora.lua` | the primitives: `petal flower lily blossom floret bud bell leaf leaflet stem cyme sprig umbel seedhead tendril sparkle rosette hedera ghost`, the visitors `butterfly bee snail bird`, plus `branch_path`. |
| `florilegium-grow.lua` | grown composition: regions, grid, stems, marks, visitors on the stems, leaves at nodes, branch loop, falling petals, filler, footer tail; seasons; animation events. Also exports the **motif table** (`M.motifs`) and layer numbers used by `florilegium-authored.lua`, `M.regions(g, layout)` and `M.field(rects)` (the free-space grid, shared with theme-math), and `M.theme(name)`, which sets the primitives (`F`), motif rows and optional composition of the current theme. Species (`g.species`, no theme): `comm` = `species.community(pool(docseed), ink.rng(seed*7919+307))`, plant k on main stem k (hero, showy, monocot), the spray on the footer, spill arcs from the stems in turn; stem points carry their plant (`S[6]`); `species_rows(sp, i, sea)` (`unit` hard, `bloom` for a hero whose cluster is not one flower, `spray` (smaller, later), `budding`, `leaf` for eudicots, `tendril` for climbers; caps shared per kind across the page through `group` = `g:<kind>` and `M.GROUPS`, `limit` 1 for a copper (red/orange) plant; airy rows `claim` 0.65 of their disc so neighbors grow into their gaps); tops (`top()`: the hero's terminal flower, open; units elsewhere), ghosts, node leaves (`species_leaves`: arrangement, rosette, a monocot's straps), marks (`species_mark`), the filler's bud; organs drawn through `florilegium-organs.lua: draw`. |
| `florilegium-theme-geometric.lua` | the geometric theme: the grown plant with every primitive redrawn flat and straight-edged (`stem`: straight runs ~L/4 apart with mitered corners; `leaf`: kite or toothed polygon in a light and a dark facet, straight white veins; `flower`: rhombus rosette or layered star polygons; `lily bud bell blossom floret cyme sprig umbel tendril`(square spiral) `rosette hedera butterfly bee snail bird`), flat tones only; `motifs()` puts blossoms/budding/bells on straight stalks and adds a `crystal` row (flat-shaded Platonic solid). |
| `florilegium-figures.lua` | the math figures: `figures` (14: `maurer hypotrochoid lissajous polyhedron knot gasket koch hilbert chords golden parabola petersen vogel fay`, each `pick(layout)` / `draw(rng, R, p)` / `caption(p)`), `families` (13 progressions: `values`, `label`, `title`, `pick`, `draw(rng, R, v, p)`), helpers `maurer phyllotaxis fay vogel hull_of` (faces from nearest-neighbor triples: uniform solids only) `truncate solid compass caption_width`. |
| `florilegium-theme-math.lua` | the math theme, a composition of its own (`page(g, grow)`): regions = column, a footer band to 72% of the text width, spill; 1. a large corner figure, 2. one or two families down the column, each figure larger than the last, copper arrows, 3. equations (TeX, `EQUATIONS`, base LaTeX only) along the footer and in rows under the text, 4. largest hole first: figure / TeX glyph (`GLYPHS`, scaled, tilted, colored) / dot, proxies at k 0.5–0.62 so things overlap; a size gradient toward the corner. `density` scales the count. |
| `florilegium-species.lua` | species (in progress, plan: board #4997): a plant sampled from a genome. `TRAITS` (the fixed draw order), `COMMON`/`EUDICOT`/`MONOCOT` defaults and 14 `PLANS` (body plans: lily iris rose mustard pea mint daisy umbellifer heath borage catkin columbine, generic eudicot/monocot) with distributions `W` (integer weights) `I` `R` (reals, as pgfmath computes `\flo@R`: exact multiples of 2^-16) `C` `BY(trait, map)`; `sample(seed, role, log)` with `ink.pgfrng` and `WARM = 2` discarded draws, returns the species and the generator (where `\florilegiumspecies` leaves pgf's); `violations`, `describe` (one sentence), `pool(docseed)` (8 species, roles hero/spray/monocot/any, no plan twice, both heroes `showy`; a role's name wins over the plan of that name, `M.ROLES`), `showy(sp)` (single flowers or loose clusters painted in the ink, not racemes, spikes, catkins, compound umbels or red/orange), `community(pool, rng)` (4 per page: hero, a second showy plant, the monocot, a spray); `tex()` writes the TikZ tables. |
| `tikzlibraryflorilegium.code.tex`, `tikzlibraryflorilegium.tables.code.tex` | the same species in pure TikZ (`\usetikzlibrary{florilegium}`, pdfLaTeX or LuaLaTeX): `\florilegiumspecies{seed}{role}` (role: hero spray monocot any, or a plan name), `\florilegiumtrait{name}`; draw macros `\flo@W \flo@I \flo@R \flo@C \flo@BY \flo@T`. Drawing (M1): v1.3's hand, ported line for line from `florilegium-flora.lua` and `-ink.lua` to pgfmath (pgf basic layer only, one draw per `\flo@rnd/range/sym/int/chance` line so Lua can mirror the order; only the random numbers differ from flora): `\flo@vpetal` (fbm-noise edge, heart blobs, mottle and specks, brush strokes, pooled rim, white streaks, veins), `\flo@vheart`, `\flo@vflower`, `\flo@vlily`, `\flo@vblossom`, `\flo@vfloret`, `\flo@vbud`, `\flo@vleaf` (lobes, teeth, darker half, veins), `\flo@vleaflet`, `\flo@vstrap` (a monocot's parallel-veined leaf in flora's manner), helpers `\flo@vtaper` (ink.taper), `\flo@vblob`, `\flo@vmottle`, `\flo@vstreak` (ink.ribbon), `\flo@vfbm/\flo@vwave` (ink.fbm1). Colors: ink's OKLCH ramp computed in TeX from the document's `ink` and `accent` (`\flo@ramp`, with pgf's `fpu` and Newton cube roots: within 0.0002 of ink.lua's), `\flo@vtone`. The species steer flora's knobs (`\flo@stone` color to tone or the accent ramp, `\flo@sflower` petal count, round or pointed, width, streaks; floret under 8 pt, blossom under 22 pt; `\flo@sdaisy` rays around a Vogel disk; `\flo@leaf` lobes and depth from the margin, strap leaves, leaflets on a rachis). Plants in v1.3's manner (M1b), in centimeters as `florilegium-grow.lua` lays out the margin: `\flo@vstem` (flora.stem: ribbon, or a stroke under 0.7 bp), `\flo@branchpath` (flora.branch_path) and `\flo@cubicstem`, `\flo@umbelunit` (flora.umbel), `\flo@racemeunit` (flora's cyme bent less, the species' flowers on pedicels, lowest oldest), `\flo@blossoms`/`\flo@budding` (v1.3's motif rows), `\flo@vtendril`, `\flo@bloom` (bud, open, past its best above 1: paler and smaller, fruit by stage), seen as `\flo@bview` decides from form and orient (M5b): `face` (erect), `tilt` (horizontal: squashed 0.5-0.7), `back` (nodding: squashed, paler, `\flo@vcalyx` on top), `lily` (flora's lily, turned), `tube` (campanulate, urceolate, tubular, funnelform: `\flo@vtube`, flora's bell generalized by a profile `\flo@turad`, bent, a shaded side, a noise edge above 0.45 cm, exserted stamens, sepals) or `salver` (`\flo@vsalver`: a slender tube, the face tilted on top); held sideways it turns 50-80 degrees, nodding 100-140, toward `\flo@bside` (1 left, -1 right; clusters set it from their stalk's side, empty draws one); a ghost lift in `\flo@vtone`. Clusters (M5a), one per inflorescence, each in its opening order: `\flo@curlunit` (flora's cyme: the coiled cyme, flowers outside the coil or alternating by `siderule`, a forked second curl), `\flo@forkunit` (flora's sprig: the dichasium, a flower in every fork), `\flo@panicleunit`, `\flo@thyrseunit`, `\flo@corymbunit`, `\flo@spikeunit`, `\flo@umbelsunit` (the simple umbel), `\flo@headunit`, `\flo@catkinunit` (hanging tassels, fruit in autumn); helpers `\flo@axis`/`\flo@axisat` (racemeunit's axis), `\flo@walk`, `\flo@hair`; a cluster collects its flowers (`\flo@fadd`) and draws them after its stalks (`\flo@fdraw`, `\flo@fat`: a dot below stage -0.25), in named lists `\flo@zset{name}{i}{value}`/`\flo@z`. A unit captures its length argument at entry (`\edef\flo@clL{#1}`): it arrives as `\flo@L`, which a loop may reassign. `\flo@i \flo@j \flo@n \flo@m \flo@p \flo@q` are count registers: never `\flo@calc` into them. A garden (`\flo@garden`) is walked once per layer (ghost, stems, leaves, airy, blooms), each walk in passes like the growth: stems and the inflorescence at each top, leaves at nodes, branches from the nodes, three fill rounds; a 5 mm room grid per walk (`\flo@room`, `\flo@takenat`) keeps leaves and branches where there is room. Every organ draws from its own stream (`\flo@seedorgan`, `\flo@organ`: half pgf's cycle from the layout's state, which is restored), so the layout never depends on what an organ draws. Pass sizes to organ macros in a macro they do not use (`\flo@oarg`), never `\flo@t`: `\flo@sflower`, `\flo@leaf`, `\flo@vbud` and others redraw `\flo@t` before reading their argument. Pics `florilegium flower`, `florilegium leaf` (keys `seed role size draw`), `florilegium plant` (one plant, size its height, `season`), `florilegium plants` (`plants={seed/role,...}`, `size`, `width`, `ghost`: plants from one root like a margin's main stems), `florilegium inflorescence` (keys `seed role scale season`: the species' cluster as the margin draws it at scale 1, the oldest flower's stage 1.2 times the season), test pics `florilegium v13 flower`, `florilegium v13 leaf`. Key `engine` (per pic or `\pgfkeys{/florilegium/engine=...}`): `auto` (the default) is `lua` under LuaLaTeX when `florilegium-organs.lua` can be found (`\flo@autoengine`, resolved once at load) and `tikz` otherwise; `lua` under pdfLaTeX warns once and draws in pure TikZ. With `lua`, `\flo@engine` hands the pic to `\flo@luapic`, which calls `florilegium-organs.lua` (`M.tex`) and draws the pgf commands it writes, the same as the TikZ code's, byte for byte in the PDF. About 4 s per large flower in pure TikZ, about 2 min per 21 cm strip of three plants; under pdfLaTeX a strip needs about 7 million words of main memory (`extra_mem_top=10000000`). The tables file is generated (`texlua tools/tikztables.lua`); never edit it. |
| `florilegium-pgfmath.lua` | pgfmath replayed exactly on integers (sp): TeX's `round_decimals` (`M.sp`) and `print_scaled` (`M.str`), a factor times a dimen (`mulf`, `xn_over_d`), `\divide` (`divn`), pgf's `divide` (long division in decimal text, `\pgfmathdivide@advance@last@digit` included), `reciprocal`, digit `sqrt`, `ln`/`exp`/`pow` polynomials, `sin`/`cos`/`atan` from pgf's tables (embedded as differences) with interpolation, `atan2`, `veclen`, `mod floor round int min max`, comparisons, `rnd`/`rand` from `M.rng`. `M.compile(expr)`: the library's expressions in pgfmath's precedences (unary minus at 500, so `-a*b` is `-(a*b)`) over `@name` (macro, sp), `#name` (count), `$name` (trait), `%1` (argument); one variant per sign pattern of the variables, because TeX expands a negative macro to `-digits` and the minus then takes in the products after it (`0.03*\flo@w*(\flo@v)` with `\flo@w<0` is `0.03*(-(|w|*v))`). |
| `florilegium-organs.lua` | the hybrid (M2): `tikzlibraryflorilegium.code.tex` transcribed macro for macro, writing the pgf code the library runs (`M.pic(kind, o)` → strings, `M.tex(...)` → `tex.sprint`). TeX's semantics where the drawing depends on them: one store `R` for macros (`V.xa` = `\flo@xa`), count registers (`V["#kb"]`) and traits (`V["v@size"]`), written through `V`/`setv` so a group (`scope`, a pgfscope) undoes them; helpers assign the same temporaries as their macros (a later line may read one); arguments TeX expands late are passed as names and read at use (`vmottle`'s x range, `bipinnate` → `pinnate("t", ...)`); loop bounds are read on every pass (`loop`); shared count registers stay shared (the fill rounds' `\flo@Gb` is moved by `\flo@branchto`'s leaflet loop, as in TeX). A garden is walked five times, one layer each, as `\flo@garden` walks it. A strip of three plants: 1.3 s in Lua, ~10 s in LuaLaTeX with the drawing. The margin (M3): `M.organ(kind, sp, z, o)` (`unit bloom budding tendril leaf ghost`, at the origin along +y, in cm) returns the pgf code, `M.draw` paints it with ink through `paint()` (reads the code back: scopes, transforms, `\colorlet` of `flo@ramp@N` / `flo@aramp@N` / `flo@accent!N!white|black` as `ink.tone`/`in_accent`/`ink.accent`, fill/stroke/clip, circle, ellipse, rectangle; errors on anything else); with `M.keep` (animation) each organ's code is computed once per page (`M.forget`). `M.unitdisc(sp, k)` and `M.lateness(sp, h)` give the layout an inflorescence's disc and stage offset. The main chunk is at Lua's 200 locals: the clusters sit in a `do` block exported through `CL` (`CL.curl`, `CL.fork` ...), the views in one exported through `VW` (`VW.bview`, `VW.vtube` ...), and new helpers belong in a block or a table (`T.Z` holds `\flo@Z<name>@<i>`). |
| `specimen-tikz.tex` | the species in TikZ (A4, two pages): two strips of three plants from one root, the body plans' flowers and leaves close up, one rose through the seasons. Under pdflatex pure TikZ, the proof (~6 min, 10.9M words of main memory); under lualatex the hybrid by the library's default (~20 s; `\pgfkeys{/florilegium/engine=tikz}` for pure TikZ, ~6.5 min); CI builds it with both (pdflatex: `pre_compile: export extra_mem_top=10000000`). |
| `florilegium-authored.lua` | authored composition: the hand-placed "score" (STEMS, LEAVES, BRANCHES, GHOSTS, VISITORS, SNAIL, ACCENTS, FOOT) for A4 with a 68 mm left margin. |
| `florilegium-initial.lua` | decorated initials: glyph outline via `fonts.handlers.otf.readers.loadshapes`, even-odd inside test, clearance grid, the vine over/under the letter, leaflets, flowers in the gaps, tile frame. |
| `florilegium-svg.lua` | a page as SVG without TeX (any Lua 5.3/5.4): `M.page(o)` stubs `tex` (`dimen`, `count`, `hoffset`), `node`, `luatexbase`, `texio` around `florilegium.grown`/`authored` and restores them, so `florilegium.geometry()` itself lays the page out; `M.sp` scans a length as TeX does, `html` converts a color as xcolor does (`\rdivide`, then `print_scaled`); `M.translate` turns ink's PDF operators into SVG (clip groups, opacity, multiply). Returns `svg, g, { streams, captions, stats }` (captions: the math theme's TeX, placed and mirrored as `florilegium.lua`'s `captions()` places it, from `florilegium.last_captions`; stats: what grew, from `florilegium.last_stats`, which `grow.page` returns as `{ stats = { motifs, counts, stems, cells, species } }`, species: `{ role, plan, clade, syndrome, seed, text, tally, grew }` per plant, `grew` false for a plant whose stem low density left out). `--species` (`o.species`, set on every call, since wasmoon keeps module state). CLI: `texlua florilegium-svg.lua --help`. |
| `web/`, `.github/workflows/pages.yml` | the playground, "a proof and its colophon": `index.html` (the proof sheet with crop marks and the measured margin, the colophon slip, styles), `app.js` (state in the URL hash; the colophon sentence built from the state, each copper word a chooser, and the garden's alt text; the knob on the measure and the foot of the text as drag/arrow-key controls; page text written from `stats`; option species as a sentence term like the visitors' (flora only: `hasSpecies`/`isSpecies`; geometric and math hide it, and it reaches `options()` and the snippets only through `isSpecies()`), its page text from `stats.species` (each grown plant's `describe` text, the `g:*` group counts in `NAMES`); the page text and the colophon's visitor clause use a garden's stats only while `grownKey()` (the options that change what grows, kept as `sentKey` with each request) still matches, so they never describe the last garden while the next grows; the `#sprout` flower (in the page's ink and accent, centered in the margin by `--sx`) shows while `.proof.growing`, after 150 ms; the folio shows on last pages too, as LaTeX prints it; the garden `img` has `will-change: transform`, its own layer, because redrawing its SVG under the moving text made the knob lag (raster 767 ms over a 30-move drag, 38 ms with the layer); "seen by" filters and the measurements table, Machado 2009 + Oklab, `WEAK` 0.10; snippets), `worker.js` (wasmoon 1.16.0 from jsDelivr, fetched with `integrity` and run from a blob: URL, mounts `MODULES` (with species, pgfmath and organs), calls `svg.page`, `setTop(0)` after each call; a species page takes 3.5–5.5 s there, a classic one ~0.5 s), `captions.js` (MathJax 3.2.2 with SRI, `tex2svg` with `fontCache: 'none'`, set at TikZ's anchor, size in pt, rotation, color, opacity, then spliced into the SVG), `fonts/` (WOFF2 subsets, licenses, README), `hedera.svg` and `sparkle.svg` (drawn by `tools/ornament.lua`). `pages.yml` runs `tools/svgcheck.sh lua5.4` and `tools/sri.sh`, then publishes `web/` + `*.lua` on pushes to main that touch them. |
| `tools/playcheck/` | `check.mjs` (puppeteer-core): operates every control of the playground and checks the garden, geometry, colophon, URL and snippets, and that the page fetches nothing from another origin but the files pinned in `web/*.js` (65 checks, ~3 min); writes two all-settings-changed pages (`combined.*`, geometric; `combined-species.*`) and their CLI/LaTeX snippets for a `cmp` / PDF check. |
| `florilegium.tex` / `florilegium-grow.tex` | demo documents (authored / grown). Body text = `text-methods.tex` (+ `text-growth.tex` for grown) + `text-sharing.tex`; it describes the code, so **update it when the method changes**. |
| `showcase.tex` | "A year in the margin": `[grown,sections,aging]`, an initial, `\florilegiumbloom`; each section describes the feature it shows. Two passes. |
| `spread.tex` | "Two sides, two gardens": `twoside`, wide outer margin, `[grown,sections]`; page 3 switches to `\florilegiumtheme{geometric}` after a `\newpage`. `make preview` puts pages 2–3 side by side in `gallery/spread.png`. Its text describes the mirror and the themes; keep page 2 full (the `\newpage`) and page 3 short enough to spill. |
| `specimen.tex` / `specimen-geometric.tex` | one of every primitive, flora / geometric theme (`gallery/specimen-geometric.png`). |
| `ornaments.tex` | `\florilegiumornament` demo (`gallery/ornaments.png`). |
| `gallery.tex`, `tools/gallery.py` | one short page per variant (`\galleryink`, `\galleryage`, `\gallerytheme`) → `gallery/seeds.png` + `seeds.gif`, `inks.png`, `seasons.png`, `themes.png`, `dials.png` (`--options density=0.4,...`, via `\PassOptionsToPackage`). |
| `animation.tex`, `tools/animate.py` | growth animation: one page per frame (`\florilegiumframe`), parallel LuaLaTeX jobs, pdftoppm, ffmpeg → `build/grow-N.gif` + `.mp4`. `tools/animcheck.lua` checks that the last frame equals the page. |
| `tools/Dockerfile`, `tools/in-docker` | TeX Live 2023 image (Ubuntu 24.04, pinned by digest for Scorecard; Dependabot leaves it alone); `make RUN=tools/in-docker` when there's no local TeX. |
| `postscript/florilegium.ps` | the PostScript port: ink + flora + grow (no animation, initials, themes, mirror, density/intensity, ornaments or authored page) and a two-page text that describes itself, with heading marks and the spill. One file, run by Ghostscript (`make postscript`, local `gs`, not the Docker image) or a printer. Not kept in sync automatically: a change to a primitive or to `florilegium-grow.lua` has to be made there too. |
| `.github/`, `.gitattributes` | `workflows/build.yml` (jobs `lua` = `tools/versioncheck.sh` (with the tag on a `v*` tag) then `tools/svgcheck.sh lua5.3 lua5.4`, and `pdfs` = the four documents plus `specimen`, `specimen-geometric` and `ornaments`, which check pgf's internal transform macros, on every PR and push, uploading the four; `release` on a `v*` tag push: attestation + draft release with the PDFs and the attestation as `florilegium-pdfs.sigstore.json`, which Scorecard counts as a signature; `gallery` on dispatch), `pages.yml`, `scorecard.yml` (OpenSSF, weekly; must stay shaped like Scorecard's example), `dependabot.yml` (one grouped PR a month, 7-day cooldown), issue forms, PR template. `.gitattributes` leaves `process/` and `gallery/` out of GitHub's "Source code" downloads (`export-ignore`; 33 MB down to 0.5 MB); `tools/` stays, since README's Docker build needs it. |
| `tools/svgcheck.sh`, `tools/sri.sh`, `tools/versioncheck.sh` | `svgcheck.sh [lua...]`: 8 varied pages (one a mirrored species page in autumn) through `florilegium-svg.lua` under each interpreter given, byte-identical across them (default `lua5.3 lua5.4`). `sri.sh`: fetches each `['https://…', 'sha384-…']` pin in `web/*.js` and checks its hash. `versioncheck.sh [tag]`: the `.sty`'s v-number and every `M.version` agree, and with a tag that they are its version. |
| `tools/speciescheck.lua`, `tools/tikzcheck.lua` + `.tex`, `tools/tikzpools.lua`, `tools/tikztables.lua` | `speciescheck.lua [N]`: N sampled species keep every rule, plan/trait histograms, the TikZ tables are current (CI, lua5.3 + lua5.4); `--pools K`, `--log a b`. `tikzcheck.lua [a b [engine]]`: TikZ and Lua find the same species for seeds a..b (choices and reals exact); `tikzcheck.lua draw [quick|full]`: builds `tools/tikzcheck-draw.tex` with `engine=tikz` and `engine=lua`, uncompressed, and compares each page's content stream (quick: a flower, a leaf and an inflorescence of every plan, an inflorescence of every kind (some also in bud and fruit) and of every view, the v1.3 pics, a plant in three seasons, 74 pics, ~4 min; full: also two strips, ~10 min); expected identical, fails beyond 0.05 bp or on any operator. `tools/pgfmathcheck.lua [N [seed [engine]]]` + `.tex`: N random expressions (a third with variables, values substituted as TeX substitutes macros) evaluated by pgfmath and by `florilegium-pgfmath.lua`, exactly equal. CI runs pgfmathcheck, tikzcheck and `tikzcheck draw quick` (pdfs job, `post_compile`). `tikzpools.lua [K]`: K documents' pools drawn by TikZ, in words, `build/pools.md`. `tikztables.lua`: writes the TikZ tables. |
| `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `CITATION.cff` | the security policy (private reporting; what the package promises not to do; `gh attestation verify`), the contributor guide, Contributor Covenant 2.1 (reports through the private reporting form), citation metadata (no version, so it can't go stale). |
| `PROCESS.md`, `process/` | the user's write-up of how the repo was made: `process/claude-ai.md` (the Claude.ai chat; the files it attached are in `process/claude-ai/`, and `response-final/florilegium-repo.zip` is the original repo) and `process/claude-code.md` (the first Claude Code session, up to v1.0). Historical: never update them along with the code. |

## Build

```sh
docker build -t florilegium-tex tools     # once, if there is no local TeX
make RUN=tools/in-docker                  # the four PDFs (showcase: two passes for aging)
make preview RUN=tools/in-docker          # + ornaments.pdf, specimen-geometric.pdf, build/{geometric,math}.pdf -> gallery/*.png
make seed-7 RUN=tools/in-docker           # one page for seed 7 -> build/seed-7.pdf
make gallery RUN=tools/in-docker          # seeds, inks and seasons sheets (~40 s)
make grow-6 RUN=tools/in-docker [EXPLAIN=1]            # ~45 s: build/grow-6.gif + .mp4
make animation RUN=tools/in-docker                     # both, copied to gallery/growth*.gif
tools/in-docker texlua tools/animcheck.lua 1 2 3       # last frame == page, byte for byte (also geometric, mirrored, density 0.4/0.05, math, species; ~5 min for 4 seeds)
tools/in-docker texlua tools/ident.lua build/ident-a    # 45 content streams, to diff -r before/after a change
make preview                              # gallery/preview-*.png, spread.png, specimen-geometric.png, geometric.png, math.png
make postscript [SEED=7]                  # the PostScript port via local gs -> build/postscript-7.pdf + gallery/preview-postscript.png
make pscheck                              # postscript/check.sh: ~40 gs runs vs postscript/expected.txt, options, clock (~10 s); --record after an intended change
make svg [SEED=7] RUN=tools/in-docker     # build/svg-7.svg: the drawing on page 1 of florilegium-grow.tex, without TeX
lualatex "\PassOptionsToPackage{species}{florilegium}\def\florilegiumseed{7}\input{florilegium-grow.tex}"   # species pages (~4 s each)
texlua florilegium-svg.lua --seed 7 --species -o build/species-7.svg   # the same page 1, without TeX
make playground                           # web/ at http://localhost:8000/web/ (the Lua is fetched from ../)
cd tools/playcheck && npm install && node check.mjs http://localhost:8000/web/ ../../build   # every control, 65 checks
tools/svgcheck.sh texlua                  # 8 pages through florilegium-svg.lua; with several interpreters, byte-identical across them (CI: lua5.3 lua5.4)
tools/sri.sh                              # the CDN files still hash to what web/*.js pins
tools/in-docker texlua tools/pgfmathcheck.lua 30000   # pgfmath replayed exactly (lualatex; add pdflatex as 3rd arg)
tools/in-docker texlua tools/tikzcheck.lua 1 1000     # TikZ and Lua sample the same species
tools/in-docker texlua tools/tikzcheck.lua draw quick # the hybrid's PDF streams equal pure TikZ's (~3 min; full ~10 min)
tools/versioncheck.sh [v1.3]              # the .sty and every Lua file name one release (and the tag's)
```

Fixed seed: `lualatex "\def\florilegiumseed{7}\input{florilegium-grow.tex}"`. Any
positive integer works.

Look at output with `pdftoppm -png -r 100 file.pdf page` and read the PNG; for fine detail
use `-r 300` with `-x -y -W -H` crops. Always look before declaring a change good. For a
quick sheet of every primitive, `scratch/` (git-ignored) is the place for test documents.

Bytes per primitive: `tools/in-docker texlua tools/bytes.lua` (stubs out TeX). A flower
is ~70 KB of path operators, a page ~3 MB uncompressed, ~0.7 MB in the PDF.

## Conventions and traps

- **US spelling everywhere** (color, center, gray, meter) — code, comments, docs.
- **Module names.** Every Lua module but `florilegium.lua` is `florilegium-<part>.lua`, required
  by that name, and a new module or theme gets the prefix too. TeX finds a file by its bare name,
  the document's folder first, so a generic name loses to a user's own file (a `figures.lua`
  beside the document once crashed `theme=geometric`), and `require` keeps one module per name
  for the whole run. The files stay flat in the root: LuaTeX looks for `.lua` in `LUAINPUTS`,
  not `TEXINPUTS`, so a subfolder would need both set wherever LuaLaTeX runs. A theme still
  named `theme-<name>.lua` loads with a warning (`florilegium-grow.lua: load_theme`).
- **Versions.** Each of those files carries `M.version` (the release), and `florilegium.lua`
  checks at load that every part in `PARTS` and the `.sty`'s `\ProvidesPackage` v-number agree,
  because each file is found on its own and two releases can meet (an old set in `~/texmf`, a
  newer `.sty` beside the document). It preloads every part but `initial` (checked with the
  first initial) and `svg` (which loads `florilegium.lua`, so it is checked then). A new module
  goes into `PARTS` and the preload with an `M.version` line; a user's own theme needs neither.
  The `.sty` itself catches a `florilegium.lua` with no version. Keep `%`, `#` and `~` out of
  Lua written inside `\directlua` in the `.sty` (TeX's comment, parameter and active characters).
- **Credits and licenses.** Every file a user copies (`florilegium.sty`, the ten `.lua`,
  `postscript/florilegium.ps`) carries the copyright line; the `.sty` and the `.ps` (which
  travels alone) carry the full MIT text. A borrowed algorithm or published constant gets a
  credit where it is used and a line under README's Credits (Ottosson's Oklab, Ettinger's
  mulberry32, Wong et al.). Trademarks stay out of user-facing names (`hypotrochoid`, not
  Spirograph); data with a license of its own stays out of the package (MSC2020 is
  CC BY-NC-SA: bare codes only). Code that reproduces pgf (`florilegium-pgfmath.lua`, ink's
  `pgfrng`, the library's patch of pgf's number parser) keeps its LPPL notice: not part of
  pgf, how it differs, no support from pgf's authors, where unmodified pgf is (LPPL 1.3c
  clauses 6 and 10, which let it stay MIT).
- **Raw literals bypass TikZ transforms.** A primitive called inside a TikZ scope must
  read pgf's matrix itself (`florilegium.lua: sync_transform`). Inside the margin picture
  the transform is just cm→bp from the page's lower-left corner.
- **Lua truncates multiple returns** in the middle of a table constructor:
  `{x0, y0, f(t), x1}` keeps only the first value of `f(t)`. Assign to locals first.
- **Line widths are absolute bp** (we transform points in Lua, not with `cm`). Anything
  that should scale with a motif is a filled shape (`taper`, `ribbon`); `flora.stem`
  switches to a stroke below ~0.7 bp.
- **Opacity/blend** need ExtGState resources: `florilegium-ink.lua: gs()` registers `/floaNN` and
  `/flomNN` (multiply) through `\pgfutil@addpdfresource@extgs` once per document.
- **Size budget.** Output, not time, is the constraint. Coordinates are printed `%.1f` bp;
  a path used for fill and clip is emitted once (`clip()` then `flood()`); streaks are
  `taper` (2 Béziers); florets below 0.7 mm are a 10-point polygon. Measure before adding
  per-petal detail.
- **Level of detail**: primitives check `ink.unit()` (cm per local unit) and
  `ink.get_lift()` (ghost) and skip specks/veins when small or pale.
- **Species parity** (TikZ and Lua): both draw from pgf's generator (`ink.pgfrng` replays
  `pgfmathfunctions.random.code.tex` exactly, values in whole sp). Every *choice* is an
  integer draw (`W` uses `random(1,total)`), and real-valued traits are pgfmath's own
  numbers (`\flo@R` computed with `florilegium-pgfmath.lua`), since organs compare some of
  them (phenology into a stage); still never key a `BY` on an `R` trait.
  The draw order is `TRAITS`; a new trait or plan goes into `florilegium-species.lua` only,
  then `texlua tools/tikztables.lua`, `tools/speciescheck.lua` and `tools/tikzcheck.lua`.
- **Hybrid parity** (`florilegium-organs.lua` is `tikzlibraryflorilegium.code.tex` in Lua): a
  change to the library's drawing is made in both, line for line, and `tikzcheck.lua draw`
  must stay identical. Evaluate with the library's own expression text (`E"@a*(@b-0.3)"`) so
  pgfmath's parse applies, keep every macro assignment in the store (not in a Lua local), read
  an argument where TeX expands it (a macro passed as `#1` that the callee reassigns first is
  read late), and keep draws in the TeX order. Write sizes and coordinates out with `str`
  (print_scaled) and literal opacities as their TeX text (pgf names an ExtGState by it).
- **Determinism**: every primitive takes an rng; layout code draws from `layout` and
  hands primitives `rng.fork()`, so a change inside a primitive does not move the layout.
  Never iterate a string-keyed table with `pairs()` where the order feeds an rng (Lua's
  order changes from run to run); `florilegium-authored.lua` uses a fixed stem order for this reason.
- **Animation replays draws.** With `g.anim`, `florilegium-grow.lua: place()` calls each closure
  several times (smaller scales first) and restores `rng` and `layout` with
  `save()`/`load()` in between. A closure may only draw from those two (fork inside the
  closure, not before it), or the last frame stops matching the page; run
  `tools/animcheck.lua` after touching `florilegium-grow.lua`.
- **Separate streams keep old pages stable.** Visitors draw from `ink.rng(seed*7919+101)`,
  the season's additions from `+211`, the authored visitors from `+103`. With no visitors,
  no age and no marks a grown page is byte-identical to before those features (check by
  comparing against `git show HEAD:florilegium-grow.lua` etc. in a texlua harness with stubbed TeX).
- **Species margin** (option `species`, M3): every species branch in `florilegium-grow.lua` is an `if comm` with the classic code untouched in the `else`, and a classic page draws nothing new (`tools/ident.lua` before/after must stay identical). The plants come from a stream of their own (`+307`). Organs are computed as the pics compute them and painted by ink, not run by TikZ (the user's choice, #5044): the margin's PDF and SVG stay byte-identical, and an organ matches its pic to ink's 0.1 bp (checked by drawing the same code both ways, 600 dpi). An organ's pgf seed is drawn inside its `place` closure (`pgfseed(rng.fork())`), so the animation replays it. A species page takes 2–8 s and 0.8–1.8× a classic page's bytes (organs cost what flora costs; there are more of them).
- **The last animation frame uses t = ∞**: for the event that ends last,
  `(t0+dur-t0)/dur` can round just below 1 and leave a 95% bloom.
- **Text end, one pass**: `\florilegiumtextend` records `\pagetotal+\pagedepth` and the
  page number; the shipout hook of that same page reads them, in the same run.
- **Marks, one pass**: `florilegium.mark` writes a `user_defined` whatsit (user_id
  0x464C4F); in the shipout/background hook `\ShipoutBox` is complete, and walking it
  (heights, depths, `node.effective_glue`) gives each mark's y; the box's origin is 1 in
  (+`\voffset`) below the top of the paper. Option `sections` wraps `\@sect` at
  `\begin{document}` and puts the mark into the typeset title (#8), so standard classes only.
- **Aging needs the .aux**: `\flo@lastpage` is written at the end and read on the next run;
  until then every page is summer and LaTeX asks for a rerun.
- **Themes**: every primitive in `florilegium-grow.lua` and `florilegium-authored.lua` is called through `F` (never
  `flora.` directly), and the motif rows' `draw` functions use the module-level `F` upvalue
  that `M.theme()` reassigns. A theme's `motifs(rows, F)` gets copies of the base rows: keep
  their names (`counts.flower`, `counts.lily` and the marks look them up), set `w = 0` to
  retire one. `M.theme(nil)` must stay exactly the old path: check unthemed pages are
  byte-identical (harness below) after touching it.
- **Theme compositions**: a theme with `page(g, grow)` gets the whole page (grow.page and
  authored.page hand it over). It must follow the animation contract (record with tags,
  replay closures from `rng`/`layout` only, return `{ rec, total }`) and may return
  `captions = { {x, y, text, event, anchor, small, scale, rotate, color, opacity} }` in
  layout cm; florilegium.lua sets them as TikZ nodes (scaled 10 pt with `transform shape`,
  so any size works), swapping east/west anchors and negating rotations on mirrored pages.
  Text that reads left to right must run in `-x` in layout coordinates on a mirrored page
  (`fwd` in theme-math). Choose parameters with `layout` *before* `place`. TeX in captions
  must not need packages the user may not load (no `\mathbb`, `\binom`).
- **Density** must reduce to the old arithmetic at 1: only multiply/divide by `D` (or use
  `2 - D`, `sqrt(D)`, `D ^ 0.6`), never add rng draws on the D = 1 path. Low on the dial the
  structure itself thins (`NSTEM`, `FOOTER`, no ghosts < 0.4, no snail/bird < 0.3,
  `NBMAX = 40 D` branches); florilegium.lua clamps at 0.03. **Intensity** is `ink.set_pale` around
  the margin only (not initials or ornaments); `get_lift` (level of detail) ignores it.
- **Ornaments** are numbered in document order for their seed; `seed=random` (os.time) is
  the only non-deterministic path in the package, and it is opt-in.
- **Mirror**: `g.mirror` means the layout is in mirrored coordinates (text edges swapped);
  only `ink.page_transform(g.mirror and g.pw)` reflects. Anything that hands a position back
  in page coordinates (`ink.to_page`, e.g. `flora.hedera`'s stem end) is already reflected and
  must be mapped back (`pw - x`) before it is drawn again in layout coordinates.
- **Byte-identity harness**: `tools/ident.lua <dir>` writes 45 content streams (5 seeds ×
  spill × summer/novisitors/spring/autumn-marks, + authored) to a directory (~170 MB); run it
  before and after a change that should move nothing (`build/ident-before`, `-after`) and
  `diff -r`.
- **Never wrap typeset text in `q`…`Q` page literals**: `Q` drops the `Tf` LuaTeX set
  inside and the rest of the page's text disappears. The initial's invisible letter uses
  `3 Tr` / `0 Tr` instead. (ActualText on a path-only span is ignored by poppler.)
- This container's TeX Live lacks luaotfload's font database for system fonts; the
  documents pin Computer Modern. Harmless to remove on a full install.
- **SVG** (`florilegium-svg.lua`) translates only what `florilegium-ink.lua` writes (`m l c h f S W n q Q rg RG w d J j`,
  `gs` with `/floaNN` `/flomNN`) and errors on anything else: a new operator in ink needs a case
  there. Anything new that the page path of `florilegium.lua` reads from TeX (`tex.dimen`, `token`)
  needs a stub in `M.page`. Byte identity with LuaLaTeX rests on the length scan and the xcolor
  conversion; check it by building with `\pdfvariable compresslevel=0` and finding the streams
  (`svg.page`'s third return) in the PDF. The math theme's text is TeX: the CLI leaves it out with
  a warning, the playground sets it with MathJax (close to TeX's setting, not identical). Chromium
  draws hairlines thinner than a pixel heavier than PDF renderers do (a Maurer rose's chords); the
  SVG itself is right (Typst's svg2pdf, then poppler, matches the LuaLaTeX page).
- **Playground**: `worker.js` mounts only the modules in `MODULES`, so a new theme or module the
  page requires goes there too (`pages.yml` copies every `*.lua`). The browser runs Lua 5.4 and
  LuaTeX 5.3: keep the Lua to both. Seeds have matched byte for byte across texlua, lua5.3,
  lua5.4 and wasmoon (18 varied pages). Every control that differs from its default is in the
  URL hash; the LaTeX and command-line snippets give the same garden (checked: the CLI output is
  the download byte for byte, and the compiled LaTeX contains its garden and head rule). wasmoon
  keeps whatever `doString` returns on the Lua stack: without `lua.global.setTop(0)` after each
  call every page stays in memory and WebAssembly fails after ~35 pages ("attempt to index a nil
  value", "memory access out of bounds"). Run `tools/playcheck` after touching `web/`.
- **Playground design** (the user's direction, 2026-10-31): a printer's proof and its colophon, not
  a sidebar of sliders. Cobalt is what is printed, copper what can be taken hold of; a choice is
  never told by color alone (a manicule ☞ and an underline). The colophon is generated from the
  state, so it cannot disagree with the page, and it offers only what the style uses: the math
  page has no season and no visitors (they change nothing there), geometric and math have no species, its density ends "pared down to
  a few figures" and its head rule starts with a circle, not an ivy leaf; a seed that no visitor
  came to says so. Each density is a whole phrase, so the sentence reads at every value. Fell for the table and slip, Latin Modern (renamed
  Florilegium Roman/Mono, as GUST asks of modified fonts) for the page; fonts are self-hosted.
- **Repository and CI** (2026-11-01): every action is pinned to a full commit SHA with the version
  in a comment (`uses: x/y@<sha> # v1.2.3`; the repository requires SHA pins), workflows default to
  `contents: read` and grant more per job, checkouts use `persist-credentials: false`. Check with
  `uvx --from actionlint-py actionlint` and `uvx zizmor --offline .github/`. Dependabot: alerts
  only for security (the user finds per-dependency PRs annoying; security-update PRs stay off),
  plus one grouped version-update PR a month. Main needs a PR with `lua` and `pdfs` green (admin
  bypass); `v*` tags can't be moved or deleted.
- **Releases** are immutable once published. First set the new version everywhere in one commit,
  the `\ProvidesPackage` date and v-number in the `.sty` and every `M.version` with
  `sed -i -E 's/^M\.version = "[^"]*"/M.version = "1.3"/' florilegium*.lua`, then
  `tools/versioncheck.sh v1.3` (CI runs it on every push, and with the tag on a tag push, so a
  missed file or a tag that doesn't match stops before any draft). Then push an annotated tag
  (`git tag -a v1.3 -m v1.3 && git push origin v1.3`), CI builds the PDFs, attests them and opens a draft release with them;
  then write the notes and `gh release edit v1.3 --notes-file … --draft=false`. Assets can't be
  added after that, so never publish a draft before CI has attached the four PDFs and
  `florilegium-pdfs.sigstore.json`.
- **Playground supply chain**: wasmoon and MathJax load from jsDelivr only as the bytes pinned
  beside their URLs (`['url', 'sha384-…']`, one line each, so `tools/sri.sh` and playcheck can
  find them); `index.html` has a Content-Security-Policy meta naming the MathJax file. A new
  version needs the URL, the hash (`tools/sri.sh` prints the served one) and, for MathJax, the CSP.
  A new third-party script needs a pin and a CSP entry, or the page refuses it.
- **PostScript port** (`postscript/florilegium.ps`, `make postscript [SEED=7]`, ~2.5 s):
  callbacks (spines, half-widths) see their caller's variables by dynamic scoping, so a
  helper that takes a procedure keeps its own names under `_` (`_p`, `_n`), and the growth
  helpers use prefixes (`d.` disc, `a.` addstem…). Nothing is painted while it grows:
  `ifill`/`istroke`/`iclip` capture the path with `pathforall` into numbered layers and
  `paintlayers` replays them. Angles are degrees (PostScript's `sin`/`cos`/`atan`); the rng
  is Park-Miller (Schrage), not mulberry32. Literal arrays in a procedure body are shared
  between calls; build fresh ones before mutating. `postscript/README.md` is the port's own
  documentation (options, the seed and clock, porting notes, Ghostscript notes, tests): keep
  it in step with the file. Options go through `optnum`/`optbool`/`seedof` in `main` (a bare
  `-dSeed` is `true`, `-sSeed` a string); seeds wrap at `SEEDMAX` 250000 so `seed*7919` stays
  in 32 bits on page 2 (printers); no seed = `clockseed` from `%Calendar%`. `-dFloCheck`
  writes a checksum of the captured layers per page to stderr; after a change that should
  move nothing, `make pscheck` must stay green, and after an intended one, `check.sh
  --record` and look at the pages.
- **Ghostscript traps** (10.05): the PS transparency operators exist only with
  `-dALLOWPSTRANSPARENCY`; a raster device also needs `0 .pushpdf14devicefilter` per page;
  a PS `stroke` takes the *fill* alpha when rasterized and the stroke alpha in pdfwrite, so
  set both; a banded second page with the compositor pushed segfaults (hence `/MaxBitmap`
  in `setpagedevice`); Adobe's `ISOLatin1Encoding` has `/minus` at 45, not `/hyphen`.
  `realtime`/`usertime` count from the interpreter's start (~20 ms when the file asks), not
  wall time; `%Calendar%` has the date and time (local, follows `TZ`) under `-dSAFER`.
  `pathforall` coordinates are rounded to the device grid, so the `-dFloCheck` checksum
  depends on device and resolution (check.sh: nullpage, 72 dpi).

## How the growth works (florilegium-grow.lua)

1. Regions: margin column, a footer band along the bottom (to ~45% of the text width),
   and on the last page the rectangle under the text, down to 0.6 cm above the text block's
   foot. Species pages (no theme) reach lower on a last page: the rectangle runs down to the
   page number's line (`footy + 0.55`) and the footer band runs the full text width under it,
   so only that line stays clear (2026-11-02, the user: v1.3 left ~2.9 cm empty there).
   `border()` treats an edge shared with another rect as open; a point whose four edges are
   all open takes its rect's nearest edge, since an infinite free radius makes the next
   disc's `each_near` loop for ever (a prototype with rects around the page number hung).
2. Stems: three from a root near the bottom-left corner; x(y) = c + A·fbm(y/λ + φ), blended
   into the root over 4 cm. Tops at the page top (hero flower), 60–72% (lily), 36–48%
   (flower). A spiral scroll at the root; a footer stem to the right. On the last page,
   Bézier arcs from a main stem into the spill, each ending in a flower.
3. Ghosts (1–2 pale flowers, layer 1) get a weak proxy so the growth leaves them some room.
4. Leaves at nodes of every "leafy" stem (alternating, 35–60°, smaller toward the top; the
   footer gets leaflets that thin out), only where `free` allows.
5. Grid (2 mm), `free` = largest disc that fits (proxies count at κ=0.85 of their radius;
   stems are chains of small discs) and `sdist` = distance to the nearest stem point.
   Updates only visit lattice cells near the new disc.
6. Branch loop: cell with the largest `free·U(0.85,1.15)` within REACH (3 cm) of a stem;
   pick a motif by weight `w/(1+count/cap)` (hard caps only for flower, lily, umbel,
   bells); scale so r(s) ≈ 0.95·free; axis = away from the nearest stem point + `upright`
   lean; `flora.branch_path` from that stem point; the branch's points become stem points.
   Stop below SMALLEST (3.6 mm).
7. Filler: holes ≥ 1.7 mm within 7.5 mm of a stem get a leaflet pair, a bud or a floret
   cluster (capped); far holes get at most 6 copper accents; no dust.
8. Footer tail: copper hairline + sparkle. Layers: 1 ghost, 2 stems, 3 leaves, 4 airy,
   5 blooms, 6 accents (7 overlay, animation only); a safety clip a little outside the regions.
9. Marks (before the leaves, right after the ghosts): a flower beside each heading
   (copper, via `ink.in_accent`) or `\florilegiumbloom[motif]`, at the column's edge,
   shrunk or left out where there's no room. Then visitors on the stems: a snail on a
   main stem (40% of pages), a bird on its own twig (22%). Butterflies and bees are motif
   rows with `fly = true` (no branch, fixed caps of 2), allowed per page by the visitor stream.
10. Seasons (`g.age`; nil = summer, unchanged): `season(spring, summer, autumn)` blends a
   value; motif rows carry `spring`/`summer`/`autumn` weight multipliers (`budding` only in
   spring, `seedhead` only in autumn); the shorter stems end in buds or seed heads; young
   leaves are smaller and paler (ghost lift); autumn turns some leaves copper and drops
   petals below the flowers (`blooms`).
11. Animation (`g.anim`, set by `\florilegiumframe`): every step is an `event` (a stem
   that grows or a motif that opens), either in a phase (stems, ghost, marks, branch,
   fall, fill, accent, tail) or starting at a fraction `at` of its parent's growth. Output is tagged
   `{event, from, to}` (`ink.tag`); stems are also drawn as prefixes every GROWSTEP with a
   pointed tip, motifs at the BLOOM scales. `schedule()` times the events (T_* constants,
   ~13 s); `florilegium.lua` records once per garden and `ink.emit`s the visible pieces of
   each frame in painting order. The explained version adds a dashed disc per branch.
   `place(..., path, steps)` moves a motif along `path(e)` instead of opening it (visitors
   fly in, petals fall, the snail crawls with `till_end`).

To add a motif: write the primitive in `florilegium-flora.lua` (origin at its base or center, axis
+y, takes `rng`), then add a row to `motifs` in `florilegium-grow.lua` with `r(s)` (proxy radius),
`off(s)` (center back to the origin along the axis), `upright`, `layer`, `w`, `max`,
optionally `hard`/`hang`/`fly` and season multipliers, and `draw(rng, s)`. `florilegium-authored.lua`
can then place it by name, and `\florilegiumbloom[name]` can ask for it.

To add a theme: write `florilegium-theme-<name>.lua` returning `{ flora = { name = fn, ... },
motifs = function(rows, F) ... return rows end }` (see `florilegium-theme-geometric.lua`), or with
`page = function(g, grow)` for a composition of its own (see `florilegium-theme-math.lua`). Its primitives
replace flora's by name with the same signature and frame (`flower(rng, s)` centered,
`sprig(rng, L)` from its base along +y, ...); `motifs` may reweight rows and append new
ones (their `draw` should call `F.x`). Then `\usepackage[grown,theme=name]` or
`\florilegiumtheme{name}`; add the theme to a case in `tools/animcheck.lua`, and look at a
page and a specimen sheet.

## Ideas not done

- Proxies of 2–3 discs for long motifs (leaves, cymes) instead of one disc.
- Read free space on every page (floats, display equations), not just the last.
- Leaf tips that curl over and show a paler underside, as in the reference image.
- Section flowers for KOMA/titlesec headings (only `\@sect`-based classes now).
- Initials in the authored composition's style for the first page, and a bigger, framed
  title-page tile.
- More themes: knots, fractals (Koch, Julia), graphs; a theme chosen from `\subjclass` /
  `\keywords` (MSC code → theme), or per section (blackboard #4941 and its subtasks).
- Form XObjects for repeated sub-shapes (florets) to cut the PDF size further.
- Plate: figures traced by a pen in the animation (they only scale in now); more figures
  (Möbius strip, torus, Penrose tiles, Sierpiński); the footer band is left empty.
