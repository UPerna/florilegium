# Quality-control review — 31 October 2026

Review baseline: `d5996fde2d44c5ccec0eafa04e403545b47791e5`, against the fork's
upstream base `138f9f2603736eba8ea9014b33b381bdd5a503f5`.
Changes and final execution receipts are attached to
[PR #1](https://github.com/UPerna/florilegium/pull/1).

## Confirmed findings and repairs

| Severity | Trigger and observed consequence | Repair and regression |
| --- | --- | --- |
| Medium | An included chapter changed its own `.aux` while the main auxiliary file stayed stable. Both engines returned a PDF displaying state 1 while the chapter had written state 2. | Build with TeX's file recorder and track recorded auxiliary outputs. Both engines must produce the settled value; a continuously changing chapter must fail at the configured pass limit. |
| Medium | The bee's dotted flight trail was cut off, including at the default export size for some seeds. At maximum size the rosette's line ends touched the page boundary. | Expand the motif-specific canvases shared by the native and reference exporters. Render 35 alpha-boundary cases across all 11 exportable motifs and representative seeds/sizes. |
| Low | The source archive omitted `gallery/printed.jpg`, leaving a broken image in its README. | Include JPEG previews and check every local README image after extraction, alongside file hashes and reproducibility. |
| Low, pre-existing example | The specimen's old font setup yielded a control character in place of the `fl` ligature during native PDF text extraction; its indentation also caused a 15.4 pt overfull line. | Use Latin Modern and an explicit picture bounding box without paragraph indentation. Include the all-primitive sheet in both build jobs; verify normalized Unicode labels and exact cross-engine illustration streams. |

Confidence is high for these findings: each has a concrete failing output and a
consumer-level confirmation of the repair. No drawing primitives or default
composition paths were changed by these repairs.

## Review and checks

- Traced the public TeX controls through validation, geometry, reservations,
  fonts, folios, native/standalone drawing sinks, Xe records and PDF resources.
- Inspected build convergence, stale rebuilds, error paths, source packaging,
  documentation and CI permissions. CI now explicitly uses `contents: read` and
  disables persisted checkout credentials in all three jobs. This follows
  [GitHub's workflow permission model](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions).
- Probed 1,056 motif/seed/size combinations with conservative path bounds. Such
  bounds include internally clipped washes, so visual alpha tests determined
  the actual crop findings.
- Rendered A5 outer margins, US Letter inner margins, landscape A4 right margins
  and a small A6 page with maximum custom focal settings in both engines. Text
  remained present; mean raster differences were 0.1069, 0.0530, 0.0528 and
  0.1971 out of 255. Reviewed the resulting contact sheet visually.
- Verified all 19 gallery image structures. The legacy PostScript port is checked
  separately with Ghostscript; the new Lua/Xe features remain outside that port.
- Required release checks remain the three upstream default fingerprints,
  28 layout checks, 22 native option cases, nine book/class cases, eight physical
  offset cases, 40 animation comparisons, 11 dual-engine documents, six rejected
  Xe inputs, full decorated outlines, export/visual checks and extracted source-kit
  builds in both engines. The recorder regression also checks bounded failure.

The local TeX installation uses its documented plain-initial fallback. The portable
CI job requires real outlines with `--require-outlines`; its result is part of the
final PR check record. Local Python and Lua syntax checks also run.

## Scope and remaining limits

This is a Linux/TeX Live review. Native Windows/macOS execution and SVG import in
Microsoft Office are unverified. Explicit unbreakable protection, class-controlled
footers, unsupported botanical labels and blocked stem routes retain the limits
in [VALIDATION.md](VALIDATION.md). Source documents and generated Xe records are
trusted build inputs; the workflow is not an untrusted-document sandbox.

Upstream advanced during this review to
[`fb253ea`](https://github.com/kevinraymond/florilegium/commit/fb253eaecb1d0bafbc3f32c43a66d4e074b6fc3a),
adding themes, intensity controls, text ornaments and other changes. Compatibility
with that newer implementation needs a separate integration review. Default-path
claims here remain pinned to the recorded upstream base.
