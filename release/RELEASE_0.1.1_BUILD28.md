# iOS 0.1.1 build 28: brackets, Quick Match, Ranked and profiles

Apple reports build `1d9643b3-2a68-4086-936c-6081be08c679` as `VALID`, with internal and external state
`IN_BETA_TESTING` (Beta App Review passed), in the Internal (all builds) and External (added) groups, on
October 4, 2026 UTC. The External invitation remains https://testflight.apple.com/join/2mSHE8rZ. None of this
proves anything on a physical iPhone or iPad.

## Changes ([#110](https://github.com/ineedsomesleep5/MagicMobile/pull/110))
- **Brackets:** every deck's Commander bracket from its list (Game Changers of February 2026, mass land denial,
  chained extra turns, two-card combos), with the player's own label; tags on play screens and Deck Studio tiles.
- **Play:** a mode chooser. Quick Match plays one AI at your deck's bracket (or the bracket, deck and skill you
  pick). Ranked is 1v1 from Bronze to Mythic in monthly seasons, with deranking; it looks for a player near your
  rank for 40 s, then an AI at your tier takes the seat. Custom Table is the old setup.
- **Profile:** rank and season history, stats, colors, decks, achievements and titles, match history; friends'
  rank badges and ranked cards.
- **Badges:** six tier badges made 3D with Meshy and rendered in Blender; rank-up and rank-down moments spin them.
- **Decks:** 21 included decks for brackets 1–4, for players and the AI.
- **Server:** the Supabase `ranked_ladder` migration (queue, matches, ranked cards) went live the same day.

## Verification
- **Signed source:** `codex/ios-build-28` at `ce0aa71`: #110's branch plus the build-28 bump, the regenerated
  Xcode project and the SwiftPM source list.
- **`ios-fast` preflight:** passed 14/14 (after regenerating the project with XcodeGen and adding the Ranked
  logic to the SwiftPM contracts). The native decision is `equivalent-source` with `ad2e8c3`.
- **Engine:** the build 21 engine, re-staged from `verified-native-10945664948`; `libmmengine.a` SHA-256
  `466597b2…9753`, unchanged.
- **Tests:** SwiftPM contracts 592 (5 skipped); the ranked unit tests; the affected UI suites, 88 tests green
  after a simulator reboot (rotation had stopped working on the old boot; `main` failed the same way).
- **Run:** `ios-0.1.1-28`, fingerprint `f20f7e65…3ad5`, IPA SHA-256 `c1b0c712…a0e8`, delivery `1d9643b3…`.
- **Not verified:** a physical iPhone or iPad; a ranked match between two phones.
