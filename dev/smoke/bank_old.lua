-- v0.44.0 (4BI-54): a state stored by an older QuestBook holds the KEYRING under the name "bank". On a client whose keyring
-- is container -1 it is not carried into a new state; on a classic client, where -1 really is the bank, it is kept.
QuestBookState = { v = 1, at = 1, xpMax = 1000, bags = { { bag = 0, slots = 16, free = 15, items = { { id = 2589, slot = 1, count = 14 } } } },
  bank = { at = 1795586131, bags = { { bag = -1, slots = 32, free = 31, items = { { id = 6893, slot = 1, count = 1, name = "Workshop Key", kind = "Key" } } } } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S = QB.modules.sync
time = time or os.time
local clock = 5000
GetTime = function() return clock end
function UnitXPMax() return 1000 end
function UnitXP() return 10 end
C_Item = { GetItemInfo = function() return "Thing", nil, 1, nil, nil, "Trade Goods", nil, nil, nil, nil, 13 end }
C_Container = { GetContainerNumSlots = function(b) return (b == 0 and 16) or (b == -1 and 32) or 0 end,
  GetContainerItemInfo = function(b, s) if s == 1 and (b == 0 or b == -1) then return { itemID = b == 0 and 2589 or 6893, stackCount = 1, quality = 1 } end end }
local function state() clock = clock + 10; __runTimers(); return S:WriteState() end

-- the Forever client: -1 is the keyring. The old "bank" is dropped; the key shows as the keyring; the bank is simply unseen
Enum.BagIndex = { Keyring = -1, Backpack = 0, CharacterBankTab_1 = 6 }
local s = state()
assert(s.bank == nil, "the keyring kept as 'bank' by an older version is not carried on")
assert(s.keyring and s.keyring.items[1].id == 6893, "it is the keyring")
-- a stored record that already says how it was read is never dropped
QuestBookState.bank = { at = 5, how = "tabs", bags = { { bag = 6, slots = 98, free = 97, items = { { id = 4234, slot = 1, count = 20 } } } } }
s = state()
assert(s.bank and s.bank.how == "tabs" and s.bank.bags[1].bag == 6, "a real record is kept as last seen")
-- an old record that holds more than container -1 is not the keyring alone: kept
QuestBookState.bank = nil; s = state()
print("bank_old ok")
