# Arena table worlds

How to make a new table theme for the Arena board. Follow this for every world. Caleb approved Radio Night and Utopia on
2026-10-31, and these rules came from his notes on them. Read `docs/ARENA_STYLE.md` "Table worlds" too.

## The rules

1. **The board is a place.** The ground flattens naturally into the play area. Never a mat, rectangle, outline or table.
2. **The UI never moves.** Scenery moves to fit the cards, piles and buttons.
3. **The game's camera never changes.** Worlds use the table's exact tilt, or the cards stop matching the ground.
4. **Nothing in the card rows.** No objects or strong shadows, and only soft, low-contrast ground under the cards.
   **The middle still belongs to the theme (Caleb, 2026-10-31):** plain ground looks unfinished. Use quiet, low-contrast detail
   that lies flat: worn paths, fallen leaves, faint mist or grass, and a faint motif at the centre, like the Walnut compass.
5. **Every pile rests on one flat surface.** Libraries, graveyards, exile and the opponent's hand sit wholly on the floor or
   wholly on a roof, never across an edge or on clutter. Build flat roofs under them on purpose.
6. **Portrait needs a front wall.** A full-width wall whose visible top is exactly where the hand ends (`railTop`, board y
   815, plate row 1630 of 1912). The cards stop at the top of the wall and never overlap it. Keep it straight and free of plants.
7. **Fronts need forced perspective.** The camera sits high, so tilt scenery (`rake`), never the camera.
8. **Hero pieces go where they're seen.** The left and right strips and top band are narrow; put the best piece where it
   shows, usually a corner.
9. **Cards must read.** Each theme sets its own card light and shadow to match the world's light. Bright tables set
   `isBright`, which puts dark glass behind thin controls.
   Keep the game's own glow colours out of the card rows and behind the buttons: bright orange is the attack glow and the
   Next button, so hot lava and fire stay at the edges and away from the corner controls.
10. **Nothing from other games or brands,** and no text or logos in the art.

## The steps

1. **Concept:** Codex paints one landscape image from `design/arena-boards/templates/tilt-guide-landscape.png`, so the camera
   is right from the start.
2. **Layout:** write `scripts/brand/arena_worlds/<name>.json`, with props in board points, and build it with
   `scripts/brand/arena_world.py`. Shared props are in `arena_world.py`; a world's own go in `arena_props_<name>.py`.
3. **Checks on the 3D:** `qa.json` must show nothing in the card rows, no bumps, every seat passing, and only sliver shadows.
4. **Repaint:** give Codex the render as image 1 and the concept as image 2, one call per view. The brief must say: keep every
   position, keep the camera, calm low-contrast plaza with no cast shadows, roofs flat and empty, the wall straight and
   unbroken with its row given in percent, and the floor under your piles empty. See "Repaint brief" below.
5. **Checks on the paint:** run `arena_safe_zones.py --check <plate> <out>`. The 3D checks can't see paint, so look at the
   overlay's seats and the rail line yourself, then repaint or fix. Grass or shadows over the rows mean repaint.
6. **Fit the wall:** if the painted wall isn't on the line, run `scripts/brand/fit_front_wall.py`.
   To change only part of a plate, such as the middle, repaint it and blend that band back so the seats and wall stay put.
7. **Install:** `scripts/brand/install_arena_world.sh <slug> <dir with landscape.png and portrait.png>`.
8. **Motion:** write `arena_worlds/<name>.motion.json` and run `scripts/brand/arena_world_motion.py` (see Motion below).
9. **Theme:** add a case to `ArenaTableTheme` (`GameBoardTheme.swift`) with its light and shadows, and a line to
   `BattlefieldBackdropTests`. The stored value is the slug.
10. **See it with cards:** capture `MAGICMOBILE_DESIGN_PREVIEW=crowded-battlefield` with `-magicmobile.arenaTable <slug>` in both
   orientations on the latest iOS simulator, after one launch so card art has loaded. Caleb decides from these, not from the
   plate alone.
11. **Test:** `BattlefieldBackdropTests` and the board UI tests (`docs/LESSONS.md` has the signing steps for this Xcode).

## Motion

Every world moves, and the board never pays for it. `Board/ArenaWorldLife.swift` sits on the plate, under the cards.

- **Never redraw the board.** A `TimelineView` re-walks the whole board (`docs/LESSONS.md`, Performance). Light and particles run in
  Core Animation. Flowing surfaces are small Metal layers on one 24 Hz clock, with mist, haze and wind at half that.
- **Motion comes from the paint.** `scripts/brand/arena_world_motion.py` reads the finished plates and finds lava, water, plants and
  lit shapes by colour, so masks can't drift from the art. Lay out each world in `arena_worlds/<name>.motion.json`, and rerun it
  after any plate changes.
- **Nothing moves in the card rows** except soft things under the cards: slow cloud shadows and breathing cracks. Fast motion and
  bright flow stay at the edges, and masks are cut out of the rows for you.
- **Patches:** `lava`, `water`, `fall`, `sway` (tall things from their foot), `haze`, `mist`, `wind`. Keep to about 10 a view.
- **Lights** use a hot glow map, because a glow made from the plate's own colours changes nothing when turned up. iOS won't blend a
  layer with the SwiftUI plate behind it, so light is alpha, never `compositingFilter`.
- **The world answers the game:** attacks, big hits, big spells, deaths and wipes go to `ArenaWorldEvents`, straight to the layers.
  Effects only decorate. Give each world one signature reaction, like Radio Night's blackout.
- **Tappable corners:** `hotspots` in the motion file, in the corners only. Light blooms under the finger, because flaring a glow that's already bright mostly clips.
- **Respect the phone:** rest with `BoardActivity` (nothing new is born, flows ease to a stop, then everything stops), half rate while
  hot, lights only on Reduced or Low Power Mode, nothing on Off or Reduce Motion, and rest behind full-table screens. One frame is on
  the GPU at a time, so a slow frame is skipped and can't stall the board.
- **Last a whole game.** Anything built on the clock has to look the same an hour in. `arenaHash` folds its lattice to stay in range;
  a new noise needs the same. Check with `MAGICMOBILE_WORLD_CLOCK=3000`.
- **Judge it moving.** Record the simulator, and use `MAGICMOBILE_WORLD_DEMO=1` to play every reaction (`=dread` shows the low-life
  edge).

## Repaint brief

> EDIT image 1, same size. Image 1 is a 3D render from a card game and fixes the camera and the position of everything: keep
> every building, wall, path and the open ground in exactly the same place and size, and keep the same high camera angle.
> Image 2 is the finished art style to match. [Theme words.] The open ground in the middle stays calm, soft, evenly lit and
> low contrast, with no objects, bold lines or cast shadows. The straight wall near the bottom crosses the full width,
> perfectly level, its top edge on the same row as in image 1, about 85 percent down, with nothing overlapping it. Below it,
> keep 21 to 44 percent across and 89 to 97 percent down plain and empty. Flat roofs at the top stay flat, plain and empty.
> No cards, UI, people, text, letters, numbers or logos.

## Limits

- **Keep:** source art outside the repo in `~/Movies/motion-assets/magicmobile-boards/`. The repo is public, so Fab sources never
  go in it, and `design/arena-boards/` is too large to commit. Only the installed plates and scripts are committed.
- **Run:** Blender and simulators through `scripts/dev/heavy.sh`, one at a time. Worlds never touch `packages/ondevice-engine`.
- **Assets:** Poly Haven is CC0. Check any other licence first.
- **Plates:** each is about 0.7 MB on iOS. Android and web need the theme added too.
- **Heat:** judge it on a phone with an Instruments trace before shipping. Simulator CPU readings swing too widely to compare: Walnut read 17% and 0.2% on identical runs.
