# Roadmap, late 2026

Caleb's priorities after TestFlight 41 / Android 25, agreed on 2026-10-16. The Mac session owns integration and
releases; heavy runs go to cloud sessions or CI (never the 8 GB Mac). App features and engine changes ship in separate
releases. Every release goes to an internal-only TestFlight build and an Android test APK first; Caleb plays it before
External and the public APK. Update the checkboxes and the log as work lands.

## Releases at a glance

| Release | What | Kind | Depends on |
|---|---|---|---|
| A | Ranked Hall and live leaderboard, token restacking, heat and memory awareness | App + server | Step 1 of the engine plan can run alongside |
| B | Combo loop shortcut (solo games) | App | A shipped |
| C | Long-game AI and safe size cuts | Engine | Measurements (engine plan step 1) |
| D | GraalVM upgrade (Gluon JDK 23, `-Os`) | Engine toolchain | C shipped |
| E… | Cards as data (simple cards first, then composed cards in batches) | Engine | D shipped |

Details for C–E, measurements and checks: `docs/LIGHTER_ENGINE_PLAN.md`.

## Release A: Ranked Hall, leaderboard, token restacking

### Ranked Hall (the new Ranked entry)
Choosing Ranked opens a Ranked Hall before matchmaking, in the Walnut Tavern style (`docs/TAVERN_STYLE.md`):
- Your rank card: animated badge, division and pips, record, season name and days left.
- Two large choices: **Play Ranked** (today's lobby: deck, bracket, AI or person) and **Leaderboard**.
- A strip with last season's finish and your rank history.

### Leaderboard
- Server: `mm_ranked_leaderboard(scope, limit)` returning the season's top players by server standing
  (`ranked_standings`, the referee's numbers, so ranks can't be claimed from a phone), plus the caller's own row and
  neighbours. Scopes: everyone and friends. Profile visibility is respected (private players never appear; friends-only
  players only to friends), blocked players are hidden, anonymous callers refused. Online status from `presence`
  (seen in the last two minutes, and "in a game" when known). PGlite tests like the other ranked functions; the
  migration goes live with Caleb's go-ahead.
- Apps (iOS and Android together): a podium for the top three with their badges, a list that refreshes every
  15–30 seconds while open (polling, no realtime server cost), rows that animate when positions change, a glowing
  dot for players online now, Mythic rows with a shimmer, your own row pinned at the bottom when you're off-screen,
  and tapping a row opens that player's profile card.

### Token restacking
- A **Stack** chip at the end of any spread-out pile puts it back together.
- A pile opened to choose from restacks by itself when the choice or combat ends; a pile opened just to look stays
  open until Stack.

### Heat and memory awareness (engine plan step 2, app only)
- Shorter AI thinking and lighter effects while the phone reports heat; free memory on warnings and in the background;
  a per-game performance log.

## Release B: combo loop shortcut (solo)
- The app watches the player's own actions. After the same sequence three times in a row it offers **Repeat this
  loop**: 5, 10 or 20 times, or until an opponent loses.
- The app then presses the same answers itself, fast; the engine still runs and checks every step, so no rule is
  skipped. Effects are skipped during the repeats and a summary plays at the end.
- It stops and hands control back the moment anything differs: an opponent responds, a choice no longer exists, a new
  question appears, the loop stops changing the game, or a cap of a few hundred repeats; there is always a Stop button.
- Solo games against the AI first. Online games need the other player's agreement and a separate design.
- Tested with real combos on the JVM engine (for example Sanguine Bond with Exquisite Blood, a token sacrifice loop and
  an untap loop) and parity tests on both platforms.

## Log
- 2026-10-16: roadmap agreed: Ranked Hall and leaderboard, token restacking, combo loop shortcut, and the lighter engine
  plan including the GraalVM upgrade and cards as data.
- 2026-10-16: release A built on `claude/release-a` (PR #188): `mm_ranked_leaderboard` with PGlite tests (not live yet);
  Ranked Hall and leaderboard, Stack chip and auto-restack, heat/memory awareness on iOS and Android. Shorter AI thinking
  while hot needs an engine change and moves to release C. Online status uses the existing 90-second presence window.
