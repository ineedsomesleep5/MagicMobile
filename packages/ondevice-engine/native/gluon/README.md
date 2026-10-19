# iOS device AOT diagnostic

From the package root, run `bash scripts/build_native_ios.sh` after the real JVM
baseline produces `build/runtime-classpath.txt` and reflection metadata.

## Toolchain (engine release D)

`toolchain.json` pins everything, checksum by checksum; the Android, iOS and guard
scripts read it:

- Gluon GraalVM `gluon-23+25.1-dev-2409082136` (GraalVM 24.1.0-dev, JDK 23) for
  Linux x86-64 (Android cross-compiler), Intel macOS (hosted iOS build) and Apple
  silicon (local default path). Neither release publishes digests; ours were
  computed from the official assets.
- GluonFX 1.0.25 (Substrate 0.0.65): the last release whose Substrate supports
  GraalVM for JDK 23. Substrate 0.0.66 and later (GluonFX 1.0.26+) went back to
  GraalVM 22.1 ([gluonhq/substrate#1310](https://github.com/gluonhq/substrate/pull/1310)).
- `libvmone.a` from [gluonhq/vmone](https://github.com/gluonhq/vmone/releases/tag/gvm-24-2.1)
  `gvm-24-2.1`: the JDK's static native libraries plus GraalVM's C helpers
  (`JvmFuncs`, `cpuid`, `getThreadId`, ...). It replaces Substrate's JDK 18 static
  JDK and its `ea+27` clibs, which predate GraalVM 24.1's C interface. Builds pass
  the verified directory with `-Djavalibspath`; the product links `-lvmone`.

What no longer applies from GraalVM 22.1:

- The far-call compiler backport. GraalVM 24.1 places AArch64 direct-call
  trampolines itself (`AArch64HostedTrampolineSupport`, the code our backport was
  taken from). `MM_FORCE_TRAMPOLINES=1 bash scripts/test_ios_toolchain.sh` forces
  them with `-H:+UseDirectCallTrampolinesALot` and counts them in the archive
  (`scripts/count_direct_call_trampolines.py`).
- The `java.awt.Color` patch. JDK 23's Color has no desktop JNI initializer;
  `scripts/test_color_native.sh` checks that and the native values.
- The iOS simulator target. vmone ships no `ios-macos-x64` library.

Substrate 0.0.65's `staticlib` goal compiles the image and archives it, so the
script runs that goal alone. `MM_NATIVE_OPTIMIZE=s` builds with `-Os` instead of
`-O2`. Native Image defaults to a 4 GiB heap and two compilation threads.
`MM_NATIVE_MAX_HEAP=5g` permits one larger local diagnostic; the hosted-only
10 GiB setting requires at least 12 GiB physical memory. Increasing the builder
limit is not evidence of acceptable iPhone runtime memory use.

Each invocation creates a fresh `build/ios-native-XXXXXX` output directory and
matching `evidence/ios-native-XXXXXX.log`. Maven/Gluon caches stay under `build`.
Failures propagate as a nonzero exit; no capability flags are updated.

## Entry points and classpath

`IosLibraryMain` satisfies Gluon's required `main(String[])`. It deliberately
throws if invoked: real engine requests use the existing `NativeEntryPoints` C
exports. Native Image registers all scanned `@CEntryPoint` methods whose inclusion
predicate is true; the generated classpath manifest includes the run's isolated
`native-java` directory. The script nevertheless requires defined `nm` symbols for
`mm_engine_request`, `mm_engine_free`, `mm_engine_shutdown_v2`, and
`graal_create_isolate` before reporting archive success.

The native classpath preserves the passed JVM baseline's ordering, including
patched directories before original XMage jars. Appending it through
`nativeImageArgs` bypasses Gluon's own dependency scan; the package reflection
and resource metadata are supplied explicitly. Any additional JNI, serialization,
or native-library configuration remains a real-engine reachability gate.

An archive is not a runnable iPhone app. `scripts/test_ios_link.sh` links the
toolchain-only probe archive with an independent C caller owning `main` against
`libvmone.a`, the same libraries the product links. No runtime execution is
claimed by either.

`MM_NATIVE_REFLECTION_PROFILE=targeted` selects the experimental reflection
manifest. `MM_NATIVE_INIT_PROFILE=reviewed-enums` additionally selects the
reviewed enum initialization experiment. Defaults retain broad reflection and
runtime initialization. See `docs/NATIVE_METADATA.md` for limitations.

The current tested-dependency diagnostic is:

```bash
MM_NATIVE_REFLECTION_PROFILE=targeted MM_NATIVE_INIT_PROFILE=reviewed-enums \
MM_NATIVE_ORM_PROFILE=runtime-defaults bash scripts/build_native_ios.sh
```

The ORMLite profile compiles the native-only date-format adaptation, preserves
runtime defaults and requires the pinned ORMLite 5.7 JAR. Full locale data is
included. `bash scripts/test_ormlite_native.sh` separately reproduces its compiler
and timezone failure cases and checks the fix on desktop; it is not an engine test.

## Hosted Intel build

The hosted device-library build is `.github/workflows/magicmobile-far-calls.yml`
(the name predates release D). It is manually dispatched with a reviewed candidate
SHA and a successful same-SHA `magicmobile-issue4-nonsimulator.yml` run, whose
real-JVM job supplies the real regressions. It runs on the standard
`macos-26-intel` runner (14 GB RAM) with Xcode 26.6.
`scripts/setup_gluon_intel.sh` downloads and verifies the Intel GraalVM archive
and the iOS `libvmone.a` and writes `build/toolchains/ios-toolchain.env`
(`MM_GRAALVM_HOME`, `MM_JAVA_STATIC_LIBS`). The workflow then runs the builder-heap
regression and the forced-trampoline toolchain probe, rebuilds the full pinned JVM
catalogue, runs the native token, Color and catalogue checks and builds the full
device library with a 10 GiB builder. The consumer engine remains on-device; the
runner is only a build machine.

Only fresh hosted evidence and a successful candidate archive/header set become
CI artifacts: `libmmengine.a`, headers, `vmone/libvmone.a` and
`toolchain-manifest.json` (the pins it was built with, which
`verify_native_candidate.py` compares with this directory's `toolchain.json`).
Local logs, downloaded toolchains, raw upstream source and signing material are not
committed. The workflow does not sign, upload to TestFlight, or claim a candidate
archive is a working native app.
