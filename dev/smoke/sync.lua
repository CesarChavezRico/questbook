-- Sync (4BI-42): the character's state and the guide's chapters written to the saved tables, for planning away from the game.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
local function slash(s) SlashCmdList.QUESTBOOK(s) end
assert(QB.modules.sync and QB.modules.sync.active, "the module is on")
time = time or os.time
-- stand-ins for the game: two bags, an item table, gear, money
local bags = { [0] = { { itemID = 2589, stackCount = 14, quality = 1, hyperlink = "|cffffffff|Hitem:2589|h[Linen Cloth]|h|r" }, false, { itemID = 4865, stackCount = 3, quality = 0 } },
  [1] = { { itemID = 5498, stackCount = 1, quality = 1, isBound = true } } }
local bank = { [-1] = { { itemID = 2318, stackCount = 20, quality = 1 } } }
local open = bags
C_Container = {
  GetContainerNumSlots = function(b) local t = open[b] or bags[b]; return t and #t or 0 end,
  GetContainerItemInfo = function(b, s) local t = open[b] or bags[b]; return t and t[s] or nil end,
}
local items = { [2589] = { "Linen Cloth", 1, "Trade Goods", 13 }, [4865] = { "Ruined Pelt", 0, "Junk", 55 }, [5498] = { "Small Lustrous Pearl", 1, "Quest", 0 }, [2318] = { "Light Leather", 1, "Trade Goods", 15 }, [7000] = { "Staff", 2, "Weapon", 900 } }
-- (this client has no global GetItemInfo: the facts come from C_Item, as on Cesar's client)
C_Item = { GetItemInfo = function(id) local i = items[id]; if not i then return nil end return i[1], nil, i[2], nil, nil, i[3], nil, nil, nil, nil, i[4] end }
function GetInventoryItemID(_, slot) return slot == 16 and 7000 or nil end
function GetInventoryItemDurability(slot) if slot == 16 then return 40, 75 end end
function GetMoney() return 123456 end
function GetBindLocation() return "Nijel's Point" end
function GetRealZoneText() return "Desolace" end
function GetSubZoneText() return "Nijel's Point" end
function GetRealmName() return "PvP" end
function GetNumBankSlots() return 0 end
-- no guide yet
slash("sync"); assert(said("0 guide chapter%(s%) exported; chapter now: none loaded"), "status without RestedXP")
slash("sync guide"); assert(said("no guide is loaded in RestedXP"), "guide export without a guide")
slash("sync now"); assert(said("state written: level %d+, 3 quests, 3 bag items %(1 slots free%), no guide loaded"), "state without a guide")
local s = QuestBookState
assert(s.v == 1 and s.money == 123456 and s.hearth == "Nijel's Point" and s.zone == "Desolace" and s.guide == nil, "the character's facts")
assert(#s.bags == 2 and s.bags[1].slots == 3 and s.bags[1].free == 1 and #s.bags[1].items == 2, "bags, with free slots")
local linen, pelt, pearl = s.bags[1].items[1], s.bags[1].items[2], s.bags[2].items[1]
assert(linen.id == 2589 and linen.count == 14 and linen.name == "Linen Cloth" and linen.sell == 13 and linen.kind == "Trade Goods" and linen.slot == 1, "an item: id, count, name, vendor price, kind")
assert(pelt.quality == 0 and pelt.sell == 55 and pelt.slot == 3 and pearl.bound == true and pearl.kind == "Quest", "junk, a bound quest item")
assert(s.gear[1].name == "Staff", "gear has its name")
assert(#s.gear == 1 and s.gear[1].slot == 16 and s.gear[1].durability == 40 and s.gear[1].durabilityMax == 75, "gear with durability")
assert(#s.quests == 3 and s.quests[2].id == 101 and s.quests[2].ready == true and s.quests[1].ready == false and s.quests[1].objectives[1].text == "Kill 5 things", "the quest log with what is ready and the objectives")
assert(s.bank == nil, "no bank seen yet")
-- the bank is read while its window is open, and kept afterwards
open = bank; __fire("BANKFRAME_OPENED"); open = bags
slash("sync now"); __take()
assert(QuestBookState.bank and QuestBookState.bank.bags[1].items[1].id == 2318 and QuestBookState.bank.at, "the bank as last seen")
-- a guide in RestedXP's memory: the place goes into the state, the steps into QuestBookGuide
local step2 = { index = 2, active = true, sticky = true, elements = {} }
step2.elements[1] = { text = "|cFFFCDC00Accept|r |Hquest:1|h[Reagents for Reclaimers]|h", tag = "accept", questId = 1458, step = step2, zone = "Desolace", x = 66.2, y = 9.6, onUpdate = function() end, frame = { index = 2 } }
step2.elements[1].element = step2.elements[1]
step2.elements[2] = { text = "Bring 10 hides", tag = "collect", id = 6245, qty = 10, textOnly = false, coords = { 1, 2, 3 }, deep = { { 1 } } }
RXP = { currentGuide = { group = "Speedrun Guide 30-40", name = "35-36 Desolace", version = 7, labels = {}, steps = { { index = 1, elements = { { text = "Fly to Nijel's Point", textOnly = true } } }, step2 } },
  GetGuideProgress = function() return 2 end, db = { profile = { guideLength = 114, guideId = 2388229751 } } }
slash("sync now"); assert(said("guide step 2"), "state with the guide")
local g = QuestBookState.guide
assert(g.chapter == "Speedrun Guide 30-40 / 35-36 Desolace" and g.step == 2 and g.steps == 2 and g.active[1] == 2 and g.version == "7:?" and g.imported.guides == 114 and g.imported.id == 2388229751, "the guide's place, the chapter's version, the imported file's header numbers when RestedXP has them")
assert(QuestBookGuide == nil, "the state holds no guide text, and writing it does not export the guide")
slash("sync guide"); assert(said('guide chapter "Speedrun Guide 30%-40 / 35%-36 Desolace" written, 2 steps'), "the chapter is exported")
local ch = QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"]
assert(ch.count == 2 and ch.guide.version == 7 and ch.imported.id == 2388229751, "the chapter's head")
local e = ch.steps[2].elements[1]
assert(ch.steps[2].sticky == true and e.text == "Accept [Reagents for Reclaimers]" and e.tag == "accept" and e.questId == 1458 and e.zone == "Desolace" and e.x == 66.2, "a step's elements with their plain values, text without codes")
assert(e.step == nil and e.onUpdate == nil and e.frame == nil and e.element == nil, "no back-references (step, the element itself), functions or frames")
local e2 = ch.steps[2].elements[2]
assert(e2.id == 6245 and e2.qty == 10 and e2.textOnly == false and e2.coords[3] == 3 and e2.deep == nil, "numbers, a false, a small list; nothing nested deeper")
slash("sync"); assert(said('1 guide chapter%(s%) exported; chapter now: "Speedrun Guide 30%-40 / 35%-36 Desolace", version 7; imported file: 114 guides, id 2388229751'), "status")
-- at unload: the state is written, and a chapter not exported yet (or from another file) is exported once
QuestBookState, QuestBookGuide = nil, nil
__fire("PLAYER_LOGOUT")
assert(QuestBookState and QuestBookState.guide.step == 2 and QuestBookGuide and QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"], "unload writes both the first time")
local at = QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"]; at.mark = true
__fire("PLAYER_LOGOUT"); assert(QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"].mark, "the same chapter of the same file is not exported again")
RXP.db.profile.guideId, RXP.db.profile.guideLength = nil, nil; slash("sync now"); __take(); __fire("PLAYER_LOGOUT")
assert(QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"].mark and QuestBookState.guide.imported == nil, "RestedXP without the header numbers (Cesar's client): no empty table, and no re-export for that")
RXP.currentGuide.version = 8; __fire("PLAYER_LOGOUT")
assert(not QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"].mark and QuestBookGuide.chapters["Speedrun Guide 30-40 / 35-36 Desolace"].version == "8:?", "a new version of the chapter: exported again")
slash("sync auto off"); __take(); QuestBookState = nil; __fire("PLAYER_LOGOUT"); assert(QuestBookState == nil, "auto off: nothing at unload")
slash("sync auto on"); __take()
-- 4BI-47: the state is taken in the world and kept; at a real logout the game no longer answers, and that hollow read
-- must never replace a whole state. (A clock the scenario moves, for the timers.)
local now = 1000
GetTime = function() return now end
QB:Disable("sync"); QB:Enable("sync"); __take()
local function gold() return QuestBookState and QuestBookState.money end
GetMoney = function() return 500 end
__runTimers(); now = now + 3; __runTimers()
slash("sync now"); __take(); assert(gold() == 500 and QuestBookState.how == "world", "a read in the world, marked so")
-- an event marks it stale; the timer takes it again once the UI has settled, not sooner than every few seconds
GetMoney = function() return 777 end
now = now + 10; __fire("PLAYER_MONEY"); __runTimers()
QuestBookState = nil; __fire("PLAYER_LOGOUT")
assert(gold() == 777 and QuestBookState.written, "unload writes the snapshot kept in memory, taken after the change")
-- a real logout: money, experience, bags, gear and finished quests all read as nothing
local realC, realMax = C_Container, UnitXPMax
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
UnitXPMax = function() return 0 end
GetMoney = function() return 0 end
QuestBookState = nil; __fire("PLAYER_LOGOUT")
assert(gold() == 777 and #QuestBookState.bags == 2, "at a real logout the game is not read again: the whole snapshot is written")
slash("sync now"); __take(); assert(gold() == 777 and #QuestBookState.bags == 2, "a hollow read on request keeps the last whole state too")
C_Container, UnitXPMax = realC, realMax
slash("sync zzz"); assert(said("/qb sync || now"), "usage")
print("sync: ok")
