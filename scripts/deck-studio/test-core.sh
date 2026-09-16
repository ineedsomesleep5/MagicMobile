#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/deck-studio-checks.XXXXXX")"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioCore.swift" \
  "$root/scripts/deck-studio/core-checks.swift" -o "$build/checks"
"$build/checks"
