# TestFlight 0.1.1 (60): the freeze logger

Uploaded October 24, 2026 and distributed to Internal and External testers (both `IN_BETA_TESTING`), together with
Android build 37. Prompted by a TestFlight report, "froze in ranked" (iPhone 16 Pro, iOS 26.6.2), that came with no crash
log and left no trace on the server.

## What changed (PR #239, docs/FREEZE_LOG.md)
- A main-thread watchdog saves a hang of 2 s or more at once and keeps its duration current.
- The game session checks every 5 s for an answer the engine hasn't taken in 20 s, or a game that hasn't moved for
  120 s (180 s at a table) while nothing waits on you (FreezeRules, shared freeze-cases.json).
- The last 80 breadcrumbs and the game's state go with each incident; the last 5 are kept in the diagnostics folder.
- Reports leave the phone only on Send: the next launch asks about an in-game freeze, and the game menu has Report a
  freeze. Both call `mm_send_diagnostic` (write-only table `diagnostic_reports`, applied live).
- The privacy manifest declares crash and performance data; the site's privacy page says what a report holds.

## Release
- **Source:** `codex/ios-build-60` in `~/Documents/MagicMobile-release-40` = `claude/freeze-logger` (PR #239) + build 59's
  ledger record + `prepare`.
- **Engine:** release C, unchanged (`prepare_ios_app_native.py --verify-installed` exit 0); preflight `ios-fast` 14/14,
  `equivalent-source`.
- **Run:** `ios-0.1.1-60`, fingerprint `d9f5247a…`, IPA `8f2f563f…`, VALID about 9 minutes after upload; the second
  resume distributed it to Internal + External.

## Verification
- `swift test`: FreezeLogTests, OnDeviceSessionTests, OnDeviceDiagnosticsTests, PrivacyManifestTests (56 passed); the app
  compiles and links for a generic iOS device; CI (`swift`, `boundary-tests`, `real-jvm`, Android `app`) green on #239.
- **Not verified:** the watchdog, the launch question, Report a freeze and a real send on a phone.
