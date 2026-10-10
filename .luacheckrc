std = "lua51"
max_line_length = false
-- offline dev tools and their stubbed-API scenarios are not game code
exclude_files = { "dev/**" }
self = false

-- Style noise is not what CI is for: unused names (the `local ADDON, QB = ...` header,
-- callback args), shadowing, empty branches. Real errors stay on: undefined globals (113),
-- accidental global writes (111, 112), unreachable code, syntax.
ignore = { "211", "212", "213", "231", "311", "312", "314", "331", "421", "431", "432", "542" }

-- WoW API globals the addon touches; luacheck flags anything NOT listed,
-- which is exactly how a typo'd API name gets caught before the client sees it.
read_globals = {
  -- core
  "CreateFrame", "UIParent", "UISpecialFrames", "GetTime", "hooksecurefunc", "InCombatLockdown",
  "UnitAffectingCombat", "IsLoggedIn", "IsInGroup", "IsMounted", "IsPlayerMoving", "issecretvalue",
  "CreateColor", "tinsert", "wipe", "print", "GameTooltip", "GameTooltip_SetTitle",
  -- namespaces and constants
  "C_Timer", "C_CVar", "C_Map", "C_QuestLog", "C_SuperTrack", "C_VoiceChat", "C_Minimap",
  "C_Texture", "C_ChatInfo", "Enum", "Constants", "MapUtil",
  -- quest log (modern and classic fallbacks)
  "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLogQuestText", "SelectQuestLogEntry",
  "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard", "IsQuestComplete", "ExpandQuestHeader",
  "QuestLogPushQuest", "QuestUtils_GetQuestName", "StaticPopup_Show", "StaticPopup_Hide",
  -- map, camera, strip, drawers
  "GetCVar", "SetCVar", "GetCameraZoom", "CameraZoomIn", "CameraZoomOut",
  "GetZoneText", "GetSubZoneText", "HasNewMail", "CursorHasItem", "GetMouseFoci", "GetMouseFocus",
  "ShowUIPanel", "HideUIPanel", "ToggleWorldMap", "PlayerMovementFrameFader",
  "HybridMinimap_LoadUI", "IsIndoors",
  "Minimap", "MinimapCluster", "WorldMapFrame", "AddonCompartmentFrame", "MicroMenu",
  "MicroMenuContainer",
}
-- globals the addon defines (slash, keybindings, saved variables, the ToggleQuestLog reroute)
globals = {
  "SlashCmdList", "ToggleQuestLog",
  "QuestBookDB", "QuestBook_Toggle", "QuestBook_MapCycle", "QuestBook_FullMap",
  "BINDING_HEADER_QUESTBOOK", "BINDING_NAME_QUESTBOOK_TOGGLE",
  "BINDING_NAME_QUESTBOOK_MAPCYCLE", "BINDING_NAME_QUESTBOOK_FULLMAP",
  "SLASH_QUESTBOOK1", "SLASH_QUESTBOOK2",
}
