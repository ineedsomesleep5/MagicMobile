#!/usr/bin/env bash
# GraalVM Community Edition ships Native Image and the Web Image API, but not the Web Image tool (--tool:svm-wasm):
# Oracle ships that only in Oracle GraalVM, licensed for use unmodified. The tool's source is in oracle/graal
# (GPLv2 with the Classpath Exception), at the very commit the CE release was built from. This builds the tool there
# with mx and installs it into the CE home, so the web engine builds with all-open-source tools. The builder fixes in
# ../builder-patch/src (docs/WEB_ENGINE_M1.md, "Fitting the free runner") go into the source first; MM_WEB_CE_FIXES=0
# builds the source as it is.
#   build_web_image_tool.sh <CE home> <work dir>      (Linux x64: CI; needs git, python3, curl and the network)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CE=$(cd "${1:?usage: build_web_image_tool.sh <CE home> <work dir>}" && pwd)
WORK=${2:?usage: build_web_image_tool.sh <CE home> <work dir>}
mkdir -p "$WORK"; WORK=$(cd "$WORK" && pwd)
# The CE release names its source commits; it has no web-image entry, but Web Image lives in the same repository.
commit=$(grep -o 'substratevm:[0-9a-f]\{40\}' "$CE/release" | head -1 | cut -d: -f2)
[[ -n $commit ]] || { echo "No substratevm commit in $CE/release" >&2; exit 1; }
echo "GraalVM CE $(grep -o 'GRAALVM_VERSION="[^"]*"' "$CE/release"), oracle/graal $commit"

cd "$WORK"
if [[ ! -d graal/.git ]]; then git init -q graal && git -C graal remote add origin https://github.com/oracle/graal.git; fi
git -C graal fetch -q --depth 1 origin "$commit"
git -C graal checkout -q --force FETCH_HEAD
json() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(eval(sys.argv[2], {"d": d}))' graal/common.json "$1"; }
mx_version=$(json 'd["mx_version"]')
[[ -d mx/.git ]] || git clone -q --depth 1 --branch "$mx_version" https://github.com/graalvm/mx.git mx
labsjdk=$(json 'd["jdks"]["labsjdk-ce-latest"]["version"]')       # e.g. ce-25.0.4.1.1+1-jvmci-25.4-b23
jdk_dir="$WORK/labsjdk-$labsjdk"
if [[ ! -x $jdk_dir/bin/java ]]; then
  name="labsjdk-$labsjdk-linux-amd64.tar.gz"
  url="https://github.com/graalvm/labs-openjdk/releases/download/jvmci-${labsjdk##*-jvmci-}/$name"
  curl -sSfL -o "$name" "$url" && curl -sSfL -o "$name.sha1" "$url.sha1"
  echo "$(tr -d ' \n' < "$name.sha1")  $name" | sha1sum -c -
  mkdir -p "$jdk_dir" && tar xzf "$name" -C "$jdk_dir" --strip-components 1 && rm -f "$name"
fi

if [[ ${MM_WEB_CE_FIXES:-1} == 1 ]]; then
  base=$(grep -o '^BASE=[0-9a-f]*' "$HERE/../builder-patch/rebase.sh" | cut -d= -f2)
  [[ $base == "$commit" ]] || { echo "The builder fixes are for oracle/graal $base, not $commit: run builder-patch/rebase.sh $commit" >&2; exit 1; }
  while IFS= read -r rel; do
    for project in com.oracle.svm.hosted.webimage com.oracle.svm.webimage; do
      target="graal/web-image/src/$project/src/$rel"
      if [[ -f $target ]]; then cp "$HERE/../builder-patch/src/$rel" "$target"; echo "fix: $rel"; continue 2; fi
    done
    echo "No $rel in oracle/graal web-image" >&2; exit 1
  done < <(cd "$HERE/../builder-patch/src" && find . -name '*.java' | sed 's|^\./||' | sort)
fi

dists=SVM_WASM,SVM_WASM_JIMFS,SVM_WASM_GUAVA,NATIVE_IMAGE_WASM_SUPPORT
export JAVA_HOME=$jdk_dir MX_PYTHON=python3
mx/mx -p graal/web-image --java-home "$jdk_dir" build --dependencies "$dists"

dest="$CE/lib/svm/tools/svm-wasm"
rm -rf "$dest"; mkdir -p "$dest/builder"
for dist in SVM_WASM SVM_WASM_JIMFS SVM_WASM_GUAVA; do
  jar=$(mx/mx -p graal/web-image --java-home "$jdk_dir" paths --output "$dist" | tail -1)
  cp "$jar" "$dest/builder/"
done
support=$(mx/mx -p graal/web-image --java-home "$jdk_dir" paths --output NATIVE_IMAGE_WASM_SUPPORT | tail -1)
props=$( { [[ -d $support ]] && find "$support" -name native-image.properties; } | head -1)
if [[ -z $props && -f $support ]]; then mkdir -p support && tar xf "$support" -C support && props=$(find support -name native-image.properties | head -1); fi
[[ -n $props ]] || { echo "No native-image.properties in $support" >&2; exit 1; }
cp "$props" "$dest/native-image.properties"
echo "Installed the Web Image tool into $dest:"; ls -la "$dest" "$dest/builder"; cat "$dest/native-image.properties" | head -5
