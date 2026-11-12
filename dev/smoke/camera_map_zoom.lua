-- The camera in the map loop (4BI-36, Cesar 2026-11-11): "keeping the char centered but zoom progressivly out ... with the
-- overland being the farthest out the camera will allow". And 2026-11-12: "Character zoom. It needs to be a specific value":
-- the maps go to ABSOLUTE distances. Stand-in camera: zoom clamps at 30. Our logic, not the feel.
local MAX = 30
local zoom = 10
function GetCameraZoom() return zoom end
function CameraZoomOut(d) zoom = math.min(MAX, zoom + d) end
function CameraZoomIn(d) zoom = math.max(0, zoom - d) end
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local C, O = QB.modules.camera, QB.modules.overlay
local function shoulder() return tonumber(__cvar("test_cameraOverShoulder")) or 0 end
local s0 = shoulder()

-- first press: the character stays centred, the camera pulls back a step
O:Cycle(); __tick(40, 0.05)
assert(O.state == "local", "local map")
assert(math.abs(shoulder() - s0) < 0.001, "no sideways shift for the local map: " .. shoulder())
assert(math.abs(zoom - 15) < 0.01, "the local map's own distance, 15: " .. zoom)
-- second press: as far as the camera goes, still centred
O:Cycle(); __tick(40, 0.05)
assert(O.state == "zone", "overland map")
assert(math.abs(zoom - MAX) < 0.01, "as far out as the camera allows: " .. zoom)
assert(math.abs(shoulder() - s0) < 0.001, "still centred")
-- back to rest: the player's own zoom
slash("overlay off"); __tick(40, 0.05)
assert(math.abs(zoom - 10) < 0.01, "back to the player's own zoom: " .. zoom)
assert(not C.engaged, "and the camera is let go")
-- straight to the overland map and back
slash("overlay zone"); __tick(40, 0.05); assert(math.abs(zoom - MAX) < 0.01)
slash("overlay off"); __tick(40, 0.05); assert(math.abs(zoom - 10) < 0.01, "restored after going straight to the overland map")
-- the master switch off: the maps still zoom (it only governs the sideways shift)
slash("camera off"); O:Cycle(); __tick(40, 0.05)
assert(math.abs(zoom - 15) < 0.01 and math.abs(shoulder() - s0) < 0.001, "camera off: zoom yes, shift no")
slash("overlay off"); __tick(40, 0.05); slash("camera on")
-- settings
slash("camera map zoom 4 12"); O:Cycle(); __tick(40, 0.05)
assert(math.abs(zoom - 4) < 0.01, "map zoom sets the local distance: " .. zoom)
O:Cycle(); __tick(40, 0.05); assert(math.abs(zoom - 12) < 0.01, "and the overland distance: " .. zoom)
slash("overlay off"); __tick(40, 0.05)
slash("camera map shift on"); O:Cycle(); __tick(40, 0.05)
assert(math.abs(shoulder() - s0) > 0.001, "map shift on brings the sideways shift back")
slash("overlay off"); __tick(40, 0.05)
assert(math.abs(shoulder() - s0) < 0.001 and math.abs(zoom - 10) < 0.01, "and everything is restored")
slash("camera map shift off")

-- a specific value whatever the camera was doing: the same distance from a different starting zoom
zoom = 3; O:Cycle(); __tick(40, 0.05)
assert(math.abs(zoom - 4) < 0.01, "the same distance from another starting zoom: " .. zoom)
slash("overlay off"); __tick(40, 0.05); assert(math.abs(zoom - 3) < 0.01, "rest off: back to the zoom it had: " .. zoom)
-- something else moves the zoom while ours is under way (a dialogue addon, the map): we look again and correct
slash("camera map zoom 15 50")
O:Cycle(); zoom = 6; __tick(60, 0.05)
assert(math.abs(zoom - 15) < 0.01, "knocked off course, corrected to the distance: " .. zoom)
slash("overlay off"); __tick(60, 0.05)
-- ... but afterwards the wheel is the player's: no correction once it has arrived
O:Cycle(); __tick(60, 0.05); zoom = 20; __tick(60, 0.05)
assert(math.abs(zoom - 20) < 0.01, "the wheel still works while the map is open: " .. zoom)
slash("overlay off"); __tick(60, 0.05)
-- a rest distance: closing the maps goes there, not to wherever the camera was
slash("camera map rest 9"); zoom = 2; O:Cycle(); __tick(40, 0.05); slash("overlay off"); __tick(60, 0.05)
assert(math.abs(zoom - 9) < 0.01, "back to the rest distance: " .. zoom)
zoom = 11; slash("camera map rest here"); assert(C.db.mapZoomRest == 11, "rest here takes the current zoom")
slash("camera map rest off"); assert(C.db.mapZoomRest == 0)
-- a dialogue owns the camera: nothing is corrected until it closes, then we go where we were going
zoom = 10; O:Cycle(); __tick(40, 0.05); __fire("GOSSIP_SHOW"); zoom = 2; __tick(60, 0.05)
assert(math.abs(zoom - 2) < 0.01, "hands off while a dialogue is open: " .. zoom)
__fire("GOSSIP_CLOSED"); __tick(80, 0.05)
assert(math.abs(zoom - 15) < 0.01, "after the dialogue: back at the map's distance: " .. zoom)
slash("overlay off"); __tick(60, 0.05)
slash("camera map what"); __take()
print("camera map zoom: ok")
