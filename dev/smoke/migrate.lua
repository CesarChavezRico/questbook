-- a settings file written by v0.7.1 (hybrid saved, no version) must not keep the painted minimap
QuestBookDB = { mod = { overlay = { ground = "hybrid", shape = "rect" } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local O = QB.modules.overlay
assert(O.db.ground == "auto", "migrated to auto, got " .. tostring(O.db.ground))
assert(O.db.v == 2)
SlashCmdList.QUESTBOOK("overlay local"); __tick(5)
assert(O.groundNow == "native" and not HybridMinimap:IsShown(), "real minimap ground after migration")
SlashCmdList.QUESTBOOK("overlay off")
-- a deliberate choice made AFTER the migration is kept
SlashCmdList.QUESTBOOK("overlay ground hybrid"); assert(O.db.ground == "hybrid")
