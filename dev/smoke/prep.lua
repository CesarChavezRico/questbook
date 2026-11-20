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
-- a clock the scenario moves: questions are answered once the UI has settled (4BI-47)
local clock = 5000
GetTime = function() return clock end

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
-- right after the UI loads, a question waits: the quest log is not whole yet (26 of 40 quests seen in the client)
QB:Disable("sync"); QB:Enable("sync"); __take()
inbound("m1.0", "lua\nreturn 2")
assert(#sent == 0, "not answered in the first seconds after the UI loads")
clock = clock + 10; __runTimers()
assert(#sent == 1 and sent[1][1] == "answer" and sent[1][2] == "m1.0" and sent[1][3]:find("^refused"), "play state: the refusal is the answer")
slash("prep on"); __take()
inbound("m1.1", "lua\nreturn 2"); assert(sent[2][3] == "ok 2" and sent[2][2] == "m1.1", "prep: answered")
inbound("m1.2", "lua\nreturn string.rep('y', 1500)")
assert(#sent == 5 and sent[3][3]:find("^part=1/3\n") and sent[5][3]:find("^part=3/3\n") and #sent[3][3] <= 700, "a long answer goes in parts with a header: " .. #sent)
local joined = (sent[3][3]:gsub("^part=%d/%d\n", "")) .. (sent[4][3]:gsub("^part=%d/%d\n", "")) .. (sent[5][3]:gsub("^part=%d/%d\n", ""))
assert(joined == 'ok "' .. string.rep("y", 1500) .. '"', "the parts join back to the answer")
slash("prep"); assert(said("ON %(free Lua is answered, in the fence%); questions can arrive through the relay addon; 2 answered, 1 refused"), "status counts")
-- v0.33.1: an answer the relay cannot take now waits and is sent when it can (first client test: four answers lost at login)
local up, connects, n0 = false, 0, #sent
WoWAI.SendData = function(kind, ref, text) if not up then return false, "the bridge is not connected" end sent[#sent + 1] = { kind, ref, text }; return true, #sent end
WoWAI.IsConnected = function() return up end
WoWAI.Connect = function() connects = connects + 1 end
inbound("m3.0", "q completed 5"); inbound("m3.1", "lua\nreturn 7")
assert(#sent == n0 and P.Waiting() == 2 and connects == 1 and not said("could not be sent"), "not connected: the answers wait, the relay is asked to reconnect once, nothing is said")
__runTimers(); assert(#sent == n0 and connects == 1, "still waiting; no second reconnect so soon")
slash("prep"); assert(said("2 answer record%(s%) waiting for the relay %(the bridge is not connected%)"), "status says what waits and why")
up = true; __runTimers()
assert(#sent == n0 + 2 and P.Waiting() == 0 and sent[n0 + 1][2] == "m3.0" and sent[n0 + 2][3] == "ok 7", "sent in order once the relay is back")
-- v0.33.2: in prep the relay is asked for waiting questions on a timer (its own signal did not fire in the client); not in play state
local checks = 0
WoWAI.CheckPush = function() checks = checks + 1; return true, 0 end
QuestBookDB.mod.prep.poll = 0
__runTimers(); __runTimers(); assert(checks == 2, "prep on: asked on the ticker: " .. checks)
WoWAI.CheckPush = function() checks = checks + 1; return false, "no reply slots left this session (reload the UI)" end
__runTimers(); slash("prep"); assert(said("the last ask for questions failed: no reply slots left"), "a failed ask is said in the status")
P.on = false; local c0 = checks; __runTimers(); __runTimers(); assert(checks == c0, "play state: never asked")
P.on = true; QuestBookDB.mod.prep.poll = 25; WoWAI.CheckPush = nil
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
-- v0.35.0: a whole number past 2^31 - 1 is written out (the client's "%d" refused RestedXP's guide ids and the answer was lost)
assert(A("lua\nreturn 2426870665, { id = 2598704232 }, -3000000000, 7, 1.5") == 'ok [2426870665,{"id":2598704232},-3000000000,7,1.5]', "large whole numbers: " .. A("lua\nreturn 2426870665, { id = 2598704232 }, -3000000000, 7, 1.5"))
-- v0.35.0: the chapters RestedXP knows, and the steps of one it has not opened (read by RestedXP's own FetchGuide)
local fetched, loaded = 0, 0
local cur = RXP.currentGuide
cur.group, cur.version, cur.guideId, cur.next = "RXP (A)", 24, 2598704232, "36-38 Stranglethorn Vale II"
local stv = { group = "RXP (A)", name = "36-38 Stranglethorn Vale II", version = 7, guideId = 2426870665, next = "38-40 Dustwallow" }
local prev = { group = "RXP (A)", name = "33-35 Shimmering Flats", version = 3, guideId = 11 }
local low = { group = "RXP (A)", name = "1-6 Teldrassil", version = 1, guideId = 12 }
local other = { group = "Free (H)", name = "36-38 Stranglethorn Vale II", version = 2, guideId = 13 }
local broken = { group = "RXP (A)", name = "40-41 Broken", version = 1, guideId = 14 }
RXP.guides = { ["RXP (A)||35-37 Desolace"] = cur, ["RXP (A)||36-38 Stranglethorn Vale II"] = stv, ["RXP (A)||33-35 Shimmering Flats"] = prev,
  ["RXP (A)||1-6 Teldrassil"] = low, ["Free (H)||36-38 Stranglethorn Vale II"] = other, ["RXP (A)||40-41 Broken"] = broken, [1] = { empty = true, name = "" } }
RXP.db = { profile = { guideLength = 106, guideId = 541251347 } }
RXP.LoadGuide = function() loaded = loaded + 1 end
RXP.FetchGuide = function(self, g)
  assert(self == RXP, "called as a method")
  if g == broken then return nil end
  fetched = fetched + 1
  local read = { group = g.group, name = g.name, version = g.version, guideId = g.guideId, next = g.next, steps = {} }
  for i = 1, 30 do read.steps[i] = { elements = { { text = "|cFFFCDC00Accept|r Quest " .. i, tag = "accept", questId = 1000 + i, completed = true } }, active = (i == 2) } end
  RXP.guides[g.group .. "||" .. g.name] = read
  return read
end
local ch = A("q chapters")
assert(ch:find('"current":"RXP (A) / 35-37 Desolace"', 1, true) and ch:find('"known":6', 1, true) and ch:find('"file":{"guides":106,"id":541251347}', 1, true), "q chapters, the head: " .. ch)
assert(ch:find('"name":"33-35 Shimmering Flats"', 1, true) and ch:find('"version":"7:2426870665"', 1, true) and ch:find('"next":"38-40 Dustwallow"', 1, true) and not ch:find("Free (H)", 1, true), "q chapters: the group in the window, with versions: " .. ch)
assert(ch:find('"current":true,"group":"RXP (A)","name":"35-37 Desolace","next":"36-38 Stranglethorn Vale II","steps":2,"version":"24:2598704232"', 1, true), "the chapter in the window is marked and counted: " .. ch)
assert(ch:find("1%-6 Teldrassil.*33%-35.*35%-37.*36%-38.*40%-41"), "in level order: " .. ch)
local rng = A("q chapters 35 38")
assert(rng:find("35-37 Desolace", 1, true) and rng:find("36-38 Stranglethorn", 1, true) and rng:find("33-35 Shimmering", 1, true) and not rng:find("Teldrassil", 1, true) and not rng:find("40-41", 1, true), "q chapters <from> <to>: " .. rng)
assert(A("q chapters all"):find("Free (H)", 1, true) and A("q chapters free"):find("Free (H)", 1, true) and not A("q chapters free"):find('"name":"35-37 Desolace"', 1, true), "all, and a piece of text")
assert(fetched == 0, "listing reads no chapter")
-- play state: a chapter not read yet is not read; the one in the window is answered
P.on = false
assert(A("q chapter 1 25 36-38 Stranglethorn Vale II"):find("^error RestedXP has not read that chapter this session") and fetched == 0, "play state: RestedXP is not asked to read a chapter")
local own = A("q chapter 1 2 35-37 Desolace")
assert(own:find('"evaluated":true', 1, true) and own:find('"current":true', 1, true) and own:find('"count":2', 1, true) and own:find('"done":true', 1, true) and own:find('"active":true', 1, true), "the chapter in the window: " .. own)
P.on = true
local s1 = A("q chapter 1 25 36-38 Stranglethorn Vale II")
assert(fetched == 1 and loaded == 0, "prep: read once by RestedXP, never loaded into its window")
assert(s1:find('"chapter":"RXP (A) / 36-38 Stranglethorn Vale II"', 1, true) and s1:find('"count":30', 1, true) and s1:find('"version":"7:2426870665"', 1, true) and s1:find('"read":true', 1, true) and s1:find('"evaluated":false', 1, true), "the head of the answer: " .. s1)
assert(s1:find('"text":"Accept Quest 25"', 1, true) and s1:find('"quest":1001', 1, true) and not s1:find("Quest 26", 1, true) and not s1:find('"done"', 1, true) and not s1:find('"active"', 1, true), "25 steps, and nothing claimed about done or active: " .. s1)
local s2 = A("q chapter 26 50 stranglethorn")
assert(fetched == 1 and s2:find('"text":"Accept Quest 30"', 1, true) and s2:find('"step":26', 1, true) and not s2:find('"read"', 1, true), "the rest, by a piece of the name, without reading again: " .. s2)
assert(RXP.currentGuide == cur and A("q guide 1 2"):find("35-37 Desolace", 1, true), "the chapter in the window is still the one")
local hd = A("q chapter 33-35 Shimmering Flats")
assert(fetched == 2 and hd:find('"count":30', 1, true) and not hd:find('"steps"', 1, true), "no numbers: the head and the count: " .. hd)
assert(A("q chapter 1 5 3"):find("^error %d+ chapters fit"), "a piece that fits several: " .. A("q chapter 1 5 3"))
assert(A("q chapter 1 5 Winterspring"):find("^error no chapter fits"), "no such chapter")
assert(A("q chapter"):find("^error which chapter"), "no name")
assert(A("q chapter 1 5 40-41 Broken"):find("^error RestedXP could not read that chapter"), "a chapter RestedXP cannot read")
RXP.FetchGuide = function() error("bad guide") end
assert(A("q chapter 1 5 1-6 Teldrassil"):find("^error RestedXP failed reading that chapter:.*bad guide"), "RestedXP's error is the answer")
RXP.FetchGuide = nil
assert(A("q chapter 1 5 1-6 Teldrassil"):find("^error this RestedXP has no FetchGuide"), "an older RestedXP")
local keep = RXP.guides; RXP.guides = nil
assert(A("q chapters"):find("^error RestedXP is not loaded") and A("q chapter x"):find("^error RestedXP is not loaded"), "no list of chapters")
RXP.guides = keep
-- leaving prep reloads the UI
slash("prep off"); assert(said("reloading the UI") and reloaded == 1 and P.on == false, "off reloads")
slash("prep off"); assert(said("already off") and reloaded == 1, "off twice does nothing")
slash("prep zzz"); assert(said("/qb prep || on"), "usage")
print("prep: ok")
