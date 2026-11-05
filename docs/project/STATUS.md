# Florilegium execution status

Stages 00–27 passed. Stage 27 CI 42003202966 accepted on d840207.

Stage 28 local acceptance passed. The fixed-source local public CLI suite accepted all 22 supported families. Each was validated, generated, structurally checked, exported and replayed with identical instance/PDF/SVG bytes. The suite checked physical page dimensions and searchable micrography with the explicit local pypdf reader. Nineteen Windows failure/path checks passed, including junctions, hardlinked locks, partial batch repair, damaged output recovery, cancellation limits and concurrent destinations. Seventeen shared replay/cross-host invariants passed on both local Lua versions. The previous native split-Escher cache passes the existing numerical policy. Native CI pending.

Publish the exact stage 28 manifest from d840207, independently fetch and verify its tree, then verify both native jobs, the Linux consumer/failure suite, all exports and the packaged CLI. Continue to stage 29 after acceptance.
