/**
 * Voice chat at online tables (VoiceChatRules.swift / .kt, parity/voice-cases.json; docs/VOICE_CHAT.md). Each game has
 * its own Agora channel, "mm-" + the game's epoch: a UUID only that table's players receive, so knowing the channel is
 * being at the table. Each player joins as their seat id. Nobody is in voice until they tap the mic.
 */

/** The server switch (mm_app_config). Off unless the server turns it on, unlike the older switches. */
export const VOICE_SWITCH = "voiceChat";

/** Push to talk (Options → Audio, the game's settings): the microphone stays off except while the mic or the key is held. */
export const PUSH_TO_TALK_KEY = "mm.web.pushToTalk";
/** The key held to talk, as a KeyboardEvent.code. */
export const PUSH_TO_TALK_BIND_KEY = "mm.web.pushToTalkKey";
export const DEFAULT_PUSH_TO_TALK_BIND = "KeyV";

export type VoiceStage = "off" | "joining" | "live" | "unavailable";

export interface VoiceState {
  stage: VoiceStage;
  /** Your microphone is off (you still hear the table). */
  muted: boolean;
  /** The browser or phone refused the microphone: you hear the table but can't talk. */
  micBlocked: boolean;
  /** Seats in the channel, yours included while live. */
  inVoice: string[];
  /** Seats talking right now (lit holdSeconds past the last loud report). */
  speaking: string[];
  /** Seats that turned their own microphone off. */
  selfMuted: string[];
  /** Seats you silenced for yourself. */
  silenced: string[];
}

const EPOCH = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const SEAT = /^player[1-9]$/;

export const VoiceChat = {
  /** A level (0–1) at or past this is speech. */
  speakingLevel: 0.08,
  /** A speaker stays lit this long after the last loud report, so a sentence doesn't flicker. */
  holdSeconds: 0.6,

  initial: (): VoiceState => ({ stage: "off", muted: false, micBlocked: false, inVoice: [], speaking: [], selfMuted: [], silenced: [] }),

  /** The game's channel; undefined before the game has an epoch. */
  channel(epoch: string | undefined): string | undefined {
    const lower = epoch?.toLowerCase();
    return lower !== undefined && EPOCH.test(lower) ? `mm-${lower}` : undefined;
  },

  /** The Agora account for a seat: the seat id itself. */
  account: (seat: string | undefined): string | undefined => (seat !== undefined && SEAT.test(seat) ? seat : undefined),

  isSpeaking: (level: number) => level >= VoiceChat.speakingLevel,

  stillSpeaking: (heardAt: number | undefined, now: number) => heardAt !== undefined && now - heardAt <= VoiceChat.holdSeconds + 1e-9,

  /** A key code as the settings show it: "KeyV" → "V", "Digit1" → "1", "Space" → "Space". */
  keyLabel: (code: string) => code.replace(/^Key(?=[A-Z]$)/, "").replace(/^Digit(?=\d$)/, "").replace(/^Numpad/, "Num "),

  /** A key that can be the push-to-talk key: not Space, Enter or Escape (the board's own), and no modifier on its own. */
  bindable: (code: string) => !["Space", "Enter", "NumpadEnter", "Escape", "Tab", "MetaLeft", "MetaRight", "ControlLeft", "ControlRight",
    "AltLeft", "AltRight", "ShiftLeft", "ShiftRight"].includes(code) && code !== "",

  /** Whether the board shows the mic: the switch on, a table with people, the game started, and the server able to answer. */
  shown: (p: { switchOn: boolean; solo: boolean; channel: boolean; account: boolean; unavailable: boolean }) =>
    p.switchOn && !p.solo && p.channel && p.account && !p.unavailable,
};
