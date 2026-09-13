# Diagnostic TestFlight 0.1.0 (2026091203)

Updated 2026-09-13 UTC. Upload is **COMPLETE**, Apple processing **VALID**, internal
state **IN_BETA_TESTING**, audience **INTERNAL_ONLY**. Access for the existing
**Internal** group (`dd37d7bb-26d8-4a0c-b8a3-7811d648a699`) is verified by explicit
and all-build membership. This is a diagnostic replacement, **not a
confirmed fix** for the native startup failure reported on build 2026091202.
PR #6 remains draft and issues #4/#7 remain open.

## Phone test

1. Install **2026091203** from the existing internal TestFlight app.
2. Select **Token Triumph** for the human, **Grave Danger** for the AI, and
   **one AI opponent**. Start the match normally.
3. If the engine stops, choose **Review engine error report** (or **Engine error
   report** on setup), review its contents, then **Share report**. Copy/paste
   the report privately into the current support conversation, along with the
   iPhone model and iOS version. Do not post a raw report to public GitHub.
4. If no report appears, report that exact result and the visible message; do
   not treat the absence of a report as successful gameplay.

Only the latest report is retained locally. Engine text is bounded to 16,384
characters; the app's saved UTF-8 report is bounded to 64 KiB. It is protected,
excluded from backups, not sent to peers, and never uploaded automatically.
The sheet provides native review/share controls and confirmed deletion.
Reports already shared cannot be removed by deleting the phone's saved copy.

The previous failure was user-confirmed on 2026091202 with default human
Token Triumph and one AI. Grave Danger is the source default AI deck; the
phone's saved AI selection was not independently confirmed. The explicit
selection above gives the next attempt a known configuration.

## Exact release evidence

- Checkout: `/Users/calebfeliciano/Documents/MagicMobile-ondevice`.
- App source: `7c27eaa20f10a7e05727f1e2fa17d1210d1932fd`.
- Engine source: `76c18bfc76ca652cbd7a979cbb8910531ccb280e`.
- Full native run: [34731298892](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34731298892),
  successful `magicmobile-far-calls.yml`; engine-input equivalence to app source passed.
- Native artifact: **10311165739**; ZIP SHA-256
  `ddb999760395493f98cee24f3d531f2b510f2b67a1b77ebadab64d54299288a0`.
- Native archive SHA-256:
  `ae22adf2a8ee5082d37e4adcea22a06a1dc909ca7a97937ae99dace5ef752db2`.
  Paired inputs are preserved in `packages/ondevice-engine/build/verified-native-10311165739`.
- Hosted product run: [34732453251](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/34732453251),
  passed. Product evidence artifact **10310992227**, ZIP SHA-256
  `2c301a81254a8989add2f70e0cef9672c560cabf8831a0f7a5a79f030edadba2`.
- Local product receipt:
  `packages/ondevice-engine/build/issue4-device-link.eLgbee/product-receipt.json`.
- Actual unsigned and exported signed app both preserve the complete
  **196,899,504-byte** Graal code image, **922** relocated instructions/targets,
  and **seven** far-call veneers. This is binary inspection, not execution.
- Exported app signature is valid for distribution; app and profile both have
  Game Center enabled and `get-task-allow=false`. Bundle remains
  `com.calebfeliciano.magicmobile`, team `82HPAY85M8`, existing ASC app **6784735182**.
- Xcode **26.6 (17F113)**, iPhoneOS SDK **26.5 (23F81a)**; ARM64 iPhone only,
  portrait and both landscape orientations. No simulator/UI workflow was run.
- Signed layout receipt:
  `build_output/testflight/issue4-2026091203-7c27eaa/signed-layout-receipt.json`.
  UUID-matched dSYM: **50AB91B4-72E5-32F5-9081-B891779E2296**.
- Archive/export/Apple validation/upload passed. Delivery UUID:
  **92c6be87-4cbf-4708-ae0c-8421932e1395**.
- IPA: `build_output/testflight/issue4-2026091203-7c27eaa/export/MagicMobile.ipa`.
  SHA-256: `f51bcd732f236bf22d5dd1baf3e9a38b9e5195d9455fac2282080055943d34cf`.
- Internal-only export used the existing tester configuration; no public App
  Store release, tester-group change or public link was created.
- English (US) What to Test notes are saved on this exact build, localization
  `868b747b-2b56-4b09-8231-e51221189d87`, including the private report instructions.

App-source CI **34732454795**, package checks **34732454790** and full
non-simulator verification **34732453204** passed. Local checks include **114**
portable app tests, **33** Swift protocol tests, **153** tooling tests, **405**
Java core assertions and **5** build-number tests. Full real JVM rules, privacy,
AI, lifecycle and completed-game regressions passed locally and in the native
workflow. Generic iPhone test compilation passed; compiled tests are not
executed phone tests. The injected JVM failure proves diagnostic capture and
peer redaction there, not the cause of the real iPhone failure.

## Remaining acceptance

Build 2026091202 failed during startup. The underlying native exception is
still unknown. Diagnostic capture, successful gameplay, native AI resource
behavior, rendered accessibility and real multi-phone play on 2026091203 are
not yet verified. Use [the physical checklist](TESTFLIGHT_ACCEPTANCE.md) and
[issue #7](https://github.com/ineedsomesleep5/MagicMobile/issues/7).

Old builds, their native inputs and their signed artifacts were preserved.
Later documentation/ledger commits describe this release; they are not the
compiled app source.
