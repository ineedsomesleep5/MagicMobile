# Card interaction repair candidate — 2026-09-15

Selected checkout: `MagicMobile-runtime-hardening`, branch
`codex/native-runtime-hardening`, PR #9. Baseline: `c76b9a41c858cb5ebcae483cd028f60a90ba47c5`.
Prepared internal-only TestFlight build: **0.1.0 (2026091502)**.

## Changes and acceptance contract

- Sideways swipes browse the entire hand; upward drags retain the existing legal
  play resolver. Tap/hold and accessibility actions inspect the card. The scrubber
  follows the actual scroll offset. No command is invented by the gesture layer.
- Native single-UUID card choices open an automatically sized card browser.
  Supplied nonmatching cards remain visible but disabled; `possibleTargets` and
  `chosenTargets`, not the broader transport candidate inventory, govern legality.
  Face aliases inherit their base card's eligibility. Hidden cards lose identity,
  rules and nested reverse-face details. ID-only offboard choices recover only
  matching cards from the current authenticated snapshot.
- Mixed card/player/other targets remain available. Selection and deselection
  submit one original ID and current prompt revision. Optional Done uses only
  the engine's explicit Boolean response. XMage owns subsequent choice/order loops.
- Priority does not automatically open a large action sheet over the stack.
  Scry/search inspection is separate from ordinary Pass/Skip/card controls.
- Game logs use native styled text: player/card emphasis, readable actions and
  turn separation, no raw HTML or UUID attributes. Only UUID-matching card suffixes
  are suppressed. The log stays closed until requested and does not force readers
  back to the bottom when they are reading earlier events.

## Verification checkpoint

Evidence is retained locally under `build_output/choice-repair/`.

- `presentation-final.log`: 236 tests, one optional fixture test skipped, zero failures.
- `protocol-final.log`: 33 protocol/transport tests passed.
- `core.log`: 419 core assertions plus 72 failure-boundary assertions passed.
- `adapter-javac.log`: current production Java adapter compiled without diagnostics.
- `real-card-choices.log`: eight real-JVM cases passed, including actual ScryEffect,
  filtered/restricted/zero-match searches and mailbox seat isolation. Pinned
  upstream compiled dependencies were reused locally; hosted clean-build evidence
  remains a separate gate. The same bounded runner is wired into the real-JVM job.
- `build-number.log`: six build-number tests passed. App Store Connect returned
  no existing build 2026091502 at preparation. Existing Internal group has all-build access.
- Simulator unit suite: 422 tests, one optional fixture test skipped, zero failures.
- Initial simulator failures exposed priority-sheet routing and competing hand
  gestures. Both were repaired; a separate subpixel edge assertion was corrected
  after confirming the final hand card was fully visible.
- `gesture-arbitration.xcresult`: five focused hand drag/scroll and stack/rotation
  cases passed. Native pan failure dependencies preserve horizontal browsing and
  upward casting in both orientations. Temporary diagnostics were removed.
- Final complete BoardPolish + OnDeviceSetup UI run is in progress on the frozen
  candidate; its conclusion remains required before release.
- Independent diff review found mixed-target omission and inaccessible hand
  inspection; both were repaired. Final independent source review found no remaining
  concrete P1/P2 blockers. Simulator and release gates remain separate requirements.

## Engine reuse and release boundary

No guarded engine input changed. Existing native run **34930407016**, engine source
`aa50beea953d7c820417826128d88de72123686b`, artifact **10383692026** remains available.
All 51 hash-covered artifact files passed validation locally. Archive SHA-256:
`cc5b79e978d2669d491a6cc9b25703af0cd8367d28429769373599e423a4bf3c`.

Final clean-source equivalence, same-source hosted non-simulator checks, unsigned
native-linked product, signed/exported layout and Apple validation are required
before upload. Do not rebuild the unchanged engine merely for a newer timestamp.
No Three.js migration, new rules engine, simulator engine, public release or
automatic upstream upgrade is included.

Fixture simulator screenshots prove presentation/interaction only. Real-JVM
checks do not prove native gameplay or Game Center transport. Apple processing,
Internal availability and physical acceptance must be recorded separately.
Phone follow-up: browse/inspect the full hand, drag a legal spell, scry with
Temple of Plenty, inspect authorized graveyard/exile/search pools, check the
formatted log and stack response in both orientations. Retain failures privately.
