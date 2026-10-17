# Roadmap, late 2026

Caleb's priorities after TestFlight 41 / Android 25, agreed on 2026-10-16. The Mac session owns integration and
releases; heavy runs go to cloud sessions or CI (never the 8 GB Mac). App features and engine changes ship in separate
releases. Every release goes to an internal-only TestFlight build and an Android test APK first; Caleb plays it before
External and the public APK. Update the checkboxes and the log as work lands.

## Releases at a glance

| Release | What | Kind | Depends on |
|---|---|---|---|
| A | Ranked Hall and live leaderboard, token restacking, heat and memory awareness | App + server | Step 1 of the engine plan can run alongside |
| B | Next release (Caleb, 2026-10-17: as much as possible in it): messages between friends, the combo loop shortcut, push notifications if the keys are ready | App + server | A shipped |
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

## Release B: messages between friends and the combo loop shortcut
Caleb chose this as the next release on 2026-10-17 and asked for as much as possible in it, so it carries both app
features (neither changes the engine, so they may ship together). Messages come first in the work order, then the
combo loop; push notifications join if Caleb provides the Apple push key and a Firebase project. Building starts when
he says.

### Messages between friends
Caleb asked for messages between friends, beside the in-game table chat (which only works during a game).
- Server: a `friend_messages` table (sender, recipient, text, sent and read times) behind `mm_*` functions, like the
  rest of the social backend: send (friends only, never across a block, length cap, rate limit), list conversations
  with the last message and unread count, read one conversation in pages, mark read. Reports reuse `mm_report`;
  blocking hides the conversation both ways; deleting an account deletes its messages. PGlite tests; the migration goes
  live with Caleb's go-ahead.
- Apps (iOS and Android together, Walnut Tavern): a Messages tab in Friends with conversations and unread dots, a
  conversation screen (parchment bubbles, send box, quick replies from the table chat), a Message button on a friend's
  profile and in the friends list, and an unread badge on the Friends button. New messages arrive by polling while the
  app is open (about every 15 seconds in a conversation, with the 45-second heartbeat otherwise), at no server cost.
- Push notifications when the app is closed (in this release if ready): an Apple push key, a Firebase project for
  Android and a Supabase server function; otherwise they follow in a later release.
- Checks: PGlite tests (friends only, blocks, rate limit, pagination, read state), parity tests, UI tests on both
  platforms with the social fixtures.

### Combo loop shortcut (solo)
- The app watches the player's own actions. After the same sequence three times in a row it offers **Loop spotted**,
  with what one round does and a count picker (− / +, +5, +10) and three starts: **Repeat N×**, **Until I can't**
  (runs until a step can't be taken, a normal finish) and **Until they lose**.
- The app then presses the same answers itself; the engine still runs and checks every step, so no rule is skipped.
  Up to 10 rounds play their effects with a short pause between rounds; longer runs go fast and show the board once a
  round. The board never flashes the prompts the repeats answer. The running card lists the last rounds and notes
  such as "Kinjalli's Caller is gone, now Zacama".
- Choices are matched by kind, not exact card: the same target while it lives, then another of the same kind
  (an opponent's creature, a Squirrel token, never a Squirrel card). Mana comes from any source of the same mana.
  Passing priority is not part of a round; before a step taken with an empty stack, the loop passes so the player's
  own triggers resolve first (Chatterfang, Pitiless Plunderer).
- It stops and hands control back with a reason: an opponent responds, a step or target is gone ("no opponent's
  creature left to choose"), a question the round doesn't answer, an open-ended loop stops changing the game for 3
  rounds (power/toughness, damage and tapping count as changes), or 300 rounds; there is always a Stop button.
- Solo games against the AI first. Online games need the other player's agreement and a separate design.

## Log
- 2026-10-16: roadmap agreed: Ranked Hall and leaderboard, token restacking, combo loop shortcut, and the lighter engine
  plan including the GraalVM upgrade and cards as data.
- 2026-10-16: release A built on `claude/release-a` (PR #188): `mm_ranked_leaderboard` with PGlite tests (applied live 2026-10-16 with Caleb's go-ahead; grants checked: authenticated only);
  Ranked Hall and leaderboard, Stack chip and auto-restack, heat/memory awareness on iOS and Android. Shorter AI thinking
  while hot needs an engine change and moves to release C. Online status uses the existing 90-second presence window.
- 2026-10-17: Caleb played TestFlight 42/43 and Android 26: the Stack chip and Ranked Hall work well and games felt
  smooth. Game Performance moved into Settings (#189). Added messages between friends to the plan as the next release,
  then folded the combo loop into the same release (release B: as much as possible in the next release); not started
  until he says.
- 2026-10-17: release B built on `claude/release-b`: friend messages (server `friend_messages` + `mm_message_*`, PGlite
  tests; Messages tab, conversations, Message buttons, unread badge, and in games a Messages button plus a banner,
  as Caleb asked: messages outside and inside games) and the combo loop shortcut (solo games), on iOS and Android.
  Push notifications not included (no Apple push key or Firebase project yet). Live migration waits for Caleb.
- 2026-10-17: Caleb tested the combo loop in TestFlight 45 (Chatterfang + Pitiless Plunderer): it stopped after 2
  rounds (the stuck check ignored +X/−X changes and new Squirrel tokens), flashed choice pop-ups, and he wanted a count
  picker, "until I can't", same-kind targets and a pace you can watch for small counts. All of it built on
  `claude/combo-loop-2` for iOS and Android (shared parity cases now carry target kinds).
