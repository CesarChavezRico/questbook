-- The overland map's own place (4BI-36). Cesar, 2026-11-16: "let's move the map overlay to the right next (towards the center of
-- the screen) to the quest log. Lets make it a little smaller and less faded". Our arithmetic and the one-time move of old
-- defaults; not how it looks.
QuestBookDB = { mod = { overlay = { v = 5, zoneSize = 0.78, zoneAlpha = 0.45, hudZone = "hide", localSize = 0.62, anchor = "corner", shape = "circle" } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local O = QB.modules.overlay
local db = O.db
local W, H = UIParent:GetWidth(), UIParent:GetHeight()
local function near(a, b) return math.abs(a - b) < 0.5 end

-- saved values that were only the old defaults moved once; the new place came in as a new setting
assert(db.v == 6 and db.zoneSize == 0.62 and db.zoneAlpha == 0.7 and db.hudZone == "keep", "old defaults moved")
assert(db.zonePlace == "own" and db.zoneX == 0.224 and db.zoneY == 0.054, "the place of its own")

-- the overland map: its own centre and size; the local map is where it was
slash("overlay zone")
local w, h, x, y = O:Geometry()
assert(near(h, 0.62 * H) and near(w, h), "a circle 0.62 of the screen high: " .. w .. " x " .. h)
assert(near(x, 0.224 * W) and near(y, 0.054 * H), "right of centre, a little above: " .. x .. ", " .. y)
slash("overlay local")
local _, lh, lx = O:Geometry()
assert(near(lh, 0.62 * H) and not near(lx, 0.224 * W), "the local map still opens on the small map")
-- the HUD stays while the overland map is open
slash("overlay zone")
assert(O:HudHidden() == false, "the HUD is kept while the overland map is open")
assert(O:CornerShown() == true, "and the small map stays in it")
slash("overlay hud zone hide"); assert(O:HudHidden() == true and O:CornerShown() == false, "hud zone hide: the old behaviour")
slash("overlay hud zone keep")

-- moving it, keeping it on screen, and sending it back to the small map's spot
slash("overlay zonepos -0.2 0.1"); w, h, x, y = O:Geometry()
assert(near(x, -0.2 * W) and near(y, 0.1 * H), "zonepos moves it")
slash("overlay zonepos 0.5 0.5"); w, h, x, y = O:Geometry()
assert(x + w / 2 <= W / 2 + 0.5 and y + h / 2 <= H / 2 + 0.5, "never off the screen")
slash("overlay zonepos corner"); local _, _, cx = O:Geometry()
slash("overlay local"); local _, _, lx2 = O:Geometry()
assert(db.zonePlace == "anchor", "corner: back with the local map")
slash("overlay off")

-- a value Cesar set himself is not touched by the one-time move
QuestBookDB.mod.overlay.v = 5; db.zoneSize = 0.5; db.zoneAlpha = 0.9; db.hudZone = "keep"
O:OnInit()
assert(db.zoneSize == 0.5 and db.zoneAlpha == 0.9, "his own values stay")
print("map zone place: ok")
