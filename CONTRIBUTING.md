# Contributing to QuestBook

Short version: branch from `dev`, change one thing, run the offline checks, say plainly what you
did and did not verify, open a PR into `dev`. Cesar reviews and merges.

## How the code is organised

```
Core.lua            module registry, protected calls, event + message bus, slash, keybinding functions
Style.lua           palettes (paper / dark), font helpers; see docs/STYLE.md
modules/QuestLog.lua   the quest reader (one page) and the quest log's duties: active, track, share, abandon, voice
modules/Overlay.lua    Off / Minimap / Map, masks, ground, bars, indoor handling
modules/Camera.lua     lateral shift + zoom-out, CVar backup and restore
modules/Tracker.lua    the compact quest list that replaces Blizzard's objective tracker
modules/Markers.lua    our quest markers on the minimap; switches the client's quest areas off
modules/Giver.lua      who gave each quest (recorded at accept); feeds the reader and, later, the voice
modules/Xp.lua         the experience bar under the strip; fades Blizzard's bottom bar while it is up
modules/Kit.lua        `/qb kit`, `/qb screen`: the sample page of the paper look, in whole pixels
modules/Strip.lua      the text strip, the Addons handle
modules/Drawers.lua    the Menu panel (micro menu + bags)
Textures/              the soft-alpha masks and the paper kit (TGA, power-of-two sizes, 32-bit with alpha)
dev/art/gen_kit.py     generates the paper textures (pure Python, our own art); run it, commit the TGAs
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
   `overlay_state` (`"off" | "local" | "zone"`), `overlay_host` (who holds the minimap), `open_full`,
   `strip_state`, `combat_start`, `combat_end`. Add a topic before you add a cross-module call.
6. **Chat text:** a single `|` followed by a letter is an escape code in the chat frame (`|t`, `|h`, `|r`, `|n`),
   so `all|tracked` prints as `allracked`. Print help and usage with `QB:Usage` (it doubles the pipes), not `QB:Say`;
   `dev/smoke/help.lua` fails on a stray one.
7. **Settings:** Core fills only *missing* keys, so a value an old version saved beats a changed
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

- Branch from `dev`; PR into `dev`. Never push to `dev` or `main` directly. Cesar reviews and merges.
- Commit message: `topic: what changed, was X now Y (why)`, one logical change per commit.
- PR description: what changed and why, **Verified**, **NOT verified (client only)**. If you found
  that an earlier claim was wrong, say so in the PR rather than quietly fixing the code.

## Pipeline: dev, main, releases

```
feature branch --PR--> dev --PR--> main --tag vX.Y.Z--> GitHub Release (zip)
   (CI runs)           (CI runs)   (CI runs)             (release workflow)
```

- **`dev`** is where work lands and is played in the game. It can be ahead of what anyone has seen
  working; the README status line says how far.
- **`main`** is known-good: a `dev` build that has been **played in the game**, with its checks
  (`/qb modules`, `/qb errors`, the thing that changed) written down in the PR. Promote with a PR
  from `dev` into `main`, never by pushing.
- **CI** (`.github/workflows/ci.yml`) runs luacheck on the repo root for every push and every pull
  request. It uses `.luacheckrc`: real errors (undefined or accidental globals, syntax) fail; style
  warnings are ignored; `dev/` is excluded. When you use a new Blizzard global, add it to
  `read_globals` in `.luacheckrc`, as luacheck is how a typo'd API name gets caught before the game.
  CI does not run the smoke tests in `dev/smoke`; run them yourself.
- **Release** (`.github/workflows/release.yml`) runs when a tag matching `v*` is pushed. It zips the
  whole addon folder (everything except `.git*`, `.github`, `dist`, `dev` and `.luacheckrc`) as
  `QuestBook-<tag>.zip` and publishes a GitHub Release with generated notes. Merging into `main`
  does **not** release anything; only a tag does.
- **Version:** edit `## Version:` in `QuestBook.toc` and `QB.version` in `Core.lua` together in the
  PR that changes behaviour. The tag should equal the TOC version (`v0.7.4` for `0.7.4`); nothing
  checks that, so check it when you tag.
- **Keeping `dev` and `main` in step:** the workflows must exist on a branch for CI to run on its
  PRs. They are on both now. If `main` gets a commit that `dev` lacks (a hotfix, a workflow change),
  merge `main` back into `dev` by PR straight away so the two do not drift.

**Release cadence: not decided.** Nothing here sets one. Until Cesar decides, the working rule is:
promote `dev` to `main` after a play session that exercised the changes, and tag a release when
`main` holds something worth giving to another player. A proposal is in the PR that added this
section; change this paragraph when it is settled.

## Design decisions

The map layout, the reasoning behind the module split, what has been seen working and the open
questions are in [docs/DESIGN.md](docs/DESIGN.md). If a change reverses one of those decisions, raise
it with Cesar first, and amend `docs/DESIGN.md` in the same PR.
