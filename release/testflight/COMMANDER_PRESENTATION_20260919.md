# iOS commander presentation refresh

Approved scope: redesign the iOS main menu, Deck Studio and native game setup; remove gold framing; add restrained motion; upload TestFlight using the existing engine. Android follows only after user acceptance.

## Design plan

- Charcoal canvas, ivory text and warm ember actions for the menu and setup. Real commander artwork supplies the fantasy character. No gold ornamental borders.
- Ivory Deck Studio workspace with charcoal typography, consistent controls and more deliberate deck-art hierarchy. Preserve dense editing, search, import, analysis and validation.
- Carry the selected commander between menu and setup with native matched geometry. Keep routine transitions under 300 ms and honor Reduce Motion.
- Present selected player and opponent decks before detailed setup controls. Preserve all existing native lifecycle, setup validation and multiplayer behavior.

## Verification and release

Review portrait and landscape menu, setup and deck editing. Exercise the existing Deck Studio release UI test and native setup checks. Build the signed native product from this checkout and verify engine provenance, archive linkage and Apple validation before upload. Engine compilation is not part of this UI change; unchanged native inputs permit reuse of the verified build-5000000000 artifact.

Simulator UI acceptance does not establish real engine execution. Existing engine evidence can be reused only for unchanged inputs. User acceptance of the new visual treatment remains a TestFlight phone check.

## Verification evidence

- Native Swift protocol/transport suite: 34 tests passed.
- iOS presentation/deck suite: 305 tests executed, one existing skip, no failures.
- Deck Studio core checks passed, including catalogue, role, organization and recording/privacy checks.
- Simulator build and focused UI checks passed on iPhone 17 Pro, iOS 26.5: new draft search/add/inspect/rotate/discard, name validation, AI difficulty persistence, menu/setup/library navigation, and the whole Play button hit area.
- Initial UI runs caught missing full-label hit regions and an obsolete heading assertion. Fixed both; reran affected checks. Final menu navigation evidence: `build_output/presentation-review/CommanderNavigation-final.xcresult`. Deck editing and setup evidence: `build_output/presentation-review/CommanderPresentation-fixed.xcresult` (three passing tests plus the earlier navigation failure, resolved in the final bundle).
- Reviewed portrait/landscape screenshots. Test preferences leave online artwork disabled, so these captures intentionally show consent-aware placeholders, not gameplay or online-art acceptance.
- Engine source remains unchanged from `f2ffad10e26a25885902e963a13810d8786ed9bc`; verified 51 staged artifact hashes before reuse. No engine compilation or Android changes.

Release target: version 0.1.0, build 5000000001. Archive/upload receipts will be retained under `build_output/testflight/menu-redesign-5000000001/`. Apple processing and phone acceptance are separate from these checks.

## Additional approved experience changes

The first archive was interrupted before upload when the user added these requirements:

- Portrait deck cards share one scrolling surface with the header and filters; workspace tabs pin at the top. Landscape keeps its split editor.
- In-game inspection lasts only while held, with release/cancel/background cleanup. Explicit accessibility inspection remains closable without holding.
- A Downloads menu reports bundled assets separately from offline artwork. The user subsequently requested full-catalogue downloads as the recommended choice, plus all-deck/individual-deck choices and Compact/Standard/High quality. Explicit downloads persist outside the evictable cache, capped at 20 GiB with a 1 GiB free-space reserve, consent, missing counts, progress, cancellation and retry. Related tokens use Scryfall UUIDs and disclosed token attributes; ambiguous or unmatched tokens remain placeholders rather than showing a potentially wrong card.

These additions remain iOS-only. Token disclosure already exists in the engine payload; mapping it in the iOS adapter does not require engine compilation.

### Additional verification

- Updated portable suite: 313 tests, one existing skip, no failures (`/tmp/magicmobile-assets-release-tests.log`). Tests cover durable images, corruption/capacity, consent denial, cancellation, token identity and hidden-information redaction.
- `Experience-final.xcresult`: hold lifecycle unit tests, crowded battlefield, large-hand scrolling and portrait pinned tabs passed. Downloads consent interaction failed and was investigated separately; this bundle is not an all-green result.
- `Experience-consent-hold.xcresult`: five-second battlefield hold passed. Reviewed `hold-five-seconds.mov` frame by frame: inspection remains visible throughout the hold and disappears on release; subsequent selection remains functional. This is simulator fixture evidence, not native gameplay.
- Portrait pinned-tabs screenshot shows nine visible card rows after the header and filters scroll away. Existing landscape editing remains a separate validation target.
- Downloads review found no new privacy/cancellation blockers. Permission now has its own Form row. Automated switch input targets the actual thumb rather than the center of the accessibility row.
- The original per-deck Downloads consent/enable/close UI flow passed in `Experience-download-deck-rerun.xcresult`. Full-catalogue UI validation is a separate later check.
- Three later deck editing attempts encountered missed activations at different controls (Decks, Add cards, Add Plains). Exported event coordinates were inside stable visible targets; no source-level cause was established, and test assertions were not weakened. The Mac was locked during earlier attempts. Direct/manual confirmation was requested after unlock; these failures must not be reported as passing tests.

### Full-catalogue artwork design

- The installed engine catalogue contains 31,726 card names. Full downloads use Scryfall bulk metadata and direct image URLs, not a separate named API lookup for every card. The engine catalogue and gameplay rules are unchanged.
- Bounded streaming parsing supports the current compressed JSON Lines feed and older JSON arrays without loading the entire raw catalogue into memory. Full token/emblem and alternate-face manifests allow later offline coverage checks.
- Standard quality is the default; Compact trades inspection clarity for storage, and High downloads larger images. Estimates are approximate and exclude token/alternate-face images and metadata. Higher-quality files satisfy lower-quality checks; upgrades preserve existing images.
- Large runs require this screen to remain open, keep the display awake while active, and cancel on background/dismissal. Relaunching and downloading missing items resumes from completed files. No automatic multi-gigabyte download starts when permission is enabled.
- Live bulk-fixture validation caught art-series records colliding with real transformed cards; the gameplay image index excludes art-series records rather than choosing ambiguous art.
- Final portable suite: 337 tests, one existing skip, zero failures (`/tmp/magicmobile-fullcatalogue-final.log`). This includes parsing the actual 2026-09-19 oracle bulk and an isolated end-to-end front/back/token download, offline rescan, quality-upgrade check and no-network-image retry.
- Direct simulator interaction after unlock opened the deck editor and Add cards search, added Plains (visible quantity 1 / success message), and discarded only the temporary unsaved test draft. This verified those controls independently of the earlier failed XCTest input runs. One initial short synthetic menu tap did not activate; a 150 ms press did. Do not conflate this focused direct check with a fully passing automated deck-editing suite.
- The final-source deck search/add/inspect/rotate/discard test passed in `Full-catalogue-ui.xcresult`; pinned tabs passed in `Full-catalogue-ui-final.xcresult`. Earlier input misses remain recorded above, not erased by these successes.
- The full-catalogue Downloads test needed to scroll to the lazily created asset-check row. Its subsequent run verified consent and the Standard-quality confirmation, but found that the system confirmation popover omitted its Cancel button. Replaced that presentation with an explicit native alert so the large-download decision always offers Download and Cancel.
- `Downloads-confirmation-final.xcresult`: final Downloads UI test passed, including asset coverage, scope/quality controls, consent gating, no automatic bulk transfer, full-catalogue confirmation and Cancel/Done dismissal. No multi-gigabyte network download was performed during UI testing; transfer/resume behavior is covered by isolated fixtures, with a real bulk-index parsing check reported separately above.

### Readability follow-up

- Before upload, the user requested less explanatory text in Downloads and Settings. Stopped the release during export, before Apple upload; the earlier archive remains preserved in `native-release.8xDnOA`.
- Downloads now groups choices, compact local coverage and the download action. Technical details and bundled-asset information start collapsed under More info. The essential Scryfall/card-name/IP consent remains visible; the large-transfer warning stays in the explicit confirmation. Removed duplicate idle progress prose.
- Native Settings drops the redundant headline and shortens orientation/artwork explanations. No consent, storage, download or engine behavior changed.
- `Downloads-simplified.xcresult` compiled successfully but missed the menu tap before entering Downloads; this attempt does not validate the changed screen.
- `Downloads-simplified-rerun.xcresult` passed the complete consent/confirmation/cancel flow and verified technical details start collapsed. Reviewed its screenshot: compact counts and short consent replace the previous paragraphs. The missing-card/token lists were then also collapsed by default; that final presentation-only adjustment is compiled in the release archive.
