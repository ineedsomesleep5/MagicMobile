# Real card-choice and payment interaction checks

These tests use the `RealQueryTests` fixture pattern to exercise
actual pinned XMage choice loops and the production MatchMailbox. These are
application interaction tests; they do not change engine sources or verifier
exclusions.

## Run

From the repository root, with JDK 21 (`java`/`javac`) and Python 3 on `PATH`:

```bash
bash apps/ios/MagicMobileTests/EngineChecks/run.sh
```

Prerequisite: current compiled core/adapter and pinned upstream dependencies in
`packages/ondevice-engine/build/runtime-classpath.txt`. The script compiles only
the two test classes, then runs them with production classes first. It retains test classes
and incidental runtime output under `packages/ondevice-engine/build/card-choice-check.*`.

Budget: sequential compilation (256 MiB heap, 60-second timeout) and two sequential test JVMs
(384 MiB heap, 90-second timeout each), at most 240 seconds of subprocess time excluding
prerequisite builds. No native compilation. Expected result:
`RealCardChoiceTests: 8 passed` and `RealPaymentInteractionTests: 7 passed`.

## Scenarios and limits

- Temple of Plenty's actual ScryEffect: keep or bottom one card.
- Five-card scry: select/deselect, Done, bottom ordering and top ordering.
- Filtered search: a visible nonmatch causes HumanPlayer to repeat the unchanged
  prompt; a matching card succeeds; declining remains possible.
- Zero-match and restricted searches: retain disclosed nonmatches, assert omitted
  empty `possibleTargets`, and keep deeper cards outside the permitted pool private.

Assertions cover visible/candidate/possible/chosen IDs, names, target zones,
required/response types and final library order. Every callback checks mailbox
seat isolation and rejects another seat's use of the owner's exact prompt token.
Restricted searches use `TargetCardInLibrary.setCardLimit`; they do not test Aven
Mindcensor's replacement-effect installation. Separate tests must cover
XmageEngine seat/controller routing, GameView privacy, Swift eligibility/redaction
and device behavior.

Payment checks execute real HumanPlayer actions, not just metadata assertions:

- Sol Ring, Selesnya Signet and Arcane Signet tap and produce the exact mana;
  Signet's activation mana is consumed. Tapped sources lose their mana offer.
- Jaspera Sentinel pays both tap costs and answers an actual color choice.
- Conclave Tribunal casts using Sol Ring + Plains, then Special → Convoke ability
  UUID → creature UUID, including a summoning-sick convoker.
- Six-permanent sacrifice selects two creatures, deselects/reselects, then selects
  four lands; all six go to the graveyard only after completion. Cancel at two
  sacrifices none. Every query rejects cross-seat answers.
- Menace icons reflect live gain/removal, including a printed keyword removed
  from the permanent; face-down permanents and hidden hands do not leak it.
- **Known upstream estimate limitation:** two lands + Jaspera offer Tribunal,
  but actually using both lands and convoking Jaspera leaves `{1}` unpaid. Cancel
  restores the card to hand and clears the stack. This characterizes the bug;
  it does not declare the estimator fixed. Cast offers must not promise payment.

The payment fixture initializes a real match without `game.start()`, seeds cards
and live keyword changes, and seeds GameImpl's normally start-initialized turn
cursor so real cancellation can restore state. It does not run an opening game,
resolve keyword-granting spells, or establish complete card/device parity.

## Validation evidence

Local validation on 2026-09-15 refreshed current core (419 core assertions and
72 failure-boundary assertions passed), recompiled the current Java adapter, and
passed all eight card-choice cases. Pinned upstream compiled classes were reused
at commit `8aea65ae9ae3c89970fe865e1316105539e097ca`; this was not a clean upstream
build. Evidence under `build_output/choice-repair/`:

- `core.log`: 419 + 72 assertions passed.
- `adapter-javac.log`: adapter compilation log (empty; no compiler diagnostics).
- `real-card-choices.log`: all eight cases passed.

A hosted clean-build pass is still required. The `real-jvm` job in
`.github/workflows/magicmobile-issue4-nonsimulator.yml` is wired to run this same
`run.sh` after `build_jvm.sh` and `test_real_engine.sh`, recording
`evidence/real-card-choices.log`. Local JVM results do not establish native or
phone acceptance.

The seven payment cases also passed locally on 2026-09-15 against freshly
compiled `ViewProjector.java` and the same reused pinned upstream classes. The
rock metadata regression fails against the preceding compiled adapter. This
new projection is **source/JVM evidence only**: the installed native candidate
`aa50beea953d7c820417826128d88de72123686b` does not contain it. The existing
hosted `run.sh` step now executes both suites, without a workflow/guard exemption.
