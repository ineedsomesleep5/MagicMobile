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
