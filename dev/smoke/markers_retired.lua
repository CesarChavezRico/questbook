-- The markers module is retired (2026-11-11). It had switched the client's quest areas off through the minimap's "Quest POIs"
-- tracking filter; its saved settings outlive it, so the overlay switches the filter back on once and removes them.
local tracking = { [1] = true, [2] = false, [3] = true }       -- 2 = "Quest POIs", left off by the retired module
local ready = false
C_Minimap.GetNumTrackingTypes = function() return ready and 3 or 0 end
C_Minimap.GetTrackingFilter = function(i) if i == 2 then return { filterID = 65536 } end return { filterID = 1 } end
C_Minimap.SetTracking = function(i, on) tracking[i] = on end
QuestBookDB = { mod = { markers = { areas = "hidden", areasBackup = true, size = 14, which = "all" } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
assert(QB.modules.markers == nil, "there is no markers module")
assert(tracking[2] == false and QuestBookDB.mod.markers ~= nil, "the tracking list is not there yet at login: nothing lost, nothing done")
ready = true
__fire("PLAYER_ENTERING_WORLD")
assert(tracking[2] == true, "the quest areas are switched back on")
assert(QuestBookDB.mod.markers == nil, "and the retired module's settings are gone")
tracking[2] = false
__fire("PLAYER_ENTERING_WORLD"); __fire("MINIMAP_UPDATE_TRACKING")
assert(tracking[2] == false, "it happens once: if the player switches them off later, that is respected")
SlashCmdList.QUESTBOOK("markers"); __take()          -- the old command is gone: it must not error
print("markers retired: ok")
