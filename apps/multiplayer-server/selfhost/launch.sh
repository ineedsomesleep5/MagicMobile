#!/usr/bin/env bash
set -euo pipefail
LAUNCHER_ROOT=$(cd "$(dirname "$0")" && pwd)
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  value=${value%$'\r'}
  [[ -z "$key" || "$key" == \#* ]] && continue
  case "$key" in SUPABASE_URL|SUPABASE_PUBLISHABLE_KEY|UPSTREAM_COMMIT|CATALOGUE_HASH|ADAPTER_VERSION|DATABASE_MIGRATION_READY|BIND_ADDRESS|PORT|JAVA_HEAP_MAX) export "$key=$value";; *) echo "Unknown configuration key: $key" >&2; exit 2;; esac
done < "$LAUNCHER_ROOT/server.properties"
[[ "${SUPABASE_URL:-}" =~ ^https://[A-Za-z0-9.-]+$ && "${SUPABASE_PUBLISHABLE_KEY:-}" =~ ^sb_publishable_[A-Za-z0-9_-]+$ ]] || { echo 'Use an HTTPS Supabase URL and public publishable key only.' >&2; exit 2; }
[[ "${UPSTREAM_COMMIT:-}" =~ ^[a-f0-9]{40}$ && "${CATALOGUE_HASH:-}" =~ ^[a-f0-9]{64}$ && "${ADAPTER_VERSION:-}" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo 'Invalid build identity.' >&2; exit 2; }
[[ "${PORT:-}" =~ ^[0-9]+$ && "$PORT" -ge 1 && "$PORT" -le 65535 && "${JAVA_HEAP_MAX:-}" =~ ^[1-9][0-9]*[mMgG]$ ]] || { echo 'Invalid port or heap size.' >&2; exit 2; }
[[ "$BIND_ADDRESS" == 127.0.0.1 || "$BIND_ADDRESS" == 0.0.0.0 || "$BIND_ADDRESS" == ::1 ]] || { echo 'Unsupported bind address.' >&2; exit 2; }
[[ "${DATABASE_MIGRATION_READY:-false}" == true ]] || { echo 'Setup pending: the reviewed Supabase matchmaking migration must be installed before setting DATABASE_MIGRATION_READY=true in server.properties.' >&2; exit 2; }
JAVA=${JAVA_HOME:+$JAVA_HOME/bin/}java
VERSION=$("$JAVA" -version 2>&1) || { echo 'Install Java 17 (Temurin) first: https://adoptium.net/temurin/releases/?version=17' >&2; exit 2; }
[[ "$VERSION" =~ version\ \"17\. ]] || { echo 'Java 17 is required. Select it with JAVA_HOME; no Java installer was run.' >&2; exit 2; }
while IFS='=' read -r key value || [[ -n "$key" ]]; do
  value=${value%$'\r'}
  case "$key" in URL) URL=$value;; SHA256) EXPECTED=$value;; DIRECTORY) RUNTIME_NAME=$value;; *) echo 'Invalid runtime manifest.' >&2; exit 2;; esac
done < "$LAUNCHER_ROOT/runtime.properties"
[[ "$URL" == https://github.com/ineedsomesleep5/MagicMobile/releases/download/* && "$EXPECTED" =~ ^[a-f0-9]{64}$ && "$RUNTIME_NAME" =~ ^runtime-[A-Za-z0-9._-]+$ ]] || exit 2
RUNTIME="$LAUNCHER_ROOT/.runtime/$RUNTIME_NAME"
if [[ ! -f "$RUNTIME/.verified-archive-sha256" ]]; then
  command -v curl >/dev/null && command -v tar >/dev/null || { echo 'curl and tar are required.' >&2; exit 2; }
  mkdir -p "$LAUNCHER_ROOT/.runtime"
  ARCHIVE="$LAUNCHER_ROOT/.runtime/$RUNTIME_NAME.tar.gz"
  if [[ ! -f "$ARCHIVE" ]]; then
    echo 'Downloading verified MagicMobile runtime (about 136 MB)…'
    curl --fail --location --proto '=https' --proto-redir '=https' --retry 3 "$URL" -o "$ARCHIVE.part"
    mv "$ARCHIVE.part" "$ARCHIVE"
  fi
  if command -v sha256sum >/dev/null; then ACTUAL=$(sha256sum "$ARCHIVE"); else ACTUAL=$(shasum -a 256 "$ARCHIVE"); fi
  [[ "${ACTUAL%% *}" == "$EXPECTED" ]] || { echo 'Runtime checksum failed. Nothing was executed; remove only the downloaded archive and retry.' >&2; exit 2; }
  STAGING=$(mktemp -d "$LAUNCHER_ROOT/.runtime/unpack.XXXXXX")
  tar -xzf "$ARCHIVE" -C "$STAGING"
  printf '%s\n' "$EXPECTED" > "$STAGING/.verified-archive-sha256"
  [[ ! -e "$RUNTIME" ]] || { echo 'An incomplete runtime directory exists; preserve or move it before retrying.' >&2; exit 2; }
  mv "$STAGING" "$RUNTIME"
fi
[[ "$(<"$RUNTIME/.verified-archive-sha256")" == "$EXPECTED" ]] || { echo 'Cached runtime does not match the pinned release.' >&2; exit 2; }
export MAGICMOBILE_BUILD_IDENTITY="{\"protocolVersion\":1,\"upstreamCommit\":\"$UPSTREAM_COMMIT\",\"catalogueHash\":\"$CATALOGUE_HASH\",\"adapterVersion\":\"$ADAPTER_VERSION\"}"
export JAVA_HEAP_INITIAL=64m JAVA_PROCESSORS=1 MAX_MATCHES=1
echo "Keep this terminal open. Local health check: http://127.0.0.1:$PORT/health"
echo 'Stop with Ctrl+C. Public phone access additionally requires HTTPS/DNS and a configured app endpoint.'
exec bash "$RUNTIME/run.sh"
