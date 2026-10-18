-- The experience bar under the strip. Stubbed API: arithmetic, state and events, not how it looks.
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local X, S = QB.modules.xp, QB.modules.strip
local Style = QB.Style
local u = Style.PixelUnit(UIParent)
assert(X and X.active and not X.unavailable, "xp module on")
local bar = QuestBookXpBar
assert(bar and bar:IsShown(), "the bar is up")

-- whole pixels, right-aligned under the strip
assert(math.abs(bar:GetWidth() - 360 * u) < 1e-6 and math.abs(bar:GetHeight() - 3 * u) < 1e-6, "360 x 3 px")
local p = { bar:GetPoint(1) }
assert(p[1] == "TOPRIGHT" and p[2] == S:GetFrame() and p[3] == "BOTTOMRIGHT", "hangs under the strip, right-aligned")

-- the fill is the XP fraction; the rested part follows it
local frac = 1240 / 2800
assert(math.abs(bar.fill:GetWidth() / bar:GetWidth() - frac) < 1e-6, "fill = xp / max")
assert(bar.rest:IsShown() and math.abs(bar.rest:GetWidth() / bar:GetWidth() - 400 / 2800) < 1e-6, "rested extends it")
local rp = { bar.rest:GetPoint(1) }
assert(math.abs(rp[4] - frac * bar:GetWidth()) < 1e-6, "starting where the fill ends")
-- Blizzard's own bar is faded out while ours is up, and given back when it goes
assert(StatusTrackingBarManager:GetAlpha() == 0, "Blizzard's bottom bar is faded out")

-- hovering shows the numbers
bar.__scripts.OnEnter(bar)
local tip = table.concat(GameTooltip.__lines, " | ")
assert(tip:find("Level 8", 1, true) and tip:find("1,240 / 2,800", 1, true) and tip:find("44%%"), "tooltip: level, xp, percent: " .. tip)
assert(tip:find("1,560 to go", 1, true) and tip:find("Rested +400", 1, true), "to go and rested: " .. tip)
bar.__scripts.OnLeave(bar); assert(GameTooltip.__shown == false)

-- XP changes, rested caps at what is left of the level
__xp.xp, __xp.rested = 2500, 900; __fire("PLAYER_XP_UPDATE")
assert(math.abs(bar.fill:GetWidth() / bar:GetWidth() - 2500 / 2800) < 1e-6)
assert(math.abs((bar.rest:GetWidth() + bar.fill:GetWidth()) / bar:GetWidth() - 1) < 1e-6, "rested never runs past the end: " .. (bar.rest:GetWidth() + bar.fill:GetWidth()) / bar:GetWidth())
__xp.rested = 0; __fire("UPDATE_EXHAUSTION"); assert(not bar.rest:IsShown(), "no rested part when none")
__xp.xp, __xp.level, __xp.max = 10, 9, 3000; __fire("PLAYER_LEVEL_UP")
assert(math.abs(bar.fill:GetWidth() / bar:GetWidth() - 10 / 3000) < 1e-6, "a new level starts over")
__xp.xp = 0; __fire("PLAYER_XP_UPDATE"); assert(not bar.fill:IsShown(), "an empty bar shows no fill")

-- settings
slash("xp width 500"); assert(math.abs(bar:GetWidth() - 500 * u) < 1e-6)
slash("xp height 6"); assert(math.abs(bar:GetHeight() - 6 * u) < 1e-6)
slash("xp width 360"); slash("xp height 3")
slash("xp rested off"); __xp.rested = 400; __xp.xp = 100; __fire("PLAYER_XP_UPDATE"); assert(not bar.rest:IsShown(), "rested off")
slash("xp rested on")
slash("xp blizzard off"); assert(StatusTrackingBarManager:GetAlpha() == 1, "left alone: Blizzard's bar is back")
slash("xp blizzard on"); assert(StatusTrackingBarManager:GetAlpha() == 0, "and faded again")

-- the overlay fades and restores the same frame in map modes (bars all): ours is put back after it
slash("overlay bars all"); slash("overlay local"); __tick(3)
assert(StatusTrackingBarManager:GetAlpha() == 0, "faded while a map is open")
slash("overlay off"); __tick(3)
assert(StatusTrackingBarManager:GetAlpha() == 0, "and still faded by the xp bar after the overlay closes (its fade restores to ours)")
slash("xp blizzard off"); assert(StatusTrackingBarManager:GetAlpha() == 1)
slash("overlay local"); __tick(3); slash("xp blizzard on")
slash("overlay off"); __tick(3)
assert(StatusTrackingBarManager:GetAlpha() == 0, "the overlay restored it to visible; the xp bar fades it again right after")
slash("overlay bars actions")

-- at the maximum level (or with XP gain off) there is nothing to show: the bar hides, Blizzard's comes back
__xp.level = 60; __fire("PLAYER_LEVEL_UP")
assert(not bar:IsShown(), "no bar at the maximum level")
assert(StatusTrackingBarManager:GetAlpha() == 1, "Blizzard's bar (reputation, honor) is back")
__xp.level, __xp.disabled = 20, true; __fire("DISABLE_XP_GAIN")
assert(not bar:IsShown(), "no bar with XP gain turned off")
__xp.disabled = false; __fire("ENABLE_XP_GAIN"); assert(bar:IsShown() and StatusTrackingBarManager:GetAlpha() == 0, "back")

-- without the strip it hangs in the screen corner
QB:SetEnabled("strip", false); __fire("PLAYER_ENTERING_WORLD")
local p2 = { bar:GetPoint(1) }
assert(p2[2] == UIParent, "no strip: the screen's top-right corner, got " .. tostring(p2[2]))
QB:SetEnabled("strip", true); __fire("PLAYER_ENTERING_WORLD")
assert(({ bar:GetPoint(1) })[2] == S:GetFrame(), "and under the strip again")

-- a value the client refuses to give (secret) hides the bar rather than erroring
local realIs = issecretvalue
issecretvalue = function(v) return v == 1240 end
__xp.xp = 1240; __fire("PLAYER_XP_UPDATE"); assert(not bar:IsShown(), "a secret value: nothing shown, no error")
issecretvalue = realIs; __xp.xp = 100; __fire("PLAYER_XP_UPDATE"); assert(bar:IsShown())

-- disabling gives Blizzard's bar back and puts ours away
QB:SetEnabled("xp", false)
assert(not bar:IsShown() and StatusTrackingBarManager:GetAlpha() == 1, "disabled: Blizzard's bar back")
QB:SetEnabled("xp", true)
slash("xp"); for _, l in ipairs(__take()) do io.write(l .. "\n") end
print("xp ok")
