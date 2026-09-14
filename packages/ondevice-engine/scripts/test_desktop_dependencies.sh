#!/usr/bin/env bash
# Static class references only. Does not execute XMage, Graal, or an iOS simulator.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
[[ -s build/runtime-classpath.txt ]] || { echo 'Run build_jvm.sh first' >&2; exit 1; }
command -v jdeps >/dev/null || { echo 'JDK jdeps is required' >&2; exit 1; }
CP=$(<build/runtime-classpath.txt)
INPUTS=(
  build/engine
  .upstream/mage/Mage/target/classes
  .upstream/mage/Mage.Common/target/classes
  .upstream/mage/Mage.Sets/target/classes
  .upstream/mage/Mage.Server.Plugins/Mage.Player.Human/target/classes
  .upstream/mage/Mage.Server.Plugins/Mage.Player.AI/target/classes
  .upstream/mage/Mage.Server.Plugins/Mage.Player.AI.MAD/target/classes
  .upstream/mage/Mage.Server.Plugins/Mage.Deck.Constructed/target/classes
  .upstream/mage/Mage.Server.Plugins/Mage.Game.CommanderFreeForAll/target/classes
)
for input in "${INPUTS[@]}"; do
  [[ -d "$input" ]] || { echo "Missing compiled audit input: $input" >&2; exit 1; }
done
mkdir -p evidence/desktop-api
{
  printf 'MagicMobile source: '
  git rev-parse HEAD
  printf 'XMage source: '
  git -C .upstream/mage rev-parse HEAD
  jdeps --version
  printf 'Audited class directory: %s\n' "${INPUTS[@]}"
} > evidence/desktop-api/environment.txt
jdeps -J-Xmx1g --multi-release 17 --class-path "$CP" -verbose:class \
  --regex 'java\.awt\..*|javax\.swing\..*|javax\.imageio\..*' \
  "${INPUTS[@]}" > evidence/desktop-api/class-references.txt
jdeps -J-Xmx1g --multi-release 17 --class-path "$CP" --missing-deps \
  "${INPUTS[@]}" > evidence/desktop-api/missing-references.txt
cat > evidence/desktop-api/SCOPE.txt <<'SCOPE'
Static references in the selected compiled XMage modules and mobile adapter.
Not method/call-path reachability, dynamic reflection coverage, native linkage,
JDK Color patch execution, complete dependency coverage, or phone acceptance.
References to desktop classes require source review; their presence alone does
not prove a reachable native defect. Missing-reference output is preserved,
not suppressed. No game, native executable, or simulator was launched here.
SCOPE
printf 'Recorded static desktop-API and missing-reference audit; NOT native compatibility or gameplay acceptance.\n'
