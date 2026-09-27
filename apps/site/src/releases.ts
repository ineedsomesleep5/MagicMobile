// Published release metadata. Bump iOS only after the new TestFlight build is verified live.
export const sharedAppVersion = "0.1.1";
const androidReleaseBuild = "10";
const iosTestFlightBuild = "18";

// Keep platform build numbers independent; the TestFlight invitation URL is stable.
export const releases = {
  android: {
    version: sharedAppVersion,
    build: androidReleaseBuild,
    url: "https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.10/MagicMobile-Android-0.1.1-build10.apk",
    notes: "https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.10",
  },
  ios: {
    version: sharedAppVersion,
    build: iosTestFlightBuild,
    url: "https://testflight.apple.com/join/2mSHE8rZ",
    status: `Build ${iosTestFlightBuild} is available now for Internal and External TestFlight testers.`,
  },
};
