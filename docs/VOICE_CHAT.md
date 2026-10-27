# Voice chat

Players at an online table (relay or Game Center, people only) can talk. It runs on Agora (Caleb picked it on
2026-10-26: 10,000 free participant-minutes a month, then about $0.99 per 1,000; a four-player 45-minute game is about
180 minutes). The account has no card, so past the free minutes voice stops for the month instead of billing.

## How it works

- **Channel:** `mm-` + the game's epoch, lower case (`VoiceChatRules.channel`). The epoch is a UUID the host makes per game
  and only that table's players receive, so knowing the channel is being at the table. iPhones write UUIDs upper case;
  every platform lowercases.
- **Account:** each player joins as their seat id (`player1`…`player9`), so the board lights the right medallion.
- **Token:** the `agora-token` edge function (`supabase/functions/agora-token`, `verify_jwt`) mints a 4-hour token for a
  signed-in player (anonymous profiles count). Apps renew it 30 s before it runs out. The function holds the App ID; the
  App Certificate is the Supabase secret `AGORA_APP_CERTIFICATE`, which only Caleb sets (Edge Functions → Secrets). Without
  it the function answers `voice_not_configured` and the apps hide the mic for that game.
- **Switch:** `voiceChat` in `mm_app_config`'s switches, **off unless named on** (unlike the older switches). The apps make
  a voice room only while it is on (docs/SERVER_CONTROLS.md).
- **SDKs:** iOS `AgoraAudio_iOS` 4.6.4 (`RtcBasic`, Swift Package in project.yml, about 13 MB on a phone), Android
  `io.agora.rtc:voice-rtc-basic` 4.6.4 (arm64 only, about 14 MB), web `agora-rtc-sdk-ng` 4.24.8, loaded only when someone
  taps the mic (its own 1.6 MB chunk).

## On the board (Arena)

- A round glass **mic** at your medallion's lower left. Nobody is in voice until they tap it; the first tap asks for the
  microphone and joins with it on. Then it turns your microphone off and on (red when off). A refused microphone still
  joins to listen; the mic then opens the app's settings (iOS, Android) or asks again (web).
- A green **halo** pulses round whoever is talking (level ≥ 0.08, held 0.6 s so a sentence doesn't flicker).
- A small **mic badge** on an opponent who is in voice, red when they muted themselves or you muted them.
- **Mute Voice / Unmute Voice** on an opponent's player card silences them for you alone.
- **Leave Voice Chat** in the gear's menu. Leaving the game leaves the channel.

## Code

| | Rules (shared cases) | Room | Board |
| --- | --- | --- | --- |
| iOS | `VoiceChatRules.swift` | `VoiceRoom.swift` (`\.voiceRoom`, made in `OnDeviceRootView.syncVoiceRoom`) | `Board/ArenaVoiceViews.swift` |
| Android | `core/.../game/VoiceChatRules.kt` | `ondevice/VoiceRoom.kt` (`LocalVoiceRoom`, `OnDeviceViewModel.syncVoiceRoom`) | `board/ArenaVoiceViews.kt` |
| Web | `src/core/voiceChat.ts` | `src/table/voiceRoom.ts` (made in `GameScreen`) | `GameScreen.tsx`, `arena.css` (`.amic`, `.aspeak`, `.avoice`) |

The shared cases are `apps/android/core/src/test/resources/parity/voice-cases.json` (iOS `VoiceChatRulesTests`, Android
`VoiceChatRulesTest`, web `voiceChat.test.ts`, which also runs the web room against a stand-in for Agora).

## Turning it on (done 2026-10-27)

1. Caleb adds `AGORA_APP_CERTIFICATE` in Supabase (legacy Agora console → Projects → pencil → Security → Primary
   Certificate; the new console shows only the App ID). Set 2026-10-27; a test join with a minted token worked.
2. Builds with voice chat reach the phones: TestFlight 65, Android 43, the web deploy `dpl_F2mkVtEy96juVChN9woevMCbrkex`.
3. `update public.app_settings set value = value || '{"voiceChat": true}', updated_at = now() where key = 'switches';`
   (on since 2026-10-27; set it `false` to hide the mic everywhere without a build).

## Not verified yet

Two phones hearing each other, the game's sounds while voice is on (Agora takes
the audio session; `chatRoom` scenario, speaker by default), Bluetooth headsets on Android (no `BLUETOOTH_CONNECT`).
