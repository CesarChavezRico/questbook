-- The action bar plan (4BI-41): dump, check, apply, undo. The game's action, spellbook and macro functions are stand-ins that follow
-- the documented shapes; this checks OUR logic and that a missing or refusing function is reported, not what the client really does.
local slots = { [1] = { "spell", 100 }, [2] = { "macro", 1 }, [13] = { "spell", 300 } }
local cursor
local macros = { [1] = { "GoFast", 134400, "/cast Travel Form" }, [121] = { "Panic", 134400, "/cast Bear Form" } }
local names = { [100] = "Wrath", [101] = "Wrath", [200] = "Claw", [300] = "Moonfire", [400] = "Rake" }
local book = {  -- one skill line: Wrath rank 1 (low), Wrath rank 2, Claw, Moonfire, a passive
  { id = 100, name = "Wrath", low = true }, { id = 101, name = "Wrath" }, { id = 200, name = "Claw" }, { id = 300, name = "Moonfire" },
  { id = 900, name = "Thick Hide", passive = true },
}
Enum = Enum or {}
Enum.SpellBookSpellBank = { Player = 0 }; Enum.SpellBookItemType = { Spell = 1 }
C_SpellBook = {
  GetNumSpellBookSkillLines = function() return 1 end,
  GetSpellBookSkillLineInfo = function() return { name = "Balance", itemIndexOffset = 0, numSpellBookItems = #book } end,
  GetSpellBookItemType = function() return 1 end,
  IsSpellBookItemPassive = function(i) return book[i].passive == true end,
  IsSpellBookItemLowRank = function(i) return book[i].low == true end,
  GetSpellBookItemInfo = function(i) return { spellID = book[i].id, name = book[i].name } end,
  IsSpellKnown = function(id) for _, b in ipairs(book) do if b.id == id then return true end end return false end,
}
C_Spell = { GetSpellName = function(id) return names[id] end, PickupSpell = function(id) cursor = { "spell", id } end }
function GetActionInfo(slot) local s = slots[slot]; if s then return s[1], s[2] end end
function GetCursorInfo() if cursor then return cursor[1], cursor[2] end end
function ClearCursor() cursor = nil end
function PickupAction(slot) cursor = slots[slot]; slots[slot] = nil end
function PlaceAction(slot) local old = slots[slot]; slots[slot] = cursor; cursor = old end
function PickupMacro(i) if macros[i] then cursor = { "macro", i } end end
function GetMacroIndexByName(n) for i, m in pairs(macros) do if m[1] == n then return i end end return 0 end
function GetNumMacros() return 1, 1 end
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
function GetBindingKey(cmd) if cmd == "ACTIONBUTTON1" then return "F5" end if cmd == "EUI_BAR9_BUTTON2" then return "MOUSEWHEELUP", "F9" end end
function UnitName() return "Thara" end

__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
local M = QB.modules.loadout
assert(M and M.active, "the module is on")

-- 1. no plan: says so, changes nothing
slash("bars apply")
assert(said("no plan yet"), "apply without a plan explains")
assert(slots[1][2] == 100, "nothing changed")

-- 2. dump: buttons, spells with rank marks, macros from both ranges, bindings
slash("bars dump")
local d = M.db.dump
assert(d and d.char == "Thara" and d.slots[1].kind == "spell" and d.slots[1].name == "Wrath" and d.slots[2].name == "GoFast", "dump: buttons")
assert(#d.spells == 4 and d.spells[1].low == true and d.spells[2].low == nil, "dump: 4 active spells, the low rank marked, the passive left out")
assert(#d.macros == 2 and d.macros[2].name == "Panic", "dump: both macro ranges")
assert(d.binds.ACTIONBUTTON1[1] == "F5" and d.binds.EUI_BAR9_BUTTON2[2] == "F9", "dump: bindings, both keys")
assert(said("bars dump: 3 button"), "dump reports")

-- 3. a plan: the highest known rank by name, a macro, an empty, an unlearned spell, a missing macro, an untouched slot
M.db.plan = { v = 1, slots = {
  [1] = { kind = "spell", name = "Wrath" },          -- rank 2 replaces rank 1
  [2] = { kind = "spell", name = "Claw" },           -- replaces the macro
  [3] = { kind = "macro", name = "Panic" },          -- into an empty button
  [13] = { kind = "empty" },                         -- clears Moonfire
  [14] = { kind = "spell", name = "Rake" },          -- not learned
  [15] = { kind = "macro", name = "Nope" },          -- no such macro
  [25] = { kind = "spell", name = "Moonfire", id = 300 },
  ["x"] = { kind = "spell", name = "Wrath" },        -- a bad key is ignored
  [999] = { kind = "spell", name = "Wrath" },        -- out of range is ignored
} }
slash("bars check")
local out = __take()
local text = table.concat(out, "\n")
assert(text:find("bars check: 5 to place, 0 already right, 2 skipped"), "check counts: " .. out[1])
assert(text:find("page 2 button 2: spell Rake skipped %(not learned%)") and text:find("no macro with that name"), "check names the skipped ones")
assert(text:find("page 1 button 1: spell Wrath %-> spell Wrath"), "check shows the rank swap")
assert(slots[1][2] == 100 and slots[13] and not slots[3], "check changed nothing")

-- 4. apply
slash("bars apply")
text = table.concat(__take(), "\n")
assert(text:find("bars apply: 5 to place %(done%), 0 already right, 2 skipped") and not text:find("FAILED"), "apply: " .. text)
assert(slots[1][2] == 101 and slots[2][1] == "spell" and slots[2][2] == 200 and slots[3][1] == "macro" and slots[3][2] == 121, "the buttons hold the plan")
assert(slots[13] == nil and slots[25][2] == 300 and slots[14] == nil, "cleared, placed by id, and the unlearned one left alone")
assert(cursor == nil, "nothing left on the cursor")
-- again: everything is already right
slash("bars apply")
assert(said("0 to place %(done%), 5 already right"), "a second apply changes nothing")

-- 5. undo puts back what the FIRST apply replaced (the second one replaced nothing and must not wipe the record)
slash("bars undo")
text = table.concat(__take(), "\n")
assert(text:find("bars undo: 5 button%(s%) put back"), "undo: " .. text)
assert(slots[1][2] == 100 and slots[2][1] == "macro" and slots[2][2] == 1 and slots[3] == nil and slots[13][2] == 300 and slots[25] == nil, "back to the start")
slash("bars undo"); assert(said("nothing to undo"), "undo is used up")

-- 6. refusals: in combat, and with something on the cursor
__combat = true
slash("bars apply"); assert(said("not in combat"), "refuses in combat"); assert(slots[1][2] == 100, "and changed nothing")
__combat = false
cursor = { "item", 5 }
slash("bars apply"); assert(said("on the cursor"), "refuses with a full cursor")
cursor = nil

-- 7. a client that refuses PlaceAction: reported per button, no error, and no undo record for buttons that did not change
local realPlace = PlaceAction
PlaceAction = function() error("blocked") end
slash("bars apply")
text = table.concat(__take(), "\n")
assert(text:find("FAILED") and text:find("PlaceAction missing or refused"), "a refused placement is reported: " .. text)
PlaceAction = realPlace
assert(cursor == nil, "the cursor was cleared after the failure")

-- 8. a client without the functions at all
local a, p = GetActionInfo, PlaceAction
GetActionInfo, PlaceAction = nil, nil
slash("bars apply"); assert(said("no GetActionInfo"), "says the client lacks the functions")
GetActionInfo, PlaceAction = a, p

-- 9. macros in the plan: created as character macros, rewritten when the text differs, and placeable in the same apply
function CreateMacro(name, icon, body, perChar)
  assert(perChar == true, "character macros")
  local i = 122; while macros[i] do i = i + 1 end
  if i > 138 then error("full") end
  macros[i] = { name, icon, body }; return i
end
function EditMacro(i, name, icon, body) macros[i] = { name, icon, body }; return i end
M.db.plan = { v = 1,
  macros = { { name = "QB Top M", body = "#showtooltip\n/cast [form:1] Bash; [noform] Regrowth" }, { name = "Panic", body = "/cast Dire Bear Form" } },
  slots = { [30] = { kind = "macro", name = "QB Top M" }, [31] = { kind = "macro", name = "Panic" } } }
slash("bars check")
text = table.concat(__take(), "\n")
assert(text:find("bars check: 2 to place, 0 already right, 0 skipped | macros: 1 new, 1 rewritten", 1, true), "check counts the macros and trusts the one to come: " .. text)
assert(GetMacroIndexByName("QB Top M") == 0 and macros[121][3] == "/cast Bear Form", "check created and rewrote nothing")
slash("bars apply")
text = table.concat(__take(), "\n")
assert(text:find("2 to place (done)", 1, true) and text:find("macros: 1 new, 1 rewritten", 1, true) and not text:find("FAILED"), "apply with macros: " .. text)
local qi = GetMacroIndexByName("QB Top M")
assert(qi > 121 and macros[qi][3]:find("Bash") and macros[121][3] == "/cast Dire Bear Form", "created one, rewrote the other")
assert(slots[30][1] == "macro" and slots[30][2] == qi and slots[31][2] == 121, "and both are on their buttons")
slash("bars apply"); assert(said("0 to place %(done%), 2 already right, 0 skipped$"), "a second apply touches no macro")
-- a client that cannot create macros: reported, and the button is skipped
M.db.plan.macros[3] = { name = "QB New", body = "/cast Wrath" }; M.db.plan.slots[32] = { kind = "macro", name = "QB New" }
local realCreate = CreateMacro; CreateMacro = function() error("no") end
slash("bars apply")
text = table.concat(__take(), "\n")
assert(text:find("macro QB New: could not be created") and text:find("no macro with that name"), "a failed creation is reported: " .. text)
CreateMacro = realCreate
-- 10. forms by name: the numbers are this character's own. Here: bear 1, cat 2 (no Aquatic Form yet).
local formSpells = { 5487, 768 }
function GetNumShapeshiftForms() return #formSpells end
function GetShapeshiftFormInfo(i) return 132276, false, true, formSpells[i] end
M.db.plan = { v = 2, slots = {},
  macros = { { name = "QB F", body = "/cast [form:cat] Rake; [form:bear/cat] Feral Charge; [form:travel] X; [noform] Wrath; [mod:shift] Y" } } }
slash("bars apply"); __take()
local body = macros[GetMacroIndexByName("QB F")][3]
assert(body == "/cast [form:2] Rake; [form:1/2] Feral Charge; [form:99] X; [noform] Wrath; [mod:shift] Y", "names become numbers: " .. body)
-- learning Aquatic Form moves cat to 3: applying again rewrites the macro
formSpells = { 5487, 1066, 768 }
slash("bars apply")
assert(said("macros: 0 new, 1 rewritten"), "a new form rewrites the macro")
assert(macros[GetMacroIndexByName("QB F")][3]:find("[form:3] Rake; [form:1/3] Feral Charge", 1, true), "cat is 3 now")
-- the first plan (v 1) wrote 1 for bear and 3 for cat: upgraded to names once, then numbered for this character
formSpells = { 5487, 768 }
M.db.plan = { v = 1, slots = {}, macros = { { name = "QB Old", body = "/cast [form:3] Rake; [form:1/3] Feral Charge; [form:1] Bash; [noform] Wrath" } } }
slash("bars apply"); __take()
assert(M.db.plan.v == 2 and M.db.plan.macros[1].body == "/cast [form:cat] Rake; [form:bear/cat] Feral Charge; [form:bear] Bash; [noform] Wrath", "v1 upgraded: " .. M.db.plan.macros[1].body)
assert(macros[GetMacroIndexByName("QB Old")][3] == "/cast [form:2] Rake; [form:1/2] Feral Charge; [form:1] Bash; [noform] Wrath", "and written with this character's numbers")
slash("bars apply"); assert(said("0 to place %(done%), 0 already right, 0 skipped$"), "the upgrade happens once and then nothing changes")

M.db.plan.macros = nil; M.db.plan.slots = { [1] = { kind = "spell", name = "Wrath" } }

slash("bars"); assert(said("bars: plan 1 button"), "status counts the valid plan entries")
slash("bars what"); assert(said("/qb bars .*dump.*check.*apply.*undo"), "usage")
print("loadout: ok")
