-- QuestBook Panel -- QuestBook's settings, inside EllesmereUI's options panel (4BI-38).
--
-- Cesar, 2026-11-09: "build the questbook settings into the panel". EllesmereUI lets another addon have a section of its own in its
-- options panel: EllesmereUI.RegisterPlugin(id, spec) (EllesmereUI/PLUGINS_API.md, PLUGIN_API_VERSION 5). Ours is "QuestBook", one sidebar
-- row with five tabs: Voice, Reader, Experience bar, Top right, Modules. Open it from the panel's sidebar, or `/qb settings`.
--
-- Every control does what the matching slash command does: the setters run the command line quietly (QB:Run), so the clamping and the live
-- apply are the ones the commands already have and the tests already cover; the getters read each module's saved value. The widgets
-- are the factory the guide describes ("the same widget factory EUI's own pages use"): SectionHeader and Toggle are documented in it;
-- Slider, Dropdown and Button are what its own pages use, and their signatures were read from its source, so every call here is
-- guarded: a widget that is missing or throws is skipped, never an error for the panel.
--
-- The guide's rules, kept: we only add a section of our own; labels are plain text; the page builder has no side effects (it also runs
-- once in a hidden pass for Ellesmere's search, with a stub factory that creates no frames); callbacks run protected.
-- UNVERIFIED (client only): how the pages look and behave in the real panel; the Slider / Dropdown / Button signatures on the version
-- you run (read from the repository's current source, not from the guide).

local _, QB = ...

local mod = QB:NewModule("panel", {})

local ID = "QuestBook"
local registered = false

local function Present()
  return type(_G.EllesmereUI) == "table" and type(_G.EllesmereUI.RegisterPlugin) == "function"
end

local function Mod(name) return QB.modules[name] end
local function Db(name) local m = Mod(name); return m and m.db or {} end
local function Run(line) QB:Run(line) end
local function OnOff(v) return v and "on" or "off" end

-- ---------------------------------------------------------------- the rows
--
-- A row is { "toggle" | "slider" | "dropdown" | "button" | "header" | "note", label, ... }. Built top-down by Build below.

local function Toggle(label, tip, get, set) return { kind = "toggle", label = label, tip = tip, get = get, set = set } end
local function Slider(label, tip, min, max, step, get, set) return { kind = "slider", label = label, tip = tip, min = min, max = max, step = step, get = get, set = set } end
local function Dropdown(label, tip, values, order, get, set) return { kind = "dropdown", label = label, tip = tip, values = values, order = order, get = get, set = set } end
local function Button(label, fn) return { kind = "button", label = label, fn = fn } end
local function Header(label) return { kind = "header", label = label } end

local function OffNote(name, what)
  local m = Mod(name)
  if m and m.active then return "" end
  return " (" .. what .. " is off: see Modules)"
end

local PAGES = {}

PAGES["Voice"] = function()
  local q = function() return Db("questlog") end
  return {
    Header("VOICE" .. OffNote("questlog", "the reader")),
    Toggle("Read the quest when you start walking", "The first step you take with the reader open reads the quest and puts the page away.",
      function() return QB.db and QB.db.voice and true or false end,
      function(v) if (QB.db and QB.db.voice and true or false) ~= v then QB:Call("questlog", "ToggleVoice") end end),
    Dropdown("Voice", "The game's own voice, or the ElevenLabs voice through the relay on your rig (falls back to the game's voice if the relay is not there).",
      { game = "The game's voice", relay = "ElevenLabs (relay)" }, { "game", "relay" },
      function() return q().engine or "game" end,
      function(v) Run("voice engine " .. v) end),
    Toggle("Prepare the audio when a quest is accepted", "With the relay voice, the audio is made when you accept the quest, so it is ready when you press Play.",
      function() return q().prefetch and true or false end,
      function(v) Run("voice prefetch " .. OnOff(v)) end),
    Slider("Speed of the game's voice", "Only for the game's own voice, -10 (slow) to 10 (fast).", -10, 10, 1,
      function() return tonumber(QB.db and QB.db.rate) or 0 end,
      function(v) Run("rate " .. math.floor(v + 0.5)) end),
    Header("TRY IT"),
    Button("Test the relay voice", function() Run("voice test") end),
    Button("Say why the relay voice is or is not used", function() QB:HandleSlash("voice status") end),   -- (prints to the chat on purpose)
  }
end

PAGES["Reader"] = function()
  local q = function() return Db("questlog") end
  return {
    Header("THE QUEST READER" .. OffNote("questlog", "the reader")),
    Slider("Text size", "Body text, in screen pixels. The title and the rest scale with it.", 14, 40, 1,
      function() return tonumber(q().body) or 22 end,
      function(v) Run("reader size " .. math.floor(v + 0.5)) end),
    Toggle("Same height as the map", "On: the page is as tall as the big map. Off: it has the height set below.",
      function() return (tonumber(q().height) or 0) <= 0 end,
      function(v)
        if v then Run("reader height auto") return end
        local h = tonumber(q().height) or 0
        if h <= 0 then h = 0.8 end                       -- it was on auto: start from a tall page, the slider below tunes it
        Run("reader height " .. string.format("%.2f", h))
      end),
    Slider("Page height", "Fraction of the screen height, when it is not the map's.", 0.3, 0.95, 0.01,
      function() local h = tonumber(q().height) or 0; return h > 0 and h or 0.8 end,
      function(v) Run("reader height " .. string.format("%.2f", v)) end),
    Slider("Page width (relative to its height)", "0.5 is narrow, 1.4 is wide.", 0.5, 1.4, 0.01,
      function() return tonumber(q().aspect) or 0.84 end,
      function(v) Run("reader aspect " .. string.format("%.2f", v)) end),
    Toggle("Scroll bar", "A thin bar beside the text. The mouse wheel scrolls either way.",
      function() return q().scrollbar and true or false end,
      function(v) Run("reader scrollbar " .. OnOff(v)) end),
    Header("WHAT THE READER HIDES WHILE IT IS OPEN"),
    Toggle("The small minimap", nil, function() return q().hideMinimap and true or false end, function(v) Run("reader hide minimap " .. OnOff(v)) end),
    Toggle("Your portrait and the target frame", nil, function() return q().hideFrames and true or false end, function(v) Run("reader hide frames " .. OnOff(v)) end),
    Toggle("Your buffs and debuffs", nil, function() return q().hideAuras and true or false end, function(v) Run("reader hide auras " .. OnOff(v)) end),
    Button("Open the reader", function() QB:Call("questlog", "Open") end),
  }
end

PAGES["Experience bar"] = function()
  local x = function() return Db("xp") end
  return {
    Header("EXPERIENCE BAR" .. OffNote("xp", "the experience bar")),
    Toggle("Show the number above the bar", '"Lv 8  44%  [14%]": the level, the XP, and the rested part in brackets.',
      function() return x().text and true or false end, function(v) Run("xp text " .. OnOff(v)) end),
    Toggle("Show the rested part on the bar", nil, function() return x().rested and true or false end, function(v) Run("xp rested " .. OnOff(v)) end),
    Toggle("Hide Blizzard's own bottom bar", "While this bar is up. At the maximum level it comes back (it also carries reputation and honor).",
      function() return x().blizzard and true or false end, function(v) Run("xp blizzard " .. OnOff(v)) end),
    Slider("Width", "Screen pixels.", 120, 900, 10, function() return tonumber(x().widthPx) or 360 end, function(v) Run("xp width " .. math.floor(v + 0.5)) end),
    Slider("Height", "Screen pixels.", 1, 12, 1, function() return tonumber(x().heightPx) or 3 end, function(v) Run("xp height " .. math.floor(v + 0.5)) end),
    Slider("Gap under the strip", "Screen pixels.", 0, 20, 1, function() return tonumber(x().gapPx) or 3 end, function(v) Run("xp gap " .. math.floor(v + 0.5)) end),
    Slider("Number size", "Screen pixels.", 10, 30, 1, function() return tonumber(x().textPx) or 15 end, function(v) Run("xp textsize " .. math.floor(v + 0.5)) end),
  }
end

PAGES["Top right"] = function()
  local s = function() return Db("strip") end
  local e = function() return Db("elle") end
  return {
    Header("THE STRIP" .. OffNote("strip", "the strip")),
    Toggle("Show the coordinates", nil, function() return s().showCoords and true or false end, function(v) Run("strip coords " .. OnOff(v)) end),
    Toggle("Show the server time", "The realm clock, after the coordinates, in the 12 or 24 hours of the game's own clock setting. The tooltip also gives your local time.",
      function() return s().showClock and true or false end, function(v) Run("strip clock " .. OnOff(v)) end),
    Toggle("Show the mail icon", nil, function() return s().showMail and true or false end, function(v) Run("strip mail " .. OnOff(v)) end),
    Header("THE PLAY BUTTON ON ELLESMEREUI'S QUEST TRACKER" .. OffNote("elle", "the button")),
    Slider("Room reserved beside each title", "Screen pixels. Applies after a /reload.", 16, 64, 2,
      function() return tonumber(e().width) or 34 end, function(v) Run("elle width " .. math.floor(v + 0.5)) end),
  }
end

-- the modules a player may switch: name -> label and what it is
local MODULES = {
  { "questlog", "Quest reader and voice", "The reader page, the Play / Stop link, the relay voice. Replaces Blizzard's quest log." },
  { "giver", "Quest-giver capture", "Remembers who gave each quest, for the voice casting and the reader's meta line." },
  { "elle", "Play button on EllesmereUI's tracker", "Needs EllesmereUI's Custom Quest Tracker." },
  { "xp", "Experience bar", nil },
  { "strip", "Top-right text strip", "Zone, coordinates, mail. The Menu handle and the experience bar hang on it." },
  { "drawers", "Menu drawer", "Blizzard's micro menu and bag bar in one panel." },
  { "tracker", "QuestBook's own quest list", "Replaces Blizzard's objective tracker. Turn it off to use EllesmereUI's." },
  { "overlay", "Map overlay", "The big translucent minimap and overland map beside your character, and the small corner minimap." },
  { "camera", "Camera shift for the overlay and the reader", "Slides the camera sideways and back while the overlay or the reader is open." },
  { "markers", "Minimap quest markers", "Needs the map overlay." },
  { "plates", "Quest icons on nameplates", nil },
}

PAGES["Modules"] = function()
  local rows = { Header("TURN PARTS OF QUESTBOOK ON OR OFF") }
  for _, m in ipairs(MODULES) do
    local name = m[1]
    if QB.modules[name] then
      rows[#rows + 1] = Toggle(m[2], m[3],
        function() local mm = QB.modules[name]; return mm and mm.active and true or false end,
        function(v) QB:SetEnabled(name, v) end)
    end
  end
  rows[#rows + 1] = Header("AFTER CHANGING THE MAP OVERLAY, THE LIST OR THE CAMERA")
  rows[#rows + 1] = Button("Reload the UI", function() if type(_G.ReloadUI) == "function" then _G.ReloadUI() end end)
  return rows
end

local TABS = { "Voice", "Reader", "Experience bar", "Top right", "Modules" }

-- ---------------------------------------------------------------- building a page

local ROW_H = 50

-- Build one page into `parent` starting at yOffset (negative, top-down); returns the content height. Every widget call is guarded.
local function BuildPage(pageName, parent, yOffset)
  local rows = PAGES[pageName] and PAGES[pageName]()
  local W = _G.EllesmereUI and _G.EllesmereUI.Widgets
  if not (rows and W) then return 0 end
  local y = yOffset
  local function call(fnName, ...)
    local fn = W[fnName]
    if type(fn) ~= "function" then return nil, ROW_H end
    local ok, frame, h = pcall(fn, W, ...)
    if not ok then QB:ReportError("panel", frame); return nil, ROW_H end
    return frame, tonumber(h) or ROW_H
  end
  for _, r in ipairs(rows) do
    local h
    if r.kind == "header" then
      _, h = call("SectionHeader", parent, r.label, y)
    elseif r.kind == "toggle" then
      _, h = call("Toggle", parent, r.label, y, function() local ok, v = pcall(r.get); return ok and v and true or false end,
        function(v) QB:Safe(mod, r.set, v and true or false) end, r.tip)
    elseif r.kind == "slider" then
      _, h = call("Slider", parent, r.label, y, r.min, r.max, r.step, function() local ok, v = pcall(r.get); return ok and tonumber(v) or r.min end,
        function(v) QB:Safe(mod, r.set, tonumber(v) or r.min) end, r.tip)
    elseif r.kind == "dropdown" then
      _, h = call("Dropdown", parent, r.label, y, r.values, function() local ok, v = pcall(r.get); return ok and v or r.order[1] end,
        function(v) QB:Safe(mod, r.set, v) end, r.order, r.tip)
    elseif r.kind == "button" then
      _, h = call("Button", parent, r.label, y, function() QB:Safe(mod, r.fn) end)
    end
    y = y - (h or ROW_H)
  end
  return math.abs(y)
end
mod.BuildPage = function(_, pageName, parent, yOffset) return BuildPage(pageName, parent, yOffset) end

-- ---------------------------------------------------------------- registering

function mod:Register()
  if registered or not Present() then return registered end
  local spec = {
    label = "QuestBook",
    modules = { {
      key = "QuestBook",
      title = "QuestBook",
      description = "The quest reader and its voice, the experience bar, the Menu drawer and the parts of QuestBook you can switch on or off.",
      pages = TABS,
      buildPage = function(pageName, parent, yOffset) return BuildPage(pageName, parent, yOffset) end,
    } },
  }
  local ok, res = pcall(_G.EllesmereUI.RegisterPlugin, ID, spec)
  registered = ok and res and true or false
  self.registerNote = registered and "registered" or (ok and "refused (see the error handler)" or ("error: " .. tostring(res)))
  return registered
end

function mod:OnInit()
  if type(CreateFrame) ~= "function" then self.unavailable = "no UI" end
end

function mod:OnEnable()
  if not self:Register() then self.waiting = true end
end

mod.events.PLAYER_ENTERING_WORLD = function(self)
  if self.waiting and self:Register() then self.waiting = false end
end

-- Open it: `/qb settings`
function mod:Open()
  if not Present() or type(_G.EllesmereUI.OpenPlugin) ~= "function" then
    QB:Say("settings: EllesmereUI's options panel is not available here (it needs EllesmereUI on WoW Forever)")
    return false
  end
  if not registered then self:Register() end
  if QB:InCombat() then QB:Say("settings: the panel does not open in combat") return false end
  local ok, res = pcall(_G.EllesmereUI.OpenPlugin, ID)
  if not (ok and res) then QB:Say("settings: could not open the QuestBook section (" .. tostring(ok and "unknown plugin" or res) .. ")") return false end
  return true
end

QB:RegisterSlash(mod, "settings", function()
  mod:Open()
  QB:Say(string.format("settings: EllesmereUI %s | section %s", type(_G.EllesmereUI) == "table" and "loaded" or "NOT loaded", mod.registerNote or "not registered"))
end, "settings: open QuestBook's section in EllesmereUI's options panel")
