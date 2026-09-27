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
  the JDK allowlist read from `Checkpoints.jdkTypes()`, and (since September 27) every other
  class a stream can name: Serializable superclasses, array types and the classes held by
  Class-typed fields (see
  [Stream class resolution](#stream-class-resolution-in-the-native-image-september-27-2026)).
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

The JVM export at upstream `4825513` registers **48,723 types** (48,632 engine classes, of
which 48,539 are concrete; 84 JDK types; 7 array types) and **no lambda capturing classes**. It
leaves out the 7 Serializable Swing client components in Mage.Common (`MageCard`, `MagePermanent`,
`TextPopup`, `ImagePanel`, `MageTable`, `MageTable$1`, `TimeAgoTableCellRenderer`; see run 3 below),
listed in `report.json` as `excludedDesktopUiClasses`. 48,581 engine classes declare no
`serialVersionUID`, so their stream identity is computed at runtime from reflective class data
(340,864 declared members across the registered classes).
The export takes about 14 s and 0.56 GB RSS on the JVM. A probe class with a serializable
lambda passed as an extra `--serialization` directory makes it fail and write no file.

`build_native_ios.sh` (every reflection profile) and `scripts/android/build_native.sh` run the
exporter and pass the file as `-Dnative.serialization.config`. Probe and toolchain builds use
`native/gluon/probes/empty-serialization-config.json`. The far-call workflow keeps the file in
the hash-covered native candidate, and `verify_native_candidate.py` requires it.

**Registration through `CheckpointSerializationFeature`, not `-H:SerializationConfigurationFiles`
(September 27, 2026).** The Android runs on this branch measured what GraalVM 22.1's own
serialization support costs for the checkpoint types, and what the feature below costs. Before save/resume, the whole native step took 8 min 47 s: analysis
ran 309 s and ended at 8.77 GB of the 10 GB builder heap, with 67,055 classes and 359,842 methods
reachable (run 36091168558).

1. Run [36289659903](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36289659903)
   (`32e05d6`, configuration file) passed `[1/7] Initializing` with the lambda fix. Then
   `[2/7] Performing analysis` had not finished when the job's 120-minute limit cancelled it,
   110 minutes later. For every entry, `SerializationBuilder.addReflections` registers all declared
   constructors and methods as reflectively *invocable*, and `ReflectionFeature` compiles a
   `ReflectiveInvokeMethod` stub for each as an analysis root (read from the `vm-22.1.0.1` source).
   Here that is roughly 95,000 constructors and 220,000 methods.
2. Run [36296135786](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36296135786)
   (`a23143c`, first version of the feature, without those invocable members) ran out of builder
   heap in analysis: `OutOfMemoryError` after 1,369 s, 71% of the time in GC. The heap was full
   from minute 7. Classes rose to 110,066 (from 67,055), because GraalVM generates one
   serialization-constructor accessor class per concrete class (`MethodAccessorGenerator`), about
   43,000 here.
3. Run [36298334924](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36298334924)
   (`dd683d2`, shared accessor below) **finished analysis**: 943 s at 9.92 GB, 17% of the time in
   GC, with 71,748 classes and 396,899 methods reachable. It then failed on
   `Unsupported type sun.awt.X11.XBaseWindow is reachable`, in 14 methods. The exporter had listed
   Mage.Common's Serializable Swing client components, and registering them (and their
   `JComponent`/`Component` superclasses and hooks) made Swing event dispatch and X11 input
   methods reachable. The exporter now leaves out every `java.awt.Component` subclass, since a
   headless game never holds one. The feature fails the build if a `java.awt`/`javax.swing`
   class reaches it.
4. Run [36299703566](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36299703566)
   (`f0f78c3`) **succeeded**. That covers the real-engine JVM tests, the ARM64 image, the staging
   checks and the native-linked APK (artifacts `android-full-native-f0f78c3…` and
   `MagicMobile-Android-NATIVE-APK-f0f78c3…`). Image generation took 20 min 39 s against 8 min 47 s
   before save/resume:

   | Stage | Time | Heap |
   | --- | --- | --- |
   | Analysis | 783 s | 9.75 GB |
   | Building universe | 86 s | 9.92 GB |
   | Compiling | 247 s | 8.49 GB |

   Peak RSS was 12.16 GB. 68,886 classes and 382,051 methods were reachable (from 67,055 and
   359,842). Code grew to 201 MB (from 193 MB), and the far-call pass inserted 216,864 veneers.

The Gluon POM therefore no longer passes `-H:SerializationConfigurationFiles`. Full builds enable
`native/gluon/.../CheckpointSerializationFeature.java` (`-Dnative.checkpoint.feature=--features=...`),
which reads the same exporter file (`-Dmagicmobile.checkpoint.serialization`). For each listed class
and its Serializable superclasses, it registers only what `ObjectStreamClass` and
`ReflectionFactory` use at run time:

- **Class and fields.** The class itself, so `Class.forName` resolves it. Only its serializable
  instance fields (non-static, non-transient, or every instance field when it declares
  `serialPersistentFields`), plus `serialVersionUID` and `serialPersistentFields`. Card classes'
  static filters are not made unsafe-accessed.
- **Hooks.** The `writeObject`, `readObject`, `readObjectNoData`, `writeReplace` and `readResolve`
  methods it declares, as invocable.
- **Constructors.** As *queried*, the constructors of every direct superclass (the JDK's
  accessible-superclass-constructor check), and the no-argument constructor serialization runs.
- **Serialization constructor accessor.** For a concrete class whose first non-Serializable
  superclass is `Object`, the accessor is an instance of one shared class,
  `jdk.internal.reflect.MobileCheckpointConstructorAccessor` (`native/gluon/src/main/java-base`).
  The build scripts compile it against `java.base`; the feature defines it with
  `MethodHandles.privateLookupIn` (`-J--add-opens=java.base/jdk.internal.reflect=ALL-UNNAMED`) and
  registers the instances in GraalVM's `SerializationSupport`. It allocates the class with
  `Unsafe.allocateInstance`, which is equivalent because `Object()` does nothing. Other classes
  (abstract, `Externalizable`, or with another non-Serializable superclass such as `AbstractMap`)
  still use GraalVM's `SerializationBuilder.addConstructorAccessor`, called reflectively. Abstract
  classes share its single stub accessor.

A JVM dry run over the exporter output, with stand-ins that apply GraalVM's rules, registers:

- 48,729 classes (6 superclasses such as `java.util.EnumSet`, `java.util.EventObject` and
  protobuf's `GeneratedMessageV3` join the list);
- 46,700 shared allocating accessors, from one class, and 184 GraalVM accessors;
- 5,540 fields (from 26,356 with all declared fields);
- 148 hooks;
- 1,232 queried constructors on 374 superclasses (from 95,522 with all constructors).

That run allocated one instance of each of the 46,700 classes through its shared accessor. It also
confirmed that for every one of them the JDK's serialization constructor is `Object()`. No class
lacks a valid serialization constructor. Default `serialVersionUID`s are computed from this
metadata. That differs from a JVM's value, but a checkpoint is only read by the build that wrote it
(`engineBuild`). The Android evidence artifact now also keeps `builder-gc.log`.

**Heap headroom is small.** Analysis and universe building peaked within 0.3 GB of the 10 GB
builder heap, the most a 16 GB hosted runner allows. Growth in upstream cards or engine code may
need more builder memory or a smaller class list. The iOS far-call build uses the same 10 GB heap on
a different runner and compiler patch; it is a separate gate, not shown by this run.

**Risk.** The feature relies on GraalVM internals that are valid for the pinned 22.1.0.1 builder,
which runs on the classpath: the package-private `SerializationBuilder.addConstructorAccessor`, the
`SerializationSupport` registry, and SVM's `MethodAccessorGenerator` substitution, which casts the
registry value to `SerializationConstructorAccessorImpl`. It also defines a class in `java.base`
while the image builds. A different GraalVM needs this reviewed again. Whether Java serialization
then works in the native image is proven only by the runtime self-test (`capabilities.saveResume`)
on a device. The Android job builds the image and APK but does not run them.

**Capability probe.** `capabilities.saveResume` is `true` only after a runtime self-test
(a real Mage.Sets card, a game zone, collections, `EnumSet`, the RNG and a named Serializable
`Condition` through the production writer, SHA-256, filter and reader). A native image built without
this metadata, or one where serialization fails for another reason, reports `false`, keeps
the failure in `diagnostics`, and refuses `create` with a checkpoint and `restore` with
`checkpoint_unavailable`.

Gzip makes the JDK `Deflater` reachable. iOS already links system zlib (`-lz`); Android's
staging check now also allows the zlib `deflate*` entry points next to the `inflate*` ones.

## Stream class resolution in the native image (September 27, 2026)

The first native engine that built with the metadata above (Android run
[36302037548](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36302037548), `dd9f869`)
reported `saveResume: false` on the Android emulator. Its self-test wrote the probe but could not
read it back: `java.lang.ClassNotFoundException: [Ljava.lang.Enum;` from `Class.forName` in
`ObjectInputStream.resolveClass`, while reading an `EnumSet$SerializationProxy` (whose `elements`
field is an `Enum[]`). A JVM resolves any class; the native image only resolves what was registered.

**How the pinned builder resolves stream classes.** `ObjectInputStream.resolveClass` calls
`Class.forName(name, false, loader)`. In 22.1.0.1 that is `DynamicHub.forName`, which looks the name
up in `ClassForNameSupport`. That map is filled by `ReflectionDataBuilder.processClass`, which calls
`ClassForNameSupport.registerClass` for every class registered for reflection
(`RuntimeReflection.register`), arrays included (read from the `vm-22.1.0.1` source). So every class
descriptor a stream can contain (object classes, superclasses, enums, arrays and the classes of
`Class` objects) needs a reflection registration of its own, whether or not it has serialization
metadata. `CheckpointSerializationFeature` now registers every listed name that way: arrays and
interfaces (`resolvable only`) get just that, and the others also get the serialization metadata
described above.

**Finding every gap at once, on the JVM.** `Checkpoints.classObserver` (null in production) sees
each class a checkpoint stream writes as a class descriptor (the writer's `annotateClass`) and each
class a read resolves or gets back from `readResolve` (input filter calls with a negative array
length; the JDK collections' `checkArray` pre-checks are not stream classes). `RealCheckpointTests`
records these in every process: the self-test, the named-condition round trips, all three game
scenarios and every fresh-JVM restore, which saves again on request and plays to the end. It then
requires each of them in `serialization-config.json`, read the way the feature reads it.
`test_real_engine.sh` exports that file first, with the same arguments as the native builds
(`build/native-metadata-check`, about 18 s). Primitive classes are exempt: `ObjectInputStream`
resolves them itself.

Against the previous exporter, the check found exactly two missing classes among the 933 that the
run's streams used:

- `[Ljava.lang.Enum;`: the `elements` field of `java.util.EnumSet$SerializationProxy` (the
  device failure). The exporter only looked at the fields of engine classes, not of the JDK types.
- `[Lmage.filter.predicate.Predicate;`: `Predicates.and(a, b)` keeps `Arrays.asList(a, b)`, whose
  generic varargs array is a `Predicate[]`, in the `Object[] a` field of `Arrays$ArrayList`. No
  field declares that type.

Every other stream class (engine classes and 25 JDK types, among them `EnumSet$SerializationProxy`,
`RegularEnumSet`, `Arrays$ArrayList` and `ReentrantLock$NonfairSync` with its superclasses) was
already listed. No stream held a `Class` object of an unlisted class.

**Exporter rules.** The list is closed over what a stream can name, not over what these games used:

- The Serializable superclasses of every listed class (6 more names; the feature already
  registered them).
- Array types, each with every nested array type, when the checkpoint allowlist admits the element
  type and it is not a desktop UI class:
  - the serial fields of every listed class, JDK types included. For JDK classes and any class
    declaring `serialPersistentFields`, the fields come from `ObjectStreamClass` itself (`BitSet`
    persists a `long[]`, `BigInteger` a `byte[]`, `ConcurrentHashMap` a `Segment[]`). Enum fields
    are skipped because an enum constant is written as its name;
  - every array type engine code creates: the exporter reads the class files and collects the
    operands of `anewarray`, `multianewarray` and `newarray` (JVMS 6.5). That covers generic
    varargs, `toArray(new T[0])`, `stream.toArray(T[]::new)` and enum `values()`: 1,887 types;
  - arrays of every allowlisted JDK type, which JDK code creates too (`String.split`).
- Class objects: a stream names the class that a `Class`-typed serial field holds. The exporter
  reads each such field's bound (`Class<? extends Ability>`) and lists every class literal (`ldc`)
  in engine code within a bound. Serializable ones already are; five interfaces (`Ability`,
  `ActivatedAbility`, `TriggeredAbility`, `Card`, `Permanent`) are added as resolvable only. Two
  upstream fields are raw or `Class<?>`; their bounds come from the reviewed values in
  `CLASS_FIELD_BOUNDS` (`ActivateAbilitiesAnyTimeYouCouldCastInstantEffect`: Equip, Loyalty and
  Meditate abilities; `ExpansionSet$SetCardInfo`: card classes). A new unbounded field fails the
  export and names the field.
- `writeReplace` and `readResolve`: the JDK serialization proxies and their `readResolve` results
  are on the checkpoint allowlist (`EnumSet$SerializationProxy`, `CollSer`, `RegularEnumSet`,
  `JumboEnumSet`, `ImmutableCollections$*`), so they are listed. The JVM check sees `readResolve`
  results, which for these proxies are the original classes; it cannot see the original object of
  a `writeReplace` directly.

The export now lists **50,684 names**: 48,632 engine classes, 84 JDK types, 6 superclasses, 1,957
array types (10 from serial fields, the rest created by engine or JDK code) and 5 resolvable-only
interfaces. `report.json` records the counts, the `Class` field bounds and the added classes. A JVM
dry run of the feature over this file, with stand-ins for the GraalVM registries, registers the same
serialization metadata as before (48,722 classes, 46,700 shared accessors, 184 GraalVM accessors,
5,540 fields, 148 hooks, 1,232 queried constructors), and every listed name is registered for
reflection, so for `Class.forName`.

**Native result.** Android run
[36306841573](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36306841573) (`e83eb15`)
passed: the real-engine JVM tests with the new check (931 stream classes, all listed), the ARM64
image and the native-linked APK (artifact `android-full-native-e83eb158876200f2072cd2509fd2398841b8b7b4`).
The feature printed `50684 listed types (1957 arrays, 5 resolvable only)` with the same accessor,
field and constructor counts as before (Linux's JDK has 144 hooks). Image generation took 19 min 45 s:
analysis 760 s at 9.58 GB, universe 55 s at 9.76 GB, compiling 239 s, peak RSS 12.21 GB. 67,846
classes and 382,051 methods were reachable (the same method count as `f0f78c3`), and
`libmmengine.so` grew by 28 KB: the extra array and interface registrations did not reduce the
builder's heap headroom.

On the Android emulator (API 35, `emulator-5554`), the signed release APK built from that artifact
reported `saveResume: true` with no diagnostics report. `NativeCheckpointTest` ran (it is skipped
while `saveResume` is false) and passed: a Token Triumph vs Grave Danger game checkpointed its first
priority decision (turn 1, 165,545 bytes), a new native runtime restored it in 630 ms and re-asked the
same decision. All 6 device tests passed (`scripts/android/test_device.sh`). In the app itself, a solo game killed with
`am force-stop` after HOME came back through "Resume your game?" twice: at turn 1 and at turn 2 with
a land on each side and the AI's spell on the stack, which resolved when play continued. This is an
emulator result; phones, iOS and write times on a device are separate gates.

## Embedded resources and a smaller Android engine (September 27, 2026)

`native/resource-config.json` used to include `mage/.*` and `.*\.properties$`. GraalVM embeds every
classpath file whose path matches an include pattern, so the image heap carried every XMage `.class`
file as a resource, twice over where a module's installed jar sat next to its `target/classes`
directory. The Android build 11 engine had 99,186 class-file headers (`CAFEBABE 0000 00xx`) in its
461.5 MB `.svm_heap`. The engine never reads one: a JVM run of the real suites under a tracing
system class loader (every `getResource*`/`findResource*` call, child JVMs included) saw only these
names:

- `mage/mobile/card-names.json.gz` and `mage/mobile/card-metadata.jsonl.gz` (`MobileCardCatalogue`,
  for card-name choices and repository queries);
- `tokens-database.txt` (`TokenRepository`);
- `log4j.properties`, `log4j.xml` and `META-INF/services/java.lang.System$LoggerFinder`, which are
  on no classpath entry, before or after this change.

`mage.util.JarVersion` (the only upstream code that reads a `.class` resource) is reached only from
the desktop repository and server paths that the mobile repository adapter replaces.

The configuration now names `mage/mobile/.*\.gz`, `tokens-database\.txt`, `META-INF/services/.*`
and `pennydreadful\.properties` (read only by upstream's `PennyDreadfulCommander` validator, which
the image contains but the app never uses; kept so that path cannot fail, 199 KB).
`scripts/check_native_resources.py` enumerates what a configuration embeds from the exact native
classpath (directories and jars, named as GraalVM names them). Both native builds run it before
`native-image` and stop if any `.class` file would be embedded or one of those resources would be
missing; the report lists every embedded resource. On Android, `stage_native.py` also counts
class-file headers in the built library's `.svm_heap` and fails on any.

The runtime classpath (`classpath.py`) no longer lists a reactor module's own installed
`org/mage/*/1.4.61` jar when its `target/classes` directory is present (Mage, Mage.Sets,
Mage.Common, Mage.Player.AI), and `build_jvm.sh` asks the dependency plugin for runtime scope only.
Its user property is `includeScope`; the `mdep.includeScope` spelling is silently ignored.
JUnit, AssertJ and their service files are gone.

Android also links with `-Wl,--pack-dyn-relocs=android` (build 11 had 108.0 MB of plain `RELA`
entries, 4.5 million of them relative; minSdk 26 supports Android-packed ones, RELR needs 28) and
stages the library stripped (`llvm-strip --strip-unneeded`: `.symtab` and `.strtab` go, the
dynamic symbols JNI and `dlopen` use stay and are re-verified). The unstripped library is the
separate `android-native-symbols-<sha>` artifact, paired by SHA-256 in its `symbols.json` and the
manifest (`unstrippedLibmmengineSha256`). The app's `keepDebugSymbols` now keeps an already
stripped file.

**Result.** Android run [36335611048](https://github.com/ineedsomesleep5/MagicMobile/actions/runs/36335611048)
(`e5711c2`) passed: real-engine JVM tests, the ARM64 image, staging and the native-linked APK.

| | Build 11 (`79de39c`) | `e5711c2` |
|---|---|---|
| Embedded resources | every XMage class file (99,186 class-file headers in the heap) | 7 files, 8.5 MB, no class files |
| `.svm_heap` (image heap) | 461.5 MB | 167.1 MB |
| Relocations | 108.0 MB `RELA` | 12.2 MB `ANDROID_RELA` |
| `libmmengine.so` | 795.5 MB | 405.4 MB unstripped, 380.8 MB stripped |
| `libmmengine.so` in the APK (deflated) | | 111.1 MB |
| Debug APK | 248.6 MB artifact | 184.9 MB |
| Builder peak RSS | 12.27 GB (`36310535888`) | 11.96 GB |

Image generation took 18 min 33 s (analysis 729 s at 9.38 GB); 67,848 classes and 382,066 methods
were reachable, as before, and the checkpoint feature registered the same 50,684 types. This is a
build result: the emulator device tests and phones are separate gates.
