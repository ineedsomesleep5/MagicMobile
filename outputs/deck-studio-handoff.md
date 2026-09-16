# Deck Studio implementation handoff

Checkout: `/Users/calebfeliciano/Documents/MagicMobile-runtime-hardening`
Branch: `codex/native-runtime-hardening`

## Behavior

- Deck opens by default. Collection search is a large portrait drawer; widths at least 650 points keep collection and deck alongside each other. Deck column receives 48% of width, at least 320 points.
- Compact collection and deck rows include optional existing artwork, names, mana costs and quantities. Quantity controls retain 44-point targets. Long mana costs fall back to wrapping text. Existing theme and artwork consent/cache behavior are reused.
- Search filters live in scrolling content. Keyboard focus collapses excess deck header controls; search supports submit-to-dismiss and interactive keyboard dismissal.
- Draft recovery is local and separate from the saved library, keyed by record ID and revision (or the new-deck slot). Incomplete deck names and row identities survive recovery. Cancel offers keep or discard. Successful Save clears recovery. Undo retains the latest 50 in-session changes, including name, quantity, section and bulk-land edits.
- Deck filters cover name/rules, printed color and type; sorting covers name, mana value and quantity; grouping covers type, section and no grouping. Statistics use existing quantity-weighted local metadata.
- Basic-land preview tops up to 37 main-deck lands using printed WUBRG pip proportions. It excludes other sections, refuses incomplete type/cost metadata, does not infer fixing or commander identity, and requires an explicit Add action. Existing lands are never removed.
- Paste, JSON, Moxfield and Archidekt imports now preview quantities, sections and unresolved names before saving. Unknown names can be explicitly retained as draft cards; strict import and native play resolution remain unchanged. Invalid quantities, provider identity/privacy mismatches, unsupported sections, redirect and response-size checks remain enforced.

## Changed source paths

All relative to the checkout:

- `apps/ios/MagicMobile/NativeDeckLibraryView.swift`
- `apps/ios/MagicMobile/NativeDeckBuilderComponents.swift`
- `apps/ios/MagicMobile/NativeDeckComponents.swift`
- `apps/ios/MagicMobile/NativeDeckMetadataCatalogue.swift`
- `apps/ios/MagicMobile/OnDeviceDeckEditing.swift`
- `apps/ios/MagicMobile/OnDeviceDeckLinkImporter.swift`

Focused tests changed:

- `apps/ios/MagicMobileTests/NativeDeckBuilderLayoutTests.swift`
- `apps/ios/MagicMobileTests/NativeDeckMetadataCatalogueTests.swift`
- `apps/ios/MagicMobileTests/OnDeviceDeckEditingTests.swift`
- `apps/ios/MagicMobileTests/OnDeviceDeckLinkImporterTests.swift`

Other workers changed files outside this ownership scope during implementation; this worker did not edit ContentView, Models, OnDeviceRootView, project files or engine protocol.

## Evidence and lead validation

Executed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/ios --jobs 2 --filter 'OnDeviceDeckEditingTests|OnDeviceDeckLinkImporterTests|NativeDeckMetadataCatalogueTests|NativeDeckEDHRECTests|NativeDeckArtworkTests'
```

Result: 48 tests executed, 1 skipped, 0 failures. The skipped test is the explicitly opt-in live Archidekt URL test; no claim of current provider availability is made. New tests cover recovery isolation/corruption, both provider previews versus strict import, pasted unresolved names and malformed inputs, and quantity-weighted land preview with section exclusions.

Swift frontend parsing passed for the three changed SwiftUI files. `git diff --check` passed. The portable package excludes the SwiftUI editor and layout tests: parsing is not SwiftUI type checking or rendering evidence.

For the lead's coordinated iOS validation, run `NativeDeckBuilderLayoutTests`, `NativeDeckPresentationTests`, and `OnDeviceDeckPersistenceTests`, then check portrait deck default/search drawer, nested inspection, landscape split with keyboard, long names/mana costs and large text, undo after remove/move/bulk lands, force-close/reopen recovery, and import review/save with unresolved names. No simulator was booted and no full iOS build, release or push was performed by this worker.

## EDHREC external dependency

The existing clearly labeled website handoff is also available from the editor. No live recommendation scraper was added. Official research did not establish a supported public API contract; published terms restrict automated requests. A reliable live-card integration needs an authorized, documented EDHREC route and agreed response contract.

- Terms: https://edhrec.com/terms
- FAQ: https://edhrec.com/faq
- Publisher contact: https://edhrec.com/contact-us

The user may copy main-deck text and open the website manually; no deck data is embedded in the URL or automatically sent to EDHREC.
