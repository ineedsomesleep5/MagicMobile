# MagicMobile on the web

Two ways to play from a desktop browser (`docs/WEB_ENGINE_OPTIONS.md`):

- **Solo against the XMage AI (M3, the front page).** The real engine (GraalVM Web Image build of the pinned
  XMage and the phones' adapter, `packages/web-engine`) runs in a worker on the player's own computer. No game
  server: only static files.
- **Guest at a phone-hosted table (M2, "Join a friend's table").** The host phone runs XMage; the browser renders
  its own seat and answers its own prompts through the existing relay.

Nothing here changes the relay, Supabase or Vercel. Not yet: hosting from the browser, ranked, sign-in, deck
import (only the five precons), save and resume, sounds.

## Run it

The engine bundle is a CI artifact (git-ignored), so fetch it once into `packages/web-engine/build/web`:

```bash
gh run download 39664967878 -n web-engine-bundle-ccd762ba2379153e -D packages/web-engine/build/web
npm --prefix apps/web install
npm --prefix apps/web run dev        # http://127.0.0.1:5173 ; builds public/generated first
npm --prefix apps/web test           # parity goldens, shared cases, smart pass, scripted-host guest and solo flows
npm --prefix apps/web run build      # typecheck + static bundle in apps/web/dist
```

Games against the AI can be played by a script, in headless desktop Chrome on the real engine (the installed Chrome;
`playwright-core` drives it). Serve the static build with `npx --prefix apps/web vite preview --port 5182`, then:

```bash
zsh scripts/dev/heavy.sh "web autoplay" -- node apps/web/scripts/play.mjs --url "http://127.0.0.1:5182/?debug" --me token-triumph --ai chaos-incarnate --games 1 --out /tmp/autoplay
```

It plays through the board's own controls (drag to cast, Auto Pay, All Attack, the browsers) and writes what the
board did per game: every answer and who sent it, the effects it painted (with a picture of each kind), banners,
reveals, the reading-hold check, missing resources and console errors. `--shots 6,10` adds pictures of the log and a
player card at those turns; `--polls` saves the raw engine polls for the replay fixtures. `--turns 30` concedes
through the menu after that turn, and `--concede-at 10` (the default) concedes once your life is that low and behind, or
an attack that would kill you unblocked comes; `0` plays it out. `--want-sweeper` mulligans for a hand with a board
wipe and casts the wipe once it would take three permanents.

That run (`claude/web-engine-heap`, GraalVM Community Edition) gives a 137 MB module (43 MB gzip). The M1 bundle
(run 39599683802, Oracle GraalVM, `engine.js`/`engine.js.wasm`) also works. `ENGINE_DIR=/path/to/bundle` points the
dev server elsewhere. In the Claude desktop app, the `web-solo` entry in `.claude/launch.json` starts the same server.

## Solo against the AI (M3)

1. **Setup** (`src/ui/SoloSetup.tsx`, Walnut Tavern): your name, a precon for you and one for the AI, AI skill 1–10
   (the phones' control and meaning, default 2) and who goes first: "Choose" (XMage asks you) or "Roll D20". The
   engine starts loading as soon as the page opens; Start waits for it.
2. **Engine** (`src/engine/`): `LocalEngine` fetches `/engine/manifest.json`, then a classic worker
   (`engine.worker.ts`) loads the module and the patched Web Image wrapper. Requests go through a
   SharedArrayBuffer (the worker's thread is blocked inside Java, `Atomics.wait`), replies come back as messages.
   One engine per page serves every game.
3. **Cache**: the module is stored in the Cache API (`magicmobile-engine`) under its SHA-256 from the manifest.
   A first visit downloads it with a progress bar, checks the hash, stores it and drops other builds; later visits
   read it from disk (1.7 s to ready on this Mac). The page calls `navigator.storage.persist()` and says whether the
   browser agreed. The dev server sends the module with `no-store` so it is not also kept in the HTTP cache.
4. **Game** (`src/table/soloTable.ts`): `create` with the phones' AI configuration (human `player1`, AI `player2`
   with `aiSkill`, no seeds), then the same `GuestSession` a relay guest uses, over the local transport. Seat
   `player1` answers XMage's starting-player question; in "Roll D20" mode the table rolls (you tap your die, the
   AI's rolls itself) and answers with the winner. Concede, a result screen with "Play again", and leaving
   concedes a running game and destroys the match.
5. **Polling**: the engine holds a poll while it plays and answers it at the next published snapshot, so the
   session polls again at once after a change (AI turns show as they happen), backs off when nothing changes, and
   waits on a 2 s heartbeat while it's your decision (`LocalPollSchedule`).
6. **Smart pass** (`src/core/smartPass.ts`, a port of `OnDeviceSmartPass`): as on the phones, routine priority
   with nothing to play passes by itself; it stops in your main phases and at the AI's attacks and end step when
   you hold a play, and lets your own spells resolve. Passes it made show in the log ("Auto-passed: …").

**Cross-origin isolation.** SharedArrayBuffer needs COOP `same-origin` and COEP `require-corp` on the page, set
for `vite` and `vite preview` in `vite.config.ts` (a static host needs the same headers). Every subresource must
then be same-origin or CORS: Scryfall images load with `crossorigin="anonymous"` (Scryfall sends ACAO `*`).

**Checked** on 2026-10-21 in the desktop app's browser pane (Chromium, 1024×768) on the 8 GB Mac: a full game to
the AI's win on turn 18 (the first turns by hand: land, cast with mana paid by tapping lands on the table, a dual
land's colour menu; the rest by an in-page script sending the same session actions), the D20 roll, a rematch,
concede and the way back to setup; first and cached engine loads.

**Untested:** Firefox, Safari and Edge; slower or smaller laptops; a real first download over the internet
(only from localhost); `persist()` granted (the pane said no); 4-player games from the web UI.

- `/?code=ABC234` or `/join/ABC234` prefills the table code. `?relay=http://127.0.0.1:8787` points at a
  local `wrangler dev` relay (default: the deployed relay).
- `?preview=2p-combat` (dev server only) plays against a scripted host that answers with one recorded
  engine poll from `apps/ios/MagicMobileTests/Fixtures/OnDevice` (`2p-priority`, `2p-battlefield`,
  `2p-combat`, `2p-attackers`, `2p-stack`, `2p-mana`). It never touches the relay. Good for layout work.

`scripts/prepare_data.py` (run by `dev` and `build`) writes `public/generated/` from the committed iOS
resources: the printing index (`printings.tsv`, whose header carries the catalogue hash and upstream
commit the guest presents) and the five precons. `scripts/prepare_images.sh` converts the tavern art
from the iOS asset catalogue into the committed `public/tavern/*.webp`.

## How a guest plays (M2)

1. **Relay** (`src/relay/relayTransport.ts`): `new WebSocket(url, ["magicmobile.1"])`; the relay never
   checks `Origin`. Handles `welcome`/`roster`/`msg`/`gone`/`error`, splits packets over 400,000
   characters into `p` parts (never inside a surrogate pair) and reassembles them per sender, resumes a
   dropped seat with its token (`magicmobile.resume.<token>` subprotocol) and pings every 20 s.
2. **Lobby** (`src/table/lobby.ts`, `guestTable.ts`): when the table is full, the browser waits for the
   host's `offer`, checks its build identity (`upstreamCommit`, `catalogueHash`,
   `ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1/chat-1/clock-1`) and AI settings, and sends
   its `submission` (name + resolved deck) on Ready. A different build ends the lobby with the apps'
   own explanation.
3. **Start**: the host's `start` carries the match ID, seat names and the D20 plan. The browser decodes
   the plan, rolls its own step (`rollStep`) and shows the host's `rollAdvance`s, then answers XMage's
   starting-player question with the shared winner.
4. **Game** (`src/table/remoteEngine.ts`, `guestSession.ts`): `hello`, `poll`, `respond` and `concede`
   requests with the host's epoch and an increasing sequence, 15 s timeouts, the same poll schedule as
   the phones (poll on the host's `revision` notice, promptly after an answer, a 15 s heartbeat
   otherwise) and the same pending-answer retry rule (same request ID; a rejection is final).
5. **Social and clock**: `chat` and `emote` packets with the shared rules (`TableChatText`, 0.5 s / 1.5 s
   flood limits, strong language masked on screen), the host's `clock` packets burn the rope on the
   medallion, and a hidden tab sends `presence` so the host pauses the table like a backgrounded phone.

## Shared logic: a TypeScript port, checked against the parity cases

The pieces a guest needs were ported from `apps/android/core` to TypeScript (`src/core/`) rather than
converting `:core` to Kotlin Multiplatform: a guest needs about 2,500 of its 15,800 lines, the KMP move
would touch Android's build and every `java.*` use, and the browser UI is TypeScript anyway. The port is
held to the same goldens the apps use:

| Port | Checked by |
|---|---|
| `snapshotAdapter.ts`, `promptAdapter.ts`, `messageLog.ts`, `models.ts`, `displayText.ts` | every `parity/golden/fixture-*.json` and `prompt-cases.json` (`test/parity.test.ts`) |
| `tableChat.ts` (chat text, filter, join links) | `chat-cases.json` |
| `turnClock.ts` (rules, packet, rope) | `turn-clock-cases.json` |
| `startingRoll.ts`, lobby, RPC, relay parts | `test/guestFlow.test.ts` against a scripted host |
| `smartPass.ts`, `messageLog.ts` auto-pass lines | `test/smartPass.test.ts` (the cases of `OnDeviceSmartPassTest.kt`) |
| `startingRoll.ts` generator, solo table | `test/soloFlow.test.ts` against a scripted local engine |
| `boardEvents.ts` (board events, the Arena pace, holds, the wipe recap) | `arena-pace-cases.json`, `combat-cases.json` (`test/arenaPace.test.ts`) |
| `smartPass.ts` Stop for Removal, skip modes | `smart-pass-cases.json` (`test/smartPass.test.ts`) |
| `autoPay.ts` | `auto-pay-cases.json` (`test/autoPay.test.ts`) |
| `arenaBoard.ts`, `promptAdapter.ts` answer actions | `arena-board-cases.json`, `answer-action-cases.json` |
| `gameLog.ts` (the log reader, combat reasons) | `text-cases.json` goldens, `combat-cases.json` log section (`test/gameLog.test.ts`) |
| `gameStats.ts` | `game-summary-cases.json` |
| `cardChoicePlan.ts`, `tokenArt.ts`, `playerStatus.ts` | the iOS unit tests' cases, ported (`test/cardChoicePlan.test.ts`, `test/tokenArt.test.ts`, `test/playerStatus.test.ts`) |
| the whole decision path (prompt, smart pass, Auto Pay, board events) | `parity/replay/*.json`, real games' polls, against iOS's trace in `parity/golden/replay-*.json` (`test/replay.test.ts`) |

When a parity case or golden changes for the apps, run `npm --prefix apps/web test` too.

## The board: Arena mode, horizontal

Solo games and relay tables play on the horizontal Arena board (`docs/ARENA_STYLE.md`), a port of the Duel Board
Prototype's landscape table (artifact T5NcAkjCThiA5hfd9Twwwu) driven by real snapshots:

The iOS Arena build is the reference (Caleb, 2026-10-21 and 2026-10-22): what it does, the web does, laid out for a
mouse and keyboard. `docs/WEB_PARITY.md` is the checklist, row by row with how each was checked, and lists the desktop
mapping (hover reads and pops, right-click or a held button opens the inspector, drag plays, Space passes and a held
Space is Full control, Enter confirms, Esc closes, Ctrl/Cmd+Z undoes mana) and what is intentionally different.

- `src/ui/arena/layout.ts`: iOS `ArenaLayout.landscape` on the 956-point plate: the opponent's lands and creatures at
  the top, yours below (lands from the left, support permanents on the right, planeswalkers and battles at the front
  row's end), the hand along the bottom edge (resting low, fanned up under the pointer), piles and medallion
  bottom-left, the stack card on the right. Every card on the table leans with it (`ArenaTableLean`).
- `src/ui/arena/ArenaCard.tsx`: every card is one element that glides between hand, stack and battlefield. With
  Card Frames off (the default, as on iOS) battlefield cards are the reference game's plain tiles; on, the tavern
  frames from `src/board/tileArt.ts`. Highlights are a CSS drop-shadow tracing the card's outline (the frame-outline
  glow). Abilities and triggers on the stack are Arena ability cards (`AbilityCard.tsx`).
- `src/ui/arena/Symbols.tsx`: the real Magic card back (libraries, the opponent's hand) and Scryfall's flat mana
  symbols (hand costs, floating mana, rules text). The Arena board has no 3D tavern pips.
- `src/ui/arena/Browsers.tsx`: the iOS browsers. No panel: the table dims under a serif title, the cards stand in the
  middle, answers sit under them as plaques, the card it's about stands on the right, and View Battlefield steps a
  browser aside. Question stage, mode and ability cards, choices (cards a choice names, colour symbols, search,
  Remember my choice), players as medallions, damage splits with lethal marks, pile wells, zones with Cast plaques,
  the stack. Numbers take the reference's pill in the button corner (hold − / + to repeat, arrow keys, Enter).
- `src/ui/GameScreen.tsx`: the corner plaques (Pass / Resolve / Attack / No Blocks / Cancel and a secondary), the
  phase strip, the smart-pass pill, medallions, menu and game log in glass, the Arena mulligan, D20 roll and result
  screens.

**Any window shape.** The board is 956 points wide and as tall as the window's shape allows, from 440 points
(2.17:1) to 717 (4:3); it re-flows live on resize. Positions in the middle of the table stretch in proportion, your
side stays anchored to the bottom edge and theirs to the top, and cards grow a little with the extra room
(`geometry()` in `layout.ts`). Under it lies the same table rendered for the nearest shape, so it is never stretched by
more than a few percent:

| Plate | Shape | |
|---|---|---|
| `public/arena/table.jpg` | 956 x 440 (2.17:1) | the prototype's plate |
| `table-195.jpg`, `table-169.jpg`, `table-1610.jpg`, `table-43.jpg` | 956 x 490, 538, 598, 717 | `scripts/render_arena_plates.sh` (Blender, the Arena renderer from `claude/arena-mode`, layouts in `scripts/arena_plates.json`) |

## Hosted on Vercel (unlisted)

https://magicmobile-web.vercel.app is the Vercel project `magicmobile-web` on Caleb's account (2026-10-21). It is
unlisted: nothing links to it and every response carries `X-Robots-Tag: noindex`, until Caleb decides between public
and private. It is a static deploy of a local build, since the engine isn't in git. To redeploy:

```
npm --prefix apps/web run build
node apps/web/scripts/stage_vercel.mjs
cd apps/web/.vercel-deploy && npx vercel@65.0.0 deploy --prod
```

`stage_vercel.mjs` copies `dist` and the engine into `apps/web/.vercel-deploy` (git-ignored). It gzips the module and
writes a `vercel.json` with the isolation headers. The folder keeps its `.vercel` link to the project between runs
(on a new machine: `npx vercel link --project magicmobile-web` inside it first).

Limits on the free Hobby plan:
- No static file over 100 MB. The module (137 MB) ships gzipped (44 MB) and the worker unpacks it.
- 100 GB of transfer a month: about 2,000 first-time engine downloads. Returning players load the engine from their
  browser's cache.
- Non-commercial use only.

Cloudflare's static assets have no transfer limit and allow commercial use, but cap files at 25 MiB, so the gzip copy
would have to be split into parts.

## Not done yet

- Ranked, friends, sign-in and deck import (later web steps); only the five precons are offered.
- **Paused 2026-10-20 (Caleb: M1 first) before any game against a real phone host.** Everything above is checked
  against fixtures and a scripted host only. Next: host a 2-player relay table on the Android emulator (simulator
  builds have no engine) and play it to the end from desktop Chrome; pods are untested.
- The out-of-game screens (iOS's Arena home, Play panel, deck boxes, options) are not ported; setup is still the
  tavern form (docs/WEB_PARITY.md section 9).
- The vertical (portrait) Arena layout isn't ported; the web board is horizontal only.
