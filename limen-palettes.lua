-- limen-palettes.lua -- the built-in palettes. Part of limen, MIT License. See LICENSE.
--
--   deep    the colour of the night field
--   flows   slow colour currents: { colour, position 0..1 along the field, strength 0..1 }
--   line    the fine lines of equal phase
--   caustic the two tones of the caustics
--   ink     headings and the beam in paper mode (\color{limenink} in the document)
--   accent  rules and bullets (\color{limenaccent} in the document)
--   nm      the wavelength of the one-colour beam, with beam=mono

local hex = require("limen-pdf").hex

local function P(t)
  local out = { deep = hex(t.deep), line = hex(t.line), ink = hex(t.ink), accent = hex(t.accent),
    caustic = { hex(t.caustic[1]), hex(t.caustic[2]) }, lineop = t.lineop or 0.88, causticop = t.causticop or 1,
    nm = t.nm or 532,
    flows = {} }
  for i, f in ipairs(t.flows) do out.flows[i] = { hex(f[1]), f[2], f[3] } end
  return out
end

return {
  -- the main palette: deep blue night and gold lines
  ultramarine = P { deep = "0A1458", line = "F2BE46", ink = "1B2F8F", accent = "C9971E",
    caustic = { "FFB02E", "FFD36B" },
    flows = { { "2145B8", 0.20, 0.64 }, { "1B3AA6", 0.52, 0.47 }, { "3A2FA8", 0.82, 0.43 } } },
  -- teal and emerald with violet: softer, the colour competes more with the beam
  peacock = P { deep = "0A1650", line = "9FE8DC", ink = "0E5F73", accent = "B98A22",
    caustic = { "FFD08A", "FFE7B8" }, lineop = 0.66, causticop = 0.8,
    flows = { { "0C7A86", 0.10, 0.70 }, { "109A7E", 0.30, 0.66 }, { "4A2AA6", 0.72, 0.50 } } },
  -- the ruby laser, 694 nm
  ruby = P { nm = 694, deep = "2A0614", line = "FFC9A3", ink = "8E1B3A", accent = "C9773A",
    caustic = { "FFB38A", "FFE0C2" }, lineop = 0.7, causticop = 0.85,
    flows = { { "7A1030", 0.18, 0.66 }, { "A81C3C", 0.50, 0.42 }, { "4A1060", 0.80, 0.50 } } },
  -- frequency-doubled Nd:YAG, 532 nm
  emerald = P { deep = "04231C", line = "C8F27A", ink = "0B6B4B", accent = "A8962E",
    caustic = { "D8E86A", "F2F7B5" }, lineop = 0.62, causticop = 0.85,
    flows = { { "0C6B4E", 0.18, 0.66 }, { "0E8A6A", 0.48, 0.48 }, { "0A4E66", 0.80, 0.50 } } },
  -- Nd:YAG itself, 1064 nm, in the colours of a thermal camera
  infrared = P { nm = 1064, deep = "150A2E", line = "FFC46B", ink = "6A1F86", accent = "D9722A",
    caustic = { "FF9A3C", "FFD48A" }, lineop = 0.78,
    flows = { { "4A1A7A", 0.20, 0.66 }, { "A52A6A", 0.50, 0.46 }, { "C4561F", 0.78, 0.36 } } },
  -- no colour in the field: the beam alone carries it
  graphite = P { deep = "0B0E14", line = "D6DEE8", ink = "2A3442", accent = "8A97A8",
    caustic = { "AEB9C7", "E4E9F0" }, lineop = 0.5, causticop = 0.85,
    flows = { { "1C2533", 0.25, 0.70 }, { "263246", 0.70, 0.60 } } },
}
