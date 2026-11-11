-- QuestBook's section in EllesmereUI's options panel (4BI-38). EllesmereUI is a stand-in that follows its plugin guide (RegisterPlugin
-- spec checks, OpenPlugin, IsSearchPrebuild) and the widget factory's signatures as read from its source: SectionHeader(parent, text, y,
-- tip), Toggle(parent, text, y, get, set, tip), Slider(parent, text, y, min, max, step, get, set, tip), Dropdown(parent, text, y, values,
-- get, set, order, tip), Button(parent, text, y, onClick); each returns frame, height. Stubbed API: our logic and the contract, not looks.
local plugins, opened = {}, {}
local function stand_in()
  local rows = {}                                    -- every row built, with its getter / setter
  local W = {}
  local function add(kind, text, get, set, extra) rows[#rows + 1] = { kind = kind, text = text, get = get, set = set, extra = extra }; return CreateFrame("Frame"), 50 end
  function W:SectionHeader(parent, text, y, tip) rows[#rows + 1] = { kind = "header", text = text }; return CreateFrame("Frame"), 40 end
  function W:Toggle(parent, text, y, get, set, tip) return add("toggle", text, get, set, { tip = tip }) end
  function W:Slider(parent, text, y, min, max, step, get, set, tip) return add("slider", text, get, set, { min = min, max = max, step = step }) end
  function W:Dropdown(parent, text, y, values, get, set, order, tip) return add("dropdown", text, get, set, { values = values, order = order }) end
  function W:Button(parent, text, y, onClick) return add("button", text, nil, onClick) end
  EllesmereUI = {
    PLUGIN_API_VERSION = 5, Widgets = W, _rows = rows,
    RegisterPlugin = function(id, spec)
      if type(id) ~= "string" or not id:match("^%a[%w_%-]*$") or #id > 40 then return false end
      if type(spec) ~= "table" or type(spec.label) ~= "string" or #spec.label > 32 or spec.label:match("^E[Uu][Ii]") or spec.label:match("^Ellesmere") then return false end
      if type(spec.modules) ~= "table" or #spec.modules < 1 or #spec.modules > 20 then return false end
      for _, m in ipairs(spec.modules) do
        if type(m.key) ~= "string" or type(m.title) ~= "string" or #m.title > 48 or type(m.buildPage) ~= "function" then return false end
        if type(m.pages) ~= "table" or #m.pages < 1 or #m.pages > 20 then return false end
        for _, p in ipairs(m.pages) do if p:find("|", 1, true) then return false end end
      end
      if plugins[id] then return false end
      plugins[id] = spec
      return true
    end,
    OpenPlugin = function(id) if not plugins[id] then return false end opened[#opened + 1] = id; return true end,
    IsSearchPrebuild = function() return false end,
  }
  return rows
end
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function build(page) local rows = EllesmereUI._rows; for i = #rows, 1, -1 do rows[i] = nil end
  local h = plugins.QuestBook.modules[1].buildPage(page, CreateFrame("Frame"), -10); return h, rows end
local function row(rows, text) for _, r in ipairs(rows) do if r.text == text then return r end end error("no row: " .. text) end

-- 1. EllesmereUI is not there: nothing breaks, /qb settings says so
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local P = QB.modules.panel
assert(P and P.active and not P.unavailable and P.waiting, "the module is on and waiting")
slash("settings"); local said = table.concat(__take(), "\n")
assert(said:find("not available", 1, true), "says the panel is missing: " .. said)

-- 2. it loads later: registered once, as one sidebar row with five tabs
stand_in()
__fire("PLAYER_ENTERING_WORLD")
local spec = plugins.QuestBook
assert(spec and spec.label == "QuestBook" and #spec.modules == 1, "one section, one sidebar row")
assert(table.concat(spec.modules[1].pages, ",") == "Voice,Reader,Experience bar,Top right,Modules", "five tabs")
__fire("PLAYER_ENTERING_WORLD"); slash("settings"); __take()
assert(opened[#opened] == "QuestBook", "/qb settings opens our section")
local count = 0 for _ in pairs(plugins) do count = count + 1 end assert(count == 1, "registered once")

-- 3. every page builds, returns a positive content height, and every row has a label and a getter that does not error
for _, page in ipairs(spec.modules[1].pages) do
  local h, rows = build(page)
  assert(type(h) == "number" and h > 0 and #rows >= 3, page .. ": height " .. tostring(h) .. ", rows " .. #rows)
  for _, r in ipairs(rows) do
    assert(type(r.text) == "string" and r.text ~= "", page .. ": a row without a label")
    if r.get then local ok, v = pcall(r.get); assert(ok, page .. " / " .. r.text .. ": getter errors: " .. tostring(v)) end
  end
end

-- 4. Voice: each control does what its command does, quietly (no chat line), and the getter shows it
local Q, X = QB.modules.questlog, QB.modules.xp
local h, rows = build("Voice")
__take()
local engine = row(rows, "Voice")
assert(engine.get() == "game", "starts on the game's voice")
engine.set("relay"); assert(Q.db.engine == "relay" and engine.get() == "relay", "the dropdown sets the engine")
assert(#__take() == 0, "quietly: no chat output from a settings change")
assert(table.concat(engine.extra.order, ",") == "game,relay" and engine.extra.values.relay, "values and order for the dropdown")
local walk = row(rows, "Read the quest when you start walking")
local was = walk.get(); walk.set(not was); assert(walk.get() == not was and QB.db.voice == not was, "walk-and-listen follows the toggle"); walk.set(was)
local pre = row(rows, "Prepare the audio when a quest is accepted")
pre.set(false); assert(Q.db.prefetch == false and pre.get() == false); pre.set(true); assert(Q.db.prefetch == true)
local speed = row(rows, "Speed of the game's voice"); speed.set(4); assert(QB.db.rate == 4 and speed.get() == 4, "the rate slider")
speed.set(0)
local sent = {}
WoWAI = { IsConnected = function() return true end, SendTts = function(a, s, r, t) sent[#sent + 1] = a; return true, 1 end }
row(rows, "Test the relay voice").set()
assert(sent[#sent] == "play", "the test button sends a test line to the relay")
__take(); row(rows, "Say why the relay voice is or is not used").set()
assert(table.concat(__take(), "\n"):find("voice:", 1, true), "and the 'why' button does print to the chat")

-- 5. Reader
h, rows = build("Reader")
row(rows, "Text size").set(28); assert(Q.db.body == 28 and row(rows, "Text size").get() == 28, "text size")
local auto = row(rows, "Same height as the map")
assert(auto.get() == true, "starts on the map's height")
auto.set(false); assert(Q.db.height > 0 and auto.get() == false, "off: its own height, from a tall start")
row(rows, "Page height").set(0.7); assert(math.abs(Q.db.height - 0.7) < 1e-6, "the height slider")
auto.set(true); assert(Q.db.height == 0, "back to the map's height")
row(rows, "Page width (relative to its height)").set(0.9); assert(math.abs(Q.db.aspect - 0.9) < 1e-6, "aspect")
row(rows, "Scroll bar").set(true); assert(Q.db.scrollbar == true)
for _, t in ipairs({ { "The small minimap", "hideMinimap" }, { "Your portrait and the target frame", "hideFrames" }, { "Your buffs and debuffs", "hideAuras" } }) do
  local r = row(rows, t[1]); r.set(false); assert(Q.db[t[2]] == false and r.get() == false, t[1]); r.set(true); assert(Q.db[t[2]] == true)
end
row(rows, "Open the reader").set(); assert(QuestBookReader and QuestBookReader:IsShown(), "the button opens the reader"); QuestBookReader:Hide()

-- 6. Experience bar
h, rows = build("Experience bar")
row(rows, "Width").set(500); assert(X.db.widthPx == 500 and row(rows, "Width").get() == 500)
row(rows, "Height").set(5); assert(X.db.heightPx == 5)
row(rows, "Gap under the strip").set(6); assert(X.db.gapPx == 6)
row(rows, "Number size").set(18); assert(X.db.textPx == 18)
row(rows, "Show the number above the bar").set(false); assert(X.db.text == false)
row(rows, "Show the rested part on the bar").set(false); assert(X.db.rested == false)
row(rows, "Hide Blizzard's own bottom bar").set(false); assert(X.db.blizzard == false)

-- 7. Top right
h, rows = build("Top right")
local S, E = QB.modules.strip, QB.modules.elle
row(rows, "Show the coordinates").set(false); assert(S.db.showCoords == false); row(rows, "Show the coordinates").set(true)
row(rows, "Show the mail icon").set(false); assert(S.db.showMail == false); row(rows, "Show the mail icon").set(true)
row(rows, "Show the server time").set(false); assert(S.db.showClock == false and row(rows, "Show the server time").get() == false, "the clock toggle")
row(rows, "Show the server time").set(true); assert(S.db.showClock == true)
row(rows, "Room reserved beside each title").set(40); assert(E.db.width == 40, "the Play button's width")

-- 8. Modules: a toggle per module that switches it for real
h, rows = build("Modules")
local tracker = row(rows, "QuestBook's own quest list")
assert(tracker.get() == true); tracker.set(false)
assert(QB.modules.tracker.active == false and tracker.get() == false, "off")
tracker.set(true); assert(QB.modules.tracker.active == true, "and on again")
local plates = row(rows, "Quest icons on nameplates"); plates.set(false); assert(QB.modules.plates.active == false)
assert(not rows[1].text:find("is off"), "the page header is plain while everything is on")
local reloaded = false
local realReload = ReloadUI; ReloadUI = function() reloaded = true end
row(rows, "Reload the UI").set(); assert(reloaded, "the reload button reloads"); ReloadUI = realReload
-- a page for a module that is off says so in its header (built fresh)
QB:SetEnabled("xp", false)
h, rows = build("Experience bar")
assert(rows[1].text:find("is off", 1, true), "an off module is named in its page header: " .. rows[1].text)
QB:SetEnabled("xp", true); QB:SetEnabled("plates", true)

-- 9. robust against a factory that lacks a widget, or one that throws: the page still builds, the error is reported, nothing is thrown
local realSlider = EllesmereUI.Widgets.Slider
EllesmereUI.Widgets.Slider = nil
h, rows = build("Experience bar"); assert(h > 0, "a missing Slider: the rest of the page is built")
EllesmereUI.Widgets.Slider = function() error("boom") end
local ok = pcall(build, "Experience bar"); assert(ok, "a widget that throws never reaches Ellesmere's panel")
assert(QB.errors.panel and QB.errors.panel.count > 0, "and it is reported against the module"); QB.errors.panel = nil
EllesmereUI.Widgets.Slider = realSlider

-- 10. the hidden search pass: a stub factory that creates no frames and returns no frame: the page still returns its height
local frameless = {}
for _, k in ipairs({ "SectionHeader", "Toggle", "Slider", "Dropdown", "Button" }) do frameless[k] = function() return nil, 50 end end
EllesmereUI.Widgets = frameless
local h2 = plugins.QuestBook.modules[1].buildPage("Voice", CreateFrame("Frame"), -10)
assert(type(h2) == "number" and h2 > 0, "the stub pass works")
-- ... and a stub that returns nothing at all for the height
for k in pairs(frameless) do frameless[k] = function() end end
h2 = plugins.QuestBook.modules[1].buildPage("Voice", CreateFrame("Frame"), -10)
assert(type(h2) == "number" and h2 > 0, "even with no heights returned")

-- 11. /qb settings in combat does not open the panel (it does not open in combat), and says so
local nOpened = #opened
__combat = true; slash("settings"); local sc = table.concat(__take(), "\n"); __combat = false
assert(#opened == nOpened and sc:find("combat", 1, true), "in combat it says so and does not open: " .. sc)
print("panel ok")
