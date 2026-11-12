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

-- ---------------------------------------------------------------- where the guide is (v0.29.0)
--
-- Cesar, 2026-11-12: "A way to discuss the guide with you through the relay ... get from the guide the step I am on so we can
-- discuss it". RestedXP keeps the loaded guide in memory (RXP.currentGuide: group, name, steps; a step has .index, .active and
-- .elements, an element has .text / .rawtext / .tooltipText, .completed, .skip, and for a level gate .level and .xp). We only
-- READ it, at the moment of asking, and only the steps around the pointer: nothing of the guide is stored by QuestBook.
-- UNVERIFIED (client only): the field names come from its source (GuideWindow.lua, functions.lua, read 2026-11-12).

-- A guide line as plain words: no colour codes, icons or links (the chat frame would also choke on a stray "|").
local function Clean(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|A.-|a", "")
  s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|n", " "):gsub("|", "/"):gsub("[\r\n]+", " "):gsub("%s+", " ")
  s = s:gsub("^%s+", ""):gsub("%s+$", "")
  if s == "" then return nil end
  return s
end

local function StepLines(step, out, marks)
  local n = 0
  if type(step) ~= "table" or type(step.elements) ~= "table" then return 0 end
  for _, e in ipairs(step.elements) do
    if type(e) == "table" then
      local text = Clean(e.text) or Clean(e.rawtext) or Clean(e.tooltipText)
      if text then
        local mark = ""
        if marks then mark = e.completed and "[done] " or (e.skip and "[skipped] " or "[ ] ") end
        local gate = ""
        if type(e.level) == "number" and e.xp ~= nil then gate = string.format(" (level gate: level %d)", e.level) end
        out[#out + 1] = "  " .. mark .. text .. gate
        n = n + 1
      end
    end
  end
  return n
end

-- The guide's place as lines of text: the active steps with what is done, then `ahead` steps after them. nil and why when
-- there is nothing to read.
local function Where(ahead)
  local rxp = _G.RXP
  if type(rxp) ~= "table" then return nil, "RestedXP Guides is not loaded" end
  local guide = rxp.currentGuide
  if type(guide) ~= "table" or type(guide.steps) ~= "table" or #guide.steps == 0 then return nil, "no guide is loaded in RestedXP" end
  local pointer
  if type(rxp.GetGuideProgress) == "function" then
    local ok, v = pcall(rxp.GetGuideProgress)
    if ok and type(v) == "number" then pointer = v end
  end
  local out = { string.format("RestedXP guide: %s / %s, step %s of %d",
    tostring(guide.group or "?"), tostring(guide.displayname or guide.name or "?"), tostring(pointer or "?"), #guide.steps) }
  local last = 0
  for i, step in ipairs(guide.steps) do
    if type(step) == "table" and step.active then
      out[#out + 1] = string.format("Step %d (active%s):", i, step.sticky and ", stays until done" or "")
      if StepLines(step, out, true) == 0 then out[#out + 1] = "  (no text)" end
      last = i
    end
  end
  if last == 0 and pointer and guide.steps[pointer] then
    out[#out + 1] = string.format("Step %d (current):", pointer)
    if StepLines(guide.steps[pointer], out, true) == 0 then out[#out + 1] = "  (no text)" end
    last = pointer
  end
  if last == 0 then return nil, "RestedXP has a guide but no active step" end
  for i = last + 1, math.min(last + (ahead or 3), #guide.steps) do
    out[#out + 1] = string.format("Step %d (next):", i)
    if StepLines(guide.steps[i], out, false) == 0 then out[#out + 1] = "  (no text)" end
  end
  return out
end

local ASK_MAX = 2200   -- bytes of guide text sent with a question: the relay carries about 2900 per message, question included

local function ShowStep(rest)
  local ahead = tonumber((rest or ""):match("(%d+)")) or 3
  local lines, why = Where(math.min(ahead, 10))
  if not lines then QB:Say("guide: " .. why); return false end
  for _, l in ipairs(lines) do QB:Say(l) end
  return true
end

-- /qb guide ask <question>: the question goes to the WoW AI window's current chat (the relay), with the guide's place under it.
local function Ask(question)
  question = (question or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if question == "" then QB:Usage("/qb guide ask <your question>"); return false end
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.Send) == "function") then QB:Say("guide: the WoW AI relay addon is not loaded, so there is nobody to ask from here"); return false end
  local lines, why = Where(3)
  if not lines then QB:Say("guide: " .. why); return false end
  local block, cut = "", false
  for _, l in ipairs(lines) do
    if #block + #l + 1 > ASK_MAX then cut = true; break end
    block = block .. l .. "\n"
  end
  if cut then block = block .. "(cut here: too long for one message)\n" end
  local ok, err = pcall(W.Send, question .. "\n\n[Where I am in the guide, sent by /qb guide ask]\n" .. block)
  if not ok then QB:Say("guide: the relay did not take the message: " .. tostring(err)); return false end
  QB:Say("guide: question sent with the guide's place; the answer comes in the WoW AI window")
  return true
end

QB:RegisterSlash(mod, "guide", function(rest)
  local sub, tail = (rest or ""):match("^%s*(%S*)%s*(.*)$")
  sub = (sub or ""):lower()
  if sub == "step" then return ShowStep(tail) end
  if sub == "ask" then return Ask(tail) end
  if sub ~= "" and sub ~= "status" then QB:Usage("/qb guide | step [steps ahead] | ask <your question>") end
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
end, "guide: RestedXP Guides: status | step [steps ahead] (where the guide is) | ask <question> (send it to the relay with the guide's place)")
