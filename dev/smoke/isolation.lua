__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush() for _, l in ipairs(__take()) do io.write(l .. "\n") end end
-- a module that explodes in its event handler and on a keybind must not break the others
local bad = QB:NewModule("bad", {})
bad.events.ZONE_CHANGED = function() error("boom in event") end
function bad:Cycle() error("boom in call") end
bad.initialised = true; bad.db = {}; QB:Enable("bad")
__fire("ZONE_CHANGED"); __fire("ZONE_CHANGED")
QB:Call("bad", "Cycle")
slash("modules"); slash("errors"); flush()
slash("disable bad"); slash("modules"); flush()
slash("")   -- quest log still opens
print("book still works:", QuestBookFrame and QuestBookFrame:IsShown()); flush()
