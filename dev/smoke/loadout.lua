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
-- the addon ships a plan and a layout (data/): they loaded, and are set aside so the scenarios below use their own
assert(type(QB.planData) == "table" and QB.planData.v == 2 and next(QB.planData.slots), "data/Plan.lua loaded")
assert(type(QB.layoutData) == "table" and #QB.layoutData.sets > 0, "data/Layout.lua loaded")
assert(type(QB.guideData) == "table" and #QB.guideData.sets > 0, "data/Guide.lua loaded")
local shippedPlan, shippedLayout, shippedGuide = QB.planData, QB.layoutData, QB.guideData
QB.planData, QB.layoutData, QB.guideData = nil, nil, nil

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

-- 11. a macro button as the Forever client reports it (seen 2026-11-10): a macro that resolves to a spell gives that spell's id,
-- not the macro's index, so the macro is recognised by the button's text
local plainInfo = GetActionInfo
function GetActionText(s) local x = slots[s]; if x and x[1] == "macro" and macros[x[2]] then return macros[x[2]][1] end end
function GetActionInfo(s) local x = slots[s]; if x and x[1] == "macro" then return "macro", 414924, "spell" end return plainInfo(s) end
M.db.plan = { v = 2, macros = { { name = "QB R", body = "/cast Rip" } }, slots = { [40] = { kind = "macro", name = "QB R" } } }
slash("bars apply")
text = table.concat(__take(), "\n")
assert(text:find("1 to place (done)", 1, true) and not text:find("FAILED"), "a resolving macro is placed without a false failure: " .. text)
slash("bars apply"); assert(said("0 to place %(done%), 1 already right"), "and is recognised as already there")
slash("bars dump"); __take()
assert(M.db.dump.slots[40].kind == "macro" and M.db.dump.slots[40].name == "QB R", "the dump names the macro")
GetActionInfo = plainInfo; GetActionText = nil

M.db.plan.macros = nil; M.db.plan.slots = { [1] = { kind = "spell", name = "Wrath" } }

-- 12. a plan in the addon folder wins over the saved one, and the status says where the plan comes from
slash("bars"); assert(said("bars: plan 1 button%(s%) from saved settings"), "status: the saved plan")
QB.planData = { v = 2, slots = { [5] = { kind = "spell", name = "Claw" }, [6] = { kind = "spell", name = "Moonfire" } } }
slash("bars"); assert(said("bars: plan 2 button%(s%) from the addon folder"), "status: the shipped plan")
slash("bars apply"); __take()
assert(slots[5] and slots[5][2] == 200 and slots[6][2] == 300, "the shipped plan was applied")
QB.planData = nil

-- 13. the layout: values written into EllesmereUI's saved settings, remembered, reloaded; undo puts them back
local reloads = 0
ReloadUI = function() reloads = reloads + 1 end
slash("layout check"); assert(said("no layout in the addon folder"), "no layout: says so")
QB.layoutData = { v = 1, name = "test", sets = {
    { path = { "profiles", "$profile", "addons", "Bars", "MainBar", "x" }, value = 12.5 },
    { path = { "profiles", "$profile", "addons", "Bars", "MainBar", "shape" }, value = "circle" },
    { path = { "profiles", "$profile", "addons", "New", "list" }, value = { 1, 2, { deep = true } } },
    { path = { "top" }, value = true },
  }, removes = { { path = { "profiles", "$profile", "addons", "Bars", "MainBar", "old" } }, { path = { "profiles", "$profile", "nothing", "here" } } } }
slash("layout check"); assert(said("EllesmereUI's settings are not loaded, so \"test\" is skipped"), "no EllesmereUI: says so")
EllesmereUIDB = { activeProfile = "Mine", profiles = { Mine = { addons = { Bars = { MainBar = { x = 1, shape = "circle", old = 7, keep = "me" } } } } } }
slash("layout check"); assert(said('layout check: EllesmereUI, "test": 4 of 6 value%(s%) differ'), "check counts what differs")
assert(EllesmereUIDB.profiles.Mine.addons.Bars.MainBar.x == 1 and reloads == 0, "check wrote nothing")
__combat = true; slash("layout apply"); assert(said("not in combat"), "refuses in combat"); __combat = false
slash("layout apply")
text = table.concat(__take(), "\n")
assert(text:find('layout apply: EllesmereUI, "test": 4 value(s) written', 1, true) and reloads == 1, "apply writes and reloads: " .. text)
local mb = EllesmereUIDB.profiles.Mine.addons.Bars.MainBar
assert(mb.x == 12.5 and mb.old == nil and mb.keep == "me" and EllesmereUIDB.top == true, "the values are in, the rest untouched")
assert(EllesmereUIDB.profiles.Mine.addons.New.list[3].deep == true and EllesmereUIDB.profiles.Mine.nothing == nil, "tables are created, and a remove creates none")
QB.layoutData.sets[3].value[3].deep = false
assert(EllesmereUIDB.profiles.Mine.addons.New.list[3].deep == true, "the settings hold a copy, not the layout's own table")
QB.layoutData.sets[3].value[3].deep = true
slash("layout apply"); assert(said("already in place"), "a second apply does nothing"); assert(reloads == 1, "and does not reload")
slash("layout undo")
assert(said("layout undo: 4 value%(s%) put back"), "undo reports")
mb = EllesmereUIDB.profiles.Mine.addons.Bars.MainBar
assert(mb.x == 1 and mb.old == 7 and EllesmereUIDB.top == nil and EllesmereUIDB.profiles.Mine.addons.New.list == nil and reloads == 2, "undo restores every value and reloads")
slash("layout undo"); assert(said("nothing to undo"), "undo is used up")
-- the layout that ships today fits a settings table it has never seen, and a second check finds nothing left
QB.layoutData = shippedLayout
EllesmereUIDB = { activeProfile = "Default", profiles = { Default = { addons = {} } } }
slash("layout apply"); __take()
slash("layout check"); assert(said(": 0 of %d+ value%(s%) differ"), "the shipped layout applies cleanly")
slash("layout"); assert(said('layout: EllesmereUI "'), "status names the layout")
QB.layoutData, EllesmereUIDB = nil, nil

-- 14. a second addon's settings: RestedXP Guides (4BI-42). Its table is an AceDB one: the profile for this character is named by
-- profileKeys["Name - Realm"]. After writing, its windows are asked to move (it saves their live places when the UI unloads).
function GetRealmName() return "PvP" end
local moved = 0
local r0 = reloads
QB.guideData = shippedGuide
slash("layout check"); assert(said("RestedXP's settings are not loaded"), "RestedXP absent: skipped, said so")
slash("layout apply"); __take(); assert(reloads == r0, "nothing to write anywhere: no reload")
RXPSettings = { profileKeys = { ["Thara - PvP"] = "Leveling" }, profiles = { Leveling = { enableQuestAutomation = true, framePositions = { arrowFrame = { { "TOP", "UIParent", "TOP", 0, 0 } } } }, Other = {} } }
RXP = { settings = { LoadFramePositions = function(self) assert(self == RXP.settings, "called as a method"); moved = moved + 1 end } }
slash("layout check"); assert(said('layout check: RestedXP, "guide in the upper left'), "check names RestedXP")
slash("layout apply")
text = table.concat(__take(), "\n")
assert(text:find("layout apply: RestedXP,", 1, true) and reloads == r0 + 1 and moved == 1, "apply writes, moves the windows once, reloads: " .. text)
local prof = RXPSettings.profiles.Leveling
assert(prof.enableQuestAutomation == false and prof.enableGossipAutomation == false and prof.activeTheme == "QuestBook", "the choices are in this character's profile")
assert(prof.framePositions.RXPFrame[1][1] == "TOPLEFT" and prof.framePositions.RXPFrame[1][2] == "UIParent" and prof.framePositions.RXPFrame[1][5] < 0, "the guide window goes to the upper left")
assert(prof.framePositions.arrowFrame[1][1] == "TOP", "a window we do not place keeps its position")
assert(next(RXPSettings.profiles.Other) == nil, "another profile is untouched")
slash("layout undo"); __take()
assert(prof.enableQuestAutomation == true and prof.activeTheme == nil and prof.framePositions.RXPFrame == nil and moved == 2 and reloads == r0 + 2, "undo restores RestedXP's values and moves the windows back")
-- both at once, RestedXP without the helper global: the values are written, and the note says the windows did not move
RXP = nil
QB.layoutData = { v = 1, name = "ui", sets = { { path = { "top" }, value = 1 } } }
EllesmereUIDB = { activeProfile = "Default", profiles = {} }
slash("layout apply")
text = table.concat(__take(), "\n")
assert(text:find("EllesmereUI,", 1, true) and text:find("RestedXP,", 1, true) and text:find("could not be moved", 1, true) and reloads == r0 + 3, "both targets in one run: " .. text)
slash("layout"); assert(said("EllesmereUI \"ui\", 1 value%(s%); RestedXP "), "status lists both")
slash("layout undo"); __take()
assert(EllesmereUIDB.top == nil and RXPSettings.profiles.Leveling.activeTheme == nil, "one undo covers both")
-- a character with no profile entry yet: AceDB's own default name, "Name - Realm"
RXPSettings = { profiles = {} }
slash("layout apply"); __take()
assert(RXPSettings.profiles["Thara - PvP"] and RXPSettings.profiles["Thara - PvP"].activeTheme == "QuestBook", "falls back to the character's own profile name")
QB.layoutData, QB.guideData, EllesmereUIDB, RXPSettings = nil, nil, nil, nil
-- the plan that ships today is well formed: every macro seat names a macro it defines
local names = {}
for _, m in ipairs(shippedPlan.macros) do names[m.name] = true; assert(#m.name <= 16 and #m.body <= 255, "macro limits: " .. m.name) end
for slot, w in pairs(shippedPlan.slots) do
  assert(type(slot) == "number" and slot >= 1 and slot <= 180, "slot range")
  if w.kind == "macro" then assert(names[w.name], "macro seat without a macro: " .. tostring(w.name)) end
end

M.db.plan.slots = { [1] = { kind = "spell", name = "Wrath" } }
slash("bars"); assert(said("bars: plan 1 button"), "status counts the valid plan entries")
slash("bars what"); assert(said("/qb bars .*dump.*check.*apply.*undo"), "usage")
print("loadout: ok")
