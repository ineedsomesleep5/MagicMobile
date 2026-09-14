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
