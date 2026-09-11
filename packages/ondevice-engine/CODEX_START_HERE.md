# Codex handoff — continue this implementation; do not start over

## Caleb's request

Rebuild `ineedsomesleep5/MagicMobile` around a **native iOS app with XMage's real rules engine on the device**. Human multiplayer must not require a user-managed computer. Preserve upstream Java rules and card implementations where possible, with a controlled update pipeline. Caleb explicitly authorizes substantial replacement of the old app. Prioritize actual engine operation before polished artwork/UI.

Caleb's 2026-09-11 clarification: **Commander gameplay is the main product goal, and it must work with the existing in-progress vertical/portrait playing mode.** Preserve and adapt the native portrait board in `apps/ios/MagicMobile/ContentView.swift` and its interaction/layout contracts. Improvements are welcome, but the engine inspection harness is not the product UI. Verify real prompt, mana, stack, combat, zone, and multi-opponent interactions in that vertical experience before release.

## First actions

1. Read `implementation-status.json`, `evidence/README.md`, `AGENTS.md`, and `docs/NATIVE_BLOCKERS.md`.
2. If this directory is still the downloaded package, use `scripts/install_into_magicmobile.py` to inspect and install into a clean local MagicMobile checkout. It creates a new local branch and does not push. If already installed under `packages/ondevice-engine`, work there; do not run the installer on itself.
3. Re-run `bash scripts/test_tooling.sh`, `bash scripts/test_native_boundary.sh`, and `swift test --package-path swift`.
4. Get the **real** XMage build working with `bash scripts/build_jvm.sh`. Correct source/API/build faults, not the tests' definition of success. Do not introduce dummy `mage.*` classes to make this gate green.

## Architecture already written

`engine/xmage` is the real engine adapter. It constructs `MobileCommanderGame`, loads actual compiled card classes from trusted set metadata, creates `MobileHumanPlayer` instances, and runs one authoritative game thread. `MobileHumanPlayer` retains XMage's choice/rules logic and replaces only its desktop response transport.

`engine/core` handles prompt correlation, idempotency, per-view state/event delivery and JSON safety. It contains no MTG rules. `ViewProjector` uses an upstream `GameView` for each seat, never broadcasts a serialized `GameState`. Full real-engine privacy fixtures are still required.

`prepare_upstream.py` makes three narrow, hash-checked changes: static card factories, static set registration, and a protected HumanPlayer response field. `RegistryExporter` generates direct `new CardClass(...)` calls in buckets, so the phone does not scan JARs or load downloaded Java classes. Keep card rules upstream-owned.

`swift` provides the C boundary, client, peer host router and packet handling. `ios-app` / `apps/ios-ondevice` is an **inspection harness**, not a finished game UI. It must show a missing-native-engine error until a genuine library is linked. The old app's visual/deck work can be reused after its transport contracts are adapted; raw upstream GameView JSON is not a drop-in replacement for the old gateway snapshot.

## What you must not assume

There is no successful full XMage compilation log, full-game run, native XMage library, simulator run, signed app, or physical-device/offline result in the handoff. Boundary tests do not establish any of those. `nativeDeviceValidated` is deliberately false. An echo backend exists only in a C memory test and must never be linked as the game backend.

## Prioritized engineering gates

### A. Compile and execute actual XMage on the JVM

Run `build_jvm.sh`. It fetches pinned commit `8aea65ae9ae3c89970fe865e1316105539e097ca`, verifies patch source blobs, builds selected modules, exports/compiles card factories and compiles the adapter. Check generated exclusions and every card-printing reference. If set singleton initialization needs the generated factory before catalogue export, split discovery/source generation and catalogue emission into separate build phases; do not disable missing-class errors.

Resolve two legal decks using `resolve_deck.py`, combine using `make_match.py`, and run `smoke_jvm.py`. Then add and execute real gameplay tests: start/mulligan/land/mana/cast/stack/combat/end, Commander rules and 4-human seating. Boot-to-first-prompt is only the first test.

### B. Complete prompts, projections and lifecycle

Test all gameplay query types and metadata against the real engine. Pay particular attention to `SELECT` variants, multiselect targeting, split/MDFC cards, ordered zones, trigger ordering, mana-pool vs mana-source inputs, revealed/looked-at cards, face-down cards and secrets in nested fields. Implement a safe, tested turn-control proxy before enabling cards that take another turn/player's choices. Preserve exact prompt IDs/revisions and request IDs across retries.

Test cancellation while waiting and while resolving complex effects. Do not start a second game while the old thread remains alive. Current destroy waits a bounded interval and returns `engine_busy_shutdown` until the old worker terminates. Do not call `game.end()` unsafely from the UI thread to suppress a hang.

### C. Prove the native engine, then iOS

Use the desktop AOT script as a diagnostic step where useful. Resolve native reachability, runtime-initialization, resource, Java desktop/SQL/serialization and threading issues. Broad reflection metadata is provisional, not an iOS compatibility proof.

Research and pin a supported Gluon/Graal iOS compilation route on this Mac. The provided Graal C/isolate ABI may need adaptation to the selected mobile toolchain. If it is unsuitable, evaluate J2ObjC against the same JVM correctness baseline; retain the protocol, static registry strategy, boundary tests and Swift work rather than rewrite the rules into Swift.

Produce real device and simulator static libraries with the native C entrypoints, package them using `package_xcframework.sh`, and integrate with `project.native.yml`. Verify exact generated headers, platform slices and runtime dependencies. Never rename a macOS library to pretend it is iOS-compatible.

### D. Multiplayer without a player-managed computer

Use `HostRouter` and `GameKitTransport` as the foundation. Implement authenticated Game Center login, matchmaking/lobby, host selection, deck exchange, explicit peer-to-seat bindings, request/response correlation and client reconciliation. A host is authoritative and trusted with hidden state; this is not anti-cheat-equivalent to a dedicated trusted server.

Test two and four physical devices, including different engine versions, delayed/duplicate messages, host backgrounding, reconnect and termination. Start with pause/reconnect semantics; do not claim persistent save/resume or host migration without implementations and tests. The Swift inspection app's arbitrary seat selector is development-only and must not become a guest privilege.

### E. Product interface and upstream upkeep

Make the new native engine path the primary experience only after the above gates. Reuse or replace old UI code freely; do not route a native failure back to the old server or development simulator. Implement a complete engine-driven prompt renderer and battlefield before claiming card coverage.

Upstream reports are read-only. A new commit requires reviewed source hashes, regenerated factories, the same regression gates and a new compiled app release. Keep engine/card/protocol build identities matched across peers.

## Required final evidence from Codex

Report exact commands, environment, counts and artifacts separately for: standalone tests; actual JVM engine build; completed JVM games; actual AOT build; simulator; physical-iPhone airplane-mode play; multi-device internet play. Record failures plainly. Do not turn capability flags true to satisfy UI expectations.

**Do not replace this package with a new plan. Continue its source, fix it, build it and prove it.**
