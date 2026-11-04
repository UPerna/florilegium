# Hershey Script Simplex

`scripts.jhf` is the Hershey Script Simplex font in James Hurt's format, the skeleton of the
letters in the GitHub social image (`tools/social.lua`, `make social`). It is not part of the
package and not in the CTAN zip.

It is copied unchanged from `hershey-fonts/scripts.jhf` in
[kamalmostafa/hershey-fonts](https://github.com/kamalmostafa/hershey-fonts) at commit
`1356bf2f83d380fcef68c887e88675eb9d445d86` (2018-01-01), whose notes give its source as
<http://emergent.unpythonic.net/software/hershey>. The font data is under its own terms, not
florilegium's MIT License, and read as follows in that repository's `hershey-fonts.notes`.

```
USE RESTRICTION:
	This distribution of the Hershey Fonts may be used by anyone for
	any purpose, commercial or otherwise, providing that:
		1. The following acknowledgements must be distributed with
			the font data:
			- The Hershey Fonts were originally created by Dr.
				A. V. Hershey while working at the U. S.
				National Bureau of Standards.
			- The format of the Font data in this distribution
				was originally created by
					James Hurt
					Cognition, Inc.
					900 Technology Park Drive
					Billerica, MA 01821
					(mit-eddie!ci-dandelion!hurt)
		2. The font data in this distribution may be converted into
			any other format *EXCEPT* the format distributed by
			the U.S. NTIS (which organization holds the rights
			to the distribution and use of the font data in that
			particular format). Not that anybody would really
			*want* to use their format... each point is described
			in eight bytes as "xxx yyy:", where xxx and yyy are
			the coordinate values as ASCII numbers.
```

Each line of the file is one character, ASCII 32 to 126 in order: the glyph number (5
columns), the number of coordinate pairs (3), then the pairs, the left and right bounds
first. A coordinate is its character's code minus that of `R`, y grows downward, and ` R`
lifts the pen.
