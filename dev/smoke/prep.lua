-- Prep (4BI-46): Nibble's questions answered by the game. The fence around free Lua is what this file is mostly about.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local P = QB.modules.prep
assert(P and P.active and P.on == false, "the module is on, in play state")
time = time or os.time
local reloaded = 0
ReloadUI = function() reloaded = reloaded + 1 end
local sentChat = 0
SendChatMessage = function() sentChat = sentChat + 1 end
function GetQuestReward() error("must never be reachable") end
function GetBindLocation() return "Nijel's Point" end
C_Timer.After = C_Timer.After or function() end
C_QuestLog.AbandonQuest = function() error("must never be reachable") end
RXP = { currentGuide = { group = "G", name = "35-37 Desolace", steps = {
    { index = 1, elements = { { text = "|cFFFCDC00Accept|r Vahlarriel's Search", tag = "accept", questId = 1437 }, { text = "note", textOnly = true, completed = true } } },
    { index = 2, active = true, elements = { { text = "Kill satyrs", tag = "complete", questId = 1458, completed = true } } } } },
  SetStep = function() error("must never be reachable") end, settings = { profile = { windowScale = 1.25 } } }
local function A(body) return (P:Answer(body)) end

-- play state: free Lua is refused, fixed questions are answered
assert(A("lua\nreturn 1"):find("^refused: free Lua is answered only in prep state"), "play state refuses free Lua")
assert(A("q nonsense"):find("^refused: not a question"), "an unknown question is refused")
assert(A("hello"):find("^refused"), "anything else too")
local st = A("q state")
assert(st:find('^ok {') and st:find('"hearth":"Nijel\'s Point"', 1, true) and st:find('"prep":false', 1, true) and st:find('"quests":3', 1, true), "q state: " .. st)
assert(A("q quests"):find('"title":"Kobolds"', 1, true), "q quests")
assert(A("q bags"):find('^ok {'), "q bags")
local gd = A("q guide 1 2")
assert(gd:find('"chapter":"G / 35-37 Desolace"', 1, true) and gd:find('"text":"Accept Vahlarriel\'s Search"', 1, true) and gd:find('"quest":1437', 1, true) and gd:find('"active":true', 1, true), "q guide: " .. gd)
C_Item = { GetItemInfo = function(id) if id == 2589 then return "Linen Cloth", nil, 1, 5, 0, "Trade Goods", "Cloth", 20, nil, nil, 13 end end }
local it = A("q items 2589, 77")
assert(it:find('"name":"Linen Cloth"', 1, true) and it:find('"sell":13', 1, true) and it:find('{"id":77,"known":false}', 1, true), "q items: " .. it)
C_QuestLog.IsQuestFlaggedCompleted = function(id) return id == 5 end
assert(A("q completed 5 6") == 'ok [{"completed":true,"id":5},{"completed":false,"id":6}]', "q completed: " .. A("q completed 5 6"))

-- prep is switched on by the typed command only
slash("prep"); assert(said("off: play state"), "status")
slash("prep on"); assert(said("prep: ON") and P.on == true, "on")
assert(QuestBookPrepBar, "the counter exists")

-- the fence: reading works
assert(A("lua\nreturn 1 + 1") == "ok 2", "arithmetic: " .. A("lua\nreturn 1 + 1"))
assert(A("lua\n1 + 1") == "ok 2", "an expression without return")
assert(A("lua\nreturn UnitLevel('player') > 0, GetBindLocation()") == 'ok [true,"Nijel\'s Point"]', "the game's reading functions, several values: " .. A("lua\nreturn UnitLevel('player') > 0, GetBindLocation()"))
assert(A("lua\nreturn C_QuestLog.IsComplete(101), C_QuestLog.IsComplete(100)") == "ok [true,false]", "reading functions of a C_ namespace")
assert(A("lua\nreturn RXP.currentGuide.name, RXP.settings.profile.windowScale") == 'ok ["35-37 Desolace",1.25]', "an addon's tables, read")
assert(A("lua\nlocal n = 0 for i, s in ipairs(RXP.currentGuide.steps) do n = n + len(s.elements) end return n, len(RXP.currentGuide.steps)") == "ok [3,2]", "ipairs and len over views")
assert(A("lua\nlocal k = {} for name, v in pairs(RXP.currentGuide) do k[#k + 1] = name end table.sort(k) return k") == 'ok ["group","name","steps"]', "pairs over a view")
local whole = A("lua\nreturn RXP.currentGuide.steps[1]")
assert(whole:find('"questId":1437', 1, true) and whole:find('"textOnly":true', 1, true) and whole:find('"index":1', 1, true), "a view written out as data: " .. whole)
assert(A("lua\nreturn { a = { 1, 2, 'x\"y' }, b = false }") == 'ok {"a":[1,2,"x\\"y"],"b":false}', "nested tables and quoting: " .. A("lua\nreturn { a = { 1, 2, 'x\"y' }, b = false }"))
assert(A("lua\nlocal t = {} for i = 1, 3 do t[i] = string.format('%02d', i) end return table.concat(t, '-')") == 'ok "01-02-03"', "the Lua basics")

-- the fence: nothing that changes the game is reachable
for _, name in ipairs({ "ReloadUI", "SendChatMessage", "GetQuestReward", "loadstring", "load", "setfenv", "getfenv", "setmetatable", "getmetatable", "rawset", "rawget",
  "RunScript", "hooksecurefunc", "CreateFrame", "SlashCmdList", "require", "dofile", "debug", "os", "io", "print" }) do
  local a = A("lua\nreturn type(" .. name .. ")")
  assert(a == 'ok "nil"' or (name == "SlashCmdList" and a == 'ok "table"'), name .. " must not be reachable: " .. a)
end
assert(A("lua\nreturn type(SlashCmdList.QUESTBOOK)") == 'ok "nil"', "a table of functions is seen, its functions are not")
assert(A("lua\nreturn type(C_Timer.After), type(C_QuestLog.AbandonQuest), type(C_QuestLog.IsComplete)") == 'ok ["nil","nil","function"]', "a C_ namespace hands over reading functions only")
assert(A("lua\nreturn type(RXP.SetStep)") == 'ok "nil"', "an addon's functions are not handed over")
assert(A("lua\nreturn type(_G.ReloadUI), _G == _G._G, type(_G.UnitLevel)") == 'ok ["nil",true,"function"]', "_G is the fence, not the game's table")
assert(A("lua\nreturn type(string.dump)") == 'ok "nil"', "no string.dump")
assert(A("lua\nReloadUI()"):find("^error run:") and reloaded == 0, "calling what is not there is an error, and nothing happened")
assert(A("lua\nSendChatMessage('hi')"):find("^error run:") and sentChat == 0, "no chat")
-- the fence: nothing can be written
assert(A("lua\nRXP.currentGuide.name = 'x'"):find("^error run:.*read%-only") and RXP.currentGuide.name == "35-37 Desolace", "an addon's table cannot be changed")
assert(A("lua\nQuestBookDB.mod.prep.limit = 999"):find("read%-only") and QuestBookDB.mod.prep.limit ~= 999, "nor our own settings")
assert(A("lua\nstring.format = nil; table.insert = nil; math.floor = nil return 1") == "ok 1" and type(string.format) == "function" and type(table.insert) == "function" and type(math.floor) == "function", "the fence's string / table / math are copies")
assert(A("lua\nUnitLevel = function() return 99 end return UnitLevel()") == "ok 99" and UnitLevel("player") ~= 99, "a question's own globals stay inside the fence")
assert(A("lua\nreturn type(leak)") == 'ok "nil"', "nothing left from the question before")
A("lua\nleak = 5"); assert(_G.leak == nil and A("lua\nreturn type(leak)") == 'ok "nil"', "a question's globals do not reach the game, nor the next question")
-- (the test harness has the addon's table as a global; the game does not. Even so: a view, whose functions are hidden and which cannot be written)
P.on = false
assert(A("lua\nreturn 1"):find("^refused"), "play state again")
P.on = true
assert(A("lua\nQB.modules.prep.on = false"):find("read%-only") and A("lua\nreturn type(QB.modules.prep.RunLua), type(QB.Say)") == 'ok ["nil","nil"]', "the addon's own table: read-only, no functions")
-- errors are answers
assert(A("lua\nreturn ((("):find("^error compile:"), "a syntax error is an answer")
assert(A("lua\nerror('boom')"):find("^error run:.*boom"), "a runtime error is an answer")
assert(A("lua\nlocal t = {} t.t = t return t") == 'ok {"t":"<seen>"}', "a table that holds itself")
local big = A("lua\nlocal t = {} for i = 1, 5000 do t[i] = string.rep('x', 50) end return t")
assert(#big <= 20100 and big:find("<cut", 1, true), "a huge answer is cut: " .. #big)

-- questions through the relay addon: registered at enable, answered with SendData, long answers in parts
local inbound, sent = nil, {}
WoWAI = { DATA_MAX = 700, RegisterInbound = function(kind, fn) if kind == "qbask" then inbound = fn end return true end,
  SendData = function(kind, ref, text) sent[#sent + 1] = { kind, ref, text }; return true, #sent end }
QB:Disable("prep"); QB:Enable("prep"); __take()
assert(type(inbound) == "function" and P.on == false, "registered; and switching the module off and on leaves play state")
inbound("m1.0", "lua\nreturn 2")
assert(#sent == 1 and sent[1][1] == "answer" and sent[1][2] == "m1.0" and sent[1][3]:find("^refused"), "play state: the refusal is the answer")
slash("prep on"); __take()
inbound("m1.1", "lua\nreturn 2"); assert(sent[2][3] == "ok 2" and sent[2][2] == "m1.1", "prep: answered")
inbound("m1.2", "lua\nreturn string.rep('y', 1500)")
assert(#sent == 5 and sent[3][3]:find("^part=1/3\n") and sent[5][3]:find("^part=3/3\n") and #sent[3][3] <= 700, "a long answer goes in parts with a header: " .. #sent)
local joined = (sent[3][3]:gsub("^part=%d/%d\n", "")) .. (sent[4][3]:gsub("^part=%d/%d\n", "")) .. (sent[5][3]:gsub("^part=%d/%d\n", ""))
assert(joined == 'ok "' .. string.rep("y", 1500) .. '"', "the parts join back to the answer")
slash("prep"); assert(said("ON %(free Lua is answered, in the fence%); questions can arrive through the relay addon; 2 answered, 1 refused"), "status counts")
-- a message cannot switch prep on: there is no question that does it
slash("prep off"); __take(); reloaded = 0; P.on = false
inbound("m2.0", "q prep on"); inbound("m2.1", "lua\nSlashCmdList.QUESTBOOK('prep on')")
assert(P.on == false, "nothing that arrives can switch prep on")

-- the away counter: shown in prep, says how long the character has been away; it sends nothing
slash("prep on"); __take()
local afk = false
UnitIsAFK = function() return afk end
__runTimers(); assert(QuestBookPrepBar:IsShown() and QuestBookPrepBar.text:GetText():find("not away", 1, true), "prep: the counter is up: " .. tostring(QuestBookPrepBar.text:GetText()))
afk = true; __runTimers(); assert(QuestBookPrepBar.text:GetText():find("AWAY 0:00: press a key", 1, true), "away: " .. QuestBookPrepBar.text:GetText())
afk = false; __runTimers(); assert(QuestBookPrepBar.text:GetText():find("not away", 1, true), "back")
slash("prep limit 5"); assert(said("turns red after 5 minutes"), "limit")
-- typed at the client: the same path, for trying the fence
slash("prep run return 6 * 7"); assert(said("prep: ok 42"), "run")
slash("prep ask q state"); assert(said("prep: ok {"), "ask")
-- leaving prep reloads the UI
slash("prep off"); assert(said("reloading the UI") and reloaded == 1 and P.on == false, "off reloads")
slash("prep off"); assert(said("already off") and reloaded == 1, "off twice does nothing")
slash("prep zzz"); assert(said("/qb prep || on"), "usage")
print("prep: ok")
