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
What to Test notes were added. The required review contact was completed and the
build was submitted to Beta App Review on 2026-09-15. Apple reports the submission
as `WAITING_FOR_REVIEW`. External access will become active after Apple's approval;
no public link or tester membership was changed.
