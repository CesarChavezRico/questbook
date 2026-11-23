-- QuestBook Playlist -- the reader's queue, shown under the reader bar (4BI-38).
--
-- Cesar, 2026-11-23: "let's add a 'playlist' display that shows the queue"; of three ways, both: the game's own list plus
-- the bridge's real one after a Story click and on request.
--
-- The game cannot watch the bridge's queue: the strip goes one way, and reading anything back means loading one of the
-- 200 reply slots of the session. So the list has two sources:
--   ESTIMATED  the game's own count of what it asked for (a guide step, a quest, a hand-in, a place), each dropped when
--              its estimated time is up (about 14 characters a second, the bridge's rule too). Free. A Story click is one
--              line here: the game does not know which chapters the bridge found.
--   BRIDGE     the bridge's real list (WoWAI.Playlist: kinds, titles, lengths, how far in the one playing is). Taken
--              whenever a slot is read for any reason, and asked for (one slot: WoWAI.CheckPush) a few seconds after a
--              Story click and by the Sync link. From then on the game counts it down by itself again.
-- What the game asked for after the bridge wrote its list is kept behind the bridge's items.
-- Display only: a line cannot be clicked. UNVERIFIED (client and rig): all of it.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("playlist", {
  open = false,        -- the panel under the reader bar is shown
  rows = 6,            -- lines shown
  storySync = 8,       -- seconds after a Story click before the bridge's list is asked for (0 = never)
})

local CPS = 14                    -- characters a second, for a length from a text
local UNKNOWN = 30                -- seconds assumed for a reading whose length the game does not know
local items = {}                  -- { kind, title, secs, ref, elapsed, added (time()), known }, the one playing first
local paused = false
local source, syncedAt = "estimated", nil      -- "estimated" | "bridge"; time() of the bridge's list
local seenAt = 0                  -- the `at` of the last bridge list taken
local panel, lines, foot, footR, sync
local PAL = { normal = { 0.92, 0.89, 0.82 }, hot = { 0.98, 0.92, 0.76 }, faded = { 0.60, 0.57, 0.50 }, warn = { 0.85, 0.68, 0.35 } }

local function Now() return (type(time) == "function" and time()) or 0 end
local function Changed() QB:Fire("playlist_changed") end

function mod:Count() return #items end
function mod:Items() return items end
function mod:Source() return source, syncedAt end
function mod:IsPaused() return paused end

-- The game asked the bridge for a reading. chars = the text's length when the game has the text (nil = unknown).
function mod:Add(kind, title, chars, ref)
  local known = type(chars) == "number" and chars > 0
  items[#items + 1] = { kind = kind or "Voice", title = tostring(title or ""), ref = ref or "", elapsed = 0, added = Now(),
    secs = known and math.max(3, math.floor(chars / CPS + 0.5)) or UNKNOWN, known = known }
  Changed()
end

-- "Play" (the Talk link) cuts what is playing and plays this now; what waits stays.
function mod:PlayNow(kind, title, chars, ref)
  if items[1] then table.remove(items, 1) end
  local known = type(chars) == "number" and chars > 0
  table.insert(items, 1, { kind = kind or "Voice", title = tostring(title or ""), ref = ref or "", elapsed = 0, added = Now(),
    secs = known and math.max(3, math.floor(chars / CPS + 0.5)) or UNKNOWN, known = known })
  paused = false
  Changed()
end

function mod:Skip() if items[1] then table.remove(items, 1) end; paused = false; Changed() end
function mod:Clear() items = {}; paused = false; Changed() end
function mod:SetPaused(on)
  on = on and true or false
  if on == paused then return end
  paused = on
  if not on and items[1] then items[1].elapsed = 0 end          -- the bridge resumes a reading from its start
  Changed()
end

-- A second (or more) went by: the one playing moves on; when its time is up the next one plays.
function mod:Advance(dt)
  if paused or not items[1] then return end
  local changed = false
  while dt > 0 and items[1] do
    local it = items[1]
    local left = it.secs - it.elapsed
    if dt >= left then
      dt = dt - left
      table.remove(items, 1)
      changed = true
    else
      it.elapsed = it.elapsed + dt
      dt = 0
    end
  end
  if changed then Changed() elseif panel and panel:IsShown() then mod:Paint() end
end

-- Take the bridge's list (WoWAI.Playlist) when it is newer than the one we have. Returns true when it was taken.
function mod:Take()
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.Playlist) == "function") then return false end
  local ok, p = pcall(W.Playlist)
  if not ok or type(p) ~= "table" or type(p.items) ~= "table" or (tonumber(p.at) or 0) <= seenAt then return false end
  seenAt = p.at
  local age = tonumber(p.age) or 0
  local fresh, have = {}, {}
  for i, it in ipairs(p.items) do
    fresh[#fresh + 1] = { kind = it.kind ~= "" and it.kind or "Voice", title = it.title, ref = it.ref, secs = math.max(1, tonumber(it.secs) or UNKNOWN),
      elapsed = (i == 1) and (tonumber(it.elapsed) or 0) or 0, added = p.at, known = true }
    if it.ref ~= "" then have[it.ref] = true end
  end
  -- what the game asked for after the bridge wrote this list is still on its way: keep it behind
  for _, it in ipairs(items) do
    if it.added > p.at and not (it.ref ~= "" and have[it.ref]) and it.kind ~= "Story" then fresh[#fresh + 1] = it end
  end
  items, paused, source, syncedAt = fresh, p.paused and true or false, "bridge", p.at
  self.more = tonumber(p.more) or 0
  if not paused and age > 0 then self.more = self.more; mod:Advance(age) end        -- the list is `age` seconds old
  Changed()
  return true
end

-- Ask the bridge for its list now: one reply slot. Returns true when a list was taken.
function mod:Sync(quiet)
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.CheckPush) == "function" and type(W.Playlist) == "function") then
    if not quiet then QB:Say("queue: the relay addon on this machine is older than the queue display (update wow-relay and copy WoWAI into AddOns)") end
    return false
  end
  local ok, did, why = pcall(W.CheckPush)
  if not (ok and did) then
    if not quiet then QB:Say("queue: could not ask the bridge (" .. tostring(ok and why or did) .. ")") end
    return false
  end
  local took = self:Take()
  if not took and not quiet then QB:Say("queue: the bridge had nothing newer") end
  return took
end

-- A Story was asked for: one line now, and the bridge's real chapters a few seconds later.
function mod:StoryAsked(title)
  self:Add("Story", "earlier chapters of " .. tostring(title or "the quest"), nil, "story")
  local wait = tonumber(self.db.storySync) or 0
  if wait > 0 and C_Timer and C_Timer.After then
    C_Timer.After(wait, function() QB:Safe(mod, mod.Sync, mod, true) end)
  end
end

-- ---------------------------------------------------------------- the panel

local function Px(n) return Style.Px(n, panel) end
local function Clock(s)
  s = math.max(0, math.floor((tonumber(s) or 0) + 0.5))
  return string.format("%d:%02d", math.floor(s / 60), s % 60)
end
local function Ago(s)
  s = math.max(0, math.floor(tonumber(s) or 0))
  if s < 90 then return s .. " s ago" end
  return math.floor(s / 60 + 0.5) .. " min ago"
end

local function Build()
  if panel then return true end
  local bar = _G.QuestBookReaderBar
  if not bar then return false end
  panel = CreateFrame("Frame", "QuestBookPlaylist", bar)
  panel:SetFrameStrata("MEDIUM")
  panel.bg = panel:CreateTexture(nil, "BACKGROUND")
  panel.bg:SetAllPoints(panel)
  panel.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  panel.bg:SetVertexColor(0.07, 0.06, 0.05, 0.88)
  panel:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -Px(4))
  local function Fs(px)
    local f = panel:CreateFontString(nil, "OVERLAY")
    f:SetFont(Style.FRIZ, Px(px), "")
    f:SetJustifyH("LEFT")
    if f.SetWordWrap then f:SetWordWrap(false) end
    return f
  end
  lines = {}
  for i = 1, 12 do
    local l = { kind = Fs(13), title = Fs(15), time = Fs(13) }
    l.time:SetJustifyH("RIGHT")
    l.mark = panel:CreateTexture(nil, "ARTWORK")
    l.mark:SetTexture("Interface\\Buttons\\WHITE8x8")
    l.mark:SetVertexColor(PAL.warn[1], PAL.warn[2], PAL.warn[3], 1)
    lines[i] = l
  end
  foot, footR = Fs(13), Fs(13)
  footR:SetJustifyH("RIGHT")
  sync = Style.InkLink(panel, 13, function() QB:Safe(mod, mod.Sync, mod) end, PAL)
  sync:SetText("Sync")
  panel.lines, panel.foot, panel.footR, panel.sync = lines, foot, footR, sync
  panel:Hide()
  return true
end

function mod:Paint()
  if not Build() then return end
  if not (self.db.open and self.active) then panel:Hide() return end
  local W, ROW, PAD = 520, 24, 14
  local shown = math.min(#items, math.max(1, math.min(12, tonumber(self.db.rows) or 6)))
  for i, l in ipairs(lines) do
    local it = i <= shown and items[i] or nil
    for _, f in ipairs({ l.kind, l.title, l.time }) do f:SetShown(it ~= nil) end
    l.mark:SetShown(it ~= nil and i == 1)
    if it then
      local y = -Px(10 + (i - 1) * ROW)
      local c = (i == 1) and PAL.warn or PAL.normal
      local k = (i == 1) and PAL.warn or PAL.faded
      l.kind:ClearAllPoints(); l.kind:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PAD), y - Px(2)); l.kind:SetWidth(Px(64))
      l.kind:SetText(it.kind); l.kind:SetTextColor(k[1], k[2], k[3], 1)
      l.title:ClearAllPoints(); l.title:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PAD + 70), y); l.title:SetWidth(Px(W - PAD * 2 - 70 - 52))
      l.title:SetText(it.title); l.title:SetTextColor(c[1], c[2], c[3], 1)
      l.time:ClearAllPoints(); l.time:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -Px(PAD), y - Px(2)); l.time:SetWidth(Px(50))
      local left = (i == 1) and (it.secs - it.elapsed) or it.secs
      l.time:SetText((it.known and "" or "~") .. Clock(left)); l.time:SetTextColor(PAL.faded[1], PAL.faded[2], PAL.faded[3], 1)
      l.mark:ClearAllPoints(); l.mark:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, y + Px(3)); l.mark:SetSize(Px(3), Px(ROW - 4))
    end
  end
  local total = 0
  for i, it in ipairs(items) do total = total + ((i == 1) and (it.secs - it.elapsed) or it.secs) end
  local more = (#items - shown) + (self.more or 0)
  local left
  if #items == 0 then left = "Nothing waiting."
  else
    left = (more > 0 and ("+ " .. more .. " more \194\183 ") or "") .. "about " .. (total < 90 and (math.floor(total + 0.5) .. " s") or (math.floor(total / 60 + 0.5) .. " min")) .. " in all"
    if paused then left = left .. " \194\183 paused" end
  end
  local fy = -Px(10 + math.max(shown, 0) * ROW + 6)
  foot:ClearAllPoints(); foot:SetPoint("TOPLEFT", panel, "TOPLEFT", Px(PAD), fy); foot:SetText(left)
  foot:SetTextColor(PAL.faded[1], PAL.faded[2], PAL.faded[3], 1)
  sync:SetPx(13)
  sync:ClearAllPoints(); sync:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -Px(PAD), fy + Px(4))
  footR:ClearAllPoints(); footR:SetPoint("TOPRIGHT", sync, "TOPLEFT", -Px(10), -Px(4))
  footR:SetText(source == "bridge" and ("from the bridge, " .. Ago(Now() - (syncedAt or Now()))) or "estimated")
  footR:SetTextColor(PAL.faded[1], PAL.faded[2], PAL.faded[3], 1)
  panel:SetSize(Px(W), Px(10 + shown * ROW + 6 + 26))
  panel:Show()
end

function mod:SetOpen(on)
  self.db.open = on and true or false
  self:Paint()
  Changed()
end

-- ---------------------------------------------------------------- lifecycle

local ticker, lastTick
local function Tick()
  local now = (GetTime and GetTime()) or 0
  local dt = lastTick and (now - lastTick) or 1
  lastTick = now
  mod:Take()                       -- a slot read for any other reason brings a list too: free
  mod:Advance(dt)
end

function mod:OnEnable()
  if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, function() QB:Safe(mod, Tick) end) end
  self:Paint()
end
function mod:OnDisable() if panel then panel:Hide() end end

QB:On("playlist_changed", function() if mod.active then mod:Paint() end end, mod)

QB:RegisterSlash(mod, "queue", function(rest)
  local sub = (rest or ""):lower():match("^(%S*)")
  if sub == "open" or sub == "show" then mod:SetOpen(true)
  elseif sub == "close" or sub == "hide" then mod:SetOpen(false)
  elseif sub == "sync" then mod:Sync()
  elseif sub ~= "" and sub ~= "status" then QB:Usage("/qb queue | open | close | sync   (sync asks the bridge for its real list: one reply slot)") end
  local s = "queue: " .. #items .. " reading" .. (#items == 1 and "" or "s") .. (paused and ", paused" or "") .. ", "
    .. (source == "bridge" and ("from the bridge " .. Ago(Now() - (syncedAt or Now()))) or "estimated") .. "; the panel is " .. (mod.db.open and "open" or "closed")
  if items[1] then s = s .. " | now: " .. items[1].kind .. ": " .. items[1].title end
  QB:Say(s)
end, "queue: what the reader is playing and has waiting (open | close | sync)")
