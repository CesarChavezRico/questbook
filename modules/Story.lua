-- QuestBook Story -- the words of your quests, kept, and the hand-in read aloud (4BI-38).
--
-- Cesar, 2026-11-23: option "1 with 3" (the quest read when the guide works it; the turn-in text read too) and: "there are some
-- quests that come from a chain, is there a way to get the quest and turn in text from previous quests in the chain?"
-- The game only gives a quest's text while the quest is in your log or its dialog is open; once it is handed in, the text is
-- gone. So the only way to have an earlier quest's words later is to KEEP them as they pass:
--   * at accept: the title and the description (from the log, a moment after QUEST_ACCEPTED)
--   * at hand-in: what the NPC says in the reward dialog (GetRewardText while QUEST_COMPLETE's dialog is up), and who said it
-- kept per quest in the saved variables, in the order you did them, newest `cap` quests. Nothing is shown yet: this is the
-- record a "story so far" page would read from (a chain is then the quests of one giver / one thread, in order).
-- Quests done before this module existed have no record.
--
-- The hand-in is also READ: when the quest is really handed in (QUEST_TURNED_IN), the NPC's words are queued in that NPC's
-- voice slot, behind whatever is being read (guide reader on, `/qb guide turnins on|off`).
--
-- UNVERIFIED (client only): GetRewardText / GetTitleText answer in the reward dialog on this client, QUEST_TURNED_IN carries
-- the quest's number, and the "npc" unit is still the NPC then. `/qb story` prints what was kept for the last quests.

local _, QB = ...

local mod = QB:NewModule("story", {
  quests = {},        -- questID -> { title, text, done, from, to, zone, t, t2 }
  order = {},         -- questIDs, oldest first (the cap drops from the front)
  cap = 600,
})

local pending           -- the reward dialog that is up: { qid, title, text, who }

local function Call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, v = pcall(fn, ...)
  if ok and not (type(issecretvalue) == "function" and issecretvalue(v)) then return v end
  return nil
end

local function Now() return (GetServerTime and Call(GetServerTime)) or nil end

local function Rec(qid)
  local db = mod.db
  local r = db.quests[qid]
  if not r then
    r = {}
    db.quests[qid] = r
    db.order[#db.order + 1] = qid
    while #db.order > (tonumber(db.cap) or 600) do
      local old = table.remove(db.order, 1)
      db.quests[old] = nil
    end
  end
  return r
end

function mod:Get(questID) return self.db.quests[questID] end
function mod:Count() return #self.db.order end

-- accepted: keep the title and the description (the log has them a moment later)
mod.events.QUEST_ACCEPTED = function(_, a, b)
  local qid = type(b) == "number" and b or nil
  if not qid then return end
  local function Keep()
    local ok, title, text = QB:Call("questlog", "TextFor", qid)
    if not (ok and text) then return end
    local r = Rec(qid)
    r.title, r.text, r.t = title, text, r.t or Now()
    local okG, g = QB:Call("giver", "Get", qid)
    if okG and g then r.from, r.zone = g.name, g.zone end
  end
  if C_Timer and C_Timer.After then C_Timer.After(2, function() QB:Safe(mod, Keep) end) else Keep() end
end

-- the reward dialog is up: this is what the NPC says, and who says it
mod.events.QUEST_COMPLETE = function()
  local qid = Call(GetQuestID)
  local text = Call(GetRewardText)
  if type(qid) ~= "number" or qid <= 0 or type(text) ~= "string" or text == "" then pending = nil return end
  local okS, who = QB:Call("giver", "Snap")
  pending = { qid = qid, title = Call(GetTitleText), text = text, who = okS and who or nil }
end

-- handed in: keep the words, and read them (queued, in that NPC's voice)
mod.events.QUEST_TURNED_IN = function(_, questID)
  local p = pending
  pending = nil
  if not p or (type(questID) == "number" and questID ~= p.qid) then return end
  local r = Rec(p.qid)
  r.title = r.title or p.title
  r.done, r.to, r.t2 = p.text, p.who and p.who.name or nil, Now()
  if not r.zone and p.who then r.zone = p.who.zone end
  local ok, reads = QB:Call("guide", "ReadsTurnIns")
  if ok and reads then QB:Call("questlog", "QueueWords", "t" .. tostring(p.qid), p.text, p.who, r.title) end
end
-- the dialog closed without a hand-in: QUEST_TURNED_IN comes before QUEST_FINISHED when there was one
mod.events.QUEST_FINISHED = function()
  if C_Timer and C_Timer.After then C_Timer.After(1, function() pending = nil end) else pending = nil end
end

QB:RegisterSlash(mod, "story", function(rest)
  local n = math.max(1, math.min(10, tonumber(rest) or 3))
  local order = mod.db.order
  QB:Say("story: " .. #order .. " quests kept (the words at accept and at hand-in; newest " .. tostring(mod.db.cap) .. ")")
  for i = #order, math.max(1, #order - n + 1), -1 do
    local r = mod.db.quests[order[i]]
    if r then
      QB:Say(string.format("story: %s (%d): %s%s", tostring(r.title or "?"), order[i],
        r.text and (#r.text .. " characters at accept" .. (r.from and (", from " .. r.from) or "")) or "no accept text",
        r.done and ("; " .. #r.done .. " at hand-in" .. (r.to and (", to " .. r.to) or "")) or "; not handed in yet"))
    end
  end
end, "story [n]: the quest words kept so far (accept text and hand-in text of your quests)")
