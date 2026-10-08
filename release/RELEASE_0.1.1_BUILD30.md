# iOS 0.1.1 build 30: the spell book (internal only)

Apple reports build `db61f798-2512-4123-972a-22a5bbacfa08` as `VALID`, uploaded on October 6, 2026 UTC. It went to the
Internal (all builds) group only, so Caleb could try the spell book; the External group was not added. Build 31
replaced it for both groups with the collector's binder. None of this proves anything on a physical iPhone or iPad.

## Changes ([#118](https://github.com/ineedsomesleep5/MagicMobile/pull/118), [#119](https://github.com/ineedsomesleep5/MagicMobile/pull/119) at `afcc8e1`)
- **Deck Studio as a spell book:** an opening film, parchment pages, page turns, a two-page spread when held
  sideways, and the card grid's tap-to-add.
- **Battery and size pass:** the game rests while it waits, a compressed card catalogue, lighter animations.

## Verification
- **Signed source:** `codex/ios-build-30` at `888364c`: unmerged `codex/spellbook` at `afcc8e1` plus the build-30 bump.
- **`ios-fast` preflight:** passed 14/14, native decision `equivalent-source`.
- **Engine:** the build 21 engine re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256 `466597b2…9753`.
- **Run:** `ios-0.1.1-30`, fingerprint `b805a319…0373`, IPA SHA-256 `fcff49a3…a6e6`, delivery `db61f798…`, Xcode 27.0.
- **Not verified:** a physical iPhone or iPad.
