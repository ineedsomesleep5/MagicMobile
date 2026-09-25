# MagicMobile download site

Standalone React/Vite marketing site. This is not the browser game. The Android and iOS apps remain native projects.

## Run and build

From `apps/site`, run `npm ci`, `npm run dev`, or `npm run build`. Production files are in `dist`. `npm run preview -- --port 4174` serves the built package locally.

## Deploy

The Git-linked Vercel project uses root directory `apps/site`, framework Vite and output `dist`. `vercel.json` carries the install/build configuration. Use the existing download-site project; do not overwrite the separate MagicMobile game project.

Production: https://magicmobile-downloads.vercel.app, project `magicmobile-downloads` in `caleb-felicianos-projects`. Pull requests create previews; `main` is the production branch. Verify download artifacts before merging. Do not upload this subdirectory alone while the project expects a repository-relative root.

## Updating downloads

The verified versions, build numbers, download URLs and Android release-notes link are in `src/releases.ts`. The single iOS build number to bump after confirming a new build is live for testers is `iosTestFlightBuild`; it drives both the displayed build and availability line. Keep planned-feature copy in `src/main.tsx` labeled as planned until that build is verified live, then update the feature claims alongside the metadata. Android has its own build number and release links. Update matching platform requirements in `src/main.tsx` if needed. The website displays configured release metadata; it does not automatically poll the stores. The public TestFlight group invitation can remain stable across eligible iOS builds. Never substitute an App Store Connect administration URL. See `../../docs/RELEASE_0.1.1_BUILD17.md` for the latest verified iOS distribution and `../../docs/RELEASE_ANDROID_0.1.1_BUILD8.md` for the latest Android release.

## Motion and provenance

Scroll Craft engine files are copied verbatim under `public/scrollcraft`, including its MIT license. All site-specific choreography stays in `src`; the shared engine is unmodified. Skill source: https://github.com/nateherkai/scroll-craft, downloaded September 19, 2026. The full creative/verification brief is in `scrollcraft/builds/magicmobile/BRIEF.md`; artwork and app screenshot provenance are in `ASSETS.md`.

The engine and Three.js have distinct jobs: semantic scroll states versus the modeled hand. Native scrolling is preserved. Reduced motion removes pinned travel and exposes all app content in normal flow. WebGL failure uses the same card imagery in a static hand. No autoplay audio, analytics, forms, or personal-data collection are added.

## Verification boundaries

Production compilation is checked separately from browser behavior. Section screenshots, compact-phone/reduced-motion checks, and Lighthouse reports live in ignored `.impeccable/review/scrollcraft`. They are local evidence, not evidence of physical-phone acceptance or production availability. The initial quiet design's reviews are superseded by the Scroll Craft revision.
