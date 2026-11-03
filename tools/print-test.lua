-- print-test.lua -- the pieces of the print test sheet: real limen art at its real size, plus lines and ramps to measure.
-- Part of limen, MIT License. See LICENSE. Used by print-test.tex.

local Art = require("limen-art")
local Pdf = require("limen-pdf")
local palettes = require("limen-palettes")

local T = {}
local SP = 72.27 * 65536 / 2.54   -- scaled points per cm
local sin, floor = math.sin, math.floor

local function put(cv, w, h)
  node.write((tex.useboxresource(cv:form(floor(w * SP), floor(h * SP)))))
end

-- a whole A4 page of art, to be cropped in TeX; the layout is the one of the examples, left margin 58 mm
function T.art(s)
  local o = Art.defaults()
  o.headrule = false
  for k, v in pairs(s.o or {}) do o[k] = v end
  local pal = palettes[o.palette]
  Art.configure(o, pal)
  local g = { pw = 21, ph = 29.7, u = 1, bleed = 0, textleft = 5.8, textright = 19.3, ytop = 26.7, ybot = 2.9, colright = 5.4 }
  if s.lake then
    g.closing, g.lake, g.textend = true, true, s.lake
  end
  local S = Art.make_story(1, g.ph, o, { pages = 1 }, s.level)
  put(Art.page(g, S, pal, o, s.marks or {}, Art.seed_for(o, s.page or 5)), 21, 29.7)
end

-- rows of wavy lines: each width at each opacity. On the night field, or on paper in the dark ink.
local WIDTHS = { 0.2, 0.3, 0.38, 0.5, 0.75, 1.0 }
local OPACITIES = { 0.3, 0.5, 0.7, 0.88, 1 }
function T.lines(w, h, night, palette)
  local pal = palettes[palette or "ultramarine"]
  Art.configure(Art.defaults(), pal)
  local cv = Pdf.canvas()
  if night then
    cv:poly({ { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }, true)
    cv:fill(pal.deep)
  end
  local colour = night and pal.line or pal.ink
  local cols, rows = #OPACITIES, #WIDTHS
  for r, lw in ipairs(WIDTHS) do
    local y = h * (rows - r + 0.5) / rows
    for c, op in ipairs(OPACITIES) do
      local x0, x1 = w * (c - 1) / cols + 0.12, w * c / cols - 0.12
      local pts = {}
      for k = 0, 40 do
        local t = k / 40
        pts[k + 1] = { x0 + (x1 - x0) * t, y + 0.07 * sin(t * 12.566) }
      end
      cv:poly(pts)
      cv:stroke(colour, lw, op)
    end
  end
  put(cv, w, h)
end

-- thin white beams on the night: whether ink spreads over them
function T.white(w, h, palette)
  local pal = palettes[palette or "ultramarine"]
  Art.configure(Art.defaults(), pal)
  local cv = Pdf.canvas()
  cv:poly({ { 0, 0 }, { w, 0 }, { w, h }, { 0, h } }, true)
  cv:fill(pal.deep)
  for r, lw in ipairs(WIDTHS) do
    local x = w * (r - 0.5) / #WIDTHS
    local pts = {}
    for k = 0, 30 do
      local t = k / 30
      pts[k + 1] = { x + 0.06 * sin(t * 9.42), h * t }
    end
    cv:poly(pts)
    cv:stroke({ 1, 1, 1 }, lw)
  end
  put(cv, w, h)
end

-- a smooth ramp between colours: banding shows here first
function T.ramp(w, h, stops)
  Art.configure(Art.defaults(), palettes.ultramarine)
  local cv = Pdf.canvas()
  local n = 96
  local a, b = {}, {}
  for i = 0, n do
    local t = i / n * (#stops - 1)
    local k = math.min(#stops - 2, floor(t))
    local f = t - k
    local p, q = Pdf.hex(stops[k + 1]), Pdf.hex(stops[k + 2])
    local r, g, bl = p[1] + (q[1] - p[1]) * f, p[2] + (q[2] - p[2]) * f, p[3] + (q[3] - p[3]) * f
    a[i + 1] = { w * i / n, 0, r, g, bl }
    b[i + 1] = { w * i / n, h, r, g, bl }
  end
  cv:mesh({ a, b }, n + 1)
  put(cv, w, h)
end

function T.spectrum(w, h)
  Art.configure(Art.defaults(), palettes.ultramarine)
  put(Art.spectrum(w, h, 400, 700), w, h)
end

return T
