-- v0.42.0 (4BI-50): the action buttons, macros and key bindings in the state, and the fixed question `q bars`.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, P, L = QB.modules.sync, QB.modules.prep, QB.modules.loadout
assert(S and S.active and P and P.active and L and L.active, "sync, prep and loadout modules on")
time = time or os.time
local clock = 5000
GetTime = function() return clock end
local function A(body) return (P:Answer(body)) end
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
  GetContainerItemInfo = function(b, s) if b == 0 and s == 1 then return { itemID = 2589, stackCount = 1, quality = 1 } end end }
C_Item = { GetItemInfo = function() return "Linen Cloth", nil, 1, nil, nil, "Trade Goods", nil, nil, nil, nil, 13 end }
function UnitXPMax() return 1000 end
function UnitXP() return 10 end

-- the game: three buttons in use (a spell, a macro, an item), two macros, two bound buttons
local slots = { [1] = { "spell", 5176 }, [2] = { "macro", 121 }, [61] = { "item", 858 } }
local macros = { [1] = { "Cat", 132115, "/cast [form:3] Claw; Cat Form" }, [121] = { "Heal", 136041, "/cast [@mouseover,help][] Healing Touch" } }
function GetActionInfo(slot) local s = slots[slot]; if s then return s[1], s[2] end end
function GetActionText(slot) local s = slots[slot]; if s and s[1] == "macro" and macros[s[2]] then return macros[s[2]][1] end end
function GetNumMacros() return 1, 1 end
function GetMacroInfo(i) local m = macros[i]; if m then return m[1], m[2], m[3] end end
function GetBindingKey(cmd) if cmd == "ACTIONBUTTON1" then return "F5" end if cmd == "MULTIACTIONBAR1BUTTON1" then return "SHIFT-1", "MOUSEWHEELUP" end end
C_Spell = C_Spell or {}; C_Spell.GetSpellName = function(id) return id == 5176 and "Wrath" or nil end
GetSpellInfo = function(id) return id == 5176 and "Wrath" or nil end

-- the reading is the loadout module's; the sync module's copy is a list of the buttons in use
local b = S.Bars()
assert(b and #b.buttons == 3 and b.at, "three buttons in use: " .. tostring(b and #b.buttons))
assert(b.buttons[1].slot == 1 and b.buttons[1].kind == "spell" and b.buttons[1].id == 5176, "a spell, by slot")
assert(b.buttons[2].slot == 2 and b.buttons[2].kind == "macro" and b.buttons[2].name == "Heal", "a macro, by its name")
assert(b.buttons[3].slot == 61 and b.buttons[3].kind == "item" and b.buttons[3].id == 858, "an item on another bar")
assert(#b.macros == 2 and b.macros[1].name == "Cat" and b.macros[1].body:find("Cat Form", 1, true) and b.macros[2].index == 121, "the macros with their text")
assert(b.binds.ACTIONBUTTON1[1] == "F5" and b.binds.MULTIACTIONBAR1BUTTON1[2] == "MOUSEWHEELUP", "the key bindings")

-- every state carries it
clock = clock + 10
local st = S:WriteState()
assert(st.bars and #st.bars.buttons == 3 and #st.bars.macros == 2, "the state carries the bars")
-- a button moved: the event marks the state for a new read
slots[3] = { "spell", 5176 }
__fire("ACTIONBAR_SLOT_CHANGED", 3); clock = clock + 10; __runTimers()
assert(#S:WriteState().bars.buttons == 4, "the new button after ACTIONBAR_SLOT_CHANGED")
-- a read where the game answers nothing (a logout): the last good copy is kept, in memory and in the state
local keep = GetActionInfo
GetActionInfo = function() return nil end
clock = clock + 10
assert(#S:WriteState().bars.buttons == 4, "an empty read does not replace the buttons")
GetActionInfo = keep

-- /qb bars dump still works, from the same reading
SlashCmdList.QUESTBOOK("bars dump")
assert(said("bars dump: 4 button%(s%) in use"), "the dump command")
assert(QuestBookDB.mod.loadout.dump.slots[61].id == 858, "and its saved copy keeps its shape")

-- q bars: buttons and bindings, macro names only; q bars macros: the macro text; both in play state
clock = clock + 10
local a = A("q bars")
assert(a:find("^ok {") and a:find('"known":true', 1, true) and a:find('"used":4', 1, true) and a:find('"bound":2', 1, true), "q bars: " .. a)
assert(a:find('"slot":61', 1, true) and a:find('"F5"', 1, true) and a:find('"macroNames"', 1, true) and not a:find("Cat Form", 1, true), "buttons, bindings, names; no macro text: " .. a)
a = A("q bars macros")
assert(a:find('"count":2', 1, true) and a:find("Cat Form", 1, true) and a:find("Healing Touch", 1, true), "q bars macros: " .. a)

-- nothing here can change a button: the game's writing functions are never called
local wrote = 0
PlaceAction = function() wrote = wrote + 1 end; PickupAction = PlaceAction; PickupSpell = PlaceAction; PickupMacro = PlaceAction
ClearCursor = PlaceAction; SetBinding = PlaceAction; EditMacro = PlaceAction; CreateMacro = PlaceAction; DeleteMacro = PlaceAction
clock = clock + 10; S:WriteState(); A("q bars"); A("q bars macros"); S.Bars()
assert(wrote == 0, "read only: no placing, picking up, binding or macro editing")

-- the loadout module off: the field is left out, the question says so, nothing breaks
SlashCmdList.QUESTBOOK("disable loadout"); __take()
assert(S.Bars() == nil, "no loadout module: nil")
a = A("q bars"); assert(a:find('"known":false', 1, true), "q bars says it cannot read: " .. a)
clock = clock + 10
st = S:WriteState()
assert(st.bars and #st.bars.buttons == 4, "the state keeps the last copy it had")
print("bars ok")
