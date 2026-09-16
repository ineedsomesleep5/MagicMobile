# Commander polish TestFlight upload 0.1.0 (2026091601)

## Intended tester notes

- Deck Studio now opens on your deck, with compact artwork rows, search/filter,
  grouping/sorting, quantity edits, undo and local draft recovery.
- Paste plain-text exports from Moxfield or Archidekt, review quantities and
  commander/sideboard sections, and keep unresolved names as an editable draft.
  Printing and category annotations are shown during review. Import confirmation
  stays accessible below the form instead of being buried after all card rows.
- Improved local startup/validation reports and historical-report labeling.
- Card-backed ability choices, richer stack/source details and inspectable logs.
- Centered phase cues, life-change feedback, stronger playable-card outlines,
  and improved expanded-hand scrolling in portrait and landscape.
- Updates menu distinguishes this installed engine from upstream XMage news.

Please test imported Commander and partner decks, invalid-deck reports, manual
mana-rock/convoke payments, large sacrifice selections, card selection/search,
hand scrolling/inspection, phase changes and life gains/losses in both orientations.
Share diagnostics only by explicit choice; reports can include card information.

## Deliberate limitations

- Public deck links depend on provider availability. Text paste does not require
  provider authentication or network access for name resolution.
- EDHREC uses an explicit copy-deck/open-website flow, not undocumented scraping
  or a claim of native personalized recommendations.
- No Rive dependency was added. Its CLI was researched separately; commercial
  export clarity and device profiling are prerequisites to adopting it.
- Simulator fixtures and JVM regressions are not physical-iPhone gameplay proof.
- XMage can offer starting a cast that still cannot be fully paid (covered by the
  Tribunal/Jaspera regression). Highlights are engine-offered actions, not a
  client guarantee of affordability; manual payment and cancellation remain available.

## Release evidence

- Selected checkout: MagicMobile-runtime-hardening, codex/native-runtime-hardening.
- Frozen engine: fca652a80f643d4a88fe2f8f0ac781be1fd096a4.
- Same-SHA non-simulator gate: 35046969413, success.
- App source: `298c2aeb021fbe13efc51e66a4b7e25d6b8a5d05`.
- Full native workflow: [35048126381](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35048126381), success.
- Native artifact: `10429233424`, ZIP SHA-256
  `26ea4aed5420484ce12df7dce87aba58e3e1fe26b2ed66eab5dc9c56ed24259f`.
- Exact-source native-linked Release product: [35051733562](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35051733562), all required steps passed.
  Product evidence artifact `10428669866` was downloaded and hash-checked.
- Build number prepared via repository helper; live ASC query confirmed no
  matching 2026091601 build immediately before the signing/upload workflow.
- Portable tests: 274, one optional live-provider skip, zero failures.
- Final SDK unit run: 477, one optional skip, zero failures.
- UI matrix plus targeted repairs cover 53 distinct cases: both provider paste
  flows, board gestures, exact ability submission, phase/life feedback, recovery,
  editing and keyboard behavior. Final deck-tool rerun: three tests, zero failures.
- Final motion capture rerun: four tests, zero failures; visible centered phase
  cue and red/green signed life deltas inspected. Preview screenshots use explicit
  development fixtures and placeholder artwork, not a native game.
- Archive/export, signed native layout, matching symbols, app identity/Game Center
  checks and Apple validation passed. Apple reported upload success with no errors
  on 2026-09-16 at 03:56:34 UTC.
- Delivery UUID: `283fbc18-a35c-4d9f-b68d-b2331e9ff4e4`.
- IPA: `build_output/testflight/commander-2026091601/native-release.HXlhwO/export/MagicMobile.ipa`.
  SHA-256: `fbbff091ee188b333ee5cb3981281ec16e2ec32950bab9e498b73c3ddc1cec5c`.
- Archive, dSYM and all source/signing/upload receipts are retained in that
  `native-release.HXlhwO` directory. The previous staged native engine is preserved
  at `build_output/commander-2026091601-previous-NativeEngine`.
- Apple processing is `VALID`; Internal is `IN_BETA_TESTING`. Membership in the
  existing Internal and External groups and the English tester notes are verified.
- TestFlight readiness validation returned zero errors/warnings/blockers. External
  review submission was rejected because build `2026091504` is already
  `WAITING_FOR_REVIEW` in the same version train. New build `2026091601` remains
  `READY_FOR_BETA_SUBMISSION`; it is not yet available to external testers.
  Retry submission after the older review completes. No older review was cancelled.

Physical-iPhone native gameplay, full offline-match acceptance, multiplayer,
memory/thermal behavior and artwork quality are not established by these checks.

## Local simulator screenshots

- [Centered phase cue](../../build_output/commander-motion-portrait-phase/8FF5ACB0-2836-43BA-A203-9C0A1B7F795F.png)
- [Life-loss pulse and signed delta](../../build_output/commander-motion-landscape-life/069A081B-BE31-4F59-A13C-46D30BDD8DEB.png)
- [Landscape Deck Studio](../../build_output/commander-final-landscape-deck/D313DF21-3483-4789-8E85-7DDB5E70381D.png)

Board images are labeled development fixtures. The deck image is an actual
local editor test with artwork downloads disabled; none proves phone artwork quality.
The [Rive CLI assessment](../../outputs/rive-cli-assessment.md) explains the
native-motion choice and prerequisites for a future authored-effects experiment.
