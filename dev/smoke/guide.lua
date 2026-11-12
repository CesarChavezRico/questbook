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
-- v0.29.0: where the guide is, and asking about it through the relay. Stand-in for RestedXP's guide in memory.
RXP = nil
SlashCmdList.QUESTBOOK("guide step"); assert(said("guide: RestedXP Guides is not loaded"), "step without RestedXP")
RXP = { settings = { profile = {} } }
SlashCmdList.QUESTBOOK("guide step"); assert(said("no guide is loaded in RestedXP"), "step without a guide")
RXP.currentGuide = { group = "Speedrun Guide 20-30", name = "24-27 Duskwood/Redridge", steps = {
  { index = 1, elements = { { text = "old step" } } },
  { index = 2, active = true, sticky = true, elements = { { text = "|cFFFCDC00Kill|r |T123:0|t Wolves", completed = true }, { text = "Loot |Hitem:1|h[Lean Wolf Flank]|h" } } },
  { index = 3, active = true, elements = { { text = "Grind to level 25", level = 25, xp = 0 }, { tag = "goto" } } },
  { index = 4, elements = { { rawtext = "Turn in Seasoned Wolf Kabobs" } } },
  { index = 5, elements = {} },
  { index = 6, elements = { { text = "six" } } }, { index = 7, elements = { { text = "seven" } } },
} }
RXP.GetGuideProgress = function() return 3 end
SlashCmdList.QUESTBOOK("guide step")
local out = table.concat(__take(), "\n")
assert(out:find("RestedXP guide: Speedrun Guide 20-30 / 24-27 Duskwood/Redridge, step 3 of 7", 1, true), "names the guide and the pointer: " .. out)
assert(out:find("Step 2 (active, stays until done):", 1, true) and out:find("[done] Kill Wolves", 1, true) and out:find("[ ] Loot [Lean Wolf Flank]", 1, true), "active step, plain words, marks: " .. out)
assert(out:find("[ ] Grind to level 25 (level gate: level 25)", 1, true), "a level gate is named")
assert(out:find("Step 4 (next):", 1, true) and out:find("Turn in Seasoned Wolf Kabobs", 1, true) and out:find("Step 5 %(next%):\n.-%(no text%)") and out:find("Step 6 (next)", 1, true) and not out:find("Step 7", 1, true), "three steps ahead by default: " .. out)
assert(not out:find("old step", 1, true) and not out:find("|T", 1, true) and not out:find("|H", 1, true), "nothing behind, no codes")
SlashCmdList.QUESTBOOK("guide step 1"); out = table.concat(__take(), "\n"); assert(out:find("Step 4 (next)", 1, true) and not out:find("Step 5", 1, true), "steps ahead as asked")
-- no step marked active: the pointer's step is the current one
RXP.currentGuide.steps[2].active, RXP.currentGuide.steps[3].active = nil, nil
SlashCmdList.QUESTBOOK("guide step"); assert(said("Step 3 %(current%):"), "falls back to the pointer")
RXP.currentGuide.steps[3].active = true
-- ask: needs the relay addon and a question; sends the question with the place under it
SlashCmdList.QUESTBOOK("guide ask why grind?"); assert(said("the WoW AI relay addon is not loaded"), "ask without the relay")
local sent
WoWAI = { Send = function(t) sent = t end }
SlashCmdList.QUESTBOOK("guide ask"); assert(said("/qb guide ask <your question>") and sent == nil, "ask needs a question")
SlashCmdList.QUESTBOOK("guide ask Why Grind here?"); assert(said("question sent"), "ask says it sent")
assert(sent:find("^Why Grind here%?\n\n%[Where I am in the guide") and sent:find("Grind to level 25", 1, true) and sent:find("Step 4 (next)", 1, true), "the question keeps its case, the place follows: " .. tostring(sent))
local long = string.rep("x", 400)
for i = 4, 7 do RXP.currentGuide.steps[i].elements = { { text = long }, { text = long }, { text = long } } end
SlashCmdList.QUESTBOOK("guide ask q"); __take(); assert(#sent < 2400 and sent:find("cut here", 1, true), "a long place is cut to fit one message: " .. #sent)
SlashCmdList.QUESTBOOK("guide bogus"); assert(said("/qb guide || step"), "usage for an unknown word")
-- the automatic form: a relay addon with RegisterContext is offered a function at enable; it returns the place, capped
SlashCmdList.QUESTBOOK("guide"); assert(said("use /qb guide ask"), "status: no attachments without the door")
local offered = {}
WoWAI = { Send = function(t) sent = t; offered.during = offered.fn and offered.fn() end, RegisterContext = function(k, fn) offered.key, offered.fn = k, fn; return true end }
QB:Disable("guide"); QB:Enable("guide"); __take()
assert(offered.key == "questbook-guide" and type(offered.fn) == "function", "offered at enable")
SlashCmdList.QUESTBOOK("guide"); assert(said("goes with your messages to the relay"), "status: attaching")
local auto = offered.fn()
assert(#auto <= 1000 + 12 and auto:find("^%[Where I am in the guide, attached by QuestBook%]\nRestedXP guide: ") and auto:find("(cut here)", 1, true), "the place, capped: " .. #auto)
SlashCmdList.QUESTBOOK("guide ask q2"); __take(); assert(offered.during == nil and offered.fn() ~= nil, "during /qb guide ask the automatic block stays out")
RXP.currentGuide = nil; assert(offered.fn() == nil, "no guide: nothing to attach")
QB:Disable("guide"); assert(offered.fn == nil, "taken back when the module is switched off"); QB:Enable("guide"); __take()
RXP, WoWAI = nil, nil
print("guide: ok")
