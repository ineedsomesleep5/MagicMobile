#!/usr/bin/env sh
set -eu

XMAGE_HOME="${XMAGE_HOME:-/opt/xmage/xmage}"
SERVER_DIR="$XMAGE_HOME/mage-server"
SERVER_JAR="$(ls "$SERVER_DIR"/lib/mage-server-*.jar | head -n 1)"
JAVA_OPEN_OPTS="${XMAGE_JAVA_OPEN_OPTS:---add-opens java.base/java.io=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.util=ALL-UNNAMED}"

cleanup() {
  if [ "${SERVER_PID:-}" ]; then
    kill "$SERVER_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if [ "${ENABLE_XMAGE_FIXTURES:-false}" = "true" ] && [ "${NODE_ENV:-production}" != "production" ]; then
  cd "$SERVER_DIR"
  exec java $JAVA_OPEN_OPTS -Xmx"$XMAGE_SERVER_XMX" \
    -cp "/opt/magicmobile/classes:$SERVER_DIR/lib/*:$SERVER_DIR/plugins/*:$XMAGE_HOME/mage-client/lib/*:$XMAGE_HOME/mage-client/plugins/*" \
    MagicMobileEmbeddedServerBridge
fi

cd "$SERVER_DIR"
java $JAVA_OPEN_OPTS -Xmx"$XMAGE_SERVER_XMX" -jar "$SERVER_JAR" &
SERVER_PID=$!

cd "$SERVER_DIR"
exec java $JAVA_OPEN_OPTS \
  -cp "/opt/magicmobile/classes:$XMAGE_HOME/mage-client/lib/*:$XMAGE_HOME/mage-client/plugins/*:$SERVER_DIR/lib/*:$SERVER_DIR/plugins/*" \
  MagicMobileBridge
