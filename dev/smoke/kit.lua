-- /qb screen, /qb kit and the pixel / paper helpers in Style. Stubbed API: layout arithmetic and no errors, not looks.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local Style = QB.Style
local K = QB.modules.kit
assert(K and K.active and not K.unavailable, "kit module on")

-- the pixel arithmetic: 1 px = 768 / physical height units at scale 1 (Blizzard_SharedXML/PixelUtil.lua)
local u = 768 / 1435
assert(math.abs(Style.PixelUnit(UIParent) - u) < 1e-9, "one pixel in units: " .. Style.PixelUnit(UIParent))
assert(math.abs(Style.Px(10, UIParent) - 10 * u) < 1e-9, "Px")
local snapped = Style.Snap(3.3, UIParent)
assert(math.abs(snapped / u - math.floor(snapped / u + 0.5)) < 1e-9, "Snap lands on whole pixels")
local scaled = CreateFrame("Frame"); scaled.GetEffectiveScale = function() return 0.5 end
assert(math.abs(Style.PixelUnit(scaled) - 2 * u) < 1e-9, "a region at half scale sees twice the units per pixel")
local rawSize = GetPhysicalScreenSize; GetPhysicalScreenSize = nil
assert(Style.PixelUnit(UIParent) == 1, "no screen-size API: falls back to 1")
GetPhysicalScreenSize = rawSize

-- /qb screen
slash("screen"); local out = table.concat(__take(), "\n")
assert(out:find("3420x1435", 1, true), "reports the physical size: " .. out)
assert(out:find("1 px = ", 1, true), "and what a pixel is in units")

-- the nine-patch page
local host = CreateFrame("Frame", nil, UIParent); host:SetSize(800, 600)
local P = Style.Paper(host)
assert(#P.parts == 9, "fill, 4 strips, 4 corners")
local e = 64 * u
assert(math.abs(P.top:GetHeight() - e) < 1e-6 and math.abs(P.left:GetWidth() - e) < 1e-6, "strips are 64 px deep")
assert(math.abs(P.tl:GetWidth() - e) < 1e-6, "corners are 64 px square")
host:SetSize(1000, 700); host.__scripts.OnSizeChanged(host, 1000, 700)
assert(P.fill ~= nil, "re-laid out on resize")
local rule = Style.Hairline(host)
assert(math.abs(rule:GetHeight() - 8 * u) < 1e-6, "the rule is 8 px tall")

-- draw order within the BACKGROUND layer: darkening < fill < strips < corners (the fill once shared the darkening's
-- sublevel and the darkening drew over it: Cesar saw a dark interior in a bright rim, 2026-10-17)
slash("kit"); slash("kit")
assert(QuestBookKit.shade.__sub < QuestBookKit.paper.fill.__sub, "the fill draws above the screen darkening")
assert(QuestBookKit.paper.fill.__sub < QuestBookKit.paper.top.__sub, "strips above the fill")
assert(QuestBookKit.paper.top.__sub < QuestBookKit.paper.tl.__sub, "corners above the strips")
for _, k in ipairs({ "fill", "top", "bottom", "left", "right", "tl", "tr", "bl", "br" }) do
  assert(QuestBookKit.paper[k].__layer == "BACKGROUND", k .. " in the background layer")
end
-- the sample page builds and toggles
slash("kit")
assert(QuestBookKit and QuestBookKit:IsShown(), "the sample page is up")
assert(math.abs(QuestBookKit:GetWidth() - 1040 * u) < 1e-6, "1040 px wide")
slash("kit"); assert(not QuestBookKit:IsShown(), "and goes away")
__fire("UI_SCALE_CHANGED")
slash("kit"); assert(QuestBookKit:IsShown())
QB:SetEnabled("kit", false); assert(not QuestBookKit:IsShown(), "disable hides it")
print("kit ok")
