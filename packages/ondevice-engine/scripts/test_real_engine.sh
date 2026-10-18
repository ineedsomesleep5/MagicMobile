#!/usr/bin/env bash
# Real-upstream regressions after build_jvm.sh, not a native or device acceptance gate.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ -s build/runtime-classpath.txt ]] || { echo "Run build_jvm.sh first" >&2; exit 1; }
CP=$(<build/runtime-classpath.txt)
mkdir -p build/test-real evidence
find engine/xmage/src/main/java -name '*.java' | sort > build/adapter-sources.txt
find engine/xmage/src/test/java -name '*.java' | sort > build/real-test-sources.txt
javac -J-Xmx384m --release 17 -cp "$CP" -d build/engine @build/adapter-sources.txt
javac -J-Xmx384m --release 17 -cp "$CP" -d build/test-real @build/real-test-sources.txt
java -Xmx256m -Djava.awt.headless=true -cp "$CP:build/test-real" mage.cards.repository.MobileCardCriteriaTests \
  2>&1 | tee evidence/MobileCardCriteriaTests.txt
# Production classes first: stale adapter classes in a developer test folder must not override them.
for suite in RealQueryTests RealDeckValidationTests RealControlledTurnTests RealControlPrivacyTests RealCommanderRulesTests RealPortraitProjectionTests RealStackResponseTests RealAIDiagnosticsTests RealAIDifficultyTests RealCombatPlannerTests; do
  java -Xmx384m -Djava.awt.headless=true -cp "$CP:build/test-real" "io.magicmobile.xmage.$suite" \
    2>&1 | tee "evidence/$suite.txt"
done
REPOSITORY_TEST=$(mktemp -d "$ROOT/build/card-repo-test-XXXXXX")
(
  cd "$REPOSITORY_TEST"
  java -Xmx768m -Djava.awt.headless=true -cp "$CP:$ROOT/build/test-real" io.magicmobile.xmage.RealCardRepositoryTests
) 2>&1 | tee "$ROOT/evidence/RealCardRepositoryTests.txt"
python3 -c 'import subprocess,sys; subprocess.run(sys.argv[1:],check=True,timeout=240)' \
  java -Xmx768m -Djava.awt.headless=true -cp "$CP:build/test-real" io.magicmobile.xmage.RealConcedeTests \
  2>&1 | tee evidence/RealConcedeTests.txt
for humans in one-human two-humans; do
  args=(java -Xmx768m -Djava.awt.headless=true -cp "$CP:build/test-real" io.magicmobile.xmage.RealAILifecycleTests)
  [[ "$humans" == one-human ]] || args+=(two-humans)
  python3 -c 'import subprocess,sys; subprocess.run(sys.argv[1:],check=True,timeout=180)' \
    "${args[@]}" \
    2>&1 | tee "evidence/RealAILifecycleTests-$humans.txt"
done
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/isamaru.txt --commander 'Isamaru, Hound of Konda' --output build/isamaru.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/yargle.txt --commander 'Yargle, Glutton of Urborg' --output build/yargle.json
python3 scripts/make_match.py build/isamaru.json build/yargle.json --output build/match.json
# These validate decks and play real games. Sets come from the set catalogue (MobileExpansionSet), so no set
# class may load: only Booster Tutor's packs use one, from the few that make their own packs.
for suite in RealStandaloneValidationLifecycleTests RealBusyShutdownTests RealResolvingCancellationTests; do
  java -Xmx384m -Xlog:class+load=info:file="build/class-load-$suite.log" -Djava.awt.headless=true -cp "$CP:build/test-real" \
    "io.magicmobile.xmage.$suite" build/match.json 2>&1 | tee "evidence/$suite.txt"
  if grep -E '\] mage\.sets\.' "build/class-load-$suite.log"; then echo "FAIL: $suite loaded XMage set classes" >&2; exit 1; fi
done
echo "PASS: no XMage set class loaded while validating decks and playing" | tee evidence/no-set-classes.txt
# The set catalogue against the real set classes: fields, card lists and lookups, packs from every set, every printing.
java -Xmx1g -Djava.awt.headless=true -cp "$CP:build/test-real" io.magicmobile.xmage.RealSetCatalogueTests \
  2>&1 | tee evidence/RealSetCatalogueTests.txt
# The same lookups on a catalogue copy that lists one collector number twice (first on the classpath).
mkdir -p build/ambiguous-set-catalogue/mage/mobile
python3 - build/engine/mage/mobile/set-catalogue.tsv.gz build/ambiguous-set-catalogue/mage/mobile/set-catalogue.tsv.gz <<'PY'
import gzip, sys
lines = gzip.open(sys.argv[1], 'rt', encoding='utf-8').read().split('\n')
header = lines[0].split('\t'); header[4] = str(int(header[4]) + 1); lines[0] = '\t'.join(header)
row = next(i for i, line in enumerate(lines) if line.startswith('P\tMRD\t16\t'))
lines.insert(row + 1, lines[row])
with gzip.open(sys.argv[2], 'wt', encoding='utf-8') as out: out.write('\n'.join(lines))
PY
java -Xmx384m -Djava.awt.headless=true -cp "build/ambiguous-set-catalogue:$CP:build/test-real" \
  io.magicmobile.xmage.RealSetCatalogueTests ambiguous 2>&1 | tee -a evidence/RealSetCatalogueTests.txt
python3 scripts/test_real_decks.py
python3 scripts/test_real_lifecycle.py
python3 scripts/play_jvm.py build/match.json --timeout 240 --report evidence/real-jvm-game.json
python3 scripts/play_jvm.py build/match.json --timeout 240 --four-seats --report evidence/real-jvm-four-player-game.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/adeline.txt --commander 'Adeline, Resplendent Cathar' --output build/adeline.json
python3 scripts/make_match.py build/adeline.json build/yargle.json --output build/token-match.json
python3 scripts/play_jvm.py build/token-match.json --timeout 240 --mulligans 2 --require-tokens \
  --report evidence/real-jvm-token-mulligan-game.json
# Save/resume checkpoints: every restore runs in a fresh child JVM (process death), with bundled
# precons that exile, make tokens, copy and change control. JVM only; not native or phone evidence.
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/token-triumph.txt --commander 'Emmara, Soul of the Accord' --output build/token-triumph.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/chaos-incarnate.txt --commander 'Kardur, Doomscourge' --output build/chaos-incarnate.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/first-flight.txt --commander 'Isperia, Supreme Judge' --output build/first-flight.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/checkpoint-features.txt --commander 'Zedruu the Greathearted' --output build/checkpoint-features.json
# Native serialization metadata for these classes, exported exactly as the native builds do
# (scripts/android/build_native.sh, build_native_ios.sh). RealCheckpointTests fails when a class
# that any checkpoint stream writes or reads is missing from it.
mkdir -p build/tools
javac -J-Xmx512m --release 17 -cp build/core -d build/tools engine/tools/NativeReflectionExporter.java
rm -rf build/native-metadata-check
java -Xmx768m -cp "build/tools:$CP" NativeReflectionExporter build/native-metadata-check \
  .upstream/mage/Mage/target/classes .upstream/mage/Mage.Sets/target/classes .upstream/mage/Mage.Common/target/classes \
  --serialization .upstream/mage/Mage.Server.Plugins/*/target/classes build/engine > /dev/null
CHECKPOINT_TEST=$(mktemp -d "$ROOT/build/checkpoint-test-XXXXXX")
python3 -c 'import subprocess,sys; subprocess.run(sys.argv[1:],check=True,timeout=1500)' \
  java -Xmx1g -Djava.awt.headless=true -cp "$CP:build/test-real" io.magicmobile.xmage.RealCheckpointTests \
  "$CHECKPOINT_TEST" build/token-triumph.json build/chaos-incarnate.json build/first-flight.json \
  build/isamaru.json build/yargle.json build/adeline.json build/checkpoint-features.json \
  build/native-metadata-check/serialization-config.json \
  2>&1 | tee evidence/RealCheckpointTests.txt
# Game records (docs/cloud/game-record.md): AI-only and scripted-human games recorded through the production
# API and replayed from the record alone to the same winner, turn and life totals, plus eight more seeds.
RECORD_TEST=$(mktemp -d "$ROOT/build/record-test-XXXXXX")
python3 -c 'import subprocess,sys; subprocess.run(sys.argv[1:],check=True,timeout=1500)' \
  java -Xmx1g -Djava.awt.headless=true -Dmagicmobile.recordSoak=8 -cp "$CP:build/test-real" io.magicmobile.xmage.RealGameRecordTests \
  "$RECORD_TEST" build/token-triumph.json build/chaos-incarnate.json build/first-flight.json \
  build/isamaru.json build/yargle.json build/adeline.json \
  2>&1 | tee evidence/RealGameRecordTests.txt
