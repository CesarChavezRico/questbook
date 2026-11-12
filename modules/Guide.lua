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
  -- Which settings RestedXP is using, for telling why a write did not show (v0.28.4): its profile's name, and whether the
  -- table saved under that name is the one it reads.
  if type(s) == "table" then
    local name
    local get = _G.RXP.settings.GetSettingsDB
    if type(get) == "function" then
      local ok, v = pcall(get)
      if ok and type(v) == "string" then name = v end
    end
    local saved = type(_G.RXPSettings) == "table" and type(_G.RXPSettings.profiles) == "table" and name and _G.RXPSettings.profiles[name]
    local pos = type(s.framePositions) == "table" and s.framePositions.RXPFrame
    pos = type(pos) == "table" and type(pos[1]) == "table" and pos[1] or nil
    QB:Say(string.format("guide: RestedXP's profile is \"%s\", %s | window at %s",
      tostring(name or "?"),
      saved == nil and "no saved table to compare" or (saved == s and "the saved table is the one in use" or "the saved table is NOT the one in use"),
      pos and string.format("%s %s, %s", tostring(pos[1]), tostring(pos[4]), tostring(pos[5])) or "no saved place"))
  end
end, "guide: RestedXP Guides and our theme for it (status)")
