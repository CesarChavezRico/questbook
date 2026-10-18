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

local ADDON, QB = ...

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

-- ---------------------------------------------------------------- pixels
--
-- The client lays out in UI units; one physical pixel is 768 / (physical screen height) of a unit at UIParent's
-- scale, and a region with its own scale sees it divided by its effective scale (Blizzard_SharedXML/PixelUtil.lua:
-- GetPixelToUIUnitFactor, GetNearestPixelSize). Borders, rules and padding written in whole pixels through these
-- come out crisp and the same weight everywhere; written in units they land between pixels and shimmer.

function Style.PixelUnit(region)
  local factor = 1
  if type(GetPhysicalScreenSize) == "function" then
    local ok, _, h = pcall(GetPhysicalScreenSize)
    if ok and type(h) == "number" and h > 0 then factor = 768 / h end
  end
  local scale = region and region.GetEffectiveScale and region:GetEffectiveScale()
  if type(scale) ~= "number" or scale <= 0 then scale = 1 end
  return factor / scale
end

-- n physical pixels, in the region's units
function Style.Px(n, region) return n * Style.PixelUnit(region) end

-- a size in units, rounded to a whole number of physical pixels
function Style.Snap(units, region)
  local u = Style.PixelUnit(region)
  return math.floor(units / u + 0.5) * u
end

-- Ask the client to round a frame's layout to whole pixels (Blizzard calls this on frames and regions alike).
function Style.PixelPerfect(frame)
  if frame and frame.SetRoundLayoutToNearestPixel then pcall(frame.SetRoundLayoutToNearestPixel, frame, true) end
end

-- ---------------------------------------------------------------- paper
--
-- A page of torn parchment as a nine-patch, drawn from our own generated textures (dev/art/gen_kit.py): a tiling
-- grain for the fill, four corners and four stretched strips (each its own tearing; their profile meets at the same depth at both
-- ends, so stretching along the page never opens a seam. Every size is in whole physical pixels. The page owns
-- no frame: it draws into `parent`'s BACKGROUND layer and re-lays itself out when `parent` changes size.

local PAPER_TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local EDGE, INSET, GRAIN = 64, 40, 256      -- px: strip depth, where the fill starts, grain tile

function Style.Paper(parent)
  local P = {}
  local function tex(file, sub, tile)
    local t = parent:CreateTexture(nil, "BACKGROUND", nil, sub)
    if tile then t:SetTexture(PAPER_TEX .. file, "REPEAT", "REPEAT") else t:SetTexture(PAPER_TEX .. file) end
    return t
  end
  P.fill = tex("paper_grain.tga", -7, true)
  P.top, P.bottom = tex("paper_top.tga", -6), tex("paper_bottom.tga", -6)
  P.left, P.right = tex("paper_left.tga", -6), tex("paper_right.tga", -6)
  P.tl, P.tr = tex("paper_corner.tga", -5), tex("paper_corner.tga", -5)
  P.bl, P.br = tex("paper_corner.tga", -5), tex("paper_corner.tga", -5)
  P.top:SetTexCoord(0, 1, 0, 1);    P.bottom:SetTexCoord(0, 1, 1, 0)
  P.left:SetTexCoord(0, 1, 0, 1);   P.right:SetTexCoord(1, 0, 0, 1)
  P.tl:SetTexCoord(0, 1, 0, 1);     P.tr:SetTexCoord(1, 0, 0, 1)
  P.bl:SetTexCoord(0, 1, 1, 0);     P.br:SetTexCoord(1, 0, 1, 0)
  P.parts = { P.fill, P.top, P.bottom, P.left, P.right, P.tl, P.tr, P.bl, P.br }

  function P:Layout()
    local u = Style.PixelUnit(parent)
    local e, i = EDGE * u, INSET * u
    local w, h = parent:GetSize()
    P.fill:ClearAllPoints()
    P.fill:SetPoint("TOPLEFT", parent, "TOPLEFT", i, -i)
    P.fill:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -i, i)
    if w and h then P.fill:SetTexCoord(0, (w - 2 * i) / (GRAIN * u), 0, (h - 2 * i) / (GRAIN * u)) end
    P.top:ClearAllPoints();    P.top:SetPoint("TOPLEFT", parent, "TOPLEFT", e, 0);         P.top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -e, 0);         P.top:SetHeight(e)
    P.bottom:ClearAllPoints(); P.bottom:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", e, 0); P.bottom:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -e, 0); P.bottom:SetHeight(e)
    P.left:ClearAllPoints();   P.left:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -e);        P.left:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, e);     P.left:SetWidth(e)
    P.right:ClearAllPoints();  P.right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -e);    P.right:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, e);  P.right:SetWidth(e)
    for key, pt in pairs({ tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }) do
      P[key]:ClearAllPoints(); P[key]:SetPoint(pt, parent, pt, 0, 0); P[key]:SetSize(e, e)
    end
  end

  function P:SetShown(on) for _, t in ipairs(P.parts) do t:SetShown(on) end end

  Style.PixelPerfect(parent)
  if parent.HookScript then parent:HookScript("OnSizeChanged", function() P:Layout() end) end
  P:Layout()
  return P
end

-- A brush-like rule that tapers to nothing at both ends (our own art): the line under a title. `color` = { r, g, b, a }.
function Style.Hairline(parent, color)
  local t = parent:CreateTexture(nil, "ARTWORK")
  t:SetTexture(PAPER_TEX .. "hairline.tga")
  local c = color or { 0.19, 0.17, 0.13, 0.9 }
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  t:SetHeight(Style.Px(8, parent))
  return t
end

-- The reader's palette and type ramp (physical pixels): warm dark-brown ink on the torn page, one strong colour.
-- Colour values follow the principle studied in Dialogue UI (ink, not black; one saturated accent); they are ours.
Style.KIT = {
  ink = { 0.19, 0.17, 0.13 },
  faded = { 0.50, 0.36, 0.24 },
  brick = { 0.416, 0.18, 0.165 },          -- the one strong colour
  done = { 0.20, 0.36, 0.18 },             -- "ready to turn in", readable on the page
  onBrick = { 0.96, 0.92, 0.84 },
  capFill = { 0.10, 0.08, 0.07, 0.85 },
  capInk = { 0.93, 0.90, 0.82 },
  -- sizes as multiples of the body size
  title = 1.82, header = 1.18, small = 0.82,
}

-- An ink link on the page: a word with a 1 px rule under it, brick when the mouse is on it, faded when disabled.
-- Sizes in physical pixels. Returns a Button with :SetText / :SetEnabled / :SetWarn / :SetPx.
function Style.InkLink(parent, px, onClick)
  local K = Style.KIT
  local b = CreateFrame("Button", nil, parent)
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFont(Style.FRIZ, Style.Px(px, parent), "")          -- a font at birth
  b.label:SetPoint("LEFT")
  b.label:SetJustifyH("LEFT")
  b.line = b:CreateTexture(nil, "ARTWORK")
  b.line:SetTexture("Interface\\Buttons\\WHITE8x8")
  b.line:SetPoint("TOPLEFT", b.label, "BOTTOMLEFT", 0, -Style.Px(2, parent))
  b.line:SetPoint("TOPRIGHT", b.label, "BOTTOMRIGHT", 0, -Style.Px(2, parent))
  b.line:SetHeight(Style.Px(1, parent))
  b.enabled, b.warn, b.over = true, false, false
  function b:Paint()
    local c = K.ink
    if not self.enabled then c = K.faded elseif self.warn or self.over then c = K.brick end
    local a = self.enabled and 1 or 0.55
    self.label:SetTextColor(c[1], c[2], c[3], a)
    self.line:SetVertexColor(c[1], c[2], c[3], self.enabled and (self.over and 0.95 or 0.5) or 0)
  end
  function b:SetPx(n)
    px = n
    self.label:SetFont(Style.FRIZ, Style.Px(n, parent), "")
    self:SetHeight(Style.Px(n + 8, parent))
    self:SetWidth(math.max(self.label:GetStringWidth(), 8) + 2)
  end
  function b:SetText(t)
    self.label:SetText(t)
    self:SetWidth(math.max(self.label:GetStringWidth(), 8) + 2)
    if self.onResize then self.onResize() end
  end
  function b:GetText() return self.label:GetText() end
  function b:SetEnabled(on) self.enabled = on and true or false; if not self.enabled then self.over = false end; self:Paint() end
  function b:SetWarn(on) self.warn = on and true or false; self:Paint() end
  b:SetHeight(Style.Px(px + 8, parent))
  b:SetScript("OnEnter", function(self) self.over = true; self:Paint() end)
  b:SetScript("OnLeave", function(self) self.over = false; self:Paint() end)
  b:SetScript("OnClick", function(self, ...) if self.enabled then onClick(self, ...) end end)
  b:Paint()
  return b
end

-- A flat button on the page: `primary` is the one strong colour (brick), otherwise a quiet grey; an optional key
-- cap (a dark square with the key's name) says which key does it. Sizes in physical pixels.
function Style.PaperButton(parent, wpx, hpx, label, primary, cap, onClick)
  local K = Style.KIT
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(Style.Px(wpx, parent), Style.Px(hpx, parent))
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints(b)
  b.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  if primary then
    b.foot = b:CreateTexture(nil, "BORDER")
    b.foot:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.foot:SetVertexColor(0, 0, 0, 0.22)
    b.foot:SetPoint("BOTTOMLEFT"); b.foot:SetPoint("BOTTOMRIGHT"); b.foot:SetHeight(Style.Px(4, parent))
  end
  local textX = 28
  if cap then
    b.cap = b:CreateTexture(nil, "ARTWORK")
    b.cap:SetTexture("Interface\\Buttons\\WHITE8x8")
    b.cap:SetVertexColor(K.capFill[1], K.capFill[2], K.capFill[3], K.capFill[4])
    local cs = Style.Px(hpx - 24, parent)
    b.cap:SetSize(cs, cs)
    b.cap:SetPoint("LEFT", b, "LEFT", Style.Px(14, parent), 0)
    b.capText = b:CreateFontString(nil, "OVERLAY")
    b.capText:SetFont(Style.FRIZ, Style.Px(16, parent), "")
    b.capText:SetPoint("CENTER", b.cap, "CENTER", 0, 0)
    b.capText:SetTextColor(K.capInk[1], K.capInk[2], K.capInk[3], 1)
    b.capText:SetText(cap)
    textX = 14 + (hpx - 24) + 18
  end
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFont(Style.FRIZ, Style.Px(24, parent), "")
  b.label:SetPoint("LEFT", b, "LEFT", Style.Px(textX, parent), Style.Px(primary and 1 or 0, parent))
  b.label:SetJustifyH("LEFT")
  b.label:SetText(label)
  b.primary, b.enabled, b.over = primary and true or false, true, false
  function b:Paint()
    local c, a
    if self.primary then c = K.brick; a = self.over and 1 or 0.92 else c = { 0.42, 0.40, 0.37 }; a = self.over and 0.72 or 0.55 end
    if not self.enabled then a = a * 0.45 end
    self.bg:SetVertexColor(c[1], c[2], c[3], a)
    self.label:SetTextColor(K.onBrick[1], K.onBrick[2], K.onBrick[3], self.enabled and 1 or 0.6)
  end
  function b:SetLabel(t) self.label:SetText(t) end
  function b:SetEnabled(on) self.enabled = on and true or false; self:Paint() end
  b:SetScript("OnEnter", function(self) self.over = true; self:Paint() end)
  b:SetScript("OnLeave", function(self) self.over = false; self:Paint() end)
  b:SetScript("OnClick", function(self, ...) if self.enabled and onClick then onClick(self, ...) end end)
  b:Paint()
  return b
end

-- A drag handle for placing a piece of our UI (the corner minimap, the quest list): a translucent brass-edged
-- rectangle that sits on the thing, is dragged with the left button and finished with a right click. Positions
-- are offsets of the TOP-RIGHT corner from the screen's, the way `pos <x> <y>` always was.
--   opts.name   global frame name
--   opts.size() -> w, h        the size of what is being moved (the handle covers it)
--   opts.get()  -> x, y        where it is now
--   opts.set(x, y)             called with whole numbers while dragging and at the drop: move the real thing
--   opts.lock()                called on a right click on the handle
--   opts.hint   text on the handle
function Style.Mover(opts)
  local t = Style.Get("dark")
  local m = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
  m:SetFrameStrata("DIALOG")
  m:SetMovable(true)
  m:EnableMouse(true)
  m:SetClampedToScreen(true)
  m:RegisterForDrag("LeftButton")
  m:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  m:SetBackdropColor(t.selected[1], t.selected[2], t.selected[3], 0.30)
  m:SetBackdropBorderColor(t.strong[1], t.strong[2], t.strong[3], 0.9)
  m.text = m:CreateFontString(nil, "OVERLAY")
  m.text:SetFont(Style.FRIZ, 12, "")                       -- a font at birth: SetText on a fontless string errors
  m.text:SetPoint("CENTER", m, "CENTER", 0, 0)
  m.text:SetJustifyH("CENTER")
  m.text:SetTextColor(t.ink[1], t.ink[2], t.ink[3], 1)
  m.text:SetText(opts.hint or "Drag to move\nright-click when done")
  m.dragging = false

  -- put the handle on the thing's current place and size (not while it is being dragged)
  function m:Layout()
    if self.dragging then return end
    local w, h = opts.size()
    self:SetSize(w or 100, h or 100)
    self:ClearAllPoints()
    local x, y = opts.get()
    self:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", x or 0, y or 0)
  end

  -- while dragging: read where the handle is and tell the owner
  function m:Follow()
    if not self.dragging then return end
    local r, tp = self:GetRight(), self:GetTop()
    local pr = UIParent:GetRight() or UIParent:GetWidth()
    local pt = UIParent:GetTop() or UIParent:GetHeight()
    if not (r and tp and pr and pt) then return end
    opts.set(math.floor(r - pr + 0.5), math.floor(tp - pt + 0.5))
  end

  m:SetScript("OnDragStart", function(f)
    f.dragging = true
    f:StartMoving()
    f:SetScript("OnUpdate", function() f:Follow() end)
  end)
  m:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    f:Follow()
    f.dragging = false
    f:SetScript("OnUpdate", nil)
    f:Layout()
  end)
  m:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" and opts.lock then opts.lock() end
  end)
  function m:Stop()
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    self:Hide()
  end
  m:Hide()
  return m
end

