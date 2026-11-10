-- QuestBook Loadout -- fills the action buttons from a plan written offline (4BI-41).
--
-- Cesar, 2026-11-10: "Can you assign abilities to action bar buttons from the configuration?" ... "yes, love the idea". He prepares his
-- UI at work and wants to come home and play. A settings file cannot say which ability sits in which button: the game keeps that on its
-- servers, per character. An addon can place abilities itself, out of combat, so this module carries a PLAN (in our saved settings,
-- written by the offline configurator, dev/elle-config) and applies it on a command.
--
--   /qb bars dump    save what the character has now (buttons, known spells, macros, key bindings) for the configurator to read
--   /qb bars check   say what the plan would change, and change nothing
--   /qb bars apply   fill the buttons from the plan (keeps what was there, for undo)
--   /qb bars undo    put back what the last apply replaced
--
-- A slot is the game's action slot number: (page - 1) * 12 + button. The plan (mod.db.plan):
--   { v = 1, slots = { [slot] = { kind = "spell", name = "Claw", id = 1082 } | { kind = "macro", name = "GoFast" }
--                              | { kind = "item", id = 858, name = "..." } | { kind = "empty" } } }
-- A spell is found by name first (the highest rank the character knows), then by id. A slot the plan does not mention is left alone.
--
-- Game functions used, and where their use on this client was seen (EllesmereUI's rank-upgrade code, read 2026-11-10, does the same
-- job for one spell): GetActionInfo, C_Spell.PickupSpell, PlaceAction, ClearCursor, InCombatLockdown, GetCursorInfo, and the
-- C_SpellBook walk (GetNumSpellBookSkillLines, GetSpellBookSkillLineInfo, GetSpellBookItemType, IsSpellBookItemPassive,
-- IsSpellBookItemLowRank, GetSpellBookItemInfo). PickupAction, PickupMacro, GetMacroIndexByName, GetNumMacros, GetMacroInfo,
-- GetBindingKey and the item pickup are from the documented API and were not seen in use there.
--
-- UNVERIFIED (client only): every one of them from this addon. Each call is checked for existence and wrapped, so a missing or
-- refusing function is reported, never an error.

local _, QB = ...

local mod = QB:NewModule("loadout", {
  -- plan, dump and undo are tables written at run time or by the configurator; no defaults
})

local MAX_SLOT = 180            -- 15 pages of 12
local MAX_LINES = 24            -- chat lines a report may take before it is summarised

local function Plain(v, kind)
  if type(issecretvalue) == "function" and issecretvalue(v) then return nil end
  if kind and type(v) ~= kind then return nil end
  return v
end

local function Where(slot)
  local page = math.floor((slot - 1) / 12) + 1
  return string.format("page %d button %d", page, slot - (page - 1) * 12)
end

-- call a global or namespaced function if it exists; returns ok, results...
local function Try(fn, ...)
  if type(fn) ~= "function" then return false end
  return pcall(fn, ...)
end

-- ---------------------------------------------------------------- reading the character

-- name -> id of the highest rank known, and a list for the dump
local function ReadSpells()
  local top, list = {}, {}
  local SB = _G.C_SpellBook
  if type(SB) ~= "table" or type(SB.GetNumSpellBookSkillLines) ~= "function" then return top, list, "no spellbook API" end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
  local okN, lines = Try(SB.GetNumSpellBookSkillLines)
  for line = 1, (okN and tonumber(lines)) or 0 do
    local okL, li = Try(SB.GetSpellBookSkillLineInfo, line)
    if okL and type(li) == "table" and not li.offSpecID then
      local first, count = tonumber(li.itemIndexOffset) or 0, tonumber(li.numSpellBookItems) or 0
      for slot = first + 1, first + count do
        local okT, kind = Try(SB.GetSpellBookItemType, slot, bank)
        local okP, passive = Try(SB.IsSpellBookItemPassive, slot, bank)
        local okR, low = Try(SB.IsSpellBookItemLowRank, slot, bank)
        if okT and kind == spellType and not (okP and passive) then
          local okI, info = Try(SB.GetSpellBookItemInfo, slot, bank)
          local id, name = okI and type(info) == "table" and Plain(info.spellID, "number"), okI and type(info) == "table" and Plain(info.name, "string")
          if id and name then
            if not (okR and low) then top[name] = id end
            list[#list + 1] = { id = id, name = name, low = (okR and low) and true or nil, line = Plain(li.name, "string") }
          end
        end
      end
    end
  end
  return top, list
end

local function SpellName(id)
  local okN, name = Try(_G.C_Spell and _G.C_Spell.GetSpellName, id)
  return okN and Plain(name, "string") or nil
end

-- what is in a slot now: { kind, id, name } or nil when empty
local function ReadSlot(slot)
  local ok, kind, id, sub = Try(_G.GetActionInfo, slot)
  kind = ok and Plain(kind, "string")
  if not kind then return nil end
  id = Plain(id)
  local rec = { kind = kind, id = id }
  if kind == "spell" and type(id) == "number" then rec.name = SpellName(id)
  elseif kind == "macro" then
    -- GetActionInfo gives a macro's index, or with subType "spell" the spell it shows; the name is what a plan uses
    local okM, name = Try(_G.GetMacroInfo, id)
    rec.name = okM and Plain(name, "string") or nil
    rec.sub = Plain(sub, "string")
  end
  return rec
end

local function Describe(rec)
  if not rec or rec.kind == "empty" then return "nothing" end
  return rec.kind .. " " .. tostring(rec.name or rec.id or "?")
end

local function Same(a, b)
  local ea, eb = (not a or a.kind == "empty"), (not b or b.kind == "empty")
  if ea or eb then return ea and eb end
  if a.kind ~= b.kind then return false end
  if a.kind == "macro" then return a.name ~= nil and a.name == b.name end
  return a.id ~= nil and a.id == b.id
end

-- ---------------------------------------------------------------- the plan

local function PlanSlots()
  local plan = mod.db and mod.db.plan
  if type(plan) ~= "table" or type(plan.slots) ~= "table" then return nil end
  local out = {}
  for slot, want in pairs(plan.slots) do
    slot = tonumber(slot)
    if slot and slot >= 1 and slot <= MAX_SLOT and slot == math.floor(slot) and type(want) == "table" and type(want.kind) == "string" then
      out[#out + 1] = { slot = slot, want = want }
    end
  end
  table.sort(out, function(a, b) return a.slot < b.slot end)
  return out
end

-- Turns a planned entry into the thing to place: { kind, id, name } or nil plus the reason it cannot be placed.
local function Resolve(want, top)
  if want.kind == "empty" then return { kind = "empty" } end
  if want.kind == "spell" then
    local id = (type(want.name) == "string" and top[want.name]) or nil
    if not id and type(want.id) == "number" then
      local SB = _G.C_SpellBook
      local okK, known = Try(SB and SB.IsSpellKnown, want.id)
      if okK and known then id = want.id end
    end
    if not id then return nil, "not learned" end
    return { kind = "spell", id = id, name = want.name or SpellName(id) }
  end
  if want.kind == "macro" then
    if type(want.name) ~= "string" then return nil, "no macro name" end
    local okM, index = Try(_G.GetMacroIndexByName, want.name)
    if not okM or not tonumber(index) or tonumber(index) == 0 then return nil, "no macro with that name" end
    return { kind = "macro", id = tonumber(index), name = want.name }
  end
  if want.kind == "item" then
    if type(want.id) ~= "number" then return nil, "no item id" end
    return { kind = "item", id = want.id, name = want.name }
  end
  return nil, "unknown kind '" .. tostring(want.kind) .. "'"
end

-- Puts one thing in one slot. Returns true, or false and why.
local function Place(slot, thing)
  if thing.kind == "empty" then
    if not ReadSlot(slot) then return true end
    if not Try(_G.PickupAction, slot) then return false, "PickupAction missing or refused" end
    Try(_G.ClearCursor)
    return true
  end
  local picked
  if thing.kind == "spell" then picked = Try(_G.C_Spell and _G.C_Spell.PickupSpell, thing.id)
  elseif thing.kind == "macro" then picked = Try(_G.PickupMacro, thing.id)
  elseif thing.kind == "item" then picked = Try(_G.C_Item and _G.C_Item.PickupItem, thing.id) or Try(_G.PickupItem, thing.id)
  end
  if not picked then Try(_G.ClearCursor); return false, "could not pick it up" end
  local okC, cursor = Try(_G.GetCursorInfo)
  if okC and cursor == nil then return false, "the cursor stayed empty" end
  if not Try(_G.PlaceAction, slot) then Try(_G.ClearCursor); return false, "PlaceAction missing or refused" end
  Try(_G.ClearCursor)              -- whatever the button held before is on the cursor now: drop it
  return true
end

local function Blocked()
  if QB:InCombat() then return "not in combat: the game blocks changing buttons during a fight" end
  local okC, cursor = Try(_G.GetCursorInfo)
  if okC and cursor ~= nil then return "something is on the cursor: drop it first" end
  if type(_G.GetActionInfo) ~= "function" or type(_G.PlaceAction) ~= "function" then return "this client has no GetActionInfo / PlaceAction" end
  return nil
end

local function Report(lines, tail)
  for i = 1, math.min(#lines, MAX_LINES) do QB:Say("  " .. lines[i]) end
  if #lines > MAX_LINES then QB:Say(string.format("  ... and %d more", #lines - MAX_LINES)) end
  if tail then QB:Say(tail) end
end

-- dry = true: only say what would happen
function mod:Run(dry)
  local entries = PlanSlots()
  if not entries or #entries == 0 then
    QB:Say("bars: no plan yet. Write one in the offline configurator and put QuestBook.lua back in SavedVariables.")
    return false
  end
  if not dry then
    local why = Blocked()
    if why then QB:Say("bars: " .. why); return false end
  end
  local top, _, noBook = ReadSpells()
  local lines, placed, same, skipped, failed = {}, 0, 0, 0, 0
  local before = {}
  for _, e in ipairs(entries) do
    local now = ReadSlot(e.slot)
    local thing, why = Resolve(e.want, top)
    if not thing then
      skipped = skipped + 1
      lines[#lines + 1] = string.format("%s: %s skipped (%s)", Where(e.slot), Describe(e.want), why)
    elseif Same(now, thing) then
      same = same + 1
    elseif dry then
      placed = placed + 1
      lines[#lines + 1] = string.format("%s: %s -> %s", Where(e.slot), Describe(now), Describe(thing))
    else
      before[e.slot] = now or { kind = "empty" }
      local ok, err = Place(e.slot, thing)
      if ok and Same(ReadSlot(e.slot), thing) then
        placed = placed + 1
      else
        failed = failed + 1
        lines[#lines + 1] = string.format("%s: %s FAILED (%s)", Where(e.slot), Describe(thing), err or "the button did not change")
      end
    end
  end
  if not dry and next(before) then mod.db.undo = { v = 1, slots = before } end
  local head = dry and "bars check" or "bars apply"
  QB:Say(string.format("%s: %d to place%s, %d already right, %d skipped%s%s", head, placed, dry and "" or " (done)", same, skipped,
    failed > 0 and (", " .. failed .. " FAILED") or "", noBook and (" | " .. noBook) or ""))
  Report(lines, (not dry and next(before)) and "bars: /qb bars undo puts the old buttons back" or nil)
  return failed == 0
end

function mod:Undo()
  local undo = self.db and self.db.undo
  if type(undo) ~= "table" or type(undo.slots) ~= "table" or not next(undo.slots) then QB:Say("bars: nothing to undo"); return false end
  local why = Blocked()
  if why then QB:Say("bars: " .. why); return false end
  local done, failed, lines = 0, 0, {}
  for slot, rec in pairs(undo.slots) do
    slot = tonumber(slot)
    if slot and type(rec) == "table" then
      local thing = rec
      if rec.kind == "macro" then                       -- a macro's index can move: find it again by name
        local okM, index = Try(_G.GetMacroIndexByName, rec.name)
        thing = (okM and tonumber(index) and tonumber(index) > 0) and { kind = "macro", id = tonumber(index), name = rec.name } or nil
      end
      local ok, err = false, "it no longer exists"
      if thing then ok, err = Place(slot, thing) end
      if ok then done = done + 1 else
        failed = failed + 1
        lines[#lines + 1] = string.format("%s: %s FAILED (%s)", Where(slot), Describe(rec), err or "?")
      end
    end
  end
  if failed == 0 then self.db.undo = nil end
  QB:Say(string.format("bars undo: %d button(s) put back%s", done, failed > 0 and (", " .. failed .. " FAILED") or ""))
  Report(lines)
  return failed == 0
end

-- The bindings the configurator may want to show: the game's own bar commands and EllesmereUI's two extra bars.
local BIND_PREFIXES = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON", "MULTIACTIONBAR2BUTTON", "MULTIACTIONBAR3BUTTON", "MULTIACTIONBAR4BUTTON",
  "MULTIACTIONBAR5BUTTON", "MULTIACTIONBAR6BUTTON", "MULTIACTIONBAR7BUTTON", "EUI_BAR9_BUTTON", "EUI_BAR10_BUTTON" }

function mod:Dump()
  local _, spells, noBook = ReadSpells()
  local slots, used = {}, 0
  for slot = 1, MAX_SLOT do
    local rec = ReadSlot(slot)
    if rec then slots[slot] = rec; used = used + 1 end
  end
  local macros = {}
  local okN, global, perChar = Try(_G.GetNumMacros)
  if okN then
    local function take(first, n)
      for i = first, first + (tonumber(n) or 0) - 1 do
        local okM, name, icon, body = Try(_G.GetMacroInfo, i)
        if okM and Plain(name, "string") then macros[#macros + 1] = { index = i, name = name, icon = Plain(icon), body = Plain(body, "string") } end
      end
    end
    take(1, global); take(121, perChar)
  end
  local binds = {}
  if type(_G.GetBindingKey) == "function" then
    for _, prefix in ipairs(BIND_PREFIXES) do
      for b = 1, 12 do
        local ok, k1, k2 = Try(_G.GetBindingKey, prefix .. b)
        k1, k2 = ok and Plain(k1, "string"), ok and Plain(k2, "string")
        if k1 then binds[prefix .. b] = { k1, k2 or nil } end
      end
    end
  end
  local okU, who = Try(_G.UnitName, "player")
  self.db.dump = { v = 1, char = okU and Plain(who, "string") or nil, version = QB.version, slots = slots, spells = spells, macros = macros, binds = binds }
  local nb = 0
  for _ in pairs(binds) do nb = nb + 1 end
  QB:Say(string.format("bars dump: %d button(s) in use, %d spell(s), %d macro(s), %d bound button(s) saved%s. Log out or /reload to write the file.",
    used, #spells, #macros, nb, noBook and (" | " .. noBook) or ""))
  return true
end

QB:RegisterSlash(mod, "bars", function(rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "dump" then mod:Dump()
  elseif sub == "check" then mod:Run(true)
  elseif sub == "apply" then mod:Run(false)
  elseif sub == "undo" then mod:Undo()
  else
    if sub ~= "" and sub ~= "status" then QB:Usage("/qb bars | dump | check | apply | undo") end
    local entries = PlanSlots()
    local undo = mod.db and mod.db.undo
    local nu = 0
    if type(undo) == "table" and type(undo.slots) == "table" then for _ in pairs(undo.slots) do nu = nu + 1 end end
    QB:Say(string.format("bars: plan %s | dump %s | undo %s | dump, check, apply, undo",
      entries and (#entries .. " button(s)") or "none", (mod.db and mod.db.dump) and "saved" or "none", nu > 0 and (nu .. " button(s)") or "none"))
  end
end, "bars: fill the action buttons from a plan written offline (dump, check, apply, undo)")
