# MagicMobile download site

Standalone React/Vite marketing site. This is not the browser game. The Android and iOS apps remain native projects.

## Run and build

From `apps/site`, run `npm ci`, `npm run dev`, or `npm run build`. Production files are in `dist`. `npm run preview -- --port 4174` serves the built package locally.

## Deploy

The Git-linked Vercel project uses root directory `apps/site`, framework Vite and output `dist`. `vercel.json` carries the install/build configuration. Use the existing download-site project; do not overwrite the separate MagicMobile game project.

Production: https://magicmobile-downloads.vercel.app, project `magicmobile-downloads` in `caleb-felicianos-projects`. Pull requests create previews; `main` is the production branch. Verify download artifacts before merging. Do not upload this subdirectory alone while the project expects a repository-relative root.

## Donation link

The apps' support banners and the home page's support card open `/support/` (`public/support/index.html`), our own page about supporting the project. Its "Leave a tip" button is the only place the donation URL lives; change it there and redeploy. No app build is needed. The apps never link straight to the donation provider, which keeps the iOS link an information page rather than a payment link.

## Updating downloads

The verified versions, build numbers, download URLs and Android release-notes link are in `src/releases.ts`. The single iOS build number to bump after confirming a new build is live for testers is `iosTestFlightBuild`; it drives both the displayed build and availability line. The FAQ answers in `src/main.tsx` name the current builds; update them with the metadata. Keep planned-feature copy labeled as planned until that build is verified live. The browser game's address is `releases.web.url`; the game itself stays unlisted (noindex). Android has its own build number and release links. Update matching platform requirements in `src/main.tsx` if needed. The website displays configured release metadata; it does not automatically poll the stores. The public TestFlight group invitation can remain stable across eligible iOS builds. Never substitute an App Store Connect administration URL. See `../../release/RELEASE_0.1.1_BUILD17.md` for the latest verified iOS distribution and `../../release/RELEASE_ANDROID_0.1.1_BUILD8.md` for the latest Android release.

## Motion and provenance

The page is "Hall and Cut" (DESIGN.md, SURFACE.md). Scroll Craft engine files are copied verbatim under `public/scrollcraft`, including its MIT license; this copy is the skill's engine as of October 23, 2026. All site-specific choreography stays in `src`: `hall.ts` walks the hall (it owns the rail's transform; the engine only pins the act) and `barDie.ts` draws the bar's D20 with Three.js, which loads after the page from its own chunk. The die is the app's own model, face map and recorded throws, copied into `public/site/d20`. The creative brief is in `scrollcraft/builds/magicmobile/BRIEF.md`; artwork, card and screenshot provenance are in `ASSETS.md`.

Native scrolling is preserved. Reduced motion keeps every section, with the walk following the scroll directly and the die standing on its 20. Without WebGL the bar shows a flat die that makes the same moves. No autoplay audio, analytics, forms, or personal-data collection.

## Verification boundaries

Production compilation is checked separately from browser behavior. Section screenshots at desktop and phone sizes come from a local `npm run preview` in headless Chrome (SwiftShader for WebGL). They are local evidence, not evidence of physical-phone acceptance or production availability.
