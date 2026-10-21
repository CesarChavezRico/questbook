-- QuestBook Tracker -- a compact quest list that REPLACES Blizzard's objective tracker.
--
-- Cesar, 2026-10-15: "the quest list should be a replacement of the original quest list, with a
-- toggle to open the book" (v0.13: the "book" is now the quest reader). Blizzard's tracker ("All Objectives", ObjectiveTrackerFrame) is hidden
-- while this module is on and given back when it is switched off. In its place, under the corner
-- minimap: your quests, their objectives, the active quest marked, and a "Log" link that
-- opens the quest reader. Left click on a quest makes it the active one; right click opens it in the reader.
--
-- It is a GLANCE surface, so it follows the glance language of docs/STYLE.md: the faint dark panel
-- and cream text, no paper. Data comes from the same calls the reader uses.
--
-- What is lost with Blizzard's tracker while it is hidden (UNVERIFIED which of these really live in
-- that frame): world quest and bonus objective blocks, scenario / dungeon objectives, achievement and
-- profession trackers, and the quest auto-accept pop-ups. /qb disable tracker brings them all back.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("tracker", {
  mode = "all",         -- "all" (every quest in the log: the list is how you reach the reader) | "tracked" (the watch list)
  widthPx = 400,        -- the panel's width in physical pixels (v0.14; the older `width` in UI units is no longer used)
  size = 21,            -- quest title size in physical pixels; the objective lines and the header scale with it
  maxFrac = 0.62,       -- the panel never grows past this fraction of the screen height
  alpha = 0.55,         -- the panel's opacity
  objectives = 3,       -- objective lines shown under each quest
  level = true,         -- the quest's level at the right of its row, in [ ] (faded)
  hidden = false,       -- the whole list is put away (the key, `/qb tracker toggle`); the module still works
  collapsed = false,    -- only the title row is shown (click "QUESTS"); the links stay
  -- x, y: where the list sits, the offset of its top-right corner from the screen's top-right corner (y < 0 = down).
  -- Not in the defaults: first run seeds them from where the corner minimap sits, then they are the list's own.
})

local FRIZ = Style.FRIZ
local PADX, PADY, ROWGAP = 24, 20, 20      -- physical pixels
local INDENT = 18                -- the objectives sit this far in from the title (Cesar, 2026-10-20)
local COLW = 64                  -- the right-hand column of a row: the level in [ ], and the Play link under it
local rows = {}                  -- pooled row buttons
local panel, header, rule, more
local refreshQueued = false

local function Tone() return Style.Get("dark") end
local function Px(n) return Style.Px(n, panel) end

-- type ramp, from the title size: title, objective lines, header
local function Sizes(self)
  local t = Style.Clamp(tonumber(self.db.size) or 21, 14, 34)
  return t, math.floor(t * 0.81 + 0.5), math.floor(t * 0.76 + 0.5)
end

-- cream ink on the dark panel, for the header links
local function LinkPalette()
  local t = Tone()
  return { normal = t.chrome, hot = t.chromeHot, faded = t.chromeOff, warn = t.chromeWarn }
end

local function Fs(parent, px, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FRIZ, Px(px), "")           -- a font at birth: SetText on a fontless string is an error
  fs:SetJustifyH(justify or "LEFT")
  fs:SetShadowOffset(Px(1), -Px(1))
  fs:SetShadowColor(0, 0, 0, 0.85)
  return fs
end

-- ---------------------------------------------------------------- data

local function QuestList(self)
  local list = {}
  if not (C_QuestLog and C_QuestLog.GetInfo) then return list end
  if self.db.mode == "all" then
    -- the reader's own scan, which also finds quests under zones Blizzard's log has collapsed
    local ok, quests = QB:Call("questlog", "Scan")
    if ok and type(quests) == "table" then return quests end
    return list
  end
  if C_QuestLog.GetNumQuestWatches and C_QuestLog.GetQuestIDForQuestWatchIndex then
    local okN, n = pcall(C_QuestLog.GetNumQuestWatches)
    for i = 1, (okN and n) or 0 do
      local okQ, qid = pcall(C_QuestLog.GetQuestIDForQuestWatchIndex, i)
      if okQ and qid and C_QuestLog.GetLogIndexForQuestID then
        local idx = C_QuestLog.GetLogIndexForQuestID(qid)
        local okI, info = pcall(C_QuestLog.GetInfo, idx or 0)
        if okI and info and not info.isHeader then
          list[#list + 1] = { questID = qid, title = info.title, level = info.level }
        end
      end
    end
  end
  return list
end

-- The first `maxLines` objectives as { text, done }, whether all of them are done, and the overall progress of the
-- counted ones (kill 6, collect 3: numFulfilled / numRequired) as a fraction, or nil when nothing is counted.
local function Objectives(qid, maxLines)
  local out = {}
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out, false, nil end
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
  local allDone = true
  local have, need = 0, 0
  if ok and type(objs) == "table" then
    for _, o in ipairs(objs) do
      if o.text and o.text ~= "" then
        if #out < maxLines then out[#out + 1] = { text = o.text, done = o.finished and true or false } end
        if not o.finished then allDone = false end
        if type(o.numRequired) == "number" and o.numRequired > 0 then
          need = need + o.numRequired
          have = have + math.min(tonumber(o.numFulfilled) or 0, o.numRequired)
        end
      end
    end
  end
  return out, allDone and #out > 0, (need > 1) and (have / need) or nil
end

local function IsActive(qid)
  if C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID then
    local ok, id = pcall(C_SuperTrack.GetSuperTrackedQuestID)
    return ok and id == qid
  end
  return false
end

local function IsReady(qid)
  if C_QuestLog and C_QuestLog.ReadyForTurnIn then
    local ok, r = pcall(C_QuestLog.ReadyForTurnIn, qid)
    if ok then return r and true or false end
  end
  return false
end

-- ---------------------------------------------------------------- panel

local function Build(self)
  panel = CreateFrame("Frame", "QuestBookTracker", UIParent, "BackdropTemplate")
  panel:SetFrameStrata("LOW")
  panel:EnableMouse(false)             -- only the rows catch the mouse
  panel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
  Style.PixelPerfect(panel)
  panel:Hide()

  local t = Tone()
  -- the title is a link: a click collapses the list to this row, and again expands it (it is always there to click)
  header = Style.InkLink(panel, 16, function() QB:Call("tracker", "ToggleCollapsed") end,
    { normal = t.faded, hot = t.chromeHot, faded = t.chromeOff, warn = t.chromeWarn })
  header:SetText("QUESTS")
  panel.head = header
  -- a rule under the header that tapers to nothing at both ends (our own art, the same as the reader's)
  rule = Style.Hairline(panel, { t.hairline[1], t.hairline[2], t.hairline[3], 0.9 })

  local pal = LinkPalette()
  -- "Log" in the header: opens the quest reader (on the active quest)
  panel.book = Style.InkLink(panel, 16, function() QB:Call("questlog", "Toggle") end, pal)
  panel.book:SetText("Log")
  -- the voice link: "Stop" while a quest is being read (the page may be put away), else the walk-and-listen switch
  panel.voice = Style.InkLink(panel, 16, function()
    local ok, state = QB:Call("questlog", "VoiceState")
    if ok and state == "speaking" then QB:Call("questlog", "StopSpeech") else QB:Call("questlog", "ToggleVoice") end
  end, pal)

  more = Style.InkLink(panel, 16, function() QB:Call("questlog", "Toggle") end, pal)
  more:Hide()
end

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, panel)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  r.hover = r:CreateTexture(nil, "BACKGROUND")
  r.hover:SetAllPoints(r)
  r.hover:SetTexture("Interface\\Buttons\\WHITE8x8")
  r.hover:Hide()
  r.accent = r:CreateTexture(nil, "ARTWORK")       -- the active quest's mark: a thin bar at the left edge
  r.accent:SetTexture("Interface\\Buttons\\WHITE8x8")
  r.accent:Hide()
  r.title = Fs(r, 21)
  r.level = Fs(r, 21, "RIGHT")                     -- "[9]", at the right edge of the title line
  r.objs = Fs(r, 17)
  -- Play: read this quest aloud (Stop while it is the one being read). A button of its own, so it does not trigger the row.
  r.play = Style.InkLink(r, 17, function()
    QB:Safe(mod, function() QB:Call("questlog", "PlayQuest", r.questID) end)
  end, LinkPalette())
  r.play:SetText("Play")
  r.objs:SetSpacing(Px(3))
  r.track = r:CreateTexture(nil, "ARTWORK")        -- progress of the counted objectives, a thin bar
  r.track:SetTexture("Interface\\Buttons\\WHITE8x8")
  r.fill = r:CreateTexture(nil, "OVERLAY")
  r.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
  r:SetScript("OnEnter", function(self) self.hover:Show() end)
  r:SetScript("OnLeave", function(self) self.hover:Hide() end)
  rows[i] = r
  return r
end

-- The list has a position of its own (Cesar, 2026-10-17: "the list position should be independent from the map"):
-- the offset of its top-right corner from the screen's. The first time, it is seeded from where the corner minimap
-- sits (right under it, as it was), after that moving the minimap does not move the list, and the other way round.
-- `/qb tracker move` drags it, `/qb tracker pos <x> <y>` sets it, `/qb tracker reset` seeds it again.
local function Seed(self)
  local x, y = -24, -44
  local ov = QB.modules.overlay
  if ov and ov.db and ov.db.corner then
    local H = UIParent:GetHeight() or 0
    local size = math.max(48, Style.Clamp(tonumber(ov.db.cornerSize) or 0.16, 0.05, 0.5) * H)
    x = tonumber(ov.db.cornerX) or x
    y = (tonumber(ov.db.cornerY) or y) - size - 10
  end
  self.db.x, self.db.y = math.floor(x + 0.5), math.floor(y + 0.5)
end

local function Place(self)
  if not panel then return end
  if self.db.x == nil or self.db.y == nil then Seed(self) end
  panel:ClearAllPoints()
  panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", self.db.x, self.db.y)
  if self.mover then self.mover:Layout() end
end

-- "Play" on a row, "Stop" when that quest is the one being read aloud.
local function PaintPlay(r, speaking)
  if not (r.play and r.questID) then return end
  local on = speaking ~= nil and speaking == r.questID
  r.play:SetText(on and "Stop" or "Play")
  r.play:SetWarn(on)
end

-- Shift + left click on a quest: put its link into the chat box being typed in, the way Blizzard's own tracker does. The link
-- goes through the game's insert function, which Blizzard's boxes and the WoW AI chat's input (a hook in the relay addon)
-- both listen to; with no box open it does nothing but say so. Returns true when a box took it.
local function QuestLink(qid, title, level)
  local link
  if C_QuestLog and C_QuestLog.GetQuestLink then
    local ok, l = pcall(C_QuestLog.GetQuestLink, qid)
    if ok and type(l) == "string" and l ~= "" then link = l end
  end
  if not link and GetQuestLink then
    local ok, l = pcall(GetQuestLink, qid)
    if ok and type(l) == "string" and l ~= "" then link = l end
  end
  -- built by hand when the client gives none: the same shape as the game's own quest link
  return link or string.format("|cffffff00|Hquest:%d:%d|h[%s]|h|r", qid, tonumber(level) or 0, tostring(title or "?"))
end

local function ShiftClicked()
  if IsModifiedClick and IsModifiedClick("CHATLINK") then return true end
  return IsShiftKeyDown and IsShiftKeyDown() and true or false
end

local function InsertQuestLink(r)
  local link = QuestLink(r.questID, r.qtitle, r.qlevel)
  local took = false
  if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
    local ok, res = pcall(ChatFrameUtil.InsertLink, link)
    took = ok and res and true or false
  elseif ChatEdit_InsertLink then
    local ok, res = pcall(ChatEdit_InsertLink, link)
    took = ok and res and true or false
  end
  -- the WoW AI chat's own box is not one of Blizzard's: it takes the link through a hook, and is not told to the caller
  local ai = _G.WoWAIInput
  if ai and ai.HasFocus and ai:HasFocus() then took = true end
  if not took then QB:Say("shift-click puts the quest link into the chat box you are typing in; open one first (Enter, or click in the AI chat's box)") end
  return took
end
mod.InsertQuestLink = function(_, r) return InsertQuestLink(r) end

function mod:RefreshVoice()
  if not (panel and panel.voice) then return end
  local okS, speaking = QB:Call("questlog", "SpeakingQuestID")
  for _, r in ipairs(rows) do if r:IsShown() then PaintPlay(r, okS and speaking or nil) end end
  local ok, state = QB:Call("questlog", "VoiceState")
  if not ok then panel.voice:Hide() return end
  panel.voice:Show()
  panel.voice:SetText(state == "speaking" and "Stop" or (state == "on" and "Voice on" or "Voice off"))
  panel.voice:SetWarn(state == "speaking")
end

-- Lay the whole list out in physical pixels: header with its links and the tapering rule, then one block per quest
-- (title, objective lines, a thin bar when objectives are counted), the active quest marked by a bar at the left and a gold
-- title, a quest ready to hand in in green.
-- Put the whole list away or bring it back (a key binding and `/qb tracker toggle`); saved across sessions.
function mod:SetListShown(on)
  self.db.hidden = not on
  self:Refresh()
end
function mod:ToggleCollapsed()
  self.db.collapsed = not self.db.collapsed
  self:Refresh()
end
function mod:ToggleList()
  self:SetListShown(self.db.hidden and true or false)
  QB:Say("quest list " .. (self.db.hidden and "hidden (/qb tracker toggle or the key brings it back)" or "shown"))
end

function mod:Refresh()
  refreshQueued = false
  if not panel then return end
  if self.db.hidden then panel:Hide(); return end
  local t = Tone()
  local u = Style.PixelUnit(panel)
  local tp, op, hp = Sizes(self)
  local Wpx = Style.Clamp(tonumber(self.db.widthPx) or 400, 240, 700)
  local innerW = Wpx - 2 * PADX
  local maxHpx = UIParent:GetHeight() * Style.Clamp(tonumber(self.db.maxFrac) or 0.42, 0.05, 0.9) / u
  panel:SetWidth(Px(Wpx))
  panel:SetBackdropColor(t.cover[1], t.cover[2], t.cover[3], Style.Clamp(tonumber(self.db.alpha) or 0.55, 0, 1))

  -- header: label left, links right, the rule under them
  local list = QuestList(self)
  header:SetPx(hp)
  header:SetText((self.db.collapsed and "\226\128\186 " or "") .. (self.db.mode == "all" and "QUESTS" or "TRACKED") .. "  " .. #list)
  header:ClearAllPoints(); header:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PADX), -Px(PADY - 3))
  panel.book:SetPx(hp); panel.voice:SetPx(hp); more:SetPx(hp)
  self:RefreshVoice()
  panel.book:ClearAllPoints(); panel.book:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -Px(PADX), -Px(PADY - 3))
  panel.voice:ClearAllPoints(); panel.voice:SetPoint("TOPRIGHT", panel.book, "TOPLEFT", -Px(18), 0)
  local y = PADY + hp + 16
  rule:ClearAllPoints()
  rule:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PADX - 8), -Px(y))
  rule:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -Px(PADX - 8), -Px(y))
  rule:SetHeight(Px(8))
  y = y + 8 + 16
  rule:SetShown(not self.db.collapsed)

  if self.db.collapsed then
    -- only the title row: no quests, no rule; the links stay so there is always something to click
    for _, r in ipairs(rows) do r:Hide() end
    more:Hide()
    self.shown, self.total = 0, #list
    panel:SetHeight(Px(PADY + hp + 8 + PADY - 4))
    Place(self)
    panel:Show()
    return
  end

  local shown = 0
  local okS, speakingNow = QB:Call("questlog", "SpeakingQuestID")
  if not okS then speakingNow = nil end
  for _, r in ipairs(rows) do r:Hide() end
  for i, q in ipairs(list) do
    local r = Row(i)
    local objs, allDone, frac = Objectives(q.questID, tonumber(self.db.objectives) or 3)
    local ready = IsReady(q.questID) or allDone
    local active = IsActive(q.questID)
    r.questID, r.active, r.ready = q.questID, active and true or false, ready and true or false
    r.qtitle, r.qlevel = q.title, q.level
    local rowW = innerW + 20
    r:SetWidth(Px(rowW))
    r.title:SetFont(FRIZ, Px(tp), ""); r.objs:SetFont(FRIZ, Px(op), "")
    -- the title and the objectives stop short of the right-hand column; the objectives are indented from the title
    r.title:SetWidth(Px(innerW - COLW)); r.objs:SetWidth(Px(innerW - COLW - INDENT))
    r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", r, "TOPLEFT", Px(10), 0)
    local lvl = self.db.level and tonumber(q.level) or nil
    r.title:SetText(q.title or "?")
    r.level:SetFont(FRIZ, Px(tp), "")
    r.level:SetWidth(Px(COLW))
    r.level:ClearAllPoints(); r.level:SetPoint("TOPRIGHT", r, "TOPRIGHT", -Px(10), 0)
    r.level:SetText((lvl and lvl > 0) and ("[" .. lvl .. "]") or "")
    r.level:SetTextColor(t.faded[1], t.faded[2], t.faded[3], 1)
    r.level:Show()
    local lineH = math.floor(tp * 1.25 + 0.5)       -- about one title line: the Play link sits under the level
    r.play:SetPx(op)
    r.play:ClearAllPoints(); r.play:SetPoint("TOPRIGHT", r, "TOPRIGHT", -Px(10), -Px(lineH + 2))
    r.play:Show()
    PaintPlay(r, speakingNow)
    local tc = ready and t.done or (active and t.strong or t.ink)
    r.title:SetTextColor(tc[1], tc[2], tc[3], 1)
    local lines = {}
    if ready then
      lines[1] = "|cff" .. Style.Hex(t.done) .. "ready to turn in|r"
    else
      for _, o in ipairs(objs) do
        lines[#lines + 1] = "|cff" .. Style.Hex(o.done and t.done or t.faded) .. o.text .. "|r"
      end
    end
    r.objs:SetText(table.concat(lines, "\n"))
    local th = (r.title:GetStringHeight() or 0) / u
    local h = th
    if #lines > 0 then
      r.objs:ClearAllPoints(); r.objs:SetPoint("TOPLEFT", r, "TOPLEFT", Px(10 + INDENT), -Px(th + 4))
      h = th + 4 + (r.objs:GetStringHeight() or 0) / u
      r.objs:Show()
    else
      r.objs:Hide()
    end
    h = math.max(h, lineH + 2 + op + 8)             -- room for the level and the Play link in the right-hand column
    if frac then
      local by = h + 8
      r.track:ClearAllPoints(); r.track:SetPoint("TOPLEFT", r, "TOPLEFT", Px(10 + INDENT), -Px(by)); r.track:SetSize(Px(innerW - INDENT), Px(4))
      r.track:SetVertexColor(t.hairline[1], t.hairline[2], t.hairline[3], 0.30)
      local fc = ready and t.done or (active and t.strong or t.faded)
      r.fill:ClearAllPoints(); r.fill:SetPoint("TOPLEFT", r.track, "TOPLEFT", 0, 0)
      r.fill:SetSize(math.max(Px(1), Px(innerW - INDENT) * Style.Clamp(frac, 0, 1)), Px(4))
      r.fill:SetVertexColor(fc[1], fc[2], fc[3], active and 0.95 or 0.75)
      r.track:Show(); r.fill:Show()
      h = by + 4
    else
      r.track:Hide(); r.fill:Hide()
    end
    if y + h + ROWGAP > maxHpx - 24 and i > 1 then break end     -- out of room: the rest is "more"
    r:SetHeight(Px(h))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PADX - 10), -Px(y))
    r.hover:SetVertexColor(t.hover[1], t.hover[2], t.hover[3], t.hover[4])
    r.accent:ClearAllPoints(); r.accent:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0); r.accent:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    r.accent:SetWidth(Px(3))
    r.accent:SetVertexColor(t.strong[1], t.strong[2], t.strong[3], 0.95)
    r.accent:SetShown(active and true or false)
    -- left click: make it the active quest (the one the markers and the game point at); right click: open it;
    -- shift + left click: its link into the chat box being typed in
    r:SetScript("OnClick", function(_, button)
      QB:Safe(mod, function()
        if button ~= "RightButton" and ShiftClicked() then InsertQuestLink(r)
        elseif button == "RightButton" then QB:Call("questlog", "Open", r.questID)
        else QB:Call("questlog", "SetActive", r.questID) end
      end)
    end)
    r:Show()
    y = y + h + ROWGAP
    shown = i
  end
  if #list == 0 then
    -- an empty list still says so, and points to the log
    local r = Row(1)
    r.questID, r.active, r.ready = nil, false, false
    r:SetWidth(Px(innerW + 20))
    r.title:SetFont(FRIZ, Px(op), "")
    r.title:SetWidth(Px(innerW)); r.title:ClearAllPoints(); r.title:SetPoint("TOPLEFT", r, "TOPLEFT", Px(10), 0)
    r.title:SetText(self.db.mode == "all" and "No quests in your log." or "No tracked quests.")
    r.title:SetTextColor(t.faded[1], t.faded[2], t.faded[3], 1)
    r.objs:Hide(); r.track:Hide(); r.fill:Hide(); r.accent:Hide(); r.level:Hide(); r.play:Hide()
    local h = (r.title:GetStringHeight() or 0) / u
    r:SetHeight(Px(h))
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PADX - 10), -Px(y))
    r:SetScript("OnClick", nil)
    r:Show()
    y = y + h + ROWGAP
  end
  local hidden = #list - shown
  if hidden > 0 then
    more:SetText("+ " .. hidden .. " more in the log")
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PADX), -Px(y - 6))
    more:Show()
    y = y + hp + 14
  else
    more:Hide()
  end
  panel:SetHeight(Px(y - ROWGAP + PADY))
  self.shown, self.total = shown, #list
  Place(self)
  panel:Show()
end

local function Queue()
  if refreshQueued or not mod.active then return end
  refreshQueued = true
  if C_Timer and C_Timer.After then C_Timer.After(0.2, function() QB:Safe(mod, mod.Refresh, mod) end)
  else mod:Refresh() end
end

-- ---------------------------------------------------------------- Blizzard's tracker

-- Hidden while we replace it. Edit Mode or Blizzard code may show it again: re-hide, with a guard
-- so our own Hide cannot loop. Restored on disable. (UNVERIFIED: that Hide() on this managed frame
-- is honoured and does not make Blizzard's layout code error; /qb tracker status reports what the
-- frame is doing.)
function mod:HideBlizzard()
  local f = _G.ObjectiveTrackerFrame
  if not f then self.blizzard = "not found on this client"; return end
  if self.wasShown == nil then self.wasShown = f:IsShown() and true or false end
  if not self.hooked and type(hooksecurefunc) == "function" then
    self.hooked = true
    local function rehide()
      if mod.active and not mod.hiding and f:IsShown() then mod:HideBlizzard() end
    end
    pcall(hooksecurefunc, f, "Show", rehide)
    pcall(hooksecurefunc, f, "SetShown", rehide)
  end
  if f:IsShown() then
    self.hiding = true
    pcall(f.Hide, f)
    self.hiding = false
  end
  self.blizzard = f:IsShown() and "STILL SHOWN (could not hide)" or "hidden"
end

function mod:RestoreBlizzard()
  local f = _G.ObjectiveTrackerFrame
  if f and self.wasShown then
    self.hiding = true
    pcall(f.Show, f)
    self.hiding = false
  end
  self.wasShown = nil
  self.blizzard = "restored"
end

-- ---------------------------------------------------------------- lifecycle

function mod:OnInit()
  if type(CreateFrame) ~= "function" or not UIParent then self.unavailable = "no UI" end
  -- v0.13: the default mode is "all" (the list is how you reach the reader), but a saved "tracked" beats a changed
  -- default, so it is moved once. (`v` is not in the defaults: Core fills those before OnInit.)
  if (self.db.v or 0) < 1 then
    if self.db.mode == "tracked" then self.db.mode = "all" end
    self.db.v = 1
  end
  -- v0.14.1: the list may use more of the screen (0.42 showed 7 of 9 quests on a 1440 px screen); a saved default moves once
  if (self.db.v or 0) < 2 then
    if tonumber(self.db.maxFrac) == 0.42 then self.db.maxFrac = 0.62 end
    self.db.v = 2
  end
end

function mod:OnEnable()
  if not panel then Build(self) end
  self:HideBlizzard()
  self:Refresh()
end

-- the drag handle (created on first use)
function mod:Move(on)
  if on then
    if not panel then return end
    if self.db.hidden then self:SetListShown(true) end       -- a hidden list has nothing to drag
    if not self.mover then
      self.mover = Style.Mover({
        name = "QuestBookTrackerMover",
        size = function() return panel:GetWidth(), panel:GetHeight() end,
        get = function() return mod.db.x, mod.db.y end,
        set = function(x, y) mod.db.x, mod.db.y = x, y; Place(mod) end,
        lock = function() QB:Safe(mod, mod.Move, mod, false) end,
      })
    end
    self.mover.dragging = false
    self.mover:Layout()
    self.mover:Show()
    QB:Say("drag the handle to move the quest list; right-click it or /qb tracker lock when done")
  elseif self.mover then
    self.mover:Stop()
    QB:Say(string.format("quest list at %d, %d from the top-right corner", self.db.x or 0, self.db.y or 0))
  end
end

function mod:OnDisable()
  if self.mover then self.mover:Stop() end
  if panel then panel:Hide() end
  self:RestoreBlizzard()
end

mod.events.QUEST_LOG_UPDATE = Queue
mod.events.QUEST_WATCH_LIST_CHANGED = Queue
mod.events.SUPER_TRACKING_CHANGED = Queue
mod.events.QUEST_REMOVED = Queue
mod.events.QUEST_TURNED_IN = Queue
mod.events.PLAYER_ENTERING_WORLD = Queue
mod.events.DISPLAY_SIZE_CHANGED = Queue
mod.events.UI_SCALE_CHANGED = Queue
mod.events.EDIT_MODE_LAYOUTS_UPDATED = function(self) self:HideBlizzard(); Queue() end

QB:On("combat_end", function() if panel and mod.active then Place(mod) end end, mod)
QB:On("speech_state", function() if panel and mod.active then mod:RefreshVoice() end end, mod)

-- ---------------------------------------------------------------- slash

QB:RegisterSlash(mod, "tracker", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  if sub == "all" or sub == "tracked" then
    mod.db.mode = sub
  elseif sub == "width" and n then
    mod.db.widthPx = Style.Clamp(n, 240, 700)
  elseif sub == "size" and n then
    mod.db.size = Style.Clamp(n, 14, 34)
  elseif sub == "alpha" and n then
    mod.db.alpha = Style.Clamp(n, 0, 1)
  elseif sub == "lines" and n then
    mod.db.objectives = Style.Clamp(math.floor(n), 0, 8)
  elseif sub == "max" and n then
    mod.db.maxFrac = Style.Clamp(n > 1 and n / 100 or n, 0.05, 0.9)
  elseif sub == "toggle" then
    mod:ToggleList()
  elseif sub == "collapse" or sub == "expand" then
    mod.db.collapsed = (sub == "collapse")
  elseif sub == "show" or sub == "hide" then
    mod:SetListShown(sub == "show")
  elseif sub == "level" and (arg == "on" or arg == "off") then
    mod.db.level = (arg == "on")
  elseif sub == "move" then
    mod:Move(true)
  elseif sub == "lock" then
    mod:Move(false)
  elseif sub == "pos" then
    local px, py = arg:match("^(%-?%d+%.?%d*)%s+(%-?%d+%.?%d*)$")
    if px then mod.db.x, mod.db.y = tonumber(px), tonumber(py) else QB:Usage("/qb tracker pos <x> <y>   (from the top-right corner of the screen; y negative = down)") end
  elseif sub == "reset" then
    mod.db.x, mod.db.y = nil, nil            -- Place seeds it again, under the corner minimap
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb tracker toggle|show|hide | collapse|expand (or click the title) | level on|off | all|tracked | width <px> | size <px> | alpha <0-1> | lines <n> | max <fraction> | move | lock | pos <x> <y> | reset   (/qb disable tracker gives Blizzard's tracker back)")
  end
  mod:Refresh()
  QB:Say(string.format("tracker: %s, %d of %d quests shown, width %d px, text %d px, alpha %.2f, %d objective lines, at %d,%d | list %s%s, levels %s | Blizzard's tracker: %s",
    mod.db.mode, mod.shown or 0, mod.total or 0, mod.db.widthPx, mod.db.size, mod.db.alpha, mod.db.objectives, mod.db.x or 0, mod.db.y or 0,
    mod.db.hidden and "hidden" or "shown", mod.db.collapsed and " (collapsed)" or "", mod.db.level and "on" or "off", tostring(mod.blizzard)))
end, "tracker toggle|show|hide|collapse|expand|level|all|tracked|width|size|alpha|lines|max|move|lock|pos|reset: the compact quest list that replaces Blizzard's tracker")
