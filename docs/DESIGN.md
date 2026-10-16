# QuestBook: design and decisions

What the addon is for, what was decided and why, what has been seen working, and what is still open.
Written for a new contributor. Status is as of **2026-10-13 (v0.8.0)**. A claim marked *seen* was
reported working in the game by Cesar; *written* means the code exists and has not been seen working;
*unverified* means it rests on a reading of Blizzard's UI source that nobody has confirmed in the client.

## Purpose

Three annoyances with the stock Forever UI, and one addon that answers all of them:

1. The quest log's text is small and cramped, and reading it is how you navigate (the project
   deliberately avoids quest-finding addons).
2. On a 21:9 ultrawide the minimap is small and far from where you look, and the full map covers the
   screen. The wanted feel is an action-RPG overlay: a translucent map over the playfield.
3. The default menu icons, bags and addon buttons sit in awkward places.

The target is the Forever client's UI (it is derived from Blizzard's retail 12.x UI). Retail is untested.

## How it is built

One addon, five isolated modules (`questlog`, `overlay`, `camera`, `strip`, `drawers`) on a small Core.
The module contract and its rules are in [CONTRIBUTING.md](../CONTRIBUTING.md). The reasons for the split:

- **A fault in the risky parts must not take down the quest log.** Camera settings and re-anchored
  Blizzard frames are the risky parts; the quest log is the one thing you cannot play without.
  Every entry point is protected, every module has an off switch, and a module that cannot run on a
  client reports `unavailable` with a reason.
- **Everything we change on a Blizzard frame is restored** on "off" and on disable, so any module can
  be switched off live.
- **Blizzard's quest log stays reachable** as a fallback (`/qb blizzlog`, `/qb log blizzard`) until the
  replacement has been lived in.

It was one addon (the quest reader) and one idea (the map) before; they were merged because they share
a layout (the freed corner slot) and a link (the active quest), and the reader's old "no navigation help"
charter was dropped on purpose.

## Decisions

### The map overlay

- **Two separate modes on one key: Off, Minimap, Map.** They were layered once (Minimap with the map
  behind it); the layered view did not work in the game and was replaced. The key is an assignable
  keybinding; which physical key it gets is the user's choice. A toggle, not hold-to-peek.
- **The Minimap mode is the real native `Minimap` widget**, moved into our panel and enlarged. It is not
  a copy and not our own drawing. Reason: blips (gather nodes, tracked units), quest areas and the
  player arrow are drawn by the client; we found no API that exposes them to Lua (searched the generated
  API docs; not proven), so a custom minimap could not show them.
- **The widget must stay square.** Stretched to a rectangle, the ground (drawn square) and the pins
  ended up on different scales (seen 2026-10-10). The panel is square for Minimap mode and follows the
  `aspect` setting for Map mode.
- **The soft edge is a mask texture on the native minimap** (`Textures/mask_*.tga`, a wide smooth
  alpha falloff). *Seen working* 2026-10-10 ("our soft mask looks great"). History worth knowing:
  an earlier note claimed the native minimap ignores soft masks; that was wrong, a confound of the
  stretched widget (the visible line was the ground's own edge). The wrong claim cost a build.
- **Do not use Blizzard's hybrid minimap art as the default ground.** It draws the painted zone map at
  minimap scale: pixelated and not the real terrain (rejected 2026-10-10). It exists as
  `ground hybrid`, and Blizzard turns it on itself in some places (indoors); `ground native` suppresses
  that. Whether the native ground has anything to draw in those places is *unverified*.
- **The Map mode is Blizzard's own `WorldMapFrame`, restyled**: borderless as far as possible,
  translucent, click-through, centred on the player, soft-edged. *Seen working* ("perfect",
  2026-10-10). Two things made it work that are easy to break:
  1. Blizzard's map canvas only masks textures **registered** with it (`AddMaskableTexture`), and only
     while a mask is set. Tiles built before our mask existed were never masked (a hard edge). The mask
     is set before the map is shown and every live tile is registered.
  2. The map is kept fully transparent until it is styled, masked and positioned (three frames), or the
     whole zone flashes before it zooms to the player.
- **Its pins are Blizzard's own** (quest markers, party, waypoint) and stay visible; we only stop them
  catching the mouse. A custom map canvas that rotates with the player was designed (a grid of tile
  textures from `C_Map.GetMapArtLayers` / `GetMapArtLayerTextures`, scale matched with
  `C_Map.GetMapWorldSize` and `C_Minimap.GetViewRadius`, behind a small show/hide/centre/rotation
  interface) and **deferred** until the restyled frame has been lived with. Its cost is redrawing the
  pins ourselves. It needs per-texture rotation and a player-facing getter, which nobody has checked
  exist in this client.
- **Rotation:** the Minimap mode rotates with facing by default (`rotateMinimap`), toggleable. The
  hybrid ground cannot rotate. The Map mode is always north-up (a frame cannot rotate).
- **Combat guard:** the toggle is ignored in combat and the overlay closes when combat starts (both
  settings). The frames involved are not protected as far as the UI source shows; every step is
  protected and retried after combat, but this is *unverified* in real combat.
- **A small corner minimap, for glancing in combat** (*written*, v0.7.5). There is one native `Minimap`
  widget, so there cannot be a second live copy: it has two hosts, the big panel (Minimap mode) and a
  small square panel in the top-right corner, where the retired minimap used to be. The corner one is up
  whenever the big one is not in use: overlay Off, Map mode, and after the overlay closes itself at combat
  start, which is exactly when it is wanted. Defaults, all tunable live with `/qb overlay corner`: 16%
  of screen height, just under the text strip, a crisp circle (the soft mask eats too much of a small
  circle), 0.9 opacity, rotating with facing, click-through so it never eats a combat click. Chosen as
  defaults to be tuned in the client, not decided by anyone; moving the widget between hosts in combat
  rests on it not being a protected frame (*unverified*).
- **The action bars fade out while a map mode is open** (`bars` setting: actions, all, none). "The
  bars" was read as the action bars; xp and reputation bars are the `all` option.
- **Opacity** has defaults and is tuned live (`/qb overlay alpha`); no target value was ever chosen.

### The camera

- While the overlay is open the camera is slid sideways so the character sits left of centre and the
  map takes the freed right side, and pulled back a little. *Seen working* (the sideways shift,
  reported 2026-10-12); the zoom-out (default 3, `/qb camera zoomout`) is *written*.
- Method, borrowed from the Dialogue UI addon (public source): the `test_cameraOverShoulder` CVar,
  scaled with camera zoom, eased in and out. Gentler than Dialogue UI by design. While shifted,
  `CameraKeepCharacterCentered` and `CameraReduceUnexpectedMovement` are forced to 0 (they override the
  offset).
- **Every CVar is backed up in saved variables before the first change and restored from there**, also
  at the next login if the game was closed with the overlay open (*unverified*: nobody has crashed it).

### The quest log

- **It is an open book** (v0.8.0 and v0.8.1, *written*): left page the quest text, right page the list. The whole
  list fits its page (rows shrink to a 16 px minimum); the text fits its page (map plate shrinks first, then
  the font down to 11, then it scrolls). Parchment theme by default, `/qb book dark` for the faint dark
  panel. Chosen by Cesar from a mock-up on 2026-10-13: option A (map and text stacked on the left page)
  over option B (ribbon tabs); a three-panel variant with a thinner list is **open**. Style rules:
  [STYLE.md](STYLE.md).
- **The map plate** (*written*, v0.8.1): above the quest text on the left page, the quest's map with Blizzard's own
  quest area and pins. It is the same world map frame the overlay's Map mode restyles, hosted inside the plate
  (crisp edge, opaque, above the book) by the overlay module, which owns that frame; the position comes from
  the game's next-waypoint for the quest, else the quest's marker on the player's map or its parents. There is one
  world map frame, so Map mode and the plate exclude each other (opening one closes the other, and the book
  re-fits). No plate in combat (retried when it ends), in the docked walking panel, or for a quest with no map
  position; `/qb book map off` turns it off. *Unverified*: that the frame can be hosted this way in the client.
- **It replaces Blizzard's.** Duties: choose the active quest (the "super-tracked" one the game points
  at), track and untrack, turn-in readiness, abandon (through Blizzard's own confirmation), share,
  zone and campaign headers. The reader and the narrated walk-and-listen mode *were seen working* in
  earlier versions; the duties and everything below are *written*.
- **Several Blizzard entry points open it**, because the default key is only one of them:
  `ToggleQuestLog` (key, micro menu button), `OpenQuestLog`, `QuestMapFrame_OpenToQuestDetails`
  (objective tracker click) and `QuestUtil.OpenQuestDetails`. A first build replaced only the first and
  Blizzard's list kept appearing. All are restored by `/qb log blizzard` or disabling the module.
- **Look:** the faint dark panel with a hairline edge that the Menu drawer uses (`/qb bg`).
- **Active quest and the map:** the intended link is that choosing the active quest in the book makes
  the game's quest markers point at it. The blue quest areas on the minimap are native; they are not
  ours to draw.

### The quest areas on the enlarged minimap

- **The problem** (Cesar's screenshot, 2026-10-15): at about six times the stock size the client's own quest-area art
  becomes thick glowing blue outlines and a grey band of large squares, which fights the paper-and-brass look.
- **What the game allows** (`MinimapFrameAPIDocumentation.lua`): setters only, no getters, no descriptions. For the
  quest blob, the task blob (world quests) and the archaeology blob: an alpha and a texture for each of INSIDE,
  OUTSIDE and RING, and a ring scalar. The functionality (the areas themselves, where they are) stays the
  client's; we only restyle it.
- **What v0.9.1 does** (*written*): replaces the textures with flat brass ones, so the look is ours: a faint fill
  (0.14), a clear outline (0.80), no halo, and an outline thickness that follows the size (`auto` = stock width /
  our width, so the big minimap does not get a fat band). Applied to the quest and task blobs, not archaeology.
  `/qb overlay blobs` tunes every part live; `native` leaves the client alone (it takes a `/reload` to come back,
  since the client's own values cannot be read).
- **Unverified:** which layer makes which part of the ugly look, whether the scalar thins the ring, and whether a
  flat texture is accepted as a blob texture. The `solo` command exists to answer the first from one screenshot.

### The tracker

- **A compact list replaces Blizzard's objective tracker** (*written*, v0.9.0; Cesar, 2026-10-15: "a replacement of
  the original quest list, with a toggle to open the book"). Under the corner minimap: your tracked quests
  (`/qb tracker all` for every quest) with up to three objective lines each, the active quest marked, "ready"
  quests in green, a "Book" link in the header, and a click on a quest opens the book on it. It is a glance
  surface, so it uses the dark panel, not paper. Blizzard's `ObjectiveTrackerFrame` is hidden while it is on and
  restored by `/qb disable tracker`. **Interpretation, not confirmed:** I read "the original quest list" as that
  tracker. *Unverified*: that hiding the frame is honoured, and what else lives in it (world quest, bonus and
  scenario objectives, achievements, auto-accept pop-ups) that is lost while it is hidden.

### The strip and drawers

- **The corner minimap is retired** and its slot reused. In its place, a one-line text strip (zone,
  coordinates, mail) that also opens Blizzard's full map on click.
- **The Addons button is Blizzard's addon compartment**, re-anchored to the strip so retiring the
  minimap cluster does not take it along. Whether the compartment exists in Forever is *unverified*
  (inferred from the TOC). Old-style round minimap buttons from libraries are **not** covered.
- **The Menu drawer re-anchors Blizzard's own `MicroMenu` and `BagsBar`** into one quiet panel instead of
  recreating them, so alert pulses and bag slots keep working. It moves `MicroMenu`, not its Edit Mode
  container: Blizzard's code lets the micro menu live elsewhere, so there is no container position to
  fight; hooks re-assert our parent and anchor if Blizzard re-parents it. Opens on click, closes on an
  outside click or combat start. The look (font, faint background) was liked; adding and removing bags,
  drag and drop onto bag slots, and the Edit Mode interaction are *unverified*.

## What has been seen working

| area | state |
|---|---|
| Minimap mode: real ground, square, soft edge | seen (2026-10-10) |
| Pins in Minimap mode after the widget was made square | not re-reported |
| Map mode: masked, no flash, centred | seen (2026-10-10) |
| Minimap indoors (real ground kept) | fix written (v0.7.3), not re-reported |
| Camera sideways shift | seen (2026-10-12) |
| Camera zoom-out, crash restore | written |
| Small corner minimap | written (v0.7.5) |
| Action bars hidden in map modes | written, not re-reported |
| Strip, Menu drawer look | seen; bags and Edit Mode behaviour not reported |
| Quest reader, narration | seen (earlier versions) |
| Quest-log duties, reroutes | written |
| Everything in combat | never exercised |

## Open

- **Quest areas: which layer is which.** The client draws each area in three layers (inside, outside, ring) and the
  docs describe none of them; `/qb overlay blobs solo <layer>` shows one at a time. Until someone has looked, the
  defaults are a guess (see The quest areas, below).
- **Which extra pin kinds** a future custom map shows (flight points, vignettes, points of interest).
- **A new name.** The addon keeps the name `QuestBook` until its first merged release, then is renamed
  (repo name, install folder, whether `/qb` stays as an alias, whether `QuestBookDB` is kept so settings
  carry over).
- **Release cadence**, see [CONTRIBUTING.md](../CONTRIBUTING.md#pipeline-dev-main-releases).

## Things learned the hard way

- A saved setting beats a changed default (Core only fills missing keys). Version your migrations.
- The stub-based smoke tests cannot see a real frame's behaviour. Two builds of "fixes" were wrong until
  a screenshot arrived. Ask for a screenshot and `/qb overlay diag` early.
- A wrong claim in a note or PR gets copied into the next decision. When a claim turns out wrong, say
  so where it was made.
- Read Blizzard's UI source (`github.com/Gethe/wow-ui-source`, branch `forever`) before guessing; it
  settled the mask-registration bug and the quest-log entry points.
