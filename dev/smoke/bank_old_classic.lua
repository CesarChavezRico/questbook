-- v0.44.0 (4BI-54): on a classic client (no Enum.BagIndex) container -1 IS the bank, so a stored record of it is kept.
QuestBookState = { v = 1, at = 1, xpMax = 1000, bags = { { bag = 0, slots = 16, free = 15, items = { { id = 2589, slot = 1, count = 14 } } } },
  bank = { at = 77, bags = { { bag = -1, slots = 24, free = 23, items = { { id = 4234, slot = 1, count = 11, name = "Heavy Leather" } } } } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S = QB.modules.sync
time = time or os.time
local clock = 5000
GetTime = function() return clock end
function UnitXPMax() return 1000 end
function UnitXP() return 10 end
C_Item = { GetItemInfo = function() return "Thing", nil, 1, nil, nil, "Trade Goods", nil, nil, nil, nil, 13 end }
C_Container = { GetContainerNumSlots = function(b) return b == 0 and 16 or 0 end,
  GetContainerItemInfo = function(b, s) if s == 1 and b == 0 then return { itemID = 2589, stackCount = 1, quality = 1 } end end }
Enum.BagIndex = nil
clock = clock + 10; __runTimers()
local s = S:WriteState()
assert(s.bank and s.bank.at == 77 and s.bank.bags[1].items[1].id == 4234, "classic: the stored bank is kept as last seen")
assert(s.keyring == nil, "no keyring content, no keyring field")
print("bank_old_classic ok")
