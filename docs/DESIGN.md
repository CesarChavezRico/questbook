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
  whenever the big one is not in use: overlay Off, Map mode (until v0.14.3), and after the overlay closes itself at combat
  start, which is exactly when it is wanted (v0.14.3: not in Map mode either; Cesar, 2026-10-17: "remove the minimap in both the
  big mini and overland"; the widget stays in its corner panel, which is hidden). Defaults, all tunable live with `/qb overlay corner`: 16%
  of screen height, just under the text strip, 0.9 opacity, rotating with facing, click-through so it never eats a combat click. Chosen as
  defaults to be tuned in the client, not decided by anyone; moving the widget between hosts in combat
  rests on it not being a protected frame (*unverified*). **Its edge** (v0.14.2, *written*; Cesar, 2026-10-17: "lets add the bleed
  out that we have on the big map. I don't like the clear circle form"): v0.7.5 chose the crisp stock circle because the big
  map's soft circle fades over most of its radius and leaves only a small core at this size. v0.14.2 adds `mask_corner.tga`
  (generated by `dev/art/gen_kit.py`): full strength to 58% of the radius, then a smooth bleed to nothing at the edge. It is the
  default (`corner mask soft`; a saved "stock", the old default, moves once); `wide` is the big map's broad circle, `stock` the
  crisp circle. A square or rounded-square corner minimap is not offered.
- **The action bars fade out while a map mode is open** (`bars` setting: actions, all, none). "The
  bars" was read as the action bars; xp and reputation bars are the `all` option.
- **Opacity** has defaults and is tuned live (`/qb overlay alpha`); no target value was ever chosen.

**Region view** (v0.20.0, *written, not yet seen in game*; Cesar, 2026-10-20: in Darnassus the overland map showed only the city, but
the quest (Tears of the Moon, in the Oracle Glade) is on the Teldrassil map above it; "I don't want another keybind ... add it to our
current rotation with the same keybind"). The map shows the player's own map (`TickZone` forces it each tick), and a city's quests are
on its parent zone. The map key's rotation is now Off, Minimap, Overland, Overland one level out, Off: in the overland map the next
press shows the parent map (`C_Map.GetMapInfo(...).parentMapID`, never the world or cosmos) whole, at zoom 1 instead of the 2x
close-up on the player, and the press after that is off. Where the player's map has no parent the extra stop is skipped. The level goes
back to 0 when the state changes or the player's own map changes. UNVERIFIED in game: that the client's `GetMapInfo` gives
`parentMapID` for Darnassus and that the world map can be set to the parent while the player is in the city.

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
- **Dialogue UI at the same time** (Cesar, 2026-10-17, v0.10.1: "the camera wobbles going in and out" when talking to a
  quest NPC with the minimap open). Cause from reading Dialogue UI's public source (`Code/Camera.lua`), not observed in
  the game: it also writes `test_cameraOverShoulder` every 0.03 s towards its own target and moves the zoom, and our
  zoom poll answered each zoom step with a second ease towards ours. Two writers, one CVar. v0.10.2 pauses the camera
  module while a gossip or quest dialogue is open (`GOSSIP_SHOW`, `QUEST_GREETING`, `QUEST_DETAIL`, `QUEST_PROGRESS`,
  `QUEST_COMPLETE`) and takes the CVar up again 0.8 s after it closes (`GOSSIP_CLOSED`, `QUEST_FINISHED`), easing to
  the shift from wherever the dialogue left it; a safety timeout of 120 s covers a close event that never comes.
  *Written, not played.* Unverified: which of those events this client sends.

### The quest log

- **It is a one-page reader** (v0.13.0, *written, not played*; Cesar, 2026-10-17: "I am not fully convinced on the book anymore,
  let's just keep a simple quest reader with the voice options ... right click on the quest opens the detail view, left click
  selects it as active", then: "the position of the dialog should be the same as the big map and there should be the same zoom
  as with the map. If the map is open and a quest is clicked this dialog should replace the map, if the map keybind is clicked
  when this dialog is open the map should come up and this moved off"). It replaces the open book of v0.8.x (two pages, a map
  plate, a right-hand list, a leather cover, a paper/dark theme, a docked walking panel), which is removed; git history keeps it.
- **Where and how:** one torn-paper page (`Style.Paper`, laid out in physical pixels) at the big map's centre and height
  (`Overlay:ReaderRect`), width 0.84 of the height. Title in the book font, the tapering rule, a meta line (level, zone, ready,
  active), a scrolling area with the description and the objectives as rows with check boxes, a row of ink links (previous,
  talk, next on the left; track, share, abandon on the right), the one strong button (make active / clear active quest) and a
  quiet Close with the Esc key cap. Text size: `/qb size <px>` (default 22).
- **It trades places with the map.** Opening it announces `reader_state` true, then closes the map overlay; the camera follows
  both topics, so the shift and the zoom-out never let go in between. The map key while it is open brings the map up
  (`overlay_state` anything but "off") and the reader hides itself. It closes for combat and does not open in combat, like the map.
- **The list is the tracker** (default mode "all", moved once from a saved "tracked"): left click on a quest makes it the active
  one, right click opens it here; the header link is "Log" (opens it on the active quest). The default key, the micro menu
  button and the objective tracker's "open quest" clicks open it too: `ToggleQuestLog`, `OpenQuestLog`,
  `QuestMapFrame_OpenToQuestDetails`, `QuestUtil.OpenQuestDetails` (all restored by `/qb log blizzard` or disabling the module).
- **Walking and the bars** (v0.13.1, *written*; Cesar, 2026-10-17: "we are not dismissing the page when we start walking with
  speak ON ... we need a way to stop the speech with the page minimized, maybe a toggle in the list", and "the quest page should
  also hide the action bars, same as the maps"): the first step with voice on reads the quest and, when the reading started,
  puts the page away (the reading is not stopped by that); with voice off the page stays. The tracker header's voice link says
  "Stop" while a quest is being read (stops it), otherwise "Voice on" / "Voice off" (the walk-and-listen switch). The reader
  hides the action bars like the map modes do (`Overlay:ReaderBars`, same `bars` setting), through the swap with the map too.
- **Room, and what else hides** (v0.14.1, *written*; Cesar, 2026-10-17, with the list at 600 px: "space on top and bottom ... no
  vertical scroll bar for the quest text ... show more quests in the list ... I couldn't find a way to increase the vertical
  size ... not sure what to do with my char portrait and the corner minimap when the page is shown, I am thinking on hiding and
  being more aggressive with the zoom"): the page has no scroll bar (the wheel still scrolls); `/qb reader height <0.3-0.95>|auto`
  gives it its own height (same centre; auto = the map's), `/qb reader aspect`; the list may use 0.62 of the screen height
  (`/qb tracker max`; a saved 0.42 default moves once); while the reader is open it hides the small corner minimap (and so the
  markers) and the player and target frames (alpha, restored on close; `/qb reader hide minimap|frames on|off`, both on by
  default); the camera has a zoom of its own for the reader, `/qb camera readerzoom <n>` (relative like `zoomout`, negative
  zooms in, default 3 = same as the map), and the two trade zooms when the reader and the map trade places.
- **Buffs and debuffs** (v0.15.3; Cesar, 2026-10-17, from a screenshot: "we are hiding the unit frame but not the buffs"): the player's buffs
  and debuffs are their own frames (`BuffFrame`, `DebuffFrame`, Blizzard_BuffFrame/BuffFrame.xml), not children of the player frame, so
  hiding the frame left them floating. They are now hidden with the same alpha tweak (`/qb reader hide auras on|off`, on by default,
  independent of `frames`). The target's auras are children of the target frame and go with it. The big deadly-debuff warning
  (`DeadlyDebuffFrame`) is never hidden.
- **Duties** (unchanged, through Blizzard's own flows): active (the "super-tracked" quest the game points at), track and
  untrack, abandon (through Blizzard's confirmation), share. Walk-and-listen: the first step with the reader open reads the quest
  (once per quest); Talk / Stop reads on demand; the arrows read the quest they land on.
- **Removed with the book:** the map plate and Overlay's "plate" host of the world map frame, `/qb book`, `/qb bg`, `/qb dock`,
  the dark theme of the reader, and the idea of a three-panel layout. The quest-area art stays the client's; the markers module
  draws our own markers on the minimap.
- **Unverified (the client has to say):** how the page looks and fits (text size, scrolling, the link row at the real width), that
  Esc closes it, that the swap with the map looks and feels right, that the camera really holds across the swap.

### The quest areas on the enlarged minimap

- **The problem** (Cesar's screenshot, 2026-10-15): at about six times the stock size the client's own quest-area art
  becomes thick glowing blue outlines and a grey band of large squares, which fights the paper-and-brass look.
- **What was tried and did not work** (v0.9.1, seen in the game 2026-10-16): the Minimap widget has setters for the
  quest, task and archaeology blobs (alpha and texture for INSIDE, OUTSIDE and RING, a ring scalar;
  `MinimapFrameAPIDocumentation.lua`, no getters, no descriptions). Calling them with flat brass textures and
  different alphas was accepted without error and changed nothing visible: `solo` on each layer, and every layer at
  alpha 0, left the same green disc with a pale glow. The texture files were valid. The forever-bugs issue 156
  (2026-09-26) reports that these areas also ignore the minimap's own alpha, which points to the client drawing them
  outside the widget's normal path. Older addon work only ever hid the "waffle" ring (`SetQuestBlobRingScalar(0)`);
  nobody documents replacing the art. The restyle code was removed in v0.10.0.
- **What v0.10.0 does** (*written, not played*): the `markers` module. It switches the areas off through the minimap's
  "Quest POIs" tracking filter (`Enum.MinimapTrackingFilter.QuestPOIs`, `C_Minimap.SetTracking`; remembered and
  given back on disable) and draws its own marker per quest over the big and the corner minimap, from
  `C_QuestLog.GetQuestsOnMap` and `C_Map.GetPlayerMapPosition`, with the distance scale from
  `C_Minimap.GetViewRadius()`. This also gives every quest in the log a marker with the active one highlighted, which
  is what Cesar remembers from retail; the client itself draws only one area.
- **Seen in the game (2026-10-17, v0.10.0):** the markers line up with the client's own quest-giver blips with scale 1.00
  (`/qb markers map`), also while rotating; the look is "ok" and open to rework. Two findings: (1) the markers trailed the
  minimap when turning, because positions were redone 10 times a second; v0.10.1 re-reads where you are 20 times a second
  and rotates the cached offsets every frame, and repaints nothing unless the quest list changes. (2) The client's own
  areas stayed: the status line read "Quest POIs ... now true" after our call. v0.10.1 only adds diagnostics (the status
  shows the entry's name and what the call returned) and answers `MINIMAP_UPDATE_TRACKING`; the cause is not known.
- **Lead, unverified:** the green disc of v0.9.1 disappeared when its setters were removed, so the blob *texture* setters
  may reach the client even though the *alpha* ones did not. A fully transparent texture on the layers could then hide the
  areas without the tracking filter. Not tried.
- **The name label** (v0.14.4; Cesar, 2026-10-17: the active quest's name ran into the action bars on the small minimap): the
  active marker's name is drawn beside it on the big minimap only; the small minimap shows the marker without a name, since the
  list already names the active quest with its gold bar. (Fitting the name inside the small minimap, or a short form, were the
  alternatives.)
- **Unverified (the client has to say):** that the tracking filter removes the areas (and not the quest-giver "!"
  blips with them); that `GetViewRadius()` is centre-to-edge as drawn on the enlarged widget (`/qb markers scale`
  corrects it, `/qb markers map` draws quest givers so the markers can be lined up with the client's own "!" blips);
  that the rotation formula matches the client's.

### The tracker

- **A compact list replaces Blizzard's objective tracker** (*written*, v0.9.0; Cesar, 2026-10-15: "a replacement of
  the original quest list, with a toggle to open the book"). Under the corner minimap: your tracked quests
  (`/qb tracker all` for every quest) with up to three objective lines each, the active quest marked, "ready"
  quests in green, a "Book" link in the header. Since v0.11.0: left click makes a quest the active one, right click opens
  it (Cesar, 2026-10-17). It is a glance
  surface, so it uses the dark panel, not paper. Blizzard's `ObjectiveTrackerFrame` is hidden while it is on and
  restored by `/qb disable tracker`. **Interpretation, not confirmed:** I read "the original quest list" as that
  tracker. *Unverified*: that hiding the frame is honoured, and what else lives in it (world quest, bonus and
  scenario objectives, achievements, auto-accept pop-ups) that is lost while it is hidden.

- **The list in the new look** (v0.14.0, *written, not played*; Cesar, 2026-10-17: "lets move on to the list"): the type ramp
  of the kit in whole pixels (quest title 21, objective lines 17, header 16; `/qb tracker size <px>` scales all three), the
  panel 400 px wide (`/qb tracker width <px>`; the older `width` in UI units is no longer used), a rule under the header that
  tapers to nothing (the reader's art, tinted for the dark panel), the active quest as the only accent (gold title and a 3 px
  bar at the row's left edge), "ready to turn in" in green, counted objectives (`numFulfilled / numRequired`, summed over the
  quest) as a 4 px bar under the lines, links drawn with `Style.InkLink` (pixel text, 1 px rule) in cream on dark. The
  "(ready)" and ">" text marks are gone. Not done: a quest-type icon (campaign, daily): the client's icon assets for it are
  not known here.
- **Level and toggle** (v0.14.5, *written*; Cesar, 2026-10-17: "do we have access to the quest level? let's add it to the list, also we need a
  way to toggle the list"): yes, `C_QuestLog.GetInfo` gives `level` (the reader's meta line already showed it). It is a faded
  numeral before the title (`/qb tracker level on|off`); difficulty colours were not used, to keep the active quest the only accent. The
  whole list is put away and brought back with a key binding ("Show / hide the quest list", none bound by default) or
  `/qb tracker toggle|show|hide`; the state is saved, a log update does not bring it back, and `/qb tracker move` shows it first.
  v0.14.6 adds the state between: the title ("QUESTS 9") is a link; a click collapses the list to its title row (the
  Voice and Log links stay, so there is always something on screen to click), another click expands it; saved,
  `/qb tracker collapse|expand`.
- **Rows: level at the right, indented objectives, Play** (v0.18.0, *written, not yet seen in game*; Cesar, 2026-10-20: "a button to
  play the read out loud from the quest list", "the quest objectives indented from the title", "the level on the right hand side of the
  quest in between [ ]"): each row has a right-hand column 64 px wide: the level as `[9]` (faded, same size as the title, replacing the
  numeral before the title; `/qb tracker level off` still hides it) and, under it, a Play link. Play is a button of its own (a click on it
  does not make the quest active) that calls `questlog:PlayQuest(questID)`: it reads that quest with its giver's slot whatever the reader
  shows, and says Stop while that quest is the one being read (`SpeakingQuestID`); a second quest replaces the first. The title and the
  objectives stop short of the column; the objectives (and the progress bar) are indented 18 px from the title. A title longer than the
  column wraps earlier than before: widen the list with `/qb tracker width`.
- **Shift-click a quest** (v0.18.1, *written, not yet seen in game*; Cesar, 2026-10-20: "shift click the quests from the list into the
  chat or the ai chat"): shift + left click on a row calls the game's link-insert function (`ChatFrameUtil.InsertLink`, else
  `ChatEdit_InsertLink`) with the quest's link (`C_QuestLog.GetQuestLink`, else `GetQuestLink`, else one built by hand). Blizzard's
  boxes take it as usual; the WoW AI chat's input takes it through a hook already in the relay addon (`TakeLink`, when that box has
  the keyboard; its `ExpandLinks` then sends the quest's tooltip with the message). With no box open nothing is inserted and a chat
  line says so. Shift + right click still opens the reader; the active quest is not changed by a shift-click.
- **Pages** (v0.19.0, *written, not yet seen in game*; Cesar, 2026-10-20: "show more quests in the list, maybe pages ... a tab controller
  next to QUESTS to move between the pages of 10"): the list shows up to `perPage` quests (default 10; `/qb tracker perpage <n>`, 1 to
  40) and never more than fit in the panel, so a bigger font makes shorter pages and no quest is out of reach (the old "+ N more in
  the log" link is gone). Row heights are measured on a scratch row, pages are cut greedily, and the current page is kept in memory
  only (`/qb tracker page <n>` too). The tabs "1 2 3" sit right of the title, the current one in the warn colour, and show only when
  there is more than one page. The game's limit on quests in the log is `Constants.QuestLogConsts.MAXIMUM_NUM_QUESTS_LOG_CAN_ACCEPT`,
  40 in the Forever API dump (`C_QuestLog.GetMaxNumQuestsCanAccept()` in game says what this client really allows; UNVERIFIED).
- **It has a position of its own** (v0.11.0, *written*; Cesar, 2026-10-17: "when I open the big overlay the quest list
  moves up", then "the list position should be independent from the map"). The list used to hang under the corner
  minimap and jumped to the screen corner whenever the big overlay hid the small minimap. Now its position is its own
  (`x`, `y`: the offset of its top-right corner from the screen's, seeded once from where the corner minimap sits so it
  starts where it was). `/qb tracker move` drags it, `pos <x> <y>` sets it, `reset` seeds it again; `/qb overlay corner
  move` drags the small minimap. Both use one drag handle (`Style.Mover`): drag, right-click to finish.

### The paper look and pixels (v0.12.0)

- **Direction** (Cesar, 2026-10-17: "take better advantage of our big display ... pixel perfect ... spectacular"): take
  design *principles* from Dialogue UI (torn parchment, quiet type hierarchy, one strong colour, key-cap hints), with
  our own art, and build the reader and then the tracker from a shared kit. See docs/STYLE.md, "Pixels and the next
  paper look".
- **Order** (Cesar chose A): the kit and the reader together (the reader replaces the book: one page, right click opens
  it, the key opens it on the active quest), then the tracker restyle. v0.12.x was the kit's first step (v0.13.0 builds the
  reader on it, see The quest log); the tracker restyle is next. v0.12.0 itself was only: the
  textures, `Style.Px` / `Style.Paper` / `Style.Hairline`, `/qb screen` and a `/qb kit` sample page, so the look can
  be judged in the game before the reader is built on it.
- **Decided for the reader** (Cesar, 2026-10-17, "on point"): one page (title, objectives, text, voice controls), previous
  and next arrows; the default key and the micro-menu button open it on the active quest; the book's right-hand list, the
  map plate and the open-book look are removed; the tracker defaults to "all quests"; the Book link becomes "Log".
- **Seen in the game (2026-10-17, v0.12.0 `/qb kit`):** screen 3440x1440 px, UI 2867x1200 units, effective scale 0.640,
  so 1 px = 0.8333 units. Text "looks good". Two findings: (1) the page interior was darker than its rim, a layering bug
  of mine: the full-screen darkening shared a sublevel with the paper fill and drew over it, so only the strips and
  corners showed true colour (fill is now one sublevel above the darkening, strips and corners above the fill);
  (2) the torn edge wanted "bigger tears", as in Dialogue UI's page (notches several tens of pixels long): v0.12.1 adds
  bites (a slow ramp, a steep drop) and narrow V cuts, tears are 1024 px long on top and bottom and 512 px at the
  sides so they are not stretched much, and each of the four sides has its own tearing, not a mirror of its opposite.
  The scroll-like curled corners of Dialogue UI's page are not attempted.
- **Seen in the game (2026-10-17, v0.12.1):** "the kit looks great", the interior bug is gone, the 1/2/3 px lines read as
  three distinct widths. Asked for: darker borders and a few more tears. v0.12.2: the page darkens toward its edge (a
  scorched line in the last 5 px and a broad soft shade over about 34 px, browner as it darkens), bites about one per 155
  px (was 210), V cuts one per 330 px, plus small nicks about one per 130 px.
- **Unverified (the client has to say):** that the generated page looks right at Cesar's size (3440x1440 physical), that
  `SetRoundLayoutToNearestPixel` and the pixel arithmetic give 1 px lines, and that tiling the 256 px grain with
  `SetTexture(file, "REPEAT", "REPEAT")` shows no visible repeat.

### The relay voice (v0.17.0; 4BI-38 steps 2 and 4, the QuestBook side)

- **Direction** (Cesar, 2026-10-18): a much better voice than the game's text-to-speech. The audio plays OUTSIDE the game: with
  `/qb voice engine relay` the reader sends the words to the WoW AI bridge on the rig over the pixel strip (`WoWAI.SendTts`, in the
  wow-relay addon; the bridge's `bridge/tts.js` makes the audio with ElevenLabs, caches it by hash and plays it). The default engine is
  still the game's own voice; a missing or disconnected relay falls back to it (and says why, at most once a minute).
- **What goes out:** `play` with the title and the description (no "ready to turn in" prefix, so the text does not change between the
  prefetch and the reading and the bridge's cache holds); `stop`; `prefetch` when a quest is accepted (after the giver is recorded; off with
  `/qb voice prefetch off`). The slot goes in the record's name field; the reference is `q<questID>`.
- **Voice slots by giver:** narrator (no giver recorded), male or female by the giver's gender, creature for a beast, dragonkin, demon,
  elemental, giant, mechanical, aberration or critter (an undead person is still a man or a woman). The bridge maps slots to ElevenLabs
  voices (`tts.voices` in its config). Per-NPC overrides and the reader's quick-pick are not built yet.
- **Talk / Stop is an estimate:** the strip only goes one way, so the game is not told when the reading ends. The state lasts about
  14 characters a second (at least 3 seconds), or until Stop or the next reading. Stop and the tracker's Stop link send a `stop`.
- **Commands:** `/qb voice engine game|relay`, `/qb voice prefetch on|off`, `/qb voice test` (the bridge speaks a test line),
  `/qb voice slot` (what the quest on the page would use).
- **Unverified (needs the rig):** all of it end to end; the ElevenLabs call and the playback live in wow-relay (pull request 12 there).

### The quest giver (v0.16.0; 4BI-38 step 1)

- **Why:** the voiceover will pick a voice by who gave the quest (creature type and gender, a per-NPC override, a quick-pick in the
  reader), and the reader shows "From <name>". The NPC is only there while its dialog is up, so the `giver` module records it when
  you accept a quest: the accept dialog (`QUEST_DETAIL`) remembers who is offering which quest, `QUEST_ACCEPTED` commits it (retail
  gives `(index, questID)`, older clients only the index, which is looked up in the log). Kept per quest in the saved variables:
  name, gender (the game's 1 / 2 / 3), creature type, NPC number (from the unit's GUID, `Creature-0-server-instance-zone-NPC-spawn`),
  zone. Capped at 500 quests, oldest dropped.
- **Not recorded:** a quest started from an item (nobody to talk to); the NPC's race (the game gives none); the turn-in NPC (it is
  only known at hand-in, when the quest has left the log). A quest shared by a party member is a player: name kept, no NPC number.
- **UNVERIFIED (the client has to say):** that `UnitName("npc")`, `UnitSex`, `UnitCreatureType` and `UnitGUID` answer for the quest
  giver on this client and what they return; `/qb giver` prints the last thing seen, so one accepted quest settles it.

### The experience bar (v0.15.0)

- **Direction** (Cesar, 2026-10-17: "I want to fold the experience info into the menu on top right", then, offered a bar, text in
  the strip, or a header in the Menu drawer: "let's see how the bar looks, go for it"): the `xp` module draws a thin bar under
  the strip (3 px by default, whole pixels, 360 px wide, right-aligned with the strip): XP in gold on a faint track, the rested
  part as a lighter blue extension (the one cool hue, because it means something different). No numbers on it; hover for level,
  XP / max (percent), to go, rested. It hangs on the strip's frame (`strip:GetFrame`), or in the screen corner if the strip is off.
- **The number** (v0.15.1; Cesar, 2026-10-17, after the first look: "we need the number so its easier to mouse over"): "Lv 8  44%" above
  the bar, right-aligned, 15 px; the frame is the bar and the number together, so the hover area is about 23 px tall instead of 3
  (`/qb xp text on|off`, `textsize <px>`). The percent is floored (never 100% before the level is done).
- **The Menu drawer and the rested percent** (v0.15.2; Cesar, 2026-10-17, from a screenshot: "the menu overlaps with the bar, also we need the
  rested xp in [ ] as a percent if avail"): the drawer used to open at the strip's bottom edge, over the xp row. The xp module reports the
  room it takes (`RowExtent`, announced on the bus topic `xp_layout` when it changes) and the drawer opens below it
  (`AnchorPanel`). The number reads "Lv 8  44%  [14%]": the rested XP as a percent of the level, only when there is some.
- **Blizzard's bottom bar** (`StatusTrackingBarManager`) is faded out by alpha while ours is up (`/qb xp blizzard off` leaves it);
  at the maximum level or with XP gain off our bar hides and Blizzard's comes back, since it also carries reputation and honor,
  which this module does not take over. The overlay's own fading of the same frame in map modes (`bars all`) is unaffected: the
  alpha this module records as "original" is never 0.
- **Not built yet, offered:** "Lv 8" in the strip text; the watched reputation (or honor) in the bar after the maximum level;
  numbers in the Menu drawer. The reputation functions on this client are unchecked.
- **Unverified (the client has to say):** how it looks; `UnitXP`, `UnitXPMax`, `GetXPExhaustion` and the XP events here; that
  hanging under the strip works with the Menu drawer opening over the same place.

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

- **Quest markers on the minimap** are written and not yet played: see The quest areas on the enlarged minimap.
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
