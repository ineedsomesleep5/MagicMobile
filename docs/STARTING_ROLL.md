# The starting roll on the tavern table

Before a game the players roll a D20 for who starts (highest wins, ties reroll). The roll is shown on the
board's own table: each seat's real 3D die is thrown onto the leather mat, tumbles, bounces off the far rail
and settles with the number the game decided on top. This file is the handoff for the next agent.

The game logic is untouched. `OnDeviceStartingRoll` (Swift) / `OnDeviceStartingRoll` (Kotlin) still records
every value, tie round and the winner; the multiplayer protocol, the roll's timing contract (`revealedStepCount`,
`onStepPlayed`, the 1.9 s read time, the auto-dismiss) and the accessibility labels and identifiers are as they
were. Only the presentation changed.

## What the player sees

- The table fills the screen: walnut boards, the board's leather mat with its compass, a raised walnut and brass
  rail. It is lit by a warm lamp up and to the left, so every die throws a soft shadow down and to the right.
- A leather title plate in brass trim ("STARTING ROLL", the headline, a brass **Skip** plaque), the ember-glass
  **Tap to roll D20** button, a parchment **Rolled N** chip, and one parchment name plate per seat with the number
  struck on a brass coin. The winner's plate turns to ember glass and their die stands in an ember halo.
- Seats keep one lane each, left to right in the roll's own order (the viewer first). A reroll (tie) clears the
  table, the tied seats throw again, and seats that are out stay on their plates ("Out of the reroll").
- Reduce Motion: no tumble. Each die simply lies on its number. Skip does the same, at once, mid-throw included.

## Files

| File | Role |
|---|---|
| `scripts/brand/d20.py` | Blender: the die (`--mode model`), the recorded throws (`throws`), the table and soft discs (`table`), contact sheets (`preview`). `all` runs the first three. |
| `scripts/brand/install_d20.sh` | Copies the results into `apps/ios/MagicMobile/Resources/D20/`. Android reads that same folder (`prepareD20Assets` in `apps/android/app/build.gradle.kts` puts it in the APK's `assets/d20/`). |
| `Resources/D20/d20.glb` | The die: beveled icosahedron, engraved gold numerals on oxblood resin. One glTF both apps load. |
| `Resources/D20/d20.json` | Per face: its number, outward normal, and the three directions to its corners (the numeral points along the first). |
| `Resources/D20/d20-throws.json` | The bank of recorded throws: 60 fps position and orientation, rail time, table hits, the face that ended up. |
| `Resources/D20/d20-table-{portrait,landscape}.glb` | The table as an unlit textured quad (its lighting is the picture's). |
| `Resources/D20/d20-shadow.glb`, `d20-glow.glb` | The soft disc under a die and the winner's halo (alpha-blended quads). |
| iOS `StartingRollDice.swift` | Pure data and maths, in the `swift test` package: model, throws, **landing**, **table layout**, a small GLB reader. |
| iOS `StartingRollTableView.swift` | SceneKit scene (`D20TableScene`) and its SwiftUI host (`D20TableView`). |
| iOS `MultiplayerD20View.swift` | The screen: playback loop, plates, controls. `StartingRollCover` is its full-screen cover. |
| Android `ondevice/StartingRollDice.kt` | The same maths, ported line for line. `ui/D20Math.kt` has `Vec3`/`Quat`. |
| Android `ondevice/StartingRollTable.kt` | Filament + gltfio scene (`D20TableScene`) and its Compose host (`D20TableView`). |
| Android `ondevice/MultiplayerD20View.kt` | The screen, like the Swift one. |
| Android `StartingRollPreview.kt` | Debug fixture, `MAGICMOBILE_DESIGN_PREVIEW=starting-roll` (see Looking at it). |
| tests | `StartingRollDiceTests.swift`, `StartingRollDiceTest.kt`: landing, symmetry, layout, golden numbers shared by both ports. |

## How a throw lands on the game's number

There is no physics in the app. `d20.py` ran a small rigid-body integrator offline (twelve corners against the
table and the rail, impulse contacts with friction, a soft pull toward the lane's middle) over a few hundred random
throws, in the launch profile that passes most often, and kept the ones that look right: they leave the near edge,
bounce at least three times, hit the rail low, come back and stop clear of it within about 0.4 radii of their lane.
Playback is slowed 1.7 times (`TIME_SCALE`), so a throw lasts 2 to 3 seconds. Each kept throw is stored as 60 fps
keyframes and ends with some face F up; twelve are kept, preferring different resting faces.

A regular icosahedron looks the same after any of its 60 rotations. To make a recorded throw end with face T up
instead, turn the body by the symmetry **S** that carries T onto F, then play the recorded motion:

    world orientation = recorded orientation * S

The motion is identical; only which numeral sits on which face changes. S is built from the two frames
(normal, first corner direction) of T and F (`D20Landing.symmetry`). Three symmetries carry T onto F, a third of a
turn about the face apart; `D20ThrowPlan` picks the one that leaves the numeral reading closest to upright (away from
the viewer) and adds the remaining yaw, plus a small deterministic wobble, over the last 0.75 s, as a die skids to a stop.
The tests check, for every throw in the bank and every number 1 to 20, that the face on top is that number, flat, at
rest height, with the numeral upright, and that S maps every corner to a corner.

Which throw a seat gets is a pure function of (round, seat index) (`D20Landing.throwIndex`), so the resting pose after
a throw is exactly the pose a skipped or reduced-motion roll shows, and a restarted playback never jumps.

## Coordinates

Everything the apps read is Y-up (x right, y up, +z toward the viewer), in units of the die's circumradius (1).
The table plane is y = 0, centred on the origin, image top toward -z. The die rests at y = inradius (0.7947).
The far rail's inner face is z = -mat depth / 2 (portrait mat 9.6 x 15.2, landscape 15.2 x 9.6 -- `D20TableLayout.matSize`).
In the throws file the rail plane is z = 0; a seat's throw is placed at its lane's x and the rail's z, and its x/z
distances are scaled by the *footprint* (0.5 to 1) so the throw fits short roll areas. Heights are never scaled.

`d20.py` works in Blender's Z-up frame and converts at the edge: positions (x, y, z) to (x, z, -y) and orientations
by conjugating with a -90 degree turn about x.

## The camera and lanes (`D20TableLayout`)

The roll area (the transparent spacer between the title plate and the controls, identifier `multiplayerD20.rollArea`)
tells the table where the dice may go. It stays after the roll ends (silent to VoiceOver), so the dice stay in view under the
result; its height is 32 % of the stage (240 to 320 points) in portrait and what is left under the one-line title in landscape. The layout makes the dice as big as the area's width allows for the number of
seats (lane spacing 2.45 radii, 3.1 for two seats, at most 58 points per radius), shortens the throw if the area is
low, puts the far rail near the top of the area and aims a 40 degree perspective camera, tilted 18 degrees from
straight down, so the middle of the area stays where it is on the stage. It is a pure function, tested, and the same
on both platforms.

## Rendering

- iOS: `SCNView` over the whole stage (it ignores the safe area). Poses come from a `CADisplayLink` that runs only while a die is
  in the air or leaving, never from SceneKit's own update loop (after being paused and resumed it did not reliably run, and some dice never appeared); the view
  renders continuously only while that link runs, plus a few frames after any change. The table a `.constant`-lit textured quad, the die
  `.physicallyBased` with base colour, normal and a packed roughness (green) / metalness (blue) map, one warm omni
  light, a dim ambient light and a small generated environment for the resin's reflections. Shadows are soft discs, not
  shadow maps. The scene is idle at rest.
- Android: Filament 1.75.1 with gltfio in a `TextureView` (newer releases, from 1.76, need compileSdk 37; the app is on 35). The same files, an `UbershaderProvider`, one directional light, one
  point light for the glint, a constant ambient `IndirectLight`, linear tone mapping so the table's colours stay as
  painted, 4x MSAA. Frames are posted with `Choreographer` only while a die is in the air or something changed; the
  engine is created when the roll appears and destroyed when it goes. The roll waits (at most 5 s) for the table's first
  frames, so nothing is thrown, or laid down, into a blank screen (the emulator takes several seconds to compile the
  ubershader the first time; phones do not). Release builds keep `com.google.android.filament.**`
  (`proguard-rules.pro`).

## Looking at it

- iOS: `MAGICMOBILE_MULTIPLAYER_D20_FIXTURE=1` (the existing fixture; `MAGICMOBILE_D20_LANDSCAPE_FIXTURE=1` for landscape,
  `MAGICMOBILE_D20_AUTOPLAY=1` to let each roll follow the last, `MAGICMOBILE_D20_SEATS=2|3|4`). Tests:
  `BoardPolishUITests/testSharedD20FitsPortraitAndLandscape` and `testStartingRollHidesTheStartingPlayerChoice`.
- Android (debug build): `adb shell am start -n com.calebfeliciano.magicmobile.android.debug/io.magicmobile.android.MainActivity
  --es MAGICMOBILE_DESIGN_PREVIEW starting-roll --es MAGICMOBILE_STARTING_ROLL_AUTO 1 --es MAGICMOBILE_STARTING_ROLL_SEATS 3`.
  Reduce Motion is the system animator scale: `adb shell settings put global animator_duration_scale 0`.
- Assets: `blender -b -P scripts/brand/d20.py -- --mode preview --out-dir build_output/d20` renders the die with
  several numbers up.

## Changing it

- A new look for the die: edit the materials/numerals in `d20.py` (`build_textures`), rerun `--mode model`, install. The
  numbering, normals and corner directions are written to `d20.json` by the same run, so nothing else changes.
- New or more throws: `--mode throws --candidates N --keep K`; the filters in `build_throws` say what a good throw is.
  Each throw must hit the rail within the lane; keep at least six so neighbours differ.
- A different table: `--mode table`. The leather is cropped from the tavern plates in the asset catalogue and the
  walnut is `battlefield-wood`; nothing is downloaded.
- Do not mirror a recorded throw to get more variety: a mirrored die shows backwards numerals.

## Not done / watch

- The pre-roll "Who goes first?" panel (until the host shares the dice) is dressed in leather and brass but sits on a
  plain dark walnut cover, not the 3D table.
- Dice do not collide with each other; lanes keep them apart (a throw stays within 0.4 radii of its lane's middle).
- SceneKit is soft-deprecated by Apple (see `BOARD_FX_ROADMAP.md`); the table is a small, self-contained scene, so a
  RealityKit port would only touch `StartingRollTableView.swift`.

## Size and checks (2026-10-07)

- Android: the release APK carries 3.65 MB more, compressed (Filament 1.27 MB + gltfio 1.52 MB for arm64, the die 0.5 MB,
  both tables 0.48 MB, throws 0.03 MB). The R8 release build still links: `com.google.android.filament.**` is kept whole
  (`proguard-rules.pro`); it cannot be exercised at runtime in a release build, because the preview fixture is debug-only
  and the roll needs a game.
- iOS: the app gains 1.1 MB of resources (`Resources/D20`).
- Run on 2026-10-07: `swift test --package-path apps/ios` (603 tests, `StartingRollDiceTests` among them), the
  `MagicMobile` scheme builds for the simulator, UI tests `BoardPolishUITests/testSharedD20FitsPortraitAndLandscape` and
  `testStartingRollHidesTheStartingPlayerChoice` pass; Android `:app:compileDebugKotlin :app:lintDebug :core:test
  :app:testDebugUnitTest :app:assembleDebug :app:assembleRelease` pass (`StartingRollDiceTest`, 8 tests). Screenshots
  (mid-tumble and settled, 2 to 4 seats, portrait and landscape, Reduce Motion) were taken on the iPhone 17 Pro Max
  simulator and the API 35 emulator.
- Not seen on a phone: how the throws feel, the lamp's brightness on real screens, and frame rate on older devices.
