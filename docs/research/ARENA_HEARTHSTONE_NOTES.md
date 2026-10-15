# Arena and Hearthstone behaviour research for MagicMobile

Research date: 2026-10-14. Search and fetch went through the TinyFish connector. A few pages were blocked (mtgsalvation, fandom wikis) and are not used.

Labels: **confirmed** = from code, protocol definitions or official Wizards/Blizzard pages. **likely** = community write-up, fan wiki or player analysis. **unknown** = no reliable public source.

**Provenance note.** An earlier draft quoted Arena enum and message definitions from a public repo whose files were extracted from Arena's installer. Those were removed (Caleb's project studies Arena only through its behaviour, its intended Player.log output, official announcements and community write-ups). What remains comes from those sources.

---

## A. Arena auto-pass and stops

### A1. Arena's pass controls

**What the controls do (likely).** The UI hotkey behaviour below is **likely**, from MTGAZone https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/, Draftsim https://draftsim.com/mtg-arena-keyboard-shortcuts/ and https://sites.google.com/view/beginners-guide-to-mtga/hotkeys-and-using-the-interface:

| UI action | Behaviour (likely) |
|---|---|
| Space | Pass priority once |
| Enter ("pass until response") | Passes through the turn until something you can respond to happens (opponent spell/ability, attack, blocks). You do NOT regain priority for triggers. |
| Shift+Enter (F6) | Passes the whole turn; you only regain priority to declare blockers |
| Ctrl | Temporary full control: no auto-pass in this phase. When you pass, Arena puts a stop on the next phase and releases full control. |
| Ctrl+Shift | Hold full control until toggled off |
| Click a phase icon | Sets a stop on that phase. Orange icons are your turn, blue are the opponent's. Stops are one-turn only. |
| Mobile: press and hold your avatar | Toggles full control |
| "Resolve All" button on the stack | Auto-resolves stack items. Players report it does not reliably skip prompts (https://www.reddit.com/r/MagicArena/comments/1nuhh1j/the_stack_needs_to_resolve_basic_triggers_faster/). |

Related UI toggles (likely, https://mtgazone.com/using-arena-interface-and-add-ons/): Auto Tap, Auto Order Triggered Abilities, Auto Choose Replacement Effects, Auto Assign Combat Damage. Full control disables auto-tap while active (Feb 2020 patch notes via https://draftsim.com/mtg-arena-patch-notes/).

### A2. Default ("smart") behaviour: stop or pass?

- **Basic rules (confirmed, Wizards, 2025-10-27, https://magic.wizards.com/en/news/mtg-arena/announcements-october-27-2025):**
  - A player typically does not get priority in their own upkeep or own end step.
  - A player usually does not get priority in response to a triggered ability they control.
  - "Smart priority" is a hand-maintained set of exceptions where Arena gives you priority so you do not need full control. Examples:
    - Urza's Saga chapter III gives priority to make a Construct.
    - Evoke sacrifice triggers give priority so you can crew a Vehicle or blink in response.
    - Flickerwisp returns give priority to activate abilities.
    - Wilderness Reclamation gives priority to float mana.
    - An opposing Sheoldred gives priority in your upkeep.
    - An opposing Goblin Rabblemaster in their main phase gives priority before combat.
    - A creature flashed in during your end step gives priority.
  - Wizards says cards not listed need a manual stop or full control.
- **Stop only if you have a play (likely):**
  - "MTG Arena only stops if you have an available play" (Draftsim, https://draftsim.com/mtg-arena-keyboard-shortcuts/).
  - Arena "will automatically pass priority through your opponent's turn if you have nothing to play" (https://sites.google.com/view/beginners-guide-to-mtga/hotkeys-and-using-the-interface).
  - Playable cards get a blue aura (https://mtgaassistant.net/Article/MTG-Arena-Match-Playing-Peculiarities-Guide).
- **Opponent casts a spell or activates an ability:**
  - **Likely** a stop only if you hold a castable/activatable response with a legal target. A 2019 thread describes that with no legal target for a removal spell, Arena auto-resolves the opponent's Legion Warboss and skips to combat before the player can act (https://www.reddit.com/r/MagicArena/comments/azud6g/they_really_need_to_fix_legion_warboss_and_other/).
  - There is no separate rule for "opponent activated an ability". It goes through the same available-action check. This is **likely**, not confirmed.
- **Something targets your permanents:** no distinct stop exists in any source I found. You get priority only through the same "you have a response" check. **Unknown** whether any special case exists.
- **Your own spells and triggers on the stack:** by default no priority (Wizards, above). "The most common case is responding to your own spell or trigger" and needing Full Control or a stop for it (MTGAZone, https://mtgazone.com/using-arena-interface-and-add-ons/).
- **Over-eager stops (likely).**
  - Any instant with a legal target keeps stopping for every item on a big stack (for example Restoration Magic during 10+ triggers).
  - Eldrazi Scion sacrifice abilities cause a stop "in response to anything" (https://www.reddit.com/r/MagicArena/comments/1nuhh1j/...). A Scion sacrifice is a mana ability with a side effect, which seems to count as a play.
  - Plain mana abilities (tapping a land) seem not to cause stops. This is **inferred**, not stated anywhere.
- **Information leak (likely):** a pause means you hold an instant, and a smooth auto-pass means you do not. Example: a pause after a spell with the opponent tapped out signals Pact of Negation (https://mtgazone.com/arena-hot-keys-and-interface-guide-simplify-your-game-with-these-easy-tricks/). Players bluff with Full Control or by stopping on every phase.
- **Full control and the timer:** full control makes the rope reachable on every priority, so it slows play (Draftsim above).

### A3. How Arena decides what is worth stopping for

- **Log-side facts (confirmed):** GRE messages are batched (over half of state-bearing events carry 2+ `GameStateMessage`s), and the log's `timers` field and `TimerStateMessage` carry rope data (https://garden.linusboyle.cn/source/clipped/Everything-We-Know-About-the-MTG-Arena-Log-File-in-2026). The 17lands client (https://github.com/rconroy293/mtga-log-client) is a draft/game-event uploader. I only read its README and did not find stop or auto-pass handling in it. I did not inspect its source in depth.

---

## B. Hearthstone presentation pacing (Power.log)

### B1. Blocks and animation sequencing

- **Block types (confirmed, python-hearthstone enum https://raw.githubusercontent.com/HearthSim/python-hearthstone/master/hearthstone/enums.py):** `ATTACK=1`, `JOUST=2` (renamed `CONTINUOUS`), `POWER=3`, `TRIGGER=5`, `DEATHS=6`, `PLAY=7`, `FATIGUE=8`, `REVEAL_CARD=10`, `GAME_RESET=11`, `MOVE_MINION=12`, `DECK_ACTION=13`. Removed or renamed: `SCRIPT`, `RITUAL`, `ACTION`, `TRADE`.
- **Meaning (confirmed, HearthSim https://hearthsim.info/docs/gamestate-protocol/):**
  - The protocol is flat, so a block is opened by `BLOCK_START` and closed by `BLOCK_END`. Blocks nest.
  - `PLAY` is a card being played. `POWER` is its on-play effect. `TRIGGER` is a reaction to something else. `ATTACK` is a combat attack. `DEATHS` is a separate pass that collects dead entities and moves them to the graveyard.
  - Their example: Arcane Intellect draws a creature, whose power triggers, which damages another minion, which draws again. The top `PLAY` block does not close until all of that has finished.
  - The block hierarchy "allows clients to keep track of what causes what, which is important in order to ensure animations play in the correct order, with the correct targets."
  - `META_DATA` packets exist only to guide animations (targets, damage numbers) and never mutate state.
- **Animation queue (confirmed):** Blizzard added a `PowerTaskList` log that "logs the animation queue - each game state delta block is logged as it happens on screen" (https://hearthsim.info/blog/fast-hearthstone-log-parsing/). So the server sends the whole block tree at once and the client drains it into an animation queue.
- **Server vs client time (likely):** effects resolve instantly on the server and the client lags behind, and Discover/choose UIs wait until the queued animations finish (https://www.reddit.com/r/hearthstone/comments/1ozo1bb/the_animation_system_is_the_single_biggest_flaw/; Blizzard forum https://us.forums.blizzard.com/en/hearthstone/t/end-of-turn-timer-question/78092).

### B2. Large repeated trigger chains

- **Constructed Hearthstone:** no published speed-up, batching or skip. Players report a long fixed per-effect animation, "some up to 10 seconds" (likely, same Blizzard forum thread), and a reported exploit where disconnecting makes the client skip the pending animations on reconnect (likely, same Reddit post). There is no fast-forward option. Nothing official contradicts this, but I found no official statement either, so it is **likely**.
- **Battlegrounds (confirmed, Blizzard 31.6 patch notes https://news.blizzard.com/en-us/article/24179332/31-6-patch-notes):** "Combat animations will now accelerate as the battle rages on (and then slow down towards the end, for a dramatic finish), to even out longer combat phases." Patch 34.2 increased the "Maximum Combat Speedup" cap in Duos (https://hearthstone.wiki.gg/wiki/Patch_34.2.0.231720). That implies a tunable cap. The numbers are **unknown**.
- **Arena (likely):** no batching and no animation skip. Players report 90-second resolution of token/lifegain chains, losing to the timer while the client animates, and restarting the client to skip the animations (https://www.reddit.com/r/MagicArena/comments/1nuhh1j/the_stack_needs_to_resolve_basic_triggers_faster/; https://www.reddit.com/r/MagicArena/comments/12192tq/is_there_a_way_to_skip_animations_i_have_lost/). Wishes for "Scute Swarm x250" style grouping are in the first thread.

---

## C. Timers

### C1. Arena

- **Numbers (likely, community; they differ by era):**
  - 2018, Hipsters of the Coast: "just over a minute" before the fuse appears, then 45 more seconds. Three timer "pips" make one timeout, and a timeout is used automatically when the fuse burns out (https://www.hipstersofthecoast.com/2018/03/how-to-play-mtg-arena-the-in-match-screen/).
  - 2018, Reddit: a timeout (hourglass) gives +30 s. You earn one per 3 full turns without the fuse showing. With no timeouts left, the turn or priority passes. 3 passes in a row concede (https://www.reddit.com/r/magicTCG/comments/9vwzy9/can_someone_explain_how_timeouts_work_in_arena/).
  - 2023, MTGA Assistant: fuse lasts 30 s, +30 s per timeout, one timeout per 3 fuse-free turns, and 2 auto-passes in a row lose the game (https://mtgaassistant.net/Article/MTG-Arena-Match-Playing-Peculiarities-Guide). The 3-vs-2 conflict with the 2018 source is unresolved.
  - Best-of-Three: 30-minute match clock (same MTGA Assistant article). Best-of-One has no match clock (a 2021 thread asks for one, https://www.reddit.com/r/MagicArena/comments/napfkf/best_of_1_really_needs_a_game_timer/).
  - 2026 player report: "like 2 minutes to resolve your turn", timeouts accrue only from quick turns, so early combo turns can time out (https://www.reddit.com/r/MagicArena/comments/1rdu5qv/arenas_timer_system_makes_certain_decks_literally/).
- **Animations count against the timer (likely):** the server has already resolved while the client animates, so the rope can burn during opponent or own trigger animations (https://www.reddit.com/r/MagicArena/comments/12192tq/is_there_a_way_to_skip_animations_i_have_lost/, https://www.reddit.com/r/MagicArena/comments/16kzczi/how_does_the_timeout_system_exactly_work/).

### C2. Hearthstone

- **Likely, from the fan wiki citing Blizzard staff (https://hearthstone.wiki.gg/wiki/Turn and https://hearthstone.wiki.gg/wiki/Gameplay):**
  - A turn lasts at most 75 seconds, plus "slush time" at the end to compensate for animations. The slush is added to the next turn start and does not always cover the full animation length.
  - A burning rope fuse appears across the board with about 20 s left. When it reaches the End Turn button, the turn ends.
  - If you take no action in a turn, your next turn starts with a faster fuse of about 7 s. As soon as you act, the fuse disappears and the turn extends to 75 s.
  - The game ends in a draw at turn 89 or 90.
- **Battlegrounds (confirmed):** Hero mulligan timer reverted to 70 s, and Duos turn timers were increased (https://hearthstone.wiki.gg/wiki/Patch_34.2.0.231720).
- **No chess-clock or banked extensions exist in Constructed.** I found no source for extensions. Treat that as likely, not confirmed.
- Disputed claims that players disable animations to gain extra actions are in the Blizzard forum thread above. They are **likely** hearsay.

---

## D. Ranked ladders

### D1. Arena constructed

- **Structure (confirmed official + likely):**
  - Ranks run Bronze, Silver, Gold, Platinum, Diamond, Mythic, each below Mythic with Tiers 4 to 1 (https://draftsim.com/mtg-arena-ranking-system/, 2026-03-11).
  - Official page https://magic.wizards.com/en/news/mtg-arena/ranked-season confirms reward tiers, monthly seasons, the reset table (partial), and a top-250 Mythic cutoff for Qualifier Weekend.
- **Steps (likely, Draftsim 2026-03-11; the official page does not publish them):**

| Rank | Bo1 win / loss | Bo3 win / loss | Steps per tier (Constructed) |
|---|---|---|---|
| Bronze | +2 / 0 | +2 / 0 | 6 |
| Silver | +2 / -1 | +2 / -2 | 6 |
| Gold | +2 / -1 | +2 / -2 | 6 |
| Platinum | +1 / -1 | +2 / -2 | 6 |
| Diamond | +1 / -1 | +2 / -2 | 6 |

  - Limited Bo1 uses +2/0 in Bronze, +2/-1 in Silver and Gold, +1/-1 in Platinum and Diamond, with 4 steps per Bronze tier and 5 per tier above.
  - Gold has been +2/-1 since April 2020 (https://hareeb.com/category/magic/, analysis post).
- **Protection (likely):** you never fall to a lower rank class, only lose tiers within it. Bronze losses cost nothing. The log's rank update has `wasLossProtected`, which confirms a protection mechanic exists (https://pkg.go.dev/github.com/gathering-gg/parser, `RankUpdated`).
- **Mythic (likely):**
  - Below Mythic is steps. In Mythic, the displayed percentile is your rating relative to the #1500 player's rating. The top ~1200 see a leaderboard number instead of a percentile (Draftsim; Hareeb says 1,500 is the baseline).
  - Player analysis finds Elo-like behaviour: K about 20.5 for Bo1 and about 45 for Bo3, expected win rate capped to roughly 25% to 75%, minimum change about 5 (Bo1) and 10 (Bo3) points, and no detectable Glicko deviation (https://hareeb.com/category/magic/, 2022 data, treat as dated).
  - A WotC staff tweet (2019, quoted by Draftsim) says only "Glicko style" for MMR.
  - Pairing is rating-based below Mythic too (same analysis).
- **Season (confirmed):** about one month. October 2026 runs 2026-09-30 12:05 PT to 2026-10-31 12:00 PT. You must have played at least one ranked game in the format to get seasonal rewards (official page).
- **Reset table (official page lists up to Gold; the rest is Draftsim):**
  - Bronze 4 stays Bronze 4. Bronze 3 and 2 go to Bronze 4. Bronze 1 goes to Bronze 3.
  - Silver 4/3 go to Bronze 3. Silver 2/1 go to Bronze 2.
  - Gold 4 goes to Bronze 1. Gold 3/2/1 go to Silver 4/3/2.
  - Platinum 4 goes to Silver 1. Platinum 3 and 2 go to Gold 4. Platinum 1 goes to Gold 3.
  - Diamond 4 goes to Gold 3. Diamond 3 and 2 go to Gold 2. Diamond 1 goes to Gold 1.
  - Mythic goes to Platinum 4.
- **Rewards (confirmed, official page):** Bronze 1 pack. Silver 1 pack + 500 gold. Gold 2 packs + 1,000 gold + a card style. Platinum 3 packs + 1,000 gold + 2 styles. Diamond 4 packs. Mythic 5 packs.

### D2. Hearthstone (likely: fan wiki citing Blizzard blog and FAQ, https://hearthstone.wiki.gg/wiki/Ranked)

- **Structure:** 5 leagues (Bronze to Diamond) of 10 ranks each, then Legend. 3 stars per rank. Loss costs 1 star unless you are on a floor.
- **Star Bonus:**
  - It is a multiplier on stars per win, set at season start from last season's rank and MMR.
  - The minimum per last season's best rank: Bronze 10 and 5 get 2x, Silver 5 gets 3x, Gold 10 gets 4x, Gold 5 gets 5x, Platinum 10 gets 6x, Platinum 5 gets 7x, Diamond 10 gets 8x, Diamond 5 gets 9x, Legend gets 10x, high Legend gets 11x.
  - It drops by 1 each time you cross a floor, so climbing slows as you go.
- **Win streak:** 2 prior non-drawn wins double the stars gained. It does not apply at Diamond 5 or above, and it resets each season.
- **Floors:** every 5 ranks (Bronze 5, Silver 10, and so on). You cannot drop below a floor for the rest of the season.
- **Legend:** a numbered leaderboard rank by region.
- **Season:** monthly. Everyone resets to Bronze 10. MMR is not reset. Matchmaking is MMR-based even after the bonus stars run out (patch 29.6, 2024-06-17).
- **Rewards:** a Highest Rank Bonus chest (needs 5 or more ranked wins) and a season card back (5 wins).
- Last overhaul: April 2020. The Apprentice league was removed in 2023.

---

## E. Animation durations

- **Arena:** **unknown.** I found no published or measured durations for cast-spell/stack display, removal, or turn-start banner. There is no animation-speed or skip setting (Draftsim settings guide https://draftsim.com/mtg-arena-settings/, and the 2023 thread above). Only anecdotes exist: a token/lifegain stack taking 90 seconds, and "5-minute combo" feel (Reddit threads cited in B2 and C1). Treat any number as something to measure from your own captures.
- **Hearthstone:** **unknown** for standard animations. A forum post says "some up to 10 seconds" (Blizzard forum thread in C2, hearsay). Battlegrounds combat acceleration has no published numbers (31.6 notes only describe the behaviour).

---

## What this suggests for MagicMobile

**Smart auto-pass**
1. Drive stops from a server-computed list of available actions per priority, like Arena's `ActionsAvailableReq`. Stop only when something other than Pass and plain mana abilities is available (a castable spell, a legal-target ability, a mana ability with a side effect such as a sacrifice).
2. Default to no priority for your own upkeep, your own end step, and your own triggers on the stack. Add a small, data-driven "smart priority" exception table keyed by card/ability (Arena's list in the Oct 2025 announcement is a ready seed). Include the opponent Rabblemaster-before-combat case, which Arena only fixed per card.
3. Offer explicit modes: pass once; pass until opponent action (leaves your triggers un-prompted); pass turn (still prompts blocks); temporary full control (releases on next pass); held full control; one-turn stops per phase (blue = opponent's turn, orange = yours). Mobile: press-and-hold avatar toggles full control.
4. Add per-ability auto-yield and a real "resolve all" that also skips prompts it can answer safely. Arena has the protocol fields but players say the UI falls short. Do not stop for the whole stack of a 100-trigger chain.
5. Counter the information leak: a pause tells the opponent you hold an instant. Consider adding a short, uniform delay on every opponent priority pass. This is a design choice.
6. Beware the Warboss edge case: if the player has no legal play, the engine may skip ahead before they can set a stop. Give pending opponent triggers a stop opportunity regardless.

**Animation pacing**
7. Separate resolution from presentation like Hearthstone: the engine resolves instantly and a presentation queue drains block trees, with each block tagged by cause (play, trigger, attack, deaths, targeting).
8. Accelerate with queue depth and slow down at the end, as Battlegrounds does (official 31.6 behaviour, with a tunable cap). Collapse identical repeated triggers into one "xN" entry. Offer a skip/fast-forward control. Never block input (Discover prompts, Pass) behind animations.
9. Do not charge animation time to the player. Hearthstone adds "slush" and Arena does not, and that is the most complained-about difference. Measure your own per-effect durations since no public numbers exist.

**Turn timer**
10. Use a per-decision rope plus a banked-extension system as Arena does (about 30 s fuse and +30 s per banked timeout, one earned per 3 fast turns is the most cited recipe), and consider a match chess clock for longer formats. Commander has up to four players, so key the rope to each priority decision rather than to each turn.
11. Add Hearthstone-style inactivity: after a turn with no action, shorten the next rope (about 7 s in Hearthstone) and auto-concede after N consecutive auto-passes (Arena: 2 or 3, sources conflict).
12. Pause the timer while animations or opponent trigger chains play, and keep the timer values server-sent (Arena's `timeoutDurationSec` and `maxTimeoutCount` show the right pattern).

**Ranked ladder**
13. Use a class ladder with tiers and step counts (Bronze to Diamond, 4 tiers, 6 steps each, then a Mythic-style percentile tier). Loss protection should never drop a class, Bronze should cost nothing on loss, and the season reset should be a partial drop table (Arena's table is a good template).
14. Borrow Hearthstone's accelerators: a star-bonus-style multiplier for new or returning players that decays with floors, and a streak bonus below the top ranks. Keep a hidden MMR that survives resets.
15. Commander is multiplayer. Arena's win/loss steps cannot be copied as-is. A placement-based step table (winner gains the most, last eliminated loses) with the same floors and protection is a design inference, not something these games do.
