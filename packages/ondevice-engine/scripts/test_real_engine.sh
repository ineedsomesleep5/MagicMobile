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
for suite in RealQueryTests RealDeckValidationTests RealControlledTurnTests RealControlPrivacyTests RealCommanderRulesTests RealPortraitProjectionTests RealAIDiagnosticsTests; do
  java -Xmx384m -Djava.awt.headless=true -cp "$CP:build/test-real" "io.magicmobile.xmage.$suite" \
    2>&1 | tee "evidence/$suite.txt"
done
REPOSITORY_TEST=$(mktemp -d "$ROOT/build/card-repo-test-XXXXXX")
(
  cd "$REPOSITORY_TEST"
  java -Xmx768m -Djava.awt.headless=true -cp "$CP:$ROOT/build/test-real" io.magicmobile.xmage.RealCardRepositoryTests
) 2>&1 | tee "$ROOT/evidence/RealCardRepositoryTests.txt"
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
for suite in RealStandaloneValidationLifecycleTests RealBusyShutdownTests RealResolvingCancellationTests; do
  java -Xmx384m -Djava.awt.headless=true -cp "$CP:build/test-real" "io.magicmobile.xmage.$suite" build/match.json \
    2>&1 | tee "evidence/$suite.txt"
done
python3 scripts/test_real_decks.py
python3 scripts/test_real_lifecycle.py
python3 scripts/play_jvm.py build/match.json --timeout 240 --report evidence/real-jvm-game.json
python3 scripts/play_jvm.py build/match.json --timeout 240 --four-seats --report evidence/real-jvm-four-player-game.json
python3 scripts/resolve_deck.py --catalogue build/generated/catalogue.jsonl \
  --input tests/decks/adeline.txt --commander 'Adeline, Resplendent Cathar' --output build/adeline.json
python3 scripts/make_match.py build/adeline.json build/yargle.json --output build/token-match.json
python3 scripts/play_jvm.py build/token-match.json --timeout 240 --mulligans 2 --require-tokens \
  --report evidence/real-jvm-token-mulligan-game.json
