-- the compact tracker that replaces Blizzard's objective tracker
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local T = QB.modules.tracker
assert(T and T.active and not T.unavailable, "tracker module is on")
local P = QuestBookTracker
assert(P and P:IsShown(), "the panel is up")
-- Blizzard's tracker is hidden, and stays hidden when something shows it again
assert(not ObjectiveTrackerFrame:IsShown(), "Blizzard's tracker is hidden")
ObjectiveTrackerFrame:Show()
assert(not ObjectiveTrackerFrame:IsShown(), "re-hidden when shown again")
assert(T.blizzard == "hidden")
-- it sits under the corner minimap
local O = QB.modules.overlay
local pt = { P:GetPoint(1) }
assert(pt[1] == "TOPRIGHT" and pt[2] == O.cornerPanel and pt[3] == "BOTTOMRIGHT", "anchored under the corner minimap")
-- tracked quests only by default: quest 100 is watched in the stub
local function visibleRows() local n = 0 for _, f in ipairs(__frames) do if f.__parent == P and f.questID and f:IsShown() then n = n + 1 end end return n end
__runTimers()
assert(T.total == 1 and T.shown == 1, "one tracked quest, got " .. tostring(T.total))
assert(visibleRows() == 1)
-- all quests
slash("tracker all")
assert(T.total == 3, "all quests in the log: " .. tostring(T.total))
slash("tracker tracked")
-- watching another quest refreshes the list (debounced)
C_QuestLog.AddQuestWatch(101); __fire("QUEST_WATCH_LIST_CHANGED"); __runTimers()
assert(T.total == 2, "the new watch shows up: " .. tostring(T.total))
-- clicking a quest opens the book on it
local row
for _, f in ipairs(__frames) do if f.__parent == P and f.questID == 101 and f:IsShown() then row = f end end
assert(row, "row for quest 101")
-- left click: it becomes the active quest and nothing opens; right click: it opens
row:Click()
assert(C_SuperTrack.GetSuperTrackedQuestID() == 101, "left click makes it the active quest")
assert(not (QuestBookFrame and QuestBookFrame:IsShown()), "left click opens nothing")
C_SuperTrack.SetSuperTrackedQuestID(0)
row:Click("RightButton")
assert(QuestBookFrame and QuestBookFrame:IsShown(), "right click opened the book")
assert(C_SuperTrack.GetSuperTrackedQuestID() == 0, "and did not change the active quest")
assert(QuestBookFrame.title:GetText():find("Kobolds"), "on the clicked quest: " .. tostring(QuestBookFrame.title:GetText()))
QuestBookFrame:Hide()
-- the Book link toggles the book
P.book:Click(); assert(QuestBookFrame:IsShown()); P.book:Click(); assert(not QuestBookFrame:IsShown())
-- active quest is marked, ready quest is marked
C_SuperTrack.SetSuperTrackedQuestID(100); __fire("SUPER_TRACKING_CHANGED"); __runTimers()
local titles = {}
for _, f in ipairs(__frames) do if f.__parent == P and f.questID and f:IsShown() then titles[f.questID] = f.title:GetText() end end
assert(titles[100]:sub(1, 2) == "> ", "active quest marked: " .. titles[100])
assert(titles[101]:find("%(ready%)"), "a quest ready to turn in says so: " .. titles[101])
-- empty state
for id in pairs({ [100] = 1, [101] = 1 }) do C_QuestLog.RemoveQuestWatch(id) end
__fire("QUEST_WATCH_LIST_CHANGED"); __runTimers()
assert(T.total == 0)
local hasEmpty = false
for _, f in ipairs(__frames) do if f.__parent == P and f:IsShown() and f.title and f.title:GetText() == "No tracked quests." then hasEmpty = true end end
assert(hasEmpty, "an empty list says so")
-- a long list is cut to the room it has and says how many are in the book
C_QuestLog.AddQuestWatch(100); C_QuestLog.AddQuestWatch(101); C_QuestLog.AddQuestWatch(102)
slash("tracker max 0.05"); __runTimers()
assert(T.shown < T.total, "limited by room: shown " .. T.shown .. " of " .. T.total)
slash("tracker max 0.42")
-- settings
slash("tracker width 300"); assert(P:GetWidth() == 300)
slash("tracker alpha 0.3"); assert(P.__bd and P.__bd[4] == 0.3)
-- following the minimap when the corner is off
slash("overlay corner off"); __tick(3)
local p2 = { P:GetPoint(1) }
assert(p2[2] == UIParent, "no corner minimap: the corner of the screen")
slash("overlay corner on"); __tick(3)
-- in combat the list still updates (it is our own frame)
__combat = true; C_QuestLog.RemoveQuestWatch(102); __fire("QUEST_WATCH_LIST_CHANGED"); __runTimers(); __combat = false
-- disabling gives Blizzard's tracker back
QB:SetEnabled("tracker", false)
assert(ObjectiveTrackerFrame:IsShown() and not P:IsShown(), "disable: Blizzard's tracker is back and ours is gone")
QB:SetEnabled("tracker", true)
assert(not ObjectiveTrackerFrame:IsShown() and P:IsShown(), "enable: replaced again")
-- the list keeps its place when the big overlay takes the minimap (Cesar, 2026-10-17: "the quest list moves up")
local before = { P:GetPoint(1) }
assert(before[2] == O.cornerPanel, "anchored to the corner minimap's slot")
slash("overlay local"); __tick(8)
assert(O.host == "big" and not O.cornerPanel:IsShown(), "the big overlay holds the minimap, the corner is hidden")
local during = { P:GetPoint(1) }
assert(during[1] == before[1] and during[2] == O.cornerPanel and during[3] == before[3] and during[4] == before[4] and during[5] == before[5],
  "the list did not move: " .. tostring(during[2]) .. " " .. tostring(during[4]) .. "," .. tostring(during[5]))
slash("overlay off"); __tick(8)
-- with no corner minimap at all it sits in the screen corner
slash("overlay corner off"); __tick(3); slash("tracker")
local nocorner = { P:GetPoint(1) }
assert(nocorner[2] == UIParent, "no corner minimap: the screen corner, got " .. tostring(nocorner[2]))
slash("overlay corner on"); __tick(3); slash("tracker")
slash("tracker"); flush("tracker")
print("tracker ok")
