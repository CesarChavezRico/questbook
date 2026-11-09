-- The Play / Stop button on EllesmereUI's quest tracker rows (4BI-38). EllesmereUI is a stand-in that follows its documented plugin API
-- (PLUGINS_API.md, version 5): RegisterQuestTrackerRow(id, fn, width) -> boolean, fn(slot, questID, title) per row per redraw, one
-- registration per id, RefreshQuestTrackerRows(). Stubbed API: our logic and the contract, not how it looks or whether the real tracker
-- takes the clicks.
local EUI_HOOKS = {}
local rows = {}                         -- the stand-in tracker's quest title rows: { row frame, title fontstring, slot }
local redraws = 0
local function stand_in(late)
  EllesmereUI = {
    PLUGIN_API_VERSION = 5,
    RegisterQuestTrackerRow = function(id, fn, width)
      if type(id) ~= "string" or id == "" or type(fn) ~= "function" then return false end
      for _, h in ipairs(EUI_HOOKS) do if h.id == id then return false end end
      EUI_HOOKS[#EUI_HOOKS + 1] = { id = id, fn = fn, width = math.max(0, math.min(64, math.floor(tonumber(width) or 0))) }
      return true
    end,
    RefreshQuestTrackerRows = function() redraws = redraws + 1 end,
  }
end
local function redraw(questIDs)             -- what the tracker does on a render: for each quest row, run every hook with that row's slot
  for i, qid in ipairs(questIDs) do
    local r = rows[i]
    if not r then
      r = { frame = CreateFrame("Frame", nil, UIParent) }
      r.title = r.frame:CreateFontString(nil, "OVERLAY"); r.title:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
      r.slot = CreateFrame("Frame", nil, r.frame); r.slot:SetSize(34, 16)
      rows[i] = r
    end
    r.slot:Show()
    for _, h in ipairs(EUI_HOOKS) do pcall(h.fn, r.slot, qid, r.title) end
  end
  for i = #questIDs + 1, #rows do rows[i].slot:Hide() end
end
local function buttonOf(slot) for _, f in ipairs(__frames) do if f.__parent == slot and f.label then return f end end end

-- 1. EllesmereUI is NOT there: nothing breaks, and the status says why
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local E, Q = QB.modules.elle, QB.modules.questlog
assert(E and E.active and not E.unavailable, "the module is on")
slash("elle")
local said = table.concat(__take(), "\n")
assert(said:find("NOT loaded", 1, true) and said:find("NOT available", 1, true), "says EllesmereUI is missing: " .. said)
assert(E.waiting, "and waits for it")

-- 2. it loads later (its tracker module comes after ours). First the id is already taken by another copy: refused, and still waiting
stand_in()
EllesmereUI.RegisterQuestTrackerRow("QuestBook", function() end, 0)
__fire("PLAYER_ENTERING_WORLD")
slash("elle"); assert(table.concat(__take(), "\n"):find("refused", 1, true), "a taken id is reported, not an error")
assert(E.waiting, "and it keeps waiting")
EUI_HOOKS = {}                                          -- (the other copy is gone)
__fire("PLAYER_ENTERING_WORLD")
assert(#EUI_HOOKS == 1 and EUI_HOOKS[1].id == "QuestBook", "registered once, under our addon's name")
assert(EUI_HOOKS[1].width == 34, "reserving 34 px right of the title")
__fire("PLAYER_ENTERING_WORLD"); assert(#EUI_HOOKS == 1, "never twice")
slash("elle"); assert(table.concat(__take(), "\n"):find("registered", 1, true))

-- 3. rows: one button per slot, created once, "Play" on each, set from the questID on every call
redraw({ 100, 101 })
local b1, b2 = buttonOf(rows[1].slot), buttonOf(rows[2].slot)
assert(b1 and b2 and b1 ~= b2, "a button on each row's slot")
assert(b1.label:GetText() == "Play" and b2.label:GetText() == "Play", "Play")
assert(b1.questID == 100 and b2.questID == 101)
redraw({ 101, 100 })                                   -- the slots are reused for other quests
assert(buttonOf(rows[1].slot) == b1 and b1.questID == 101 and b2.questID == 100, "reused: set from the questID each time")
local count = 0 for _, f in ipairs(__frames) do if f.label and f.__parent and f.__parent.__parent then count = count + 1 end end
redraw({ 100, 101 })

-- 4. a click reads that quest: the relay engine with a connected stand-in
local sent = {}
WoWAI = { IsConnected = function() return true end, SendTts = function(a, s, r, t) sent[#sent + 1] = { a = a, r = r, t = t }; return true, #sent end }
slash("voice engine relay"); __take()
b1.__scripts.OnClick(b1)
assert(sent[#sent].a == "play" and sent[#sent].r == "q100", "clicking Play on quest 100 sent its reading: " .. tostring(sent[#sent] and sent[#sent].r))
assert(Q:SpeakingQuestID() == 100, "and it is the quest being read")
assert(b1.label:GetText() == "Stop" and b2.label:GetText() == "Play", "only that row says Stop")
assert(redraws > 0, "the tracker was asked to redraw when the reading started")
redraw({ 100, 101 }); assert(buttonOf(rows[1].slot).label:GetText() == "Stop", "and a redraw keeps it")

-- 5. Stop on the same row; clicking another row's Play replaces the reading
b1.__scripts.OnClick(b1)
assert(sent[#sent].a == "stop", "Stop sends a stop")
assert(b1.label:GetText() == "Play", "back to Play")
b1.__scripts.OnClick(b1); b2.__scripts.OnClick(b2)
assert(sent[#sent].a == "play" and sent[#sent].r == "q101" and b2.label:GetText() == "Stop" and b1.label:GetText() == "Play", "another row's Play replaces the reading")
b2.__scripts.OnClick(b2)

-- 6. the reading ends by itself: back to Play
b1.__scripts.OnClick(b1); __runTimers()
assert(b1.label:GetText() == "Play", "when the estimated time is up it says Play again")

-- 7. the title's own font sets the button's text size
rows[1].title:SetFont("Fonts\\FRIZQT__.TTF", 16, ""); redraw({ 100, 101 })
assert(b1.label.__fsize == 15, "one point under the title: " .. tostring(b1.label.__fsize))

-- 8. the module off: buttons hide, the callback does nothing (the registry has no unregister)
QB:SetEnabled("elle", false); redraw({ 100, 101 })
assert(not b1:IsShown() and not b2:IsShown(), "disabled: no buttons")
QB:SetEnabled("elle", true); redraw({ 100, 101 })
assert(b1:IsShown() and #EUI_HOOKS == 1, "enabled again: the buttons are back, still one registration")

-- 9. an error inside our row function is reported and never thrown into the tracker
local before = (QB.errors.elle and QB.errors.elle.count) or 0
local ok = pcall(EUI_HOOKS[1].fn, rows[1].slot, 100, { GetFont = function() error("boom") end })
assert(ok, "the hook function never throws into Ellesmere's render")
assert(QB.errors.elle and QB.errors.elle.count == before + 1, "it was reported against the module")
QB.errors.elle = nil

print("elle ok")
