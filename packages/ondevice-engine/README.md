# MagicMobile · On-device XMage migration

**Maintained XMage port; desktop continuation updated September 12, 2026.**

The native iOS product embeds XMage's actual rules engine. A player must not need a desktop JVM, Docker container, browser simulator, local gateway, or external computer. The selected host's phone owns the authoritative multiplayer game; real multi-phone execution remains an acceptance gate.

## Actual delivery status

Full XMage+MAD ARM64 AOT compilation (**34723517045**), actual product linkage (**34724909323**) and internal TestFlight **0.1.0 (2026091202)** passed. This replacement includes the opening-selection cancellation fix in engine `a34fb08`, with app source `55be4f4`; Apple reports **VALID / IN_BETA_TESTING**, with verified Internal group access. The earlier build 2026091201 is superseded. Real JVM rules/AI/complete-game and portable app/protocol tests passed. **Native iPhone gameplay, AI resource behavior and real multi-device execution remain unverified.** See [current status](docs/LOCAL_CONTINUATION_STATUS.md) and [physical acceptance](docs/TESTFLIGHT_ACCEPTANCE.md) for exact provenance and separate gates.

The product retains and adapts the existing **vertical/portrait playing mode** and landscape support in `apps/ios/MagicMobile`; `apps/ios-ondevice` remains a diagnostic harness. See [PORTRAIT_INTEGRATION.md](docs/PORTRAIT_INTEGRATION.md).

The unlinked Swift package deliberately returns `nativeEngineNotLinked`. It never simulates success. The synthetic Java/C/Swift fixtures are test-only and are not Magic implementations.

`SHA256SUMS.txt` records the downloaded handoff, not the subsequently edited continuation. Current local changes and separately dated evidence supersede those original source hashes; the pinned upstream patch hashes remain enforced.

**Start with [LOCAL_CONTINUATION_STATUS.md](docs/LOCAL_CONTINUATION_STATUS.md)** and `implementation-status.json`. [BUILD_AND_DEVICE_GATES.md](docs/BUILD_AND_DEVICE_GATES.md) and [UPSTREAM_MAINTENANCE.md](docs/UPSTREAM_MAINTENANCE.md) describe current verification and signed updates. `CODEX_START_HERE.md` and the original handoff hashes are historical setup material, not instructions to reinstall over this continuation.

## What is included

| Area | Implementation |
|---|---|
| Actual XMage integration source | In-process Commander factory, human-player input channel, query adapter, upstream per-seat GameView projections, compiled-printing deck resolution, lifecycle and capabilities |
| Engine/UI boundary | Strict JSON, prompt tokens/revisions, actor binding, command idempotency, bounded viewer-scoped events, terminal states and cleanup |
| Static card/set registration | Pinned source patches; build-time constructor discovery; sharded direct-call Java factories; direct set singleton registration; catalogue and provisional reflection metadata |
| Swift package | Native C bridge actor, typed engine client, exact-prompt responses, build identity matching, host-side peer router, chunking and quota-limited reassembly |
| Apple-only source | Existing portrait/landscape product setup, native session/prompt/snapshot adapters, authenticated Game Center lobby/transport; separate diagnostic harness |
| Native work | C lifetime wrapper, Graal entrypoints, retryable isolate lifecycle, full ARM64 build/compiler backport, verified product long calls and signed-binary layout inspection |
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

## Historical installer (not for this existing continuation)

Only for an authorized fresh installation from an original package; do not rerun
this over `MagicMobile-ondevice`, reset its branch, or replace it with an old ZIP:

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

The source supports a local human with 1–3 actual MAD opponents or 2–4 Game Center humans. Turn-control routing/authorized views and native controls have regression coverage; nested control remains explicitly unsupported. Lobby and portrait integration are implemented, but their phone acceptance is not run. Durable save/resume, host migration and exhaustive card/UI parity are not claimed. The engine is not a guaranteed background server when an iPhone locks or suspends.

The reviewed Gluon/Graal ARM64 build produces real iOS artifacts with paired generated headers/dependencies. Source changes require exact provenance, rebuilt native inputs where necessary, actual product verification and a signed app update. Desktop native-image output is **not** an iOS binary; neither native compilation nor TestFlight upload proves phone gameplay.

Review all third-party content and distribution rights before publishing. See `THIRD_PARTY_NOTICES.md`.
