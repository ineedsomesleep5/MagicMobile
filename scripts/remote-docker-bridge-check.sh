#!/usr/bin/env bash
set -euo pipefail

HOST="${MAGICMOBILE_DEPLOY_HOST:-root@100.107.89.62}"
REMOTE_DIR="${MAGICMOBILE_REMOTE_DIR:-/root/MagicMobile}"
REMOTE_REF="${MAGICMOBILE_REMOTE_REF:-}"
STOP_REMOTE_DOCKER_AFTER="${STOP_REMOTE_DOCKER_AFTER:-0}"

ssh "$HOST" \
  "REMOTE_DIR='$REMOTE_DIR' REMOTE_REF='$REMOTE_REF' STOP_REMOTE_DOCKER_AFTER='$STOP_REMOTE_DOCKER_AFTER' bash -seu" <<'REMOTE'
started_docker=0

if command -v systemctl >/dev/null 2>&1 && ! systemctl is-active --quiet docker; then
  echo "==> Starting Docker daemon for remote bridge build"
  systemctl start docker
  started_docker=1
fi

cleanup() {
  docker builder prune -f --filter until=24h >/dev/null 2>&1 || true

  if [ "$STOP_REMOTE_DOCKER_AFTER" = "1" ] && [ "$started_docker" = "1" ]; then
    echo "==> Stopping Docker daemon started by this check"
    systemctl stop docker
  fi
}
trap cleanup EXIT

cd "$REMOTE_DIR"

if [ -f /root/.ssh/magicmobile_deploy_key ]; then
  export GIT_SSH_COMMAND="ssh -i /root/.ssh/magicmobile_deploy_key -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
fi

git fetch origin

if [ -n "$REMOTE_REF" ]; then
  git checkout --detach "$REMOTE_REF"
fi

echo "==> Building XMage bridge image on VPS from $(git rev-parse --short HEAD)"
docker build -t magicmobile-xmage-bridge-check apps/xmage-gateway/bridge
REMOTE
