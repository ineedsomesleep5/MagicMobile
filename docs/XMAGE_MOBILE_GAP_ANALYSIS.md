# XMage Mobile Gap Analysis

This analysis is tied to the current repo shape and Commander-only product scope. The goal is a polished mobile/web Commander client powered by XMage, not a separate Magic rules implementation.

## Current Pause State - June 22, 2026

Latest continuation on June 23, 2026:

- The dev-only fixture harness is still disabled by default and production-disabled. Fixture mode now has an embedded same-JVM startup path that can reach XMage's server-side `GameController` / `Game.cheat(...)`, and the rebuilt fixture-mode stack reached ready locally.
- Bridge command routing was corrected to mirror XMage desktop default card-click behavior: `play_land`, normal `cast_spell`, basic `make_mana`, and playable-object `activate_ability` submit the source card UUID, while `activate_ability` still validates the selected ability UUID. This is a generic playable-object route fix, not card-specific logic.
- The latest focused `commander-gauntlet` run passes on the real bridge path with deterministic same-JVM fixture setup, `source: "xmage-java-bridge"`, `directStateSeeded: true`, `seededStateVerified: true`, and `stepsBlocked: []`.
- The focused `activated-ability-stack` fixture also passed live against real XMage after the latest bridge rebuild. It proved Seal of Cleansing activation, `GAME_CHOOSE_ABILITY`, `GAME_TARGET`, Sol Ring target selection, stack observation, and pass priority with `routeFamiliesMissing: []` and `stepsBlocked: []`.
- Do not mark real iPhone alpha ready yet. The backend gauntlet is green, but commander damage, real blocker assignment, and prompt-variety are later-scope unless explicitly moved into the alpha gate, and real iPhone manual QA is still unchecked.

Latest follow-up on June 22, 2026:

- Native iOS command encoding was fixed for the core `LegalAction` routes already exposed by XMage: keep, mulligan, play land, cast spell, pass/yield, concede, tap/untap, make mana, activate ability, and typed declare-attacker/blocker payloads. The phone client now preserves `commandTemplate` metadata such as source zone, card name, and combat pairs instead of dropping it before submission.
- Verified after that iOS fix with `pnpm typecheck`, `xcodegen generate --spec apps/ios/project.yml`, a generic iOS `xcodebuild` with signing disabled, and `pnpm --filter @magicmobile/xmage-gateway test`.
- A dev-only fixture harness route exists at `POST /dev/xmage-fixtures/commander`, guarded by `ENABLE_XMAGE_FIXTURES=true` and `NODE_ENV !== production`. It reports fixture metadata and now fails explicitly instead of treating deterministic real-XMage deck creation as release-gate proof.
- Deterministic real-XMage state seeding is implemented as a dev/test-only same-JVM hook and is live-proven by the current gauntlet. The proof requires `directStateSeeded: true` only after `Game.cheat(...)`, `GameController.updateGame()`, and a refreshed real `GameView` snapshot confirm the seeded cards/zones.

The latest real-XMage general smoke now passes on the local Docker stack after two generic bridge fixes:

- `GAME_TARGET` / `GAME_SELECT` UUID actions no longer auto-send a boolean immediately after the UUID. XMage desktop sends the UUID for normal clicks and uses `false` only for the explicit Done/OK button; auto-sending a boolean could race and overwrite the UUID response.
- `GAME_PLAY_MANA` choices are derived from the human player's actual `ManaPoolView`, so generic costs use available floating mana instead of exposing fake choices.

The current confirmed command path is:

```sh
XMAGE_GATEWAY_URL=http://localhost:17171 pnpm smoke:xmage
```

Latest June 23 evidence: the broad smoke starts a real `xmage-java-bridge` game, keeps, passes priority, waits for AI, plays a Forest, and exposes real cast actions. Before the final `make_mana` source-UUID fix in this pause, it looped on `Tap Forest` because XMage did not treat the submitted ability UUID as the default land click. The bridge has now been patched so basic mana uses the source card UUID; rerun this smoke after rebuilding the bridge image.

The next blocker is targeted fixture startup reliability. A follow-up run of:

```sh
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=blocker-flow pnpm smoke:xmage
```

initially failed before gameplay with `Timed out waiting for XMage game snapshot` after XMage reported a disconnect/reconnect and forced join for a disconnected human. A rerun after the bridge settled passed and reported `combatExercised: true`.

The current blocker has moved to the commander-state fixture:

```sh
XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-replacement-tax pnpm smoke:xmage
```

The latest run reproved commander tax after casting Isamaru, but failed before commander damage because XMage AI stalled at turn 3 precombat main with priority on `ai-1`. Do not mark commander damage live-verified from the latest run until this smoke reports a non-empty `commanderDamageChanges` array.

| Feature | Current repo status | Needed for real XMage mobile play | Gap severity | Files involved | Recommended next step |
|---|---|---|---|---|---|
| XMage bridge health | Gateway and Java bridge expose health; Docker compose wires bridge/gateway/web. Local Docker health was verified ready on June 22, 2026. | Health must also be proven on production hosts. | small | `apps/xmage-gateway/server.mjs`, `apps/xmage-gateway/bridge/MagicMobileBridge.java`, `docker-compose.yml` | Keep live health evidence in playtest notes and add production smoke evidence separately. |
| Commander table creation | Java bridge creates a 1v1 Commander table with human plus one XMage AI. Local smoke created a real `xmage-java-bridge` Commander game. | Stable table creation for selected human and AI decks. | small | `MagicMobileBridge.java` | Keep live create-game smoke mandatory. |
| Joining seats | Current real path supports one human and one AI. | Human-vs-human and pods later need per-player join/reconnect. | medium | `MagicMobileBridge.java`, `packages/shared/src/types.ts` | Do not expand yet; keep future data model compatible. |
| Deck submission | iOS/web send Commander deck lists; bridge converts to XMage deck lists. | Exact card compatibility errors from XMage before start. | medium | `apps/ios/MagicMobile/MagicMobileAPI.swift`, `MagicMobileBridge.java`, `packages/deck` | Add bridge card-lookup preflight or clearer deck-load failure output. |
| Opening hand / mulligan / keep | Supported in mock and bridge; iOS/web expose actions. Live smoke verified one keep path. | Multiple mulligans and keep must work live without duplicate taps. | medium | `ContentView.swift`, `ArenaBattlefield.tsx`, `MagicMobileBridge.java` | Add repeated mulligan branch to live smoke. |
| Player-specific snapshots | Opponent hand/library hidden as placeholders for 1v1 AI; APIs are not viewer-scoped. | Viewer-scoped snapshot and WebSocket for human multiplayer. | large | `packages/shared/src/types.ts`, gateway routes, web/iOS APIs | Add before human-vs-human milestone. |
| Full zones | Shared zones include library, hand, battlefield, graveyard, exile, command, stack. | Mobile drawers for all public/owned zones and searched/revealed/looked-at zones. | small | `types.ts`, `ContentView.swift`, `ArenaBattlefield.tsx` | Finish zone drawers and manual checklist coverage. |
| Command zone | Rendered from command objects/zones. | Commander replacement prompts and commander tax must stay authoritative. | medium | `MagicMobileBridge.java`, iOS/web play UI | Live test command-zone replacement. |
| Commander tax | Live verified on June 22, 2026 through real `XMAGE_GATEWAY_URL=http://localhost:17171 XMAGE_SMOKE_SCENARIO=commander-replacement-tax pnpm smoke:xmage`; bridge parses XMage command-card rules such as `1 time played from the command zone`. | Keep regression fixture green and render tax from XMage only. | small | `MagicMobileBridge.java`, smoke runner, iOS/web HUDs | Keep targeted `commander-state` smoke as release gate. |
| Commander damage | Previously live-verified on June 22, 2026, but not reproven in the latest run. Latest `commander-state` reached commander tax, then XMage AI stalled before combat damage. | Keep damage matrix tied to XMage rules text; do not fabricate if missing. | medium | `MagicMobileBridge.java`, smoke runner, iOS/web HUDs | Make `commander-state` AI-stall-resistant and require non-empty `commanderDamageChanges`. |
| Commander Gauntlet | A real `XMAGE_SMOKE_SCENARIO=commander-gauntlet` gate now exists with a legal singleton deck and reports completed/blocked steps from the real bridge. Latest run proved land, mana, command-zone commander cast, pass priority, and AI continuation, but still failed on unavailable one-of proof cards. | A passing full acceptance loop: mana rock, fetch/search, commander cast, stack/trigger/ability, commander removal/replacement, recast tax, and AI continuation. | large | `apps/xmage-gateway/scripts/smoke-create-commander-game.ts`, `MagicMobileBridge.java`, docs | Add a smoke-only real-XMage setup hook or equivalent upstream-supported deterministic setup so singleton test cards are available after shuffling. |
| Stack | Bridge exposes stack objects; UI renders stack details. Live smoke cast a simple spell and passed priority, but does not yet assert full stack detail shape. | Paid/unpaid status, source/controller, and resolution must be live-verified. | medium | `MagicMobileBridge.java`, `ArenaBattlefield.tsx`, `ContentView.swift` | Add cast/pass/resolve stack assertions to smoke. |
| Priority | Snapshot exposes active/priority/waiting player; live smoke verified `pass_priority` moves into an AI-waiting state without simulator fallback. | More pass/yield variants must be proven, including response windows and next-turn skip. | medium | `MagicMobileBridge.java` | Add dedicated pass-until-response and pass-until-next-turn assertions. |
| Legal actions | Bridge maps playable objects; UI glows/renders actions. Pending command snapshots now expose only pending-safe actions to avoid stale duplicate submissions. | Every action must carry enough command template data to avoid client guessing. | medium | `types.ts`, `MagicMobileBridge.java`, `GameController.tsx`, `MagicMobileAPI.swift` | Make XMage legal actions template-complete over time. |
| Prompt envelopes | PromptEnvelopeV2 is broad. Live smoke verified confirmation, target/search-style, mana-payment, and combat-attacker prompt families. | Live coverage for every common Commander prompt family. | medium | `types.ts`, `MagicMobileBridge.java`, iOS/web prompt panels | Add prompt fixture decks and tests for mode/ability/pile/amount/order/blocker/commander-replacement prompts. |
| Prompt responses | Prompt id/message id and min/max validation exist; boolean prompts now fail closed when missing explicit answer. | No first-choice/default-answer fallbacks for required prompts. | small | `MagicMobileBridge.java`, iOS/web command builders | Keep fail-closed tests and remove remaining unsafe defaults. |
| Target/card/player/mode/ability/amount/mana prompts | Modeled and mostly rendered; mana prompts were live-smoked after exposing real battlefield mana-source actions during `GAME_PLAY_MANA`; target/search-style prompts now infer `selected 0 of N` counts from XMage callback text. | Multi-select and option-specific command templates need more UI polish. | medium | `ContentView.swift`, `ArenaBattlefield.tsx` | Add prompt selection state for min/max and order. |
| Cost payment | Transport exists; UI is basic; pay/decline command templates now preserve explicit `pay: true/false`. | Clear pay/decline and mana payment prompts. | medium | `MagicMobileBridge.java`, iOS/web prompt panels | Add explicit pay-cost UI and smoke fixture. |
| Trigger/replacement ordering | Modeled as ordered items; UI placeholders exist. | Reorderable mobile/web surfaces. | medium | `types.ts`, `ContentView.swift`, `ArenaBattlefield.tsx` | Add reorder UI once bridge exposes real ordered items. |
| Commander replacement | Modeled; bridge requires explicit boolean. | Clear command-zone/original-zone choices. | medium | `MagicMobileBridge.java`, iOS/web prompt panels | Add live commander death/exile test. |
| Attack/block/combat damage | Partially live verified on June 22, 2026 through real smokes. `XMAGE_SMOKE_SCENARIO=blocker-flow` exposed and submitted typed `declare_attackers`; the latest `commander-state` run stalled before reproving combat damage. | Typed blockers, combat damage, and damage-assignment prompts still need deterministic live fixtures; UI still needs better combat picker polish. | medium | `MagicMobileBridge.java`, iOS/web play UI | Keep combat fixture as release gate; make commander-state AI-stall-resistant, then add blocker and damage-assignment fixtures. |
| Pass/yield actions | Pass-until actions exist; `pass_priority` has live smoke proof. | Clear Done/Pass/Skip states and exact bridge mapping for all pass variants. | medium | `MagicMobileBridge.java`, iOS/web action docks | Add targeted smoke for `pass_until_response` and `pass_until_next_turn`. |
| Reconnect snapshots | iOS has WebSocket/polling behavior; gateway broadcasts snapshots. | Player-scoped reconnect and stale revision handling for human games. | medium | `ContentView.swift`, `server.mjs`, shared contracts | Add manual reconnect button/test. |
| `/play` real XMage | Web `/play` uses XMage and shows setup when unavailable. | Preserve fail-closed behavior. | none | `apps/web/src/app/play/page.tsx`, `apps/web/src/lib/engine.ts` | Keep regression tests. |
| `/dev/play-simulator` | Separate dev route. | Clearly dev-only, never product proof. | none | `apps/web/src/app/dev/play-simulator/page.tsx` | Keep labels and tests. |
| iOS prompt UI | Broad prompt UI exists, with gaps for multi-select/order/combat. | Full universal prompt handling for Commander. | medium | `apps/ios/MagicMobile/ContentView.swift` | Add min/max selection state and combat pickers. |
| Web prompt UI | Broad prompt panel exists, with gaps for multi-select/order/combat. | Same prompt contract as iOS. | medium | `apps/web/src/app/play/ArenaBattlefield.tsx` | Add selection-state tests. |
| Scryfall display/cache | Server/card cache packages and iOS local image/symbol cache paths exist. | Gameplay must not wait on missing art. | small | `packages/card-data`, iOS cache code, web card visuals | Test local cache download and missing-art fallback. |
| Deck import | TS and Swift parsers exist. | One reliable import/validation path for real Commander decks. | medium | `packages/deck`, `MagicMobileAPI.swift`, web deck pages | Prefer server parser for iOS imports later. |
| Moxfield/Archidekt text import | Pasted text supported; links exist. | Keep no-scrape text import policy clear. | small | `packages/deck/src/parser.ts`, iOS deck import UI | Clarify URL fields are not scraped. |
| Bracket/deck analysis | Analyzer/generator exist. | Not central to real XMage play. | small | `packages/deck` | Keep from blocking real gameplay. |
| EDHREC policy | Link-out/disabled provider only. | No scraping. | none | `packages/recommendations`, `docs/data-policy.md` | Preserve fail-closed provider. |
| Future webcam/hybrid readiness | Types and placeholder rooms exist. | Not current product. | medium | `packages/realtime`, `packages/video`, room pages | Mark future/not-current where shown. |
