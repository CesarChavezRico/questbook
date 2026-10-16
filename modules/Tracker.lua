-- QuestBook Tracker -- a compact quest list that REPLACES Blizzard's objective tracker.
--
-- Cesar, 2026-10-15: "the quest list should be a replacement of the original quest list, with a
-- toggle to open the book". Blizzard's tracker ("All Objectives", ObjectiveTrackerFrame) is hidden
-- while this module is on and given back when it is switched off. In its place, under the corner
-- minimap: your tracked quests, their objectives, the active quest marked, and a "Book" link that
-- opens the quest book. Clicking a quest opens the book on it.
--
-- It is a GLANCE surface, so it follows the glance language of docs/STYLE.md: the faint dark panel
-- and cream text, no paper. Data comes from the same calls the book uses.
--
-- What is lost with Blizzard's tracker while it is hidden (UNVERIFIED which of these really live in
-- that frame): world quest and bonus objective blocks, scenario / dungeon objectives, achievement and
-- profession trackers, and the quest auto-accept pop-ups. /qb disable tracker brings them all back.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("tracker", {
  mode = "tracked",     -- "tracked" (the watch list, like Blizzard's) | "all" (every quest in the log)
  width = 260,
  maxFrac = 0.42,       -- the panel never grows past this fraction of the screen height
  alpha = 0.55,         -- the panel's opacity
  objectives = 3,       -- objective lines shown under each quest
})

local FRIZ = Style.FRIZ
local PAD, GAP = 8, 8
local rows = {}                  -- pooled row buttons
local panel, header, more
local refreshQueued = false

local function Tone() return Style.Get("dark") end

local function NewText(parent, size)
  local fs = parent:CreateFontString(nil, "OVERLAY")
  fs:SetFont(FRIZ, size, "")             -- a font at birth: SetText on a fontless string is an error
  fs:SetJustifyH("LEFT")
  fs:SetShadowOffset(1, -1)
  fs:SetShadowColor(0, 0, 0, 0.85)
  return fs
end

-- ---------------------------------------------------------------- data

local function QuestList(self)
  local list = {}
  if not (C_QuestLog and C_QuestLog.GetInfo) then return list end
  if self.db.mode == "all" then
    -- the book's own scan, which also finds quests under zones Blizzard's log has collapsed
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

local function Objectives(qid, maxLines)
  local out = {}
  if not (C_QuestLog and C_QuestLog.GetQuestObjectives) then return out, false end
  local ok, objs = pcall(C_QuestLog.GetQuestObjectives, qid)
  local allDone = true
  if ok and type(objs) == "table" then
    for _, o in ipairs(objs) do
      if o.text and o.text ~= "" then
        if #out < maxLines then out[#out + 1] = { text = o.text, done = o.finished and true or false } end
        if not o.finished then allDone = false end
      end
    end
  end
  return out, allDone and #out > 0
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
  panel:Hide()

  header = NewText(panel, 11)
  header:SetPoint("TOPLEFT", PAD, -PAD)
  header:SetText("QUESTS")

  -- "Book" in the header: opens the quest book
  panel.book = Style.Link(panel, function() QB:Call("questlog", "Toggle") end, Tone)
  panel.book:SetText("Book")
  panel.book:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -PAD + 3)

  more = Style.Link(panel, function() QB:Call("questlog", "Toggle") end, Tone)
  more:Hide()
end

local function Row(i)
  local r = rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, panel)
  r.title = NewText(r, 12)
  r.title:SetPoint("TOPLEFT", 0, 0)
  r.objs = NewText(r, 11)
  r.objs:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
  r.hover = r:CreateTexture(nil, "BACKGROUND")
  r.hover:SetAllPoints(r)
  r.hover:Hide()
  r:SetScript("OnEnter", function(self) self.hover:Show() end)
  r:SetScript("OnLeave", function(self) self.hover:Hide() end)
  rows[i] = r
  return r
end

-- Anchor under the corner minimap (when it is up), else in the corner under the text strip.
local function Place(self)
  if not panel then return end
  panel:ClearAllPoints()
  local ov = QB.modules.overlay
  local corner = ov and ov.active and ov.cornerPanel
  if corner and corner:IsShown() then
    panel:SetPoint("TOPRIGHT", corner, "BOTTOMRIGHT", 0, -10)
  else
    panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -24, -44)
  end
end

function mod:Refresh()
  refreshQueued = false
  if not panel then return end
  local t = Tone()
  local W = Style.Clamp(tonumber(self.db.width) or 260, 160, 520)
  local innerW = W - 2 * PAD
  local maxH = UIParent:GetHeight() * Style.Clamp(tonumber(self.db.maxFrac) or 0.42, 0.05, 0.9)
  panel:SetWidth(W)
  panel:SetBackdropColor(t.cover[1], t.cover[2], t.cover[3], Style.Clamp(tonumber(self.db.alpha) or 0.55, 0, 1))
  Style.SetInk(header, t.faded)
  header:SetText(self.db.mode == "all" and "ALL QUESTS" or "TRACKED QUESTS")

  local list = QuestList(self)
  local y = PAD + 20
  local shown = 0
  for _, r in ipairs(rows) do r:Hide() end
  for i, q in ipairs(list) do
    local r = Row(i)
    local objs, allDone = Objectives(q.questID, tonumber(self.db.objectives) or 3)
    local ready = IsReady(q.questID) or allDone
    local active = IsActive(q.questID)
    r.questID = q.questID
    r:SetWidth(innerW)
    r.title:SetWidth(innerW)
    r.objs:SetWidth(innerW - 10)
    r.objs:ClearAllPoints()
    r.objs:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 10, -2)
    r.title:SetText((active and "> " or "") .. (q.title or "?") .. (ready and "  (ready)" or ""))
    Style.SetInk(r.title, ready and t.done or (active and t.chromeHot or t.ink))
    local lines = {}
    for _, o in ipairs(objs) do
      lines[#lines + 1] = "|cff" .. Style.Hex(o.done and t.done or t.faded) .. "- " .. o.text .. "|r"
    end
    r.objs:SetText(table.concat(lines, "\n"))
    local h = r.title:GetStringHeight() + (#lines > 0 and (r.objs:GetStringHeight() + 2) or 0)
    if y + h + GAP > maxH - 16 and i > 1 then break end     -- out of room: the rest is "more"
    r:SetHeight(h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
    r.hover:SetColorTexture(t.hover[1], t.hover[2], t.hover[3], t.hover[4])
    r:SetScript("OnClick", function(_, button)
      QB:Safe(mod, function() QB:Call("questlog", "OpenBook", r.questID) end)
    end)
    r:Show()
    y = y + h + GAP
    shown = i
  end
  if #list == 0 then
    -- an empty list still says so, and points to the book
    local r = Row(1)
    r.questID = nil
    r:SetWidth(innerW); r.title:SetWidth(innerW)
    r.title:SetText("No tracked quests.")
    Style.SetInk(r.title, t.faded)
    r.objs:SetText("")
    r:SetHeight(r.title:GetStringHeight())
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
    r:SetScript("OnClick", nil)
    r:Show()
    y = y + r:GetHeight() + GAP
  end
  local hidden = #list - shown
  if hidden > 0 then
    more:SetText("+ " .. hidden .. " more in the book")
    more:ClearAllPoints()
    more:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -y)
    more:Show()
    y = y + 20
  else
    more:Hide()
  end
  panel:SetHeight(y + PAD - GAP)
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
end

function mod:OnEnable()
  if not panel then Build(self) end
  self:HideBlizzard()
  self:Refresh()
end

function mod:OnDisable()
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

-- the minimap moves between the corner and the big panel: follow it
QB:On("overlay_state", function() if panel and mod.active then Place(mod) end end, mod)
QB:On("overlay_host", function() if panel and mod.active then Place(mod) end end, mod)
QB:On("combat_end", function() if panel and mod.active then Place(mod) end end, mod)

-- ---------------------------------------------------------------- slash

QB:RegisterSlash(mod, "tracker", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  if sub == "all" or sub == "tracked" then
    mod.db.mode = sub
  elseif sub == "width" and n then
    mod.db.width = Style.Clamp(n, 160, 520)
  elseif sub == "alpha" and n then
    mod.db.alpha = Style.Clamp(n, 0, 1)
  elseif sub == "lines" and n then
    mod.db.objectives = Style.Clamp(math.floor(n), 0, 8)
  elseif sub == "max" and n then
    mod.db.maxFrac = Style.Clamp(n > 1 and n / 100 or n, 0.05, 0.9)
  elseif sub ~= "" and sub ~= "status" then
    QB:Say("/qb tracker all|tracked | width <n> | alpha <0-1> | lines <n> | max <fraction>   (/qb disable tracker gives Blizzard's tracker back)")
  end
  mod:Refresh()
  QB:Say(string.format("tracker: %s, %d of %d quests shown, width %d, alpha %.2f, %d objective lines | Blizzard's tracker: %s",
    mod.db.mode, mod.shown or 0, mod.total or 0, mod.db.width, mod.db.alpha, mod.db.objectives, tostring(mod.blizzard)))
end, "tracker all|tracked|width|alpha|lines|max: the compact quest list that replaces Blizzard's tracker")
