# Maintenance continuation checkpoint

## Scope and baseline

Checkout: `/Users/calebfeliciano/Documents/MagicMobile-runtime-hardening`.
Branch/PR: `codex/native-runtime-hardening`, #9, based on #8 and #6.
Baseline: `56d94497ba887dfff49ea46c6c03d49deb73df3f`.
Root verified both ancestor commits with `git merge-base --is-ancestor`.
Other occupied worktrees were preserved. No source is replaced from the older ZIP.

Acceptance: reconcile current evidence, map production paths, add bounded lifecycle
coverage, implement inactive upstream automation and an explicit native approval
gate, then execute relevant local/hosted checks and review the final diff.
No signing, distribution, simulator, upstream-pin advancement or issue comments.

## Phase 1 evidence

Live run/artifact metadata checked September 14, 2026 using `gh api`.
Native run `34803650513` and unsigned product run `34805592902`: completed/success,
attempt 1, correct repository/workflow and respective source SHAs `f8e1680`/`101985d`.
Artifact `10334439109` was retrieved with `download_issue4_native.py`; GitHub ZIP
digest and safe extraction passed. `verify_native_candidate.validate_receipt`
verified 51 hash-covered files. Native archive SHA-256:
`99c8d7ef186c37d3c409473101eaeb89abc8075cbb5eaddad9196eff43e97a9b`.
Product evidence `10334294606` downloaded/hash-checked with the same helper.
The actual unsigned product receipt records app `101985d`, engine `f8e1680`,
191,665,664 Graal code bytes, 818 checked relocations and seven checked veneers.
This receipt is historical product inspection; no phone execution is claimed.

Current local caches: `build/review-native-10334439109` and
`build/review-product-10334294606`, relative to this package. They are ignored
artifacts, not committed or installed into the app.

## Bounded verification plan

`scripts/test_seeded_soak.py` defines ten scenarios: driver seeds 1907/2909,
two/four human seats and one human with one/two/three real MAD opponents.
Each scenario interrupts one initial choice, recreates in the same JVM, submits
eight human choices through the real protocol until priority and a newer running
prompt after the final queued answer are observed, destroys
and checks stale-match rejection, then shuts down and rejects new creation.
Per-scenario process-group limit: 150 seconds. Whole matrix budget: 1,550 seconds.
Driver seeds control deck-row ordering/explicit choice selection only; upstream
shuffle and AI scheduling are not deterministic. This matrix is not full games,
multi-device transport or native execution. Existing complete-game and MAD
land/cast/combat suites remain required.

Receipts retain synthetic test correlation and commands, never production user
cards or private snapshots. Failure type/seed and an explicit timeout receipt
survive bounded failure; the owned process group is cleaned on success, failure,
timeout and parent cancellation. Cached class/JAR bytes are fingerprinted, but the
driver explicitly does not assert their source from checkout HEAD. Fresh hosted
checkout/build job provenance supplies that separate association.

## Focused implementation and local checks

- `DecisionSpec.java` previously accepted another valid UUID for a floating-mana
  response. A negative core test failed before repair. Exact prompt `manaPlayerId`
  validation now preserves the acted player's pool during controlled turns.
  A second reproduced defect classified malformed mana UUIDs as engine failures;
  these now return `invalid_response`. Core: 419 assertions; failure-boundary:
  72 assertions. The added real-XMage
  controlled-turn regression still requires hosted execution.
- Lobby validation now distinguishes an authenticated incompatible build from
  stale, unauthorized and malformed traffic. The first negative tests failed twice
  before repair. Independent review added submission/start schema regressions;
  124 macOS presentation tests passed after the final fix. Actual GameKit callbacks
  remain SDK/physical gates, not portable execution evidence.
- Soak critic reproduced queued-final-answer false success and incomplete parent
  cancellation cleanup. Sixteen driver fixtures now pass after those repairs.
- Final package tooling: 227 tests passed, two explicit skips; C boundary: 8,000 normal
  and 1,000 sanitizer requests plus five shutdown-failure fixtures passed.
- Swift protocol: 33 Swift Testing cases (and the separate XCTest protocol cases)
  passed. Production runtime-manager fixtures: 27 assertions; Swift-close fixtures
  passed. These are not actual XMage AOT execution.

Local commands used package `scripts/test_tooling.sh`, `test_native_boundary.sh`,
`test_swift_close.sh`, `test_runtime_manager.sh`, and the two documented
`swift test --package-path ... --jobs 2` commands. Apple commands used
`/Applications/Xcode.app/Contents/Developer`; core used Homebrew JDK 21.

Final source **requires a new full ARM64 artifact** because production Java and
guarded engine regression sources changed. The downloaded prior artifact is
historical evidence only; it cannot contain the new mana validation fix.

## Work and review pending

Upstream automation and native gate are independently scoped to orchestration
directories outside native build inputs. Independent critics reviewed the actual
Java, Swift, gate and maintenance diffs. Their reproduced findings were repaired:
malformed handshake classification, producer step/attempt verification, both
upstream source manifests, metadata identity and exported-tree static auditing.
Final re-review found no remaining concrete blocker in that bounded scope.
Maintenance fixtures: 27 passed; native approval fixtures: 12 passed. Workflow
YAML (12 files), shell syntax and whitespace checks passed.

Only local/source/fixture gates are complete at this checkpoint. Final immutable
hosted non-simulator checks, newly required ARM64 compilation, paired unsigned
product linkage and publication identities will be recorded after execution.
The maintenance schedule and publisher remain inactive; no real upstream upgrade
has been selected or executed. No signing, TestFlight, native phone gameplay or
multi-device Game Center acceptance is claimed.

## First published verification and justified driver correction

Published source `258b78d8134b01e798ab1ff596d4aca6b339a3f5`, policy
`ccd5ea578760e8ac8e20c916c09a3e7a48898121`: CI `34869095016` and package
`34869094959` passed. The latter executed the new mana-identity regression,
15 real query cases, controlled turns/privacy, commander and lifecycle suites.
Package upstream reporting was intentionally skipped on the PR event.

Non-simulator `34869089547` passed four jobs (including Apple SDK compilation)
but failed the new matrix. Retained JVM artifact `10358961581`, ZIP SHA-256
`975917eb8cee2b13f500d8efff22d9b7500af6ae2a69efc5ccceaaa556e2ac15`, was
downloaded/hash-verified. Four human-only scenarios passed; the first 2-player,
1-AI case failed before any response. The driver incorrectly expected `create.seats`
to omit AI. Production `XmageEngine.create` correctly returns the complete roster;
mailbox authorization separately limits input recipients to humans.

Correction checks the full configured roster and asserts actual AI-seat polling
returns `unauthorized_seat`; it does not weaken the engine, progress assertion,
scenario count or deadlines. Seventeen driver fixtures pass. A new exact-source
hosted run is required. No native build was dispatched on the failed cheap gate.

Apple artifact `10358328354`, ZIP SHA-256
`6b577fd71ea6c9d7d0df1aafbce3324f1a25d57a12571e1170f3b33ac0a7e2f5`, was
also downloaded/hash-verified: 124 app tests, 21+33 protocol cases, 27 runtime
fixtures, five exact exported decks and successful generic SDK test compilation.

## Verified pre-phone candidate — September 14, 2026

Functional application and engine source: `d04f9cac88d680af10fe7174fab85f624e5ad491`.
[Non-simulator 34871098576](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871098576),
[CI 34871103720](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871103720)
and [package 34871103725](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34871103725)
passed. All five non-simulator jobs and their required steps executed successfully;
package upstream reporting was intentionally skipped on the PR event.

A **new** full ARM64 engine was required by the production mana validation and
guarded engine regressions. [Native 34872508758](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34872508758)
passed on attempt 1 after the exact-SHA cheap approval gate.
[Unsigned Release product 34883826069](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34883826069)
passed on the same application source with that exact artifact; all required
verification, staging, release-source, linking and settings steps passed.

Native artifact `10363785536`, ZIP SHA-256
`b82f90f08f7ac0b3505b96cf23e83e1759e517bbf4243b4543dd296051fa4c0a`,
was downloaded safely and all 51 hash-covered inputs verified. Archive SHA-256:
`b4e361b5687474e658dcc25470e70de6f8816c08c8f11e4fd49be78eec9424f8`.
Guarded input digest:
`1a9a449fd8af68bd96bc7f5d4b3f729ff1ecc5c4122e4b38c69c8ff1ffe2db95`.
Product evidence artifact `10364317309`, ZIP SHA-256
`0458ffd778cd4b207be53fe8011302dcd93637554350f5b7c1d0359d88ff743b`,
was downloaded/hash-checked. Its receipt binds the exact engine provenance and
records unsigned binary SHA-256
`3c7deafd526ed09a2d85cdfe6dc2c48b34089b3f3cead652167d898c05f8442c`,
191,584,800 intact Graal code bytes, 818 verified relocated instructions and seven
verified veneers. This is ARM64 compilation/product linkage, **not native execution**.

The final documentation commit may be newer than this functional source. Reuse
requires unchanged guarded engine and application/product inputs; a newer document
timestamp is not a new hosted build. No signing, upload, simulator, phone execution
or actual Game Center transport acceptance occurred. The unsigned product still
uses the old build-number setting `2026091301`; it is not upload-ready with that
number. Select an unused number only in a separately authorized release task.

## Final bounded verification and maintenance result

The first matrix-driver correction was published as `d04f9cac88d680af10fe7174fab85f624e5ad491`.
Non-simulator run 34871098576 passed all ten scenarios: eight human answers each,
observed priority and a newer post-answer running prompt, lifecycle cleanup and
AI-seat authorization rejection. No deadline, scenario count or production guard
was weakened. Real query tests: 15; controlled turns: 5; privacy: 8; commander: 10;
projection: 9; busy shutdown: 4; resolving cancellation: 2. Completed two/four-seat
and token/mulligan JVM games and all five exact exported precons passed separately.
Real-JVM artifact `10359357164`, ZIP SHA-256
`8302fd995c8f3d4e9d9e0bef4e7928e4ed752c77fb9d78b249acacf556db7848`,
was downloaded/hash-checked and all ten complete scenario receipts inspected.

Final local/hosted counts supersede the chronological intermediate counts above:
419 core + 72 failure-boundary assertions; 228 tooling cases with two skips;
124 macOS app XCTest cases; 21 protocol XCTest + 33 Swift Testing cases;
27 runtime-manager assertions; 17 soak-driver fixtures; 27 maintenance fixtures;
12 approval fixtures; six exported-tree static-audit fixtures. C checks exercised
8,000 normal plus 1,000 sanitizer requests and five shutdown failure cases.
Generic device SDK tests compiled but were not executed.

Independent critics reviewed the actual runtime, lobby, maintenance, soak and gate
diffs. All reproduced findings were repaired before the final cheap/native gates.
No known demonstrated defect remains in that bounded scope; no exhaustive-card,
native gameplay, rendered-UI or multi-phone acceptance is implied.

Read-only live detection was also executed:
`python3 -B scripts/magicmobile-maintenance/upstream.py detect --output packages/ondevice-engine/build/maintenance-live-detection-d04f9ca.json`.
It observed upstream `e709c4d324caba2fe63bfad9b5f99eabcf64d25a`: 66 changed paths,
zero detected dependency-file changes, all three main and five repository patch
blobs unchanged. Report SHA-256:
`596e524c3ec98f70c511afe9d959293f83e4c647f5261c59a7c5216826a9cbfa`.
This observation did not select or approve an upgrade. Production remains pinned
to `8aea65ae9ae3c89970fe865e1316105539e097ca`.
Schedule, notifications and candidate publisher remain inactive; candidate
preparation/publication and failure handling were fixture/dry-run tested, not
end-to-end executed against an actual upstream upgrade. See the maintenance README
for explicit future activation, review and dispatch instructions.

## Separate signing/internal-TestFlight handoff

With separate release authorization, use this PR #9 continuation and the exact
verified new native artifact; check final source equality, preserve paired inputs
and `com.calebfeliciano.magicmobile`, select an unused App Store Connect build
number, regenerate/stage the actual product and run all existing Release/signing/
archive/dSYM/layout/privacy guards. Use internal-only TestFlight, verify Apple
processing and existing Internal-group access. No public release or new audience.
Do not reuse build 2026091301 or infer phone acceptance from this unsigned build.

First phone test: Token Triumph versus one Grave Danger MAD opponent, human starting
player, mulligan/keep-hand; then mana, commander, AI, combat/tokens, background/resume,
exit/new match. Use explicit private diagnostics on failure. Issue #7 remains the
unexecuted physical and multi-device acceptance gate.
