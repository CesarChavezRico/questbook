-- The version line at login.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local out = table.concat(__take(), "\n")
assert(out:find("v" .. QB.version .. " loaded", 1, true), "login says which version loaded: " .. out)
print("version ok")
