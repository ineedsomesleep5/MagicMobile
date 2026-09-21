# iOS 0.1.1 build 8

## Scope

- iOS-only release. Android work and releases are paused at Caleb's request;
  its existing APK, version code and public links are unchanged.
- Repair offline token artwork identity, equivalent printings, Treasure wording,
  double-sided token faces and immediate battlefield refresh after local storage.
- Download missing/corrupt/insufficient-quality images without replacing valid
  existing artwork. Show additional-download estimates and honest discovery/errors.
- Resolve pinned XMage ASCII/ellipsis spellings against public artwork names.
  In name collisions, ordinary cards take precedence over explicit playtest,
  memorabilia and planar names. Equal-priority identities remain ambiguous.
- Opponent-led match history with separately opted-in local public timelines,
  life/permanent graphs, observation scrubbing and inspectable public card events.
  This is not deterministic engine replay. Older sessions cannot gain retroactive
  detail. Hidden cards, hands, opponent decks and raw log messages are not saved.
- Compact battlefield badges use current engine icons, including flying, reach
  and hexproof, with bounded overflow and accessible names.

## Verification before distribution

- Portable suite: 399 tests, zero failures, two explicitly optional skips.
- Final affected artwork suite: 47 tests, zero failures, including live public
  bulk index audit and real image download/offline reopen.
- Current public bulk index resolves all 31,881 bundled ordinary card names.
  This verifies references, not downloading every ordinary card image.
- Downloaded and decoded all 1,063 supported token faces (70 back faces), then
  reopened the persistent store and resolved them with network disabled. Explicit
  Soldier, Human, Elf Warrior, Zombie and Treasure identities are covered.
- Betor, Kin to All downloaded and resolved offline. Repeating the full token
  request queued zero image transfers. Corrupt-file repair tests transfer only
  the damaged image and preserve the other stored face.
- 27 iOS simulator presentation tests passed, including badge capacity, current
  engine state, accessibility and actual Flying/Reach/Hexproof asset loading.
- App and test bundles compiled with an exact-source fingerprint. Nine selected
  UI scenarios passed across the initial run and focused corrected rerun: both
  board orientations, pinned workspaces, four download/consent checks, and the
  dashboard's expansion, scrubbing, card inspection and landscape transition.
  The new test exposed inherited accessibility identifiers and then two test
  selector/partially-visible-row mistakes; these were corrected and rerun.
- Seven focused history tests passed after correcting saved-detail retention
  when detailed recording is disabled and re-enabled during the same match.
- Portrait/landscape dashboard and battlefield badge screenshots were visually
  reviewed. These are explicitly labeled development fixtures, not live games.

Public audit evidence is retained at `/tmp/magicmobile-offline-artwork.zvEZKT/`;
the token audit contains public Scryfall artwork, not private game data.
The public bulk input SHA-256 is
`55fc9a3c2e116c58c2510b5420d4ac7ee4961a28e083e162dc376b4a6752241e`.

## Native provenance and boundaries

No XMage engine inputs were changed. Reuse the paired build-7 native candidate
from source `d9d745fe0904068f197ad8d6a81e69ac4a5eedaf`, upstream
`4825513287ba6c42c32fd205d227f4a5fc44c2f3`, workflow `35630421619`, artifact
`10658094630`. The release guard must independently verify input equivalence,
staged hashes, signed exported code, dSYM and Game Center entitlements.
Prior real-engine/native evidence is described in `RELEASE_0.1.1_BUILD7.md`;
new simulator fixtures and artwork tests are not physical-device gameplay.

Custom or unpublished token art cannot be guaranteed. A safe labeled token
retains its engine characteristics rather than substituting a different token.

## Distribution

Released 2026-09-21 from `codex/ios-offline-artwork`, source commit
`7f12cb02d5e8579ed358898fa4e0a0d6d2c15dab`, in the
`/Users/calebfeliciano/Documents/MagicMobile-board-polish` checkout.
Build number 8 was verified absent before preparation and again before upload.

- Signed archive/export, signed-native/Game Center guard, Apple validation and
  upload passed. The unchanged native engine was reused, not rebuilt.
- App identity: `com.calebfeliciano.magicmobile`; Apple app `6784735182`.
- Delivery UUID and Apple build ID: `92848363-bd13-43bb-b324-6c684e354ccb`.
- IPA: `build_output/testflight/native-release.ldGiX0/export/MagicMobile.ipa`.
- IPA SHA-256: `6638c563a4413ad9386f0f8bc1e76f2be2f6de868e7effa442a715df6522816b`.
- Apple processing: `VALID`; Beta App Review: `APPROVED`.
- Independently verified Internal and External group membership; both build
  states are `IN_BETA_TESTING`, with automatic tester notifications enabled.
- English What to Test notes explain missing-only downloads, offline token checks,
  current ability badges and enabling detailed history before a new AI match.
- Fingerprint-bound release controller `ios-0.1.1-8` completed; original receipts,
  Apple responses and checksummed logs remain under the release root above and
  `build_output/release-controller/ios-0.1.1-8/`.

No physical-iPhone gameplay acceptance is claimed for this build. Android remains
paused; no Android build, engine update, website or server deployment was performed.
