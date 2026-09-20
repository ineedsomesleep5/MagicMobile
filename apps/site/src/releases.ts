// Release candidate metadata. Deploy only after both distribution artifacts are verified.
export const sharedAppVersion = "0.1.1";
export const sharedReleaseBuild = "3";

// Update the version, build and download URL together for each published release.
export const releases = {
  android: {
    version: sharedAppVersion,
    build: sharedReleaseBuild,
    url: "https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.3/MagicMobile-Android-0.1.1-build3.apk",
    notes: "https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.3",
  },
  ios: {
    version: sharedAppVersion,
    build: sharedReleaseBuild,
    url: "https://testflight.apple.com/join/2mSHE8rZ",
    status: "Build 3 is uploaded and processing. Public access is pending Apple's TestFlight review.",
  },
};
