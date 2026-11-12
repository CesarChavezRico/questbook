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
-- The plan may also carry macros to create first, so a seat that changes with the druid's form can be one macro instead of a paged
-- bar:   macros = { { name = "QB Top M", body = "#showtooltip\n/cast [form:bear] Bash; [noform] Regrowth" } }
-- A druid's forms are named in the macro text (form:bear, form:cat, also aquatic, travel, moonkin, and lists like form:bear/cat),
-- because their numbers depend on which forms the character has learned: at Cesar's first test (2026-11-10) Thara had no Aquatic
-- Form, so cat was form 2 and the plan's "form:3" matched nothing. The names become the character's own numbers when the plan is
-- applied; applying again after learning a form rewrites the macros.
-- They are made as character macros (18 at most), or rewritten when one of that name exists and its text differs.
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
local MACRO_ICON = "INV_MISC_QUESTIONMARK"   -- the question mark: with #showtooltip the button shows the spell's own icon
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
    -- For a macro, GetActionInfo's id is not reliable: seen on Forever (2026-11-10), a macro that currently resolves to a spell
    -- reports that spell's id (subType "spell"), not the macro's index. The button's text is the macro's name either way.
    local okT, text = Try(_G.GetActionText, slot)
    rec.name = okT and Plain(text, "string") or nil
    if not rec.name then
      local okM, name = Try(_G.GetMacroInfo, id)
      rec.name = okM and Plain(name, "string") or nil
    end
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

-- The plan in force: the one shipped in the addon folder (data/Plan.lua, updated by a git pull) if there is one, else the one in
-- our saved settings (how the first plan was delivered, 2026-11-10).
local function Plan()
  if type(QB.planData) == "table" then return QB.planData, "the addon folder" end
  local saved = mod.db and mod.db.plan
  if type(saved) == "table" then return saved, "saved settings" end
  return nil
end

local function PlanSlots()
  local plan = Plan()
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

-- Shapeshift forms by name -> the spell that is the form.
local FORM_SPELLS = { bear = { 5487, 9634 }, cat = { 768 }, aquatic = { 1066 }, travel = { 783 }, moonkin = { 24858 } }

-- name -> this character's stance number (a form it does not have is absent)
local function FormNumbers()
  local out = {}
  local okN, n = Try(_G.GetNumShapeshiftForms)
  for i = 1, (okN and tonumber(n)) or 0 do
    local okF, _, _, _, spellID = Try(_G.GetShapeshiftFormInfo, i)
    spellID = okF and Plain(spellID, "number")
    if spellID then
      for name, ids in pairs(FORM_SPELLS) do
        for _, id in ipairs(ids) do if id == spellID then out[name] = i end end
      end
    end
  end
  return out
end

-- "[form:bear/cat]" -> "[form:1/2]". A form the character lacks becomes 99, which is never true.
local function NameForms(body, forms)
  return (body:gsub("form:([%a/]+)", function(list)
    local parts = {}
    for name in list:gmatch("[^/]+") do
      if not FORM_SPELLS[name] then return nil end          -- not a list of form names: leave the text alone
      parts[#parts + 1] = tostring(forms[name] or 99)
    end
    return "form:" .. table.concat(parts, "/")
  end))
end

-- The first plan (v = 1, written by hand on 2026-11-10) used the usual numbers: 1 for bear, 3 for cat. Rewrite them as names, once.
local V1_FORMS = { ["1"] = "bear", ["3"] = "cat" }
local function UpgradePlan(plan)
  if type(plan) ~= "table" or plan.v ~= 1 then return end
  if type(plan.macros) == "table" then
    for _, m in ipairs(plan.macros) do
      if type(m) == "table" and type(m.body) == "string" then
        m.body = m.body:gsub("form:([%d/]+)", function(list)
          local parts = {}
          for num in list:gmatch("[^/]+") do
            if not V1_FORMS[num] then return nil end
            parts[#parts + 1] = V1_FORMS[num]
          end
          return "form:" .. table.concat(parts, "/")
        end)
      end
    end
  end
  plan.v = 2
end

-- The plan's macros: creates the missing ones, rewrites those whose text differs. Returns made, changed, lines of trouble.
-- dry = true only counts.
local function SyncMacros(dry)
  local plan = Plan()
  local list = plan and plan.macros
  local made, changed, lines = 0, 0, {}
  if type(list) ~= "table" then return made, changed, lines end
  local forms = FormNumbers()
  for _, planned in ipairs(list) do
    if type(planned) == "table" and type(planned.name) == "string" and planned.name ~= "" and type(planned.body) == "string" then
      local m = { name = planned.name, icon = planned.icon, body = NameForms(planned.body, forms) }
      local okI, index = Try(_G.GetMacroIndexByName, m.name)
      index = okI and tonumber(index) or 0
      if index > 0 then
        local okM, _, _, body = Try(_G.GetMacroInfo, index)
        if not (okM and Plain(body, "string") == m.body) then
          changed = changed + 1
          if not dry and not Try(_G.EditMacro, index, m.name, m.icon or MACRO_ICON, m.body) then
            changed = changed - 1
            lines[#lines + 1] = "macro " .. m.name .. ": could not be rewritten"
          end
        end
      else
        made = made + 1
        if not dry then
          local okC, newIndex = Try(_G.CreateMacro, m.name, m.icon or MACRO_ICON, m.body, true)
          if not okC or not tonumber(newIndex) then
            made = made - 1
            lines[#lines + 1] = "macro " .. m.name .. ": could not be created (18 character macros at most)"
          end
        end
      end
    end
  end
  return made, changed, lines
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
  local plan = Plan()
  local hasMacros = plan and type(plan.macros) == "table" and #plan.macros > 0
  if not entries or (#entries == 0 and not hasMacros) then
    QB:Say("bars: no plan yet. Write one in the offline configurator and put QuestBook.lua back in SavedVariables.")
    return false
  end
  if not dry then
    local why = Blocked()
    if why then QB:Say("bars: " .. why); return false end
  end
  UpgradePlan(plan)
  local top, _, noBook = ReadSpells()
  local madeMacros, changedMacros, lines = SyncMacros(dry)
  local placed, same, skipped, failed = 0, 0, 0, 0
  -- a macro the plan is about to create does not exist yet during a check: it will be there when the plan is applied
  local coming = {}
  if dry and type(plan.macros) == "table" then
    for _, m in ipairs(plan.macros) do if type(m) == "table" and type(m.name) == "string" then coming[m.name] = true end end
  end
  local before = {}
  for _, e in ipairs(entries) do
    local now = ReadSlot(e.slot)
    local thing, why = Resolve(e.want, top)
    if not thing and dry and e.want.kind == "macro" and coming[e.want.name] then thing = { kind = "macro", name = e.want.name } end
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
  QB:Say(string.format("%s: %d to place%s, %d already right, %d skipped%s%s%s", head, placed, dry and "" or " (done)", same, skipped,
    failed > 0 and (", " .. failed .. " FAILED") or "",
    (madeMacros + changedMacros > 0) and string.format(" | macros: %d new, %d rewritten", madeMacros, changedMacros) or "",
    noBook and (" | " .. noBook) or ""))
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

-- ---------------------------------------------------------------- the EllesmereUI layout, delivered by git pull
--
-- Cesar, 2026-11-10: "we need a better way for better cadence". Swapping EllesmereUI's settings file cost a logout and two file
-- transfers per change. The layout now ships in the addon folder (data/Layout.lua, written by dev/elle-config) as a list of values
-- to set in EllesmereUI's saved settings, and is applied here while the game runs:
--   /qb layout check   how many values differ from the layout
--   /qb layout apply   write them, remember what was there, and reload the UI so EllesmereUI reads them
--   /qb layout undo    put the remembered values back, and reload
-- A layout = { v = 1, name = "...", sets = { { path = { "profiles", "$profile", ... }, value = ... } }, removes = { { path = {...} } } }
-- "$profile" stands for EllesmereUI's active profile. This touches EllesmereUI's DATA only, the same values a hand edit of its
-- settings file would change; none of its code is called.
-- UNVERIFIED (client only): that EllesmereUI keeps values written this way through the reload and does not write its own back.

local function Copy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = Copy(x) end
  return out
end

local function Equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then
    if type(a) == "number" then return math.abs(a - b) < 1e-6 end
    return a == b
  end
  for k, x in pairs(a) do if not Equal(x, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

-- The settings a layout can be written into. Each is another addon's saved table, with its own way to name the profile in use.
--   ui    = EllesmereUI (data/Layout.lua, QB.layoutData): the profile is EllesmereUIDB.activeProfile
--   guide = RestedXP Guides (data/Guide.lua, QB.guideData, 4BI-42): an AceDB table, whose profile for this character is
--           RXPSettings.profileKeys["Name - Realm"]. RestedXP saves its windows' live positions when the UI unloads, so after
--           writing we ask it to move its windows to the saved positions (its LoadFramePositions, reached through the global
--           `RXP` it keeps "for debug purposes"); without that the reload would write the old places back over ours.
--   plates = MF Nameplates (data/Plates.lua, QB.platesData, 4BI-43): MFNameplatesDB, whose profile for this character is under
--           profileKeys. In Cesar's file (2026-11-12) the key there is "Thara Moonward", not the "Thara" UnitName gives, and we
--           do not know how the addon builds it; so: the key that is the name or starts with it, else the only key there is.
--           UNVERIFIED (client only): that MF Nameplates keeps values written this way through the reload.
local function CharKey()
  local okN, name = Try(_G.UnitName, "player")
  local okR, realm = Try(_G.GetRealmName)
  if okN and okR and Plain(name, "string") and Plain(realm, "string") then return name .. " - " .. realm end
  return nil
end

local function PlatesProfile(root)
  local keys = root.profileKeys
  if type(keys) ~= "table" then return "Default" end
  local okN, name = Try(_G.UnitName, "player")
  name = okN and Plain(name, "string") or nil
  local only, count, starts = nil, 0, nil
  for k, v in pairs(keys) do
    if type(k) == "string" and type(v) == "string" then
      count = count + 1
      only = v
      if name and k == name then return v end
      if name and k:sub(1, #name + 1) == name .. " " then starts = v end
    end
  end
  return starts or (count == 1 and only) or "Default"
end

local TARGETS = {
  { id = "ui", label = "EllesmereUI", data = function() return QB.layoutData end, root = function() return _G.EllesmereUIDB end,
    profile = function(root) return root.activeProfile or "Default" end },
  { id = "guide", label = "RestedXP", data = function() return QB.guideData end, root = function() return _G.RXPSettings end,
    profile = function(root)
      local key = CharKey()
      local name = key and type(root.profileKeys) == "table" and root.profileKeys[key]
      return name or key or "Default"
    end,
    -- v0.28.4: the profile table RestedXP is using right now. In the first client test (2026-11-11) the values written by
    -- name into RXPSettings.profiles did not reach it (RestedXP still said "RXP Blue" while our check said "already in
    -- place"), so when its table can be reached the values go straight into it, and the name is only the fallback.
    live = function()
      local rxp = _G.RXP
      local p = type(rxp) == "table" and type(rxp.settings) == "table" and rxp.settings.profile
      return type(p) == "table" and p or nil
    end,
    after = function()
      local rxp = _G.RXP
      if type(rxp) == "table" and type(rxp.settings) == "table" and type(rxp.settings.LoadFramePositions) == "function" then
        if pcall(rxp.settings.LoadFramePositions, rxp.settings) then return true end
      end
      return false, "RestedXP's windows could not be moved from here: they keep their old place until you move them"
    end },
  { id = "plates", label = "MF Nameplates", data = function() return QB.platesData end, root = function() return _G.MFNameplatesDB end,
    profile = PlatesProfile },
}

-- The table that holds the last key of a path, and that key. create = true makes the tables on the way.
local function Reach(root, path, create, profile, live)
  local t, from = root, 1
  if live and path[1] == "profiles" and path[2] == "$profile" and #path > 2 then t, from = live, 3 end
  for i = from, #path - 1 do
    local k = path[i]
    if k == "$profile" then k = profile end
    local nx = t[k]
    if type(nx) ~= "table" then
      if not create then return nil end
      nx = {}
      t[k] = nx
    end
    t = nx
  end
  local last = path[#path]
  if last == "$profile" then last = profile end
  return t, last
end

local function LayoutChanges(root, data, profile, live)
  local n = 0
  for _, s in ipairs(data.sets or {}) do
    local t, k = Reach(root, s.path, false, profile, live)
    if not t or not Equal(t[k], s.value) then n = n + 1 end
  end
  for _, r in ipairs(data.removes or {}) do
    local t, k = Reach(root, r.path, false, profile, live)
    if t and t[k] ~= nil then n = n + 1 end
  end
  return n
end

local function Reload()
  QB:Say("layout: reloading the UI")
  if not Try(_G.ReloadUI) then QB:Say("layout: type /reload to finish") end
end

function mod:LayoutRun(dry)
  local any, wrote, parts = false, 0, {}
  for _, target in ipairs(TARGETS) do
    local data = target.data()
    if type(data) == "table" then
      any = true
      local root = target.root()
      local total = #(data.sets or {}) + #(data.removes or {})
      if type(root) ~= "table" then
        QB:Say(string.format("layout: %s's settings are not loaded, so \"%s\" is skipped", target.label, tostring(data.name or "?")))
      else
        local profile = target.profile(root)
        local live = target.live and target.live() or nil
        local n = LayoutChanges(root, data, profile, live)
        if dry then
          QB:Say(string.format("layout check: %s, \"%s\": %d of %d value(s) differ", target.label, tostring(data.name or "?"), n, total))
        elseif QB:InCombat() then
          QB:Say("layout: not in combat"); return false
        elseif n == 0 then
          QB:Say(string.format("layout: %s already in place", target.label))
        else
          local undo = {}
          for _, s in ipairs(data.sets or {}) do
            local t, k = Reach(root, s.path, true, profile, live)
            if not Equal(t[k], s.value) then
              undo[#undo + 1] = { path = Copy(s.path), had = t[k] ~= nil, old = Copy(t[k]) }
              t[k] = Copy(s.value)
            end
          end
          for _, r in ipairs(data.removes or {}) do
            local t, k = Reach(root, r.path, false, profile, live)
            if t and t[k] ~= nil then
              undo[#undo + 1] = { path = Copy(r.path), had = true, old = Copy(t[k]) }
              t[k] = nil
            end
          end
          parts[#parts + 1] = { id = target.id, profile = profile, name = data.name, list = undo }
          wrote = wrote + #undo
          QB:Say(string.format("layout apply: %s, \"%s\": %d value(s) written", target.label, tostring(data.name or "?"), #undo))
          if target.after then
            local ok, why = target.after()
            if not ok and why then QB:Say("layout: " .. why) end
          end
        end
      end
    end
  end
  if not any then QB:Say("layout: no layout in the addon folder (data/)"); return false end
  if dry then return true end
  if wrote == 0 then return true end
  mod.db.layoutUndo = { v = 2, parts = parts }
  QB:Say("layout: /qb layout undo puts the old values back")
  Reload()
  return true
end

function mod:LayoutUndo()
  local u = mod.db and mod.db.layoutUndo
  local parts = type(u) == "table" and (u.parts or (type(u.list) == "table" and { { id = "ui", profile = u.profile, list = u.list } })) or nil
  if type(parts) ~= "table" or #parts == 0 then QB:Say("layout: nothing to undo"); return false end
  if QB:InCombat() then QB:Say("layout: not in combat"); return false end
  local done = 0
  for _, part in ipairs(parts) do
    for _, target in ipairs(TARGETS) do
      if target.id == part.id and type(part.list) == "table" then
        local root = target.root()
        if type(root) ~= "table" then
          QB:Say(string.format("layout: %s's settings are not loaded, its values stay as they are", target.label))
        else
          local profile = part.profile or target.profile(root)
          local live = target.live and target.live() or nil
          for i = #part.list, 1, -1 do
            local e = part.list[i]
            local t, k = Reach(root, e.path, true, profile, live)
            if e.had then t[k] = Copy(e.old) else t[k] = nil end
            done = done + 1
          end
          if target.after then target.after() end
        end
      end
    end
  end
  QB:Say(string.format("layout undo: %d value(s) put back", done))
  mod.db.layoutUndo = nil
  Reload()
  return true
end

QB:RegisterSlash(mod, "layout", function(rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "check" then mod:LayoutRun(true)
  elseif sub == "apply" then mod:LayoutRun(false)
  elseif sub == "undo" then mod:LayoutUndo()
  else
    if sub ~= "" and sub ~= "status" then QB:Usage("/qb layout | check | apply | undo") end
    local have = {}
    for _, target in ipairs(TARGETS) do
      local data = target.data()
      if type(data) == "table" then
        have[#have + 1] = string.format("%s \"%s\", %d value(s)", target.label, tostring(data.name or "?"), #(data.sets or {}) + #(data.removes or {}))
      end
    end
    local u = mod.db and mod.db.layoutUndo
    local nu = 0
    if type(u) == "table" then
      if type(u.parts) == "table" then for _, part in ipairs(u.parts) do nu = nu + #(part.list or {}) end
      elseif type(u.list) == "table" then nu = #u.list end
    end
    QB:Say(string.format("layout: %s | undo %s | check, apply, undo", #have > 0 and table.concat(have, "; ") or "none in the addon folder",
      nu > 0 and (nu .. " value(s)") or "none"))
  end
end, "layout: put the layouts shipped with the addon in place: EllesmereUI, RestedXP (check, apply, undo)")

QB:RegisterSlash(mod, "bars", function(rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "dump" then mod:Dump()
  elseif sub == "check" then mod:Run(true)
  elseif sub == "apply" then mod:Run(false)
  elseif sub == "undo" then mod:Undo()
  else
    if sub ~= "" and sub ~= "status" then QB:Usage("/qb bars | dump | check | apply | undo") end
    local entries = PlanSlots()
    local _, from = Plan()
    local undo = mod.db and mod.db.undo
    local nu = 0
    if type(undo) == "table" and type(undo.slots) == "table" then for _ in pairs(undo.slots) do nu = nu + 1 end end
    QB:Say(string.format("bars: plan %s | dump %s | undo %s | dump, check, apply, undo",
      entries and (#entries .. " button(s) from " .. tostring(from)) or "none", (mod.db and mod.db.dump) and "saved" or "none", nu > 0 and (nu .. " button(s)") or "none"))
  end
end, "bars: fill the action buttons from a plan written offline (dump, check, apply, undo)")
