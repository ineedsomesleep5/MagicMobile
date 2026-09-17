#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/deck-scryfall-checks.XXXXXX")"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Services/CommanderSpellbookModels.swift" \
  "$root/apps/ios/MagicMobile/DeckStudio/Services/CommanderSpellbookClient.swift" \
  "$root/apps/ios/MagicMobile/DeckStudio/Services/DeckStudioScryfall.swift" \
  "$root/scripts/deck-studio/scryfall-checks.swift" -o "$build/checks"
"$build/checks"
