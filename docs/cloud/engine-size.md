# What fills the native engine, and what can safely go

C4, game improvement program Phase 3 (docs/GAME_IMPROVEMENT_PROGRAM.md). Engine of Android run
[37683328246](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/37683328246) (`0546f91`,
XMage `dac400b`): `.text` 202,023,936 B of AOT code and `.svm_heap` 167,301,120 B of image heap. iOS has
the same heap (167,280,640 B) and about 10 MB more `__text`, which includes the Swift app
(docs/audits/APP_AUDIT_2026-10.md). Nothing here was measured on a phone.

## Why there was no build report

- GraalVM 22.1 (Gluon 22.1.0.1) has no `--emit build-report` (it arrived in 23+) and no `-Os`;
  `-O` takes only `b`, `0`, `1`, `2` and the build uses the default `-O2`.
- Its usual "Top 10 packages in code area / object types in image heap" table never prints for us.
  Gluon adds `-H:+ExitAfterRelocatableImageWrite` to every cross-compile (Android on Linux, iOS on a Mac),
  and native-image returns right after writing the object file, before the table.
- Options that still work despite the early exit: `-H:+PrintHeapHistogram`,
  `-H:+PrintImageHeapPartitionSizes`, `-H:+PrintClassInitialization` and
  `-H:DashboardDump=<path> -H:+DashboardHeap -H:+DashboardCode -H:+DashboardJson` (heap and code size per
  class and method). These were read from the vm-22.1.0 sources, not run.

So this report takes the code apart from the unstripped library's symbol table, which needs no rebuild,
and adds an opt-in heap report for the next native build (below).

## Code: 202 MB, by owner (measured)

`.github/workflows/magicmobile-native-code-sizes.yml` downloads an `android-native-symbols-<sha>` artifact
and runs `packages/ondevice-engine/scripts/native_code_sizes.py` on it. GraalVM names each method
`<SimpleClass>_<method>_<sha1>` without its package, so the script maps simple names to packages from the
pinned XMage sources, this package's sources, the JDK 17 class list and the library jars. Run
[38730356046](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/38730356046): 257,057 sized
function symbols, 202,020,484 B (the whole `.text`).

| Owner | MB | Share |
|---|---|---|
| XMage card classes (`mage.cards.<letter>`, 48,739 classes: cards and their effect classes) | 117.7 | 58.3% |
| XMage set classes (`mage.sets`, 589 classes) | 27.7 | 13.7% |
| MagicMobile generated card factory (256 `GeneratedCardBucket` classes) | 18.7 | 9.3% |
| JDK | 11.2 | 5.5% |
| XMage abilities, effects, game, filters, targets, watchers, views, AI and other | 14.2 | 7.0% |
| H2 database | 3.2 | 1.6% |
| ambiguous simple names (`Parser`, `Function`, `Pattern`) | 2.5 | 1.2% |
| GraalVM reflection accessors, allocation factories, JNI wrappers, runtime and GC | 4.0 | 2.0% |
| protobuf | 1.3 | 0.6% |
| MagicMobile adapter | 0.4 | 0.2% |
| Gson, ORMLite, Guava, reload4j, JBoss, other libraries | 1.2 | 0.6% |

Card-class code by method: constructors 66.5 MB, `copy` 28.6 MB, `apply` 10.3 MB, static initialisers
7.0 MB, everything else under 1 MB each. A card class averages 2.4 KB of code. The largest set classes
are the promo and Secret Lair lists (`MagicOnlinePromos` 702 KB, `SecretLairDrop` 659 KB); a set class's
code is its constructor, which builds one `SetCardInfo` per printing. JDK code is mostly TLS and crypto
(`sun.security.ssl` 1.7 MB, `com.sun.crypto.provider` 0.7 MB, `sun.security.x509` 0.5 MB, certpath and
providers 0.6 MB): Gluon adds `-H:EnableURLProtocols=http,https`, and the engine opens no connection.

## Image heap: 167 MB (partly known)

`mage` and `io.magicmobile` are initialised at run time, so XMage's card, set and filter statics are not
in the heap. Known parts:

| Part | Size | Evidence |
|---|---|---|
| Vtables (one 8-byte slot per virtual method per class; these are the 4.5 M load-time relocations) | at least 34 MB | relocation count (audit, docs/cloud/c2-relocations.md) |
| Embedded resources: card catalogue `card-metadata.jsonl.gz` 7.2 MB and `card-names.json.gz` 1.1 MB, plus 0.3 MB of others | 8.6 MB | build log `NATIVE-RESOURCES` |
| Reflection and serialization registration for 52,566 classes (the save/resume checkpoint feature registers 50,816 names) | not measured | build log |
| Code metadata for 257k methods (frame, deoptimisation and exception tables), strings, locales (`-H:+IncludeAllLocales`), charsets (Gluon's `-H:+AddAllCharsets`) | not measured | |

No H2 database file, no card images and no `.class` files are in the image (`stage_native.py` refuses
class headers).

## Run-time memory found along the way (measured on the JVM)

`GeneratedSetRegistry.install()` runs when the engine starts and constructs all 589 XMage set classes.
They keep **93,420 `SetCardInfo` objects, 24.1 MB of retained Java heap**, and the install took 10.5 s on a
cold JVM in the cloud (`SetMemory` probe: 589 sets, `-Xmx1g`, serial GC). The native image is
ahead-of-time compiled and uses compressed references, so its numbers will be lower, but this is phone RAM
and start-up time paid on every launch for data the embedded catalogue already holds (set code, collector
number and card class for every printing). The phone figure needs a device measurement.

## Proposed cuts

Savings are estimates unless marked measured. "Risk" is the risk to behaviour. Cards are never removed:
the no-pruning rule (packages/ondevice-engine/docs/BUILD_AND_DEVICE_GATES.md) stands, and only 539 card
classes (1.7%, about 2 MB) are exclusive to sets that aren't Commander-legal anyway.

| # | Cut | Saves | Risk | Status |
|---|---|---|---|---|
| 1 | **Table-driven generated card factory.** Each bucket binary-searches a sorted name table and switches on an int, with one `CardSetInfo` check per bucket, instead of a string switch with an inlined `String.equals` and a throw site per card | est. 8–15 MB code (bytecode 4.55 to 3.61 MB; 134 `equals` sites per bucket removed) | low: same constructor for all 32,498 catalogue classes, checked against the old factory with and without `CardSetInfo`; covered by every real-JVM game | **done** (`RegistryExporter.java`) |
| 2 | **Sets from the catalogue.** Answer `DeckLoader` and `ViewProjector` printing lookups (set code and number to card class) from `MobileCardCatalogue`, and register lightweight set objects (code, name, type, release date, no card list) instead of XMage's set classes | up to 27.7 MB code (measured size of the set classes), about 24 MB of run-time heap on the JVM (measured), and the set install at start-up | medium: an upstream patch in `prepare_mobile_repository.py` style; anything that reads a set's card list (boosters, Momir, `MobileCardCatalogue.boosterSets`) must move to the catalogue first | **built, JVM-verified, not natively measured** (release C draft): a set catalogue resource replaces the set classes; 492 of 589 (5.7 of 8.3 MB bytecode) unreferenced, the 95 with their own booster code kept for Booster Tutor; JVM heap after start 26.5 → 4.5 MB (packages/ondevice-engine/docs/NATIVE_METADATA.md) |
| 3 | **Make H2 and ORMLite JDBC unreachable.** Patch the remaining database paths of the runtime repositories (`checkDatabaseHealthAndFix` and friends) to throw like the others, drop `META-INF/services/java.sql.Driver` from the resource config, then leave `h2` and `ormlite-jdbc` off the native classpath | about 3.5 MB code plus their heap | low to medium: confirm with `-H:ReportAnalysisForbiddenType=org.h2.Driver:Reachable` first (it fails the build and prints the path) | **built, not natively measured**: the path was `mage.db.EntityManager`'s initializer (registered for checkpoints); left out, no JDBC driver registered, forbidden-type guard |
| 4 | **No TLS.** Find what keeps `sun.security.ssl` reachable (`-H:ReportAnalysisForbiddenType=sun.security.ssl.SSLContextImpl:Reachable`); then override Gluon's URL protocols or cut that path | up to 3.5 MB code | low: the engine opens no network connection | **built, not natively measured**: `-H:DisableURLProtocols=http,https` overrides Gluon's option |
| 5 | **protobuf out of checkpoints.** The generated `mage.game.result.ResultProtos` messages (tournament results) are Serializable, so the checkpoint feature registers them; exclude them and other never-checkpointed packages (`mage.remote`, `mage.collectors`) in `NativeReflectionExporter` | up to 1.3 MB code plus registration heap | low: `RealCheckpointTests` fails if a class a real checkpoint writes is missing from the list | **built, not natively measured**: `mage.game.result` (and `mage.db`, `mage.sets`) left out, forbidden-type guard |
| 6 | Locales and charsets: `-H:IncludeLocales=en` instead of `-H:+IncludeAllLocales`, and `-H:-AddAllCharsets` after Gluon's flag | not measured (heap) | medium: ORMLite date formatting on non-English phones was the reason for all locales; rerun `test_ormlite_native.sh` | not done: the engine formats with the phone's locale, so dropping locale data could change non-English phones; needs a device or emulator check first |
| 7 | `-O1` | perhaps 10–20% of code | high: AI think time on the phone; needs a phone | not recommended without a device |

Cuts 1 to 5 together come to roughly 45–50 MB of code (about a quarter of `.text`), plus heap and start-up
memory, before any change to the card classes themselves.

## Workflow changes on this branch

- `magicmobile-native-code-sizes.yml` (new, measurement only): runs the code breakdown on any Android
  symbols artifact (`workflow_dispatch` with `run_id` and `artifact`). It also runs on pushes to this branch
  that touch it, against run 37683328246, whose symbols artifact expires on 2026-10-21. It takes about a
  minute and builds nothing.
- `magicmobile-android.yml` and `scripts/android/build_native.sh`: a `native_reports` input
  (`MM_NATIVE_REPORTS=1`) adds the heap histogram, partition sizes, class-initialisation report and a
  dashboard dump (heap and code per class and method) to the evidence artifact. Off by default; the library
  is unchanged either way. The builder ends analysis at about 9.8 GB of its 10 GB heap, so the heavier
  analysis reports (call tree, object tree, points-to dashboard) are left out on purpose.

## How to check cut 1, and measure the heap, on the next native build

1. Dispatch `magicmobile-android.yml` on the integrated R2 source with `native_reports: true`.
2. Dispatch `magicmobile-native-code-sizes.yml` with that run's id and `android-native-symbols-<sha>`. The
   `io.magicmobile.generated (card factory)` row should drop from 18.7 MB.
3. Read `PrintHeapHistogram` in `full-native.log` and `native-reports/dashboard.dump` for the heap's
   contents, and decide cuts 2 to 6 from those numbers.
