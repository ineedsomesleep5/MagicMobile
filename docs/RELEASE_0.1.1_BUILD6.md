# 0.1.1 build 6: scrolling and rotation

Android is published and iOS is available to Internal and External TestFlight
testers. All six iOS interaction cases passed against the release app sources.
Production website verification and merge remain pending.

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

## Android publication

[Download build 6](https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.6/MagicMobile-Android-0.1.1-build6.apk)
([release notes](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.6)).

- App source: `74bc56801a2ee352b01dd4d144c10400a61c3cc6`.
- APK SHA-256: `9574fa289f9a6cf26477d776ade8ba624628c7329cb67f635449ffdc0456757c`.
- Packaged engine SHA-256: `29c2cdee7da7201d00cb5b7707442b1e5f8a92cef29539a5a27352b53bc123af`.
- Existing signer SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.
- 228 core assertions, release build, lint, signing and 16 KB alignment passed.
  Published asset digest matched; public download returned HTTP 200.
- No fresh emulator run: only version metadata changed on Android; guarded engine
  inputs and Android gameplay source remain unchanged from the recorded build-5
  native runtime acceptance.

## iOS validation and publication

- Intel run 35551869274 timed out during app compilation, before any interaction
  test. Superseded runs 35552009395 and 35552357796 were cancelled.
- Standard Apple Silicon baseline run 35553010089 (`ebb41f6`) reproduced lands
  not moving after a drag on artwork, inaccessible later library choices, and
  the graveyard browse timeout. Its menu test used an obsolete button label;
  that selector was corrected to Game controls → Game Settings in `d335729`.
- Intermediate run 35553011416 (`3c45056`) passed artwork-driven lands and
  permanents scrolling and five-orientation combat indicator checks. Captures
  showed arrows resolving to the current visible cards/header or clipped edge.
  Card/choice selection failed with the UIKit overlay, and the zone test timed
  out after initially advancing (its swipe used the app rather than inspector
  viewport). This intermediate implementation was not uploaded to TestFlight.
- `6ba2c2c` tested a sequenced SwiftUI long press / drag. Run 35554629049 passed
  tap selection but still blocked lands/library/zone scrolling. It was not
  uploaded. The zone test now clips drags to its actual scroll viewport and
  requires the final inspection action fully visible.
- Focused menu run 35553854994 (`d335729`) reached Quit after selecting Classic
  Wood, then failed returning to Done: its whole-screen downward swipe opened
  Notification Center (captured screenshot). The updated test swipes the menu's
  scroll view; `a0a0d85` also pins Done outside scrolling content so no return-to-
  top gesture is needed. Focused run 35554908621 passed theme selection, reaching
  Quit, pinned Done, and reopening the menu.
- `4dc9530` uses native tap and long-press recognizers together. Tap waits for hold
  failure; a swipe can cancel both through the containing scroll view. Explicit
  tap callbacks preserve each former card action and accessibility activation.
  Run 35555719280 passed card tap/hold release, five-orientation combat checks,
  lands/permanents swipes, library scrolling/selection/hold-without-selection,
  and menu theme/reopening checks. Zone scrolling progressed through the fixture
  and reached the final card, but repeated per-card accessibility queries caused
  the test to exceed its 120-second limit before completing its assertions.
- `7603c52` changes only the zone test to read one accessibility snapshot per
  swipe, retaining final-card reachability, full visibility and no-command
  assertions. Standalone XCTest type-check passed. Focused run 35557119693 passed
  in 60.397 seconds; the other five passing UI results apply to identical app
  sources (`git diff 4dc9530..0866a5e -- apps/ios/MagicMobile packages/ondevice-engine`
  is empty). Six cases are accepted across these two runs, not a claimed green
  result for the earlier full run that exceeded its zone-test timeout.
- Source `acd619d` passed SDK compilation, portable tests, native boundary tests,
  real JVM regressions, and Android CI. UI execution remains a separate gate.
- The source/artifact guard passed at `0866a5e`; iOS 0.1.1 build 6 was rechecked
  absent in App Store Connect immediately before starting release packaging.
- Signed source: `43378ce6bddaf02524a386a0d4e1d5e8f2fa09d2`.
- IPA SHA-256: `e91b06cea0e6c04a8eac8f610f55a2b08038ef7483a337738f168c88a7435d44`.
- Archive/export, staged native integrity, code-layout, signed Game Center,
  and Apple validation guards passed. Apple upload completed without errors.
- Build/delivery ID: `855596ba-cd01-4df9-a0d4-86f6a83d23e9`, version 0.1.1 (6).
- Apple processing: VALID. Beta App Review: APPROVED. Both Internal and External
  build states are IN_BETA_TESTING; expected group memberships were verified.
  What to Test notes were updated in en-US.
- Release receipt root:
  `build_output/testflight/scroll-rotation-0.1.1-build6/native-release.rAtp7K`.
  The archive, dSYM, signed IPA, native provenance, Apple responses and receipts
  remain preserved there. No physical-phone gameplay acceptance is claimed.
- Website now references the verified Android build-6 asset and approved
  TestFlight build 6. Production deployment verification remains pending.
