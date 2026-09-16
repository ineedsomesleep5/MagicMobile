# Plain-text deck paste parser

Implemented in `apps/ios/MagicMobile/OnDeviceDeckEditing.swift` with eight focused parser regression tests in `apps/ios/MagicMobileTests/OnDeviceDeckEditingTests.swift`. No engine or UI implementation files changed. Separately authorized: the UI test quantity helper is scoped to `nativeDeck.editor.rows`, retaining strict matching and the lead's historical-control change.

## Integration by the importer owner

Integration has landed: `OnDeviceDeckEditing.importText(text, name: name)` returns `TextImport` containing `deck` and line-numbered `annotations`; the importer routes the deck through local-name preview and carries those annotations to review. Printing/foil/labels/tags are represented as review metadata rather than gameplay fields. This parser does not resolve or reject unknown card identities.

The lead has now routed `OnDeviceDeckLinkImporter.preview(text:name:)` through this parser and retained its annotations. The integrated provider fixture test passes, including main-deck Land category and sideboard preservation. Lead reports review annotations wired into the UI without double-preview loss; UI provider-paste execution remains a separate pending gate.

UI status: the active matrix's partner-import confirmation failure is undiagnosed. No app/parser root cause is established; screenshot/log review after completion is needed. The lead added actual Archidekt text to the existing PasteValid test and a MoxfieldPlainText test, but the currently running binary predates those changes. Portable passing evidence is not UI acceptance.

Read-only edge review: marked grouping headings preserve the previous explicit zone, so `Commander / 1 Leader / // Creatures / 1 Creature` needs a `Deck` header to avoid treating the creature as a commander. Also, a terminal single-token parenthesized name component (for example an unresolved name ending `(Alpha)`) matches the printing suffix grammar; it is retained as an annotation but removed from the identity passed to name resolution. These are compatibility risks, not established causes of the partner-confirm failure. No parser changes made during this review.

## Exact supported grammar

- Quantity plus whitespace plus name: `1 Sol Ring` or `1x Sol Ring` (uppercase X also accepted).
- Explicit headings: Deck/Main/Mainboard, Commander/Commanders, Companion/Companions, Sideboard, Maybeboard/Considering. Case-insensitive; optional `//`, `#`, or trailing colon.
- Grouping headings require `//`, `#`, or a trailing colon. They retain the current zone (main deck by default) and receive a line-numbered review annotation. For example, `// Creatures` does not create an engine zone. Use `Deck` to return from an explicit Commander/Sideboard/etc header to the main deck. Unmarked unknown headings produce a line-specific error.
- Optional suffixes in this order: `(SET)` with optional alphanumeric/★/†/hyphen collector token, `*F*` or `*E*`, one `[Category]`, one `^Label,#RRGGBB^`, then Moxfield `#!tag text`.
- `[Commander{top}]` maps that row to commanders without changing the following rows' zone. Ordinary bracket categories (Ramp/Creature/Land/custom names) retain the current zone and a review annotation. Conflicting recognized section/category roles fail. Unsupported flags such as `{noDeck}` fail explicitly rather than risking including excluded cards.
- Multiple separate bracket groups, malformed bracket/label suffixes and unsupported premier categories fail, rather than dropping information. CSV, arbitrary prose, implicit blank-line sideboards and arbitrary provider format variants are not supported.
- BOM, CRLF and CR inputs are supported; errors count source lines including blank lines. Quantities and aggregate card count are limited to 2,000; input is limited to 2 MiB.
- Punctuation in ordinary names is preserved, including commas, apostrophes, quoted names, Unicode, split-card `//`, and parentheses containing words/spaces.

Examples covered by tests (constructed fixtures following the documented syntax):

```text
Commander
1 Tymna the Weaver
1x Thrasios, Triton Hero
Companion:
1 Zirda, the Dawnwaker
Deck
1 Sol Ring (CMM) 396 #!Mana Ramp
1 Arcane Signet (CMM) 384 *F*
Sideboard
1 Forest
Maybeboard
1 Unknown New Card
```

```text
1x Emmara, Soul of the Accord (grn) *F* [Commander{top}] ^Owned,#000000^
1x Sol Ring (clb) [Ramp]
2x Swamp (ltr) 267 [Land]
1x Unknown Future Card [Maybeboard]
```

Ordinary categories such as Ramp/Land remain grouping metadata, not engine sections; normal main-deck exports do not require zone repair. Annotations must still be presented for review, since text cannot establish every provider's custom category settings. Card quantities are never duplicated across categories. The first commander becomes `deck.commander`; partners remain commander entries.

## Provider-hosted research

- Official Archidekt FAQ distinguishes custom card categories and grouping/display settings: https://archidekt.com/faq . Preserving the current zone for ordinary groups is this parser's explicit compatibility policy, not a claim that arbitrary custom category flags are understood.
- Archidekt export syntax and maintainer response: https://archidekt.com/forum/thread/6024990/1
- Archidekt Commander top marker: https://archidekt.com/forum/thread/2532072
- Archidekt moderator's import syntax example: https://archidekt.com/forum/thread/3137701?page=3
- Archidekt collector-number export example: https://archidekt.com/forum/thread/8280120
- Moxfield's own feedback site, user-reported bulk export examples with set/number and tags: https://moxfield.nolt.io/2407

These are provider-hosted discussions, not a formal versioned export specification. Moxfield's help page returned only a JavaScript-loading shell in the research tool. The exact accepted grammar above is the compatibility claim; no claim of every export option or live-provider acceptance is made. `*E*` is an explicitly supported parser extension, not a format verified from these examples.

## Tests queued for lead

Latest integrated portable run: 2026-09-15 21:27:04 local, `swift test --package-path apps/ios --jobs 2 --filter 'OnDeviceDeckEditingTests|OnDeviceDeckLinkImporterTests'` with the Xcode developer directory selected. 37 tests, one live-provider test skipped, zero failures (23 editing and 14 importer tests). Includes all eight parser regressions below and `testProviderTextExportPreviewPreservesQuantitiesRolesAndAnnotations`. SwiftUI/UI execution is not covered by this portable run; the quantity-helper and provider-paste UI reruns remain pending.

- `testExactProviderHostedCopiedSyntax` uses verbatim Archidekt moderator and Moxfield feedback examples, independently of the constructed fixtures below.
- `testArchidektGroupingsPreserveMainDeckAndExplicitZones`
- `testTextExportHeadersKeepCommanderPartnerCompanionAndBoards`
- `testMoxfieldPrintingFoilAndBulkTagsRetainNamesAndAnnotations`
- `testArchidektCategoryPrintingLabelAndCommanderTop`
- `testTextImportPreservesPunctuationAndUnknownCustomSections`
- `testTextImportBOMCRLFAndExactErrorLineNumbers`
- `testTextImportRejectsConflictingRolesAndLimitsWithoutDroppingRows`

Portable command (authorized by lead): `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path apps/ios --jobs 2 --filter OnDeviceDeckEditingTests`. Importer/UI integration coverage remains separate; no xcodebuild was run for this task.
