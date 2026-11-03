# Building and checking

The documents need LuaLaTeX, one run each, about a second a page (two runs for `showcase.tex`,
whose seasons need the page count). The TikZ specimen sheet builds under pdfLaTeX too.

```sh
make                        # the four PDFs
make seed-7                 # one page from seed 7 -> build/seed-7.pdf
make preview                # the gallery's preview images
make gallery                # gallery/seeds.png + seeds.gif, inks.png, seasons.png, themes.png, dials.png (python3, Pillow, pdftoppm)
make grow-6                 # growth animation of seed 6 -> build/grow-6.gif + .mp4 (ffmpeg)
make grow-6 EXPLAIN=1       # the same with the free discs marked -> build/grow-6-explain.*
make svg SEED=7             # the same page as SVG, without TeX -> build/svg-7.svg
make playground             # the browser playground at http://localhost:8000/web/
make postscript             # the PostScript port through Ghostscript -> build/postscript-7.pdf
make bench                  # v1.3 against this tree, and the TikZ library's engines (about 5 minutes)
lualatex specimen-tikz.tex                         # every species form, the Lua engine (seconds)
extra_mem_top=20000000 pdflatex specimen-tikz.tex  # the same in pure TikZ (about 10 minutes)
```

No TeX installed? Build the image once and run everything in it:

```sh
docker build -t florilegium-tex tools
make RUN=tools/in-docker
```

## Checks

These are the checks CI runs, or that a change to one part calls for. Each is described at the
top of its file.

```sh
tools/svgcheck.sh lua5.3 lua5.4                       # varied pages through florilegium-svg.lua, byte-identical across interpreters
tools/in-docker texlua tools/speciescheck.lua 2000    # sampled species and visitors keep every rule; the TikZ tables are current
tools/in-docker texlua tools/tikzcheck.lua 1 1000     # TikZ and Lua sample the same species
tools/in-docker texlua tools/tikzcheck.lua draw quick # the Lua engine's pics render as pure TikZ's (about 15 minutes)
tools/in-docker texlua tools/pgfmathcheck.lua 30000   # the pgfmath arithmetic Lua takes from TeX, exactly
tools/in-docker texlua tools/animcheck.lua 1 2 3      # the last frame of the animation is the page
tools/in-docker texlua tools/ident.lua build/ident-a  # content streams to diff before and after a change
tools/versioncheck.sh                                 # every file names the same release
tools/sri.sh                                          # the playground's pinned CDN files still match their hashes
make pscheck                                          # the PostScript port against its recorded checksums
```

The playground has its own check, which operates every control in a headless browser. Serve the
repository (`make playground`), then run `cd tools/playcheck && npm install && node check.mjs
http://localhost:8000/web/ ../../build`.
