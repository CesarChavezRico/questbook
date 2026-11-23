-- v0.36.0 (4BI-38): the quest is read when the guide puts you to work on it, the hand-in is read, and the words are kept.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, G, Q = QB.modules.story, QB.modules.guide, QB.modules.questlog
assert(S and S.active and G and G.active, "story and guide modules on")
local tts = {}
WoWAI = { SendTts = function(action, slot, ref, text, meta) tts[#tts + 1] = { action = action, slot = slot, ref = ref, text = text, meta = meta }; return true, #tts end,
  IsConnected = function() return true end, Connect = function() end }
local function refs(action) local out = {} for _, t in ipairs(tts) do if t.action == action then out[#out + 1] = t.ref end end return table.concat(out, ",") end
RXPGuides = {}
-- the guide: step 1 accepts 100 and 101 at the hub, step 2 works 100, step 3 works 101, step 4 hands 101 in; 102 is not in it
RXP = { settings = { profile = {} }, currentGuide = { group = "G", name = "N", steps = {
  { index = 1, active = true, elements = { { tag = "accept", questId = 100, text = "Accept Wolves" }, { tag = "accept", questId = 101, text = "Accept Kobolds" } } },
  { index = 2, elements = { { tag = "complete", questId = 100, text = "Kill wolves" } } },
  { index = 3, elements = { { tag = "complete", questId = 101, text = "Kill kobolds" } } },
  { index = 4, elements = { { tag = "turnin", questId = 101, text = "Turn in Kobolds" } } },
} } }
__runTimers()
assert(refs("queue") == "g1", "the hub step is read: " .. refs("queue"))

-- accepting at the hub no longer reads the quests the guide will work: their audio is only made ready
__npc = { name = "Zenn Foulhoof", sex = 2, ctype = "Humanoid", guid = "Creature-0-4379-1-30-3498-000012345A", quest = 100 }
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 1, 100)
__npc.quest = 101; __fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 2, 101)
__runTimers()
assert(refs("queue") == "g1", "nothing more is read at accept: " .. refs("queue"))
assert(refs("prefetch") == "q100,q101", "but both are made ready: " .. refs("prefetch"))
assert(G:WorksLater(100) and G:WorksLater(101) and not G:WorksLater(102), "the guide works 100 and 101, not 102")

-- a quest the guide never mentions is still read at accept
__npc.quest = 102; __fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 3, 102); __runTimers()
assert(refs("queue") == "g1,q102", "a quest outside the guide is read at accept: " .. refs("queue"))

-- the guide moves to the step that works quest 100: its line first, then the quest's own text, once
RXP.currentGuide.steps[1].active = nil; RXP.currentGuide.steps[2].active = true
__runTimers()
assert(refs("queue") == "g1,q102,g2,q100", "the step, then the story of its quest: " .. refs("queue"))
assert(tts[#tts].slot == "male" and tts[#tts].text:find("Go and slay", 1, true), "in the giver's voice, the quest's text")
__runTimers(); __runTimers()
assert(refs("queue") == "g1,q102,g2,q100", "read once")
-- step 3 works 101; step 4 hands it in: already told, not read again
RXP.currentGuide.steps[2].active = nil; RXP.currentGuide.steps[3].active = true; __runTimers()
RXP.currentGuide.steps[3].active = nil; RXP.currentGuide.steps[4].active = true; __runTimers()
assert(refs("queue") == "g1,q102,g2,q100,g3,q101,g4", "101 on its work step, not again on its hand-in step: " .. refs("queue"))
assert(QuestBookDB.mod.guide.told[100] and QuestBookDB.mod.guide.told[101] and QuestBookDB.mod.guide.told[102], "what was told is saved (a reload does not repeat it)")

-- a delivery quest (no work line): read on the step that sends you to hand it in; and only once it is in the log
G.db.told[100] = nil
RXP.currentGuide.steps[5] = { index = 5, active = true, elements = { { tag = "turnin", questId = 100, text = "Turn in Wolves" } } }
__runTimers()
assert(refs("queue"):find("g5,q100$"), "a hand-in step reads a quest not told yet: " .. refs("queue"))
RXP.currentGuide.steps[6] = { index = 6, active = true, elements = { { tag = "complete", questId = 999, text = "Not accepted yet" } } }
__runTimers()
assert(not G.db.told[999] and not refs("queue"):find("q999"), "a quest not in the log waits")
-- a work line already done is not a reason to read
RXP.currentGuide.steps[4].active = nil
G.db.told[101] = nil
RXP.currentGuide.steps[7] = { index = 7, active = true, elements = { { tag = "complete", questId = 101, text = "done", completed = true }, { text = "Run back" } } }
__runTimers()
assert(not G.db.told[101], "a finished objective does not start the story")
SlashCmdList.QUESTBOOK("guide quests off"); __take()
RXP.currentGuide.steps[5].active = nil
G.db.told[100] = nil; RXP.currentGuide.steps[8] = { index = 8, active = true, elements = { { tag = "complete", questId = 100, text = "again" } } }
__runTimers(); assert(not G.db.told[100], "quests off: no story")
SlashCmdList.QUESTBOOK("guide quests on"); __take(); G.db.told[100] = true

-- the words are kept at accept
assert(S:Get(100) and S:Get(100).text:find("Go and slay", 1, true) and S:Get(100).from == "Zenn Foulhoof", "the accept text is kept, with who gave it")
assert(S:Get(100).done == nil and S:Count() == 3)

-- the hand-in: the reward dialog shows the NPC's words; they are kept and read when the quest is really handed in
__npc = { name = "Sentinel Kyra Starsong", sex = 3, ctype = "Humanoid", guid = "Creature-0-4379-1-30-61000-0000ABCDEF", quest = 100 }
GetRewardText = function() return "Well done. The wolves will trouble us no more." end
GetTitleText = function() return "Wolves" end
local n = #tts
__fire("QUEST_COMPLETE")
assert(#tts == n, "nothing is read while the dialog is only open")
__fire("QUEST_TURNED_IN", 100, 250, 0); __runTimers()
local last = tts[#tts]
assert(last.action == "queue" and last.ref == "t100" and last.slot == "female" and last.text == "Well done. The wolves will trouble us no more.", "the hand-in is queued in the NPC's voice: " .. tostring(last.ref) .. " " .. tostring(last.slot))
assert(last.meta and last.meta.giver == "Sentinel Kyra Starsong", "with who is speaking")
assert(S:Get(100).done == "Well done. The wolves will trouble us no more." and S:Get(100).to == "Sentinel Kyra Starsong", "and kept")
-- the dialog closed without handing in: nothing read, nothing kept
__npc.quest = 101; __fire("QUEST_COMPLETE"); __fire("QUEST_FINISHED"); __runTimers()
n = #tts; __fire("QUEST_TURNED_IN", 102, 0, 0); __runTimers()
assert(#tts == n and S:Get(101).done == nil, "no hand-in, no reading")
-- another quest handed in than the dialog showed: not mixed up
__fire("QUEST_COMPLETE"); n = #tts; __fire("QUEST_TURNED_IN", 102, 0, 0); __runTimers()
assert(#tts == n and S:Get(102).done == nil, "a different quest number is not given these words")
-- turnins off: kept, not read
SlashCmdList.QUESTBOOK("guide turnins off"); __take()
__fire("QUEST_COMPLETE"); n = #tts; __fire("QUEST_TURNED_IN", 101, 0, 0); __runTimers()
assert(#tts == n and S:Get(101).done, "turnins off: the words are kept but not read")
SlashCmdList.QUESTBOOK("guide turnins on"); __take()
-- no reward text (an API that is not there): no error
GetRewardText = nil; __fire("QUEST_COMPLETE"); __fire("QUEST_TURNED_IN", 101, 0, 0); __runTimers()
-- the cap drops the oldest
S.db.cap = 2; __npc = { name = "X", sex = 2, ctype = "Humanoid", guid = "Creature-0-1-1-1-7-1", quest = 103 }
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 4, 103); __runTimers()
assert(S:Count() <= 3, "capped")
SlashCmdList.QUESTBOOK("story 5")
local said = table.concat(__take(), "\n")
assert(said:find("quests kept", 1, true) and said:find("at hand-in", 1, true), "/qb story says what is kept: " .. said)
print("story ok")
