# EllesmereUI offline configurator

A single web page that previews and edits an EllesmereUI settings file without the game
running (4BI-39). Open `elle-config.html` in a browser; it needs no server and no network.

## Use

1. Copy `WTF/Account/<account>/SavedVariables/EllesmereUI.lua` and keep the copy as a backup.
2. Open `elle-config.html`, load the file, and edit. The right-hand panel lists every value changed.
3. Press "Download edited file". With the game fully closed, put the downloaded file in
   `SavedVariables` in place of the original. The game rewrites the file on logout and on
   `/reload`, so a swap made while it runs is lost.

"Screenshot behind" lays a screenshot under the drawing, to compare the preview with the game.

## What it covers

- Action bars and cooldown manager bars: position, size, spacing, rows, shape, border, hidden.
- Unit frames are drawn as dashed boxes for orientation only. Their size is rough and they
  cannot be edited.

## Limits

- It is a layout mockup. Fonts, textures, glows and spell icons are not drawn.
- The settings file only stores values that were changed. Everything else falls back to
  EllesmereUI's defaults, which `src/model.js` holds as plain values (read from v9.8.4 on
  2026-11-10). An EllesmereUI update can change a default or rename a setting.
- The preview has not been compared with the game yet. Until it is, treat it as unproven.
- A bar that was never moved has no position in the file and is not drawn.
- The number of cooldown icons depends on the character's spells; the page uses the count the
  file remembers, or a guess, and never saves it.

EllesmereUI has no licence file, so it is treated as all rights reserved. This tool reads the
settings file and mirrors how the settings behave; it contains no EllesmereUI code or art.

## Develop

```
node dev/elle-config/build.js                      # src/ -> elle-config.html
node dev/elle-config/test/run.js                   # checks against test/fixture.txt
node dev/elle-config/test/run.js path/to/EllesmereUI.lua   # also checks a real file
```

The tests need `npm ci` in `dev/` (real Lua, through wasmoon, confirms that a written file
loads as the same data). Never commit a real settings file: it holds character names.
