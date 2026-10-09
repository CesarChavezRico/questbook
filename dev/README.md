# dev tools (not shipped)

Offline checks for when there is no game client at hand.

    cd dev && npm install
    node lint.js ../Core.lua ../modules/*.lua       # Lua 5.1 syntax + non-local globals report
    LUA_STRICT=1 node lint.js ../Core.lua ../modules/*.lua   # same, without the built-in WoW allowlist
    cd smoke                                         # the addon root is two levels up from here
    node run.js ../.. quest_strip_drawers_camera.lua    # load the addon on a stubbed API, drive it
    node run.js ../.. overlay.lua
    node run.js ../.. isolation.lua                     # a broken module must not break the others (exits 1 by design: it lists the broken module's errors)
    node run.js ../.. bare.lua bare_pre.lua             # a client missing every Blizzard piece we use

The stub (`smoke/mock.lua`) makes unknown widget methods no-ops, so it finds logic, nil and typo
errors in our own code. It cannot tell whether a real Blizzard frame has a method; only the game
client can. Every `UNVERIFIED:` comment in the modules is something the client has to confirm.
