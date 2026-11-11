-- The camera in the map loop (4BI-36, Cesar 2026-11-11): "keeping the char centered but zoom progressivly out ... with the
-- overland being the farthest out the camera will allow". Stand-in camera: zoom clamps at 30. Our logic, not the feel.
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
assert(math.abs(zoom - 18) < 0.01, "pulled back by 8: " .. zoom)
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
assert(math.abs(zoom - 18) < 0.01 and math.abs(shoulder() - s0) < 0.001, "camera off: zoom yes, shift no")
slash("overlay off"); __tick(40, 0.05); slash("camera on")
-- settings
slash("camera map zoom 4 12"); O:Cycle(); __tick(40, 0.05)
assert(math.abs(zoom - 14) < 0.01, "map zoom sets the local step: " .. zoom)
O:Cycle(); __tick(40, 0.05); assert(math.abs(zoom - 22) < 0.01, "and the overland step: " .. zoom)
slash("overlay off"); __tick(40, 0.05)
slash("camera map shift on"); O:Cycle(); __tick(40, 0.05)
assert(math.abs(shoulder() - s0) > 0.001, "map shift on brings the sideways shift back")
slash("overlay off"); __tick(40, 0.05)
assert(math.abs(shoulder() - s0) < 0.001 and math.abs(zoom - 10) < 0.01, "and everything is restored")
slash("camera map what"); __take()
print("camera map zoom: ok")
