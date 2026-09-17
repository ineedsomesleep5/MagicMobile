#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
build="$(mktemp -d "${TMPDIR:-/tmp}/deck-studio-finishing.XXXXXX")"
trap 'rm -rf "$build"' EXIT
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioRecordedGame.swift" \
  "$root/scripts/deck-studio/recording-completion-checks.swift" -o "$build/recording"
"$build/recording"
swiftc -swift-version 5 -warnings-as-errors \
  "$root/apps/ios/MagicMobile/DeckStudio/Core/DeckStudioOrganization.swift" \
  "$root/scripts/deck-studio/organization-checks.swift" -o "$build/organization"
"$build/organization"
