#!/usr/bin/env bash
# Original repository export is build-time only, with an isolated in-memory H2 database.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
[[ -s "$ROOT/build/runtime-classpath.txt" ]]
CP=$(<"$ROOT/build/runtime-classpath.txt")
EXPORT_BUILD=$(mktemp -d "$ROOT/build/card-metadata-export-XXXXXX")
python3 "$ROOT/scripts/prepare_mobile_repository.py" --mode export --output "$EXPORT_BUILD/source"
find "$EXPORT_BUILD/source" -name '*.java' | sort > "$EXPORT_BUILD/sources.txt"
javac -J-Xmx256m --release 17 -cp "$CP" -d "$EXPORT_BUILD/classes" \
  @"$EXPORT_BUILD/sources.txt" "$ROOT/engine/tools/CardMetadataExporter.java"
mkdir -p "$ROOT/build/engine/mage/mobile"
# Original SQL-backed repository classes precede the mobile runtime adapters here only.
(
  cd "$EXPORT_BUILD"
  java -Xmx2g -Djava.awt.headless=true -cp "$EXPORT_BUILD/classes:$CP" CardMetadataExporter \
    "$ROOT/build/engine/mage/mobile"
) 2>&1 | tee "$ROOT/evidence/card-metadata-export.log"
[[ -s "$ROOT/build/engine/mage/mobile/card-metadata-report.json" ]]
