-- v0.41.0 (4BI-49): the recipes of a profession, saved when its window is opened, and the fixed question `q recipes`.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, P = QB.modules.sync, QB.modules.prep
assert(S and S.active and P and P.active, "sync and prep modules on")
time = time or os.time
local clock = 5000
GetTime = function() return clock end
local function A(body) return (P:Answer(body)) end
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
  GetContainerItemInfo = function(b, s) if b == 0 and s == 1 then return { itemID = 2589, stackCount = 1, quality = 1 } end end }
C_Item = { GetItemInfo = function() return "Linen Cloth", nil, 1, nil, nil, "Trade Goods", nil, nil, nil, nil, 13 end }
function UnitXPMax() return 1000 end
function UnitXP() return 10 end
C_SkillInfo = { GetNumSkillLines = function() return 4 end, GetSkillLineInfo = function(i) return ({
  { name = "Leatherworking", skillID = 165, rank = 161, maxRank = 225 }, { name = "Skinning", skillID = 393, rank = 230, maxRank = 300 },
  { name = "Cooking", skillID = 185, rank = 149, maxRank = 225 }, { name = "First Aid", skillID = 129, rank = 222, maxRank = 225 } })[i] end }
local function open() __fire("TRADE_SKILL_SHOW"); __runTimers() end

-- 1. a client with no recipe functions: nothing is saved, the field is left out, the question still answers
C_TradeSkillUI, GetNumTradeSkills, GetTradeSkillInfo, GetTradeSkillLine = nil, nil, nil, nil
open()
assert(next(S:Recipes()) == nil, "no API: nothing saved")
clock = clock + 10
assert(S:WriteState().recipes == nil, "no API: the state has no recipes field")
local a = A("q recipes")
assert(a:find("^ok {") and a:find('"captured":[]', 1, true) or a:find('"captured":{}', 1, true), "q recipes with nothing captured: " .. a)
assert(a:find("Leatherworking", 1, true) and a:find("Cooking", 1, true) and a:find("First Aid", 1, true) and not a:find("Skinning", 1, true), "it names the crafting professions never captured, not the gathering ones: " .. a)
assert(A("q recipes leatherworking"):find("not captured yet", 1, true), "one profession, never captured")
local _, why = S:CaptureRecipes(); assert(why:find("no recipe functions", 1, true), "says why: " .. tostring(why))

-- 2. the modern window (C_TradeSkillUI), Leatherworking: learned recipes with difficulty, how many can be made, materials
local info = {
  [2881] = { name = "Light Leather", learned = true, relativeDifficulty = 3, recipeID = 2881 },
  [3760] = { name = "Hillman's Cloak", learned = true, relativeDifficulty = 0, recipeID = 3760 },
  [3761] = { name = "Fine Leather Tunic", learned = true, relativeDifficulty = 1, recipeID = 3761 },
  [9999] = { name = "Not Learned Yet", learned = false, relativeDifficulty = 0, recipeID = 9999 },
}
local ready, linked, prof = true, false, { professionName = "Leatherworking", professionID = 165, skillLevel = 161, maxSkillLevel = 225 }
C_TradeSkillUI = {
  IsTradeSkillReady = function() return ready end, IsTradeSkillLinked = function() return linked end,
  GetAllRecipeIDs = function() return { 2881, 3760, 3761, 9999 } end,
  GetRecipeInfo = function(id) return info[id] end,
  GetCraftableCount = function(id) return id == 3760 and 2 or 0 end,
  GetBaseProfessionInfo = function() return prof end,
  GetRecipeSchematic = function(id) if id == 3760 then return { reagentSlotSchematics = {
    { reagents = { { itemID = 2319 } }, quantityRequired = 5 }, { reagents = { { itemID = 2321 } }, quantityRequired = 2 }, { reagents = {}, quantityRequired = 1 } } } end end,
}
-- the first frame: not ready, nothing saved; then the list fills and the update captures it
ready = false; open()
assert(next(S:Recipes()) == nil, "not ready: nothing saved")
ready = true; clock = clock + 2; __fire("TRADE_SKILL_LIST_UPDATE"); __runTimers()
local lw = S:Recipes().Leatherworking
assert(lw and lw.count == 3 and lw.skill == 161 and lw.max == 225 and lw.id == 165 and lw.how == "C_TradeSkillUI" and lw.at, "captured: " .. tostring(lw and lw.count))
assert(lw.list[1].name == "Light Leather" and lw.list[1].diff == "grey" and lw.list[2].diff == "orange" and lw.list[3].diff == "yellow", "difficulty as a colour")
assert(lw.list[2].can == 2 and lw.list[2].id == 3760, "how many can be made, and the id")
assert(#lw.list[2].mats == 2 and lw.list[2].mats[1].id == 2319 and lw.list[2].mats[1].count == 5 and lw.list[1].mats == nil, "materials where the game gives them")
assert(lw.partial == nil)
-- it travels with the state
clock = clock + 10; __runTimers()
local st = S:WriteState()
assert(st.recipes and st.recipes.Leatherworking and st.recipes.Leatherworking.count == 3, "the state carries the capture")
-- q recipes: the summary, then one profession
a = A("q recipes")
assert(a:find('"profession":"Leatherworking"', 1, true) and a:find('"count":3', 1, true) and a:find('"skill":161', 1, true), "the summary: " .. a)
assert(a:find("notCaptured", 1, true) and a:find("Cooking", 1, true) and a:find("First Aid", 1, true), "and what was never captured: " .. a)
a = A("q recipes leather")
assert(a:find('"captured":true', 1, true) and a:find("Hillman's Cloak", 1, true) and a:find('"diff":"orange"', 1, true) and a:find('"can":2', 1, true), "one profession by the start of its name: " .. a)

-- 3. opened again later: the new list replaces the old one; an empty read never does
info[3761].relativeDifficulty = 2; info[9999].learned = true; prof.skillLevel = 170
clock = clock + 30; open()
lw = S:Recipes().Leatherworking
assert(lw.count == 4 and lw.skill == 170 and lw.list[3].diff == "green", "a second capture replaces the first")
local keep = C_TradeSkillUI.GetAllRecipeIDs
C_TradeSkillUI.GetAllRecipeIDs = function() return {} end
clock = clock + 30; open()
assert(S:Recipes().Leatherworking.count == 4, "an empty list does not replace a saved one")
C_TradeSkillUI.GetAllRecipeIDs = keep
-- someone else's window (a link): not ours
linked = true; prof = { professionName = "Tailoring", professionID = 197, skillLevel = 300, maxSkillLevel = 300 }
clock = clock + 30; open()
assert(S:Recipes().Tailoring == nil, "a linked window is not captured")
linked = false
-- another profession is kept beside the first
prof = { professionName = "Cooking", professionID = 185, skillLevel = 149, maxSkillLevel = 225 }
clock = clock + 30; open()
assert(S:Recipes().Cooking and S:Recipes().Leatherworking, "two professions side by side")
-- no full list on this client: the filtered one, marked partial
C_TradeSkillUI.GetAllRecipeIDs = nil; C_TradeSkillUI.GetFilteredRecipeIDs = function() return { 2881 } end
prof = { professionName = "First Aid", professionID = 129, skillLevel = 222, maxSkillLevel = 225 }
clock = clock + 30; open()
assert(S:Recipes()["First Aid"].count == 1 and S:Recipes()["First Aid"].partial, "the filtered list is marked partial")
a = A("q recipes"); assert(not a:find('"notCaptured":["', 1, true) or not a:find("Cooking\"]", 1, true), "all three captured now")

-- 4. the classic globals: optimal / medium / easy / trivial, a collapsed header marks the list partial
C_TradeSkillUI = nil
local rows = { { "Trade Goods", "header", 0, true }, { "Heavy Leather", "trivial", 3 }, { "Armor", "header", 0, false }, { "Nightscape Tunic", "optimal", 0 } }
GetTradeSkillLine = function() return "Leatherworking", 180, 225 end
GetNumTradeSkills = function() return #rows end
GetTradeSkillInfo = function(i) local r = rows[i]; return r[1], r[2], r[3], r[4] end
GetTradeSkillRecipeLink = function(i) return i == 4 and "|cffffd000|Henchant:10499|h[Nightscape Tunic]|h|r" or nil end
GetTradeSkillNumReagents = function(i) return i == 4 and 1 or 0 end
GetTradeSkillReagentInfo = function() return "Thick Leather", nil, 7, 3 end
GetTradeSkillReagentItemLink = function() return "|cffffffff|Hitem:4304:0:0|h[Thick Leather]|h|r" end
clock = clock + 30; open()
lw = S:Recipes().Leatherworking
assert(lw.how == "classic" and lw.count == 2 and lw.skill == 180 and lw.partial, "classic: " .. tostring(lw.how) .. " " .. tostring(lw.count))
assert(lw.list[1].diff == "grey" and lw.list[1].can == 3 and lw.list[2].diff == "orange" and lw.list[2].id == 10499 and lw.list[2].mats[1].id == 4304 and lw.list[2].mats[1].count == 7, "classic rows")
-- no window open in the classic API
GetTradeSkillLine = function() return "UNKNOWN", 0, 0 end
_, why = S:CaptureRecipes(); assert(why:find("no profession window", 1, true), "closed window: " .. tostring(why))

-- 5. a long list answers without its materials, whole
local big = { name = "Leatherworking", count = 150, at = 1, skill = 300, max = 300, list = {} }
for i = 1, 150 do big.list[i] = { name = "Recipe number " .. i, id = i, diff = "grey", can = 0, mats = { { id = 1, count = 1 } } } end
S:Recipes().Leatherworking = big
a = A("q recipes leatherworking")
assert(a:find('"matsLeftOut":true', 1, true) and a:find("Recipe number 150", 1, true) and not a:find("<cut", 1, true), "a long list is whole, without materials")
print("recipes ok")
