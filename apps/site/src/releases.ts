// Release candidate metadata. Deploy only after both distribution artifacts are verified.
export const sharedAppVersion = "0.1.1";
export const sharedReleaseBuild = "7";

// Update the version, build and download URL together for each published release.
export const releases = {
  android: {
    version: sharedAppVersion,
    build: sharedReleaseBuild,
    url: "https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.7/MagicMobile-Android-0.1.1-build7.apk",
    notes: "https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.7",
  },
  ios: {
    version: sharedAppVersion,
    build: sharedReleaseBuild,
    url: "https://testflight.apple.com/join/2mSHE8rZ",
    status: "Build 7 is available now for Internal and External TestFlight testers.",
  },
};
