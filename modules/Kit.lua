-- QuestBook Kit -- `/qb screen` and `/qb kit`: how big your screen is in real pixels, and a sample page in the
-- new paper look (torn page, type ramp, rule, rows, buttons, a dark tracker swatch) laid out in WHOLE PIXELS.
--
-- Cesar, 2026-10-17: "I will be spending a lot of time looking at this UI, so I want it to be as pleasing as
-- possible and pixel perfect". The reader and the tracker will be built from what is on this sample once it has
-- been looked at in the game; nothing here changes any real window. The look follows principles studied from
-- Dialogue UI (torn parchment, a quiet type hierarchy, one strong colour, key-cap hints); its art and code are
-- not used (its repository carries no licence). All textures here are our own (dev/art/gen_kit.py).
--
-- UNVERIFIED (client only): that the torn edge, the grain and the rule look right at your size; that the pixel
-- lines below really are one pixel wide and the same weight (`/qb screen` prints what the client reports).

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("kit", {})

-- type ramp, in physical pixels (Style.Px turns them into units)
local TYPE = { title = 40, header = 26, body = 22, small = 18 }
local INK, FADED, BRICK = Style.KIT.ink, Style.KIT.faded, Style.KIT.brick     -- the reader's palette
local frame

local function Text(parent, path, px, color, justify)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  fs:SetFont(path, Style.Px(px, parent), "")          -- a font at birth: SetText on a fontless string errors
  fs:SetJustifyH(justify or "LEFT")
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  return fs
end

-- ---------------------------------------------------------------- numbers

function mod:ScreenLine()
  local pw, ph
  if type(GetPhysicalScreenSize) == "function" then
    local ok, w, h = pcall(GetPhysicalScreenSize)
    if ok then pw, ph = w, h end
  end
  local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
  local eff = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  local px = Style.PixelUnit(UIParent)
  return string.format("screen %sx%s px | UI %.0fx%.0f units, effective scale %.3f | 1 px = %.4f units (1 unit = %.2f px)",
    tostring(pw or "?"), tostring(ph or "?"), uw or 0, uh or 0, eff, px, 1 / px)
end

-- ---------------------------------------------------------------- the sample page

local function Build()
  local f = CreateFrame("Frame", "QuestBookKit", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  tinsert(UISpecialFrames, "QuestBookKit")
  f.shade = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  f.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
  f.shade:SetVertexColor(0, 0, 0, 0.42)
  f.shade:SetPoint("TOPLEFT", UIParent, -400, 400)
  f.shade:SetPoint("BOTTOMRIGHT", UIParent, 400, -400)
  f.paper = Style.Paper(f)
  f.parts = {}
  return f
end

local function Px(n) return Style.Px(n, frame) end

-- a filled rectangle in the layer above the paper, placed in pixels from the page's top-left
local function Rect(x, y, w, h, c, layer)
  local t = frame:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8x8")
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  t:SetPoint("TOPLEFT", frame, "TOPLEFT", Px(x), -Px(y))
  t:SetSize(Px(w), Px(h))
  return t
end

local function Place(fs, x, y, w)
  fs:ClearAllPoints()
  fs:SetPoint("TOPLEFT", frame, "TOPLEFT", Px(x), -Px(y))
  if w then fs:SetWidth(Px(w)) end
end

function mod:Layout()
  local PW, PH = 1040, 720                          -- the page, in pixels
  frame:SetSize(Px(PW), Px(PH))
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", -Px(180), 0)
  frame.paper:Layout()
  for _, p in ipairs(frame.parts) do p:Hide() end
  frame.parts = {}
  local function keep(x) frame.parts[#frame.parts + 1] = x; return x end

  local M = 76                                      -- margin
  local title = keep(Text(frame, Style.MORPHEUS, TYPE.title, INK))
  title:SetText("Soft Saber Pelts")
  Place(title, M, 62)
  local rule = keep(Style.Hairline(frame, { INK[1], INK[2], INK[3], 0.85 }))
  rule:ClearAllPoints()
  rule:SetPoint("TOPLEFT", frame, "TOPLEFT", Px(M - 8), -Px(120))
  rule:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -Px(M - 8), -Px(120))
  rule:SetHeight(Px(8))

  local body = keep(Text(frame, Style.FRIZ, TYPE.body, INK))
  body:SetText("Sample text. The quest description goes here, in the body size, with room between the lines so that a long text stays easy to read for a long time. Nothing is bold; the size and the colour do the work.")
  body:SetSpacing(Px(7))
  Place(body, M, 150, PW - 2 * M)

  local tab = keep(Rect(M - 10, 290, 240, 40, { INK[1], INK[2], INK[3], 0.07 }))
  local tabText = keep(Text(frame, Style.FRIZ, TYPE.header, INK))
  tabText:SetText("Objectives")
  Place(tabText, M + 4, 296)

  local rows = {
    { "Soft Saber Pelts", "2/6", false }, { "Nightsaber Fangs", "6/6", true }, { "Return to the huntress", "", false },
  }
  for i, r in ipairs(rows) do
    local y = 348 + (i - 1) * 52
    keep(Rect(M - 10, y - 6, PW - 2 * M + 20, 46, { INK[1], INK[2], INK[3], i % 2 == 1 and 0.045 or 0 }))
    local box = keep(Rect(M, y + 8, 18, 18, { INK[1], INK[2], INK[3], 0.85 }))
    keep(Rect(M + 2, y + 10, 14, 14, r[3] and BRICK or { 0.83, 0.70, 0.50, 1 }))
    local t = keep(Text(frame, Style.FRIZ, TYPE.body, r[3] and FADED or INK))
    t:SetText(r[1]); Place(t, M + 36, y + 4)
    if r[2] ~= "" then
      local c = keep(Text(frame, Style.FRIZ, TYPE.body, FADED, "RIGHT"))
      c:SetText(r[2]); Place(c, PW - M - 120, y + 4, 120)
    end
  end

  -- the one strong colour, and a quiet second action; key caps say which key does it
  local by = PH - 132
  keep(Rect(M, by, 410, 62, BRICK))
  keep(Rect(M, by + 62 - 4, 410, 4, { 0, 0, 0, 0.22 }))
  local cap = keep(Rect(M + 14, by + 12, 38, 38, { 0.10, 0.08, 0.07, 0.85 }))
  local capText = keep(Text(frame, Style.FRIZ, TYPE.small, { 0.93, 0.90, 0.82 }, "CENTER"))
  capText:SetText("A"); Place(capText, M + 14, by + 20, 38)
  local primary = keep(Text(frame, Style.FRIZ, TYPE.header, { 0.96, 0.92, 0.84 }))
  primary:SetText("Make active"); Place(primary, M + 70, by + 16)
  keep(Rect(PW - M - 410, by, 410, 62, { 0.42, 0.40, 0.37, 0.55 }))
  keep(Rect(PW - M - 410 + 14, by + 12, 38, 38, { 0.10, 0.08, 0.07, 0.85 }))
  local escText = keep(Text(frame, Style.FRIZ, TYPE.small, { 0.93, 0.90, 0.82 }, "CENTER"))
  escText:SetText("Esc"); Place(escText, PW - M - 410 + 14, by + 20, 38)
  local close = keep(Text(frame, Style.FRIZ, TYPE.header, { 0.96, 0.92, 0.84 }))
  close:SetText("Close"); Place(close, PW - M - 410 + 70, by + 16)

  -- a pixel check: lines that must be exactly 1, 2 and 3 physical pixels wide, with the same weight everywhere
  local cx = PW - M - 260
  for n = 1, 3 do keep(Rect(cx + (n - 1) * 24, 20, n, 56, INK)) end
  local pc = keep(Text(frame, Style.FRIZ, TYPE.small, FADED))
  pc:SetText("1 2 3 px"); Place(pc, cx - 4, 82)

  -- footer: what the client says about the screen
  local foot = keep(Text(frame, Style.FRIZ, 14, FADED))
  foot:SetText(mod:ScreenLine()); Place(foot, M, PH - 52, PW - 2 * M)

  -- the dark swatch for glance surfaces: the tracker at the proposed scale
  local dk = Style.Get("dark")
  local sw = keep(CreateFrame("Frame", nil, frame, "BackdropTemplate"))
  sw:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  sw:SetBackdropColor(dk.cover[1], dk.cover[2], dk.cover[3], 0.62)
  sw:SetPoint("TOPLEFT", frame, "TOPRIGHT", Px(40), -Px(40))
  sw:SetSize(Px(420), Px(420))
  local function SText(px, c, x, y, w, str, path)
    local fs = sw:CreateFontString(nil, "ARTWORK")
    fs:SetFont(path or Style.FRIZ, Style.Px(px, sw), "")
    fs:SetTextColor(c[1], c[2], c[3], 1)
    fs:SetJustifyH("LEFT"); fs:SetPoint("TOPLEFT", sw, "TOPLEFT", Style.Px(x, sw), -Style.Px(y, sw))
    if w then fs:SetWidth(Style.Px(w, sw)) end
    fs:SetText(str)
    return fs
  end
  SText(16, dk.faded, 24, 22, nil, "QUESTS")
  local hr = sw:CreateTexture(nil, "ARTWORK")
  hr:SetTexture("Interface\\Buttons\\WHITE8x8"); hr:SetVertexColor(dk.hairline[1], dk.hairline[2], dk.hairline[3], dk.hairline[4])
  hr:SetPoint("TOPLEFT", sw, "TOPLEFT", Style.Px(24, sw), -Style.Px(50, sw)); hr:SetSize(Style.Px(372, sw), Style.Px(1, sw))
  SText(21, dk.strong, 24, 66, 372, "Soft Saber Pelts")
  SText(17, dk.faded, 24, 96, 372, "2/6 Soft Nightsaber Pelt")
  local bar = sw:CreateTexture(nil, "ARTWORK"); bar:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar:SetVertexColor(dk.hairline[1], dk.hairline[2], dk.hairline[3], 0.30)
  bar:SetPoint("TOPLEFT", sw, "TOPLEFT", Style.Px(24, sw), -Style.Px(126, sw)); bar:SetSize(Style.Px(372, sw), Style.Px(4, sw))
  local fillb = sw:CreateTexture(nil, "OVERLAY"); fillb:SetTexture("Interface\\Buttons\\WHITE8x8")
  fillb:SetVertexColor(dk.strong[1], dk.strong[2], dk.strong[3], 0.9)
  fillb:SetPoint("TOPLEFT", sw, "TOPLEFT", Style.Px(24, sw), -Style.Px(126, sw)); fillb:SetSize(Style.Px(372 / 3, sw), Style.Px(4, sw))
  SText(21, dk.ink, 24, 156, 372, "The Road to Darnassus")
  SText(17, dk.faded, 24, 186, 372, "0/6 Gnarlpine Ambusher slain")
  SText(21, dk.done, 24, 236, 372, "Not Dead Yet")
  SText(17, dk.done, 24, 266, 372, "ready to turn in")
  SText(15, dk.faded, 24, 330, 372, "tracker at 21 / 17 / 16 px; the active quest in gold, ready in green, counts as a thin bar")
end

function mod:Toggle()
  if not frame then frame = Build() end
  if frame:IsShown() then frame:Hide(); return end
  self:Layout()
  frame:Show()
end

function mod:OnInit()
  if type(CreateFrame) ~= "function" or not UIParent then self.unavailable = "no UI" end
end
function mod:OnDisable() if frame then frame:Hide() end end

-- the UI scale can change under us
mod.events.UI_SCALE_CHANGED = function(self) if frame and frame:IsShown() then self:Layout() end end
mod.events.DISPLAY_SIZE_CHANGED = mod.events.UI_SCALE_CHANGED

QB:RegisterSlash(mod, "kit", function() mod:Toggle() end, "kit: a sample page in the new paper look, in whole pixels (a look-at-it preview; changes nothing)")
QB:RegisterSlash(mod, "screen", function() QB:Say(mod:ScreenLine()) end, "screen: your screen in real pixels and the UI scale")
