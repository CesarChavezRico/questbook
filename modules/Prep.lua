-- QuestBook Prep -- Nibble questions the game while Cesar is away from the rig (4BI-46).
--
-- Cesar, 2026-11-20: "what I want is a way for you to 'question' the game for the information needed for offline prep of a
-- game session"; on free Lua: "Why don't we write a 'prep state' into QuestBook where errors are harmless and we move to
-- 'play state' when I am sitting at the rig"; and on keeping the game open from work: "a quick login and a key press now
-- and then are acceptable from work, an away counter will help me keep it alive".
--
-- Questions arrive through the relay addon (WoWAI.RegisterInbound, kind "qbask": wow-relay 4BI-45), answers go back with
-- WoWAI.SendData("answer", ...). A question is a few lines of text; its first line says what it is:
--
--   q <name> [arguments]     a FIXED question, answered in either state: state | bags | quests | guide <from> <to> |
--                            items <id,id,...> | completed <id,id,...>
--   lua                      FREE Lua on the lines that follow, answered ONLY in prep state
--
-- THE RULES (the ticket's, kept here because this file is where they are enforced):
--   * Prep state is switched on only by a command typed at the client (/qb prep on). No message can switch it on: the
--     inbound handler has no path to it. It lives in memory only, so any /reload ends it, and /qb prep off IS a /reload
--     (code that arrived this way taints what it touched until the UI reloads).
--   * In play state free Lua is refused; the answer says so.
--   * Free Lua runs inside pcall, in a FENCE: an environment that is not the game's. It can call the game's reading
--     functions (names starting Get / Is / Has / Can / Unit / Num / Does / Find / Ready / Are, minus the known ones that
--     change something), read the game's and the addons' tables through read-only views (their functions are not handed
--     over, except reading functions of the C_ namespaces), and use the plain Lua basics. It cannot reach loadstring,
--     setfenv, the real _G, frames' methods, timers, chat, or anything that buys, abandons, sends, deletes or reloads.
--   * Nothing here sends input to the game. The away counter only shows how long the character has been flagged away.
--
-- WHAT THE FENCE IS NOT: proof. "A name starting with Get only reads" is a rule of thumb, not a guarantee, and the list of
-- exceptions (DENY below) is built from memory of the classic API, not from this client. A loop that never ends hangs the
-- client (nothing in the game's Lua can interrupt it); accepted in prep, where nobody is playing.
-- UNVERIFIED (client only): all of it. /qb prep run <lua> runs a line through the same fence from the chat box, to try it.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("prep", {
  limit = 20,           -- minutes flagged away before the counter turns red (the game's own disconnect time is not known here)
  poll = 25,            -- seconds between asking the relay for waiting questions while prep is on (each ask uses one reply slot)
})

local ANSWER_MAX = 20000        -- bytes of one answer, over all its parts
local PARTS_MAX = 10
local DEPTH_MAX = 7
local ENTRIES_MAX = 600         -- entries of one table written into an answer

-- ---------------------------------------------------------------- the fence

local ALLOW = { "^Get", "^Is", "^Has", "^Can", "^Unit", "^Num", "^Does", "^Find", "^Ready", "^Are" }
-- Names that pass ALLOW and still change something (classic API, from memory; extend as they are found):
local DENY = {
  GetQuestReward = true,        -- takes the reward: completes the turn-in
  GetInboxText = true,          -- marks the mail read
  GetGuildRoster = true,        -- asks the server for the roster
}

local function Reads(name)
  if type(name) ~= "string" or DENY[name] then return false end
  for _, p in ipairs(ALLOW) do if name:find(p) then return true end end
  return false
end

local realOf = setmetatable({}, { __mode = "k" })    -- view -> the real table
local viewOf = setmetatable({}, { __mode = "k" })    -- real table -> its view
local nsOf = setmetatable({}, { __mode = "k" })      -- real table -> true when it is a C_ namespace (its reading functions are handed over)

local View

-- What the fenced code gets for a value found in a real table.
local function Expose(v, k, namespace)
  local t = type(v)
  if t == "table" then return View(v, false) end
  if t == "function" then
    if namespace and Reads(k) then return v end
    return nil
  end
  if t == "userdata" or t == "thread" then return nil end
  return v
end

View = function(real, namespace)
  local view = viewOf[real]
  if view then return view end
  view = setmetatable({}, {
    __index = function(_, k)
      local ok, v = pcall(function() return real[k] end)
      if not ok then return nil end
      return Expose(v, k, nsOf[real])
    end,
    __newindex = function() error("read-only: the fence does not let a question change the game's tables", 2) end,
    __metatable = false,
  })
  realOf[view], viewOf[real] = real, view
  if namespace then nsOf[real] = true end
  return view
end

local function Unview(v) return realOf[v] or v end

-- pairs / next / ipairs / # for views (Lua 5.1 has no __pairs and no __len for tables)
local function FencedNext(t, k)
  local real = realOf[t]
  if not real then return next(t, k) end
  local v
  repeat
    k, v = next(real, k)
    if k == nil then return nil end
    v = Expose(v, k, nsOf[real])
  until v ~= nil
  return k, v
end
local function FencedPairs(t) return FencedNext, t, nil end
local function FencedIpairs(t)
  local real = realOf[t]
  if not real then return ipairs(t) end
  local i = 0
  return function()
    i = i + 1
    local v = Expose(real[i], i, nsOf[real])
    if v ~= nil then return i, v end
  end
end
local function FencedLen(t) return #(Unview(t)) end

local function Copy(t) local c = {}; for k, v in pairs(t) do c[k] = v end; return c end

local BASICS = { "type", "tostring", "tonumber", "select", "unpack", "pcall", "error", "assert", "time", "date", "format", "strsplit", "strjoin",
  "strtrim", "strlower", "strupper", "strsub", "strfind", "strmatch", "gsub", "strlen", "strrep", "floor", "ceil", "abs", "max", "min", "mod",
  "tinsert", "tremove", "sort", "tContains", "strlenutf8" }

-- Tables that are not handed over even as views (their functions would be hidden anyway; this keeps the surface small).
local HIDDEN = { debug = true, os = true, io = true, package = true, coroutine = true, QuestBookGuide = false }

local env
local function Env()
  if env then return env end
  local base = { pairs = FencedPairs, ipairs = FencedIpairs, next = FencedNext, len = FencedLen,
    string = Copy(string), table = Copy(table), math = Copy(math) }
  base.string.dump = nil
  for _, name in ipairs(BASICS) do
    local f = _G[name]
    if type(f) == "function" then base[name] = f end
  end
  env = setmetatable({}, {
    __index = function(_, k)
      local b = base[k]
      if b ~= nil then return b end
      if type(k) ~= "string" or HIDDEN[k] then return nil end
      local v = _G[k]
      local t = type(v)
      if t == "function" then
        if not Reads(k) then return nil end
        -- a reading function of the game: views handed in as arguments become the real tables again
        return function(...)
          local n = select("#", ...)
          if n == 0 then return v() end
          local a = { ... }
          for i = 1, n do a[i] = Unview(a[i]) end
          return v(unpack(a, 1, n))
        end
      elseif t == "table" then
        return View(v, k:find("^C_") and true or false)
      elseif t == "userdata" or t == "thread" then
        return nil
      end
      return v
    end,
    __newindex = function(t, k, v) rawset(t, k, v) end,     -- a question's own globals stay in the fence (and are wiped after it)
    __metatable = false,
  })
  base._G = env
  return env
end

local function Compile(code)
  local e = Env()
  for k in pairs(e) do rawset(e, k, nil) end
  local ls, sf = _G.loadstring, _G.setfenv
  if type(ls) == "function" and type(sf) == "function" then
    local f, err = ls("return " .. code, "=question")
    if not f then f, err = ls(code, "=question") end
    if not f then return nil, err end
    sf(f, e)
    return f
  end
  local ld = _G.load                     -- (the offline test harness runs a newer Lua, which has no setfenv)
  if type(ld) ~= "function" then return nil, "this client cannot compile text" end
  local f, err = ld("return " .. code, "=question", "t", e)
  if not f then f, err = ld(code, "=question", "t", e) end
  return f, err
end

-- ---------------------------------------------------------------- writing an answer

local function Quote(s)
  s = s:gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' elseif c == "\\" then return "\\\\" elseif c == "\n" then return "\\n" elseif c == "\t" then return "\\t" end
    return string.format("\\u%04x", c:byte())
  end)
  return '"' .. s .. '"'
end

-- A value as JSON text. Views are followed into the real tables with the same rules as the fence (no functions except
-- none at all here, no userdata); frames come out as "<frame>". `budget` = { left = bytes }.
local function Json(v, depth, budget, seen)
  local t = type(v)
  if t == "string" then
    if #v > 2000 then v = v:sub(1, 2000) .. "..." end
    local s = Quote(v); budget.left = budget.left - #s; return s
  elseif t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "null" end
    local s = (v == math.floor(v) and math.abs(v) < 1e15) and string.format("%d", v) or string.format("%.6g", v)
    budget.left = budget.left - #s; return s
  elseif t == "boolean" then budget.left = budget.left - 5; return v and "true" or "false"
  elseif t ~= "table" then return "null" end
  local real = Unview(v)
  if type(rawget(real, 0)) == "userdata" then return '"<frame>"' end
  if depth >= DEPTH_MAX then return '"<deeper>"' end
  if seen[real] then return '"<seen>"' end
  seen[real] = true
  local n = #real
  local isArray = n > 0
  if isArray then for k in pairs(real) do if type(k) ~= "number" or k < 1 or k > n or k ~= math.floor(k) then isArray = false; break end end end
  local parts, count = {}, 0
  if isArray then
    for i = 1, n do
      if count >= ENTRIES_MAX or budget.left <= 0 then parts[#parts + 1] = '"<cut>"'; break end
      parts[#parts + 1] = Json(real[i], depth + 1, budget, seen); count = count + 1
    end
    seen[real] = nil
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local keys = {}
  for k, val in pairs(real) do
    local tk, tv = type(k), type(val)
    if (tk == "string" or tk == "number") and tv ~= "function" and tv ~= "userdata" and tv ~= "thread" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, k in ipairs(keys) do
    if count >= ENTRIES_MAX or budget.left <= 0 then parts[#parts + 1] = '"<cut>":true'; break end
    parts[#parts + 1] = Quote(tostring(k)) .. ":" .. Json(real[k], depth + 1, budget, seen); count = count + 1
    budget.left = budget.left - #tostring(k) - 4
  end
  seen[real] = nil
  return "{" .. table.concat(parts, ",") .. "}"
end

local function Encode(values, n)
  local budget = { left = ANSWER_MAX - 200 }
  local out = {}
  for i = 1, n do out[i] = Json(values[i], 0, budget, {}) end
  local text = n == 1 and out[1] or ("[" .. table.concat(out, ",") .. "]")
  if #text > ANSWER_MAX - 200 then text = text:sub(1, ANSWER_MAX - 200) .. " <cut: the answer was too long>" end
  return text
end

-- ---------------------------------------------------------------- answering

mod.on = false
mod.answered, mod.refused, mod.lastAt = 0, 0, nil

-- Run a free question. Returns the answer text ("ok ..." / "error ...").
function mod:RunLua(code)
  local f, err = Compile(code)
  if not f then return "error compile: " .. tostring(err) end
  local r = { pcall(f) }
  if not r[1] then return "error run: " .. tostring(r[2]) end
  local n = 0
  for k in pairs(r) do if type(k) == "number" and k > n then n = k end end
  if n <= 1 then return "ok null" end
  local values = {}
  for i = 2, n do values[i - 1] = r[i] end
  local ok, text = pcall(Encode, values, n - 1)
  if not ok then return "error encode: " .. tostring(text) end
  return "ok " .. text
end

local function IdList(s)
  local ids = {}
  for id in tostring(s or ""):gmatch("%d+") do ids[#ids + 1] = tonumber(id) end
  return ids
end

local function ItemFacts(id)
  local C = _G.C_Item
  local r
  if type(C) == "table" and type(C.GetItemInfo) == "function" then r = { pcall(C.GetItemInfo, id) } end
  if not (r and r[1] and r[2]) and type(_G.GetItemInfo) == "function" then r = { pcall(_G.GetItemInfo, id) } end
  if not (r and r[1] and r[2]) then return { id = id, known = false } end
  return { id = id, known = true, name = r[2], quality = r[4], level = r[5], minLevel = r[6], kind = r[7], sub = r[8], stack = r[9], sell = r[12] }
end

local FIXED = {}
FIXED.state = function()
  local ok, s = QB:Call("sync", "WriteState")
  if not ok or type(s) ~= "table" then return nil, "the sync module is off" end
  local free, items, ready = 0, 0, 0
  for _, b in ipairs(s.bags or {}) do free = free + (b.free or 0); items = items + #(b.items or {}) end
  for _, q in ipairs(s.quests or {}) do if q.ready then ready = ready + 1 end end
  return { name = s.name, level = s.level, xp = s.xp, xpMax = s.xpMax, rested = s.rested, money = s.money, zone = s.zone, subzone = s.subzone,
    hearth = s.hearth, guide = s.guide, quests = #(s.quests or {}), ready = ready, bagItems = items, bagFree = free, at = s.at, prep = mod.on }
end
FIXED.bags = function()
  local ok, s = QB:Call("sync", "WriteState")
  if not ok or type(s) ~= "table" then return nil, "the sync module is off" end
  return { bags = s.bags, bank = s.bank, gear = s.gear, money = s.money }
end
FIXED.quests = function()
  local ok, s = QB:Call("sync", "WriteState")
  if not ok or type(s) ~= "table" then return nil, "the sync module is off" end
  return s.quests
end
FIXED.completed = function(args)
  local Q = _G.C_QuestLog
  local out = {}
  for _, id in ipairs(IdList(args)) do
    local done
    if type(Q) == "table" and type(Q.IsQuestFlaggedCompleted) == "function" then local ok, r = pcall(Q.IsQuestFlaggedCompleted, id); if ok then done = r and true or false end
    elseif type(_G.IsQuestFlaggedCompleted) == "function" then local ok, r = pcall(_G.IsQuestFlaggedCompleted, id); if ok then done = r and true or false end end
    out[#out + 1] = { id = id, completed = done }
  end
  return out
end
FIXED.items = function(args)
  local out = {}
  for _, id in ipairs(IdList(args)) do out[#out + 1] = ItemFacts(id) end
  return out
end
-- guide <from> <to>: the text of those steps of the loaded chapter (at most 25 steps), with which elements are done
FIXED.guide = function(args)
  local rxp = _G.RXP
  local guide = type(rxp) == "table" and rxp.currentGuide
  if type(guide) ~= "table" or type(guide.steps) ~= "table" then return nil, "no guide is loaded in RestedXP" end
  local a, b = tostring(args or ""):match("(%d+)%D+(%d+)")
  a, b = tonumber(a) or tonumber(tostring(args or ""):match("%d+")) or 1, tonumber(b)
  b = math.min(b or a, a + 24, #guide.steps)
  local out = { chapter = tostring(guide.group or "?") .. " / " .. tostring(guide.name or "?"), steps = {} }
  for i = a, b do
    local step = guide.steps[i]
    local lines = {}
    if type(step) == "table" and type(step.elements) == "table" then
      for _, e in ipairs(step.elements) do
        if type(e) == "table" and type(e.text) == "string" and e.text ~= "" then
          local text = e.text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h(.-)|h", "%1")
          lines[#lines + 1] = { text = text, tag = e.tag, quest = e.questId, done = e.completed and not e.textOnly or nil }
        end
      end
    end
    out.steps[#out.steps + 1] = { step = i, active = type(step) == "table" and step.active or nil, lines = lines }
  end
  return out
end

-- The answer to one question (the whole text of it). Returns the text and whether it counted as refused.
function mod:Answer(body)
  body = tostring(body or "")
  local first, rest = body:match("^%s*([^\r\n]*)[\r\n]*(.*)$")
  first = (first or ""):gsub("%s+$", "")
  if first == "lua" then
    if not mod.on then return "refused: free Lua is answered only in prep state, which is switched on at the client (/qb prep on)", true end
    return mod:RunLua(rest or "")
  end
  local name, args = first:match("^q%s+(%S+)%s*(.*)$")
  if name and FIXED[name:lower()] then
    local ok, value, why = pcall(FIXED[name:lower()], args)
    if not ok then return "error " .. tostring(value) end
    if value == nil then return "error " .. tostring(why or "nothing to answer") end
    local ok2, text = pcall(Encode, { value }, 1)
    if not ok2 then return "error encode: " .. tostring(text) end
    return "ok " .. text
  end
  return "refused: not a question this addon knows (first line: \"lua\", or \"q state | bags | quests | guide <from> <to> | items <ids> | completed <ids>\")", true
end

-- Answers go back through the relay addon, in parts when long. They wait in an outbox until the relay takes them: the
-- first client test (2026-11-20) delivered four questions at login, a moment before the bridge was connected, and every
-- answer was lost to "the bridge is not connected". A record that cannot go now is tried again every second, the relay
-- is asked to reconnect (at most every 45 s), and after ten minutes it is given up, with a line in the chat.
local Poll                      -- (defined below: asks the relay for waiting questions while prep is on)
local outbox = {}               -- { id = , text = , at = } in order
local KEEP = 600
local CONNECT_GAP = 45
local lastConnect

local function Flush()
  if #outbox == 0 then return end
  local W = _G.WoWAI
  local now = (GetTime and GetTime()) or 0
  while outbox[1] do
    local rec = outbox[1]
    if now - rec.at > KEEP then
      table.remove(outbox, 1)
      QB:Say("prep: an answer could not be sent in ten minutes and was dropped (" .. tostring(rec.why or "the relay did not take it") .. ")")
    else
      if not (type(W) == "table" and type(W.SendData) == "function") then rec.why = "the relay addon has no SendData"; return end
      local ok, sent, why = pcall(W.SendData, "answer", rec.id, rec.text)
      if ok and sent then
        table.remove(outbox, 1)
      else
        rec.why = tostring(why or sent)
        if type(W.IsConnected) == "function" and type(W.Connect) == "function" then
          local okC, connected = pcall(W.IsConnected)
          if okC and not connected and (not lastConnect or now - lastConnect >= CONNECT_GAP) then lastConnect = now; pcall(W.Connect) end
        end
        return
      end
    end
  end
end

local function Send(id, text)
  local W = _G.WoWAI
  local room = math.max(400, (tonumber(type(W) == "table" and W.DATA_MAX) or 2400) - 60)
  local now = (GetTime and GetTime()) or 0
  if #text <= room then
    outbox[#outbox + 1] = { id = tostring(id), text = text, at = now }
  else
    local parts = {}
    local i = 1
    while i <= #text and #parts < PARTS_MAX do parts[#parts + 1] = text:sub(i, i + room - 1); i = i + room end
    if i <= #text then parts[#parts] = parts[#parts]:sub(1, room - 40) .. " <cut: too many parts>" end
    for n, p in ipairs(parts) do
      outbox[#outbox + 1] = { id = tostring(id), text = string.format("part=%d/%d\n%s", n, #parts, p), at = now }
    end
  end
  Flush()
end
mod.Waiting = function() return #outbox end

-- A question arrived (the relay addon calls this once per question).
local function Inbound(id, body)
  local text, refused = mod:Answer(body)
  mod.lastAt = (GetTime and GetTime()) or 0
  if refused then mod.refused = mod.refused + 1 else mod.answered = mod.answered + 1 end
  Send(id, text)
end

-- In prep, ask the relay for waiting questions ourselves. Client test, 2026-11-20: the relay's own signal for a waiting
-- push did not fire, so questions were only picked up at a reload, and a reload ends prep: free Lua could never arrive in
-- prep state. Each ask loads one of the relay addon's 200 reply slots of this UI session, so it is done only while prep is
-- on, every POLL_EVERY seconds: about an hour and a half of prep per reload at the default.
local POLL_EVERY = 25
local lastPoll
mod.polls, mod.pollWhy = 0, nil

Poll = function()
  if not mod.on then return end
  local W = _G.WoWAI
  if not (type(W) == "table" and type(W.CheckPush) == "function") then return end
  local now = (GetTime and GetTime()) or 0
  if lastPoll and now - lastPoll < (tonumber(mod.db.poll) or POLL_EVERY) then return end
  lastPoll = now
  local ok, took, why = pcall(W.CheckPush)
  mod.polls = mod.polls + 1
  mod.pollWhy = (ok and took) and nil or tostring(why or took)
end

-- ---------------------------------------------------------------- the away counter

local bar, ticker
local awaySince

local function Clock(secs)
  secs = math.max(0, math.floor(secs))
  return string.format("%d:%02d", math.floor(secs / 60), secs % 60)
end

local function Paint()
  if not bar then return end
  if not mod.on then bar:Hide(); return end
  local now = (GetTime and GetTime()) or 0
  local away = false
  if type(_G.UnitIsAFK) == "function" then local ok, r = pcall(_G.UnitIsAFK, "player"); away = ok and r and true or false end
  if away and not awaySince then awaySince = now elseif not away then awaySince = nil end
  local text = string.format("PREP  |  %d answered", mod.answered)
  if mod.refused > 0 then text = text .. string.format(", %d refused", mod.refused) end
  if #outbox > 0 then text = text .. string.format(", %d waiting to be sent", #outbox) end
  if mod.lastAt then text = text .. "  |  last question " .. Clock(now - mod.lastAt) .. " ago" end
  local r, g, b = 0.92, 0.89, 0.82
  if awaySince then
    local secs = now - awaySince
    text = text .. "  |  AWAY " .. Clock(secs) .. ": press a key"
    if secs >= (tonumber(mod.db.limit) or 20) * 60 then r, g, b = 0.95, 0.30, 0.25 else r, g, b = 0.85, 0.68, 0.35 end
  else
    text = text .. "  |  not away"
  end
  bar.text:SetText(text)
  bar.text:SetTextColor(r, g, b, 1)
  bar:SetWidth(bar.text:GetStringWidth() + Style.Px(28, bar))
  bar:Show()
end

local function Build()
  if bar then return end
  bar = CreateFrame("Frame", "QuestBookPrepBar", UIParent)
  bar:SetFrameStrata("HIGH")
  bar:SetHeight(Style.Px(34, bar))
  bar:SetPoint("TOP", UIParent, "TOP", 0, -Style.Px(90, bar))
  bar.bg = bar:CreateTexture(nil, "BACKGROUND")
  bar.bg:SetAllPoints(bar)
  bar.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  bar.bg:SetVertexColor(0.07, 0.06, 0.05, 0.92)
  bar.text = bar:CreateFontString(nil, "OVERLAY")
  bar.text:SetFont(Style.FRIZ, Style.Px(17, bar), "")
  bar.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
  bar:Hide()
end

function mod:OnEnable()
  local W = _G.WoWAI
  mod.listening = false
  if type(W) == "table" and type(W.RegisterInbound) == "function" then
    local ok, took = pcall(W.RegisterInbound, "qbask", Inbound)
    mod.listening = ok and took ~= false
  end
  Build()
  if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(1, function() QB:Safe(mod, Flush); QB:Safe(mod, Poll); QB:Safe(mod, Paint) end) end
end

function mod:OnDisable()
  local W = _G.WoWAI
  if type(W) == "table" and type(W.RegisterInbound) == "function" then pcall(W.RegisterInbound, "qbask", nil) end
  mod.listening, mod.on = false, false
  if ticker then ticker:Cancel(); ticker = nil end
  if bar then bar:Hide() end
end

QB:RegisterSlash(mod, "prep", function(rest)
  local sub, tail = (rest or ""):match("^%s*(%S*)%s*(.*)$")
  sub = (sub or ""):lower()
  if sub == "on" then
    mod.on = true
    QB:Say("prep: ON. Nibble's questions are answered, free Lua included, inside the fence. Leave with /qb prep off, which reloads the UI")
    if not mod.listening then QB:Say("prep: the relay addon has no door for questions (RegisterInbound), so none will arrive until it is updated") end
    Paint()
  elseif sub == "off" then
    if not mod.on then QB:Say("prep: already off (play state)"); return end
    mod.on = false
    QB:Say("prep: off; reloading the UI so nothing a question touched stays")
    if type(_G.ReloadUI) == "function" then pcall(_G.ReloadUI) else QB:Say("prep: type /reload to finish") end
  elseif sub == "limit" then
    local n = tonumber(tail:match("%d+"))
    if n and n >= 1 then mod.db.limit = n elseif tail ~= "" then QB:Usage("/qb prep limit <minutes>") end
    QB:Say(string.format("prep: the away counter turns red after %d minutes away", mod.db.limit))
  elseif sub == "run" or sub == "ask" then
    -- the same path a question from Nibble takes, typed at the client (to try the fence)
    local body = sub == "run" and ("lua\n" .. tail) or tail
    local text = mod:Answer(body)
    if #text > 900 then text = text:sub(1, 900) .. " ... (" .. #text .. " characters)" end
    QB:Usage("prep: " .. text)
  else
    if sub ~= "" and sub ~= "status" then QB:Usage("/qb prep | on | off | limit <minutes> | run <lua> | ask q <name>") end
    QB:Say(string.format("prep: %s; questions %s; %d answered, %d refused since the UI loaded%s",
      mod.on and "ON (free Lua is answered, in the fence)" or "off: play state (fixed questions only)",
      mod.listening and "can arrive through the relay addon" or "cannot arrive (the relay addon has no door for them)",
      mod.answered, mod.refused, (mod.on and mod.pollWhy and ("; the last ask for questions failed: " .. mod.pollWhy) or "") .. (#outbox > 0 and string.format("; %d answer record(s) waiting for the relay (%s)", #outbox, tostring(outbox[1].why or "not tried yet")) or "")))
  end
end, "prep: Nibble questions the game for planning a session: on | off (reloads) | limit <minutes> | run <lua> | ask q <name>")
