// Published release metadata. Bump iOS only after the new TestFlight build is verified live.
export const sharedAppVersion = "0.1.1";
const androidReleaseBuild = "56";
const iosTestFlightBuild = "79";

// Keep platform build numbers independent; the TestFlight invitation URL is stable.
export const releases = {
  android: {
    version: sharedAppVersion,
    build: androidReleaseBuild,
    // Same-origin file. Do not point this at a code host.
    url: "/downloads/MagicMobile-Android-0.1.1-build56.apk",
  },
  ios: {
    version: sharedAppVersion,
    build: iosTestFlightBuild,
    url: "https://testflight.apple.com/join/2mSHE8rZ",
    status: `Build ${iosTestFlightBuild} is available now for Internal and External TestFlight testers, on iPhone and iPad.`,
  },
  // The browser game is linked from here but stays unlisted: the game itself carries noindex.
  web: {
    url: "https://magicmobile-web.vercel.app",
  },
};

