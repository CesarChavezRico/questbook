-- a settings file written by v0.7.1 (hybrid saved, no version) must not keep the painted minimap
QuestBookDB = { mod = { overlay = { ground = "hybrid", shape = "rect", cornerMask = "stock" }, tracker = { mode = "tracked", maxFrac = 0.42, v = 1 } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local O = QB.modules.overlay
assert(O.db.ground == "auto", "migrated to auto, got " .. tostring(O.db.ground))
assert(O.db.v == 3)
-- the small minimap bleeds out now: a saved "stock" (the old default) moved to "soft" once
assert(O.db.cornerMask == "soft", "corner mask migrated: " .. tostring(O.db.cornerMask))
-- the list may use more of the screen: a saved 0.42 default moves once, a deliberate mode stays
local T = QB.modules.tracker
assert(T.db.maxFrac == 0.62 and T.db.v == 2 and T.db.mode == "tracked", "tracker migrated: " .. tostring(T.db.maxFrac))
SlashCmdList.QUESTBOOK("overlay local"); __tick(5)
assert(O.groundNow == "native" and not HybridMinimap:IsShown(), "real minimap ground after migration")
SlashCmdList.QUESTBOOK("overlay off")
-- a deliberate choice made AFTER the migration is kept
SlashCmdList.QUESTBOOK("overlay ground hybrid"); assert(O.db.ground == "hybrid")
