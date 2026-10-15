-- QuestBook Style -- one place for the look: palettes, fonts, small helpers.
--
-- Two visual languages (docs/STYLE.md): things you GLANCE at during play stay quiet and
-- translucent (strip, drawers, corner minimap, map overlay); things you stop and READ
-- (the quest book) can be a paper surface. This file holds the palettes for the second.
-- Colours are written as { r, g, b } in 0..1; an optional fourth value is alpha.
--
-- Loaded right after Core.lua, before every module: `local Style = QB.Style`.
--
-- The paper palette follows what a parchment page needs: ink that is dark and warm,
-- a red accent for headings, no black text shadow (it smudges ink). Gold and green that
-- read well on a dark panel vanish on parchment, so every ink here is re-inked darker.
-- (Ideas credited to a study of the Social Diary addon's design brief, MIT; no code copied.)

local _, QB = ...

local Style = {}
QB.Style = Style

Style.THEMES = {
  -- parchment pages in a dark leather cover
  paper = {
    paper = true,
    cover = { 0.23, 0.16, 0.10, 0.97 },
    coverEdge = { 0.07, 0.05, 0.03, 1 },
    pageLeft = { 0.86, 0.77, 0.58, 1 },
    pageRight = { 0.84, 0.74, 0.55, 1 },
    gutter = { 0.20, 0.13, 0.06 },        -- shade near the spine, drawn as a few faint strips
    ink = { 0.24, 0.16, 0.07 },
    strong = { 0.13, 0.08, 0.03 },
    faded = { 0.44, 0.35, 0.21 },
    rubric = { 0.50, 0.10, 0.05 },        -- headings, the active mark
    done = { 0.18, 0.36, 0.16 },          -- finished objectives, "ready to turn in"
    pending = { 0.24, 0.16, 0.07 },
    selected = { 0.45, 0.28, 0.08, 0.24 },
    hover = { 0.24, 0.16, 0.07, 0.10 },
    hairline = { 0.24, 0.16, 0.07, 0.45 },
    plateEdge = { 0.24, 0.16, 0.07, 0.65 },
    plateFill = { 0.93, 0.87, 0.70, 1 },
  },
  -- the faint dark panel of the strip and the Menu drawer
  dark = {
    paper = false,
    cover = { 0.04, 0.04, 0.04, 0.62 },   -- alpha replaced by db.bgAlpha
    coverEdge = { 0.85, 0.82, 0.72, 0.22 },
    ink = { 0.92, 0.89, 0.82 },
    strong = { 0.95, 0.87, 0.65 },
    faded = { 0.70, 0.66, 0.55 },
    rubric = { 0.95, 0.87, 0.65 },
    done = { 0.43, 0.79, 0.43 },
    pending = { 0.85, 0.78, 0.54 },
    selected = { 0.85, 0.75, 0.45, 0.20 },
    hover = { 0.85, 0.82, 0.72, 0.10 },
    hairline = { 0.85, 0.82, 0.72, 0.30 },
    plateEdge = { 0.85, 0.82, 0.72, 0.45 },
    plateFill = { 0.10, 0.09, 0.08, 1 },
  },
}

Style.FRIZ = "Fonts\\FRIZQT__.TTF"
-- The game's book / quest-title font. Its lowercase turns to glyphs below about 18 pt
-- (observed by the Social Diary author in this client), so it is only used at display size.
Style.MORPHEUS = "Fonts\\MORPHEUS.TTF"
Style.MORPHEUS_MIN = 18

function Style.Get(name)
  return Style.THEMES[name] or Style.THEMES.paper
end

local function Byte(x) return math.floor(x * 255 + 0.5) end

-- "rrggbb" for |cffrrggbb text codes, written from the same RGB so the two never drift.
function Style.Hex(color)
  return ("%02x%02x%02x"):format(Byte(color[1]), Byte(color[2]), Byte(color[3]))
end

-- Colour a string inline.
function Style.Color(color, text)
  return "|cff" .. Style.Hex(color) .. text .. "|r"
end

-- Set a FontString's font. kind "title" uses Morpheus at display size on a paper theme and
-- falls back to the normal font where the client refuses the file; everything else is Friz.
-- Returns the file that took.
function Style.SetFont(fs, kind, size, theme)
  size = math.floor(size + 0.5)
  if kind == "title" and theme and theme.paper and size >= Style.MORPHEUS_MIN then
    if fs:SetFont(Style.MORPHEUS, size, "") then return Style.MORPHEUS end
  end
  fs:SetFont(Style.FRIZ, size, "")
  return Style.FRIZ
end

-- Text colour from a palette entry.
function Style.SetInk(fs, color)
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
end

-- No drop shadow on paper: it turns ink into a smudge.
function Style.SetShadow(fs, theme)
  if theme.paper then
    fs:SetShadowOffset(0, 0)
  else
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.85)
  end
end

function Style.Clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
