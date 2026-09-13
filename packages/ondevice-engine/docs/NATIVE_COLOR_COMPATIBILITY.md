# Native Color initialization — 2026-09-13

## Observed failure and minimal regression

Build 2026091203 reached `HumanPlayer.chooseMulligan` on the physical iPhone but
stopped when `java.awt.Color` initialized. The pinned Gluon JDK 17.0.3 Color
initializer calls `Toolkit.loadLibraries()` unconditionally, before its headless
check. That attempts to load the desktop `awt` library, which is unavailable in
the embedded iOS app. Setting headless mode alone does not bypass that call.

`scripts/test_color_native.sh` reproduces the same
`UnsatisfiedLinkError: no awt in java.library.path` in a small real native
executable. The baseline reaches `Toolkit` and `Color.<clinit>`, not a simulated
exception. Current local evidence: `build/color-native-lYcHrQ/`.

## Rejected first policy

The first Color-only build-time policy passed a host-native probe but failed
full iOS run **34737322860** at source `017b9c5`. Color initialized Toolkit on
the builder, violating the iOS Toolkit runtime-initialization constraint.
Adding that exact constraint to the host probe reproduces the compiler failure
in approximately 13 seconds. The earlier host-only pass is not iOS evidence.
The regression now retains this failing-policy build as well as the original
runtime missing-AWT reproduction.

## Narrow adaptation

`scripts/prepare_native_color.py` reads Color.java from the pinned Gluon
JDK's `lib/src.zip`. It refuses any source other than SHA-256
`4010cb2e2fee98b0f285a7a191997fd23a140430d8aa344917c7c55f8b87bc30`.
The generated source removes only the desktop JNI bootstrap block:
`Toolkit.loadLibraries()` and the headless-conditional `initIDs()` call.
All original fields, constants, constructors, validation and color methods remain
unchanged. The original copyright/GPL-with-Classpath-exception header is retained.
The installed JDK and upstream XMage sources are never modified.

The helper compiles only `java/awt/Color.class` into an owned build directory.
The native builder receives it through the JVM's `--patch-module=java.desktop`
option. **Both Color and Toolkit remain explicitly runtime-initialized.**
Color's original static RGB constant assignments still execute on the device;
no desktop JNI registration is needed for these Java value operations.
No new private Graal substitution API or fake desktop implementation is used.
The compiler artifact preserves and hashes the generated source, class and
manifest alongside the exact native library and paired SDK inputs.

Do not replace this with a package-wide `java.awt`/Toolkit initialization policy,
swallow native-library failures, or supply fake graphics services. Toolkit's
original implementation remains intact. After Color succeeds, an explicit
Toolkit initialization in the native regression still throws the missing-AWT
error. ColorSpace/ICC, painting, images and desktop GUI operations are not made
supported by this fix. Re-review the initializer if the JDK changes.

The regression compares native and JVM RGB/alpha values, constants, HSB
conversion, invalid-input rejection, and actual upstream `HintUtils` output for
free/paid mulligan and colored cost hints. An additional 1,024 samples compare
float construction, brighter/darker colors and transparency with the original
JVM (fingerprint `326ce1c7edb97d65`). Both headless settings pass after adaptation.
The workflow executes this dependency regression before the full ARM64 build
and preserves its logs. These are real host-native tests, not iPhone execution.

## Why not patch just mulligans?

The mulligan call evaluates `Color.GREEN`/`YELLOW` before entering `HintUtils`.
Other rules paths also use Color, including Collect Evidence, Teamwork, Crew,
Saddle and colored card/stack hints. Changing one prompt would leave the same
native initialization failure reachable later. `HintUtils` itself only reads
RGB components and formats text; its HTML font tag invokes no font service.

## Acceptance boundary

Passing the small native regression is not full XMage or iPhone acceptance.
The changed native inputs require a fresh full engine artifact, paired-input
verification, actual product linking, and direct phone reproduction of the
original matchup. Keep the existing private diagnostic report available while
exercising subsequent game paths. Do not label the app fully working until the
relevant phone gameplay checks pass.
