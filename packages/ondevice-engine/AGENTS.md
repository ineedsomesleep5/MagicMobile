# Implementation constraints

- XMage is the rules authority. Do not create a miniature MTG simulator and call it the port.
- No required external desktop computer, JVM process, localhost server, Docker, web gateway or cloud rules engine in the intended consumer path.
- Keep the Java rules source upstream-owned. Isolate mobile changes to platform/build/transport adapters where possible.
- Preserve exact player choice tokens/revisions and authenticated peer-to-seat binding.
- Do not serialize raw Game/GameState objects to peers. Test all nested hidden information, including face-down and looked-at zones.
- Only install the real compiled native backend in the application. C echo/recording transports and synthetic registry classes are test-only.
- Missing native code is an explicit error, never an automatic remote or simulator fallback.
- Do not claim iOS, full-card parity, AI, host migration, persistence or multiplayer success based on Linux/unit/fixture tests.
- The inspected source APIs are pinned; real compilation is still a gate, not a completed fact.
- Do not mark unavailable capabilities true or weaken validation to make a demo look complete.
- Avoid new remote writes or deleting legacy work outside the authorized repository. Keep changes reviewable in a local branch.
- Run the available tests after changes and keep real-engine/device results separate from fixture evidence.
