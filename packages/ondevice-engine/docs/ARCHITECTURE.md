# Architecture and decisions

## Executable boundaries

```
Existing apps/ios portrait/landscape SwiftUI product UI
                  |
         Swift EngineClient actor transport
                  |
           C memory/lifetime boundary
                  |
   NativeEntryPoints + XmageEngine (ARM64 AOT compiled/linked)
                  |
      actual XMage Java rules/cards, compiled native
```

For multiplayer, all installations contain an engine, but a match initially has one authoritative host. Remote peers exchange player actions and their own projected state. Their `viewerId` comes from a trusted binding in `HostRouter`, not peer payloads. `GameKitTransport` handles packets, not rules, matchmaking or host migration.

## Threads and decisions

The actual game runs on a `GAME mobile-…` thread. User decisions wait on a bounded input channel in `MobileHumanPlayer`; responses are assigned into its upstream PlayerResponse only on the game thread. There is no calls-to-desktop-session layer. Each copy retains its player's response channel, consistent with upstream copies sharing response data.

The `MatchMailbox` sits outside game semantics. On each engine decision, the game thread creates independent per-seat `GameView`s and freezes their JSON projections. It publishes an immutable prompt with token and prompt revision. A remote/UI answer must carry the same token/revision and a stable request UUID. A duplicate UUID with different content is rejected; a repeated identical command returns its earlier receipt. Queued does not mean fully resolved: the next engine view is authoritative.

Polling reads frozen objects. It never traverses a concurrently mutating GameState. Event history is viewer-scoped and bounded; an expired cursor requires resynchronization from the returned snapshot. Global revision numbers can have gaps for a viewer, so overflow detection uses each viewer's actual eviction watermark, not a naive contiguous sequence assumption.

## Construction and updates

Three source patches are protected by commit and blob hashes. The adapter installs generated direct card factories, then generated set singletons, then resolves deck printings from those trusted sets. Caller-supplied Java class names and rarities are not accepted in match configuration. Card legality/identity/Commander rules stay in the upstream validator.

`RegistryExporter` runs in the developer JVM. Reflection there discovers public constructors, not rules text. Generated runtime factories use direct constructor calls and explicit set singleton calls. Large factories are sharded to avoid a single oversized Java method. Excluded classes and missing printing factories are visible failures/reports, not silently omitted cards.

Registration does not solve every native issue. Gson/Java resources, runtime class initialization, serialization and Java desktop dependencies still need reachability/runtime proof. Source scans are indicators, not proof of whether a class will execute on a phone.

## Native ownership

`mm_runtime` owns a native backend state/isolate. Requests on one runtime are mutex-serialized. The backend owns the initial response; the wrapper copies it, frees the original, and returns length-delimited bytes to Swift. Swift frees those bytes exactly once. No assumption is made that returned bytes are NUL-terminated.

Backend registration occurs once at startup; it does not use dlopen or load a downloaded JAR. The Graal binding creates/attaches/detaches threads and exposes explicit shutdown. The ARM64 product uses seven far-call veneers around the intact Graal image; actual device Release and signed export passed. Native phone execution remains unverified. Busy shutdown retains isolate ownership for explicit retry.

## Scope decisions

One active match per engine instance, 2–4 total seats: local human with 1–3 actual MAD opponents, or 2–4 Game Center humans. Rules are casual Commander FreeForAll, not tournament Duel Commander. AI JVM behavior is tested; native device validation flags remain false until phone acceptance.

The existing apps/ios product now has native setup/session/snapshot/prompt adapters and authenticated Game Center lobby/transport integration. apps/ios-ondevice remains only a diagnostic harness. Source and portable tests are not real multi-phone or rendered-UI acceptance. No host migration or persistent game resume is implemented. See TESTFLIGHT_ACCEPTANCE.md and UPSTREAM_MAINTENANCE.md for the remaining runtime gates and signed update process.
