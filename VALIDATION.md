# Validation and practical limits

Run from the repository root with TeX Live (LuaLaTeX, XeLaTeX and texlua), Python,
Pillow, Poppler and Inkscape installed. `tools/Dockerfile` includes these dependencies.

| Contract | Check | Evidence boundary |
| --- | --- | --- |
| Original default paths are preserved | `texlua tools/layoutcheck.lua` | Three pinned upstream path fingerprints, plus layout controls. PDF metadata and document text are separate. |
| Reservations use physical coordinates | `python3 tools/offsetcheck.py` | Flooded artwork and Poppler-measured text positions; eight combinations of side, parity and positive/negative offsets. The baseline fails before the origin correction. |
| Lettering remains upright | `texlua tools/backendcheck.lua` | Physical left-to-right stroke-body comparison for Arabic and Roman labels; decorative curls may turn toward the paper edge. |
| Standalone rendering needs no TeX node host | `texlua tools/backendcheck.lua` | TeX host globals are removed; real primitive paths and transparency resources are produced. |
| Both engines share vector behavior | `python3 tools/enginecheck.py` | Ten real documents, exact paths for the primitive/authored/initial/animation cases, bounded raster differences, searchable labels, metadata, monochrome output, physical reservations, cached animation, reused PDF assets, stale rebuilds and rejected inputs. |
| Decorated font outlines really run | `python3 tools/enginecheck.py --require-outlines` | Required in full TeX Live CI; fails if the decorated initial falls back. A reduced local installation may run the ordinary checks using the documented fallback. |
| Animation ends on the normal drawing | `texlua tools/animcheck.lua 1 6` | Forty comparisons across seasons, reservations, layouts, Arabic/Roman labels and monochrome output. |
| SVG/PDF export stays vector and reuse works | `python3 tools/exportcheck.py` | No SVG raster nodes; transparent round-trip; a 48-repeat PDF size/render comparison. The measured saving is for repeated identical assets. |
| Reservations remain clear in the normal layout | `python3 tools/visualcheck.py` | Rendered book sides, callout, overlapping barriers and a full-page reservation. |
| Source kit works after extraction | `python3 tools/packagecheck.py` | Reproducible archive, SHA-256 manifest, and both engines building the kit's own template from a separate directory. |

`make check` also runs real LuaLaTeX option, KOMA/titlesec/hyperref and font-failure
checks. `make engine-check`, `make offset-check`, `make export-check` and
`make visual-check` expose the other integration checks separately.

## Limits

- Protected boxes are explicit and unbreakable. They do not automatically cover
  every float or support one box spanning multiple pages.
- A reservation that blocks every route can interrupt a clipped stem. The final
  clip prioritizes clear protected content over stem continuity.
- Botanical labels support Arabic digits and Roman-letter forms. Unsupported or
  too-wide labels, and label regions blocked by a reservation, are omitted with
  a warning. Keep a normal footer for such layouts. This package does not take
  over a class's page style or suppress a custom footer.
- Spread variation uses the document's logical even/odd page numbering. Text
  marks, reservations, seasons and label shapes still affect the resulting garden.
- Monochrome applies to newly rendered paths, not arbitrary colored document text
  or colors already embedded in an included PDF. Export a mono asset when needed.
  SVGs are checked with Inkscape; Office import is not tested here.
- The PostScript port retains its original capabilities. The new book controls,
  lettering and portable renderer are not automatically ported into it.
