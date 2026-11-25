-- v0.43.0 (4BI-52): the recipes not learned yet, kept beside the known ones, and `q recipes <profession> unlearned [<from> <to>]`.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, P = QB.modules.sync, QB.modules.prep
assert(S and S.active and P and P.active, "sync and prep modules on")
time = time or os.time
local clock = 5000
GetTime = function() return clock end
local function A(body) return (P:Answer(body)) end
local function open() clock = clock + 30; __fire("TRADE_SKILL_SHOW"); __runTimers() end

-- Leatherworking at 161: two recipes known, four not learned (a trainer one at 165, a pattern, a drop, one with no source)
local info = {
  [1] = { name = "Light Leather", learned = true, relativeDifficulty = 3, recipeID = 1 },
  [2] = { name = "Hillman's Cloak", learned = true, relativeDifficulty = 0, recipeID = 2 },
  [10] = { name = "Guardian Gloves", learned = false, recipeID = 10, sourceType = 1, maxTrivialLevel = 190 },
  [11] = { name = "Nightscape Headband", learned = false, recipeID = 11, sourceType = 1, maxTrivialLevel = 200 },
  [12] = { name = "Stalker's Tunic", learned = false, recipeID = 12, sourceType = 3, maxTrivialLevel = 220 },
  [13] = { name = "Nameless Thing", learned = false, recipeID = 13 },
}
local source = {
  [10] = "|cffffd000Trainer:|r Darianna|n|cffffd000Zone:|r Darnassus|nRequires Leatherworking (165)",
  [11] = "|cffffd000Trainer:|r Drakk Stonehand (180)",
  [12] = "|cffffd000Drop:|r Zul'Farrak\r\nPattern: Stalker's Tunic, requires (205)",
}
local ids = { 1, 2, 10, 11, 12, 13 }
C_TradeSkillUI = {
  IsTradeSkillReady = function() return true end,
  GetAllRecipeIDs = function() return ids end,
  GetRecipeInfo = function(id) return info[id] end,
  GetCraftableCount = function() return 0 end,
  GetBaseProfessionInfo = function() return { professionName = "Leatherworking", professionID = 165, skillLevel = 161, maxSkillLevel = 225 } end,
  GetRecipeSourceText = function(id) return source[id] end,
}
open()
local lw = S:Recipes().Leatherworking
assert(lw and lw.count == 2 and #lw.list == 2, "the known list keeps its meaning: " .. tostring(lw and lw.count))
assert(lw.unlearnedCount == 4 and #lw.unlearned == 4, "four unlearned kept apart: " .. tostring(lw.unlearnedCount))
local u = lw.unlearned
assert(u[1].name == "Guardian Gloves" and u[1].skill == 165 and u[2].skill == 180 and u[3].skill == 205, "lowest skill first: " .. u[1].name .. " " .. tostring(u[1].skill))
assert(u[4].name == "Nameless Thing" and u[4].skill == nil and u[4].source == nil, "one with nothing known goes last")
assert(u[1].source == "Trainer: Darianna Zone: Darnassus Requires Leatherworking (165)", "the source as the game words it, cleaned: " .. tostring(u[1].source))
assert(u[3].source:find("^Drop: Zul'Farrak Pattern") and u[1].grey == 190 and u[1].sourceType == 1 and u[1].id == 10 and u[1].mats == nil, "short entries, no materials")
assert(lw.unlearnedSkillFrom == "source text", "says where the skill came from: " .. tostring(lw.unlearnedSkillFrom))
assert(lw.unlearnedSample and lw.unlearnedSample.keys:find("maxTrivialLevel:number", 1, true) and lw.unlearnedSample.sourceRaw:find("||cffffd000Trainer", 1, true), "one sample of what the game gave")

-- the question: sorted, with skill and source; the range keeps it short
local a = A("q recipes leatherworking unlearned")
assert(a:find('"unlearnedKnown":true', 1, true) and a:find('"total":4', 1, true) and a:find('"count":4', 1, true) and a:find('"skillFrom":"source text"', 1, true), "the list: " .. a)
assert(a:find("Guardian Gloves", 1, true) and a:find('"skill":165', 1, true) and a:find("Trainer: Darianna", 1, true) and not a:find('"missing"', 1, true), "names, skill, source")
assert(a:find("Guardian Gloves", 1, true) < a:find("Nightscape Headband", 1, true), "in order")
a = A("q recipes Leatherworking unlearned 160 190")
assert(a:find('"count":2', 1, true) and a:find("Guardian Gloves", 1, true) and a:find("Nightscape Headband", 1, true) and not a:find("Stalker", 1, true), "the range: " .. a)
assert(a:find('"on":"skill"', 1, true), "and what the range was on")
-- the summary counts them; the plain list still answers the known ones
a = A("q recipes"); assert(a:find('"unlearned":4', 1, true) and a:find('"count":2', 1, true), "the summary: " .. a)
a = A("q recipes leather"); assert(a:find("Hillman's Cloak", 1, true) and not a:find("Guardian Gloves", 1, true), "the known list is as before")
-- "first aid unlearned": a profession with a space in its name, never captured
assert(A("q recipes first aid unlearned"):find("not captured yet", 1, true), "a two-word profession")

-- a field of the recipe info gives the skill: it wins over the source text
info[10].requiredSkillRank = 170
open()
lw = S:Recipes().Leatherworking
assert(lw.unlearned[1].skill == 170 and lw.unlearnedSkillFrom == "field requiredSkillRank", "a field wins: " .. tostring(lw.unlearnedSkillFrom))
info[10].requiredSkillRank = nil

-- the game gives no skill at all (no field, no number in the text): the answer says so, lists the names, ranges on grey
source = { [10] = "Trainer: Darianna", [11] = "Trainer: Drakk", [12] = "Drop" }
open()
a = A("q recipes leatherworking unlearned")
assert(a:find('"missing":["skill"]', 1, true) and a:find("Guardian Gloves", 1, true) and a:find('"sample"', 1, true), "no skill: said, names listed, the sample shown: " .. a)
a = A("q recipes leatherworking unlearned 195 225")
assert(a:find('"on":"grey"', 1, true) and a:find("Nightscape Headband", 1, true) and a:find("Stalker", 1, true) and not a:find("Guardian", 1, true), "the range falls back to grey: " .. a)
-- no source either
C_TradeSkillUI.GetRecipeSourceText = nil
open()
a = A("q recipes leatherworking unlearned")
assert(a:find('"missing":["skill","source"]', 1, true) and a:find("Nameless Thing", 1, true), "neither: both named: " .. a)
C_TradeSkillUI.GetRecipeSourceText = function(id) return source[id] end

-- a client whose list holds learned recipes only: the field is left out, the question says so
ids = { 1, 2 }
open()
lw = S:Recipes().Leatherworking
assert(lw.unlearned == nil and lw.unlearnedCount == nil and lw.count == 2, "learned only: no unlearned field")
a = A("q recipes leatherworking unlearned")
assert(a:find('"unlearnedKnown":false', 1, true) and a:find("learned recipes only", 1, true), "and the answer says so: " .. a)

-- the size limits: 800 kept at capture, 90 in one answer, whole (not cut), with how many more
ids = { 1 }
for i = 1000, 1899 do ids[#ids + 1] = i; info[i] = { name = "Unlearned recipe number " .. i, learned = false, recipeID = i, maxTrivialLevel = 100 }; source[i] = "Trainer: Someone with a fairly long name in a fairly long place (" .. (i - 900) .. ")" end
open()
lw = S:Recipes().Leatherworking
assert(#lw.unlearned == 800 and lw.unlearnedCut == 100, "800 kept, 100 counted as left out: " .. #lw.unlearned .. " " .. tostring(lw.unlearnedCut))
a = A("q recipes leatherworking unlearned")
assert(a:find('"count":90', 1, true) and a:find('"more":710', 1, true) and a:find('"leftOutAtCapture":100', 1, true) and not a:find("<cut", 1, true) and #a < 20000, "90 in one answer, whole: " .. #a)
a = A("q recipes leatherworking unlearned 100 120")
assert(a:find('"count":21', 1, true) and not a:find('"more"', 1, true), "a range brings it down: " .. a:sub(1, 200))

-- the classic globals have no unlearned recipes: nothing breaks
C_TradeSkillUI = nil
GetTradeSkillLine = function() return "Cooking", 149, 225 end
GetNumTradeSkills = function() return 1 end
GetTradeSkillInfo = function() return "Roast Boar", "trivial", 0 end
open()
assert(S:Recipes().Cooking.unlearned == nil and A("q recipes cooking unlearned"):find("learned recipes only", 1, true), "classic: learned only")
print("unlearned ok")
