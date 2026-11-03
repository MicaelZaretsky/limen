-- limen.lua -- the TeX-facing side of limen.sty: options, page layout, marks in the text, the story.
-- Part of limen, MIT License. See LICENSE.
--
-- The geometry and the search for marks in the page box follow florilegium by Kevin Raymond (MIT).

local Pdf = require("limen-pdf")
local Art = require("limen-art")
local palettes = require("limen-palettes")

local M = { version = "0.2" }
if Pdf.version ~= M.version or Art.version ~= M.version then
  tex.error("limen: the files limen*.lua come from different releases", { "Copy limen.sty and every limen*.lua from one release." })
end

local max, min, floor = math.max, math.min, math.floor
local SP_CM = 2.54 / (72.27 * 65536)
local function cm(name) return tex.dimen[name] * SP_CM end
local function lerp(a, b, t) return a + (b - a) * t end

-- ---------------------------------------------------------------- options
M.opt = Art.defaults()
local NUMERIC = { threshold = true, level = true, density = true, caustics = true, column = true, seed = true,
  wavelength = true, bleed = true }
local BOOLEAN = { lines = true, headings = true, finale = true, headrule = true, draft = true, sameart = true }
local CHOICE = { mode = { night = true, paper = true }, story = { threshold = true, flat = true, chapter = true },
  beam = { spectrum = true, mono = true }, color = { rgb = true, cmyk = true },
  caustic = { ellipse = true, cardioid = true, nephroid = true, rings = true, speckle = true, mix = true } }

local function warn(msg) luatexbase.module_warning("limen", msg) end

local function parse(str)
  local out = {}
  for item in tostring(str):gmatch("[^,]+") do
    local key, val = item:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if not key then
      key = item:match("^%s*(.-)%s*$")
      val = "true"
    end
    if key ~= "" then out[#out + 1] = { key, val } end
  end
  return out
end

function M.setup(str)
  for _, kv in ipairs(parse(str)) do
    local key, val = kv[1], kv[2]
    if M.opt[key] == nil then
      warn("unknown option '" .. key .. "'")
    elseif CHOICE[key] and not CHOICE[key][val] then
      warn("option " .. key .. " cannot be '" .. val .. "'")
    elseif NUMERIC[key] then
      local n = tonumber(val)
      if n then M.opt[key] = n else warn("option " .. key .. " needs a number, got '" .. val .. "'") end
    elseif BOOLEAN[key] then
      M.opt[key] = val == "true"
    else
      M.opt[key] = val
    end
  end
  if not palettes[M.opt.palette] then
    warn("unknown palette '" .. tostring(M.opt.palette) .. "', using ultramarine")
    M.opt.palette = "ultramarine"
  end
  M.opt.threshold = max(0, min(0.9, M.opt.threshold))
  M.opt.density = max(0.2, min(3, M.opt.density))
  M.opt.bleed = max(0, min(10, M.opt.bleed))
end

function M.colors()
  local p = palettes[M.opt.palette]
  tex.sprint(string.format("\\definecolor{limenink}{HTML}{%s}\\definecolor{limenaccent}{HTML}{%s}",
    Pdf.tohex(p.ink), Pdf.tohex(p.accent)))
end

-- \limendefinepalette{name}{deep=, flow=, flow2=, line=, ink=, accent=, caustic=}
function M.define_palette(name, str)
  local v = {}
  for _, kv in ipairs(parse(str)) do v[kv[1]] = kv[2] end
  local base = palettes.ultramarine
  local h = Pdf.hex
  local p = {
    deep = v.deep and h(v.deep) or base.deep, line = v.line and h(v.line) or base.line,
    ink = v.ink and h(v.ink) or base.ink, accent = v.accent and h(v.accent) or base.accent,
    caustic = v.caustic and { h(v.caustic), h(v.caustic) } or { v.line and h(v.line) or base.line, v.line and h(v.line) or base.line },
    lineop = tonumber(v.lineop) or 0.8, causticop = tonumber(v.causticop) or 0.9,
    flows = {},
  }
  p.flows[1] = { v.flow and h(v.flow) or base.flows[1][1], 0.2, 0.64 }
  p.flows[2] = { v.flow2 and h(v.flow2) or p.flows[1][1], 0.72, 0.46 }
  palettes[name] = p
end

-- ---------------------------------------------------------------- the page layout
-- In cm from the lower-left corner of the paper. The art goes into the wider side margin: when that is the
-- right one, the layout is made for the mirrored page and drawn reflected.
M.twoside = false
M.beamer = false
local function geometry()
  local inch = 2.54
  local g = { pw = cm("paperwidth"), ph = cm("paperheight"), bleed = M.beamer and 0 or M.opt.bleed / 10 }
  g.u = max(0.45, min(1.4, min(g.pw / 21, g.ph / 29.7)))
  if M.beamer then
    g.colright = M.opt.column or 2.2
    g.textleft, g.textright = g.colright + 0.5, g.pw - 0.8
    g.ytop, g.ybot = g.ph, 0
    g.u = max(0.45, min(0.62, g.ph / 15))
    return g
  end
  local even = M.twoside and tex.count[0] % 2 == 0
  g.textleft = inch + tex.hoffset * SP_CM - g.bleed + cm(even and "evensidemargin" or "oddsidemargin")
  g.textright = g.textleft + cm("textwidth")
  if g.pw - g.textright > g.textleft + 0.05 then
    g.mirror = true
    g.textleft, g.textright = g.pw - g.textright, g.pw - g.textleft
  end
  g.ytop = g.ph - inch - cm("topmargin") - cm("headheight") - cm("headsep")
  g.ybot = g.ytop - cm("textheight")
  g.colright = M.opt.column or (g.textleft - 0.4)
  g.headrule = g.ytop + cm("headsep") - 0.1
  return g
end

-- ---------------------------------------------------------------- marks in the text
-- A mark is a whatsit in the text; the page box is searched for them at shipout, so the margin knows the
-- height of the marked lines on the same page in the same run.
local MARK = 0x4C494D                         -- "LIM"
local marks = {}
function M.mark(kind, arg)
  marks[#marks + 1] = { kind = kind, arg = arg }
  local n = node.new("whatsit", "user_defined")
  n.user_id, n.type, n.value = MARK, 100, #marks
  node.write(n)
end

local HLIST, VLIST, GLUE, KERN, RULE, WHATSIT = node.id("hlist"), node.id("vlist"), node.id("glue"), node.id("kern"),
  node.id("rule"), node.id("whatsit")
local USER = node.subtype("user_defined")
local function walk(head, parent, x, y, vertical, out)
  for n in node.traverse(head) do
    local id = n.id
    if id == HLIST or id == VLIST then
      if vertical then
        local base = y + n.height
        if n.list then walk(n.list, n, x + n.shift, id == VLIST and y or base, id == VLIST, out) end
        y = base + n.depth
      else
        local base = y + n.shift
        if n.list then walk(n.list, n, x, id == VLIST and base - n.height or base, id == VLIST, out) end
        x = x + n.width
      end
    elseif id == GLUE then
      local w = node.effective_glue(n, parent)
      if vertical then y = y + w else x = x + w end
    elseif id == KERN then
      if vertical then y = y + n.kern else x = x + n.kern end
    elseif id == RULE then
      if vertical then y = y + n.height + n.depth else x = x + n.width end
    elseif id == WHATSIT and n.subtype == USER and n.user_id == MARK then
      local m = marks[n.value]
      if m then out[#out + 1] = { kind = m.kind, arg = m.arg, x = x, y = y } end
    elseif not vertical then
      x = x + node.dimensions(n, n.next)
    end
  end
end
local function page_marks(box)
  local b = box and tex.box[box]
  if not b then return {} end
  local out = {}
  walk(b.list, b, 0, 0, b.id == VLIST, out)
  local ph, inch, bl = tex.dimen.paperheight * SP_CM, 2.54, M.beamer and 0 or M.opt.bleed / 10
  for _, m in ipairs(out) do
    m.x = inch + tex.hoffset * SP_CM - bl + m.x * SP_CM
    m.y = ph - inch - (tex.voffset * SP_CM - bl) - m.y * SP_CM
  end
  return out
end

-- ---------------------------------------------------------------- what the last run measured
-- The story needs the length of the document, so it needs two runs, like a table of contents.
local prev = { restarts = {}, ths = {} }
function M.aux_in(key, val)
  if key == "pages" then prev.pages = tonumber(val)
  elseif key == "threshold" then
    local i, y = val:match("^([%d%.]+):([%d%.]+)$")
    if i then prev.ths[#prev.ths + 1] = { i = tonumber(i), y = tonumber(y) } end
  elseif key == "restart" then prev.restarts[#prev.restarts + 1] = tonumber(val)
  elseif key == "endpage" then prev.endpage = tonumber(val)
  end
end

local idx, last_frame = 0, nil
local now = { restarts = {}, ths = {} }
local override, enabled = nil, true
local closed, warned_narrow, overlay_form = false, false, nil

function M.aux_out()
  local function w(k, v)
    tex.sprint(luatexbase.registernumber("catcodetable@atletter"),
      string.format("\\immediate\\write\\@mainaux{\\string\\limen@aux{%s}{%s}}", k, v))
  end
  w("pages", idx)
  for _, t in ipairs(now.ths) do w("threshold", string.format("%d:%.3f", t.i, t.y)) end
  for _, r in ipairs(now.restarts) do w("restart", r) end
  if now.endpage then w("endpage", now.endpage) end
  w("headings", now.headings or 0)
  local changed = prev.pages ~= idx
  if #now.ths ~= #prev.ths or #now.restarts ~= #prev.restarts or now.endpage ~= prev.endpage then changed = true end
  for i, t in ipairs(now.ths) do
    local p = prev.ths[i]
    if p and (p.i ~= t.i or math.abs(p.y - t.y) > 0.01) then changed = true end
  end
  if changed then warn("the length of the document or a mark has changed. Rerun to get the story right") end
end

local function story(page_index, ph)
  return Art.make_story(page_index, ph, M.opt, prev, override)
end

-- ---------------------------------------------------------------- one shipped page
-- The closing page: the one with \\limenend, otherwise the last page of the document by the last run's count.
-- What is really on it is measured in the page box when it ships, so floats and footnotes count too.
local GLYPH, COLORSTACK = node.id("glyph"), node.subtype("pdf_colorstack")
local function measure(head, parent, y, vertical, limit, st)
  for n in node.traverse(head) do
    local id = n.id
    if id == HLIST or id == VLIST then
      if vertical then
        local base = y + n.height
        if id == HLIST and base > limit then
          st.foot[#st.foot + 1] = n
        else
          if id == HLIST and n.list and n.width > 0 and base + n.depth > st.low then st.low = base + n.depth end
          if n.list then measure(n.list, n, id == VLIST and y or base, id == VLIST, limit, st) end
        end
        y = base + n.depth
      elseif n.list then
        local base = y + n.shift
        measure(n.list, n, id == VLIST and base - n.height or base, id == VLIST, limit, st)
      end
    elseif id == GLUE then
      if vertical then y = y + node.effective_glue(n, parent) end
    elseif id == KERN then
      if vertical then y = y + n.kern end
    elseif id == RULE then
      if vertical then
        y = y + n.height + n.depth
        if y <= limit and y > st.low then st.low = y end
      end
    elseif id == GLYPH and y + parent.depth > st.low and y <= limit then
      st.low = y + parent.depth
    end
  end
end

-- On a page whose night field runs under the footer, the footer turns white. This happens in the shipped box,
-- so it works with any page style and any colour the footer asked for.
local function whiten(head)
  for n in node.traverse(head) do
    if n.id == HLIST or n.id == VLIST then
      if n.list then whiten(n.list) end
    elseif n.id == WHATSIT and n.subtype == COLORSTACK and (n.command == 0 or n.command == 1) then
      n.data = "1 g 1 G"
    end
  end
end
local function stack_node(command, data)
  local w = node.new("whatsit", "pdf_colorstack")
  w.stack, w.command = 0, command
  if data then w.data = data end
  return w
end
local function whiten_foot(hlist)
  if not hlist.list then return end
  whiten(hlist.list)
  hlist.list = node.insert_before(hlist.list, hlist.list, stack_node(1, "1 g 1 G"))
  node.insert_after(hlist.list, node.tail(hlist.list), stack_node(2))
end

local function closing_page(box, g)
  local b = tex.box[box]
  if not b then return end
  local top = cm("paperheight") - 2.54 - (tex.voffset * SP_CM - g.bleed)
  local limit = floor((top - g.ybot) / SP_CM) + 65536
  local st = { low = 0, foot = {} }
  measure(b.list, b, 0, b.id == VLIST, limit, st)
  g.textend = top - st.low * SP_CM
  if g.textend >= 8 * g.u then
    g.lake = true
    if M.opt.mode ~= "paper" then
      for _, f in ipairs(st.foot) do whiten_foot(f) end
    end
  end
end

-- the size of the drawing with bleed, and the sheet's boxes, which are set once and stay
local boxes_set, group_set

-- With \\DocumentMetadata, LaTeX's PDF management writes the page attributes itself and would overwrite what
-- pdf.setpageattributes sets, so the same keys go through it instead.
local function box_values(pw, ph, b)
  local bp = 72 / 2.54
  return string.format("[%.3f %.3f %.3f %.3f]", b * bp, b * bp, (pw + b) * bp, (ph + b) * bp),
    string.format("[0 0 %.3f %.3f]", (pw + 2 * b) * bp, (ph + 2 * b) * bp)
end
local function colour_space() return M.opt.color == "cmyk" and "DeviceCMYK" or "DeviceRGB" end
function M.managed_attributes()
  if M.opt.draft then return end
  group_set = true
  local function add(k, v)
    tex.sprint(string.format("\\csname pdfmanagement_add:nnn\\endcsname{Page}{%s}{%s}", k, v))
  end
  add("Group", "<</S/Transparency/I true/CS/" .. colour_space() .. ">>")
  local b = M.beamer and 0 or M.opt.bleed / 10
  if b > 0 then
    boxes_set = true
    local trim, bleed = box_values(cm("paperwidth"), cm("paperheight"), b)
    add("TrimBox", trim)
    add("BleedBox", bleed)
  end
end
local function seed_for(i) return Art.seed_for(M.opt, i) end

-- Lines and glows are translucent. Without a transparency group on the page Acrobat chooses the colour space for
-- blending itself, and areas around translucent objects can come out paler than the rest. So the page names it.
local function page_group()
  if group_set then return end
  group_set = true
  local attr = pdf.getpageattributes() or ""
  if not attr:find("/Group", 1, true) then
    pdf.setpageattributes(string.format("%s /Group << /S /Transparency /I true /CS /%s >>", attr, colour_space()))
  end
end

local function sheet(g)
  local b = g.bleed
  local sp = floor(b / SP_CM)
  if b > 0 and not boxes_set then
    boxes_set = true
    local trim, bleed = box_values(g.pw, g.ph, b)
    pdf.setpageattributes(string.format("%s /TrimBox %s /BleedBox %s", pdf.getpageattributes() or "", trim, bleed))
  end
  return tex.dimen.paperwidth + 2 * sp, tex.dimen.paperheight + 2 * sp, b
end

function M.page(box, page_number, frame)
  local o = M.opt
  local found = page_marks(box)
  local cover, pause, explicit_end
  for _, m in ipairs(found) do
    if m.kind == "cover" then cover = m.arg
    elseif m.kind == "pause" then pause = true
    elseif m.kind == "off" then enabled = false
    elseif m.kind == "on" then enabled = true
    elseif m.kind == "level" then override = tonumber(m.arg)
    end
  end
  local fresh = true
  if not cover then
    if frame and frame == last_frame then fresh = false
    else
      idx = idx + 1
      last_frame = frame
    end
  end
  local ph = cm("paperheight")
  for _, m in ipairs(found) do
    if m.kind == "heading" or m.kind == "star" then now.headings = (now.headings or 0) + 1 end
    if m.kind == "threshold" then
      -- the overlays of a frame carry the same mark, so it is counted once
      local y, last_t = max(0, min(1, m.y / ph)), now.ths[#now.ths]
      if not (last_t and last_t.i == idx and math.abs(last_t.y - y) < 0.002) then now.ths[#now.ths + 1] = { i = idx, y = y } end
    elseif m.kind == "restart" or (m.kind == "heading" and tonumber(m.arg) == 0) then
      if now.restarts[#now.restarts] ~= idx then now.restarts[#now.restarts + 1] = idx end
    elseif m.kind == "end" then
      explicit_end = true
      now.endpage = idx
    end
  end
  if o.draft then return end
  local pal = palettes[o.palette]
  Art.configure(o, pal)
  local g = geometry()
  local cv
  if cover then
    g.mirror = nil
    local style = cover:match("style%s*=%s*(%w+)") or "spectrum"
    local P0 = style == "dark" and 0.02 or 1
    local S = {
      P = function() return P0 end,
      ramp = function(P) return P >= 0.5 and 1 or 0 end,
      curve = function(P, a, b) return P >= 0.5 and 1 or lerp(a, b, 0.5) end,
    }
    cv = Art.cover(g, S, pal, o, style, seed_for(0))
  else
    if not enabled or pause then return end
    if not fresh and overlay_form then
      -- the overlays of one frame share one picture
      node.write((tex.useboxresource(overlay_form)))
      return
    end
    if not M.beamer and g.colright < 2.5 * g.u and not warned_narrow then
      warned_narrow = true
      warn(string.format("the coloured column is only %.1f cm wide; give the text a wider left margin", g.colright))
    end
    if o.finale and not closed and (explicit_end or (not prev.endpage and prev.pages == idx)) then
      closed = true
      g.closing = true
      if not M.beamer then closing_page(box, g) end
    end
    if M.beamer then g.extra_nodes = Art.slide_nodes(g) end
    local S = story(idx, g.ph)
    cv = Art.page(g, S, pal, o, found, seed_for(idx))
  end
  page_group()
  local w, h, shift = sheet(g)
  if M.beamer and not cover then
    overlay_form = cv:form(w, h, shift)
    node.write((tex.useboxresource(overlay_form)))
    return
  end
  node.write((tex.useboxresource(cv:form(w, h, shift))))
end

-- ---------------------------------------------------------------- things placed in the text
function M.hidden(on)
  local n = node.new("whatsit", "pdf_literal")
  n.mode = 1
  n.data = on and "3 Tr" or "0 Tr"
  node.write(n)
end

-- by default the letter comes from the bold face of the document's own font
local initial_file
local font_warned = false
function M.note_font()
  local f = font.getfont(font.current())
  local file = f and f.filename
  if f and (not file or file == "") then
    -- The font cache keeps the path a font was first loaded by. When that path was relative and leads nowhere from this
    -- folder, the file name comes back empty. LuaTeX cannot embed such a font either, so say what to do about it.
    file = (f.name or ""):match("^%[(.-)%]")
    if file and not font_warned then
      font_warned = true
      warn("the font cache holds a path to " .. file:match("[^/\\]*$") .. " that does not lead anywhere from this folder,\n"
        .. "so LuaTeX will stop with: cannot find file ''. Delete this font's file in luatex-cache/generic/fonts/otl\n"
        .. "and build again. An absolute Path alone does not help: the path in the cache wins")
    end
  end
  initial_file = file and file:match("%.%a+$") and file or nil
end

function M.initial(letter, side)
  local o = M.opt
  local file = o.initialfont ~= "auto" and o.initialfont or initial_file or "lmroman10-bold.otf"
  local S = side * SP_CM
  Art.configure(o, palettes[o.palette])
  local st = story(idx + 1, cm("paperheight"))
  local level = st.curve(st.P(cm("paperheight") / 2), 0.04, 0.07)
  local cv, err = Art.initial(S, level, letter, file, palettes[o.palette], o)
  if not cv then
    tex.error("limen: " .. tostring(err), { "Choose a font with this letter: \\limensetup{initialfont=<file>}." })
    return
  end
  node.write((tex.useboxresource(cv:form(side, side))))
end

local forms = {}
local function reuse(key, make, w, h)
  local i = forms[key]
  if not i then
    i = make():form(w, h)
    forms[key] = i
  end
  node.write((tex.useboxresource(i)))
end

function M.rule(w, h)
  local o = M.opt
  Art.configure(o, palettes[o.palette])
  reuse(table.concat({ "rule", w, h, o.palette }, ":"), function()
    return Art.rule(w * SP_CM, h * SP_CM, palettes[o.palette], o)
  end, w, h)
end

function M.spark(s)
  local o = M.opt
  Art.configure(o, palettes[o.palette])
  reuse(table.concat({ "spark", s, o.palette }, ":"), function()
    return Art.spark(s * SP_CM, palettes[o.palette].accent)
  end, s, s)
end

function M.spectrum(w, h, from, to)
  Art.configure(M.opt, palettes[M.opt.palette])
  reuse(table.concat({ "spectrum", w, h, from, to }, ":"), function()
    return Art.spectrum(w * SP_CM, h * SP_CM, from, to)
  end, w, h)
end

return M
