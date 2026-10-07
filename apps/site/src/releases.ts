// Published release metadata. Bump iOS only after the new TestFlight build is verified live.
export const sharedAppVersion = "0.1.1";
const androidReleaseBuild = "17";
const iosTestFlightBuild = "32";

// Keep platform build numbers independent; the TestFlight invitation URL is stable.
export const releases = {
  android: {
    version: sharedAppVersion,
    build: androidReleaseBuild,
    url: "https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.17/MagicMobile-Android-0.1.1-build17.apk",
    notes: "https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.17",
  },
  ios: {
    version: sharedAppVersion,
    build: iosTestFlightBuild,
    url: "https://testflight.apple.com/join/2mSHE8rZ",
    status: `Build ${iosTestFlightBuild} is available now for Internal and External TestFlight testers, on iPhone and iPad.`,
  },
};

// Obtainium installs MagicMobile from its GitHub releases and offers each new build.
// The `latest/download` link always serves Obtainium's newest ARM64 APK; the add link
// opens Obtainium with MagicMobile's repository filled in.
export const obtainium = {
  download: "https://github.com/ImranR98/Obtainium/releases/latest/download/app-arm64-v8a-release.apk",
  addApp: "obtainium://add/https://github.com/ineedsomesleep5/MagicMobile",
  source: "github.com/ineedsomesleep5/MagicMobile",
};
