---
name: MagicMobile download site
description: Arena, like the apps. The Hall and Cut to Play in one page, with the game's real D20 in the bar.
colors:
  canvas: "#0c0d11"
  bar: "#08090c"
  bar-rule: "#e8b25a"
  ink: "#f2ebdb"
  ink-soft: "#c2b8a6"
  gold: "#fad685"
  hairline: "rgba(232, 190, 112, 0.55)"
  glass: "linear-gradient(rgba(26, 28, 36, 0.92), rgba(10, 11, 15, 0.95))"
  orange: "linear-gradient(#ffb24a, #f47a1c 48%, #c9420d)"
typography:
  display: "Source Serif 4 Variable, 900, letter-spacing -0.035em (the one-word cuts)"
  title: "Source Serif 4 Variable, 700"
  text: "system sans (-apple-system, Segoe UI, system-ui)"
---

# Design

The site wears the apps' Arena look (`docs/ARENA_STYLE.md`, `apps/web/src/ui/menus/menus.css`): dark glass in a gold
hairline, Arena's orange pill for the one action, serif titles over sans text, and commander art as the light. One
accent, the orange; gold is the hairline. Tokens are at the top of `src/style.css`; the privacy, support and join pages
repeat the few they need inline.

## The page

Caleb's pick of three mock-ups (October 23–24, 2026): **The Hall** and **Cut to Play** in one page.

1. **The bar** (Cut to Play): the wordmark, the D20 in its socket, and iPhone / Android / Browser at the wordmark's
   weight. Your own screen is orange and goes straight to the download; the others go to their row below. On a phone
   only your own shows.
2. **Hard cuts**: *Commander.* (the Ur-Dragon's art, its card in front of the word), *Draw.* (the Opening Hand screen)
   and *Attack.* (the landscape board in a phone bezel). Screens are whole and level, with the word beside or under
   them, never over them.
3. **The Hall**: a pinned sideways walk past seven exhibits, one per way to play, each a commander's art, its card, a
   giant Cut word (Play, Climb, Build, Host, Challenge, Classic, Learn) and a glass label. The room's light takes each
   commander's colour identity; the index of medallions jumps; the Ranked badge climbs Bronze to Mythic.
4. **The roll** (the peak): a pinned stage where the bar's real 3D D20 leaves the bar, plays one of the app's recorded
   throws under your scroll, lands on 20 and glows: *You go first.* It goes back to the bar showing its 20.
5. **Your turn.**: the close, on Giada's art, with the three screens. Then **Get MagicMobile**: a row per screen with
   its build, the Obtainium steps for Android, the FAQ, the support card and the footer.

## Rules

- Every image is real (ASSETS.md). Battlefield and hand images are actual app screens with real card art.
- No taglines or helper text; the labels say what each mode does, checked against the apps.
- Reduced motion keeps every section: the walk follows the scroll without easing or parallax, and the die stands on
  its 20 in the middle of the roll.
- Without WebGL (or until Three.js loads), the bar shows Cut to Play's flat die, which makes the same moves.
