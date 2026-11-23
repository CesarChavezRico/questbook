-- v0.40.0 (4BI-48): profession skills in the state and the fixed prep question `q skills`.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, P = QB.modules.sync, QB.modules.prep
assert(S and S.active and P and P.active, "sync and prep modules on")
time = time or os.time
local clock = 5000
GetTime = function() return clock end
local function A(body) return (P:Answer(body)) end
-- a whole character (bags and experience), so a read is not hollow
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 2 or 0 end,
  GetContainerItemInfo = function(b, s) if b == 0 and s == 1 then return { itemID = 2589, stackCount = 1, quality = 1 } end end }
C_Item = { GetItemInfo = function() return "Linen Cloth", nil, 1, nil, nil, "Trade Goods", nil, nil, nil, nil, 13 end }
function UnitXPMax() return 1000 end
function UnitXP() return 10 end
local function names(list) local t = {} for _, s in ipairs(list or {}) do t[#t + 1] = s.name .. ":" .. s.rank .. "/" .. s.max .. ":" .. s.kind end return table.concat(t, " ") end

-- 1. a client with none of the skill functions: the field is left out, the question says so, nothing breaks
C_SkillInfo, GetNumSkillLines, GetSkillLineInfo, GetProfessions, GetProfessionInfo = nil, nil, nil, nil, nil
assert(S.Skills() == nil, "no API: nil")
local s = S:WriteState()
assert(type(s) == "table" and s.skills == nil and type(s.bags) == "table", "no API: the state has no skills field and is otherwise whole")
clock = clock + 10
local a = A("q skills")
assert(a:find("^ok {") and a:find('"known":false', 1, true), "q skills without the API: " .. a)

-- 2. the Forever way: C_SkillInfo, one table per line; headers, a child line and weapon skills are not professions
local lines = {
  { name = "Class Skills", isHeader = true }, { name = "Balance", skillID = 574, rank = 0, maxRank = 0 },
  { name = "Professions", isHeader = true },
  { name = "Skinning", skillID = 393, rank = 187, maxRank = 225 }, { name = "Leatherworking", skillID = 165, rank = 150, maxRank = 150 },
  { name = "Leatherworking child", skillID = 9999, parentSkillLineID = 165, rank = 1, maxRank = 1 },
  { name = "Secondary Skills", isHeader = true },
  { name = "Cooking", skillID = 185, rank = 96, maxRank = 150 }, { name = "First Aid", skillID = 129, rank = 40, maxRank = 75 }, { name = "Fishing", skillID = 356, rank = 1, maxRank = 75 },
  { name = "Riding", skillID = 762, rank = 75, maxRank = 75 },
  { name = "Weapon Skills", isHeader = true }, { name = "Staves", skillID = 136, rank = 170, maxRank = 170 },
}
C_SkillInfo = { GetNumSkillLines = function() return #lines end, GetSkillLineInfo = function(i) return lines[i] end }
local list = S.Skills()
assert(names(list) == "Skinning:187/225:primary Leatherworking:150/150:primary Cooking:96/150:secondary First Aid:40/75:secondary Fishing:1/75:secondary Riding:75/75:secondary",
  "C_SkillInfo: " .. names(list))
assert(list[1].id == 393, "with the skill id")
clock = clock + 10
s = S:WriteState()
assert(names(s.skills):find("Skinning:187/225:primary", 1, true), "the state carries them")
a = A("q skills")
assert(a:find('"known":true', 1, true) and a:find('"name":"Skinning"', 1, true) and a:find('"rank":187', 1, true) and a:find('"max":225', 1, true) and a:find('"kind":"primary"', 1, true), "q skills: " .. a)
-- a skill point gained: the event marks the state for a new read
lines[4].rank = 188
__fire("SKILL_LINES_CHANGED"); clock = clock + 10; __runTimers()
assert(names(S:WriteState().skills):find("Skinning:188/225", 1, true), "the new rank after SKILL_LINES_CHANGED")
-- a read where the game lists nothing (a collapsed header, a late answer): the last list is kept
local kept = lines; lines = {}
clock = clock + 10
assert(names(S:WriteState().skills):find("Skinning:188/225", 1, true), "an empty list does not erase the skills")
lines = kept
-- the functions throw: no error, nothing listed
C_SkillInfo = { GetNumSkillLines = function() error("boom") end, GetSkillLineInfo = function() error("boom") end }
assert(#S.Skills() == 0, "a failing API gives an empty list, not an error")

-- 3. the classic globals: names under the Professions and Secondary Skills headers
C_SkillInfo = nil
local classic = { { "Professions", true }, { "Skinning", false, 187, 225 }, { "Secondary Skills", true }, { "Cooking", false, 96, 150 }, { "Weapon Skills", true }, { "Staves", false, 170, 170 } }
GetNumSkillLines = function() return #classic end
GetSkillLineInfo = function(i) local l = classic[i]; return l[1], l[2], nil, l[3], nil, nil, l[4] end
assert(names(S.Skills()) == "Skinning:187/225:primary Cooking:96/150:secondary", "classic globals: " .. names(S.Skills()))

-- 4. the retail way: GetProfessions gives indexes (two primary, then secondary ones), some of them nil
GetNumSkillLines, GetSkillLineInfo = nil, nil
GetProfessions = function() return 7, nil, nil, 9, 10, nil end
GetProfessionInfo = function(i) if i == 7 then return "Skinning", nil, 187, 225, nil, nil, 393 elseif i == 9 then return "Fishing", nil, 1, 75, nil, nil, 356 elseif i == 10 then return "Cooking", nil, 96, 150, nil, nil, 185 end end
assert(names(S.Skills()) == "Skinning:187/225:primary Fishing:1/75:secondary Cooking:96/150:secondary", "GetProfessions: " .. names(S.Skills()))
print("skills ok")
