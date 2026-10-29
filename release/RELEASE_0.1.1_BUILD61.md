# TestFlight 0.1.1 (61): deck Power, more AI decks, spread-hand drag, one-step multi-card choices

Uploaded October 25, 2026 and distributed to Internal and External testers; Beta App Review `APPROVED`. Released with
Android build 38 and a web deploy of the same main (`d18fe1d5`).

## What changed
- **Deck Power (PR #241, docs/DECK_POWER.md):** every AI deck has a hidden 1–10 Power measured from about 7,200
  AI-vs-AI games. Ranked brings the deck nearest the division's target from the tier's bracket or lower; Quick Match
  offers Easy, Medium and Hard (Advanced keeps the old controls). 43 AI decks (was 21).
- **Board (PR #242):** a card can be dragged out of the spread hand; a drafted multi-card choice (a discard of seven)
  finishes with one Done instead of handing the rest back.

## Release
- **Source:** `codex/ios-build-61` in `~/Documents/MagicMobile-release-40` = main `d18fe1d5` + `prepare` + a release-only
  commit restoring `packages/ondevice-engine/scripts/ai_calibration.py` and its test to build 60's version (calibration
  tooling, not shipped) so the staged engine's inputs match. Never merge that branch.
- **Engine:** release C, unchanged (`--verify-installed` ok); preflight `ios-fast` 14/14, `equivalent-source`.
- **Run:** `ios-0.1.1-61`, fingerprint `1a171b78…`, IPA `aa8517de…`, delivery `eac66504…`, VALID then distributed.

## Verification
- CI green on #241 and #242 (`swift`, `boundary-tests`, `real-jvm`, Android `app`, web tests).
- Locally: web 316 tests; Android ranked, card-choice and board-model tests; the iOS app and tests compile for the
  simulator (iOS unit tests not run locally).
- **Not verified on a phone:** Quick Match's Easy/Medium/Hard row, a ranked game's pick, the spread-hand drag and a real
  multi-card discard.
