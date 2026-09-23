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
| `apps/ios/MagicMobile/BoardFXOverlay.swift` | SwiftUI renderer, painter helpers, shake, haptics, settings picker. App target only. |
| `apps/ios/MagicMobile/ContentView.swift` | Integration only: state on `NativeGameView`, `ingestBoardFX`, `boardFXOverlay`, both board overlays, three settings panels. |

Event order within one transition: spell cast → attack declared → left battlefield →
damage → entered battlefield → counters → life. At most
`BoardFXScheduler.decorativeLimit` decorative effects per transition; life changes
are always kept.

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
- Visual acceptance still needs a device or simulator game: play a creature, kill a
  creature, cast an instant, attack, take damage, and switch Board Effects between
  Full, Reduced and Off (plus iOS Reduce Motion).

## Status

| Phase | State |
|---|---|
| 1 Event timeline + first effects | Implemented on `codex/board-fx-timeline`. Unit tests, ios-fast preflight and generic iPhone compile pass. On-device visual acceptance pending. |
| 2 Card motion | Flights (arrive/depart/cast) and attack lunge implemented on `codex/board-fx-motion` (stacked on phase 1). Tests and generic iPhone compile pass. Visual acceptance pending. Blocker lunge/defender targeting and hand-card exact source rect not done. |
| 3 Card shaders | Not started |
| 4 Particles and sound upgrade | Not started |
| 5 RealityKit moments | Not started |

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
