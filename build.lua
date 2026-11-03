-- build.lua: l3build configuration for the CTAN package. `l3build ctan` writes build/distrib/limen-ctan.zip.
-- Before uploading, fill in `author` below and check that the name limen is still free on https://ctan.org/pkg/limen .

module = "limen"
tdsroot = "lualatex"
packtdszip = false

sourcefiledir = "."
sourcefiles = { "limen.sty", "limen.lua", "limen-art.lua", "limen-pdf.lua", "limen-palettes.lua", "limen-svg.lua" }
installfiles = sourcefiles
unpackfiles = {}

docfiledir = "doc"
docfiles = { "limen-guide.tex", "limen-guide-en.tex", "limen-guide-common.tex" }
typesetfiles = { "limen-guide-en.tex", "limen-guide.tex" }
typesetexe = "lualatex"
typesetruns = 3

textfiles = { "LICENSE", "CHANGELOG.md", "README-CTAN.md" }
ctanreadme = "README-CTAN.md"

-- the guides are set in fonts and show pictures that do not belong on CTAN, so they are copied only for typesetting
function docinit_hook()
  mkdir(typesetdir .. "/fonts")
  mkdir(typesetdir .. "/gallery")
  cp("*.*", "doc/fonts", typesetdir .. "/fonts")
  cp("*.png", "gallery", typesetdir .. "/gallery")
  cp("hyph-ru.*", "doc", typesetdir)
  return 0
end

uploadconfig = {
  pkg = "limen",
  version = "0.2 2026-11-03",
  author = "the limen contributors",
  license = "mit",
  summary = "Page margins where light has to earn its colour, drawn by Lua",
  description = [[Page margins for LuaLaTeX: a night field, lines of equal phase and a beam that closes into a white star at
    every heading and opens into a spectrum between them. The beam starts thin and almost white and grows after a threshold,
    which the author can place in the text, until the full spectrum leaves through the edge of the sheet on the last page.
    Everything is computed in Lua and written straight into the PDF. Six palettes, a printer mode, covers, slides.]],
  topic = { "decoration", "luatex", "physics" },
  ctanPath = "/macros/luatex/latex/limen",
  repository = "https://github.com/MicaelZaretsky/limen",
  bugtracker = "https://github.com/MicaelZaretsky/limen/issues",
  update = false,
}
