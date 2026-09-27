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
- `lambdaCapturingTypes`: always an empty list. The pinned 22.1 parser requires both keys of
  the object form (GraalVM 21.3+ format). Proxies and serializable lambdas are refused by the
  checkpoint writer and reader, so neither is registered.

**No serializable lambdas (September 27, 2026).** The first metadata listed 15 lambda capturing
classes (the 13 upstream classes below, `Checkpoints` for its self-test, and
`XmageEngine$Running` for its `Listener` method references). Android run
[36287088288](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36287088288) on
`9b26186` then failed 20 s into image generation, in `[1/7] Initializing`:
`Serializable lambda class must contain the writeReplace method`. GraalVM 22.1.0.1's
`SerializationFeature.beforeAnalysis` parses every declared method and constructor of each
capturing class and requires `writeReplace` on every lambda class it finds there, without
checking whether that lambda is serializable (read from the `vm-22.1.0.1` source). `Checkpoints` (its
`ObjectInputFilter` lambda) and `XmageEngine$Running` (its thread factory and mailbox callbacks)
create such lambdas, so any metadata listing them cannot build. Instead, nothing needs a
serializable lambda any more:

- `scripts/prepare_upstream.py` (`LAMBDA_PATCHES`, reviewed exact-text patches with pinned blob
  IDs in `upstream.lock.json`) turns each Serializable `Condition`/`Predicate` lambda or method
  reference in the 13 classes that declared `$deserializeLambda$` at `4825513` into a named enum
  singleton. Where upstream referenced a static method (`...Watcher::checkSpell` and similar),
  the enum's `apply` calls that same method; the three inline lambdas (For the Ancestors,
  Shaile's filter, Surge Engine's ability condition) moved verbatim into `apply`. The classes:
  `ReconfigureUnattachAbility` (Mage core) and, in Mage.Sets, `ArcaneBombardment`,
  `CaptainNghathrod`, `ForTheAncestorsEffect`, `HotheadedGiant`,
  `LeylineImmersionConditionalMana`, `MaarikaBrutalGladiator`, `NeyaliSunsVanguardEffect`,
  `SailorsBaneValue`, `ShaileDeanOfRadiance`, `SurgeEngineAbility`, `SwordswornCavalier`,
  `TalarasBattalion`. `Condition.getManaText()` is the class simple name, which Leyline
  Immersion's mana shows and `ManaOptions` uses as a de-duplication key: it becomes the stable
  `LeylineImmersionSpellCondition`, still one name per condition, instead of a generated lambda
  class name. A restored enum is the same object, so `ConditionalMana.equals` still holds.
- `Checkpoints` round-trips a named Serializable `ProbeCondition`; `XmageEngine$Running` uses
  named `Listener` classes (kept only in upstream's transient event sources).
- The checkpoint allowlist no longer contains `java.lang.invoke.SerializedLambda`, so the writer
  refuses any serializable lambda and the reader rejects one in a stream.
- `NativeReflectionExporter` fails, before writing `serialization-config.json`, if any scanned
  engine, card, plugin or adapter class still declares `$deserializeLambda$` (for example after
  an upstream bump), naming the classes. Its `LAMBDA_SAFE` map, empty, would only admit a class
  with a reviewed reason that its lambda never reaches a checkpoint; even then it is not a
  capturing type.

The JVM export at upstream `4825513` registers **48,730 types** (48,639 engine classes, of
which 48,544 are concrete; 84 JDK types; 7 array types) and **no lambda capturing classes**.
48,586 engine classes declare no `serialVersionUID`, so their stream identity is computed at
runtime from reflective class data (340,962 declared members across the registered classes).
The export takes about 14 s and 0.56 GB RSS on the JVM. A probe class with a serializable
lambda passed as an extra `--serialization` directory makes it fail and write no file.

`build_native_ios.sh` (every reflection profile) and `scripts/android/build_native.sh` run the
exporter and pass the file as `-Dnative.serialization.config`. Probe and toolchain builds use
`native/gluon/probes/empty-serialization-config.json`. The far-call workflow keeps the file in
the hash-covered native candidate, and `verify_native_candidate.py` requires it.

**Registration through `CheckpointSerializationFeature`, not `-H:SerializationConfigurationFiles`
(September 27, 2026).** With the lambda fix, Android run
[36289659903](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36289659903)
(`32e05d6`) passed `[1/7] Initializing` (20 s), then `[2/7] Performing analysis` had not finished
when the job's 120-minute limit cancelled it, 110 minutes later. Before save/resume the whole
native step took about 10 minutes (run 36091168558). GraalVM 22.1's serialization configuration
does more than serialization needs: for every entry, `SerializationBuilder.addReflections`
registers all declared constructors and methods as reflectively *invocable*, and
`ReflectionFeature` compiles a `ReflectiveInvokeMethod` stub for each as an analysis root (read
from the `vm-22.1.0.1` source). Across the checkpoint types that is roughly 95,000 constructors
and 220,000 methods.

The Gluon POM therefore no longer passes `-H:SerializationConfigurationFiles`. Full builds enable
`native/gluon/.../CheckpointSerializationFeature.java` (`-Dnative.checkpoint.feature=--features=...`),
which reads the same exporter file (`-Dmagicmobile.checkpoint.serialization`) and registers, for each
listed class and its Serializable superclasses, only what `ObjectStreamClass` and
`ReflectionFactory` use at run time:

- the class (so `Class.forName` resolves it) and its declared fields, which gives default and
  `serialPersistentFields`, `serialVersionUID` and unsafe offsets;
- its declared constructors as *queried*, for the accessible-superclass-constructor check;
- only the `writeObject`, `readObject`, `readObjectNoData`, `writeReplace` and `readResolve` hooks it
  declares, as invocable;
- the serialization constructor accessor, generated by GraalVM's own `SerializationBuilder`
  (called reflectively, exactly as for a configuration entry, including its stub for abstract
  classes), plus that constructor.

A JVM dry run over the exporter output, with a stand-in builder that applies GraalVM's rules,
registers 48,745 classes (15 JDK superclasses such as `java.util.EnumSet` join the list), 46,900
constructor accessors, 26,356 fields, 95,522 queried constructors and 159 hooks in 16 s. No class
lacks a valid serialization constructor. The only invocable members are the hooks, the target
constructors (almost all `Object()`) and `computeDefaultSUID`, so about 200 stubs remain instead of
about 315,000. Default `serialVersionUID`s are computed from this metadata. That differs from a
JVM's value, but a checkpoint is only read by the build that wrote it (`engineBuild`). The Android
evidence artifact now also keeps `builder-gc.log`.

**Risk.** The feature calls GraalVM-internal code (`SerializationBuilder.addConstructorAccessor`,
package-private, through reflection), valid for the pinned 22.1.0.1 builder, which runs on the
classpath. A different GraalVM needs this reviewed again. Whether Java serialization then works in
the native image is proven only by the runtime self-test (`capabilities.saveResume`) on a device.
The Android job builds the image and APK but does not run them.

**Capability probe.** `capabilities.saveResume` is `true` only after a runtime self-test
(a real Mage.Sets card, a game zone, collections, `EnumSet`, the RNG and a named Serializable
`Condition` through the production writer, SHA-256, filter and reader). A native image built without
this metadata, or one where serialization fails for another reason, reports `false`, keeps
the failure in `diagnostics`, and refuses `create` with a checkpoint and `restore` with
`checkpoint_unavailable`.

Gzip makes the JDK `Deflater` reachable. iOS already links system zlib (`-lz`); Android's
staging check now also allows the zlib `deflate*` entry points next to the `inflate*` ones.
