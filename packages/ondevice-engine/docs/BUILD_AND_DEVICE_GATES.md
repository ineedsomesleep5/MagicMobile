# Build and acceptance sequence

## 1. Repeat the delivered portable checks

```sh
bash scripts/test_tooling.sh
bash scripts/test_native_boundary.sh
swift test --package-path swift
```

The package was tested with OpenJDK 21 targeting Java 17, Swift 6.2.1 on Linux, Python and clang ASan/UBSan. Apple SDK code is excluded from that Linux compilation.

## 2. Compile the genuine XMage path

On a machine with JDK, Maven and source/dependency download access:

```sh
bash scripts/build_jvm.sh
python3 scripts/audit_upstream.py .upstream/mage --output evidence/pinned-upstream-audit.json
```

The build is pinned and patches only reviewed entry points. Inspect `build/generated/registry-report.json`; no skipped/missing class may be treated as supported. Expect to fix compatibility faults in this first full build. This command has not passed in the delivery environment.

## 3. Resolve decks and run the actual first-prompt probe

A text file contains counts and names, including its explicitly identified commander(s). Optional exact printing syntax is `1 Name (SET) COLLECTOR`.

```sh
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input your-deck.txt --commander 'Your Commander Name' --output deck-a.json
# Resolve a second legal deck in the same way into deck-b.json.
python3 scripts/make_match.py deck-a.json deck-b.json --output match.json
python3 scripts/smoke_jvm.py match.json
```

`--commander` may be repeated for partners; `--companion` is separate. The resolver chooses a deterministic printing when none is specified; legality is still decided by XMage. It is not an Archidekt account scraper or an oracle text parser. No sample data is secretly playable.

The smoke creates real cards/game objects and waits for a real prompt. It deliberately reports `completedGame: false`. Extend it with actual scripted gameplay after this first gate. For manual protocol work, run the line-oriented `EngineCli` using `build/runtime-classpath.txt`; that CLI is a developer harness, not a required user PC service.

## 4. Native compilation diagnostics

With a supported GraalVM JDK:

```sh
GRAALVM_HOME=/absolute/path/to/graalvm bash scripts/build_native_desktop.sh
```

Supply `GRAAL_SDK_CP` if that distribution requires an explicit Native Image SDK classpath. SDK/version details, metadata and resource dependencies must be validated for the actual toolchain. Compiler and probe failure must fail the gate. This output is for the developer's desktop platform, not iOS.

Next, establish and pin the iOS compilation setup on the Mac (Gluon/Graal first candidate; J2ObjC alternative if necessary). No untested magic command is supplied as a claimed finished iOS build. This is substantive remaining porting work.

After genuine iOS device/simulator static libraries and generated headers exist:

```sh
bash scripts/package_xcframework.sh \
  /absolute/device/libmmengine.a /absolute/device/headers \
  /absolute/simulator/libmmengine.a /absolute/simulator/headers
```

Inspect architecture **and platform**—arm64 can be either device or simulator. Do not package a macOS library as iOS. The AOT library must include any runtime libraries needed by its toolchain.

## 5. Xcode harness

`ios-app/project.yml` builds the inspection app with a deliberately unlinked engine boundary. Using XcodeGen from that directory:

```sh
xcodegen generate --spec project.yml
```

This is a useful Apple SDK UI/package compile gate, but a successful launch should report the missing native library. It is not gameplay proof.

After the real native framework exists, generate `project.native.yml` instead, check the generated native headers/link flags and select a signing team. The installer rewrites paths correctly when the harness lives in `apps/ios-ondevice` inside MagicMobile.

## 6. Required device evidence

Complete a match on a physical iPhone in airplane mode after installation. Record real device/iOS version, app/engine build IDs, cold start, resident/peak memory, battery/thermal behavior and any unsupported card/prompt. No numeric target is claimed as measured in this delivery.

Then test two and four physical devices over internet connections after Game Center lobby/orchestration is implemented. Include duplicated/stale messages, wrong build IDs, temporary disconnection, host app switching, device lock, force quit and version mismatch. Clearly document whether the match pauses, reconnects or is lost. Do not label nonpersistent in-memory state as save/resume.
