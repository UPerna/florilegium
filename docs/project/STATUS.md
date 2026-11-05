# Florilegium execution status

Stages 00–28 passed. Stage 29 positive native gates pass at 9201a57; the expected-failure log matcher is being repaired.

Native 9201a57 produced the compact four-page book and passed all positive consumer gates, including nine measured placements (maximum error 0.000135785 cm), protected ink controls, searchable text, floats/spreads, four load orders and discarded-page identity. It correctly rejected an unknown asset; the test matcher then failed because TeX wrapped the word asset across lines. The repair matches complete expected phrases across whitespace, reads full failed-pass logs, requires compiler failure, and records failure-log hashes. Positive source behavior and all geometry tolerances are unchanged.

Publish the diagnostic-test repair as an ordinary child of 9201a57 and independently fetch/verify it. Rerun exact-head CI. Native positive book gates already pass: 9 placements at unchanged 0.01 cm, L-mask/control ink, full text, float/spread, 4 load orders, discarded-page identity and convergence. Complete all expected-failure/collision checks using full compiler logs, then verify inherited pdfs/portable jobs and final artifacts/visuals. Remain on 29 until every gate passes, then start 30 immediately.
