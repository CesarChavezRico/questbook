-- v0.38.0 (4BI-38): the Lore link on the reader bar: hidden / new / read, and what it asks the bridge for.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local P, G = QB.modules.places, QB.modules.guide
assert(P and P.active and G and G.active, "places and guide modules on")
assert(type(QB.PlacesIndex) == "table" and QB.PlacesIndex[1438] and QB.PlacesIndex[1438].zone == "Teldrassil", "the list of places with a story is loaded")
local tts = {}
WoWAI = { SendTts = function(action, slot, ref, text, meta) tts[#tts + 1] = { action = action, ref = ref, text = text, meta = meta }; return true, #tts end,
  IsConnected = function() return true end, Connect = function() end }
local map, sub, parents = 1438, "The Oracle Glade", {}
C_Map.GetBestMapForUnit = function() return map end
C_Map.GetMapInfo = function(id) return { mapID = id, name = "Map " .. id, parentMapID = parents[id] or 0 } end
GetSubZoneText = function() return sub end
local bar = QuestBookReaderBar
local function at(m, s) map, sub = m, s; __fire("ZONE_CHANGED") end

-- the key rule is the list's
assert(P:Norm("The Oracle Glade") == "oracle glade" and P:Norm("Ban'ethil Barrow Den") == "banethil barrow den" and P:Norm("Lake Al'Ameth") == "lake alameth", "keys")

-- an area with a story, not asked for yet: the link is there, in the attention colour
at(1438, "The Oracle Glade")
local cur = P:Current()
assert(cur and cur.map == 1438 and cur.name == "The Oracle Glade" and cur.id == "1438:oracle glade" and not cur.read, "the area you stand in")
assert(bar.lore:IsShown() and bar.lore:GetText() == "Lore" and bar.lore.warn, "new: Lore, marked")
-- a click asks the bridge for it and marks it read
__take(); bar.lore:Click()
local s = tts[#tts]
assert(s.action == "place" and s.ref == "p1438" and s.text == "" and s.meta.area == "The Oracle Glade", "the request: place, the map, the area's name")
assert(table.concat(__take(), "\n"):find("asked for the story of The Oracle Glade", 1, true), "says what it asked for")
assert(bar.lore:GetText() == "Lore (read)" and not bar.lore.warn, "read: says so: " .. tostring(bar.lore:GetText()))
assert(QuestBookDB.mod.places.read["1438:oracle glade"], "and it is saved")
-- a click on a read one reads it again
local n = #tts; bar.lore:Click(); assert(#tts == n + 1 and table.concat(__take(), "\n"):find("(again)", 1, true), "again")

-- an area with no story of its own: the zone's story is offered, with its own mark
at(1438, "Some Unnamed Hollow")
cur = P:Current()
assert(cur and cur.name == "Teldrassil" and cur.area == "" and cur.id == "1438:" and not cur.read, "no area story: the zone's")
assert(bar.lore:GetText() == "Lore", "the zone is new")
bar.lore:Click(); assert(tts[#tts].ref == "p1438" and tts[#tts].meta.area == "", "the zone is asked for with no area")
assert(bar.lore:GetText() == "Lore (read)")
-- no sub-zone text at all: the zone
at(1438, ""); assert(P:Current().id == "1438:" and P:Current().read)
-- back in the first area: still read
at(1438, "The Oracle Glade"); assert(bar.lore:GetText() == "Lore (read)")

-- a map the list does not have, inside a listed zone (a cave's own map): the zone above it
parents[5000] = 1438
at(5000, "Aldrassil"); assert(P:Current().map == 1438 and P:Current().name == "Aldrassil", "the parent zone's list is used")
-- an area the list keeps under another zone than the map says: found when only one zone has it
at(1438, "Temple Gardens"); cur = P:Current()
assert(cur.map == 1457 and cur.id == "1457:temple gardens", "found under the one zone that has it: " .. tostring(cur.map))
-- nowhere the list knows: the link is hidden
at(424242, "Limbo"); assert(P:Current() == nil and not bar.lore:IsShown(), "no story: no link")
__take(); SlashCmdList.QUESTBOOK("lore read"); assert(table.concat(__take(), "\n"):find("no story for this place", 1, true))
-- the other links still sit in a row with Lore hidden
assert(bar.story:IsShown() and bar.onoff:IsShown())

-- status, forget, and an old relay addon
at(1438, "The Oracle Glade")
SlashCmdList.QUESTBOOK("lore"); local said = table.concat(__take(), "\n")
assert(said:find("The Oracle Glade: already read", 1, true) and said:find("2 of 925 places read", 1, true), "status: " .. said)
SlashCmdList.QUESTBOOK("lore forget"); __take()
assert(not P:Current().read and bar.lore:GetText() == "Lore", "forget clears the marks")
local old = WoWAI.SendTts
WoWAI.SendTts = function() return false, "bad action" end
SlashCmdList.QUESTBOOK("lore read")
assert(table.concat(__take(), "\n"):find("older than the lore", 1, true) and not P:Current().read, "an old relay addon: said, and not marked read")
WoWAI.SendTts = old
print("places ok")
