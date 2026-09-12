# iOS device AOT diagnostic

From the package root, run `bash scripts/build_native_ios.sh` after the real JVM
baseline produces `build/runtime-classpath.txt` and reflection metadata.

The script pins Gluon GraalVM 22.1.0.1 Java 17 M1, GluonFX 1.0.29 (Substrate
0.0.69), static JDK 18-ea+prep18-9, and `/Applications/Xcode.app`. It compiles
only the native bridge and the launcher in this module. The upstream Maven
reactor is not invoked. Native Image defaults to a 4 GiB heap and two compilation threads.

`MM_NATIVE_NEW_RATIO=7` is an optional builder-memory diagnostic that reserves
more of the same 4 GiB heap for retained compiler objects. The baseline is `2`.
This changes the builder VM only, not the generated runtime's garbage collector.
See `evidence/ios-native-memory-diagnostic.txt` for the measured baseline and
limitations; neither setting is evidence of a successful native engine build.
`MM_NATIVE_MAX_HEAP=5g` permits one larger local diagnostic; the hosted-only
10 GiB setting requires at least 12 GiB physical memory. Leave idle applications
closed and run only one compiler. Increasing the builder limit is not evidence
of acceptable iPhone runtime memory use.

Each invocation creates a fresh `build/ios-native-XXXXXX` output directory and
matching `evidence/ios-native-XXXXXX.log`. Maven/Gluon caches stay under `build`.
Failures propagate as a nonzero exit; no capability flags are updated.

`IosLibraryMain` satisfies this Gluon version's required `main(String[])`.
It deliberately throws if invoked: real engine requests use the existing
`NativeEntryPoints` C exports. Archive success also requires those exports.
In this pinned distribution, `com.oracle.svm.hosted.NativeImageGenerator`
(`lib/svm/builder/svm.src.zip`, lines 1084-1106) registers all scanned
`@CEntryPoint` methods whose inclusion predicate is true. The generated classpath
manifest includes the run's isolated `native-java` directory; no Java call from the launcher or custom
Feature is required to root these exports. The script nevertheless requires
defined `nm` symbols for `mm_engine_request`, `mm_engine_free`,
`mm_engine_shutdown_v2`, and `graal_create_isolate` before reporting archive success.

The native classpath preserves the passed JVM baseline's ordering, including
patched directories before original XMage jars. Appending it through
`nativeImageArgs` bypasses Gluon's own dependency scan; the package reflection
and resource metadata are supplied explicitly. Any additional JNI, serialization,
or native-library configuration remains a real-engine reachability gate.

An archive is not a runnable iPhone app. Before Swift integration, inspect its
objects (Gluon's archive can include `AppDelegate.o` with its own `main`), retain
the generated Graal headers, and link the matching platform runtime libraries.
This diagnostic neither packages an XCFramework nor installs or distributes an app.

The no-XMage probe subsequently linked both through Gluon's `link` goal and
through an independent C caller owning `main`. The latter did not pull in
Gluon's `AppDelegate` and reported iOS 17 / SDK 26.5 load metadata. Reproduce
with `scripts/test_ios_link.sh build/ios-abi-XXXXXX` after the toolchain probe;
`test_ios_toolchain.sh` now includes this gate. No runtime execution is claimed.
The legacy Graal object lacks a platform load command, so the Apple linker
warns that it assumes iOS. The final executable's platform metadata and a
successful link do not remove the requirement for a real device run.

Static archives do not contain all target runtime libraries. The link goal
retrieves Gluon C libraries `ios-arm64-ea+27` and static JDK
`18-ea+prep18-9`; the caller links these explicitly. The downloaded ZIP hashes
in this local link check were respectively
`9fdf9203f99286a0fa88916da9dfffb4b7019c55a048fe077dac0d220b6ca7ad` and
`95520e5e01adebfb0c9fdce12e87c39d1e630e0d1fa1a7a5af2288efd1c89d00`.

`MM_NATIVE_REFLECTION_PROFILE=targeted` selects the experimental 1,429-entry
reflection manifest. `MM_NATIVE_INIT_PROFILE=reviewed-enums` additionally selects
the reviewed 18-enum initialization experiment. Defaults retain broad reflection
and runtime initialization. See `docs/NATIVE_METADATA.md` for limitations.

The current tested-dependency diagnostic is:

```bash
MM_NATIVE_REFLECTION_PROFILE=targeted MM_NATIVE_INIT_PROFILE=reviewed-enums \
MM_NATIVE_ORM_PROFILE=runtime-defaults bash scripts/build_native_ios.sh
```

The ORMLite profile compiles the native-only date-format adaptation, preserves
runtime defaults and requires the pinned ORMLite 5.7 JAR. Full locale data is
included. `bash scripts/test_ormlite_native.sh` separately reproduces its compiler
and timezone failure cases and checks the fix on desktop; it is not an engine test.

Toolchain archive: [official Gluon Java 17 M1 release](https://github.com/gluonhq/graal/releases/download/gluon-22.1.0.1-Final/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final.tar.gz),
stored locally as `build/toolchains/gluon-graal17.tar.gz`, SHA-256
`847b549a616f47687625e77a044ed3e162e96850f227f852db57b04528d09024`.
The static SDK pin follows `DEFAULT_JAVA_STATIC_SDK_VERSION` in
[Substrate 0.0.69](https://github.com/gluonhq/substrate/blob/0.0.69/src/main/java/com/gluonhq/substrate/Constants.java#L101),
also verified in the downloaded JAR. Toolchain availability does not prove the
full engine is compatible.

## Hosted Intel build diagnostic

`.github/workflows/magicmobile-native-ios.yml` is manually dispatched on the
standard `macos-26-intel` runner (14 GB RAM), using Xcode 26.6. It rebuilds the
full pinned JVM catalogue, runs real regressions, checks the isolated iOS
toolchain probe, then attempts the full device library with a 10 GiB builder.
That heap setting is rejected on hosts with less than 12 GiB physical memory.
The consumer engine remains on-device; the runner is only a build machine.

`scripts/setup_gluon_intel.sh` downloads the official Java 17 **Intel** Gluon
22.1.0.1 archive and verifies SHA-256
`61084c8e12a500e5019657d3160fa3394cd8230a0e780718a051d59028fbfb99`.
The digest was computed from the official release asset; the old release API
does not publish a separate digest. `MM_GRAALVM_HOME` selects this verified SDK
for the build/probe; the original M1 path remains the local default.

Only fresh hosted evidence and a successful candidate archive/header set become
CI artifacts. Local logs, downloaded toolchains, raw upstream source and signing
material are not committed. The workflow does not sign, upload to TestFlight,
or claim a candidate archive is a working native app.
