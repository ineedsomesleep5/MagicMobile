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
exception. Local evidence: `build/color-native-xFtM1D/`. The baseline went red;
the production policy below made the adapted executable pass.

## Narrow adaptation

`native/gluon/pom.xml` explicitly initializes **only `java.awt.Color`** at build
time. Its pinned static state consists of the standard RGB Color values and
primitive constants. Their RGB construction does not create a ColorSpace,
desktop peer, image, window or display. Runtime constructors and color methods
remain Java's original implementation. XMage and mobile adapters remain
runtime-initialized; no rules, choice logic or desktop service is replaced.
Hosted Color initialization can run Toolkit's bootstrap on the build machine;
the required value operations do not depend on that bootstrap's platform caches.
The headless test variants establish value compatibility, not runtime reconfiguration
of Toolkit or support for its graphics operations.

Do not replace this with a package-wide `java.awt`/Toolkit initialization policy,
swallow native-library failures, or supply fake graphics services. ColorSpace/ICC,
painting, images and desktop GUI operations are not made supported by this fix.
Re-review the initializer if the JDK changes.

The regression compares native and JVM RGB/alpha values, constants, HSB
conversion, invalid-input rejection, and actual upstream `HintUtils` output for
free/paid mulligan and colored cost hints. Both headless settings pass after
adaptation. The workflow executes this dependency regression before the full
ARM64 build and preserves its logs.

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
