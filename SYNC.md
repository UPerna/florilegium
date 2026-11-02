# Repository synchronization record

Verified 2 November 2026.

## Published baseline

- Repository: [UPerna/florilegium](https://github.com/UPerna/florilegium).
- Default branch `main`: `138f9f2603736eba8ea9014b33b381bdd5a503f5`.
- Development branch `improve/layout-controls`: `e795c2513b2eb2eb7aa1f0558c18b9236983dcc2`.
- [PR #1](https://github.com/UPerna/florilegium/pull/1) is open against main.
- [Build #8](https://github.com/UPerna/florilegium/actions/runs/41183516215) completed successfully for that development commit. This is existing CI evidence, not a new local test run.
- The development commit's tree is `1756d4daf45c21741da4d4a83580b89f1f19dfd7`.

These references describe the baseline before this documentation update.

## Unrecovered work

An earlier conversation reported an additional local commit, abbreviated
`96545fa`, and another checkout with uncommitted changes. GitHub's commit lookup
returned “No commit found” for that abbreviation on this verification date.
The current desktop workspace contains no repository checkout.

The earlier local changes are therefore **unrecovered**. Their contents, full
commit identifier and test results cannot be established from the available
repository. Do not reconstruct them from a short SHA or describe them as published.
Recovery requires the original checkout, a Git bundle, patch or source archive.
Compare any recovered work against the published baseline before applying it.

## Publication procedure

1. Read the target branch head and record its full SHA.
2. Prepare one coherent change against that tree; preserve unchanged files.
3. Inspect the diff and run the checks appropriate to that change.
4. Publish a commit, preserving existing history. For Git database publication,
   create blobs, a tree based on the existing tree, and a commit with the recorded
   head as parent; update the branch with an expected-head guard.
5. Read the remote head and changed files back. After a timeout, inspect remote
   state before retrying. If another writer advanced the branch, reconcile first.
6. Record publication and test status separately. A successful upload is not
   evidence that CI passed.

Keep source changes small. Deliver generated galleries and archives through the
existing artifact workflow. Integrating newer upstream changes is a separate
task from recovering unpublished work.
