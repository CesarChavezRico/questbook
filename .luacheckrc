std = "lua51"
max_line_length = false
self = false

-- WoW API globals QuestBook touches; luacheck flags anything NOT listed,
-- which is exactly how a typo'd API name gets caught before the client sees it.
read_globals = {
  "C_QuestLog", "C_VoiceChat", "Enum",
  "GetNumQuestLogEntries", "GetQuestLogTitle", "GetQuestLogQuestText",
  "SelectQuestLogEntry", "GetNumQuestLeaderBoards", "GetQuestLogLeaderBoard",
  "CreateFrame", "UIParent", "UISpecialFrames", "tinsert",
  "print",
}
globals = {
  "SlashCmdList",
  "QuestBookDB", "QuestBook_Toggle",
  "BINDING_HEADER_QUESTBOOK", "BINDING_NAME_QUESTBOOK_TOGGLE",
  "SLASH_QUESTBOOK1", "SLASH_QUESTBOOK2",
}
