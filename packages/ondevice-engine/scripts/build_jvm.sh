#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
command -v mvn >/dev/null || { echo "Maven 3.9+ and a JDK are required on the development machine." >&2;exit 1; }
bash "$ROOT/scripts/bootstrap.sh"
U="$ROOT/.upstream/mage"
MODULES="Mage.Sets,Mage.Common,Mage.Server.Plugins/Mage.Player.Human,Mage.Server.Plugins/Mage.Player.AI,Mage.Server.Plugins/Mage.Player.AI.MAD,Mage.Server.Plugins/Mage.Deck.Constructed,Mage.Server.Plugins/Mage.Game.CommanderFreeForAll"
export MAVEN_OPTS="${MAVEN_OPTS:--Xmx4g}"
# Do not include desktop Client, SessionImpl, server networking, HTTP or Docker.
(cd "$U" && mvn -B -pl "$MODULES" -am -Dmaven.test.skip=true install)
(cd "$U" && mvn -B -pl "$MODULES" -am dependency:build-classpath -Dmdep.outputFile=target/mobile-classpath.txt)
mkdir -p "$ROOT/build/engine" "$ROOT/build/tools" "$ROOT/build/generated" "$ROOT/evidence"
python3 "$ROOT/scripts/classpath.py" "$U" "$ROOT/build/classpath.txt"
CP=$(cat "$ROOT/build/classpath.txt")
bash "$ROOT/scripts/test_core.sh"
javac --release 17 -cp "$ROOT/build/core" -d "$ROOT/build/tools" "$ROOT/engine/tools/RegistryExporter.java"
# Exporter needs all Mage/Mage.Sets class definitions, NOT test classes or server UI classes.
java -Xmx4g -cp "$ROOT/build/core:$ROOT/build/tools:$CP" RegistryExporter "$ROOT/build/generated" \
 "$U/Mage/target/classes" "$U/Mage.Sets/target/classes" "$U/Mage.Common/target/classes"
python3 "$ROOT/scripts/prepare_mobile_repository.py" --mode runtime --output "$ROOT/build/generated/platform"
find "$ROOT/engine/xmage/src/main/java" "$ROOT/build/generated/java" "$ROOT/build/generated/platform" \
  "$ROOT/platform/java" -name '*.java' | sort > "$ROOT/build/engine-sources.txt"
javac --release 17 -cp "$ROOT/build/core:$CP" -d "$ROOT/build/engine" @"$ROOT/build/engine-sources.txt"
echo "$ROOT/build/core:$ROOT/build/engine:$CP" > "$ROOT/build/runtime-classpath.txt"
bash "$ROOT/scripts/build_card_metadata.sh"
javac --release 17 -cp "$ROOT/build/core:$ROOT/build/engine:$CP" -d "$ROOT/build/tools" "$ROOT/engine/tools/CommanderSetExporter.java"
java -Xmx384m -cp "$ROOT/build/core:$ROOT/build/engine:$ROOT/build/tools:$CP" CommanderSetExporter "$ROOT/build/generated/commander-set-codes.json"
# Compiler success is distinct from a completed game.
printf 'Adapter compilation completed. Real-engine match smoke has not run yet.\n' | tee "$ROOT/evidence/jvm-compile.txt"
