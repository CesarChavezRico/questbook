__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush() for _, l in ipairs(__take()) do io.write(l .. "\n") end end
slash("modules"); flush()
slash(""); slash("overlay cycle"); slash("camera flip"); slash("strip status"); slash("drawers open"); __tick(5)
QuestBook_MapCycle(); QuestBook_FullMap(); QuestBook_Toggle()
__fire("QUEST_LOG_UPDATE"); __fire("ZONE_CHANGED"); __fire("PLAYER_REGEN_DISABLED"); __fire("PLAYER_REGEN_ENABLED")
flush()
