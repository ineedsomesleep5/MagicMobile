/**
 * What the game screen needs from a table: a phone-hosted relay table (GuestTable) or a solo game against the
 * XMage AI on this computer (SoloTable). Both drive the same GuestSession over the same JSON protocol.
 */
import type { GameEmote } from "../core/tableChat";
import type { GuestSession } from "./guestSession";
import type { TableState } from "./guestTable";

export interface GameTable {
  /** A solo game: no chat, clock or other players to tell, and the result screen offers a rematch. */
  readonly solo: boolean;
  readonly state: TableState;
  readonly session?: GuestSession;
  /** Bumped on every change, for React's external-store hook. */
  readonly version: number;
  subscribe(listener: () => void): () => void;
  /** The local seat rolls its D20 for the starting player. */
  rollStartingPlayer(): void;
  concede(): Promise<void>;
  /** Leaves the game for good (a running solo game is conceded first). */
  leave(): void;
  /** Solo only: a new game with the same decks and settings. */
  rematch?(): void;
  sendChat(message: string): void;
  sendEmote(emote: GameEmote): void;
  /** A table with people: vote to go on without the player who is away (TableLeaveRules). */
  voteToContinue?(): void;
  /** Clears the "Jed left. The game goes on." notice once shown. */
  clearTableNotice?(): void;
  /** A table with people, once the game has its epoch: the voice channel (VoiceChat.channel). */
  readonly voiceChannel?: string;
}
