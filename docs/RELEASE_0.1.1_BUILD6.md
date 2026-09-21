# 0.1.1 build 6: scrolling and rotation

Release in progress; publication and runtime results below must be verified before
this document is used as availability evidence.

## Changes

- In-game settings scroll within the available sheet height, support expanded
  presentation, and provide an explicit Done button. Theme selection no longer
  puts Quit below a non-scrollable container.
- Card inspection uses a cancellable long press instead of a zero-distance drag
  competing with the containing scroll view. Ordinary selection and release-to-
  dismiss inspection remain part of the regression checks.
- Combat arrows and offscreen indicators resolve card anchors in the current
  layout, without sharing cached rectangles between portrait and landscape.
- Development fixtures include overflowing lands, permanents and graveyards;
  interaction tests drag directly on card artwork and repeatedly rotate combat.

## Android scope

Android uses bounded Compose lists for settings, gameplay, zones and authorized
card choices. Its inspection gesture does not consume browsing motion. Leave is
in the game header, and combat relationships come from the current snapshot as
text rather than cached arrow coordinates. Source review found no corresponding
defect; no speculative gameplay changes were made. Build 6 preserves that app
behavior and the verified build-5 engine, with installation code 2026092002.
This source audit does not establish physical-device interaction acceptance.

## Engine reuse

Both platforms retain engine source
`9453fe648cb0890c2bc072a80aead81305b22512`, reviewed XMage upstream
`4825513287ba6c42c32fd205d227f4a5fc44c2f3`, and 31,881 supported names.
The unchanged-source and staged-artifact integrity guards passed locally.
See [build 5 evidence](RELEASE_0.1.1_BUILD5.md) for native runtime provenance.
No engine rebuild was dispatched. Game Center remains available; dedicated Online
and Render remain on hold.

## Validation and publication

- Pre-fix interaction run: 35551869274, source `ebb41f6` (pending).
- Fixed interaction run: 35552009395, source `5c16c16` (pending).
- iOS syntax parsing passed locally; actual SDK compilation and UI execution are
  distinct pending gates.
- iOS 0.1.1 build 6 was absent in App Store Connect before preparation; recheck
  immediately before upload.
- Android signed package, TestFlight distribution, website verification, and
  final release receipts are pending.
