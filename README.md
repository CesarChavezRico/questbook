# QuestBook

A quest log you can read, and a HUD that gets the minimap and the chrome out of your way, for
World of Warcraft: Forever (it targets the Forever client's UI; retail is not tested).

It is one addon built from isolated modules, so a fault in one cannot take down the others:
`/qb modules` shows what is on, `/qb errors` what broke, `/qb disable <module>` switches one off.

> **Status: v0.7.4, in active development.** Everything here was written against Blizzard's UI
> source for the Forever client and has been run in the game client only in short sessions by one
> person. Code that relies on a guess says `UNVERIFIED:` in its comment, with what to check
> in-game. Treat a feature as working only when this file or an issue says it was seen working.

## What it does

| module | what it does |
|---|---|
| `questlog` | A readable replacement for Blizzard's quest log: choose the active quest, track and untrack, turn-in readiness, abandon, share, zone and campaign headers, narrated walk-and-listen. The default key, the micro menu button and the objective tracker's "open quest" clicks open this book. Blizzard's log stays reachable as a fallback. |
| `overlay` | The map beside your character, two separate modes on one key: **Off, Minimap, Map**. Minimap is the real minimap, blown up and always square, with a soft edge. Map is the world map, restyled, translucent, soft-edged, opened already centred on you. Action bars are hidden while either is open. The old corner minimap is retired. |
| `camera` | Slides the camera sideways and a little back while the overlay is open, so the character sits left of centre. Backs up your camera settings and restores them, also after a crash. |
| `strip` | A one-line text strip where the minimap used to be: zone, coordinates, mail. Click it to open Blizzard's full map. |
| `drawers` | The Menu drawer (Blizzard's micro menu and bag bar, re-anchored into one quiet panel) and the Addons button (Blizzard's addon compartment). |

Not built yet, discussed: a small always-on minimap for glancing in combat, replacing the
objective tracker with a compact quest list, and tuning how quest areas look on the big minimap.
The design record is `notes/2026-10-09-hud-map-addon-design.md` in the 4bits-cesar repo (the
Chavez family's knowledge repo); this addon's decisions are in that note, not in this one.

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
reason when a module is unavailable.

- Quest log: `size <n>`, `dark`, `bg <0-1>`, `voice`, `rate <n>`, `prosody`, `voices`, `usevoice <id>`,
  `say`, `debug`, `dock left|right`, `log replace|blizzard`, `blizzlog`.
- Overlay: `/qb overlay cycle | off | local | zone`, `shape`, `size`, `alpha`, `rotate`,
  `ground auto|native|hybrid`, `bars actions|all|none`, `icons <n>`, `mask`, `diag`.
- Camera: `/qb camera flip | strength <n> | zoomout <n> | zoom <n> | ease <s> | on | off`.
- Strip and drawers: `/qb strip ...`, `/qb drawers open|close|toggle|status`.

`/qb overlay diag` prints the state of the minimap, the hybrid frame and the world map: paste it into
a bug report.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): how the code is organised, how to add a module, how to check
a change without the game (and what that does not prove), and the branch and review flow.

## Branches

`main` = known-good · `dev` = where work lands and is tested in the game.

Built by Cesar & Nibble for the Chavez family's WoW: Forever launch. MIT.
