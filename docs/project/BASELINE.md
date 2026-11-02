# Recoverable compatibility baseline

Verified 2 November 2026. Source revision `a77e32057da52d44b9baa8c0c1bce55865a45bf7`, tree `34b2d21674dc999eb0da6772bc6b72882dc9fdc4`. Branch: `improve/layout-controls`, PR #1. The user explicitly accepted `dd8ee95` as replacement for the lost delivery `96545fa`; that delivery was never recovered. The checkpoint adds records while retaining all 99 original source/binary blobs and their modes. See the stage 00 manifest.

## Build and verification

The reproduced engine baseline is Linux, TeX Live 2026, LuaHBTeX/LuaTeX 1.24.0, from [build #11](https://github.com/UPerna/florilegium/actions/runs/41439783001) for exactly `a77e320`. Both required jobs passed. The optional manually triggered gallery job was skipped. This run was initiated by publication during this execution; it is not an older green check substituted for current evidence.

Install TeX Live with LuaLaTeX, XeLaTeX, texlua, LaTeX recommended/extra/pictures packages, Latin Modern and Computer Modern fonts; Python 3 with Pillow; Poppler including pdftotext and pdftoppm; Inkscape 1.x; and Make. The Dockerfile provides the declared Ubuntu 24.04 package route. Its TeX Live 2023 comment describes that distribution route, not the 2026 CI runtime. Dependency availability in this Windows session differs from the tested Linux environment.

Run from the repository root:

```sh
make check CHECK_SEEDS="1 6"
python3 tools/enginecheck.py --require-outlines
python3 tools/offsetcheck.py
python3 tools/exportcheck.py
python3 tools/visualcheck.py
python3 tools/foliopreview.py
python3 tools/build.py folio-demo.tex --engine xe --output-dir build/xe
python3 tools/packagecheck.py
```

The CI workflow also compiles authored/grown/showcase/book/asset/folio/specimen documents before regressions. Actual observations include 28 layout checks (three upstream fingerprints), 22 option cases, nine class/book cases, 11 dual-engine documents, six rejected Xe inputs, eight rendered physical-offset cases, required decorated outlines, reservation visual checks, vector exports and extracted Lua/Xe source-kit builds. Animation, routing, standalone resource and upright lettering checks run in the same required jobs. Commands and test oracles remain in the existing workflow and tools; no thresholds or fixtures were changed.

Locally reproduced: all 99 baseline Git blob identities; binary SHA-256 inventory; clean Git tree/history and bundle integrity; source-kit byte reproducibility, all 93 packaged hashes and local README image existence; PDF parsing/text comparison and rendered specimen inspection. Local tools: Python 3.12.14, pypdf 6.10.0, bundled Poppler pdfinfo/pdftoppm. The bundled Poppler omits pdftotext. A release-digest-verified portable TinyTeX v2026.11 was downloaded, but its executables fail Windows path initialization before any test executes. Moving it to a shorter workspace path and direct invocation did not fix initialization; Win32 long-path lookup itself succeeds. Local engine checks remain failed/unrun, and native Windows compatibility is not claimed. Linux CI provides the engine evidence, not an invented Windows pass.

## Source and public behavior

Lua modules preserve their established responsibilities: `ink` handles deterministic streams, transforms, paints and drawing sinks; `flora` primitives; `authored` and `grow` compositions; `layout` controls; `space` reservations/routing; `initial` glyph decoration; `numeral` and `folio` lettering; `pdfwriter` standalone resources; `fontreader` optional font loading; `florilegium` host glue; `florilegium-xe` external records. The `.sty` file and two `.def` hosts retain the public TeX interface. Source text, demos, vector assets, Make targets, Python build/export/package tools and CI remain intact. No new platform family is implemented by this baseline stage.

The exact default drawing compatibility target is upstream `138f9f2603736eba8ea9014b33b381bdd5a503f5`, using the three existing path fingerprints. Upstream HEAD observed separately was `231f5eb058af11d59508f532c66697df57d73793`. It was neither merged nor tested for compatibility. The prior `fb253ea` compatibility review reported in the lost delivery cannot be recovered or treated as verified.

## Sample freshness and durable fixtures

Tracked root PDFs are historical snapshots. Fresh authoritative PDFs for this baseline are the seven outputs in [the exact-revision artifact](https://github.com/UPerna/florilegium/actions/runs/41439783001/artifacts/13138616147), ZIP SHA-256 `f339ddb5b28a2a30132403c5855076f8b2efbcd291118eb228d25f4da320eb7b`. The CI source-kit artifact is available from the same run. Preserve downloaded copies and their manifests outside normal source history.

Investigation found actual outdated sharing/build prose in tracked `florilegium.pdf` and `florilegium-grow.pdf`, compared with the current `.tex` inputs and fresh CI outputs. Other extracted mathematical differences are glyph variation selectors/spacing. `showcase.pdf` and `specimen.pdf` have equal extracted text after Unicode NFKC normalization. The specimen source's explicit bounding box also explains the changed page composition; old and fresh sheets were rendered and inspected. These historical PDFs are retained rather than silently refreshed as expected baselines. Use regenerated CI outputs or rebuild from source for current documentation. No byte-identity claim spans differing TeX versions/metadata/fonts.

Small durable fixtures are the existing three seeded fingerprint cases in `tools/layoutcheck.lua`, the original `examples/assets/butterfly.pdf` and matching SVG/TeX recipe, the book template, and the fixture registry. Stage 00 records exact asset/blob/SHA-256 identities. The complete-history recovery bundle preserves the baseline independently of transient build folders.

## Limits and licenses

MIT project/source notices and the pinned K1o0n/wilsybubs attributions remain in LICENSE and ACKNOWLEDGEMENTS.md. No font binaries are added. Asset provenance and later paper/data licenses require stage 02's capability ledger.

Reservations are explicit and unbreakable; a blocked route can interrupt a clipped stem. Folios support the declared Arabic/Roman forms and may be omitted with diagnostics when obstructed/unsupported. Document classes own footers. Monochrome does not recolor arbitrary included PDFs. SVG is tested with Inkscape; Office import is untested. The PostScript port retains its separate legacy capabilities. Native Windows/macOS execution and compatibility with moving upstream are unverified. Source documents and Xe records are trusted inputs. VALIDATION.md remains the detailed existing contract table.
