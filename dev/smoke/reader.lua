-- The quest reader: one page set where the big map sits, trading places with the map, same camera shift and zoom;
-- the duties, the arrows, walk-and-listen, the tracker's clicks. Stubbed API: layout arithmetic, order of events
-- and state, not how it looks (that is for the game).
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function click(b, btn) b.__scripts.OnClick(b, btn or "LeftButton") end
local Q, O, C = QB.modules.questlog, QB.modules.overlay, QB.modules.camera
local Style = QB.Style
local u = Style.PixelUnit(UIParent)
local H, W = UIParent:GetHeight(), UIParent:GetWidth()
local seen = {}
QB:On("reader_state", function(open) seen[#seen + 1] = open and "open" or "closed" end, "test")

-- opens with /qb, on the active (else first) quest
slash("")
local R = QuestBookReader
assert(R and R:IsShown(), "the reader is up")
assert(R.title:GetText() == "Wolves", "first quest in the log, got " .. tostring(R.title:GetText()))
assert(seen[#seen] == "open", "announced")
assert(R.paper and #R.paper.parts == 9, "on the torn page")
local tUIPS = 0
for _, n in ipairs(UISpecialFrames) do if n == "QuestBookReader" then tUIPS = 1 end end
assert(tUIPS == 1, "Esc closes it (a UISpecialFrame)")

-- it sits where the big map sits: same centre, same height
local ow, oh, ocx, ocy = O:Geometry()
local p = { R:GetPoint(1) }
assert(p[1] == "CENTER" and p[2] == UIParent, "centred on the screen")
assert(math.abs(p[4] - ocx) <= u and math.abs(p[5] - ocy) <= u, ("same centre as the map: %.2f,%.2f vs %.2f,%.2f"):format(p[4], p[5], ocx, ocy))
assert(math.abs(R:GetHeight() - oh) <= u, "same height as the map: " .. R:GetHeight() .. " vs " .. oh)
local pxw = R:GetWidth() / u
assert(math.abs(pxw - math.floor(pxw + 0.5)) < 1e-6, "a whole number of pixels wide: " .. pxw)

-- the same camera shift and zoom as the map
__tick(40, 0.05)
assert(C.engaged and not C.releasing, "camera shifted for the reader")
local base = C.oldZoom
assert(base and math.abs(GetCameraZoom() - (base + 3)) < 0.01, "and zoomed out by 3: " .. tostring(GetCameraZoom()) .. " from " .. tostring(base))

-- objectives as rows, the duties
assert(R.objs and #R.objs == 1 and R.objs[1].text == "Kill 5 things", "one objective row")
click(R.primary); assert(C_SuperTrack.GetSuperTrackedQuestID() == 100, "make active")
assert(R.primary:GetText() ~= nil)
click(R.primary); assert(C_SuperTrack.GetSuperTrackedQuestID() == 0, "and clear it again")
local watched = C_QuestLog.GetQuestWatchType(100) ~= nil
click(R.trackBtn); assert((C_QuestLog.GetQuestWatchType(100) ~= nil) ~= watched, "track toggles")
click(R.abandon); assert(__popup and __popup[1] == "ABANDON_QUEST", "abandon asks Blizzard's popup")
click(R.next); assert(R.title:GetText() == "Kobolds", "next, got " .. tostring(R.title:GetText()))
click(R.next); click(R.next)
assert(R.title:GetText() == "Wolves", "the arrows wrap around, got " .. tostring(R.title:GetText()))
click(R.prev); assert(R.title:GetText() ~= "Wolves", "previous")
assert(R.meta:GetText():find("Level"), "a meta line with the level: " .. tostring(R.meta:GetText()))

-- a text size command rescales the page text
local b0 = R.body.__fsize
slash("size 30"); assert(Q.db.body == 30 and R.body.__fsize > b0, "size changes the body text")
slash("size 22")

-- the map key while the reader is open: the map comes up, the reader goes away, the shift stays
O:Cycle(); __tick(20, 0.05)
assert(O.state == "local" and not R:IsShown(), "the map replaced the reader")
assert(seen[#seen] == "closed", "announced as gone")
assert(C.engaged and not C.releasing, "the camera never let go")
-- a quest clicked while the map is open: the reader replaces the map, the shift stays
QB:Call("questlog", "Open", 101); __tick(5, 0.05)
assert(R:IsShown() and O.state == "off", "the reader replaced the map")
assert(R.title:GetText() == "Kobolds", "on the clicked quest, got " .. tostring(R.title:GetText()))
assert(C.engaged and not C.releasing, "the camera stayed shifted through the swap")
assert(seen[#seen] == "open")
-- ... and the same through zone mode
R:Hide(); __tick(40, 0.05)
O:Cycle(); O:Cycle(); __tick(20, 0.05)
assert(O.state == "zone", "map mode")
QB:Call("questlog", "Open", 100); __tick(5, 0.05)
assert(R:IsShown() and O.state == "off", "the reader replaced the zone map too")
assert(not O.cornerPanel:IsShown(), "the small minimap is out of the way while the reader is open (it hides it by default)")

-- the action bars go with the reader as they go with the map (and stay hidden through a swap)
local bar = MainActionBar
R:Hide(); __tick(60, 0.05)
assert(bar:GetAlpha() == 1, "bars visible with nothing open")
QB:Call("questlog", "Open", 100); __tick(3, 0.05)
assert(bar:GetAlpha() == 0, "bars hidden while the reader is open")
O:Cycle(); __tick(3, 0.05)
assert(O.state == "local" and bar:GetAlpha() == 0, "hidden through the swap to the map")
QB:Call("questlog", "Open", 100); __tick(3, 0.05)
assert(R:IsShown() and bar:GetAlpha() == 0, "and through the swap back")
R:Hide(); __tick(3, 0.05)
assert(bar:GetAlpha() == 1, "visible again when the reader closes")
QB:Call("questlog", "Open", 100); O:Cycle(); __tick(3, 0.05)
assert(not R:IsShown() and bar:GetAlpha() == 0, "the map keeps them hidden when it takes over")
O:SetState("off"); __tick(3, 0.05)
assert(bar:GetAlpha() == 1, "and gives them back")
QB:Call("questlog", "Open", 100)

-- what else it hides: the small minimap (and so the markers), the player and target frames; all back when it closes
R:Hide(); __tick(60, 0.05)
assert(O.cornerPanel:IsShown() and PlayerFrame:GetAlpha() ~= 0 and TargetFrame:GetAlpha() ~= 0, "everything visible with nothing open")
assert(QuestBookMarkers and QuestBookMarkers:IsShown(), "the markers are on the small minimap")
QB:Call("questlog", "Open", 100); __tick(3, 0.05)
assert(not O.cornerPanel:IsShown(), "the small minimap is hidden")
assert(not QuestBookMarkers:IsShown(), "and the markers with it")
assert(PlayerFrame:GetAlpha() == 0 and TargetFrame:GetAlpha() == 0, "the player and target frames are hidden")
R:Hide(); __tick(3, 0.05)
assert(O.cornerPanel:IsShown() and QuestBookMarkers:IsShown(), "minimap and markers are back")
assert(PlayerFrame:GetAlpha() ~= 0 and TargetFrame:GetAlpha() ~= 0, "frames are back")
slash("reader hide minimap off"); slash("reader hide frames off")
QB:Call("questlog", "Open", 100); __tick(3, 0.05)
assert(O.cornerPanel:IsShown() and PlayerFrame:GetAlpha() ~= 0, "both left alone when the settings say so")
slash("reader hide minimap on")                    -- takes effect at once, with the page open
assert(not O.cornerPanel:IsShown(), "the setting applies live")
slash("reader hide frames on"); assert(PlayerFrame:GetAlpha() == 0)
R:Hide(); __tick(3, 0.05)

-- no scroll bar on the page; its own height
QB:Call("questlog", "Open", 100); __tick(3, 0.05)
assert(not R.thumb:IsShown() and not R.track:IsShown(), "no scroll bar")
slash("reader scrollbar on"); slash("reader scrollbar off")      -- (the setting exists; nothing overflows in the stub)
local mapH = R:GetHeight()
slash("reader height 0.8")
local want = Style.Snap(UIParent:GetHeight() * 0.8, R)
assert(math.abs(R:GetHeight() - want) <= u, "its own height: " .. R:GetHeight() .. " vs " .. want)
local p2 = { R:GetPoint(1) }
assert(math.abs(p2[4] - ocx) <= u and math.abs(p2[5] - ocy) <= u, "same centre")
slash("reader height auto")
assert(math.abs(R:GetHeight() - mapH) <= u, "auto = the map's height again")
R:Hide(); __tick(60, 0.05)

-- the reader's own zoom (negative zooms in), and the map's again after a swap
QB:Call("questlog", "Open", 100); __tick(40, 0.05)
local b2 = C.oldZoom
assert(math.abs(GetCameraZoom() - (b2 + 3)) < 0.01, "reader zoom 3 by default")
slash("camera readerzoom -2"); __tick(5, 0.05)
assert(math.abs(GetCameraZoom() - (b2 - 2)) < 0.01, "readerzoom -2 zooms in: " .. GetCameraZoom() .. " from " .. b2)
O:Cycle(); __tick(40, 0.05)
assert(O.state == "local" and math.abs(GetCameraZoom() - (b2 + 3)) < 0.01, "the map's own zoom after the swap: " .. GetCameraZoom())
QB:Call("questlog", "Open", 100); __tick(40, 0.05)
assert(math.abs(GetCameraZoom() - (b2 - 2)) < 0.01, "and the reader's again")
slash("camera readerzoom 3")
R:Hide(); __tick(60, 0.05)

-- closing releases the camera
R:Hide(); __tick(60, 0.05)
assert(not C.engaged and seen[#seen] == "closed", "closed: the camera is released")
assert(math.abs(GetCameraZoom() - base) < 0.01, "zoom back, got " .. GetCameraZoom() .. " want " .. base)

-- the tracker: left click = active, right click = reader (covered in tracker.lua); the Log link toggles it
QB:Call("questlog", "Toggle"); assert(R:IsShown()); QB:Call("questlog", "Toggle"); assert(not R:IsShown(), "Toggle")

-- combat: not opened, and closed when combat starts
__combat = true
QB:Call("questlog", "Open"); assert(not R:IsShown(), "not in combat")
__combat = false
QB:Call("questlog", "Open"); assert(R:IsShown())
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __combat = false
assert(not R:IsShown(), "combat start closes it")
__fire("PLAYER_REGEN_ENABLED"); __runTimers(); __tick(60, 0.05)

-- walk-and-listen: the first step with it open reads the quest once AND puts the page away; the reading goes on
local spoken, stopped = 0, 0
C_VoiceChat.SpeakText = function() spoken = spoken + 1 end
C_VoiceChat.StopSpeakingText = function() stopped = stopped + 1 end
QB:Call("questlog", "Open", 100)
__fire("PLAYER_STARTED_MOVING"); __fire("PLAYER_STARTED_MOVING")
assert(spoken == 1, "read once, got " .. spoken)
assert(not R:IsShown(), "the page is put away when you walk off with voice on")
assert(stopped == 0, "and the reading was not stopped by it")
-- the tracker's voice link: "Stop" while it reads, the switch otherwise
local P = QuestBookTracker
assert(P.voice and P.voice:GetText() == "Voice on", "voice link says Voice on: " .. tostring(P.voice and P.voice:GetText()))
__fire("VOICE_CHAT_TTS_PLAYBACK_STARTED")
assert(P.voice:GetText() == "Stop", "while reading it says Stop, got " .. tostring(P.voice:GetText()))
click(P.voice); assert(stopped == 1 and P.voice:GetText() == "Voice on", "Stop stops the reading with the page away")
click(P.voice); assert(Q.db and QB.db.voice == false and P.voice:GetText() == "Voice off", "the link switches walk-and-listen off")
-- with voice off the page stays when you walk
QB:Call("questlog", "Open", 100)
__fire("PLAYER_STARTED_MOVING")
assert(R:IsShown() and spoken == 1, "voice off: the page stays, nothing is read")
R:Hide()
click(P.voice); assert(QB.db.voice == true and P.voice:GetText() == "Voice on", "and back on")
-- Talk reads on demand
QB:Call("questlog", "Open", 100)
click(R.talk); assert(spoken == 2, "Talk reads on demand")

-- the log changes under the page: it follows
__fire("QUEST_LOG_UPDATE"); __runTimers()
assert(R:IsShown() and R.title:GetText() == "Wolves", "refreshed in place")

-- an empty log says so
local realN = C_QuestLog.GetNumQuestLogEntries
C_QuestLog.GetNumQuestLogEntries = function() return 0, 0 end
__fire("QUEST_LOG_UPDATE"); __runTimers()
assert(R.title:GetText() == "No quests in your log.", "empty log: " .. tostring(R.title:GetText()))
C_QuestLog.GetNumQuestLogEntries = realN
__fire("QUEST_LOG_UPDATE"); __runTimers()

-- disabling the module closes it and gives Blizzard's log back
QB:SetEnabled("questlog", false); assert(not R:IsShown(), "disable closes it")
QB:SetEnabled("questlog", true)
print("reader ok")
