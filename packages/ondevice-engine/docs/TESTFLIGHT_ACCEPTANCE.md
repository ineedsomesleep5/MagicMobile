# Physical TestFlight acceptance — startup failed; diagnostic retest pending

Tracked separately from source/build issue #4 in
[issue #7](https://github.com/ineedsomesleep5/MagicMobile/issues/7).

Candidate: **0.1.0 (2026091203)**, product source `7c27eaa`, engine `76c18bf`, existing ASC app
`6784735182` / `com.calebfeliciano.magicmobile`. Internal-only upload succeeded;
Apple processing is **VALID**, internal state **IN_BETA_TESTING**, and access for
the existing **Internal** group is verified. This candidate's physical install
and diagnostic capture are still **NOT RUN**.
Upload ID: `92c6be87-4cbf-4708-ae0c-8421932e1395`. No USB connection is required.
The build's English (US) **What to Test** notes include these test areas and the
known recovery limits, with a link to issue #7.
Compilation, JVM gameplay and signing are separate evidence, not phone acceptance.

Build **2026091202** was installed and **FAILED during native startup** with
Token Triumph and one AI. The underlying native exception is unknown. This
replacement adds local-only error capture and is **not a confirmed gameplay fix**.
Builds **2026091201** and **2026091202** are not final accepted candidates.

## Immediate diagnostic retest

- [ ] Install **2026091203**. Explicitly select human **Token Triumph**, AI
  **Grave Danger**, and **one AI opponent**, then start normally.
- [ ] If the engine stops, open **Review engine error report** (or **Engine
  error report** on setup), review it and select **Share report**. Copy/paste
  privately into the current support conversation with iPhone model/iOS version.
  Do not post raw reports to public GitHub; error text may contain private cards.
- [ ] If no report appears, record that result and the visible message. Check
  saved-report persistence/recovery and confirmed deletion separately.

See [the exact diagnostic release handoff](DIAGNOSTIC_TESTFLIGHT_2026091203.md).

Record iPhone model, iOS version, build, player/device count, decks, elapsed time,
observed result and screenshots/crash logs. Every unchecked item is **not
accepted**; some may have partial or failed attempts rather than no execution.

## Offline and local AI

- [ ] Cold-launch normally without a debug argument. Confirm local setup and
  player name/deck selection; no external computer or rules server is required.
- [ ] After installation, enable airplane mode. Start and complete a Commander
  game using bundled data. Missing remote artwork must not block rules/play.
- [ ] Exercise 1, 2 and 3 MAD opponents. Record thinking stalls, UI responsiveness,
  duration, crashes, resident/peak memory where available, battery change and
  thermal warnings. No mobile performance budget has been proven.
- [ ] Start/leave/restart repeatedly, including during AI simulation or a resolving
  choice. Busy cleanup must retain ownership, report retry truthfully and eventually
  allow a new game; no stale board/prompt or extra engine should survive.
- [ ] Validate every bundled precon; import a valid Commander deck and reject
  unknown/illegal cards clearly. Setup preferences may survive relaunch but must
  not present a prior match as saved or resumable.

## Rules, prompts and controls

- [ ] Priority/pass, mana sources, floating mana, X, exact special payment
  (including convoke), cancellation and commander-zone confirmations.
- [ ] Target/deselect across four seats; attacker deselection/blockers; mode/ability
  choices; trigger/library ordering; signed amounts; multi-allocation totals;
  pile selection; optional and empty-special choices.
- [ ] Independent partner commander tax/damage and actual win/loss finish.
- [ ] Own/authorized controlled hands and looked-at/revealed/exile zones;
  opponent hands/libraries and face-down identities must stay hidden.
- [ ] Portrait/landscape rotation during setup, payment, targeting and combat.
  Full prompt details beside quick actions, touch targets, large text and VoiceOver.
  Record clipping or inaccessible actions rather than bypassing them.

## Real Game Center multiplayer

- [ ] 2, 3 and 4 authenticated installations on exactly the same build. Test
  different Wi-Fi networks and cellular: lobby, private deck exchange, names,
  start, ordered actions and a completed real match.
- [ ] Each device sees only its authorized private data and cannot act for another
  seat. Retried/duplicate actions must not apply twice.
- [ ] Different build is rejected before deck exchange/start. No state/protocol
  migration is implemented.
- [ ] Background/foreground, lock/unlock and temporary disconnect on host and
  peers. Check suspension/rejection and clear messages. A recovered connection
  alone does not prove a match can reconnect/resume.
- [ ] Force-quit the host. Match loss may require starting again; no host migration
  or durable restore exists. Confirm the UI describes that truthfully.

## Release boundary

Track results separately from issue #4 source/build completion. Keep this build
internal while evaluating runtime/usability. Nested control, durable save/resume,
host migration, draft and tournament construction are outside the implemented MVP.
Do not claim exhaustive card coverage from a few completed matches.
