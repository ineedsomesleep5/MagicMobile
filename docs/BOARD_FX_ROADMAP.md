# Board FX roadmap and handoff

Goal: move the iOS board toward the feel of MTG Arena and Hearthstone (choreographed
card motion, card shaders, particles, haptics and sound, then selected 3D moments)
without replacing the native SwiftUI app or the on-device XMage engine.

This file is the shared handoff between agents (Claude, Codex). **Whoever works on
board FX updates the Status and Log sections before stopping**, including partial
work, so the next agent can continue from the branch alone.

## Decisions (settled with Caleb, 2026-09-23)

- Stay native: SwiftUI + Metal shaders + Core Animation/Canvas particles, and
  RealityKit for true 3D. No Unity (would replace the app and add a second heavy
  runtime beside XMage on an 8 GB-class phone budget). No three.js/WebView board.
- SceneKit is soft-deprecated by Apple (WWDC25). New 3D goes to RealityKit.
  `RealityView` on iOS needs iOS 18 while the app targets iOS 17, so gate it with
  `if #available(iOS 18, *)` and keep a 2D fallback.
- Personal, non-commercial project (card IP). No paid assets.
- Performance is a hard requirement: no work while idle, cap simultaneous effects,
  honor Reduce Motion, and offer a Board Effects setting (Full / Reduced / Off).
- Effects only decorate transitions that the client already applied. XMage stays the
  source of truth; effects never block input, never delay snapshots, and never read
  or reveal information that is not in the viewer's snapshot.

## Architecture

```
snapshot applied ──► BoardFXRevisionKey changes (NativeGameView.boardObservation)
                    └► BoardFXDirector.ingest(snapshot)
                         BoardFXState(snapshot)            public board summary
                         BoardEventDiffer.events(old,new)  ordered BoardFXEvent list
                         BoardFXScheduler.schedule(level)  delays, durations, caps
                    └► BoardFXOverlay (Canvas in TimelineView, only while active)
                         uses PortraitCardBoundsKey anchors + metrics rects
                    └► BoardFXHaptics, BoardImpactShake (viewer hit, Full only)
                    └► environment boardFXCardMotion → BoardFXCardMotionModifier on
                         every battlefield tile (hide while a flight is airborne, lunge)
```

Card flights (Full level only) draw a real `CardTile` above the Canvas:
arrivals arc in from the owner's hand point (or the stack) and land at the tile's
anchor, then the landing glow plays; departures shrink toward the owner's side (or
hand); spell casts rise to the stack point and hold as a showcase. Faces for departed
cards come from the previous snapshot (`BoardFXDirector.subjects`). Attackers lunge
toward the opponent with a keyframe spring. Reduced/Off levels have no flights or lunges.

| File | Role |
|---|---|
| `apps/ios/MagicMobile/BoardEventTimeline.swift` | Pure logic: state, diff, schedule, director, levels. In the portable package. |
| `apps/ios/MagicMobileTests/BoardEventTimelineTests.swift` | Portable unit tests (`swift test --package-path apps/ios --filter BoardEventTimelineTests`). |
| `apps/ios/MagicMobile/BoardFXOverlay.swift` | SwiftUI renderer, painter helpers, flights, tile motion modifier, shader modifier, shake, haptics, settings picker. App target only. |
| `apps/ios/MagicMobile/BoardFXShaders.metal` | `mmDissolve` (noise burn with glowing edge) and `mmFoil` (rainbow wash + glint) SwiftUI `colorEffect` shaders. App target only. |
| `apps/ios/MagicMobile/ContentView.swift` | Integration only: state on `NativeGameView`, `ingestBoardFX`, `boardFXOverlay`, both board overlays, three settings panels, turn banner + phase pill, hand fan/lift (`PortraitHandRow`), `PlayableGlowPulse`, `InspectionFoil`, restyled `GameCompletionOverlay`. |
| `apps/ios/MagicMobile/ArenaBoardPresentation.swift` | Legendary gold edge on `ArenaBattlefieldCard`; `BoardLifeTotal` hides its own delta badge unless Board Effects is Off (the overlay draws the floating number). |

Event order within one transition: spell cast → attack declared → block declared →
combat strike → damage → left battlefield → entered battlefield → counters → life. At most
`BoardFXScheduler.decorativeLimit` decorative effects per transition; life changes
are always kept.

Pacing (build 14): each group starts at the previous group's `handoff`, not at a fixed
stagger. Spell showcases (2.4 s, big spells 2.7 s, commanders 3.1 s) hand off only as they
fade, so a permanent never lands before its spell has been read; strikes hand off at
impact, so damage numbers, deaths and life changes land on the hit. Showcases play one
after another (`isSequential`), and a later snapshot waits for a showcase still playing
(`BoardFXDirector` passes `hold`, capped at `BoardFXScheduler.maximumHold` = 3 s so the
board never falls far behind the engine).

- `spellCast` carries a weight: ability (small, quick), spell, big (printed mana value
  ≥ 6: board flash + light rays) or commander (name seen in a command zone this game:
  gold flash, rays, COMMANDER banner).
- `enteredBattlefield` carries an entrance: plain (flies to its slot), showcase (a
  non-land, non-token card that arrived from hand or nowhere without being seen on the
  stack: rises to the center, holds, settles into its slot) or commander (showcase with
  gold rays, shockwave landing, haptic and shake). A permanent that was on the stack in
  the previous snapshot flies from the stack point with no second showcase.
- `combatStrike` fires for every attacker when the step leaves begin-combat /
  declare-attackers / declare-blockers. Target: first blocker, else the public combat
  defender (player or permanent), else the first opponent. The attacker's tile is hidden
  while a flight winds up, charges, hits (shockwave + sparks) and returns.
- `blockDeclared` draws a steel-blue tether from blocker to attacker.
- Tiles hold a stance while the snapshot says attacking (red glow, 12 pt forward,
  scale 1.05) or blocking (blue glow, 7 pt forward). Reduced keeps the glow only.
- Color identity particles (`BoardFXPainter.elemental`) around showcased cards: embers
  (red), frost shards (blue), leaves (green), light motes (white), smoke (black), gold
  glints (multicolor), steel glints (colorless).

Timing: a snapshot can stall the main thread while the board relays out (0.4–1.3 s
seen in the Debug simulator). `BoardFXClock` starts each batch on its first drawn
frame, and tiles reveal on the same clock, so no effect opening plays off-screen.
The director only prunes effects older than `renderGrace` on ingest; the overlay
prunes precisely.

Sound: `BoardFXSound` plays five CC0 Kenney Impact Sounds (converted to 64 kbps AAC
in `Resources/BoardFX`, license alongside) with an ambient audio session (respects
the silent switch, mixes with music). "Effect Sounds" toggle next to Board Effects.

Known limitation: XMage may give a card a new object ID when it changes zones. The
differ matches a departing permanent to a same-name card newly visible in the same
player's graveyard/exile/command zone; otherwise the destination is `nil` (generic ash).

## Phases

1. **Event timeline + first effects (this branch).** Spell rune burst with name
   banner at the stack, arrival glow + sparks, departure ghost with embers (graveyard)
   or rising motes (exile), damage flash + number, counter sparkle, attack flare,
   floating life numbers, viewer-hit shake and haptics, Board Effects setting.
2. **Card motion.** Real card flights (hand → stack → battlefield, battlefield →
   graveyard) using `matchedGeometryEffect` or a flight layer drawing the card image
   between last-known and new bounds. Attack lunge toward the defender. Requires
   extracting the battlefield card view out of `ContentView.swift` (see
   `docs/WORKFLOW_EFFICIENCY.md` step 5: incremental extraction during feature work).
3. **Card shaders.** Foil/holo sheen driven by tilt or drag, playable-card glow,
   dissolve on death, heat haze on big hits. SwiftUI `layerEffect`/`colorEffect`
   with `.metal` files (`[[ stitchable ]]`). Candidate source: Inferno (below).
4. **Particles and sound upgrade.** Evaluate Vortex for richer particle presets;
   add a small CC0 sound set (Kenney) behind a Sound setting.
5. **RealityKit moments.** Move the D20 (`MultiplayerD20View.swift`, SceneKit) to
   RealityKit; add a few 3D hero moments (commander entry, game win).

## Free/open material researched

| Source | License | Use | Status |
|---|---|---|---|
| [Inferno](https://github.com/twostraws/Inferno) (Metal shaders for SwiftUI) | MIT | Phase 3 shimmer, dissolve, transitions | Not added. Prefer copying individual shaders with the license notice over a package dependency. |
| [Vortex](https://github.com/twostraws/Vortex) (SwiftUI particles) | MIT | Phase 4 richer particles | Not added. Phase 1 uses a tiny custom Canvas particle painter instead. |
| [Pow](https://github.com/EmergeTools/Pow) (SwiftUI effects/transitions) | MIT | Shake/spray/shine change effects, burn transitions | Not added. Evaluate for phase 2 transitions. |
| [Kenney Impact Sounds](https://kenney.nl/assets/impact-sounds), [Particle Pack](https://kenney.nl/assets/particle-pack) | CC0 | Phase 4 sound and particle sprites | Not downloaded (downloads need Caleb's OK). |
| Apple WWDC25 [Bring your SceneKit project to RealityKit](https://developer.apple.com/videos/play/wwdc2025/288/) | Apple sample | Phase 5 D20 migration | Reference only. |

Adding any Swift package dependency changes CI resolution and the privacy/security
review surface: ask Caleb before adding one, record it here, and prefer vendoring a
single MIT file with its license header when that is enough.

## Verification recipe

- `swift test --package-path apps/ios --filter BoardEventTimelineTests`
- `python3 scripts/release/preflight.py run --profile ios-fast`
- Generic iPhone compile (from AGENTS/Caleb):
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project apps/ios/MagicMobileiOS.xcodeproj -scheme MagicMobile -configuration Debug -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
- The committed Xcode project is generated from `apps/ios/native-engine.yml`
  (`cd apps/ios && xcodegen generate --spec native-engine.yml`). Generating from
  `project.yml` drops the native link phase; do not commit that.
- A worktree without its own `apps/ios/NativeEngine` needs an APFS clone
  (`cp -cR <other checkout>/apps/ios/NativeEngine apps/ios/NativeEngine`). The native
  verifier refuses symlinks by design.
- Simulator walkthrough (Debug build, no engine): launch with
  `SIMCTL_CHILD_MAGICMOBILE_DESIGN_PREVIEW=board-fx SIMCTL_CHILD_MAGICMOBILE_BOARD_FX_AUTOPLAY=1 xcrun simctl launch --terminate-running-process booted com.calebfeliciano.magicmobile`.
  It steps every 3.6 s through cast Swords → exile Serra Angel (+4) → Sol Ring enters
  from hand (showcase, +1 counter) → AI casts commander Kozilek → Kozilek enters
  (commander entrance) → Isamaru attacks → Kozilek blocks → combat damage (strike) →
  Isamaru dies. Plain Debug builds run the simulator several times slower than real time;
  for timing checks build with `SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule`
  (still Debug, so the preview exists). `MAGICMOBILE_DESIGN_PREVIEW=mode-choice` shows the
  mode prompt rows.
  Record with `xcrun simctl io booted recordVideo` and inspect frames with ffmpeg
  (the Claude simulator tool's screenshot/inspect were unavailable on 2026-09-23).
  Without autoplay, the "Next board FX step" button advances manually.
- The preview has no native engine, so card art loads over the network via
  `AsyncImage`; flights can show the beige placeholder in the simulator. On device,
  art comes from `NativeCardArtworkView` local files.
- Still needed on device: a real engine game, Board Effects Full/Reduced/Off, iOS
  Reduce Motion, landscape layout, and sound levels.

## Status

| Phase | State |
|---|---|
| 1 Event timeline + first effects | Implemented on `codex/board-fx-timeline`. Unit tests, ios-fast preflight and generic iPhone compile pass. On-device visual acceptance pending. |
| 2 Card motion | Flights (arrive/depart/cast) and attack lunge implemented on `codex/board-fx-motion` (stacked on phase 1). Tests and generic iPhone compile pass. Visual acceptance pending. Blocker lunge/defender targeting and hand-card exact source rect not done. |
| 3 Card shaders | Dissolve (graveyard: ember edge, exile: cold edge) on departing flights and foil on the cast showcase, on `codex/board-fx-shaders` (stacked on phase 2). Compile + preflight pass. Not yet: foil on the held inspection card image (needs the image isolated inside `CardInspector`, not its rules text), playable-card glow, heat haze. |
| 4 Particles and sound upgrade | Sounds (cast, land, damage, death, player hit) and Effect Sounds toggle on `codex/board-fx-polish`. Vortex particles not adopted. |
| 5 RealityKit moments | Not started. D20 migration deliberately deferred (see log 2026-09-23 build 14). |
| 6 Game feel (build 14) | Readable spell showcases, arrival-after-cast, showcase for unseen casts, commander cast/entrance, attack stance + block tether + strike with impact-timed damage, turn-start ribbon, compact phase pill, victory/defeat screen, hand fan + lift under finger + breathing playable glow, legendary gold edge, inspection foil, color-identity particles, life badge de-duplication. Verified in the board-fx simulator walkthrough (optimized Debug build). Not yet: device feel, landscape combat pass. |

## Log

- 2026-09-23 (Claude): Created roadmap, phase 1 timeline/diff/scheduler/director with
  10 portable tests, Canvas overlay in both portrait and landscape boards, haptics,
  viewer-hit shake, Board Effects picker in the menu Display panel, in-game menu and
  Settings sheet. Not yet seen on a device. Next: phone check, tune timings/colors,
  then phase 2 (card flights) starting with extracting the battlefield card view.
- 2026-09-23 (Claude): Phase 2 card motion: `BoardFXDirector.subjects` + `cardMotion`,
  `BoardFXAnchors`, `BoardFXFlight` placements (arc, scale, rotation), tile modifier
  applied at all three `PortraitCardBoundsKey` sites. 12 portable tests. Next: phase 3
  shaders (foil sheen, playable glow, dissolve) in a `.metal` file.
- 2026-09-23 (Claude): Phase 3 first shaders: `BoardFXShaders.metal`, `BoardFXShading`
  modifier; graveyard/exile/unknown departures now burn away in place instead of
  flying off; bounces still fly to the hand. ios-fast preflight 11/11, generic compile
  clean. Next candidates: inspection-card foil, sound (needs Kenney download OK),
  simulator/device visual pass to tune timings and colors.
- 2026-09-23 (Claude): Simulator visual pass with the new `board-fx` preview. Fixed:
  effects lost to post-snapshot main-thread stalls (`BoardFXClock`), viewer/opponent
  life numbers overlapping creature damage (now at the life HUDs in portrait), flights
  now use `ArenaBattlefieldCard` for arrivals/departures. Added Kenney sounds and
  toggle. All six walkthrough steps verified on iPhone 17 Pro simulator (portrait).
  Next: device run with the real engine, landscape check, inspection-card foil.
- 2026-09-23 (Claude): Phases 1–4 merged (#24, #27) and shipped in TestFlight build 13. Next: real-engine game on device, landscape check, inspection-card foil, RealityKit D20 (phase 5).
- 2026-09-23 (Claude, build 14, branch `codex/board-fx-build-14`): Caleb's device notes on
  build 13: life number drawn twice (fixed: `BoardLifeTotal` badge only when effects are
  Off), cast showcase too fast (now 2.4 s with a readable hold), permanents landing before
  their spell finished (handoff pacing + cross-snapshot hold), wanted real attack motion
  (stance, strike flight, impact-timed damage, block tether). Also shipped the "next steps"
  list: hand fan/lift/pulse, commander entrance, turn ribbon, victory/defeat backdrop,
  big-spell flash, inspection foil, legendary edge, color particles. The old center phase
  card became a small pill under the top HUD so it no longer covers combat (UI test
  updated). Prompts: `PromptButtonLabel` renders {T}/mana symbols and {this}, strips XMage
  object IDs (`PromptDisplayText`), long options become full-width rows, primary buttons
  moved from light gold to deep bronze for contrast, the tapped-card ability popup lists
  abilities as full rows, and mode prompts are titled "Choose mode" (new `mode-choice`
  preview fixture). Preview walkthrough now has 10 steps (adds Kozilek commander cast and
  entrance, block, strike). Deferred on purpose: D20 SceneKit → RealityKit (identical
  visuals, SceneKit still supported, would put the start-of-game roll at risk; revisit with
  a real 3D feature) and a tilted 3D table (perspective would misalign touch targets and
  the effect anchors). Next: Caleb plays build 14 on device; tune durations, landscape
  combat pass, then consider RealityKit hero moments.
- 2026-09-24 (Claude): Build 14 work merged (#29) and shipped in TestFlight build 14
  (VALID, Beta App Review APPROVED, Internal + External). Next: Caleb's device notes.
- 2026-09-24 (Claude, build 15 work, branch `codex/board-fx-build-15`, installed directly on
  Caleb's phone, no TestFlight yet): abilities picked in the tap popup now carry the engine
  ability ID and the session answers XMage's follow-up "choose ability" prompt with it
  (exact ID match only, prompt held off screen, shown if anything fails); shortened XMage
  ability labels are completed from the card's rules line; Skip availability no longer
  flickers with the poll loop and a tap during a poll arms and passes after it; the card
  inspector shows detail chips (type, P/T, tapped, counters, keywords) and only shows rules
  text when the real image is not showing; keyword icons fall back to bare keyword lines in
  the engine's current rules text (not menace, which the engine projects); the top bar
  shows a colored "YOUR TURN / X'S TURN · phase" line and glow, the phase pill and turn
  ribbon fly into it, and the life orb glows on your turn; the hand-card lift on touch was
  removed. Next: Caleb's device feedback, then TestFlight when he says it's done.

