#!/usr/bin/env bash
# Packages already-built native iOS libraries. Does NOT compile Java to iOS.
set -euo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo "Requires macOS/Xcode" >&2;exit 1; }
[[ $# == 4 ]] || { echo "Usage: $0 DEVICE.a DEVICE_HEADERS SIMULATOR.a SIMULATOR_HEADERS" >&2;exit 1; }
ROOT=$(cd "$(dirname "$0")/.." && pwd)
for file in "$1" "$3"; do [[ -f "$file" ]] || { echo "Missing library $file" >&2;exit 1; }; done
for dir in "$2" "$4"; do [[ -f "$dir/libmmengine.h" ]] || { echo "Missing generated libmmengine.h in $dir" >&2;exit 1; }; done
OUTPUT="$ROOT/build/ios/MMXmage.xcframework"
[[ ! -e "$OUTPUT" ]] || { echo "Output exists; inspect/remove it deliberately before replacing it." >&2;exit 1; }
mkdir -p "$ROOT/build/ios/headers"
xcodebuild -create-xcframework -library "$1" -headers "$2" -library "$3" -headers "$4" -output "$OUTPUT"
# Both variants must expose the identical entrypoint ABI.
diff "$2/libmmengine.h" "$4/libmmengine.h" >/dev/null || { echo "Headers differ: review ABI before linking" >&2;exit 1; }
cp "$2/"*.h "$ROOT/build/ios/headers/"
echo "XCFramework packaged. Physical-iPhone and simulator execution are still required."
