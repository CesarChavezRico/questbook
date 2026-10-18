# dev tools (not shipped)

Offline checks for when there is no game client at hand.

    cd dev && npm install
    node lint.js ../Core.lua ../modules/*.lua       # Lua 5.1 syntax + non-local globals report
    LUA_STRICT=1 node lint.js ../Core.lua ../modules/*.lua   # same, without the built-in WoW allowlist
    cd smoke                                         # the addon root is two levels up from here
    node run.js ../.. quest_strip_drawers_camera.lua    # load the addon on a stubbed API, drive it
    node run.js ../.. overlay.lua
    node run.js ../.. isolation.lua                     # a broken module must not break the others (exits 1 by design: it lists the broken module's errors)
    node run.js ../.. questroute.lua                    # tracker clicks open the reader, zoom-out, fallback
    node run.js ../.. camera_dialogue.lua               # the camera shift and a quest dialogue: no fighting over the CVar
    node run.js ../.. giver.lua                         # the quest giver: recorded at accept, capped, shown in the reader
    node run.js ../.. xp.lua                            # the experience bar: fill, rested, tooltip, max level, Blizzard's bar, no strip
    node run.js ../.. kit.lua                           # /qb screen, /qb kit, pixel arithmetic, the nine-patch page
    node run.js ../.. version.lua                       # the version line at login
    node run.js ../.. help.lua                          # every help / usage line survives the chat frame (no stray "|")
    node run.js ../.. markers.lua                       # quest markers: positions, rotation, edge, switching the client's areas off and back
    node run.js ../.. tracker.lua                       # the compact tracker: hides and restores Blizzard's, follows the corner minimap
    node run.js ../.. reader.lua                        # the reader: sits where the map sits, trades places with it, camera, duties, voice
    node run.js ../.. migrate.lua                          # settings saved by an older build
    node run.js ../.. bare.lua bare_pre.lua             # a client missing every Blizzard piece we use

The stub (`smoke/mock.lua`) makes unknown widget methods no-ops, so it finds logic, nil and typo
errors in our own code. It cannot tell whether a real Blizzard frame has a method; only the game
client can. Every `UNVERIFIED:` comment in the modules is something the client has to confirm.

## Art

`python3 dev/art/gen_kit.py` regenerates the paper textures in `Textures/` (torn edges, corners, grain, the tapering
rule) and writes `dev/art/preview*.png` (git-ignored) so the result can be looked at without the game. It is pure Python with no
dependencies. The art is generated from nothing: no texture, atlas or code from another addon or from Blizzard is
used or traced. Change the generator, rerun it, commit the TGAs and look at the previews.
