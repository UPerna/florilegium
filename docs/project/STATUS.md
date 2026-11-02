# Florilegium execution status

Stages00–05 passed. Stage06 in_progress. Initial07f3fdb (treed8529318, parent814d772) was independently verified and CI41502953750 passed both jobs, including196 source-kit hashes. Visual inspection then rejected a clipped multiply mismatch in Inkscape1.4.2; this green CI is not a stage pass.

Isolated work/stage06-followup corrects SVG per-paint blend placement and adds an analytic interior-color check. Both local Lua runtimes pass44 scene checks; independent librsvg/Poppler checks pass source digestcad26079ee23ce1e6c8103dce7940fbd11c7bb42a0aea2e4c620081052e47618. Next: publish follow-up with expected07f3fdb, independently verify exact files/tree, run exact-head required CI and inspect its images. Only then mark06 passed and immediately begin07 through39.

Preserve all dirty worktrees, initial stage06 bundles and original PR1. Draft PR2 stays open; no merge/release/deploy before39. Lost96545fa was replaced by verifieddd8ee95 only under explicit user amendment. Native Windows TeX remains unavailable; Linux gates are mandatory.
