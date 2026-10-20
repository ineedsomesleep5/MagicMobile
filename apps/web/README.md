# MagicMobile on the web: guest client (M2)

A desktop browser joins a **phone-hosted** cross-play table through the existing relay and plays the
game to its end. The host phone runs XMage; the browser runs no engine. It only renders its own seat's
snapshots and answers its own prompts, exactly like a guest phone (`docs/WEB_ENGINE_OPTIONS.md`, M2).

Not in this milestone: solo against the AI, hosting from the browser, ranked, Supabase sign-in, deck
import. Nothing here changes the relay, Supabase or Vercel.

## Run it

```bash
npm --prefix apps/web install
npm --prefix apps/web run dev        # http://127.0.0.1:5173 ; builds public/generated first
npm --prefix apps/web test           # parity goldens, shared cases, scripted-host guest flow
npm --prefix apps/web run build      # typecheck + static bundle in apps/web/dist
```

- `/?code=ABC234` or `/join/ABC234` prefills the table code. `?relay=http://127.0.0.1:8787` points at a
  local `wrangler dev` relay (default: the deployed relay).
- `?preview=2p-combat` (dev server only) plays against a scripted host that answers with one recorded
  engine poll from `apps/ios/MagicMobileTests/Fixtures/OnDevice` (`2p-priority`, `2p-battlefield`,
  `2p-combat`, `2p-attackers`, `2p-stack`, `2p-mana`). It never touches the relay. Good for layout work.

`scripts/prepare_data.py` (run by `dev` and `build`) writes `public/generated/` from the committed iOS
resources: the printing index (`printings.tsv`, whose header carries the catalogue hash and upstream
commit the guest presents) and the five precons. `scripts/prepare_images.sh` converts the tavern art
from the iOS asset catalogue into the committed `public/tavern/*.webp`.

## How a guest plays

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
