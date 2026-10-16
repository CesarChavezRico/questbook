-- quest areas on the enlarged minimap: our fill, outline and thickness instead of the default art
__fire("ADDON_LOADED", "QuestBook"); __loggedIn = true; __fire("PLAYER_LOGIN")
local function slash(s) SlashCmdList.QUESTBOOK(s) end
local function flush(tag) for _, l in ipairs(__take()) do io.write(tag .. " | " .. l .. "\n") end end
local O = QB.modules.overlay
local H = UIParent:GetHeight()

-- the corner minimap is up at login: the style is applied there too, with a thicker (native-ish) outline
assert(O.host == "corner")
assert(__blob.QuestInsideAlpha == 0.14 and __blob.QuestRingAlpha == 0.8 and __blob.QuestOutsideAlpha == 0, "default look: faint fill, clear outline, no halo")
assert(__blob.TaskInsideAlpha == 0.14, "world-quest areas get the same look")
assert(__blob.QuestInsideTexture:find("blob_fill.tga") and __blob.QuestRingTexture:find("blob_ring.tga"), "our flat brass textures")
assert(__blob.ArchInsideAlpha == nil, "archaeology areas are left alone")
local cornerW = Minimap:GetWidth()
local cornerScalar = __blob.QuestRingScalar
assert(math.abs(cornerScalar - 140 / cornerW) < 1e-6, "auto thickness = native size / our size")
-- the big minimap is much larger: the outline is thinner so it does not become a fat band
slash("overlay local"); __tick(3)
local bigW = Minimap:GetWidth()
assert(bigW > 3 * cornerW and __blob.QuestRingScalar < cornerScalar / 2, "thinner outline at the big size: " .. __blob.QuestRingScalar .. " vs " .. cornerScalar)
assert(math.abs(__blob.QuestRingScalar - 140 / bigW) < 1e-6)
-- settings take effect right away
slash("overlay blobs fill 0.3"); assert(__blob.QuestInsideAlpha == 0.3)
slash("overlay blobs ring 0.5"); assert(__blob.QuestRingAlpha == 0.5)
slash("overlay blobs halo 0.2"); assert(__blob.QuestOutsideAlpha == 0.2)
slash("overlay blobs thick 0.4"); assert(__blob.QuestRingScalar == 0.4 and __blob.TaskRingScalar == 0.4)
slash("overlay blobs thick auto"); assert(math.abs(__blob.QuestRingScalar - 140 / bigW) < 1e-6)
-- styles
slash("overlay blobs soft"); assert(__blob.QuestRingAlpha == 0 and __blob.QuestOutsideAlpha == 0 and __blob.QuestInsideAlpha == 0.3, "soft = fill only")
slash("overlay blobs off"); assert(__blob.QuestInsideAlpha == 0 and __blob.QuestRingAlpha == 0, "off hides the areas (pins stay)")
slash("overlay blobs brass"); assert(__blob.QuestRingAlpha == 0.5)
-- the diagnostic: one layer at a time at full strength
slash("overlay blobs solo ring"); assert(__blob.QuestRingAlpha == 1 and __blob.QuestInsideAlpha == 0 and __blob.QuestOutsideAlpha == 0)
slash("overlay blobs solo inside"); assert(__blob.QuestInsideAlpha == 1 and __blob.QuestRingAlpha == 0)
slash("overlay blobs solo outside"); assert(__blob.QuestOutsideAlpha == 1 and __blob.QuestInsideAlpha == 0)
slash("overlay blobs solo none"); assert(__blob.QuestInsideAlpha == 0.3 and __blob.QuestRingAlpha == 0.5, "solo none puts the settings back")
-- clamping and bad input never throw
slash("overlay blobs fill 9"); assert(__blob.QuestInsideAlpha == 1)
slash("overlay blobs fill -3"); assert(__blob.QuestInsideAlpha == 0)
slash("overlay blobs nonsense")
slash("overlay blobs fill 0.14"); slash("overlay blobs ring 0.8"); slash("overlay blobs halo 0")
-- leaving the big panel: the corner gets its own (thicker) outline again
slash("overlay off"); __tick(3)
assert(O.host == "corner" and math.abs(__blob.QuestRingScalar - 140 / cornerW) < 1e-6, "back in the corner: outline thickness follows the size")
-- "native" never touches a client that was not touched; once touched it says a reload is needed
local before = 0; for _ in pairs(__blob) do before = before + 1 end
slash("overlay blobs native")
local said = table.concat(__take(), "\n")
assert(said:find("reload"), "native after touching explains the reload")
-- a client without the setters: nothing throws, one notice, areas keep their default look
for k in pairs(Minimap) do if type(k) == "string" and k:find("Blob") then Minimap[k] = false end end
__take()
slash("overlay blobs brass"); slash("overlay local"); __tick(3); slash("overlay blobs fill 0.2")
local out = table.concat(__take(), "\n")
assert(out:find("no quest%-area setters"), "a client without the setters says so once")
local _, count = out:gsub("no quest%-area setters", "")
assert(count == 1, "only once, got " .. count)
assert(O.blobCalls == 0)
print("blobs ok")
