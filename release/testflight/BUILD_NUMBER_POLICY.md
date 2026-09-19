# TestFlight build-number policy

The user-selected baseline is **version 0.1.1, build 1**. Keep the marketing
version at 0.1.1 for subsequent updates and increment only the release build:
2, 3, 4, and so on. Do not start another marketing version without an explicit
user request. Apple may require review for the first build of this version;
later builds are still subject to Apple's review decisions.

After initial preparation with `node scripts/ios/testflight-build-number.mjs prepare --start-at 1`,
use `node scripts/ios/testflight-build-number.mjs prepare` for each later release.
An unuploaded prepared build is reused; an uploaded or directly installed build
is not. Store lookups must include both marketing version and build number.
Preparation does not upload or distribute anything.

The ledger preserves older date-based and 5000000000-series receipts. The new
version-scoped sequence does not use that legacy floor. Upload records are
identified by both version and build, so an older version's build 1 is not lost.

Android and the website use the same visible version/release build. Android's
installation `versionCode` remains separately monotonic: 2026091902 for 0.1.1
build 1. Never reset that internal code to 1, because existing users must be
able to install updates without uninstalling or losing their data.
