# External TestFlight candidate 2026091504

Version **0.1.0 (2026091504)** is the external-eligible copy of the reviewed Arena
update. There are no gameplay/UI changes from build 2026091503.

- Application source: `176b9a895f43782f8f4393cc3988bdcd991af8bb`
- Engine source: `91220d27c62f9fc7a47447a7b2f4d08cf15651ce`
- Delivery/build ID: `c6ae8e51-a677-432d-ba16-b255523ff339`
- IPA: `build_output/testflight/external-2026091504/native-release.oPh9Zl/export/MagicMobile.ipa`
- IPA SHA-256: `36defe3924b539c2544b65490a8c167cb852b2d46308a0ba7efd3a09ce260d37`

The external release guard requires an explicit `external` audience and a separate
export policy with `testFlightInternalTestingOnly` disabled. Its 16 guard tests and
six build-number tests passed. The signed archive/export, Game Center profile,
native code image/relocation checks, Apple validation and upload passed. Apple then
reported the build `VALID` with `APP_STORE_ELIGIBLE` audience.

The build is assigned to both the existing all-builds **Internal** group and the
existing **External** group. An English Beta App Description and build-specific
What to Test notes were added. External access is not active yet: Apple refused the
Beta App Review submission because required review information is still missing.
The app-level Beta App Review detail currently exposes no contact fields. Submission
requires the owner's review contact first name, last name, email and phone number.
No values were guessed, and no public link or tester membership was changed.
