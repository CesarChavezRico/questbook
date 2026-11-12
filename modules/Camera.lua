-- QuestBook Camera -- shifts the game camera sideways while the map overlay is
-- open, so the character sits left of centre and the map panel (right side of
-- the screen) does not cover them.
--
-- Mechanism (same trick as Dialogue UI, /tmp/yui/Code/Camera.lua):
--   * CVar test_cameraOverShoulder is the lateral camera offset.
--   * It is scaled with camera zoom: offset = (zoom * 0.4314 + 0.1057) * multiplier
--     (GetShoulderOffsetByZoom, Dialogue UI Camera.lua).
--   * CameraKeepCharacterCentered and CameraReduceUnexpectedMovement override the
--     offset, so both are forced to 0 while shifted (Dialogue UI "11.0.2 Fix").
--   * Dialogue UI also unregisters EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED on
--     UIParent so test_* CVars do not raise a confirmation popup.
--
-- Safety: every CVar is backed up into mod.db.backup BEFORE the first change and
-- restored from there. A leftover backup at login (crash / closed with the
-- overlay open) is restored immediately.
--
-- Bus: listens "overlay_state" ("off" | "local" | "zone") fired by Overlay.lua.
-- Slash: /qb camera ...

local ADDON, QB = ...

local mod = QB:NewModule("camera", {
  strength = 0.5,     -- multiplier (times side); 1.0 is Dialogue UI's full shift
  side = 1,           -- +1 / -1; which sign moves the character left is UNVERIFIED, see /qb camera flip
  zoomGoal = 0,       -- 0 = off, else an ABSOLUTE camera zoom to go to while shifted (wins over zoomOut)
  zoomOut = 3,        -- RELATIVE: zoom out by this much while shifted, back when it ends (0 = off). Used when mapShift is on.
  -- The map loop (Cesar, 2026-11-11: "We still zoom to the right when stepping into map mode. lets change that by keeping the char
  -- centered but zoom progressivly out, with the zoom out of the map, with the overland being the farthest out the camera will allow"):
  mapShift = false,   -- the sideways shift for the MAPS (the quest reader keeps its shift); off = the character stays centred
  -- Cesar, 2026-11-12: "Character zoom. It needs to be a specific value. I found wierd behaviour and I think it has something to
  -- do with other camera adjustments form the map itself or other addons like dialogUI". So the maps go to ABSOLUTE distances
  -- (v0.28.2's zoomLocal / zoomZone were steps from wherever the camera happened to be, which another addon could have moved).
  mapZoomLocal = 15,  -- ABSOLUTE camera distance while the large local map is open
  mapZoomZone = 50,   -- ABSOLUTE, the overland map; 50 is more than any camera allows, so: as far as it goes
  mapZoomRest = 0,    -- ABSOLUTE distance to return to when the maps close; 0 = the distance the camera had before
  readerZoom = 3,     -- the same, while the QUEST READER is what is open (negative zooms IN, 0 = no zoom change)
  ease = 0.35,        -- seconds
  shift = true,       -- /qb camera on|off: master switch for the shift itself
  mountMult = 4.8,    -- extra multiplier while mounted (MOUNTED_CAMERA_MULTIPLIER in Dialogue UI)
})

local CVAR_SHOULDER = "test_cameraOverShoulder"
local OWNED_CVARS = { CVAR_SHOULDER, "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }
local OVERRIDE_CVARS = { CameraKeepCharacterCentered = "0", CameraReduceUnexpectedMovement = "0" }

local STEP = 0.03          -- seconds between CVar writes while easing (Dialogue UI throttles at 0.03)
local POLL = 0.10          -- seconds between zoom / mount polls while shifted
local RETARGET_EASE = 0.15 -- ease time when zoom or mount changes while shifted
local RETARGET_EPS = 0.02  -- minimum offset change that triggers a retarget
local YIELD_RESUME = 0.8   -- seconds to wait after a dialogue closes: its camera moves back first
local YIELD_MAX = 120      -- a dialogue that never reports closing does not hold the camera forever
local SEEK_POLL = 0.25     -- seconds between looks at the zoom while going to a distance
local SEEK_TRIES = 4       -- corrections before giving up (the camera's own limit, or another addon that insists)
local SEEK_EPS = 0.3       -- close enough

mod.engaged = false        -- CVars are currently overridden (backup exists)
mod.releasing = false      -- easing back to the original, restore at the end
mod.easing = false
mod.yielding = false       -- a quest / gossip dialogue is open: another camera owns the CVars for now
mod.yieldToken = 0
mod.cur = 0                -- last offset written
mod.overlayState = "off"
mod.readerOpen = false     -- the quest reader is up: it sits where the map sits, so it gets the same shift and zoom
mod.acc = 0

-- ---------------------------------------------------------------- helpers

local function GetCV(name)
  if not (C_CVar and C_CVar.GetCVar) then return nil end
  local ok, v = pcall(C_CVar.GetCVar, name)
  if ok then return v end
  return nil
end

-- Returns true when the write took.
local function SetCV(name, value)
  if not (C_CVar and C_CVar.SetCVar) then return false end
  local ok, res = pcall(C_CVar.SetCVar, name, tostring(value))
  return ok and res ~= false
end

local function Zoom()
  if type(GetCameraZoom) ~= "function" then return 0 end
  local ok, z = pcall(GetCameraZoom)
  if ok and type(z) == "number" then return z end
  return 0
end

local function Mounted()
  if type(IsMounted) ~= "function" then return false end
  local ok, m = pcall(IsMounted)
  return ok and m and true or false
end

local function Smooth(k) return k * k * (3 - 2 * k) end

local function Fmt(v) return string.format("%.4f", v) end

-- Dialogue UI Camera.lua GetShoulderOffsetByZoom
local function OffsetByZoom(zoom)
  return zoom * 0.4314 + 0.1057
end

-- ---------------------------------------------------------------- target

function mod:Target()
  -- a map with mapShift off (or the master switch off) keeps the character centred: no sideways offset, only the zoom
  local map = self.overlayState ~= "off"
  if (map and not self.db.mapShift) or not self.db.shift then return 0 end
  local mult = self.db.strength * self.db.side
  if Mounted() then mult = mult * self.db.mountMult end
  return OffsetByZoom(Zoom()) * mult
end

function mod:Original()
  local b = self.db.backup
  return tonumber(b and b[CVAR_SHOULDER]) or 0
end

-- ---------------------------------------------------------------- backup / restore

-- Take the backup BEFORE the first change; never overwrite an existing one
-- (an existing backup is the user's true original).
function mod:Backup()
  if type(self.db.backup) ~= "table" then self.db.backup = {} end
  local b = self.db.backup
  for _, name in ipairs(OWNED_CVARS) do
    if b[name] == nil then
      local v = GetCV(name)
      if v ~= nil then b[name] = v end
    end
  end
end

-- Restore from mod.db.backup. Entries that were written back are removed; if any
-- write failed the rest stays and is retried on PLAYER_REGEN_ENABLED / next login.
function mod:RestoreAll()
  local b = self.db.backup
  self.pendingRestore = false
  if type(b) == "table" then
    for name, val in pairs(b) do
      if SetCV(name, val) then b[name] = nil end
    end
    if next(b) == nil then
      self.db.backup = nil
    else
      self.pendingRestore = true
    end
  end
  if not self.pendingRestore then
    self.engaged = false
    self.releasing = false
    self.easing = false
    if self.driver then self.driver:SetScript("OnUpdate", nil) end
    if self.oldZoom then
      local rest = (self.zoomedForMap and tonumber(self.db.mapZoomRest) or 0)
      self:SeekZoom(rest > 0 and rest or self.oldZoom)
      self.oldZoom = nil
      self.zoomedForMap = nil
    end
  end
end

-- ---------------------------------------------------------------- zoom goal

-- Dialogue UI Camera.lua ZoomTo (CameraZoomIn / CameraZoomOut take a distance).
function mod:ZoomTo(goal)
  if type(CameraZoomIn) ~= "function" or type(CameraZoomOut) ~= "function" then return end
  local diff = Zoom() - goal
  if diff < 0.1 and diff > -0.1 then return end
  if diff > 0 then
    pcall(CameraZoomIn, diff)
  else
    pcall(CameraZoomOut, -diff)
  end
end

-- Go to a distance and make sure the camera ends there. CameraZoomIn / CameraZoomOut are steps, and GetCameraZoom reads the
-- camera mid-glide, so one step computed while another zoom (ours, the wheel's, a dialogue addon's) is still gliding lands
-- somewhere else. So: step, wait until the camera has stopped, look again, correct; a few times at most, and the wheel is the
-- player's again afterwards. Nothing is corrected while a dialogue owns the camera.
function mod:SeekZoom(goal)
  self.seekGoal = goal
  self.seekTries = 0
  self.seekLast = nil
  self.seekAcc = 0
  if not self.yielding then self:ZoomTo(goal) end
  if self.seeker then self.seeker:SetScript("OnUpdate", self.SeekOnUpdate) end
end

function mod:StopSeek()
  self.seekGoal = nil
  if self.seeker then self.seeker:SetScript("OnUpdate", nil) end
end

function mod:SeekStep(elapsed)
  if not self.seekGoal then return self:StopSeek() end
  if self.yielding then self.seekLast = nil return end
  self.seekAcc = (self.seekAcc or 0) + elapsed
  if self.seekAcc < SEEK_POLL then return end
  self.seekAcc = 0
  local z = Zoom()
  local last = self.seekLast
  self.seekLast = z
  if not last or math.abs(z - last) > 0.05 then return end      -- still gliding
  if math.abs(z - self.seekGoal) <= SEEK_EPS or self.seekTries >= SEEK_TRIES then return self:StopSeek() end
  self.seekTries = self.seekTries + 1
  self.seekLast = nil
  self:ZoomTo(self.seekGoal)
end

mod.SeekOnUpdate = function(_, elapsed) QB:Safe(mod, mod.SeekStep, mod, elapsed) end

-- ---------------------------------------------------------------- easing

function mod:WriteShoulder(v)
  self.cur = v
  SetCV(CVAR_SHOULDER, Fmt(v))
end

function mod:StartEase(to, dur)
  self.from = self.cur
  self.to = to
  self.t = 0
  self.dur = dur or self.db.ease
  if self.dur < 0 then self.dur = 0 end
  self.easing = true
  self.acc = 0
end

function mod:Step(elapsed)
  if self.yielding then
    -- Dialogue UI (and any addon like it) writes test_cameraOverShoulder every 0.03 s towards its own target
    -- and moves the zoom; our zoom poll would answer with a second ease towards ours, and the two fight
    -- ("the camera wobbles going in and out", Cesar 2026-10-17). So write nothing while a dialogue is open.
    self.yieldT = (self.yieldT or 0) + elapsed
    if self.yieldT > YIELD_MAX then self:Resume(self.yieldToken, 0) end
    return
  end
  self.acc = self.acc + elapsed
  if self.easing then
    self.t = self.t + elapsed
    if self.acc >= STEP or self.t >= self.dur then
      self.acc = 0
      local k = 1
      if self.dur > 0 then k = math.min(self.t / self.dur, 1) end
      self:WriteShoulder(self.from + (self.to - self.from) * Smooth(k))
      if k >= 1 then
        self.easing = false
        if self.releasing then self:RestoreAll() end
      end
    end
    return
  end
  -- steady state while shifted: poll zoom / mount (UNVERIFIED: that GetCameraZoom
  -- reflects wheel zoom immediately; Dialogue UI reads it the same way)
  if self.acc >= POLL then
    self.acc = 0
    if self.engaged and not self.releasing then
      local target = self:Target()
      if math.abs(target - self.cur) > RETARGET_EPS then
        self:StartEase(target, RETARGET_EASE)
      end
    end
  end
end

local function DriverOnUpdate(_, elapsed)
  QB:Safe(mod, mod.Step, mod, elapsed)
end

-- ---------------------------------------------------------------- dialogues

function mod:Yield()
  self.yielding = true
  self.yieldT = 0
  self.yieldToken = self.yieldToken + 1
  self.easing = false                    -- drop a half-done ease: the dialogue's camera starts from where it is
end

-- After the dialogue has closed (and its camera has moved back): take the CVar up again from wherever it
-- was left, and ease to what it should be now (the shift, or the original if the overlay closed meanwhile).
function mod:Resume(token, delay)
  if token ~= self.yieldToken or not self.yielding then return end
  local function go()
    if token ~= self.yieldToken or not self.yielding then return end
    self.yielding = false
    self.acc = 0
    if self.seekGoal then self:SeekZoom(self.seekGoal) end     -- the dialogue moved the zoom: go where we were going
    if not self.engaged then return end
    self.cur = tonumber(GetCV(CVAR_SHOULDER)) or self.cur
    if not self.releasing and self.oldZoom then self:SeekZoom(self:GoalZoom()) end
    if self.releasing then
      self:StartEase(self:Original(), self.db.ease)
    else
      self:StartEase(self:Target(), RETARGET_EASE)
    end
  end
  if delay and delay > 0 and C_Timer and C_Timer.After then C_Timer.After(delay, function() QB:Safe(mod, go) end)
  else go() end
end

-- ---------------------------------------------------------------- engage / release

-- How far to go out (or in, if negative) from the player's own zoom: the reader's own setting while the quest reader is
-- what is open, else the shifted map's.
function mod:RelativeZoom()
  if self.readerOpen and self.overlayState == "off" then return tonumber(self.db.readerZoom) or 0 end
  if self.db.mapShift then return tonumber(self.db.zoomOut) or 0 end
  return 0
end

-- The distance the camera should be at now. A centred map (mapShift off) names an ABSOLUTE distance; everything else is a
-- step from the distance the camera had when we took it (self.oldZoom).
function mod:GoalZoom()
  local goal = self.db.zoomGoal
  if type(goal) == "number" and goal > 0 then return goal end
  if not self.db.mapShift and not (self.readerOpen and self.overlayState == "off") then
    local abs = (self.overlayState == "local" and tonumber(self.db.mapZoomLocal))
      or (self.overlayState == "zone" and tonumber(self.db.mapZoomZone)) or nil
    if abs and abs > 0 then self.zoomedForMap = true return abs end
  end
  return (self.oldZoom or Zoom()) + self:RelativeZoom()
end

function mod:Engage()
  if self.unavailable then return end
  if GetCV(CVAR_SHOULDER) == nil then
    if not self.warnedMissing then
      self.warnedMissing = true
      QB:Say("camera: CVar " .. CVAR_SHOULDER .. " not readable on this client; no shift")
    end
    return
  end
  self.releasing = false
  if not self.engaged then
    self:Backup()                                    -- before the first change
    for name, val in pairs(OVERRIDE_CVARS) do SetCV(name, val) end
    self.engaged = true
    self.cur = tonumber(GetCV(CVAR_SHOULDER)) or 0
    -- remembered even when this first step does not zoom: the next one (local map -> overland map) starts from it.
    -- A zoom of ours still on its way back (the map closed a moment ago) is where the camera is going, not where it is.
    self.oldZoom = self.seekGoal or Zoom()
    self:SeekZoom(self:GoalZoom())                               -- the client clamps at its own limits
  elseif self.oldZoom then
    -- already engaged and something changed hands (local map -> overland map, or the map and the quest reader trade
    -- places): go to the new distance. A no-op when the camera is already there.
    self:SeekZoom(self:GoalZoom())
  end
  self:StartEase(self:Target(), self.db.ease)
  if self.driver then self.driver:SetScript("OnUpdate", DriverOnUpdate) end
end

function mod:Release(immediate)
  if not self.engaged then return end
  if immediate then
    self:RestoreAll()
    return
  end
  self.releasing = true
  self:StartEase(self:Original(), self.db.ease)
  if self.driver then self.driver:SetScript("OnUpdate", DriverOnUpdate) end
end

function mod:Sync()
  -- a map always engages (for its zoom); the reader only while the shift is on
  local want = self.overlayState ~= "off" or (self.db.shift and self.readerOpen)
  if want then
    self:Engage()
  elseif self.engaged then
    self:Release()
  end
end

function mod:OnOverlayState(state)
  self.overlayState = state or "off"
  self:Sync()
end

-- ---------------------------------------------------------------- lifecycle

function mod:OnInit()
  if not (C_CVar and C_CVar.GetCVar and C_CVar.SetCVar) then
    self.unavailable = "C_CVar missing"
    return
  end
  if type(GetCameraZoom) ~= "function" then
    self.unavailable = "GetCameraZoom missing"
    return
  end
  self.driver = CreateFrame("Frame")
  self.seeker = CreateFrame("Frame")
end

function mod:OnEnable()
  -- Dialogue UI Camera.lua: UIParent:UnregisterEvent("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
  -- UNVERIFIED: whether this client raises that popup for test_* CVars at all; harmless if not.
  if UIParent and UIParent.IsEventRegistered and UIParent:IsEventRegistered("EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED") then
    pcall(UIParent.UnregisterEvent, UIParent, "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED")
    self.unregisteredPopup = true
  end

  -- A previous session ended with the shift active: put the user's values back first.
  if type(self.db.backup) == "table" then
    self.engaged = true
    self:RestoreAll()
    QB:Say("camera: restored camera settings left over from a previous session")
  end

  -- If the overlay is already open (module switched on mid-session), follow it.
  local ov = QB.modules.overlay
  if ov and ov.active and type(ov.GetState) == "function" then
    self.overlayState = ov:GetState() or "off"
  else
    self.overlayState = "off"
  end
  self:Sync()
end

function mod:OnDisable()
  self:Release(true)
  if self.unregisteredPopup then
    self.unregisteredPopup = false
    if UIParent then pcall(UIParent.RegisterEvent, UIParent, "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED") end
  end
end

-- ---------------------------------------------------------------- events

-- Same events Dialogue UI uses to restore on exit (Camera.lua ListenEvent), plus mount.
local function RestoreOnExit(self)
  self:Release(true)
end
mod.events.PLAYER_LOGOUT = RestoreOnExit
mod.events.PLAYER_QUITING = RestoreOnExit
mod.events.PLAYER_CAMPING = RestoreOnExit

-- Dialogue UI Camera.lua OnMountChanged: the multiplier changes while mounted.
mod.events.PLAYER_MOUNT_DISPLAY_CHANGED = function(self)
  if self.engaged and not self.releasing then
    self:StartEase(self:Target(), RETARGET_EASE)
  end
end

-- A quest-giver / gossip dialogue opens: hold off; it closes: take over again once it has settled. These are the
-- client's own interaction events (UNVERIFIED which of them this client sends; an unknown one is just never fired).
for _, e in ipairs({ "GOSSIP_SHOW", "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
  mod.events[e] = function(self) self:Yield() end
end
for _, e in ipairs({ "GOSSIP_CLOSED", "QUEST_FINISHED" }) do
  mod.events[e] = function(self) if self.yielding then self:Resume(self.yieldToken, YIELD_RESUME) end end
end

mod.events.PLAYER_REGEN_ENABLED = function(self)
  if self.pendingRestore then self:RestoreAll() end
end

QB:On("overlay_state", function(state) mod:OnOverlayState(state) end, mod)

-- The quest reader trades places with the map (modules/QuestLog.lua): it announces itself BEFORE it closes the map
-- and the map announces itself when it takes the place back, so the shift is never let go in between.
QB:On("reader_state", function(open)
  mod.readerOpen = open and true or false
  mod:Sync()           -- (Engage also moves the zoom when the map and the reader trade places)
end, mod)

-- ---------------------------------------------------------------- slash

local function Status()
  local db = mod.db
  return string.format(
    "camera: shift=%s maps: shift=%s zoom local=%s zone=%s rest=%s now=%.1f | strength=%.2f side=%+d zoomOut=%s readerZoom=%s zoomGoal=%s ease=%.2fs mountMult=%.2f | overlay=%s engaged=%s offset=%.3f%s",
    db.shift and "on" or "off", db.mapShift and "on" or "off", tostring(db.mapZoomLocal), tostring(db.mapZoomZone),
    (tonumber(db.mapZoomRest) or 0) > 0 and tostring(db.mapZoomRest) or "as before", Zoom(), db.strength, db.side,
    (db.zoomOut and db.zoomOut > 0) and tostring(db.zoomOut) or "off",
    (db.readerZoom and db.readerZoom ~= 0) and tostring(db.readerZoom) or "off",
    (db.zoomGoal and db.zoomGoal > 0) and tostring(db.zoomGoal) or "off",
    db.ease, db.mountMult, mod.overlayState, tostring(mod.engaged), mod.cur or 0,
    mod.yielding and " (paused: a dialogue is open)" or "")
end

QB:RegisterSlash(mod, "camera", function(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  sub = (sub or ""):lower()
  local db = mod.db
  local n = tonumber(arg)
  if sub == "flip" then
    db.side = -db.side
    mod:Sync()   -- re-engages with the new sign (retargets the ease)
  elseif sub == "strength" and n then
    db.strength = math.max(0, math.min(n, 3))
    if mod.engaged and not mod.releasing then mod:StartEase(mod:Target(), mod.db.ease) end
  elseif sub == "readerzoom" and n then
    -- relative, like zoomout, for the quest reader; negative zooms in
    db.readerZoom = math.max(-10, math.min(n, 30))
    if mod.engaged and not mod.releasing and mod.oldZoom and mod.readerOpen and mod.overlayState == "off" then
      mod:SeekZoom(mod:GoalZoom())
    end
  elseif sub == "zoomout" and n then
    -- relative: how far to pull the camera back while the overlay is open (0 = off); takes
    -- effect the next time the overlay opens, or now if it is open
    db.zoomOut = math.max(0, math.min(n, 30))
    if mod.engaged and not mod.releasing and mod.oldZoom then mod:SeekZoom(mod:GoalZoom()) end
  elseif sub == "map" then
    -- /qb camera map shift on|off | zoom <local> <zone> | rest <n>|here|off
    local what, v1, v2 = arg:lower():match("^(%S*)%s*(%S*)%s*(%S*)$")
    if what == "shift" and (v1 == "on" or v1 == "off") then
      db.mapShift = (v1 == "on")
      mod:Sync()
    elseif what == "zoom" and tonumber(v1) then
      db.mapZoomLocal = math.max(0, math.min(tonumber(v1), 50))     -- 0 = that map leaves the zoom alone
      if tonumber(v2) then db.mapZoomZone = math.max(0, math.min(tonumber(v2), 50)) end
      if mod.engaged and not mod.releasing and mod.oldZoom and mod.overlayState ~= "off" then mod:SeekZoom(mod:GoalZoom()) end
    elseif what == "rest" and (tonumber(v1) or v1 == "here" or v1 == "off") then
      -- the distance to come back to when the maps close: a number, "here" (where the camera is now), or "off" (as before)
      if v1 == "here" then db.mapZoomRest = math.floor(Zoom() * 10 + 0.5) / 10
      elseif v1 == "off" then db.mapZoomRest = 0
      else db.mapZoomRest = math.max(0, math.min(tonumber(v1), 50)) end
    else
      QB:Usage("/qb camera map shift on|off | zoom <local> <zone> | rest <n>|here|off   (camera distances: for each map, 50 = as far as it goes; rest = where it returns to)")
    end
  elseif sub == "zoom" and n then
    db.zoomGoal = math.max(0, n)
  elseif sub == "ease" and n then
    db.ease = math.max(0, math.min(n, 3))
  elseif sub == "mount" and n then
    db.mountMult = math.max(0, math.min(n, 10))
    if mod.engaged and not mod.releasing then mod:StartEase(mod:Target(), mod.db.ease) end
  elseif sub == "off" then
    db.shift = false
    mod:Sync()
  elseif sub == "on" then
    db.shift = true
    mod:Sync()
  elseif sub ~= "" and sub ~= "status" then
    QB:Usage("/qb camera map shift on|off | map zoom <local> <zone> | map rest <n>|here|off | flip | strength <n> | zoomout <n> | readerzoom <n> | zoom <n|0> | ease <s> | mount <n> | on | off")
  end
  QB:Say(Status())
end, "camera shift tied to the map overlay and the quest reader (flip | strength <n> | zoomout <n> | readerzoom <n> | zoom <n> | on | off)")
