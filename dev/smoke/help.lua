-- Help and usage text must survive the chat frame: a single "|" followed by a letter is an escape code there
-- ("|t", "|h", "|r", "|n"), so "all|tracked" printed as "allracked" (Cesar, 2026-10-17). A literal pipe is "||".
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local bad, checked = {}, 0
local function check(tag)
  for _, l in ipairs(__take()) do
    l = l:gsub("|cffd8c88aQuestBook|r", "")          -- our own prefix is a real colour code
    l = l:gsub("||", "")                              -- an escaped pipe
    checked = checked + 1
    if l:find("|%a") then bad[#bad + 1] = tag .. ": " .. l end
  end
end
slash("help"); check("help")
-- every subcommand asked something it does not know prints its usage
local subs = {}
for s in pairs(QB.slash) do subs[#subs + 1] = s end
table.sort(subs)
for _, s in ipairs(subs) do slash(s .. " zzzbogus"); check(s) end
for _, m in ipairs({ "overlay corner zzz", "strip zzz", "strip anchor ZZZ", "drawers zzz", "tracker zzz", "markers zzz", "camera zzz" }) do
  slash(m); check(m)
end
assert(checked > 20, "looked at " .. checked .. " lines")
assert(#bad == 0, "unescaped pipes:\n" .. table.concat(bad, "\n"))
-- the helper itself
QB:Usage("x all|tracked y"); local out = __take()[1]
assert(out:find("all||tracked", 1, true), "QB:Usage doubles pipes: " .. tostring(out))
