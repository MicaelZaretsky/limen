-- limen-pdf.lua -- the drawing surface: paths, alpha and Gouraud meshes, written into one Form XObject.
-- Part of limen, MIT License. See LICENSE.
--
-- Everything a page draws goes into one Form XObject with resources of its own. That keeps limen out of
-- the page's resource dictionary, which other packages such as pgf also manage.
--
-- Colour is painted with lattice-form Gouraud shadings (PDF shading type 5). They are smooth at any zoom
-- and much smaller than stacks of translucent contours. Limen never uses PDF blend modes: colours that
-- add up are computed in Lua and written as opaque vertices, because viewers disagree on how a blended
-- mesh should look (Poppler blends each triangle on its own and washes a Screen mesh out to white).

local M = { version = "0.2" }

local floor, max, min = math.floor, math.max, math.min
local concat, fmt, pack = table.concat, string.format, string.pack
local BP = 72 / 2.54
M.BP = BP

-- Colour model of everything drawn from now on: "rgb", or "cmyk" for a print shop. The conversion is the plain
-- one, without an ICC profile, so a printer's proof remains necessary.
local use_cmyk = false
function M.set_colormodel(model) use_cmyk = model == "cmyk" end
local function to_cmyk(r, g, b)
  local k = 1 - max(r, g, b)
  if k >= 0.999 then return 0, 0, 0, 1 end
  return (1 - r - k) / (1 - k), (1 - g - k) / (1 - k), (1 - b - k) / (1 - k), k
end
local function colour_op(c, stroke)
  if use_cmyk then
    local a, b, d, k = to_cmyk(c[1], c[2], c[3])
    return fmt(stroke and "%.3f %.3f %.3f %.3f K" or "%.3f %.3f %.3f %.3f k", a, b, d, k)
  end
  return fmt(stroke and "%.3f %.3f %.3f RG" or "%.3f %.3f %.3f rg", c[1], c[2], c[3])
end

function M.hex(s)
  s = tostring(s):gsub("^#", "")
  return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255 }
end

function M.tohex(c)
  return fmt("%02X%02X%02X", floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5), floor(c[3] * 255 + 0.5))
end

-- one shared ExtGState object for each opacity, in whole percent
local alpha_objects = {}
local function alpha_object(p)
  local n = alpha_objects[p]
  if not n then
    n = pdf.immediateobj(fmt("<< /ca %.2f /CA %.2f >>", p / 100, p / 100))
    alpha_objects[p] = n
  end
  return n
end

local C = {}
C.__index = C

-- a new surface; lengths are in cm unless a call says otherwise
function M.canvas()
  return setmetatable({ ops = {}, nops = 0, path = {}, npath = 0, shadings = {}, alphas = {} }, C)
end

function C:put(s)
  self.nops = self.nops + 1
  self.ops[self.nops] = s
end

local function add(self, s)
  self.npath = self.npath + 1
  self.path[self.npath] = s
end

function C:moveto(x, y) add(self, fmt("%.3f %.3f m", x * BP, y * BP)) end
function C:lineto(x, y) add(self, fmt("%.3f %.3f l", x * BP, y * BP)) end
function C:curveto(a, b, c, d, e, f)
  add(self, fmt("%.3f %.3f %.3f %.3f %.3f %.3f c", a * BP, b * BP, c * BP, d * BP, e * BP, f * BP))
end
function C:close() add(self, "h") end

function C:poly(pts, closed)
  local p = pts[1]
  add(self, fmt("%.2f %.2f m", p[1] * BP, p[2] * BP))
  for i = 2, #pts do
    p = pts[i]
    add(self, fmt("%.2f %.2f l", p[1] * BP, p[2] * BP))
  end
  if closed then add(self, "h") end
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

local function take(self)
  local s = concat(self.path, " ", 1, self.npath)
  self.npath = 0
  return s
end

local function alpha(self, op)
  if not op or op >= 0.995 then return "" end
  local p = max(1, min(99, floor(op * 100 + 0.5)))
  local name = "A" .. p
  self.alphas[name] = alpha_object(p)
  return "/" .. name .. " gs "
end

function C:fill(c, op)
  local g = alpha(self, op)
  self:put(fmt("q %s%s %s f Q", g, colour_op(c), take(self)))
end

function C:stroke(c, w, op)
  local g = alpha(self, op)
  self:put(fmt("q %s%s %.3f w 1 j 1 J %s S Q", g, colour_op(c, true), w, take(self)))
end

function C:clip() self:put("q " .. take(self) .. " W n") end
function C:unclip() self:put("Q") end
-- the art is laid out for a page with the wide margin on the left; on a right-hand page it is reflected
function C:mirror(pw) self:put(fmt("q -1 0 0 1 %.3f 0 cm", pw * BP)) end
function C:unmirror() self:put("Q") end

-- A lattice mesh: rows[j][i] = { x, y, r, g, b }, x and y in cm, every row with ncol vertices.
-- The stream is compressed by LuaTeX along with the rest of the file.
function C:mesh(rows, ncol)
  local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
  for _, row in ipairs(rows) do
    for i = 1, ncol do
      local v = row[i]
      if v[1] < x0 then x0 = v[1] end
      if v[1] > x1 then x1 = v[1] end
      if v[2] < y0 then y0 = v[2] end
      if v[2] > y1 then y1 = v[2] end
    end
  end
  if x1 <= x0 then x1 = x0 + 1e-3 end
  if y1 <= y0 then y1 = y0 + 1e-3 end
  local sx, sy = 65535 / (x1 - x0), 65535 / (y1 - y0)
  local buf, n = {}, 0
  for _, row in ipairs(rows) do
    for i = 1, ncol do
      local v = row[i]
      n = n + 1
      if use_cmyk then
        local a, b, d, k = to_cmyk(max(0, min(1, v[3])), max(0, min(1, v[4])), max(0, min(1, v[5])))
        buf[n] = pack(">I2I2BBBB", floor((v[1] - x0) * sx + 0.5), floor((v[2] - y0) * sy + 0.5),
          floor(a * 255 + 0.5), floor(b * 255 + 0.5), floor(d * 255 + 0.5), floor(k * 255 + 0.5))
      else
        buf[n] = pack(">I2I2BBB",
          floor((v[1] - x0) * sx + 0.5), floor((v[2] - y0) * sy + 0.5),
          floor(max(0, min(1, v[3])) * 255 + 0.5), floor(max(0, min(1, v[4])) * 255 + 0.5),
          floor(max(0, min(1, v[5])) * 255 + 0.5))
      end
    end
  end
  local obj = pdf.immediateobj("stream", concat(buf), fmt(
    "/ShadingType 5 /ColorSpace /%s /BitsPerCoordinate 16 /BitsPerComponent 8 "
    .. "/VerticesPerRow %d /Decode [%.3f %.3f %.3f %.3f %s]",
    use_cmyk and "DeviceCMYK" or "DeviceRGB", ncol, x0 * BP, x1 * BP, y0 * BP, y1 * BP,
    use_cmyk and "0 1 0 1 0 1 0 1" or "0 1 0 1 0 1"))
  local name = "S" .. (#self.shadings + 1)
  self.shadings[#self.shadings + 1] = { name, obj }
  self:put("/" .. name .. " sh")
end

-- Turn the surface into a Form XObject of the given size in scaled points; returns the resource index
-- that tex.useboxresource takes. All of it is marked as an artifact, so that software reading a tagged PDF
-- aloud passes over it. The origin of the drawing can be moved by shift, in cm, for pages with bleed.
function C:form(w, h, shift)
  local lit = node.new("whatsit", "pdf_literal")
  lit.mode = 1
  local body = concat(self.ops, "\n", 1, self.nops)
  if shift and shift > 0 then body = fmt("q 1 0 0 1 %.3f %.3f cm\n%s\nQ", shift * BP, shift * BP, body) end
  lit.data = "/Artifact BMC\n" .. body .. "\nEMC"
  local box = node.hpack(lit)
  box.width, box.height, box.depth = w, h, 0
  local res = {}
  if #self.shadings > 0 then
    local t = {}
    for _, s in ipairs(self.shadings) do t[#t + 1] = fmt("/%s %d 0 R", s[1], s[2]) end
    res[#res + 1] = "/Shading << " .. concat(t, " ") .. " >>"
  end
  local names = {}
  for name in pairs(self.alphas) do names[#names + 1] = name end
  if #names > 0 then
    table.sort(names)
    local t = {}
    for _, name in ipairs(names) do t[#t + 1] = fmt("/%s %d 0 R", name, self.alphas[name]) end
    res[#res + 1] = "/ExtGState << " .. concat(t, " ") .. " >>"
  end
  return tex.saveboxresource(box, "", concat(res, " "), true)
end

return M
