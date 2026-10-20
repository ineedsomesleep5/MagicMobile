/**
 * A guest's game: polls the host's engine for this seat's snapshot and answers its prompts. Port of
 * the guest paths of OnDeviceSession.kt (poll schedule, pending response, chosen-ability follow-up).
 */
import { EngineClient, type MatchPoll } from "../core/engineClient";
import { EngineError, get, type J, jsonEqual, newUuid, str } from "../core/json";
import { OnDeviceMessageLog } from "../core/messageLog";
import type { GameCommand, GameSnapshot, LegalAction } from "../core/models";
import { OnDevicePromptAdapter } from "../core/promptAdapter";
import { OnDeviceSnapshotAdapter } from "../core/snapshotAdapter";
import { HostRetryPolicy, type RemoteEngineTransport } from "./remoteEngine";

/** OnDeviceGuestPollSchedule: when a guest at a phone-hosted table polls its host next. */
export const GuestPollSchedule = {
  /** Safety net for a dropped notice. Notices are never queued or acknowledged. */
  HEARTBEAT_MILLIS: 15_000,
  /** After sending an answer, the guest polls promptly this long, or until the answer lands. */
  ANSWER_WINDOW_MILLIS: 10_000,
  SPACING_MILLIS: 300,
  next(hostAnnounces: boolean, noticedRevision: number, appliedRevision: number | undefined, awaitingAnswer: boolean,
    sinceActionMillis: number | undefined, sinceLastPollMillis: number, spacingMillis: number): { poll: number } | { await: number } {
    const gap = Math.max(0, spacingMillis - sinceLastPollMillis);
    // A host that never announced (an older build) is polled on the short timer.
    if (!hostAnnounces || appliedRevision === undefined || noticedRevision > appliedRevision) return { poll: gap };
    if (awaitingAnswer && sinceActionMillis !== undefined && sinceActionMillis < GuestPollSchedule.ANSWER_WINDOW_MILLIS) return { poll: gap };
    const remaining = GuestPollSchedule.HEARTBEAT_MILLIS - sinceLastPollMillis;
    return remaining > gap ? { await: remaining } : { poll: gap };
  },
};

interface Submission { promptId: string; promptRevision: number; answer: J; requestID: string; label: string }
interface ChosenAbility { sourceID: string; abilityID: string; activationPromptID: string }

export interface SessionState {
  snapshot?: GameSnapshot;
  phase?: string;
  status: string;
  errorMessage?: string;
  pendingActionID?: string;
  working: boolean;
}

export class GuestSession {
  state: SessionState = { status: "Connecting", working: false };
  private readonly client: EngineClient;
  private poll?: MatchPoll;
  private log = new OnDeviceMessageLog();
  private pending?: Submission;
  private chosenAbility?: ChosenAbility;
  private stopped = false;
  private wakeLoop?: () => void;
  private lastActionAt?: number;
  private lastPollAt = 0;
  private noticedRevision = -1;
  private hostAnnounces = false;
  private refreshing = false;
  private retries = new HostRetryPolicy();
  /** Asked after every applied snapshot: an automatic answer the table wants sent (the D20 winner). */
  autoCommand?: (snapshot: GameSnapshot) => GameCommand | undefined;

  constructor(remote: RemoteEngineTransport, readonly matchID: string, readonly seatID: string, private readonly onChange: () => void) {
    this.client = new EngineClient(remote.request);
  }

  start() { void this.loop(); }

  stop() { this.stopped = true; this.wakeLoop?.(); }

  /** The host announced a new revision: poll soon. Repeated or late notices are harmless. */
  noticed(revision: number) {
    this.hostAnnounces = true;
    this.noticedRevision = Math.max(this.noticedRevision, revision);
    this.wakeLoop?.();
  }

  /** Re-evaluates the poll schedule now (the table's own events, such as the last die settling). */
  wake() { this.wakeLoop?.(); }

  private set(patch: Partial<SessionState>) { this.state = { ...this.state, ...patch }; this.onChange(); }

  private async loop() {
    while (!this.stopped) {
      try {
        await this.refresh();
        this.retries.reset();
      } catch (error) {
        if (this.stopped) return;
        const backoff = this.retries.delayAfter(error);
        this.set({ errorMessage: error instanceof Error ? error.message : String(error) });
        if (backoff !== undefined) { await this.sleep(backoff); continue; }
        this.retries.reset();
      }
      if (this.poll && ["ended", "failed", "closed"].includes(this.poll.phase)) {
        // The game is over; one slow heartbeat keeps the final board current.
        await this.sleep(GuestPollSchedule.HEARTBEAT_MILLIS);
        continue;
      }
      await this.waitForNextPoll();
    }
  }

  private sleep(millis: number) {
    return new Promise<void>((resolve) => {
      const timer = setTimeout(() => { this.wakeLoop = undefined; resolve(); }, millis);
      this.wakeLoop = () => { clearTimeout(timer); this.wakeLoop = undefined; resolve(); };
    });
  }

  private async waitForNextPoll() {
    for (;;) {
      if (this.stopped) return;
      const now = Date.now();
      const step = GuestPollSchedule.next(this.hostAnnounces, this.noticedRevision, this.poll?.revision,
        this.pending !== undefined || this.chosenAbility !== undefined, this.lastActionAt === undefined ? undefined : now - this.lastActionAt,
        now - this.lastPollAt, GuestPollSchedule.SPACING_MILLIS);
      if ("poll" in step) { if (step.poll > 0) await this.sleep(step.poll); return; }
      await this.sleep(step.await);
    }
  }

  async refresh() {
    if (this.refreshing || this.stopped) return;
    this.refreshing = true;
    try {
      this.lastPollAt = Date.now();
      const next = await this.client.poll(this.matchID, this.seatID, this.poll?.revision ?? 0);
      if (this.stopped) return;
      if (next.matchID !== this.matchID || next.seatID !== this.seatID) throw EngineError.unboundPeer();
      if (this.poll && next.revision < this.poll.revision) return;
      const unchanged = this.poll === next || (this.poll !== undefined && jsonEqual(this.poll.raw, next.raw));
      this.poll = next;
      if (!unchanged) {
        this.log.ingest(next);
        let snapshot = this.state.snapshot;
        if (next.phase === "closed") snapshot = undefined;
        else if (next.snapshot !== undefined) snapshot = OnDeviceSnapshotAdapter.snapshot(next, this.seatID, this.log.entries);
        if (this.pending && (next.prompt?.id !== this.pending.promptId || next.prompt?.revision !== this.pending.promptRevision)) {
          this.pending = undefined;
        }
        const status = ({ ended: "Game complete", failed: "Game stopped", closed: "Game closed", starting: "Starting game" } as Record<string, string>)[next.phase] ?? "Live";
        this.set({
          snapshot, phase: next.phase, status, errorMessage: str(get(get(next.raw, "failure"), "message")),
          pendingActionID: this.pending ? this.state.pendingActionID : undefined,
        });
        this.followUp(next, snapshot);
      }
    } finally {
      this.refreshing = false;
    }
  }

  /** Answers XMage's "which ability" follow-up for the exact ability the player tapped, and the table's automatic answers. */
  private followUp(poll: MatchPoll, snapshot: GameSnapshot | undefined) {
    const prompt = poll.prompt;
    const chosen = this.chosenAbility;
    if (chosen && prompt && !prompt.submitted && prompt.id !== chosen.activationPromptID) {
      const rows = poll.prompt?.payload.abilities;
      const offered = ["CHOOSE_ABILITY", "PICK_ABILITY"].includes(prompt.kind) && Array.isArray(rows) &&
        rows.some((row) => str(get(row, "id")) === chosen.abilityID);
      this.chosenAbility = undefined;
      if (offered && snapshot) {
        void this.submit({
          type: "choose_ability", gameId: this.matchID, playerId: snapshot.viewerPlayerId ?? "human", abilityId: chosen.abilityID,
          promptId: prompt.id, messageId: prompt.revision,
        }, "Choose ability", `auto-ability-${chosen.abilityID}`).catch(() => { /* the player answers it by hand */ });
        return;
      }
    }
    if (snapshot && !this.pending && !this.state.working) {
      const command = this.autoCommand?.(snapshot);
      if (command) void this.submit(command, "Starting player", "auto-starting-player").catch(() => { /* retried next poll */ });
    }
  }

  /** A legal action the board offered. */
  send(action: LegalAction) {
    const snapshot = this.state.snapshot;
    if (!snapshot) return Promise.reject(EngineError.invalid("The game is still loading."));
    return this.submit({
      type: action.type, gameId: snapshot.id, playerId: action.playerId, cardInstanceId: action.cardInstanceId,
      sourceInstanceId: action.sourceInstanceId, abilityId: action.abilityId, promptId: action.promptId, messageId: action.messageId,
      choiceIds: action.choiceIds, targetIds: action.targetIds, cardInstanceIds: action.cardInstanceIds, modeIds: action.modeIds,
      pile: action.pile, amount: action.amount, amounts: action.amounts, orderedIds: action.orderedIds, manaType: action.manaType,
      playerIds: action.playerIds, confirmed: action.confirmed, expectedBridgeRevision: snapshot.bridgeRevision,
    }, action.label, action.id);
  }

  async submit(command: GameCommand, label: string, actionID: string) {
    const snapshot = this.state.snapshot;
    const prompt = this.poll?.prompt;
    if (this.state.working || this.stopped) throw EngineError.invalid("Wait for the current operation before responding");
    if (!snapshot || !prompt || this.state.pendingActionID !== undefined || snapshot.gameStatus === "completed" ||
      ["ended", "failed", "closed"].includes(this.poll?.phase ?? "") || command.gameId !== this.matchID ||
      command.playerId !== snapshot.viewerPlayerId ||
      (command.expectedBridgeRevision !== undefined && command.expectedBridgeRevision !== snapshot.bridgeRevision)) {
      throw EngineError.invalid("The game or decision changed. Refresh before choosing again.");
    }
    const answer = OnDevicePromptAdapter.answer(command, prompt, snapshot.viewerPlayerId!);
    const source = command.sourceInstanceId ?? command.cardInstanceId;
    if (["make_mana", "activate_ability", "play_land", "cast_spell"].includes(command.type) && command.abilityId && source) {
      this.chosenAbility = { sourceID: source, abilityID: command.abilityId, activationPromptID: prompt.id };
    } else if (command.type !== "choose_ability") this.chosenAbility = undefined;
    this.pending = { promptId: prompt.id, promptRevision: prompt.revision, answer, requestID: newUuid(), label };
    this.set({ pendingActionID: actionID, working: true });
    await this.performPending();
  }

  /** Retries the exact pending answer (same request ID) after a timeout or busy host. */
  async retryPending() {
    if (!this.pending || this.state.working) throw EngineError.invalid("There is no pending response to retry");
    this.set({ working: true });
    await this.performPending();
  }

  private async performPending() {
    const pending = this.pending!;
    const prompt = this.poll?.prompt;
    try {
      this.lastActionAt = Date.now();
      if (!prompt || prompt.id !== pending.promptId) throw EngineError.invalid("There is no pending response to retry");
      await this.client.respond(this.matchID, this.seatID, prompt, pending.answer, pending.requestID);
      this.set({ working: false, errorMessage: undefined, status: `${pending.label} sent; waiting for XMage` });
      this.wakeLoop?.();
    } catch (error) {
      // An engine rejection is certain; a timeout or busy RPC is not: keep the exact request for retry.
      const certain = error instanceof EngineError && error.isRejection && error.code !== "rpc_busy";
      if (certain) { this.pending = undefined; this.set({ pendingActionID: undefined }); this.wakeLoop?.(); }
      this.set({ working: false, errorMessage: error instanceof Error ? error.message : String(error) });
      throw error;
    }
  }

  /** The browser player concedes; the host plays on or ends the game. */
  async concede() {
    await this.client.concede(this.matchID, this.seatID);
    this.wakeLoop?.();
  }

  get hasPending() { return this.pending !== undefined; }
}
