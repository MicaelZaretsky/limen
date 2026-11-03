# limen

Page margins where light has to earn its colour, drawn by Lua. LuaLaTeX only, LaTeX from October 2020 or later.

The margin holds a night field, fine lines of equal phase and one beam. At every heading the beam closes into a white star;
between headings it opens into a spectrum. On the first pages the beam is thin and almost white. After a threshold, which you
can place in the text with `\limenthreshold`, it grows until the full spectrum leaves through the edge of the sheet on the
last page. Everything is computed while the page ships and written straight into the PDF: no images, no external files.

    \usepackage[palette=ultramarine]{limen}

Run LuaLaTeX twice, as for a table of contents.

- `limen-guide-en.pdf`: the guide, in English. `limen-guide.pdf`: the same in Russian.
- `limen-svg.lua`: the same art without TeX, as an SVG page, for Typst and other tools.

The sources of the guides need the fonts and pictures kept in the repository. The repository also has examples, tests, a
Typst wrapper and a page for choosing a palette in the browser.

The idea of drawing margins in Lua, the page geometry and the search for marks in the page box come from florilegium by
Kevin Raymond (MIT). MIT License, see `LICENSE`.
