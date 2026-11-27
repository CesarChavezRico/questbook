-- v0.44.0 (4BI-54): the bank is read from the containers this client really uses; the keyring is never the bank.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local S, P = QB.modules.sync, QB.modules.prep
assert(S and S.active and P and P.active, "sync and prep modules on")
time = time or os.time
local clock = 5000
GetTime = function() return clock end
local function A(body) return (P:Answer(body)) end
function UnitXPMax() return 1000 end
function UnitXP() return 10 end
local names = { [2589] = "Linen Cloth", [6893] = "Workshop Key", [4234] = "Heavy Leather", [4235] = "Heavy Hide", [4338] = "Mageweave Cloth", [8170] = "Rugged Leather" }
C_Item = { GetItemInfo = function(id) return names[id], nil, 1, nil, nil, id == 6893 and "Key" or "Trade Goods", nil, nil, nil, nil, 13 end }
-- the containers of the game: [container] = { slots, [slot] = { id, count } }; `visible` says which the client answers for now
local boxes, bankIsOpen = {}, false
local function isBank(b) return b >= 6 end
C_Container = {
  GetContainerNumSlots = function(b) local x = boxes[b]; if not x then return 0 end if isBank(b) and not bankIsOpen then return x.slots end return x.slots end,
  GetContainerItemInfo = function(b, s) local x = boxes[b]; if not x or (isBank(b) and not bankIsOpen) then return nil end
    local it = x[s]; if it then return { itemID = it[1], stackCount = it[2], quality = 1 } end end,
}
local function openBank() bankIsOpen = true; __fire("BANKFRAME_OPENED"); __runTimers() end
local function closeBank() bankIsOpen = false; __fire("BANKFRAME_CLOSED") end
local function state() clock = clock + 10; __runTimers(); return S:WriteState() end
local function has(list, id) for _, b in ipairs(list and list.bags or {}) do for _, it in ipairs(b.items) do if it.id == id then return it.count end end end end

-- ===== 1. the Forever client: the keyring is container -1, the bank is tabs 6.., the shared bank tabs 15..
Enum.BagIndex = { Keyring = -1, Backpack = 0, Bag_1 = 1, ReagentBag = 5, Characterbanktab = -2, Accountbanktab = -3 }
for i = 1, 9 do Enum.BagIndex["CharacterBankTab_" .. i] = 5 + i; Enum.BagIndex["AccountBankTab_" .. i] = 14 + i end
Enum.BankType = { Character = 0, Guild = 1, Account = 2 }
boxes = {
  [0] = { slots = 16, { 2589, 14 } },
  [-1] = { slots = 32, { 6893, 1 } },                                              -- the keyring
  [6] = { slots = 98, { 4234, 20 }, { 4234, 20 }, { 4235, 2 } },                   -- character bank tab 1
  [7] = { slots = 98, [5] = { 4338, 4 } },                                         -- character bank tab 2
  [15] = { slots = 98, { 8170, 7 } },                                              -- the shared bank
}
C_Bank = {
  FetchPurchasedBankTabData = function(t) if t == 0 then return { { ID = 6, name = "Leather" }, { ID = 7, name = "Cloth" } } elseif t == 2 then return { { ID = 15, name = "Shared" } } end return {} end,
}
-- never opened: no bank field at all (not an empty one), the keyring is its own field, and the question says the bank is unseen
local s = state()
assert(s.bank == nil and s.accountBank == nil, "a bank never opened has no field")
assert(s.keyring and s.keyring.bag == -1 and s.keyring.items[1].id == 6893, "the keyring is its own field")
assert(has({ bags = s.bags }, 2589) == 14 and not has({ bags = s.bags }, 6893), "the bags are the bags")
local a = A("q bags")
assert(a:find("the bank has not been seen", 1, true) and a:find('"keyring"', 1, true), "q bags says the bank is unseen: " .. a:sub(1, 300))
-- the bank window opens: the tabs are read, with their names; the Workshop Key is not bank content
openBank()
s = state()
assert(s.bank and s.bank.how == "tabs" and #s.bank.bags == 2 and s.bank.at, "the two character tabs: " .. tostring(s.bank and #s.bank.bags))
assert(s.bank.bags[1].bag == 6 and s.bank.bags[1].name == "Leather" and s.bank.bags[2].name == "Cloth", "tabs by number and name")
assert(has(s.bank, 4234) == 20 and has(s.bank, 4235) == 2 and has(s.bank, 4338) == 4, "the leather, the hides and the cloth are in it")
assert(not has(s.bank, 6893), "the Workshop Key is not bank content")
assert(s.accountBank and has(s.accountBank, 8170) == 7 and s.accountBank.bags[1].name == "Shared", "the shared bank under its own name")
a = A("q bags"); assert(a:find("Heavy Leather", 1, true) and a:find('"accountBank"', 1, true) and not a:find("has not been seen", 1, true), "q bags shows it")
-- something is deposited while the window is open: the view follows
boxes[7][6] = { 4235, 3 }
__fire("BAG_UPDATE", 7); __runTimers()
assert(has(state().bank, 4235) == 2 and state().bank.bags[2].items[2].count == 3, "a deposit is seen while the window is open")
-- the window closes: the client stops answering for the bank; what was seen stays, with its time
local seenAt = state().bank.at
closeBank()
boxes[6] = { slots = 98 }                                   -- (whatever the game holds now cannot be read)
__fire("BAG_UPDATE", 6); __fire("PLAYERBANKSLOTS_CHANGED"); __runTimers()
s = state()
assert(has(s.bank, 4234) == 20 and s.bank.at == seenAt, "closed: the bank is as last seen, not emptied")
-- C_Bank missing: the tabs are found through the enum's own numbers
C_Bank = nil
boxes[6] = { slots = 98, { 4234, 5 } }
openBank(); s = state()
assert(s.bank.how == "tabs" and has(s.bank, 4234) == 5 and s.bank.bags[1].name == nil, "without C_Bank: the enum's containers")
closeBank()

-- ===== 2. the modern client before bank tabs: Bank = -1, bank bags 6.., a reagent bank, keyring -2
Enum.BagIndex = { Bank = -1, Reagentbank = -3, Keyring = -2, Backpack = 0, BankBag_1 = 6, BankBag_2 = 7 }
isBank = function(b) return b == -1 or b == -3 or b >= 6 end
boxes = { [0] = { slots = 16, { 2589, 14 } }, [-2] = { slots = 32, { 6893, 1 } }, [-1] = { slots = 28, { 4234, 9 } }, [6] = { slots = 16, { 4338, 2 } }, [-3] = { slots = 98, { 8170, 1 } } }
openBank(); s = state()
assert(s.bank.how == "enum" and has(s.bank, 4234) == 9 and has(s.bank, 4338) == 2 and #s.bank.bags == 2, "enum: Bank and its bags")
assert(s.reagentBank and has(s.reagentBank, 8170) == 1, "the reagent bank under its own name")
assert(s.keyring.bag == -2 and not has(s.bank, 6893), "keyring -2, apart")
closeBank()

-- ===== 3. the classic client (no Enum.BagIndex): the bank IS container -1, with its bags 5..; keyring -2
Enum.BagIndex = nil
isBank = function(b) return b == -1 or b >= 5 end
GetNumBankSlots = function() return 1 end
boxes = { [0] = { slots = 16, { 2589, 14 } }, [-2] = { slots = 32, { 6893, 1 } }, [-1] = { slots = 24, { 4234, 11 } }, [5] = { slots = 12, { 4235, 1 } } }
openBank(); s = state()
assert(s.bank.how == "classic" and has(s.bank, 4234) == 11 and has(s.bank, 4235) == 1, "classic: container -1 is the bank there")
assert(s.keyring.bag == -2, "and the keyring is -2")
closeBank()
print("bank ok")
