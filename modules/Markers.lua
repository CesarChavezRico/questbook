-- QuestBook Markers -- our own quest markers on the enlarged (and the corner) minimap, in place of
-- the client's quest areas.
--
-- Cesar, 2026-10-15: the client's quest-area art does not survive the blow-up and cannot be restyled
-- (the Minimap blob setters were tried in v0.9.1 and change nothing on this client), so "remove them
-- from the blown up minimap and replace the areas with icons". Two parts:
--
--   1. The areas are switched off through the minimap's "Quest POIs" tracking filter
--      (Enum.MinimapTrackingFilter.QuestPOIs, C_Minimap.SetTracking; the same switch as the magnifier
--      menu next to the minimap). The old state is remembered and put back on disable.
--   2. One small brass marker per quest, placed over the minimap from the quest's position on the map
--      (C_QuestLog.GetQuestsOnMap) and the player's (C_Map.GetPlayerMapPosition): all quests in the log,
--      the active (super-tracked) one larger and labelled, a quest ready to hand in marked "?". A marker
--      past the edge sticks to the edge, dimmer, so it still says which way.
--
-- UNVERIFIED (client only): that the tracking filter really removes the areas; that GetViewRadius() is
-- the distance from the minimap's centre to its edge as drawn (the pixels-per-yard maths rests on it:
-- `/qb markers scale <n>` corrects it, `/qb markers map` draws the quest givers too so they can be lined up
-- with the client's own "!" blips); that the rotation formula matches the client's.

local ADDON, QB = ...
local Style = QB.Style

local mod = QB:NewModule("markers", {
  which = "all",      -- "all" (every quest in the log) | "tracked" (the watch list) | "map" (also quest givers)
  size = 14,          -- marker diameter in UI units on the big minimap (the corner one uses 0.75 of it)
  scale = 1,          -- calibration: multiplies pixels per yard
  areas = "hidden",   -- "hidden" (the client's quest areas are switched off) | "native" (left alone)
})

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local DISC = TEX .. "mask_circle.tga"          -- white, soft edge: tinted it is a round marker
local QUEST_POIS = 65536                       -- Enum.MinimapTrackingFilter.QuestPOIs (MinimapConstantsDocumentation.lua)
local ROTATE_CVAR = "rotateMinimap"
local LOCATE = 0.05                            -- seconds between re-reads of where you are (turning is every frame)
local COLLECT = 0.25                           -- at most this often re-read the quest list
local EDGE = 0.94                              -- markers past the edge stick here (fraction of the half-size)
local CULL = 1.6                               -- a non-active marker farther than this (x the edge) is hidden

local FRIZ = Style.FRIZ
local frame
local pool = {}
local entries = {}
local dirty = true
local sinceLocate, sinceCollect = 0, 99
local playerPos, worldSize = {}, {}            -- per-pass caches keyed by map id
local cos, sin, abs, max = math.cos, math.sin, math.abs, math.max

local function Tone() return Style.Get("dark") end

local function NewText(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FRIZ, size, "")             -- a font at birth: SetText on a fontless string is an error
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.9)
  return fs
end

-- ---------------------------------------------------------------- the client's quest areas

-- The index of the "Quest POIs" entry in the minimap's tracking list, or nil.
local function QuestPoiIndex()
  if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingFilter) then return nil end
  local okN, n = pcall(C_Minimap.GetNumTrackingTypes)
  if not (okN and type(n) == "number") then return nil end
  local want = (Enum and Enum.MinimapTrackingFilter and Enum.MinimapTrackingFilter.QuestPOIs) or QUEST_POIS
  for i = 1, n do
    local ok, f = pcall(C_Minimap.GetTrackingFilter, i)
    if ok and type(f) == "table" and f.filterID == want then return i end
  end
  return nil
end

local function PoiName(index)
  if not (index and C_Minimap and C_Minimap.GetTrackingInfo) then return "?" end
  local ok, info = pcall(C_Minimap.GetTrackingInfo, index)
  if ok and type(info) == "table" then return tostring(info.name) end
  return "?"
end

local function PoiActive(index)
  if not (index and C_Minimap and C_Minimap.GetTrackingInfo) then return nil end
  local ok, info = pcall(C_Minimap.GetTrackingInfo, index)
  if ok and type(info) == "table" then return info.active and true or false end
  return nil
end

-- Switch the client's areas off (remembering that we did) or give them back. `release` = this module is
-- going away: always give them back (QB:Disable runs OnDisable while `active` is still true).
-- What the call did is kept in self.areasCall for the status line: in the game (2026-10-17) the areas stayed
-- while the status read "now true" after this ran, and nothing says which of the three is at fault: the call
-- is refused, the reading is not what we take it for, or the client switches it back on afterwards.
function mod:ApplyAreas(release)
  local db = self.db
  local idx = QuestPoiIndex()
  self.poiIndex = idx
  if not (idx and C_Minimap.SetTracking) then
    self.areasNote = idx and "no SetTracking" or "no Quest POIs entry in the tracking list"
    return
  end
  self.areasNote = nil
  local active = PoiActive(idx)
  if db.areas == "hidden" and not release then
    if active then
      local ok, err = pcall(C_Minimap.SetTracking, idx, false)
      self.areasCall = ok and "call ok" or ("call failed: " .. tostring(err))
      if ok then db.areasBackup = true end
    else
      self.areasCall = "already off"
    end
  elseif db.areasBackup then
    local ok, err = pcall(C_Minimap.SetTracking, idx, true)
    self.areasCall = ok and "restored" or ("restore failed: " .. tostring(err))
    if ok then db.areasBackup = nil end
  end
end

-- ---------------------------------------------------------------- data

local function Info(qid)
  -- (in the log?, ready to hand in?, on the watch list?)
  local inLog, ready, tracked = false, false, false
  if C_QuestLog then
    if C_QuestLog.GetLogIndexForQuestID then
      local ok, idx = pcall(C_QuestLog.GetLogIndexForQuestID, qid)
      inLog = ok and type(idx) == "number" and idx > 0
    end
    if inLog and C_QuestLog.IsComplete then
      local ok, c = pcall(C_QuestLog.IsComplete, qid)
      ready = ok and c and true or false
    end
    if inLog and C_QuestLog.GetQuestWatchType then
      local ok, w = pcall(C_QuestLog.GetQuestWatchType, qid)
      tracked = ok and w ~= nil
    end
  end
  return inLog, ready, tracked
end

local function ActiveQuest()
  if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  return nil
end

-- The quests with a point on the player's map or on the maps above it (the most specific map wins).
function mod:Collect()
  wipe(entries)
  self.total = 0
  if not (C_Map and C_Map.GetBestMapForUnit and C_QuestLog and C_QuestLog.GetQuestsOnMap) then return end
  local which = self.db.which
  local active = ActiveQuest()
  local seen = {}
  local okM, m = pcall(C_Map.GetBestMapForUnit, "player")
  m = okM and m or nil
  for _ = 1, 5 do
    if not m then break end
    local ok, list = pcall(C_QuestLog.GetQuestsOnMap, m)
    if ok and type(list) == "table" then
      for _, q in ipairs(list) do
        local qid = q.questID
        if qid and not seen[qid] and q.x and q.y then
          local inLog, ready, tracked = Info(qid)
          local keep = (which == "map") or (inLog and (which == "all" or tracked or qid == active))
          if keep then
            seen[qid] = true
            entries[#entries + 1] = {
              qid = qid, map = m, x = q.x, y = q.y,
              inLog = inLog, ready = ready, active = (qid == active),
            }
          end
        end
      end
    end
    local okI, info = pcall(C_Map.GetMapInfo, m)
    m = okI and info and info.parentMapID
    if not m or m == 0 then break end
  end
  self.total = #entries
end

-- ---------------------------------------------------------------- drawing

local function GetMarker(i)
  local mk = pool[i]
  if mk then return mk end
  mk = CreateFrame("Frame", nil, frame)
  mk:EnableMouse(false)                       -- click-through, like the minimap panel it sits on
  mk.shadow = mk:CreateTexture(nil, "ARTWORK", nil, 0)
  mk.shadow:SetTexture(DISC)
  mk.shadow:SetVertexColor(0, 0, 0, 0.55)
  mk.halo = mk:CreateTexture(nil, "ARTWORK", nil, 1)
  mk.halo:SetTexture(DISC)
  mk.disc = mk:CreateTexture(nil, "ARTWORK", nil, 2)
  mk.disc:SetTexture(DISC)
  mk.glyph = NewText(mk, 11)
  mk.glyph:SetPoint("CENTER", mk, "CENTER", 0, 0)
  mk.label = NewText(mk, 11)
  mk.label:SetJustifyH("LEFT")
  mk.label:SetPoint("LEFT", mk, "RIGHT", 6, 0)
  pool[i] = mk
  return mk
end

-- Everything that does not change while you turn: size, colour, glyph, title, halo. Run when the quest list
-- or the host changes, never per frame.
local function Paint(mk, e, size)
  local t = Tone()
  mk:SetSize(size, size)
  mk.shadow:ClearAllPoints()
  mk.shadow:SetPoint("CENTER", mk, "CENTER", 0, 0)
  mk.shadow:SetSize(size * 1.55, size * 1.55)
  mk.disc:ClearAllPoints()
  mk.disc:SetPoint("CENTER", mk, "CENTER", 0, 0)
  mk.disc:SetSize(size, size)
  local c = e.ready and t.done or (e.active and t.strong or t.pending)
  mk.disc:SetVertexColor(c[1], c[2], c[3], 1)
  if e.active then
    mk.halo:ClearAllPoints()
    mk.halo:SetPoint("CENTER", mk, "CENTER", 0, 0)
    mk.halo:SetSize(size * 1.45, size * 1.45)
    mk.halo:SetVertexColor(t.chromeHot[1], t.chromeHot[2], t.chromeHot[3], 0.9)
    mk.halo:Show()
  else
    mk.halo:Hide()
  end
  local glyph = ""
  if e.ready then glyph = "?" elseif not e.inLog then glyph = "!" end
  mk.glyph:SetText(glyph)
  mk.glyph:SetTextColor(0.10, 0.09, 0.08, 1)
  if e.active then
    local title
    if C_QuestLog and C_QuestLog.GetTitleForQuestID then
      local ok, name = pcall(C_QuestLog.GetTitleForQuestID, e.qid)
      title = ok and name or nil
    end
    mk.label:SetText(title or "")
    mk.label:SetTextColor(t.ink[1], t.ink[2], t.ink[3], 1)
    mk.label:Show()
  else
    mk.label:SetText("")
    mk.label:Hide()
  end
end

local function PlayerPos(mapID)
  local p = playerPos[mapID]
  if p ~= nil then return p[1], p[2] end
  playerPos[mapID] = false
  if C_Map and C_Map.GetPlayerMapPosition then
    local ok, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
    if ok and type(pos) == "table" then
      local x, y = pos.x, pos.y
      if (x == nil or y == nil) and pos.GetXY then x, y = pos:GetXY() end
      if type(x) == "number" and type(y) == "number" then playerPos[mapID] = { x, y } end
    end
  end
  local q = playerPos[mapID]
  if q then return q[1], q[2] end
  return nil
end

local function WorldSize(mapID)
  local s = worldSize[mapID]
  if s ~= nil then return s[1], s[2] end
  worldSize[mapID] = false
  if C_Map and C_Map.GetMapWorldSize then
    local ok, w, h = pcall(C_Map.GetMapWorldSize, mapID)
    if ok and type(w) == "number" and type(h) == "number" and w > 0 and h > 0 then worldSize[mapID] = { w, h } end
  end
  local s2 = worldSize[mapID]
  if s2 then return s2[1], s2[2] end
  return nil
end

local function Rotating()
  if not (C_CVar and C_CVar.GetCVar) then return false end
  local ok, v = pcall(C_CVar.GetCVar, ROTATE_CVAR)
  return ok and v == "1"
end

function mod:Host()
  local ov = QB.modules.overlay
  return ov and ov.active and ov.host or nil
end

-- One marker per entry, painted once.
function mod:PaintAll()
  local size = (tonumber(self.db.size) or 14) * (self:Host() == "corner" and 0.75 or 1)
  local lvl = frame:GetFrameLevel()
  for i, e in ipairs(entries) do
    local mk = GetMarker(i)
    e.mk = mk
    Paint(mk, e, e.active and size * 1.35 or size)
    mk:SetFrameLevel(lvl + (e.active and 3 or 1))
    mk:Hide(); mk.vis = false; mk.edge = nil
  end
  for i = #entries + 1, #pool do pool[i]:Hide(); pool[i].vis = false end
  self.moved = true
end

-- How far each quest is from you in yards (east, north), and the minimap's scale. Re-read at LOCATE
-- intervals: it costs a few API calls and a table each, so it is not done every frame. Turning does not
-- need it: Draw rotates these cached offsets every frame.
function mod:Locate()
  local mm = _G.Minimap
  local w, h
  if mm then w, h = mm:GetSize() end
  local radius
  if C_Minimap and C_Minimap.GetViewRadius then
    local ok, r = pcall(C_Minimap.GetViewRadius)
    if ok and type(r) == "number" and r > 0 then radius = r end
  end
  self.radius = radius
  if not (w and h and w > 0 and h > 0 and radius) then self.geo = nil; return end
  local g = self.geo or {}
  self.geo = g
  local hw, hh = w / 2, h / 2
  local ppy = math.min(hw, hh) / radius * (tonumber(self.db.scale) or 1)
  local rot = Rotating()
  if g.hw ~= hw or g.hh ~= hh or g.ppy ~= ppy or g.rotating ~= rot then self.moved = true end
  g.hw, g.hh, g.ppy, g.rotating = hw, hh, ppy, rot
  wipe(playerPos); wipe(worldSize)
  for _, e in ipairs(entries) do
    local px, py = PlayerPos(e.map)
    local W, H = WorldSize(e.map)
    local east, north
    if px and W then
      -- yards east / north of the player (map x grows east, map y grows south)
      east, north = (e.x - px) * W, -(e.y - py) * H
    end
    if east ~= e.east or north ~= e.north then
      if not (east and e.east and math.abs(east - e.east) < 0.02 and math.abs(north - e.north) < 0.02) then
        self.moved = true
        e.east, e.north = east, north
      end
    end
  end
end

-- Every frame: rotate the cached offsets by the current facing and move the markers. Does nothing at all
-- when you are neither turning nor moving.
function mod:Draw(force)
  local g = self.geo
  if not (g and frame and frame:IsShown()) then return end
  local facing = 0
  if g.rotating and GetPlayerFacing then
    local f = GetPlayerFacing()
    if type(f) == "number" then facing = f end
  end
  if not (force or self.moved or facing ~= self.lastFacing) then return end
  self.moved = false
  self.lastFacing = facing
  local c, s = cos(facing), sin(facing)
  local hw, hh, ppy = g.hw, g.hh, g.ppy
  local used = 0
  for _, e in ipairs(entries) do
    local mk = e.mk
    local show = false
    if mk and e.east then
      local sx = (e.east * c + e.north * s) * ppy
      local sy = (-e.east * s + e.north * c) * ppy
      local k = max(abs(sx) / (hw * EDGE), abs(sy) / (hh * EDGE))
      local edge = k > 1
      if edge then sx, sy = sx / k, sy / k end
      if not edge or e.active or k <= CULL then
        show = true
        used = used + 1
        if mk.edge ~= edge then mk.edge = edge; mk:SetAlpha(edge and 0.6 or 1) end
        mk:SetPoint("CENTER", frame, "CENTER", sx, sy)     -- same anchor point: replaces the old offset
        if not mk.vis then mk:Show(); mk.vis = true end
      end
    end
    if not show and mk and mk.vis then mk:Hide(); mk.vis = false end
  end
  self.shown = used
end

-- The whole pass: read the quests, paint, locate, draw.
function mod:Refresh()
  if not frame then return end
  dirty = false
  sinceCollect, sinceLocate = 0, 0
  self:Collect()
  self:PaintAll()
  self:Locate()
  self:Draw(true)
end

local function Tick(dt)
  if not mod.active then return end
  sinceCollect = sinceCollect + dt
  sinceLocate = sinceLocate + dt
  if dirty and sinceCollect >= COLLECT then
    mod:Refresh()
    return
  end
  if sinceLocate >= LOCATE then
    sinceLocate = 0
    mod:Locate()
  end
  mod:Draw()
end

local function Build()
  if frame then return frame end
  frame = CreateFrame("Frame", "QuestBookMarkers", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:EnableMouse(false)
  frame:Hide()
  -- every frame, so no QB:Safe here (it builds a table per call); a fault is still reported, once
  frame:SetScript("OnUpdate", function(_, dt)
    local ok, err = pcall(Tick, dt or 0)
    if not ok then QB:ReportError("markers", err) end
  end)
  return frame
end

-- On while the Minimap is held by the big panel or the corner (the overlay says which); off otherwise.
function mod:Sync()
  if not frame then return end
  local mm = _G.Minimap
  local host = self:Host()
  if host and mm and mm:IsVisible() then      -- visible: the corner minimap may be hidden while the reader is open
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 0, 0)
    local lvl = mm.GetFrameLevel and mm:GetFrameLevel() or 1
    frame:SetFrameLevel(lvl + 5)
    frame:Show()
    self:Refresh()
  else
    frame:Hide()
  end
end

-- ---------------------------------------------------------------- lifecycle

function mod:OnInit()
  if type(CreateFrame) ~= "function" or not UIParent then self.unavailable = "no UI"; return end
  -- a crash while the areas were off, with this module then switched off: give them back
  if self.db.enabled == false and self.db.areasBackup then
    local idx = QuestPoiIndex()
    if idx and C_Minimap.SetTracking and pcall(C_Minimap.SetTracking, idx, true) then self.db.areasBackup = nil end
  end
end

function mod:OnEnable()
  Build()
  dirty = true
  self:ApplyAreas()
  self:Sync()
end

function mod:OnDisable()
  if frame then frame:Hide() end
  self:ApplyAreas(true)        -- gives the client's areas back
end

local function Dirty() dirty = true end

mod.events.QUEST_LOG_UPDATE = Dirty
mod.events.QUEST_WATCH_LIST_CHANGED = Dirty
mod.events.QUEST_POI_UPDATE = Dirty
mod.events.SUPER_TRACKING_CHANGED = Dirty
mod.events.QUEST_REMOVED = Dirty
mod.events.QUEST_TURNED_IN = Dirty
mod.events.ZONE_CHANGED_NEW_AREA = Dirty
mod.events.ZONE_CHANGED = Dirty
mod.events.PLAYER_ENTERING_WORLD = function(self) dirty = true; self:ApplyAreas(); self:Sync() end
-- the client switching a tracking entry back on (login restore, the magnifier menu) is answered once the
-- change has settled; our own call also fires it, and finds the entry already off
mod.events.MINIMAP_UPDATE_TRACKING = function(self)
  if self.db.areas ~= "hidden" or self.trackingQueued then return end
  self.trackingTries = (self.trackingTries or 0) + 1
  if self.trackingTries > 6 then return end        -- the client keeps winning: stop arguing with it
  self.trackingQueued = true
  local function again() self.trackingQueued = false; if self.active then self:ApplyAreas() end end
  if C_Timer and C_Timer.After then C_Timer.After(0.5, again) else again() end
end

QB:On("overlay_host", function() if mod.active then mod:Sync() end end, mod)
QB:On("overlay_state", function() if mod.active then mod:Sync() end end, mod)

-- ---------------------------------------------------------------- slash

local function Status()
  local db = mod.db
  local idx = mod.poiIndex
  QB:Say(string.format(
    "markers: %s, %d of %d quests shown, size %d, scale %.2f | client areas: %s (tracking entry %s \"%s\", now %s, %s%s) | view radius %s yd, host %s",
    db.which, mod.shown or 0, mod.total or 0, db.size, db.scale, db.areas,
    idx and tostring(idx) or "not found", PoiName(idx), tostring(PoiActive(idx)),
    tostring(mod.areasCall),
    mod.areasNote and (", " .. mod.areasNote) or "",
    mod.radius and string.format("%.0f", mod.radius) or "?", tostring(mod:Host())))
end

QB:RegisterSlash(mod, "markers", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  local db = mod.db
  if sub == "all" or sub == "tracked" or sub == "map" then
    db.which = sub
  elseif sub == "which" and (arg == "all" or arg == "tracked" or arg == "map") then
    db.which = arg
  elseif sub == "size" and n then
    db.size = Style.Clamp(n, 6, 40)
  elseif sub == "scale" and n then
    db.scale = Style.Clamp(n, 0.2, 5)
  elseif sub == "areas" and (arg == "native" or arg == "hidden") then
    db.areas = arg
    mod:ApplyAreas()
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb markers all|tracked|map | size <n> | scale <n> | areas native|hidden   (map = also quest givers, to line the markers up with the client's own blips; scale corrects the distance if they sit too near or too far)")
  end
  dirty = true
  mod:Sync()
  Status()
end, "markers all|tracked|map|size|scale|areas: our quest markers on the minimap, in place of the client's quest areas")
