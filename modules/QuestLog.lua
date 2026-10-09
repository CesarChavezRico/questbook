-- QuestBook / QuestLog module -- a readable page for the quests you accepted,
-- and (v0.7) the replacement for Blizzard's quest log.
--
-- WHY: the quest log's text is small and cramped; reading it is how we
-- navigate (no Questie by choice). This opens the quest log as one big, quiet,
-- readable page. v0.7 adds the log DUTIES so it can replace Blizzard's log:
-- choose the active quest, track / untrack, turn-in readiness, abandon, share,
-- and zone / campaign grouping (design note decisions 13, 15, 18).
--
-- Every duty below follows the flow Blizzard's own quest log uses in the
-- Forever client dump (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:
-- QuestMapQuestOptions_TrackQuest / _ShareQuest / _AbandonQuest).
--
-- COMMANDS (legacy set kept; new ones in /qb help):
--   /qb            toggle the book
--   /qb size <n>   body font size (default 17)
--   /qb dark       toggle the darkened backdrop
--   /qb voice      toggle walk-and-listen TTS (default on)
--   /qb debug      narrate the walk-and-listen chain in chat
--   /qb rate <n>   speaking rate, -10..10 (0 = normal)
--   /qb prosody    toggle SAPI pause tags between paragraphs
--   /qb say | voices | usevoice <id>   TTS diagnostics
--   /qb log replace|blizzard   which quest log the default key / menu button opens
--   /qb blizzlog   open Blizzard's own quest log once (the fallback)
--   /qb dock left|right        where the book docks while you walk
--
-- v0.6: objectives update LIVE while the book is open; completed quests are
-- marked and announced by the narrator. v0.5: dock controls [<] [read] [>].

local _, QB = ...

local mod = QB:NewModule("questlog", {
  replaceLog = true,    -- ToggleQuestLog (default key, micro menu button) opens this book
  dock = "right",       -- docked side while walking: the freed right-wing minimap slot
  collapsed = {},       -- our own zone-header collapse state (header title -> true)
})

local db              -- QB.db: the flat legacy QuestBookDB settings
local Book            -- main frame
local ListButtons = {}
local docked = false
local lastEntry, lastDesc
local debugMode = false
local currentEntries = {}   -- quests only, in log order (prev / next walks this)
local currentIndex
local isSpeaking = false
local NavQuest, SpeakerToggle   -- forward declarations (buttons close over them)
local ShowQuest, OnStartedMoving, RefreshList, RefreshChrome

local function Dbg(msg) if debugMode then print("|cff7faaffQB-debug|r: " .. msg) end end
local function Say(msg) QB:Say(msg) end

-- Wrap a UI script so a fault in it is isolated like any other module entry.
local function Guard(fn)
  return function(...) QB:Safe(mod, fn, ...) end
end

-- ---------------------------------------------------------------- log data

local UNAVAILABLE = "|cff888888(text unavailable -- tell Nibble the quest name)|r"

-- Walk the log. Returns rows (headers + quests, for the list) and quests (for
-- prev / next). Quests under a header Blizzard's own log has collapsed are not
-- returned by GetInfo, so a collapsed header is expanded and the scan redone
-- (ExpandQuestHeader is the global Blizzard's QuestMapFrame.lua itself uses).
-- Our own collapse state (mod.db.collapsed) is separate and only hides rows.
local function ScanLog()
  local rows, quests = {}, {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for _ = 1, 12 do
      rows, quests = {}, {}
      local expandedOne = false
      local ok, n = pcall(C_QuestLog.GetNumQuestLogEntries)
      if not ok or not n then break end
      local headerTitle
      for i = 1, n do
        local ok2, info = pcall(C_QuestLog.GetInfo, i)
        if ok2 and info then
          if info.isHeader then
            headerTitle = info.title
            rows[#rows + 1] = { kind = "header", title = info.title }
            if info.isCollapsed and type(ExpandQuestHeader) == "function" then
              pcall(ExpandQuestHeader, i)
              expandedOne = true
              break
            end
          elseif info.questID and not info.isHidden then
            local entry = { index = i, questID = info.questID, title = info.title,
              level = info.level, header = headerTitle, campaignID = info.campaignID }
            quests[#quests + 1] = entry
            rows[#rows + 1] = { kind = "quest", entry = entry, header = headerTitle }
          end
        end
      end
      if not expandedOne then return rows, quests end
    end
    return rows, quests
  end
  -- classic-style fallback (no headers)
  if GetNumQuestLogEntries and GetQuestLogTitle then
    local n = GetNumQuestLogEntries() or 0
    for i = 1, n do
      local title, level, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if title and not isHeader then
        local entry = { index = i, questID = questID, title = title, level = level }
        quests[#quests + 1] = entry
        rows[#rows + 1] = { kind = "quest", entry = entry }
      end
    end
  end
  return rows, quests
end

-- Objectives complete? Modern then classic, guarded.
local function IsQuestDone(entry)
  if not entry then return false end
  if C_QuestLog and C_QuestLog.IsComplete then
    local ok, done = pcall(C_QuestLog.IsComplete, entry.questID)
    if ok then return done and true or false end
  end
  if IsQuestComplete then
    local ok, done = pcall(IsQuestComplete, entry.questID)
    if ok then return done and true or false end
  end
  return false
end

-- Turn-in readiness (C_QuestLog.ReadyForTurnIn, Blizzard_APIDocumentationGenerated/QuestLogDocumentation.lua).
local function IsReadyToTurnIn(entry)
  if not entry then return false end
  if C_QuestLog and C_QuestLog.ReadyForTurnIn then
    local ok, ready = pcall(C_QuestLog.ReadyForTurnIn, entry.questID)
    if ok then return ready and true or false end
  end
  return IsQuestDone(entry)
end

local function IsWatched(questID)
  if C_QuestLog and C_QuestLog.GetQuestWatchType then
    local ok, wt = pcall(C_QuestLog.GetQuestWatchType, questID)
    if ok then return wt ~= nil end
  end
  return false
end

local function IsActiveQuest(questID)
  if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok then return id == questID end
  end
  return false
end

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

-- ---------------------------------------------------------------- duties

-- Track / untrack (QuestMapQuestOptions_TrackQuest, QuestMapFrame.lua).
local function ToggleTrack(entry)
  if not (entry and C_QuestLog and C_QuestLog.AddQuestWatch and C_QuestLog.RemoveQuestWatch) then
    Say("tracking is not available on this client")
    return
  end
  if IsWatched(entry.questID) then
    pcall(C_QuestLog.RemoveQuestWatch, entry.questID)
  else
    local max = (Constants and Constants.QuestWatchConsts and Constants.QuestWatchConsts.MAX_QUEST_WATCHES) or 25
    local count = (C_QuestLog.GetNumQuestWatches and C_QuestLog.GetNumQuestWatches()) or 0
    if count >= max then
      Say("too many tracked quests (" .. max .. "); untrack one first")
    else
      pcall(C_QuestLog.AddQuestWatch, entry.questID)
    end
  end
  RefreshChrome()
end

-- Choose the active (super-tracked) quest: the one the game points at.
-- Picking one also tracks it, as Blizzard's log does.
local function ToggleActive(entry)
  if not (entry and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then
    Say("choosing the active quest is not available on this client")
    return
  end
  if IsActiveQuest(entry.questID) then
    if C_SuperTrack.ClearAllSuperTracked then
      pcall(C_SuperTrack.ClearAllSuperTracked)
    else
      pcall(C_SuperTrack.SetSuperTrackedQuestID, 0)
    end
  else
    if not IsWatched(entry.questID) and C_QuestLog and C_QuestLog.AddQuestWatch then
      pcall(C_QuestLog.AddQuestWatch, entry.questID)
    end
    pcall(C_SuperTrack.SetSuperTrackedQuestID, entry.questID)
  end
  RefreshChrome()
end

local function CanShare(entry)
  if not entry or type(QuestLogPushQuest) ~= "function" then return false end
  local pushable = false
  if C_QuestLog and C_QuestLog.IsPushableQuest then
    local ok, p = pcall(C_QuestLog.IsPushableQuest, entry.questID)
    pushable = ok and p and true or false
  end
  local grouped = IsInGroup and IsInGroup() or false
  return pushable and grouped
end

-- Share (QuestMapQuestOptions_ShareQuest: QuestLogPushQuest(logIndex)).
local function ShareQuest(entry)
  if not CanShare(entry) then
    Say("this quest cannot be shared right now (needs a group and a shareable quest)")
    return
  end
  local index = entry.index
  if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
    index = C_QuestLog.GetLogIndexForQuestID(entry.questID) or index
  end
  pcall(QuestLogPushQuest, index)
end

-- Abandon (QuestMapQuestOptions_AbandonQuest): select, arm, confirm in Blizzard's
-- own ABANDON_QUEST popup, then restore the previous selection.
local function AbandonQuest(entry)
  if not (entry and C_QuestLog and C_QuestLog.SetAbandonQuest and StaticPopup_Show) then
    Say("abandoning is not available on this client")
    return
  end
  if C_QuestLog.CanAbandonQuest then
    local ok, can = pcall(C_QuestLog.CanAbandonQuest, entry.questID)
    if ok and not can then Say("this quest cannot be abandoned") return end
  end
  local old = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
  C_QuestLog.SetSelectedQuest(entry.questID)
  C_QuestLog.SetAbandonQuest()
  local title = entry.title
  if QuestUtils_GetQuestName and C_QuestLog.GetAbandonQuest then
    title = QuestUtils_GetQuestName(C_QuestLog.GetAbandonQuest()) or title
  end
  if StaticPopup_Hide then StaticPopup_Hide("ABANDON_QUEST_WITH_ITEMS") end
  StaticPopup_Show("ABANDON_QUEST", title)
  if old and old ~= 0 then C_QuestLog.SetSelectedQuest(old) end
end

-- ---------------------------------------------------------------- voice

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

-- SAPI XML pause tags between paragraphs (Blizzard's docs: SpeakText
-- supports XML TTS tags on Windows). If a client ever reads the tags
-- aloud instead of honouring them, /qb prosody turns this off.
local function Shape(text)
  if not db.prosody then return text end
  return (text:gsub("\n\n", ' <silence msec="550"/> '):gsub("\n", ' <silence msec="250"/> '))
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
  local ok, err = pcall(C_VoiceChat.SpeakText, voiceID, Shape(text), db.rate or 0, 100)
  if not ok then return false, "SpeakText error: " .. tostring(err) end
  return true, nil
end

local function Speak(entry, desc, force)
  if not db then Dbg("no db -- core never booted?") return end
  if not force and not db.voice then Dbg("voice is OFF (/qb voice)") return end
  if not desc then Dbg("no description cached") return end
  if desc == UNAVAILABLE then Dbg("description unavailable") return end
  Dbg("calling SpeakText...")
  local prefix = IsReadyToTurnIn(entry) and "This quest is complete and ready to turn in. " or ""
  local ok, why = SpeakText(((entry and entry.title) or "") .. ". " .. prefix .. desc)
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

local function ApplyLayout()
  if docked then
    Book:ClearAllPoints()
    if mod.db.dock == "left" then
      Book:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
    else
      -- the freed right-wing slot where the corner minimap used to be (decision 13)
      Book:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -90)
    end
    Book:SetSize(440, 540)
    Book.list:Hide(); Book.shade:Hide()
    Book.page:ClearAllPoints()
    Book.page:SetPoint("TOPLEFT", 16, -40); Book.page:SetPoint("BOTTOMRIGHT", -30, 14)
  else
    Book:ClearAllPoints(); Book:SetPoint("CENTER")
    Book:SetSize(db.width, db.height)
    Book.list:Show(); Book.shade:SetShown(db.darken)
    Book.page:ClearAllPoints()
    Book.page:SetPoint("TOPLEFT", 340, -36); Book.page:SetPoint("BOTTOMRIGHT", -36, 20)
  end
  local w = docked and 380 or (db.width - 400)
  Book.title:SetWidth(w); Book.objectives:SetWidth(w); Book.body:SetWidth(w)
  Book.pageChild:SetWidth(w + 20)
  if lastEntry then ShowQuest(lastEntry) end
end

local function MakeButton(parent, label, x, w, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, -6)
  b:SetText(label)
  b:SetScript("OnClick", Guard(onClick))
  return b
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
  Book.close:SetScript("OnClick", Guard(function()
    StopSpeaking()
    Book:Hide()
  end))

  -- control strip: [<] [talk] [>]  then the log duties (they act on the quest on the page)
  Book.prev = MakeButton(Book, "<", 8, 26, function() NavQuest(-1) end)
  Book.speaker = MakeButton(Book, "talk", 38, 52, function() SpeakerToggle() end)
  Book.next = MakeButton(Book, ">", 94, 26, function() NavQuest(1) end)
  Book.btnTrack = MakeButton(Book, "Track", 130, 62, function() ToggleTrack(lastEntry) end)
  Book.btnActive = MakeButton(Book, "Active", 196, 62, function() ToggleActive(lastEntry) end)
  Book.btnShare = MakeButton(Book, "Share", 262, 56, function() ShareQuest(lastEntry) end)
  Book.btnAbandon = MakeButton(Book, "Abandon", 322, 70, function() AbandonQuest(lastEntry) end)

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

local function UpdateButtons(entry)
  Book.btnTrack:SetText(IsWatched(entry.questID) and "Untrack" or "Track")
  Book.btnActive:SetText(IsActiveQuest(entry.questID) and "Clear" or "Active")
  Book.btnShare:SetEnabled(CanShare(entry))
  Book.btnAbandon:SetEnabled(true)
end

ShowQuest = function(entry)
  for i, e in ipairs(currentEntries) do
    if e.questID == entry.questID then currentIndex = i break end
  end
  local desc, obj = GetQuestText(entry)
  lastEntry, lastDesc = entry, desc
  ApplyFonts()
  local ready, done = IsReadyToTurnIn(entry), IsQuestDone(entry)
  local mark = ready and "  |cff6fca6f(ready to turn in)|r" or (done and "  |cff6fca6f(complete)|r" or "")
  Book.title:SetText((entry.level and ("[" .. entry.level .. "] ") or "") .. (entry.title or "") .. mark)
  Book.objectives:SetText((ready and "|cff6fca6fReady to turn in.|r\n" or (done and "|cff6fca6fObjectives complete.|r\n" or "")) .. obj)
  Book.body:SetText(desc)
  Book.pageChild:SetHeight(Book.title:GetStringHeight() + Book.objectives:GetStringHeight()
    + Book.body:GetStringHeight() + 80)
  Book.page:SetVerticalScroll(0)
  UpdateButtons(entry)
end

-- List with zone / campaign headers (Blizzard's own headers), our own collapse.
-- `keepID`: select this quest again; `keepScroll`: leave the list scroll alone.
RefreshList = function(keepID, keepScroll)
  local rows, quests = ScanLog()
  currentEntries = quests
  local scroll = keepScroll and Book.list:GetVerticalScroll() or 0
  for _, b in ipairs(ListButtons) do b:Hide() end
  local y, shown = 0, 0
  local collapsed = mod.db.collapsed
  for _, row in ipairs(rows) do
    local hidden = row.kind == "quest" and row.header and collapsed[row.header]
    if not hidden then
      shown = shown + 1
      local btn = ListButtons[shown]
      if not btn then
        btn = CreateFrame("Button", nil, Book.listChild)
        btn:SetSize(270, 24)
        btn.text = btn:CreateFontString(nil, "ARTWORK")
        btn.text:SetPoint("LEFT", 4, 0)
        btn.text:SetWidth(262); btn.text:SetJustifyH("LEFT"); btn.text:SetWordWrap(false)
        btn:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
        ListButtons[shown] = btn
      end
      btn:ClearAllPoints()
      btn:SetPoint("TOPLEFT", 0, -y)
      btn.text:SetFont(FONT, 13, "")
      if row.kind == "header" then
        local isCollapsed = collapsed[row.title]
        btn.text:SetTextColor(0.95, 0.87, 0.65)
        btn.text:SetText((isCollapsed and "+ " or "- ") .. (row.title or "?"))
        btn:SetScript("OnClick", Guard(function()
          collapsed[row.title] = (not collapsed[row.title]) or nil
          RefreshList(lastEntry and lastEntry.questID, true)
        end))
        y = y + 28
      else
        local e = row.entry
        local tag = ""
        if IsActiveQuest(e.questID) then tag = "> "
        elseif IsWatched(e.questID) then tag = "* " end
        local ready = IsReadyToTurnIn(e)
        btn.text:SetTextColor(ready and 0.55 or 0.85, ready and 0.85 or 0.82, ready and 0.55 or 0.72)
        btn.text:SetText("  " .. tag .. (e.title or "?"))
        btn:SetScript("OnClick", Guard(function() ShowQuest(e) end))
        y = y + 26
      end
      btn:Show()
    end
  end
  Book.listChild:SetHeight(math.max(y, 10))
  Book.list:SetVerticalScroll(scroll)
  -- keep the selection if that quest still exists, else the first quest
  local pick
  if keepID then
    for _, e in ipairs(quests) do
      if e.questID == keepID then pick = e break end
    end
  end
  pick = pick or quests[1]
  if pick then
    ShowQuest(pick)
  else
    lastEntry, lastDesc = nil, nil
    Book.title:SetText("No quests in your log.")
    Book.objectives:SetText(""); Book.body:SetText("")
  end
end

-- After a duty (track / active): refresh marks without losing the reading position.
RefreshChrome = function()
  if not (Book and Book:IsShown() and lastEntry) then return end
  local sc = Book.page:GetVerticalScroll()
  RefreshList(lastEntry.questID, true)
  if lastEntry then Book.page:SetVerticalScroll(sc) end
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

function mod:Toggle()
  if not Book then BuildBook() end
  if Book:IsShown() then
    StopSpeaking()
    Book:Hide()
    return
  end
  docked = false
  ApplyLayout()
  RefreshList(lastEntry and lastEntry.questID)
  Book:Show()
  if IsPlayerMoving and IsPlayerMoving() then
    Dbg("already moving at open -- docking now")
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

-- ---------------------------------------------------------------- events

local refreshPending = false
local function RefreshAll()
  refreshPending = false
  RefreshChrome()
end

-- these fire in bursts; coalesce to one re-render, keep the reading position
local function QueueRefresh()
  if Book and Book:IsShown() and not refreshPending then
    refreshPending = true
    if C_Timer and C_Timer.After then
      C_Timer.After(0.25, Guard(RefreshAll))
    else
      RefreshAll()
    end
  end
end

mod.events.QUEST_LOG_UPDATE = QueueRefresh
mod.events.QUEST_WATCH_LIST_CHANGED = QueueRefresh
mod.events.SUPER_TRACKING_CHANGED = QueueRefresh
mod.events.QUEST_REMOVED = QueueRefresh
mod.events.PLAYER_STARTED_MOVING = function() OnStartedMoving() end
mod.events.VOICE_CHAT_TTS_PLAYBACK_STARTED = function() SetSpeaking(true) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FINISHED = function() SetSpeaking(false) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FAILED = function() SetSpeaking(false) end

-- ---------------------------------------------------------------- replace Blizzard's log

-- In this UI ToggleQuestLog() opens the quest tab of the WORLD MAP panel
-- (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:2170), and both the default
-- key (Blizzard_FrameXML/Bindings_Camelot.xml) and the micro menu button
-- (Blizzard_MicroMenu/Mainline/MainMenuBarMicroButtons.lua:1138) call that one
-- global, so replacing it reroutes both.
-- UNVERIFIED: that replacing a global function from an addon taints nothing the map
-- needs; /qb log blizzard (or /qb disable questlog) puts Blizzard's back at once.
local function InstallToggleOverride()
  if type(_G.ToggleQuestLog) ~= "function" then
    Say("ToggleQuestLog not found on this client: the default key still opens Blizzard's log")
    return
  end
  if mod.origToggle then return end
  mod.origToggle = _G.ToggleQuestLog
  mod.ourToggle = function(...)
    if mod.active and mod.db.replaceLog then
      QB:Safe(mod, mod.Toggle, mod)
    else
      return mod.origToggle(...)
    end
  end
  _G.ToggleQuestLog = mod.ourToggle
end

local function RemoveToggleOverride()
  if mod.origToggle and _G.ToggleQuestLog == mod.ourToggle then
    _G.ToggleQuestLog = mod.origToggle
  end
  mod.origToggle, mod.ourToggle = nil, nil
end

function mod:OnInit()
  db = QB.db
end

function mod:OnEnable()
  db = QB.db
  InstallToggleOverride()
end

function mod:OnDisable()
  RemoveToggleOverride()
  if Book then Book:Hide() end
end

-- ---------------------------------------------------------------- slash

QB:RegisterSlash(mod, "blizzlog", function()
  if mod.origToggle then mod.origToggle() else Say("Blizzard's quest log is already the default") end
end, "open Blizzard's own quest log once (the fallback)")

QB:RegisterSlash(mod, "log", function(rest)
  rest = (rest or ""):lower()
  if rest == "replace" then
    mod.db.replaceLog = true
  elseif rest == "blizzard" then
    mod.db.replaceLog = false
  end
  Say("the default quest log key opens " .. (mod.db.replaceLog and "QuestBook" or "Blizzard's log"))
end, "log replace|blizzard: which quest log the default key / menu button opens")

QB:RegisterSlash(mod, "dock", function(rest)
  rest = (rest or ""):lower()
  if rest == "left" or rest == "right" then mod.db.dock = rest end
  Say("the book docks on the " .. mod.db.dock .. " while you walk")
  if Book and Book:IsShown() and docked then ApplyLayout() end
end, "dock left|right: where the book docks while you walk")

-- The legacy command set (everything that is not a registered subcommand).
QB.legacySlash = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", "")
  if not db then return end
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
  elseif msg:match("^rate%s+-?%d+$") then
    db.rate = math.max(-10, math.min(10, tonumber(msg:match("(-?%d+)"))))
    Say("rate " .. db.rate .. " -- test with /qb say")
  elseif msg == "prosody" then
    db.prosody = not db.prosody
    Say("paragraph pauses " .. (db.prosody and "on" or "off"))
  elseif msg == "debug" then
    debugMode = not debugMode
    Say("debug " .. (debugMode and "on -- open the book and move" or "off"))
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
    Say("voice set to " .. usevoice .. " -- test with /qb say")
  elseif msg == "say" then
    local ok, why = SpeakText("QuestBook voice test. If you hear this, the book can read to you.")
    Say(ok and "speaking -- did you hear it?" or ("not speaking: " .. tostring(why)))
  else
    mod:Toggle()
  end
end
