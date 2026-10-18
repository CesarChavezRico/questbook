__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local O = QB.modules.overlay
slash("overlay corner off")   -- these assertions are about the big layers; the corner has corner.lua
assert(O and O.active and not O.unavailable, "overlay should be active")
local seen = {}
QB:On("overlay_state", function(s) seen[#seen + 1] = s end, "test")
local function barsAlpha() return MainActionBar:GetAlpha(), MultiBarLeft:GetAlpha(), StatusTrackingBarManager:GetAlpha() end

-- off -> local -> zone -> off
assert(not MinimapCluster:IsShown(), "corner cluster retired")
slash("overlay cycle"); __tick(10)
assert(O:GetState() == "local", "first press = local")
local w, h = Minimap:GetSize()
assert(w == h, "the minimap must be square, got " .. w .. "x" .. h)
assert(Minimap:GetParent() ~= MinimapCluster, "minimap moved into the panel")
assert(O.groundNow == "native", "the REAL minimap ground is the default outdoors, got " .. tostring(O.groundNow))
assert(not HybridMinimap:IsShown(), "no painted hybrid art outdoors")
assert(C_Minimap.GetUiMapID() == nil, "no map id override outdoors")
assert(O.maskMode == "ours", "our soft mask by default")
slash("xp blizzard off")         -- (the xp module fades Blizzard's xp bar by default; this scenario is about the overlay)
local a1, a2, a3 = barsAlpha(); assert(a1 == 0 and a2 == 0, "action bars hidden in local mode")
assert(a3 == 1, "xp/rep bars untouched by default")
assert((__zoomSets or 0) >= 2, "zoom nudged after the resize")
print("local ok: square", w, h, "bars alpha", a1, a2, a3)

slash("overlay cycle")          -- no frames have run yet
assert(O:GetState() == "zone", "second press = zone (separate mode)")
assert(Minimap:GetParent() == MinimapCluster, "minimap restored when the map mode opens")
assert(not HybridMinimap:IsShown())
assert(C_Minimap.GetUiMapID() == nil, "map id function untouched")
-- the Map mode: masked before it is visible, positioned before it is revealed
assert(WorldMapFrame:IsShown(), "world map shown")
assert(WorldMapFrame:GetMaskTexture() == O.zoneMask and WorldMapFrame:GetUseMaskTexture(), "soft mask set on the map canvas")
assert(WorldMapFrame.__maskables[WorldMapFrame.__tile] == true, "existing detail tile registered with the mask")
assert((__zoomed or 0) >= 1, "zoomed to the player on the very first pass, not on a later tick")
assert(WorldMapFrame:GetAlpha() == 0, "hidden until positioned (no flash of the whole zone)")
__tick(1, 0.016); assert(WorldMapFrame:GetAlpha() == 0, "still hidden after one frame")
__tick(4, 0.016)
assert(WorldMapFrame:GetAlpha() == 1, "revealed after the position pass, got " .. WorldMapFrame:GetAlpha())
assert(WorldMapFrame.ScrollContainer:GetAlpha() < 1, "map translucent")
a1, a2 = barsAlpha(); assert(a1 == 0 and a2 == 0, "action bars hidden in zone mode")
print("zone ok")

slash("overlay cycle"); __tick(10)
assert(O:GetState() == "off", "third press = off")
a1, a2, a3 = barsAlpha(); assert(a1 == 1 and a2 == 1, "bars restored")
assert(not WorldMapFrame:IsShown(), "map closed")
assert(Minimap:GetParent() == MinimapCluster)
print("off ok")

-- bars setting
slash("overlay bars all"); slash("overlay local"); __tick(3)
a1, a2, a3 = barsAlpha(); assert(a3 == 0, "status bars hidden with bars=all")
slash("overlay bars none"); a1, a2, a3 = barsAlpha(); assert(a1 == 1 and a3 == 1, "bars=none restores")
slash("overlay bars actions")
slash("overlay off")

-- native ground + auto indoors
slash("overlay local"); __tick(3)
assert(O.db.ground == "auto" and O.groundNow == "native" and not HybridMinimap:IsShown(), "auto outdoors = native")
-- indoors: the REAL minimap stays (auto never switches to the painted art)
__indoors = true; __fire("ZONE_CHANGED_INDOORS"); __tick(3)
assert(O.groundNow == "native" and not HybridMinimap:IsShown(), "indoors in auto = still the real minimap")
-- Blizzard's own hybrid turns on indoors: auto leaves it, native suppresses it
HybridMinimap:Show()
__tick(3); assert(HybridMinimap:IsShown(), "auto leaves Blizzard's own hybrid alone")
slash("overlay ground native"); __tick(3)
assert(not HybridMinimap:IsShown(), "native suppresses Blizzard's hybrid")
HybridMinimap:Show(); __tick(3)
assert(not HybridMinimap:IsShown(), "and keeps it hidden when Blizzard shows it again")
slash("overlay ground auto"); __indoors = false
slash("overlay off")

-- explicit hybrid never showing falls back to native
slash("overlay ground hybrid")
local saved = C_Map.GetBestMapForUnit; C_Map.GetBestMapForUnit = function() return nil end
slash("overlay local"); __tick(60)
assert(O.groundNow == "native", "fallback when the hybrid frame never shows")
C_Map.GetBestMapForUnit = saved
slash("overlay off")
slash("overlay ground auto")

-- mask debug cycle
slash("overlay local"); slash("overlay mask"); assert(O.maskMode == "stock"); slash("overlay mask"); assert(O.maskMode == "solid"); slash("overlay mask"); assert(O.maskMode == "ours")
slash("overlay off")

-- combat start closes everything and gives the bars back
slash("overlay local"); __tick(3)
__combat = true; __fire("PLAYER_REGEN_DISABLED"); __combat = false; __fire("PLAYER_REGEN_ENABLED"); __tick(3)
assert(O:GetState() == "off"); a1 = barsAlpha(); assert(a1 == 1, "bars back after combat start")

-- removed state, icons, diag
slash("overlay both")
slash("overlay icons 2"); slash("overlay local"); __tick(3); assert(__iconScale == 2, "icon scale applied")
slash("overlay diag"); slash("overlay off"); assert(__iconScale == 1, "icon scale reset")
QB:SetEnabled("overlay", false); assert(MinimapCluster:IsShown(), "cluster back on disable")
QB:SetEnabled("overlay", true)
print("states seen:", table.concat(seen, ","))
flush("log")
