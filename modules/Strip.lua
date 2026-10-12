-- QuestBook Strip -- the minimal text strip that replaces the corner minimap.
--
-- A quiet line at the top of the RIGHT wing of the screen:
--     <zone - sub-zone>   <x, y>   <Mail>   [Addons] [Menu]
-- * zone / sub-zone (shortened), refreshed on ZONE_CHANGED* and PLAYER_ENTERING_WORLD
-- * player coordinates, percent of the map with one decimal, refreshed on a 0.2 s
--   ticker (never per frame); a dash where the map gives no position
-- * mail indicator, shown only while HasNewMail() is true (UPDATE_PENDING_MAIL)
-- * click on the text -> QB:Fire("open_full")   (the overlay module opens the Full map)
-- * the ADDONS handle is Blizzard's own AddonCompartmentFrame, re-parented here so
--   that hiding MinimapCluster does not take it along; restored on disable
-- * the MENU handle is our own text button; it asks the "drawers" module to toggle
--   its panel (QB:Call("drawers", "ToggleMenu")). The two modules never reference
--   each other's frames: the strip only exposes GetFrame / GetMenuHandle /
--   GetAddonsHandle, and announces itself on the bus topic "strip_state"
--   (arg: true when switched on, false when switched off).
--
-- The strip creates only its own frames, so it never touches a protected frame.
-- The one Blizzard frame it moves (AddonCompartmentFrame) is a DropdownButton
-- without a secure template (Blizzard_Minimap/Mainline/AddonCompartment.xml).

local ADDON, QB = ...

local strip = QB:NewModule("strip", {
  anchor = "TOPRIGHT",   -- point of the strip AND of UIParent it is attached to
  offsetX = -24,
  offsetY = -14,
  scale = 1,
  showCoords = true,
  showMail = true,
})

-- ---------------------------------------------------------------- constants

local FONT = "Fonts\\FRIZQT__.TTF"
local FONT_SIZE = 12
local COLOR = { 0.85, 0.82, 0.72 }       -- QuestBook text colour
local COLOR_HOT = { 1.00, 0.96, 0.82 }   -- hover / open
local COLOR_MAIL = { 1.00, 0.82, 0.30 }
local HEIGHT = 18
local GAP = 10            -- between text elements
local HANDLE_GAP = 6      -- between the two drawer handles
local COORD_SAMPLE = "88.8, 88.8"   -- used once to fix the width of the coordinate slot

local ANCHORS = {
  TOPRIGHT = true, TOPLEFT = true, TOP = true, BOTTOMRIGHT = true,
  BOTTOMLEFT = true, BOTTOM = true, LEFT = true, RIGHT = true, CENTER = true,
}

-- ---------------------------------------------------------------- state

local ui = {}              -- frames: frame, bg, zoneFS, coordFS, mailFS, hit, menu, menuFS
local addons = {           -- AddonCompartmentFrame handling
  btn = nil,               -- the Blizzard frame while attached
  orig = nil,              -- recorded original state (while attached)
  note = "not attempted",  -- shown by /qb strip
}
local ticker = nil
local tickCount = 0
local last = {}            -- cache of what is currently displayed

-- ---------------------------------------------------------------- helpers

-- Values from the 12.x client can be "secret" in restricted situations; arithmetic or
-- string ops on them throw. issecretvalue is documented in
-- Blizzard_APIDocumentationGenerated/FrameScriptDocumentation.lua.
local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

-- Cut a string to maxChars characters (UTF-8 aware), ending in "..." when cut.
local function Shorten(s, maxChars)
  if type(s) ~= "string" then return "" end
  if #s <= maxChars then return s end    -- bytes <= max implies chars <= max
  local chars = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    chars[#chars + 1] = ch
  end
  if #chars <= maxChars then return s end
  return table.concat(chars, "", 1, maxChars - 1) .. "..."
end

local function SetColor(fs, c)
  fs:SetTextColor(c[1], c[2], c[3])
end

local function MakeText(parent, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FONT, FONT_SIZE, "")
  SetColor(fs, COLOR)
  fs:SetJustifyH(justify or "RIGHT")
  fs:SetWordWrap(false)
  fs:SetShadowColor(0, 0, 0, 0.85)
  fs:SetShadowOffset(1, -1)
  return fs
end

-- ---------------------------------------------------------------- layout

-- (Re)anchor every element right-to-left and size the strip to fit.
-- Cheap; called whenever a width or a visibility changes.
local function Relayout()
  local f = ui.frame
  if not f then return end

  local width = 0

  ui.menu:ClearAllPoints()
  ui.menu:SetPoint("RIGHT", f, "RIGHT", 0, 0)
  local prev = ui.menu
  width = width + ui.menu:GetWidth()

  -- the Addons handle is always anchored (so it is right when it appears later) but
  -- only takes room while it is shown
  local abtn = addons.btn
  if abtn then
    abtn:ClearAllPoints()
    abtn:SetPoint("RIGHT", ui.menu, "LEFT", -HANDLE_GAP, 0)
    if abtn:IsShown() then
      prev = abtn
      width = width + HANDLE_GAP + (abtn:GetWidth() or 16)
    end
  end

  local list = {}
  if ui.mailFS:IsShown() then list[#list + 1] = ui.mailFS end
  if ui.coordFS:IsShown() then list[#list + 1] = ui.coordFS end
  list[#list + 1] = ui.zoneFS

  for _, el in ipairs(list) do
    el:ClearAllPoints()
    el:SetPoint("RIGHT", prev, "LEFT", -GAP, 0)
    prev = el
    local w = (el == ui.coordFS) and (ui.coordW or 0) or el:GetStringWidth()
    width = width + GAP + (w or 0)
  end

  -- click / tooltip area: the text part only (not the handles)
  ui.hit:ClearAllPoints()
  ui.hit:SetPoint("TOPLEFT", ui.zoneFS, "TOPLEFT", -4, 3)
  ui.hit:SetPoint("BOTTOMRIGHT", list[1], "BOTTOMRIGHT", 4, -3)

  f:SetWidth(math.max(width + 8, 24))
end

-- ---------------------------------------------------------------- content

local function UpdateZone()
  if not ui.frame then return end
  local zone = GetZoneText() or ""
  local sub = GetSubZoneText() or ""
  if IsSecret(zone) or IsSecret(sub) then return end
  ui.zoneFull, ui.subFull = zone, sub

  local text = Shorten(zone, 26)
  if sub ~= "" and sub ~= zone then
    text = text .. " - " .. Shorten(sub, 24)
  end
  if text ~= last.zone then
    last.zone = text
    ui.zoneFS:SetText(text)
    Relayout()
  end
end

-- "x, y" as percent of the best map for the player, or nil (indoors, instances, no map).
local function ReadCoords()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
  local mapID = C_Map.GetBestMapForUnit("player")
  if not mapID or IsSecret(mapID) then return nil end
  local pos = C_Map.GetPlayerMapPosition(mapID, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()      -- Vector2DMixin:GetXY (Blizzard_SharedXML/Vector2D.lua)
  if type(x) ~= "number" or type(y) ~= "number" or IsSecret(x) or IsSecret(y) then return nil end
  return string.format("%.1f, %.1f", x * 100, y * 100)
end

local function UpdateCoords()
  if not ui.frame or not strip.db.showCoords then return end
  local ok, text = pcall(ReadCoords)
  if not ok or not text then text = "-" end
  if text ~= last.coords then
    last.coords = text
    ui.coordFS:SetText(text)
  end
end

local function UpdateMail()
  if not ui.frame then return end
  local has = false
  -- HasNewMail: legacy global, still used by Blizzard_Minimap/Mainline/Minimap.lua
  if strip.db.showMail and type(HasNewMail) == "function" then
    local ok, r = pcall(HasNewMail)
    has = ok and r and true or false
  end
  if has ~= last.mail then
    last.mail = has
    if has then ui.mailFS:Show() else ui.mailFS:Hide() end
    Relayout()
  end
end

local function UpdateAddonsShown()
  local abtn = addons.btn
  local shown = abtn and abtn:IsShown() and true or false
  if shown ~= last.addonsShown then
    last.addonsShown = shown
    Relayout()
  end
end

local function ApplyCoordsVisibility()
  if not ui.frame then return end
  if strip.db.showCoords then
    ui.coordFS:Show()
    last.coords = nil
    UpdateCoords()
  else
    ui.coordFS:Hide()
  end
  Relayout()
end

-- ---------------------------------------------------------------- AddonCompartmentFrame

local function RecordOriginal(f)
  local o = {
    parent = f:GetParent(),
    strata = f:GetFrameStrata(),
    level = f:GetFrameLevel(),
    points = {},
  }
  for i = 1, f:GetNumPoints() do
    local point, rel, relPoint, x, y = f:GetPoint(i)
    o.points[i] = { point, rel, relPoint, x, y }
  end
  return o
end

local function DetachAddons()
  local f, o = addons.btn, addons.orig
  addons.btn, addons.orig = nil, nil
  if not f or not o then return end
  pcall(function()
    f:SetParent(o.parent)
    f:ClearAllPoints()
    for _, p in ipairs(o.points) do
      f:SetPoint(p[1], p[2] or o.parent, p[3], p[4], p[5])
    end
    f:SetFrameStrata(o.strata)
    f:SetFrameLevel(o.level)
  end)
  addons.note = "restored to its original parent"
end

local function AttachAddons()
  if addons.btn then return end
  local f = _G.AddonCompartmentFrame
  if type(f) ~= "table" or type(f.SetParent) ~= "function" then
    -- UNVERIFIED: the Blizzard_Minimap TOC loads AddonCompartment only for game type
    -- "mainline"; if Forever (camelot) does not, the global is nil and we skip.
    addons.note = "AddonCompartmentFrame does not exist on this client; Addons handle skipped"
    return
  end
  local ok, err = pcall(function()
    addons.orig = RecordOriginal(f)   -- record first, so a partial failure can be undone
    addons.btn = f
    f:SetParent(ui.frame)
    f:ClearAllPoints()
    f:SetPoint("RIGHT", ui.menu, "LEFT", -HANDLE_GAP, 0)
    f:SetFrameLevel(ui.frame:GetFrameLevel() + 3)
  end)
  if ok then
    addons.note = "attached (shown only when addons registered a compartment entry)"
  else
    local why = tostring(err)
    DetachAddons()
    addons.note = "failed to attach: " .. why
  end
end

-- ---------------------------------------------------------------- tooltip + clicks

local function OnHitEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")   -- same call as Blizzard_Minimap/Mainline/GameTime.lua
  local zone, sub = ui.zoneFull or "", ui.subFull or ""
  GameTooltip:SetText(zone ~= "" and zone or "QuestBook", 1, 0.96, 0.82)
  if sub ~= "" and sub ~= zone then
    GameTooltip:AddLine(sub, 0.85, 0.82, 0.72)
  end
  if last.coords and last.coords ~= "-" then
    GameTooltip:AddLine(last.coords, 0.7, 0.7, 0.7)
  end
  if last.mail then
    GameTooltip:AddLine("You have new mail", COLOR_MAIL[1], COLOR_MAIL[2], COLOR_MAIL[3])
  end
  GameTooltip:AddLine("Click: open map", 0.62, 0.60, 0.52)
  GameTooltip:Show()
end

local function OnHitLeave()
  GameTooltip:Hide()
end

local function OnHitClick()
  QB:Fire("open_full")
end

local function OnMenuClick()
  if QB:Get("drawers") then
    QB:Call("drawers", "ToggleMenu")
  else
    QB:Say("menu drawer is off")
  end
end

-- ---------------------------------------------------------------- build

local function ApplySettings()
  local f = ui.frame
  if not f then return end
  local db = strip.db
  local scale = tonumber(db.scale) or 1
  if scale < 0.5 then scale = 0.5 elseif scale > 2 then scale = 2 end
  local anchor = ANCHORS[db.anchor] and db.anchor or "TOPRIGHT"
  f:SetScale(scale)
  f:ClearAllPoints()
  -- anchor offsets are expressed in the frame's own (scaled) units
  f:SetPoint(anchor, UIParent, anchor, (tonumber(db.offsetX) or -24) / scale, (tonumber(db.offsetY) or -14) / scale)
end

local function EnsureBuilt()
  if ui.frame then return end

  local f = CreateFrame("Frame", nil, UIParent)
  f:SetSize(24, HEIGHT)
  -- MEDIUM, not HIGH: the Menu panel hosts Blizzard HUD frames that live in MEDIUM, and a
  -- panel in a higher strata could end up under or over its own children.
  -- UNVERIFIED: whether the overlay map should draw above or below this; adjust in-game.
  f:SetFrameStrata("MEDIUM")
  f:SetFrameLevel(20)
  f:Hide()
  ui.frame = f

  -- very faint dark gradient, transparent on the left, the right end sits on the screen edge
  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(f)
  bg:SetColorTexture(1, 1, 1, 1)
  local okGrad = false
  if type(CreateColor) == "function" then
    -- Texture:SetGradient(orientation, minColor, maxColor): signature as used on textures by
    -- Blizzard_SharedXML/MarchingAnts.lua
    okGrad = pcall(bg.SetGradient, bg, "HORIZONTAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.35))
  end
  if not okGrad then bg:SetColorTexture(0, 0, 0, 0.22) end
  ui.bg = bg

  ui.zoneFS = MakeText(f, "RIGHT")
  ui.coordFS = MakeText(f, "RIGHT")
  ui.mailFS = MakeText(f, "RIGHT")
  SetColor(ui.mailFS, COLOR_MAIL)
  ui.mailFS:SetText("Mail")
  ui.mailFS:Hide()

  -- fixed-width coordinate slot so the zone text does not jitter as digits change
  ui.coordFS:SetText(COORD_SAMPLE)
  ui.coordW = ui.coordFS:GetStringWidth() + 2
  ui.coordFS:SetWidth(ui.coordW)
  ui.coordFS:SetText("")

  -- Menu handle
  local menu = CreateFrame("Button", nil, f)
  menu:RegisterForClicks("LeftButtonUp")
  menu:SetFrameLevel(f:GetFrameLevel() + 3)
  local mfs = MakeText(menu, "CENTER")
  mfs:SetText("Menu")
  mfs:SetPoint("CENTER", menu, "CENTER", 0, 0)
  menu:SetSize(mfs:GetStringWidth() + 10, HEIGHT)
  menu:SetScript("OnClick", OnMenuClick)
  menu:SetScript("OnEnter", function(self)
    SetColor(mfs, COLOR_HOT)
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetText("Menu", 1, 0.96, 0.82)
    GameTooltip:AddLine("Click: micro menu and bags", 0.62, 0.60, 0.52)
    GameTooltip:Show()
  end)
  menu:SetScript("OnLeave", function()
    SetColor(mfs, ui.menuOpen and COLOR_HOT or COLOR)
    GameTooltip:Hide()
  end)
  ui.menu, ui.menuFS = menu, mfs

  -- click / hover area over the text part
  local hit = CreateFrame("Button", nil, f)
  hit:RegisterForClicks("LeftButtonUp")
  hit:SetFrameLevel(f:GetFrameLevel() + 2)
  hit:SetScript("OnClick", OnHitClick)
  hit:SetScript("OnEnter", OnHitEnter)
  hit:SetScript("OnLeave", OnHitLeave)
  ui.hit = hit

  Relayout()
end

-- ---------------------------------------------------------------- ticker

local function Tick()
  tickCount = tickCount + 1
  UpdateCoords()
  if tickCount % 5 == 0 then       -- once a second: cheap safety nets
    UpdateZone()
    UpdateAddonsShown()
  end
end

local function StartTicker()
  if ticker then return end
  if C_Timer and C_Timer.NewTicker then
    ticker = C_Timer.NewTicker(0.2, function() QB:Safe(strip, Tick) end)
  end
end

local function StopTicker()
  if ticker then
    ticker:Cancel()
    ticker = nil
  end
end

-- ---------------------------------------------------------------- module API

function strip:GetFrame() return ui.frame end
function strip:GetMenuHandle() return ui.menu end
function strip:GetAddonsHandle() return addons.btn end

-- Optional courtesy for the drawers module: tint the Menu handle while its panel is open.
function strip:SetMenuOpen(open)
  ui.menuOpen = open and true or false
  if ui.menuFS then SetColor(ui.menuFS, ui.menuOpen and COLOR_HOT or COLOR) end
end

-- ---------------------------------------------------------------- lifecycle

function strip:OnInit()
  local db = self.db
  if type(db.scale) ~= "number" then db.scale = 1 end
  if not ANCHORS[db.anchor] then db.anchor = "TOPRIGHT" end
  if type(CreateFrame) ~= "function" or not UIParent then
    self.unavailable = "no UI frames available"
  end
end

function strip:OnEnable()
  EnsureBuilt()
  ApplySettings()
  AttachAddons()
  last = {}
  tickCount = 0
  ApplyCoordsVisibility()
  UpdateZone()
  UpdateMail()
  UpdateAddonsShown()
  Relayout()
  ui.frame:Show()
  StartTicker()
  QB:Fire("strip_state", true)
end

function strip:OnDisable()
  StopTicker()
  self:SetMenuOpen(false)
  if ui.frame then
    if GameTooltip and GameTooltip.IsOwned and (GameTooltip:IsOwned(ui.hit) or GameTooltip:IsOwned(ui.menu)) then
      GameTooltip:Hide()
    end
    ui.frame:Hide()
  end
  DetachAddons()
  QB:Fire("strip_state", false)
end

-- ---------------------------------------------------------------- events

strip.events.ZONE_CHANGED = function() UpdateZone() end
strip.events.ZONE_CHANGED_INDOORS = function() UpdateZone() end
strip.events.ZONE_CHANGED_NEW_AREA = function() UpdateZone() end
strip.events.UPDATE_PENDING_MAIL = function() UpdateMail() end
strip.events.PLAYER_ENTERING_WORLD = function()
  UpdateZone()
  UpdateMail()
  UpdateCoords()
  UpdateAddonsShown()
end

-- ---------------------------------------------------------------- slash

local function OnOff(word)
  word = (word or ""):lower()
  if word == "on" or word == "1" or word == "true" then return true end
  if word == "off" or word == "0" or word == "false" then return false end
  return nil
end

local function Status()
  local db = strip.db
  QB:Say(string.format("strip: coords %s, mail %s, scale %s, anchor %s %s,%s",
    db.showCoords and "on" or "off", db.showMail and "on" or "off",
    tostring(db.scale), tostring(db.anchor), tostring(db.offsetX), tostring(db.offsetY)))
  QB:Say("strip: Addons handle: " .. addons.note)
  local menuState = QB:Get("drawers") and "drawers module on" or "drawers module off (Menu click only prints a notice)"
  QB:Say("strip: Menu handle: " .. menuState)
end

local function OnSlash(rest)
  local db = strip.db
  local a, b, c = (rest or ""):match("^(%S*)%s*(%S*)%s*(%S*)")
  a = (a or ""):lower()

  if a == "" or a == "status" then
    Status()
  elseif a == "coords" then
    local v = OnOff(b)
    if v == nil then QB:Say("usage: /qb strip coords on|off") return end
    db.showCoords = v
    ApplyCoordsVisibility()
    Status()
  elseif a == "mail" then
    local v = OnOff(b)
    if v == nil then QB:Say("usage: /qb strip mail on|off") return end
    db.showMail = v
    last.mail = nil
    UpdateMail()
    Status()
  elseif a == "scale" then
    local n = tonumber(b)
    if not n then QB:Say("usage: /qb strip scale <0.5-2>") return end
    db.scale = math.max(0.5, math.min(2, n))
    ApplySettings()
    Status()
  elseif a == "pos" then
    local x, y = tonumber(b), tonumber(c)
    if not (x and y) then QB:Say("usage: /qb strip pos <x> <y>   (offsets from the anchor, default -24 -14)") return end
    db.offsetX, db.offsetY = x, y
    ApplySettings()
    Status()
  elseif a == "anchor" then
    local p = b:upper()
    if not ANCHORS[p] then QB:Say("usage: /qb strip anchor TOPRIGHT|TOPLEFT|TOP|BOTTOMRIGHT|BOTTOMLEFT|BOTTOM|LEFT|RIGHT|CENTER") return end
    db.anchor = p
    ApplySettings()
    Status()
  else
    QB:Say("usage: /qb strip [status] | coords on|off | mail on|off | scale <n> | pos <x> <y> | anchor <POINT>")
  end
end

QB:RegisterSlash(strip, "strip",
  OnSlash,
  "minimal zone/coords/mail strip: coords on|off, mail on|off, scale <n>, pos <x> <y>, anchor <POINT>")
