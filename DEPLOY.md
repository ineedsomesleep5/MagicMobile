# Deploying MagicMobile

This documents how code reaches the **hosted server** that the iOS app and web client
talk to in production. The hosted server is the source of truth for live play; GitHub
`main` is the source of truth for code. Always land changes in `main` first, then deploy.

## Topology

```
iOS app / browser
   │  https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud   (no port → web routes)
   ▼
apps/web  (Next.js, container magicmobile-web-1, :3000)         ── /api/engine/* proxy
   ▼  ENGINE_MODE=xmage, XMAGE_GATEWAY_URL=http://xmage-gateway:17171
apps/xmage-gateway/server.mjs  (container magicmobile-xmage-gateway-1, :17171)
   ▼  XMAGE_BRIDGE_URL=http://xmage-bridge:17172
apps/xmage-gateway/bridge  (container magicmobile-xmage-bridge-1, :17172)  ── Java bridge + XMage
```

> The iOS app picks **web routes** vs **direct gateway routes** by port: a Server URL with
> port `17171`/`17172` uses direct gateway routes; anything else (the public HTTPS URL) uses
> the web app's `/api/engine/*` proxy. So the **web container must be current**, not just the
> gateway/bridge.

## Hosts

| Host | Address | Notes |
|---|---|---|
| Hosted server | `root@72.62.200.185` (public) or `100.107.89.62` (Tailscale `srv1420950`) | Runs all containers via Docker Compose at `/root/MagicMobile` |
| Dev Mac | `caleb-codex-mac` `100.105.112.22` | Local Docker stack for testing; gateway reachable at `http://100.105.112.22:17171` over Tailscale |

## How the server pulls code

`/root/MagicMobile` is a **git checkout of `origin/main`** authenticated with a **read-only
deploy key** (`~/.ssh/magicmobile_deploy`, configured in `~/.ssh/config` for `github.com`).
The deploy key is registered on the GitHub repo under **Settings → Deploy keys**
(`srv1420950-deploy`). `node_modules`, `.cache`, and `.pnpm-store` are gitignored and persist
across pulls.

- `apps/web` and `apps/xmage-gateway` run from the **volume-mounted working tree** (`.:/workspace`)
  and re-run `pnpm install` + build on container (re)start — so they pick up new code on restart.
- `apps/xmage-gateway/bridge` is a **built Docker image** (Java is compiled into it) and must be
  **rebuilt** to pick up changes to `MagicMobileBridge.java`.

## Deploy (the normal path)

From the dev Mac, after your change is committed:

```sh
git push origin main           # land it in GitHub first
./scripts/deploy-hosted.sh     # pull on server, rebuild bridge, restart, health-check
```

`scripts/deploy-hosted.sh` SSHes to the server and runs the steps below. Override the target
with `MAGICMOBILE_DEPLOY_HOST=root@100.107.89.62 ./scripts/deploy-hosted.sh` (Tailscale).

## Deploy (manual, on the server)

```sh
ssh root@72.62.200.185
cd /root/MagicMobile
git pull --ff-only origin main
docker compose build xmage-bridge          # only needed when the Java bridge changed
docker compose up -d xmage-bridge xmage-gateway web
# wait for health:
curl -s http://localhost:17172/health      # bridge
curl -s http://localhost:17171/health      # gateway
```

- Bridge changes → always `docker compose build xmage-bridge` before `up`.
- Gateway/web-only changes → just `docker compose up -d --force-recreate xmage-gateway web`
  (no image build needed; they reinstall/build from the mounted tree on boot).

## Recover the live code from the server

Because the server is a git checkout, you can always see exactly what's deployed:

```sh
ssh root@72.62.200.185 'cd /root/MagicMobile && git log --oneline -1 && git status --short'
```

If something was hot-patched directly on the server, `git status` will show it. Pull it back
into the repo before it's lost.

## Diagnostics

The Java bridge logs `[CASTDIAG]` lines for every `cast_spell`/`play_land` (canPlay membership,
priority owner, expected vs current revision, hand/stack/make_mana/prompt before+after):

```sh
ssh root@72.62.200.185 "docker logs --tail 200 magicmobile-xmage-bridge-1 2>&1 | grep CASTDIAG"
```

## iOS app

The native iOS client ships via TestFlight, not this server — see `scripts/ios/deploy-testflight.sh`.
Its default Server URL is the public HTTPS URL above; it can be pointed at the dev Mac
(`http://100.105.112.22:17171`) for local testing with live bridge diagnostics.

## Multi-user note (future)

Today this is single-user. Before a second human player (vs-human / pods), the bridge needs
**viewer-scoped snapshots** so hands and libraries are hidden per player — see
`docs/PLAYER_SCOPED_SNAPSHOTS_PLAN.md`. The gateway already has a `playerId` obfuscation hook
(`obfuscateSnapshotForPlayer`) that this will build on.
