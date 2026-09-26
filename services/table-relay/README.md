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
Codes use `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`.

`GET /v1/tables/{code}/socket` upgrades to a WebSocket (text frames, JSON):

| Query | Meaning |
|---|---|
| `key=<hostKey>&name=…` | The creator opens the table and takes seat 1. |
| `name=…` | A guest takes the next free seat. |
| `resume=<token>` | A phone that dropped reclaims its seat within 90 seconds. |

Peer IDs are `p<seat>-<random>`, so sorting them gives seat order; the host sorts first,
matching the Game Center lobby's rule that the first sorted peer hosts.

Relay → phone:

- `{"t":"welcome","you":id,"token":…,"code":…,"seats":n,"peers":[{"id","name","connected"}],"full":bool}`
- `{"t":"roster","peers":[…],"full":bool}` whenever someone joins, drops or returns
- `{"t":"msg","from":id,"d":"<packet JSON text>","p":{"id","i","n"}?}`; `p` marks one part of a split packet
- `{"t":"gone","id":…}` a player left or did not return in time
- `{"t":"error","error":code,"message":…}` then the socket closes (`no_table`, `table_full`,
  `host_missing`, `host_left`, `not_host`, `host_taken`, `resume_failed`, `too_large`, `peer_backlog`)
- `{"t":"pong"}` answers `{"t":"ping"}` without waking the table

Phone → relay: `{"t":"send","to":id,"d":…,"p":…?}`, `{"t":"ping"}`, `{"t":"bye"}` (leave for good).

Frames are limited to 1,000,000 characters; the apps split larger packets into parts.

## Develop, test, deploy

```sh
node --test services/table-relay/test/relay.test.mjs          # runs wrangler dev locally
RELAY_URL=https://magicmobile-relay.calebjfeliciano.workers.dev node --test services/table-relay/test/relay.test.mjs
cd services/table-relay && npx wrangler deploy
```

The relay sits outside the pnpm workspace on purpose: it has no dependencies beyond `wrangler`
run through `npx`, so it never changes the monorepo lockfile.
