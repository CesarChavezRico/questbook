-- Quest icons on the nameplates of mobs a quest needs (4BI-36): the game says "related", the tooltip says which objective,
-- the quest log says kill or drop and the counts. Stubbed API.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local P = QB.modules.plates
assert(P and P.active and not P.unavailable, "plates module on")

-- the stub world: two nameplates; quest 100 = kill 8 wolves, quest 101 = collect 5 pelts (dropped by bears)
local related, tips, hostile, isPlayer = {}, {}, {}, {}
local plates = {}
for _, u in ipairs({ "nameplate1", "nameplate2", "nameplate3" }) do plates[u] = CreateFrame("Frame", nil, UIParent) end
C_NamePlate = { GetNamePlateForUnit = function(u) return plates[u] end }
function UnitIsPlayer(u) return isPlayer[u] and true or false end
function UnitCanAttack(_, u) return hostile[u] ~= false end
C_QuestLog.UnitIsRelatedToActiveQuest = function(u) return related[u] and true or false end
C_TooltipInfo = { GetUnit = function(u) return tips[u] end }
local objs = {
  [100] = { { text = "Wolf slain: 3/8", type = "monster", finished = false, numFulfilled = 3, numRequired = 8 } },
  [101] = { { text = "Bear Pelt: 0/5", type = "item", finished = false, numFulfilled = 0, numRequired = 5 } },
}
C_QuestLog.GetQuestObjectives = function(qid) return objs[qid] or {} end
local function tip(lines) local t = { lines = {} } for _, l in ipairs(lines) do t.lines[#t.lines + 1] = { type = l[1], leftText = l[2] } end return t end
local function iconOf(u) for _, f in ipairs(__frames) do if f.__parent == plates[u] and f.text then return f end end end

-- a wolf: kill icon with the counts
related.nameplate1 = true
tips.nameplate1 = tip({ { 0, "Timber Wolf" }, { 17, "Wolves at the Gate" }, { 8, "- Wolf slain: 3/8" } })
__fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
local f = iconOf("nameplate1")
assert(f and f:IsShown(), "an icon on the wolf's plate")
assert(f.text:GetText() == "3/8", "with the counts: " .. tostring(f.text:GetText()))

-- a bear that drops pelts: the loot icon
related.nameplate2 = true
tips.nameplate2 = tip({ { 0, "Black Bear" }, { 17, "Pelts" }, { 8, "- Bear Pelt: 0/5" } })
__fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
local f2 = iconOf("nameplate2")
assert(f2 and f2:IsShown() and f2.text:GetText() == "0/5", "the bear shows the pelts: " .. tostring(f2 and f2.text:GetText()))

-- a mob that is not related: nothing
tips.nameplate3 = tip({ { 0, "Rabbit" } })
__fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
local f3 = iconOf("nameplate3")
assert(not f3 or not f3:IsShown(), "no icon on an unrelated mob")

-- a party member's quest after a QuestPlayer line is not ours: only that objective is on the mob, so nothing for us
related.nameplate3 = true
tips.nameplate3 = tip({ { 0, "Wolf" }, { 18, "Mara" }, { 8, "- Wolf slain: 1/8" } })
__fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
f3 = iconOf("nameplate3")
assert(not f3 or not f3:IsShown() or f3.text:GetText() == "", "a party member's objective is not ours to show (the game still says related: generic mark at most)")

-- a kill counted: the next quest update refreshes the counts (once, after the debounce)
objs[100][1].text, objs[100][1].numFulfilled = "Wolf slain: 4/8", 4
__fire("QUEST_LOG_UPDATE"); __runTimers()
assert(f.text:GetText() == "4/8", "counts follow the quest log: " .. tostring(f.text:GetText()))

-- the objective is done: the icon goes
objs[100][1].text, objs[100][1].numFulfilled, objs[100][1].finished = "Wolf slain: 8/8", 8, true
__fire("QUEST_LOG_UPDATE"); __runTimers()
assert(not f:IsShown(), "a finished objective shows nothing")

-- friendly NPCs and players are skipped even when related (a quest giver is "related" but is not a target)
related.nameplate2 = true; hostile.nameplate2 = false
__fire("QUEST_LOG_UPDATE"); __runTimers()
assert(not f2:IsShown(), "a friendly unit gets no icon")
hostile.nameplate2 = nil
isPlayer.nameplate2 = true; __fire("QUEST_LOG_UPDATE"); __runTimers()
assert(not f2:IsShown(), "a player gets no icon")
isPlayer.nameplate2 = nil; __fire("QUEST_LOG_UPDATE"); __runTimers()
assert(f2:IsShown(), "back again")

-- the plate goes away: the icon hides
__fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
assert(not f2:IsShown(), "removed with its plate")

-- no tooltip API: the game's word is enough, a plain quest mark without counts
C_TooltipInfo = nil
related.nameplate1 = true
objs[100][1].finished = false
__fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
assert(f:IsShown() and f.text:GetText() == "", "no tooltip data: a plain mark")
C_TooltipInfo = { GetUnit = function(u) return tips[u] end }

-- settings
slash("plates off"); assert(not f:IsShown() and P.db.on == false, "off hides every icon")
slash("plates on"); assert(f:IsShown(), "on brings them back")
slash("plates size 40"); assert(P.db.size == 40)
slash("plates size 400"); assert(P.db.size == 80, "clamped")
slash("plates side left"); slash("plates side top"); slash("plates side right"); assert(P.db.side == "right")
slash("plates progress off"); assert(f.text:GetText() == "", "counts off")
slash("plates progress on")
-- diag prints what is seen, with the target
related.target = true; tips.target = tips.nameplate1; plates.target = plates.nameplate1
UnitExists = function(u) return u == "target" end
UnitName = function() return "Timber Wolf" end
__take(); slash("plates diag")
local said = table.concat(__take(), "\n")
assert(said:find("related to a quest: true", 1, true) and said:find("Wolf slain", 1, true) and said:find("result:", 1, true), "diag says what it sees: " .. said)
print("plates ok")
