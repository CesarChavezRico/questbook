-- QuestBook Giver -- who gave you each quest (4BI-38, step 1 of the voiceover).
--
-- The voiceover will choose a voice by the quest giver (creature type and gender, and a per-NPC override), and the reader
-- shows "From <name>". The NPC is only there while its dialog is up, so the giver is recorded when you ACCEPT a quest and
-- kept per quest in the saved variables: name, gender, creature type, NPC number (from the unit's GUID) and zone. Quests
-- accepted before this module existed have no record (the reader just leaves the line out).
--
-- The game's unit token for whoever you are talking to is "npc" (UnitName / UnitSex / UnitCreatureType / UnitGUID, the
-- same calls Blizzard's own gossip and quest frames make). Not available to an addon: an NPC's RACE.
--
-- UNVERIFIED (client only): that these calls answer for "npc" on this client, and what they return; `/qb giver` prints the
-- last thing seen so one accepted quest settles it. A quest shared by a party member comes from a player ("Player-" GUID):
-- its name is kept, its NPC number is nil.

local _, QB = ...

local mod = QB:NewModule("giver", {
  quests = {},        -- questID -> { name, sex, type, npc, kind, zone, t }
  order = {},         -- questIDs, oldest first (the cap drops from the front)
  cap = 500,          -- records kept
})

local SEX = { [1] = "neutral", [2] = "male", [3] = "female" }
local pending           -- the giver seen at the last accept dialog: { qid, snap }
local lastSnap, lastSeen

local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok and not IsSecret(v) then return v end
  return nil
end

-- What the game says about whoever you are talking to, or nil when nobody (a quest started from an item, say).
local function Snap()
  local name = Call(UnitName, "npc")
  if type(name) ~= "string" or name == "" then return nil end
  local guid = Call(UnitGUID, "npc")
  local npc, kind
  if type(guid) == "string" then
    kind = guid:match("^(%a+)%-")
    npc = tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))      -- Creature-0-server-instance-zone-NPCID-spawn
  end
  local sex = Call(UnitSex, "npc")
  return {
    name = name,
    sex = type(sex) == "number" and sex or nil,
    type = Call(UnitCreatureType, "npc"),
    npc = npc, kind = kind,
    zone = Call(GetZoneText),
  }
end

local function Remember(qid, snap)
  local db = mod.db
  if not (qid and snap) then return end
  if not db.quests[qid] then
    db.order[#db.order + 1] = qid
    while #db.order > (tonumber(db.cap) or 500) do
      local old = table.remove(db.order, 1)
      db.quests[old] = nil
    end
  end
  db.quests[qid] = { name = snap.name, sex = snap.sex, type = snap.type, npc = snap.npc, kind = snap.kind,
    zone = snap.zone, t = (GetServerTime and Call(GetServerTime)) or nil }
end

-- The record for a quest, or nil.
function mod:Get(questID) return self.db.quests[questID] end
function mod:Count() return #self.db.order end

function mod:Describe(rec)
  if not rec then return "no record" end
  return string.format("%s (%s %s, NPC %s%s%s)", tostring(rec.name), SEX[rec.sex] or tostring(rec.sex or "?"), tostring(rec.type or "?"),
    tostring(rec.npc or "none"), rec.kind and (", " .. rec.kind) or "", rec.zone and (", " .. rec.zone) or "")
end

-- ---------------------------------------------------------------- events

local function Seen()
  local s = Snap()
  if s then lastSnap, lastSeen = s, (GetTime and Call(GetTime)) or 0 end
  return s
end

-- the accept dialog is up: this is who is offering which quest
mod.events.QUEST_DETAIL = function()
  local s = Seen()
  local qid = Call(GetQuestID)
  pending = (s and type(qid) == "number" and qid > 0) and { qid = qid, snap = s } or nil
end
mod.events.GOSSIP_SHOW = function() Seen() end
mod.events.QUEST_GREETING = function() Seen() end
-- the dialog closed without an accept
mod.events.QUEST_FINISHED = function() end      -- (kept: QUEST_ACCEPTED can arrive after it)

-- accepted: (questLogIndex, questID) on retail clients, just the index on older ones
mod.events.QUEST_ACCEPTED = function(_, a, b)
  local qid = type(b) == "number" and b or nil
  if not qid and type(a) == "number" and C_QuestLog and C_QuestLog.GetInfo then
    local info = Call(C_QuestLog.GetInfo, a)
    qid = type(info) == "table" and info.questID or nil
  end
  if pending and (qid == nil or qid == pending.qid) then
    Remember(pending.qid, pending.snap)
    pending = nil
  elseif pending and qid and not mod.db.quests[qid] then
    -- another quest was accepted than the dialog showed (auto-accept chains): the same NPC is the giver, but a record
    -- that already exists is never overwritten by a guess
    Remember(qid, pending.snap)
  end
end

-- ---------------------------------------------------------------- slash

QB:RegisterSlash(mod, "giver", function()
  local s = lastSnap
  if s then
    QB:Say("giver: last seen " .. mod:Describe(s) .. ", " .. string.format("%.0f", ((GetTime and Call(GetTime)) or 0) - (lastSeen or 0)) .. " s ago")
  else
    QB:Say("giver: nobody seen yet (talk to a quest giver)")
  end
  QB:Say("giver: " .. mod:Count() .. " quests recorded")
  local ok, sel = QB:Call("questlog", "CurrentQuestID")
  if ok and sel then QB:Say("giver: the quest on the reader's page: " .. mod:Describe(mod:Get(sel))) end
end, "giver: who gave the quests (and what the game says about the NPC you last talked to)")
