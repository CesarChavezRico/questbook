# QuestBook

A quest log you can read, and the HUD around it — for World of Warcraft: Forever
(and retail). One addon, built as isolated modules: a fault in one cannot take
down the others (`/qb modules`, `/qb errors`, `/qb disable <module>`).

> **Status: v0.7.0, first build of the merged addon. Nothing in the overlay,
> camera, strip or drawers modules has run in a game client yet.** The quest-log
> module is the tested v0.6 reader plus new duties (also not yet run). Each module
> is written against the Forever client's UI dump and says `UNVERIFIED` in its
> comments wherever it relies on a guess. Design and decisions:
> `notes/2026-10-09-hud-map-addon-design.md` in the 4bits-cesar repo.

## Modules

| module | what it does |
|---|---|
| `questlog` | The readable quest log and the replacement for Blizzard's: choose the active quest, track / untrack, turn-in readiness, abandon, share, zone / campaign headers. Walk-and-listen narration. The default quest-log key and the micro menu button open this book. |
| `overlay` | The map as a translucent layer beside your character: **Off, Local, Local + Zone** on one key. Local is the real minimap, blown up; Zone is the world map, restyled. Rectangle or circle, soft edge, no frame. |
| `camera` | Slides the camera sideways while the overlay is open so the character sits left of centre (the same trick as Dialogue UI, gentler). Backs up your camera settings and restores them. |
| `strip` | A minimal text strip where the minimap used to be: zone, coordinates, mail. Click it to open the Full map. Hosts the drawer handles. |
| `drawers` | The Menu drawer (Blizzard's micro menu and the bag bar, re-anchored) and the Addons button (Blizzard's addon compartment). |

Blizzard's own quest log stays reachable as a fallback: `/qb blizzlog`, or
`/qb log blizzard` to give the default key back to it.

## Keys

Options > Keybindings > AddOns > QuestBook: **Toggle quest log**, **Map overlay: cycle**,
**Open the Full map**. No key is assigned by default.

## Commands

`/qb` toggles the book. `/qb help` lists every subcommand, `/qb modules` shows which
modules are on, unavailable (with the reason) or off.

- Quest log: `size <n>`, `dark`, `voice`, `rate <n>`, `prosody`, `voices`, `usevoice <id>`,
  `say`, `debug`, `log replace|blizzard`, `blizzlog`, `dock left|right`.
- Overlay, camera, strip, drawers: `/qb overlay`, `/qb camera`, `/qb strip`, `/qb drawers`.

## Install

Clone (or unzip a Release) as `Interface/AddOns/QuestBook`. The repo root is the
addon root. Settings live in `QuestBookDB`.

## Branches

`main` = known-good · `dev` = live iteration (the beta lab runs on dev).

Built by Cesar & Nibble for the Chavez family's WoW: Forever launch. MIT.
