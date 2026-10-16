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
local TICK = 0.1                               -- seconds between position updates while shown
local COLLECT = 0.5                            -- at most this often re-read the quest list
local EDGE = 0.94                              -- markers past the edge stick here (fraction of the half-size)
local CULL = 1.6                               -- a non-active marker farther than this (x the edge) is hidden

local FRIZ = Style.FRIZ
local frame
local pool = {}
local entries = {}
local dirty = true
local sinceTick, sinceCollect = 0, 99
local playerPos, worldSize = {}, {}            -- per-tick caches keyed by map id

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

local function PoiActive(index)
  if not (index and C_Minimap and C_Minimap.GetTrackingInfo) then return nil end
  local ok, info = pcall(C_Minimap.GetTrackingInfo, index)
  if ok and type(info) == "table" then return info.active and true or false end
  return nil
end

-- Switch the client's areas off (remembering that we did) or give them back. `release` = this module is
-- going away: always give them back (QB:Disable runs OnDisable while `active` is still true).
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
      if pcall(C_Minimap.SetTracking, idx, false) then db.areasBackup = true end
    end
  elseif db.areasBackup then
    if pcall(C_Minimap.SetTracking, idx, true) then db.areasBackup = nil end
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

local function Paint(mk, e, size, edge)
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
  mk:SetAlpha(edge and 0.6 or 1)
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

function mod:Place()
  if not (frame and frame:IsShown()) then return end
  local mm = _G.Minimap
  if not mm then return end
  local w, h = mm:GetSize()
  if not (w and h and w > 0 and h > 0) then return end
  local radius
  if C_Minimap and C_Minimap.GetViewRadius then
    local ok, r = pcall(C_Minimap.GetViewRadius)
    if ok and type(r) == "number" and r > 0 then radius = r end
  end
  self.radius = radius
  if not radius then
    for i = 1, #pool do pool[i]:Hide() end
    return
  end
  wipe(playerPos); wipe(worldSize)
  local hw, hh = w / 2, h / 2
  local ppy = math.min(hw, hh) / radius * (tonumber(self.db.scale) or 1)
  local facing = 0
  if Rotating() and GetPlayerFacing then
    local ok, f = pcall(GetPlayerFacing)
    if ok and type(f) == "number" then facing = f end
  end
  local c, s = math.cos(facing), math.sin(facing)
  local size = (tonumber(self.db.size) or 14) * (self:Host() == "corner" and 0.75 or 1)
  local used = 0
  for _, e in ipairs(entries) do
    local px, py = PlayerPos(e.map)
    local W, H = WorldSize(e.map)
    if px and W then
      -- yards east / north of the player (map x grows east, map y grows south)
      local east, north = (e.x - px) * W, -(e.y - py) * H
      local sx = (east * c + north * s) * ppy
      local sy = (-east * s + north * c) * ppy
      local k = math.max(math.abs(sx) / (hw * EDGE), math.abs(sy) / (hh * EDGE))
      local edge = k > 1
      if edge then sx, sy = sx / k, sy / k end
      if not edge or e.active or k <= CULL then
        used = used + 1
        local mk = GetMarker(used)
        Paint(mk, e, e.active and size * 1.35 or size, edge)
        mk:ClearAllPoints()
        mk:SetPoint("CENTER", frame, "CENTER", sx, sy)
        mk:SetFrameLevel(frame:GetFrameLevel() + (e.active and 3 or 1))
        mk:Show()
      end
    end
  end
  for i = used + 1, #pool do pool[i]:Hide() end
  self.shown = used
end

local function Tick(_, dt)
  if not mod.active then return end
  sinceTick = sinceTick + (dt or 0)
  sinceCollect = sinceCollect + (dt or 0)
  if sinceTick < TICK then return end
  sinceTick = 0
  if dirty and sinceCollect >= COLLECT then
    dirty = false
    sinceCollect = 0
    mod:Collect()
  end
  mod:Place()
end

local function Build()
  if frame then return frame end
  frame = CreateFrame("Frame", "QuestBookMarkers", UIParent)
  frame:SetFrameStrata("MEDIUM")
  frame:EnableMouse(false)
  frame:Hide()
  frame:SetScript("OnUpdate", function(f, dt) QB:Safe(mod, Tick, f, dt) end)
  return frame
end

-- On while the Minimap is held by the big panel or the corner (the overlay says which); off otherwise.
function mod:Sync()
  if not frame then return end
  local mm = _G.Minimap
  local host = self:Host()
  if host and mm and mm:IsShown() then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", mm, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", mm, "BOTTOMRIGHT", 0, 0)
    local lvl = mm.GetFrameLevel and mm:GetFrameLevel() or 1
    frame:SetFrameLevel(lvl + 5)
    if not frame:IsShown() then dirty = true; sinceCollect = 99 end
    frame:Show()
    self:Place()
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

QB:On("overlay_host", function() if mod.active then mod:Sync() end end, mod)
QB:On("overlay_state", function() if mod.active then mod:Sync() end end, mod)

-- ---------------------------------------------------------------- slash

local function Status()
  local db = mod.db
  local idx = mod.poiIndex
  QB:Say(string.format(
    "markers: %s, %d of %d quests shown, size %d, scale %.2f | client areas: %s (Quest POIs entry %s, now %s%s) | view radius %s yd, host %s",
    db.which, mod.shown or 0, mod.total or 0, db.size, db.scale, db.areas,
    idx and tostring(idx) or "not found", tostring(PoiActive(idx)),
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
    QB:Say("/qb markers all|tracked|map | size <n> | scale <n> | areas native|hidden   (map = also quest givers, to line the markers up with the client's own blips; scale corrects the distance if they sit too near or too far)")
  end
  dirty = true; sinceCollect = 99
  mod:Collect(); mod:Sync()
  Status()
end, "markers all|tracked|map|size|scale|areas: our quest markers on the minimap, in place of the client's quest areas")
