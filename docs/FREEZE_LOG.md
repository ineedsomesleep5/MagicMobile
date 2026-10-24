# Freeze log

Why: on 2026-10-24 TestFlight got "froze in ranked" with no crash log (a freeze leaves none) and the server had no trace
of the game. The phones now keep their own record of a freeze and send it only when the player taps Send.

## What counts as a freeze

| Kind | Rule | Where |
| --- | --- | --- |
| `hang` | The main thread didn't answer a watchdog ping for 2 s or more. Saved the moment it's noticed (iOS may kill a stuck app before it recovers); the duration is updated if it recovers. | watchdog thread |
| `answer-not-accepted` | You answered and the engine hasn't replied for 20 s. | `FreezeRules.stall` |
| `engine-quiet` | The game is on, nothing is asking you, and the game hasn't changed for 120 s (solo, AI turns run up to about 70 s) or 180 s (a table with people). | `FreezeRules.stall` |
| `reported` | The player tapped Report a freeze in the game's menu. | game menu |

A stall is recorded once per episode: progress (a new snapshot, or the answer landing) starts a new one. The shared
cases are `apps/android/core/src/test/resources/parity/freeze-cases.json`; iOS (`FreezeRules`) and Android
(`FreezeRules.kt`) both run them.

## What an incident holds

- the kind, the time, how long it lasted (hangs);
- app version and build, OS, device model, thermal state, the app's memory footprint, foreground or background;
- the game: mode (quick, ranked, custom, table), round and step, whose turn, whether a prompt waits on you and its kind
  and message, the pending answer's label, busy/auto-pass/smart-pass state, the session status and error text, seconds
  since the game last changed;
- the last 80 breadcrumbs: game start, matchmaking steps, each answer sent, each new snapshot (turn, step, prompt kind),
  errors, going to the background and back, memory warnings.

No account details, no deck lists. Prompt messages can name cards.

## Where it goes

- On the phone: `freeze-log.json` in the diagnostics folder (iOS Application Support/MagicMobile/Diagnostics, excluded
  from backups; Android's no-backup Diagnostics folder), the last 5 incidents. It's part of the diagnostics report sheet.
- To the developer, only on Send: the next launch after a freeze asks "The last game froze. Send the report?"; the
  game menu's Report a freeze records and sends at once (it asks first). Both call `mm_send_diagnostic`, which stores
  the text in `diagnostic_reports` (own rows only, 64 KB, 20 an hour). Nothing reads it back to the app.

Read the reports with SQL: `select created_at, platform, build, kind, report from diagnostic_reports order by created_at desc`.
