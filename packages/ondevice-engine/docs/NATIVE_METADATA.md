# Targeted reflection diagnostic

`engine/tools/NativeReflectionExporter.java` generates an **experimental** alternative to the handoff's blanket reflection metadata. It does not alter the full generated card factory or printing catalogue.

The initial native attempt registered 48,626 Mage types' constructors/fields, including `mage.remote.SessionImpl`, even though the in-process application does not use server sessions. It reached active Native Image analysis but was stopped at the 15-minute diagnostic bound under memory pressure. That is not an OOM or unsupported-platform verdict.

The narrower manifest is derived from real compiled types:

- Field metadata for the `GameView`/`AbilityPickerView` client DTO graph, including generic collection elements, inherited fields, and runtime card/command-view subclasses.
- Constructors and fields for every actual `Watcher` subtype and its Mage superclasses, because upstream `Watcher.copy()` uses reflection. Anonymous/nonpublic types are not silently skipped.
- Constructors for all concrete token, plane and emblem subtypes needed by upstream name-based lookup.
- Fatal linkage failures and explicit checks preventing accidental `SessionImpl` or `GameState` roots. No missing card/factory fallback is introduced.

The first export inspected 49,308 classes including 32,313 Card types, 456 Watcher types and 928 concrete dynamic token/plane/emblem types. It emitted 1,429 reflection entries and 45 client DTO types. The static catalogue remains 32,275 generated card factories; inspected types include abstract and non-factory classes.

This tests whether unnecessary reflection roots explain native-build cost. It does **not** prove complete native reflection, serialization, JNI, resources, or full-card gameplay compatibility. Genuine native execution and the real regression suites remain required. The original broad metadata remains available for comparison.

The policy follows the pinned compiler's [reflection documentation](https://www.graalvm.org/22.1/reference-manual/native-image/Reflection/): reflection configuration affects reachability and must describe actual dynamic accesses.

## Explicit enum initialization diagnostic

Both broad and targeted reflection runs reached analysis but were stopped after 15 minutes without a compiler incompatibility or OOM report. A third, separate variable is available as `MM_NATIVE_INIT_PROFILE=reviewed-enums`: 18 explicitly listed enums whose pinned source initializers create only enum instances with primitive/String fields. Methods may use runtime game objects, but initializers do not. `Outcome` has a non-final private boolean, assigned only by its constructor and never mutated afterward in the pinned source.

This is deliberately not a `mage.constants` package override: `AffinityType` creates filters/hints, `SubType` initializes a logger and collections, `BeholdType` contains a mutable cache, and other enums construct predicate objects. Those remain runtime-initialized, as do all mutable engine, card and factory classes. The allowlist is `native/gluon/buildtime-enums.txt`; its hash is recorded in each run. It changes neither the card catalogue nor the rules source.

The testable prediction is that removing repeated runtime initialization checks for these shared enums reduces analysis work. It is an experiment, not an accepted performance fix or native-compatibility claim. [Pinned Graal class-initialization semantics](https://www.graalvm.org/22.1/reference-manual/native-image/ClassInitialization/) prohibit runtime-initialized instances in the image heap; a successful compile and real native regression remain necessary.

The first run using this profile (`ios-native-ez6E3n`) also snapshots the now-regression-tested turn-control adapter and versioned shutdown entrypoint, unlike the earlier frozen pre-control baseline. Its elapsed time therefore cannot establish an isolated enum-initialization speedup. It is a current-candidate build diagnostic; causal performance claims would need both profiles run against identical class snapshots.

## ORMLite annotations and runtime defaults

`ios-native-ez6E3n` ended with 41 concrete image-heap errors after 201.3 seconds of analysis. ORMLite 5.7's annotation `DataType` enum retains converter singleton instances, but the default compiler policy initializes those converters at runtime. `native/gluon/probes/OrmLiteInitProbe.java` reproduces the same class of failure in about six seconds, without XMage on its classpath. Marking the entire ORMLite package runtime-initialized still failed that probe.

Initializing only `com.j256.ormlite.field.types` at build time permits compilation, but the first real native execution caught frozen builder timezone in `DateStringFormatConfig`. Its [upstream constructor](https://github.com/j256/ormlite-core/blob/ormlite-core-5.7/src/main/java/com/j256/ormlite/field/types/DateStringFormatConfig.java) eagerly constructs `SimpleDateFormat`. The native-only substitution resets that field and lazily constructs a formatter at first runtime use, synchronizes initialization, and retains clone-per-caller behavior. Runtime-created configs keep the original constructor behavior. This also covers `SqlDateType`'s separate template without changing config-object identity. Optional Joda reflection caches are reset; that does not provide missing Joda runtime metadata.

`MM_NATIVE_ORM_PROFILE=runtime-defaults` opts into that converter policy and substitution. It does not initialize database connections, ORMLite's registration manager, mutable Mage state, or game rules at build time. All locale data is included because the compiler's default locale subset otherwise produced a French JVM/native mismatch. The expected semantic boundary is that compiled-in formatter templates capture defaults at first runtime use, not on the build Mac.

`bash scripts/test_ormlite_native.sh` verifies both failure reproductions and native/JVM equality under UTC/Tokyo and English/French. Each case checks SQL dates, 800 concurrent formatter accesses, new runtime configs and clone isolation. `evidence/ormlite-check-55Hbub.log` records the first complete passing run. This is a macOS native dependency test only; full XMage, JDBC/H2 operations, iOS execution and full locale coverage remain separate gates.

## Save/resume serialization metadata (September 26, 2026)

Save/resume checkpoints ([PROTOCOL.md](PROTOCOL.md)) are Java serialization. A native image
can only write and read classes registered with `-H:SerializationConfigurationFiles`, and a
checkpoint may contain any card, ability, effect, watcher, filter, target or token, not just
the classes one game used. `NativeReflectionExporter ... --serialization EXTRA_DIRS...` therefore
writes `serialization-config.json` next to `reflect-config.json`:

- `types`: every Serializable, non-interface class under `mage.` and `io.magicmobile.xmage.`
  in Mage, Mage.Sets, Mage.Common, the built plugin modules and the adapter (`build/engine`),
  the JDK allowlist read from `Checkpoints.jdkTypes()`, and the array types of serializable
  fields.
- `lambdaCapturingTypes`: classes with serializable lambdas. Upstream stores method
  references in Serializable `Condition` fields (Reconfigure and 12 cards); the checkpoint
  self-test uses one in `Checkpoints` too. The object form with `types` and
  `lambdaCapturingTypes` is the GraalVM 21.3+ format; the pinned 22.1 parser is expected to
  accept it (read, not yet exercised by a native build). Proxies are refused, so none are listed.

The JVM export at upstream `4825513` registers **48,715 types** (48,623 engine classes, of
which 48,528 are concrete; 85 JDK types; 7 array types) and **15 lambda capturing classes**
(13 upstream, `Checkpoints`, and `XmageEngine$Running`, whose listener method references live
only in transient event sources). 48,571 engine classes declare no `serialVersionUID`, so
their stream identity is computed at runtime from reflective class data (340,868 declared
members across the registered classes). The export takes about 13 s and 0.6 GB on the JVM.

`build_native_ios.sh` (every reflection profile) and `scripts/android/build_native.sh` run the
exporter and pass the file as `-Dnative.serialization.config`; the Gluon POM adds the
`-H:SerializationConfigurationFiles` argument. Probe and toolchain builds use
`native/gluon/probes/empty-serialization-config.json`. The far-call workflow keeps the file in
the hash-covered native candidate, and `verify_native_candidate.py` requires it.

**Risk, unmeasured.** This is the same order of size as the broad reflection profile (48,826
entries) that the targeted profile replaced because analysis was too slow for the local
builder. GraalVM also generates a serialization constructor accessor per registered class.
Expect higher builder heap, analysis time and image size; whether the 10 GB hosted profile
and the 180-minute step are enough is the first thing the next ARM64 run must show. No
native-image was run locally.

**Capability probe.** `capabilities.saveResume` is `true` only after a runtime self-test
(a real Mage.Sets card, a game zone, collections, `EnumSet`, the RNG and a serializable lambda
through the production writer, SHA-256, filter and reader). A native image built without
this metadata, or one where serialization fails for another reason, reports `false`, keeps
the failure in `diagnostics`, and refuses `create` with a checkpoint and `restore` with
`checkpoint_unavailable`.

Gzip makes the JDK `Deflater` reachable. iOS already links system zlib (`-lz`); Android's
staging check now also allows the zlib `deflate*` entry points next to the `inflate*` ones.
