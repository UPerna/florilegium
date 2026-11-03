# florilegium

[![build](https://github.com/kevinraymond/florilegium/actions/workflows/build.yml/badge.svg?branch=main)](https://github.com/kevinraymond/florilegium/actions/workflows/build.yml)
[![playground](https://github.com/kevinraymond/florilegium/actions/workflows/pages.yml/badge.svg?branch=main)](https://kevinraymond.github.io/florilegium/)
[![release](https://img.shields.io/github/v/release/kevinraymond/florilegium?color=2456c4)](https://github.com/kevinraymond/florilegium/releases/latest)
[![license](https://img.shields.io/github/license/kevinraymond/florilegium?color=2456c4)](LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/kevinraymond/florilegium/badge)](https://scorecard.dev/viewer/?uri=github.com/kevinraymond/florilegium)

Procedurally generated Delft-blue floral page margins for LaTeX. No images, no imported paths,
no external assets: every petal, leaf and stem is a curve computed while the page is being
written, painted like a watercolor, and written straight into the PDF. Every page grows a
garden of its own, and every document its own plants, each sampled from a genome.

![six seeds](gallery/seeds.gif)

*Six seeds of the grown margin. Same code, different seed, and the garden fills whatever space
the text leaves free.*

**[Try it in your browser](https://kevinraymond.github.io/florilegium/)** ·
[download the PDFs](https://github.com/kevinraymond/florilegium/releases/latest) ·
[documentation](#documentation)

## Origin

The [Reddit post](https://www.reddit.com/r/LaTeX/comments/1xixznw/how_do_you_make_these_flowers_in_latex/)
asked how to make flowers like these in LaTeX. I don't know how the original was made. This
project is one possible way. The way I did it first, in 1.3, uses hand-authored primitives with
randomized parameters, painted in Lua and placed by a procedural layout whose "fill the unused
space" part borrows a 1998 idea from the ornament literature. In 2.0 the plants and animals of
the grown margin are sampled from genomes of botanical traits, so what grows is procedural too,
not only where it grows. It gets a similar look, but I explicitly tried to not replicate the
original.

This project was made with the assistance of AI (Claude), and I'm sharing the
[process I used](PROCESS.md) to bring it to life.

## Quick start

With LuaLaTeX, put `florilegium.sty` and the `florilegium*.lua` files beside your document (or
upload them to an [Overleaf](https://www.overleaf.com) project set to LuaLaTeX):

```latex
\usepackage[a4paper,left=68mm,right=22mm]{geometry}   % a wide margin for the garden
\usepackage[grown,sections]{florilegium}              % flowers at the headings, too
\definecolor{ink}{HTML}{5B2A1F}                       % optional: any hue (this is sepia)
...
\florilegiuminitial[4]{T}his paragraph starts with a decorated T.
\florilegiumtextend                                   % at the very end: fill the space below
```

With pdfLaTeX, or in any TikZ picture, the TikZ library draws the same species in pure TikZ
(it needs only its two `tikzlibraryflorilegium*.code.tex` files):

```latex
\usepackage{tikz}
\usetikzlibrary{florilegium}
\begin{tikzpicture}
  \pic {florilegium plants={plants={3/rose, 17/umbellifer, 29/mustard}, size=21cm, width=6cm}};
\end{tikzpicture}
```

[Using the package](docs/usage.md) lists every option and command.

## The documents

| | `florilegium-grow.tex` | `florilegium.tex` |
|---|---|---|
| composition | **grown**: plants grown to fit the page by a greedy space-filling loop | **authored**: stems, leaves and flowers placed by hand, every parameter sampled |
| adapts to | the page layout, and the free space below the text on the last page | nothing (tuned for A4, 68 mm margin) |
| preview | <img src="gallery/preview-grown.png" alt="grown" width="300"> | <img src="gallery/preview-authored.png" alt="authored" width="300"> |
| PDF | [florilegium-grow.pdf](https://github.com/kevinraymond/florilegium/releases/latest/download/florilegium-grow.pdf) | [florilegium.pdf](https://github.com/kevinraymond/florilegium/releases/latest/download/florilegium.pdf) |

Both are self-describing: their body text is the write-up of how the margin is drawn.
[`showcase.tex`](https://github.com/kevinraymond/florilegium/releases/latest/download/showcase.pdf)
shows what the margin does with a document's text, and
[`spread.tex`](https://github.com/kevinraymond/florilegium/releases/latest/download/spread.pdf)
two-sided pages.

## Watch it grow

| as it grows | with the free space it fills |
|---|---|
| <img src="gallery/growth.gif" alt="seed 6 growing" width="400"> | <img src="gallery/growth-explain.gif" alt="seed 6 growing, with the free discs marked" width="400"> |

*Seed 6, from an empty margin to the finished page. The stems rise first, leaves open as the
tips pass their nodes, and each stem ends in a flower. Then the greedy loop takes over: on the
right, each dashed circle is the largest free disc it found, just before a branch grows to it.
Big holes come first, small ones last. The visitors fly in at the end, and the last frame is
exactly the page this seed always gives.*

[How it works](docs/how-it-works.md) follows the loop step by step.

## Plants from genomes

| three plants on one root, twice | every flower form, as its plant holds it |
|---|---|
| <img src="gallery/species-strips.png" alt="two strips of three species plants" width="400"> | <img src="gallery/species-forms.png" alt="the flower forms of the species" width="400"> |

Each plant in a grown margin is a species, 62 traits sampled in a fixed order from one of
fifteen body plans, from the visitor its flowers are for to its flower, its cluster, its leaf
and its fruit. A body plan keeps botany's rules, so a lily has its parts in threes and a pea
flower is two-sided with a pod. A document gets eight species and each page grows four, so
they recur through the document the way plants recur through a garden. Each species can
describe itself:

> A blue wheel of five lobes in a coiled cyme that uncurls, for bees; hairy, smooth-edged, oval
> leaves; then nutlets.
>
> A blue pea flower along a raceme, for bees; leaves of five pairs of smooth-edged leaflets,
> climbing by tendrils; then pods.

[The species garden](docs/species.md) describes the genome and how a page chooses its plants.

## Visitors

<img src="gallery/species-visitors.png" alt="butterflies, moths, bees, a hoverfly, dragonflies, beetles, caterpillars, a snail and a bird" width="600">

Visitors are sampled from genomes of their own, fifteen kinds from butterflies and hawkmoths to
ladybirds, caterpillars, snails and birds. Each plant brings the visitor its flowers are for, so
a bee flies in near a bee flower and a hummingbird near a red tube, while a snail climbs a stem
and a caterpillar eats a leaf of its own. About three come to a page; `novisitors` leaves them
out and the page exactly as it was.

## The margin reads the text

![the three pages of showcase.tex](gallery/preview-showcase.png)

*`showcase.tex`, "A year in the margin": spring on the first page, summer, autumn on the last.*

A paragraph can open with a decorated initial, the letter's outline read from a font and wound
with a vine that passes over and under its strokes. Every numbered heading can get a flower
beside it in copper, the way headings were once picked out in red, and `\florilegiumbloom`
puts one beside any line. With the option `aging`, the garden ages from buds on the first page
to fruit and seed heads on the last. [Using the package](docs/usage.md#the-margin-reads-the-text)
has the details.

## In pure TikZ

The species don't need Lua. Under pdfLaTeX, `\usetikzlibrary{florilegium}` samples each plant
and visitor from its genome, grows it and paints it with pgfmath and TikZ alone, and each of
the strips above is one `\pic`. It takes a minute and a half for a strip of three plants 21 cm
tall, and pdfTeX needs more memory than it has by default. Under LuaLaTeX, the same pics are drawn by
florilegium's Lua in under a second, within a fraction of a point of pure TikZ's drawing. Only
the margin itself, laid out around a page's text, is the package's and needs LuaLaTeX.

```latex
\pic {florilegium flower={seed=7, role=hero, size=2.6cm}};
\pic {florilegium inflorescence={seed=20, role=heath, scale=1.3, season=0.3}};   % in spring
\pic {florilegium visitor={seed=3, role=butterfly, size=3cm}};
```

[The TikZ library](docs/tikz.md) lists every pic and key.

## Themes

![seed 6 as the species garden, geometric and math](gallery/themes.png)

*Seed 6 three times: the species garden, with `theme=geometric`, and with `theme=math`.*

The growth loop never knew what it was drawing, so a theme can redraw it. `theme=geometric`
cuts v1.3's plant from flat, straight-edged shapes, with crystals among the flowers.
`theme=math` grows no plant at all, but figures, families of figures and equations that cascade
down the margin and across the foot of the page. [Themes](docs/themes.md) shows both, and how
to write one.

## More in the margin

| | |
|---|---|
| <img src="gallery/inks.png" alt="one seed in six inks" width="400"> | <img src="gallery/dials.png" alt="seed 6 at four densities and a lower intensity" width="400"> |
| *[Any ink](docs/usage.md#colors).* The whole palette comes from one color, computed in OKLCH so the pale end never turns gray. | *[Less in the margin](docs/usage.md#less-in-the-margin).* `density` grows less, down to a single vine; `intensity` paints paler. |
| <img src="gallery/spread.png" alt="pages 2 and 3 of spread.tex" width="400"> | <img src="gallery/ornaments.png" alt="ornaments set in the text" width="400"> |
| *[Both sides of the page](docs/usage.md#both-sides-of-the-page).* The garden grows in the wider margin, mirrored on a right-hand page. | *[One ornament in the text](docs/usage.md#one-ornament-in-the-text).* `\florilegiumornament{leaf}` sets one shape in the line. |

## Without TeX

| SVG and the browser | PostScript |
|---|---|
| <img src="gallery/playground.png" alt="the playground, a proof of the page and its colophon" width="400"> | <img src="gallery/printed.jpg" alt="two prints of florilegium.ps, two different gardens" width="400"> |
| `florilegium-svg.lua` runs the package's own Lua under any Lua 5.3 or 5.4 and writes the page as SVG, byte for byte the drawing LuaLaTeX would make, for Typst or any page background. The [playground](https://kevinraymond.github.io/florilegium/) runs it in the browser, set as a printer's proof whose colophon is the set of controls. | `postscript/florilegium.ps` grows v1.3's garden in PostScript, one self-contained file. Ghostscript or a printer computes every petal while it reads the page; sent twice to a printer with no seed, it prints two different gardens. |

[SVG, Typst and the browser](docs/svg-and-web.md) and [the PostScript port](postscript/README.md)
have the details.

## 1.3 and 2.0

Nothing in either release is an image: every shape is computed from a seed. What the code
decides is another matter. In 1.3 the margin is grown, but what grows in it comes from a fixed
set of *hand-designed kinds*, shapes written by hand (a flower, a lily, a leaf, a butterfly ...)
whose sizes and details are random. In 2.0 the grown margin's plants and animals are *species*
sampled from genomes, so each document's seed grows plants of its own, and the TikZ library
draws the same species on their own.

| page 2 of the grown document, 1.3 and 2.0 | up close at 600 dpi, 1.3 left and 2.0 right |
|---|---|
| <img src="gallery/compare-pages.png" alt="the margin of the same page in 1.3 and in 2.0" width="300"> | <img src="gallery/compare-600dpi.png" alt="the top flower and the middle of the column of each, at 600 dpi" width="500"> |

*The same page and seed in both releases. 2.0 paints its species with 1.3's washes, streaks and
veins, so what changes is what grows: daisies, star lilies, a fern at the root, and the visitors
those plants bring.*

| what | release | where things go | the plants and animals | drawn by |
|---|---|---|---|---|
| grown margin | 1.3 | **procedural**, grown into the free space | hand-designed kinds | Lua (LuaLaTeX) |
| grown margin | 2.0 | **procedural**, grown into the free space | **procedural** species from genomes | Lua (LuaLaTeX) |
| authored page | both | placed by hand | hand-designed kinds | Lua (LuaLaTeX) |
| geometric theme | both | **procedural**, grown | hand-designed kinds, cut flat | Lua (LuaLaTeX) |
| math theme | both | **procedural**, packed into the free space | figures computed from their mathematics, and TeX's equations | Lua and TeX (LuaLaTeX) |
| ornaments and initials | both | set in the text; an initial's vine grown round its letter | hand-designed kinds | Lua (LuaLaTeX) |
| TikZ pics (`\usetikzlibrary{florilegium}`) | 2.0 | **procedural**, each pic grows its own plants | **procedural** species from genomes | pure TikZ (pdfLaTeX or LuaLaTeX), or Lua (LuaLaTeX's default) |
| SVG without TeX, and the playground | both | as that release's margin | as that release's margin | any Lua 5.3 or 5.4, a browser |
| PostScript (`postscript/florilegium.ps`) | both | **procedural**, grown | hand-designed kinds (1.3's garden) | PostScript |

A species page draws about 1.7 times as much as a 1.3 page, and takes a little under twice as
long:

| | 1.3 | 2.0 |
|---|---|---|
| ten pages of text, no margin (LuaLaTeX) | 0.4 s, 33 KB | 0.4 s, 33 KB |
| the same ten pages with the grown margin (LuaLaTeX) | 7.1 s, 6.3 MB | 12.6 s, 10.7 MB |
| what the margin adds to a page | 0.67 s, 0.63 MB | 1.23 s, 1.1 MB |
| one TikZ strip of three plants, pdfLaTeX, pure TikZ | not in 1.3 | 86 s, 1.3 MB (6.3 million words of TeX's memory) |
| the same strip, LuaLaTeX, pure TikZ (`engine=tikz`) | not in 1.3 | 98 s, 1.3 MB |
| the same strip, LuaLaTeX, Lua engine (the default) | not in 1.3 | 0.8 s, 0.5 MB |

*`tools/bench.tex` (seed 7, the last page short) and `tools/bench-tikz.tex`, timed on
2026-11-03 on an Intel Core i9-13900K with LuaHBTeX 1.17.0 (TeX Live 2023), each time the
median of three runs (pure TikZ: one run). What the margin adds is the difference from the same
text without one (option `nomargin`), per page. `make bench` measures every row again.*

## Documentation

- [Using the package](docs/usage.md) has the options and commands, seeds, colors, initials,
  headings, seasons, density, two-sided pages and ornaments.
- [The species garden](docs/species.md) describes the genomes, the body plans, how a document
  chooses its plants, and the visitors.
- [The TikZ library](docs/tikz.md) lists the pics and their keys, and explains the two engines
  and pdfLaTeX's memory.
- [Themes](docs/themes.md) shows geometric and math, and how to write a theme.
- [How it works](docs/how-it-works.md) follows the painting, the growth loop, the reading of the
  page, the initials and the animation.
- [SVG, Typst and the browser](docs/svg-and-web.md) and [the PostScript port](postscript/README.md)
  draw the garden without TeX.
- [Building and checking](docs/building.md) lists every `make` target and check.
- [CLAUDE.md](CLAUDE.md) is a handoff-style map of the code, its conventions and traps, and ideas
  not yet done.

## Build

```sh
make                        # the four PDFs (LuaLaTeX)
make RUN=tools/in-docker    # the same in a TeX Live image, after: docker build -t florilegium-tex tools
make playground             # the browser playground at http://localhost:8000/web/
```

## Credits

- The [Reddit post](https://www.reddit.com/r/LaTeX/comments/1xixznw/how_do_you_make_these_flowers_in_latex/)
  that asked the question (see [Origin](#origin)).
- The growth loop follows Wong, Zongker & Salesin,
  [*Computer-Generated Floral Ornament*](https://dl.acm.org/doi/10.1145/280814.280948) (SIGGRAPH 1998).
- The tone ramp is computed in [Oklab](https://bottosson.github.io/posts/oklab/), Björn Ottosson's
  perceptual color space; the conversion matrices in `florilegium-ink.lua` are his, released into
  the public domain (or under the MIT license, for those who prefer it).
- The random numbers come from [mulberry32](https://gist.github.com/tommyettinger/46a874533244883189143505d203312c),
  Tommy Ettinger's generator, dedicated to the public domain (CC0). The PostScript port uses the "minimal standard"
  generator of Park and Miller (Communications of the ACM, 1988) by Schrage's method (ACM
  Transactions on Mathematical Software, 1979).
- The species' trait tables follow research notes made for this project. Only a radially
  symmetric flower varies its number of petals, as Damerval and Nadot found in the buttercup
  order (Annals of Botany, 2007). Flowers and visitors are paired by the pollination syndromes
  of the U.S. Forest Service's
  [*Pollinator Syndromes*](https://www.fs.usda.gov/wildflowers/pollinators/What_is_Pollination/syndromes.shtml)
  page. Heads and daisy discs are packed on Helmut Vogel's model of the sunflower (Mathematical
  Biosciences, 1979), and a butterfly's pattern follows the nymphalid groundplan of Schwanwitsch
  (1924) and Süffert (1927).
- The TikZ library draws with [PGF/TikZ](https://github.com/pgf-tikz/pgf) (Till Tantau and
  others; LPPL 1.3c or GPL 2), and its random numbers and arithmetic are pgfmath's, by Mark
  Wibrow, whose ln follows an algorithm due to Rouben Rostamian with coefficients by Alain
  Matthes. `florilegium-pgfmath.lua` and `florilegium-ink.lua`'s `pgfrng` reimplement the part
  the species need in Lua (pgf's generator; pgfmath's reading and printing of numbers, its
  multiply, divide, ln, exp and pow); they are not part of pgf, and their headers say how they
  differ and where pgf is, as the LPPL asks of derived work.
- `\florilegiumornament`, its `ink` and `seed=random` keys, and the `density` option answer
  [issue #4](https://github.com/kevinraymond/florilegium/issues/4) from rubyFeedback.
- The playground runs the Lua in the browser with [wasmoon](https://github.com/ceifa/wasmoon)
  (MIT) and typesets the math theme's equations with [MathJax](https://www.mathjax.org) (Apache 2.0),
  both loaded from jsDelivr. It is set in Igino Marini's IM FELL DW Pica (SIL OFL) and Latin Modern
  (GUST e-foundry, GUST Font License); see `web/fonts/README.md`. Its color-blindness views use
  the model of Machado, Oliveira & Fernandes, *A Physiologically-based Model for Simulation of
  Color Vision Deficiency* (IEEE TVCG, 2009).
- The math theme's figures keep the names of the people they come from: Maurer's roses, Vogel's
  model of the sunflower, Temple Fay's butterfly curve, the Petersen graph, Koch's snowflake,
  Hilbert's curve, Lissajous figures, the gasket of Apollonius.

## License

MIT, see [LICENSE](LICENSE). Copyright (c) 2026 Kevin Raymond.
