# MagicMobile 0.1.1 — build 4

Marketing version remains **0.1.1**; shared visible build is **4**. Android installation versionCode is **2026091905**. Existing verified native engines are reused, not rebuilt.

## Changes

- Artwork metadata uses batches of up to 75 cards for decks and a cached bulk index for the full catalogue. Four concurrent direct image connections, missing-only downloads, quality selection, exact token identity, and alternate-face coverage avoid redundant work. Compact is the smallest download option; no speed multiplier is claimed.
- iOS image transfers use a durable background URLSession queue. Downloads no longer stop when leaving the screen or starting a game. Android uses a foreground download service with a pause notification and a persisted resume request. Completed files survive interruption, and matching visible cards refresh as each image arrives.
- Operating systems control background scheduling. Initial iOS image-list preparation can suspend on a slow connection; force-quitting is not uninterrupted background execution. Android can impose a foreground-service time limit. Missing artwork can be retried without redownloading completed files.
- Auras and equipment follow their public attachment relationships, including cross-controller and nested attachments. Player enchantments are associated with the enchanted player's HUD rather than floating in an unrelated battlefield lane.
- Explicitly phased-out permanents fade and are labeled, while remaining inspectable. Poison and other public player counters, monarch, and initiative are visible. State changes use restrained animations and respect reduced-motion/system animation settings. Explicit engine-authorized choices remain authoritative.
- Response windows show the actual step and the opportunity to respond; they are not presented as a fictitious extra phase. Deck Studio analysis and combo text use mana symbols.
- Pass priority retains its rules meaning and adds a short contextual helper: "Let others respond" with a stack, or "Let this step continue" without one. Accessible explanations clarify that resolution/advancement requires everyone to pass. No extra casting confirmation, misleading cast label, or engine change is introduced.
- Future release guidance requires separately verified iOS/Android parity, shared visible numbering, and accurate website links/status. Android multiplayer remains excluded.

## Verification and release status

Both signed artifacts use app source `63ca7667e7a2089d478a64b2bcdc0c1c7781d9c5`. Compilation, fixture checks, real native gameplay, physical-phone acceptance, and store availability remain separate evidence categories.

- Portable artwork checks cover durable queue restoration, bounded scheduling, consent, cancellation, staging/storage failures, service-requested pauses, front/back/token identity, quality upgrades, incremental image notifications, and missing-only repeat downloads.
- First iOS simulator pass: 87 selected logic tests, one skipped, no failures. UI checks exposed inherited attachment accessibility identifiers, a cramped landscape effects rail, and an undelivered synthetic menu tap. The identifiers and layout were corrected; the menu test uses a deliberate short press while retaining its selection assertions.
- Final affected iOS rerun: 20 presentation logic tests and seven UI tests passed. Portrait/landscape checks cover attachments and their hit targets, phasing out/in, moved player enchantments, poison changes, opponent selection, stack inspection/response cues, and download-selection persistence. The prior Downloads consent and shared-preference checks also passed. Screenshots were inspected; these are explicitly labeled unlinked fixtures, not physical-phone or native-gameplay acceptance.
- Final priority-help follow-up: two logic and two portrait/landscape stack UI tests passed, with both layouts visually inspected. The stack fixture now matches the actual GAME_SELECT/priority prompt; the inspector-opening test uses a deliberate short press after an undelivered synthesized tap, retaining its destination and interaction assertions.
- Final Android compilation and 22 JVM tests passed, alongside the earlier unchanged 42 auto-yield and 81 protocol/deck/privacy assertions. Service completion and notification updates are ownership-checked on the main dispatcher so an old cancelled job cannot stop a replacement job.
- The exact final signed APK passed all nine emulator instrumentation checks, including native Commander gameplay, distinct AI deck configuration, persistence, privacy, and ten native close/reopen cycles. Final report: `build_output/android-acceptance/instrumentation-wlpQS5`.
- A real Scryfall download exposed omitted `has_more` metadata in collection responses; Android validation was corrected and malformed/bounded-response regressions added. iOS already accepted this shape; its fixture was updated and 17 catalogue tests completed with one skip and no failures.
- Live final-APK artwork acceptance: resumed the saved Token Triumph/Compact/tokens request after installing the corrected APK, left the app for the launcher, observed foreground service ID 4201 and its ongoing download notification, then returned to "Artwork download complete." with 1.19 MB stored and no remaining resume request. This verifies actual Scryfall transfer and background completion, not an uninterrupted full-catalogue transfer or physical Android phone acceptance.
- Release helper checks: 10 Node tests and 20 Python tests passed.
- The reused iOS engine's pinned XMage revision includes phased-out permanents in public battlefield snapshots; visual phasing support does not depend on a new engine binary.

The obsolete TestFlight **0.3.0 (5000000002)**, ID `86d52ad6-a6f8-44f6-89c0-4489d11b1893`, was explicitly expired at the user's request and verified expired in App Store Connect. Other builds and reviews were preserved.

## Signed artifacts and delivery

- Android release: https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.4
- APK: `MagicMobile-Android-0.1.1-build4.apk`, 191,915,895 bytes; SHA-256 `b0781c81688dca47121cb3d2d876e5eb0fcc24124bc4020885c69ab0cc367641`. Public download returned HTTP 200; GitHub asset digest matches the tested file. Existing signing identity is unchanged.
- iOS IPA: `build_output/testflight/parity-0.1.1-build4/native-release.rZrrSa/export/MagicMobile.ipa`; SHA-256 `51efd4707b753d8cad5c0a7b4b90e7b2f7a195878177bd46eeb1ebd16b9e4fdf`.
- iOS archive/export, native provenance/linkage/signing guards, Apple validation, and upload succeeded. Delivery UUID: `785dd658-32a3-4ab2-9c42-a05671fb4d96`. Store processing/tester availability is separate from upload success; subsequent App Store Connect receipts are retained beside this archive. The website states public access is pending instead of promising access from the public link.
- Website release labels and links were checked at 390×844 and 1440×1000: platform switching, exact URLs, build 4 labels, meaningful content, no runtime console errors or error overlays, and no horizontal overflow. Existing Playwright was used because the Browser plugin is unavailable.
- Remaining acceptance: physical iPhone/Android gameplay on this build; unrestricted long-duration/full-catalogue transfers under each OS's scheduling limits; exhaustive special-card interactions are not claimed by these targeted tests.
