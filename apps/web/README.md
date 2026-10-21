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

When a parity case or golden changes for the apps, run `npm --prefix apps/web test` too.

## The board

`src/board/TableScene.ts` draws the landscape Walnut Tavern plate (956 x 440 points, sockets from
`scripts/brand/tavern_layout.json`) through a pitched Three.js camera. Permanents lie on it as tiles in
the tavern frames (`tileArt.ts`: Scryfall art crop, frame, name ribbon, power/toughness gems); tapped
tiles tilt 12° and dim; glows follow the frame outline. Medallions, the pass disc, the mana rail and the
stack sit in the plate's own sockets as HTML. The hand is plain printed cards (Scryfall images) with
their mana cost capsule; the right column holds the decision, the stack, the log and chat.

## Not done yet

- Ranked, friends, sign-in and deck import (later web steps); only the five precons are offered.
- **Paused 2026-10-20 (Caleb: M1 first) before any game against a real phone host.** Everything above is checked
  against fixtures and a scripted host only. Next: host a 2-player relay table on the Android emulator (simulator
  builds have no engine) and play it to the end from desktop Chrome; pods are untested.
- No sounds, card moments or animations beyond tiles gliding into place.
