# QuestBook

A quest log you can read, and a HUD that gets the minimap and the chrome out of your way, for
World of Warcraft: Forever (it targets the Forever client's UI; retail is not tested).

It is one addon built from isolated modules, so a fault in one cannot take down the others:
`/qb modules` shows what is on, `/qb errors` what broke, `/qb disable <module>` switches one off.

> **Status: v0.12.1, in active development.** Everything here was written against Blizzard's UI
> source for the Forever client and has been run in the game client only in short sessions by one
> person. Code that relies on a guess says `UNVERIFIED:` in its comment, with what to check
> in-game. Treat a feature as working only when this file, `docs/DESIGN.md` or an issue says it was seen working.

## What it does

| module | what it does |
|---|---|
| `questlog` | A readable replacement for Blizzard's quest log, laid out as an open book: a map of where the quest is (with its quest area) above the quest text on the left page, the whole list of quests on the right (rows shrink so none scroll away; the map shrinks first, then the text, so the quest text fits one page), in a parchment theme (`/qb book paper|dark`). Choose the active quest, track and untrack, turn-in readiness, abandon, share, zone and campaign headers, narrated walk-and-listen. The default key, the micro menu button and the objective tracker's "open quest" clicks open this book. Blizzard's log stays reachable as a fallback. |
| `overlay` | The map beside your character, two separate modes on one key: **Off, Minimap, Map**. Minimap is the real minimap, blown up and always square, with a soft edge. Map is the world map, restyled, translucent, soft-edged, opened already centred on you. Action bars are hidden while either is open. While the big one is not in use, the same minimap sits small in the top-right corner for a glance (`/qb overlay corner`). |
| `tracker` | A compact quest list that replaces Blizzard's objective tracker: under the corner minimap, your tracked quests with their objectives, the active quest marked, a "Book" link in the header. Left click on a quest makes it the active one, right click opens it. The list has a position of its own, independent of the minimap: `/qb tracker move` drags it, `/qb overlay corner move` drags the small minimap. Blizzard's tracker is hidden while it is on and given back by `/qb disable tracker`. |
| `markers` | Our own quest markers on the minimap, in place of the client's quest areas (which cannot be restyled on this client and look wrong blown up): one small brass marker per quest in the log, the active quest larger and labelled, a quest ready to hand in marked "?", markers past the edge stuck to it. The client's areas are switched off through the minimap's "Quest POIs" tracking filter and given back when the module is switched off. |
| `kit` | A look-at-it preview of the next visual language (a torn paper page, the type ramp, rows, buttons, a dark tracker swatch) laid out in whole screen pixels: `/qb kit`. `/qb screen` prints your screen in real pixels and the UI scale. Changes no real window. |
| `camera` | Slides the camera sideways and a little back while the overlay is open, so the character sits left of centre. Backs up your camera settings and restores them, also after a crash. Pauses while a quest or gossip dialogue is open, so it does not fight a dialogue addon (Dialogue UI) over the camera. |
| `strip` | A one-line text strip where the minimap used to be: zone, coordinates, mail. Click it to open Blizzard's full map. |
| `drawers` | The Menu drawer (Blizzard's micro menu and bag bar, re-anchored into one quiet panel) and the Addons button (Blizzard's addon compartment). |

Also written, not yet played: a small corner minimap for glancing in combat (the same minimap widget, up whenever the big one is not in use, so it is back when combat closes the overlay).

Written, not yet played: the `markers` module (our quest markers on the minimap, in place of the client's quest areas). The earlier attempt to restyle those areas did not change anything in the game and was removed.
What was decided and why, what has been seen working in the game and what has not, and what is
still open: [docs/DESIGN.md](docs/DESIGN.md).

## Install

Clone this repo (or unzip a Release) as `Interface/AddOns/QuestBook`, so that
`Interface/AddOns/QuestBook/QuestBook.toc` exists (a nested `QuestBook/QuestBook/` folder will not
load). Restart the game after pulling: the TOC lists files, and `/reload` does not pick up new ones.
Settings are saved in `QuestBookDB`.

## Keys

Options > Keybindings > AddOns > QuestBook: **Toggle quest log**, **Map overlay: cycle**,
**Open the Full map**. No key is assigned by default.

## Commands

`/qb` toggles the book. `/qb help` lists the subcommands; `/qb modules` shows module state, with the
reason when a module is unavailable. The version is printed in chat at login and by `/qb version`; if the `.toc` file
says something else than the Lua files, it says so (a mixed or half-updated install).

- Quest log: `book paper|dark|map on|off` (no argument: how the page and list fit), `size <n>`, `dark`, `bg <0-1>`, `voice`, `rate <n>`, `prosody`, `voices`, `usevoice <id>`,
  `say`, `debug`, `dock left|right`, `log replace|blizzard`, `blizzlog`.
- Overlay: `/qb overlay cycle | off | local | zone`, `shape`, `size`, `alpha`, `rotate`, `corner on|off|move|lock|reset|size|pos|alpha|rotate|mask`,
  `ground auto|native|hybrid`, `bars actions|all|none`, `icons <n>`, `mask`, `diag`.
- Look: `/qb kit` (sample page), `/qb screen`.
- Markers: `/qb markers all|tracked|map`, `size <n>`, `scale <n>`, `areas native|hidden` (no argument: status; `map` also draws quest givers, to line the markers up with the client's own "!" blips; `scale` corrects the distance).
- Tracker: `/qb tracker all|tracked|width <n>|alpha <0-1>|lines <n>|max <fraction>|move|lock|pos <x> <y>|reset` (no argument: status).
- Camera: `/qb camera flip | strength <n> | zoomout <n> | zoom <n> | ease <s> | on | off`.
- Strip and drawers: `/qb strip ...`, `/qb drawers open|close|toggle|status`.

`/qb overlay diag` prints the state of the minimap, the hybrid frame and the world map: paste it into
a bug report.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): how the code is organised, how to add a module, how to check
a change without the game (and what that does not prove), and the branch and review flow.

## Branches

`main` = known-good · `dev` = where work lands and is tested in the game. Releases are `vX.Y.Z` tags on `main`. The pipeline and how work moves between them: [CONTRIBUTING.md](CONTRIBUTING.md#pipeline-dev-main-releases).

Built by Cesar & Nibble for the Chavez family's WoW: Forever launch. MIT.
