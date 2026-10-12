__fire("ADDON_LOADED", "QuestBook")
__loggedIn = true
__fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do print(tag .. " | " .. l) end end
slash("modules"); flush("modules")
-- quest log: open, buttons, duties
slash(""); flush("open")
local Book = QuestBookFrame
assert(Book and Book:IsShown(), "book should be shown")
print("title:", Book.title:GetText())
local function click(b) b.__scripts.OnClick(b) end
click(Book.btnTrack);   print("track label now:", Book.btnTrack:GetText())
click(Book.btnActive);  print("active label now:", Book.btnActive:GetText(), "super:", C_SuperTrack.GetSuperTrackedQuestID())
click(Book.btnShare);   print("pushed index:", __pushed)
click(Book.btnAbandon); print("popup:", __popup and __popup[1], __popup and __popup[2])
click(Book.next);       print("title after next:", Book.title:GetText())
click(Book.next);       print("title after next:", Book.title:GetText())
__fire("QUEST_LOG_UPDATE"); __runTimers()
__fire("PLAYER_STARTED_MOVING"); print("docked layout points:", #Book.__points)
slash("size 20"); slash("dark"); slash("dock left"); slash("log blizzard")
ToggleQuestLog(); print("blizz log opened via override with replace off:", __blizzLogOpened)
slash("log replace"); __blizzLogOpened = false
ToggleQuestLog(); print("override closes book (shown):", Book:IsShown(), "blizz:", __blizzLogOpened)
slash("blizzlog"); print("blizzlog fallback opened:", __blizzLogOpened)
flush("qlog")
-- strip / coordinates
__runTimers(); __runTimers()
local strip = QB.modules.strip
print("strip active:", strip.active, "unavailable:", tostring(strip.unavailable))
slash("strip status"); flush("strip")
-- drawers
slash("drawers open"); slash("drawers status"); flush("drawers")
slash("drawers close")
-- combat guard events
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __combat = false; __fire("PLAYER_REGEN_ENABLED"); __runTimers()
-- camera
if QB.modules.camera then
  slash("camera strength 0.4"); flush("camera")
  QB:Fire("overlay_state", "local"); __tick(40, 0.05)
  print("overlay local -> test_cameraOverShoulder =", __cvar("test_cameraOverShoulder"))
  QB:Fire("overlay_state", "off"); __tick(40, 0.05)
  print("overlay off   -> test_cameraOverShoulder =", __cvar("test_cameraOverShoulder"))
end
-- disable / enable cycle for every module
for _, name in ipairs(QB.order) do
  QB:SetEnabled(name, false); QB:SetEnabled(name, true)
end
slash("modules"); flush("after cycle")
