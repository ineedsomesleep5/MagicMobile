# MagicMobile 0.1.1 — build 4

Release candidate. Marketing version remains **0.1.1**; shared visible build is **4**. Android installation versionCode is **2026091905**. Existing verified native engines are reused, not rebuilt.

## Changes

- Artwork metadata uses batches of up to 75 cards for decks and a cached bulk index for the full catalogue. Four concurrent direct image connections, missing-only downloads, quality selection, exact token identity, and alternate-face coverage avoid redundant work. Compact is the smallest download option; no speed multiplier is claimed.
- iOS image transfers use a durable background URLSession queue. Downloads no longer stop when leaving the screen or starting a game. Android uses a foreground download service with a pause notification and a persisted resume request. Completed files survive interruption, and matching visible cards refresh as each image arrives.
- Operating systems control background scheduling. Initial iOS image-list preparation can suspend on a slow connection; force-quitting is not uninterrupted background execution. Android can impose a foreground-service time limit. Missing artwork can be retried without redownloading completed files.
- Auras and equipment follow their public attachment relationships, including cross-controller and nested attachments. Player enchantments are associated with the enchanted player's HUD rather than floating in an unrelated battlefield lane.
- Explicitly phased-out permanents fade and are labeled, while remaining inspectable. Poison and other public player counters, monarch, and initiative are visible. State changes use restrained animations and respect reduced-motion/system animation settings. Explicit engine-authorized choices remain authoritative.
- Response windows show the actual step and the opportunity to respond; they are not presented as a fictitious extra phase. Deck Studio analysis and combo text use mana symbols.
- Future release guidance requires separately verified iOS/Android parity, shared visible numbering, and accurate website links/status. Android multiplayer remains excluded.

## Verification and release status

Build 4 verification and distribution are in progress. Compilation, fixture checks, real native gameplay, physical-phone acceptance, and store availability are separate gates; final evidence will be recorded here before handoff.

- Portable artwork checks cover durable queue restoration, bounded scheduling, consent, cancellation, staging/storage failures, service-requested pauses, front/back/token identity, quality upgrades, incremental image notifications, and missing-only repeat downloads.
- First iOS simulator pass: 87 selected logic tests, one skipped, no failures. UI checks exposed inherited attachment accessibility identifiers, a cramped landscape effects rail, and an undelivered synthetic menu tap. The identifiers and layout were corrected; the menu test uses a deliberate short press while retaining its selection assertions.
- Final affected iOS rerun: 20 presentation logic tests and seven UI tests passed. Portrait/landscape checks cover attachments and their hit targets, phasing out/in, moved player enchantments, poison changes, opponent selection, stack inspection/response cues, and download-selection persistence. The prior Downloads consent and shared-preference checks also passed. Screenshots were inspected; these are explicitly labeled unlinked fixtures, not physical-phone or native-gameplay acceptance.
- Android compilation and 18 JVM tests passed, alongside 42 auto-yield and 81 protocol/deck/privacy assertions. Service completion and notification updates are ownership-checked on the main dispatcher so an old cancelled job cannot stop a replacement job.
- Release helper checks: 10 Node tests and 20 Python tests passed.
- The reused iOS engine's pinned XMage revision includes phased-out permanents in public battlefield snapshots; visual phasing support does not depend on a new engine binary.

The obsolete TestFlight **0.3.0 (5000000002)**, ID `86d52ad6-a6f8-44f6-89c0-4489d11b1893`, was explicitly expired at the user's request and verified expired in App Store Connect. Other builds and reviews were preserved.
