# Common pattern architecture

Design direction captured from the project discussion. **Proposed; not implemented
by this document.** Existing floral rendering remains the compatibility baseline.
See [SYNC.md](SYNC.md) for publication and recovery status and
[VALIDATION.md](VALIDATION.md) for current implementation limits.

## Separate construction, views and appearance

A persistent pattern instance describes the construction. A document view selects
a region of that instance. Materials turn its structure into a drawable scene.
Page resizing should reveal more of the same instance rather than regenerate
previously visible tiles.

| Contract | Responsibility |
| --- | --- |
| Design specification | Physical regions, reservations, guides, anchors, family, style, seed and resource limits |
| Pattern definition | Prototiles or motifs, construction rules, allowed transformations and declared capabilities |
| Pattern instance | Stable element identities, geometry, topology and construction parameters/history |
| Document view | Page or spread window, placement and clipping, retaining source identities |
| Drawable scene | Paths, strokes, fills, layers, clips, symbols and positioned text |
| Build record | Inputs, versions, fonts, random streams, limits, validation outcomes and output hashes |

Represent strand crossings, tile adjacency, shared boundaries and text order
explicitly. Anonymous paths cannot substitute for this structure. Shared edges
must support subdivisions. Prefer exact family coordinates for identities where
practical; record physical tolerances for numerical geometry and rendering.

## Core and adapters

Start with the existing portable Lua renderer. Extract narrow interfaces gradually
around geometry, transforms, regions, spatial queries, random streams and drawing
resources. Keep LuaLaTeX and XeLaTeX as document adapters. A browser worker is a
future adapter to the same core, with support declared per engine.

Generators construct patterns; a composition planner allocates regions and anchors;
validators check structure and clearances; materials produce drawing instructions;
renderers export them. Candidate generation must be transactional: failed or
cancelled proposals leave accepted work intact.

Use named random streams and stable identities. Recoloring must preserve geometry.
Separate geometry and appearance caches. Preview and print should use the same
placement, with independently adjustable rendering detail.

Document adapters supply settled page geometry, explicit protected regions and
anchors. Preserve searchable text, font identity and reading order. Clipping is a
final protection step, accompanied by family checks for severed strands or
incomplete structural elements.

## Engine families

| Family | Structure and required checks |
| --- | --- |
| Growth and grammars | Branch connections, continuity and permitted regions |
| Interlacing | Strand graph, crossing order and closure |
| Geometric ornament | Compatible boundaries, rosette relationships and symmetry |
| Aperiodic tilings | Recorded construction, adjacency, overlap/gap checks and permitted transformations |
| Packing and mosaics | Separation, coverage, orientation and gaps |
| Mazes | Connectivity, reachability and specified paths |
| Fields and stroke synthesis | Direction, spacing and regional boundaries |
| Typography | Shaping, reading order and preservation of source text |
| Example synthesis and shape optimization | Method-specific constraints, fidelity and bounded solver outcomes |
| Architectural construction | Dedicated geometry and assembly validation, including 3D where needed |

These are extension targets, not claims of supported features or reproductions
of published methods. Each implementation needs a source and license review,
construction description, reproduction examples and explicit deviations.

## Aperiodic requirements

Support hierarchical substitution and projection/multigrid constructions through
separate interfaces. Constraint-based experiments need bounded search with explicit
success, failure and unresolved results.

For Penrose and Ammann–Beenker, record the tile forms and chosen construction,
including hierarchy or projection-window/phase data and boundary decisions.
For hat and Spectre, record metatile history and permitted handedness. Reflection
must be a declared capability; page-side mirroring cannot silently change chirality.
Select and document a published construction before implementation.

Crop a sufficiently large legal patch to a view. Clipped fragments keep their
parent identity. Whole-tile exact fitting is a separate constraint that may fail.
Facing pages declare whether they use adjacent windows, coordinated variants or
independent instances.

A finite drawing does not prove aperiodicity. Record construction provenance and
implementation checks separately from the mathematical theorem for the family.
Repeating strips made from aperiodic tile shapes require a separate classification.

## Small implementation steps and acceptance gates

1. **Recover the baseline.** Resolve the unrecovered work in SYNC.md when original
   sources become available. Preserve the currently published branch meanwhile.
2. **Introduce contracts.** Add versioned Lua data contracts and one floral adapter.
   Require the existing three default path fingerprints and relevant engine checks.
   Avoid rewriting the entire generator in this step.
3. **Exercise different structures.** Add individual Celtic, Islamic geometric,
   Penrose and Spectre demonstrations in separate changes. Together with flowers,
   these are the architecture acceptance set. Each needs family validation and a
   rendered example before broadening its scope.
4. **Verify instance stability.** Test adjacent views, expanded viewports, recoloring,
   reflection restrictions, stable IDs and deterministic bounded cancellation.
5. **Broaden construction coverage.** Add Ammann–Beenker and hat, then mixed
   compositions, browser controls, packing, mazes, strokes and typography.
6. **Add expensive methods.** Evaluate example synthesis, Escher optimization and
   3D construction with method-specific reproductions and resource measurements.

Each step should have a coherent commit, an inspected diff, appropriate checks and
a verified remote SHA. Report prepared, published, tested and released states
separately. Stop expanding a step when its acceptance gate fails; retain evidence
and resolve that failure before adding another engine.
