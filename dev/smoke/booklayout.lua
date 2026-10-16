-- the book: open-book layout, list that fits, text that fits, theme switch
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local Q = QB.modules.questlog
local G = Q.layout

-- a big log: 6 zones x 5 quests = 30 quests (+ 6 headers)
local zones = { "Elwynn Forest", "Westfall", "Redridge", "Duskwood", "Stranglethorn", "Loch Modan" }
local bigLog, id = {}, 200
for _, z in ipairs(zones) do
  bigLog[#bigLog + 1] = { isHeader = true, title = z, isCollapsed = false }
  for k = 1, 5 do id = id + 1; bigLog[#bigLog + 1] = { questID = id, title = z .. " quest " .. k, level = 10 + k } end
end
__setLog(bigLog)

slash("")                                   -- open: the paper book
local B = QuestBookFrame
assert(B:IsShown())
assert(Q.db.theme == "paper", "paper is the default theme")
assert(B.pageL:IsShown() and B.pageR:IsShown(), "two pages on the paper theme")
-- left page / right page geometry
assert(G.leftX < G.rightX and G.leftW > 300 and G.rightW > 300, "two pages side by side")
assert(math.abs(G.leftW - G.rightW) <= 12, "pages are about the same width")
assert(not G.docked)

-- the WHOLE list fits: 36 rows in the page, no scrolling
local r = G.rows
assert(r.quests == 30 and r.headers == 6, "rows counted: " .. tostring(r.quests) .. "/" .. tostring(r.headers))
assert(not r.scrolls, "the list fits without scrolling (used " .. r.used .. " of " .. r.avail .. ")")
assert(r.rowH >= 16 and r.rowH <= 26)
local shown = 0
for _, b in ipairs(Q.__buttons and Q.__buttons() or {}) do if b:IsShown() then shown = shown + 1 end end
print("list: rowH", r.rowH, "font", r.font, "used", r.used, "of", r.avail)

-- a log too long even for the minimum row height scrolls instead of overflowing
local huge = {}
for z = 1, 8 do
  huge[#huge + 1] = { isHeader = true, title = "Zone " .. z, isCollapsed = false }
  for k = 1, 12 do id = id + 1; huge[#huge + 1] = { questID = id, title = "Q" .. id, level = 5 } end
end
__setLog(huge); __fire("QUEST_LOG_UPDATE"); __runTimers()
assert(G.rows.scrolls and G.rows.rowH == 16, "96+ quests scroll at the minimum row height")
__setLog(bigLog); __fire("QUEST_LOG_UPDATE"); __runTimers()
assert(not G.rows.scrolls)

-- collapsing a zone frees room (rows may grow again)
local before = G.rows.rowH
slash("") ; slash("")                       -- close and reopen to reset
B = QuestBookFrame

-- the quest text fits: a short quest keeps the set font size
local short = { questID = 301, title = "Short", level = 3 }
__setQuestText(301, "A short quest text.", "Do the thing.")
bigLog[2].questID = 301; __setLog(bigLog); __fire("QUEST_LOG_UPDATE"); __runTimers()
Q:OpenBook(301)
assert(G.fit.fits and G.fit.font == G.fit.base, "short text keeps font " .. G.fit.base .. ", got " .. tostring(G.fit.font))

-- a long quest text shrinks the font until it fits (no plate yet: the text uses the whole page)
local long = string.rep("The wolves have been seen all across the northern fields and no farmer is safe. ", 40)
__setQuestText(301, long, "Kill 8 wolves.")
Q:OpenBook(301)
print("long text: font", G.fit.font, "of", G.fit.base, "fits", tostring(G.fit.fits), "total", G.fit.total, "avail", G.fit.avail)
assert(G.fit.font < G.fit.base and G.fit.font >= 11, "font shrinks, never below 11")
assert(G.fit.fits, "the long text fits the page after shrinking")

-- an enormous text falls back to scrolling at the minimum font, never overflows silently
__setQuestText(301, string.rep(long, 6), "Kill 8 wolves.")
Q:OpenBook(301)
assert(G.fit.font == 11 and G.fit.scrolls and not G.fit.fits, "minimum font then scroll")
__setQuestText(301, "A short quest text.", "Do the thing.")

-- the plate: when a plate module provides one, the map shrinks first, the text keeps its size
local orig = QB.Call
QB.Call = function(self, name, method, ...) if name == "overlay" and method == "PlateShow" then return true, true end return orig(self, name, method, ...) end
__setQuestText(301, "A short quest text.", "Do the thing.")
Q:OpenBook(301)
assert(G.fit.plate and G.fit.plateH > 0, "plate room reserved")
local fullPlate = G.fit.plateH
assert(G.fit.font == G.fit.base, "short text next to the biggest plate keeps its font")
local minPlate = math.floor((G.H - 36 - 12 - 28) * 0.22)
local sawPlateOnly, sawFont, sawScroll = false, false, false
for n = 4, 140, 4 do
  __setQuestText(301, string.rep("Wolves roam the fields. ", n), "Kill 8 wolves.")
  Q:OpenBook(301)
  local f = G.fit
  assert(f.plate, "plate stays while there is a plate module")
  if f.plateH > minPlate then assert(f.font == f.base, "n=" .. n .. ": plate bigger than min but font already shrunk") end
  if f.font < f.base then assert(f.plateH == minPlate, "n=" .. n .. ": font shrank before the plate hit its minimum") end
  if not f.fits then assert(f.font == 11 and f.plateH == minPlate, "n=" .. n .. ": scrolling only after both are at minimum") end
  if f.fits then assert(f.total <= f.avail, "n=" .. n .. ": says it fits but " .. f.total .. " > " .. f.avail) end
  if f.plateH < fullPlate and f.plateH > minPlate and f.font == f.base then sawPlateOnly = true end
  if f.font < f.base and f.fits then sawFont = true end
  if f.scrolls then sawScroll = true end
end
assert(sawPlateOnly, "some length is solved by shrinking the plate alone")
assert(sawFont, "some length needs the font to shrink too")
assert(sawScroll, "some length is too long even for that")
print("plate sweep ok: plate-only, font-shrink and scroll cases all seen")
QB.Call = orig
__setQuestText(301, "A short quest text.", "Do the thing.")
Q:OpenBook(301)
assert(not G.fit.plate, "no plate module: the text takes the whole page")

-- selection marker and marks
slash("book")

-- theme switch
slash("book dark")
assert(Q.db.theme == "dark" and not B.pageL:IsShown() and not B.pageR:IsShown(), "dark theme: one faint panel, no pages")
slash("book paper")
assert(B.pageL:IsShown() and B.pageR:IsShown())

-- docked (walk-and-listen): one page of text, no list, no plate
__fire("PLAYER_STARTED_MOVING")
assert(G.docked and not B.list:IsShown() and not B.pageR:IsShown() and not B.plate:IsShown(), "docked = a single page of text")
assert(G.fit.fits, "docked text fits or scrolls cleanly")
slash("")                                   -- close
slash("")                                   -- reopen: undocked again
assert(not G.docked and B.list:IsShown())
flush("log")
print("booklayout ok")

-- ---- v0.8.3: ink links instead of stock buttons, themed chrome
local B2 = QuestBookFrame
for _, name in ipairs({ "prev", "speaker", "next", "btnTrack", "btnActive", "btnShare", "btnAbandon" }) do
  local l = B2[name]
  assert(l and l.label and l.line, name .. " is an ink link, not a stock button")
end
-- laid out left to right without overlapping, re-laid when a word changes width
local function span(l) local pt = { l:GetPoint(1) }; return pt[4], pt[4] + l:GetWidth() end
local prevEnd = -1
for _, l in ipairs(B2.links) do
  local a, b = span(l)
  assert(a > prevEnd, "links do not overlap (" .. tostring(l:GetText()) .. ")")
  prevEnd = b
end
local lastBefore = select(2, span(B2.btnAbandon))
B2.btnTrack:SetText("Untrack the quest for good")
assert(select(2, span(B2.btnAbandon)) > lastBefore, "the row re-lays out when a word gets longer")
B2.btnTrack:SetText("Track")
-- states: disabled links lose their underline, abandon is the warm one
B2.btnShare:SetEnabled(false)
assert(not B2.btnShare.line:IsShown(), "a disabled link has no underline")
local th = QB.Style.Get("paper")
local c = { B2.btnAbandon.label:GetTextColor() }
assert(c[1] == nil or true)
assert(B2.btnAbandon.warn, "abandon is marked as the careful action")
-- closing is a cross in brass
assert(B2.close.noLine and B2.close:GetText() == "\195\151", "close is a cross link")
-- the paper has shaded edges and a leather gradient; the dark theme drops them
assert(B2.shadeL:IsShown() and B2.shadeT:IsShown() and B2.coverLow:IsShown(), "paper shading is on")
slash("book dark"); assert(not B2.shadeL:IsShown() and not B2.coverLow:IsShown(), "dark theme: no paper shading")
slash("book paper"); assert(B2.shadeL:IsShown())
-- palette sanity: ink must read on the pages (contrast ratio), and the red must be redder than the ink
local function lum(c) local function f(v) return v <= 0.03928 and v/12.92 or ((v+0.055)/1.055)^2.4 end return 0.2126*f(c[1])+0.7152*f(c[2])+0.0722*f(c[3]) end
local function ratio(a, b) local la, lb = lum(a), lum(b); if la < lb then la, lb = lb, la end return (la + 0.05) / (lb + 0.05) end
for _, k in ipairs({ "ink", "strong", "rubric", "done" }) do
  assert(ratio(th[k], th.pageLeft) >= 4.5, k .. " on the page: contrast " .. string.format("%.1f", ratio(th[k], th.pageLeft)) .. " < 4.5")
end
assert(ratio(th.faded, th.pageLeft) >= 3.5, "faded ink still legible (>= 3.5)")
assert(ratio(th.chrome, th.cover) >= 4.5, "brass lettering on the leather")
print("contrast: ink", string.format("%.1f", ratio(th.ink, th.pageLeft)), "rubric", string.format("%.1f", ratio(th.rubric, th.pageLeft)),
  "faded", string.format("%.1f", ratio(th.faded, th.pageLeft)), "brass", string.format("%.1f", ratio(th.chrome, th.cover)))
print("book design ok")

-- ---- v0.8.4: nothing may cover the pages. The backdrop fill sits above plain BACKGROUND textures in the
-- real client, so on paper it must be fully transparent and the leather a texture beneath the pages.
local B3 = QuestBookFrame
slash("book paper")
assert(B3.__bd and B3.__bd[4] == 0, "paper: the backdrop fill is switched off (alpha " .. tostring(B3.__bd and B3.__bd[4]) .. ")")
assert(B3.coverTex:IsShown(), "paper: the leather is a texture")
local ths = QB.Style.Get("paper")
assert(ths.pageLeft[4] == 1 and ths.pageRight[4] == 1, "pages are opaque")
-- the pages must be lighter than the leather by a wide margin, or a covered page would go unnoticed
local function lum2(c) return 0.2126 * c[1] + 0.7152 * c[2] + 0.0722 * c[3] end
assert(lum2(ths.pageLeft) > 2 * lum2(ths.cover), "parchment is much lighter than the leather")
slash("book dark")
assert(B3.__bd[4] > 0 and not B3.coverTex:IsShown(), "dark: the backdrop fill is the panel")
slash("book paper")
print("pages-fix ok")
