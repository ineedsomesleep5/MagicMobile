# iOS 0.1.1 build 50: steal pull, longer dice throw, v2 tavern room, ranked roll

Apple reports build `df487476-56a1-49f8-ad7d-82e9dbe2796c` as `VALID`, with Internal and External both `IN_BETA_TESTING`
and Beta App Review `APPROVED`, on October 19, 2026. Caleb asked for External along with Internal. The External
invitation remains https://testflight.apple.com/join/2mSHE8rZ. Same native engine as builds 48 and 49 (release C,
`21a82eb7`), so tables seat Android 31–33. Android 33 carries the same app changes (`RELEASE_ANDROID_0.1.1_BUILD33.md`).

Build 49 (October 19, internal only, delivery `d92c8931…`) added the card moments (#209) and the art cleanup (#210);
it had no record of its own. Its ledger entry comes to main with this one.

## Changes
- #212 Ranked always rolls the D20 for the first turn. Ranked used the shared "Who goes first?" choice, which defaults
  to "choose" and has no picker in the Ranked lobby. Quick Match and custom tables keep the player's choice.
- #213 A steal pulls from the taker: the brass chain shoots from the new controller's portrait, hooks the card on its
  old side and drags it to its new slot.
- #213 The dice table: throws come in from the viewer's edge of the table, reach the rail after about a second
  (was about 0.65 s), touch it gently, and settle back from it. Each throw runs 2.6–3.2 s, and the die is slightly
  smaller so the whole run fits.
- #213 The v2 tavern room behind the menu: a thin warm haze in the back layer and a hotter hearth.

## Release
- **Source:** `codex/ios-build-50` at `4a362c50` (main after #212, build 49's ledger, `claude/steal-dice-room` for
  #213, and the build-number prepare). Preflight native decision `equivalent-source`. Xcode 27.1.
- **Run:** `ios-0.1.1-50`, fingerprint `ab1fa04d…`, delivery `df487476-56a1-49f8-ad7d-82e9dbe2796c`, IPA `b039087c…`.
  VALID after about 5 minutes. A second resume from the upload commit, with only the ledger changed, distributed the
  build to the Internal and External groups.

## Verification
- Preflight `ios-fast`: 14/14.
- `swift test`: BoardEventTimelineTests, StartingRollDiceTests, OnDeviceStartingRollTests and RankedStandingTests.
- iOS simulator build. Simulator recordings of the walkthrough's steal (step 14) and the dice fixture.
- **Still to check on Caleb's iPhone:** a ranked game rolls the D20; the steal and the dice feel right; the v2 room on
  the menu.
