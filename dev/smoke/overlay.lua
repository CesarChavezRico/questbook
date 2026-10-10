__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local O = QB.modules.overlay
print("overlay active:", O and O.active, "unavailable:", O and tostring(O.unavailable))
print("cluster shown after enable:", MinimapCluster:IsShown())
local seen = {}
QB:On("overlay_state", function(s) seen[#seen+1] = s end, "test")
slash("overlay cycle"); __tick(10); print("state:", O:GetState(), "minimap parent is cluster:", Minimap:GetParent() == MinimapCluster, "rotate cvar:", __cvar("rotateMinimap"), "map alpha:", Minimap:GetAlpha(), "mouse:", Minimap:IsMouseEnabled())
slash("overlay cycle"); __tick(10); print("state:", O:GetState(), "rotate cvar:", __cvar("rotateMinimap"), "worldmap shown:", WorldMapFrame:IsShown(), "wm alpha:", WorldMapFrame:GetAlpha(), "wm mouse:", WorldMapFrame:IsMouseEnabled())
-- combat: cycle ignored, force off
__combat = true; slash("overlay cycle"); print("state in combat after cycle:", O:GetState()); __combat = false
__combat = true; __fire("PLAYER_REGEN_DISABLED"); print("state after combat start:", O:GetState()); __combat = false; __fire("PLAYER_REGEN_ENABLED"); __tick(5)
print("state:", O:GetState(), "minimap parent is cluster:", Minimap:GetParent() == MinimapCluster, "rotate cvar:", __cvar("rotateMinimap"), "wm alpha:", WorldMapFrame:GetAlpha(), "wm mouse:", WorldMapFrame:IsMouseEnabled())
slash("overlay shape circle"); slash("overlay size 0.5"); slash("overlay alpha 0.6 0.4"); slash("overlay rotate off"); slash("overlay mask")
slash("overlay local"); __tick(5); print("state:", O:GetState())
QB:Fire("open_full"); __tick(5); print("after open_full state:", O:GetState(), "worldMapToggled:", __worldMapToggled)
slash("overlay both"); __tick(5); slash("overlay off"); __tick(5)
QB:SetEnabled("overlay", false); print("disabled; cluster shown:", MinimapCluster:IsShown(), "minimap parent cluster:", Minimap:GetParent() == MinimapCluster, "wm alpha:", WorldMapFrame:GetAlpha(), "wm scale:", WorldMapFrame:GetScale())
QB:SetEnabled("overlay", true); __tick(3)
print("events seen:", table.concat(seen, ","))
flush("log")
