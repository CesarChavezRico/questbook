-- QuestBook Overlay -- the corner minimap is retired. Two SEPARATE map modes live in
-- a panel "over the character's right shoulder":
--   "local" = the minimap, blown up (the native Minimap widget, kept SQUARE)
--   "zone"  = the overland map (Blizzard's own WorldMapFrame, restyled)
-- (v0.7.0 layered both; Cesar asked for separate modes after the first client run.)
--
-- One key cycles ONE toggle:  "off" -> "local" -> "zone" -> "off".
-- While either mode is open the action bars are hidden (setting `bars`).
-- Public API: Cycle(), SetState(state), GetState(), OpenFull().
-- Bus: fires "overlay_state" (state) after every change; listens "combat_start"
-- (force off when db.combatGuard) and "open_full" (Strip -> OpenFull).
--
-- No logic outside functions touches a Blizzard frame, so loading this file can
-- never error; every Blizzard property we change is recorded in a "tweak set" and
-- restored from it on "off" / OnDisable.

local ADDON, QB = ...

local mod = QB:NewModule("overlay", {
  size = 0.62,         -- panel height, fraction of screen (UIParent) height
  offsetX = 0.17,      -- panel centre, fraction of screen width, from centre toward the right
  offsetY = 0.02,      -- panel centre, fraction of screen height, from centre upward
  shape = "rect",      -- "rect" | "circle"
  aspect = 1.25,       -- Zone rect width / height (the minimap is always square; circle is 1)
  localAlpha = 0.55,
  zoneAlpha = 0.45,
  zoneZoom = 2.0,      -- Zone layer magnification over "whole zone fits the panel"
  rotate = true,       -- "local" rotates with facing (native ground only); "zone" is always north-up
  ground = "hybrid",   -- Local ground: "hybrid" (soft edge, north-up) | "native" (hard edge, can rotate) | "auto"
  bars = "actions",    -- hidden while a map mode is open: "actions" | "all" (adds xp/rep bars) | "none"
  iconScale = 1,       -- Minimap:SetIconScale for blips (1 = Blizzard's default)
  combatGuard = true,  -- refuse to open in combat and force "off" when combat starts
})

local NEXT = { off = "local", ["local"] = "zone", zone = "off" }
-- Blizzard frames faded to alpha 0 while a map mode is open (frame names read from
-- Blizzard_ActionBar/*.xml and Blizzard_StatusTrackingBar/Mainline/StatusTrackingBar.xml)
local BAR_FRAMES = {
  actions = { "MainActionBar", "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
    "MultiBar5", "MultiBar6", "MultiBar7", "StanceBar", "PetActionBar", "PossessActionBar" },
  status = { "StatusTrackingBarManager" },
}
local TICK = 0.25                       -- seconds between verify passes while open

local TEX = "Interface\\AddOns\\" .. ADDON .. "\\Textures\\"
local MASK_PATHS = { rect = TEX .. "mask_rect.tga", circle = TEX .. "mask_circle.tga" }
-- (Blizzard_Minimap/Camelot/Skin.lua) the stock mask Blizzard puts on the Minimap
local STOCK_MASK = "ui-hud-minimap-frame-generic-mask"
local ROTATE_CVAR = "rotateMinimap"

mod.state = "off"
mod.localOn = false      -- Local layer currently realised (Minimap moved into the panel)
mod.zoneOn = false       -- Zone layer currently realised (WorldMapFrame restyled)
mod.zoneReady = false    -- Zone style may be (re)applied by hooks
mod.maskMode = "ours"    -- debug: "ours" | "stock" (/qb overlay mask)
mod.localTweaks = { order = {}, map = {} }
mod.zoneTweaks = { order = {}, map = {} }
mod.barTweaks = { order = {}, map = {} }
mod.mode = "off"         -- the mode being laid out ("local" panel is square, "zone" follows `aspect`)
mod.groundNow = "native" -- what Local actually uses right now ("hybrid" | "native")
mod.hybridFails = 0

-- ---------------------------------------------------------------- helpers

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

local function G(name) return _G[name] end

local function GetC(name)
  if not (C_CVar and C_CVar.GetCVar) then return nil end
  local ok, v = pcall(C_CVar.GetCVar, name)
  if ok then return v end
  return nil
end

local function SetC(name, value)
  if not (C_CVar and C_CVar.SetCVar) then return false end
  local ok, res = pcall(C_CVar.SetCVar, name, tostring(value))
  return ok and res ~= false
end

-- hooksecurefunc(obj, "Method", fn)  or  hooksecurefunc("GlobalFunction", fn)
local function SafeHook(obj, method, fn)
  if type(hooksecurefunc) ~= "function" then return false end
  if type(obj) == "string" then
    if type(_G[obj]) ~= "function" then return false end
    return (pcall(hooksecurefunc, obj, fn))
  end
  if type(obj) ~= "table" or type(obj[method]) ~= "function" then return false end
  return (pcall(hooksecurefunc, obj, method, fn))
end

function mod:Note(label, err)
  self.lastError = label .. ": " .. tostring(err)
end

local function Try(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then mod:Note(label, err) end
  return ok
end

-- ---------------------------------------------------------------- tweak sets
-- A tweak records the original value of one property the first time it is
-- changed; TweakDo re-applies on every call (idempotent), TweakUndoAll restores
-- in reverse order. A tweak whose undo fails stays in the set and is retried.

local function TweakDo(set, id, obj, capture, apply, undo)
  if not obj then return false end
  local t = set.map[id]
  if not t then
    local ok, orig = pcall(capture, obj)
    if not ok then return false end
    t = { id = id, obj = obj, orig = orig, undo = undo }
    set.map[id] = t
    set.order[#set.order + 1] = t
  end
  local ok, err = pcall(apply, obj)
  if not ok then mod:Note("tweak " .. id, err) end
  return ok
end

local function TweakUndoAll(set)
  local failed = 0
  for i = #set.order, 1, -1 do
    local t = set.order[i]
    local ok, err = pcall(t.undo, t.obj, t.orig)
    if ok then
      set.map[t.id] = nil
      table.remove(set.order, i)
    else
      failed = failed + 1
      mod:Note("undo " .. t.id, err)
    end
  end
  return failed
end

-- Undo only the tweaks whose id starts with `prefix` (switching a sub-feature off alone).
local function TweakUndoPrefix(set, prefix)
  for i = #set.order, 1, -1 do
    local t = set.order[i]
    if t.id:sub(1, #prefix) == prefix then
      local ok, err = pcall(t.undo, t.obj, t.orig)
      if ok then
        set.map[t.id] = nil
        table.remove(set.order, i)
      else
        mod:Note("undo " .. t.id, err)
      end
    end
  end
end

local function TAlpha(set, id, o, a)
  return TweakDo(set, id, o,
    function(x) return x:GetAlpha() end,
    function(x) x:SetAlpha(a) end,
    function(x, orig) x:SetAlpha(orig) end)
end

local function TShown(set, id, o, shown)
  return TweakDo(set, id, o,
    function(x) return x:IsShown() and true or false end,
    function(x) if (x:IsShown() and true or false) ~= shown then x:SetShown(shown) end end,
    function(x, orig) x:SetShown(orig) end)
end

local function TMouse(set, id, o, enabled)
  return TweakDo(set, id, o,
    function(x) return x:IsMouseEnabled() and true or false end,
    function(x) x:EnableMouse(enabled) end,
    function(x, orig) x:EnableMouse(orig) end)
end

local function TWheel(set, id, o, enabled)
  return TweakDo(set, id, o,
    function(x) return x:IsMouseWheelEnabled() and true or false end,
    function(x) x:EnableMouseWheel(enabled) end,
    function(x, orig) x:EnableMouseWheel(orig) end)
end

local function TStrata(set, id, o, strata)
  return TweakDo(set, id, o,
    function(x) return x:GetFrameStrata() end,
    function(x) x:SetFrameStrata(strata) end,
    function(x, orig) x:SetFrameStrata(orig) end)
end

local function TLevel(set, id, o, level)
  return TweakDo(set, id, o,
    function(x) return x:GetFrameLevel() end,
    function(x) x:SetFrameLevel(level) end,
    function(x, orig) x:SetFrameLevel(orig) end)
end

local function CapturePoints(o)
  local pts = {}
  for i = 1, o:GetNumPoints() do
    local p, rel, relPoint, x, y = o:GetPoint(i)
    pts[i] = { p, rel, relPoint, x or 0, y or 0 }
  end
  return pts
end

local function ApplyPoints(o, spec)
  o:ClearAllPoints()
  for _, s in ipairs(spec) do o:SetPoint(s[1], s[2], s[3], s[4], s[5]) end
end

local function RestorePoints(o, pts)
  o:ClearAllPoints()
  for _, a in ipairs(pts) do
    if a[2] then o:SetPoint(a[1], a[2], a[3], a[4], a[5]) else o:SetPoint(a[1], a[4], a[5]) end
  end
end

local function HasPoints(o, spec)
  if o:GetNumPoints() ~= #spec then return false end
  for i, s in ipairs(spec) do
    local p, rel, relPoint, x, y = o:GetPoint(i)
    if p ~= s[1] or rel ~= s[2] or relPoint ~= s[3]
      or math.abs((x or 0) - s[4]) > 0.5 or math.abs((y or 0) - s[5]) > 0.5 then
      return false
    end
  end
  return true
end

-- Re-anchors only when the current anchors differ (avoids relayout churn every tick).
local function TPoints(set, id, o, spec)
  return TweakDo(set, id, o, CapturePoints,
    function(x) if not HasPoints(x, spec) then ApplyPoints(x, spec) end end,
    RestorePoints)
end

-- ---------------------------------------------------------------- geometry / panel

-- Returns width, height, centre offset x, y (UI units from the screen centre).
function mod:Geometry()
  local db = self.db
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local h = math.max(64, clamp(tonumber(db.size) or 0.62, 0.1, 1.5) * H)
  local aspect = 1
  -- the minimap is ALWAYS square: a stretched widget put the ground and the blips on different
  -- scales (the first client run showed pins off in position and direction)
  if db.shape ~= "circle" and self.mode ~= "local" then aspect = clamp(tonumber(db.aspect) or 1.25, 0.5, 3) end
  return h * aspect, h, (tonumber(db.offsetX) or 0) * W, (tonumber(db.offsetY) or 0) * H
end

function mod:EnsurePanel()
  if self.panel then return self.panel end
  local panel = CreateFrame("Frame", nil, UIParent)
  panel:SetFrameStrata("LOW")        -- Zone layer sits in BACKGROUND, so Local draws above it
  panel:EnableMouse(false)           -- click-through
  panel:Hide()
  self.panel = panel
  return panel
end

function mod:LayoutPanel()
  local panel = self:EnsurePanel()
  local w, h, cx, cy = self:Geometry()
  panel:SetSize(w, h)
  panel:ClearAllPoints()
  panel:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
end

function mod:Layout()
  if not self.panel then return end
  Try("layout panel", self.LayoutPanel, self)
  if self.localOn then Try("layout local", self.LocalUpdate, self) end
  if self.zoneOn then Try("layout zone", self.ReapplyZone, self) end
end

-- ---------------------------------------------------------------- rotation CVar

-- Back up the user's rotateMinimap on first use (persisted so a crash is recoverable),
-- put the value the state wants, restore the backup on "off".
function mod:ApplyRotation()
  local want
  if self.state == "local" then
    want = self.db.rotate and "1" or "0"
  end                     -- "zone" / "off": the user's own value
  if want then
    if self.db.rotateBackup == nil then
      local cur = GetC(ROTATE_CVAR)
      if cur == nil then return end
      self.db.rotateBackup = cur
    end
    if GetC(ROTATE_CVAR) ~= want then
      self.rotWanted = want
      SetC(ROTATE_CVAR, want)
    end
  else
    self.rotWanted = nil
    if self.db.rotateBackup ~= nil then
      if SetC(ROTATE_CVAR, self.db.rotateBackup) then
        self.db.rotateBackup = nil
      else
        self.dirty = true
      end
    end
  end
end

-- ---------------------------------------------------------------- Local layer (native Minimap)

local HITCHILDREN = { "ZoomHitArea", "ZoomIn", "ZoomOut" }   -- (Blizzard_Minimap/Mainline/Minimap.xml)

function mod:ApplyMinimapMask()
  local mm = G("Minimap")
  if not (mm and mm.SetMaskTexture) then return false end
  local path = MASK_PATHS[self.db.shape] or MASK_PATHS.rect
  if self.maskMode == "stock" then path = STOCK_MASK end
  self.wantMask = path
  self.maskSetting = true
  local ok, err = pcall(mm.SetMaskTexture, mm, path)
  self.maskSetting = false
  if not ok then
    self:Note("Minimap:SetMaskTexture", err)
    if not self.maskWarned then
      self.maskWarned = true
      QB:Say("overlay: could not set the minimap mask (" .. tostring(err) .. ")")
    end
  end
  return ok
end

-- Put all Local-layer properties in place (idempotent; also the layout pass).
function mod:LocalUpdate()
  local mm = G("Minimap")
  local panel = self.panel
  if not (mm and panel) then return end
  local set = self.localTweaks
  local w, h = panel:GetSize()
  local resized = false
  self.layouting = true
  -- reparent first, then anchor, then size (undone in reverse)
  TweakDo(set, "mm.parent", mm,
    function(x) return x:GetParent() end,
    function(x) if x:GetParent() ~= panel then x:SetParent(panel) end end,
    function(x, orig) x:SetParent(orig) end)
  TPoints(set, "mm.points", mm, { { "CENTER", panel, "CENTER", 0, 0 } })
  TweakDo(set, "mm.size", mm,
    function(x) local a, b = x:GetSize() return { a, b } end,
    function(x)
      local cw, ch = x:GetSize()
      if math.abs(cw - w) > 0.5 or math.abs(ch - h) > 0.5 then x:SetSize(w, h); resized = true end
    end,
    function(x, orig) x:SetSize(orig[1], orig[2]) end)
  TAlpha(set, "mm.alpha", mm, clamp(tonumber(self.db.localAlpha) or 0.55, 0, 1))
  TStrata(set, "mm.strata", mm, "LOW")
  TLevel(set, "mm.level", mm, panel:GetFrameLevel() + 1)
  -- click-through: the widget, its wheel, and the small zoom hit areas
  TMouse(set, "mm.mouse", mm, false)
  TWheel(set, "mm.wheel", mm, false)
  for _, key in ipairs(HITCHILDREN) do
    local child = mm[key]
    if child and child.EnableMouse then TMouse(set, "mm.mouse." .. key, child, false) end
  end
  -- no frame art: MinimapBackdrop holds the compass / frame textures
  -- (Blizzard_Minimap/Mainline/Minimap.xml, Camelot/Skin.lua)
  local bd = G("MinimapBackdrop")
  if bd then TShown(set, "mm.backdrop", bd, false) end
  self.layouting = false
  self.layoutDirty = false
  self:ApplyMinimapMask()
  if resized then self:RefreshMinimapZoom() end
  Try("ground", self.ApplyGround, self)
  Try("icon scale", self.ApplyIconScale, self)
end

-- After the widget changes size the client keeps blip positions from the old size until the
-- zoom is touched. UNVERIFIED: remembered addon trick (nudge the zoom and put it back); the
-- frames involved are the ones documented in MinimapFrameAPIDocumentation.lua (GetZoom/SetZoom).
function mod:RefreshMinimapZoom()
  local mm = G("Minimap")
  if not (mm and mm.GetZoom and mm.SetZoom) then return end
  local ok, z = pcall(mm.GetZoom, mm)
  if not (ok and type(z) == "number") then return end
  local alt = (z > 0) and (z - 1) or (z + 1)
  pcall(mm.SetZoom, mm, alt)
  pcall(mm.SetZoom, mm, z)
end

function mod:ApplyIconScale()
  local mm = G("Minimap")
  if not (mm and mm.SetIconScale) then return end
  local want = clamp(tonumber(self.db.iconScale) or 1, 0.5, 4)
  if self.iconApplied ~= want then
    if pcall(mm.SetIconScale, mm, want) then self.iconApplied = want end
  end
end

-- ---------------------------------------------------------------- Local ground (hybrid / native)
--
-- The first client run showed the native Minimap cuts its ground with a HARD edge (a dead-straight
-- line; it ignores a soft-alpha mask). Blizzard's own HybridMinimap draws the ground from the zone
-- map art instead (a MapCanvas whose textures DO take a mask) while the native Minimap keeps
-- drawing the blips, arrow and quest areas on top (Blizzard_HybridMinimap/*.lua: it turns the
-- Minimap's ground textures off in OnShow and is parented to the Minimap). Trade-off: the hybrid
-- ground is north-up only (SetIgnoreRotateMinimap(true) in its OnShow).

local function HybridFrame()
  local hm = G("HybridMinimap")
  if hm then return hm end
  if type(HybridMinimap_LoadUI) == "function" then     -- (Blizzard_Minimap/Mainline/Minimap.lua)
    pcall(HybridMinimap_LoadUI)
    return G("HybridMinimap")
  end
  return nil
end

function mod:WantHybrid()
  if self.hybridBroken then return false end
  local g = self.db.ground
  if g == "native" then return false end
  if g == "hybrid" then return true end
  -- "auto": hybrid where Blizzard itself uses it, or indoors (native ground is blank there)
  if C_Minimap and C_Minimap.ShouldUseHybridMinimap then
    local ok, v = pcall(C_Minimap.ShouldUseHybridMinimap)
    if ok and v then return true end
  end
  if type(IsIndoors) == "function" then
    local ok, v = pcall(IsIndoors)
    if ok and v then return true end
  end
  return false
end

function mod:HybridOn()
  local hm = HybridFrame()
  if not (hm and hm.Enable and hm.CheckMap and hm.MapCanvas and hm.MapCanvas.SetMaskTexture
      and hm.CreateMaskTexture) then
    return false, "HybridMinimap frame not available on this client"
  end
  -- map id source: Blizzard assigns exactly this when it uses the hybrid minimap
  -- (Blizzard_Minimap/Mainline/Minimap.lua, PLAYER_ENTERING_WORLD)
  if C_Minimap and C_Map and C_Map.GetBestMapForUnit and not self.uiMapOverride then
    self.uiMapOrig = C_Minimap.GetUiMapID
    self.uiMapOverride = function() return C_Map.GetBestMapForUnit("player") end
  end
  if self.uiMapOverride and C_Minimap.GetUiMapID ~= self.uiMapOverride then
    C_Minimap.GetUiMapID = self.uiMapOverride
  end
  local set = self.localTweaks
  if hm.Background then TAlpha(set, "hy.bg", hm.Background, 0) end      -- no black disc
  if not self.hybridMask then
    local m = hm:CreateMaskTexture()
    m:SetAllPoints(hm)
    self.hybridMask = m
    self.hybridMaskShape = nil
  end
  if self.hybridMaskShape ~= self.db.shape then
    self.hybridMask:SetTexture(MASK_PATHS[self.db.shape] or MASK_PATHS.rect, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    self.hybridMaskShape = self.db.shape
  end
  local mask = self.hybridMask
  TweakDo(set, "hy.mask", hm.MapCanvas,
    function(x) return x:GetMaskTexture() end,
    function(x)
      if x:GetMaskTexture() ~= mask then x:SetMaskTexture(mask) end
      if not x:GetUseMaskTexture() then x:SetUseMaskTexture(true) end
    end,
    function(x, orig) if orig then x:SetMaskTexture(orig) end end)
  hm:Enable()
  hm:CheckMap()
  if hm.mapID and hm.UpdateZoom then pcall(hm.UpdateZoom, hm) end
  self.hybridEnabled = true
  return true
end

function mod:HybridOff()
  TweakUndoPrefix(self.localTweaks, "hy.")
  local hm = G("HybridMinimap")
  if hm and self.hybridEnabled then
    local blizzardWants = false
    if C_Minimap and C_Minimap.ShouldUseHybridMinimap then
      local ok, v = pcall(C_Minimap.ShouldUseHybridMinimap)
      blizzardWants = ok and v and true or false
    end
    if not blizzardWants and hm.Disable then pcall(hm.Disable, hm) end
  end
  self.hybridEnabled = false
  if C_Minimap and self.uiMapOverride and C_Minimap.GetUiMapID == self.uiMapOverride then
    C_Minimap.GetUiMapID = self.uiMapOrig
  end
  self.uiMapOrig, self.uiMapOverride = nil, nil
end

-- Idempotent; follows db.ground and (for "auto") the indoors state.
function mod:ApplyGround()
  if not self.localOn then return end
  local want = self:WantHybrid()
  if want then
    local ok, why = self:HybridOn()
    if ok then
      self.groundNow = "hybrid"
      return
    end
    self.hybridBroken = true
    self:Note("hybrid ground", why)
    QB:Say("overlay: hybrid ground not available (" .. tostring(why) .. "); using the native ground (hard edge)")
  end
  if self.groundNow == "hybrid" or self.hybridEnabled then self:HybridOff() end
  self.groundNow = "native"
end

-- While hybrid is wanted the Blizzard frame must actually be shown; if it never shows
-- (no map art for this place) fall back to the native ground instead of an empty minimap.
function mod:VerifyGround()
  if self.groundNow ~= "hybrid" then return end
  local hm = G("HybridMinimap")
  if hm and hm:IsShown() then self.hybridFails = 0 return end
  if hm and hm.CheckMap then pcall(hm.CheckMap, hm) end
  self.hybridFails = (self.hybridFails or 0) + 1
  if self.hybridFails >= 8 then          -- ~2 s
    self.hybridFails = 0
    if self.db.ground == "hybrid" then
      QB:Say("overlay: the hybrid ground is not showing here; native ground for now (/qb overlay diag)")
    end
    self.hybridBroken = true
    self:HybridOff()
    self.groundNow = "native"
    if C_Minimap and C_Minimap.SetDrawGroundTextures then pcall(C_Minimap.SetDrawGroundTextures, true) end
  end
end

function mod:LocalEnter()
  local mm = G("Minimap")
  if not (mm and mm.SetParent and mm.SetMaskTexture) then
    QB:Say("overlay: native Minimap not available")
    return false
  end
  self:LayoutPanel()
  self.panel:Show()
  self.localOn = true       -- before the hooks can fire
  self:LocalUpdate()
  return true
end

function mod:LocalLeave()
  local mm = G("Minimap")
  self.localOn = false
  self.layouting = true
  local failed = TweakUndoAll(self.localTweaks)
  self:HybridOff()
  self.hybridBroken = false
  self.layouting = false
  if mm and mm.SetIconScale and self.iconApplied and self.iconApplied ~= 1 then
    pcall(mm.SetIconScale, mm, 1)
  end
  self.iconApplied = nil
  if mm and mm.SetMaskTexture then
    -- the stock mask is what Skin.lua installs; no getter exists to remember it
    self.maskSetting = true
    local ok, err = pcall(mm.SetMaskTexture, mm, STOCK_MASK)
    self.maskSetting = false
    if not ok then failed = failed + 1; self:Note("restore mask", err) end
  end
  if failed > 0 then
    self.localOn = true     -- keep the cleanup pending
    self.dirty = true
  end
end

-- ---------------------------------------------------------------- Zone layer (WorldMapFrame)

local function PlayerMapID()
  if MapUtil and MapUtil.GetDisplayableMapForPlayer then   -- (Blizzard_WorldMap.lua OnShow)
    local ok, id = pcall(MapUtil.GetDisplayableMapForPlayer)
    if ok and id then return id end
  end
  if C_Map and C_Map.GetBestMapForUnit then
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    if ok then return id end
  end
  return nil
end

mod.pinMouse = setmetatable({}, { __mode = "k" })   -- pin -> { click, motion }

function mod:PinDisable(pin)
  if not pin or not pin.SetMouseClickEnabled then return end
  if self.pinMouse[pin] == nil then
    self.pinMouse[pin] = { pin:IsMouseClickEnabled() and true or false, pin:IsMouseMotionEnabled() and true or false }
  end
  pin:SetMouseClickEnabled(false)
  pin:SetMouseMotionEnabled(false)
end

function mod:PinsRestore()
  for pin, rec in pairs(self.pinMouse) do
    pcall(pin.SetMouseClickEnabled, pin, rec[1])
    pcall(pin.SetMouseMotionEnabled, pin, rec[2])
    self.pinMouse[pin] = nil
  end
end

-- Soft edge for the Zone layer: MapCanvasMixin mask mechanism
-- (Blizzard_MapCanvas.lua SetMaskTexture / SetUseMaskTexture / AddMaskableTexture).
-- Only the map art (detail tiles + tiled background) is masked; pins are not.
function mod:ZoneApplyMask()
  local wmf = G("WorldMapFrame")
  local sc = wmf and wmf.ScrollContainer
  if not (sc and sc.CreateMaskTexture and wmf.SetMaskTexture and wmf.SetUseMaskTexture) then return false end
  local shape = self.db.shape
  if not self.zoneMask then
    local m = sc:CreateMaskTexture()
    m:SetAllPoints(sc)
    self.zoneMask = m
  end
  if self.zoneMaskShape ~= shape then
    self.zoneMask:SetTexture(MASK_PATHS[shape] or MASK_PATHS.rect, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    self.zoneMaskShape = shape
  end
  if wmf:GetMaskTexture() ~= self.zoneMask then
    wmf:SetMaskTexture(self.zoneMask)
    -- register textures that already exist (tiles built before the mask was set)
    local bg = sc.Child and sc.Child.TiledBackground
    if bg and wmf.AddMaskableTexture then wmf:AddMaskableTexture(bg) end
    if wmf.mapID and wmf.ForceRefreshDetailLayers then wmf:ForceRefreshDetailLayers() end
  end
  if not wmf:GetUseMaskTexture() then wmf:SetUseMaskTexture(true) end
  return true
end

function mod:ZoneRemoveMask()
  local wmf = G("WorldMapFrame")
  if wmf and wmf.GetMaskTexture and wmf:GetMaskTexture() and wmf.SetUseMaskTexture then
    wmf:SetUseMaskTexture(false)
  end
end

-- Idempotent: put the WorldMapFrame into the Zone look. Called after Show, from
-- hooks (Blizzard re-lays the frame out on Minimize/Maximize/panel updates) and
-- from the tick.
function mod:ZoneStyle()
  local wmf = G("WorldMapFrame")
  local sc = wmf and wmf.ScrollContainer
  if not sc then return end
  local set = self.zoneTweaks
  local db = self.db

  -- keep the fader from fighting our alpha (Blizzard_FrameXMLBase/PlayerMovementFrameFader.lua)
  if PlayerMovementFrameFader and PlayerMovementFrameFader.RemoveFrame then
    Try("fader", PlayerMovementFrameFader.RemoveFrame, wmf)
  end

  -- normalise the display state without touching the user's CVars:
  -- Minimize()/SetQuestLogPanelShown() are plain methods (Blizzard_WorldMap.lua,
  -- QuestLogOwnerMixin.lua); only HandleUserAction* write miniWorldMap/questLogOpen.
  if wmf.IsMaximized and wmf:IsMaximized() and wmf.Minimize then
    Try("Minimize", wmf.Minimize, wmf)
  end
  if wmf.QuestLog and wmf.QuestLog:IsShown() and wmf.SetQuestLogPanelShown then
    Try("hide quest log", wmf.SetQuestLogPanelShown, wmf, false)
  end

  -- chrome: border/portrait/title, background, navbar + overlay buttons
  if wmf.BlackoutFrame then TShown(set, "z.blackout", wmf.BlackoutFrame, false) end
  local border = wmf.BorderFrame
  if border then
    TShown(set, "z.border", border, false)
    -- Bg is re-parented to the map frame by SetupTitle, so hiding BorderFrame does not hide it
    if border.Bg then TShown(set, "z.bg", border.Bg, false) end
  end
  if wmf.OverscrollBG then TShown(set, "z.overscroll", wmf.OverscrollBG, false) end
  if type(wmf.overlayFrames) == "table" then
    for i, f in ipairs(wmf.overlayFrames) do TShown(set, "z.overlay" .. i, f, false) end
  end

  -- look: translucent, behind the Local layer and the HUD
  TAlpha(set, "z.alpha.wmf", wmf, 1)
  TAlpha(set, "z.alpha.sc", sc, clamp(tonumber(db.zoneAlpha) or 0.45, 0, 1))
  TStrata(set, "z.strata", wmf, "BACKGROUND")

  -- click-through (pins are handled in PinDisable)
  TMouse(set, "z.mouse.wmf", wmf, false)
  TMouse(set, "z.mouse.sc", sc, false)
  TWheel(set, "z.wheel.sc", sc, false)

  -- geometry: the map frame has the panel's size and the scroll container fills it
  -- (drops the 67px title strip, TITLE_CANVAS_SPACER_FRAME_HEIGHT in Blizzard_WorldMap.lua)
  local panel = self.panel
  if panel then
    local w, h = panel:GetSize()
    local resized = false
    TweakDo(set, "z.size", wmf,
      function(x) local a, b = x:GetSize() return { a, b } end,
      function(x)
        local cw, ch = x:GetSize()
        if math.abs(cw - w) > 0.5 or math.abs(ch - h) > 0.5 then
          x:SetSize(w, h)
          resized = true
        end
      end,
      function(x, orig) x:SetSize(orig[1], orig[2]) end)
    TPoints(set, "z.points", wmf, { { "CENTER", panel, "CENTER", 0, 0 } })
    TPoints(set, "z.sc.points", sc, {
      { "TOPLEFT", wmf, "TOPLEFT", 0, 0 },
      { "BOTTOMRIGHT", wmf, "BOTTOMRIGHT", 0, 0 },
    })
    if resized then
      if wmf.OnFrameSizeChanged then Try("OnFrameSizeChanged", wmf.OnFrameSizeChanged, wmf) end
      self.zoomDirty = true
    end
  end

  Try("zone mask", self.ZoneApplyMask, self)

  -- pins: stay visible, stop catching the mouse
  if wmf.ExecuteOnAllPins then
    Try("pins", wmf.ExecuteOnAllPins, wmf, function(pin) mod:PinDisable(pin) end)
  end
end

function mod:ReapplyZone()
  if not (self.zoneOn and self.zoneReady) or self.zoneApplying then return end
  if QB:InCombat() then self.zoneDirty = true; return end
  self.zoneApplying = true
  local ok, err = pcall(self.ZoneStyle, self)
  self.zoneApplying = false
  if not ok then QB:ReportError(self.name, err) end
end

-- Keep the Zone layer on the player's zone and centred on the player.
function mod:TickZone()
  local wmf = G("WorldMapFrame")
  local sc = wmf and wmf.ScrollContainer
  if not (sc and wmf:IsShown()) then return end
  self:ReapplyZone()

  local mapID = PlayerMapID()
  if mapID and wmf.GetMapID and wmf:GetMapID() ~= mapID then
    wmf:SetMapID(mapID)
    self.zoomDirty = true
  end
  mapID = wmf:GetMapID()

  local sw = sc:GetWidth()
  if sw ~= self.lastSW then
    self.lastSW = sw
    if wmf.OnFrameSizeChanged then Try("OnFrameSizeChanged", wmf.OnFrameSizeChanged, wmf) end
    self.zoomDirty = true
  end

  if not (mapID and sc.HasZoomLevels and sc:HasZoomLevels()) then return end
  if not (C_Map and C_Map.GetPlayerMapPosition) then return end
  local okp, pos = pcall(C_Map.GetPlayerMapPosition, mapID, "player")
  if not (okp and pos and pos.GetXY) then return end
  local px, py = pos:GetXY()
  if not (px and py) then return end

  local minS, maxS = sc:GetScaleForMinZoom(), sc:GetScaleForMaxZoom()
  local want = clamp(minS * (tonumber(self.db.zoneZoom) or 2), minS, maxS)
  local cur = sc:GetCanvasScale()
  if self.zoomDirty or math.abs(cur - want) > want * 0.01 then
    self.zoomDirty = false
    sc:InstantPanAndZoom(want, px, py, true)         -- (MapCanvas_ScrollContainerMixin.lua)
  else
    local x0, x1, y0, y1 = sc:CalculateScrollExtentsAtScale(cur)
    sc:SetPanTarget(clamp(px, x0, x1), clamp(py, y0, y1))   -- eased by the container's own OnUpdate
  end
end

function mod:InstallZoneHooks()
  if self.zoneHooked then return end
  local wmf = G("WorldMapFrame")
  if not wmf then return end
  self.zoneHooked = true
  local function reapply() if mod.active then mod:ReapplyZone() end end
  -- Blizzard re-lays the frame out in these; re-apply right after, same frame
  for _, m in ipairs({ "Minimize", "Maximize", "SynchronizeDisplayState", "RefreshOverlayFrames",
                       "SetQuestLogPanelShown", "UpdateSpacerFrameAnchoring" }) do
    SafeHook(wmf, m, reapply)
  end
  -- the UI panel manager re-anchors panels in here (Blizzard_Minimap.lua calls it too)
  SafeHook("UpdateUIPanelPositions", reapply)
  -- new / reused pins
  SafeHook(wmf, "RegisterPin", function(_, pin)
    if mod.active and mod.zoneOn and mod.zoneReady then Try("pin", mod.PinDisable, mod, pin) end
  end)
  -- Blizzard (ESC, another panel, the M key) closed the map behind our back
  if wmf.HookScript then
    pcall(wmf.HookScript, wmf, "OnHide", function()
      if mod.active and mod.zoneOn and mod.zoneReady and not mod.zoneLeaving then
        QB:Safe(mod, mod.OnZoneClosedExternally, mod)
      end
    end)
  end
end

function mod:OnZoneClosedExternally()
  QB:Say("overlay: the game closed the map; overlay off")
  self:SetState("off", true)
end

function mod:ZoneEnter()
  local wmf = G("WorldMapFrame")
  if not (wmf and wmf.ScrollContainer and wmf.SetMapID and wmf.GetMaskTexture) then
    QB:Say("overlay: the world map frame is not available (/qb overlay diag)")
    return false
  end
  self:InstallZoneHooks()
  self.zoneOn = true
  self.zoneReady = false          -- hooks stay quiet while Blizzard's own OnShow runs
  self.zoomDirty = true
  self.lastSW = nil
  -- UI panel path: the same one the M key uses (OpenWorldMap -> ShowUIPanel, Blizzard_WorldMap.lua)
  if not wmf:IsShown() then
    if type(ShowUIPanel) == "function" then
      Try("ShowUIPanel", ShowUIPanel, wmf)
    end
    if not wmf:IsShown() then Try("Show", wmf.Show, wmf) end
  end
  if not wmf:IsShown() then
    self.zoneOn = false
    QB:Say("overlay: could not show the world map (/qb overlay diag)")
    return false
  end
  -- OnShow makes the character play the READ emote (Blizzard_WorldMap.lua); cancel it
  if C_ChatInfo and C_ChatInfo.CancelEmote then Try("CancelEmote", C_ChatInfo.CancelEmote) end
  self.zoneReady = true
  self:ReapplyZone()
  return true
end

function mod:ZoneLeave()
  local wmf = G("WorldMapFrame")
  self.zoneOn = false
  self.zoneReady = false
  self.zoneLeaving = true
  Try("remove mask", self.ZoneRemoveMask, self)
  self:PinsRestore()
  if wmf and wmf:IsShown() then
    if type(HideUIPanel) == "function" then Try("HideUIPanel", HideUIPanel, wmf) end
    if wmf:IsShown() then Try("Hide", wmf.Hide, wmf) end
  end
  local failed = TweakUndoAll(self.zoneTweaks)
  self.zoneLeaving = false
  if failed > 0 then
    self.zoneOn = true         -- keep cleanup pending, retried on PLAYER_REGEN_ENABLED
    self.dirty = true
  end
end

-- ---------------------------------------------------------------- bars

-- Action bars are faded to alpha 0 (not hidden): SetAlpha is not protected, so it is also
-- safe to undo from the combat-start path, and Edit Mode keeps its own show/hide state.
function mod:ApplyBars(on)
  local set = self.barTweaks
  local mode = self.db.bars
  if not on or mode == "none" then
    if #set.order > 0 then TweakUndoAll(set) end
    return
  end
  local lists = { BAR_FRAMES.actions }
  if mode == "all" then lists[#lists + 1] = BAR_FRAMES.status end
  local found = 0
  for _, list in ipairs(lists) do
    for _, name in ipairs(list) do
      local f = G(name)
      if f and f.SetAlpha then
        TAlpha(set, "bar." .. name, f, 0)
        found = found + 1
      end
    end
  end
  self.barsFound = found
end

-- ---------------------------------------------------------------- state machine

function mod:Apply(target)
  self.mode = target
  local needLocal = target == "local"
  local needZone = target == "zone"
  local panel = self:EnsurePanel()

  if self.zoneOn and not needZone then self:ZoneLeave() end
  if self.localOn and not needLocal then self:LocalLeave() end
  self:LayoutPanel()                      -- the panel is square for "local", `aspect` for "zone"
  if needLocal then
    if not self.localOn then
      if not self:LocalEnter() then target = "off" end
    else
      self:LocalUpdate()
    end
  elseif needZone then
    if not self.zoneOn then
      if not self:ZoneEnter() then target = "off" end
    else
      self:ReapplyZone()
    end
  end

  local achieved = "off"
  if self.localOn then achieved = "local" elseif self.zoneOn then achieved = "zone" end
  if target == "off" then achieved = "off" end   -- a failed cleanup is retried via self.dirty
  self.state = achieved
  self.mode = achieved
  self:ApplyRotation()
  self:ApplyBars(achieved ~= "off")

  if self.localOn or self.zoneOn then
    panel:SetScript("OnUpdate", function(_, elapsed)
      mod.acc = (mod.acc or 0) + elapsed
      if mod.acc < TICK then return end
      mod.acc = 0
      QB:Safe(mod, mod.Tick, mod)
    end)
    panel:Show()
  else
    panel:SetScript("OnUpdate", nil)
    panel:Hide()
  end
end

function mod:SetState(state, force)
  if state ~= "off" and state ~= "local" and state ~= "zone" then return false end
  if state ~= "off" and not force and self.db.combatGuard and QB:InCombat() then
    QB:Say("map overlay: not in combat")
    return false
  end
  local prev = self.state
  self:Apply(state)
  if self.state ~= prev then QB:Fire("overlay_state", self.state) end
  return self.state == state
end

function mod:GetState() return self.state end

function mod:Cycle()
  if self.db.combatGuard and QB:InCombat() then
    QB:Say("map overlay: not in combat")
    return
  end
  self:SetState(NEXT[self.state] or "off")
end

-- Restore everything, then open Blizzard's normal world map (it must look normal).
function mod:OpenFull()
  self:SetState("off", true)
  local wmf = G("WorldMapFrame")
  if wmf and wmf:IsShown() then return end
  if type(ToggleWorldMap) == "function" then       -- (Blizzard_WorldMap.lua)
    ToggleWorldMap()
  elseif wmf and type(ShowUIPanel) == "function" then
    ShowUIPanel(wmf)
  end
end

-- ---------------------------------------------------------------- tick / verify

function mod:Tick()
  if QB:InCombat() then return end
  if self.dirty then          -- a cleanup failed earlier; retry out of combat
    self.dirty = false
    self:Apply(self.state)
    return
  end
  if self.localOn and self.state ~= "off" then
    local mm = G("Minimap")
    if mm and (self.layoutDirty or mm:GetParent() ~= self.panel
        or math.abs(mm:GetAlpha() - clamp(tonumber(self.db.localAlpha) or 0.55, 0, 1)) > 0.01) then
      self:LocalUpdate()
    end
    -- something (Edit Mode layout apply) may have flipped the CVar back
    if self.rotWanted and GetC(ROTATE_CVAR) ~= self.rotWanted then
      self.rotFixes = (self.rotFixes or 0) + 1
      if self.rotFixes <= 5 then
        SetC(ROTATE_CVAR, self.rotWanted)
        self:ApplyMinimapMask()
      end
    else
      self.rotFixes = 0
    end
  end
  if self.state ~= "off" then self:ApplyBars(true) end     -- Blizzard code may set the alpha back
  if self.localOn then
    if self.db.ground == "auto" then self:ApplyGround() end
    self:VerifyGround()
  end
  if self.zoneOn and self.state == "zone" then self:TickZone() end
end

-- ---------------------------------------------------------------- hooks / cluster

function mod:HideCluster()
  local c = G("MinimapCluster")
  if not c then return end
  if self.clusterWas == nil then self.clusterWas = c:IsShown() and true or false end
  if c:IsShown() then
    self.hidingCluster = true
    pcall(c.Hide, c)
    self.hidingCluster = false
  end
end

function mod:ShowCluster()
  local c = G("MinimapCluster")
  if c and self.clusterWas then
    self.restoringCluster = true
    pcall(c.Show, c)
    self.restoringCluster = false
  end
  self.clusterWas = nil
end

function mod:InstallHooks()
  if self.hooked then return end
  self.hooked = true
  local c = G("MinimapCluster")
  if c then
    -- Blizzard / Edit Mode may re-show the retired cluster
    local function rehide()
      if mod.active and not mod.restoringCluster and not mod.hidingCluster and c:IsShown() then
        mod:HideCluster()
      end
    end
    SafeHook(c, "Show", rehide)
    SafeHook(c, "SetShown", rehide)
  end
  local mm = G("Minimap")
  if mm then
    -- Skin.lua reinstalls the stock mask whenever rotateMinimap changes
    SafeHook(mm, "SetMaskTexture", function(_, asset)
      if mod.active and mod.localOn and not mod.maskSetting and asset ~= mod.wantMask then
        mod:ApplyMinimapMask()
      end
    end)
    -- UNVERIFIED: whether Blizzard code ever re-anchors the Minimap; flag and let the tick fix it
    local function dirty() if mod.active and mod.localOn and not mod.layouting then mod.layoutDirty = true end end
    for _, m in ipairs({ "SetPoint", "ClearAllPoints", "SetParent", "SetSize", "SetAlpha" }) do
      SafeHook(mm, m, dirty)
    end
  end
  -- the toggle key on the world map is left to Blizzard (M while in "zone")
end

-- ---------------------------------------------------------------- lifecycle

function mod:OnInit()
  if type(CreateFrame) ~= "function" or not UIParent then
    self.unavailable = "no UI"
    return
  end
  local mm = G("Minimap")
  if not (mm and mm.SetMaskTexture and mm.SetParent) then
    self.unavailable = "native Minimap widget missing"
    return
  end
end

function mod:OnEnable()
  self.state = "off"
  self:EnsurePanel()
  self:LayoutPanel()
  -- previous session ended with the overlay open: put the user's rotation back
  if self.db.rotateBackup ~= nil then
    if SetC(ROTATE_CVAR, self.db.rotateBackup) then self.db.rotateBackup = nil end
  end
  self:InstallHooks()
  self:HideCluster()
end

function mod:OnDisable()
  self:SetState("off", true)
  self:ShowCluster()
end

-- ---------------------------------------------------------------- events

mod.events.PLAYER_REGEN_ENABLED = function(self)
  if self.dirty then
    self.dirty = false
    self:Apply(self.state)
  end
  if self.zoneDirty then
    self.zoneDirty = false
    self:ReapplyZone()
  end
end
mod.events.ZONE_CHANGED_INDOORS = function(self) if self.localOn then self:ApplyGround() end end
mod.events.DISPLAY_SIZE_CHANGED = function(self) self:Layout() end
mod.events.UI_SCALE_CHANGED = function(self) self:Layout() end
mod.events.EDIT_MODE_LAYOUTS_UPDATED = function(self) self:HideCluster() end
-- make sure the saved CVar holds the user's value, not ours
mod.events.PLAYER_LOGOUT = function(self) self:SetState("off", true) end

function mod:OnCombatStart()
  if not self.db.combatGuard then return end
  if self.state ~= "off" or self.localOn or self.zoneOn then
    -- Deviation from "no changes in combat": the frames involved (Minimap, WorldMapFrame,
    -- MinimapCluster) are not protected; every step is pcall-guarded and anything that
    -- fails is retried on PLAYER_REGEN_ENABLED.
    self:SetState("off", true)
    QB:Say("map overlay closed for combat")
  end
end

QB:On("combat_start", function() mod:OnCombatStart() end, mod)
QB:On("open_full", function() mod:OpenFull() end, mod)

-- ---------------------------------------------------------------- slash

local function Status()
  local db = mod.db
  local s = string.format(
    "overlay: %s | shape=%s size=%.2f pos=%.2f,%.2f zone-aspect=%.2f alpha=%.2f/%.2f zonezoom=%.1f rotate=%s ground=%s(now %s) bars=%s icons=%.1f mask=%s",
    mod.state, db.shape, db.size, db.offsetX, db.offsetY, db.aspect, db.localAlpha, db.zoneAlpha,
    db.zoneZoom, db.rotate and "on" or "off", db.ground, mod.groundNow, db.bars, db.iconScale, mod.maskMode)
  if mod.lastError then s = s .. " | last error: " .. mod.lastError end
  return s
end

local function Fmt(v)
  if type(v) == "number" then return string.format("%.2f", v) end
  return tostring(v)
end

local function FrameLine(label, f)
  if not f then return label .. ": missing" end
  local parts = { label .. ":" }
  local function add(name, fn)
    if type(f[fn]) == "function" then
      local ok, a, b = pcall(f[fn], f)
      if ok then parts[#parts + 1] = name .. "=" .. Fmt(a) .. ((b ~= nil and type(b) == "number") and ("x" .. Fmt(b)) or "") end
    end
  end
  add("shown", "IsShown"); add("visible", "IsVisible"); add("alpha", "GetAlpha"); add("effAlpha", "GetEffectiveAlpha")
  add("size", "GetSize"); add("strata", "GetFrameStrata"); add("level", "GetFrameLevel"); add("scale", "GetScale")
  local okp, parent = pcall(f.GetParent, f)
  if okp and parent and parent.GetName then parts[#parts + 1] = "parent=" .. tostring(parent:GetName() or "?") end
  return table.concat(parts, " ")
end

-- /qb overlay diag: the facts needed to debug what the client does (paste it back).
local function Diag()
  QB:Say(Status())
  QB:Say(FrameLine("Minimap", G("Minimap")))
  local mm = G("Minimap")
  if mm and mm.GetZoom then
    local ok, z = pcall(mm.GetZoom, mm)
    QB:Say("Minimap zoom=" .. tostring(ok and z or "?") .. " rotateMinimap=" .. tostring(GetC(ROTATE_CVAR)))
  end
  if C_Minimap then
    local function q(name)
      if not C_Minimap[name] then return "n/a" end
      local ok, v = pcall(C_Minimap[name])
      return ok and tostring(v) or "error"
    end
    QB:Say("C_Minimap: ShouldUseHybrid=" .. q("ShouldUseHybridMinimap") .. " GetDrawGroundTextures=" .. q("GetDrawGroundTextures")
      .. " GetUiMapID=" .. q("GetUiMapID") .. " IsIndoors=" .. (type(IsIndoors) == "function" and tostring(IsIndoors()) or "n/a"))
  end
  local hm = G("HybridMinimap")
  QB:Say(hm and (FrameLine("HybridMinimap", hm) .. " mapID=" .. tostring(hm.mapID) .. " enabledByUs=" .. tostring(mod.hybridEnabled)
    .. " broken=" .. tostring(mod.hybridBroken)) or "HybridMinimap: not loaded")
  local wmf = G("WorldMapFrame")
  QB:Say(FrameLine("WorldMapFrame", wmf) .. " mapID=" .. tostring(wmf and wmf.GetMapID and wmf:GetMapID()))
  if wmf and wmf.ScrollContainer then QB:Say(FrameLine("  ScrollContainer", wmf.ScrollContainer)) end
  QB:Say("bars: mode=" .. tostring(mod.db.bars) .. " frames faded=" .. tostring(#mod.barTweaks.order)
    .. " (found " .. tostring(mod.barsFound or 0) .. ")")
  if mod.lastError then QB:Say("last error: " .. mod.lastError) end
end

QB:RegisterSlash(mod, "overlay", function(rest)
  local sub, arg = (rest or ""):match("^(%S*)%s*(.-)$")
  sub = (sub or ""):lower()
  arg = (arg or ""):lower()
  local db = mod.db
  local a, b = arg:match("^(%S+)%s*(%S*)$")
  local n1, n2 = tonumber(a), tonumber(b)

  if sub == "cycle" then
    mod:Cycle()
  elseif sub == "off" or sub == "local" or sub == "zone" then
    mod:SetState(sub)
  elseif sub == "minimap" then
    mod:SetState("local")
  elseif sub == "map" then
    mod:SetState("zone")
  elseif sub == "both" then
    QB:Say("'both' was removed: the minimap and the map are separate modes now (local | zone)")
  elseif sub == "shape" and (arg == "rect" or arg == "circle") then
    db.shape = arg
    mod:Layout()
    if mod.localOn then mod:ApplyMinimapMask(); mod:ApplyGround() end
  elseif sub == "size" and n1 then
    if n1 > 1.5 then n1 = n1 / 100 end      -- allow percent
    db.size = clamp(n1, 0.1, 1.5)
    mod:Layout()
  elseif sub == "aspect" and n1 then
    db.aspect = clamp(n1, 0.5, 3)
    mod:Layout()
  elseif sub == "pos" and n1 and n2 then
    db.offsetX = clamp(n1, -1, 1)
    db.offsetY = clamp(n2, -1, 1)
    mod:Layout()
  elseif sub == "alpha" and n1 then
    db.localAlpha = clamp(n1, 0, 1)
    if n2 then db.zoneAlpha = clamp(n2, 0, 1) end
    mod:Layout()
  elseif sub == "zoom" and n1 then
    db.zoneZoom = clamp(n1, 1, 8)
    mod.zoomDirty = true
  elseif sub == "rotate" and (arg == "on" or arg == "off") then
    db.rotate = (arg == "on")
    mod:ApplyRotation()
    if mod.localOn then mod:ApplyMinimapMask() end
  elseif sub == "ground" and (arg == "hybrid" or arg == "native" or arg == "auto") then
    db.ground = arg
    mod.hybridBroken = false
    if mod.localOn then mod:ApplyGround() end
  elseif sub == "bars" and (arg == "actions" or arg == "all" or arg == "none") then
    mod:ApplyBars(false)
    db.bars = arg
    mod:ApplyBars(mod.state ~= "off")
  elseif sub == "icons" and n1 then
    db.iconScale = clamp(n1, 0.5, 4)
    if mod.localOn then mod:ApplyIconScale() end
  elseif sub == "mask" then
    -- debug: compare our soft-alpha mask with Blizzard's stock mask in the client
    mod.maskMode = (mod.maskMode == "ours") and "stock" or "ours"
    if mod.localOn then mod:ApplyMinimapMask() end
    QB:Say("overlay mask: " .. mod.maskMode .. " (" .. tostring(mod.maskMode == "stock" and STOCK_MASK or MASK_PATHS[db.shape]) .. ")")
  elseif sub == "diag" then
    Diag()
    return
  elseif sub ~= "" and sub ~= "status" then
    QB:Say("/qb overlay cycle | off | local | zone | shape rect|circle | size <n> | aspect <n> | pos <x> <y> | alpha <local> [zone] | zoom <n> | rotate on|off | ground hybrid|native|auto | bars actions|all|none | icons <n> | mask | diag")
  end
  QB:Say(Status())
end, "map overlay (cycle | off | local | zone | shape | size | alpha | rotate | ground | bars | icons | mask | diag)")
