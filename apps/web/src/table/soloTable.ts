/**
 * A solo game against the XMage AI on this computer (docs/WEB_ENGINE_OPTIONS.md, M3): the engine runs in this
 * page's worker (LocalEngine) and the game is played through the same GuestSession a relay guest uses. Like the
 * phones' AI games, the human sits in seat player1 and so answers XMage's starting-player question; in "roll"
 * mode the table rolls D20s (the player taps their own die, the AI's rolls itself) and answers it with the winner.
 */
import { EngineClient } from "../core/engineClient";
import { arr, EngineError, get, type J, type JObject, str } from "../core/json";
import type { GameSnapshot } from "../core/models";
import { loadSmartPass } from "../core/smartPass";
import { storage } from "../ui/storage";
import { OnDeviceStartingPlayerChoice, OnDeviceStartingRoll, OnDeviceStartingRollProgress } from "../core/startingRoll";
import { TurnClockBoard } from "../core/turnClock";
import type { LocalEngine, WorkerTransport } from "../engine/localEngine";
import type { GameTable } from "./gameTable";
import { GuestSession } from "./guestSession";
import type { TableState } from "./guestTable";

export type StartingPlayerMode = "choose" | "roll";

export interface SoloSetup {
  /** The human seat's name at the table. */
  name: string;
  /** Resolved engine decks (DeckResolver.resolve). */
  deck: J;
  aiDeck: J;
  /** 1–10, the phones' AI skill control (PROTOCOL.md). */
  aiSkill: number;
  startingPlayerMode: StartingPlayerMode;
}

export const SOLO_SEAT = "player1";
export const AI_SEAT = "player2";
/** The phones' AI seat name (OnDeviceAppConfiguration.aiGameSeats). */
export const AI_NAME = "AI 1";

/** OnDeviceAppConfiguration.aiGameSeats for one AI opponent: the apps send only aiSkill, no seeds. */
export function soloConfiguration(setup: SoloSetup): JObject {
  if (!Number.isInteger(setup.aiSkill) || setup.aiSkill < 1 || setup.aiSkill > 10) throw EngineError.invalid("Choose AI skill from 1–10.");
  return {
    seats: [
      { seatId: SOLO_SEAT, name: setup.name, controller: "human", deck: setup.deck },
      { seatId: AI_SEAT, name: AI_NAME, controller: "ai", deck: setup.aiDeck, aiSkill: setup.aiSkill },
    ],
  };
}

/** How long a revealed AI die waits before the next one (OnDeviceRootView.advanceAIRollIfNeeded). */
const AI_DIE_MILLIS = 650;
/** How long the winner stays on screen before the table answers XMage. */
const RESULT_MILLIS = 1_800;

const sleep = (millis: number) => new Promise((resolve) => setTimeout(resolve, millis));
const message = (error: unknown) => (error instanceof Error ? error.message : String(error));

export class SoloTable implements GameTable {
  readonly solo = true;
  state: TableState;
  session?: GuestSession;
  version = 0;
  private listeners = new Set<() => void>();
  private transport?: WorkerTransport;
  private matchID?: string;
  private progress?: OnDeviceStartingRollProgress;
  private rollSettled = false;
  private timers = new Set<ReturnType<typeof setTimeout>>();
  private unsubscribeEngine?: () => void;
  private left = false;

  /** `onLeave` returns to the setup screen; `onRematch` starts a new game with the same setup. */
  constructor(private readonly engine: LocalEngine, readonly setup: SoloSetup, private readonly onLeave: () => void,
    private readonly onRematch?: () => void) {
    this.state = {
      stage: "starting", status: "Waiting for the engine…", tableCode: `AI skill ${setup.aiSkill}`, seatsTaken: 1, seatsWanted: 2,
      waiting: [], seatNames: {}, tableSeats: [], turnClock: new TurnClockBoard(), isSuspended: false, reconnecting: false, chat: [], bubbles: {},
    };
  }

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private changed = () => { this.version += 1; this.listeners.forEach((listener) => listener()); };
  private set(patch: Partial<TableState>) { this.state = { ...this.state, ...patch }; this.changed(); }
  private later(millis: number, run: () => void) {
    const timer = setTimeout(() => { this.timers.delete(timer); if (!this.left) run(); }, millis);
    this.timers.add(timer);
  }

  /** Waits for the engine, creates the match and starts polling it. */
  async start() {
    try {
      const transport = await this.engine.start();
      if (this.left) return;
      this.transport = transport;
      this.unsubscribeEngine = this.engine.subscribe(() => {
        if (this.engine.state.stage === "failed") this.fail(this.engine.state.error ?? "The engine stopped.");
      });
      this.set({ status: "Shuffling up…" });
      const client = new EngineClient(transport.request);
      // The engine's optional answer actions (remembered answers, trigger order, pass after casting).
      const capabilities = await client.call("capabilities").catch(() => undefined);
      const answerActions = (arr(get(capabilities, "answerActions")) ?? []).map((a) => str(a)).filter((a): a is string => a !== undefined);
      const created = await client.call("create", { configuration: soloConfiguration(this.setup) });
      const matchID = str(get(created, "matchId"));
      if (!matchID) throw EngineError.invalid("The engine did not name the new match.");
      this.matchID = matchID;
      if (this.left) { void this.release(matchID, false); return; }
      const session = new GuestSession(transport.request, matchID, SOLO_SEAT, () => this.sessionChanged(), "local");
      session.autoCommand = (snapshot) => this.startingCommand(snapshot);
      session.smartPass = loadSmartPass(storage.get);
      session.supportedAnswerActions = new Set(answerActions);
      session.setAutoPassAfterCast(storage.get("mm.web.autoPassAfterCast") !== "off");
      // The combo loop shortcut, as in solo games on the phones.
      session.comboLoopsAllowed = true;
      this.session = session;
      session.start();
      this.set({ stage: "playing", status: "Playing the XMage AI on this computer." });
    } catch (error) {
      this.fail(message(error));
    }
  }

  private sessionChanged() {
    const snapshot = this.session?.state.snapshot;
    if (snapshot) this.prepareRoll(snapshot);
    this.changed();
  }

  /** XMage asked the player who starts: in "roll" mode, roll for it, the player first (OnDeviceRootView.prepareAIRollIfNeeded). */
  private prepareRoll(snapshot: GameSnapshot) {
    if (this.setup.startingPlayerMode !== "roll" || this.progress) return;
    const candidates = OnDeviceStartingPlayerChoice.candidateIDs(snapshot);
    const viewer = snapshot.viewerPlayerId;
    if (!candidates || !viewer || !candidates.includes(viewer)) return;
    try {
      const roll = OnDeviceStartingRoll.generate([viewer, ...candidates.filter((id) => id !== viewer)]);
      this.progress = new OnDeviceStartingRollProgress(roll, new Set([viewer]));
      const seatNames = Object.fromEntries(snapshot.players.map((p) => [p.playerId, p.playerId === viewer ? "You" : p.displayName ?? "AI opponent"]));
      this.state = { ...this.state, seatNames, localSeatID: viewer };
      this.updateRoll();
    } catch (error) {
      // XMage's own question stays on the table, so the player can still choose.
      this.set({ status: `Could not roll for the starting player: ${message(error)}` });
    }
  }

  private updateRoll() {
    const progress = this.progress;
    if (!progress) return;
    const next = progress.nextSeatID;
    const names = this.state.seatNames;
    const winner = progress.roll.winnerSeatID;
    const status = next === this.state.localSeatID ? "Roll your D20. Highest goes first; ties roll again."
      : next !== undefined ? `${names[next] ?? "The AI"} is rolling…`
      : winner === this.state.localSeatID ? "You go first." : `${names[winner] ?? "The AI"} goes first.`;
    this.set({ roll: { roll: progress.roll, revealed: progress.revealedCount, nextSeatID: next, hasRolled: false, status } });
    if (next !== undefined && next !== this.state.localSeatID) {
      const index = progress.revealedCount;
      this.later(AI_DIE_MILLIS, () => {
        if (progress.revealedCount !== index) return;
        progress.acceptHostAdvance(index);
        this.updateRoll();
      });
    } else if (next === undefined) {
      this.later(RESULT_MILLIS, () => { this.rollSettled = true; this.session?.wake(); });
    }
  }

  rollStartingPlayer() {
    const progress = this.progress;
    if (!progress || progress.nextSeatID === undefined || progress.nextSeatID !== this.state.localSeatID) throw EngineError.invalid("Wait for your turn to roll.");
    progress.acceptHostAdvance(progress.revealedCount);
    this.updateRoll();
  }

  /** Once the winner has been shown, XMage's starting-player question is answered with them. */
  private startingCommand(snapshot: GameSnapshot) {
    const progress = this.progress;
    if (!progress?.isComplete || !this.rollSettled) return undefined;
    return OnDeviceStartingPlayerChoice.commandForPlayerID(snapshot, progress.roll.winnerSeatID);
  }

  async concede() {
    if (!this.session) throw EngineError.invalid("The game has not started.");
    await this.session.concede();
  }

  /** Back to the setup screen. A game still running is conceded, then the engine lets go of it. */
  leave() {
    if (this.left) return;
    const running = this.isRunning();
    this.stop();
    if (this.matchID) void this.release(this.matchID, running);
    this.onLeave();
  }

  rematch() {
    if (!this.onRematch) return;
    const running = this.isRunning();
    this.stop();
    if (this.matchID) void this.release(this.matchID, running);
    this.onRematch();
  }

  private isRunning() {
    const phase = this.session?.state.phase;
    return this.session !== undefined && !["ended", "failed", "closed"].includes(phase ?? "");
  }

  private stop() {
    this.left = true;
    this.timers.forEach(clearTimeout);
    this.timers.clear();
    this.session?.stop();
    this.unsubscribeEngine?.();
  }

  /** Concedes (when still running) and destroys the match; destroy waits while the game unwinds on the worker. */
  private async release(matchID: string, concede: boolean) {
    const transport = this.transport;
    if (!transport || transport.failure) return;
    const client = new EngineClient(transport.request);
    if (concede) { try { await client.concede(matchID, SOLO_SEAT); } catch { /* already over */ } }
    for (let attempt = 0; attempt < 150; attempt += 1) {
      try {
        await client.call("destroy", { matchId: matchID });
        return;
      } catch (error) {
        if (error instanceof EngineError && error.code === "engine_busy_shutdown") { await sleep(200); continue; }
        return; // unknown_match: already gone
      }
    }
  }

  private fail(status: string) {
    if (this.state.stage === "failed" || this.left) return;
    this.timers.forEach(clearTimeout);
    this.timers.clear();
    this.session?.stop();
    this.set({ stage: "failed", status, roll: undefined });
  }

  sendChat() { /* no one else at a solo table */ }
  sendEmote() { /* no one else at a solo table */ }
}
