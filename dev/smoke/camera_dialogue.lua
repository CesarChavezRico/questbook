-- A quest dialogue (Dialogue UI) and the camera shift must not fight over test_cameraOverShoulder.
-- Stubbed API: this checks that we stop writing while a dialogue is open and take over again after it.
-- (Which events this client sends, and whether that ends the wobble, only the game can say.)
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local C = QB.modules.camera
assert(C and C.active, "camera module on")
local writes = 0
local rawSet = C_CVar.SetCVar
C_CVar.SetCVar = function(n, v) if n == "test_cameraOverShoulder" then writes = writes + 1 end return rawSet(n, v) end

slash("overlay local"); __tick(40, 0.05)
assert(C.engaged and not C.easing, "engaged and settled")
local shifted = tonumber(__cvar("test_cameraOverShoulder"))
assert(shifted and shifted ~= 0, "shifted: " .. tostring(shifted))

-- a dialogue opens; the other addon eases the CVar and zooms the camera
__fire("GOSSIP_SHOW")
assert(C.yielding, "yields to the dialogue")
writes = 0
local other = shifted
for i = 1, 30 do other = other + 0.05; rawSet("test_cameraOverShoulder", other); CameraZoomIn(0.05); __tick(1, 0.03) end
assert(writes == 0, "we write nothing while it is open, got " .. writes .. " writes")
assert(math.abs(tonumber(__cvar("test_cameraOverShoulder")) - other) < 1e-3, "the other addon's value stands")

-- it closes: we wait, then ease back to our shift
__fire("GOSSIP_CLOSED")
assert(C.yielding, "still waiting for the dialogue's own camera to settle")
-- (the stub runs every timer at the next tick, so the 0.8 s wait itself is not modelled here)
__runTimers()
assert(not C.yielding, "took over again")
__tick(30, 0.05)
local target = C:Target()
assert(math.abs(tonumber(__cvar("test_cameraOverShoulder")) - target) < 0.01, "back on our shift " .. target .. ", got " .. tostring(__cvar("test_cameraOverShoulder")))
assert(writes > 0, "and writing again")

-- a dialogue that never says it closed does not hold the camera forever
__fire("QUEST_DETAIL"); assert(C.yielding)
__tick(2500, 0.05)
assert(not C.yielding, "released after the safety timeout")

-- the overlay closing during a dialogue: it is put right after the dialogue
__tick(40, 0.05)
__fire("QUEST_GREETING")
slash("overlay off"); __tick(10, 0.05)
assert(C.engaged, "not released while the dialogue holds the CVar")
__fire("QUEST_FINISHED"); __runTimers(); __tick(40, 0.05)
assert(not C.engaged, "released after it")
assert(math.abs(tonumber(__cvar("test_cameraOverShoulder")) - C:Original()) < 0.01 or C.db.backup == nil, "original shoulder value back")
local line = nil
slash("camera"); for _, l in ipairs(__take()) do line = l end
assert(line and line:find("engaged=false"), "status: " .. tostring(line))
