# 0.1.1 build 5 release evidence

## Shared engine

The approved upstream is `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.
See [the source/inventory review](ENGINE_UPDATE_4825513.md). The exact-source
non-simulator gate [35526972236](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35526972236)
passed on `9453fe648cb0890c2bc072a80aead81305b22512`.

Marketing version remains **0.1.1**, shared visible build **5**. Matching numbers
alone do not establish platform parity or gameplay acceptance.

## Android: published

[Download signed APK](https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.5/MagicMobile-Android-0.1.1-build5.apk)
([release](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.5)).

- App source: `5c44fae492959a3dc358d19eac53fadc02edc2e9`.
- Native source: `9453fe648cb0890c2bc072a80aead81305b22512`.
- Native run [35526973708](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35526973708) passed.
- Native artifact `10609363709`, ZIP SHA-256
  `a1341fef75e84ed51d1d4dcdb4ffd500dca767dcf9bb063e0b54d86bd623b02d`.
- Packaged engine SHA-256: `29c2cdee7da7201d00cb5b7707442b1e5f8a92cef29539a5a27352b53bc123af`.
- APK SHA-256: `1b6f95cb1e17e021643c8b8cf24821fc9448f045c9980903d81d4fcd01983f22`.
- Existing signer SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.
- Application ID `com.calebfeliciano.magicmobile.android`, installation code `2026092001`.
- Source equivalence, core checks, release build/lint, signing and 16 KB alignment passed.
- All 10 instrumentation tests passed on the exact signed APK on `MagicMobile_API35`
  ARM64 emulator. The actual native Commander game ended at turn 17 after 83
  responses. Ten reopen cycles and three distinct AI opponent decks passed.
- Evidence: `build_output/android-release/build5-xmage4825513/` and
  `build_output/android-acceptance/instrumentation-pkPvi5` (local, not tracked).
- Published asset digest matches the tested APK; public URL returned HTTP 200.

This is emulator native execution, not physical Android hardware acceptance.

## Portable server: prerelease published, hosted Online still disabled

[Launcher ZIP](https://github.com/ineedsomesleep5/MagicMobile/releases/download/server-build5-4825513/magicmobile-selfhost-0.1.1-build5.zip)
([setup instructions](../apps/multiplayer-server/selfhost/README.md)).

- Runtime source `5c44fae492959a3dc358d19eac53fadc02edc2e9`; launcher source
  `0a592955ebca943a560999e4a011c2fa77ccf9b0`.
- Packaging run [35527028356](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35527028356) passed.
- Runtime archive SHA-256 `b90c95a11a71549aaba51290bd487e0093fb1ea65449c020c6510300244a3a74`.
- Launcher SHA-256 `0243edeb4840371f5a9ea54dcc95ec76dac4844b9b6be5e0a4c6f841d3694186`.
- Fresh Java 17 build, five Swift-resolved precons, bridge regressions, package
  checks and 1,094 real-engine HTTP assertions passed for two-/four-seat openings.
- Seven isolated launcher tests passed. Published digests match; launcher HTTP 200.

The HTTP test uses synthetic authentication/lobby data. It does not prove full
multiplayer games, production Supabase, Windows/Linux execution, phone acceptance
or capacity on a free host. Database readiness stays false, binding stays loopback,
and Render stays on hold. Game Center is preserved on iOS. Dedicated Online must
remain disabled until its independent deployment/security/device gates pass.

## iOS, website, schedule and merge: pending

The full iOS native rebuild is [35528082243](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35528082243).
Product linkage, signing/upload, internal/external distribution and website
release-label updates are not completed by the Android or server results above.
No physical iPhone is currently connected for fresh acceptance.

The [weekly gated release policy](AUTOMATIC_UPDATE_PIPELINE.md) is committed,
but Codex automation reads/updates fail. The existing weekly heartbeat remains
read-only; automatic release scheduling must not be reported as configured.

[PR 15](https://github.com/ineedsomesleep5/MagicMobile/pull/15) remains a draft
until applicable release gates are complete. This document is not merge approval
or proof of the pending iOS release.
