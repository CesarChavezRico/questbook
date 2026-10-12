__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local O = QB.modules.overlay
assert(O and O.active, "overlay active")
local H = UIParent:GetHeight()
local seen = {}
QB:On("overlay_state", function(s) seen[#seen + 1] = s end, "test")

-- at login (state off) the small minimap is up
assert(O.host == "corner", "corner hosts the minimap at login, got " .. tostring(O.host))
assert(Minimap:GetParent() == O.cornerPanel and O.cornerPanel:IsShown(), "minimap in the corner panel")
local w, h = Minimap:GetSize(); assert(w == h and math.abs(w - 0.16 * H) < 0.5, "square, 16% of screen height, got " .. w .. "x" .. h)
assert(Minimap:GetAlpha() == 0.9 and not Minimap:IsMouseEnabled(), "alpha 0.9 and click-through")
assert(O.state == "off" and not O.panel:IsShown(), "big panel hidden")
assert(not MinimapCluster:IsShown(), "old cluster stays hidden")
assert(__cvar("rotateMinimap") == "1", "corner rotates with facing by default, got " .. tostring(__cvar("rotateMinimap")))
assert(O.wantMask == "ui-hud-minimap-frame-generic-mask", "crisp stock circle in the corner, got " .. tostring(O.wantMask))
local pt = { O.cornerPanel:GetPoint(1) }
assert(pt[1] == "TOPRIGHT" and pt[4] == -24 and pt[5] == -44, "top-right under the strip")
local a1 = MainActionBar:GetAlpha(); assert(a1 == 1, "bars untouched with only the corner up")

-- big panel takes the widget, then gives it back
slash("overlay cycle"); __tick(5)
assert(O.state == "local" and O.host == "big", "local = big host")
assert(Minimap:GetParent() == O.panel and not O.cornerPanel:IsShown() and O.panel:IsShown())
local bw, bh = Minimap:GetSize(); assert(bw == bh and bw > 0.5 * H, "big and square")
assert(MainActionBar:GetAlpha() == 0, "bars hidden in local mode")
slash("overlay cycle"); __tick(5)
assert(O.state == "zone" and O.host == "corner", "zone mode: the small one is back")
assert(Minimap:GetParent() == O.cornerPanel and WorldMapFrame:IsShown())
local w2 = Minimap:GetSize(); assert(math.abs(w2 - 0.16 * H) < 0.5, "small again")
slash("overlay cycle"); __tick(5)
assert(O.state == "off" and O.host == "corner" and MainActionBar:GetAlpha() == 1)

-- combat: the overlay closes, the small one is simply there; no spam when it was already off
slash("overlay local"); __tick(5)
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __combat = false; __fire("PLAYER_REGEN_ENABLED"); __tick(5)
assert(O.state == "off" and O.host == "corner" and Minimap:GetParent() == O.cornerPanel, "combat start: local closes, corner returns")
__take()
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __combat = false; __fire("PLAYER_REGEN_ENABLED")
local said = table.concat(__take(), "\n")
assert(not said:find("closed for combat"), "no 'closed for combat' message when only the corner was up")

-- settings
slash("overlay corner size 0.2"); assert(math.abs(Minimap:GetSize() - 0.2 * H) < 0.5, "size applies live")
slash("overlay corner size 25"); assert(math.abs(Minimap:GetSize() - 0.25 * H) < 0.5, "percent form")
slash("overlay corner pos -40 -60"); local p2 = { O.cornerPanel:GetPoint(1) }; assert(p2[4] == -40 and p2[5] == -60)
slash("overlay corner alpha 0.5"); assert(Minimap:GetAlpha() == 0.5)
slash("overlay corner mask soft"); assert(O.wantMask:find("mask_circle"), "soft circle on request")
slash("overlay corner rotate off"); assert(__cvar("rotateMinimap") == "0", "rotation off for the corner")
slash("overlay corner rotate on")
-- rotation is restored to the user's own value when the corner goes away
local orig = O.db.rotateBackup
slash("overlay corner off"); __tick(3)
assert(O.host == nil and Minimap:GetParent() == MinimapCluster, "corner off: minimap back in Blizzard's cluster")
assert(O.db.rotateBackup == nil, "rotation backup cleared")
slash("overlay corner on"); __tick(3); assert(O.host == "corner")

-- the cycle's states and the bus are unchanged
slash("overlay local"); slash("overlay zone"); slash("overlay off")
assert(table.concat(seen, ","):find("local,zone,off"), "states: " .. table.concat(seen, ","))

-- disabling the module gives everything back
QB:SetEnabled("overlay", false)
assert(Minimap:GetParent() == MinimapCluster and MinimapCluster:IsShown() and O.host == nil, "disable restores the cluster and the minimap")
assert(__cvar("rotateMinimap") ~= nil)
QB:SetEnabled("overlay", true); assert(O.host == "corner", "enable puts the corner back")
slash("overlay diag"); flush("diag")
print("corner ok")
