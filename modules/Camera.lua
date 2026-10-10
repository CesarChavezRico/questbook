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
  zoomGoal = 0,       -- 0 = leave zoom alone, else camera zoom to ease to while shifted
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

mod.engaged = false        -- CVars are currently overridden (backup exists)
mod.releasing = false      -- easing back to the original, restore at the end
mod.easing = false
mod.cur = 0                -- last offset written
mod.overlayState = "off"
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
      self:ZoomTo(self.oldZoom)
      self.oldZoom = nil
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

-- ---------------------------------------------------------------- engage / release

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
    local goal = self.db.zoomGoal
    if type(goal) == "number" and goal > 0 then
      self.oldZoom = Zoom()
      self:ZoomTo(goal)
    end
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
  local want = self.db.shift and self.overlayState ~= "off"
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

mod.events.PLAYER_REGEN_ENABLED = function(self)
  if self.pendingRestore then self:RestoreAll() end
end

QB:On("overlay_state", function(state) mod:OnOverlayState(state) end, mod)

-- ---------------------------------------------------------------- slash

local function Status()
  local db = mod.db
  return string.format(
    "camera: shift=%s strength=%.2f side=%+d zoomGoal=%s ease=%.2fs mountMult=%.2f | overlay=%s engaged=%s offset=%.3f",
    db.shift and "on" or "off", db.strength, db.side,
    (db.zoomGoal and db.zoomGoal > 0) and tostring(db.zoomGoal) or "off",
    db.ease, db.mountMult, mod.overlayState, tostring(mod.engaged), mod.cur or 0)
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
    QB:Say("/qb camera flip | strength <n> | zoom <n|0> | ease <s> | mount <n> | on | off")
  end
  QB:Say(Status())
end, "camera shift tied to the map overlay (flip | strength <n> | zoom <n> | on | off)")
