-- Minimal WoW API stub: enough to LOAD the addon and drive its lifecycle.
-- It does NOT validate that real widgets have the methods we call (any unknown
-- method is a silent no-op), so it finds logic / typo / nil errors in OUR code only.
unpack = unpack or table.unpack
local out = {}
function print(...) local t = {} for i = 1, select('#', ...) do t[#t+1] = tostring((select(i, ...))) end out[#out+1] = table.concat(t, " ") end
function __take() local o = out out = {} return o end

__frames = {}
local Frame = {}
local noop = function() end
local function newFrame(kind, name, parent)
  local f = setmetatable({ __kind = kind, __name = name, __parent = parent, __shown = true, __w = 100, __h = 20, __alpha = 1,
    __scale = 1, __points = {}, __scripts = {}, __events = {}, __strata = "MEDIUM", __level = 1, __text = "", __mouse = true,
    __enabled = true, __children = {} }, Frame)
  __frames[#__frames+1] = f
  if name then _G[name] = f end
  return f
end
Frame.__index = function(t, k)
  local m = rawget(Frame, k)
  if m ~= nil then return m end
  if type(k) == "string" and k:match("^[A-Z][a-z]+[A-Z]") and k:match("^(%u%l+)") and ({Set=1,Get=1,Is=1,Enable=1,Disable=1,Register=1,Unregister=1,Create=1,Clear=1,Add=1,Remove=1,Hook=1,Raise=1,Lower=1,Stop=1,Start=1,Play=1,Can=1,Has=1,Apply=1,Update=1,Click=1,Lock=1,Unlock=1,Freeze=1,Fade=1,Rotate=1,Animate=1,Layout=1,Mark=1,Reset=1,Pulse=1,Ping=1,Fire=1,Toggle=1,Resize=1,Close=1,Open=1,Highlight=1,Unhighlight=1,Send=1,Cancel=1})[k:match("^(%u%l+)")] then return function() end end
end
function Frame:Show() self.__shown = true; if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function Frame:Hide() if self.__shown then self.__shown = false; if self.__scripts.OnHide then self.__scripts.OnHide(self) end end end
function Frame:IsShown() return self.__shown end
function Frame:IsVisible() return self.__shown end
function Frame:SetShown(b) if b then self:Show() else self:Hide() end end
function Frame:SetScript(n, fn) self.__scripts[n] = fn end
function Frame:GetScript(n) return self.__scripts[n] end
function Frame:HookScript(n, fn) local old = self.__scripts[n]; self.__scripts[n] = function(...) if old then old(...) end fn(...) end end
function Frame:RegisterEvent(e) self.__events[e] = true end
function Frame:UnregisterEvent(e) self.__events[e] = nil end
function Frame:SetSize(w, h) self.__w, self.__h = w, h end
function Frame:SetWidth(w) self.__w = w end
function Frame:SetHeight(h) self.__h = h end
function Frame:GetWidth() return self.__w end
function Frame:GetSize() return self.__w, self.__h end
function Frame:GetHeight() return self.__h end
-- like the client: a second SetPoint with the same point name REPLACES the first (it does not add an anchor)
function Frame:SetPoint(...)
  local a = { ... }
  for i, p in ipairs(self.__points) do if p[1] == a[1] then self.__points[i] = a; return end end
  self.__points[#self.__points+1] = a
end
function Frame:ClearAllPoints() self.__points = {} end
function Frame:GetNumPoints() return #self.__points end
function Frame:GetPoint(i) local p = self.__points[i or 1]; if p then return unpack(p) end end
function Frame:GetParent() return self.__parent end
function Frame:SetParent(p) self.__parent = p end
function Frame:SetAlpha(a) self.__alpha = a end
function Frame:GetAlpha() return self.__alpha end
function Frame:SetScale(s) self.__scale = s end
function Frame:GetScale() return self.__scale end
function Frame:GetEffectiveScale() return 1 end
function GetPhysicalScreenSize() return 3420, 1435 end
function Frame:SetFrameStrata(s) self.__strata = s end
function Frame:GetFrameStrata() return self.__strata end
function Frame:SetFrameLevel(l) self.__level = l end
function Frame:GetFrameLevel() return self.__level end
function Frame:EnableMouse(b) self.__mouse = b end
function Frame:IsMouseEnabled() return self.__mouse end
function Frame:SetText(t)
  -- the real client refuses this on a FontString that has no font yet (seen 2026-10-15)
  if self.__kind == "FontString" and not self.__ffile then error("FontString:SetText(): Font not set", 2) end
  self.__text = t
end
function Frame:GetText() return self.__text end
function Frame:GetStringWidth() return #tostring(self.__text) * 7 end
function Frame:SetFont(file, size) self.__fsize = size; self.__ffile = file; return true end
function Frame:SetSpacing(s) self.__spacing = s end
function Frame:GetStringHeight()
  -- crude but monotone: wrap by width / (0.5 * font size), one line height = size + spacing
  local size = self.__fsize or 12
  local w = self.__w or 100
  local cpl = math.max(1, math.floor(w / (size * 0.5)))
  local text = tostring(self.__text or "")
  local lines = 0
  for para in (text .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil(#para / cpl)) end
  return lines * (size + (self.__spacing or 0))
end
function Frame:SetEnabled(b) self.__enabled = b end
function Frame:IsEnabled() return self.__enabled end
function Frame:GetName() return self.__name end
function Frame:CreateFontString(n, ...) return newFrame("FontString", n, self) end
function Frame:CreateTexture(n, layer, tmpl, sub) local t = newFrame("Texture", n, self); t.__layer, t.__sub = layer, sub; return t end
function Frame:CreateMaskTexture(n, ...) return newFrame("MaskTexture", n, self) end
function Frame:GetLeft() return 0 end
function Frame:GetRight() return self.__w end
function Frame:GetTop() return self.__h end
function Frame:GetBottom() return 0 end
function Frame:GetCenter() return 500, 500 end
function Frame:GetVerticalScroll() return 0 end
function Frame:GetStringWidthOf() return 0 end
function Frame:IsMouseOver() return false end
function Frame:GetNumChildren() return 0 end
function Frame:Click(b) if self.__scripts.OnClick then self.__scripts.OnClick(self, b or "LeftButton") end end

function CreateFrame(kind, name, parent) return newFrame(kind, name, parent) end
UIParent = newFrame("Frame", "UIParent")
UIParent.__w, UIParent.__h = 3440, 1440
function UIParent:GetWidth() return 3440 end
function UIParent:GetHeight() return 1440 end
UISpecialFrames = {}
tinsert = table.insert; tremove = table.remove
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function hooksecurefunc(a, b, c)
  local tbl, name, fn = a, b, c
  if type(a) == "string" then tbl, name, fn = _G, a, b end
  local orig = tbl[name]
  tbl[name] = function(...) local r = { orig and orig(...) }; fn(...); return unpack(r) end
end
SlashCmdList = {}
local t0 = 0
function GetTime() t0 = t0 + 0.01 return t0 end
-- timers: queued, run by __runTimers()
local timers = {}
C_Timer = {
  After = function(d, fn) timers[#timers+1] = { fn = fn } end,
  NewTicker = function(d, fn) local t = { fn = fn, ticker = true, Cancel = function(s) s.dead = true end }; timers[#timers+1] = t; return t end,
}
function __runTimers() local q = timers timers = {} for _, t in ipairs(q) do if not t.dead then t.fn(t) if t.ticker and not t.dead then timers[#timers+1] = t end end end end
local cvars = { rotateMinimap = "0", test_cameraOverShoulder = "0", CameraKeepCharacterCentered = "1", CameraReduceUnexpectedMovement = "1" }
C_CVar = { GetCVar = function(n) return cvars[n] end, SetCVar = function(n, v) cvars[n] = tostring(v) end }
function GetCVar(n) return cvars[n] end
function SetCVar(n, v) cvars[n] = tostring(v) end
function __cvar(n) return cvars[n] end
local zoom = 5
function GetCameraZoom() return zoom end
function CameraZoomIn(d) zoom = zoom - d end
function CameraZoomOut(d) zoom = zoom + d end
__combat = false
function InCombatLockdown() return __combat end
function UnitAffectingCombat() return __combat end
function IsLoggedIn() return __loggedIn or false end
function IsInGroup() return true end
function IsPlayerMoving() return false end
function HasNewMail() return true end
function GetZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "Goldshire" end
function GetMinimapZoneText() return "Goldshire" end
function GetCursorInfo() return nil end
function CursorHasItem() return false end
function IsMouseButtonDown() return false end
function GetMouseFoci() return {} end
function GetMouseFocus() return nil end
function issecretvalue() return false end
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
function GetCursorPosition() return 0, 0 end
C_Map = {
  GetBestMapForUnit = function() return 37 end,
  GetPlayerMapPosition = function() return { x = 0.42, y = 0.61, GetXY = function(s) return s.x, s.y end } end,
  GetMapInfo = function() return { name = "Elwynn Forest", mapID = 37 } end,
}
C_Texture = { GetAtlasInfo = function() return { width = 100, height = 100 } end }
Enum = { UIMapType = {}, GameRule = {} }
C_Minimap = { GetViewRadius = function() return 200 end }
-- a fake quest log: 2 zone headers, 3 quests
local log = {
  { isHeader = true, title = "Elwynn Forest", isCollapsed = false },
  { questID = 100, title = "Wolves", level = 3 },
  { questID = 101, title = "Kobolds", level = 4 },
  { isHeader = true, title = "Westfall", isCollapsed = true },
}
local westfall = { { questID = 102, title = "Harvest", level = 8 } }
local watched, super, selected, abandonArmed = { [100] = true }, 0, 0, nil
function __watchedSet() return watched end
C_QuestLog = {
  GetNumQuestLogEntries = function() return #log, 3 end,
  GetInfo = function(i) local e = log[i]; if not e then return nil end
    local r = { isHeader = e.isHeader, title = e.title, questID = e.questID, level = e.level, isCollapsed = e.isCollapsed, questLogIndex = i }
    return r end,
  IsComplete = function(id) return id == 101 end,
  ReadyForTurnIn = function(id) return id == 101 end,
  GetQuestObjectives = function(id) return { { text = "Kill 5 things", finished = false } } end,
  SetSelectedQuest = function(id) selected = id end,
  GetSelectedQuest = function() return selected end,
  GetQuestWatchType = function(id) return watched[id] and 0 or nil end,
  AddQuestWatch = function(id) watched[id] = true return true end,
  RemoveQuestWatch = function(id) watched[id] = nil return true end,
  GetNumQuestWatches = function() local n = 0 for _ in pairs(watched) do n = n + 1 end return n end,
  IsPushableQuest = function(id) return true end,
  GetLogIndexForQuestID = function(id) for i, e in ipairs(log) do if e.questID == id then return i end end end,
  CanAbandonQuest = function() return true end,
  SetAbandonQuest = function() abandonArmed = selected end,
  GetAbandonQuest = function() return abandonArmed end,
}
function ExpandQuestHeader(i) log[i].isCollapsed = false; table.insert(log, i + 1, westfall[1]) end
function GetQuestLogQuestText() return "Go and slay the beasts.\n\nThen return.", "Kill 5 things" end
C_SuperTrack = {
  GetSuperTrackedQuestID = function() return super end,
  SetSuperTrackedQuestID = function(id) super = id end,
  ClearAllSuperTracked = function() super = 0 end,
}
C_VoiceChat = { GetTtsVoices = function() return { { voiceID = 1, name = "Zira" } } end, SpeakText = function() end, StopSpeakingText = function() end }
Constants = { QuestWatchConsts = { MAX_QUEST_WATCHES = 25 } }
function QuestLogPushQuest(i) __pushed = i end
function StaticPopup_Show(n, t) __popup = { n, t } end
function StaticPopup_Hide() end
function QuestUtils_GetQuestName(id) return "Quest " .. tostring(id) end
function ToggleQuestLog() __blizzLogOpened = true end
function ToggleWorldMap() __worldMapToggled = true end
-- Blizzard frames our modules touch
Minimap = newFrame("Minimap", "Minimap", nil)
MinimapCluster = newFrame("Frame", "MinimapCluster", UIParent)
Minimap.__parent = MinimapCluster
WorldMapFrame = newFrame("Frame", "WorldMapFrame", UIParent)
AddonCompartmentFrame = newFrame("DropdownButton", "AddonCompartmentFrame", MinimapCluster)
MicroMenuContainer = newFrame("Frame", "MicroMenuContainer", UIParent)
MicroMenu = newFrame("Frame", "MicroMenu", MicroMenuContainer)
BagsBar = newFrame("Frame", "BagsBar", UIParent)
function __fire(event, ...)
  for _, f in ipairs(__frames) do
    if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
end
function __tick(n, dt)
  for _ = 1, n or 1 do
    for _, f in ipairs(__frames) do
      if f.__shown ~= false and f.__scripts.OnUpdate then f.__scripts.OnUpdate(f, dt or 0.05) end
    end
    __runTimers()
  end
end
-- richer WorldMapFrame for the Zone path
WorldMapFrame.ScrollContainer = newFrame("ScrollFrame", nil, WorldMapFrame)
WorldMapFrame.ScrollContainer.Child = newFrame("Frame", nil, WorldMapFrame.ScrollContainer)
WorldMapFrame.BorderFrame = newFrame("Frame", "WorldMapBorder", WorldMapFrame)
WorldMapFrame.NavBar = newFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.SidePanelToggle = newFrame("Button", nil, WorldMapFrame)
WorldMapFrame.BlackoutFrame = newFrame("Frame", nil, WorldMapFrame)
WorldMapFrame.mapID = 37
function WorldMapFrame:SetMapID(id) self.mapID = id end
function WorldMapFrame:GetMapID() return self.mapID end
function WorldMapFrame:GetMaskTexture() return nil end
function WorldMapFrame:SetMaskTexture() end
function WorldMapFrame:IsMaximized() return true end
function WorldMapFrame:GetCanvasContainer() return self.ScrollContainer end
QuestMapFrame = newFrame("Frame", "QuestMapFrame", WorldMapFrame)
-- hybrid minimap + C_Minimap pieces (v0.7.1)
local groundOn = true
C_Minimap.GetUiMapID = function() return nil end
C_Minimap.ShouldUseHybridMinimap = function() return __hybridWanted or false end
C_Minimap.GetDrawGroundTextures = function() return groundOn end
C_Minimap.SetDrawGroundTextures = function(b) groundOn = b end
function IsIndoors() return __indoors or false end
HybridMinimap = newFrame("Frame", "HybridMinimap", Minimap)
HybridMinimap.__shown = false
HybridMinimap.Background = newFrame("Texture", nil, HybridMinimap)
HybridMinimap.CircleMask = newFrame("MaskTexture", nil, HybridMinimap)
HybridMinimap.MapCanvas = newFrame("Frame", nil, HybridMinimap)
HybridMinimap.MapCanvas.__mask = HybridMinimap.CircleMask
HybridMinimap.MapCanvas.__useMask = true
function HybridMinimap.MapCanvas:GetMaskTexture() return self.__mask end
function HybridMinimap.MapCanvas:SetMaskTexture(m) self.__mask = m end
function HybridMinimap.MapCanvas:GetUseMaskTexture() return self.__useMask end
function HybridMinimap.MapCanvas:SetUseMaskTexture(b) self.__useMask = b end
function HybridMinimap:Enable() self.__enabledNow = true; self:CheckMap() end
function HybridMinimap:Disable() self.__enabledNow = false; self:Hide() end
function HybridMinimap:CheckMap()
  local id = C_Minimap.GetUiMapID()
  if not id then self:Hide() else self.mapID = id; self:Show(); C_Minimap.SetDrawGroundTextures(false) end
end
function HybridMinimap:UpdateZoom() end
function HybridMinimap_LoadUI() return true end
function __ground() return groundOn end
function Minimap:GetZoom() return 1 end
function Minimap:SetZoom(z) __zoomSets = (__zoomSets or 0) + 1 end
function Minimap:SetIconScale(s) __iconScale = s end
-- action bars
for _, n in ipairs({ "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight", "StanceBar", "PetActionBar", "StatusTrackingBarManager" }) do
  newFrame("Frame", n, UIParent)
end
-- real mask bookkeeping on the world map + a pooled detail layer (v0.7.2)
do
  local wmf = WorldMapFrame
  wmf.__maskables = {}
  function wmf:SetMaskTexture(m) self.__mask = m end
  function wmf:GetMaskTexture() return self.__mask end
  function wmf:SetUseMaskTexture(b) self.__useMask = b end
  function wmf:GetUseMaskTexture() return not not self.__useMask end
  function wmf:AddMaskableTexture(t)
    if not self.__mask then return end            -- Blizzard: no mask set -> not registered
    if self.__maskables[t] == nil then self.__maskables[t] = true end
  end
  local tile = newFrame("Texture", nil, wmf)
  local layer = newFrame("Frame", nil, wmf)
  layer.detailTilePool = { EnumerateActive = function() local done = false return function() if not done then done = true return tile end end end }
  wmf.detailLayerPool = { EnumerateActive = function() local done = false return function() if not done then done = true return layer end end end }
  wmf.__tile = tile
  function wmf.ScrollContainer:HasZoomLevels() return true end
  function wmf.ScrollContainer:GetScaleForMinZoom() return 1 end
  function wmf.ScrollContainer:GetScaleForMaxZoom() return 4 end
  function wmf.ScrollContainer:GetCanvasScale() return self.__scale2 or 1 end
  function wmf.ScrollContainer:InstantPanAndZoom(sc2) self.__scale2 = sc2; __zoomed = (__zoomed or 0) + 1 end
  function wmf.ScrollContainer:CalculateScrollExtentsAtScale() return 0, 1, 0, 1 end
  function wmf.ScrollContainer:SetPanTarget() end
  function wmf.ScrollContainer:GetWidth() return 500 end
end
-- Blizzard quest-log entry points that the tracker uses (v0.7.4)
function OpenQuestLog(mapID) __blizzOpenQuestLog = true end
function QuestMapFrame_OpenToQuestDetails(id) __blizzOpenDetails = id end
QuestUtil = { OpenQuestDetails = function(id) __blizzPopupDetails = id end }
function IsPlayerMoving() return false end

-- helpers for scenarios that need a different log / quest text (v0.8)
function __setLog(newlog) for i = #log, 1, -1 do log[i] = nil end for i, e in ipairs(newlog) do log[i] = e end end
local qtext = {}
function __setQuestText(id, desc, obj) qtext[id] = { desc, obj } end
function GetQuestLogQuestText() local sel = C_QuestLog.GetSelectedQuest(); local t = qtext[sel]; if t then return t[1], t[2] end return "Go and slay the beasts.\n\nThen return.", "Kill 5 things" end

-- quest map positions for the book's plate (v0.8)
__waypoints, __pois, __noArt = {}, {}, {}
C_QuestLog.GetNextWaypoint = function(qid) local w = __waypoints[qid]; if w then return w[1], w[2], w[3] end end
C_QuestLog.GetQuestsOnMap = function(map) return __pois[map] or {} end
C_Map.GetMapInfo = function(id) return { name = "Map " .. tostring(id), mapID = id, parentMapID = (id == 37) and 13 or 0 } end
C_Map.MapHasArt = function(id) return not __noArt[id] end
WorldMapFrame.__focus = nil
function WorldMapFrame:SetFocusedQuestID(id) self.__focus = id end
function WorldMapFrame:ClearFocusedQuestID() self.__focus = nil end
function WorldMapFrame.ScrollContainer:InstantPanAndZoom(sc2, x, y) self.__scale2 = sc2; self.__pan = { x, y }; __zoomed = (__zoomed or 0) + 1 end

-- remember the backdrop fill, so a scenario can check nothing opaque sits over the pages (v0.8.4)
function Frame:SetBackdropColor(r, g, b, a) self.__bd = { r, g, b, a } end

-- Blizzard's objective tracker and the watch list by index (v0.9.0)
ObjectiveTrackerFrame = newFrame("Frame", "ObjectiveTrackerFrame", UIParent)
C_QuestLog.GetQuestIDForQuestWatchIndex = function(i)
  local ids = {}
  for id in pairs(__watchedSet and __watchedSet() or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids[i]
end

-- quest-area setters on the minimap: record the last value of every call (v0.9.1)
__blob = {}
for _, kind in ipairs({ "Quest", "Task", "Arch" }) do
  for _, layer in ipairs({ "Inside", "Outside", "Ring" }) do
    for _, what in ipairs({ "Alpha", "Texture", "Scalar" }) do
      if not (what == "Scalar" and layer ~= "Ring") then
        local name = "Set" .. kind .. "Blob" .. layer .. what
        Minimap[name] = function(self, v) __blob[kind .. layer .. what] = v end
      end
    end
  end
end
