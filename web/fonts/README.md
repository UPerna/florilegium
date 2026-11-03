# Fonts of the playground

Subsets (Latin, the punctuation the page uses) in WOFF2, served with the site so no
font request leaves it.

| file | font | license |
|---|---|---|
| `fell.woff2`, `fell-italic.woff2`, `fell-sc.woff2` | IM FELL DW Pica (roman, italic, small caps), Igino Marini's revival of the Fell types, from google/fonts ([roman and italic](https://github.com/google/fonts/tree/main/ofl/imfelldwpica), [small caps](https://github.com/google/fonts/tree/main/ofl/imfelldwpicasc)) | SIL Open Font License 1.1 (no Reserved Font Name), `OFL.txt` |
| `lmroman.woff2`, `lmroman-italic.woff2`, `lmroman-bold.woff2`, `lmmono.woff2` | Latin Modern Roman 10 and Mono 10 (GUST e-foundry), from TeX Live, subset and renamed Florilegium Roman and Florilegium Mono, as the license asks of modified versions | GUST Font License, `GUST-FONT-LICENSE.txt` |

Made with fonttools: `pyftsubset <font> --unicodes=U+0020-007E,U+00A0-00FF,U+2013-2014,U+2018-201D,U+2022,U+2026,U+2039-203A,U+00B7,U+2192,U+00D7 --layout-features=kern,liga,onum,smcp,c2sc --flavor=woff2`.
