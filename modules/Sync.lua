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

-- The realm's name: GetRealmName came back empty on Cesar's client in every file since v0.33.0.
local function Realm()
  local r = Call("GetRealmName")
  if type(r) ~= "string" or r == "" then r = Call("GetNormalizedRealmName") end
  if type(r) ~= "string" or r == "" then return nil end
  return r
end

-- ---------------------------------------------------------------- profession skills (4BI-48, v0.40.0)
--
-- Cesar, 2026-11-23: "do you have info on Thara's professions? can we map a plan for leveling each one while working on the
-- guide?" The state had no profession skill. Now: for each profession its name, skill id, current skill, current cap and
-- whether it is primary or secondary. Three ways to ask, tried in this order (each guarded, any may be missing):
--   1. C_SkillInfo.GetNumSkillLines / GetSkillLineInfo(i): one table per line (name, isHeader, rank, maxRank, skillID,
--      parentSkillLineID). The relay addon reads the Forever client this way (its WoWAI.SkillLines: "Forever only has
--      C_SkillInfo"), so this is the one expected to answer.
--   2. the classic globals GetNumSkillLines / GetSkillLineInfo(i): name, header flag, ..., rank, ..., max rank; professions
--      sit under the "Professions" and "Secondary Skills" headers (a collapsed header hides its lines).
--   3. the retail GetProfessions / GetProfessionInfo(index).
-- A profession is known by its skill id (the vanilla ids), else by the header it sits under. nil when the client has none
-- of the three, so the field is simply left out. The recipes known are NOT read: that needs the profession window open,
-- and this module never opens a window. UNVERIFIED (client only): which of the three answers, and the header names.
local PRIMARY = { [164] = true, [165] = true, [171] = true, [182] = true, [186] = true, [197] = true, [202] = true, [333] = true, [393] = true }
local SECONDARY = { [129] = true, [185] = true, [356] = true }
local HEADER_KIND = { professions = "primary", ["secondary skills"] = "secondary" }

local function Skills()
  local out, seen = {}, {}
  local function Add(name, id, rank, max, kind)
    if type(name) ~= "string" or name == "" or not kind then return end
    local key = id or name
    if seen[key] then return end
    seen[key] = true
    out[#out + 1] = { name = name, id = id, rank = tonumber(rank) or 0, max = tonumber(max) or 0, kind = kind }
  end
  local function Kind(id, header)
    if id and PRIMARY[id] then return "primary" end
    if id and SECONDARY[id] then return "secondary" end
    return header and HEADER_KIND[header] or nil
  end
  local S = _G.C_SkillInfo
  if type(S) == "table" and type(S.GetNumSkillLines) == "function" and type(S.GetSkillLineInfo) == "function" then
    local okN, n = pcall(S.GetNumSkillLines)
    local header
    for i = 1, (okN and type(n) == "number") and n or 0 do
      local ok, sk = pcall(S.GetSkillLineInfo, i)
      if ok and type(sk) == "table" and type(sk.name) == "string" then
        if sk.isHeader then header = sk.name:lower()
        elseif (sk.parentSkillLineID or 0) == 0 then Add(sk.name, tonumber(sk.skillID), sk.rank, sk.maxRank, Kind(tonumber(sk.skillID), header)) end
      end
    end
    return out
  end
  if Fn("GetNumSkillLines") and Fn("GetSkillLineInfo") then
    local n = Call("GetNumSkillLines")
    local header
    for i = 1, type(n) == "number" and n or 0 do
      local name, isHeader, _, rank, _, _, max = Call("GetSkillLineInfo", i)
      if type(name) == "string" then
        if isHeader then header = name:lower() else Add(name, nil, rank, max, Kind(nil, header)) end
      end
    end
    return out
  end
  if Fn("GetProfessions") and Fn("GetProfessionInfo") then
    local idx = { Call("GetProfessions") }
    for slot = 1, 6 do
      local index = idx[slot]
      if index then
        local name, _, rank, max, _, _, id = Call("GetProfessionInfo", index)
        Add(name, tonumber(id), rank, max, (slot <= 2) and "primary" or "secondary")
      end
    end
    return out
  end
  return nil
end
mod.Skills = function() return Skills() end

-- ---------------------------------------------------------------- recipes (4BI-49, v0.41.0)
--
-- Cesar, 2026-11-23: "can you also access the recipes I have, that way we can make more specific plans"; of two ways, the
-- capture at the profession window. The game only lists a profession's recipes while its window is open, and this module
-- never opens a window and never crafts. So: when Cesar opens a profession window, that profession's recipes are saved,
-- and stay until the same window is opened again. Per profession: { name, id, at, skill, max, how, partial, list }, and
-- per recipe { name, id, diff, can, mats }: diff = "orange" | "yellow" | "green" | "grey" (will it still give skill),
-- can = how many can be made from the bags now, mats = { { id, count }, ... }.
-- Two ways to ask, each guarded:
--   1. C_TradeSkillUI (the Forever client's profession window is the modern one: Blizzard_Professions, read 2026-11-23 in
--      the Forever UI source): GetAllRecipeIDs (else GetFilteredRecipeIDs: the list is then marked partial), GetRecipeInfo
--      (name, learned, relativeDifficulty), GetCraftableCount, GetRecipeSchematic for the materials, GetBaseProfessionInfo
--      for the profession. Someone else's linked window, a guild's, or an NPC's crafting is not ours: not captured.
--   2. the classic globals: GetTradeSkillLine, GetNumTradeSkills, GetTradeSkillInfo (type optimal / medium / easy /
--      trivial / header), reagents, links for the ids. A collapsed header hides its recipes: marked partial, never expanded.
-- The first read after the window shows can be empty, so the capture runs a moment after TRADE_SKILL_SHOW and again on
-- TRADE_SKILL_LIST_UPDATE; a read with no recipes never replaces a saved list.
-- UNVERIFIED (client only): which way answers, the field names of the modern one, and the event names.
local recipes                   -- [profession name] = the capture; nil until one is made or found in the stored state
local DIFF_NUM = { [0] = "orange", [1] = "yellow", [2] = "green", [3] = "grey" }      -- Enum.TradeskillRelativeDifficulty
local DIFF_WORD = { optimal = "orange", medium = "yellow", easy = "green", trivial = "grey" }
local RECIPES_MAX = 400         -- recipes kept for one profession

local function ReadRecipesModern()
  local T = _G.C_TradeSkillUI
  if type(T) ~= "table" or type(T.GetRecipeInfo) ~= "function" then return nil end
  local function Tc(name, ...)
    if type(T[name]) ~= "function" then return nil end
    local ok, a = pcall(T[name], ...)
    if ok then return a end
    return nil
  end
  if Tc("IsTradeSkillLinked") or Tc("IsTradeSkillGuild") or Tc("IsNPCCrafting") then return false end       -- not the character's own
  if type(T.IsTradeSkillReady) == "function" and not Tc("IsTradeSkillReady") then return false end
  local how, ids = "all", Tc("GetAllRecipeIDs")
  if type(ids) ~= "table" then how, ids = "filtered", Tc("GetFilteredRecipeIDs") end
  if type(ids) ~= "table" then return nil end
  local prof = Tc("GetBaseProfessionInfo") or Tc("GetChildProfessionInfo")
  local cap = { how = "C_TradeSkillUI", list = {} }
  if type(prof) == "table" then
    cap.name, cap.id = prof.professionName or prof.parentProfessionName, tonumber(prof.professionID or prof.parentProfessionID)
    cap.skill, cap.max = tonumber(prof.skillLevel), tonumber(prof.maxSkillLevel)
  end
  if how == "filtered" then cap.partial = "the window's filtered list (the client has no full list)" end
  for _, id in ipairs(ids) do
    local info = Tc("GetRecipeInfo", id)
    if type(info) == "table" and info.learned and type(info.name) == "string" and #cap.list < RECIPES_MAX then
      local d = info.relativeDifficulty
      local r = { name = info.name, id = tonumber(info.recipeID) or tonumber(id),
        diff = (type(d) == "number" and DIFF_NUM[d]) or (type(d) == "string" and DIFF_WORD[d:lower()]) or nil,
        can = tonumber(Tc("GetCraftableCount", id)) }
      local sch = Tc("GetRecipeSchematic", id, false)
      if type(sch) == "table" and type(sch.reagentSlotSchematics) == "table" then
        local mats = {}
        for _, slot in ipairs(sch.reagentSlotSchematics) do
          local first = type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents[1]
          if type(first) == "table" and first.itemID and (tonumber(slot.quantityRequired) or 0) > 0 and (slot.required == nil or slot.required) then
            mats[#mats + 1] = { id = tonumber(first.itemID), count = tonumber(slot.quantityRequired) }
          end
        end
        if #mats > 0 then r.mats = mats end
      end
      cap.list[#cap.list + 1] = r
    end
  end
  return cap
end

local function ReadRecipesClassic()
  if not (Fn("GetNumTradeSkills") and Fn("GetTradeSkillInfo")) then return nil end
  local name, skill, max = Call("GetTradeSkillLine")
  if type(name) ~= "string" or name == "" or name == "UNKNOWN" then return false end
  local cap = { how = "classic", name = name, skill = tonumber(skill), max = tonumber(max), list = {} }
  local n = Call("GetNumTradeSkills")
  for i = 1, type(n) == "number" and n or 0 do
    local rname, kind, can, expanded = Call("GetTradeSkillInfo", i)
    if kind == "header" then
      if expanded == false or expanded == 0 then cap.partial = "a collapsed header hides some recipes" end
    elseif type(rname) == "string" and #cap.list < RECIPES_MAX then
      local link = Call("GetTradeSkillRecipeLink", i) or Call("GetTradeSkillItemLink", i)
      local r = { name = rname, id = type(link) == "string" and tonumber(link:match("|H%a+:(%d+)")) or nil,
        diff = type(kind) == "string" and DIFF_WORD[kind:lower()] or nil, can = tonumber(can) }
      local nr = Call("GetTradeSkillNumReagents", i)
      local mats = {}
      for j = 1, type(nr) == "number" and nr or 0 do
        local _, _, count = Call("GetTradeSkillReagentInfo", i, j)
        local rl = Call("GetTradeSkillReagentItemLink", i, j)
        local rid = type(rl) == "string" and tonumber(rl:match("|Hitem:(%d+)")) or nil
        if rid and tonumber(count) then mats[#mats + 1] = { id = rid, count = tonumber(count) } end
      end
      if #mats > 0 then r.mats = mats end
      cap.list[#cap.list + 1] = r
    end
  end
  return cap
end

local function Stored()
  if recipes == nil then
    local prev = _G.QuestBookState
    recipes = (type(prev) == "table" and type(prev.recipes) == "table" and prev.recipes) or {}
  end
  return recipes
end

-- Read the open profession window and keep its recipes. Returns the capture, or nil and why nothing was kept.
function mod:CaptureRecipes()
  local cap = ReadRecipesModern()
  if cap == nil then cap = ReadRecipesClassic() end
  if cap == nil then return nil, "this client has no recipe functions" end
  if cap == false then return nil, "no profession window of the character's own is open (or it is not ready yet)" end
  if type(cap.name) ~= "string" or cap.name == "" then return nil, "the game did not say which profession the window is" end
  if #cap.list == 0 then return nil, "the window listed no recipes (not ready yet?)" end        -- never replaces a saved list
  cap.at, cap.count = Call("time"), #cap.list
  Stored()[cap.name] = cap
  mod.recipesChanged = true                -- the next tick takes a new snapshot, so the state in memory carries it
  return cap
end

-- The saved captures: [profession name] = { name, id, at, skill, max, how, partial, count, list }.
function mod:Recipes() return Stored() end

local captureAt
local function CaptureSoon()
  local now = (GetTime and GetTime()) or 0
  if captureAt and now - captureAt < 1 then return end                 -- one capture for a burst of list updates
  captureAt = now
  if C_Timer and C_Timer.After then C_Timer.After(0.6, function() QB:Safe(mod, mod.CaptureRecipes, mod) end)
  else mod:CaptureRecipes() end
end

-- Read the character from the game, now.
local function Read(how)
  local s = { v = VERSION, at = Call("time"), addon = QB.version, how = how }
  s.name = Call("UnitName", "player"); s.realm = Realm()
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
  s.skills = Skills()
  return s
end

-- A HOLLOW read (4BI-47). Seven state files of 2026-11-20 showed it: a state written at a real logout had money 0,
-- experience 0, no bags, no gear, no finished quests and no objectives (7.0 KB), while one written by a /reload in the
-- world was whole (21.3 KB). At a real logout the client no longer answers these reads, each guarded call quietly gives
-- nil or zero, and the hollow state replaced the good one. So: the state is taken WHILE IN THE WORLD and kept in memory
-- (`snap`), refreshed when bags, quests, money, experience, gear or the zone change (at most every few seconds) and once
-- a minute; at unload the snapshot is what is written and the game is not read again; and a hollow read never replaces
-- a whole state, in memory or in the file.
local function Hollow(s)
  if type(s) ~= "table" then return true end
  if type(s.bags) ~= "table" or #s.bags == 0 then return true end
  if type(s.xpMax) ~= "number" or s.xpMax <= 0 then return true end
  return false
end

local snap                      -- the last whole state read in the world
local dirty, lastTake, enabledAt = true, nil, nil
local TAKE_GAP = 5              -- seconds between two reads caused by events
local TAKE_EVERY = 60           -- seconds between two reads with no event
local SETTLE = 6                -- seconds after the UI loads before the first read (the quest log fills in late: a read in
                                -- the first second after login held 26 of 40 quests, seen twice on 2026-11-20)

local function WithBank(s)
  local prev = _G.QuestBookState
  s.bank = bankSeen or (snap and snap.bank) or (type(prev) == "table" and prev.bank) or nil
  -- the recipes seen at the profession windows travel with every state (4BI-49): nothing reads them again here
  local rec = recipes or (snap and snap.recipes) or (type(prev) == "table" and type(prev.recipes) == "table" and prev.recipes) or nil
  if type(rec) == "table" and next(rec) ~= nil then s.recipes = rec end
  return s
end

-- Take a snapshot now if the read is whole. Returns the snapshot in memory (the new one, or the one kept).
local function Take(how)
  local s = Read(how or "world")
  lastTake = (GetTime and GetTime()) or 0
  dirty = false
  -- the skills of a whole read replace the kept ones only when the game listed some (a collapsed header, or a client that
  -- answers late, gives an empty list: the last list seen is then the better record)
  if not Hollow(s) and (type(s.skills) ~= "table" or #s.skills == 0) and snap and type(snap.skills) == "table" and #snap.skills > 0 then
    s.skills = snap.skills
  end
  if not Hollow(s) then snap = WithBank(s) end
  return snap, s
end

-- true once the UI has been up long enough for the quest log to be whole (the prep module waits for this to answer)
function mod:Settled()
  local now = (GetTime and GetTime()) or 0
  return enabledAt ~= nil and now - enabledAt >= SETTLE
end

local function Tick()
  local now = (GetTime and GetTime()) or 0
  if not enabledAt or now - enabledAt < SETTLE then return end
  if mod.recipesChanged then mod.recipesChanged = nil; dirty = true end
  if not lastTake or (dirty and now - lastTake >= TAKE_GAP) or now - lastTake >= TAKE_EVERY then Take("world") end
end

-- The state for now: a fresh read when it is whole, else the last whole one. Written into QuestBookState (it reaches the
-- file at the next unload). Used by /qb sync now and by the prep module's fixed questions.
function mod:WriteState()
  local kept, fresh = Take("world")
  local s = kept or WithBank(fresh)
  if Hollow(s) and not Hollow(_G.QuestBookState) then return _G.QuestBookState end     -- never a hollow one over a whole one
  _G.QuestBookState = s
  return s
end

-- ---------------------------------------------------------------- when

local function Dirty() dirty = true end
mod.events.BAG_UPDATE_DELAYED = Dirty
mod.events.QUEST_LOG_UPDATE = Dirty
mod.events.PLAYER_MONEY = Dirty
mod.events.PLAYER_XP_UPDATE = Dirty
mod.events.PLAYER_LEVEL_UP = Dirty
mod.events.PLAYER_EQUIPMENT_CHANGED = Dirty
mod.events.ZONE_CHANGED_NEW_AREA = Dirty
mod.events.TRADE_SKILL_SHOW = CaptureSoon
mod.events.TRADE_SKILL_LIST_UPDATE = CaptureSoon
mod.events.SKILL_LINES_CHANGED = Dirty
mod.events.CHAT_MSG_SKILL = Dirty

local ticker
function mod:OnEnable()
  enabledAt = (GetTime and GetTime()) or 0
  if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(2, function() QB:Safe(mod, Tick) end) end
end
function mod:OnDisable()
  if ticker then ticker:Cancel(); ticker = nil end
end

mod.events.BANKFRAME_OPENED = function() ReadBank() end
mod.events.PLAYERBANKSLOTS_CHANGED = function() if bankSeen then ReadBank() end end
mod.events.PLAYER_LOGOUT = function(self)
  if not self.db.auto then return end
  -- The snapshot from memory. Only when there is none (the UI unloaded within seconds of loading) is the game read here,
  -- and that read is kept only if it is whole: at a real logout it is hollow, and then the stored state stays as it is.
  local s = snap
  if not s then
    local fresh = Read("unload")
    if not Hollow(fresh) then s = WithBank(fresh) end
  end
  if s then
    s.written = Call("time")
    _G.QuestBookState = s
  end
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
