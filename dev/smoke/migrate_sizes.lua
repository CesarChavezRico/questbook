-- v0.28.3: the large maps grew. Sizes saved by v0.28.0 were only its defaults and move once; a size the player chose stays.
QuestBookDB = { mod = { overlay = { v = 4, shape = "circle", localSize = 0.45, zoneSize = 0.9 } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local O = QB.modules.overlay
assert(O.db.v == 5 and O.db.localSize == 0.62, "the old default local size grew: " .. tostring(O.db.localSize))
assert(O.db.zoneSize == 0.9, "a chosen overland size stays: " .. tostring(O.db.zoneSize))
print("migrate sizes: ok")
