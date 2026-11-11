-- The minimap's tracking list in the Menu drawer (4BI-36, Cesar 2026-11-11). Stand-in for the game's tracking menu:
-- our logic (list, switching, repaint, size), not the look.
local tracking = { { name = "Find Herbs", texture = 133939, active = false }, { name = "Quest POIs", texture = 136460, active = true }, { name = "Flight Master", active = false } }
C_Minimap.GetNumTrackingTypes = function() return #tracking end
C_Minimap.GetTrackingInfo = function(i) local t = tracking[i]; return { name = t.name, texture = t.texture, active = t.active } end
C_Minimap.SetTracking = function(i, on) tracking[i].active = on end
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
local D = QB.modules.drawers
assert(D and D.active, "drawers is on")
slash("drawers open"); __tick(3)
local panel = D:GetPanel()
assert(panel and panel:IsShown(), "the menu is open")
-- the rows are buttons of ours under the panel: find them by their text
local function row(name)
  for _, f in ipairs(__frames) do if f.text and f.text.GetText and f.text:GetText() == name and f.index then return f end end
end
local herbs, pois, flight = row("Find Herbs"), row("Quest POIs"), row("Flight Master")
assert(herbs and pois and flight, "one row per entry of the game's tracking menu")
assert(pois.active == true and herbs.active == false, "the rows know what is on")
local h0 = panel:GetHeight()
assert(h0 >= 4 * 17, "the panel has room for the title and three rows: " .. tostring(h0))
-- a click switches the entry
herbs:GetScript("OnClick")(herbs)
assert(tracking[1].active == true and row("Find Herbs").active == true, "clicking switches it on")
pois:GetScript("OnClick")(pois)
assert(tracking[2].active == false, "and off")
-- the game changes one behind our back: the list follows
tracking[3].active = true
__fire("MINIMAP_UPDATE_TRACKING")
assert(row("Flight Master").active == true, "the list repaints when the game says tracking changed")
-- a game that refuses: said, no error
local real = C_Minimap.SetTracking
C_Minimap.SetTracking = function() error("blocked") end
flight:GetScript("OnClick")(flight)
assert(said("tracking: the game refused"), "a refusal is reported")
C_Minimap.SetTracking = real
-- off: the list goes and the panel shrinks
slash("drawers tracking off"); __tick(1)
assert(said("the tracking list is off"), "says so")
assert(panel:GetHeight() < h0, "the panel is smaller without the list")
slash("drawers tracking on"); __tick(1)
assert(math.abs(panel:GetHeight() - h0) < 0.5, "and back")
slash("drawers tracking what"); assert(said("drawers tracking on"), "usage")
-- a client without the tracking functions: no list, no error
C_Minimap.GetNumTrackingTypes = nil
slash("drawers close"); slash("drawers open"); __tick(2)
assert(panel:GetHeight() < h0, "no list when the game has no tracking menu")
print("tracking menu: ok")
