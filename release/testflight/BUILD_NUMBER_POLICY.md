# TestFlight build-number policy

MagicMobile uses a monotonic ten-digit TestFlight build counter. The configured
`nextBuildFloor` in `build-ledger.json` is the first value available after older
date-based builds; it does not itself prepare or upload a build.

The next `node scripts/ios/testflight-build-number.mjs prepare` will select
`5000000000`. After that build is recorded as uploaded, the next prepare will
select `5000000001`, then increment by one for each later release. The helper
refuses to reuse an uploaded or directly installed build and refuses to exceed
the ten-digit range.
