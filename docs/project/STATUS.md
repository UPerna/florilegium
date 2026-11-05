# Florilegium execution status

Stages 00–27 passed. Stage 28 remains in progress. Native build, all-family CLI and failure tests passed on 9f5af38, but artifact upload failed. Repair the exported evidence permissions and rerun CI.

Publish the evidence-copy permission repair as a fast-forward child of 9f5af38, independently fetch/verify it, rerun both native jobs, inspect artifacts and replay the native solver-cache on Windows. Stage 28 remains in progress until all gates pass; then start stage 29.
