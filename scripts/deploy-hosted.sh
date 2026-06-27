#!/usr/bin/env bash
# Deploy the current origin/main to the hosted MagicMobile server.
#
# Usage:
#   ./scripts/deploy-hosted.sh                 # deploy main, rebuild bridge, restart, health-check
#   MAGICMOBILE_DEPLOY_HOST=root@100.107.89.62 ./scripts/deploy-hosted.sh   # via Tailscale
#   SKIP_BRIDGE_BUILD=1 ./scripts/deploy-hosted.sh                          # gateway/web-only change
#
# The server (/root/MagicMobile) is a git checkout of origin/main using a read-only deploy key.
# See DEPLOY.md for the full topology and recovery instructions.
set -euo pipefail

HOST="${MAGICMOBILE_DEPLOY_HOST:-root@72.62.200.185}"
REMOTE_DIR="${MAGICMOBILE_REMOTE_DIR:-/root/MagicMobile}"
SKIP_BRIDGE_BUILD="${SKIP_BRIDGE_BUILD:-0}"

echo "==> Deploy target: $HOST:$REMOTE_DIR"

# 1. Make sure local main is pushed.
LOCAL=$(git rev-parse HEAD)
echo "==> Local HEAD: $LOCAL"
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "!! Working tree has uncommitted changes. Commit + push before deploying." >&2
  exit 1
fi
echo "==> Pushing origin main..."
git push origin main

# 2. On the server: pull, (build bridge), restart, health-check.
ssh -o BatchMode=yes "$HOST" \
  REMOTE_DIR="$REMOTE_DIR" SKIP_BRIDGE_BUILD="$SKIP_BRIDGE_BUILD" 'bash -seu' <<'REMOTE'
cd "$REMOTE_DIR"
export GIT_SSH_COMMAND="ssh -i ~/.ssh/magicmobile_deploy -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"
echo "==> git pull --ff-only"
git pull --ff-only origin main
echo "==> Deployed commit: $(git log --oneline -1)"

if [ "$SKIP_BRIDGE_BUILD" != "1" ]; then
  echo "==> Building xmage-bridge image"
  docker compose build xmage-bridge
fi

echo "==> Restarting services"
docker compose up -d xmage-bridge xmage-gateway web

echo "==> Waiting for bridge health"
for i in $(seq 1 45); do
  sleep 4
  if curl -fsS http://localhost:17172/health 2>/dev/null | grep -q '"status":"ready"'; then
    echo "bridge ready"
    break
  fi
  echo "...waiting ($i)"
done
echo "==> bridge:  $(curl -s http://localhost:17172/health)"
echo "==> gateway: $(curl -s http://localhost:17171/health)"
REMOTE

echo "==> Done. Tail cast diagnostics with:"
echo "    ssh $HOST \"docker logs --tail 200 magicmobile-xmage-bridge-1 2>&1 | grep CASTDIAG\""
