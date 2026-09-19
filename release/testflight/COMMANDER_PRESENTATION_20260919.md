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
