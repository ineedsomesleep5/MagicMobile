# MagicMobile: Hall and Cut

Supersedes "The opening hand" (Walnut & Ember, September–October 2026), which stays in FINGERPRINTS.md.

## Evidence (Caleb)

- 2026-10-23: "we have ios android and webapp ... now that we changed our style we need to plan on updating our website
  big time." Decisions: the browser game is linked but stays unlisted; Arena, like the apps; no cross-play claim.
- 2026-10-23: use Nate Herk's scroll-craft; "it doesn't have to follow the current scroll animation the website has if
  you find a better one."
- 2026-10-23: "if you are going to have images on the website make sure the cards load all of them"; "make sure it
  looks exactly how it's supposed in game."
- Three directions were mocked (The Hall: gallery; Your Turn: live surface on the Arena board; Cut to Play: cutlist with
  the D20 in the bar). 2026-10-24: "I didn't like the table one I wanted the hall and the cut one and combo of that
  one", with "the real 3d model we use" for the dice; then "I like the one you made. Let's update our website to that
  one."
- 2026-10-24 review of the mock: the Draw and Attack screens "do not look good" (tilted, cropped, under the word) and the
  walk "doesn't scroll smoothly ... shifts side to side". Both fixed before the build (DESIGN.md, `src/hall.ts`).

## The eight topics

1. Vibe: Arena at night. Dark glass, gold hairlines, one orange action, commander art as the light source.
2. Journey: see the game (a hand, a board), learn what you can play, pick your screen.
3. Energy: hard cuts open, a slow walk, one held peak, an abrupt full-bleed close, then calm downloads.
4. Feeling: pulse (cuts), recognition (the real hand and board), curiosity and pride (the hall, the badge climbing),
   suspense into release (the roll), decision (your turn).
5. Signature: **the bar rolls the D20.** The app's own die sits in the nav bar and turns as you scroll; at the peak it
   leaves the bar, plays a recorded throw under your scroll, lands on 20 and glows.
6. Range: playful-cinematic for a game, never premium-minimal.
7. One world: one dark Arena room; the hall is its gallery.
8. Assets: real only (ASSETS.md). No generation.

## Feeling curve

- Pulse: *Commander.*, *Draw.*, *Attack.*, a screen each.
- Curiosity: the walk past seven commanders, the room taking each one's colours.
- Pride: the Ranked badge climbs Bronze to Mythic while it holds the middle.
- Suspense into release (the peak): the die leaves the bar, tumbles, lands on 20. "You go first."
- Decision: *Your turn.* with the three screens.

Peak sentence: "The die in the menu bar rolled a 20 and the site said I go first."

## Score

| Beat | Device | Span | Purpose |
|---|---|---|---|
| Commander | flow, full-bleed art | 1 screen | The game in one word |
| Draw, Attack | flow, reveal | short | The real hand and board |
| The Hall | pin + bespoke rail (soft stops, parallax, regrade, badge climb) | 9 screens | What you can play |
| The roll | pin + the bar's D20 (Three.js, recorded throw) | 3.2 screens | The peak |
| Your turn | flow, full-bleed art | 1 screen | The choice |
| Get MagicMobile | flow | natural | Builds, install help, FAQ, support |

## Fingerprint

Grammar: cutlist into gallery. Nav: a loud full-width bar with the three screens at the wordmark's weight, plus the
hall's medallion index while the hall has the screen. Hero: one hard cut, a commander and one word. Act shape: three
short cuts, one long sideways pin, one held peak, a full-bleed close, natural flow. Close: the three screens on art,
then rows. Signature: the bar's D20. Against "The opening hand" it changes grammar, nav, hero, act shape, close and
signature (6 of 6).

## Verification

Production build; desktop 1440 × 900 and phone 390 × 844 frames at every beat (headless Chrome with SwiftShader for
WebGL); no console errors, failed requests or sideways overflow; the walk measured monotonic step by step; reduced
motion; the flat die without WebGL; real download links. Not covered: a physical phone.
