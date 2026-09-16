# Commander polish execution ledger

Approved scope: native gameplay and deck studio polish, structured failure reporting,
card-backed ability/stack presentation, centered turn cue, upstream maintenance and
news, followed by verified internal/external TestFlight delivery.

## Ownership

- Lead: shared board/root integration, Models.swift, project configuration,
  release identity, final verification and TestFlight.
- Engine agent: validation/diagnostic protocol, native source-card metadata,
  prompt adapter, diagnostic store and setup cleanup, focused tests.
- Deck agent: NativeDeck* and OnDeviceDeck* editor/import presentation and tests.
- Subsequent maintenance agent: upstream workflow and news data.
- Subsequent independent reviewer: integrated regression and privacy review.

Two implementation subagents maximum; one build process and one simulator.
No agent may change another owner's files without handoff. No fixture result is
native gameplay evidence. Existing engine rules and response UUIDs remain authoritative.

## Acceptance checklist

- [ ] Actionable deck validation; useful reports without native exceptions;
  historical identity; scoped failed-start cleanup; report privacy.
- [ ] Card-backed ability selection with exact duplicate identities and source
  metadata; readable actual stack; ordering distinct from resolution.
- [ ] Centered phase/step announcements for both players, deduplicated across
  priority/polls, replacing stale cues; persistent compact phase label; life delta
  animation; Reduce Motion. User added phase announcements during implementation.
- [ ] Portrait/landscape density, five-card lanes, hand clipping and scrubber,
  drag/inspect separation, artwork/rules inspection, offscreen combat indicators.
- [ ] Authoritative castability, mana rocks/convoke/special payments, undo,
  target/sacrifice/search/pile/mode selection; meaningful phase/action labels.
- [ ] Compact deck editor with art, filters, groups, counts, editing/persistence,
  import preview/errors, basic lands/stats; honest EDHREC integration status.
- [ ] Closed-by-default readable and inspectable logs; coherent menu/news.
- [ ] Weekly upstream detection and candidate PR preparation with review gates.
- [ ] Independent review and affected tests; simulator visuals/interactions.
- [ ] Native artifact and product verification; physical acceptance recorded.
- [ ] Exact build uploaded, processed and assigned to requested TestFlight groups;
  external beta review/availability reported separately.

## Evidence

Baseline: branch codex/native-runtime-hardening, clean HEAD 2a04f4d. Existing
release 2026091504; new source changes require a new verified artifact and number.
No completion boxes imply success until evidence is recorded here.

Phase announcement logic: `swift test --package-path apps/ios --jobs 2 --filter
PortraitInteractionPolicyTests` passed all 8 tests, including both main phases,
upkeep, draw, attacker/blocker declaration, first-strike damage, end/cleanup and
priority-change deduplication. SwiftUI rendering and native execution remain
pending. Cues are transient, non-interactive, follow authoritative engine steps,
and replace stale announcements rather than queueing through fast transitions.

Integrated portable presentation suite: 260 tests, 1 opt-in live-provider test
skipped, 0 failures. This includes the updated ability metadata, diagnostics,
deck editing/imports and phase policy. An initial iOS simulator SDK build passed;
the final compact phase-label correction requires its incremental build. Neither
result constitutes native engine execution or TestFlight delivery.

Continuation: frozen engine commit `fca652a80f643d4a88fe2f8f0ac781be1fd096a4`
published to the existing candidate branch for same-SHA non-simulator gate
35046969413. Core: 419 assertions and 79 failure-boundary assertions passed.
The local runtime-manager fixture passed 45 assertions; this is not XMage execution.
Updated portable suite: 262 tests, 1 optional provider test skipped, 0 failures.
Initial iOS unit run: 465 tests, 1 skipped, 0 failures. Later UI/news/test changes
still require their coordinated final rerun.

The first UI matrix exposed a landscape log-opening failure and a landscape
expanded-hand swipe failure. Neither is waived. Expanded-hand controls now sit
below the cards, with the space-saving overlay retained only while tucked.
Added card-backed ability, mana-action submission and transient phase UI cases.
User additionally required plain-text export pastes from Moxfield and Archidekt;
provider-specific parser regression work is part of release acceptance.

Weekly Codex heartbeat `watch-xmage-updates-for-magicmobile` is active, checking
upstream and requesting review before executing candidate code or releasing.
GitHub's weekly detection remains pending default-branch integration; no claim
that its branch-only schedule is active. The in-app Updates menu separates
installed revision/release notes from upstream GitHub links.

Motion decision: retain native SwiftUI for phase cues, life deltas and gameplay
transitions in this release. Rive supports SwiftUI/UIKit and may suit authored
cosmetic effects later (https://rive.app/docs/runtimes/apple/apple); its CLI is
available (https://www.rive.app/downloads). Adding a second renderer is not needed
to fix these input/layout issues and would add release/performance work. No new
Rive or Three.js dependency was introduced. EDHREC's published terms restrict
automated queries (https://edhrec.com/terms); the authorized website handoff stays
honest, with a user question pending about partner API access.

User-requested deeper Rive CLI review is recorded in `outputs/rive-cli-assessment.md`.
Official CLI authoring, headless verification/capture, RML/state machines, Apple
runtime/version integration, accessibility and performance were investigated.
The live getting-started documentation says published CLI exports currently carry
a watermark while account binding is forthcoming; unsigned output is described
as local use. No paid account, dependency or installer was added. Recommend
native health/phase feedback now, with a bounded cosmetic effect evaluation only
after export rights and actual iPhone performance are established.

Same-SHA non-simulator gate 35046969413 completed successfully. Full native engine
workflow 35048126381 was dispatched on the verified frozen engine SHA fca652a;
its output has not yet been accepted, linked or uploaded.

Provider-paste integration now uses the reviewed parser in the actual import
sheet, preserves annotations through preview, and keeps ordinary Archidekt
categories in the main deck rather than inventing engine zones. Portable suite:
274 tests, one optional live-provider skip, zero failures. Rebuilt SDK unit suite:
477 tests, one skip, zero failures. The first landscape log failure passed a
same-artifact isolated rerun and the subsequent rebuilt matrix; no unproven app
root cause was asserted. Expanded-hand swipe/drag/scrubber checks now pass.

Two import UI failures were confirmed as successful previews with offscreen
confirmation beneath the keyboard/card list. The actual form now dismisses the
keyboard for preview and pins confirmation above the bottom safe area. Provider
paste UI reruns are pending. New ability/phase fixture assertions needed explicit
sheet dismissal and a user-triggered phase transition, respectively; these
fixture-harness changes remain pending execution, not claimed gameplay fixes.
Independent review corrected duplicate ability occurrence identity and historical
diagnostic labeling on multiplayer startup without changing submitted UUIDs.

Final scoped payment review found no additional app-source blocker. Same-SHA
cheap-run logs explicitly record RealQueryTests 16 passed, RealCardChoiceTests
8 passed, and RealPaymentInteractionTests 7 passed. These exercise real JVM
mana-source, convoke, sacrifice-cost and cancellation paths; they do not prove
Swift-to-native physical-phone completion. XMage's characterized cast-offer
affordability limitation remains explicit in tester notes.

Final landscape visual review collapsed editor utilities beneath Deck tools,
leaving cards visible first and exposing an active-filter label when necessary.
Affected layout/land/filter cases require the rebuilt targeted run. The invalid
paste UI assertion was updated to the new line-numbered parser error while
retaining checks for preserved input and no imported cards.

Final local acceptance (2026-09-15 evening): 477 SDK tests executed with one
optional provider skip and zero failures. The 51-case UI matrix initially had
four failures; the targeted rerun passed both orientations of ability choice,
phase announcements and the two added life-change cases, plus invalid import.
All three final deck-tool cases passed after removing an inherited parent
accessibility identifier (the text field existed, but its identifier was masked).
Both Moxfield and Archidekt paste/save paths passed in the actual simulator UI.
The first deck card is now asserted hittable before scrolling in landscape.
Motion screenshot capture was moved ahead of slow accessibility-tree export;
the production cue/pulse duration was not extended for tests. Its visual rerun
is separate from the already-passing functional motion assertions.

Evidence bundles: `commander-polish-verified.xcresult`,
`commander-polish-final-targeted.xcresult`, `commander-deck-tools-final.xcresult`
under `build_output`. Test failures were retained, not reclassified as passes.
Automatic simulator-wide diagnostic gathering on the first completed run was
interrupted after logs/screenshots were retained; all test results were exported.
