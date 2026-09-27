# Direct iPhone install — 0.1.0 (2026091501)

Installed and launched September 15, 2026 on Caleb's iPhone 16 Pro Max.
Bundle remains `com.calebfeliciano.magicmobile`. No uninstall, saved-data reset,
TestFlight upload or public release occurred. CoreDevice's installed-app query
confirmed version `0.1.0`, bundle version `2026091501`, and developer-built status.
The direct connection was reported as wired by CoreDevice at delivery; do not
describe that receipt as proof of wireless transport.

## Frozen source and checks

- Checkout: `/Users/calebfeliciano/Documents/MagicMobile-runtime-hardening`.
- Branch: `codex/native-runtime-hardening`, PR #9 over
  `codex/testflight-readiness-audit`; stacked history preserved.
- Application source: `72249f37ffe86f291c4750143adb65643d3b5ea8`.
- Engine source: `aa50beea953d7c820417826128d88de72123686b`.
- Final simulator: 398 app tests, one optional live test skipped, zero failures;
  all 27 UI journeys passed. These use development presentation fixtures, not
  native gameplay. Result: `build_output/final-complete-ui-candidate.xcresult`.
- CI 34933986200, package gates 34933986285, non-simulator 34933982982 passed.
  Non-simulator includes actual Apple SDK and real-JVM jobs. The package's
  dispatch-only upstream report was intentionally skipped on the PR event.
- Full native run 34930407016 passed on attempt 1. Paired unsigned Release product
  34934101113 passed on the exact final app source; all required steps succeeded.

## Artifact and signing evidence

Native artifact `10383692026`, ZIP SHA-256:
`fe1658ec3e038b2af670fe73f904e8e5b20c94a0787f3fa23961c8fa13639da0`.
Engine archive SHA-256:
`cc5b79e978d2669d491a6cc9b25703af0cd8367d28429769373599e423a4bf3c`.
Unmodified source verifier accepted guarded equivalence digest:
`d9c564ef5536aa9ee70acd877163966acb0b25806020e16e6d2e438d91aa7f0a`.

Signed installed binary SHA-256:
`82594f5e10d5be8f2f6fcaa71f6c8fbf5999c5a721f2cdca3e89a387fcd423ca`.
Actual product verification found ARM64/iPhoneOS, embedded XMage and all required
native definitions. Layout verification, including matched dSYM, preserved
191,602,720 Graal code bytes, 818 relocated instructions and seven veneers.
Strict codesign verification passed. Embedded development profile/certificate,
team, bundle, expiry, Caleb's authorized device, Game Center and development
entitlements were checked. The bundled privacy manifest matches source.

The first manual-signing attempt was rejected because the existing profile is
Xcode-managed. Automatic signing with the existing team succeeded without
allowing provisioning updates. The default archive stripped symbols required by
the product verifier, so the final development archive uses
`STRIP_INSTALLED_PRODUCT=NO`. No verifier or source guards were weakened.
Both were app-archive corrections, not additional native-engine compilations.

Final archive: `build_output/direct-72249f3/MagicMobile-device.xcarchive`.
Receipts/logs under `build_output/direct-72249f3/`: `native-run.json`,
`source-receipt.json`, `generated-project.json`, `product-receipt.json`,
`signed-layout.json`, `archive-device.log`, `install.json`, `launch.json`,
and `installed-apps.json`. Device/profile diagnostics stay local.
The previous staged engine is preserved at `previous-NativeEngine` in that folder.
The generated native project and other tracked source remained unchanged through
verification. Subsequent documentation/ledger commits are not the binary source.

## Acceptance boundary

Installation and launch are verified; new native gameplay, motion/performance,
automatic rotation, offline endurance and multi-device Game Center acceptance
remain manual. No claim of exhaustive card correctness or Hearthstone parity.
First check: Token Triumph versus one Grave Danger MAD opponent, human starts,
mulligan/keep, then mana/commander/combat/tokens, logs, crowded landscape resizing,
zone/stack inspection, background/resume and exit/new match. Share any hidden-card
diagnostics only through the explicit private reporting flow.
