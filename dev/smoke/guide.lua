-- The RestedXP theme hand-off (4BI-42): before RestedXP starts, the list it reads holds our theme. Stand-in for RestedXP's side:
-- its ImportCustomThemes registers every entry of RXPGuides_Themes, requiring name and author, then empties the list.
assert(type(RXPGuides_Themes) == "table" and #RXPGuides_Themes == 1, "our theme is offered at file load")
local t = RXPGuides_Themes[1]
assert(t.name == "QuestBook" and type(t.author) == "string" and t.author ~= "", "it has the two fields RestedXP requires")
for _, k in ipairs({ "background", "bottomFrameBG", "bottomFrameHighlight", "mapPins" }) do
  assert(type(t[k]) == "table" and #t[k] == 4, k .. " is r, g, b, a")
  for i = 1, 4 do assert(type(t[k][i]) == "number" and t[k][i] >= 0 and t[k][i] <= 1, k .. " in range") end
end
assert(type(t.textColor) == "table" and #t.textColor == 3 and type(t.font) == "string" and t.tooltip:match("^|c%x%x%x%x%x%x%x%x$"), "text colour, font, tooltip colour code")
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function said(pat) for _, l in ipairs(__take()) do if l:find(pat) then return l end end end
assert(QB.modules.guide and QB.modules.guide.active, "the module is on")
SlashCmdList.QUESTBOOK("guide"); assert(said("guide: RestedXP Guides NOT loaded"), "status without RestedXP")
RXPGuides = {}; RXP = { settings = { profile = { activeTheme = "RXP Blue" } } }
SlashCmdList.QUESTBOOK("guide"); assert(said('RestedXP Guides loaded | our theme "QuestBook" offered; the active theme is "RXP Blue"'), "status: another theme active")
RXP.settings.profile.activeTheme = "QuestBook"
SlashCmdList.QUESTBOOK("guide"); assert(said("is the active theme"), "status: ours active")
-- v0.28.4: the status also says which profile RestedXP uses and whether the table saved under that name is the one it reads
RXP.settings.GetSettingsDB = function() return "Thara - PvP" end
RXP.settings.profile.framePositions = { RXPFrame = { { "TOPLEFT", "UIParent", "TOPLEFT", 30, -60 } } }
RXPSettings = { profiles = { ["Thara - PvP"] = RXP.settings.profile } }
SlashCmdList.QUESTBOOK("guide"); assert(said('profile is "Thara %- PvP", the saved table is the one in use | window at TOPLEFT 30, %-60'), "status: same table")
RXPSettings.profiles["Thara - PvP"] = {}
SlashCmdList.QUESTBOOK("guide"); assert(said("the saved table is NOT the one in use"), "status: a different table")
RXPSettings = nil
print("guide: ok")
