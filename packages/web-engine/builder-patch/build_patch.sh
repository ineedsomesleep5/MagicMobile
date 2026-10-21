#!/usr/bin/env bash
# Builds the Web Image builder patch (docs/WEB_ENGINE_M1.md, "Fitting the free runner") and prints the native-image
# option that loads it:
#   build_patch.sh <output dir>   ->   -J--patch-module=org.graalvm.extraimage.builder=<output dir>
#
# src/ holds three classes of GraalVM's open-source Web Image builder (GPLv2 with the Classpath Exception), taken
# from oracle/graal commit 95ce1499c8c96ab7d5a6697c5b4bf42160f3b68b, the commit Oracle GraalVM 25.4.4.1.1 was built
# from; unmodified, they compile to the same bytecode as the shipped classes. The changes (marked "MagicMobile") stop
# the builder from keeping comments nobody prints and limit the unsafe access dispatch arrays to unsafe-accessed
# fields, which cuts its peak memory and the module. They only change the builder, never the engine's sources.
#
# Needs GRAALVM_HOME = Oracle GraalVM 25.4.4.1.1. Any other toolchain is refused: expected.sha256 pins the shipped
# classes the patch replaces, so a GraalVM update fails here instead of running against stale copies. To move to a
# new GraalVM, take the same files from its commit (SOURCE in $GRAALVM_HOME/release), re-apply the marked changes,
# check the unchanged copies compile to the shipped bytecode, and update expected.sha256.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build_patch.sh <output dir>}
: "${GRAALVM_HOME:?Set GRAALVM_HOME to Oracle GraalVM 25.4.4.1.1}"
JAR="$GRAALVM_HOME/lib/svm/tools/svm-wasm/builder/svm-wasm.jar"
[[ -s $JAR ]] || { echo "No Web Image builder at $JAR" >&2; exit 1; }

shipped=$(mktemp -d)
trap 'rm -rf "$shipped"' EXIT
(cd "$shipped" && unzip -q "$JAR" $(awk '{print $2}' "$HERE/expected.sha256"))
python3 - "$shipped" "$HERE/expected.sha256" <<'PY' || { echo "The Web Image builder classes differ from the ones the patch was made for (see the header of build_patch.sh)" >&2; exit 1; }
import hashlib, sys
from pathlib import Path
root, expected = Path(sys.argv[1]), Path(sys.argv[2])
bad = [name for digest, name in (l.split() for l in expected.read_text().splitlines() if l.strip())
       if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest]
print("\n".join(f"changed: {n}" for n in bad), file=sys.stderr)
sys.exit(1 if bad else 0)
PY

# Compiled on the class path against every builder jar: the class files are the same as a module build's, and
# --patch-module puts them into org.graalvm.extraimage.builder at build time.
cp=$(find "$GRAALVM_HOME/lib/svm" -name '*.jar' | sort | paste -sd: -)
exports=()
for module in jdk.internal.vm.ci jdk.graal.compiler; do
  # JVMCI's packages also go to the compiler module, whose signatures (CompilationResult) name them.
  to=ALL-UNNAMED; [[ $module == jdk.internal.vm.ci ]] && to=ALL-UNNAMED,jdk.graal.compiler
  for pkg in $("$GRAALVM_HOME/bin/java" --describe-module "$module" | awk '$1 == "contains" || $1 == "qualified" {print ($1 == "contains") ? $2 : $3}' | sort -u); do
    exports+=(--add-exports "$module/$pkg=$to")
  done
done
rm -rf "$OUT"; mkdir -p "$OUT"
"$GRAALVM_HOME/bin/javac" -J-Xmx768m -nowarn -proc:none -cp "$cp" --add-modules jdk.internal.vm.ci,jdk.graal.compiler \
  "${exports[@]}" -d "$OUT" $(find "$HERE/src" -name '*.java' | sort)
# Every shipped class the patch replaces must come out of the patched sources, and nothing else.
diff <(awk '{print $2}' "$HERE/expected.sha256" | sort) <(cd "$OUT" && find . -name '*.class' | sed 's|^\./||' | sort) >&2 ||
  { echo "The patched sources compile to a different set of classes" >&2; exit 1; }
echo "-J--patch-module=org.graalvm.extraimage.builder=$OUT"
