# Required actual XMage regression matrix (not executed in this handoff)

For every test below, run the same scenario on the pinned JVM baseline and the embedded native build. Compare legal choices and resulting normalized game state, not random UUID values. Do not claim parity from deterministic boundary fixtures.

| Scenario | Minimum acceptance |
|---|---|
| Basic game | Starting-player selection, mulligans, draw, land play, pay mana, creature spell, stack resolution, turns, combat and winner |
| Commander | 40-life selected variant, command zone, tax after repeat casts, commander damage, move-to-command-zone replacement and legal partner choices |
| Priority | Stack interaction, instant response, special actions, pass/hold semantics, no duplicate casts on retries |
| Targets | Required/optional/multiple targets, deselection, no legal targets, target becoming illegal before resolution |
| Payment | Mana abilities, floating colored/colorless mana, X amounts, alternate/additional costs, sacrifice/discard, cancellation |
| Advanced choices | Modes, trigger ordering, replacement order, search, ordered library cards, pile choice, individual/total multi-amount constraints |
| Card forms | Split, adventure, transform, MDFC land/spell, meld, copied spells/abilities, tokens and face-down cards |
| Viewer privacy | Opponent hands, library order, face-down permanent/exile identity, looked-at/revealed effects, nested card faces, spectators disabled |
| Four humans | Turn order, multiple defenders, simultaneous choices where applicable, a player leaving/conceding, terminal cleanup |
| Lifecycle | Destroy while waiting/resolving; no leaked worker; old response invalid after restart; no second game while shutdown is incomplete |
| Native | Correct callback threads, C memory lifetime, resource access, exception containment, first load with network unavailable |
| Networking | Bound peer seat, build mismatch, stale/duplicate frames, message fragmentation, size/rate limits, disconnect/host suspension |
| Controlled turns | Currently explicit unsupported error; must gain a validated response proxy and correct viewing permission before enabling |

Card examples can come from Caleb's decks after they are deliberately imported. This package does not bundle card artwork or claim an authoritative current legality list; the pinned upstream validator supplies the selected implementation's rules.
