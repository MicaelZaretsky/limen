# Changelog

## 0.2, November 2026

- `beam=mono`, `wavelength`: one colour, like a real laser.
- Kinds of caustics: `cardioid`, `nephroid`, `rings`, `speckle`, `mix`; `\limencaustic[kind=...,size=...]`.
- Several `\limenthreshold` make steps.
- `color=cmyk`, `bleed`: for a print shop, with TrimBox and BleedBox. All art is marked as an Artifact for tagged PDFs.
- `limen-svg.lua`, a Typst wrapper and a page for the browser, all on the same drawing code.
- `sameart` and a growth animation. An English guide. `l3build ctan`. GitHub workflows for three systems.
- Fixed: no stars at headings with current KOMA-Script, with memoir sections, and in tagged documents. The tests now count them.
- Fixed: the bundled Lora fonts are now the project's own unmodified files, as their Reserved Font Name requires.
- A star now always means a heading or a mark in the text; on a long stretch without one the beam only narrows.
- Pages carry a transparency group, so that the viewer does not choose the colour space for blending.
- `make print-test`: one A4 sheet for checking a printer, `doc/limen-print-test.pdf`.
- Fixed: after `make doc`, the Russian example stopped on a clean font cache, because the guide had left its relative font path
  there. All documents of the project now name their fonts the same way, and `\limeninitial` warns about this trap.
- Tested on a clean TeX Live 2026, built on GitHub on Linux, macOS and Windows, and looked over in Adobe Acrobat on Windows.

## 0.1, November 2026

First version.

- Page margins: night field, lines of equal phase, dispersed beam, stars at headings, caustics, closing fan.
- The threshold story: `threshold`, `\limenthreshold`, `story=flat`, `story=chapter`, `\limenlevel`, `\limenend`.
- Six palettes and `\limendefinepalette`.
- `mode=paper` for office printers, `\limencover`, `\limeninitial`, `\limenrule`, `\limenspark`, `\limenspectrum`.
- Slides: beamer is detected, overlays of one frame share one picture.
- Tests (`make test`), a renderer comparison (`tools/crosscheck.py`), a guide in Russian.
