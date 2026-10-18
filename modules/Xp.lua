-- QuestBook Xp -- the experience bar, folded into the top-right strip.
--
-- Cesar, 2026-10-17: "I want to fold the experience info into the menu on top right"; first look: "let's see how the bar
-- looks". A thin bar (3 px by default, whole pixels) hangs under the text strip (modules/Strip.lua), right-aligned with it:
-- the XP you have, in gold, on a faint track, with the rested part as a lighter blue extension. Above it, "Lv 8  44%" (a
-- bigger thing to hover than 3 px); hover for the rest (XP / max, to go, rested). While it is on, Blizzard's own bottom bar is faded out (setting `blizzard`).
-- At the maximum level (or with XP gain turned off) there is nothing to show: the bar hides and Blizzard's comes back, since
-- it also carries reputation and honor, which this module does not (yet) take over.
--
-- It only creates its own frame and fades one Blizzard frame by alpha (the same way the overlay fades the action bars).
-- UNVERIFIED (client only): how it looks; the XP functions on this client (UnitXP, UnitXPMax, GetXPExhaustion, and the
-- events PLAYER_XP_UPDATE, UPDATE_EXHAUSTION, PLAYER_LEVEL_UP); that the strip's frame is a good thing to hang under (the
-- Menu panel opens over the same place).

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("xp", {
  widthPx = 360,        -- the bar's width in physical pixels, right-aligned under the strip
  heightPx = 3,         -- its height in physical pixels
  gapPx = 3,            -- the gap between the strip and the bar
  rested = true,        -- show the rested part
  text = true,          -- the number above the bar: "Lv 8  44%" (a bigger thing to hover than 3 px)
  textPx = 15,          -- its size in physical pixels
  blizzard = true,      -- fade out Blizzard's own bottom bar while this one is up
})

local BLIZZARD_BAR = "StatusTrackingBarManager"
local REST_COLOR = { 0.45, 0.62, 0.85 }      -- the one cool hue: rested XP
local bar                                     -- the frame
local origAlpha                               -- Blizzard's bar alpha before we faded it

local function Tone() return Style.Get("dark") end

local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

local function Comma(n)
  local s = tostring(math.floor(n + 0.5))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

-- ---------------------------------------------------------------- data

-- level, xp, max, rested, resting; or nil when there is no XP to show (maximum level, XP gain off, no data).
function mod:Read()
  if not (UnitXP and UnitXPMax and UnitLevel) then return nil end
  local okL, lvl = pcall(UnitLevel, "player")
  local okX, xp = pcall(UnitXP, "player")
  local okM, mx = pcall(UnitXPMax, "player")
  if not (okL and okX and okM) then return nil end
  if IsSecret(lvl) or IsSecret(xp) or IsSecret(mx) then return nil end
  if type(xp) ~= "number" or type(mx) ~= "number" or mx <= 0 then return nil end
  if IsXPUserDisabled then
    local ok, off = pcall(IsXPUserDisabled)
    if ok and off then return nil end
  end
  local maxLevel = (GetMaxPlayerLevel and select(2, pcall(GetMaxPlayerLevel))) or nil
  if type(lvl) == "number" and type(maxLevel) == "number" and lvl >= maxLevel then return nil end
  local rested = 0
  if GetXPExhaustion then
    local ok, r = pcall(GetXPExhaustion)
    if ok and type(r) == "number" and not IsSecret(r) then rested = r end
  end
  local resting = false
  if IsResting then
    local ok, r = pcall(IsResting)
    resting = ok and r and true or false
  end
  return lvl, xp, mx, rested, resting
end

-- ---------------------------------------------------------------- Blizzard's own bar

function mod:ApplyBlizzard()
  local f = _G[BLIZZARD_BAR]
  if not (f and f.SetAlpha and f.GetAlpha) then return end
  local fade = self.active and self.db.blizzard and self.showing
  if fade then
    if origAlpha == nil then
      local a = f:GetAlpha()
      origAlpha = (type(a) == "number" and a > 0) and a or 1      -- 0 would be somebody else's fade: assume 1
    end
    if f:GetAlpha() ~= 0 then f:SetAlpha(0) end
  elseif origAlpha ~= nil then
    f:SetAlpha(origAlpha)
    origAlpha = nil
  end
end

-- ---------------------------------------------------------------- the bar

local function Px(n) return Style.Px(n, bar) end

local function Build()
  bar = CreateFrame("Frame", "QuestBookXpBar", UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:EnableMouse(true)                       -- the tooltip
  bar:Hide()
  Style.PixelPerfect(bar)
  bar.text = bar:CreateFontString(nil, "OVERLAY")
  bar.text:SetFont(Style.FRIZ, Style.Px(15, bar), "")           -- a font at birth: SetText on a fontless string errors
  bar.text:SetJustifyH("RIGHT")
  bar.text:SetShadowOffset(Style.Px(1, bar), -Style.Px(1, bar))
  bar.text:SetShadowColor(0, 0, 0, 0.85)
  bar.track = bar:CreateTexture(nil, "BACKGROUND")
  bar.track:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar.rest = bar:CreateTexture(nil, "ARTWORK")
  bar.rest:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar.fill = bar:CreateTexture(nil, "OVERLAY")
  bar.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar:SetScript("OnEnter", function(self) QB:Safe(mod, mod.ShowTooltip, mod, self) end)
  bar:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- Under the strip, right-aligned; the screen's top-right corner when the strip is off.
function mod:Place()
  if not bar then return end
  bar:ClearAllPoints()
  local ok, strip = QB:Call("strip", "GetFrame")
  if ok and strip then
    bar:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, -Px(tonumber(self.db.gapPx) or 3))
  else
    bar:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -34)
  end
end

function mod:Refresh()
  if not bar then return end
  local lvl, xp, mx, rested = self:Read()
  self.showing = lvl ~= nil or xp ~= nil
  if not self.showing then
    bar:Hide()
    self:ApplyBlizzard()
    return
  end
  local t = Tone()
  local w, h = Px(Style.Clamp(tonumber(self.db.widthPx) or 360, 120, 900)), Px(Style.Clamp(tonumber(self.db.heightPx) or 3, 1, 12))
  -- the frame is the bar AND the number above it: one bigger thing to hover (Cesar, 2026-10-17: "we need the number so
  -- it's easier to mouse over")
  local textPx = self.db.text and Style.Clamp(tonumber(self.db.textPx) or 15, 10, 30) or 0
  local textH = textPx > 0 and Px(textPx + 5) or 0
  bar:SetSize(w, h + textH)
  self:Place()
  bar.track:ClearAllPoints()
  bar.track:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", 0, 0); bar.track:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
  bar.track:SetHeight(h)
  bar.track:SetVertexColor(t.hairline[1], t.hairline[2], t.hairline[3], 0.30)
  local frac = Style.Clamp(xp / mx, 0, 1)
  bar.fill:ClearAllPoints(); bar.fill:SetPoint("TOPLEFT", bar.track, "TOPLEFT", 0, 0)
  bar.fill:SetSize(math.max(frac * w, frac > 0 and Px(1) or 0), h)
  bar.fill:SetVertexColor(t.strong[1], t.strong[2], t.strong[3], 0.95)
  bar.fill:SetShown(frac > 0)
  local restFrac = (self.db.rested and rested and rested > 0) and Style.Clamp(math.min(rested, mx - xp) / mx, 0, 1 - frac) or 0
  bar.rest:ClearAllPoints(); bar.rest:SetPoint("TOPLEFT", bar.track, "TOPLEFT", frac * w, 0)
  bar.rest:SetSize(restFrac * w, h)
  bar.rest:SetVertexColor(REST_COLOR[1], REST_COLOR[2], REST_COLOR[3], 0.60)
  bar.rest:SetShown(restFrac > 0)
  if textPx > 0 then
    bar.text:SetFont(Style.FRIZ, Px(textPx), "")
    bar.text:ClearAllPoints(); bar.text:SetPoint("BOTTOMRIGHT", bar.track, "TOPRIGHT", 0, Px(3))
    bar.text:SetText("Lv " .. tostring(lvl) .. "  " .. math.floor(frac * 100) .. "%")
    bar.text:SetTextColor(t.faded[1], t.faded[2], t.faded[3], 1)
    bar.text:Show()
  else
    bar.text:Hide()
  end
  bar:Show()
  self.last = { level = lvl, xp = xp, max = mx, rested = rested, frac = frac }
  self:ApplyBlizzard()
end

function mod:ShowTooltip(owner)
  if not GameTooltip then return end
  local lvl, xp, mx, rested, resting = self:Read()
  if not xp then return end
  GameTooltip:SetOwner(owner, "ANCHOR_BOTTOMLEFT")
  GameTooltip:SetText("Level " .. tostring(lvl), 1, 0.96, 0.82)
  GameTooltip:AddLine(string.format("%s / %s  (%d%%)", Comma(xp), Comma(mx), math.floor(xp / mx * 100)), 0.85, 0.82, 0.72)
  GameTooltip:AddLine(Comma(mx - xp) .. " to go", 0.7, 0.7, 0.7)
  if rested and rested > 0 then
    GameTooltip:AddLine(string.format("Rested +%s  (%d%%)%s", Comma(rested), math.floor(rested / mx * 100 + 0.5), resting and "  resting" or ""),
      REST_COLOR[1], REST_COLOR[2], REST_COLOR[3])
  end
  GameTooltip:Show()
end

-- ---------------------------------------------------------------- lifecycle

function mod:OnInit()
  if type(CreateFrame) ~= "function" or not UIParent then self.unavailable = "no UI"; return end
  if not (UnitXP and UnitXPMax) then self.unavailable = "no UnitXP on this client" end
end

function mod:OnEnable()
  if not bar then Build() end
  self:Refresh()
end

function mod:OnDisable()
  if bar then bar:Hide() end
  self.showing = false
  self:ApplyBlizzard()          -- gives Blizzard's bar back
end

local function Update() if bar and mod.active then mod:Refresh() end end
mod.events.PLAYER_XP_UPDATE = Update
mod.events.UPDATE_EXHAUSTION = Update
mod.events.PLAYER_LEVEL_UP = Update
mod.events.PLAYER_UPDATE_RESTING = Update
mod.events.ENABLE_XP_GAIN = Update
mod.events.DISABLE_XP_GAIN = Update
mod.events.PLAYER_ENTERING_WORLD = Update
mod.events.DISPLAY_SIZE_CHANGED = Update
mod.events.UI_SCALE_CHANGED = Update
-- the strip appeared, went away or was re-laid out: hang under it again
QB:On("strip_state", function() if bar and mod.active then mod:Place() end end, mod)
-- the overlay fades and restores the same frame in map modes (`bars all`): put ours back after it
QB:On("overlay_state", function() if bar and mod.active then mod:ApplyBlizzard() end end, mod)
QB:On("reader_state", function() if bar and mod.active then mod:ApplyBlizzard() end end, mod)

-- ---------------------------------------------------------------- slash

QB:RegisterSlash(mod, "xp", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  local d = mod.db
  if sub == "width" and n then
    d.widthPx = Style.Clamp(n, 120, 900)
  elseif sub == "height" and n then
    d.heightPx = Style.Clamp(n, 1, 12)
  elseif sub == "gap" and n then
    d.gapPx = Style.Clamp(n, 0, 20)
  elseif sub == "rested" and (arg == "on" or arg == "off") then
    d.rested = (arg == "on")
  elseif sub == "text" and (arg == "on" or arg == "off") then
    d.text = (arg == "on")
  elseif sub == "textsize" and n then
    d.textPx = Style.Clamp(n, 10, 30)
  elseif sub == "blizzard" and (arg == "on" or arg == "off") then
    d.blizzard = (arg == "on")        -- on = fade Blizzard's bottom bar while this one is up
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb xp width <px> | height <px> | gap <px> | text on|off | textsize <px> | rested on|off | blizzard on|off   (blizzard on = Blizzard's own bottom bar is faded out)")
  end
  mod:Refresh()
  local l = mod.last
  QB:Say(string.format("xp bar: %s, %d x %d px, gap %d, number %s, rested %s, Blizzard's bar %s%s",
    mod.showing and "shown" or "not shown (maximum level, XP gain off, or no data)", d.widthPx, d.heightPx, d.gapPx,
    d.text and "on" or "off", d.rested and "on" or "off", d.blizzard and "faded out" or "left alone",
    l and string.format(" | level %s, %d / %d (%.0f%%), rested %d", tostring(l.level), l.xp, l.max, l.frac * 100, l.rested or 0) or ""))
end, "xp width|height|gap|text|textsize|rested|blizzard: the experience bar under the strip")
