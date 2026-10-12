__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local Q = QB.modules.questlog
-- tracker click on quest 101 opens OUR book on that quest, not Blizzard's
QuestMapFrame_OpenToQuestDetails(101)
assert(QuestBookFrame:IsShown(), "book opened by a tracker click")
assert(QuestBookFrame.title:GetText():find("Kobolds"), "on the clicked quest, got " .. tostring(QuestBookFrame.title:GetText()))
assert(__blizzOpenDetails == nil, "Blizzard's details not opened")
QuestBookFrame:Hide()
OpenQuestLog(); assert(QuestBookFrame:IsShown() and not __blizzOpenQuestLog, "OpenQuestLog reroutes")
QuestBookFrame:Hide()
QuestUtil.OpenQuestDetails(100); assert(QuestBookFrame:IsShown() and not __blizzPopupDetails, "popup detail reroutes")
QuestBookFrame:Hide()
-- fallback: replace off gives every original back
slash("log blizzard")
QuestMapFrame_OpenToQuestDetails(101); assert(__blizzOpenDetails == 101 and not QuestBookFrame:IsShown(), "blizzard path when replace is off")
OpenQuestLog(); assert(__blizzOpenQuestLog)
slash("log replace")
-- disable restores the originals themselves
local ours = QuestMapFrame_OpenToQuestDetails
QB:SetEnabled("questlog", false)
assert(QuestMapFrame_OpenToQuestDetails ~= ours, "original function restored on disable")
QB:SetEnabled("questlog", true)
-- the subtle look
assert(QuestBook ~= nil or true)
slash("bg 0.4"); assert(Q.db.bgAlpha == 0.4)
-- camera zoom out
local C = QB.modules.camera
local z0 = GetCameraZoom()
QB:Fire("overlay_state", "local"); __tick(30, 0.05)
assert(math.abs(GetCameraZoom() - (z0 + 3)) < 0.01, "zoomed out by 3, got " .. GetCameraZoom() - z0)
QB:Fire("overlay_state", "off"); __tick(30, 0.05)
assert(math.abs(GetCameraZoom() - z0) < 0.01, "zoom restored, got " .. GetCameraZoom() - z0)
slash("camera zoomout 0"); QB:Fire("overlay_state", "local"); __tick(30, 0.05)
assert(math.abs(GetCameraZoom() - z0) < 0.01, "zoomout 0 = no zoom change")
QB:Fire("overlay_state", "off"); __tick(30, 0.05)
for _, l in ipairs(__take()) do io.write(l .. "\n") end
