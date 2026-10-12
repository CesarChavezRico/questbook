# Contributing to QuestBook

Short version: branch from `dev`, change one thing, run the offline checks, say plainly what you
did and did not verify, open a PR into `dev`. Cesar reviews and merges.

## How the code is organised

```
Core.lua            module registry, protected calls, event + message bus, slash, keybinding functions
modules/QuestLog.lua   the quest log and its duties (the oldest code, from before the modular split)
modules/Overlay.lua    Off / Minimap / Map, masks, ground, bars, indoor handling
modules/Camera.lua     lateral shift + zoom-out, CVar backup and restore
modules/Strip.lua      the text strip, the Addons handle
modules/Drawers.lua    the Menu panel (micro menu + bags)
Textures/              the soft-alpha masks (TGA, 256x256, white with an alpha gradient)
Bindings.xml           keybinding entry points, named in Core.lua
QuestBook.toc          load order (Core first); lists every file
dev/                   offline tools, not shipped (see below)
```

Every file starts with `local ADDON, QB = ...`: the engine hands all files of an addon the same table,
and that is how modules reach Core.

### The module contract

```lua
local _, QB = ...
local mod = QB:NewModule("name", { someSetting = 1 })   -- defaults live in db.mod.name

mod.events.SOME_EVENT = function(self, ...) end         -- registered when the module is enabled
function mod:OnInit()    end   -- once, at login; set mod.unavailable = "reason" to refuse to run
function mod:OnEnable()  end   -- when switched on
function mod:OnDisable() end   -- MUST undo everything OnEnable changed
QB:RegisterSlash(mod, "name", function(rest) end, "help text")   -- /qb name ...
QB:On("topic", function(...) end, mod)                           -- message bus listener
```

Rules the design depends on:

1. **Nothing outside a function touches a Blizzard frame.** Loading a file must never error.
2. **Every entry point runs under `QB:Safe`** (Core does this for events, slash, bus handlers and
   enable/disable; wrap your own `OnClick`/`OnUpdate` scripts too). A module that errors is reported
   once and carries on; the others are unaffected. This is the reason the addon is modular.
3. **Whatever you change on a Blizzard frame you must restore** on "off" and in `OnDisable`.
   Overlay's "tweak sets" (record the original, apply, undo in reverse) are the pattern to copy.
4. **No protected-frame work in combat.** Check `QB:InCombat()` and defer to `PLAYER_REGEN_ENABLED`.
5. **Modules talk through the bus, not through each other's tables.** Current topics:
   `overlay_state` (`"off" | "local" | "zone"`), `open_full`, `strip_state`, `combat_start`,
   `combat_end`. Add a topic before you add a cross-module call.
6. **Settings:** Core fills only *missing* keys, so a value an old version saved beats a changed
   default. When you change what a default means, add a versioned migration (see `OnInit` in
   `Overlay.lua`, which fixed exactly this once). Keep a new version key *out* of the defaults table.

### The UI source is the reference

Blizzard's UI Lua/XML and generated API docs for the Forever client are public at
`github.com/Gethe/wow-ui-source`, branch `forever`. Read it before guessing: a method that Blizzard's
own Lua calls on a frame exists on that frame. The generated API docs list `C_` functions, events and
CVars; they do not list widget methods. Cite the file in a comment when a claim rests on it.
Whether the client **behaves** the way the source suggests is a different question: mark it
`UNVERIFIED:` until someone has seen it in the game.

## Checking a change without the game

```
cd dev && npm install
node lint.js ../Core.lua ../modules/*.lua       # Lua 5.1 syntax + every non-local global
cd smoke
node run.js ../.. overlay.lua                   # also: quest_strip_drawers_camera, questroute,
                                                # migrate, isolation, bare (+ bare_pre.lua)
```

`dev/README.md` has the full list. The smoke harness loads the addon into a Lua VM against a
**stubbed** WoW API (`dev/smoke/mock.lua`). It finds logic, nil and typo errors in our code, and it
checks the state machines. It cannot tell you whether a real Blizzard frame has a method, accepts what
we do to it, or draws as we expect. A green smoke run is **not** "works in the game".

When you add behaviour, add an assertion for it to a scenario; when you add a Blizzard function the
stub lacks, add it to `mock.lua` in the shape the UI source shows.

## Testing in the game

1. Clone your branch as `Interface/AddOns/QuestBook` and restart the game.
2. `/qb modules`: each module should be `on`, or `unavailable` with a reason. `/qb errors` should be empty.
3. Exercise the thing you changed, in and out of combat, indoors and outdoors where relevant.
4. For anything map-related, attach `/qb overlay diag` to the PR or issue.

A PR is only as honest as its "not verified" list. Write it.

## Branches, commits and PRs

- Branch from `dev`; PR into `dev`. `main` is known-good and gets `dev` merged when a build has been
  played. Never push to `dev` or `main` directly.
- Commit message: `topic: what changed, was X now Y (why)`, one logical change per commit.
- PR description: what changed and why, **Verified**, **NOT verified (client only)**. If you found
  that an earlier claim was wrong, say so in the PR rather than quietly fixing the code.
- CI (luacheck on the repo root) and the release workflow currently live on `main` only; a PR that
  brings them to `dev` is pending. Until then run the lint in `dev/` yourself.
- Releases are tags `vX.Y.Z`; the workflow zips the whole addon directory.

## Design decisions

The map layout, the keybinding plan and the reasoning behind the module split are recorded in the
design note named in the README, with the open questions marked. If a change reverses one of those
decisions, raise it with Cesar first; the note gets amended in the same breath.
