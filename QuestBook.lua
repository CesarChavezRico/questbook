-- QuestBook v0.5.3 -- a readable page for quests you already accepted.
--
-- WHY: the quest log's text is small and cramped; reading it is how we
-- navigate (no Questie by choice). This opens the selected quest as one
-- big, quiet, readable page. Display only; no combat APIs anywhere near it.
--
-- v0.4.2: TTS fixed/diagnosable -- the voice is now resolved from the
-- client's installed voice list (GetTtsVoices) instead of assuming ID 0,
-- and three commands exist to see what's happening:
--   /qb say            speak a test line + print diagnostics
--   /qb voices         list installed TTS voices with their IDs
--   /qb usevoice <id>  pick a voice (saved)
--
-- COMMANDS:
--   /qb            toggle the book
--   /qb size <n>   body font size (default 17)
--   /qb dark       toggle the darkened backdrop
--   /qb voice      toggle walk-and-listen TTS (default on)
--   /qb debug      narrate the walk-and-listen chain in chat
--
-- v0.5: dock controls — [<] [read] [>]: step through quests with instant
-- narration; the read/stop button restarts or silences the narrator and
-- works regardless of the /qb voice auto-setting (buttons are intent).

local ADDON_NAME = ...
local DEFAULTS = { fontSize = 17, width = 1040, height = 860, darken = true, voice = true, voiceID = nil }

local db
local Book        -- main frame
local ListButtons = {}
local docked = false
local lastEntry, lastDesc
local debugMode = false
local currentEntries = {}
local currentIndex
local isSpeaking = false
local NavQuest, SpeakerToggle   -- forward declarations (buttons close over them)
local function Dbg(msg) if debugMode then print("|cff7faaffQB-debug|r: " .. msg) end end

-- ---------------------------------------------------------------- helpers

local function InitDB()
  QuestBookDB = QuestBookDB or {}
  for k, v in pairs(DEFAULTS) do
    if QuestBookDB[k] == nil then QuestBookDB[k] = v end
  end
  db = QuestBookDB
end

local function GetLogEntries()
  local entries = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
    if ok and n then
      for i = 1, n do
        local ok2, info = pcall(C_QuestLog.GetInfo, i)
        if ok2 and info and not info.isHeader and info.questID then
          entries[#entries + 1] = { index = i, questID = info.questID, title = info.title, level = info.level }
        end
      end
      return entries
    end
  end
  if GetNumQuestLogEntries and GetQuestLogTitle then
    local n = GetNumQuestLogEntries() or 0
    for i = 1, n do
      local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if title and not isHeader then
        entries[#entries + 1] = { index = i, questID = questID, title = title, level = level }
      end
    end
  end
  return entries
end

local UNAVAILABLE = "|cff888888(text unavailable -- tell Nibble the quest name)|r"

local function GetQuestText(entry)
  local desc, obj
  if C_QuestLog and C_QuestLog.SetSelectedQuest then
    pcall(C_QuestLog.SetSelectedQuest, entry.questID)
  elseif SelectQuestLogEntry then
    pcall(SelectQuestLogEntry, entry.index)
  end
  if GetQuestLogQuestText then
    local ok, d, o = pcall(GetQuestLogQuestText)
    if ok and (d or o) then desc, obj = d, o end
    if not desc then
      local ok2, d2, o2 = pcall(GetQuestLogQuestText, entry.index)
      if ok2 then desc, obj = d2, o2 end
    end
  end

  local lines = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, list = pcall(C_QuestLog.GetQuestObjectives, entry.questID)
    if ok and type(list) == "table" then
      for _, item in ipairs(list) do
        if item.text and item.text ~= "" then
          lines[#lines + 1] = (item.finished and "|cff6fca6f" or "|cffd8c88a") .. "- " .. item.text .. "|r"
        end
      end
    end
  elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    local ok, n = pcall(GetNumQuestLeaderBoards, entry.index)
    if ok and n then
      for j = 1, n do
        local ok2, text, _, finished = pcall(GetQuestLogLeaderBoard, j, entry.index)
        if ok2 and text then
          lines[#lines + 1] = (finished and "|cff6fca6f" or "|cffd8c88a") .. "- " .. text .. "|r"
        end
      end
    end
  end

  local objectivesBlock = (#lines > 0 and table.concat(lines, "\n")) or obj or UNAVAILABLE
  return desc or UNAVAILABLE, objectivesBlock
end

-- ---------------------------------------------------------------- voice

local function Say(msg) print("|cffd8c88aQuestBook|r: " .. msg) end

-- The client only speaks for a voiceID it actually has installed. Resolve
-- the saved pick, else the first installed voice; nil = no voices at all.
local function ResolveVoice()
  if not (C_VoiceChat and C_VoiceChat.GetTtsVoices) then return nil, "no GetTtsVoices API" end
  local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
  if not ok or type(voices) ~= "table" or #voices == 0 then return nil, "no TTS voices installed" end
  if db.voiceID then
    for _, v in ipairs(voices) do
      if v.voiceID == db.voiceID then return v.voiceID, nil end
    end
  end
  return voices[1].voiceID, nil
end

local function SpeakText(text)
  if not (C_VoiceChat and C_VoiceChat.SpeakText) then return false, "no SpeakText API" end
  local voiceID, why = ResolveVoice()
  if not voiceID then return false, why end
  -- Forever's signature (per Blizzard's API docs in the client dump,
  -- 2026-10-03): SpeakText(voiceID, text, rate, volume[, overlap]) -- the
  -- retail-era destination parameter is GONE. Passing it shifted rate into
  -- volume's seat and spoke at volume 0: silent, errorless. Found by the
  -- /qb say diagnostics + the dump.
  local ok, err = pcall(C_VoiceChat.SpeakText, voiceID, text, 0, 100)
  if not ok then return false, "SpeakText error: " .. tostring(err) end
  return true, nil
end

local function Speak(entry, desc, force)
  if not db then Dbg("no db — InitDB never ran?") return end
  if not force and not db.voice then Dbg("voice is OFF (/qb voice)") return end
  if not desc then Dbg("no description cached") return end
  if desc == UNAVAILABLE then Dbg("description unavailable") return end
  Dbg("calling SpeakText…")
  local ok, why = SpeakText(((entry and entry.title) or "") .. ". " .. desc)
  if not ok and why then Say("voice problem: " .. why .. " (try /qb voices)") end
end

local function SetSpeaking(state)
  isSpeaking = state
  if Book and Book.speaker then Book.speaker:SetText(state and "stop" or "talk") end
end

local function StopSpeaking()
  if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
  SetSpeaking(false)   -- a killed speech fires no FINISHED event; reset locally
end

-- ---------------------------------------------------------------- UI

local FONT = "Fonts\\FRIZQT__.TTF"
local ShowQuest      -- forward declaration
local OnStartedMoving -- forward declaration

local function ApplyLayout()
  if docked then
    Book:ClearAllPoints(); Book:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
    Book:SetSize(440, 540)
    Book.list:Hide(); Book.shade:Hide()
    Book.page:ClearAllPoints()
    Book.page:SetPoint("TOPLEFT", 16, -36); Book.page:SetPoint("BOTTOMRIGHT", -30, 14)
  else
    Book:ClearAllPoints(); Book:SetPoint("CENTER")
    Book:SetSize(db.width, db.height)
    Book.list:Show(); Book.shade:SetShown(db.darken)
    Book.page:ClearAllPoints()
    Book.page:SetPoint("TOPLEFT", 340, -20); Book.page:SetPoint("BOTTOMRIGHT", -36, 20)
  end
  local w = docked and 380 or (db.width - 400)
  Book.title:SetWidth(w); Book.objectives:SetWidth(w); Book.body:SetWidth(w)
  Book.pageChild:SetWidth(w + 20)
  if lastEntry then ShowQuest(lastEntry) end
end

local function BuildBook()
  Book = CreateFrame("Frame", "QuestBookFrame", UIParent, "BackdropTemplate")
  Book:SetFrameStrata("HIGH")
  Book:SetMovable(true); Book:EnableMouse(true)
  Book:RegisterForDrag("LeftButton")
  Book:SetScript("OnDragStart", Book.StartMoving)
  Book:SetScript("OnDragStop", Book.StopMovingOrSizing)
  Book:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  Book:SetBackdropColor(0.07, 0.06, 0.05, 0.96)
  Book:Hide()
  Book:SetScript("OnHide", StopSpeaking)   -- ANY close path silences the voice
  tinsert(UISpecialFrames, "QuestBookFrame")

  Book.shade = Book:CreateTexture(nil, "BACKGROUND", nil, -8)
  Book.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
  Book.shade:SetVertexColor(0, 0, 0, 0.45)
  Book.shade:SetPoint("TOPLEFT", UIParent, -400, 400)
  Book.shade:SetPoint("BOTTOMRIGHT", UIParent, 400, -400)

  Book.close = CreateFrame("Button", nil, Book, "UIPanelCloseButton")
  Book.close:SetPoint("TOPRIGHT", -2, -2)
  Book.close:SetScript("OnClick", function()
    StopSpeaking()
    Book:Hide()
  end)

  -- control strip: [<] [read] [>]
  Book.prev = CreateFrame("Button", nil, Book, "UIPanelButtonTemplate")
  Book.prev:SetSize(26, 22); Book.prev:SetPoint("TOPLEFT", 8, -6)
  Book.prev:SetText("<")
  Book.prev:SetScript("OnClick", function() NavQuest(-1) end)

  Book.speaker = CreateFrame("Button", nil, Book, "UIPanelButtonTemplate")
  Book.speaker:SetSize(52, 22); Book.speaker:SetPoint("TOPLEFT", 38, -6)
  Book.speaker:SetText("talk")
  Book.speaker:SetScript("OnClick", function() SpeakerToggle() end)

  Book.next = CreateFrame("Button", nil, Book, "UIPanelButtonTemplate")
  Book.next:SetSize(26, 22); Book.next:SetPoint("TOPLEFT", 94, -6)
  Book.next:SetText(">")
  Book.next:SetScript("OnClick", function() NavQuest(1) end)

  Book.list = CreateFrame("ScrollFrame", nil, Book, "UIPanelScrollFrameTemplate")
  Book.list:SetPoint("TOPLEFT", 16, -34)
  Book.list:SetSize(280, db.height - 50)
  Book.listChild = CreateFrame("Frame", nil, Book.list)
  Book.listChild:SetSize(280, 10)
  Book.list:SetScrollChild(Book.listChild)

  Book.page = CreateFrame("ScrollFrame", nil, Book, "UIPanelScrollFrameTemplate")
  Book.pageChild = CreateFrame("Frame", nil, Book.page)
  Book.pageChild:SetSize(db.width - 380, 10)
  Book.page:SetScrollChild(Book.pageChild)

  Book.title = Book.pageChild:CreateFontString(nil, "ARTWORK")
  Book.title:SetPoint("TOPLEFT", 0, 0)
  Book.title:SetJustifyH("LEFT")

  Book.objectives = Book.pageChild:CreateFontString(nil, "ARTWORK")
  Book.objectives:SetPoint("TOPLEFT", Book.title, "BOTTOMLEFT", 0, -18)
  Book.objectives:SetJustifyH("LEFT"); Book.objectives:SetSpacing(6)

  Book.body = Book.pageChild:CreateFontString(nil, "ARTWORK")
  Book.body:SetPoint("TOPLEFT", Book.objectives, "BOTTOMLEFT", 0, -22)
  Book.body:SetJustifyH("LEFT"); Book.body:SetSpacing(7)
end

local function ApplyFonts()
  local base = docked and math.max(12, db.fontSize - 2) or db.fontSize
  Book.title:SetFont(FONT, base + 7, "")
  Book.title:SetTextColor(0.95, 0.87, 0.65)
  Book.objectives:SetFont(FONT, base, "")
  Book.body:SetFont(FONT, base, "")
  Book.body:SetTextColor(0.92, 0.89, 0.82)
end

ShowQuest = function(entry)
  for i, e in ipairs(currentEntries) do
    if e == entry then currentIndex = i break end
  end
  local desc, obj = GetQuestText(entry)
  lastEntry, lastDesc = entry, desc
  ApplyFonts()
  Book.title:SetText((entry.level and ("[" .. entry.level .. "] ") or "") .. (entry.title or ""))
  Book.objectives:SetText(obj)
  Book.body:SetText(desc)
  Book.pageChild:SetHeight(Book.title:GetStringHeight() + Book.objectives:GetStringHeight()
    + Book.body:GetStringHeight() + 80)
  Book.page:SetVerticalScroll(0)
end

local function RefreshList()
  local entries = GetLogEntries()
  currentEntries = entries
  for _, b in ipairs(ListButtons) do b:Hide() end
  local y = 0
  for i, entry in ipairs(entries) do
    local btn = ListButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, Book.listChild)
      btn:SetSize(270, 24)
      btn.text = btn:CreateFontString(nil, "ARTWORK")
      btn.text:SetPoint("LEFT", 4, 0)
      btn.text:SetWidth(262); btn.text:SetJustifyH("LEFT"); btn.text:SetWordWrap(false)
      btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
      ListButtons[i] = btn
    end
    btn.text:SetFont(FONT, 13, "")
    btn.text:SetTextColor(0.85, 0.82, 0.72)
    btn.text:SetText(entry.title or "?")
    btn:SetPoint("TOPLEFT", 0, -y)
    btn:SetScript("OnClick", function() ShowQuest(entry) end)
    btn:Show()
    y = y + 26
  end
  Book.listChild:SetHeight(math.max(y, 10))
  if entries[1] then ShowQuest(entries[1]) end
end

NavQuest = function(delta)
  local n = #currentEntries
  if n == 0 then return end
  local idx = (((currentIndex or 1) - 1 + delta) % n) + 1
  ShowQuest(currentEntries[idx])
  StopSpeaking()
  Speak(lastEntry, lastDesc, true)
end

SpeakerToggle = function()
  if isSpeaking then
    StopSpeaking()
  else
    StopSpeaking()
    Speak(lastEntry, lastDesc, true)
  end
end

local function Toggle()
  if not Book then BuildBook() end
  if Book:IsShown() then
    StopSpeaking()
    Book:Hide()
    return
  end
  docked = false
  ApplyLayout()
  RefreshList()
  Book:Show()
  if IsPlayerMoving and IsPlayerMoving() then
    Dbg("already moving at open — docking now")
    OnStartedMoving()
  end
end

OnStartedMoving = function()
  Dbg("PLAYER_STARTED_MOVING fired (shown=" .. tostring(Book and Book:IsShown())
    .. " docked=" .. tostring(docked) .. ")")
  if Book and Book:IsShown() and not docked then
    docked = true
    ApplyLayout()
    Speak(lastEntry, lastDesc)
  end
end

BINDING_HEADER_QUESTBOOK = "QuestBook"
_G["BINDING_NAME_QUESTBOOK_TOGGLE"] = "Toggle QuestBook"
function QuestBook_Toggle()
  Toggle()
end

-- ---------------------------------------------------------------- wiring

local EL = CreateFrame("Frame")
EL:RegisterEvent("ADDON_LOADED")
pcall(EL.RegisterEvent, EL, "PLAYER_STARTED_MOVING")
pcall(EL.RegisterEvent, EL, "VOICE_CHAT_TTS_PLAYBACK_STARTED")
pcall(EL.RegisterEvent, EL, "VOICE_CHAT_TTS_PLAYBACK_FINISHED")
pcall(EL.RegisterEvent, EL, "VOICE_CHAT_TTS_PLAYBACK_FAILED")
EL:SetScript("OnEvent", function(_, event, name)
  if event == "ADDON_LOADED" and name == ADDON_NAME then
    InitDB()
  elseif event == "PLAYER_STARTED_MOVING" then
    OnStartedMoving()
  elseif event == "VOICE_CHAT_TTS_PLAYBACK_STARTED" then
    SetSpeaking(true)
  elseif event == "VOICE_CHAT_TTS_PLAYBACK_FINISHED"
      or event == "VOICE_CHAT_TTS_PLAYBACK_FAILED" then
    SetSpeaking(false)
  end
end)

SLASH_QUESTBOOK1, SLASH_QUESTBOOK2 = "/qb", "/questbook"
SlashCmdList.QUESTBOOK = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", "")
  local size = msg:match("^size%s+(%d+)")
  local usevoice = msg:match("^usevoice%s+(%d+)")
  if size then
    db.fontSize = math.min(30, math.max(10, tonumber(size)))
    if Book and Book:IsShown() then ApplyFonts(); if lastEntry then ShowQuest(lastEntry) end end
    Say("font size " .. db.fontSize)
  elseif msg == "dark" then
    db.darken = not db.darken
    if Book and Book:IsShown() and not docked then Book.shade:SetShown(db.darken) end
    Say("backdrop " .. (db.darken and "on" or "off"))
  elseif msg == "debug" then
    debugMode = not debugMode
    Say("debug " .. (debugMode and "on — open the book and move" or "off"))
  elseif msg == "voice" then
    db.voice = not db.voice
    if not db.voice then StopSpeaking() end
    Say("walk-and-listen " .. (db.voice and "on" or "off"))
  elseif msg == "voices" then
    if C_VoiceChat and C_VoiceChat.GetTtsVoices then
      local ok, voices = pcall(C_VoiceChat.GetTtsVoices)
      if ok and type(voices) == "table" and #voices > 0 then
        for _, v in ipairs(voices) do
          Say("voice " .. tostring(v.voiceID) .. ": " .. tostring(v.name))
        end
        Say("pick one with /qb usevoice <id>")
      else
        Say("no TTS voices installed (Windows Settings > Time & Language > Speech)")
      end
    else
      Say("this client has no GetTtsVoices API")
    end
  elseif usevoice then
    db.voiceID = tonumber(usevoice)
    Say("voice set to " .. usevoice .. " — test with /qb say")
  elseif msg == "say" then
    local ok, why = SpeakText("QuestBook voice test. If you hear this, the book can read to you.")
    Say(ok and "speaking — did you hear it?" or ("not speaking: " .. tostring(why)))
  else
    Toggle()
  end
end
