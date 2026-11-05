# Traits

The traits a species and a visitor are sampled with, in the order they are drawn, and what
each may be fixed to: one of the names listed, or a number in the range given (a whole
number where it says so). Fix them with `\florilegiumspecies[...]`, `\florilegiumvisitor[...]`
or a pic's `traits` key; [the TikZ library](tikz.md#a-genome-of-your-own) shows how. `clade` and
`group` follow from the plan and the kind and are not fixed themselves.

This page is written by `tools/tikztables.lua` from `florilegium-species.lua`.

## A species

| trait | what it may be |
|---|---|
| `plan` | `borage`, `catkin`, `columbine`, `daisy`, `eudicot`, `fern`, `heath`, `iris`, `lily`, `mint`, `monocot`, `mustard`, `pea`, `rose`, `umbellifer` |
| `syndrome` | `bee`, `beetle`, `bird`, `butterfly`, `fly`, `moth`, `none`, `wind` |
| `color` | `blue`, `green`, `orange`, `pink`, `red`, `violet`, `white`, `yellow` |
| `form` | `bilabiate`, `campanulate`, `cruciform`, `funnelform`, `head`, `iris`, `lily`, `none`, `orchid`, `papilionaceous`, `rosaceous`, `rotate`, `salverform`, `spurred`, `tubular`, `urceolate` |
| `symmetry` | `bilateral`, `none`, `radial` |
| `fused` | a whole number from 0 to 1 |
| `merosity` | a whole number from 0 to 21 |
| `merovar` | a whole number from 0 to 1 |
| `petalshape` | `lanceolate`, `linear`, `none`, `oblong`, `obovate`, `orbicular`, `spatulate` |
| `petalaspect` | a number from 0.9 to 6 |
| `apex` | `acuminate`, `acute`, `bifid`, `emarginate`, `fringed`, `none`, `rounded` |
| `petalmargin` | `crenate`, `entire`, `fimbriate`, `laciniate`, `none`, `undulate` |
| `petalamp` | a number from 0 to 0.06 |
| `claw` | a number from 0 to 0.5 |
| `reflex` | a number from -80 to 30 |
| `overlap` | a number from 0 to 0.4 |
| `cup` | a number from 0 to 1 |
| `guides` | `blotch`, `dots`, `eye`, `lines`, `none` |
| `guidecount` | a whole number from 0 to 6 |
| `picotee` | a whole number from 0 to 1 |
| `corona` | `cup`, `none`, `trumpet` |
| `spurs` | `all`, `none` |
| `stamens` | `exserted`, `included`, `none` |
| `orient` | `erect`, `horizontal`, `nodding` |
| `inflo` | `catkin`, `corymb`, `cumbel`, `dichasium`, `head`, `monochasium`, `none`, `panicle`, `raceme`, `solitary`, `spike`, `thyrse`, `umbel` |
| `count` | a whole number from 0 to 80 |
| `rays` | a whole number from 0 to 20 |
| `depth` | a whole number from 0 to 3 |
| `openorder` | `base`, `center`, `none`, `outside` |
| `siderule` | `alternate`, `none`, `same` |
| `coil` | a number from 0 to 1 |
| `size` | a number from 0 to 90 |
| `compound` | `bipinnate`, `frond`, `palmate`, `pinnate`, `simple`, `trifoliate` |
| `leaflets` | a whole number from 0 to 9 |
| `leafshape` | `cordate`, `deltoid`, `elliptic`, `hastate`, `lanceolate`, `linear`, `oblong`, `obovate`, `orbicular`, `ovate`, `reniform`, `sagittate` |
| `leafaspect` | a number from 0.6 to 20 |
| `leafmargin` | `crenate`, `dentate`, `doubly`, `entire`, `lobed`, `palmatelobed`, `pinnatifid`, `serrate`, `undulate` |
| `teeth` | a whole number from 0 to 28 |
| `dissection` | a number from 0 to 0.92 |
| `leafapex` | `acuminate`, `acute`, `emarginate`, `mucronate`, `obtuse`, `rounded` |
| `leafbase` | `auriculate`, `cordate`, `cuneate`, `oblique`, `rounded`, `truncate` |
| `venation` | `arcuate`, `forked`, `palmate`, `parallel`, `pinnate` |
| `attachment` | `clasping`, `none`, `petiolate`, `sessile`, `sheathing` |
| `stipules` | `leafy`, `none`, `small` |
| `arrangement` | `alternate`, `crown`, `distichous`, `opposite`, `rosette`, `whorled` |
| `curl` | a number from -0.3 to 0.6 |
| `twist` | a number from 0 to 50 |
| `taper` | a number from 0.4 to 1 |
| `turns` | a whole number from 0 to 1 |
| `habit` | `climbing`, `erect`, `sprawling`, `woody` |
| `section` | `prickly`, `ribbed`, `round`, `square` |
| `hairy` | a whole number from 0 to 1 |
| `tendrils` | a whole number from 0 to 1 |
| `fruit` | `achene`, `berry`, `capsule`, `drupe`, `follicle`, `hip`, `legume`, `nut`, `nutlets`, `pappus`, `pome`, `samara`, `schizocarp`, `silicle`, `silique`, `spores` |
| `phenology` | a number from -0.15 to 0.15 |
| `division` | a whole number from 0 to 3 |
| `pinnae` | a whole number from 0 to 26 |
| `outline` | `deltoid`, `lanceolate`, `none`, `oblong`, `ovate` |
| `stipe` | a number from 0 to 0.4 |
| `sori` | `dots`, `lines`, `marginal`, `none` |
| `dimorphic` | a whole number from 0 to 1 |

## A visitor

| trait | what it may be |
|---|---|
| `kind` | `beetle`, `bird`, `bumblebee`, `butterfly`, `caterpillar`, `damselfly`, `dragonfly`, `hawkmoth`, `honeybee`, `hoverfly`, `hummingbird`, `ladybird`, `moth`, `snail`, `solitarybee` |
| `size` | a number from 4 to 140 |
| `tone` | a number from 0.26 to 0.5 |
| `ground` | `copper`, `dark`, `ink`, `pale` |
| `pose` | `closed`, `cross`, `curl`, `flat`, `fly`, `folded`, `glide`, `hover`, `loop`, `open`, `perch`, `rest`, `spread`, `straight`, `tent`, `visit`, `walk` |
| `apex` | `angular`, `falcate`, `pointed`, `rounded` |
| `wingedge` | `scalloped`, `smooth`, `toothed` |
| `tails` | a whole number from 0 to 2 |
| `basal` | a whole number from 0 to 1 |
| `central` | `band`, `none`, `spots` |
| `discal` | a whole number from 0 to 1 |
| `border` | `band`, `eyes`, `none`, `spots` |
| `eyes` | a whole number from 0 to 7 |
| `rings` | a whole number from 0 to 3 |
| `parafocal` | a whole number from 0 to 1 |
| `lunules` | a whole number from 0 to 2 |
| `veins` | a whole number from 0 to 1 |
| `antenna` | `clubbed`, `comb`, `elbowed`, `feathery`, `short`, `thread` |
| `bands` | a whole number from 0 to 8 |
| `hair` | a number from 0 to 1 |
| `pollen` | a whole number from 0 to 1 |
| `build` | a number from 0.1 to 0.9 |
| `paletail` | a whole number from 0 to 1 |
| `tint` | `clear`, `tinted` |
| `stigma` | a whole number from 0 to 1 |
| `pattern` | `plain`, `spots`, `stripes` |
| `spots` | a whole number from 0 to 22 |
| `spotsize` | a number from 0 to 0.2 |
| `stripes` | `back`, `none`, `side` |
| `tufts` | a whole number from 0 to 1 |
| `horn` | a whole number from 0 to 1 |
| `whorls` | a number from 3.5 to 6 |
| `expansion` | a number from 1.6 to 3.2 |
| `spire` | a number from 0.1 to 1.2 |
| `hand` | `dextral`, `sinistral` |
| `shellbands` | a whole number from 0 to 5 |
| `lip` | a whole number from 0 to 1 |
| `extension` | a number from 0.4 to 1 |
| `bill` | `conical`, `curved`, `straight` |
| `crest` | a whole number from 0 to 1 |
| `tail` | a number from 0.3 to 0.5 |
| `aperture` | a number from 0.85 to 1.3 |
| `suture` | a number from 0.15 to 0.8 |
| `sculpture` | `cords`, `ribs`, `smooth` |
| `ribs` | a whole number from 0 to 24 |
| `opencoil` | a whole number from 0 to 1 |
| `withdrawn` | a whole number from 0 to 1 |
