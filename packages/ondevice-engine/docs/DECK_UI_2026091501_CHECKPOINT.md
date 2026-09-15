# Deck builder and board polish — candidate checkpoint

Selected checkout: `/Users/calebfeliciano/Documents/MagicMobile-runtime-hardening`,
branch `codex/native-runtime-hardening`, stacked PR #9. Starting HEAD:
`30749724f369812555ddba242d79fc97373b1b03`. The approved UI-thread changes were
already uncommitted in this checkout and are being preserved/integrated.

## Delivery boundary

### ManaBox-inspired follow-up (September 14, 22:04 local)

The user added ManaBox deck-building references after publication of
`80d2927ca14ffd7fa8a27384506b9796ec782884`. Native compilation and installation
are held while the new deck-library/editor work is implemented and checked.
The scope is Commander deck building, not collection/scanning, card purchases,
speculative bracket ratings or unsupported future card sets.

Acceptance: visual deck covers; readable grouped card rows and inspection;
quantity/section editing that preserves commander roles and durable saves;
truthful pinned-metadata search and statistics; deliberate basic-land controls;
and an explicitly supported recommendations route. Search results must stay
within the compiled catalogue. Unknown metadata must not appear as zero or as
proof of legality. The existing real-engine play routing must remain intact.

Baseline `80d2927` completed the actual simulator app suite: 370 unit cases
(one opt-in live import skipped) and all nine UI journeys passed. Result:
`build_output/deck-ui-complete-candidate.xcresult`; log:
`/tmp/magicmobile-deck-ui-complete-candidate.log`. CI 34922961049 and on-device
gates 34922961126 succeeded; non-simulator 34922958699 also succeeded, with
compiler-source-inspection, source-provenance, apple-source-and-sdk,
portable-contracts and real-jvm jobs completed successfully. This evidence
predates the ManaBox follow-up and is not its clearance.

Follow-up local checks so far: 198 portable presentation tests, one opt-in live
import skipped, zero failures (`/tmp/magicmobile-manabox-presentation.log`);
exporter seven self-tests and exact bundled-byte check passed. Basic-land edits
have regression coverage for protected sections, stable IDs, zero/removal and
atomic limit rejection. UI source and independent-review repairs are still in
progress; no native build or install was dispatched for this follow-up.

EDHREC research: [ManaBox documents its integration](https://www.manabox.app/guides/decks/faq/)
and [EDHREC Recs](https://edhrec.com/recs) provides a user-facing form with
commander/partner and deck-list inputs. No official public API contract was
verified. [EDHREC terms](https://edhrec.com/terms) restrict automated requests.
Do not use undocumented endpoints or present local heuristics as EDHREC results.
The user has been asked whether a labeled website/manual-copy flow is acceptable
pending approved embedded integration. No user deck was sent to EDHREC.

Implemented follow-up surfaces: art-cover library, grouped card rows, direct
quantity controls, Cards/Stats/Info detail pages, local rules/type/mana inspection,
name/rules search with type and exact printed-color filters, main-deck mana curve,
type totals, printed-symbol occurrences and deliberate basic-land counts.
Metadata and the play resolver are loaded off-main and passed to child views.
Artwork remains opt-in; offline inspection shows card text without a large blank
image. Long deck titles are bounded visually, not truncated in saved data.

This is not complete ManaBox parity. Color identity is unavailable in the pinned
CardInfo export and remains unknown (not inferred from printed color). Set codes
exist in the model but there is no full set-browser UI. There is no production
mana estimate, automatic mana-base balancing, bracket score, market pricing,
collection/scanner feature or embedded EDHREC integration. These are not silently
represented by fake data or disabled decorative controls.

The full follow-up simulator run `build_output/manabox-complete.xcresult` passed
383 app unit tests (one opt-in live test skipped), but **failed** one of ten UI
tests during cleanup. The import/inspect/rename/save/reopen assertions passed;
cleanup swiped immediately after opening the library without waiting for the
destination/search field. Cleanup now waits for both visible controls and retains
diagnostics on failure. The original failed result remains retained.

Final focused rerun `build_output/manabox-final-focused.xcresult` passed 23 app
unit tests and four UI journeys: land tools/stats/inspection, catalogue quantity
editing, included-deck copy protection, and the original import/rename/relaunch
flow including cleanup. Log: `/tmp/magicmobile-manabox-final-focused.log`.
Screenshot review then found overflowing offline thumbnail placeholders; compact,
clipped placeholders fixed it. `build_output/manabox-thumbnail.xcresult` passed
four presentation tests plus the included-deck copy journey after that fix.
The corrected screenshot is
`build_output/manabox-thumbnail-screenshots/F60BC6C2-B674-4400-8E90-FC766EDD27E0.png`.
Offline inspector and stats captures are in `build_output/manabox-final-screenshots`.
These screenshots intentionally keep artwork downloads off; they verify offline
layout, not live artwork retrieval or native gameplay.

Final portable presentation suite passed 201 tests with one opt-in live import
skipped (`/tmp/magicmobile-manabox-final-presentation.log`). The seven exporter
self-tests and exact byte check passed (`/tmp/magicmobile-manabox-exporter.log`).
No single post-fix full simulator suite is claimed: the failed broad run and
successful affected reruns are recorded separately. The ManaBox follow-up has
not been published, natively compiled, signed, installed or uploaded. Resolve the
EDHREC route and Moxfield fallback choice before freezing a release candidate;
then publish it and run same-source hosted/native/product/device gates.

The user changed delivery from internal TestFlight to **direct installation on
Caleb's iPhone over Wi-Fi**. Do not upload this candidate to App Store Connect.
Build `0.1.0 (2026091501)` was prepared before that change; both ASC build and
upload queries returned no matching record. A prepared number is not an upload.
The phone was listed as paired/available, but its detailed connection request
did not complete. Recheck connection before installing; do not substitute another
phone or TestFlight. Preserve bundle `com.calebfeliciano.magicmobile`.

## Implemented scope under review

- Shared portrait/landscape menu and board polish from the approved UI thread.
- Measured landscape combat anchors, clipped hand viewport with a separate active
  drag overlay, enlarged inspection and centered choices, purple castable glow.
- Native local deck library, included-deck copies, catalogue search, card/list
  views, quantity/section editing, durable revision-checked save/delete, selection
  into the existing real-engine setup route.
- Public Archidekt/Moxfield link import, bounded pasted/file imports and lossless
  JSON draft exchange. Moxfield's endpoint returned HTTP 403 on this host; its
  decoder tests do not prove live availability. Paste export is the fallback.
- Optional, default-off Scryfall artwork with disclosure of card-name/IP sharing,
  local cache, bounded downloads, throttling and allowlisted redirects. The native
  board and deck views share that route; Settings and Decks expose the same consent.
  Native card rendering does not fetch the legacy gateway fallback. Hidden and
  face-down card artwork is not requested. Artwork does not provide rules.
- Real XMage public INFO/STATUS forwarding; private messages remain seat-private.
  This production Java change requires a **new full native engine artifact**.

Saved drafts are not Commander-legality certificates. Exact names/sections are
resolved before match creation and XMage remains the legality/rules authority.
The editor preserves primary commander identity and unsupported sections rather
than silently converting or removing them. Unsupported sections block play.

## Evidence so far (not final clearance)

- Initial actual iOS simulator app build passed (before final artwork/review fixes).
- Portable presentation package: 191 XCTest tests passed, including a live public
  Archidekt URLSession import of deck 669560 (100 main/commander cards after the
  explicit excluded-board option). This is import evidence, not native legality.
- Exact double-faced aliases are derived from pinned XMage printing metadata;
  exporter self-tests (6) and bundled-byte `--check` passed. Maintenance's
  reviewed generated receipt now includes metadata (27 fixture tests passed).
- Actual artwork loader fetched and decoded Sol Ring (488x680, 71,336 bytes)
  from Scryfall, then returned identical bytes with networking disabled.
- Swift protocol package passed: 21 XCTest cases plus 33 Swift Testing cases.
- Full pinned JVM adapter compilation passed: 32,275 card factories, 587 set
  references, 15 explicit exclusions. Core 419 assertions and injected
  failure-boundary 72 assertions passed during that build.
- Focused real-XMage `RealControlPrivacyTests`: 10 cases passed, including the
  new public log fan-out, personal-message isolation, unchanged pending prompts,
  bounded history and post-close silence checks.
- Actual-app simulator unit suite: 367 cases, one opt-in live import skipped,
  zero failures. The nine UI journeys are still under verification; this is
  not a claim that the complete UI suite passed.
- Focused final checks passed: 14 artwork/layout tests; visible text selection
  and empty-draft save/relaunch; catalogue search/add/quantity/save/relaunch;
  paste/import/inspect/rename/relaunch; precon copy preservation; and Play-label
  hit routing. Earlier failures and screenshots identified caret-dependent test
  input, ignored simulator keyboard shortcuts, and a missing label hit shape.
  The test now uses the observed iPhone Select All menu item and asserts exact
  text before saving. No failed journey is counted as a successful full suite.
- Full real-JVM suite passed. Native C ASan/UBSan ownership, Swift close and
  runtime-manager (27) fixture checks passed; these do not execute native XMage.
- Core/tooling run passed 228 Python tests plus the existing core/failure suites.
  Build-number regressions passed six tests, including avoiding reuse of a
  directly installed build number. Installation must record `lastInstalledBuild`
  only after the actual install succeeds; no upload receipt is fabricated.
- Final hosted cheap gates, new ARM64 native build,
  unsigned product gate, signed direct-install artifact and phone installation
  remain pending. No native/gameplay acceptance is inferred from simulator fixtures.

Local logs are under `/tmp/magicmobile-deck-*.log`; simulator build/test output is
in `build_output/deck-ui-preview` and `build_output/deck-ui-tests-2026091501.xcresult`.
These paths identify local work, not retained hosted evidence or distributed builds.

Final source review covered the new library/edit/import/selection paths and
native artwork routing. Follow-up source fixes preserve precon source URLs and
keep artwork consent consistent between decks and gameplay. The reviewed
candidate may be published for hosted verification while final UI checks run;
native compilation and installation remain gated on their actual conclusions.

## Final acceptance still required

Run the actual-app deck import/edit/copy/relaunch/setup tests and inspect rendered
portrait/landscape behavior. Fix failures, review the final diff, then publish the
exact candidate. Require completed same-SHA non-simulator gates before dispatching
`magicmobile-far-calls.yml` with that SHA and successful cheap run. Verify all new
artifact receipts/provenance, run `magicmobile-product-device.yml`, stage matching
native inputs, generate `native-engine.yml`, and validate a signed device product
before direct installation. Never install the unlinked simulator/UI preview.

Phone acceptance remains manual: Token Triumph against one Grave Danger MAD,
human starting player, mulligan/keep, mana/commander/AI/combat/tokens, public log,
background/resume and exit/new game; also verify saved/imported decks and the new
card/stack/zone inspection. Multi-device Game Center acceptance is separate.
