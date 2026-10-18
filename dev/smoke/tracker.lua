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
assert(pt[1] == "TOPRIGHT" and pt[2] == UIParent, "anchored to the screen's top-right corner (it has a position of its own)")
-- the default is every quest in the log (v0.13); this scenario starts from the watch list: quest 100 is watched in the stub
assert(T.db.mode == "all", "the default list is every quest")
slash("tracker tracked")
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
assert(not (QuestBookReader and QuestBookReader:IsShown()), "left click opens nothing")
C_SuperTrack.SetSuperTrackedQuestID(0)
row:Click("RightButton")
assert(QuestBookReader and QuestBookReader:IsShown(), "right click opened the reader")
assert(C_SuperTrack.GetSuperTrackedQuestID() == 0, "and did not change the active quest")
assert(QuestBookReader.title:GetText():find("Kobolds"), "on the clicked quest: " .. tostring(QuestBookReader.title:GetText()))
QuestBookReader:Hide()
-- the Log link toggles the reader
P.book:Click(); assert(QuestBookReader:IsShown()); P.book:Click(); assert(not QuestBookReader:IsShown())
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
-- the list has its own position, independent of the corner minimap (Cesar, 2026-10-17)
local Hh = UIParent:GetHeight()
local seededY = -44 - math.max(48, 0.16 * Hh) - 10
local before = { P:GetPoint(1) }
assert(before[1] == "TOPRIGHT" and before[2] == UIParent and before[3] == "TOPRIGHT", "anchored to the screen")
assert(before[4] == -24 and math.abs(before[5] - seededY) <= 0.5, "seeded right under where the corner minimap sits: " .. tostring(before[4]) .. "," .. tostring(before[5]))
assert(T.db.x == -24 and math.abs(T.db.y - seededY) <= 0.5, "and saved")
slash("overlay local"); __tick(8)
local during = { P:GetPoint(1) }
assert(during[4] == before[4] and during[5] == before[5], "the big overlay does not move it")
slash("overlay off"); __tick(8)
slash("overlay corner pos -300 -100"); __tick(3)
local moved = { P:GetPoint(1) }
assert(moved[4] == before[4] and moved[5] == before[5], "moving the corner minimap does not move the list")
slash("overlay corner reset"); __tick(3)
-- its own handle: drag
slash("tracker move")
local TM = T.mover
assert(TM and TM:IsShown(), "the handle is up")
local W2 = UIParent:GetWidth()
TM.GetRight = function() return W2 - 40 end
TM.GetTop = function() return Hh - 300 end
UIParent.GetRight = function() return W2 end
UIParent.GetTop = function() return Hh end
TM.__scripts.OnDragStart(TM); TM.__scripts.OnUpdate(TM)
assert(T.db.x == -40 and T.db.y == -300, "follows the handle live, got " .. T.db.x .. "," .. T.db.y)
local dragged = { P:GetPoint(1) }
assert(dragged[4] == -40 and dragged[5] == -300, "the list moved with it")
TM.__scripts.OnDragStop(TM)
assert(not TM.dragging, "dropped")
TM.__scripts.OnMouseUp(TM, "RightButton")
assert(not TM:IsShown(), "right-click locks")
slash("tracker move"); slash("tracker lock"); assert(not TM:IsShown(), "lock hides the handle")
slash("tracker pos -10 -20"); local pp = { P:GetPoint(1) }
assert(pp[4] == -10 and pp[5] == -20, "pos sets it")
slash("tracker reset"); __tick(3); slash("tracker")
local rp = { P:GetPoint(1) }
assert(rp[4] == -24 and math.abs(rp[5] - seededY) <= 0.5, "reset seeds it again")
-- with no corner minimap it is still seeded sensibly
slash("overlay corner off"); slash("tracker reset"); slash("tracker")
local nc = { P:GetPoint(1) }
assert(nc[4] == -24 and nc[5] == -44, "no corner minimap: the screen corner, got " .. nc[4] .. "," .. nc[5])
slash("overlay corner on"); slash("tracker reset"); slash("tracker")
slash("tracker"); flush("tracker")
print("tracker ok")
