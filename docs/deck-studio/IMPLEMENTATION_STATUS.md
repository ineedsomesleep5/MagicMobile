# Deck Studio 2.0 — source implementation and release boundary

Latest desktop delivery: **0.1.0 (2026091701)** uploaded to internal TestFlight on September 17 UTC. See [the exact source, artifact and verification receipt](RELEASE_2026091701.md). Apple availability and the remaining physical acceptance checklist are distinct from upload success.

Continue **PR #10**, branch `codex/deck-studio-2`, targeting `main`. Do not create another Deck Studio PR, reset to an old checkpoint, overwrite newer desktop work, or reinstall an earlier ZIP. The main baseline is merged PR #9 at `1f7bd7213875f181d35bac5d88b97b2cb2f76634`.

This pass resumes the implemented validation, Scryfall and recording work at `72d6c5a38e4b47a66cd33f85daa2d7a47cacd6b5`. Source commit `2598c7dc7a6896527c5e2ad1426acf41c6d0af83` adds the deck-detail/import linkage and recording/editor hardening described below. Consult the PR's current head and check runs for final evidence, rather than the older descriptions in the conversation.

## Implemented product paths

| Approved area | Implemented behavior | Acceptance still requiring a real app/device |
| --- | --- | --- |
| Clean Modern library | Cream/charcoal palette, artwork tiles, grid/list preference, search, favorites, filters, sorting, create, duplicate, delete, JSON export | Actual appearance, small-phone layout, large text, scrolling/performance |
| Native card editor | Cards / Ideas / Curve / Stats, local name/rules search, typed sections/color filters, type/color/numeric-mana grouping, quantity edits, card inspection, card/commander replacement, basic-land tool, undo/redo, draft recovery | Gesture/keyboard usability, save/reopen/recovery on a phone |
| Local organization | Saved deck tags, searchable in My Decks; private building notes; revision-checked storage; separate undo/redo; deliberate export; duplicate/delete integration | Sharing UI, simultaneous-window interaction and storage failure presentation |
| Import | Paste, file, public supported provider links, Apple Vision image text recognition, parsed/resolved review, unknown names preserved, explicit XMage validation | Real provider access, actual photos/OCR, photo permissions and import completion |
| Original import information | Full original receipt linked to the saved deck; annotations visible under the tag/details button; full receipt export; large annotations remain in the complete receipt rather than being silently truncated | Export/open full receipt after quitting/relaunching and after duplication |
| MagicMobile Insights | Counts, curve, printed pips, probabilities, explained functional roles from curated Scryfall oracle tags baked into the catalogue at build time, conservative text-pattern fallback, user-reviewed roles and personal target ranges | Readability and accuracy on representative real decks; curated tags are community-maintained, so no exhaustive classification claim |
| Commander Spellbook | Explicitly approved deck lookup, all response groups, prerequisites/results, carefully gated missing-piece additions, bounded cache/HTTP, manual pagination | Live lookup, server schema/access, offline/cancellation behavior on phone |
| Scryfall | Optional exact-name reference and explicit online search, dated cache, provider attribution, shared request pacing with artwork, no remote replacement of engine identity | Live service access, dual-faced references, unsupported-engine result UX |
| Inline EDHREC | User-driven commander buttons resolve Scryfall's public related link; normal browsing fallback, real embedded website, back/forward/reload/Safari, retained workspace session, clear session | Correct destination, return-to-scroll, memory pressure and external navigation behavior |
| XMage validation | Standalone real engine operation, source/build-specific validation receipt, original error detail, validation UI in editor/import, playable copy for explicitly excluded boards, engine-ownership/cleanup safeguards | Fresh compiled native library; repeated validate → play → close cycles on phone |
| Recorded playtests | Opt-in new local one-human-versus-AI sessions, canonical playing-deck identity, duration, highest observed turn, own native commander cast counters, explicit outcome when supplied, up to 100 local summaries, export/clear | Play/relaunch/end/leave/disable/clear on real phone; no simulated results count as acceptance |

All remote features are optional. EDHREC is a website view, not an EDHREC API integration: no DOM scraping, injected extraction scripts, automated form filling or background deck submission. Partner-pair buttons open individual pages; EDHREC's own pairing controls handle combined browsing.

## Repairs in this continuation

### Desktop editor finishing pass — September 17

- Compact card rows put artwork, readable names, mana symbols, quantities and a visible options menu together. Narrow widths and accessibility text fall back to stacked controls with 44-point targets.
- Editable workspaces at least 700 points wide show catalogue search beside the deck. Short landscape windows use a compact deck summary; portrait keeps the Add cards sheet. Read-only included decks still require an editable copy.
- Local and Scryfall search show live draft/destination counts and allow removing a copy without leaving search. Local search gives advisory singleton reminders, respecting basic lands and explicit copy-limit rules; XMage still decides legality.
- Cards / Ideas / Analysis / Playtest have distinct responsibilities. Curve, probabilities and local role analysis live together; recorded games and validation live under Playtest. Explanatory recording details are collapsed rather than filling the screen.
- Library tiles expose an options menu without requiring long press. Library and editor can share standard-board plain text, including partners, companions and optional boards. Export round-trips through the production importer before sharing; empty drafts, custom boards and names that cannot survive text normalization explicitly retain JSON export instead.
- Inspection uses the existing rules-markup normalizer and mana-symbol renderer. Validation failures give player-facing recovery instructions without hiding the retained engine diagnostics.

Verification for this pass: the portable app suite passed 296 tests (one existing skip); native transport/protocol suites passed 34 tests; Deck Studio scripts passed 4,478 core, 93 Spellbook, 70 role, 45 recording/receipt, 40 Scryfall, 26 recording-integrity and 26 organization assertions. Generic-device app/test compilation passed. The added app-model search/undo regression is compiled, not executed on a phone. Scryfall's live Scarab God reference resolved to EDHREC's commander page (HTTP 200); that is endpoint evidence, not embedded-browser or phone visual acceptance.

Release candidate preparation: build `2026091701`. A successful full engine already exists at source `3f6405a08610790b1d09d15f446f31c0e9cb8579`, run `35162245370`; reuse is permitted only after the existing source-equivalence, archive digest and paired-header guards pass. Upload and Apple processing evidence must be recorded separately below when completed.

- The recorder expected uppercase terminal phases, but `MatchMailbox` emits lowercase `failed` and `closed`. Corrected the production parser and the existing unrealistic uppercase fixture; added real-protocol-shape regression cases. A failed or interrupted game is not a loss.
- Wrong nested viewer identity cannot advance the recorded revision and block a later valid update. Unknown phases, negative revisions, malformed/nonfinite dates and unrelated commander names cannot poison persisted summaries. Terminal results remain immutable.
- Playtest summaries and optional private deck details are excluded from system backup and use iOS file protection. Recording does not persist hand snapshots or opponent deck contents.
- Explicit discard can exit an invalid/blank-name draft even when recovery is unreadable. It restores the saved baseline without overwriting the saved record or deleting corrupt/unrelated recovery data. Quantity overflow is rejected transactionally.
- Import completion links its already-written receipt to the actual saved record. A failed optional-details write gives an explicit partial-success error and Finish retries the same record rather than silently duplicating it.
- Import details use a separate bounded sidecar so large original receipts do not turn ordinary tags/search into huge documents. Tags/notes never enter XMage or remote recommendation payloads. Old imports lacking a linked receipt are not retroactively reconstructed.
- Validation exclusion acknowledgment resets when the draft changes; it is not permanent permission to omit later board edits.

## Deliberately not claimed

Phase 8 is a **recording foundation**, not the complete future analytics wishlist. The current poll-level signals do not reliably expose every draw, mulligan, mana payment, land play or exact first-cast turn. Therefore the app does **not** fabricate those metrics, stranded-card diagnoses, perfect mana-source recommendations, matchup win rates or AI batch simulation results. Adding richer event telemetry later requires explicit authoritative event instrumentation, privacy tests, real-game tests and a new native build. Role hints now come first from Scryfall's community-curated oracle tags, bundled at build time and resolved offline; cards those tags miss fall back to conservative text patterns that still leave triggered and conditional effects unclassified. Curated coverage is measured against a hand-labelled staple set by `scripts/deck-studio/check-role-accuracy.py`, which is a floor and not exhaustive card evaluation. An available named combo is still not proof of executable game state.

No cloud accounts/sync, collection/price tracking, EDHREC partner feed, full tournament-format editor, drag-based custom groups or social collaboration was added. These were outside the first scoped product or explicitly later work in the approved plan.

## Catalogue data added this pass

- **Color identity** is exported from the pinned XMage card implementation by `CardMetadataExporter.java`.
  This supersedes the front-face heuristic: transform, modal double-faced and split cards include their
  other faces. The iOS exporter validates and preserves the engine's identity, separately from printed color.
- **Curated role tags** are fetched by `packages/ondevice-engine/scripts/fetch_role_tags.py` from Scryfall's
  public oracle-tag search, intersected with the shipped catalogue, and stored per card. A reviewed snapshot
  is committed in `engine/data/role-tags.json`; normal builds do not fetch live tags. The phone resolves roles
  entirely offline. Scryfall tag data is CC-BY and is credited in the analysis
  panel. Re-running the fetch changes `ROLE_TAGS_SHA256`, which must be repinned in the exporter alongside the
  other source SHAs.

## Verification commands and scope

Use the existing non-simulator pipeline. Do not remove tests or substitute fixtures for release gameplay.

```sh
bash scripts/deck-studio/test-core.sh
swift test --package-path packages/ondevice-engine/swift
swift test --package-path apps/ios --jobs 2
```

The core script retains all earlier suites and now calls `test-finishing.sh`. New local checks passed against the production Foundation code: **26 recording-integrity assertions**, **26 organization/storage assertions**, and the **45 existing recording/storage/validation-receipt assertions** after correcting the fixture phase. The first recording regression was run against the original production source and failed at the lowercase terminal-state assertion before the fix. Changed SwiftUI files were syntax-parsed locally; that is not Apple SDK typechecking or visual execution. Three editor XCTest regressions were added to the existing app test file; they require the Apple app test target to execute.

The inherited checkpoint `72d6c5a` passed CI `35165012426` and on-device gates `35165012424`. Those are historical baseline results, not evidence for this new source. Record final hosted check results in PR #10 after the new revision runs. The existing workflow tests the real XMage JVM, boundary/tooling/ownership behavior, portable Swift and fixture contracts, and compiles the actual iOS app/test targets for the generic device SDK without signing or a simulator. It does not run the iPhone UI or prove the newly linked full native Release product.

## Desktop Codex release handoff

1. Fetch PR #10 and verify the current branch/head and worktree. Preserve uncommitted and newer work. Do not merge or publish a release just because this document exists.
2. Review changed source and all latest PR check logs. Re-run affected checks if anything changed. Complete native app-target tests on the available Apple environment while honoring the user's no-simulator route; unexecuted tests remain explicit.
3. **Build a fresh real ARM64 engine including this PR's standalone `validateDeck` Java changes.** An older successful engine archive is not automatically equivalent, even if this last finishing commit changed only Swift. Preserve exact source/registry/compiler-patch provenance and paired headers/static dependencies. Never bypass the product workflow's source-equivalence guards.
4. Link the actual `apps/ios` Release product against that exact successful candidate, verify architecture/symbols/entrypoint/resources and archive/export layout. Keep the process-wide native ownership and cleanup tests. `apps/ios-ondevice` is a harness, not the released application.
5. Only with the user's explicit release authorization, use the existing app identity `com.calebfeliciano.magicmobile` and existing App Store Connect app, obtain an unused build number, sign and upload an internal TestFlight candidate. Check Apple's processing/tester state; do not report availability from the upload command alone.
6. Record the final source SHA, native candidate/run/hash, Release/link/export evidence, exact TestFlight build and remaining device checks. No public release, paid infrastructure, engine rewrite or card pruning.

## Physical acceptance checklist — still unverified by this chat

- Library: existing local/precon decks, grid/list after relaunch, tags/search, favorites, duplication/deletion and Details exports.
- Editor: 100+ cards, partners, unresolved rows, replacement, quantities, basics, undo/redo, saved/recovery/discard behavior; portrait/landscape and accessibility text sizes.
- Import: text/provider/file/image → review → validation → save; annotated receipt remains accessible after relaunch; retrying a failed details link does not duplicate the deck.
- Validation/play: valid and invalid decks produce real exact results; mutation invalidates receipts; exclusion consent resets; cancel/background/cleanup/retry does not compete with a running game; repeatedly validate, start, leave and start another actual game.
- Network tools: explicit consent, offline/cache/error/429 states, live Spellbook and Scryfall, supported/unsupported card mapping, EDHREC commander destination and preserved tab scroll. No background deck transmission.
- Recording: enable, start a new local AI game, observe commander casts/turns, leave versus complete versus engine failure, relaunch history, disable and clear while playing. No hand contents/opponent data in exported summaries.
- Existing gameplay: opening/mulligan, casting/payment/targeting/combat, AI responsiveness, memory/thermal behavior, background/resume; Game Center remains separately tested on multiple real phones.

Keep the PR draft until its source review and release/device acceptance boundaries are explicitly resolved. Passing CI alone never certifies perfect gameplay or readiness for public distribution.
