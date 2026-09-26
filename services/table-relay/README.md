# MagicMobile table relay

Lets iPhones and Android phones play at one table. The host's phone runs the XMage engine,
exactly as in a Game Center match; this Cloudflare Worker only passes the table's packets
between phones. It assigns every connection its peer ID and stamps each delivered message
with the sender's ID, which gives the apps the same trusted sender that `GKMatch` gives them.

Deployed: `https://magicmobile-relay.calebjfeliciano.workers.dev` (Workers free plan, one
SQLite-backed Durable Object per table code). Nothing is stored beyond the table's roster
and messages waiting for a phone that briefly dropped its connection; a table and its data
are deleted when everyone leaves or it sits idle for 30 minutes.

## Protocol 1

`POST /v1/tables` with `{"seats": 2…4}` → `{"code": "ABC234", "hostKey": "…", "seats": n}`.
Codes use `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Each caller (an IPv4 address, or an IPv6 /64) may
open 5 tables a minute, counted by Cloudflare's rate-limiting binding (`TABLE_CREATES` in
`wrangler.toml`) at each Cloudflare location. Over the limit the answer is HTTP 429 with
`Retry-After: 60` and `{"error":"rate_limited","message":…}`; the apps show the message.

`GET /v1/tables/{code}/socket?name=…` upgrades to a WebSocket (text frames, JSON). A phone says
who it is with WebSocket subprotocols, so no secret appears in a URL or a request log:

| Offered subprotocols | Meaning |
|---|---|
| `magicmobile.1, magicmobile.key.<hostKey>` | The creator opens the table and takes seat 1. |
| `magicmobile.1` | A guest takes the next free seat. |
| `magicmobile.1, magicmobile.resume.<token>` | A phone that dropped reclaims its seat within 90 seconds. |

The relay answers with the `magicmobile.1` subprotocol, including when it turns a phone away.
Android build 8 sends the same credentials in the query instead (`key=<hostKey>`,
`resume=<token>`, no subprotocol); the relay still accepts that form.

Peer IDs are `p<seat>-<random>`, so sorting them gives seat order; the host sorts first,
matching the Game Center lobby's rule that the first sorted peer hosts.

While the table is still filling, the host may send `{"t":"remove","id":peer}` to turn a joiner
away. That phone gets the `removed` error and its socket closes; the others get a roster without
it (never `gone`, which ends a table), and the next phone to join takes the freed seat number.
Once the table is full every phone has opened the match room, so the relay ignores `remove`, as it
does one from any phone but the host. A removed phone cannot resume its seat.

Relay → phone:

- `{"t":"welcome","you":id,"token":…,"code":…,"seats":n,"peers":[{"id","name","connected"}],"full":bool}`
- `{"t":"roster","peers":[…],"full":bool}` whenever someone joins, drops or returns
- `{"t":"msg","from":id,"d":"<packet JSON text>","p":{"id","i","n"}?}`; `p` marks one part of a split packet
- `{"t":"gone","id":…}` a player left or did not return in time
- `{"t":"error","error":code,"message":…}` then the socket closes (`no_table`, `table_full`,
  `host_missing`, `host_left`, `not_host`, `host_taken`, `resume_failed`, `removed`, `too_large`, `peer_backlog`)
- `{"t":"pong"}` answers `{"t":"ping"}` without waking the table

Phone → relay: `{"t":"send","to":id,"d":…,"p":…?}`, `{"t":"ping"}`, `{"t":"bye"}` (leave for good),
`{"t":"remove","id":peer}` (host only, while the table fills). Both apps ignore frame types they
do not know.

Frames are limited to 1,000,000 characters; the apps split larger packets into parts.

### Messages for a phone that is away

While a phone is away (up to the 90-second resume window), messages sent to it wait at the relay
and arrive in order, ahead of anything new, when it resumes its seat. Each waiting message is its
own storage entry, split into pieces of at most 524,288 characters, because SQLite-backed Durable
Objects refuse a key and value over 2 MB. One phone can have up to 512 messages and 8,000,000
characters waiting; a message that does not fit, or that storage refuses, gets its sender
`peer_backlog` instead of being lost.

A host's answer to a guest's engine request (a packet whose `type` is `reply`, sent by the seat-1
phone) is dropped once it has waited more than 15 seconds: the guest's request gives up after 15
seconds, so the answer would be discarded anyway. The apps encode packets with sorted keys, so the
relay recognises an answer by its ending, `…,"type":"reply"}`; for a split packet it checks the last
part and drops the whole packet. Every other message waits as before.

## Develop, test, deploy

```sh
node --test services/table-relay/test/relay.test.mjs          # runs wrangler dev locally
RELAY_URL=https://magicmobile-relay.calebjfeliciano.workers.dev node --test services/table-relay/test/relay.test.mjs
cd services/table-relay && npx wrangler deploy
```

The local run serves `test/strict-storage.js`: the relay with the 2 MB storage entry limit
enforced, since local SQLite accepts larger entries. `.github/workflows/table-relay.yml` runs the
local tests on pull requests and pushes to `main` that touch this folder. Locally the tests name a
different caller address (`CF-Connecting-IP`) for each table, so the creation limit only applies
where a test checks it; against a deployed relay, `createTable` waits out the limit instead.

Deploy the relay before app builds that use a new protocol feature: it keeps accepting what older
apps send. If Cloudflare refuses the `[[ratelimits]]` binding on the account's plan, remove that
block and deploy again; without the binding the relay opens tables with no limit.

The relay sits outside the pnpm workspace on purpose: it has no dependencies beyond `wrangler`
run through `npx`, so it never changes the monorepo lockfile.
