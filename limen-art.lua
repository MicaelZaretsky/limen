-- limen-art.lua -- what limen draws: the night field, lines of equal phase, the dispersed beam, caustics,
-- stars, the closing fan, the cover, initials and small ornaments. Part of limen, MIT License. See LICENSE.
--
-- What is computed and what is only an image
--   lines     contours of the path difference between two pairs of point sources
--   beam      a sum of Gaussian strands, one per wavelength, with conserved energy. A narrow beam therefore
--             really adds up to white, and a wide one really separates into pure colours
--   caustics  ray tracing inside an elliptical mirror; orbits that nearly close are rejected
--   image     a real Nd:YAG beam is monochromatic and invisible (1064 nm). The rainbow is a picture;
--             the scale of the fringes and the bends of the beam are decorative

local Pdf = require("limen-pdf")
local M = { version = "0.2" }
-- where the drawing goes; limen-svg.lua replaces this outside TeX
M.surface = Pdf.canvas

local sin, cos, tan, atan, sqrt, pi, abs, floor, ceil, max, min, exp = math.sin, math.cos, math.tan, math.atan,
  math.sqrt, math.pi, math.abs, math.floor, math.ceil, math.max, math.min, math.exp

local function lerp(a, b, t) return a + (b - a) * t end
local function sm(a, b, x)
  local t = max(0, min(1, (x - a) / (b - a)))
  return t * t * (3 - 2 * t)
end

-- ---------------------------------------------------------------- options and seeds shared by every front end
function M.defaults()
  return {
    palette = "ultramarine", mode = "night", story = "threshold",
    threshold = 0.25,      -- share of the document where the beam crosses the threshold
    beam = "spectrum",     -- or mono: one wavelength, as a real laser
    wavelength = false,    -- nm of the one-colour beam; by default the palette's own
    caustic = "ellipse",   -- or cardioid, nephroid, rings, speckle, mix
    color = "rgb",         -- or cmyk, for a print shop
    bleed = 0,             -- mm added on every side of the sheet, with TrimBox and BleedBox
    sameart = false,       -- the same picture on every page: for animations
    level = 0.75,          -- the fixed stage of story=flat
    density = 1,           -- more or fewer lines of equal phase
    caustics = 2,          -- at most this many on a page, 0 for none
    lines = true, headings = true, finale = true, headrule = true, draft = false,
    column = false,        -- width of the coloured column in cm; false: up to the text
    seed = 1, paper = "FFFFFF", initialfont = "auto",
    step = 0.28,
  }
end

function M.seed_for(o, i) return floor(o.seed) * 7919 + (o.sameart and 1 or i) * 97 + 1030 end

-- ---------------------------------------------------------------- the story
-- One curve runs through the document, like laser output against pump power: almost nothing below the
-- threshold, then a nearly straight rise. With several thresholds it climbs in steps: each one starts a rise that
-- settles before the next. P(y) is the share of the document reached at height y of the page; the bottom of a page
-- continues into the top of the next.
--   prev: what the last run measured: pages, endpage, ths = { { i = page, y = share of page height } }, restarts
function M.make_story(page_index, ph, o, prev, override)
  local N = prev.endpage or prev.pages
  local ths = {}
  if N and o.story ~= "chapter" and prev.ths then
    for _, t in ipairs(prev.ths) do ths[#ths + 1] = max(0, min(0.9, ((t.i - 1) + (1 - t.y)) / N)) end
  end
  if #ths == 0 then ths[1] = o.threshold end
  table.sort(ths)
  local first_th, count = ths[1], #ths
  local S = {}
  function S.ramp(P)
    local sum = 0
    for i, lo in ipairs(ths) do
      local hi = i < count and lo + 0.65 * (ths[i + 1] - lo) or max(lo + 0.15, 0.95)
      local r = (P - lo) / max(1e-6, hi - lo)
      if r > 0 then sum = sum + min(1, r) ^ 0.85 end
    end
    return sum / count
  end
  local function under(P) return first_th <= 0 and 1 or max(0, min(1, P / first_th)) end
  function S.curve(P, a, b) return lerp(a, b, under(P)) + (1 - b) * S.ramp(P) end
  local first, last = 1, N
  if o.story == "chapter" and N then
    for i, r in ipairs(prev.restarts or {}) do
      if r <= page_index then
        first = r
        last = prev.restarts[i + 1] and prev.restarts[i + 1] - 1 or N
      end
    end
  end
  local fixed = override or (o.story == "flat" and o.level) or (not N and 0.6) or nil
  function S.P(y)
    if fixed then return fixed end
    local f = max(0, min(1, y / ph))
    return max(0, min(1, (page_index - first + 1 - f) / max(1, last - first + 1)))
  end
  return S
end

-- ---------------------------------------------------------------- random numbers: reproducible by seed
-- xorshift32. Written so that the same seed gives the same numbers with 64-bit integers (LuaTeX, Lua 5.3) and with
-- the 32-bit integers of Fengari in the browser.
local INT32 = math.maxinteger == 2147483647
local TWO32 = 2 ^ 32
local function mul32(a, b)
  local al, ah, bl, bh = a % 65536, floor(a / 65536), b % 65536, floor(b / 65536)
  return (al * bl + ((al * bh + ah * bl) % 65536) * 65536) % TWO32
end
local function new_rng(seed)
  local v = (mul32(seed % TWO32, 2654435761.0) + 12345) % TWO32
  if v == 0 then v = 88172645 end
  if INT32 and v >= 2147483648 then v = v - TWO32 end
  local s = math.tointeger(v)
  local r = {}
  local function nx()
    s = s ~ ((s << 13) & 0xFFFFFFFF)
    s = s ~ (s >> 17)
    s = s ~ ((s << 5) & 0xFFFFFFFF)
    return s < 0 and s + TWO32 or s
  end
  function r.u() return nx() / TWO32 end
  function r.range(a, b) return a + (b - a) * r.u() end
  function r.sym(a) return r.range(-a, a) end
  function r.fork() return new_rng(nx()) end
  for _ = 1, 4 do nx() end
  return r
end
M.new_rng = new_rng

-- ---------------------------------------------------------------- light
-- wavelength in nm to colour: not a colorimetric conversion but a rainbow with a real green in it
local STOPS = { { 400, 0.32, 0, 0.8 }, { 430, 0.28, 0, 1 }, { 465, 0, 0.22, 1 }, { 492, 0, 0.88, 1 }, { 522, 0, 1, 0.2 },
  { 562, 0.72, 1, 0 }, { 585, 1, 0.86, 0 }, { 620, 1, 0.36, 0 }, { 660, 1, 0, 0.04 }, { 700, 0.8, 0, 0.06 } }
local function wl(l)
  if l <= STOPS[1][1] then return STOPS[1][2], STOPS[1][3], STOPS[1][4] end
  for i = 2, #STOPS do
    local p, q = STOPS[i - 1], STOPS[i]
    if l <= q[1] then
      local t = (l - p[1]) / (q[1] - p[1])
      return p[2] + (q[2] - p[2]) * t, p[3] + (q[3] - p[3]) * t, p[4] + (q[4] - p[4]) * t
    end
  end
  local e = STOPS[#STOPS]
  return e[2], e[3], e[4]
end
M.wl = wl

local function make_strands(n)
  local t = {}
  for j = 1, n do
    local r, g, b = wl(430 + 230 * (j - 1) / (n - 1))
    t[j] = { r, g, b, (j - (n + 1) / 2) / ((n - 1) / 2) }
  end
  return t
end
local NL = 21
local STRANDS = make_strands(NL)

-- Mesh sizes are a trade-off with Poppler (Evince, Okular), which cuts a non-parametric Gouraud triangle into
-- pieces until each is nearly one colour: long thin cells across the spectrum cost it the least. With these
-- sizes a page takes 1 to 4 s there and about 0.1 s in PDFium (Chrome, Edge).
-- "preview" is for the page in the browser, where Lua runs about twenty times slower.
local Q = {}
function M.set_quality(level)
  if level == "preview" then
    Q = { ribbon = 25, fan = 41, field = 0.34, iso = 0.15, row = 0.5, fanrows = 10 }
    NL, STRANDS = 9, make_strands(9)
  else
    Q = { ribbon = 61, fan = 101, field = 0.16, iso = 0.07, row = 0.22, fanrows = 24 }
    NL, STRANDS = 21, make_strands(21)
  end
end
M.set_quality("full")

-- beam=mono: one wavelength, as a real laser. The story then shows in the width and heat of the beam alone.
local MONO
function M.configure(o, pal)
  if Pdf.set_colormodel then Pdf.set_colormodel(o.color) end
  MONO = nil
  if o.beam == "mono" then
    local nm = o.wavelength or pal.nm or 532
    if nm > 720 then MONO = { 1, 0.2, 0.06 }     -- infrared has no colour of its own: the false one of a thermal camera
    else
      local r, g, b = wl(nm)
      MONO = { r, g, b }
    end
  end
end

-- the light at distance q from the axis: strands spread over +-D, each a Gaussian of width sig.
-- E is the energy of the beam per unit length, ha and hal the strength and width of a faint halo.
local function light(q, D, sig, E, hal, ha)
  if MONO then
    local w = sqrt(sig * sig + 0.3 * D * D)
    local z = q / w
    local I = 0.5 * E / (w * 1.772) * exp(-z * z)
    local h = exp(-(q / hal) * (q / hal)) * ha
    local a, hot = 1 - exp(-1.6 * I - 0.8 * h), 1 - exp(-0.03 * I * I * I)
    return min(1, MONO[1] * a + hot), min(1, MONO[2] * a + hot), min(1, MONO[3] * a + hot)
  end
  local R, G, B = 0, 0, 0
  if NL < 21 then
    -- fewer strands in a preview: wider, so that they still merge
    local gap = 2 * D / (NL - 1)
    sig = sqrt(sig * sig + 0.45 * gap * gap)
  end
  for j = 1, NL do
    local c = STRANDS[j]
    local z = (q - c[4] * D) / sig
    local zz = z * z
    if zz < 9 then
      local g = exp(-zz)
      R, G, B = R + c[1] * g, G + c[2] * g, B + c[3] * g
    end
  end
  local k = 1.25 * E / (NL * sig * 1.772)
  local h = exp(-(q / hal) * (q / hal)) * ha
  -- brightness saturates but the hue is kept, otherwise every green drifts to yellow and every blue to cyan
  R, G, B = R * k + 0.5 * h, G * k + 0.55 * h, B * k + 1.1 * h
  local m = max(R, G, B)
  if m < 1e-6 then return 0, 0, 0 end
  local s = (1 - exp(-1.6 * m)) / m
  return R * s, G * s, B * s
end

-- Laying light over what is underneath. On a night field it glows and covers the field by its own strength,
-- so red stays red over blue instead of turning magenta. On paper it becomes ink: its hue with coverage equal
-- to its strength, and whatever is white in it (the narrow beam) in the dark ink.
local function add_night(fr, fg, fb, R, G, B)
  local keep = 1 - max(R, G, B)
  return R + fr * keep, G + fg * keep, B + fb * keep
end
local function add_paper(ink)
  return function(fr, fg, fb, R, G, B)
    local a = max(R, G, B)
    if a < 1e-4 then return fr, fg, fb end
    local w = min(R, G, B) / a
    local r, g, b = lerp(R / a, ink[1], w), lerp(G / a, ink[2], w), lerp(B / a, ink[3], w)
    return lerp(fr, r, a), lerp(fg, g, a), lerp(fb, b, a)
  end
end

-- A ribbon of light along a path of { x, y, D, sig, E, hal, ha }, with colour = comp(x, y, R, G, B). Near a
-- tight bend the inner side is cut short so the mesh does not fold over itself.
local function ribbon(cv, path, comp, ncol)
  local n, rows = #path, {}
  for k = 1, n do
    local p, a, b = path[k], path[max(1, k - 1)], path[min(n, k + 1)]
    local tx, ty = b[1] - a[1], b[2] - a[2]
    local l = max(1e-6, sqrt(tx * tx + ty * ty))
    local nx, ny = -ty / l, tx / l
    local D, sig, E, hal, ha = p[3], p[4], p[5], p[6], p[7]
    local w = D + max(2.8 * sig, 1.9 * hal)
    local wp, wn = w, w
    if k > 1 and k < n then
      local ux, uy, vx, vy = p[1] - a[1], p[2] - a[2], b[1] - p[1], b[2] - p[2]
      local kappa = 2 * (ux * vy - uy * vx) / max(1e-9, sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy) * l)
      if kappa > 1e-6 then wp = min(w, 0.9 / kappa) elseif kappa < -1e-6 then wn = min(w, 0.9 / -kappa) end
    end
    local row = {}
    for i = 1, ncol do
      local v = (i - 1) / (ncol - 1) * 2 - 1
      local av = abs(v)
      local q = av ^ 1.7 * (v < 0 and -wn or wp)
      local R, G, B = light(q, D, sig, E, hal, ha)
      local e = 1 - av * av * av * av
      local x, y = p[1] + nx * q, p[2] + ny * q
      row[i] = { x, y, comp(x, y, R * e, G * e, B * e) }
    end
    rows[k] = row
  end
  cv:mesh(rows, ncol)
end

-- a star where the spectrum has closed into white; white over colour with alpha is the same as adding light
local function star(cv, x, y, g, col, strength)
  strength = strength or 1
  for k = 0, 11 do
    cv:circle(x, y, 0.72 * 0.78 ^ k * g)
    cv:fill(col, (0.022 + 0.008 * k) * strength)
  end
  local function spike(dx, dy, L, wd, op)
    cv:poly({ { x - dy * wd, y + dx * wd }, { x + dx * L, y + dy * L }, { x + dy * wd, y - dx * wd },
      { x - dx * L, y - dy * L } }, true)
    cv:fill(col, op * strength)
  end
  spike(1, 0, 1.55 * g, 0.012 * g, 0.85)
  spike(0, 1, 1.55 * g, 0.012 * g, 0.85)
  local r = sqrt(0.5)
  spike(r, r, 0.42 * g, 0.009 * g, 0.55)
  spike(r, -r, 0.42 * g, 0.009 * g, 0.55)
  cv:circle(x, y, 0.055 * g)
  cv:fill(col, strength)
end

-- ---------------------------------------------------------------- lines of equal phase
local CASES = {
  [1] = { { "B", "L" } }, [2] = { { "R", "B" } }, [3] = { { "R", "L" } }, [4] = { { "T", "R" } },
  [6] = { { "T", "B" } }, [7] = { { "T", "L" } }, [8] = { { "L", "T" } }, [9] = { { "B", "T" } },
  [11] = { { "R", "T" } }, [12] = { { "L", "R" } }, [13] = { { "B", "R" } }, [14] = { { "L", "B" } },
}
-- marching squares for every level k * step at once; lines keep one thickness, unlike filled fringes
local function isolines(x0, y0, x1, y1, h, step, fn, tol)
  local nx, ny = ceil((x1 - x0) / h), ceil((y1 - y0) / h)
  local V = {}
  for j = 0, ny do
    local row, y = {}, y0 + h * j
    for i = 0, nx do row[i] = fn(x0 + h * i, y) end
    V[j] = row
  end
  local stride = nx + 1
  local L = {}
  for j = 0, ny - 1 do
    local r0, r1 = V[j], V[j + 1]
    for i = 0, nx - 1 do
      local a, b, c, d = r0[i], r0[i + 1], r1[i + 1], r1[i]
      for k = ceil(min(a, b, c, d) / step), floor(max(a, b, c, d) / step) do
        local level = k * step
        local idx = (a >= level and 1 or 0) + (b >= level and 2 or 0) + (c >= level and 4 or 0) + (d >= level and 8 or 0)
        if idx ~= 0 and idx ~= 15 then
          local lv = L[k]
          if not lv then lv = { nxt = {}, px = {}, py = {} } L[k] = lv end
          local px, py = lv.px, lv.py
          local function edge(e)
            local id
            if e == "B" then id = 2 * (j * stride + i)
              if not px[id] then px[id] = x0 + h * (i + (level - a) / (b - a)) py[id] = y0 + h * j end
            elseif e == "T" then id = 2 * ((j + 1) * stride + i)
              if not px[id] then px[id] = x0 + h * (i + (level - d) / (c - d)) py[id] = y0 + h * (j + 1) end
            elseif e == "L" then id = 2 * (j * stride + i) + 1
              if not px[id] then px[id] = x0 + h * i py[id] = y0 + h * (j + (level - a) / (d - a)) end
            else id = 2 * (j * stride + i + 1) + 1
              if not px[id] then px[id] = x0 + h * (i + 1) py[id] = y0 + h * (j + (level - b) / (c - b)) end
            end
            return id
          end
          local segs = CASES[idx]
          if idx == 5 then
            segs = ((a + b + c + d) / 4 >= level) and { { "B", "R" }, { "T", "L" } } or { { "B", "L" }, { "T", "R" } }
          elseif idx == 10 then
            segs = ((a + b + c + d) / 4 >= level) and { { "L", "B" }, { "R", "T" } } or { { "R", "B" }, { "L", "T" } }
          end
          for _, sg in ipairs(segs) do lv.nxt[edge(sg[1])] = edge(sg[2]) end
        end
      end
    end
  end
  -- everything in sorted order: the order of pairs() differs between Lua builds, and the drawing should not
  local out = {}
  local levels = {}
  for k in pairs(L) do levels[#levels + 1] = k end
  table.sort(levels)
  for _, k in ipairs(levels) do
    local lv = L[k]
    local nxt, px, py = lv.nxt, lv.px, lv.py
    local function walk(start)
      local pts, id = {}, start
      while id do
        local x, y = px[id], py[id]
        if #pts >= 2 then
          local p, q = pts[#pts - 1], pts[#pts]
          local ux, uy = x - p[1], y - p[2]
          local d2 = ux * ux + uy * uy
          local cr = (q[1] - p[1]) * uy - (q[2] - p[2]) * ux
          if d2 > 1e-9 and d2 < 0.04 and cr * cr / d2 < tol * tol then pts[#pts] = nil end
        end
        pts[#pts + 1] = { x, y }
        local f = nxt[id]
        nxt[id] = nil
        id = f
      end
      if #pts >= 2 then out[#out + 1] = pts end
    end
    local has, starts = {}, {}
    for _, t in pairs(nxt) do has[t] = true end
    for id in pairs(nxt) do if not has[id] then starts[#starts + 1] = id end end
    table.sort(starts)
    for _, id in ipairs(starts) do walk(id) end
    local rest = {}
    for id in pairs(nxt) do rest[#rest + 1] = id end
    table.sort(rest)
    for _, id in ipairs(rest) do if nxt[id] then walk(id) end end
  end
  return out
end

-- draw polylines whose opacity follows weight(x, y): cut into bands, one stroke per band
local BANDS = { 0.035, 0.06, 0.09, 0.13, 0.18, 0.25, 0.34, 0.45, 0.58, 0.74, 0.92 }
local function band_of(m)
  for b = #BANDS, 1, -1 do if m >= BANDS[b] then return b end end
  return 0
end
local function draw_lines(cv, lines, weight, col, w, op, glow)
  local groups = {}
  local function add(b, seg)
    local t = groups[b]
    if not t then t = {} groups[b] = t end
    t[#t + 1] = seg
  end
  for _, pts in ipairs(lines) do
    local cur, bb
    for _, q in ipairs(pts) do
      local b = band_of(weight(q[1], q[2]))
      if b ~= bb then
        if cur then
          cur[#cur + 1] = q
          if bb > 0 and #cur >= 2 then add(bb, cur) end
        end
        cur, bb = { q }, b
      else
        cur[#cur + 1] = q
      end
    end
    if cur and bb > 0 and #cur >= 2 then add(bb, cur) end
  end
  for b = 1, #BANDS do
    local list = groups[b]
    if list then
      local s = b == #BANDS and 1 or (BANDS[b] + BANDS[b + 1]) / 2
      if s >= 0.4 and glow > 0 then
        for _, l in ipairs(list) do cv:poly(l) end
        cv:stroke(col, w * 3.6, glow * op * s)
      end
      for _, l in ipairs(list) do cv:poly(l) end
      cv:stroke(col, w * (0.55 + 0.45 * s), op * s)
    end
  end
end

-- ---------------------------------------------------------------- caustics
-- Chrome and pdf.js widen hairlines to one pixel, Poppler does not. Few chords of a moderate width look alike
-- in all of them; hundreds of very thin ones turn into a solid gold disc on screen in the first two.
local CAUSTIC_W = 0.3
local function trace_orbit(a, b, rot, phi, N)
  local px, py = a * cos(phi), b * sin(phi)
  local dth = 2 * pi * rot
  local dx, dy = a * cos(phi + dth) - px, b * sin(phi + dth) - py
  local l = sqrt(dx * dx + dy * dy)
  dx, dy = dx / l, dy / l
  local pts = { { px, py } }
  for i = 1, N do
    local t = -2 * (px * dx / (a * a) + py * dy / (b * b)) / (dx * dx / (a * a) + dy * dy / (b * b))
    px, py = px + t * dx, py + t * dy
    pts[i + 1] = { px, py }
    local nx, ny = px / (a * a), py / (b * b)
    local d = 2 * (dx * nx + dy * ny) / (nx * nx + ny * ny)
    dx, dy = dx - d * nx, dy - d * ny
  end
  return pts
end
-- A good orbit lies evenly on the mirror. Two large gaps are legitimate (the hourglass caustic); a third
-- means bundles with holes, the ones that read as stars and symbols.
local function orbit_ok(pts, a, b)
  local us = {}
  for i, q in ipairs(pts) do us[i] = (atan(q[2] / b, q[1] / a) + pi) / (2 * pi) end
  table.sort(us)
  local gaps, n = {}, #us
  for i = 1, n - 1 do gaps[i] = us[i + 1] - us[i] end
  gaps[n] = us[1] + 1 - us[n]
  table.sort(gaps, function(x, y) return x > y end)
  return gaps[3] <= 4 / n and gaps[1] <= 0.3
end
local function pick_orbit(r, a, b, N)
  for _ = 1, 40 do
    local rot, phi = r.range(0.33, 0.47), r.range(0, 6.283)
    local pts = trace_orbit(a, b, rot, phi, N)
    if orbit_ok(pts, a, b) then return pts end
  end
  return nil
end
-- Bessel J1, polynomial approximation from Abramowitz and Stegun, 9.4.4 and 9.4.6
local function j1(x)
  local ax = abs(x)
  if ax < 3 then
    local t = (x / 3) ^ 2
    return x * (0.5 + t * (-0.56249985 + t * (0.21093573 + t * (-0.03954289 + t * (0.00443319 + t * (-0.00031761 + t * 0.00001109))))))
  end
  local t = 3 / ax
  local f = 0.79788456 + t * (0.00000156 + t * (0.01659667 + t * (0.00017105 + t * (-0.00249511 + t * (0.00113653 - t * 0.00020033)))))
  local th = ax - 2.35619449 + t * (0.12499612 + t * (0.00005650 + t * (-0.00637879 + t * (0.00074348 + t * (0.00079824 - t * 0.00029166)))))
  local v = f * cos(th) / sqrt(ax)
  return x < 0 and -v or v
end

-- rings: the diffraction pattern of a round aperture, (2 J1(x) / x)^2, out to its fifth dark ring. Its outer
-- rings would be invisible at their true brightness, so they are lifted by a power. A mesh, drawn before the lines.
local function draw_rings(cv, cx, cy, R, comp, cols, strength)
  local rows, nt = {}, 49
  for j = 0, 90 do
    local r = R * j / 90
    local x = 16.47 * j / 90
    local I = (x < 1e-3 and 1 or (2 * j1(x) / x) ^ 2) ^ 0.34
    local e = strength * I * (1 - (j / 90) ^ 4)
    local c = cols[j % 2 + 1]
    local row = {}
    for i = 1, nt do
      local th = 2 * pi * (i - 1) / (nt - 1)
      local px, py = cx + r * cos(th), cy + r * sin(th)
      row[i] = { px, py, comp(px, py, c[1] * e, c[2] * e, c[3] * e) }
    end
    rows[j + 1] = row
  end
  cv:mesh(rows, nt)
end

-- cardioid and nephroid: the caustics of a cup. Rays from a point on the rim draw the first (a chord to twice the
-- angle), parallel rays the second (a chord to three times the angle).
local function draw_cup(cv, cx, cy, R, w, k, cols, op, lw, N)
  local function P(a) return { cx + R * cos(a + w), cy + R * sin(a + w) } end
  for tone = 0, 1 do
    for i = tone, N - 1, 2 do
      local a = 2 * pi * i / N
      cv:poly({ P(a), P(k * a) })
    end
    cv:stroke(cols[tone + 1], lw, op)
  end
end

-- speckle: what a coherent beam makes on a rough wall, a sum of waves with random directions and phases. A dot at
-- every bright maximum, so a fine gold dust rather than a pattern. It fades towards the rim.
local function draw_speckle(cv, r, cx, cy, R, cols, op, u)
  local waves = {}
  local kmax = 2 * pi / (0.24 * u)
  for i = 1, 36 do
    local a, k = r.range(0, 2 * pi), kmax * sqrt(r.u())
    waves[i] = { k * cos(a), k * sin(a), r.range(0, 2 * pi) }
  end
  local h = 0.05 * u
  local n = ceil(R / h)
  local I = {}
  for j = -n, n do
    local row = {}
    for i = -n, n do
      local a, b = 0, 0
      local x, y = i * h, j * h
      for w = 1, 36 do
        local v = waves[w]
        local ph = v[1] * x + v[2] * y + v[3]
        a, b = a + cos(ph), b + sin(ph)
      end
      row[i] = (a * a + b * b) / 36
    end
    I[j] = row
  end
  local bands = { {}, {}, {} }
  for j = -n + 1, n - 1 do
    for i = -n + 1, n - 1 do
      local v = I[j][i]
      local x, y = i * h, j * h
      local d = sqrt(x * x + y * y) / R
      if d < 1 and v > 0.7 and v >= I[j][i - 1] and v >= I[j][i + 1] and v >= I[j - 1][i] and v >= I[j + 1][i] then
        local f = 1 - d * d * d
        local b = v * f > 2.2 and 3 or (v * f > 1.1 and 2 or 1)
        local list = bands[b]
        list[#list + 1] = { cx + x, cy + y, (0.012 + 0.012 * min(v, 3)) * u * sqrt(f) }
      end
    end
  end
  for b, list in ipairs(bands) do
    if #list > 0 then
      for _, q in ipairs(list) do cv:circle(q[1], q[2], q[3]) end
      cv:fill(cols[b % 2 + 1], op * (0.35 + 0.325 * b))
    end
  end
end

local function draw_orbit(cv, pts, cx, cy, w, colours, op, lw)
  local ca, sa = cos(w), sin(w)
  local P = {}
  for i, q in ipairs(pts) do P[i] = { cx + q[1] * ca - q[2] * sa, cy + q[1] * sa + q[2] * ca } end
  for i = 1, #P - 1, 2 do cv:poly({ P[i], P[i + 1] }) end
  cv:stroke(colours[1], lw, op)
  for i = 2, #P - 1, 2 do cv:poly({ P[i], P[i + 1] }) end
  cv:stroke(colours[2], lw, op)
end

-- ---------------------------------------------------------------- the field shared by pages and covers
-- returns colour(x, y) of the bare field and the path difference it is built on
local function make_field(g, S, pal, o, rng, mask)
  local u, ph = g.u, g.ph
  local function src()
    return rng.range(-1.6, -0.6) * u, rng.sym(0.8) * u, rng.range(1.0, 2.6) * u, rng.sym(0.8) * u
  end
  local a1x, a1d, b1x, b1d = src()
  local a2x, a2d, b2x, b2d = src()
  local a3x, a3d, b3x, b3d = src()
  local y1, y2, y3 = ph + 1.6 * u, ph * 0.5, -1.6 * u
  local a1y, b1y = y1 - 2 * u + a1d, y1 + 3 * u + b1d
  local a2y, b2y = y2 - 1 * u + a2d, y2 + 4.5 * u + b2d
  local a3y, b3y = y3 + 2 * u + a3d, y3 - 3 * u + b3d
  local p72, p50, p42, p20 = ph * 0.72, ph * 0.5, ph * 0.42, ph * 0.2
  local function pathdiff(x, y)
    local function d(ax, ay, bx, by)
      local ux, uy, vx, vy = x - ax, y - ay, x - bx, y - by
      return sqrt(ux * ux + uy * uy) - sqrt(vx * vx + vy * vy)
    end
    local t1, t2 = sm(p72, p50, y), sm(p42, p20, y)
    local D = d(a1x, a1y, b1x, b1y)
    D = D * (1 - t1) + d(a2x, a2y, b2x, b2y) * t1
    return D * (1 - t2) + d(a3x, a3y, b3x, b3y) * t2
  end
  local paper = Pdf.hex(o.paper)
  local night = o.mode ~= "paper"
  local deep, flows, ink = pal.deep, pal.flows, pal.ink
  local function colour(x, y)
    local m = mask(x, y)
    if m <= 0 then return paper[1], paper[2], paper[3] end
    local r, gr, b
    if night then
      r, gr, b = deep[1], deep[2], deep[3]
      local ff = S.curve(S.P(y), 0.06, 0.14)
      local f = (pathdiff(x, y) / (8.2 * u) + 0.13 * sin(y / (2.9 * u)) + 0.05 * sin(x / (0.9 * u))) % 1
      for _, fl in ipairs(flows) do
        local d = abs(f - fl[2])
        d = min(d, 1 - d)
        local w = ff * fl[3] * sm(0.3, 0.02, d)
        local c = fl[1]
        r, gr, b = lerp(r, c[1], w), lerp(gr, c[2], w), lerp(b, c[3], w)
      end
    else
      r, gr, b = lerp(paper[1], ink[1], 0.05), lerp(paper[2], ink[2], 0.05), lerp(paper[3], ink[3], 0.05)
    end
    return lerp(paper[1], r, m), lerp(paper[2], gr, m), lerp(paper[3], b, m)
  end
  return colour, pathdiff
end

local function field_mesh(cv, colour, x0, y0, x1, y1, h)
  local nx, ny = ceil((x1 - x0) / h), ceil((y1 - y0) / h)
  local rows = {}
  for j = 0, ny do
    local row, y = {}, y0 + (y1 - y0) * j / ny
    for i = 0, nx do
      local x = x0 + (x1 - x0) * i / nx
      row[i + 1] = { x, y, colour(x, y) }
    end
    rows[j + 1] = row
  end
  cv:mesh(rows, nx + 1)
end

-- ---------------------------------------------------------------- a page
function M.page(g, S, pal, o, marks, seed)
  local cv = M.surface()
  local rng = new_rng(seed)
  local layout = rng.fork()
  local u, W, ph, pw = g.u, g.colright, g.ph, g.pw
  local night = o.mode ~= "paper"
  local bl = g.bleed or 0
  if g.mirror then cv:mirror(pw) end

  -- the shape of the night: a wide soft edge, and a lake below the text on the closing page
  local lake = g.lake
  local ym = lake and g.textend - 0.45 * u or 0
  local e1, e2, e3, t1, t2, t3 = rng.range(0, 6.28), rng.range(0, 6.28), rng.range(0, 6.28),
    rng.range(0, 6.28), rng.range(0, 6.28), rng.range(0, 6.28)
  local fade = min(1.4 * u, 0.5 * W)
  local function mask(x, y)
    local yy = y / u
    local e = W - 0.2 * u + 0.3 * u * (0.6 * sin(yy / 3.3 + e1) + 0.3 * sin(yy / 1.9 + e2) + 0.1 * sin(yy / 0.9 + e3))
    local m = sm(e, e - fade, x)
    if lake and y < ym then
      local xx = x / u
      local top = ym - 0.25 * u + 0.3 * u * (0.6 * sin(xx / 3.3 + t1) + 0.3 * sin(xx / 1.9 + t2) + 0.1 * sin(xx / 0.9 + t3))
      local q = sm(top, top - 1.4 * u, y)
      m = m + q - m * q
    end
    return m
  end
  local colour, pathdiff = make_field(g, S, pal, o, rng, mask)
  local x1 = lake and pw + 0.1 + bl or W + 0.5 * u
  field_mesh(cv, colour, -0.1 - bl, -0.1 - bl, x1, ph + 0.1 + bl, max(0.09, Q.field * u))

  local add = night and add_night or add_paper(pal.ink)
  local function comp(x, y, R, G, B)
    local fr, fg, fb = colour(x, y)
    return add(fr, fg, fb, R, G, B)
  end

  -- ------------------------------------------------ the nodes of the beam: headings, stars, even supports
  local xr = W - 1.25 * u
  if xr < 0.5 * W then xr = 0.55 * W end
  local nodes = {}
  for _, mk in ipairs(marks) do
    if mk.kind == "heading" and o.headings then
      nodes[#nodes + 1] = { y = mk.y + 0.13, size = (tonumber(mk.arg) or 2) <= 1 and 0.98 or 0.74, head = true }
    elseif mk.kind == "star" then
      nodes[#nodes + 1] = { y = mk.y + 0.13, size = 0.74, head = true }
    elseif mk.kind == "threshold" then
      nodes[#nodes + 1] = { y = mk.y + 0.13, size = 1.25, head = true }
    end
  end
  for _, n in ipairs(g.extra_nodes or {}) do nodes[#nodes + 1] = n end
  table.sort(nodes, function(a, b) return a.y > b.y end)
  local final
  if lake then
    local R = min(3.2 * u, (ym - 1.2 * u) / 2)
    local fy = max(R * 0.9 + 0.7 * u, min(ym - 4.6 * u, ym - R * 0.9 - 0.5 * u))
    final = { x = W * 0.66, y = fy, R = R, lake = true }
  elseif g.closing then
    local R = min(1.3 * u, W * 0.3)
    final = { x = W * 0.62, y = max(2.6 * u, g.ybot * 0.7), R = R }
  end
  local kept, last = {}, ph + 1
  for _, n in ipairs(nodes) do
    if last - n.y >= 1.6 * u and n.y > 0.3 and (not final or n.y > final.y + 2 * u) then
      kept[#kept + 1] = n
      last = n.y
    end
  end
  local seq = { { y = ph + 0.6 * u + bl, edge = true } }
  local function push(n)
    local p = seq[#seq]
    local gap = p.y - n.y
    local parts = max(1, floor(gap / (7.6 * u) + 0.35))
    for i = 1, parts - 1 do seq[#seq + 1] = { y = p.y - gap * i / parts, inner = true } end
    seq[#seq + 1] = n
  end
  for _, n in ipairs(kept) do push(n) end
  push(final and { y = final.y, x = final.x, final = true } or { y = -0.6 * u - bl, edge = true })

  -- ------------------------------------------------ caustics in the free gaps, or where the text asks
  local calm, plan = {}, {}
  local used = 0
  for _, mk in ipairs(marks) do
    if mk.kind == "caustic" then
      local arg = tostring(mk.arg or "")
      local R = (tonumber(arg) or tonumber(arg:match("size%s*=%s*([%d.]+)")) or 1.3) * u
      plan[#plan + 1] = { x = 0.34 * u + R, y = mk.y, R = R, P = S.P(mk.y), kind = arg:match("kind%s*=%s*(%a+)") }
      used = used + 1
      for i = 2, #seq do
        if seq[i - 1].y >= mk.y and seq[i].y <= mk.y then seq[i].calm = true end
      end
    end
  end
  local avail = xr - 0.55 * u - 0.34 * u
  local skip = false
  if o.caustics > 0 then
    for i = 2, #seq do
      local p, n = seq[i - 1], seq[i]
      local gap = p.y - n.y
      local Pc = S.P(n.y + gap / 2)
      local limit = S.ramp(Pc) > 0 and o.caustics or min(1, o.caustics)
      if not skip and used < limit and gap >= 5.2 * u and not n.final then
        local R = min(1.5 * u, gap / 2 - 0.75 * u, avail / 2 + 0.2 * u)
        local cy = n.y + gap / 2
        if cy > 1.2 * u and cy < ph - 1.2 * u and R >= 0.8 * u then
          n.calm = true
          plan[#plan + 1] = { x = 0.34 * u + R + layout.range(0, 0.2) * u, y = cy, R = R, P = Pc }
          used = used + 1
          skip = true
        end
      else
        skip = false
      end
    end
  end

  -- ------------------------------------------------ the beam
  local Dmax = min(0.82 * u, 0.17 * W)
  local beam = {}
  for i = 2, #seq do
    local p, n = seq[i - 1], seq[i]
    local xa, xb = p.x or xr, n.x or xr
    local gapy = p.y - n.y
    local room = xr - 0.35 * u - Dmax
    local maxamp = min(room, gapy * gapy / (2 * pi * pi * 1.0 * u))
    if n.calm then maxamp = min(maxamp, 0.55 * u) end
    local G0 = S.curve(S.P((p.y + n.y) / 2), 0.04, 0.07)
    local amp = layout.range(0.72, 1) * maxamp * lerp(0.72, 1, G0)
    local w2 = layout.sym(0.2) * u * min(1, gapy / (5 * u))
    local steps = max(12, floor(gapy / (Q.row * u)))
    local widen = min(1, gapy / (6.5 * u) + 0.2) * (n.calm and 0.78 or 1)
    local path, seg = {}, { y0 = p.y, y1 = n.y, xc = {}, hw = {}, n = steps }
    for k = 0, steps do
      local t = k / steps
      local s = sin(pi * t)
      local x = lerp(xa, xb, t) - amp * s * s + w2 * sin(2 * pi * t) * s
      local y = p.y - gapy * t
      local sp = (s ^ 1.05) * widen * S.curve(S.P(y), 0.04, 0.07)
      local D = Dmax * sp
      local sig = (0.03 + 0.06 * sp) * u
      local E = 3.2 * Dmax * (0.35 + 0.65 * sm(0, 0.5, sp))
      path[k + 1] = { x, y, D, sig, E, (0.12 + 0.25 * sp) * u, lerp(0.2, 0.1, sm(0, 0.4, sp)) }
      seg.xc[k] = x
      seg.hw[k] = D + 2 * sig
    end
    ribbon(cv, path, comp, Q.ribbon)
    beam[#beam + 1] = seg
  end

  -- the closing fan: a straight ribbon whose spread grows along it, leaving through the page edge
  local fan
  if final then
    local axis, half, xe
    if final.lake then
      xe = pw + 0.5 + bl
      local L0 = xe - final.x
      axis = -3.5 * pi / 180
      local up = atan((ym - 0.5 * u - final.y) / L0) - axis
      half = min(11.5 * pi / 180, max(5 * pi / 180, up))
    else
      xe = -0.5 - bl
      axis = pi + 6 * pi / 180
      half = 16 * pi / 180
    end
    local L = abs(xe - final.x) / abs(cos(axis))
    local rows = Q.fanrows
    local path = {}
    for k = 0, rows do
      local t = k / rows
      local d = L * t
      local D = max(1e-3, d * tan(half))
      local sig = (0.012 * u + D * 0.11)
      path[k + 1] = { final.x + cos(axis) * d, final.y + sin(axis) * d, D, sig, 3.2 * D + 0.5 * u, (0.1 * u + D * 0.2), 0.1 }
    end
    ribbon(cv, path, comp, Q.fan)
    fan = { x = final.x, y = final.y, axis = axis, half = half }
  end

  -- ------------------------------------------------ what kind each caustic is; rings are meshes and go first
  local function kind_for(c)
    if c.kind then return c.kind end
    if o.caustic ~= "mix" then return o.caustic end
    local v = layout.u()
    if v < 0.55 then return "ellipse" elseif v < 0.7 then return "cardioid"
    elseif v < 0.85 then return "nephroid" else return "rings" end
  end
  local cols = night and pal.caustic or { pal.ink, pal.accent }
  local cop = night and pal.causticop or 0.55
  for _, c in ipairs(plan) do
    c.kind = kind_for(c)
    if c.kind == "rings" then draw_rings(cv, c.x, c.y, c.R, comp, cols, 0.8 * S.curve(c.P, 0.3, 0.42) * cop) end
  end
  local fk = (o.caustic == "mix" or o.caustic == "speckle") and "ellipse" or o.caustic
  if final and fk == "rings" then draw_rings(cv, final.x, final.y, final.R, comp, cols, 0.7 * cop) end

  -- ------------------------------------------------ lines over the colour, passing behind the beam
  for _, c in ipairs(plan) do calm[#calm + 1] = c end
  if final then calm[#calm + 1] = final end
  if o.lines then
    local paths = isolines(-0.35 - bl, -0.35 - bl, x1, ph + 0.35 + bl, max(0.05, Q.iso * u), o.step * u / o.density, pathdiff, 0.004)
    local pa, pb, pc = rng.range(0, 6.28), rng.range(0, 6.28), rng.range(0, 6.28)
    local function weight(x, y)
      local m = mask(x, y)
      if m <= 0.05 then return 0 end
      local Py = S.P(y)
      local xx, yy = x / u, y / u
      local nz = 0.6 * sin(xx / 1.7 + pa) * cos(yy / 2.6 + pb) + 0.4 * sin((xx + yy) / 3.4 + pc)
      local T = lerp(0.1, -1.7, sm(0.05, 0.6, Py))
      m = m * S.curve(Py, 0.16, 0.26) * sm(T, T + 0.6, nz)
      for _, c in ipairs(calm) do
        local dx, dy = x - c.x, y - c.y
        local d2 = (dx * dx + dy * dy) / (c.R * c.R)
        if d2 < 1.35 then m = m * lerp(0.3, 1, sm(0.75, 1.35, d2)) end
      end
      for _, sg in ipairs(beam) do
        if y <= sg.y0 and y >= sg.y1 then
          local k = floor((sg.y0 - y) / (sg.y0 - sg.y1) * sg.n + 0.5)
          local d = abs(x - sg.xc[k]) / (sg.hw[k] + 0.06 * u)
          m = m * lerp(0.12, 1, sm(0.8, 1.25, d))
          break
        end
      end
      if fan then
        local dx, dy = x - fan.x, y - fan.y
        local ang = atan(dy, dx) - fan.axis
        ang = (ang + pi) % (2 * pi) - pi
        if abs(ang) < fan.half * 1.1 then m = m * 0.45 end
      end
      return m
    end
    if night then
      draw_lines(cv, paths, weight, pal.line, 0.38, pal.lineop, 0.1)
    else
      draw_lines(cv, paths, weight, pal.ink, 0.3, 0.42, 0)
    end
  end

  -- ------------------------------------------------ caustics
  for _, c in ipairs(plan) do
    local op = 0.8 * S.curve(c.P, 0.16, 0.24) * cop
    local N = floor(c.R * lerp(58, 78, S.ramp(c.P)))
    local drawn = true
    if c.kind == "cardioid" or c.kind == "nephroid" then
      draw_cup(cv, c.x, c.y, c.R, layout.range(0, 2 * pi), c.kind == "cardioid" and 2 or 3, cols, op, CAUSTIC_W, floor(N * 1.1))
    elseif c.kind == "speckle" then
      draw_speckle(cv, layout, c.x, c.y, c.R, cols, min(1, op * 2.2), u)
    elseif c.kind ~= "rings" then
      local orbit = pick_orbit(layout, c.R, c.R * layout.range(0.78, 0.92), N)
      drawn = orbit ~= nil
      if orbit then draw_orbit(cv, orbit, c.x, c.y, layout.sym(0.6), cols, op, CAUSTIC_W) end
    end
    if drawn then star(cv, c.x, c.y, 0.4 * u * lerp(0.6, 1, S.ramp(c.P)), night and { 1, 0.97, 0.9 } or pal.ink) end
  end
  if final and fk == "cardioid" or final and fk == "nephroid" then
    draw_cup(cv, final.x, final.y, final.R, 0.22, fk == "cardioid" and 2 or 3, cols, 0.72 * cop, CAUSTIC_W, floor(final.R * 62))
  elseif final and fk == "ellipse" then
    local orbit = trace_orbit(final.R, final.R * 0.8, 0.3819, 0.9, floor(final.R * 62))
    draw_orbit(cv, orbit, final.x, final.y, 0.22, cols, 0.72 * cop, CAUSTIC_W)
  end

  -- ------------------------------------------------ stars
  local white = night and { 1, 0.97, 0.9 } or pal.ink
  for i = 2, #seq do
    local n = seq[i]
    local q = lerp(0.72, 1, S.ramp(S.P(n.y))) * u
    -- a star means a heading or a mark in the text; on a long stretch without one the beam only narrows
    if n.head then star(cv, xr, n.y, n.size * q, white)
    elseif n.final then star(cv, n.x, n.y, (final.lake and 1.5 or 0.9) * u, white) end
  end

  -- the head rule starts in the margin and runs to the end of the text
  if o.headrule and g.headrule then
    local a = pal.accent
    cv:circle(g.colright + 0.02, g.headrule, 0.045)
    cv:fill(a)
    cv:moveto(g.colright + 0.02, g.headrule)
    cv:lineto(g.textright, g.headrule)
    cv:stroke(a, 0.4)
  end
  if g.mirror then cv:unmirror() end
  return cv
end

-- ---------------------------------------------------------------- the cover: the whole sheet
-- style spectrum: the full fan, the promise of the document. Style dark: only the thin white beam.
function M.cover(g, S, pal, o, style, seed)
  local cv = M.surface()
  local rng = new_rng(seed)
  local u, pw, ph = g.u, g.pw, g.ph
  local night = o.mode ~= "paper"
  local dark = style == "dark"
  local function mask() return 1 end
  local colour, pathdiff = make_field(g, S, pal, o, rng, mask)
  local bl = g.bleed or 0
  field_mesh(cv, colour, -0.1 - bl, -0.1 - bl, pw + 0.1 + bl, ph + 0.1 + bl, max(0.12, 0.2 * u))
  local add = night and add_night or add_paper(pal.ink)
  local function comp(x, y, R, G, B)
    local fr, fg, fb = colour(x, y)
    return add(fr, fg, fb, R, G, B)
  end
  local cx, cy = 0.3 * pw, 0.4 * ph
  local R = min(0.2 * pw, 0.27 * ph)
  -- the incoming beam, thin and white
  local path = {}
  local x0, y0 = -0.5 - bl, cy + 0.34 * ph
  local steps = 80
  for k = 0, steps do
    local t = k / steps
    local x = lerp(x0, cx, t)
    local y = lerp(y0, cy, t) + 0.06 * ph * sin(pi * t)
    path[k + 1] = { x, y, 0.002, 0.03 * u, 3.9 * 0.82 * u * 0.35, 0.16 * u, 0.2 }
  end
  ribbon(cv, path, comp, Q.ribbon)
  local axis = -9 * pi / 180
  local xe = pw + 0.5 + bl
  local L = (xe - cx) / cos(axis)
  local half = 12 * pi / 180
  if dark then
    local p2 = {}
    for k = 0, 40 do
      local t = k / 40
      p2[k + 1] = { cx + cos(axis) * L * t, cy + sin(axis) * L * t, 0.012 * u, 0.03 * u, 3.9 * 0.82 * u * 0.35, 0.16 * u, 0.2 }
    end
    ribbon(cv, p2, comp, Q.ribbon)
  else
    local rows, p2 = Q.fanrows, {}
    for k = 0, rows do
      local d = L * k / rows
      local D = max(1e-3, d * tan(half))
      p2[k + 1] = { cx + cos(axis) * d, cy + sin(axis) * d, D, 0.012 * u + D * 0.11, 3.2 * D + 0.5 * u, 0.1 * u + D * 0.2, 0.1 }
    end
    ribbon(cv, p2, comp, Q.fan)
  end
  if o.lines then
    local paths = isolines(-0.35 - bl, -0.35 - bl, pw + 0.35 + bl, ph + 0.35 + bl, max(0.06, 0.09 * u), o.step * 1.3 * u / o.density, pathdiff, 0.005)
    local function weight(x, y)
      local dx, dy = x - cx, y - cy
      local d2 = (dx * dx + dy * dy) / (R * R)
      local m = dark and 0.3 or 1
      if d2 < 1.35 then m = m * lerp(0.3, 1, sm(0.75, 1.35, d2)) end
      if not dark then
        local ang = (atan(dy, dx) - axis + pi) % (2 * pi) - pi
        if abs(ang) < half * 1.1 then m = m * 0.45 end
      end
      return m
    end
    if night then
      draw_lines(cv, paths, weight, pal.line, 0.34, pal.lineop * 0.8, 0.08)
    else
      draw_lines(cv, paths, weight, pal.ink, 0.28, 0.4, 0)
    end
  end
  local cols = night and pal.caustic or { pal.ink, pal.accent }
  local orbit = trace_orbit(R, R * 0.8, 0.3819, 0.9, floor(R * 55))
  draw_orbit(cv, orbit, cx, cy, 0.22, cols, (dark and 0.3 or 0.72) * (night and pal.causticop or 0.55), CAUSTIC_W)
  star(cv, cx, cy, 1.6 * u, night and { 1, 0.97, 0.9 } or pal.ink)
  return cv
end

-- ---------------------------------------------------------------- slides: the same page, narrower
-- A frame has no marks to lean on: the beam is held by a star at the frame title.
function M.slide_nodes(g)
  return { { y = g.ph - 0.95 * g.u * 2, size = 0.8, head = true } }
end

-- ---------------------------------------------------------------- initials
local shapes_cache = {}
local function outline(cv, file, char, cx, cy, h, w)
  local f = shapes_cache[file]
  if not f then
    local path = file
    local fh = io.open(path, "rb")
    if fh then fh:close()
    else path = kpse.find_file(file, "opentype fonts") or kpse.find_file(file, "truetype fonts") end
    if not path then return nil, "font not found: " .. file end
    local shapes = fonts.handlers.otf.readers.loadshapes(path)
    local byuni = {}
    for _, gl in pairs(shapes.glyphs or {}) do
      if type(gl.unicode) == "number" and not byuni[gl.unicode] then byuni[gl.unicode] = gl end
    end
    f = { byuni = byuni }
    shapes_cache[file] = f
  end
  local gl = f.byuni[utf8.codepoint(char)]
  if not gl or not gl.segments then return nil, "no outline for '" .. char .. "' in " .. file end
  local bb = gl.boundingbox
  local k = min(h / (bb[4] - bb[2]), w / (bb[3] - bb[1]))
  local ox, oy = cx - k * (bb[1] + bb[3]) / 2, cy - k * (bb[2] + bb[4]) / 2
  return function()
    local lx, ly = 0, 0
    local open = false
    for _, sg in ipairs(gl.segments) do
      local op = sg[#sg]
      if op == "m" then
        if open then cv:close() end
        lx, ly = ox + k * sg[1], oy + k * sg[2]
        cv:moveto(lx, ly)
        open = true
      elseif op == "l" then
        lx, ly = ox + k * sg[1], oy + k * sg[2]
        cv:lineto(lx, ly)
      elseif op == "c" then
        lx, ly = ox + k * sg[5], oy + k * sg[6]
        cv:curveto(ox + k * sg[1], oy + k * sg[2], ox + k * sg[3], oy + k * sg[4], lx, ly)
      elseif op == "q" then
        local qx, qy = ox + k * sg[1], oy + k * sg[2]
        local x3, y3 = ox + k * sg[3], oy + k * sg[4]
        cv:curveto(lx + 2 / 3 * (qx - lx), ly + 2 / 3 * (qy - ly), x3 + 2 / 3 * (qx - x3), y3 + 2 / 3 * (qy - y3), x3, y3)
        lx, ly = x3, y3
      end
    end
    if open then cv:close() end
  end
end

-- The tile follows the story: a thin white beam behind the letter early on, a spectrum later.
function M.initial(S, level, letter, file, pal, o)
  local cv = M.surface()
  local night = o.mode ~= "paper"
  local trace, err = outline(cv, file, letter, S * 0.5, S * 0.5, S * 0.7, S * 0.74)
  if not trace then return nil, err end
  local back = night and pal.deep or { 1, 1, 1 }
  cv:poly({ { 0, 0 }, { S, 0 }, { S, S }, { 0, S } }, true)
  cv:fill(back)
  local add = night and add_night or add_paper(pal.ink)
  local path = {}
  local Dm = S * 0.2 * level
  for k = 0, 60 do
    local t = k / 60
    local s = sin(pi * t)
    path[k + 1] = { S * t, S * (0.5 + 0.09 * sin(2 * pi * t)), Dm * s, S * (0.012 + 0.02 * level * s),
      3.9 * Dm + 0.05 * S, S * 0.07, 0.15 }
  end
  ribbon(cv, path, function(x, y, R, G, B) return add(back[1], back[2], back[3], R, G, B) end, 25)
  cv:poly({ { 0, 0 }, { S, 0 }, { S, S }, { 0, S } }, true)
  cv:stroke(night and pal.line or pal.ink, 0.5, 1)
  trace()
  cv:stroke(back, 1.7)
  trace()
  cv:fill(night and { 1, 0.84, 0.42 } or pal.ink)
  return cv
end

-- ---------------------------------------------------------------- ornaments in the text, always on paper
-- a spindle: dark at both ends, a spectrum in the middle
function M.rule(w, h, pal, o)
  local cv = M.surface()
  local add = add_paper(pal.ink)
  local paper = Pdf.hex(o.paper)
  local Dm = h * 0.38
  local path = {}
  for k = 0, 80 do
    local t = k / 80
    local s = sin(pi * t) ^ 1.4
    path[k + 1] = { w * t, h / 2, Dm * s, h * (0.03 + 0.06 * s), 3.9 * Dm * (0.35 + 0.65 * s), h * 0.1, 0.05 }
  end
  ribbon(cv, path, function(x, y, R, G, B) return add(paper[1], paper[2], paper[3], R, G, B) end, 31)
  return cv
end

-- a small four-pointed glint
function M.spark(s, c)
  local cv = M.surface()
  local m, k = s / 2, s * 0.06
  cv:moveto(m, 0)
  cv:curveto(m + k, m - k, m + k, m - k, s, m)
  cv:curveto(m + k, m + k, m + k, m + k, m, s)
  cv:curveto(m - k, m + k, m - k, m + k, 0, m)
  cv:curveto(m - k, m - k, m - k, m - k, m, 0)
  cv:close()
  cv:fill(c)
  return cv
end

-- a straight strip of the spectrum, for legends and captions
function M.spectrum(w, h, from, to)
  local cv = M.surface()
  local rows, n = { {}, {} }, 64
  for i = 0, n do
    local l = lerp(from, to, i / n)
    local r, g, b = wl(l)
    local f = 1
    if l < 420 then f = 0.3 + 0.7 * (l - 380) / 40 elseif l > 700 then f = 0.3 + 0.7 * (780 - l) / 80 end
    f = max(0, min(1, f))
    r, g, b = r * f, g * f, b * f
    rows[1][i + 1] = { w * i / n, 0, r, g, b }
    rows[2][i + 1] = { w * i / n, h, r, g, b }
  end
  cv:mesh(rows, n + 1)
  return cv
end

return M
