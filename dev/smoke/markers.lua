-- Our quest markers on the minimap, and switching the client's quest areas off and back on.
-- Stubbed API: this checks our logic (positions, rotation, edge, restore), not what the client draws.
local tracking = { [1] = true, [2] = true, [3] = true }       -- 2 = "Quest POIs"
C_Minimap.GetNumTrackingTypes = function() return 3 end
C_Minimap.GetTrackingFilter = function(i) if i == 2 then return { filterID = 65536 } elseif i == 3 then return { spellID = 5 } end return { filterID = 1 } end
C_Minimap.GetTrackingInfo = function(i) return { name = "t" .. i, active = tracking[i] } end
C_Minimap.SetTracking = function(i, on) tracking[i] = on end
C_Map.GetMapWorldSize = function() return 1000, 1000 end
local facing = 0
function GetPlayerFacing() return facing end
local ppos = { x = 0.42, y = 0.61 }
C_Map.GetPlayerMapPosition = function() return { x = ppos.x, y = ppos.y, GetXY = function(s) return s.x, s.y end } end
__pois[37] = {
  { questID = 100, x = 0.42, y = 0.51 },    -- 100 yards north of the player (0.42, 0.61), watched, in the log
  { questID = 101, x = 0.52, y = 0.61 },    -- 100 yards east, ready to hand in
  { questID = 102, x = 0.30, y = 0.61 },    -- in a collapsed zone: not in the log index
  { questID = 999, x = 0.45, y = 0.61 },    -- a quest giver, not in the log
  { questID = 103, x = 0.90, y = 0.61 },    -- far east, in the log
}
local baseIdx = C_QuestLog.GetLogIndexForQuestID
C_QuestLog.GetLogIndexForQuestID = function(id) if id == 103 then return 7 end return baseIdx(id) end

-- the tracker's default "all" mode scans the log, which expands collapsed zones and would put quest 102 in it
QuestBookDB = { mod = { tracker = { mode = "tracked", v = 1 } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local M, O = QB.modules.markers, QB.modules.overlay
assert(M and M.active and not M.unavailable, "markers module is on")
local F = QuestBookMarkers
assert(F, "the marker frame exists")

-- the client's quest areas are switched off, and we remember it
assert(tracking[2] == false, "Quest POIs tracking switched off")
assert(tracking[1] and tracking[3], "the other tracking entries are untouched")
assert(M.db.areasBackup == true, "remembered that we switched it off")

-- the small minimap hosts at login: markers sit on it, smaller
assert(O.host == "corner" and F:IsShown(), "markers shown over the corner minimap")
local p1 = { F:GetPoint(1) }
assert(p1[2] == Minimap, "anchored to the minimap widget")

local function markers()
  local out = {}
  for _, f in ipairs(__frames) do if f.__parent == F and f.disc and f:IsShown() then out[#out + 1] = f end end
  return out
end
local function byGlyph(g) for _, f in ipairs(markers()) do if f.glyph:GetText() == g then return f end end end
__tick(8)
local sh = markers()
-- 100 (watched, in log) and 101 (ready): in the log. 102, 999: not. 103: in the log but far -> culled
assert(#sh == 2, "two quests in the log and near, got " .. #sh)
assert(byGlyph("?"), "the ready quest is marked ?")

-- the big minimap: exact positions
slash("overlay cycle"); __tick(8)
assert(O.host == "big", "big host")
local bw = select(1, Minimap:GetSize())
local ppy = (bw / 2) / 200
local function pos(f) local p = f.__points[1]; return p[4], p[5] end
local ready = byGlyph("?")
local sx, sy = pos(ready)
assert(math.abs(sx - 100 * ppy) < 0.01 and math.abs(sy) < 0.01, ("101 is 100 yd east: got %.2f,%.2f want %.2f,0"):format(sx, sy, 100 * ppy))
local north
for _, f in ipairs(markers()) do if f ~= ready then north = f end end
sx, sy = pos(north)
assert(math.abs(sx) < 0.01 and math.abs(sy - 100 * ppy) < 0.01, ("100 is 100 yd north: got %.2f,%.2f"):format(sx, sy))
-- big marker is full size, the corner one was smaller
assert(math.abs(north:GetWidth() - 14) < 0.01, "full size on the big minimap, got " .. north:GetWidth())

-- rotation: facing west puts north on the player's right
facing = math.pi / 2; __tick(3)
sx, sy = pos(north)
assert(math.abs(sx - 100 * ppy) < 0.01 and math.abs(sy) < 0.01, ("rotated: north to the right: got %.2f,%.2f"):format(sx, sy))
facing = 0; __tick(3)

-- DRAWING COST (Cesar, 2026-10-17: "when I rotate, the blips take time to follow"): turning is applied on
-- the very next frame, not at the next position refresh, and nothing is repainted or re-anchored needlessly.
local function counter(obj, name) local n = 0; local orig = obj[name]; obj[name] = function(...) n = n + 1; return orig(...) end; return function() return n end end
local nPoints = counter(north, "SetPoint")
local nText = counter(north.glyph, "SetText")
for _ = 1, 20 do __tick(1, 0.016) end                       -- standing still, not turning: no work at all
assert(nPoints() == 0, "idle frames move nothing, got " .. nPoints() .. " SetPoint calls")
assert(nText() == 0, "idle frames repaint nothing, got " .. nText())
facing = math.pi / 2; __tick(1, 0.016)                      -- ONE frame of 16 ms: shorter than any refresh interval
sx, sy = pos(north)
assert(math.abs(sx - 100 * ppy) < 0.01 and math.abs(sy) < 0.01, ("one frame after turning: got %.2f,%.2f"):format(sx, sy))
facing = math.pi; __tick(1, 0.016)
sx, sy = pos(north)
assert(math.abs(sx) < 0.01 and math.abs(sy + 100 * ppy) < 0.01, ("and the next: got %.2f,%.2f"):format(sx, sy))
for i = 1, 60 do facing = facing + 0.05; __tick(1, 0.016) end -- a long turn: positions only, never a repaint
assert(nText() == 0, "turning repaints nothing, got " .. nText())
assert(nPoints() == 62, "turning moves the markers once per frame, got " .. nPoints())
facing = 0; __tick(3, 0.016)
-- walking: the markers follow within a refresh interval (0.05 s)
ppos.y = ppos.y - 0.05                                      -- 50 yd north
__tick(4, 0.016)
sx, sy = pos(north)
assert(math.abs(sy - 50 * ppy) < 0.01, ("after walking 50 yd north the quest is 50 yd away: got %.2f"):format(sy))
ppos.y = 0.61; __tick(4, 0.016)

-- the active quest is larger, haloed and labelled; the others are not
C_SuperTrack.SetSuperTrackedQuestID(100); __fire("SUPER_TRACKING_CHANGED"); __tick(12)
local act
for _, f in ipairs(markers()) do if f.label:IsShown() then act = f end end
assert(act, "the active quest has a label")
assert(math.abs(act:GetWidth() - 14 * 1.35) < 0.01, "active is larger: " .. act:GetWidth())
assert(act.halo:IsShown(), "active has a halo")
assert(not ready.label:IsShown(), "the others have no label")

-- far quests: culled, unless active (then stuck to the edge)
local function find103() for _, f in ipairs(markers()) do local x = select(1, pos(f)); if x > 0.9 * (bw / 2) then return f end end end
assert(not find103(), "a far quest is not drawn")
C_SuperTrack.SetSuperTrackedQuestID(103); __fire("SUPER_TRACKING_CHANGED"); __tick(12)
local far = find103()
assert(far, "the active quest is drawn even when far")
sx = pos(far)
assert(math.abs(sx - 0.94 * bw / 2) < 0.01, ("stuck to the edge, got %.2f want %.2f"):format(sx, 0.94 * bw / 2))
assert(far:GetAlpha() < 1, "dimmer at the edge")
C_SuperTrack.SetSuperTrackedQuestID(0); __fire("SUPER_TRACKING_CHANGED"); __tick(12)

-- "tracked" shows only the watch list
slash("markers tracked"); __tick(12)
assert(#markers() == 1, "tracked: only quest 100, got " .. #markers())
-- "map" also shows the quest givers, marked !
slash("markers map"); __tick(12)
assert(byGlyph("!"), "map: the quest giver is drawn")
slash("markers all"); __tick(12)

-- calibration
local before = select(1, pos(byGlyph("?")))
slash("markers scale 1.5"); __tick(12)
assert(math.abs(select(1, pos(byGlyph("?"))) - 1.5 * before) < 0.01, "scale 1.5 stretches the distance")
slash("markers scale 1"); __tick(12)

-- off: the frame hides when no host has the minimap; back when it does
slash("overlay cycle"); __tick(8)        -- zone: the corner minimap again
assert(F:IsShown(), "still on the corner minimap in Map mode")

-- the client switching the areas back on (login restore, the magnifier menu) is answered
tracking[2] = true; __fire("MINIMAP_UPDATE_TRACKING"); __runTimers()
assert(tracking[2] == false, "switched off again after the client turned it on")
slash("markers")
local said = table.concat(__take(), "\n")
assert(said:find("call ok") or said:find("already off"), "the status says what the call did: " .. said)

-- giving the client's areas back
slash("markers areas native")
assert(tracking[2] == true and not M.db.areasBackup, "areas back on `areas native`")
slash("markers areas hidden")
assert(tracking[2] == false and M.db.areasBackup, "off again")
slash("disable markers")
assert(tracking[2] == true and not M.db.areasBackup, "disabling the module gives the areas back")
assert(not F:IsShown(), "frame hidden when disabled")
-- a quest area the user had switched off themselves is left off
tracking[2] = false; M.db.areasBackup = nil
slash("enable markers")
assert(tracking[2] == false and not M.db.areasBackup, "not ours to restore when it was already off")
slash("disable markers")
assert(tracking[2] == false, "and still left as the user had it")

-- a client without the tracking API: no error, says so
C_Minimap.GetNumTrackingTypes = nil
slash("enable markers"); __tick(3)
assert(M.areasNote, "says why the areas could not be switched off")
flush("markers")
