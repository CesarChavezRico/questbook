-- QuestBook Sync -- what the character and the guide look like, written down for planning away from the game (4BI-42).
--
-- Cesar, 2026-11-20: "we need a better way for you to interact with the guide so you can help me in and out of the game ...
-- Can I export the steps and give it to you so we can better plan offline?"; "we need to add my bags to the dump so you can
-- recommend items to destroy or sell depending on the quests I have and the following steps in the guide"; and on splitting
-- the two: "yes, it works".
--
-- Two saved tables, apart on purpose (they change at different speeds, and only one holds paid content):
--   QuestBookState  the CHARACTER: where the guide is, level and experience, money, the quest log, finished quests, bags,
--                   gear, the bank as last seen. Rewritten when the UI unloads (logout, /reload) and by /qb sync now. No
--                   guide text. This is the part meant to travel by itself after every session.
--   QuestBookGuide  the GUIDE: every step of each RestedXP chapter that has been loaded, as RestedXP holds it in memory
--                   (the steps are decoded by RestedXP itself; nothing is decrypted here). Paid content: it stays in this
--                   file, is sent by hand, and never goes into a repository. Written by /qb sync guide, and by itself the
--                   first time a chapter is seen at unload.
-- Both live in the addon's one settings file (WTF/.../SavedVariables/QuestBook.lua) as separate top-level tables.
--
-- UNVERIFIED (client only): the bag and bank calls on this client (C_Container, with the older globals as a fallback), the
-- finished-quest list, and RestedXP's field names, which is why a guide element is copied whole (every plain value it has)
-- instead of by a list of names.

local _, QB = ...

local mod = QB:NewModule("sync", {
  auto = true,          -- write the state when the UI unloads
  guideAuto = true,     -- export a chapter of the guide the first time it is seen at unload
})

local VERSION = 1
local ItemInfo                  -- (defined with the bags)
local TEXT_MAX = 400            -- characters of one guide text kept
local FIELDS_MAX = 40           -- plain values kept per guide element

local function Fn(name) local f = _G[name]; return type(f) == "function" and f or nil end
local function Call(name, ...)
  local f = Fn(name)
  if not f then return nil end
  local r = { pcall(f, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end

local function Plain(s)
  if type(s) ~= "string" then return s end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " ")
  if #s > TEXT_MAX then s = s:sub(1, TEXT_MAX) end
  return s
end

-- ---------------------------------------------------------------- the guide

-- Every plain value (text, number, yes/no) of a RestedXP table, and one level of small lists of plain values (a step's
-- coordinates, a list of quest ids). Functions, frames and back-references (element.step) are left out.
local function Scalars(t)
  local out, n = {}, 0
  for k, v in pairs(t) do
    if n >= FIELDS_MAX then break end
    local tk, tv = type(k), type(v)
    if tk == "string" or tk == "number" then
      if tv == "string" then out[k] = Plain(v); n = n + 1
      elseif tv == "number" or tv == "boolean" then out[k] = v; n = n + 1
      -- (first real export, 2026-11-20: every element carries `element`, a reference to itself, which doubled the file, and
      --  `frame`, its row in RestedXP's window)
      elseif tv == "table" and k ~= "step" and k ~= "parent" and k ~= "elements" and k ~= "element" and k ~= "frame" then
        local list, m = {}, 0
        for k2, v2 in pairs(v) do
          local t2 = type(v2)
          if (type(k2) == "string" or type(k2) == "number") and (t2 == "string" or t2 == "number" or t2 == "boolean") then
            list[k2] = Plain(v2); m = m + 1
            if m >= 12 then break end
          end
        end
        if m > 0 then out[k] = list; n = n + 1 end
      end
    end
  end
  return out
end

local function GuideKey(guide) return tostring(guide.group or "?") .. " / " .. tostring(guide.name or "?") end

-- The string RestedXP imported, as it names it (its GuideLoader keeps the header's two numbers): how many guides the file
-- held and the file's id. A new download with other numbers is a new version.
-- First real export, 2026-11-20: those two were not there on Cesar's client (an empty table came out), so nil when absent.
-- What does identify a chapter is in its own head, which the export copies: `version` (24 for "35-37 Desolace") and
-- `guideId`; Version() below is what the re-export test uses.
local function Imported()
  local rxp = _G.RXP
  local p = type(rxp) == "table" and type(rxp.db) == "table" and rxp.db.profile
  if type(p) ~= "table" or (p.guideLength == nil and p.guideId == nil) then return nil end
  return { guides = p.guideLength, id = p.guideId }
end

local function Version(guide)
  return tostring(guide.version or "?") .. ":" .. tostring(guide.guideId or "?")
end

local function CurrentGuide()
  local rxp = _G.RXP
  local guide = type(rxp) == "table" and rxp.currentGuide
  if type(guide) ~= "table" or type(guide.steps) ~= "table" or #guide.steps == 0 then return nil end
  return guide, rxp
end

-- Write the loaded chapter into QuestBookGuide. Returns the key and the number of steps, or nil and why.
function mod:ExportGuide()
  local guide = CurrentGuide()
  if not guide then return nil, "no guide is loaded in RestedXP" end
  local steps = {}
  for i, step in ipairs(guide.steps) do
    if type(step) == "table" then
      local s = Scalars(step)
      s.elements = {}
      if type(step.elements) == "table" then
        for _, e in ipairs(step.elements) do
          if type(e) == "table" then s.elements[#s.elements + 1] = Scalars(e) end
        end
      end
      steps[i] = s
    else
      steps[i] = {}
    end
  end
  if type(_G.QuestBookGuide) ~= "table" then _G.QuestBookGuide = { v = VERSION, chapters = {} } end
  local store = _G.QuestBookGuide
  if type(store.chapters) ~= "table" then store.chapters = {} end
  local key = GuideKey(guide)
  local head = Scalars(guide)
  store.chapters[key] = { key = key, guide = head, steps = steps, count = #steps, version = Version(guide), imported = Imported(), at = Call("time") }
  store.v = VERSION
  return key, #steps
end

-- ---------------------------------------------------------------- the character

local function GuidePlace()
  local guide, rxp = CurrentGuide()
  if not guide then return nil end
  local pointer
  if type(rxp.GetGuideProgress) == "function" then
    local ok, v = pcall(rxp.GetGuideProgress)
    if ok and type(v) == "number" then pointer = v end
  end
  local active = {}
  for i, step in ipairs(guide.steps) do
    if type(step) == "table" and step.active then active[#active + 1] = i end
  end
  return { chapter = GuideKey(guide), step = pointer, steps = #guide.steps, active = active, version = Version(guide), next = guide.next, imported = Imported() }
end

local function QuestLog()
  local out = {}
  local ok, quests = QB:Call("questlog", "Scan")
  if not ok or type(quests) ~= "table" then return out end
  local Q = _G.C_QuestLog
  for _, q in ipairs(quests) do
    local rec = { id = q.questID, title = q.title, level = q.level, zone = q.header }
    if type(Q) == "table" then
      if type(Q.ReadyForTurnIn) == "function" then local o, r = pcall(Q.ReadyForTurnIn, q.questID); rec.ready = o and r and true or false end
      if type(Q.IsComplete) == "function" then local o, r = pcall(Q.IsComplete, q.questID); rec.complete = o and r and true or false end
      if type(Q.GetQuestObjectives) == "function" then
        local o, objs = pcall(Q.GetQuestObjectives, q.questID)
        if o and type(objs) == "table" then
          rec.objectives = {}
          for _, ob in ipairs(objs) do
            if type(ob) == "table" then rec.objectives[#rec.objectives + 1] = { text = Plain(ob.text), done = ob.finished and true or false, have = ob.numFulfilled, need = ob.numRequired } end
          end
        end
      end
    end
    out[#out + 1] = rec
  end
  return out
end

local function Completed()
  local Q = _G.C_QuestLog
  if type(Q) == "table" and type(Q.GetAllCompletedQuestIDs) == "function" then
    local ok, ids = pcall(Q.GetAllCompletedQuestIDs)
    if ok and type(ids) == "table" then return ids end
  end
  local t = Call("GetQuestsCompleted")
  if type(t) == "table" then
    local ids = {}
    for id, done in pairs(t) do if done then ids[#ids + 1] = id end end
    table.sort(ids)
    return ids
  end
  return nil
end

-- An item's facts. First real export, 2026-11-20: no item had a vendor price or a kind, and gear had no names: this client
-- has no global GetItemInfo, so C_Item.GetItemInfo first (the same values in the same order).
ItemInfo = function(id)
  local C = _G.C_Item
  if type(C) == "table" and type(C.GetItemInfo) == "function" then
    local r = { pcall(C.GetItemInfo, id) }
    if r[1] and r[2] ~= nil then return unpack(r, 2) end
  end
  return Call("GetItemInfo", id)
end

-- One container: its size and what is in it. Items of the same kind in several slots are kept apart (count per slot).
local function ReadBag(bag)
  local C = _G.C_Container
  local slots
  if type(C) == "table" and type(C.GetContainerNumSlots) == "function" then
    local ok, n = pcall(C.GetContainerNumSlots, bag); slots = ok and n or nil
  else
    slots = Call("GetContainerNumSlots", bag)
  end
  if type(slots) ~= "number" or slots <= 0 then return nil end
  local items, used = {}, 0
  for slot = 1, slots do
    local id, count, quality, link, bound
    if type(C) == "table" and type(C.GetContainerItemInfo) == "function" then
      local ok, info = pcall(C.GetContainerItemInfo, bag, slot)
      if ok and type(info) == "table" then id, count, quality, link, bound = info.itemID, info.stackCount, info.quality, info.hyperlink, info.isBound end
    else
      local _, c, _, q, _, _, l, _, _, i = Call("GetContainerItemInfo", bag, slot)
      id, count, quality, link = i, c, q, l
    end
    if id then
      used = used + 1
      local name, _, q2, _, _, itemType, itemSubType, _, _, _, sell = ItemInfo(id)
      items[#items + 1] = { id = id, slot = slot, count = count or 1, name = name or (type(link) == "string" and link:match("%[(.-)%]")) or nil,
        quality = quality or q2, kind = itemType, sub = itemSubType, sell = sell, bound = bound and true or nil }
    end
  end
  return { bag = bag, slots = slots, free = slots - used, items = items }
end

local function Bags(first, last)
  local out = {}
  for bag = first, last do
    local b = ReadBag(bag)
    if b then out[#out + 1] = b end
  end
  return out
end

local function Gear()
  local out = {}
  for slot = 1, 19 do
    local id = Call("GetInventoryItemID", "player", slot)
    if id then
      local cur, max = Call("GetInventoryItemDurability", slot)
      local name, _, quality = ItemInfo(id)
      out[#out + 1] = { slot = slot, id = id, name = name, quality = quality, durability = cur, durabilityMax = max }
    end
  end
  return out
end

-- The bank can only be read while its window is open: keep what was seen then, with when.
local bankSeen
local function ReadBank()
  local list = Bags(-1, -1)
  local n = Call("GetNumBankSlots") or 0
  local more = Bags(5, 4 + math.min(type(n) == "number" and n or 0, 7))
  for _, b in ipairs(more) do list[#list + 1] = b end
  if #list > 0 then bankSeen = { at = Call("time"), bags = list } end
end

function mod:WriteState()
  local prev = _G.QuestBookState
  local s = { v = VERSION, at = Call("time"), addon = QB.version }
  s.name = Call("UnitName", "player"); s.realm = Call("GetRealmName")
  s.level = Call("UnitLevel", "player")
  s.xp = Call("UnitXP", "player"); s.xpMax = Call("UnitXPMax", "player"); s.rested = Call("GetXPExhaustion")
  s.money = Call("GetMoney")
  s.zone = Call("GetRealZoneText"); s.subzone = Call("GetSubZoneText")
  s.hearth = Call("GetBindLocation")
  s.guide = GuidePlace()
  s.quests = QuestLog()
  s.completed = Completed()
  s.bags = Bags(0, 4)
  s.gear = Gear()
  s.bank = bankSeen or (type(prev) == "table" and prev.bank) or nil
  _G.QuestBookState = s
  return s
end

-- ---------------------------------------------------------------- when

mod.events.BANKFRAME_OPENED = function() ReadBank() end
mod.events.PLAYERBANKSLOTS_CHANGED = function() if bankSeen then ReadBank() end end
mod.events.PLAYER_LOGOUT = function(self)
  if not self.db.auto then return end
  self:WriteState()
  if self.db.guideAuto then
    local guide = CurrentGuide()
    if guide then
      local store = _G.QuestBookGuide
      local have = type(store) == "table" and type(store.chapters) == "table" and store.chapters[GuideKey(guide)]
      if not (have and have.version == Version(guide) and have.count == #guide.steps) then self:ExportGuide() end
    end
  end
end

QB:RegisterSlash(mod, "sync", function(rest)
  local sub = (rest or ""):lower():match("^%s*(%S*)")
  if sub == "now" then
    local s = mod:WriteState()
    local items, free = 0, 0
    for _, b in ipairs(s.bags or {}) do items = items + #b.items; free = free + b.free end
    QB:Say(string.format("sync: state written: level %s, %d quests, %d bag items (%d slots free)%s. It reaches the file at /reload or logout",
      tostring(s.level or "?"), #(s.quests or {}), items, free, s.guide and (", guide step " .. tostring(s.guide.step or "?")) or ", no guide loaded"))
  elseif sub == "guide" then
    local key, n = mod:ExportGuide()
    if key then QB:Say(string.format("sync: guide chapter \"%s\" written, %d steps. It reaches the file at /reload or logout", key, n))
    else QB:Say("sync: " .. tostring(n)) end
  elseif sub == "auto" then
    local arg = (rest or ""):lower():match("^%s*%S+%s+(%S+)")
    if arg == "on" or arg == "off" then mod.db.auto = arg == "on" elseif arg then QB:Usage("/qb sync auto on | off") end
    QB:Say("sync: the state is " .. (mod.db.auto and "written by itself when the UI unloads" or "written only by /qb sync now"))
  else
    if sub ~= "" and sub ~= "status" then QB:Usage("/qb sync | now | guide | auto on|off") end
    local chapters = 0
    local store = _G.QuestBookGuide
    if type(store) == "table" and type(store.chapters) == "table" then for _ in pairs(store.chapters) do chapters = chapters + 1 end end
    local imp = Imported()
    local guide = CurrentGuide()
    QB:Say(string.format("sync: state %s; %d guide chapter(s) exported; chapter now: %s%s",
      mod.db.auto and "written at every unload" or "written only on request", chapters,
      guide and string.format("\"%s\", version %s", GuideKey(guide), tostring(guide.version or "?")) or "none loaded",
      imp and imp.id and string.format("; imported file: %s guides, id %s", tostring(imp.guides or "?"), tostring(imp.id)) or ""))
  end
end, "sync: the character (QuestBookState) and the guide (QuestBookGuide) written to the settings file for planning away from the game: now | guide | auto on|off")
