# Battlefield, card choices, tokens and match history

Implementation branch: `codex/board-choices-token-history`, based on main `9097d31`.
This is a work-in-progress acceptance record, not a release announcement.

## Approved behavior

- Landscape resource lanes: two rows of lands, or a land row and noncreature mana-rock row; rows scroll independently. Mana creatures remain in combat.
- Portrait: sparse mixed board, dense combat/support rows. Equipment and combat permanents stay in front; attachments follow their host. Every public permanent stays reachable through rotation and overflow.
- Large choice lists have search. Redundant chooser headings disappear.
- Multi-card selection is drafted locally, numbered/reorderable and submitted once by the user. XMage still receives one authorized answer per matching prompt. Scry shows keep-top and put-bottom with explicit next-draw order. Unexpected prompts or rejections stop continuation.
- Modal double-faced aliases represent one selectable object, with no raw UUID choice labels.
- All supported downloadable token images have a dedicated offline download route. Online artwork consent remains required. Copied tokens can use the original card's art only from explicitly disclosed source identity; engine-provided live types, abilities and stats stay authoritative.
- Match history has commander artwork, public opponents, deck identity, outcomes and expandable details. Completed-only aggregate results, all retained sessions reachable, backward-compatible local records, and pinned workspace tabs while the header scrolls away.
- Ship matching iOS and Android updates after applicable verification. TestFlight internal/external availability is separate from upload and external review submission.

## Invariants

XMage remains pinned to `4825513287ba6c42c32fd205d227f4a5fc44c2f3`. A bridge artwork hint is not an upstream rules update. Preserve Game Center. Dedicated Online and Render remain disabled/on hold. Never treat a fixture as engine or physical-device acceptance. Do not expose hidden card identities or download images without existing consent. Originals and release receipts remain recoverable.

## Acceptance checklist

- [x] Review integrated changes and regression tests (automated Astra orchestration/review with scoped Sol implementation; not human approval).
- [x] Portable Swift tests; Android core and app unit tests.
- [x] Exact-source JVM/privacy tests if bridge changes.
- [x] iOS simulator interactions and screenshots in both orientations (fixtures clearly labeled).
- [ ] Android compilation, lint and relevant native runtime/UI checks.
- [ ] Exact-source native artifacts, matching headers and provenance if rebuilt.
- [ ] Live build-number check, signed artifacts, preserved Game Center and unchanged app identities.
- [ ] Android APK checksum/signer/update compatibility; published download verified.
- [ ] Apple upload, processing, internal group, external group and actual beta-review state recorded.
- [ ] Final evidence and remaining physical-device limitations recorded.

## Initial review evidence

- Current App Store Connect 0.1.1 builds checked read-only on September 21, 2026: highest visible build is 6. Recheck immediately before signing/upload.
- Existing local Android SDK discovered at `/opt/homebrew/share/android-commandlinetools`; no new SDK installation is needed.
- One existing iPhone 17 Pro simulator (iOS 26.5) selected for presentation verification; no simulator data erased.

No upload or Android publication has happened for this change set yet.

## Frozen engine candidate

- Bridge source: `d9d745fe0904068f197ad8d6a81e69ac4a5eedaf`, branch `codex/board-token-engine-build7`.
- Adds seat-scoped token artwork/template hints only; rules pin and live characteristics remain unchanged.
- Independent local compilation and 10 real JVM projection regressions passed using the verified pinned baseline dependency cache. This is not native execution.
- Fresh exact-source non-simulator gate: https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628109901 (passed, including real JVM checks).
- Android native build: https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628113147 (passed). Full native ZIP verified against GitHub's SHA-256 and staged with exact-source verification; signing/runtime acceptance remains separate.
- Gated iOS far-call native build: https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35630421619 (pending, dispatched only after the same-SHA gate passed).
- Shared version prepared: 0.1.1 (7); Android installation code 2026092101. Apple build 7 was absent at preparation; check again before upload.
- Local build-number tests: 10 passed. Android tooling tests: 7 passed. Native C boundary fixtures passed (not real native engine gameplay).

## Integrated verification in progress

- Initial unlinked iOS app and test-target compilation passed. This does not establish native linkage or gameplay.
- First simulator batch: token-only scope consent/persistence, portrait resource rotation, and Cards pinned-tabs tests passed. Two landscape tests failed before delivering a drag because their chosen fixture cards started offscreen; the revised helper must drag visible artwork and retain movement/independence assertions. The history test measured a small accessibility element rather than the whole header; revised visible-content and sticky-scroll assertions still require execution.
- First batch evidence: `/tmp/magicmobile-board-ui.VXMyx4/Presentation.xcresult`; exported screenshots/recordings remain alongside it. All board/history development fixtures are labeled and do not run XMage.
- Follow-up integrated compilation found an optional-binding error in the new stop/review handler; corrected. Third integrated `build-for-testing` passed (`/tmp/magicmobile-board-integrated-build3.log`).
- Full portable Swift rerun passed: **384 tests, two explicit opt-in skips, zero failures** (`/tmp/magicmobile-board-portable-final.log`). The skipped cases require a local bulk-artwork fixture and an explicitly enabled live Archidekt URL. An artwork test's persistent URL cache caused a prior request-count failure; an isolated memory-only test cache corrected it without changing production behavior.
- Matching self-host runtime packaging passed from the frozen bridge source: https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628982999 (959 real-engine HTTP assertions, verified artifact and runtime checksums; no hosting deployment).
- A bounded public Scryfall query confirmed that ordinary black 2/2 Zombie token metadata/art is available, alongside different token variants and double-faced records. The resolver must match metadata safely rather than take the first name match. This query did not exercise a full device download.
- Second simulator batch: 24 Arena presentation unit tests passed; nine of ten UI tests passed, including all three resource-row/rotation tests, both creature-type search states, portrait/landscape scry drafting, Cards sticky tabs, and token-download consent. Playtest history failed at scroll-view discovery after tab selection and remains under investigation. Evidence: `Presentation2.xcresult` and `test2.log` beside the first batch.
- Parent-reviewed landscape scry screenshot exposed clipped captions/order labels despite passing touch assertions; a compact-layout correction and visual rerun are required. The completed test batch's OS diagnostic collection stalled; only its owned `simctl diagnose` subprocess was terminated, preserving the finalized xcresult and attachments. No running test was cancelled.
- Independent integrated Android validation passed: 132 protocol/deck/privacy assertions, 42 auto-yield assertions, 71 Deck Studio assertions, 14 provider assertions, 20 role/probability assertions, **41 app unit tests**, and `lintDebug`. Log: `/tmp/magicmobile-board-android-integrated.log`. These are JVM/compile/lint checks, not native gameplay or phone acceptance.
- Final portable Swift rerun after recovery fixes: **387 tests, three explicit opt-in skips, zero failures** (`/tmp/magicmobile-board-portable-final2.log`). The added opt-in test separately passed against public Scryfall: downloaded/decoded Zombie token art, persisted and reloaded offline, and resolved distinct source-card artwork for copied Loyal Guardian. No private deck or game information was transmitted.
- Independent review found a staged-choice failure could otherwise wait indefinitely on an unchanged prompt. New command failures and cleared-but-unchanged submissions now return to manual review without automatic retry. Focused plan/adapter regressions passed; new simulator error-recovery and landscape clipping assertions are pending execution.
- Integrated compilation after recovery wiring hit SwiftUI expression complexity. Splitting observation, choice overlays and phase presentation into separately type-checked expressions preserved modifier order and passed `build-for-testing` (`/tmp/magicmobile-board-integrated-build6.log`).
- Third simulator batch: six of seven tests passed, including error recovery, both search states, landscape caption/order visibility, Cards tabs and Playtest history (all 18 fixture sessions reachable). Independent screenshots confirm readable landscape choices and pinned Playtest tabs. The remaining portrait test read a lazy card after tapping an offscreen ordering control scrolled it away; the capture shows correct order. The test must navigate back within its scroll view and rerun the original order/deselect/confirmation assertions.
- Artwork-focused checks after isolating the two remaining test caches: 76 tests, two opt-in skips, zero failures. No production cache behavior changed or generated cache files committed.
- Final portrait scry rerun passed all original order, deselection and single-confirmation assertions after scrolling the actual choice viewport back to its cards (`PortraitFinal.xcresult`, 16.530 seconds). All seven affected choice/history tests now have passing current-source evidence, alongside the earlier three resource-row/rotation and token-scope consent tests. These remain labeled simulator fixtures, not native engine gameplay.
