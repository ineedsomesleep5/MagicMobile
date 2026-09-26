# 0.1.1 build 5 release evidence

## Shared engine

The approved upstream is `4825513287ba6c42c32fd205d227f4a5fc44c2f3`.
See [the source/inventory review](../docs/ENGINE_UPDATE_4825513.md). The exact-source
non-simulator gate [35526972236](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35526972236)
passed on `9453fe648cb0890c2bc072a80aead81305b22512`.

Marketing version remains **0.1.1**, shared visible build **5**. Matching numbers
alone do not establish platform parity or gameplay acceptance.

## Android: published

[Download signed APK](https://github.com/ineedsomesleep5/MagicMobile/releases/download/android-v0.1.1-build.5/MagicMobile-Android-0.1.1-build5.apk)
([release](https://github.com/ineedsomesleep5/MagicMobile/releases/tag/android-v0.1.1-build.5)).

- App source: `5c44fae492959a3dc358d19eac53fadc02edc2e9`.
- Native source: `9453fe648cb0890c2bc072a80aead81305b22512`.
- Native run [35526973708](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35526973708) passed.
- Native artifact `10609363709`, ZIP SHA-256
  `a1341fef75e84ed51d1d4dcdb4ffd500dca767dcf9bb063e0b54d86bd623b02d`.
- Packaged engine SHA-256: `29c2cdee7da7201d00cb5b7707442b1e5f8a92cef29539a5a27352b53bc123af`.
- APK SHA-256: `1b6f95cb1e17e021643c8b8cf24821fc9448f045c9980903d81d4fcd01983f22`.
- Existing signer SHA-256: `b10ca2cdf5d184c2b264b56dae888d950f3ab52a40551b7f8eb634de0316d4bb`.
- Application ID `com.calebfeliciano.magicmobile.android`, installation code `2026092001`.
- Source equivalence, core checks, release build/lint, signing and 16 KB alignment passed.
- All 10 instrumentation tests passed on the exact signed APK on `MagicMobile_API35`
  ARM64 emulator. The actual native Commander game ended at turn 17 after 83
  responses. Ten reopen cycles and three distinct AI opponent decks passed.
- Evidence: `build_output/android-release/build5-xmage4825513/` and
  `build_output/android-acceptance/instrumentation-pkPvi5` (local, not tracked).
- Published asset digest matches the tested APK; public URL returned HTTP 200.

This is emulator native execution, not physical Android hardware acceptance.

## Portable server: prerelease published, hosted Online still disabled

[Launcher ZIP](https://github.com/ineedsomesleep5/MagicMobile/releases/download/server-build5-4825513/magicmobile-selfhost-0.1.1-build5.zip)
([setup instructions](../apps/multiplayer-server/selfhost/README.md)).

- Runtime source `5c44fae492959a3dc358d19eac53fadc02edc2e9`; launcher source
  `0a592955ebca943a560999e4a011c2fa77ccf9b0`.
- Packaging run [35527028356](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35527028356) passed.
- Runtime archive SHA-256 `b90c95a11a71549aaba51290bd487e0093fb1ea65449c020c6510300244a3a74`.
- Launcher SHA-256 `0243edeb4840371f5a9ea54dcc95ec76dac4844b9b6be5e0a4c6f841d3694186`.
- Fresh Java 17 build, five Swift-resolved precons, bridge regressions, package
  checks and 1,094 real-engine HTTP assertions passed for two-/four-seat openings.
- Seven isolated launcher tests passed. Published digests match; launcher HTTP 200.

The HTTP test uses synthetic authentication/lobby data. It does not prove full
multiplayer games, production Supabase, Windows/Linux execution, phone acceptance
or capacity on a free host. Database readiness stays false, binding stays loopback,
and Render stays on hold. Game Center is preserved on iOS. Dedicated Online must
remain disabled until its independent deployment/security/device gates pass.

## Weekly schedule: active

After restarting Codex restored its connection, the existing
`watch-xmage-updates-for-magicmobile` heartbeat was updated and its saved active
configuration verified. It now runs the [weekly gated release policy](../docs/AUTOMATIC_UPDATE_PIPELINE.md)
on Mondays at 09:23 using the selected repository. Its existing thread attachment
was preserved; no duplicate automation or workaround cron was created. Automatic
publication is conditional on reviewed changes and passing release gates.
The superseded build-4-only submission heartbeat was first paused, then repurposed
and verified active as **Finish MagicMobile build 5 release**, every ten minutes.
It follows the exact existing native/product runs, resumes the guarded release
without duplicate uploads, and must never submit build 4. It deletes itself after
the release/merge and any pending Apple availability follow-up are resolved.
No Apple review was cancelled or altered by this scheduler change.

## iOS: Internal and External TestFlight testing

- Full ARM64 native run [35528082243](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35528082243)
  and exact-artifact product-link run [35529469186](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/35529469186)
  passed.
- Native artifact `10611477138`, ZIP SHA-256
  `148b488970162bae27d6028ef1b8d66adca3d81fdc381cbed050179be36182b8`;
  engine archive SHA-256
  `1b39d68b97acf21a463945314b933e7f023d2439a613a6bf84abafd14ea67147`.
- Signed source: `15be96db45b6887f1bd417a041fb52f1558b7040` with engine source
  `9453fe648cb0890c2bc072a80aead81305b22512`.
- The archive, export, UUID-matched dSYM/native layout, privacy, Game Center
  entitlement and Apple validation gates passed. IPA SHA-256:
  `d6ff58896b67cf80d28ba1d5778bba4010826613c02378834bfed6f8a823e7bc`.
- Delivery UUID and App Store Connect build ID:
  `0b51bd9f-edb4-4950-84fa-bd5a87e0ba53`.
- Apple reports the build `VALID`, Beta App Review `APPROVED`, and both Internal
  and External states `IN_BETA_TESTING`. Membership in both existing tester groups
  and the public TestFlight link were verified. Accurate What to Test notes were
  added for build 5.

[Join the iOS TestFlight](https://testflight.apple.com/join/2mSHE8rZ).
No physical iPhone acceptance is inferred from signing, upload or TestFlight
availability.

## Website and merge

[The production download site](https://magicmobile-downloads.vercel.app) now shows
version **0.1.1**, build **5** for both platforms. The promoted Vercel deployment
`magicmobile-downloads-nor50zpci-caleb-felicianos-projects.vercel.app` reached
`READY`. The live production page was checked after promotion: its Android button
uses the verified build-5 APK URL, its release-notes link uses the build-5 GitHub
release, and its iPhone panel reports build 5 available to Internal and External
TestFlight testers with the existing public invitation URL.

The site layout code did not change in this release-label update, so the prior
mobile/desktop visual acceptance remains applicable; the current live accessibility
tree and both platform panels were rechecked. [PR 15](https://github.com/ineedsomesleep5/MagicMobile/pull/15)
carries this release into `main`; GitHub remains authoritative for its final merge
state and checks.
