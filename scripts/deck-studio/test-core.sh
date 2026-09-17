#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/deck-studio-checks.XXXXXX")"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioCore.swift" \
  "$root/scripts/deck-studio/core-checks.swift" -o "$build/checks"
"$build/checks"
bash "$root/scripts/deck-studio/test-spellbook.sh"
bash "$root/scripts/deck-studio/test-roles.sh"
bash "$root/scripts/deck-studio/test-observations.sh"
bash "$root/scripts/deck-studio/test-scryfall.sh"
bash "$root/scripts/deck-studio/test-finishing.sh"
python3 "$root/scripts/deck-studio/check-role-accuracy.py"
