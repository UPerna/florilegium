# Florilegium execution status

Stages 00–28 passed. Stage 29 remains in progress; 200db9a native book placement failed and is being corrected.

Native run 42044636324 built and converged the five-page book, passed 35 adapter checks and the lookup regression, then correctly rejected background placement errors of 0.3 cm horizontally / 0.2 cm vertically. All native inline positions were independently measured within 0.00014 cm. The correction cancels inherited picture-origin offsets; foreground callout coordinates use the same physical convention. Local lookup regressions pass on both Lua versions. Book asset views trim only blank canvas beyond conservative paint bounds, preserving source designs; native text/visual recheck remains required.

Publish the offset correction as a guarded child of 200db9a, independently fetch/verify it, then rerun all exact-head CI. Native book already builds/converges, but the physical placement gate rejected inherited custom offsets. Preserve 0.01 cm tolerance. Verify corrected background/foreground origins, complete text after source-preserving canvas trims, mask controls, floats, spreads, load orders, failures, convergence, inherited PDF/portable jobs and final book visuals before stage 30.
