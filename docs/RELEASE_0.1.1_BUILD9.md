# iOS 0.1.1 build 9 — candidate, not yet distributed

## Scope

- iOS only. Android development, versioning and distribution remain paused.
- Resolve compiled MDFCs by combined, front and unambiguous reverse names,
  including existing saved decks and text imports. Unknown cards still fail closed.
- Show green land offers, white spell offers, or a split border when the engine
  currently offers both. Native spell metadata, not a guessed phase or card type,
  distinguishes modal spell offers from other playable actions.
- Match Food's self-named sacrifice cost to the equivalent downloaded token
  identity without collapsing incompatible token variants or replacing valid art.
- Search visible card choices by name, type and rules text. Keep engine selection
  eligibility intact. Center the responsive chooser in both orientations.
- Keep the primary completion action distinct from special actions such as Attack
  all, and bind its view identity to the current prompt/message revision. Actual
  forced attacks from rules such as Kardur remain engine-owned.
- Open opponent-led match history as a full-screen dashboard with responsive
  charts, observation review and inspectable public events. This is sampled
  public evidence, not deterministic replay or reconstructed hidden information.

## Verification recorded so far

- Portable suite: 413 tests, four optional live checks skipped, zero failures.
  Original log: `/tmp/magicmobile-build9-portable-full.log`.
- Separate bulk audit: all 31,881 supported ordinary card names resolved, zero
  unresolved. This is reference coverage, not a fresh download of every image.
  Log: `/tmp/magicmobile-build9-bulk-audit.log`.
- Persisted offline token audit covers runtime Food wording and stored Food,
  Treasure, Clue and Blood; existing missing/corrupt repair tests preserve valid
  cached images. Public token-store evidence remains at
  `/tmp/magicmobile-offline-artwork.zvEZKT/live/`.
- Exporter: 12 self-tests pass. The regenerated alias map adds 44 missing compiled
  MDFCs; no ordinary catalogue values were changed. Full exporter regeneration
  was not claimed: exact complete generation inputs are not available locally.
- Real pinned-JVM modal spell and land-only regressions pass independently:
  `/tmp/magicmobile-build9-real-modal-spell.log` and
  `/tmp/magicmobile-build9-real-modal-land.log`.
- Simulator app/test compilation passes. Five focused UI tests pass for both
  orientations of library search and scry, plus full-screen history inspection,
  preserved observation, rotation, side-by-side charts and legacy fallback.
  Keyboard-open search results stay reachable. Screenshots were visually reviewed.
  Original log: `/tmp/magicmobile-build9-ui-run7.log`; screenshots and earlier
  failed runs remain under `build_output/ios-ui-build9/`. The run exposed unstable
  presentation ownership inside adaptive/lazy content; the full-screen dashboard
  is now owned by the workspace root. These are labeled development fixtures,
  not real native gameplay or physical-device acceptance.
- Ten additional integrated UI regressions pass: both orientations of MDFC
  offer glows and mixed choices, two pinned workspace checks, and four download
  coverage/consent/preference checks. Log:
  `/tmp/magicmobile-build9-ui-regressions.log`. Copies of the accepted logs and
  UI source/binary fingerprint are retained in `build_output/build9-evidence.LP48ic/`.

## Native and release gates

Upstream remains `4825513287ba6c42c32fd205d227f4a5fc44c2f3`. This candidate
changes the adapter and requires a newly verified native artifact; build 8's
archive is not a substitute.

Frozen native source: `54264b0ae2645515b8dacf908c9be6bfd0db247c` on
`codex/ios-build9-native`. Cheap gate: GitHub run `35672119944` passed all
required jobs, including the real-game lifecycle and bundled-deck checks.
Native run `35673448459` passed candidate approval and is building.
The earlier cheap run `35671388465` failed on stale runtime-manager fixture
dependencies. The repair compiles the real production timeline and sanitizer;
it does not stub or weaken the assertions.

Native build/provenance, final app verification, signed export, Apple validation,
upload and Internal/External distribution remain pending. No new TestFlight
availability or physical-iPhone gameplay acceptance is claimed here.
