-- QuestBook Drawers -- the collapsible Menu panel (micro menu + bag bar).
--
-- Approach A: Blizzard's OWN frames are re-parented/re-anchored into one panel of ours,
-- nothing is recreated, so alert pulses (unspent talents, ...) and drag-and-drop of bags
-- onto the bag slots keep working while the panel is open.
--
--   MicroMenu  (parent MicroMenuContainer)   Blizzard_MicroMenu/Camelot/MainMenuBarMicroMenu.xml
--   BagsBar    (parent UIParent)             Blizzard_MainMenuBarBagButtons/Camelot/MainMenuBarBagButtons.xml
--     children: MainMenuBarBackpackButton, BagSlotCluster (CharacterBag0..3Slot,
--     BagBarExpandToggle, reagent bag slot), KeyRingButton -- they move with BagsBar.
--
-- WHY WE MOVE MicroMenu AND NOT MicroMenuContainer (deviation from the first brief):
-- MicroMenuContainer is the Edit Mode system frame (EditModeMicroMenuSystemTemplate,
-- Blizzard_MicroMenu/Mainline/MicroMenuContainer.xml); Edit Mode re-applies its saved
-- anchor in ApplySystemAnchor (Blizzard_EditMode/Shared/EditModeSystemTemplates.lua) and
-- MainActionBar is anchored to it in Camelot (Blizzard_EditMode/Camelot/EditModeUtil.lua).
-- Blizzard supports a micro menu that lives somewhere else: MicroMenuMixin:AnchorToMenuContainer
-- and MicroMenuContainerMixin:Layout both return early when MicroMenu:GetParent() ~=
-- MicroMenuContainer ("temporarily being overridden", Blizzard_MicroMenu/Shared/
-- MicroMenuContainer.lua). So we leave the container exactly where Edit Mode wants it and
-- there is no container position to fight.
--
-- WHAT STILL FIGHTS US, and how it is handled (all hooks are hooksecurefunc post-hooks and are
-- inert while the module is off; a re-entrancy flag `busy` stops any recursion):
--   * MainActionBarMixin:OnShow calls MicroMenu:ResetMicroMenuPosition(), which does
--     MicroMenu:SetParent(MicroMenuContainer) (Blizzard_ActionBar/Shared/MainActionBar.lua).
--     -> hooks on MicroMenu.ResetMicroMenuPosition, .SetParent, .SetPoint re-assert our
--        parent + anchor. The re-assert inside the SetParent hook runs before Reset's next
--        step, so the container's Layout already sees the new parent and returns early.
--   * Edit Mode re-applies the BagsBar anchor (EditModeSystemMixin:ApplySystemAnchor ->
--     ClearAllPoints + SetPoint, on login via EDIT_MODE_LAYOUTS_UPDATED and on layout change).
--     -> hooks on BagsBar.SetPoint / .SetParent re-assert, plus an EDIT_MODE_LAYOUTS_UPDATED
--        handler that re-asserts a frame and half a second later.
--   Edit Mode system frames replace SetPoint/ClearAllPoints with *Override versions that also
--   record "snapped to frame" state; we deliberately call the saved originals
--   (SetPointBase / ClearAllPointsBase) when they exist so Edit Mode's snap bookkeeping is
--   never touched, and the same originals restore the anchor on disable.
--
-- COMBAT: nothing is reparented/anchored while QB:InCombat(); the work is flagged pending
-- and done on PLAYER_REGEN_ENABLED (drawers.events). Hiding our own panel in combat is fine
-- and happens on the bus topic "combat_start".
--
-- Bus: listens to "strip_state" (true/false) from modules/Strip.lua to know whether the strip's
-- Menu handle exists; when it does not, drawers makes a tiny handle of its own at the
-- top right of UIParent.

local ADDON, QB = ...

local drawers = QB:NewModule("drawers", {
  moveMicro = true,   -- bring MicroMenu into the panel
  moveBags = true,    -- bring BagsBar into the panel
  hideArt = true,     -- hide Blizzard's ornate frame art (BorderArt/BackgroundArt) inside the panel
  pad = 12,           -- panel padding
  gap = 6,            -- space between the two rows
  fallbackX = -24,    -- own handle position when the strip is absent (TOPRIGHT of UIParent)
  fallbackY = -14,
})

local FONT = "Fonts\\FRIZQT__.TTF"
local COLOR = { 0.85, 0.82, 0.72 }
local COLOR_HOT = { 1.00, 0.96, 0.82 }

-- ---------------------------------------------------------------- targets

-- Row order = top to bottom. `art` lists parentKey textures of the Blizzard frame that are
-- hidden (and restored) when db.hideArt is on: MicroMenu.BorderArt/.BackgroundArt
-- (Camelot/MainMenuBarMicroMenu.xml), BagsBar.BorderArt (Camelot/MainMenuBarBagButtons.xml).
local TARGETS = {
  { key = "micro", global = "MicroMenu", setting = "moveMicro", art = { "BorderArt", "BackgroundArt" } },
  { key = "bags", global = "BagsBar", setting = "moveBags", art = { "BorderArt" } },
}
-- per target at runtime: frame, orig (recorded original state), moved, hooked, note

local panel = nil           -- our Frame
local fallback = nil        -- our own Menu handle, only when the strip is absent
local engaged = false       -- true between OnEnable and OnDisable (hooks check this, not mod.active)
local busy = false          -- re-entrancy guard
local pending = false       -- work postponed because of combat
local stripOn = false       -- is the strip module's Menu handle available
local measureQueued = false
local restoreFrame = nil    -- tiny always-on frame to finish a restore after combat

-- ---------------------------------------------------------------- small helpers

local function SetColor(fs, c) fs:SetTextColor(c[1], c[2], c[3]) end

local function ResolveFrame(T)
  local f = _G[T.global]
  if type(f) == "table" and type(f.SetParent) == "function" and type(f.GetNumPoints) == "function" then
    return f
  end
  return nil
end

-- Edit Mode system frames save the original methods as *Base; use them when present.
local function ClearPts(f)
  local fn = f.ClearAllPointsBase or f.ClearAllPoints
  fn(f)
end

local function SetPt(f, ...)
  local fn = f.SetPointBase or f.SetPoint
  fn(f, ...)
end

local function Record(f, T)
  local o = {
    parent = f:GetParent(),
    strata = f:GetFrameStrata(),
    level = f:GetFrameLevel(),
    points = {},
    art = {},
  }
  for i = 1, f:GetNumPoints() do
    local point, rel, relPoint, x, y = f:GetPoint(i)
    o.points[i] = { point, rel, relPoint, x, y }
  end
  for _, key in ipairs(T.art) do
    local t = f[key]
    if type(t) == "table" and type(t.IsShown) == "function" then
      o.art[key] = t:IsShown() and true or false
    end
  end
  return o
end

local function Close(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.05 end

local function IsAnchored(f, point, rel, relPoint, x, y)
  if f:GetNumPoints() ~= 1 then return false end
  local p, r, rp, ox, oy = f:GetPoint(1)
  return p == point and r == rel and rp == relPoint and Close(ox, x) and Close(oy, y)
end

-- ---------------------------------------------------------------- layout

local function Extent(T)
  local f = T.frame
  if not (T.moved and f and f:IsShown()) then return 0, 0 end
  local s = f:GetScale() or 1
  return (f:GetWidth() or 0) * s, (f:GetHeight() or 0) * s
end

-- Panel size from the contents' real size (scale-aware). Only touches OUR frame, so it is
-- safe at any time including combat.
local function Measure()
  if not panel then return end
  local db = drawers.db
  local pad, gap = db.pad, db.gap
  local mw, mh = Extent(TARGETS[1])
  local bw, bh = Extent(TARGETS[2])
  local w = math.max(mw, bw)
  local h = mh + bh + ((mh > 0 and bh > 0) and gap or 0)
  if w <= 0 or h <= 0 then w, h = 60, 16 end
  local newW, newH = w + 2 * pad, h + 2 * pad
  if math.abs(panel:GetWidth() - newW) > 0.5 or math.abs(panel:GetHeight() - newH) > 0.5 then
    panel:SetSize(newW, newH)
  end
end

local function ScheduleMeasure()
  if measureQueued or not C_Timer or not C_Timer.After then return end
  measureQueued = true
  C_Timer.After(0, function()
    measureQueued = false
    if engaged then QB:Safe(drawers, Measure) end
  end)
end

-- Where a target should sit. Rows are right-aligned (the panel hangs under a handle at the
-- right end of the strip). The bag row hangs under the micro row when that is present.
local function Desired(T)
  local f = T.frame
  local db = drawers.db
  local s = f:GetScale() or 1
  if s <= 0 then s = 1 end
  local micro = TARGETS[1]
  if T.key ~= "micro" and micro.moved and micro.frame and micro.frame:IsShown() then
    return "TOPRIGHT", micro.frame, "BOTTOMRIGHT", 0, -db.gap / s
  end
  return "TOPRIGHT", panel, "TOPRIGHT", -db.pad / s, -db.pad / s
end

-- ---------------------------------------------------------------- hooks

local ApplyAll   -- forward

local function Touched()
  if engaged and not busy then QB:Safe(drawers, ApplyAll) end
end

local function InstallHooks(T, f)
  if T.hooked then return end
  T.hooked = true
  if type(hooksecurefunc) ~= "function" then return end
  pcall(hooksecurefunc, f, "SetParent", Touched)
  pcall(hooksecurefunc, f, "SetPoint", Touched)
  if type(f.ResetMicroMenuPosition) == "function" then
    pcall(hooksecurefunc, f, "ResetMicroMenuPosition", Touched)
  end
  -- Blizzard resizes both frames from their own Layout; OnSizeChanged catches that even where
  -- Layout was registered as a callback by function reference (EventRegistry in BagsBar.lua)
  if type(f.HookScript) == "function" then
    pcall(f.HookScript, f, "OnSizeChanged", function()
      if engaged then ScheduleMeasure() end
    end)
  end
end

-- ---------------------------------------------------------------- move / restore

local function Ensure(T)
  if not drawers.db[T.setting] then return end
  local f = ResolveFrame(T)
  if not f then
    T.note = "frame '" .. T.global .. "' not found on this client"
    return
  end
  if not T.orig then
    T.orig = Record(f, T)
    T.frame = f
  end
  if f:GetParent() ~= panel then f:SetParent(panel) end
  local point, rel, relPoint, x, y = Desired(T)
  if not IsAnchored(f, point, rel, relPoint, x, y) then
    ClearPts(f)
    SetPt(f, point, rel, relPoint, x, y)
  end
  if drawers.db.hideArt then
    for _, key in ipairs(T.art) do
      local t = f[key]
      if type(t) == "table" and type(t.Hide) == "function" and t:IsShown() then t:Hide() end
    end
  end
  T.moved = true
  T.note = "re-anchored into the panel"
  InstallHooks(T, f)
end

local function RestoreOne(T)
  local f, o = T.frame, T.orig
  T.moved, T.orig = false, nil
  if not (f and o) then return end
  pcall(function()
    f:SetParent(o.parent)
    ClearPts(f)
    for _, p in ipairs(o.points) do
      SetPt(f, p[1], p[2] or o.parent, p[3], p[4], p[5])
    end
    f:SetFrameStrata(o.strata)
    f:SetFrameLevel(o.level)
    for key, wasShown in pairs(o.art) do
      local t = f[key]
      if type(t) == "table" then
        if wasShown then t:Show() else t:Hide() end
      end
    end
  end)
  T.note = "restored"
end

local function RestoreAll()
  busy = true
  for _, T in ipairs(TARGETS) do RestoreOne(T) end
  -- let the container recompute its size now that the micro menu is back in it
  -- (UNVERIFIED: probably unnecessary, Blizzard re-layouts on its next pass anyway)
  local c = _G.MicroMenuContainer
  if type(c) == "table" and type(c.Layout) == "function" then pcall(c.Layout, c) end
  busy = false
end

local function DoApply()
  for _, T in ipairs(TARGETS) do
    if drawers.db[T.setting] then
      Ensure(T)
    elseif T.orig then
      RestoreOne(T)   -- the user switched this part off in the settings
    end
  end
  Measure()
end

-- Idempotent: safe to call from hooks, events, enable and open.
ApplyAll = function()
  if not engaged or busy or not panel then return end
  if QB:InCombat() then
    pending = true
    return
  end
  busy = true
  local ok, err = pcall(DoApply)
  busy = false
  if not ok then error(err, 0) end   -- QB:Safe reports it once
end

local function Later(delay)
  if C_Timer and C_Timer.After then
    C_Timer.After(delay, function() QB:Safe(drawers, ApplyAll) end)
  end
end

-- ---------------------------------------------------------------- handles

local function StripHandle()
  local s = QB.modules.strip
  if stripOn and s and type(s.GetMenuHandle) == "function" then
    return s:GetMenuHandle()
  end
  return nil
end

-- The Menu handle the panel hangs from: the strip's, else our own (created on first need).
local function CurrentHandle()
  local h = StripHandle()
  if h then return h, false end
  if not fallback then
    local b = CreateFrame("Button", nil, UIParent)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(20)
    b:RegisterForClicks("LeftButtonUp")
    local fs = b:CreateFontString(nil, "OVERLAY")
    fs:SetFont(FONT, 12, "")
    SetColor(fs, COLOR)
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
    fs:SetText("Menu")
    fs:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetSize(fs:GetStringWidth() + 10, 18)
    b:SetScript("OnClick", function() QB:Safe(drawers, drawers.ToggleMenu, drawers) end)
    b:SetScript("OnEnter", function() SetColor(fs, COLOR_HOT) end)
    b:SetScript("OnLeave", function() SetColor(fs, COLOR) end)
    b:Hide()
    fallback = b
  end
  return fallback, true
end

local function AnchorPanel()
  if not panel then return end
  local handle, isFallback = CurrentHandle()
  if fallback then
    fallback:ClearAllPoints()
    fallback:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", drawers.db.fallbackX, drawers.db.fallbackY)
    if isFallback and engaged then fallback:Show() else fallback:Hide() end
  end
  panel:ClearAllPoints()
  panel:SetPoint("TOPRIGHT", handle, "BOTTOMRIGHT", 0, -4)
end

local function NotifyStrip(open)
  local s = QB.modules.strip
  if s and s.active and type(s.SetMenuOpen) == "function" then s:SetMenuOpen(open) end
end

-- ---------------------------------------------------------------- outside click

-- A click that lands on a bag window (ContainerFrame*) must not close the panel: changing bags
-- means picking a bag up there and dropping it on a slot of our bag bar.
local function IsInsideMenu(frame)
  local handle = StripHandle()
  local cur, depth = frame, 0
  while cur and depth < 40 do
    if cur == panel or cur == handle or cur == fallback then return true end
    local name = cur.GetName and cur:GetName()
    if type(name) == "string" and name:find("^ContainerFrame") then return true end
    cur = cur.GetParent and cur:GetParent() or nil
    depth = depth + 1
  end
  return false
end

local function OnGlobalMouseDown()
  if not (panel and panel:IsShown()) then return end
  -- holding an item (a bag we are about to drop onto a slot): stay open
  if type(CursorHasItem) == "function" and CursorHasItem() then return end
  local foci
  if type(GetMouseFoci) == "function" then
    foci = GetMouseFoci()        -- Blizzard_SharedXMLBase/FrameUtil.lua uses it
  elseif type(GetMouseFocus) == "function" then
    foci = { GetMouseFocus() }   -- UNVERIFIED: older name, only a fallback
  end
  if type(foci) == "table" then
    for _, fr in ipairs(foci) do
      if IsInsideMenu(fr) then return end
    end
  end
  panel:Hide()
end

-- ---------------------------------------------------------------- build

local function EnsureBuilt()
  if panel then return end
  local p = CreateFrame("Frame", nil, UIParent)
  -- MEDIUM like the HUD frames it hosts; a low level so the hosted frames (Blizzard levels
  -- ~51/52) always sit above our background.
  -- UNVERIFIED: SetParent may reset the hosted frames' strata/level; the original values are
  -- recorded and restored on disable. If the micro buttons look dimmed in-game, raise their
  -- level here after SetParent.
  p:SetFrameStrata("MEDIUM")
  p:SetFrameLevel(5)
  p:SetSize(60, 16)
  p:EnableMouse(true)   -- clicks on the padding belong to the panel, not to the world
  p:Hide()

  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(p)
  bg:SetColorTexture(0.04, 0.04, 0.04, 0.45)
  p.bg = bg

  p:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")   -- Blizzard_APIDocumentationGenerated/SystemDocumentation.lua
    NotifyStrip(true)
    QB:Safe(drawers, Measure)
    if C_Timer and C_Timer.After then
      -- GridLayout frames lay out on a later pass; measure again once they have
      C_Timer.After(0, function() if engaged then QB:Safe(drawers, Measure) end end)
      C_Timer.After(0.2, function() if engaged then QB:Safe(drawers, Measure) end end)
    end
  end)
  p:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    NotifyStrip(false)
  end)
  p:SetScript("OnEvent", function(_, event)
    if event == "GLOBAL_MOUSE_DOWN" then QB:Safe(drawers, OnGlobalMouseDown) end
  end)
  panel = p
end

-- ---------------------------------------------------------------- module API

local function AnyMoved()
  for _, T in ipairs(TARGETS) do
    if T.moved then return true end
  end
  return false
end

function drawers:OpenMenu()
  if not engaged then return end
  if QB:InCombat() then
    QB:Say("menu drawer: not while in combat")
    return
  end
  ApplyAll()
  if not AnyMoved() then
    QB:Say("menu drawer: nothing to show (/qb drawers status)")
    return
  end
  AnchorPanel()
  Measure()
  panel:Show()
end

function drawers:CloseMenu()
  if panel and panel:IsShown() then panel:Hide() end   -- our own frame: fine in combat
end

function drawers:ToggleMenu()
  if panel and panel:IsShown() then
    self:CloseMenu()
  else
    self:OpenMenu()
  end
end

-- ---------------------------------------------------------------- lifecycle

function drawers:OnInit()
  local microOk = ResolveFrame(TARGETS[1]) ~= nil
  local bagsOk = ResolveFrame(TARGETS[2]) ~= nil
  if not microOk and not bagsOk then
    -- UNVERIFIED: both frames are created by Blizzard_MicroMenu / Blizzard_MainMenuBarBagButtons at
    -- UI load, i.e. before PLAYER_LOGIN; if they were lazy-loaded this would wrongly refuse.
    self.unavailable = "neither MicroMenu nor BagsBar exists on this client"
  end
end

function drawers:OnEnable()
  engaged = true
  EnsureBuilt()
  local s = QB.modules.strip
  stripOn = (s and s.active) and true or false
  AnchorPanel()
  if QB:InCombat() then
    pending = true          -- PLAYER_REGEN_ENABLED (drawers.events) does the work
  else
    ApplyAll()
  end
end

function drawers:OnDisable()
  engaged = false          -- hooks are inert from here on
  pending = false
  if panel then panel:Hide() end
  if fallback then fallback:Hide() end
  if QB:InCombat() then
    -- cannot touch the frames now: finish when combat ends (Core no longer dispatches events
    -- to a disabled module, hence the small private frame)
    if not restoreFrame then restoreFrame = CreateFrame("Frame") end
    restoreFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    restoreFrame:SetScript("OnEvent", function(self)
      self:UnregisterEvent("PLAYER_REGEN_ENABLED")
      if not engaged then QB:Safe(drawers, RestoreAll) end
    end)
  else
    RestoreAll()
  end
end

-- ---------------------------------------------------------------- events + bus

drawers.events.PLAYER_REGEN_ENABLED = function()
  if pending then
    pending = false
    ApplyAll()
  end
end

drawers.events.PLAYER_ENTERING_WORLD = function()
  Later(0)
  Later(1)
end

-- Edit Mode (re)applies saved anchors when layouts arrive; our hooks re-assert at once, this is
-- the belt-and-braces pass. Unknown event names are swallowed by Core's pcall(RegisterEvent).
drawers.events.EDIT_MODE_LAYOUTS_UPDATED = function()
  Later(0)
  Later(0.5)
end

QB:On("combat_start", function()
  drawers:CloseMenu()
end, drawers)

QB:On("strip_state", function(on)
  stripOn = on and true or false
  if engaged then AnchorPanel() end
end, drawers)

-- ---------------------------------------------------------------- slash

local function Status()
  QB:Say("drawers: panel " .. ((panel and panel:IsShown()) and "open" or "closed")
    .. (pending and " (work pending: combat)" or ""))
  for _, T in ipairs(TARGETS) do
    local f = ResolveFrame(T)
    local state
    if not f then
      state = "|cffff9040NOT FOUND|r"
    elseif T.moved then
      state = "found, " .. (T.note or "moved") .. (T.hooked and ", hooks installed" or "")
    elseif not drawers.db[T.setting] then
      state = "found, not moved (setting " .. T.setting .. " is off)"
    else
      state = "found, NOT moved yet" .. (T.note and (" (" .. T.note .. ")") or "")
    end
    QB:Say("  " .. T.key .. " (" .. T.global .. "): " .. state)
  end
  local bagKids = {}
  for _, name in ipairs({ "MainMenuBarBackpackButton", "BagSlotCluster", "KeyRingButton" }) do
    bagKids[#bagKids + 1] = name .. (_G[name] and "=yes" or "=no")
  end
  QB:Say("  bag bar children present: " .. table.concat(bagKids, " "))
  QB:Say("  handle: " .. (StripHandle() and "strip Menu handle" or "own (strip is off)"))
end

QB:RegisterSlash(drawers, "drawers", function(rest)
  local a = (rest or ""):lower():match("^(%S*)") or ""
  if a == "open" then
    drawers:OpenMenu()
  elseif a == "close" then
    drawers:CloseMenu()
  elseif a == "toggle" then
    drawers:ToggleMenu()
  elseif a == "status" or a == "" then
    Status()
  else
    QB:Say("usage: /qb drawers open | close | toggle | status")
  end
end, "Menu drawer (micro menu + bags): open | close | toggle | status")
