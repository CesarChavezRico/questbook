-- The quest reader's zoom next to a dialogue addon's zoom (4BI-36). Cesar, 2026-11-15: "the bug of the zoom is still there
-- but with the left camera, maybe an unintended interaction with the dialogUI zoom?". The reader steps out from "the player's own
-- zoom"; taken at the instant the reader opens, that was whatever a dialogue addon had zoomed to. Stand-in camera and a stand-in
-- dialogue addon that zooms in while a quest dialogue is open and back out when it closes. Our logic, not the feel.
local zoom = 10
function GetCameraZoom() return zoom end
function CameraZoomOut(d) zoom = math.min(30, zoom + d) end
function CameraZoomIn(d) zoom = math.max(0, zoom - d) end
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local C = QB.modules.camera
local function near(a, b) return math.abs(a - b) < 0.05 end
__tick(40, 0.05)                                   -- the camera sits at the player's own distance for a while

-- 1. the reader alone: out by its step, and back
QB:Fire("reader_state", true); __tick(40, 0.05)
assert(near(zoom, 13), "the reader steps out from the player's zoom: " .. zoom)
QB:Fire("reader_state", false); __tick(40, 0.05)
assert(near(zoom, 10), "and back: " .. zoom)

-- 2. a dialogue zooms in, and the reader opens WHILE it is open (accepting a quest with the reader up)
__fire("QUEST_DETAIL"); zoom = 4                   -- the dialogue addon's close-up
__tick(10, 0.05)
QB:Fire("reader_state", true); __tick(10, 0.05)
assert(near(zoom, 4), "nothing is moved while the dialogue owns the camera: " .. zoom)
__fire("QUEST_FINISHED"); zoom = 10                -- the dialogue addon puts its own zoom back
__tick(60, 0.05)
assert(near(zoom, 13), "the reader's distance is counted from the player's zoom, not from the close-up: " .. zoom)
QB:Fire("reader_state", false); __tick(40, 0.05)
assert(near(zoom, 10), "closing the reader returns to the player's zoom, not to the close-up: " .. zoom)

-- 3. the reader opens right AFTER the dialogue closes, while its zoom is still on the way back
__fire("QUEST_DETAIL"); zoom = 4; __tick(10, 0.05)
__fire("QUEST_FINISHED"); zoom = 6                 -- part of the way back
QB:Fire("reader_state", true)
__tick(4, 0.05); zoom = 10                         -- the dialogue addon arrives
__tick(60, 0.05)
assert(near(zoom, 13), "still counted from the player's zoom: " .. zoom)
QB:Fire("reader_state", false); __tick(40, 0.05)
assert(near(zoom, 10), "and back to it: " .. zoom)

-- 4. the player's own wheel is respected: a new resting distance becomes the one to return to
zoom = 18; __tick(40, 0.05)
QB:Fire("reader_state", true); __tick(40, 0.05); assert(near(zoom, 21), "from the new distance: " .. zoom)
QB:Fire("reader_state", false); __tick(40, 0.05); assert(near(zoom, 18), "and back to the new distance: " .. zoom)
print("camera reader dialogue: ok")
