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
local Style = QB.Style

local mod = QB:NewModule("questlog", {
  replaceLog = true,    -- ToggleQuestLog (default key, micro menu button) opens this book
  dock = "right",       -- docked side while walking: the freed right-wing minimap slot
  collapsed = {},       -- our own zone-header collapse state (header title -> true)
  plate = true,         -- the map plate on the left page (/qb book map on|off)
  bgAlpha = 0.62,       -- dark theme only: the panel's opacity
  theme = "paper",      -- "paper" (two parchment pages) | "dark" (the faint dark panel)
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

-- The quests in the log, headers expanded as the book needs them (used by the tracker's "all" mode).
function mod:Scan()
  local _, quests = ScanLog()
  return quests
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
          lines[#lines + 1] = "|cff" .. Style.Hex(item.finished and Style.Get(mod.db.theme).done or Style.Get(mod.db.theme).pending) .. "- " .. item.text .. "|r"
        end
      end
    end
  elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    local ok, n = pcall(GetNumQuestLeaderBoards, entry.index)
    if ok and n then
      for j = 1, n do
        local ok2, text, _, finished = pcall(GetQuestLogLeaderBoard, j, entry.index)
        if ok2 and text then
          lines[#lines + 1] = "|cff" .. Style.Hex(finished and Style.Get(mod.db.theme).done or Style.Get(mod.db.theme).pending) .. "- " .. text .. "|r"
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

-- Make a quest the active one (never clears it: the tracker's left click; Book > Active toggles).
function mod:SetActive(questID)
  if not (questID and C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then
    Say("choosing the active quest is not available on this client")
    return
  end
  if not IsWatched(questID) and C_QuestLog and C_QuestLog.AddQuestWatch then
    pcall(C_QuestLog.AddQuestWatch, questID)
  end
  pcall(C_SuperTrack.SetSuperTrackedQuestID, questID)
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

-- ---------------------------------------------------------------- layout
--
-- Non-docked book = an open book: LEFT page = (map plate, when there is one) + the quest's
-- text; RIGHT page = the quest list. The whole list fits its page (rows shrink to fit) and the
-- quest text fits its page (the plate shrinks first, then the font, then it scrolls).
-- Docked (walk-and-listen) = one single page of text, as before.

local PAD, SB = 14, 24                 -- page padding; room kept for a scrollbar
local TOP, BOTTOM = 36, 12             -- below the button row; above the cover's lower edge
local MIN_FONT = 11                    -- the quest text never shrinks below this
local PLATE_STEPS = { 0.42, 0.32, 0.22 }   -- the plate's share of the left page, largest first
local ROW_MIN, ROW_MAX = 16, 26
local G = {}                           -- the last computed geometry and fit (also read by /qb book)
mod.layout = G

local function Theme() return Style.Get(mod.db.theme) end

-- Page textures, the spine shade and the plate's frame follow the theme.
local function ApplyTheme()
  if not Book then return end
  local th = Theme()
  -- The backdrop's own fill is drawn ABOVE ordinary BACKGROUND textures in this client (measured on a
  -- screenshot, 2026-10-15: parchment showed at 2% through it). So on paper the fill is switched off and
  -- the leather is a plain texture beneath the pages; the dark theme keeps the backdrop fill.
  if th.paper then
    Book:SetBackdropColor(th.cover[1], th.cover[2], th.cover[3], 0)
    Book.coverTex:SetColorTexture(th.cover[1], th.cover[2], th.cover[3], th.cover[4])
    Book.coverTex:Show()
  else
    Book:SetBackdropColor(th.cover[1], th.cover[2], th.cover[3], mod.db.bgAlpha or 0.62)
    Book.coverTex:Hide()
  end
  Book:SetBackdropBorderColor(th.coverEdge[1], th.coverEdge[2], th.coverEdge[3], th.coverEdge[4])
  Book.coverLow:SetShown(th.paper)
  for _, t in ipairs({ Book.shadeL, Book.shadeR, Book.shadeT, Book.shadeB }) do t:SetShown(th.paper) end
  if th.paper then
    Book.pageL:SetColorTexture(th.pageLeft[1], th.pageLeft[2], th.pageLeft[3], th.pageLeft[4])
    Book.pageR:SetColorTexture(th.pageRight[1], th.pageRight[2], th.pageRight[3], th.pageRight[4])
    for _, t in ipairs(Book.spine) do t:SetColorTexture(th.gutter[1], th.gutter[2], th.gutter[3], t.alphaWant) end
    -- leather darkens toward the bottom
    Style.Gradient(Book.coverLow, "VERTICAL", { th.coverLow[1], th.coverLow[2], th.coverLow[3], 0.9 },
      { th.cover[1], th.cover[2], th.cover[3], 0 })
    -- outer edges of each page shade into the paper (strength 0.28), drawn as gradients
    local sh = th.pageShade
    Style.Gradient(Book.shadeL, "HORIZONTAL", { sh[1], sh[2], sh[3], 0.30 }, { sh[1], sh[2], sh[3], 0 })
    Style.Gradient(Book.shadeR, "HORIZONTAL", { sh[1], sh[2], sh[3], 0 }, { sh[1], sh[2], sh[3], 0.30 })
    Style.Gradient(Book.shadeT, "VERTICAL", { sh[1], sh[2], sh[3], 0 }, { sh[1], sh[2], sh[3], 0.22 })
    Style.Gradient(Book.shadeB, "VERTICAL", { sh[1], sh[2], sh[3], 0.22 }, { sh[1], sh[2], sh[3], 0 })
  end
  for _, l in ipairs(Book.links or {}) do l:Paint() end
  if Book.close then Book.close:Paint() end
  Style.SetInk(Book.listHead, th.faded)
  Style.SetInk(Book.legend, th.faded)
  Style.SetFont(Book.listHead, "body", 11, th)
  Style.SetFont(Book.legend, "body", 10, th)
  Style.SetShadow(Book.listHead, th); Style.SetShadow(Book.legend, th)
  Style.SetInk(Book.plateCap, th.faded)
  Style.SetFont(Book.plateCap, "body", 10, th)
  Book.plateEdge:SetColorTexture(th.plateEdge[1], th.plateEdge[2], th.plateEdge[3], th.plateEdge[4])
  Book.plateBg:SetColorTexture(th.plateFill[1], th.plateFill[2], th.plateFill[3], th.plateFill[4])
end

-- Measure the quest text at body size `f` into the three strings (their widths are already set).
local function MeasureText(f, th)
  local gap = math.floor(f * 0.8)
  Style.SetFont(Book.title, "title", f + 7, th)
  Style.SetFont(Book.objectives, "body", f, th)
  Style.SetFont(Book.body, "body", f, th)
  Book.objectives:SetSpacing(math.max(2, math.floor(f * 0.35)))
  Book.body:SetSpacing(math.max(2, math.floor(f * 0.4)))
  Book.objectives:ClearAllPoints()
  Book.objectives:SetPoint("TOPLEFT", Book.title, "BOTTOMLEFT", 0, -gap)
  Book.body:ClearAllPoints()
  Book.body:SetPoint("TOPLEFT", Book.objectives, "BOTTOMLEFT", 0, -(gap + 4))
  local total = Book.title:GetStringHeight() + gap + Book.objectives:GetStringHeight()
    + gap + 4 + Book.body:GetStringHeight()
  return total
end

-- Pick the plate size and the font so the quest text fits the left page.
-- Order (Cesar, 2026-10-13: "reduce the text size or the map size"): shrink the plate through
-- PLATE_STEPS first, keeping the text at its set size; then shrink the font down to MIN_FONT;
-- if it still does not fit, the page scrolls (G.fit.scrolls).
local function FitLeft()
  if not (Book and G.leftW) then return end
  local th = Theme()
  local inner = G.H - TOP - BOTTOM - 2 * PAD
  local plateOn = Book.plateWanted and not G.docked
  local base = G.docked and math.max(12, db.fontSize - 2) or db.fontSize
  local capH = plateOn and 16 or 0
  local ph = 0
  local chosenF, total, availText, fits = base, 0, inner, false
  local steps = plateOn and PLATE_STEPS or { 0 }
  for _, frac in ipairs(steps) do
    ph = plateOn and math.floor(inner * frac) or 0
    availText = inner - (plateOn and (ph + capH + 8) or 0)
    total = MeasureText(base, th)
    chosenF = base
    if total <= availText then fits = true break end
  end
  if not fits then
    for f = base - 1, MIN_FONT, -1 do
      total = MeasureText(f, th)
      chosenF = f
      if total <= availText then fits = true break end
    end
  end
  G.fit = { plateH = ph, font = chosenF, base = base, total = total, avail = availText,
    fits = fits, scrolls = not fits, plate = plateOn and true or false }
  -- apply
  local blockH = plateOn and (ph + capH + 8) or 0
  Book.plate:SetShown(plateOn and true or false)
  Book.plateCap:SetShown(plateOn and true or false)
  if plateOn then
    Book.plate:ClearAllPoints()
    Book.plate:SetPoint("TOPLEFT", Book, "TOPLEFT", G.leftX + PAD, -(TOP + PAD))
    Book.plate:SetSize(G.leftW - 2 * PAD, ph)
    Book.plateCap:ClearAllPoints()
    Book.plateCap:SetPoint("TOP", Book.plate, "BOTTOM", 0, -3)
    Book.plateCap:SetWidth(G.leftW - 2 * PAD)
  end
  Book.page:ClearAllPoints()
  Book.page:SetPoint("TOPLEFT", Book, "TOPLEFT", G.leftX + PAD, -(TOP + PAD + blockH))
  Book.page:SetPoint("BOTTOMRIGHT", Book, "BOTTOMLEFT", G.leftX + G.leftW - PAD - SB, BOTTOM + PAD)
  Book.pageChild:SetWidth(G.textW)
  Book.pageChild:SetHeight(math.max(total, availText))
  Book.page:SetVerticalScroll(0)
  if plateOn then QB:Call("overlay", "PlateLayout") end    -- the map follows the plate's new size
end

local function ApplyLayout()
  local th = Theme()
  local W, H
  Book:ClearAllPoints()
  if docked then
    if mod.db.dock == "left" then
      Book:SetPoint("LEFT", UIParent, "LEFT", 40, 80)
    else
      -- the freed right-wing slot where the corner minimap used to be (decision 13)
      Book:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -90)
    end
    W, H = 440, 540
  else
    Book:SetPoint("CENTER")
    W, H = db.width, db.height
  end
  Book:SetSize(W, H)
  Book.shade:SetShown(not docked and db.darken and true or false)

  local leftX, leftW, rightX, rightW
  if docked then
    leftX, leftW = 10, W - 20
    rightX, rightW = 0, 0
  else
    local mid = math.floor(W / 2)
    leftX, leftW = 12, mid - 12 - 6
    rightX, rightW = mid + 6, W - mid - 6 - 12
  end
  G.W, G.H, G.docked = W, H, docked
  G.leftX, G.leftW, G.rightX, G.rightW = leftX, leftW, rightX, rightW
  G.textW = leftW - 2 * PAD - SB
  G.listW = rightW - 2 * PAD - SB
  G.listH = H - TOP - BOTTOM - 2 * PAD - 22 - 18     -- minus the heading above and the legend below

  -- the pages (paper theme only; the dark theme is one faint panel)
  local showPages = th.paper
  Book.pageL:SetShown(showPages)
  Book.pageR:SetShown(showPages and not docked)
  if showPages then
    Book.pageL:ClearAllPoints()
    Book.pageL:SetPoint("TOPLEFT", Book, "TOPLEFT", leftX, -TOP)
    Book.pageL:SetPoint("BOTTOMRIGHT", Book, "BOTTOMLEFT", leftX + leftW, BOTTOM)
    Book.pageR:ClearAllPoints()
    Book.pageR:SetPoint("TOPLEFT", Book, "TOPLEFT", rightX, -TOP)
    Book.pageR:SetPoint("BOTTOMRIGHT", Book, "BOTTOMRIGHT", -12, BOTTOM)
  end
  if showPages then
    local SHW = 46
    Book.shadeL:ClearAllPoints()
    Book.shadeL:SetPoint("TOPLEFT", Book.pageL, "TOPLEFT", 0, 0)
    Book.shadeL:SetPoint("BOTTOMLEFT", Book.pageL, "BOTTOMLEFT", 0, 0)
    Book.shadeL:SetWidth(SHW)
    Book.shadeR:ClearAllPoints()
    Book.shadeR:SetPoint("TOPRIGHT", Book.pageR, "TOPRIGHT", 0, 0)
    Book.shadeR:SetPoint("BOTTOMRIGHT", Book.pageR, "BOTTOMRIGHT", 0, 0)
    Book.shadeR:SetWidth(SHW)
    Book.shadeR:SetShown(not docked)
    Book.shadeT:ClearAllPoints()
    Book.shadeT:SetPoint("TOPLEFT", Book.pageL, "TOPLEFT", 0, 0)
    Book.shadeT:SetPoint("TOPRIGHT", docked and Book.pageL or Book.pageR, "TOPRIGHT", 0, 0)
    Book.shadeT:SetHeight(28)
    Book.shadeB:ClearAllPoints()
    Book.shadeB:SetPoint("BOTTOMLEFT", Book.pageL, "BOTTOMLEFT", 0, 0)
    Book.shadeB:SetPoint("BOTTOMRIGHT", docked and Book.pageL or Book.pageR, "BOTTOMRIGHT", 0, 0)
    Book.shadeB:SetHeight(28)
  end
  for i, t in ipairs(Book.spine) do
    t:SetShown(showPages and not docked)
    if showPages and not docked then
      local left = (i % 2 == 1)
      local k = math.ceil(i / 2)
      t:ClearAllPoints()
      if left then
        t:SetPoint("TOPRIGHT", Book.pageL, "TOPRIGHT", -2 * (k - 1), 0)
        t:SetPoint("BOTTOMRIGHT", Book.pageL, "BOTTOMRIGHT", -2 * (k - 1), 0)
      else
        t:SetPoint("TOPLEFT", Book.pageR, "TOPLEFT", 2 * (k - 1), 0)
        t:SetPoint("BOTTOMLEFT", Book.pageR, "BOTTOMLEFT", 2 * (k - 1), 0)
      end
      t:SetWidth(2)
    end
  end

  -- the list (right page)
  Book.list:SetShown(not docked)
  Book.listHead:SetShown(not docked)
  Book.legend:SetShown(not docked)
  if not docked then
    Book.listHead:ClearAllPoints()
    Book.listHead:SetPoint("TOPLEFT", Book, "TOPLEFT", rightX + PAD, -(TOP + PAD))
    Book.list:ClearAllPoints()
    Book.list:SetPoint("TOPLEFT", Book, "TOPLEFT", rightX + PAD, -(TOP + PAD + 22))
    Book.list:SetPoint("BOTTOMRIGHT", Book, "BOTTOMRIGHT", -(12 + PAD + SB), BOTTOM + PAD + 18)
    Book.listChild:SetWidth(G.listW)
    Book.legend:ClearAllPoints()
    Book.legend:SetPoint("BOTTOMLEFT", Book, "BOTTOMLEFT", rightX + PAD, BOTTOM + PAD)
  end

  -- the text page widths (set before any measuring)
  Book.title:SetWidth(G.textW); Book.objectives:SetWidth(G.textW); Book.body:SetWidth(G.textW)
  Book.pageChild:SetWidth(G.textW)
  ApplyTheme()
  FitLeft()
  if lastEntry then ShowQuest(lastEntry) end
end

-- A FontString always gets a font at birth: the client refuses SetText on one that has none
-- ("Font not set"), and the real fonts are applied later by ApplyTheme / FitLeft.
local function NewText(parent, size)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  fs:SetFont(Style.FRIZ, size or 12, "")
  return fs
end

-- An action word on the cover: ink-link style (Style.Link), not a stock button. The row is laid out
-- by LayoutLinks, since the words change (Track / Untrack, talk / stop) and so do their widths.
local function MakeLink(parent, label, onClick)
  local l = Style.Link(parent, Guard(onClick), function() return Theme() end)
  l:SetText(label)
  return l
end

-- The row: [<] [talk] [>]   Track  Active  Share  Abandon  ... close at the right.
local function LayoutLinks()
  if not (Book and Book.links) then return end
  local x = 14
  for i, l in ipairs(Book.links) do
    l:ClearAllPoints()
    l:SetPoint("TOPLEFT", Book, "TOPLEFT", x, -9)
    x = x + l:GetWidth() + (l.gapAfter or 16)
  end
end

local function BuildBook()
  Book = CreateFrame("Frame", "QuestBookFrame", UIParent, "BackdropTemplate")
  Book:SetFrameStrata("HIGH")
  Book:SetMovable(true); Book:EnableMouse(true)
  Book:RegisterForDrag("LeftButton")
  Book:SetScript("OnDragStart", Book.StartMoving)
  Book:SetScript("OnDragStop", Book.StopMovingOrSizing)
  Book:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  Book:Hide()
  Book:SetScript("OnHide", function()
    StopSpeaking()
    QB:Call("overlay", "PlateHide")    -- gives the world map back (the overlay module hosts it)
  end)
  tinsert(UISpecialFrames, "QuestBookFrame")

  Book.shade = Book:CreateTexture(nil, "BACKGROUND", nil, -8)
  Book.shade:SetTexture("Interface\\Buttons\\WHITE8x8")
  Book.shade:SetVertexColor(0, 0, 0, 0.45)
  Book.shade:SetPoint("TOPLEFT", UIParent, -400, 400)
  Book.shade:SetPoint("BOTTOMRIGHT", UIParent, 400, -400)

  -- paper pages and the shade along the spine (flat colour: Blizzard's paper textures cost
  -- contrast in this client, per the Social Diary author)
  Book.pageL = Book:CreateTexture(nil, "BACKGROUND", nil, -6)
  Book.pageR = Book:CreateTexture(nil, "BACKGROUND", nil, -6)
  Book.spine = {}
  for i = 1, 12 do        -- odd = left page strips, even = right page strips; 6 each, fading out
    local t = Book:CreateTexture(nil, "BACKGROUND", nil, -5)
    t.alphaWant = 0.05 * (7 - math.ceil(i / 2))
    Book.spine[i] = t
  end

  -- shading on the paper: the reference's pages are not flat (edges darken, the spine shades);
  -- flat colour read as "bad colours" in the first client run. Cover gradient and edge shades:
  Book.coverTex = Book:CreateTexture(nil, "BACKGROUND", nil, -8)
  Book.coverTex:SetPoint("TOPLEFT", Book, "TOPLEFT", 1, -1)
  Book.coverTex:SetPoint("BOTTOMRIGHT", Book, "BOTTOMRIGHT", -1, 1)
  Book.coverLow = Book:CreateTexture(nil, "BACKGROUND", nil, -7)
  Book.coverLow:SetPoint("BOTTOMLEFT", Book, "BOTTOMLEFT", 1, 1)
  Book.coverLow:SetPoint("BOTTOMRIGHT", Book, "BOTTOMRIGHT", -1, 1)
  Book.coverLow:SetHeight(120)
  Book.shadeL = Book:CreateTexture(nil, "BACKGROUND", nil, -4)     -- left page: outer edge darkens
  Book.shadeR = Book:CreateTexture(nil, "BACKGROUND", nil, -4)     -- right page: outer edge darkens
  Book.shadeT = Book:CreateTexture(nil, "BACKGROUND", nil, -4)     -- under the cover's top edge
  Book.shadeB = Book:CreateTexture(nil, "BACKGROUND", nil, -4)     -- bottom edge, a page stack's shadow

  -- close: a cross in tooled brass, not the stock red-and-gold button
  Book.close = Style.Link(Book, function()
    StopSpeaking()
    Book:Hide()
  end, function() return Theme() end)
  Book.close.noLine = true                        -- a cross needs no underline
  Book.close.label:SetFont(Style.FRIZ, 16, "")
  Book.close:SetText("\195\151")                -- the multiplication sign, U+00D7
  Book.close:SetHeight(20)
  Book.close:SetPoint("TOPRIGHT", Book, "TOPRIGHT", -8, -6)

  -- control strip: [<] [talk] [>]  then the log duties (they act on the quest on the page)
  Book.prev = MakeLink(Book, "<", function() NavQuest(-1) end)
  Book.speaker = MakeLink(Book, "talk", function() SpeakerToggle() end)
  Book.next = MakeLink(Book, ">", function() NavQuest(1) end)
  Book.btnTrack = MakeLink(Book, "Track", function() ToggleTrack(lastEntry) end)
  Book.btnActive = MakeLink(Book, "Active", function() ToggleActive(lastEntry) end)
  Book.btnShare = MakeLink(Book, "Share", function() ShareQuest(lastEntry) end)
  Book.btnAbandon = MakeLink(Book, "Abandon", function() AbandonQuest(lastEntry) end)
  Book.btnAbandon:SetWarn(true)
  Book.prev.gapAfter, Book.next.gapAfter, Book.speaker.gapAfter = 10, 26, 10
  Book.links = { Book.prev, Book.speaker, Book.next, Book.btnTrack, Book.btnActive, Book.btnShare, Book.btnAbandon }
  for _, l in ipairs(Book.links) do l.onResize = LayoutLinks end
  LayoutLinks()

  -- right page: the list
  Book.listHead = NewText(Book, 11)
  Book.listHead:SetJustifyH("LEFT")
  Book.legend = NewText(Book, 11)
  Book.legend:SetJustifyH("LEFT")
  Book.legend:SetText("> active    * tracked")
  Book.list = CreateFrame("ScrollFrame", nil, Book, "UIPanelScrollFrameTemplate")
  Book.listChild = CreateFrame("Frame", nil, Book.list)
  Book.listChild:SetSize(280, 10)
  Book.list:SetScrollChild(Book.listChild)

  -- left page: the plate (the map goes here, modules/Plate.lua) and its caption
  Book.plate = CreateFrame("Frame", nil, Book)
  Book.plate:Hide()
  Book.plateEdge = Book.plate:CreateTexture(nil, "BACKGROUND", nil, -3)
  Book.plateEdge:SetAllPoints(Book.plate)
  Book.plateBg = Book.plate:CreateTexture(nil, "BACKGROUND", nil, -2)
  Book.plateBg:SetPoint("TOPLEFT", Book.plate, "TOPLEFT", 1, -1)
  Book.plateBg:SetPoint("BOTTOMRIGHT", Book.plate, "BOTTOMRIGHT", -1, 1)
  Book.plateCap = NewText(Book, 11)
  Book.plateCap:SetJustifyH("CENTER")
  Book.plateCap:Hide()

  -- left page: the quest text
  Book.page = CreateFrame("ScrollFrame", nil, Book, "UIPanelScrollFrameTemplate")
  Book.pageChild = CreateFrame("Frame", nil, Book.page)
  Book.pageChild:SetSize(400, 10)
  Book.page:SetScrollChild(Book.pageChild)

  Book.title = NewText(Book.pageChild, 13)
  Book.title:SetPoint("TOPLEFT", 0, 0)
  Book.title:SetJustifyH("LEFT")
  Book.objectives = NewText(Book.pageChild, 13)
  Book.objectives:SetJustifyH("LEFT")
  Book.body = NewText(Book.pageChild, 13)
  Book.body:SetJustifyH("LEFT")
end

local function UpdateButtons(entry)
  Book.btnTrack:SetText(IsWatched(entry.questID) and "Untrack" or "Track")
  Book.btnActive:SetText(IsActiveQuest(entry.questID) and "Clear" or "Active")
  Book.btnShare:SetEnabled(CanShare(entry))
  Book.btnAbandon:SetEnabled(true)
  LayoutLinks()
end

-- Which list row shows the quest on the page.
local function MarkSelected()
  local id = lastEntry and lastEntry.questID
  for _, b in ipairs(ListButtons) do
    if b.sel then b.sel:SetShown(b:IsShown() and b.questID ~= nil and b.questID == id) end
  end
end

-- Ask the overlay module (which owns the world map frame) for a map plate for this quest; the text then makes room for it.
-- `Book.plateWanted` is only true where it really has something to show.
local function UpdatePlate(entry)
  if docked or mod.db.plate == false then
    QB:Call("overlay", "PlateHide")
    Book.plateWanted = false
    return
  end
  local ok, shown = QB:Call("overlay", "PlateShow", Book.plate, entry, Book.plateCap)
  Book.plateWanted = (ok and shown) and true or false
end

ShowQuest = function(entry)
  for i, e in ipairs(currentEntries) do
    if e.questID == entry.questID then currentIndex = i break end
  end
  local th = Theme()
  local desc, obj = GetQuestText(entry)
  lastEntry, lastDesc = entry, desc
  UpdatePlate(entry)
  local ready, done = IsReadyToTurnIn(entry), IsQuestDone(entry)
  local doneHex = Style.Hex(th.done)
  local mark = ready and ("  |cff" .. doneHex .. "(ready to turn in)|r") or (done and ("  |cff" .. doneHex .. "(complete)|r") or "")
  Book.title:SetText((entry.level and ("[" .. entry.level .. "] ") or "") .. (entry.title or "") .. mark)
  Book.objectives:SetText((ready and ("|cff" .. doneHex .. "Ready to turn in.|r\n") or (done and ("|cff" .. doneHex .. "Objectives complete.|r\n") or "")) .. obj)
  Book.body:SetText(desc)
  Style.SetInk(Book.title, th.strong)
  Style.SetInk(Book.objectives, th.pending)
  Style.SetInk(Book.body, th.ink)
  Style.SetShadow(Book.title, th); Style.SetShadow(Book.objectives, th); Style.SetShadow(Book.body, th)
  FitLeft()
  -- a text height read right after SetText can lag a frame; settle once more
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, Guard(function() if Book:IsShown() and lastEntry == entry then FitLeft() end end))
  end
  UpdateButtons(entry)
  MarkSelected()
end

-- The list: zone / campaign headers (Blizzard's own), our own collapse, and EVERY quest on
-- the page: rows shrink to fit the page (down to ROW_MIN); only a log too long even for that scrolls.
-- `keepID`: select this quest again; `keepScroll`: leave the list scroll alone.
RefreshList = function(keepID, keepScroll)
  local rows, quests = ScanLog()
  currentEntries = quests
  local th = Theme()
  local scroll = keepScroll and Book.list:GetVerticalScroll() or 0
  for _, b in ipairs(ListButtons) do b:Hide() end
  local collapsed = mod.db.collapsed

  -- visible rows, then the row height that fits them all
  local visible, nHead, nQuest = {}, 0, 0
  for _, row in ipairs(rows) do
    local hidden = row.kind == "quest" and row.header and collapsed[row.header]
    if not hidden then
      visible[#visible + 1] = row
      if row.kind == "header" then nHead = nHead + 1 else nQuest = nQuest + 1 end
    end
  end
  local avail = G.listH or 600
  local units = nQuest + 1.2 * nHead
  local rowH = units > 0 and Style.Clamp(math.floor(avail / units), ROW_MIN, ROW_MAX) or ROW_MAX
  local headH = math.floor(rowH * 1.2)
  local fontSize = Style.Clamp(math.floor(rowH * 0.55), 9, 13)
  local used = nQuest * rowH + nHead * headH
  G.rows = { rowH = rowH, headH = headH, font = fontSize, quests = nQuest, headers = nHead,
    used = used, avail = avail, scrolls = used > avail }
  Book.listHead:SetText("QUESTS  (" .. nQuest .. ")")

  local y = 0
  for i, row in ipairs(visible) do
    local btn = ListButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, Book.listChild)
      btn.text = NewText(btn, 12)
      btn.text:SetPoint("LEFT", 4, 0)
      btn.text:SetJustifyH("LEFT"); btn.text:SetWordWrap(false)
      btn.sel = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
      btn.sel:SetAllPoints(btn); btn.sel:Hide()
      btn.hov = btn:CreateTexture(nil, "BACKGROUND", nil, 0)
      btn.hov:SetAllPoints(btn); btn.hov:Hide()
      btn:SetScript("OnEnter", function(self) self.hov:Show() end)
      btn:SetScript("OnLeave", function(self) self.hov:Hide() end)
      ListButtons[i] = btn
    end
    local h = (row.kind == "header") and headH or rowH
    btn:SetSize(G.listW or 280, h)
    btn.text:SetWidth((G.listW or 280) - 8)
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", 0, -y)
    btn.sel:SetColorTexture(th.selected[1], th.selected[2], th.selected[3], th.selected[4])
    btn.hov:SetColorTexture(th.hover[1], th.hover[2], th.hover[3], th.hover[4])
    Style.SetShadow(btn.text, th)
    if row.kind == "header" then
      Style.SetFont(btn.text, "body", fontSize, th)
      Style.SetInk(btn.text, th.rubric)
      local isCollapsed = collapsed[row.title]
      btn.questID = nil
      btn.text:SetText((isCollapsed and "+ " or "- ") .. string.upper(row.title or "?"))
      btn:SetScript("OnClick", Guard(function()
        collapsed[row.title] = (not collapsed[row.title]) or nil
        RefreshList(lastEntry and lastEntry.questID, true)
      end))
    else
      local e = row.entry
      local tag = ""
      if IsActiveQuest(e.questID) then tag = "> "
      elseif IsWatched(e.questID) then tag = "* " end
      local ready = IsReadyToTurnIn(e)
      Style.SetFont(btn.text, "body", fontSize, th)
      Style.SetInk(btn.text, ready and th.done or th.ink)
      btn.questID = e.questID
      btn.text:SetText("  " .. tag .. (e.title or "?"))
      btn:SetScript("OnClick", Guard(function() ShowQuest(e) end))
    end
    y = y + h
    btn:Show()
  end
  Book.listChild:SetWidth(G.listW or 280)
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
    Book.plateWanted = false
    QB:Call("overlay", "PlateHide")
    Book.title:SetText("No quests in your log.")
    Book.objectives:SetText(""); Book.body:SetText("")
    FitLeft()
  end
  MarkSelected()
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

-- the world map is the one thing the plate shares: Map mode, ESC, the M key or combat can take it
QB:On("plate_lost", function()
  if Book then Book.plateWanted = false; if Book:IsShown() then FitLeft() end end
end, mod)
-- a plate refused in combat is tried again when combat ends
QB:On("combat_end", function()
  if Book and Book:IsShown() and lastEntry and not Book.plateWanted then ShowQuest(lastEntry) end
end, mod)

mod.events.QUEST_LOG_UPDATE = QueueRefresh
mod.events.QUEST_WATCH_LIST_CHANGED = QueueRefresh
mod.events.SUPER_TRACKING_CHANGED = QueueRefresh
mod.events.QUEST_REMOVED = QueueRefresh
mod.events.PLAYER_STARTED_MOVING = function() OnStartedMoving() end
mod.events.VOICE_CHAT_TTS_PLAYBACK_STARTED = function() SetSpeaking(true) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FINISHED = function() SetSpeaking(false) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FAILED = function() SetSpeaking(false) end

-- ---------------------------------------------------------------- replace Blizzard's log

-- Open the book (and on a quest, if given). Used by every rerouted Blizzard entry point.
function mod:OpenBook(questID)
  if not Book then BuildBook() end
  if not Book:IsShown() then
    docked = false
    ApplyLayout()
    Book:Show()
  end
  RefreshList(questID or (lastEntry and lastEntry.questID), false)
  if questID and lastEntry and lastEntry.questID ~= questID then
    Say("quest " .. tostring(questID) .. " is not in your log")
  end
  if IsPlayerMoving and IsPlayerMoving() then OnStartedMoving() end
end

-- Blizzard's quest log is reached through several globals, all rerouted here while the book is
-- the default (/qb log replace):
--   ToggleQuestLog()                     default key, micro menu button
--   OpenQuestLog(mapID)                  "view in quest log" paths, objective tracker bonus blocks
--   QuestMapFrame_OpenToQuestDetails(id) objective tracker click on a quest (it calls OpenQuestLog)
--   QuestUtil.OpenQuestDetails(id)       tracker menu "view in quest log" (popup detail frame)
-- (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua, Blizzard_ObjectiveTracker/*.lua,
--  Blizzard_FrameXMLUtil/Mainline/QuestUtils.lua)
-- UNVERIFIED: that replacing these taints nothing the map needs; /qb log blizzard (or
-- /qb disable questlog) puts every original back at once.
local OVERRIDES = {
  { name = "ToggleQuestLog", run = function() mod:Toggle() end },
  { name = "OpenQuestLog", run = function() mod:OpenBook() end },
  { name = "QuestMapFrame_OpenToQuestDetails", run = function(questID) mod:OpenBook(questID) end },
  { name = "QuestUtil.OpenQuestDetails", table = "QuestUtil", field = "OpenQuestDetails",
    run = function(questID) mod:OpenBook(questID) end },
}

local function Owner(o)
  if o.table then return _G[o.table], o.field end
  return _G, o.name
end

local function InstallToggleOverride()
  mod.orig = mod.orig or {}
  local missing = {}
  for _, o in ipairs(OVERRIDES) do
    local t, k = Owner(o)
    if type(t) == "table" and type(t[k]) == "function" then
      if not mod.orig[o.name] then
        local orig = t[k]
        mod.orig[o.name] = orig
        o.ours = function(...)
          if mod.active and mod.db.replaceLog then
            QB:Safe(mod, o.run, ...)
          else
            return orig(...)
          end
        end
        t[k] = o.ours
      end
    else
      missing[#missing + 1] = o.name
    end
  end
  if #missing > 0 then
    mod.missingOverrides = table.concat(missing, ", ")
    Say("not found on this client, still Blizzard's: " .. mod.missingOverrides)
  end
end

local function RemoveToggleOverride()
  for _, o in ipairs(OVERRIDES) do
    local t, k = Owner(o)
    if mod.orig and mod.orig[o.name] and type(t) == "table" and t[k] == o.ours then
      t[k] = mod.orig[o.name]
    end
    if mod.orig then mod.orig[o.name] = nil end
    o.ours = nil
  end
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
  if mod.orig and mod.orig.ToggleQuestLog then mod.orig.ToggleQuestLog() else Say("Blizzard's quest log is already the default") end
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

QB:RegisterSlash(mod, "bg", function(rest)
  local n = tonumber(rest)
  if n then
    mod.db.bgAlpha = math.max(0, math.min(1, n))
    ApplyTheme()
  end
  Say("dark theme panel opacity " .. string.format("%.2f", mod.db.bgAlpha) .. " (/qb bg <0-1>; the paper theme ignores it)")
end, "bg <0-1>: opacity of the dark theme's panel")

QB:RegisterSlash(mod, "book", function(rest)
  rest = (rest or ""):lower()
  if rest == "map on" or rest == "map off" then
    mod.db.plate = (rest == "map on")
    if Book and Book:IsShown() and lastEntry then ShowQuest(lastEntry) end
  elseif rest == "paper" or rest == "dark" then
    mod.db.theme = rest
    if Book then
      ApplyLayout()
      if Book:IsShown() then RefreshList(lastEntry and lastEntry.questID, true) end
    end
  end
  local f, r = G.fit, G.rows
  Say("book theme: " .. mod.db.theme .. "  map plate: " .. (mod.db.plate and "on" or "off") .. "  (/qb book paper||dark, /qb book map on||off)")
  if f then
    Say(string.format("  left page: text %d px at font %d (set %d) in %d px, %s%s", f.total or 0, f.font or 0, f.base or 0,
      f.avail or 0, f.fits and "fits" or "SCROLLS", f.plate and (", plate " .. f.plateH .. " px") or ", no map plate"))
  end
  if r then
    Say(string.format("  list: %d quests + %d headers, rows %d px (font %d), %d of %d px, %s", r.quests, r.headers,
      r.rowH, r.font, r.used, r.avail, r.scrolls and "SCROLLS" or "fits"))
  end
end, "book paper|dark: the quest book's theme; with no argument, how the page and the list fit")

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
    if Book and Book:IsShown() and lastEntry then ShowQuest(lastEntry) end
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
