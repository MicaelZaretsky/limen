-- limen-svg.lua -- the same art without TeX: runs limen-art.lua on a surface that writes SVG.
-- Part of limen, MIT License. See LICENSE.
--
--   texlua limen-svg.lua --page 3 --pages 8 --palette ruby > page-3.svg
--   lua limen-svg.lua --help
--
-- Any Lua 5.3 or later runs it. The picture is the one LuaLaTeX draws with the same options, seed and marks,
-- because the drawing code is the same file. Paths stay vector. SVG has no colour meshes, so the field and the beam
-- go into a PNG embedded in the file, at --dpi. The result is a whole page with a transparent background.

-- run from anywhere: the other files lie next to this one
local here = arg and arg[0] and arg[0]:match("^(.*)[/\\][^/\\]*$")
if here then package.path = here .. "/?.lua;" .. package.path end

local Art = require("limen-art")
local palettes = require("limen-palettes")

local M = { version = "0.2" }
local BP = 72 / 2.54
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min
local fmt, concat = string.format, table.concat

-- ---------------------------------------------------------------- PNG
local CRC = {}
for i = 0, 255 do
  local c = i
  for _ = 1, 8 do c = (c & 1) == 1 and (0xEDB88320 ~ (c >> 1)) or (c >> 1) end
  CRC[i] = c
end
local function crc32(s)
  local c = 0xFFFFFFFF
  for i = 1, #s do c = CRC[(c ~ s:byte(i)) & 255] ~ (c >> 8) end
  return c ~ 0xFFFFFFFF
end
local function deflate(s)
  if zlib and zlib.compress then return zlib.compress(s, 9) end
  -- plain Lua has no compressor: stored blocks are valid and only larger
  local out = { "\x78\x01" }
  local a, b, n = 1, 0, #s
  local pos = 1
  while pos <= n do
    local len = min(65535, n - pos + 1)
    local chunk = s:sub(pos, pos + len - 1)
    out[#out + 1] = string.pack("<BI2I2", pos + len > n and 1 or 0, len, len ~ 0xFFFF) .. chunk
    for i = 1, len do
      a = (a + chunk:byte(i)) % 65521
      b = (b + a) % 65521
    end
    pos = pos + len
  end
  out[#out + 1] = string.pack(">I4", b << 16 | a)
  return concat(out)
end
local function chunk(kind, data)
  return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
end
-- rows[y][x] = 0xRRGGBB + 1, nil where nothing was painted; the Up filter suits smooth colour
local function png(rows, w, h)
  local lines, prev = {}, {}
  for y = 0, h - 1 do
    local r = rows[y]
    local cur = {}
    local bytes = { "\2" }
    for x = 0, w - 1 do
      local v = r and r[x]
      local p = prev[x]
      if v == p and y > 0 then
        bytes[#bytes + 1] = "\0\0\0\0"
      elseif y == 0 then
        -- the Up filter of the first row is relative to zeros
        local c = v and v - 1 or 0xFFFFFF
        bytes[#bytes + 1] = string.char(c >> 16, (c >> 8) & 255, c & 255, v and 255 or 0)
      else
        -- an empty pixel is transparent white: black there would leave a dark fringe when the image is smoothed
        local cr, cg, cb, ca = 255, 255, 255, 0
        if v then
          v = v - 1
          cr, cg, cb, ca = v >> 16, (v >> 8) & 255, v & 255, 255
        end
        local pr, pg, pb, pa = 255, 255, 255, 0
        if p then
          p = p - 1
          pr, pg, pb, pa = p >> 16, (p >> 8) & 255, p & 255, 255
        end
        bytes[#bytes + 1] = string.char((cr - pr) & 255, (cg - pg) & 255, (cb - pb) & 255, (ca - pa) & 255)
      end
      cur[x] = r and r[x]
    end
    lines[y + 1] = concat(bytes)
    prev = cur
  end
  return "\137PNG\r\n\26\n"
    .. chunk("IHDR", string.pack(">I4I4BBBBB", w, h, 8, 6, 0, 0, 0))
    .. chunk("IDAT", deflate(concat(lines)))
    .. chunk("IEND", "")
end
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local function base64(s)
  local out, n = {}, 0
  for i = 1, #s - 2, 3 do
    local a, b, c = s:byte(i, i + 2)
    local v = a << 16 | b << 8 | c
    n = n + 1
    out[n] = B64:sub((v >> 18) + 1, (v >> 18) + 1) .. B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
      .. B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) .. B64:sub((v & 63) + 1, (v & 63) + 1)
  end
  local rest = #s % 3
  if rest > 0 then
    local a, b = s:byte(#s - rest + 1, #s)
    b = b or 0
    local v = a << 16 | b << 8
    n = n + 1
    out[n] = B64:sub((v >> 18) + 1, (v >> 18) + 1) .. B64:sub(((v >> 12) & 63) + 1, ((v >> 12) & 63) + 1)
      .. (rest == 2 and B64:sub(((v >> 6) & 63) + 1, ((v >> 6) & 63) + 1) or "=") .. "="
  end
  return concat(out)
end

-- ---------------------------------------------------------------- the surface
local C = {}
C.__index = C

-- spec: pw, ph (cm), bleed (cm), dpi; onmesh(rows, ncol, mirror_pw) replaces the built-in rasteriser if given
function M.canvas(spec)
  local self = setmetatable({ out = {}, path = {}, spec = spec, rows = {}, depth = 0 }, C)
  local b = spec.bleed or 0
  self.scale = spec.dpi / 2.54
  self.w = ceil((spec.pw + 2 * b) * self.scale)
  self.h = ceil((spec.ph + 2 * b) * self.scale)
  return self
end

local function num(v) return fmt("%.3f", v) end
function C:moveto(x, y) self.path[#self.path + 1] = "M" .. num(x) .. " " .. num(y) end
function C:lineto(x, y) self.path[#self.path + 1] = "L" .. num(x) .. " " .. num(y) end
function C:curveto(a, b, c, d, e, f)
  self.path[#self.path + 1] = "C" .. num(a) .. " " .. num(b) .. " " .. num(c) .. " " .. num(d) .. " " .. num(e) .. " " .. num(f)
end
function C:close() self.path[#self.path + 1] = "Z" end
function C:poly(pts, closed)
  local p = self.path
  p[#p + 1] = "M" .. num(pts[1][1]) .. " " .. num(pts[1][2])
  for i = 2, #pts do p[#p + 1] = "L" .. num(pts[i][1]) .. " " .. num(pts[i][2]) end
  if closed then p[#p + 1] = "Z" end
end
function C:circle(x, y, r)
  local k = 0.5523 * r
  self:moveto(x + r, y)
  self:curveto(x + r, y + k, x + k, y + r, x, y + r)
  self:curveto(x - k, y + r, x - r, y + k, x - r, y)
  self:curveto(x - r, y - k, x - k, y - r, x, y - r)
  self:curveto(x + k, y - r, x + r, y - k, x + r, y)
  self:close()
end
local function colour(c)
  return fmt("#%02x%02x%02x", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end
local function take(self)
  local s = concat(self.path)
  self.path = {}
  return s
end
function C:fill(c, op)
  local a = (op and op < 0.995) and fmt(' fill-opacity="%.2f"', op) or ""
  self.out[#self.out + 1] = fmt('<path d="%s" fill="%s"%s/>', take(self), colour(c), a)
end
function C:stroke(c, w, op)
  local a = (op and op < 0.995) and fmt(' stroke-opacity="%.2f"', op) or ""
  self.out[#self.out + 1] = fmt('<path d="%s" fill="none" stroke="%s" stroke-width="%.4f" stroke-linecap="round" stroke-linejoin="round"%s/>',
    take(self), colour(c), w / BP, a)
end
function C:mirror(pw)
  self.mirror_pw = pw
  self.out[#self.out + 1] = fmt('<g transform="matrix(-1 0 0 1 %.3f 0)">', pw)
end
function C:unmirror()
  self.mirror_pw = nil
  self.out[#self.out + 1] = "</g>"
end

-- a Gouraud triangle into the raster; x and y are already in pixels
local function triangle(rows, W, H, ax, ay, ar, ag, ab, bx, by, br, bg, bb, cx, cy, cr, cg, cb)
  local den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
  if den > -1e-9 and den < 1e-9 then return end
  local x0, x1 = max(0, floor(min(ax, bx, cx))), min(W - 1, ceil(max(ax, bx, cx)))
  local y0, y1 = max(0, floor(min(ay, by, cy))), min(H - 1, ceil(max(ay, by, cy)))
  local e = -0.02
  for y = y0, y1 do
    local row = rows[y]
    if not row then
      row = {}
      rows[y] = row
    end
    local py = y + 0.5
    for x = x0, x1 do
      local px = x + 0.5
      local u = ((by - cy) * (px - cx) + (cx - bx) * (py - cy)) / den
      if u >= e then
        local v = ((cy - ay) * (px - cx) + (ax - cx) * (py - cy)) / den
        if v >= e then
          local w = 1 - u - v
          if w >= e then
            local r, g, b = u * ar + v * br + w * cr, u * ag + v * bg + w * cg, u * ab + v * bb + w * cb
            r = r <= 0 and 0 or (r >= 1 and 255 or floor(r * 255 + 0.5))
            g = g <= 0 and 0 or (g >= 1 and 255 or floor(g * 255 + 0.5))
            b = b <= 0 and 0 or (b >= 1 and 255 or floor(b * 255 + 0.5))
            row[x] = (r << 16 | g << 8 | b) + 1
          end
        end
      end
    end
  end
end

function C:mesh(rows, ncol)
  if self.spec.onmesh then return self.spec.onmesh(rows, ncol, self.mirror_pw) end
  local s, b, ph = self.scale, self.spec.bleed or 0, self.spec.ph
  local mp = self.mirror_pw
  local W, H, R = self.w, self.h, self.rows
  local function px(v) return ((mp and mp - v[1] or v[1]) + b) * s, (ph + b - v[2]) * s end
  for j = 1, #rows - 1 do
    local r0, r1 = rows[j], rows[j + 1]
    for i = 1, ncol - 1 do
      local a, c, d, e = r0[i], r0[i + 1], r1[i + 1], r1[i]
      local ax, ay = px(a)
      local cx, cy = px(c)
      local dx, dy = px(d)
      local ex, ey = px(e)
      triangle(R, W, H, ax, ay, a[3], a[4], a[5], cx, cy, c[3], c[4], c[5], dx, dy, d[3], d[4], d[5])
      triangle(R, W, H, ax, ay, a[3], a[4], a[5], dx, dy, d[3], d[4], d[5], ex, ey, e[3], e[4], e[5])
    end
  end
end

-- the paths alone, for a host that paints the raster itself
function C:vector() return concat(self.out, "\n") end

function C:svg()
  local sp = self.spec
  local b = sp.bleed or 0
  local W, H = sp.pw + 2 * b, sp.ph + 2 * b
  local image = ""
  if next(self.rows) then
    image = fmt('<image x="%.3f" y="%.3f" width="%.4f" height="%.4f" preserveAspectRatio="none" xlink:href="data:image/png;base64,%s"/>\n',
      -b, -b, self.w / self.scale, self.h / self.scale, base64(png(self.rows, self.w, self.h)))
  end
  return concat({
    fmt('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="%.3fcm" height="%.3fcm" viewBox="%.3f %.3f %.3f %.3f">\n',
      W, H, -b, -b, W, H),
    image,
    fmt('<g transform="matrix(1 0 0 -1 0 %.3f)">\n', sp.ph),
    self:vector(),
    "\n</g>\n</svg>\n",
  })
end

-- ---------------------------------------------------------------- one page
-- The layout is the one limen.lua reads from TeX, here given by hand: everything in cm from the lower-left corner.
function M.layout(s)
  local pw, ph = s.pw or 21, s.ph or 29.7
  local g = { pw = pw, ph = ph, bleed = s.bleed or 0, u = max(0.45, min(1.4, min(pw / 21, ph / 29.7))) }
  g.textleft, g.textright = s.left or 5.8, pw - (s.right or 1.7)
  if s.even and pw - g.textright > g.textleft + 0.05 then g.mirror = true end
  if pw - g.textright > g.textleft + 0.05 then
    g.mirror = true
    g.textleft, g.textright = pw - g.textright, pw - g.textleft
  end
  g.ytop = ph - (s.top or 3)
  g.ybot = s.bottom or 2.9
  g.colright = s.column or (g.textleft - 0.4)
  g.headrule = g.ytop + (s.headsep or 0.8) - 0.1
  return g
end

-- o: options over Art.defaults(); s: page, pages, marks, ths, restarts, textend, closing, cover, level, dpi and the layout
function M.page(o, s, surface)
  local opt = Art.defaults()
  for k, v in pairs(o or {}) do opt[k] = v end
  local pal = opt.custom or palettes[opt.palette] or palettes.ultramarine
  Art.configure(opt, pal)
  local g = M.layout(s)
  local spec = { pw = g.pw, ph = g.ph, bleed = g.bleed, dpi = s.dpi or 110, onmesh = s.onmesh }
  Art.surface = surface or function() return M.canvas(spec) end
  local page = s.page or 1
  if s.cover then
    g.mirror = nil
    local P0 = s.cover == "dark" and 0.02 or 1
    local S = {
      P = function() return P0 end,
      ramp = function(P) return P >= 0.5 and 1 or 0 end,
      curve = function(P, a, b) return P >= 0.5 and 1 or a + (b - a) * 0.5 end,
    }
    return Art.cover(g, S, pal, opt, s.cover, Art.seed_for(opt, 0))
  end
  if not opt.headrule then g.headrule = nil end
  if opt.finale and (s.closing or (s.closing == nil and page == s.pages)) then
    g.closing = true
    if s.textend and s.textend >= 8 * g.u then
      g.textend = s.textend
      g.lake = true
    end
  end
  local prev = { pages = s.pages, endpage = s.endpage, ths = s.ths, restarts = s.restarts }
  local S = Art.make_story(page, g.ph, opt, prev, s.level)
  return Art.page(g, S, pal, opt, s.marks or {}, Art.seed_for(opt, page)), g
end

-- ---------------------------------------------------------------- the command line
local HELP = [[
limen-svg: one page of limen as SVG, without TeX.

  texlua limen-svg.lua [options] > page.svg

The document
  --page N --pages N      which page of how many (default 1 of 1)
  --level X               fixed stage 0..1 instead of the story
  --closing yes|no        whether this page closes the story (default: the last page)
  --textend CM            where the text ends on the closing page, from the bottom of the sheet
  --marks LIST            heading:Y:LEVEL,star:Y,threshold:Y,caustic:Y:KIND, Y in cm from the bottom
  --ths LIST              thresholds of the whole document, PAGE:SHARE,... SHARE from the top of that page 0..1
  --restarts LIST         pages where a new story starts, with --story chapter
  --cover spectrum|dark   a cover instead of a page

The sheet, in cm unless a unit is given
  --paper a4|a5|letter    or --width --height
  --left --right --top --bottom --headsep --column --bleed --dpi (default 110)

Options of the package
  --palette --mode --story --threshold --level --beam --wavelength --caustic --density --caustics --seed
  --lines --headings --finale --headrule yes|no
]]

local function length(v)
  local n, unit = tostring(v):match("^([%d.]+)%s*(%a*)$")
  n = tonumber(n)
  if not n then error("not a length: " .. tostring(v)) end
  if unit == "mm" then return n / 10 elseif unit == "in" then return n * 2.54 elseif unit == "pt" then return n * 2.54 / 72.27 end
  return n
end
local PAPER = { a4 = { 21, 29.7 }, a5 = { 14.8, 21 }, letter = { 21.59, 27.94 } }

function M.main(args)
  local a, i = {}, 1
  while i <= #args do
    local key = args[i]:match("^%-%-(.+)$")
    if not key then error("unexpected argument: " .. args[i]) end
    if key == "help" then
      io.stdout:write(HELP)
      return
    end
    a[key] = args[i + 1]
    i = i + 2
  end
  local o = {}
  for _, k in ipairs({ "palette", "mode", "story", "beam", "caustic" }) do o[k] = a[k] end
  for _, k in ipairs({ "threshold", "wavelength", "density", "caustics", "seed" }) do
    if a[k] then o[k] = tonumber(a[k]) end
  end
  for _, k in ipairs({ "lines", "headings", "finale", "headrule" }) do
    if a[k] then o[k] = a[k] == "yes" end
  end
  local s = { page = tonumber(a.page) or 1, pages = tonumber(a.pages) or 1, dpi = tonumber(a.dpi), cover = a.cover,
    level = tonumber(a.level) }
  local p = PAPER[a.paper or "a4"] or PAPER.a4
  s.pw, s.ph = a.width and length(a.width) or p[1], a.height and length(a.height) or p[2]
  for _, k in ipairs({ "left", "right", "top", "bottom", "headsep", "column", "bleed", "textend" }) do
    if a[k] then s[k] = length(a[k]) end
  end
  if a.closing then s.closing = a.closing == "yes" end
  if a.marks then
    s.marks = {}
    for item in a.marks:gmatch("[^,]+") do
      local kind, y, arg = item:match("^(%a+):([%d.]+):?(.*)$")
      if kind == "caustic" and arg ~= "" then arg = "kind=" .. arg end
      if kind then s.marks[#s.marks + 1] = { kind = kind, y = tonumber(y), arg = arg ~= "" and arg or nil } end
    end
  end
  if a.ths then
    s.ths = {}
    for pg, y in a.ths:gmatch("(%d+):([%d.]+)") do s.ths[#s.ths + 1] = { i = tonumber(pg), y = 1 - tonumber(y) } end
  end
  if a.restarts then
    s.restarts = {}
    for pg in a.restarts:gmatch("%d+") do s.restarts[#s.restarts + 1] = tonumber(pg) end
  end
  local cv = M.page(o, s)
  io.stdout:write(cv:svg())
end

if arg and arg[0] and arg[0]:match("limen%-svg") then M.main(arg) end

return M
