# The page curl

Caleb, October 6, 2026, of the binder's page turns: "instead of a flat page, really stiff, turning, I want that paper
roll animation... I want the page to actually look like a piece of paper is being folded and turned", and "let's try to
make the page curl be draggable." The stiff swing is gone. A page now bends round a moving fold, follows a finger that
drags it, and the same curl plays by itself for an index tab, Done and opening a deck. Both platforms, one algorithm.

## What the player sees

- **Drag.** A sideways drag anywhere on a deck's page curls it under the finger. Forward (leftward drag): upright, the
  page peels from its bottom-right corner toward the spine; sideways, the right page curls over the spine onto the left.
  Back (rightward drag): upright, the previous page unrolls from the spine over the current one; sideways, the left page
  curls onto the right. Let go past 40% of the way, or flung faster than 300 points per second, and the turn finishes;
  otherwise it falls back and the chapter is unchanged. A finger held higher leans the fold further over.
- **Automatic.** Tapping an index tab, Done, opening a deck or the importer plays the same curl in 0.5 s, eased in and out.
- **The paper's back.** The curled flap shows the other face of the sheet. Upright it is parchment, a little darker than the
  face, with a faint show-through of the ink. On a spread the other face of a sheet is the page that lands, so the flap
  carries the new left page (or new right page) over the spine and settles exactly onto what is already there.
- **Shading.** The roll is lit from the upper left: a soft highlight on the crest, darker where the paper turns away, a
  thin darker edge, a soft shadow thrown on the page revealed underneath and a tighter one that keeps the flap's edge
  readable on the page it lies over.
- **Only the paper turns.** The turn is cut to the registered `BinderPage` frames: the shader draws inside the pages' rounded
  outlines (and the strip between two pages, which a flap crosses) and leaves everything else transparent, so the binder's
  leather, head and index tabs are the live ones and stay still. Pages need not be the same height (the head sat above the left page on the base
  layout), so the back of a flap shows the landing page where that page has paper and plain parchment where it has none.
- **Reduce Motion** (iOS) is a 0.2 s crossfade of the page, with no curl and no drag (a swipe of more than 80 points turns
  the chapter when it ends, as before). On Android, animations switched off is the same crossfade, which takes no time,
  so the change simply happens.
- **UI tests** run with no turns at all unless `MAGICMOBILE_UI_TEST_GRIMOIRE_MOTION` is set, as before.

## The model

The classic cylinder page curl. The sheet is flat. A cylinder of radius `r` lies along the fold, resting on the page; the part
of the sheet beyond the fold wraps over the cylinder and lies back, face down, over the part that is still flat. With `n` the
unit vector across the fold (from the flat part toward the flap) and `c` the position of the fold along `n` (the "foot", where
the flat part ends), a point of the sheet at distance `s` past the foot, measured along the paper, lands at:

| `s` | where it lands (`t` = its distance past the foot along `n`) | which face shows |
| --- | --- | --- |
| `s <= 0` | `t = s`, flat | front |
| `0 < s <= pi*r/2` | `t = r sin(s/r)`, rising | front (hidden under the next row) |
| `pi*r/2 < s <= pi*r` | `t = r sin(s/r)`, over the top of the roll | back |
| `s > pi*r` | `t = -(s - pi*r)`, lying flat at height `2r` | back |

The renderer runs this backwards, one pixel at a time, so there are no meshes:

1. For a pixel at distance `t` past the foot, the sheet point that lands there on the back face is `s = r (pi - asin(t/r))`
   for `0 <= t <= r` and `s = pi*r - t` for `t < 0`; on the rising front face `s = r asin(t/r)` for `0 < t <= r`.
2. The source point is `q = p + n (s - t)`: the same place across the fold, moved along `n`. If `q` is inside the sheet that
   face is there. The back face wins over the front, which wins over what is under the sheet.
3. Lighting uses the surface normal on the roll, `(sin(theta), -cos(theta))` with `theta = s/r`, against a light at
   `(0.5, 0.86)`: brightness `0.42 + 0.58 * diffuse/diffuse_flat`, plus a small sheen term around the half vector.
4. The shadow is the flap's outline (the same inverse test, as a 0/1 mask) sampled at twelve points on a spiral, shifted by
   `n * (0.5 r + 3) + (0, 0.14 r)` away from the light, plus a six-point halo; the result darkens whatever lies under. The
   spiral is turned by interleaved-gradient noise at every pixel, so the steps of a few binary samples are fine grain instead
   of bands (the first version, nine fixed taps, banded visibly).
5. The sheet's outline is a rounded rectangle (the binder page's own 13-point corners); one-pixel soft edges at its free edges
   and at the roll's silhouette keep the flap from shimmering.

**Progress.** Everything is a function of one number, `progress` from 0 (flat) to 1 (turned), so a drag, a fling's follow-through
and an automatic turn are the same thing:

- the fold's lean `phi = 0.20 (1 - progress)` radians: the bottom corner lifts first and the fold levels out so that the finished
  page lies exactly over its neighbour;
- the foot runs linearly from beyond the far corner to the spine (`foot = far + (spine - far) * progress`);
- the radius is `maxRadius * sin(pi * progress)^0.55`, `maxRadius` being 12% of the sheet's width limited to 26..60 points,
  so the roll is tight at both ends and fullest in the middle.

**Back.** Upright, going back is the forward turn run backwards with the other picture as the sheet: the previous page is
rolled up beside the spine and unrolls over the current one. On a spread, back is forward in a mirror (`mirror` flips x first).

**Drag.** `progress = fingerDistance / travel`, with `travel` between half and nine tenths of a page's width (the way from
where the finger touched to the far edge, less 20 points). A release finishes the turn when `progress >= 0.4`, or when the
finger's speed along the turn exceeds 300 points (dp) per second and `progress > 0.12`; a fling against the turn cancels unless the page is
more than 60% over. The remaining turn then runs with an ease-out over `0.16 + 0.34 * remaining` seconds.

## How a turn runs

1. `turnPage(forward:change:)` (called as before by the index tabs, Done, opening a deck and the chapter swipes) pictures
   the paper's rectangle (the registered binder pages: one upright, the union of two on a spread) before the change.
2. `change()` runs, and about 0.07 s later (two frames on Android) the screen underneath is pictured again.
3. A Metal layer (iOS) or an AGSL shader (Android) over the rectangle draws the two pictures bent by the curl. Until the
   second picture is ready the first is shown flat. The real screen underneath is never touched.
4. At the end the layer goes. Nothing runs when idle: iOS runs a `CADisplayLink` only while the page moves or is being
   dragged, and draws only when something changed; Android draws on the frame clock only while `progress` changes.
5. A curl that plays by itself, or settles after a finger let go, lets touches through (iOS: the stage window's `hitTest`
   returns nil; Android: the overlay takes no pointer input). A tap or drag during it takes it to its end at
   once (the screen underneath already shows the new page, or has the old one put back) and starts the new turn, so a quick
   second tab, or a swipe right after a tab, is never swallowed. On iOS the automatic turn's clock is a Core Animation
   animation on a layer's position (`PageCurlTurn.clock`), which the display link reads each frame, so the system and UI tests
   can see that something is moving.

**A drag reaches `turnPage` the same way.** The screens' callers are unchanged. When a drag turns sideways the watcher arms a
drag session and calls the screen's own "next chapter" or "previous chapter", which calls `turnPage`; `turnPage` finds the
session and, instead of animating, follows the finger. If the finger lets go early the watcher calls the opposite closure,
which `turnPage` (busy) runs as a plain change. A turn that left the screen (back past the first chapter is the library's
page, a different binder screen) cannot be put back from here, so it always finishes, wherever the finger lets go.
If the closure does not turn a page (the last chapter, or the unsaved-changes dialog on the way back to the library) the
drag turns nothing; the dialog, if any, appears when the drag starts instead of when it ends.

**Drags are watched on the book, not on a screen.** iOS: one `UIPanGestureRecognizer` on the window belongs to
`GrimoireSwipeHub` (`GrimoireChrome.swift`); `grimoireSwipe` only registers a screen's two closures. It still recognizes
alongside everything and never cancels or delays a touch, which is what fixed the swallowed first tap in October. Android:
`watchGrimoireDrags` is the book's own pointer input (`GrimoirePages`), watching at the final pass. It starts a turn once
the finger has moved 12 dp (12 points) with no child having used the movement (a row scrolling, a vertical scroll) and the
move mostly sideways (more than twice its vertical part); on iOS the same test, plus `ownsSidewaysDrags` (a slider, a text
field or a sideways scroll view under the finger). On both platforms a drag has to begin on the paper, below the page's head:
the plaques along a page's top (Done, Save, the tags, the more menu) are buttons, and a finger that slides off one of them turns
nothing, as does one that begins off the paper (the leather, the index tabs). `GrimoireStage.pageMayCurl` decides it from the
registered page frames and `Grimoire.headBand` (64 points), so it holds whether the head sits on the leather above a page or at
the top of the page itself. With no pages registered a drag may begin anywhere.

## Files

| Piece | iOS | Android |
| --- | --- | --- |
| The algorithm | `Grimoire/PageCurl.metal` | `studio/PageCurlShader.kt` (`PAGE_CURL_AGSL`) |
| Progress, pose, drag and release rules | `PageCurlModel` in `Grimoire/GrimoirePageCurl.swift` | `PageCurlModel` in `studio/PageCurlShader.kt` |
| Renderer, one turn | `PageCurlRenderer`, `PageCurlView`, `PageCurlTurn` in `GrimoirePageCurl.swift` | `CurlSurface` in `studio/GrimoireStage.kt` |
| The stage, drag sessions, Reduce Motion | `Grimoire/GrimoireStage.swift` (`turnPage`, `beginDrag`, `dragChanged`, `dragEnded`) | `studio/GrimoireStage.kt` |
| Drag watching | `GrimoireSwipeHub` in `Grimoire/GrimoireChrome.swift` | `watchGrimoireDrags` in `studio/GrimoireChrome.kt` |
| Fallback before Android 13 | none (Metal is on every iOS 17 device; without it, a crossfade) | `SwingSurface` in `GrimoireStage.kt` |

The shader compiles at run time on Android, so `curlShaderWorks()` tries it once and the swing takes over if it ever
fails (a reserved word, `cast`, crashed the first build on the emulator: AGSL has more reserved names than MSL).

iOS draws into a `CAMetalLayer` the size of the paper's rectangle, with two textures made from `drawHierarchy` pictures (so
materials and blurs are in them; `MTKTextureLoader` failed now and then when memory was short, so the bitmap is drawn by hand
into a BGRA texture) and a fragment function over one full-rectangle quad. Android draws a `RuntimeShader` (API 33) with
the recorded `GraphicsLayer` pictures as `BitmapShader` inputs. Before Android 13 there is no AGSL, so the page swings about
the spine as a flat sheet, driven by the same progress and so the same drag. (A mesh fallback with `drawBitmapMesh` would
bend before Android 13 too; the swing was kept for cost.)

## Tuning

| Knob | Where | Now |
| --- | --- | --- |
| Starting lean of the fold | `PageCurlModel.tilt` / `TILT` | 0.20 rad |
| Roll radius | `radiusShare`, `radiusRange` | 12% of the sheet, 26..60 pt |
| Roll profile over the turn | `pow(sin(pi k), 0.55)` in `pose` | tight at both ends |
| Finish at | `completeShare` | 40% |
| Fling speed | `flingSpeed` | 300 pt/s (past 12%) |
| Automatic turn | `PageCurlTurn.animate` call in `turnPage` | 0.5 s ease in and out |
| Settle after release | `finishDrag` | 0.16 + 0.34 * remaining, ease out |
| Drag starts after | `GrimoireSwipeHub.decide`, `watchGrimoireDrags` | 12 pt |
| Head of a page (no curl from it) | `Grimoire.headBand` | 64 pt |
| Back of the paper | `paper` uniform, `look.y` | `(0.80, 0.71, 0.55)`, 10% show-through |
| Shadow | `look.x`, `flapShadow` | 45%, shift `0.5 r + 3`, blur `0.62 r + 6` |
| Light | `light` in the shader | `(0.5, 0.86)` in (across the fold, up) |

## Sources

The cylinder model and its vocabulary (a curl defined by a position, a direction it opens to and a radius, a page as a
texture, the fragment's place relative to the cylinder and the curl axis) were taken from these write-ups, read through
their READMEs and descriptions (no code was fetched or copied); the code here is written for the app.

- harism, *android_page_curl* (Apache 2.0): https://github.com/harism/android-pagecurl, the OpenGL ES curl whose cylinder
  parameters (position, direction, radius) this follows.
- Andrew Hung, "Page Curl Shader Breakdown": https://andrewhungblog.wordpress.com/2018/04/29/page-curl-shader-breakdown/,
  the fragment-shader form (two page textures, each fragment classified against the cylinder and the curl axis).

## Tests

- `GrimoireUITests.testDraggingAPageCurlsItAndLettingGoFinishesOrReturnsIt`: a slow drag held short of 40% falls back to the
  chapter it came from, a long one turns; a picture is taken while the finger holds the page mid-curl.
- `GrimoireUITests.testDraggingASpreadsPageCurlsItOverTheSpine`: the same sideways, the right page forward and the left page back.
- The first of those also drags from the head's Done button and checks that nothing turns.
- `testTheBookOpensTurnsItsPagesAndCloses` and the other existing tests drive the automatic curl (index tabs, Done, opening a
  deck) and the fast swipes. They now wait for the turn to end before the next touch (`waitForTurn`: the Done button is
  hittable again): XCUITest finds no hit point for a button while the stage window is up, so a tap sent mid-curl is lost, where
  the old 0.42 s swing happened to be over in time. A real finger is not affected (it passes through, above).
- Runs: all five `GrimoireUITests` passed together on the iPhone 17 Pro Max simulator (Xcode 27), after earlier runs in which
  one or two of them flaked on taps the simulator dropped; Android `:app:compileDebugKotlin :app:lintDebug :core:test` passed.
- Mid-curl pictures: `build/screens/` in the work tree (`ios-*` from the UI tests' held drags, `android-*` from `adb shell input
  motionevent` held on the API 35 emulator).

## Known limits

- Seen on the iPhone 17 Pro Max simulator and the API 35 emulator only. How the drag feels under a real finger, and the
  frame rate on a device, are still to be judged on a phone. iPhones need `CADisableMinimumFrameDurationOnPhone` in
  Info.plist for a display link above 60 Hz; it is not set (the app's own file), so the curl runs at 60 until it is.
- Starting a drag costs the main thread 0.1 to 0.3 s on the simulator (picturing the page, building two textures, the stage
  window); the Metal pipeline is built ahead of the first turn so it does not add to that. Judge it on a phone.
- The picture is a rectangle: the binder page's stitched seam and brass corner mounts curl with the paper.
- The texture is sampled without mipmaps, so very fine detail shimmers slightly in the last few pixels of the roll's
  silhouette.
- The flap's back is a plain paper tone (a faint show-through upright); only on a spread does it carry the landing page.
- A sideways drag in the middle of a vertical scroll is judged once, when the finger has moved 12 points. A drag that
  starts sideways and turns vertical keeps turning the page.
- A drag that lets go early puts the chapter back by calling the screen's own opposite turn, so the chapter reopens at its
  own top (the title plate scrolled away) rather than where it was scrolled. Keeping the old scroll position needs the
  Deck Studio screens to expose a way to peek at the next chapter without leaving this one (see the report's integration notes).
- Dragging toward the previous chapter on the first one starts the library's page turn at once (and the unsaved-changes
  question, if the deck has changes, at the start of the drag instead of the end).
- The curl's tilt follows the finger's height only by a little (`0.7 * lift / height`, 0.05..0.4 rad).
- The Reduce Motion crossfade (iOS and Android) and the Android swing have each had little checking: the swing was run once on
  the API 35 emulator with the shader forced off (it follows a drag and lets go correctly); no device older than Android 13 and
  no Reduce Motion run has been seen. The crossfade is the one code path of this feature no test drives.
