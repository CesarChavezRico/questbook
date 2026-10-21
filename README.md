# QuestBook

A quest log you can read, and a HUD that gets the minimap and the chrome out of your way, for
World of Warcraft: Forever (it targets the Forever client's UI; retail is not tested).

It is one addon built from isolated modules, so a fault in one cannot take down the others:
`/qb modules` shows what is on, `/qb errors` what broke, `/qb disable <module>` switches one off.

> **Status: v0.19.0, in active development.** Everything here was written against Blizzard's UI
> source for the Forever client and has been run in the game client only in short sessions by one
> person. Code that relies on a guess says `UNVERIFIED:` in its comment, with what to check
> in-game. Treat a feature as working only when this file, `docs/DESIGN.md` or an issue says it was seen working.

## What it does

| module | what it does |
|---|---|
| `questlog` | The quest reader, a readable replacement for Blizzard's quest log: ONE torn-paper page set where the big map sits (same centre and height, same camera shift and zoom-out) with the quest's title, level and zone, description and objectives, and the duties (make it the active quest, track, share, abandon), arrows to walk through your quests, and narrated walk-and-listen, with the game's own voice or, with `/qb voice engine relay`, a better one spoken by the WoW AI bridge on your rig (ElevenLabs; see 4BI-38), chosen by who gave the quest (the first step you take with voice on reads the quest and puts the page away; the tracker's header has a "Stop" link while it reads, and "Voice on / off" otherwise). The action bars are hidden while it is open, as for the map, and so (settings) are the small minimap, the player and target frames, and the player's buffs and debuffs. It has no scroll bar (the wheel still scrolls); its height is `/qb reader height`. It trades places with the map: opening it closes the map overlay, the map key while it is open brings the map up and closes it. The default key, the micro menu button and the objective tracker's "open quest" clicks open it; Blizzard's log stays reachable as a fallback. |
| `overlay` | The map beside your character, two separate modes on one key: **Off, Minimap, Map**. Minimap is the real minimap, blown up and always square, with a soft edge. Map is the world map, restyled, translucent, soft-edged, opened already centred on you. Action bars are hidden while either is open. While no map is open, the same minimap sits small in the corner for a glance (`/qb overlay corner`); it is not shown with the big minimap or the overland map. |
| `tracker` | The quest list, in the new look, replacing Blizzard's objective tracker: every quest in your log, its level at the right in [ ] (faded; `/qb tracker level off` hides it) with a Play link under it that reads the quest aloud (Stop while it is read), and its objective lines indented under the title, in whole-pixel type; click the title to collapse the list to its title row (and again to expand it); the whole list can also be put away and brought back (key binding, `/qb tracker toggle|show|hide`); the active quest has a gold title and a bar at its left edge (its one accent), a quest ready to hand in is green, counted objectives (kill 6, collect 3) get a thin progress bar, a tapering rule under the header, header links "Voice on / off" (or "Stop" while a quest is read) and "Log". Left click on a quest makes it the active one, right click opens it in the reader, shift + left click puts its link into the chat box you are typing in (Blizzard's or the WoW AI chat's). Quests are shown in pages of up to 10 (`/qb tracker perpage <n>`), fewer when they do not fit the panel, with tabs "1 2 3" next to the title. The list has a position of its own: `/qb tracker move` drags it, `/qb overlay corner move` drags the small minimap. Blizzard's tracker is hidden while it is on and given back by `/qb disable tracker`. |
| `markers` | Our own quest markers on the minimap, in place of the client's quest areas (which cannot be restyled on this client and look wrong blown up): one small brass marker per quest in the log, the active quest larger (and named, on the big minimap), a quest ready to hand in marked "?", markers past the edge stuck to it. The client's areas are switched off through the minimap's "Quest POIs" tracking filter and given back when the module is switched off. |
| `giver` | Records who gave each quest when you accept it (name, gender, creature type, NPC number, zone: from the game's `npc` unit while its dialog is up), kept per quest in the saved variables. The reader's meta line says "From Zenn Foulhoof". The first step of the voiceover (4BI-38: voice by quest giver). `/qb giver` prints what the game says about the NPC you last talked to. Quests accepted before it existed have no record. |
| `xp` | The experience bar, folded into the top-right strip: a thin bar (3 px) under it, right-aligned, the XP you have in gold on a faint track, the rested part as a lighter blue extension, with "Lv 8  44%  [14%]" above it (the rested part, as a percent of the level, in brackets, only when there is some; the bar and the number are one hover area; the Menu drawer opens below them); hover for level, XP / max, to go and rested. Blizzard's own bottom bar is faded out while it is up (`/qb xp blizzard off` leaves it). At the maximum level, or with XP gain off, it hides and Blizzard's bar comes back (it also carries reputation and honor). |
| `kit` | A look-at-it preview of the next visual language (a torn paper page, the type ramp, rows, buttons, a dark tracker swatch) laid out in whole screen pixels: `/qb kit`. `/qb screen` prints your screen in real pixels and the UI scale. Changes no real window. |
| `camera` | Slides the camera sideways and a little back while the overlay is open, so the character sits left of centre. Backs up your camera settings and restores them, also after a crash. Pauses while a quest or gossip dialogue is open, so it does not fight a dialogue addon (Dialogue UI) over the camera. |
| `strip` | A one-line text strip where the minimap used to be: zone, coordinates, mail. Click it to open Blizzard's full map. |
| `drawers` | The Menu drawer (Blizzard's micro menu and bag bar, re-anchored into one quiet panel) and the Addons button (Blizzard's addon compartment). |

Also written, not yet played: a small corner minimap for glancing in combat (the same minimap widget, up whenever no map is open, so it is back when combat closes the overlay).

Written, not yet played: the `markers` module (our quest markers on the minimap, in place of the client's quest areas). The earlier attempt to restyle those areas did not change anything in the game and was removed.
What was decided and why, what has been seen working in the game and what has not, and what is
still open: [docs/DESIGN.md](docs/DESIGN.md).

## Install

Clone this repo (or unzip a Release) as `Interface/AddOns/QuestBook`, so that
`Interface/AddOns/QuestBook/QuestBook.toc` exists (a nested `QuestBook/QuestBook/` folder will not
load). Restart the game after pulling: the TOC lists files, and `/reload` does not pick up new ones.
Settings are saved in `QuestBookDB`.

## Keys

Options > Keybindings > AddOns > QuestBook: **Toggle quest log**, **Show / hide the quest list**, **Map overlay: cycle**,
**Open the Full map**. No key is assigned by default.

## Commands

`/qb` toggles the quest reader. `/qb help` lists the subcommands; `/qb modules` shows module state, with the
reason when a module is unavailable. The version is printed in chat at login and by `/qb version`; if the `.toc` file
says something else than the Lua files, it says so (a mixed or half-updated install).

- Quest reader: `reader height <0.3-0.95>|auto`, `reader aspect <n>`, `reader size <px>`, `reader scrollbar on|off`, `reader hide minimap|frames|auras on|off`, `size <px>` (body text, 14-40, default 22), `voice`, `rate <n>`, `prosody`, `voices`, `usevoice <id>`, `say`, `debug`,
  `voice engine game|relay`, `voice prefetch on|off`, `voice test`, `voice slot`, `log replace|blizzard`, `blizzlog`.
- Overlay: `/qb overlay cycle | off | local | zone`, `shape`, `size`, `alpha`, `rotate`, `corner on|off|move|lock|reset|size|pos|alpha|rotate|mask soft|wide|stock` (the small minimap bleeds out into the world by default; `stock` is the crisp circle),
  `ground auto|native|hybrid`, `bars actions|all|none`, `icons <n>`, `mask`, `diag`.
- Experience bar: `/qb xp width <px>|height <px>|gap <px>|text on|off|textsize <px>|rested on|off|blizzard on|off` (no argument: status).
- Look: `/qb kit` (sample page), `/qb screen`.
- Markers: `/qb markers all|tracked|map`, `size <n>`, `scale <n>`, `areas native|hidden` (no argument: status; `map` also draws quest givers, to line the markers up with the client's own "!" blips; `scale` corrects the distance).
- Tracker: `/qb tracker toggle|show|hide|collapse|expand|level on|off|all|tracked|width <px>|size <px>|alpha <0-1>|lines <n>|perpage <n>|page <n>|max <fraction>|move|lock|pos <x> <y>|reset` (no argument: status).
- Camera: `/qb camera flip | strength <n> | zoomout <n> | readerzoom <n> | zoom <n> | ease <s> | on | off`.
- Strip and drawers: `/qb strip ...`, `/qb drawers open|close|toggle|status`.

`/qb overlay diag` prints the state of the minimap, the hybrid frame and the world map: paste it into
a bug report.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): how the code is organised, how to add a module, how to check
a change without the game (and what that does not prove), and the branch and review flow.

## Branches

`main` = known-good · `dev` = where work lands and is tested in the game. Releases are `vX.Y.Z` tags on `main`. The pipeline and how work moves between them: [CONTRIBUTING.md](CONTRIBUTING.md#pipeline-dev-main-releases).

Built by Cesar & Nibble for the Chavez family's WoW: Forever launch. MIT.
