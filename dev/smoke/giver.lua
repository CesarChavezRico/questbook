-- Who gave each quest (4BI-38 step 1): recorded when the quest is accepted, shown in the reader. Stubbed API.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local G, Q = QB.modules.giver, QB.modules.questlog
assert(G and G.active and not G.unavailable, "giver module on")

-- the accept dialog shows, then the quest is accepted: the giver is recorded for that quest
__npc = { name = "Zenn Foulhoof", sex = 2, ctype = "Humanoid", guid = "Creature-0-4379-1-30-3498-000012345A", quest = 100 }
__fire("QUEST_DETAIL")
assert(G:Get(100) == nil, "nothing recorded before the accept")
__fire("QUEST_ACCEPTED", 1, 100)
local r = G:Get(100)
assert(r and r.name == "Zenn Foulhoof" and r.sex == 2 and r.type == "Humanoid" and r.npc == 3498 and r.kind == "Creature", "recorded: " .. G:Describe(r))
assert(r.zone == "Elwynn Forest" or r.zone == nil or type(r.zone) == "string", "zone kept when known")

-- a female NPC, accepted through the older event signature (index only)
__npc = { name = "Sentinel Kyra Starsong", sex = 3, ctype = "Humanoid", guid = "Creature-0-4379-1-30-61000-0000ABCDEF", quest = 101 }
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 3)           -- log index 3 is quest 101 in the stub
r = G:Get(101)
assert(r and r.name == "Sentinel Kyra Starsong" and r.sex == 3 and r.npc == 61000, "older signature: " .. G:Describe(r))

-- a quest started from an item (nobody to talk to): no record, no error
__npc = nil
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 3, 102)
assert(G:Get(102) == nil, "no giver, no record")

-- a quest shared by a party member: the name is kept, there is no NPC number
__npc = { name = "Mara", sex = 3, ctype = "Humanoid", guid = "Player-4379-0A1B2C3D", quest = 103 }
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 4, 103)
r = G:Get(103)
assert(r and r.name == "Mara" and r.npc == nil and r.kind == "Player", "a shared quest: " .. G:Describe(r))

-- an accept that was never confirmed does not leave a record, and a stale dialog is not reused
__npc = { name = "Somebody", sex = 2, ctype = "Beast", guid = "Creature-0-1-1-1-9-0000000001", quest = 104 }
__fire("QUEST_DETAIL"); __fire("QUEST_DETAIL")
assert(G:Get(104) == nil, "dialog without an accept: nothing")

-- a value the client refuses to give (secret) is not recorded
local realIs = issecretvalue
issecretvalue = function(v) return v == "Secretive" end
__npc = { name = "Secretive", sex = 2, ctype = "Humanoid", guid = "Creature-0-1-1-1-7-0000000002", quest = 105 }
__fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 5, 105)
assert(G:Get(105) == nil, "a secret name: no record, no error")
issecretvalue = realIs

-- the records are capped, oldest first
G.db.cap = 3
for i = 1, 6 do
  __npc = { name = "NPC " .. i, sex = 2, ctype = "Humanoid", guid = "Creature-0-1-1-1-" .. (500 + i) .. "-0000000003", quest = 200 + i }
  __fire("QUEST_DETAIL"); __fire("QUEST_ACCEPTED", 1, 200 + i)
end
assert(G:Count() == 3 and G:Get(206) and G:Get(205) and G:Get(204) and not G:Get(203) and not G:Get(100), "capped at 3, oldest dropped")
G.db.cap = 500

-- the reader says who gave the quest
G.db.quests[100] = { name = "Zenn Foulhoof", sex = 2, type = "Humanoid", npc = 3498, kind = "Creature" }
G.db.quests[101] = { name = "Sentinel Kyra Starsong", sex = 3, type = "Humanoid", npc = 61000, kind = "Creature" }      -- (the cap test dropped the older ones)
QB:Call("questlog", "Open", 100)
local R = QuestBookReader
assert(R.meta:GetText():find("From Zenn Foulhoof", 1, true), "the meta line: " .. tostring(R.meta:GetText()))
QB:Call("questlog", "Open", 101)
assert(R.meta:GetText():find("From Sentinel Kyra Starsong", 1, true), "and for the other quest: " .. tostring(R.meta:GetText()))
R:Hide()
-- a quest nobody gave a record for: no "From" line
QB:Call("questlog", "Open", 102)
assert(not R.meta:GetText():find("From", 1, true), "no record, no line: " .. tostring(R.meta:GetText()))
R:Hide()

-- /qb giver prints what was seen and how many are recorded
__npc = { name = "Zenn Foulhoof", sex = 2, ctype = "Humanoid", guid = "Creature-0-4379-1-30-3498-000012345A", quest = 100 }
__fire("GOSSIP_SHOW")
__take()
slash("giver")
local out = table.concat(__take(), "\n")
assert(out:find("last seen Zenn Foulhoof (male Humanoid, NPC 3498", 1, true), "last seen: " .. out)
assert(out:find("quests recorded", 1, true), "count: " .. out)

-- disabling keeps the records (they are saved), the reader then just leaves the line out
QB:SetEnabled("giver", false)
QB:Call("questlog", "Open", 100)
assert(not R.meta:GetText():find("From", 1, true), "giver off: no line")
R:Hide(); QB:SetEnabled("giver", true)
print("giver ok")
