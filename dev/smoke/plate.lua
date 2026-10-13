-- the quest book hosts the world map in its left page: the map plate
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local Q = QB.modules.questlog
local O = QB.modules.overlay
local G = Q.layout

-- quests 100/101/102 are in the stub log; give them map positions
__waypoints[100] = { 37, 0.30, 0.40 }          -- a waypoint
__pois[37] = { { questID = 101, mapID = 37, x = 0.55, y = 0.65 } }   -- a marker on the player's map
-- 102 has neither

-- open the book on quest 100: the map moves into the plate
Q:OpenBook(100)
local B = QuestBookFrame
local W = WorldMapFrame
assert(B:IsShown())
assert(B.plateWanted and G.fit.plate and G.fit.plateH > 0, "the left page reserves a plate")
assert(O.zoneHost == "plate" and O.zoneOn, "the overlay module hosts the map for the plate")
assert(W:IsShown(), "world map shown")
assert(W:GetMapID() == 37, "on the quest's map")
assert(W.__focus == 100, "the quest is focused so the providers draw its area, got " .. tostring(W.__focus))
assert(O.cornerPanel and Minimap:GetParent() == O.cornerPanel, "the corner minimap stays up beside it")
-- placed inside the plate: size = plate - 2, anchored to it, above the book, opaque, no soft mask
local pw, ph = B.plate:GetSize()
local ww, wh = W:GetSize()
assert(ww == pw - 2 and wh == ph - 2, "map sized to the plate: " .. ww .. "x" .. wh .. " vs " .. pw .. "x" .. ph)
local pt = { W:GetPoint(1) }
assert(pt[1] == "CENTER" and pt[2] == B.plate, "anchored to the plate")
assert(W:GetFrameStrata() == "DIALOG", "above the book")
assert(W.ScrollContainer:GetAlpha() == 1, "opaque on the plate")
assert(not W:GetUseMaskTexture(), "no soft mask on the plate")
assert(not W:IsMouseEnabled(), "click-through")
assert(W:GetAlpha() == 0, "hidden until styled and positioned")
__tick(5, 0.016)
assert(W:GetAlpha() == 1, "revealed after the first frames")
local pan = W.ScrollContainer.__pan
assert(pan and math.abs(pan[1] - 0.30) < 1e-6 and math.abs(pan[2] - 0.40) < 1e-6, "centred on the quest's waypoint")
assert(B.plateCap:IsShown() and B.plateCap:GetText() == "Map 37", "caption names the map")

-- another quest: the position comes from its marker on the player's map; still one map host
Q:OpenBook(101)
__tick(5, 0.016)
pan = W.ScrollContainer.__pan
assert(W.__focus == 101, "focus follows the quest")
assert(math.abs(pan[1] - 0.55) < 1e-6 and math.abs(pan[2] - 0.65) < 1e-6, "centred on the marker")
-- a quest with no position: text only, the map is given back
Q:OpenBook(102)
assert(not B.plateWanted and not G.fit.plate, "no plate for a quest with no map position")
assert(O.zoneHost == "overlay" and not O.zoneOn and not W:IsShown(), "the world map is back with Blizzard")
assert(W.__focus == nil, "focus cleared")
assert(W:GetAlpha() == 1 and W:GetFrameStrata() ~= "DIALOG", "world map restored")
assert(select(1, B.plate:GetSize()) >= 0)

-- back to a quest with a position: it comes back
Q:OpenBook(100); __tick(5, 0.016)
assert(O.zoneHost == "plate" and W:IsShown())

-- Map mode takes the map from the book; the book's page gets its text back
slash("overlay zone"); __tick(5, 0.016)
assert(O.state == "zone" and O.zoneHost == "overlay", "Map mode owns the map")
assert(not B.plateWanted and not G.fit.plate, "the book lost its plate and re-fitted")
assert(W.ScrollContainer:GetAlpha() < 1 and W:GetFrameStrata() == "BACKGROUND", "Map mode look is back (translucent, behind)")
assert(W:GetUseMaskTexture(), "soft mask is back")
-- and the book takes it back, closing Map mode
Q:OpenBook(100); __tick(5, 0.016)
assert(O.zoneHost == "plate" and O.state ~= "zone", "the book's plate closes Map mode (one world map)")
assert(B.plateWanted)

-- ESC / the M key close the map: the plate goes, the text takes the page
W:Hide(); __tick(2, 0.016)
assert(not B.plateWanted and O.zoneHost == "overlay", "map closed by the game: plate released")
Q:OpenBook(100); __tick(5, 0.016)
assert(B.plateWanted)

-- combat: a plate is not started in combat, and is retried when combat ends
Q:OpenBook(102); assert(not B.plateWanted)
__combat = true
Q:OpenBook(100)
assert(not B.plateWanted and not O.zoneOn, "no re-hosting in combat")
__combat = false; __fire("PLAYER_REGEN_ENABLED"); __tick(3, 0.016)
assert(B.plateWanted and O.zoneHost == "plate", "retried when combat ended")
-- the overlay closing itself for combat does not take the book's plate
__combat = true; __fire("PLAYER_REGEN_DISABLED")
assert(O.zoneHost == "plate" and B.plateWanted, "combat start leaves the book's plate alone")
__combat = false; __fire("PLAYER_REGEN_ENABLED")

-- setting off
slash("book map off"); assert(not B.plateWanted and not O.zoneOn, "plate off: text only")
slash("book map on"); assert(B.plateWanted)

-- docked: no map in the small walking panel
__fire("PLAYER_STARTED_MOVING")
assert(G.docked and not B.plate:IsShown() and not O.zoneOn, "docked = text only, map given back")

-- closing the book gives the map back
slash(""); slash("")                         -- close and reopen
Q:OpenBook(100); __tick(5, 0.016)
assert(O.zoneOn)
B:Hide()
assert(not O.zoneOn and not W:IsShown() and O.zoneHost == "overlay", "book closed: the world map is Blizzard's again")
assert(W:GetAlpha() == 1)

-- disabling the overlay module: the book just has no plate
QB:SetEnabled("overlay", false)
Q:OpenBook(100)
assert(not B.plateWanted, "no overlay module, no plate; the book still works")
QB:SetEnabled("overlay", true)
slash("overlay diag"); flush("diag")
print("plate ok")
