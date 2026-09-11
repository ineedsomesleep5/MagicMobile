#!/usr/bin/env bash
# Real desktop AOT dependency probe, never an XMage or iOS backend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export JAVA_HOME="$ROOT/build/toolchains/graalvm-svm-java17-darwin-m1-gluon-22.1.0.1-Final/Contents/Home"
export PATH="$JAVA_HOME/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
mkdir -p "$ROOT/build" "$ROOT/evidence"
PROBE_BUILD=$(mktemp -d "$ROOT/build/ormlite-check-XXXXXX")
PROBE_LOG="$ROOT/evidence/$(basename "$PROBE_BUILD").log"
exec > >(tee "$PROBE_LOG") 2>&1
ORM_CP=$(tr ':' '\n' < "$ROOT/build/runtime-classpath.txt" | grep '/ormlite-core/5.7/ormlite-core-5.7.jar$')
[[ -s "$ORM_CP" ]]
mkdir -p "$PROBE_BUILD/probe" "$PROBE_BUILD/substitutions"
javac -J-Xmx256m -cp "$ORM_CP" -d "$PROBE_BUILD/probe" "$ROOT/native/gluon/probes/OrmLiteInitProbe.java"
javac -J-Xmx256m -cp "$JAVA_HOME/lib/svm/builder/svm.jar:$ORM_CP" -d "$PROBE_BUILD/substitutions" \
  "$ROOT/native/gluon/src/main/java/io/magicmobile/nativebridge/OrmLiteDateFormatSubstitutions.java"
ARGS=(--no-fallback -J-Xmx1g -H:NumberOfThreads=2 "-H:Path=$PROBE_BUILD")
CP="$PROBE_BUILD/probe:$ORM_CP"
if native-image "${ARGS[@]}" -cp "$CP" -H:Name=baseline OrmLiteInitProbe > "$PROBE_BUILD/baseline.log" 2>&1; then
  echo 'Baseline unexpectedly passed; re-evaluate the reproduction' >&2; exit 1
fi
grep 'No instances of com.j256.ormlite.field.types.' "$PROBE_BUILD/baseline.log"
echo 'PASS: baseline reproduces converter image-heap incompatibility'
TZ=America/Chicago native-image "${ARGS[@]}" -H:+IncludeAllLocales \
  --initialize-at-build-time=com.j256.ormlite.field.types -cp "$CP" -H:Name=unsafe-dates OrmLiteInitProbe
if TZ=UTC "$PROBE_BUILD/unsafe-dates" > "$PROBE_BUILD/unsafe-dates.log" 2>&1; then
  echo 'Unadapted date defaults unexpectedly passed' >&2; exit 1
fi
grep 'Build-time date defaults leaked:' "$PROBE_BUILD/unsafe-dates.log"
echo 'PASS: unadapted converter initialization reproduces frozen build timezone'
TZ=America/Chicago native-image "${ARGS[@]}" -H:+IncludeAllLocales \
  --initialize-at-build-time=com.j256.ormlite.field.types \
  -cp "$PROBE_BUILD/substitutions:$CP" -H:Name=runtime-dates OrmLiteInitProbe
for probe_tz in UTC Asia/Tokyo; do
  for probe_locale in en-US fr-FR; do
    expected=$(TZ="$probe_tz" java -Xmx256m -cp "$CP" OrmLiteInitProbe "$probe_locale")
    actual=$(TZ="$probe_tz" "$PROBE_BUILD/runtime-dates" "$probe_locale")
    if [[ "$expected" != "$actual" ]]; then
      printf 'MISMATCH %s %s\nJVM: %s\nNative: %s\n' "$probe_tz" "$probe_locale" "$expected" "$actual" >&2
      exit 1
    fi
    printf 'MATCH %s %s: %s\n' "$probe_tz" "$probe_locale" "$actual"
  done
done
printf 'PASS: desktop dependency probe only; no XMage/iOS execution. Evidence: %s\n' "$PROBE_LOG"
