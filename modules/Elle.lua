-- QuestBook Elle -- a Play / Stop button on the quest rows of EllesmereUI's quest tracker (4BI-38).
--
-- Cesar, 2026-11-09: "playing the quest text looks painful. Can we integrate the play/stop button into the elle's tracker?"
-- Our own list is retired in favour of Ellesmere's, and with it went the list's Play button. EllesmereUI publishes a plugin API for
-- exactly this (EllesmereUI/PLUGINS_API.md, PLUGIN_API_VERSION 5: "the API only ever grows; existing functions and fields will not
-- change"): EllesmereUI.RegisterQuestTrackerRow(id, fn, width) calls fn(slot, questID, title) for every quest title row each time
-- its Custom Quest Tracker redraws (WoW Forever only, and only while the Custom Quest Tracker is on). `slot` is our own frame at
-- the right end of the title, `width` wide; we put a small button on it, create it once per slot, set everything from questID on every
-- call, and never use a secure frame there (the tracker moves and hides its rows in combat). Written from that document alone.
--
-- The button reads the quest aloud with whatever voice engine is set (QuestLog:PlayQuest: the relay's ElevenLabs voice or the game's
-- own), says Stop while that quest is being read, and Play otherwise. It follows the reading through the "speech_state" topic.
--
-- UNVERIFIED (client only): that the button shows and clicks inside Ellesmere's rows on this client; how it looks next to Ellesmere's
-- own row icons; that a click does not also fall through to the row. Nothing here touches Ellesmere's frames except our own slot.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("elle", {
  width = 34,      -- pixels kept free right of each title for the button (the API allows 0 to 64)
})

local ID = "QuestBook"          -- our id in the registry: "your addon's folder name" (one registration per id)
local registered = false
local buttons = {}              -- slot -> its button

local function Present()
  return type(_G.EllesmereUI) == "table" and type(_G.EllesmereUI.RegisterQuestTrackerRow) == "function"
end

-- What the button says for a quest: Stop while it is the quest being read, Play otherwise.
local function Label(questID)
  local ok, speaking = QB:Call("questlog", "SpeakingQuestID")
  if ok and speaking and speaking == questID then return "Stop", true end
  return "Play", false
end

local function Paint(b)
  local text, on = Label(b.questID)
  b.label:SetText(text)
  local c = on and { 0.95, 0.60, 0.45 } or { 0.85, 0.82, 0.72 }       -- warm while it speaks, cream otherwise (the dark panel's inks)
  b.label:SetTextColor(c[1], c[2], c[3], b.over and 1 or 0.8)
end

local function Dress(slot, questID, title)
  if not mod.active then
    if buttons[slot] then buttons[slot]:Hide() end
    return
  end
  local b = buttons[slot]
  if not b then
    b = CreateFrame("Button", nil, slot)
    b:SetPoint("RIGHT", slot, "RIGHT", 0, 0)
    b.label = b:CreateFontString(nil, "OVERLAY")
    b.label:SetFont(Style.FRIZ, 12, "")            -- a font at birth: SetText on a fontless string is an error
    b.label:SetPoint("RIGHT", b, "RIGHT", 0, 0)
    b.label:SetJustifyH("RIGHT")
    b.label:SetShadowOffset(1, -1)
    b.label:SetShadowColor(0, 0, 0, 0.85)
    b:SetScript("OnEnter", function(self) self.over = true; Paint(self) end)
    b:SetScript("OnLeave", function(self) self.over = false; Paint(self) end)
    b:SetScript("OnClick", function(self)
      local q = self.questID
      if q then QB:Safe(mod, function() QB:Call("questlog", "PlayQuest", q) end) end
    end)
    buttons[slot] = b
  end
  b.questID = questID
  -- the title's own font and size, so the button sits with the text; the slot is as tall as the title
  local font, size
  if title and title.GetFont then font, size = title:GetFont() end
  if font and size then b.label:SetFont(font, math.max(9, size - 1), "") end
  local w = tonumber(mod.db.width) or 34
  b:SetSize(math.max(16, w), math.max(12, slot:GetHeight() or 14))
  Paint(b)
  b:Show()
end

local function Refresh()
  if Present() and type(_G.EllesmereUI.RefreshQuestTrackerRows) == "function" then pcall(_G.EllesmereUI.RefreshQuestTrackerRows) end
  for _, b in pairs(buttons) do if b:IsShown() then Paint(b) end end
end

-- Register once (the registry has no unregister: a disabled module hides its buttons and the callback does nothing).
function mod:Register()
  if registered or not Present() then return registered end
  local ok, res = pcall(_G.EllesmereUI.RegisterQuestTrackerRow, ID, function(slot, questID, title)
    local okD, err = pcall(Dress, slot, questID, title)
    if not okD then QB:ReportError("elle", err) end
  end, tonumber(self.db.width) or 34)
  registered = ok and res and true or false
  self.registerNote = registered and "registered" or (ok and "refused (id taken or bad argument)" or ("error: " .. tostring(res)))
  return registered
end

function mod:OnInit()
  if type(CreateFrame) ~= "function" then self.unavailable = "no UI" end
end

function mod:OnEnable()
  if not self:Register() then
    -- EllesmereUI's tracker may load after us: try again once the world is up
    self.waiting = true
  end
  Refresh()
end

function mod:OnDisable()
  for _, b in pairs(buttons) do b:Hide() end
  Refresh()
end

mod.events.PLAYER_ENTERING_WORLD = function(self)
  if self.waiting and self:Register() then self.waiting = false; Refresh() end
end

-- the reading started or ended: relabel, and let the tracker redraw (it may also be showing a different quest)
QB:On("speech_state", function() if mod.active then Refresh() end end, mod)

QB:RegisterSlash(mod, "elle", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  if sub == "width" and n then
    mod.db.width = Style.Clamp(math.floor(n), 16, 64)
    QB:Say("elle: the width applies after /reload (EllesmereUI reserves it once, when we register)")
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb elle | width <16-64>")
  end
  local shown = 0
  for _, b in pairs(buttons) do if b:IsShown() then shown = shown + 1 end end
  QB:Say(string.format("elle: EllesmereUI %s | quest tracker row hook %s | %s | %d button(s) showing | width %d",
    type(_G.EllesmereUI) == "table" and "loaded" or "NOT loaded", Present() and "available" or "NOT available (needs the Custom Quest Tracker, WoW Forever)",
    mod.registerNote or "not registered", shown, tonumber(mod.db.width) or 34))
end, "elle: the Play / Stop button on EllesmereUI's quest tracker rows (status, width)")
