-- The map loop (4BI-36, Cesar 2026-11-11): rest = the small map inside the HUD; first press = the large local map on top of
-- the HUD, on the small map's spot; second press = the overland map in place of the HUD; third = back. Stand-in frames carry
-- EllesmereUI's names. This checks placement arithmetic and which frames are faded, not how it looks.
local function fake(name) local f = CreateFrame("Frame", name, UIParent); f:SetAlpha(1); _G[name] = f; return f end
local elle = {}
for _, n in ipairs({ "EABBar_MainBar", "EABBar_Bar2", "ECME_CDMBar_cooldowns", "EllesmereUIUnitFrames_Player", "EllesmereUIUnitFrames_Target",
  "EllesmereUIPlayerAuraBars_Debuffs", "EllesmereUIResourceBarsFrame", "ERB_CastBarFrame" }) do elle[n] = fake(n) end
elle.EABBar_Bar2:SetAlpha(0.6)                       -- one that EllesmereUI keeps half faded: it must come back at 0.6
local other = fake("SomebodyElsesFrame")
-- Cesar's small map: a fifth of the screen high, in the lower middle
QuestBookDB = { mod = { overlay = { cornerSize = 0.2, cornerX = -1314, cornerY = -784, v = 3, shape = "rect" } } }
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local O = QB.modules.overlay
local W, H = UIParent:GetWidth(), UIParent:GetHeight()
assert(O.db.v == 5 and O.db.shape == "circle" and O.db.anchor == "corner", "migrated to the loop's defaults")
local s = 0.2 * H
local smallX, smallY = W / 2 - 1314 - s / 2, H / 2 - 784 - s / 2          -- the small map's centre, from the screen centre
local function centre() local p = { O.panel:GetPoint(1) }; return p[4], p[5] end

-- sizes saved by v0.28.0 (its defaults) grow once; a size the player chose stays
assert(O.db.localSize == 0.62 and O.db.zoneSize == 0.78, "the new sizes")

-- rest
assert(O.state == "off" and O.cornerPanel:IsShown(), "at rest the small map shows")
for n, f in pairs(elle) do assert(f:GetAlpha() > 0, n .. " visible at rest") end

-- first press: the local map, a circle on the small map's spot, the HUD untouched
O:Cycle(); __tick(3)
assert(O.state == "local", "first press opens the local map")
local x, y = centre()
assert(math.abs(O.panel:GetHeight() - 0.62 * H) < 0.5 and math.abs(O.panel:GetWidth() - O.panel:GetHeight()) < 0.5, "local map: 0.62 of the screen, square")
assert(math.abs(x - smallX) < 0.5, "local map centred on the small map (x): " .. x .. " vs " .. smallX)
local wantY = math.max(-(H / 2 - 0.62 * H / 2), math.min(H / 2 - 0.62 * H / 2, smallY))
assert(math.abs(y - wantY) < 0.5, "and (y), kept on screen: " .. y .. " vs " .. wantY)
for n, f in pairs(elle) do assert(f:GetAlpha() > 0, n .. " stays under the local map") end
assert(Minimap:GetFrameStrata() == "HIGH", "the local map is drawn over the HUD: " .. tostring(Minimap:GetFrameStrata()))
slash("overlay layer under"); __tick(1)
assert(Minimap:GetFrameStrata() == "LOW", "layer under puts it behind the HUD")
slash("overlay layer over"); __tick(1)
assert(MainActionBar:GetAlpha() == 1, "the game's own bars too")

-- second press: the overland map replaces the HUD
O:Cycle(); __tick(3)
assert(O.state == "zone", "second press opens the overland map")
assert(math.abs(O.panel:GetHeight() - 0.78 * H) < 0.5, "overland map: 0.78 of the screen")
local _, zy = centre()
assert(zy - O.panel:GetHeight() / 2 >= -H / 2 - 0.5, "kept on screen at the bottom")
for n, f in pairs(elle) do assert(f:GetAlpha() == 0, n .. " faded under the overland map") end
assert(MainActionBar:GetAlpha() == 0 and other:GetAlpha() == 1, "the game's bars too, and nobody else's frames")
-- EllesmereUI puts an alpha back: the next verify pass fades it again
elle.EABBar_MainBar:SetAlpha(1); __tick(60, 0.05)
assert(elle.EABBar_MainBar:GetAlpha() == 0, "a frame that came back is faded again")

-- third press: back to rest, every alpha as it was
slash("overlay off"); __tick(3)
assert(O.state == "off" and O.cornerPanel:IsShown(), "back to rest")
assert(Minimap:GetFrameStrata() == "LOW", "the small map is below the HUD again")
assert(elle.EABBar_Bar2:GetAlpha() == 0.6 and elle.EABBar_MainBar:GetAlpha() == 1 and elle.ERB_CastBarFrame:GetAlpha() == 1, "every frame has its own alpha back")

-- combat closes the map and gives the HUD back
slash("overlay zone"); __tick(3)
assert(elle.EllesmereUIUnitFrames_Player:GetAlpha() == 0)
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __tick(1)
assert(O.state == "off" and elle.EllesmereUIUnitFrames_Player:GetAlpha() == 1, "combat: the map closes and the HUD is back")
__combat = false; __fire("PLAYER_REGEN_ENABLED")

-- the settings
slash("overlay hud zone keep"); slash("overlay zone"); __tick(3)
assert(elle.EABBar_MainBar:GetAlpha() == 1, "hud zone keep leaves the HUD under the overland map")
slash("overlay hud zone hide"); __tick(1)
assert(elle.EABBar_MainBar:GetAlpha() == 0, "and hide fades it")
slash("overlay sizes 0.3 0.4"); __tick(1)
assert(math.abs(O.panel:GetHeight() - 0.4 * H) < 0.5, "sizes sets both")
slash("overlay anchor offset"); __tick(1)
local ox = centre()
assert(math.abs(ox - O.db.offsetX * W) < 0.5, "anchor offset goes back to the old placement")
slash("overlay off")
print("map loop: ok")
