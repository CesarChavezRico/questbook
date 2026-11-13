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

local mod = QB:NewModule("guide", {
  read = true,          -- read each new step of the guide aloud (the relay's ElevenLabs voice, slot "guide")
  bar = true,           -- show the reader's control (Pause / Skip / Voice on)
  barPos = false,       -- { point, x, y } once it has been dragged; false = its default place
})

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

-- The quests in the log that are ready to turn in, set against the REST of the loaded guide (v0.30.3). First client use,
-- 2026-11-12: at a level gate ("Grind to 29845+/34000xp") with 12 quests ready, the answer could not say whether turning
-- them in was extra experience or experience the guide had already counted for later ("What I can't see is whether those
-- turn-ins are later steps in the guide"). A turn-in line of the guide is an element with tag "turnin" and a questId.
-- Only the loaded chapter is known: a quest the next chapter turns in shows as "not in the rest".
local function ReadyLines(guide, from, out)
  local okS, quests = QB:Call("questlog", "Scan")
  if not okS or type(quests) ~= "table" then return end
  local at = {}
  for i = from, #guide.steps do
    local step = guide.steps[i]
    if type(step) == "table" and type(step.elements) == "table" then
      for _, e in ipairs(step.elements) do
        if type(e) == "table" and e.tag == "turnin" and type(e.questId) == "number" and not at[e.questId] then at[e.questId] = i end
      end
    end
  end
  local later, extra = {}, {}
  for _, q in ipairs(quests) do
    local ready = false
    if C_QuestLog and C_QuestLog.ReadyForTurnIn then
      local ok, r = pcall(C_QuestLog.ReadyForTurnIn, q.questID); ready = ok and r and true or false
    elseif C_QuestLog and C_QuestLog.IsComplete then
      local ok, r = pcall(C_QuestLog.IsComplete, q.questID); ready = ok and r and true or false
    end
    if ready then
      local title = Clean(q.title) or ("quest " .. tostring(q.questID))
      if at[q.questID] then later[#later + 1] = string.format("%s (step %d)", title, at[q.questID]) else extra[#extra + 1] = title end
    end
  end
  if type(UnitXP) == "function" and type(UnitXPMax) == "function" and type(UnitLevel) == "function" then
    local okX, xp, max, level = pcall(function() return UnitXP("player"), UnitXPMax("player"), UnitLevel("player") end)
    if okX and type(xp) == "number" and type(max) == "number" then out[#out + 1] = string.format("Experience now: %d of %d at level %s", xp, max, tostring(level)) end
  end
  if #later + #extra == 0 then out[#out + 1] = "Quests ready to turn in: none"; return end
  if #later > 0 then out[#out + 1] = "Ready to turn in, and the guide turns them in later (their experience is already in its plan): " .. table.concat(later, "; ") end
  if #extra > 0 then out[#out + 1] = "Ready to turn in, and NOT in the rest of this guide chapter (extra experience): " .. table.concat(extra, "; ") end
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
  local okR = pcall(ReadyLines, guide, pointer or last, out)
  if not okR then out[#out + 1] = "(the ready quests could not be read)" end
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
  mod.asking = true     -- the place is already in this message: the automatic attachment below stays out of it
  local ok, err = pcall(W.Send, question .. "\n\n[Where I am in the guide, sent by /qb guide ask]\n" .. block)
  mod.asking = nil
  if not ok then QB:Say("guide: the relay did not take the message: " .. tostring(err)); return false end
  QB:Say("guide: question sent with the guide's place; the answer comes in the WoW AI window")
  return true
end

-- The automatic form (Cesar, 2026-11-12: asking from the chat box with /ask should just work). A relay addon that has
-- WoWAI.RegisterContext asks this function for text with every message, and puts it under the words when it has changed
-- since the last one. Registered at login, when the relay addon (which loads after us) is there. An older relay addon has
-- no such door: /qb guide ask stays the way.
local AUTO_MAX = 1000
local function Attached()
  if mod.asking then return nil end
  local lines = Where(3)
  if not lines then return nil end
  local block = "[Where I am in the guide, attached by QuestBook]"
  for _, l in ipairs(lines) do
    if #block + #l + 1 > AUTO_MAX then block = block .. "\n(cut here)"; break end
    block = block .. "\n" .. l
  end
  return block
end

local function Offer(fn)
  local W = _G.WoWAI
  if type(W) == "table" and type(W.RegisterContext) == "function" then
    local ok, took = pcall(W.RegisterContext, "questbook-guide", fn)
    return ok and took and true or false
  end
  return false
end

-- ---------------------------------------------------------------- the guide read aloud (v0.30.0)
--
-- Cesar, 2026-11-12: "connect the guide to the bridge and have the instructions ... read to me while questing"; "Let's use
-- ElevenLabs for the guide too"; "a 'reader control' that can pause/play, skip and disable the reader".
-- Every second and a half we look at which steps RestedXP has active; a step not read yet in this session is sent to the
-- relay's voice helper as a QUEUED reading in the voice slot "guide" (WoWAI.SendTts "queue": it waits for what is playing,
-- so it never cuts a quest being read). Looking, instead of listening for RestedXP's own "step activated" message, works
-- the same with either of its guide windows. The control drives the bridge's reader: pause, resume, skip.
-- UNVERIFIED (client and rig): all of it. A relay addon without "queue" gets "play" (which cuts what is playing).
local READ_EVERY = 1.5
local READ_MAX = 500            -- characters of one step read aloud
local CONNECT_GAP = 45          -- seconds between asking a quiet relay to reconnect
local spoken = {}               -- ["group/name:index"] = true: steps already sent this session
local ticker, lastConnect, noQueue

local function StepSpeech(step)
  local parts = {}
  if type(step) ~= "table" or type(step.elements) ~= "table" then return nil end
  for _, e in ipairs(step.elements) do
    if type(e) == "table" and not e.completed and not e.skip then
      local text = Clean(e.text) or Clean(e.rawtext) or Clean(e.tooltipText)
      if text then
        text = text:gsub("%[(.-)%]", "%1")                  -- [Lean Wolf Flank] is read as its name
        if not text:find("[%.%!%?]$") then text = text .. "." end
        parts[#parts + 1] = text
      end
    end
  end
  if #parts == 0 then return nil end
  local text = table.concat(parts, " ")
  if #text > READ_MAX then text = text:sub(1, READ_MAX) end
  return text
end

-- true when the request went out; false and why otherwise ("wait" = the relay is quiet, try again on the next look)
local function Speak(ref, text)
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.SendTts) == "function") then return false, "norelay" end
  if type(W.IsConnected) == "function" and not W.IsConnected() then
    local now = GetTime and GetTime() or 0
    if type(W.Connect) == "function" and (not lastConnect or now - lastConnect >= CONNECT_GAP) then
      lastConnect = now
      pcall(W.Connect)
    end
    return false, "wait"
  end
  local ok, sent, err = pcall(W.SendTts, noQueue and "play" or "queue", "guide", ref, text)
  if ok and not sent and err == "bad action" and not noQueue then
    noQueue = true                                          -- an older relay addon: no queue, so each step cuts the one before
    ok, sent, err = pcall(W.SendTts, "play", "guide", ref, text)
  end
  if ok and sent then return true end
  return false, tostring(err or sent)
end

local RefreshUsage                 -- (defined with the bar: repaints it when the numbers changed)

local function Look()
  if RefreshUsage then RefreshUsage() end
  if not (mod.db and mod.db.read) or mod.paused then return end
  local rxp = _G.RXP
  local guide = type(rxp) == "table" and rxp.currentGuide
  if type(guide) ~= "table" or type(guide.steps) ~= "table" then return end
  local key = tostring(guide.group or "?") .. "/" .. tostring(guide.name or "?") .. ":"
  for i, step in ipairs(guide.steps) do
    if type(step) == "table" and step.active and not spoken[key .. i] then
      local text = StepSpeech(step)
      if not text then
        spoken[key .. i] = true                             -- nothing to say (all done, or no words)
      else
        local ok, why = Speak("g" .. i, text)
        if ok then spoken[key .. i] = true elseif why == "wait" or why == "norelay" then return end
        if not ok then spoken[key .. i] = true end          -- refused for another reason (too long ...): do not retry forever
      end
    end
  end
end

local function Control(action)
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.SendTts) == "function") then return false end
  local ok, sent = pcall(W.SendTts, action, "", "", "")
  return ok and sent and true or false
end

-- the control: three words on a small dark panel, dragged with the left button
local bar
local PAL = { normal = { 0.92, 0.89, 0.82 }, hot = { 0.98, 0.92, 0.76 }, faded = { 0.60, 0.57, 0.50 }, warn = { 0.85, 0.68, 0.35 } }

-- What the voice has cost, from the relay addon (WoWAI.VoiceUsage: ElevenLabs credits used of the account's total, and
-- the average one paid reading costs this month). The bridge sends it with whatever the game reads next, so it can be
-- some minutes behind. nil when the relay addon does not have it (an older one, or nothing heard yet).
local function Short(n)
  n = tonumber(n) or 0
  if n >= 1000000 then return string.format("%.2fM", n / 1000000) end
  if n >= 10000 then return string.format("%.1fk", n / 1000) end
  return string.format("%d", n)
end

local function Usage()
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.VoiceUsage) == "function") then return nil end
  local ok, v = pcall(W.VoiceUsage)
  if not ok or type(v) ~= "table" or type(v.total) ~= "number" then return nil end
  return v
end

local function UsageText()
  local v = Usage()
  if not v then return "credits: not known yet" end
  return string.format("%s / %s credits \194\183 %s avg", Short(v.used), Short(v.total), Short(v.avg))
end

local function PaintBar()
  if not bar then return end
  bar.pause:SetText(mod.paused and "Play" or "Pause")
  bar.onoff:SetText(mod.db.read and "Voice on" or "Voice off")
  bar.onoff:SetWarn(not mod.db.read)
  bar.pause:SetEnabled(mod.db.read); bar.skip:SetEnabled(mod.db.read)
  local x = Style.Px(12, bar)
  for _, b in ipairs({ bar.pause, bar.skip, bar.onoff }) do
    b:ClearAllPoints(); b:SetPoint("LEFT", bar, "LEFT", x, 0)
    x = x + b:GetWidth() + Style.Px(18, bar)
  end
  bar.shownUsage = UsageText()
  bar.usage:SetText(bar.shownUsage)
  bar.usage:ClearAllPoints(); bar.usage:SetPoint("LEFT", bar, "LEFT", x, 0)
  x = x + bar.usage:GetStringWidth() + Style.Px(18, bar)
  bar:SetWidth(x - Style.Px(6, bar))
  if mod.db.bar and mod.active then bar:Show() else bar:Hide() end
end

RefreshUsage = function()
  if bar and bar.shownUsage ~= UsageText() then PaintBar() end
end

local function PlaceBar()
  bar:ClearAllPoints()
  local p = mod.db.barPos
  if type(p) == "table" and p[1] then bar:SetPoint(p[1], UIParent, p[1], p[2] or 0, p[3] or 0)
  else bar:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -130) end
end

function mod:SetPaused(on)
  on = on and true or false
  if on == (mod.paused or false) then return end
  mod.paused = on
  Control(on and "pause" or "resume")
  PaintBar()
end

function mod:Skip() Control("skip") end

function mod:SetRead(on)
  mod.db.read = on and true or false
  if not mod.db.read then Control("stop"); mod.paused = false end
  PaintBar()
end

local function BuildBar()
  if bar then return end
  bar = CreateFrame("Frame", "QuestBookReaderBar", UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetHeight(Style.Px(30, bar))
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(bar)
  bar.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar.bg:SetVertexColor(0.07, 0.06, 0.05, 0.88)
  bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton"); bar:SetClampedToScreen(true)
  bar:SetScript("OnDragStart", bar.StartMoving)
  bar:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    local point, _, _, x, y = f:GetPoint(1)
    if point then mod.db.barPos = { point, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5) } end
  end)
  bar.pause = Style.InkLink(bar, 15, function() mod:SetPaused(not mod.paused) end, PAL)
  bar.skip = Style.InkLink(bar, 15, function() mod:Skip() end, PAL); bar.skip:SetText("Skip")
  bar.onoff = Style.InkLink(bar, 15, function() mod:SetRead(not mod.db.read) end, PAL)
  bar.usage = bar:CreateFontString(nil, "OVERLAY")
  bar.usage:SetFont(Style.FRIZ, Style.Px(13, bar), "")
  bar.usage:SetTextColor(PAL.faded[1], PAL.faded[2], PAL.faded[3], 1)
  PlaceBar()
end

function mod:OnEnable()
  mod.attaching = Offer(Attached)
  BuildBar(); PaintBar()
  if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(READ_EVERY, function() QB:Safe(mod, Look) end) end
end

function mod:OnDisable()
  Offer(nil); mod.attaching = false
  if ticker then ticker:Cancel(); ticker = nil end
  if bar then bar:Hide() end
end

local function ReaderSlash(sub, tail)
  tail = (tail or ""):lower():match("^(%S*)")
  if sub == "read" then
    if tail == "on" or tail == "off" then mod:SetRead(tail == "on") elseif tail ~= "" then QB:Usage("/qb guide read on | off") end
    QB:Say("guide: the steps are " .. (mod.db.read and "read aloud (the relay's voice slot \"guide\")" or "not read aloud"))
  elseif sub == "pause" then mod:SetPaused(true); QB:Say("guide: reading paused (/qb guide play)")
  elseif sub == "play" then mod:SetPaused(false); QB:Say("guide: reading goes on")
  elseif sub == "skip" then mod:Skip(); QB:Say("guide: skipped")
  elseif sub == "bar" then
    if tail == "on" or tail == "off" then mod.db.bar = tail == "on"
    elseif tail == "reset" then mod.db.barPos = false; if bar then PlaceBar() end
    elseif tail ~= "" then QB:Usage("/qb guide bar on | off | reset") end
    PaintBar()
    QB:Say("guide: the reader's control is " .. (mod.db.bar and "shown (drag it with the left button)" or "hidden"))
  end
  return true
end

QB:RegisterSlash(mod, "guide", function(rest)
  local sub, tail = (rest or ""):match("^%s*(%S*)%s*(.*)$")
  sub = (sub or ""):lower()
  if sub == "step" then return ShowStep(tail) end
  if sub == "ask" then return Ask(tail) end
  if sub == "read" or sub == "pause" or sub == "play" or sub == "skip" or sub == "bar" then return ReaderSlash(sub, tail) end
  if sub ~= "" and sub ~= "status" then QB:Usage("/qb guide | step [steps ahead] | ask <your question> | read on|off | pause | play | skip | bar on|off|reset") end
  local active
  local s = _G.RXP and _G.RXP.settings and _G.RXP.settings.profile
  if type(s) == "table" then active = s.activeTheme end
  QB:Say(string.format("guide: RestedXP Guides %s | our theme \"%s\" %s | /qb layout apply puts its windows and settings in place",
    Present() and "loaded" or "NOT loaded", THEME_NAME,
    active == THEME_NAME and "is the active theme" or (active and ("offered; the active theme is \"" .. tostring(active) .. "\"") or "offered")))
  QB:Say("guide: the steps are " .. (mod.db.read and (mod.paused and "read aloud, paused now" or "read aloud") or "not read aloud")
    .. " | /qb guide read on, read off, pause, play, skip, bar on, bar off")
  do
    local v = Usage()
    if v then
      local age = (type(_G.time) == "function" and v.at and v.at > 0) and math.max(0, math.floor((_G.time() - v.at) / 60)) or nil
      QB:Say(string.format("guide: voice credits %d of %d (%s), %d paid readings this month, %d credits each on average%s",
        v.used, v.total, v.source == "account" and "the ElevenLabs account" or "the bridge's own count against its cap", v.made, v.avg,
        age and string.format(", as of %d min ago", age) or ""))
    else
      QB:Say("guide: voice credits not known yet (the relay addon has not heard them from the bridge)")
    end
  end
  QB:Say("guide: " .. (mod.attaching and "the step you are on goes with your messages to the relay (/ask ...) when it has changed"
    or "the relay addon does not take attachments (or is not loaded): use /qb guide ask <question>"))
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
end, "guide: RestedXP Guides: status | step [steps ahead] (where the guide is) | ask <question> (send it to the relay with the guide's place) | read on|off, pause, play, skip, bar on|off (the steps read aloud)")
