# Seeded vector assets

These flower, leaf and butterfly files were generated with `tools/exportasset.py`
from the MIT-licensed florilegium primitives. Each pair contains a vector PDF and
a plain SVG on the same transparent 6 cm canvas. Seed: 7; ink: `2456C4`.
Sizes: flower 1.2, leaf 2.0, butterfly 1.4.

To regenerate a pair from the repository root:

```sh
python3 tools/exportasset.py flower --seed 7 --size 1.2 --output examples/assets/flower
```

Use the SVG in a vector editor or a slide application. For repeated decoration
inside LuaLaTeX, declare the PDF once and reuse it:

```tex
\florilegiumdeclareasset{flower}{examples/assets/flower.pdf}
\florilegiumuseasset[width=18mm]{flower}
```

The native PDF inclusion reuses a Form XObject; it does not repeat the full path
stream for each occurrence. The files have no external image dependencies.
