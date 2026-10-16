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
    -- Sampled 2026-10-16 from a screenshot of the reference book in the game (pages about
    -- 0.82/0.67/0.47, cover 0.28/0.20/0.14 fading to 0.17/0.11/0.08): the reference renders
    -- warmer, darker and more saturated than its own flat-colour constants, because its pages
    -- carry grain and shaded edges. We reach that look with edge shading instead of grain.
    cover = { 0.25, 0.18, 0.12, 0.98 },
    coverLow = { 0.15, 0.10, 0.07, 0.98 },
    coverEdge = { 0.62, 0.47, 0.22, 0.85 },   -- the brass edge
    pageLeft = { 0.83, 0.70, 0.50, 1 },
    pageRight = { 0.81, 0.68, 0.48, 1 },
    pageShade = { 0.30, 0.18, 0.06 },         -- the edge / spine shading, drawn at low alpha
    gutter = { 0.30, 0.18, 0.06 },
    ink = { 0.25, 0.15, 0.06 },
    strong = { 0.12, 0.06, 0.02 },
    faded = { 0.40, 0.29, 0.12 },
    rubric = { 0.52, 0.12, 0.06 },            -- headings, the active mark
    done = { 0.10, 0.28, 0.10 },              -- finished objectives, "ready to turn in"
    pending = { 0.25, 0.15, 0.06 },
    selected = { 0.45, 0.28, 0.08, 0.26 },
    hover = { 0.25, 0.15, 0.06, 0.10 },
    hairline = { 0.25, 0.15, 0.06, 0.45 },
    plateEdge = { 0.33, 0.23, 0.13, 0.95 },   -- the map plate's frame (sampled: 0.33/0.23/0.14)
    plateFill = { 0.93, 0.87, 0.70, 1 },
    -- lettering on the leather cover (the action links): tooled brass, cream when lit
    chrome = { 0.85, 0.70, 0.42 },
    chromeHot = { 0.98, 0.92, 0.76 },
    chromeWarn = { 0.90, 0.50, 0.38 },
    chromeOff = { 0.55, 0.47, 0.36 },
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
    chrome = { 0.85, 0.82, 0.72 },
    chromeHot = { 1, 0.96, 0.82 },
    chromeWarn = { 0.90, 0.50, 0.38 },
    chromeOff = { 0.50, 0.48, 0.42 },
    pageShade = { 0, 0, 0 },
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

-- A two-colour gradient on a texture. SetGradient takes colour objects in current clients; where
-- that fails, a flat wash at the average alpha is close enough. `orient` HORIZONTAL or VERTICAL;
-- `from` is the left (or bottom) end, `to` the right (or top). Colours are { r, g, b, a }.
function Style.Gradient(tex, orient, from, to)
  local ok = false
  if tex.SetGradient and CreateColor then
    ok = pcall(tex.SetGradient, tex, orient,
      CreateColor(from[1], from[2], from[3], from[4] or 1), CreateColor(to[1], to[2], to[3], to[4] or 1))
  end
  if not ok then
    tex:SetColorTexture((from[1] + to[1]) / 2, (from[2] + to[2]) / 2, (from[3] + to[3]) / 2,
      ((from[4] or 1) + (to[4] or 1)) / 2)
  end
end

-- Text that behaves like a link: a word with a hairline under it, brighter when the mouse is on
-- it. This replaces the stock red buttons: the reference design names "rows of big red buttons
-- that all look equally important" as the thing to avoid, and uses links for those choices.
-- `tone`: a function returning the theme's colour table { normal, hot, warn, off }.
-- Methods: SetText, SetEnabled, SetWarn(bool); `link.noLine = true` drops the underline (a cross). A parent that lays links out in a row sets
-- link.onResize to be told when the text (and so the width) changed.
function Style.Link(parent, onClick, getTone)
  local link = CreateFrame("Button", nil, parent)
  link:SetHeight(18)
  link.label = link:CreateFontString(nil, "OVERLAY")
  link.label:SetFont(Style.FRIZ, 12, "")
  link.label:SetPoint("LEFT")
  link.label:SetJustifyH("LEFT")
  link.line = link:CreateTexture(nil, "ARTWORK")
  link.line:SetHeight(1)
  link.line:SetPoint("TOPLEFT", link.label, "BOTTOMLEFT", 0, -1)
  link.line:SetPoint("TOPRIGHT", link.label, "BOTTOMRIGHT", 0, -1)
  link.enabled, link.warn, link.over = true, false, false

  local function Paint(self)
    local t = getTone()
    local c = t.chrome
    if not self.enabled then c = t.chromeOff
    elseif self.warn then c = t.chromeWarn
    elseif self.over then c = t.chromeHot end
    self.label:SetTextColor(c[1], c[2], c[3], 1)
    self.line:SetColorTexture(c[1], c[2], c[3], self.over and 0.9 or 0.45)
    self.line:SetShown(self.enabled and not self.noLine)
  end
  link.Paint = Paint

  function link:SetText(text)
    self.label:SetText(text)
    self:SetWidth(math.max(self.label:GetStringWidth(), 8) + 2)
    if self.onResize then self.onResize() end
  end
  function link:GetText() return self.label:GetText() end
  function link:SetEnabled(on)
    self.enabled = on and true or false
    if not self.enabled then self.over = false end
    self:Paint()
  end
  function link:IsEnabled() return self.enabled end
  function link:SetWarn(on) self.warn = on and true or false; self:Paint() end

  link:SetScript("OnEnter", function(self) self.over = true; self:Paint() end)
  link:SetScript("OnLeave", function(self) self.over = false; self:Paint() end)
  link:SetScript("OnClick", function(self, ...) if self.enabled then onClick(self, ...) end end)
  link:Paint()
  return link
end
