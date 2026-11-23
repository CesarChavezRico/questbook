-- v0.39.0 (4BI-38): the reader's queue under the reader bar: the game's own count, and the bridge's real list.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local L, G = QB.modules.playlist, QB.modules.guide
assert(L and L.active and G and G.active, "playlist and guide modules on")
local tts, bridgeList, checks = {}, nil, 0
local clock = 1700000000
time = function() return clock end
WoWAI = { SendTts = function(action, slot, ref, text, meta) tts[#tts + 1] = { action = action, ref = ref, text = text }; return true, #tts end,
  IsConnected = function() return true end, Connect = function() end,
  Playlist = function() if bridgeList then local p = bridgeList; p.age = clock - p.at; return p end end,
  CheckPush = function() checks = checks + 1; return true, 0 end }
local bar = QuestBookReaderBar
local function titles() local t = {} for _, it in ipairs(L:Items()) do t[#t + 1] = it.kind .. ":" .. it.title end return table.concat(t, " | ") end

-- nothing yet: the link says Queue, the panel is closed
assert(bar.queue and bar.queue:GetText() == "Queue" and not bar.queue.warn, "an empty queue")
assert(not (QuestBookPlaylist and QuestBookPlaylist:IsShown()), "closed by default")

-- a guide step and a quest are asked for: two lines, the first one playing
RXPGuides = {}
RXP = { settings = { profile = {} }, currentGuide = { group = "G", name = "N", steps = {
  { index = 1, active = true, elements = { { text = "Kill eight spiders for the venom, then gather the sacs from each of them and bring every one back to the camp by the road before nightfall, taking care on the way" }, { tag = "complete", questId = 100, text = "do it" } } } } } }
__npc = { name = "Zenn Foulhoof", sex = 2, ctype = "Humanoid", guid = "Creature-0-4379-1-30-3498-000012345A", quest = 100 }
__runTimers()
assert(L:Count() == 2 and titles():find("^Guide:Kill eight spiders") and titles():find("Quest:Wolves", 1, true), "the step and its quest: " .. titles())
assert(bar.queue:GetText() == "Queue 2" and bar.queue.warn, "the link counts them: " .. tostring(bar.queue:GetText()))
assert(select(1, L:Source()) == "estimated")
-- the link opens the panel: one line each, the first marked, a footer
bar.queue:Click()
local P = QuestBookPlaylist
assert(P and P:IsShown() and QuestBookDB.mod.playlist.open, "the panel opens, and that is saved")
assert(P.lines[1].kind:GetText() == "Guide" and P.lines[1].mark:IsShown() and P.lines[2].kind:GetText() == "Quest" and not P.lines[2].mark:IsShown(), "the lines")
assert(not P.lines[3].title:IsShown(), "no third line")
assert(P.footR:GetText() == "estimated" and P.foot:GetText():find("in all", 1, true), "the footer: " .. tostring(P.foot:GetText()))
-- time goes by: the first reading ends by its estimate and the next one plays
local first = L:Items()[1].secs - L:Items()[1].elapsed
assert(first > 2, "the first reading has time left: " .. first)
L:Advance(first - 1); assert(L:Count() == 2, "not over yet")
L:Advance(2); assert(L:Count() == 1 and L:Items()[1].kind == "Quest" and L:Items()[1].elapsed == 1, "the next one is playing, a second in")
-- pause holds it; play starts that reading again; skip drops it
SlashCmdList.QUESTBOOK("guide pause"); __take()
L:Advance(100); assert(L:Count() == 1 and L:IsPaused(), "paused: nothing moves")
assert(P.foot:GetText():find("paused", 1, true))
SlashCmdList.QUESTBOOK("guide play"); __take()
assert(not L:IsPaused() and L:Items()[1].elapsed == 0, "resumed from its start")
SlashCmdList.QUESTBOOK("guide skip"); __take()
assert(L:Count() == 0 and bar.queue:GetText() == "Queue" and P.foot:GetText() == "Nothing waiting.", "skip drops it")

-- a hand-in and a place are listed too
QB.modules.questlog:QueueWords("t100", "Well done indeed.", { name = "Kyra", sex = 3, type = "Humanoid" }, "Wolves")
assert(titles() == "Hand-in:Wolves", "the hand-in: " .. titles())
C_Map.GetBestMapForUnit = function() return 1438 end
GetSubZoneText = function() return "Aldrassil" end
__fire("ZONE_CHANGED"); bar.lore:Click(); __take()
assert(titles() == "Hand-in:Wolves | Lore:Aldrassil", "and the place: " .. titles())

-- a Story click: one line now; a few seconds later the bridge's list is asked for (one slot) and replaces the guess
RXP.currentGuide.steps[1].elements = { { tag = "complete", questId = 928, text = "x" } }
bar.story:Click(); __take()
assert(titles():find("Story:earlier chapters of", 1, true) and checks == 0, "the story as one line, no slot yet: " .. titles())
bridgeList = { at = clock - 3, paused = false, more = 2, items = {
  { kind = "Hand-in", title = "Wolves", ref = "t100", secs = 6, elapsed = 2 },
  { kind = "Lore", title = "Aldrassil", ref = "p1438:aldrassil", secs = 20 },
  { kind = "Story", title = "Webwood Venom \194\183 accept", ref = "q916", secs = 35 },
  { kind = "Story", title = "Webwood Venom \194\183 hand-in", ref = "t916", secs = 16 } } }
__runTimers()
assert(checks == 1, "one slot spent for the story: " .. checks)
assert(titles() == "Hand-in:Wolves | Lore:Aldrassil | Story:Webwood Venom \194\183 accept | Story:Webwood Venom \194\183 hand-in", "the bridge's list, with the chapters: " .. titles())
assert(L:Items()[1].elapsed >= 5 and L:Items()[1].elapsed < 6, "the one playing is as far in as the bridge said, plus the list's age: " .. L:Items()[1].elapsed)
assert(select(1, L:Source()) == "bridge" and P.footR:GetText():find("from the bridge", 1, true), "the footer says where it came from: " .. tostring(P.footR:GetText()))
assert(P.foot:GetText():find("+ 2 more", 1, true), "and what is not listed: " .. tostring(P.foot:GetText()))
assert(bar.queue:GetText() == "Queue 4")
-- the same list again is not taken twice; a newer one is (a slot read for any reason)
assert(not L:Take(), "nothing newer")
-- something the game asked for AFTER the bridge wrote its list stays behind it
clock = clock + 10
L:Add("Guide", "Go north", 140, "g9")
bridgeList = { at = clock - 4, paused = true, more = 0, items = { { kind = "Story", title = "Webwood Venom \194\183 hand-in", ref = "t916", secs = 16, elapsed = 1 } } }
assert(L:Take() and titles() == "Story:Webwood Venom \194\183 hand-in | Guide:Go north", "kept behind: " .. titles())
assert(L:IsPaused() and L:Items()[1].elapsed == 1, "a paused list does not move with its age")
-- Sync on the panel: one more slot; nothing newer is said
__take(); P.sync:Click()
assert(checks == 2 and table.concat(__take(), "\n"):find("nothing newer", 1, true), "Sync asks again")
-- an old relay addon: said, nothing breaks
local old = WoWAI.Playlist; WoWAI.Playlist = nil
SlashCmdList.QUESTBOOK("queue sync"); assert(table.concat(__take(), "\n"):find("older than the queue display", 1, true))
WoWAI.Playlist = old
-- voice off clears it; close hides the panel
SlashCmdList.QUESTBOOK("guide read off"); __take()
assert(L:Count() == 0, "stop clears the list")
SlashCmdList.QUESTBOOK("queue close"); __take(); assert(not P:IsShown() and not QuestBookDB.mod.playlist.open)
SlashCmdList.QUESTBOOK("queue"); assert(table.concat(__take(), "\n"):find("0 readings", 1, true))
print("playlist ok")
