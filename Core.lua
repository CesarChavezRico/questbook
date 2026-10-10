-- QuestBook Core -- module registry, isolation, settings, slash, keybinds.
--
-- Design (4bits-cesar notes/2026-10-09-hud-map-addon-design.md, decision 15):
-- one addon, isolated modules. Every module entry point is called through
-- QB:Safe (pcall), every module has an off switch, and a module that cannot
-- run on this client marks itself `unavailable` with a reason instead of
-- erroring. A fault in the map modules must never take down the quest log.
--
-- Files share one table: every file starts with `local ADDON, QB = ...`.

local ADDON, QB = ...
QB.name = ADDON
QB.version = "0.7.0"
QB.modules = {}      -- name -> module table
QB.order = {}        -- registration order
QB.errors = {}       -- module name -> { msg = string, count = number }
QB.slash = {}        -- subcommand -> { fn = function, help = string, mod = table }
QB.listeners = {}    -- topic -> { { fn = function, owner = table|string }, ... }

-- Core + legacy QuestLog settings stay flat (existing QuestBookDB keeps working);
-- each module's own settings live in db.mod[<name>].
local CORE_DEFAULTS = {
  fontSize = 17, width = 1040, height = 860, darken = true,
  voice = true, rate = 0, prosody = true,
  mod = {},
}

local function DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = DeepCopy(x) end
  return out
end

local function FillDefaults(dst, src)
  for k, v in pairs(src) do
    if dst[k] == nil then
      dst[k] = DeepCopy(v)
    elseif type(dst[k]) == "table" and type(v) == "table" then
      FillDefaults(dst[k], v)
    end
  end
end

function QB:Say(msg)
  print("|cffd8c88aQuestBook|r: " .. tostring(msg))
end

-- ---------------------------------------------------------------- isolation

function QB:ReportError(modName, err)
  local rec = QB.errors[modName]
  if not rec then
    rec = { msg = tostring(err), count = 0 }
    QB.errors[modName] = rec
    QB:Say("|cffff6060module '" .. tostring(modName) .. "' hit an error and was isolated:|r "
      .. tostring(err) .. "  (/qb errors, /qb disable " .. tostring(modName) .. ")")
  end
  rec.count = rec.count + 1
  rec.msg = tostring(err)
end

-- Run fn(...) protected. `owner` is a module table or a name string.
-- Returns ok, ... (like pcall) and reports the failure once per module.
function QB:Safe(owner, fn, ...)
  if type(fn) ~= "function" then return false end
  local name = type(owner) == "table" and owner.name or tostring(owner)
  local res = { pcall(fn, ...) }
  if not res[1] then
    QB:ReportError(name, res[2])
    return false
  end
  return true, unpack(res, 2, #res)
end

-- ---------------------------------------------------------------- bus

-- Loose coupling between modules: topics, not references.
-- Used topics: "overlay_state" (state string "off"|"local"|"both"),
-- "open_full" (request to open the Full map), "combat_start", "combat_end".
function QB:On(topic, fn, owner)
  local list = QB.listeners[topic]
  if not list then list = {}; QB.listeners[topic] = list end
  list[#list + 1] = { fn = fn, owner = owner or "core" }
end

function QB:Fire(topic, ...)
  local list = QB.listeners[topic]
  if not list then return end
  for _, l in ipairs(list) do
    local owner = l.owner
    if type(owner) ~= "table" or owner.active then
      QB:Safe(owner, l.fn, ...)
    end
  end
end

-- ---------------------------------------------------------------- modules

-- mod.events  = { EVENT_NAME = function(self, ...) }   registered on Enable
-- mod.OnInit(self)    once, at login, mod.db is ready (defaults merged)
-- mod.OnEnable(self)  when switched on (also at login if enabled)
-- mod.OnDisable(self) when switched off: must undo what OnEnable changed
-- mod.unavailable     set to a reason string (in OnInit) to refuse to run
function QB:NewModule(name, defaults)
  local mod = {
    name = name,
    defaults = defaults or {},
    events = {},
    active = false,
    initialised = false,
  }
  QB.modules[name] = mod
  QB.order[#QB.order + 1] = name
  return mod
end

-- The module table if it exists AND is active, else nil.
function QB:Get(name)
  local mod = QB.modules[name]
  if mod and mod.active then return mod end
  return nil
end

-- Call mod:method(...) protected, only if the module is active and has it.
function QB:Call(name, method, ...)
  local mod = QB:Get(name)
  if mod and type(mod[method]) == "function" then
    return QB:Safe(mod, mod[method], mod, ...)
  end
  return false
end

function QB:InCombat()
  if InCombatLockdown and InCombatLockdown() then return true end
  if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
  return false
end

local eventFrame = CreateFrame("Frame")
QB.frame = eventFrame
local eventMods = {}   -- event -> { mod, ... }

local function RegisterModEvent(mod, event)
  local list = eventMods[event]
  if not list then
    list = {}
    eventMods[event] = list
    -- an event unknown to this client throws; that must not break loading
    pcall(eventFrame.RegisterEvent, eventFrame, event)
  end
  for _, m in ipairs(list) do
    if m == mod then return end
  end
  list[#list + 1] = mod
end

local function ModDB(name)
  local db = QB.db
  db.mod[name] = db.mod[name] or {}
  return db.mod[name]
end

function QB:IsEnabledSetting(name)
  return ModDB(name).enabled ~= false
end

function QB:Enable(name)
  local mod = QB.modules[name]
  if not mod or mod.active or not mod.initialised then return false end
  if mod.unavailable then return false end
  mod.active = true
  for event in pairs(mod.events) do RegisterModEvent(mod, event) end
  if mod.OnEnable then
    local ok = QB:Safe(mod, mod.OnEnable, mod)
    if not ok then
      mod.active = false
      return false
    end
  end
  return true
end

function QB:Disable(name)
  local mod = QB.modules[name]
  if not mod or not mod.active then return false end
  if mod.OnDisable then QB:Safe(mod, mod.OnDisable, mod) end
  mod.active = false
  return true
end

function QB:SetEnabled(name, on)
  local mod = QB.modules[name]
  if not mod then return false end
  ModDB(name).enabled = on and true or false
  if on then return QB:Enable(name) end
  return QB:Disable(name)
end

function QB:RegisterSlash(mod, sub, fn, help)
  QB.slash[sub:lower()] = { fn = fn, help = help, mod = mod }
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    local name = ...
    if name == ADDON then QB:Boot() end
    return
  end
  if event == "PLAYER_LOGIN" then
    QB:Boot(true)   -- IsLoggedIn() may still be false inside this very handler
    return
  end
  if event == "PLAYER_REGEN_DISABLED" then QB:Fire("combat_start") end
  if event == "PLAYER_REGEN_ENABLED" then QB:Fire("combat_end") end
  local list = eventMods[event]
  if not list then return end
  for _, mod in ipairs(list) do
    if mod.active then
      local handler = mod.events[event]
      if handler then QB:Safe(mod, handler, mod, ...) end
    end
  end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")

-- Idempotent: runs at ADDON_LOADED (db ready) and again at PLAYER_LOGIN
-- (modules enabled once the UI exists).
function QB:Boot(loggedIn)
  if not QB.db then
    QuestBookDB = QuestBookDB or {}
    FillDefaults(QuestBookDB, CORE_DEFAULTS)
    QB.db = QuestBookDB
  end
  if not (loggedIn or (IsLoggedIn and IsLoggedIn())) then return end
  if QB.booted then return end
  QB.booted = true
  for _, name in ipairs(QB.order) do
    local mod = QB.modules[name]
    local mdb = ModDB(name)
    FillDefaults(mdb, mod.defaults)
    mod.db = mdb
    mod.initialised = true
    if mod.OnInit then QB:Safe(mod, mod.OnInit, mod) end
    if mdb.enabled ~= false then QB:Enable(name) end
  end
end

-- ---------------------------------------------------------------- slash

local function ModuleLine(name)
  local mod = QB.modules[name]
  local state
  if mod.unavailable then
    state = "|cffff9040unavailable|r (" .. tostring(mod.unavailable) .. ")"
  elseif mod.active then
    state = "|cff6fca6fon|r"
  else
    state = "|cff888888off|r"
  end
  local rec = QB.errors[name]
  local errs = rec and (" |cffff6060errors: " .. rec.count .. "|r") or ""
  return name .. ": " .. state .. errs
end

function QB:HandleSlash(msg)
  msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local sub, rest = msg:match("^(%S+)%s*(.-)$")
  sub = sub and sub:lower() or ""
  if sub == "modules" or sub == "status" then
    QB:Say("v" .. QB.version)
    for _, name in ipairs(QB.order) do QB:Say("  " .. ModuleLine(name)) end
    return
  elseif sub == "enable" or sub == "disable" then
    local target = rest:lower()
    if not QB.modules[target] then
      QB:Say("no module '" .. target .. "' (try /qb modules)")
    else
      QB:SetEnabled(target, sub == "enable")
      QB:Say(ModuleLine(target))
    end
    return
  elseif sub == "errors" then
    local any = false
    for name, rec in pairs(QB.errors) do
      any = true
      QB:Say(name .. " x" .. rec.count .. ": " .. rec.msg)
    end
    if not any then QB:Say("no module errors this session") end
    return
  elseif sub == "help" then
    QB:Say("/qb modules | enable <m> | disable <m> | errors")
    for s, rec in pairs(QB.slash) do
      if rec.help then QB:Say("/qb " .. s .. " -- " .. rec.help) end
    end
    return
  end
  local handler = QB.slash[sub]
  if handler then
    if handler.mod == nil or handler.mod.active then
      QB:Safe(handler.mod or "core", handler.fn, rest)
    else
      QB:Say("module '" .. tostring(handler.mod and handler.mod.name) .. "' is off")
    end
    return
  end
  -- everything else is the legacy QuestBook command set (size, dark, voice, ...)
  if QB.legacySlash then
    QB:Safe("questlog", QB.legacySlash, msg)
  end
end

SLASH_QUESTBOOK1, SLASH_QUESTBOOK2 = "/qb", "/questbook"
SlashCmdList.QUESTBOOK = function(msg) QB:HandleSlash(msg) end

-- ---------------------------------------------------------------- keybinds

BINDING_HEADER_QUESTBOOK = "QuestBook"
_G["BINDING_NAME_QUESTBOOK_TOGGLE"] = "Toggle quest log"
_G["BINDING_NAME_QUESTBOOK_MAPCYCLE"] = "Map overlay: cycle Off / Local / Local + Zone"
_G["BINDING_NAME_QUESTBOOK_FULLMAP"] = "Open the Full map"

function QuestBook_Toggle() QB:Call("questlog", "Toggle") end
function QuestBook_MapCycle() QB:Call("overlay", "Cycle") end
function QuestBook_FullMap() QB:Fire("open_full") end
