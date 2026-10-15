# QuestBook: style brief

How the addon should look, and the rule that keeps surfaces consistent. Short on purpose: if you
add a surface, read this first; if you change the look, change this file in the same PR.

## Two visual languages, split by what you do with the surface

| you... | the surface is... | looks like |
|---|---|---|
| **glance** at it during play (strip, drawers, corner minimap, map overlay) | quiet, translucent, gets out of the way | the faint dark panel: dark fill at about 0.45 to 0.6 opacity, text in the warm cream colour, no ornament, no frame art, soft edges where it meets the world |
| **stop and read** it (the quest book) | a paper object | parchment pages in a dark leather cover, ink-coloured text, a red accent for headings |

Do not mix them on one surface: a half-paper panel looks worse than either. The paper theme is a
**setting** (`/qb book paper|dark`), because a look that delights on day one can tire by day thirty.

## The paper theme

- **Pages:** flat parchment colour, not Blizzard's paper textures (they cost contrast in this
  client). Two pages side by side with a faint shade along the spine, drawn as a few thin strips.
- **Ink, not UI colours.** Gold and green that read on a dark panel vanish on parchment, so the
  paper palette re-inks everything darker: body ink, strong ink, faded ink, a red "rubric" for
  headings and the active mark, a dark green for "done". All of them live in `Style.lua`; never write a
  colour literal in a module for a paper surface.
- **No text shadow** on paper: the default black shadow turns ink into a smudge.
- **Fonts:** the game's book font (Morpheus) only at display size (18 pt and up; its lowercase turns
  to glyphs below that), for the quest title. Everything else in the normal UI font. If the client
  refuses the Morpheus file the title falls back to the normal font.
- **Selected and hovered rows** are shaded with ink at low alpha, not a bright highlight.
- **Hairlines** (rules, borders) are ink at about 45% opacity, so the paper shows through.
- Stock widgets (buttons, close button, scroll bars) are still Blizzard's; only the widely used ones
  are borrowed, to keep taint risk low. They look out of place on paper and are the next thing to
  restyle if the theme stays.

## Fit rules (the book)

- **The whole quest list is on the page.** Rows shrink (down to 16 px, font 9) so every quest in the
  log fits; only a log too long even for that scrolls.
- **The quest text fits its page.** The map plate shrinks first (to about a fifth of the page), then
  the font (never below 11), and only then does the page scroll. The set font size is the maximum.

## What is not converted yet

The strip, the drawers, the corner minimap and the overlay still carry their own colour literals
(the glance language). They should read their colours from `Style.THEMES.dark` too; that is a
mechanical change worth doing before a third surface is added.

## Credit

The two-languages idea, the flat-colour-over-textures finding and the font caveat come from studying
the Social Diary addon (github.com/social-diary/social_diary, MIT) and its design brief. No code was
copied; the palette and layout here are our own.
