/**
 * Voice chat at online tables (VoiceChatRules.swift / .kt, parity/voice-cases.json; docs/VOICE_CHAT.md). Each game has
 * its own Agora channel, "mm-" + the game's epoch: a UUID only that table's players receive, so knowing the channel is
 * being at the table. Each player joins as their seat id. Nobody is in voice until they tap the mic.
 */

/** The server switch (mm_app_config). Off unless the server turns it on, unlike the older switches. */
export const VOICE_SWITCH = "voiceChat";

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

  /** Whether the board shows the mic: the switch on, a table with people, the game started, and the server able to answer. */
  shown: (p: { switchOn: boolean; solo: boolean; channel: boolean; account: boolean; unavailable: boolean }) =>
    p.switchOn && !p.solo && p.channel && p.account && !p.unavailable,
};
