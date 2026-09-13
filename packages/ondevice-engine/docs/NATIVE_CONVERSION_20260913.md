# Conversion follow-up — 2026-09-13

Scope: existing pinned XMage engine, local consumer runtime, existing free hosted
Intel native builder, TestFlight delivery requested. No replacement rules,
desktop server, paid runner or automatic phone controls.

## Compiler heap

Failed full native run 34740553245 at `28185e5` timed out after 180 minutes.
It analyzed 66,586 classes and 367,227 methods, essentially the same inventory
as successful diagnostic run 34731298892 (367,228 methods). After analysis,
the HotSpot builder's Parallel old generation retained 9,174,658 KiB of a
9,175,040 KiB capacity. Repeated full collections took roughly 60–96 seconds
without meaningful reclamation. There was no reported compiler exception or
Java OOM before the timeout. This evidence indicates heap-layout pressure;
the full-run benefit of changing collectors still needs measurement.

The builder now uses G1 without NewRatio. The guarded hosted heap remains
10 GiB, with two native compiler workers on the same 14 GiB runner. Local
4/5 GiB defaults remain; 10 GiB is rejected below 12 GiB physical RAM. The
application native runtime collector is unchanged. `test_builder_heap.sh`
retains the same objects with a 256 MiB bound: the old Parallel/NewRatio=7
policy throws OOM, while the production G1 arguments pass. This synthetic
retention test is not a full-compiler reproduction. `test_ios_toolchain.sh`
also passes actual small ARM64/iOS compilation, archiving and independent
linking with the G1 builder (`build/ios-abi-JTL26v`).

The product wait is now 210 minutes inside a 215-minute job, covering the
native job's 210-minute maximum rather than expiring at the compiler's
180-minute step boundary. Increasing the wait is not the compiler fix.

## Runtime dependency failures

- **Token metadata:** real `TokenRepository.loadMtgTokens` failed natively
  because root `tokens-database.txt` was excluded. The exact resource pattern
  is added, without widening unrelated resource access. Native/JVM comparison
  passes for all 2,740 rows and Saproling metadata (`build/token-native-sp0C9E`).
- **Card names and metadata:** the fresh original repository creates an empty
  desktop database; `ChooseACardNameEffect.TypeOfName.ALL.makeChoiceObject()`
  then fails. Checked generated platform copies replace base repository reads
  with bundled immutable metadata and fail explicitly for desktop mutations.
  Build-time export retains original CardScanner and SQL queries in isolated
  in-memory H2 with the original IGNORECASE setting. The upstream checkout is
  not rewritten. The export has 92,166 printings, 92,738 rows including halves,
  and 33,070 names; original category queries provide all nine naming sets.
- **AI diagnostics:** upstream timed simulation may consume an
  ExecutionException. The mobile adapter captures the original failure in the
  existing bounded private diagnostic channel before rethrowing it unchanged.
  Cancellation/closing does not publish a spurious report. Existing worker
  counting and cleanup remain in `finally`.

`RealAIDiagnosticsTests` and `RealCardRepositoryTests` were observed failing
against old adapter bytecode and now pass against the new implementation.
The latter exercises actual factories, split and alternate-face lookups,
criteria, defensive copies, naming-payload bounds and no database creation.
`MobileCardCriteriaTests` passes 326 comparisons against original H2 queries,
including colors, persisted sort columns, SQL LIKE escapes and pagination.
Unsupported original modal-column queries and pathological pagination fail
explicitly rather than silently returning unrelated results. These are JVM
checks, not native gameplay acceptance.

Full `build_jvm.sh` and `test_real_engine.sh` pass with the new adapter, including
completed two-/four-seat and token/mulligan games, rules/privacy/control tests,
real MAD lifecycle and cancellation checks.
The Python tooling suite passes 166 tests. No iOS runtime result follows from
those JVM/fixture results.

The 114 portable app tests also pass. Their fresh Swift-exported Token Triumph,
First Flight, Grave Danger, Chaos Incarnate and Draconic Destruction decks each
pass real Commander validation and reach the first prompt through
`test_ios_precons.py`. This remains JVM, not native startup evidence.

The small real host-native catalogue check also passes at
`build/card-catalogue-native-744Kt3`: all nine naming categories, exact metadata
fields/enums, printing/split lookups, filters, sorting/pagination and defensive
copies match the JVM results. Its production-derived reflection subset includes
CardInfo fields and only the zero-argument decoding constructor. It does not
install factories, start an engine, or execute iOS code.

## Artifact boundary

Native input snapshots now hash class files **and** generated resources.
Candidate artifacts carry catalogue resources/report and the checked repository
patch manifest. Source equivalence includes platform sources and export scripts.
The full native artifact must be newly produced; the previously staged
2026091203 library cannot verify this candidate. Native resource/reflection
execution, full-engine compilation, actual app linkage/signing and TestFlight
processing remain distinct gates. See [current status](LOCAL_CONTINUATION_STATUS.md)
for the latest completed stages. No full-card or phone acceptance is claimed.
