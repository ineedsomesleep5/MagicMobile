# Lessons: the scripted tutorial

Five short lessons teach Commander and the app on the real Arena board. Each one has preset cards in hand and library, a
staged board and an opponent (Rook) who casts exactly what the script says. Maren, the tavern keeper, explains each step,
rings what to touch and waits for the move. The guided game against the easy AI is the last step on the phones.

| # | Lesson | Teaches |
|---|--------|---------|
| 1 | Lands and spells | play a land, cast a creature, pay with lands or Auto Pay, read a card, summoning sickness, Next, attack, win |
| 2 | Combat | block, power and toughness, flying |
| 3 | Instants and the stack | answer Rook's Shock with Giant Growth; the last spell cast resolves first |
| 4 | Your commander | cast from the command zone, back to the command zone, commander tax, 40 life, 21 commander damage, deck rules |
| 5 | Around the table | four players, choosing whom to attack, a player knocked out |

## How it works

No engine runs during a lesson. `scripts/lessons/record.py` plays each script once in the real XMage engine on a Mac (the
JVM build) and saves the learner's view after every change. The apps play that recording back:

- **The lesson transport** (`LessonTransport` in iOS `Lessons.swift`, Android `core/.../Lessons.kt` and web
  `src/core/lessons.ts`) stands in for the engine. It speaks the same six calls (`capabilities`, `create`, `poll`,
  `respond`, `concede`, `destroy`), so the board, session, animations and rules text are the normal ones.
- **Moves.** A frame that waits for a move accepts only the recorded answer. Another card with the same name in the same
  place and state also counts (two Forests), and the recording swaps their IDs from then on. Anything else is refused
  with `lesson_wrong_move`: Maren's card shakes and says so, and the board shows no error of its own.
- **Pacing.** Frames without a move go on by themselves when polled: briefly when only the step changed, longer when
  something happened on the table. A note waits for Got it.
- **Rings.** The coach's `spot` names a card (the expected one when it has that name), a player, `primary` (the corner
  button) or `medallion`.
- **Not counted.** Lessons never reach stats, ranked, saves or game records. Finished lessons are remembered on the
  device (`magicmobile.lessons.completed`).

## Files

- `scripts/lessons/lessons.py`: the scripts and Maren's words. `scripts/lessons/recorder.py`: staging, playing and
  frames. `packages/ondevice-engine/engine/tools/LessonCli.java`: the Mac-only `lessonStage` op (XMage's test cheat,
  outside the engine's source list, never shipped).
- `apps/ios/MagicMobile/Resources/Lessons/`: `lessons.json` (order and titles) and `lesson-<id>.json`. Android copies
  them at build time (`scripts/android/prepare_assets.py`), the web too (`apps/web/scripts/prepare_data.py`).
- Tests: iOS `LessonsTests`, Android `LessonsTest`, web `test/lessons.test.ts`. Each plays every lesson through with its
  recorded moves and checks a wrong move and the two-Forest swap.

## Changing a lesson

1. Edit `scripts/lessons/lessons.py` (cards from the engine catalogue; coach lines name the Arena board's buttons).
2. With a JVM engine build (`packages/ondevice-engine/scripts/build_jvm.sh`) and JDK 17:
   `python3 scripts/lessons/record.py --engine <checkout>/packages/ondevice-engine [lesson ids]`.
   `LESSON_DEBUG=1` prints every question and answer.
3. Run the three test suites, and play the lesson on the iPhone simulator: `--ondevice-setup-ui-test` with
   `MAGICMOBILE_UI_TEST_LESSON=<id>` (DEBUG builds) opens it without an engine.

Recordings follow the engine's snapshot format. After an engine release that changes it, record the lessons again.
