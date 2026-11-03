// limen for Typst: page margins where light has to earn its colour. Part of limen, MIT License.
//
// Typst cannot run the drawing code, so the art is drawn outside and placed as a page background:
//
//   python3 typst/build.py report.typ
//
// build.py reads the marks left by this file with `typst query`, draws one SVG per page with limen-svg.lua and
// compiles the document with them. Without build.py the document still compiles, just without art.
//
//   #import "limen.typ": limen, limen-threshold, limen-star, limen-caustic, limen-end
//   #show: limen.with(margin: (left: 58mm, right: 17mm, top: 30mm, bottom: 29mm))

// A mark remembers where it landed. Reading it back is what `typst query` is for.
#let limen-mark(kind, arg: none) = context {
  let p = here().position()
  [#metadata((kind: kind, arg: arg, page: p.page, y: p.y / 1pt)) <limen-mark>]
}

#let limen-threshold() = limen-mark("threshold")
#let limen-star() = limen-mark("star")
#let limen-caustic(kind: "ellipse") = limen-mark("caustic", arg: kind)
#let limen-end() = limen-mark("end")

// the page where the night field runs under the footer; build.py passes it in, and the footer turns white there
#let limen-lake-page = int(sys.inputs.at("limen-lake", default: "0"))

#let limen(margin: (left: 58mm, right: 17mm, top: 30mm, bottom: 29mm), paper: "a4", footer-fill: gray, doc) = {
  // Everything is measured against the sheet, so the sheet and the margins are read back by build.py too.
  set page(paper: paper, margin: margin,
    background: context {
      let dir = sys.inputs.at("limen-art", default: none)
      if dir != none { image(dir + "/page-" + str(here().page()) + ".svg", width: 100%, height: 100%) }
    },
    footer: context {
      let fill = if here().page() == limen-lake-page { white } else { footer-fill }
      align(right, text(size: 8pt, fill: fill, counter(page).display()))
    })
  show heading: it => {
    limen-mark("heading", arg: it.level)
    it
  }
  context {
    let w = page.width / 1cm
    let h = page.height / 1cm
    let m(side) = margin.at(side) / 1cm
    [#metadata((kind: "sheet", width: w, height: h, left: m("left"), right: m("right"), top: m("top"), bottom: m("bottom"))) <limen-mark>]
  }
  doc
  limen-mark("textend")
}
