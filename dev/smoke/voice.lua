-- The relay voice (4BI-38): the reader asks the WoW AI bridge to speak, by voice slot (chosen by the quest giver);
-- Stop, prefetch at accept, the fallback to the game's voice. WoWAI is a stub here. Stubbed API.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function click(b) b.__scripts.OnClick(b) end
local Q, G = QB.modules.questlog, QB.modules.giver

-- a stand-in for the relay addon
local calls, connected = {}, true
WoWAI = {
  IsConnected = function() return connected end,
  SendTts = function(action, slot, ref, text, meta) calls[#calls + 1] = { action = action, slot = slot, ref = ref, text = text, meta = meta }; return true, #calls end,
}
local spoken, stopped = 0, 0
C_VoiceChat.SpeakText = function() spoken = spoken + 1 end
C_VoiceChat.StopSpeakingText = function() stopped = stopped + 1 end

-- the default engine is the game's own voice: the relay is never touched
QB:Call("questlog", "Open", 100)
local R = QuestBookReader
click(R.talk)
assert(spoken == 1 and #calls == 0, "engine game: the game speaks, nothing sent to the relay")
R:Hide(); __runTimers()
local gameSpoke = spoken

-- the relay engine, with the quest giver chosen by gender and type
slash("voice engine relay")
G.db.quests[100] = { name = "Zenn Foulhoof", sex = 2, type = "Humanoid", npc = 3498, kind = "Creature" }
G.db.quests[101] = { name = "Sentinel Kyra Starsong", sex = 3, type = "Humanoid", npc = 61000, kind = "Creature" }
G.db.quests[102] = { name = "A Wolf", sex = 1, type = "Beast", npc = 99, kind = "Creature" }
assert(Q:VoiceSlot(100) == "male" and Q:VoiceSlot(101) == "female" and Q:VoiceSlot(102) == "creature", "slots by giver")
assert(Q:VoiceSlot(103) == "narrator", "no giver: the narrator")
G.db.quests[104] = { name = "A Dead Man", sex = 2, type = "Undead", npc = 5 }
assert(Q:VoiceSlot(104) == "male", "an undead person is still a man (only beasts, demons, elementals ... are creatures)")

QB:Call("questlog", "Open", 100)
local before = #calls
click(R.talk)
assert(#calls == before + 1, "Talk sent one request")
local c = calls[#calls]
assert(c.action == "play" and c.slot == "male" and c.ref == "q100", "play, the giver's slot, the quest: " .. c.action .. " " .. c.slot .. " " .. c.ref)
assert(c.text:find("^Wolves%. ") and c.text:find("Go and slay the beasts", 1, true), "the title, then the description: " .. c.text)
assert(not c.text:find("ready to turn in", 1, true), "no changing prefix: the cache must hold")
assert(spoken == gameSpoke, "the game did not speak as well")
assert(R.talk:GetText() == "Stop", "the page shows Stop while it is read")
-- the giver goes with the request, so the bridge can cast a voice for him; no giver, no meta
assert(c.meta and c.meta.giver == "Zenn Foulhoof" and c.meta.npc == 3498 and c.meta.sex == 2 and c.meta.type == "Humanoid" and c.meta.title == "Wolves",
  "the giver and the quest title travel with the request: " .. tostring(c.meta and c.meta.giver))
-- Stop sends a stop and does not wait for the estimate
click(R.talk)
assert(calls[#calls].action == "stop", "Stop sends a stop")
assert(R.talk:GetText() == "Talk")
-- the estimate ends the reading by itself (about 14 characters a second, at least 3 seconds)
click(R.talk); assert(R.talk:GetText() == "Stop")
__runTimers()
assert(R.talk:GetText() == "Talk", "when the estimated time is up it says Talk again")
-- an older reading's timer does nothing to a newer one
click(R.talk); click(R.next)                         -- next reads the next quest at once
assert(calls[#calls].action == "play" and calls[#calls].ref ~= "q100", "the arrows read the quest they land on: " .. calls[#calls].ref)
R:Hide()

-- the tracker's Play button: PlayQuest reads any quest by id with its giver's slot, with the reader shut; again = Stop
local n0 = #calls
Q:PlayQuest(101)
assert(#calls == n0 + 1 and calls[#calls].action == "play" and calls[#calls].slot == "female" and calls[#calls].ref == "q101", "PlayQuest sent the quest's own slot")
assert(Q:SpeakingQuestID() == 101, "and knows which quest is being read")
Q:PlayQuest(100)
assert(calls[#calls].ref == "q100" and Q:SpeakingQuestID() == 100, "another quest replaces it")
Q:PlayQuest(100)
assert(calls[#calls].action == "stop" and Q:SpeakingQuestID() == nil, "the same quest again is Stop")
local n1 = #calls; Q:PlayQuest(99999); assert(#calls == n1, "an unknown quest does nothing")

-- walk-and-listen puts the page away when the reading started
QB:Call("questlog", "Open", 101)
local n = #calls
__fire("PLAYER_STARTED_MOVING")
assert(#calls == n + 1 and calls[#calls].slot == "female", "the first step reads it: " .. tostring(calls[#calls].slot))
assert(not R:IsShown(), "and the page goes away")
assert(calls[#calls].action == "play" and #calls == n + 1, "the reading was not stopped by the page closing")

-- the relay is not there: Talk uses the game's voice and says why
__runTimers()                                         -- (the walking reading's estimated time is over)
connected = false
QB:Call("questlog", "Open", 100)
local calls0, spoken0 = #calls, spoken
click(R.talk)
assert(#calls == calls0 and spoken == spoken0 + 1, "not connected: the game's voice speaks instead")
assert(table.concat(__take(), "\n"):find("not connected", 1, true), "and it says why")
R:Hide()
connected = true
local savedWoWAI = WoWAI; WoWAI = nil
QB:Call("questlog", "Open", 100)
local s1 = spoken
click(R.talk)
assert(spoken == s1 + 1, "no relay addon: the game's voice")
R:Hide()
WoWAI = savedWoWAI

-- THE RELAY HAS GONE QUIET (Cesar, 2026-11-05: "it goes idle and almost every time I want a quest read I get the default voice;
-- I need to go and reconnect the relay and wait a bit"): Talk asks the relay addon to reconnect, waits a few seconds, and only
-- then falls back to the game's voice.
slash("voice engine relay"); __take()
local clock = 0
local realGetTime = GetTime
GetTime = function() return clock end
local connects, answerAfter = 0, nil          -- answerAfter: seconds after the Connect when the bridge "answers"; nil = never
local connectAt
WoWAI.Connect = function() connects = connects + 1; connectAt = clock end
WoWAI.IsConnected = function() return connected or (answerAfter ~= nil and connectAt ~= nil and clock - connectAt >= answerAfter) end
WoWAI.BridgeState = function() return "stale", 0.9, 0.8, 0.2, "Bridge: last seen 7m 3s ago" end
local function scenario(answer)               -- a fresh quiet bridge: it answers `answer` seconds after a Connect (nil = never)
  connected = false; answerAfter = answer; connectAt = nil; calls = {}; connects = 0; clock = clock + 100
end
local function pass(secs)                     -- let `secs` seconds go by, a timer pass every half second
  for _ = 1, math.floor(secs / 0.5) do clock = clock + 0.5; __runTimers() end
end

-- 1. quiet, and it answers after 2 s: Talk waits, then the RELAY speaks; the game's voice never does
scenario(2)
QB:Call("questlog", "Open", 100)
local sp0 = spoken
click(R.talk)
assert(connects == 1, "Talk asked the relay addon to reconnect, once: " .. connects)
assert(#calls == 0 and spoken == sp0, "nothing is said yet")
assert(R.talk:GetText() == "Stop", "the page says Stop while it waits (and Stop cancels it)")
assert(table.concat(__take(), "\n"):find("reconnecting", 1, true), "and says what it is doing")
pass(3)
assert(#calls == 1 and calls[1].action == "play" and calls[1].slot == "male", "the bridge answered: the request went out with the giver's slot")
assert(spoken == sp0, "the game's voice did not speak")
click(R.talk); pass(1)                                       -- Stop
R:Hide(); __take()

-- 2. quiet, and it never answers: after 10 s the game's voice, with the reason (and how long the bridge has been quiet)
scenario(nil)
QB:Call("questlog", "Open", 100)
sp0 = spoken
click(R.talk)
pass(9)
assert(spoken == sp0 and #calls == 0, "still waiting at 9 s")
pass(2)
assert(spoken == sp0 + 1 and #calls == 0, "after 10 s the game's voice speaks")
local said2 = table.concat(__take(), "\n")
assert(said2:find("not connected", 1, true) and said2:find("last seen 7m 3s ago", 1, true), "and it says why: " .. said2)
-- a second Talk soon after: no new attempt, the game's voice at once
local function done() __fire("VOICE_CHAT_TTS_PLAYBACK_FINISHED") end      -- (the stub has no game speech: say the last reading ended)
done()
local c2 = connects
sp0 = spoken
click(R.talk)
assert(connects == c2 and spoken == sp0 + 1, "within 45 s of a failed try the game's voice speaks at once, without another reconnect")
-- 45 s later it tries again, and this time the bridge is back
done(); clock = clock + 50; answerAfter = 1; connectAt = nil
click(R.talk); pass(2)
assert(connects == c2 + 1 and #calls == 1, "after the gap it tries again, and this time the bridge is back")
click(R.talk); R:Hide(); __take(); done()

-- 3. Stop while it waits cancels the reading: nothing is sent, nothing is said
scenario(3)
QB:Call("questlog", "Open", 100)
sp0 = spoken
click(R.talk); assert(R.talk:GetText() == "Stop")
click(R.talk)
assert(R.talk:GetText() == "Talk", "Stop puts it back")
pass(12)
assert(#calls == 0 and spoken == sp0, "cancelled: nothing sent, nothing said")

-- 4. a newer reading replaces the waiting one: only the latest goes out
scenario(3); done()
click(R.talk)
click(R.next)                                                -- reads the next quest: the first wait is dropped
pass(5)
assert(#calls == 1 and calls[1].ref ~= "q100", "only the newest reading was sent: " .. tostring(calls[1] and calls[1].ref))
assert(connects == 1, "and one reconnect served both")
R:Hide(); __take()

-- 5. prefetch at accept asks quietly and sends once the bridge is back (and says nothing if it is not)
scenario(2)
slash("voice prefetch on"); __take()
__fire("QUEST_ACCEPTED", 2, 100); __runTimers()
assert(connects == 1, "prefetch asked for a reconnect")
pass(3)
assert(#calls == 1 and calls[1].action == "prefetch" and calls[1].ref == "q100", "and the prefetch went out once it answered")
assert(not table.concat(__take(), "\n"):find("reconnecting", 1, true), "quietly: no chat line for a background prefetch")
scenario(nil)
__fire("QUEST_ACCEPTED", 2, 100); __runTimers(); pass(12)
assert(#calls == 0 and table.concat(__take(), "\n") == "", "bridge really gone: no request, no message")

-- 6. /qb voice status says why, in one line
scenario(nil)
slash("voice status")
local st = table.concat(__take(), "\n")
assert(st:find("not connected", 1, true) and st:find("last seen 7m 3s ago", 1, true) and st:find("/ai diag", 1, true), "status: " .. st)
connected = true
slash("voice status"); assert(table.concat(__take(), "\n"):find("the relay voice is used", 1, true))
-- no relay addon at all: nothing to reconnect, the game's voice at once (as before)
local savedW = WoWAI; WoWAI = nil; connected = true
QB:Call("questlog", "Open", 100); sp0 = spoken; click(R.talk)
assert(spoken == sp0 + 1, "no relay addon: the game's voice, no waiting")
click(R.talk); R:Hide(); WoWAI = savedW
GetTime = realGetTime
connected = true; answerAfter = nil; calls = {}; __take()

-- prefetch at accept: the bridge makes the audio before you ask
slash("voice prefetch on")
calls = {}
__fire("QUEST_ACCEPTED", 2, 100); __runTimers()
assert(#calls == 1 and calls[1].action == "prefetch" and calls[1].ref == "q100" and calls[1].slot == "male", "prefetch with the giver's slot")
assert(calls[1].meta and calls[1].meta.giver == "Zenn Foulhoof" and calls[1].meta.npc == 3498, "and with the giver, so the voice is cast at accept")
slash("voice prefetch off"); calls = {}
__fire("QUEST_ACCEPTED", 2, 100); __runTimers()
assert(#calls == 0, "prefetch off: nothing")
slash("voice prefetch on")
slash("voice engine game"); __fire("QUEST_ACCEPTED", 2, 100); __runTimers()
assert(#calls == 0, "the game's engine: no prefetch")

-- the commands
slash("voice engine relay"); __take()
slash("voice test"); assert(calls[#calls].action == "play" and calls[#calls].ref == "test", "voice test sends a test line")
QB:Call("questlog", "Open", 101); __take()
slash("voice slot")
assert(table.concat(__take(), "\n"):find("slot for the quest on the page: female", 1, true), "voice slot says what the page would use")
R:Hide()
slash("voice")
assert(table.concat(__take(), "\n"):find("voice engine: relay", 1, true), "/qb voice says the engine")
print("voice ok")
