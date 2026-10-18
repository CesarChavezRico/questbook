-- QuestBook / QuestLog module -- the quest reader, and the replacement for Blizzard's quest log.
--
-- v0.13: ONE page, set where the big map sits. It replaces the open-book design (two pages, a map plate, a list):
-- the list is the tracker (modules/Tracker.lua), where a left click makes a quest the active one and a right click
-- opens it here. The reader shows the quest's title, a meta line, the description, the objectives, and the duties
-- (make it the active quest, track, share, abandon), walks through your quests with the arrows, and reads the quest
-- aloud (walk-and-listen, below).
--
-- It shares the map's place: the same centre and height as the big overlay (Overlay:ReaderRect), and the same
-- camera shift and zoom-out (modules/Camera.lua, through the "reader_state" topic). Opening it closes the map overlay;
-- the map key while it is open brings the map up and closes the reader ("overlay_state" with anything but "off").
--
-- Every duty follows the flow Blizzard's own quest log uses in the Forever client dump (Blizzard_UIPanels_Game/
-- Mainline/QuestMapFrame.lua: QuestMapQuestOptions_TrackQuest / _ShareQuest / _AbandonQuest).
--
-- COMMANDS:
--   /qb               toggle the reader
--   /qb size <px>     body text size in physical pixels (default 22; title and the rest scale with it)
--   /qb voice         toggle walk-and-listen TTS (default on)
--   /qb debug         narrate the walk-and-listen chain in chat
--   /qb rate <n>      speaking rate, -10..10 (0 = normal)
--   /qb prosody       toggle SAPI pause tags between paragraphs
--   /qb say | voices | usevoice <id>   TTS diagnostics
--   /qb log replace|blizzard   which quest log the default key / menu button opens
--   /qb blizzlog      open Blizzard's own quest log once (the fallback)
--
-- UNVERIFIED (client only): how the page looks and fits in the game; that the reader and the map really trade places
-- cleanly; that the Esc key closes it (it is a UISpecialFrame).

local _, QB = ...
local Style = QB.Style
local K = Style.KIT

local mod = QB:NewModule("questlog", {
  replaceLog = true,    -- ToggleQuestLog (default key, micro menu button) opens the reader
  body = 22,            -- body text size, physical pixels
  height = 0,           -- page height as a fraction of the screen (0.3-0.95); 0 = the big map's height
  aspect = 0.84,        -- page width / height
  hideMinimap = true,   -- hide the small corner minimap while the reader is open
  hideFrames = true,    -- hide the player and target frames while the reader is open
  scrollbar = false,    -- a thin scroll track beside the text (off: the wheel still scrolls)
})

local db              -- QB.db: the flat legacy QuestBookDB settings
local R               -- the reader frame
local entries = {}    -- quests only, in log order (the arrows walk this)
local index
local lastEntry, lastDesc
local debugMode = false
local isSpeaking = false
local openFlag = false           -- "reader_state" was announced as open
local spokeFor                   -- quest the walk-and-listen already read for this opening
local keepSpeech = false         -- the page is closing because you walked off: the reading goes on
local RefreshChrome              -- forward declaration (the duties call it)

local function Dbg(msg) if debugMode then print("|cff7faaffQB-debug|r: " .. msg) end end
local function Say(msg) QB:Say(msg) end

-- Wrap a UI script so a fault in it is isolated like any other module entry.
local function Guard(fn)
  return function(...) QB:Safe(mod, fn, ...) end
end

-- ---------------------------------------------------------------- log data

local UNAVAILABLE = "(the text of this quest is not available)"

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

-- The quests in the log, headers expanded as the reader needs them (used by the tracker's "all" mode).
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

-- The description, the objectives as a list ({ text, done }), and a fallback block of text when the log gives no list.
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

  local list = {}
  if C_QuestLog and C_QuestLog.GetQuestObjectives then
    local ok, items = pcall(C_QuestLog.GetQuestObjectives, entry.questID)
    if ok and type(items) == "table" then
      for _, item in ipairs(items) do
        if item.text and item.text ~= "" then list[#list + 1] = { text = item.text, done = item.finished and true or false } end
      end
    end
  elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
    local ok, n = pcall(GetNumQuestLeaderBoards, entry.index)
    if ok and n then
      for j = 1, n do
        local ok2, text, _, finished = pcall(GetQuestLogLeaderBoard, j, entry.index)
        if ok2 and text then list[#list + 1] = { text = text, done = finished and true or false } end
      end
    end
  end
  return desc or UNAVAILABLE, list, obj
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

-- Make a quest the active one (never clears it: the tracker's left click; the reader's button toggles).
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
  return ok
end

local function SetSpeaking(state)
  local changed = (isSpeaking ~= state)
  isSpeaking = state
  if R and R.talk then R.talk:SetText(state and "Stop" or "Talk") end
  if changed then QB:Fire("speech_state", state) end       -- the tracker's voice link follows it
end

local function StopSpeaking()
  if C_VoiceChat and C_VoiceChat.StopSpeakingText then pcall(C_VoiceChat.StopSpeakingText) end
  SetSpeaking(false)   -- a killed speech fires no FINISHED event; reset locally
end

-- ---------------------------------------------------------------- the page
--
-- Everything is laid out in physical pixels (Style.Px), on a torn-paper page (Style.Paper). From the top: the title
-- (the game's book font), a tapering rule, a meta line; then a scrolling area with the description and the
-- objectives; then a row of ink links (previous, talk, next on the left; track, share, abandon on the right); then
-- the one strong button (make active) and a quiet one (close, with the Esc key cap).

local M = 68                 -- margin, px
local objRows = {}           -- pooled objective rows
local ObjRow

local function Px(n) return Style.Px(n, R) end
local function Unit() return Style.PixelUnit(R) end

local function Sizes()
  local body = Style.Clamp(tonumber(mod.db.body) or 22, 14, 40)
  return body, math.floor(body * K.title + 0.5), math.floor(body * K.header + 0.5), math.floor(body * K.small + 0.5)
end

local function Fs(parent, path, px, color, justify)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  fs:SetFont(path, Px(px), "")                            -- a font at birth: SetText on a fontless string errors
  fs:SetJustifyH(justify or "LEFT")
  fs:SetTextColor(color[1], color[2], color[3], color[4] or 1)
  return fs
end

local function Rect(parent, c, layer)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  t:SetTexture("Interface\\Buttons\\WHITE8x8")
  t:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
  return t
end

local function ScrollMax()
  return math.max(0, (R.child:GetHeight() or 0) - (R.scroll:GetHeight() or 0))
end

-- No scroll bar on the page by default (Cesar, 2026-10-17): a long text still scrolls with the wheel, and
-- `/qb reader height` makes the page taller. `/qb reader scrollbar on` brings the thin track and thumb back.
local function UpdateThumb()
  if not mod.db.scrollbar then R.thumb:Hide(); R.track:Hide(); return end
  local max = ScrollMax()
  if max <= 0 then R.thumb:Hide(); R.track:Hide(); return end
  local vh = R.scroll:GetHeight()
  local ch = R.child:GetHeight()
  local th = math.max(Px(40), vh * vh / ch)
  local frac = (R.scroll:GetVerticalScroll() or 0) / max
  R.track:Show(); R.thumb:Show()
  R.thumb:SetHeight(th)
  R.thumb:ClearAllPoints()
  R.thumb:SetPoint("TOP", R.track, "TOP", 0, -(vh - th) * frac)
end

local function SetScroll(v)
  v = Style.Clamp(v or 0, 0, ScrollMax())
  R.scroll:SetVerticalScroll(v)
  UpdateThumb()
end

local function Build()
  R = CreateFrame("Frame", "QuestBookReader", UIParent)
  R:SetFrameStrata("HIGH")
  R:EnableMouse(true)                                      -- it is a page: clicks on it stay on it
  R:Hide()
  tinsert(UISpecialFrames, "QuestBookReader")              -- Esc closes it
  R.paper = Style.Paper(R)

  R.title = Fs(R, Style.MORPHEUS, 40, K.ink)
  R.rule = Style.Hairline(R, { K.ink[1], K.ink[2], K.ink[3], 0.85 })
  R.meta = Fs(R, Style.FRIZ, 18, K.faded)

  R.scroll = CreateFrame("ScrollFrame", nil, R)
  R.child = CreateFrame("Frame", nil, R.scroll)
  R.scroll:SetScrollChild(R.child)
  R.scroll:EnableMouseWheel(true)
  R.scroll:SetScript("OnMouseWheel", Guard(function(_, delta) SetScroll((R.scroll:GetVerticalScroll() or 0) - delta * Px(64)) end))
  R.body = Fs(R.child, Style.FRIZ, 22, K.ink)
  R.body:SetPoint("TOPLEFT", R.child, "TOPLEFT", 0, 0)
  R.tab = Rect(R.child, { K.ink[1], K.ink[2], K.ink[3], 0.07 }, "BACKGROUND")
  R.tabText = Fs(R.child, Style.FRIZ, 26, K.ink)
  R.tabText:SetText("Objectives")
  R.track = Rect(R, { K.ink[1], K.ink[2], K.ink[3], 0.10 }, "ARTWORK")
  R.thumb = Rect(R, { K.ink[1], K.ink[2], K.ink[3], 0.38 }, "OVERLAY")

  -- ink links: left group walks and reads, right group acts on the quest
  R.prev = Style.InkLink(R, 18, function() mod:Nav(-1) end);  R.prev:SetText("\226\128\185 previous")
  R.talk = Style.InkLink(R, 18, function() mod:ToggleSpeak() end); R.talk:SetText("Talk")
  R.next = Style.InkLink(R, 18, function() mod:Nav(1) end);   R.next:SetText("next \226\128\186")
  R.trackBtn = Style.InkLink(R, 18, function() ToggleTrack(lastEntry) end); R.trackBtn:SetText("Track")
  R.share = Style.InkLink(R, 18, function() ShareQuest(lastEntry) end);    R.share:SetText("Share")
  R.abandon = Style.InkLink(R, 18, function() AbandonQuest(lastEntry) end); R.abandon:SetText("Abandon")
  R.abandon:SetWarn(true)
  R.links = { R.prev, R.talk, R.next, R.trackBtn, R.share, R.abandon }

  R.primary = Style.PaperButton(R, 300, 60, "Make active", true, nil, function() ToggleActive(lastEntry) end)
  R.closeBtn = Style.PaperButton(R, 300, 60, "Close", false, "Esc", function() R:Hide() end)

  R:SetScript("OnHide", Guard(function() mod:OnClosed() end))
end

ObjRow = function(i)
  local r = objRows[i]
  if r then return r end
  r = {}
  r.stripe = Rect(R.child, { K.ink[1], K.ink[2], K.ink[3], 0.045 }, "BACKGROUND")
  r.box = Rect(R.child, { K.ink[1], K.ink[2], K.ink[3], 0.85 }, "ARTWORK")
  r.fill = Rect(R.child, { 0.83, 0.70, 0.50, 1 }, "OVERLAY")
  r.text = Fs(R.child, Style.FRIZ, 22, K.ink)
  objRows[i] = r
  return r
end

-- Place everything for the current quest at the current size. Cheap enough to run on every change.
function mod:Reflow()
  if not (R and R.paper) then return end
  local u = Unit()
  local pw, ph = (R:GetWidth() or 0) / u, (R:GetHeight() or 0) / u
  if pw <= 0 then return end
  local body, tpx, hpx, spx = Sizes()
  local cw = pw - 2 * M

  R.title:SetFont(Style.MORPHEUS, Px(tpx), "")
  R.title:ClearAllPoints(); R.title:SetPoint("TOPLEFT", R, "TOPLEFT", Px(M), -Px(60)); R.title:SetWidth(Px(cw))
  local y = 60 + (R.title:GetStringHeight() or 0) / u + 14
  R.rule:ClearAllPoints()
  R.rule:SetPoint("TOPLEFT", R, "TOPLEFT", Px(M - 8), -Px(y))
  R.rule:SetPoint("TOPRIGHT", R, "TOPRIGHT", -Px(M - 8), -Px(y))
  R.rule:SetHeight(Px(8))
  y = y + 18
  R.meta:SetFont(Style.FRIZ, Px(spx), "")
  R.meta:ClearAllPoints(); R.meta:SetPoint("TOPLEFT", R, "TOPLEFT", Px(M), -Px(y)); R.meta:SetWidth(Px(cw))
  y = y + (R.meta:GetStringHeight() or 0) / u + 22

  -- the bottom: the two buttons, the link row above them
  local btnH = 60
  local btnTop = ph - 56 - btnH
  local bw = math.floor((cw - 24) / 2)
  R.primary:SetSize(Px(bw), Px(btnH)); R.primary:ClearAllPoints(); R.primary:SetPoint("TOPLEFT", R, "TOPLEFT", Px(M), -Px(btnTop))
  R.closeBtn:SetSize(Px(bw), Px(btnH)); R.closeBtn:ClearAllPoints(); R.closeBtn:SetPoint("TOPRIGHT", R, "TOPRIGHT", -Px(M), -Px(btnTop))
  local linkTop = btnTop - 22 - (spx + 8)
  for _, l in ipairs(R.links) do l:SetPx(spx) end
  local x = M
  for _, l in ipairs({ R.prev, R.talk, R.next }) do
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", R, "TOPLEFT", Px(x), -Px(linkTop))
    x = x + (l:GetWidth() or 0) / u + 26
  end
  x = pw - M
  for _, l in ipairs({ R.abandon, R.share, R.trackBtn }) do
    x = x - (l:GetWidth() or 0) / u
    l:ClearAllPoints(); l:SetPoint("TOPLEFT", R, "TOPLEFT", Px(x), -Px(linkTop))
    x = x - 26
  end

  -- the scrolling area: the description, then the objectives
  local vTop, vBottom = y, linkTop - 16
  R.scroll:ClearAllPoints()
  R.scroll:SetPoint("TOPLEFT", R, "TOPLEFT", Px(M), -Px(vTop))
  R.scroll:SetSize(Px(cw), Px(math.max(40, vBottom - vTop)))
  R.child:SetWidth(Px(cw))
  R.body:SetFont(Style.FRIZ, Px(body), "")
  R.body:SetWidth(Px(cw))
  R.body:SetSpacing(Px(math.floor(body * 0.34)))
  local h = (R.body:GetStringHeight() or 0) / u
  local objs = R.objs or {}
  if #objs > 0 then
    local ty = h + 34
    R.tabText:SetFont(Style.FRIZ, Px(hpx), "")
    R.tab:ClearAllPoints(); R.tab:SetPoint("TOPLEFT", R.child, "TOPLEFT", -Px(10), -Px(ty))
    R.tabText:ClearAllPoints(); R.tabText:SetPoint("TOPLEFT", R.child, "TOPLEFT", Px(4), -Px(ty + 5))
    local tabH = hpx + 16
    R.tab:SetSize(Px(math.max(200, (R.tabText:GetStringWidth() or 0) / u + 28)), Px(tabH))
    R.tab:Show(); R.tabText:Show()
    local ry = ty + tabH + 12
    for i, o in ipairs(objs) do
      local r = ObjRow(i)
      r.text:SetFont(Style.FRIZ, Px(body), "")
      r.text:SetWidth(Px(cw - 40))
      r.text:SetText(o.text)
      local c = o.done and K.faded or K.ink
      r.text:SetTextColor(c[1], c[2], c[3], 1)
      local th = (r.text:GetStringHeight() or 0) / u
      local rh = math.max(46, th + 16)
      r.stripe:ClearAllPoints(); r.stripe:SetPoint("TOPLEFT", R.child, "TOPLEFT", -Px(10), -Px(ry)); r.stripe:SetSize(Px(cw + 20), Px(rh))
      r.stripe:SetShown(i % 2 == 1)
      local by = ry + (rh - 18) / 2
      r.box:ClearAllPoints(); r.box:SetPoint("TOPLEFT", R.child, "TOPLEFT", 0, -Px(by)); r.box:SetSize(Px(18), Px(18))
      r.fill:ClearAllPoints(); r.fill:SetPoint("TOPLEFT", R.child, "TOPLEFT", Px(2), -Px(by + 2)); r.fill:SetSize(Px(14), Px(14))
      local fc = o.done and K.brick or { 0.83, 0.70, 0.50, 1 }
      r.fill:SetVertexColor(fc[1], fc[2], fc[3], 1)
      r.text:ClearAllPoints(); r.text:SetPoint("TOPLEFT", R.child, "TOPLEFT", Px(36), -Px(ry + (rh - th) / 2))
      r.stripe:Show(); r.box:Show(); r.fill:Show(); r.text:Show()
      r.stripe:SetShown(i % 2 == 1)
      ry = ry + rh
    end
    for i = #objs + 1, #objRows do
      local r = objRows[i]; r.stripe:Hide(); r.box:Hide(); r.fill:Hide(); r.text:Hide()
    end
    h = ry + 8
  else
    R.tab:Hide(); R.tabText:Hide()
    for _, r in ipairs(objRows) do r.stripe:Hide(); r.box:Hide(); r.fill:Hide(); r.text:Hide() end
  end
  R.child:SetHeight(Px(math.max(h, 10)))

  -- the scroll track sits just outside the right margin
  R.track:ClearAllPoints()
  R.track:SetPoint("TOPLEFT", R.scroll, "TOPRIGHT", Px(14), 0)
  R.track:SetSize(Px(4), R.scroll:GetHeight() or 0)
  SetScroll(R.scroll:GetVerticalScroll() or 0)
end

-- Size and place the page where the big map sits: the same centre and height (Overlay:ReaderRect).
function mod:Layout()
  if not R then return end
  local O = QB.modules.overlay
  local w, h, cx, cy
  local aspect = Style.Clamp(tonumber(self.db.aspect) or 0.84, 0.5, 1.4)
  if O and O.active and O.ReaderRect then w, h, cx, cy = O:ReaderRect(aspect) end
  if not w then
    local W, H = UIParent:GetWidth(), UIParent:GetHeight()
    h = H * 0.62; w = h * aspect; cx = W * 0.17; cy = H * 0.02
  end
  local own = tonumber(self.db.height) or 0
  if own > 0 then                                   -- its own height: taller (or shorter) than the map, same centre
    h = UIParent:GetHeight() * Style.Clamp(own, 0.3, 0.95)
    w = h * aspect
  end
  w, h = Style.Snap(w, R), Style.Snap(h, R)
  R:SetSize(w, h)
  R:ClearAllPoints()
  R:SetPoint("CENTER", UIParent, "CENTER", Style.Snap(cx, R), Style.Snap(cy, R))
  R.paper:Layout()
  self:Reflow()
end

local function ActiveID()
  if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    if ok and type(id) == "number" and id > 0 then return id end
  end
  return nil
end

local function UpdateButtons(entry)
  R.primary:SetLabel(IsActiveQuest(entry.questID) and "Clear active quest" or "Make active")
  R.trackBtn:SetText(IsWatched(entry.questID) and "Untrack" or "Track")
  R.share:SetEnabled(CanShare(entry))
  R.abandon:SetEnabled(true)
  R.primary:SetEnabled(true)
  R.talk:SetText(isSpeaking and "Stop" or "Talk")
  R.prev:SetEnabled(#entries > 1); R.next:SetEnabled(#entries > 1)
  mod:Reflow()                    -- the link widths changed with their text
end

local function ShowQuest(entry, keepScroll)
  for i, e in ipairs(entries) do
    if e.questID == entry.questID then index = i break end
  end
  local scroll = keepScroll and (R.scroll:GetVerticalScroll() or 0) or 0
  local desc, objs, objText = GetQuestText(entry)
  lastEntry, lastDesc = entry, desc
  local ready, done = IsReadyToTurnIn(entry), IsQuestDone(entry)
  local meta = {}
  if entry.level then meta[#meta + 1] = "Level " .. entry.level end
  if entry.header then meta[#meta + 1] = entry.header end
  if ready then meta[#meta + 1] = "|cff" .. Style.Hex(K.done) .. "Ready to turn in|r"
  elseif done then meta[#meta + 1] = "|cff" .. Style.Hex(K.done) .. "Complete|r" end
  if IsActiveQuest(entry.questID) then meta[#meta + 1] = "Active quest" end
  R.title:SetText(entry.title or "?")
  R.meta:SetText(table.concat(meta, "  \194\183  "))
  R.body:SetText(desc)
  if #objs == 0 and objText and objText ~= "" then objs = { { text = objText, done = ready } } end
  R.objs = objs
  UpdateButtons(entry)
  SetScroll(scroll)
  -- a text height read right after SetText can lag a frame; settle once more
  if C_Timer and C_Timer.After then
    C_Timer.After(0.05, Guard(function() if R:IsShown() and lastEntry == entry then mod:Reflow() end end))
  end
end

-- Scan the log and show a quest: the one asked for, else the one on the page, else the active one, else the first.
local function ShowFromLog(wantID, keepScroll)
  local _, quests = ScanLog()
  entries = quests
  local pick
  for _, id in ipairs({ wantID or 0, lastEntry and lastEntry.questID or 0, ActiveID() or 0 }) do
    for _, e in ipairs(quests) do
      if e.questID == id then pick = e break end
    end
    if pick then break end
  end
  pick = pick or quests[1]
  if pick then
    ShowQuest(pick, keepScroll)
  else
    lastEntry, lastDesc = nil, nil
    R.title:SetText("No quests in your log.")
    R.meta:SetText("")
    R.body:SetText("")
    R.objs = {}
    UpdateButtons({ questID = 0 })
    R.primary:SetEnabled(false); R.abandon:SetEnabled(false); R.share:SetEnabled(false)
    mod:Reflow()
  end
end

-- After a duty (track / active) or a log event: refresh the marks without losing the reading position.
RefreshChrome = function()
  if R and R:IsShown() and lastEntry then ShowFromLog(lastEntry.questID, true) end
end

function mod:Nav(delta)
  local n = #entries
  if n == 0 then return end
  local idx = (((index or 1) - 1 + delta) % n) + 1
  ShowQuest(entries[idx])
  StopSpeaking()
  Speak(lastEntry, lastDesc, true)
end

function mod:ToggleSpeak()
  if isSpeaking then
    StopSpeaking()
  else
    StopSpeaking()
    Speak(lastEntry, lastDesc, true)
  end
end

-- ---------------------------------------------------------------- opening, closing, trading places with the map

local function Blocked()
  local O = QB.modules.overlay
  return O and O.db and O.db.combatGuard and QB:InCombat()
end

-- Open the reader (on a quest, if given). Used by every rerouted Blizzard entry point and by the tracker's right click.
function mod:Open(questID)
  if not R then Build() end
  if not R:IsShown() then
    if Blocked() then Say("quest reader: not in combat") return end
    -- Order matters: announce the reader BEFORE the map closes, so the camera never lets go in between
    -- (it follows "reader_state" and "overlay_state": the shift stays while either is up).
    if not openFlag then openFlag = true; QB:Fire("reader_state", true) end
    -- hide what the map hides, and what the settings add (before the map closes, so it all stays hidden through the swap)
    QB:Call("overlay", "ReaderOpen", true, { minimap = mod.db.hideMinimap, frames = mod.db.hideFrames })
    local O = QB.modules.overlay
    if O and O.active and O.state ~= "off" then QB:Call("overlay", "SetState", "off", true) end
    self:Layout()
    R:Show()
    spokeFor = nil
  end
  ShowFromLog(questID)
  if questID and lastEntry and lastEntry.questID ~= questID then Say("quest " .. tostring(questID) .. " is not in your log") end
  if IsPlayerMoving and IsPlayerMoving() then mod:OnStartedMoving() end
end
mod.OpenBook = mod.Open         -- the name earlier versions (and the tracker) used

function mod:Toggle()
  if R and R:IsShown() then R:Hide() else self:Open() end
end

function mod:OnClosed()
  if not keepSpeech then StopSpeaking() end
  QB:Call("overlay", "ReaderOpen", false)            -- the bars, minimap and frames come back (the bars stay hidden if the map took the place)
  if openFlag then
    openFlag = false
    QB:Fire("reader_state", false)
  end
end

-- the map key brought the map up (any overlay state but "off"): the page makes way for it
QB:On("overlay_state", function(state)
  if state ~= "off" and R and R:IsShown() then R:Hide() end
end, mod)
QB:On("combat_start", function()
  if R and R:IsShown() then
    R:Hide()
    Say("quest reader closed for combat")
  end
end, mod)

-- Walk-and-listen: the first step you take with the reader open reads the quest to you (once per quest) and, when the
-- reading started, puts the page away so you can see where you walk; the reading goes on, and the tracker has a link
-- to stop it. With voice off the page stays.
function mod:OnStartedMoving()
  if R and R:IsShown() and lastEntry and spokeFor ~= lastEntry.questID then
    spokeFor = lastEntry.questID
    if Speak(lastEntry, lastDesc) then
      keepSpeech = true
      R:Hide()
      keepSpeech = false
    end
  end
end

-- For the tracker's voice link: what it should say and do.
function mod:VoiceState()
  if isSpeaking then return "speaking" end
  return (db and db.voice) and "on" or "off"
end
function mod:StopSpeech() StopSpeaking() end
function mod:ToggleVoice()
  if not db then return end
  db.voice = not db.voice
  if not db.voice then StopSpeaking() end
  QB:Fire("speech_state", isSpeaking)
end

-- ---------------------------------------------------------------- events

local refreshPending = false
local function RefreshAll()
  refreshPending = false
  RefreshChrome()
end

-- these fire in bursts; coalesce to one re-render, keep the reading position
local function QueueRefresh()
  if R and R:IsShown() and not refreshPending then
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
mod.events.PLAYER_STARTED_MOVING = function(self) self:OnStartedMoving() end
mod.events.VOICE_CHAT_TTS_PLAYBACK_STARTED = function() SetSpeaking(true) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FINISHED = function() SetSpeaking(false) end
mod.events.VOICE_CHAT_TTS_PLAYBACK_FAILED = function() SetSpeaking(false) end
mod.events.DISPLAY_SIZE_CHANGED = function(self) if R and R:IsShown() then self:Layout() end end
mod.events.UI_SCALE_CHANGED = mod.events.DISPLAY_SIZE_CHANGED

-- ---------------------------------------------------------------- replace Blizzard's log

-- Blizzard's quest log is reached through several globals, all rerouted here while the reader is
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
  { name = "OpenQuestLog", run = function() mod:Open() end },
  { name = "QuestMapFrame_OpenToQuestDetails", run = function(questID) mod:Open(questID) end },
  { name = "QuestUtil.OpenQuestDetails", table = "QuestUtil", field = "OpenQuestDetails",
    run = function(questID) mod:Open(questID) end },
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
  if R then R:Hide() end
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
  Say("the default quest log key opens " .. (mod.db.replaceLog and "the QuestBook reader" or "Blizzard's log"))
end, "log replace|blizzard: which quest log the default key / menu button opens")

QB:RegisterSlash(mod, "reader", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  local d = mod.db
  if sub == "height" then
    if arg == "auto" or arg == "map" then d.height = 0 elseif n then d.height = Style.Clamp(n, 0.3, 0.95) end
  elseif sub == "aspect" and n then
    d.aspect = Style.Clamp(n, 0.5, 1.4)
  elseif sub == "scrollbar" and (arg == "on" or arg == "off") then
    d.scrollbar = (arg == "on")
  elseif sub == "size" and n then
    d.body = Style.Clamp(n, 14, 40)
  elseif sub == "hide" then
    local what, val = arg:match("^(%S+)%s*(%S*)$")
    if (what == "minimap" or what == "frames") and (val == "on" or val == "off") then
      if what == "minimap" then d.hideMinimap = (val == "on") else d.hideFrames = (val == "on") end
    else
      QB:Usage("/qb reader hide minimap|frames on|off")
    end
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb reader height <0.3-0.95>|auto | aspect <0.5-1.4> | size <px> | scrollbar on|off | hide minimap|frames on|off")
  end
  if R and R:IsShown() then
    mod:Layout()
    QB:Call("overlay", "ReaderOpen", true, { minimap = d.hideMinimap, frames = d.hideFrames })
  end
  Say(string.format("reader: height %s, aspect %.2f, text %d px | hides the small minimap: %s, the player and target frames: %s",
    (tonumber(d.height) or 0) > 0 and string.format("%.2f of the screen", d.height) or "as the map", d.aspect, d.body,
    d.hideMinimap and "yes" or "no", d.hideFrames and "yes" or "no"))
end, "reader height|aspect|size|hide: the quest reader's size and what it hides while open")

-- The legacy command set (everything that is not a registered subcommand).
QB.legacySlash = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", "")
  if not db then return end
  local size = msg:match("^size%s+(%d+)")
  local usevoice = msg:match("^usevoice%s+(%d+)")
  if size then
    mod.db.body = Style.Clamp(tonumber(size), 14, 40)
    if R and R:IsShown() then mod:Reflow() end
    Say("reader text " .. mod.db.body .. " px (14-40; the title and the rest scale with it)")
  elseif msg:match("^rate%s+-?%d+$") then
    db.rate = math.max(-10, math.min(10, tonumber(msg:match("(-?%d+)"))))
    Say("rate " .. db.rate .. " -- test with /qb say")
  elseif msg == "prosody" then
    db.prosody = not db.prosody
    Say("paragraph pauses " .. (db.prosody and "on" or "off"))
  elseif msg == "debug" then
    debugMode = not debugMode
    Say("debug " .. (debugMode and "on -- open the reader and move" or "off"))
  elseif msg == "voice" then
    mod:ToggleVoice()
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
    local ok, why = SpeakText("QuestBook voice test. If you hear this, the reader can read to you.")
    Say(ok and "speaking -- did you hear it?" or ("not speaking: " .. tostring(why)))
  else
    mod:Toggle()
  end
end
