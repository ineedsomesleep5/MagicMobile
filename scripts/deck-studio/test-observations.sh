#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/deck-observation-checks.XXXXXX")"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioRecordedGame.swift" \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioPublicTimeline.swift" \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioValidationReceipt.swift" \
  "$root/apps/ios/MagicMobile/DeckStudio/Services/DeckStudioPlaytestStore.swift" \
  "$root/scripts/deck-studio/observations-checks.swift" -o "$build/checks"
"$build/checks"
