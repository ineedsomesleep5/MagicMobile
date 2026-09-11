# MagicMobile · On-device XMage migration

**For Caleb. Repository-ready source and Codex handoff, September 11, 2026.**

The target is a native iOS client that embeds XMage's actual rules engine. A player must not need a desktop JVM, Docker container, browser simulator, local gateway, or external computer. The selected host's phone should eventually run the authoritative multiplayer game.

## Actual delivery status

This is **an experimental port foundation, not a finished or verified iPhone engine**. On 2026-09-11 the selected real XMage modules and adapter compiled successfully on the Mac, the complete printing catalogue exported, and two- and four-human-seat Commander fixtures completed real games. The Swift package passed 29 macOS tests with GameKit compilation. A pinned Gluon/Graal device AOT diagnostic is underway; no native artifact, iOS gameplay, physical-iPhone or multi-device internet result is established yet. See the timestamped evidence rather than treating portable tests as phone proof.

The product must retain and adapt the existing **vertical/portrait playing mode** in `apps/ios/MagicMobile`, not ship the inspection app as the gameplay experience. See [PORTRAIT_INTEGRATION.md](docs/PORTRAIT_INTEGRATION.md).

The unlinked Swift package deliberately returns `nativeEngineNotLinked`. It never simulates success. The synthetic Java/C/Swift fixtures are test-only and are not Magic implementations.

`SHA256SUMS.txt` records the downloaded handoff, not the subsequently edited continuation. Current local changes and separately dated evidence supersede those original source hashes; the pinned upstream patch hashes remain enforced.

**Start with [CODEX_START_HERE.md](CODEX_START_HERE.md).** Exact verification scope is in [evidence/README.md](evidence/README.md) and `implementation-status.json`.

## What is included

| Area | Implementation |
|---|---|
| Actual XMage integration source | In-process Commander factory, human-player input channel, query adapter, upstream per-seat GameView projections, compiled-printing deck resolution, lifecycle and capabilities |
| Engine/UI boundary | Strict JSON, prompt tokens/revisions, actor binding, command idempotency, bounded viewer-scoped events, terminal states and cleanup |
| Static card/set registration | Pinned source patches; build-time constructor discovery; sharded direct-call Java factories; direct set singleton registration; catalogue and provisional reflection metadata |
| Swift package | Native C bridge actor, typed engine client, exact-prompt responses, build identity matching, host-side peer router, chunking and quota-limited reassembly |
| Apple-only source | GameKit data transport and a SwiftUI engine inspection app, including a native-linked XcodeGen variant |
| Native work | C lifetime wrapper, Graal C entrypoints, isolate adapter, desktop AOT diagnostic build script, XCFramework packaging helper |
| Handoff and maintenance | Clean-tree installer into MagicMobile, CI template, upstream movement check, build/rules/device gates, tests and captured evidence |

XMage itself is fetched at a pinned revision during the developer build. Its tens of thousands of card implementations are **not replaced by a small handwritten Swift rules engine** and are not vendored in this ZIP. Players would receive the compiled result in the app; they would not execute the build scripts.

## Run the checks available without XMage/Xcode

Requirements: JDK 17+, Python 3.10+, git, clang with sanitizers, Swift 6.

```sh
bash scripts/test_tooling.sh
bash scripts/test_native_boundary.sh
swift test --package-path swift
```

The first command also runs the Java core checks. These are boundary/build-tool checks, **not gameplay acceptance tests**. Apple-only `GameKit` and `SwiftUI` branches still require Xcode.

## Install into the existing repository

From this extracted directory:

```sh
python3 scripts/install_into_magicmobile.py /absolute/path/to/MagicMobile
python3 scripts/install_into_magicmobile.py /absolute/path/to/MagicMobile --apply
```

The first command is a dry run. The second creates local branch `codex/ondevice-xmage`, adds `packages/ondevice-engine` and `apps/ios-ondevice`, installs a CI template, and appends a migration note to the repository README. It refuses a dirty tree or existing destination. It does **not** commit, push, delete the existing apps, or silently replace unrelated code.

The inspected repository baseline was `058478f690b713332c13d0a8369e98f5b792a282`. The installer can add the new paths on a newer clean baseline; Codex must review integration changes against that baseline.

## Build the real engine on the developer machine

```sh
bash scripts/build_jvm.sh
python3 scripts/audit_upstream.py .upstream/mage --output evidence/pinned-upstream-audit.json
```

This needs network access, Maven, and a JDK. The original delivery container could not execute this gate; the subsequent Mac continuation passed it. New changes still require regression checks against the pinned real dependencies.

After the build creates `build/generated/catalogue.jsonl`, resolve decks, make a match configuration, then run the real boot-to-first-prompt probe. See [docs/BUILD_AND_DEVICE_GATES.md](docs/BUILD_AND_DEVICE_GATES.md). That probe also is not a full-game test.

`scripts/play_jvm.py build/match.json` drives the small real Commander fixture through completion; `--four-seats` expands it to four human seats. This is a developer test driver, not an app AI or player-required service. `scripts/test_real_lifecycle.py` exercises the real protocol lifecycle separately.

## Important boundaries

The current source enables 2–4 human seats and no AI. Turn-control proxies, input routing and permitted in-game visibility have real-JVM regression coverage; nested control remains explicitly unsupported and native UI consumption is pending. Save/resume, host migration, live Game Center lobby orchestration, portrait-board integration, and full prompt/card parity are not complete. The engine is not a guaranteed background server when an iPhone locks or suspends.

Graal shared-library entrypoints are provided, but desktop native-image output is **not** an iOS binary. A working iOS cross-compilation/runtime configuration and the complete dependency/metadata adaptation are still required. Keep this uncertainty visible; do not describe the remaining task as merely dragging files into Xcode.

Review all third-party content and distribution rights before publishing. See `THIRD_PARTY_NOTICES.md`.
