# Unresolved native/engine work — do not hide these gates

| Gate | Current state | Required proof |
|---|---|---|
| Complete XMage + adapter compile | Passed against pinned real sources on 2026-09-11; adapter fixes remain under regression | Real selected modules, generated registry and adapter compile together without fake Mage classes |
| Actual match semantics | Current adapter completed two- and four-human-seat Commander games at turns 16 and 41, plus a token/mulligan game; ten seeded Commander rule groups passed | Broader representative games and prompt/combat UI acceptance, then expand coverage |
| Card/set registry on full catalogue | 32,275 card factories, 587 sets, 92,166 printings exported; no unregistered printing reference | Exclusions remain reviewed implementation categories, not claimed universal playable coverage |
| Native runtime/toolchain | ORMLite compiler fault minimized and dependency fix tested; local 4/5 GiB compiler configurations saturated; unsigned Intel hosted build started | Working full-engine AOT compilation and genuine XMage execution |
| iOS libraries | Non-XMage x86_64 iOS simulator probe executed create/call/teardown successfully in run 34666765499; longer full ARM64 engine build remains running after the earlier 75-minute timeout | Full XMage device + simulator engine artifacts, correct ABI/platform slices, runtime dependencies, and genuine gameplay |
| SwiftUI/GameKit SDK code | 32 package tests and 73 portable presentation tests passed; existing product compiled build-for-testing; hosted UI/geometry run 34669768265 active | Native-engine Xcode integration and device execution |
| Human prompt completeness | Typed native adapters and 23 prompt tests cover current query families, exact revisions, mana cancellation and nullable special choices | Real-engine UI fixtures for every gameplay prompt subtype and metadata shape |
| Turn/player control | Proxy, routing and permitted-visibility regression groups passed on JVM; nested control explicitly unsupported | Native UI consumption and full controlled-turn card-game acceptance |
| Hidden information | Real query/control/privacy regressions and per-seat hand-ID checks passed; not exhaustive zone coverage | Broader native XMage hands, morphs, libraries, exile and looked-at/controlled-player leak tests |
| Storage/restart | Not implemented | Durable, versioned full-game restore with random/hidden state preservation |
| Host migration | Not implemented | Correct state/authority transfer; do not substitute partial snapshots |
| Game Center lobby/client routing | Authenticated lobby, private deck exchange, ordered bounded RPC, correlations, suspension and retry implemented; bundle capability enabled | Real two-/four-phone matches, signing entitlement and background/disconnection acceptance; no host migration/reconnect claimed |
| AI | Real upstream MAD integrated; JVM tests observe land/cast/attack and cancellation/recreate; diagnostic native capability remains unvalidated | Native integration/runtime, mobile RAM/CPU/thermal benchmarks |
| Product UI | Existing board now has native snapshot/prompt adapters, setup names/AI/Game Center, four-seat opponent focus and authorized zones; release switch held for native linkage | Hosted UI acceptance, actual native gameplay and physical acceptance delivered through existing TestFlight |

## Specific source/runtime hazards

- `java.awt` appears even in HumanPlayer. Headless behavior on a JVM does not establish availability on iOS. Trace actual reachable classes and replace only their non-rules presentation dependencies where needed.
- Upstream includes SQL/H2/ORMLite paths. Direct deck loading avoids the ordinary deck lookup path, but other rules/helpers/validators may still access repository services. Audit and adapt those reachable paths; do not assume the database is gone.
- Dynamic reflection, serialized copies, plugin lookups and resources may occur beyond the patched card and set entry points. The supplied reflection metadata is broad and provisional, not a complete validated native manifest.
- Set singleton constructors may have initialization dependencies. If catalogue export touches a card before factories exist, separate source generation, generated-class compilation and catalogue execution into explicit phases.
- `GameView.toJson()` uses Gson. Validate nested types, reflection configuration and face-down/controller rules on the real engine. Do not strip unknown fields just to make serialization pass if they are semantically required.
- HumanPlayer copies and game rollback/simulation copies share response semantics. Macros and controlled-turn proxies are deliberately not silently emulated. Add genuine fixtures before extending them.
- An iPhone app can be suspended or terminated. The source only stops UI activity on backgrounding, and the host router can reject input while suspended. That is not game checkpointing or guaranteed continued hosting.
- Native destruction now uses ABI v2 and the distinct `mm_engine_shutdown_v2` export. Busy/failed shutdown retains ownership and does not tear down the isolate; Swift has explicit retryable close. C failure-path and Swift fixtures passed, but actual Graal/iPhone shutdown is unverified. Failed deinit or ambiguous SDK teardown intentionally retains allocations until process exit; production lifecycle must explicitly close/retry rather than rely on deinit.
- Gluon automatically copies objects from the package's `build/native` folder. Swift-close and C boundary test outputs now use separate fixture directories. A macOS runtime object from the old fixture output was observed in a toolchain probe's staging directory (not in its archive), then moved to a quarantine directory. Do not reintroduce fixture objects into Gluon's reserved native-input folder.

## What counts as progress

A desktop JVM match is valuable but not on-device execution. A desktop native shared library is valuable but not an iOS binary. A simulator build is valuable but not a physical iPhone RAM/thermal/offline result. Record each separately.

Do not weaken the source-hash checks to auto-apply patches to a changed upstream revision. Review the new sources and update lock hashes deliberately. Do not replace missing functionality with a rules approximation or a remote service without Caleb explicitly changing the product goal.
