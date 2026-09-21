# 0.1.1 build 7 candidate — release not yet complete

This is an in-progress evidence record. It does not announce TestFlight or APK availability.

## Scope

App implementation source: `ef5ebf68337233b9c4c8bfaa6d8c638db784e9c2`, with
the final Android noncreature-stat correction in `fbd46ad`,
[PR #17](https://github.com/ineedsomesleep5/MagicMobile/pull/17).
Its source/CI checks passed; release-specific gates below remain separate.

Adaptive land/mana-rock rows, searchable large choices, guarded multi-card/scry drafts,
token-only artwork downloads and on-demand caching, explicit copied-token source artwork,
and expanded private match history on iOS and Android. See
[implementation and verification](BOARD_CHOICES_TOKEN_HISTORY.md).

XMage remains pinned to `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.
Only the mobile bridge's seat-scoped artwork metadata changed; live rules and token
characteristics remain authoritative. Artwork cannot be guaranteed for custom tokens
without a matching published image; safe placeholders retain their live information.

## Engine and runtime provenance

- Frozen bridge source: `d9d745fe0904068f197ad8d6a81e69ac4a5eedaf`.
- Exact-source [non-simulator gate](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628109901): passed.
- [Android native build](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628113147): passed.
  Full native artifact `10654193422`, ZIP SHA-256
  `b6317e39a8ec572152107f816cf2dde3fb88958458f88e22fbb87bc0f3f9c843`.
  The workflow's APK is not the new app candidate and must not be published as build 7.
- [Gated iOS native build](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35630421619): pending.
- [Matching self-host runtime](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35628982999): passed.
  959 real-engine HTTP assertions covered two-/four-seat opening flows, not completed
  games, physical phones, or production services.
  Artifact `10653743508`, verified ZIP SHA-256
  `0df9b69897726b1f5b5ebae94da5cc07f939c3ff8602b2af906c2fe3dd137fa4`.
  Runtime TAR SHA-256
  `7d340b55d503e57d92cc46071481210175436df80557c02f746af6b38f9e1868`.
  Exact runtime source is the frozen bridge commit; source changes were empty.
  Seven isolated launcher regressions passed after updating the pinned candidate URL.
  Candidate launcher ZIP SHA-256:
  `96bcb197a8d450f04cd289be61dd3388521f5c4d37f54329fbd354c02d5b051c`.

## Signed Android candidate (not yet published)

- Version `0.1.1`, shared build `7`, installation code `2026092101`, unchanged package
  `com.calebfeliciano.magicmobile.android`.
- APK SHA-256: `3b255f9db824b0a7379ebb7ac6565e810e005d2a271fe46e01971543d87b89e5`.
- Instrumentation APK SHA-256: `01afbb2346997647d5c8d22029205dda27f691a7ade16dd8a50f8d7dfc860166`.
- Existing signer SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.
- Exact native source/input guard, release compilation, core contracts, release lint,
  16 KiB alignment and signing verification passed. Main agent independently verified
  the release APK checksum, certificate and packaged version.
- The final APK updated the existing emulator installation without erasing data and
  passed all ten packaged-engine instrumentation tests (`instrumentation-statsfix.txt`,
  55.759 seconds), including completed Commander play, ten native isolate reopen cycles,
  deck persistence, offline OCR and disabled-online readiness. This is emulator evidence,
  not physical Android hardware acceptance. A preliminary APK with redundant build text
  in versionName is preserved locally but will not be published. The prior `3ad31f4…`
  candidate is also preserved as `superseded-stats.apk`. A final real-app screenshot
  confirms Plains no longer displays false 0/0; regression checks retain real creature
  0/0, planeswalker loyalty and hidden-card redaction. Core contracts now total 136.

## Open release gates

Paired iOS native artifact/product link, signed iOS archive/privacy/Game Center validation,
Apple processing and both tester groups, public artifact checksums/links, and safe
main-branch integration remain to be recorded. Shared visible build 7 was absent
from the 0.1.1 App Store Connect version on the latest read-only check (an older 0.1.0
build 7 is unrelated). Android versionCode is `2026092101`.

No physical-device acceptance is inferred from source tests, fixtures, CI, emulator
execution, signing, or distribution. Dedicated Online remains disabled, database
readiness remains false, and Render remains on hold.
