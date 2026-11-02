# Florilegium execution status

Stage 00 in progress: replacement baseline approved by user after original delivery was confirmed lost. Original 96545fa was not recovered or published.

Verified baseline: dd8ee951523072d4eca414e4bdfd9dff57cee8b0; tree 8fd03004ae5aae37bcf3e6d5ea4ecf9139411ae7. All 99 blob hashes verified, including binary SHA-256 manifest. Clean full Git clone at work/florilegium. Existing CI build #10 passed for exactly this baseline, PR #1. No pre-existing checkout was modified.

Current action: publish this checkpoint with expected-head protection, independently verify resulting commit/tree and current CI. Then mark stage 00 passed under the user-approved amendment and begin stage 01. Stages 01–39 remain pending.

CLI HTTPS requires existing system proxy settings and per-command OpenSSL TLS backend; no certificate validation was disabled and no global configuration changed. Python 3.12.14 and Poppler available; TeX engines, Lua, Inkscape, Docker and Make were not found on PATH. Local baseline tests remain unrun. Preserve that limitation until dependencies or equivalent exact-revision CI evidence establish each check.
