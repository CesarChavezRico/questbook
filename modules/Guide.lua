-- QuestBook Guide -- makes RestedXP Guides sit with the rest of the setup (4BI-42).
--
-- Cesar, 2026-11-11: "I am leaning towards a guide for questing and leveling ... Lets take a good look at rested xp addon and see if
-- we can meld it to our setup." RestedXP Guides (github.com/RestedXP/RXPGuides, CC BY-NC-SA 4.0) is its own addon; we only hand it
-- two things through the doors it leaves open, and none of its code or art is here:
--   1. a THEME. Before it starts it reads the global list RXPGuides_Themes and registers every theme in it (its Themes.lua,
--      ImportCustomThemes; its TOC names an optional "RXPGuides_Themes" addon for exactly this). Ours uses the colours of the dark
--      panel of the strip and the drawer. We load before it (alphabetical order), so the list is ready when it looks.
--   2. its SETTINGS, written by /qb layout apply from data/Guide.lua (modules/Loadout.lua): where its windows sit, the scale,
--      which theme is active, and which of its automations are on.
--
-- UNVERIFIED (client only): that RestedXP shows the theme in its list and paints with it; how its own banner art (which a theme
-- cannot replace without supplying textures) looks beside these colours. Written from its source, read 2026-11-11.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("guide", {})

local THEME_NAME = "QuestBook"

-- the dark panel's palette (Style.lua): a warm near-black, cream ink, brass for what is active
local theme = {
  name = THEME_NAME,
  displayName = THEME_NAME,
  author = "Cesar & Nibble",
  background = { 0.07, 0.06, 0.05, 0.88 },
  bottomFrameBG = { 0.10, 0.09, 0.07, 0.88 },
  bottomFrameHighlight = { 0.36, 0.28, 0.14, 1 },
  mapPins = { 0.85, 0.68, 0.35, 1 },
  tooltip = "|cFFD8C88A",
  font = Style.FRIZ,
  textColor = { 0.92, 0.89, 0.82 },
  applicable = true,
}

-- Offered at file load: RestedXP empties the list once it has read it.
if type(_G.RXPGuides_Themes) ~= "table" then _G.RXPGuides_Themes = {} end
table.insert(_G.RXPGuides_Themes, theme)

local function Present()
  return type(_G.RXPGuides) == "table"
end

QB:RegisterSlash(mod, "guide", function()
  local active
  local s = _G.RXP and _G.RXP.settings and _G.RXP.settings.profile
  if type(s) == "table" then active = s.activeTheme end
  QB:Say(string.format("guide: RestedXP Guides %s | our theme \"%s\" %s | /qb layout apply puts its windows and settings in place",
    Present() and "loaded" or "NOT loaded", THEME_NAME,
    active == THEME_NAME and "is the active theme" or (active and ("offered; the active theme is \"" .. tostring(active) .. "\"") or "offered")))
end, "guide: RestedXP Guides and our theme for it (status)")
