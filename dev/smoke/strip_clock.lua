-- The server clock in the strip (Cesar, 2026-11-09: "add the server clock into our menu"). GetGameTime() is the realm time; the game's own
-- clock setting (the CVar timeMgrUseMilitaryTime) picks 12 or 24 hours. Stubbed API: our logic, not how it looks.
local hour, minute = 21, 7
function GetGameTime() return hour, minute end
function date() return { hour = 15, min = 7 } end
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local S = QB.modules.strip
local F = S:GetFrame()
local function clockFS() for _, f in ipairs(__frames) do if f.__parent == F and f.__kind == "FontString" and f.__w and f:GetText() and f:GetText():match("^%d+:%d%d") then return f end end end
local function second() for _ = 1, 5 do __runTimers() end end         -- the strip's ticker runs five times a second; the clock once a second

-- 1. at login: the server time, 24 hours (the CVar is unset), shown
second()
local C = clockFS()
assert(C and C:IsShown() and C:GetText() == "21:07", "the server time in the strip: " .. tostring(C and C:GetText()))

-- 2. it sits between the coordinates and the mail: right to left it is [mail] clock coords zone
local coords
for _, f in ipairs(__frames) do if f.__parent == F and f.__kind == "FontString" and f ~= C and f.__points and f.__points[1] and f.__points[1][2] == C then coords = f end end
assert(coords, "the coordinates are anchored to the clock's left edge")
assert(C.__points[1][1] == "RIGHT", "the clock is anchored from its right")

-- 3. a minute later: the next once-a-second refresh shows it
minute = 8; second()
assert(C:GetText() == "21:08", "follows the server: " .. C:GetText())

-- 4. the game's own 12 / 24 hour choice
SetCVar("timeMgrUseMilitaryTime", "0"); second()
assert(C:GetText() == "9:08 PM", "12 hours: " .. C:GetText())
hour, minute = 0, 5; second(); assert(C:GetText() == "12:05 AM", "midnight is 12 AM: " .. C:GetText())
hour, minute = 12, 0; second(); assert(C:GetText() == "12:00 PM", "noon is 12 PM: " .. C:GetText())
hour, minute = 9, 30; second(); assert(C:GetText() == "9:30 AM", C:GetText())
SetCVar("timeMgrUseMilitaryTime", "1"); hour, minute = 21, 8; second()
assert(C:GetText() == "21:08", "back to 24 hours: " .. C:GetText())

-- 5. the tooltip gives the server and the local time
local seen
for _, f in ipairs(__frames) do
  if f.__parent == F and f.__scripts and f.__scripts.OnEnter and f.__scripts.OnClick then
    f.__scripts.OnEnter(f)
    for _, l in ipairs(GameTooltip.__lines) do if tostring(l):find("Server time", 1, true) then seen = GameTooltip.__lines end end
  end
end
assert(seen, "the strip's tooltip has the server time")
local joined = table.concat(seen, " | ")
assert(joined:find("Server time  21:08", 1, true) and joined:find("Local time  15:07", 1, true), "both times: " .. joined)

-- 6. the setting: off hides it and the neighbours close up, on brings it back; the status says
slash("strip clock off"); local st = table.concat(__take(), "\n")
assert(not C:IsShown(), "off hides the clock")
assert(st:find("clock off", 1, true), "the status line says so: " .. st)
slash("strip clock on"); second(); __take()
assert(C:IsShown() and C:GetText() == "21:08", "on brings it back with the right time")
slash("strip clock maybe"); assert(table.concat(__take(), "\n"):find("usage", 1, true), "a bad word shows the usage")

-- 7. no time to read (the call missing, or a secret value): a dash, never an error
local realGet = GetGameTime
GetGameTime = nil; hour = nil; second(); assert(C:GetText() == "-", "no GetGameTime: a dash")
GetGameTime = realGet; hour, minute = 21, 9; second(); assert(C:GetText() == "21:09")
local realSecret = issecretvalue
issecretvalue = function(v) return v == 21 end
second(); assert(C:GetText() == "-", "a secret value: a dash")
issecretvalue = realSecret; second(); assert(C:GetText() == "21:09")
local n = 0 for _ in pairs(QB.errors) do n = n + 1 end
assert(n == 0, "no module errors")

print("strip clock ok")
