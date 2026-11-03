// Run from the project root: python3 typst/build.py typst/example.typ --palette ultramarine
#import "limen.typ": limen, limen-threshold, limen-caustic

#show: limen
#set text(size: 10pt, lang: "en")
#set par(justify: true)
#set heading(numbering: "1.1")

#text(size: 20pt, weight: "bold")[How light earns its colour]

This document is set by Typst. The margin is drawn by the same Lua as in LaTeX and placed behind the page.

= Below the threshold
#lorem(320)

== What the margin shows
#lorem(260)

= The threshold
#limen-threshold()
From here the beam opens into a spectrum.
#lorem(420)

= Above it
#limen-caustic(kind: "rings")
#lorem(520)

== The spindles widen
#lorem(620)

= The end
#lorem(90)
