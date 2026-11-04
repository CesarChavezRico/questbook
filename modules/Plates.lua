-- QuestBook Plates -- an icon on the nameplate of a mob that one of your quests needs (4BI-36; Cesar, 2026-10-21: "display an
-- icon if there's a quest associated with killing the unit or if it drops something for a quest").
--
-- How it knows (all from Blizzard's own APIs, none from a database of ours):
--   1. C_QuestLog.UnitIsRelatedToActiveQuest(unit): the game says whether the unit is tied to a quest in your log.
--   2. C_TooltipInfo.GetUnit(unit): the unit's tooltip lines; the QuestObjective lines (type 8) under a QuestTitle (17), up to the
--      first QuestPlayer line (18), which starts a party member's quests. Each objective line is matched, by its text without the
--      counts, to the objectives of the quests in your log (C_QuestLog.GetQuestObjectives), whose `type` says what the objective is:
--      "monster" = kill it (a sword), "item" = it drops something (a bag), anything else = a plain quest mark. The counts
--      (have / need) come from that objective and are written beside the icon.
-- An objective already done shows nothing. Nameplates the game forbids addons to touch (instances, probably) are skipped.
--
-- UNVERIFIED (client only): that these two calls answer on this client the way the Forever API dump documents them, that the
-- tooltip's objective text matches the quest log's, and the icon art paths. `/qb plates diag` (with a mob targeted or under the
-- mouse) prints everything this module sees about it, so one test settles each of them.

local _, QB = ...
local Style = QB.Style

local mod = QB:NewModule("plates", {
  on = true,         -- show the icons
  size = 26,         -- icon size in physical pixels
  side = "right",    -- where on the nameplate: "right" | "left" | "top"
  progress = true,   -- the counts (3/8) beside the icon
})

-- the icon art: stock client icons (the same paths Blizzard's own UI and every classic addon use)
local ART = {
  kill = { "Interface\\Icons\\INV_Sword_04", true },
  loot = { "Interface\\Icons\\INV_Misc_Bag_08", true },
  quest = { "Interface\\GossipFrame\\AvailableQuestIcon", false },     -- a plain "!": no zoom, it has its own shape
}
local KIND = { monster = "kill", item = "loot" }     -- C_QuestLog.GetQuestObjectives type -> icon

local active = {}        -- unit token -> true, for the nameplates on screen now
local frames = {}        -- unit token -> the icon frame (pooled by token)
local objCache           -- normalised objective text -> { kind, have, need, done }; nil = rebuild on next use
local queued = false

local function IsSecret(v)
  return type(issecretvalue) == "function" and issecretvalue(v) and true or false
end

-- ---------------------------------------------------------------- what the game says

-- An objective's text without colours, counts and punctuation, so the tooltip's line and the quest log's compare equal.
local function Norm(text)
  if type(text) ~= "string" then return nil end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  text = text:gsub("%d+%s*/%s*%d+", ""):gsub("%d+%%", "")
  text = text:lower():gsub("[^%w]+", "")
  if text == "" then return nil end
  return text
end

-- The objectives of every quest in the log, by normalised text.
local function Objectives()
  if objCache then return objCache end
  local map = {}
  local ok, quests = QB:Call("questlog", "Scan")
  if ok and type(quests) == "table" and C_QuestLog and C_QuestLog.GetQuestObjectives then
    for _, q in ipairs(quests) do
      local okO, objs = pcall(C_QuestLog.GetQuestObjectives, q.questID)
      if okO and type(objs) == "table" then
        for _, o in ipairs(objs) do
          local key = Norm(o.text)
          if key then
            map[key] = { kind = KIND[o.type] or "quest", have = tonumber(o.numFulfilled), need = tonumber(o.numRequired),
              done = o.finished and true or false, objType = o.type }
          end
        end
      end
    end
  end
  objCache = map
  return map
end

-- The unit tooltip as { type, text } lines, or nil when the client has no tooltip data for units.
local function TooltipLines(unit)
  if not (C_TooltipInfo and C_TooltipInfo.GetUnit) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
  if not (ok and type(data) == "table" and type(data.lines) == "table") then return nil end
  local surface = TooltipUtil and TooltipUtil.SurfaceArgs
  if surface then pcall(surface, data) end
  local out = {}
  for _, line in ipairs(data.lines) do
    if surface then pcall(surface, line) end
    local t, text = line.type, line.leftText
    if IsSecret(t) then t = nil end
    if IsSecret(text) or type(text) ~= "string" then text = "" end
    out[#out + 1] = { type = t, text = text }
  end
  return out
end

-- nil = show nothing; otherwise { kind = "kill" | "loot" | "quest", have, need }.
local function Analyse(unit)
  if not (C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest) then return nil end
  local okR, rel = pcall(C_QuestLog.UnitIsRelatedToActiveQuest, unit)
  if not okR or IsSecret(rel) or rel ~= true then return nil end
  local lines = TooltipLines(unit)
  if not lines then return { kind = "quest" } end          -- no tooltip data: the game's word is all there is
  local map = Objectives()
  local sawQuest, best = false, nil
  for _, l in ipairs(lines) do
    if l.type == 18 then break end                         -- QuestPlayer: what follows is a party member's quests
    if l.type == 17 then sawQuest = true end
    if l.type == 8 then
      sawQuest = true
      local info = map[Norm(l.text) or ""]
      if info then
        if not info.done and not best then best = { kind = info.kind, have = info.have, need = info.need } end
      elseif not best then
        local h, n = l.text:match("(%d+)%s*/%s*(%d+)")
        h, n = tonumber(h), tonumber(n)
        if not (h and n and h >= n) then best = { kind = "quest", have = h, need = n } end
      end
    end
  end
  if best then return best end
  if not sawQuest then return { kind = "quest" } end        -- related, but the tooltip shows no quest lines: trust the game
  return nil                                                -- every objective on it is done
end

-- ---------------------------------------------------------------- the icon

local function Px(n, f) return Style.Px(n, f) end

local function Frame(unit)
  local f = frames[unit]
  if f then return f end
  f = CreateFrame("Frame", nil, UIParent)
  f:EnableMouse(false)
  f:SetFrameStrata("MEDIUM")
  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(Style.FRIZ, Px(14, f), "OUTLINE")           -- a font at birth: SetText on a fontless string is an error
  f.text:SetShadowOffset(Px(1, f), -Px(1, f))
  f.text:SetShadowColor(0, 0, 0, 0.9)
  f:Hide()
  frames[unit] = f
  return f
end

local function PlateOf(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
  local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)     -- (a forbidden plate is not returned: addons may not touch it)
  return ok and plate or nil
end

local function Hide(unit)
  local f = frames[unit]
  if f then f:Hide() end
end

local function Show(unit, res, plate)
  local f = Frame(unit)
  local db = mod.db
  local size = Style.Clamp(tonumber(db.size) or 26, 12, 80)
  local art = ART[res.kind] or ART.quest
  f:SetParent(plate)
  f:SetSize(Px(size, f), Px(size, f))
  f.icon:SetSize(Px(size, f), Px(size, f))
  f.icon:SetTexture(art[1])
  if art[2] then f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) else f.icon:SetTexCoord(0, 1, 0, 1) end
  f.text:SetFont(Style.FRIZ, Px(math.max(11, math.floor(size * 0.55)), f), "OUTLINE")
  f.text:ClearAllPoints()
  f.text:SetPoint("LEFT", f.icon, "RIGHT", Px(3, f), 0)
  local txt = ""
  if db.progress and res.need and res.need > 0 then txt = (res.have or 0) .. "/" .. res.need end
  f.text:SetText(txt)
  f.text:SetTextColor(1, 0.92, 0.55, 1)
  f:ClearAllPoints()
  local side = db.side
  if side == "left" then f:SetPoint("RIGHT", plate, "LEFT", -Px(4, f), 0)
  elseif side == "top" then f:SetPoint("BOTTOM", plate, "TOP", 0, Px(2, f))
  else f:SetPoint("LEFT", plate, "RIGHT", Px(4, f), 0) end
  f:SetFrameLevel((plate.GetFrameLevel and plate:GetFrameLevel() or 1) + 5)
  f:Show()
end

-- Look at one nameplate unit and show or hide its icon.
local function Update(unit)
  if not (mod.db.on and unit) then Hide(unit) return end
  local plate = PlateOf(unit)
  if not plate then Hide(unit) return end
  if UnitIsPlayer and UnitIsPlayer(unit) then Hide(unit) return end
  if UnitCanAttack and not UnitCanAttack("player", unit) then Hide(unit) return end      -- quest givers and other friends are not targets
  local res = Analyse(unit)
  if res then Show(unit, res, plate) else Hide(unit) end
end

local function UpdateAll()
  queued = false
  for unit in pairs(active) do Update(unit) end
end

-- the quest log changed (a kill counted, a quest taken or handed in): look at every plate again, once, a moment later
local function Queue()
  objCache = nil
  if queued then return end
  queued = true
  if C_Timer and C_Timer.After then
    C_Timer.After(0.3, function() QB:Safe(mod, UpdateAll) end)
  else
    UpdateAll()
  end
end

mod.events.NAME_PLATE_UNIT_ADDED = function(_, unit) active[unit] = true; Update(unit) end
mod.events.NAME_PLATE_UNIT_REMOVED = function(_, unit) active[unit] = nil; Hide(unit) end
mod.events.QUEST_LOG_UPDATE = Queue
mod.events.UNIT_QUEST_LOG_CHANGED = Queue
mod.events.QUEST_WATCH_UPDATE = Queue
mod.events.QUEST_ACCEPTED = Queue
mod.events.QUEST_REMOVED = Queue
mod.events.QUEST_TURNED_IN = Queue
mod.events.PLAYER_ENTERING_WORLD = function() wipe(active); for _, f in pairs(frames) do f:Hide() end; objCache = nil end

function mod:OnDisable()
  for _, f in pairs(frames) do f:Hide() end
end

-- ---------------------------------------------------------------- slash

-- Everything seen about one unit, for the first test in the game.
local function Diag()
  local unit = (UnitExists and UnitExists("target")) and "target" or "mouseover"
  if not (UnitExists and UnitExists(unit)) then QB:Say("plates: target a mob or put the mouse on one, then /qb plates diag") return end
  local okR, rel = pcall(function() return C_QuestLog.UnitIsRelatedToActiveQuest(unit) end)
  QB:Say("plates: " .. tostring(UnitName and UnitName(unit)) .. " | related to a quest: " .. (okR and tostring(rel) or ("error " .. tostring(rel))))
  QB:Say("plates: its nameplate: " .. tostring(PlateOf(unit) ~= nil) .. " | tooltip API: " .. tostring(C_TooltipInfo and C_TooltipInfo.GetUnit ~= nil))
  local lines = TooltipLines(unit)
  if lines then
    local shown = 0
    for i, l in ipairs(lines) do
      if i > 1 and shown < 12 then
        shown = shown + 1
        QB:Say(string.format("plates: line %d type %s: %s", i, tostring(l.type), (l.text:gsub("|", "||"))))
      end
    end
  end
  local res = Analyse(unit)
  QB:Say("plates: result: " .. (res and (res.kind .. (res.need and (" " .. tostring(res.have) .. "/" .. tostring(res.need)) or "")) or "nothing to show"))
  local n = 0
  for _ in pairs(Objectives()) do n = n + 1 end
  QB:Say("plates: " .. n .. " objectives known from the quest log")
end

QB:RegisterSlash(mod, "plates", function(rest)
  local sub, arg = (rest or ""):lower():match("^(%S*)%s*(.-)$")
  local n = tonumber(arg)
  if sub == "diag" then
    Diag()
    return
  elseif sub == "on" or sub == "off" then
    mod.db.on = (sub == "on")
  elseif sub == "size" and n then
    mod.db.size = Style.Clamp(math.floor(n), 12, 80)
  elseif sub == "side" and (arg == "right" or arg == "left" or arg == "top") then
    mod.db.side = arg
  elseif sub == "progress" and (arg == "on" or arg == "off") then
    mod.db.progress = (arg == "on")
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb plates on|off | size <px> | side right|left|top | progress on|off | diag   (diag: with a mob targeted or under the mouse)")
  end
  objCache = nil
  UpdateAll()
  local shown = 0
  for _, f in pairs(frames) do if f:IsShown() then shown = shown + 1 end end
  QB:Say(string.format("plates: %s, icon %d px at the %s of the nameplate, counts %s, %d icons showing", mod.db.on and "on" or "off",
    mod.db.size, mod.db.side, mod.db.progress and "on" or "off", shown))
end, "plates on|off|size|side|progress|diag: a sword or a bag on the nameplates of mobs your quests need")
