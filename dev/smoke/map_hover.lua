-- Hover on the large maps (4BI-36, Cesar 2026-11-12): "The bigger minimap and both overland maps should allow tooltips on quest
-- objectives and questing areas". The large maps answer the pointer resting on them and let every click through; the small
-- map stays fully click-through. Our switches only: whether the client then shows a tooltip is the client's business.
function Minimap:SetMouseMotionEnabled(b) self.__motion = b end
function Minimap:SetMouseClickEnabled(b) self.__click = b end
function Minimap:IsMouseMotionEnabled() return self.__motion end
function Minimap:IsMouseClickEnabled() return self.__click end
local sc = WorldMapFrame.ScrollContainer
function sc:SetMouseMotionEnabled(b) self.__motion = b end
function sc:SetMouseClickEnabled(b) self.__click = b end
function sc:IsMouseMotionEnabled() return self.__motion end
function sc:IsMouseClickEnabled() return self.__click end
Minimap.__motion, Minimap.__click = true, true
sc.__motion, sc.__click = true, true
-- one pin on the world map, hoverable and clickable as Blizzard made it
local pin = { motion = true, click = true }
function pin:SetMouseMotionEnabled(b) self.motion = b end
function pin:SetMouseClickEnabled(b) self.click = b end
function pin:IsMouseMotionEnabled() return self.motion end
function pin:IsMouseClickEnabled() return self.click end
function WorldMapFrame:ExecuteOnAllPins(fn) fn(pin) end

__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local O = QB.modules.overlay
__tick(3)
assert(O.db.hover == true, "hover is on by default")
-- at rest: the small map does not answer the mouse at all
assert(O.host ~= "big" and not Minimap:IsMouseEnabled(), "the small map is click-through")

-- the large local map: hover yes, clicks no
O:Cycle(); __tick(3)
assert(O.state == "local" and O.host == "big")
assert(Minimap.__motion == true and Minimap.__click == false, "large local map: hover on, clicks pass through")
slash("overlay hover off"); __tick(1)
assert(not Minimap:IsMouseEnabled(), "hover off: click-through again")
slash("overlay hover on"); __tick(1)
assert(Minimap.__motion == true and Minimap.__click == false, "and on again")

-- the overland map: the canvas and the pins hover, nothing clicks, and it comes in front of the faded HUD
O:Cycle(); __tick(3)
assert(O.state == "zone")
assert(sc.__motion == true and sc.__click == false, "overland canvas: hover on, clicks pass through")
assert(pin.motion == true and pin.click == false, "pins keep their hover, lose their click")
assert(WorldMapFrame:GetFrameStrata() == "HIGH", "in front of the faded HUD: " .. tostring(WorldMapFrame:GetFrameStrata()))
slash("overlay hud zone keep"); __tick(2)
assert(WorldMapFrame:GetFrameStrata() == "BACKGROUND", "HUD kept: the map goes behind it again")
slash("overlay hud zone hide"); __tick(2)
slash("overlay hover off"); __tick(2)
assert(pin.motion == false and pin.click == false, "hover off: pins fully click-through")
assert(not sc:IsMouseEnabled() and WorldMapFrame:GetFrameStrata() == "BACKGROUND", "hover off: canvas click-through, map behind")
slash("overlay hover on"); __tick(2)

-- closing gives everything back as it was
slash("overlay off"); __tick(3)
assert(pin.motion == true and pin.click == true, "pins restored")
assert(sc.__motion == true and sc.__click == true, "canvas restored")
assert(not Minimap:IsMouseEnabled(), "the small map is click-through again")
print("map hover: ok")
