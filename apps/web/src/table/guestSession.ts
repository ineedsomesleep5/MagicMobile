/**
 * A seat's game: polls an engine for this seat's snapshot and answers its prompts. Port of the guest
 * paths of OnDeviceSession.kt (poll schedule, pending response, chosen-ability follow-up). The engine is
 * a phone host's, through the relay, or this page's own (a solo game against the AI, `schedule: "local"`).
 */
import { BoardPresentationHold, revisionKey, stackTopFirst, displayName } from "../core/boardEvents";
import { EngineClient, type EngineTransport, type MatchPoll } from "../core/engineClient";
import { EngineError, get, type J, jsonEqual, newUuid, str } from "../core/json";
import { OnDeviceMessageLog } from "../core/messageLog";
import type { GameCommand, GameSnapshot, LegalAction } from "../core/models";
import { OnDevicePromptAdapter } from "../core/promptAdapter";
import {
  passPrompt, situation, SMART_PASS_ACTION_PREFIX, type SmartPassSettings, STOP_MESSAGES, stepFromEngine, threatensViewer, YIELD_PASS_ACTION_PREFIX,
  yieldContext, type YieldContext, type YieldMode, YieldModes, YieldPolicy,
} from "../core/smartPass";
import { OnDeviceSnapshotAdapter } from "../core/snapshotAdapter";
import { HostRetryPolicy } from "./remoteEngine";

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

/**
 * When a seat polls the engine in this page (the Web Image worker). That engine holds a poll while the game runs
 * and answers it at the next published snapshot, so after a change the next poll goes out at once and the engine
 * sets the pace; AI turns then show as they happen.
 */
export const LocalPollSchedule = {
  /** The player has an open decision: nothing moves until they answer (an answer wakes the loop). */
  DECIDING_MILLIS: 2_000,
  /** Backoff while replies come back unchanged (an engine between games answers at once). */
  IDLE_MILLIS: [16, 60, 250],
  next(changed: boolean, deciding: boolean, unchangedPolls: number): number {
    if (deciding) return LocalPollSchedule.DECIDING_MILLIS;
    if (changed) return 0;
    return LocalPollSchedule.IDLE_MILLIS[Math.min(unchangedPolls, LocalPollSchedule.IDLE_MILLIS.length) - 1] ?? 0;
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
  /** A skip (End Turn, Skip to my turn) is passing for the player. */
  autoPassing: boolean;
  /** The running skip's line, or why the last one stopped. */
  autoPassStatus: string;
  /** Full control is on for the turn being played: smart pass stops at every priority. */
  fullControl: boolean;
}

const nowSeconds = () => performance.now() / 1000;
const pause = (millis: number) => new Promise<void>((resolve) => setTimeout(resolve, millis));

export class GuestSession {
  state: SessionState = { status: "Connecting", working: false, autoPassing: false, autoPassStatus: "", fullControl: false };
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
  private lastChanged = false;
  private unchangedPolls = 0;
  /** Asked after every applied snapshot: an automatic answer the table wants sent (the D20 winner). */
  autoCommand?: (snapshot: GameSnapshot) => GameCommand | undefined;
  /** Arena-style smart pass (OnDeviceSmartPass); undefined leaves every priority to the player. */
  smartPass?: SmartPassSettings;
  private smartPassing = false;
  private smartPassedPromptID?: string;
  /** What the board is still showing (the board attaches it); smart pass lets it finish before passing. */
  presentationHold?: BoardPresentationHold;
  /** The page is visible; a hidden tab neither smart-passes nor skips. */
  private foreground = true;
  /** Full control (holding the primary, or the skip menu): smart pass stops at every priority until this turn ends. */
  private fullControlTurn?: number;
  /** The skip modes (OnDeviceYieldPolicy): local scheduling of ordinary passes, never an engine skip command. */
  private yieldPolicy = new YieldPolicy();
  private yieldGeneration = 0;

  constructor(transport: EngineTransport, readonly matchID: string, readonly seatID: string, private readonly onChange: () => void,
    private readonly schedule: "relay" | "local" = "relay") {
    this.client = new EngineClient(transport);
  }

  start() { void this.loop(); }

  stop() { this.stopped = true; this.wakeLoop?.(); }

  get isStopped() { return this.stopped; }

  /** The host announced a new revision: poll soon. Repeated or late notices are harmless. */
  noticed(revision: number) {
    this.hostAnnounces = true;
    this.noticedRevision = Math.max(this.noticedRevision, revision);
    this.wakeLoop?.();
  }

  /**
   * Re-evaluates the poll schedule now (the table's own events, such as the last die settling), and offers the
   * table's automatic answer again: the event may have made it ready without the board changing.
   */
  wake() {
    this.wakeLoop?.();
    if (this.poll && !this.stopped) this.sendAutoCommand(this.state.snapshot);
  }

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
    if (this.schedule === "local") {
      const prompt = this.poll?.prompt;
      const deciding = prompt !== undefined && !prompt.submitted && this.pending === undefined && !this.state.working;
      const delay = LocalPollSchedule.next(this.lastChanged, deciding, this.unchangedPolls);
      if (delay > 0) await this.sleep(delay);
      return;
    }
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
      this.lastChanged = !unchanged;
      this.unchangedPolls = unchanged ? this.unchangedPolls + 1 : 0;
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
        if (this.state.fullControl !== this.isFullControl) this.set({ fullControl: this.isFullControl });
        if (this.state.errorMessage) this.stopAutoPass(STOP_MESSAGES.interrupted);
        this.scheduleSmartPass();
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
    this.sendAutoCommand(snapshot);
  }

  private sendAutoCommand(snapshot: GameSnapshot | undefined) {
    if (snapshot && !this.pending && !this.state.working) {
      const command = this.autoCommand?.(snapshot);
      if (command) void this.submit(command, "Starting player", "auto-starting-player").catch(() => { /* retried next poll */ });
    }
  }

  /** The seat's yield context, with the threat stop when the player asked for it. */
  private get yieldContextNow(): YieldContext | undefined {
    if (!this.poll) return undefined;
    const threat = (this.smartPass?.stopForThreats ?? true) && this.state.snapshot !== undefined && threatensViewer(this.state.snapshot);
    return yieldContext(this.poll, this.foreground, threat);
  }

  private get currentTurn() { return this.state.snapshot?.turn; }

  /** Full control is on for the turn being played. */
  get isFullControl() { return this.fullControlTurn !== undefined && this.fullControlTurn === this.currentTurn; }

  /** Turns Full control for this turn on or off; turning it on keeps an unsent smart pass from going. */
  toggleFullControl() {
    this.fullControlTurn = this.isFullControl ? undefined : this.currentTurn;
    this.set({ fullControl: this.isFullControl });
    if (!this.isFullControl) this.scheduleSmartPass();
  }

  /** The page was hidden or shown: a hidden tab cancels an unsent smart pass and stops a skip. */
  setForeground(value: boolean) {
    this.foreground = value;
    if (!value) this.stopAutoPass();
    else this.scheduleSmartPass();
  }

  /**
   * Passes this seat's ordinary priority when it has nothing to play, or nothing it stops for (OnDeviceSession
   * .scheduleSmartPass): the same pass a tap sends, once per prompt; a failure is left to the player, never retried. It
   * first lets the board finish what it is showing, then checks the same prompt is still a pass.
   */
  private scheduleSmartPass() {
    const settings = this.smartPass;
    const poll = this.poll;
    const snapshot = this.state.snapshot;
    if (!settings || !poll || !snapshot?.viewerPlayerId || this.smartPassing || this.stopped || this.pending || this.chosenAbility ||
      this.state.working || this.state.pendingActionID !== undefined || this.state.autoPassing || this.isFullControl || this.state.errorMessage) return;
    const value = situation(poll, this.foreground, snapshot);
    const prompt = value && passPrompt(value, settings);
    if (!value || !prompt || prompt.id === this.smartPassedPromptID) return;
    this.smartPassing = true;
    void (async () => {
      // The response lane frees right after the answer that led here.
      for (let i = 0; i < 150 && (this.state.working || this.refreshing); i++) await pause(20);
      await this.waitForBoardPresentation();
      const now = this.poll;
      const current = now && this.smartPass ? (() => { const v = situation(now, this.foreground, this.state.snapshot); return v && passPrompt(v, this.smartPass!); })() : undefined;
      const board = this.state.snapshot;
      if (this.stopped || this.state.working || this.pending || this.state.pendingActionID !== undefined || this.state.autoPassing || this.isFullControl ||
        !current || !board?.viewerPlayerId || current.id !== prompt.id || current.revision !== prompt.revision || current.id === this.smartPassedPromptID) {
        this.smartPassing = false;
        return;
      }
      this.smartPassedPromptID = current.id;
      const label = stackTopFirst(board)[0] ? displayName(stackTopFirst(board)[0]) : stepFromEngine(value.step)?.title ?? "Priority";
      this.log.noteAutoPass(label, current.id);
      let sent = false;
      try {
        await this.submit({
          type: "pass_priority", gameId: this.matchID, playerId: board.viewerPlayerId, promptId: current.id, messageId: current.revision,
          expectedBridgeRevision: board.bridgeRevision,
        }, "Pass priority", SMART_PASS_ACTION_PREFIX + current.id);
        sent = true;
      } catch { /* the player passes by hand */ }
      this.smartPassing = false;
      // The answer's own refresh may already show the next routine priority.
      if (sent) this.scheduleSmartPass();
    })();
  }

  /**
   * Lets the board finish what it is showing before smart pass moves the game on (OnDeviceSession
   * .waitForBoardPresentation): first the board takes in the published snapshot, then its held effects play out (at most
   * BoardPresentationHold.maximumWait), and a card being read holds the pass until it closes (at most a minute).
   */
  private async waitForBoardPresentation() {
    const hold = this.presentationHold;
    const snapshot = this.state.snapshot;
    if (!hold || !snapshot) return;
    const key = revisionKey(snapshot);
    const start = nowSeconds();
    const elapsed = () => nowSeconds() - start;
    while (hold.ingested !== key && elapsed() < BoardPresentationHold.ingestWait && !this.stopped) await pause(20);
    while (hold.until !== undefined && hold.until > nowSeconds() && elapsed() < BoardPresentationHold.maximumWait && !this.stopped) {
      await pause(Math.min(hold.until - nowSeconds(), 0.1) * 1000);
    }
    while (hold.reading && elapsed() < BoardPresentationHold.readingWait && !this.stopped) await pause(100);
  }

  // ---------------- skips (OnDeviceSession.startYield) ----------------

  canStartYield(mode: YieldMode) {
    const context = this.yieldContextNow;
    return !this.state.autoPassing && !this.pending && !this.state.errorMessage && context !== undefined && YieldPolicy.canStart(context, mode);
  }

  /** Cancellable local scheduling of ordinary passes until the mode's end, never an engine skip command. */
  startYield(mode: YieldMode) {
    const context = this.yieldContextNow;
    if (!this.canStartYield(mode) || !context || !this.yieldPolicy.start(context, nowSeconds(), mode)) return;
    const generation = ++this.yieldGeneration;
    this.set({ autoPassing: true, autoPassStatus: YieldModes[mode].status });
    void (async () => {
      try {
        while (!this.stopped && this.yieldGeneration === generation && this.state.autoPassing) {
          await pause(300);
          if (this.yieldGeneration !== generation || !this.state.autoPassing) return;
          if (this.state.working || this.refreshing) continue;
          // A new poll, never just the rendered snapshot, authorizes each pass.
          await this.refresh();
          if (this.yieldGeneration !== generation || !this.state.autoPassing || this.state.working) continue;
          const now = this.yieldContextNow;
          if (!now) { this.stopAutoPass(STOP_MESSAGES.interrupted); return; }
          const decision = this.yieldPolicy.evaluate(now, nowSeconds());
          if (decision.kind === "wait") continue;
          if (decision.kind === "stop") { this.stopAutoPass(STOP_MESSAGES[decision.reason]); return; }
          const prompt = this.poll?.prompt;
          const snapshot = this.state.snapshot;
          if (this.pending || !prompt || !snapshot?.viewerPlayerId || prompt.id !== decision.prompt.id || prompt.revision !== decision.prompt.revision) continue;
          this.yieldPolicy.recordPass(decision.prompt);
          await this.submit({
            type: "pass_priority", gameId: this.matchID, playerId: snapshot.viewerPlayerId, promptId: prompt.id, messageId: prompt.revision,
            expectedBridgeRevision: snapshot.bridgeRevision,
          }, "Pass priority", YIELD_PASS_ACTION_PREFIX + prompt.id, true);
        }
      } catch {
        // Keep an uncertain pending answer for the Retry control; scheduling never retries or retargets.
        if (this.yieldGeneration === generation) this.stopAutoPass(STOP_MESSAGES.interrupted);
      }
    })();
  }

  /** Stops a running skip; a pass already sent may still finish. */
  stopAutoPass(reason = "Auto-pass stopped. A pass already sent may still finish.") {
    if (!this.state.autoPassing && !this.yieldPolicy.isActive) return;
    this.yieldGeneration += 1;
    this.yieldPolicy.stop();
    this.set({ autoPassing: false, autoPassStatus: reason });
  }

  /** A legal action the board offered. Any action of the player's own stops a running skip. */
  send(action: LegalAction) {
    this.stopAutoPass();
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

  /** Sends an answer; one the player chose (not a skip's pass, `fromSkip`) stops a running skip. */
  async submit(command: GameCommand, label: string, actionID: string, fromSkip = false) {
    if (!fromSkip && !actionID.startsWith(SMART_PASS_ACTION_PREFIX) && !actionID.startsWith("auto-")) this.stopAutoPass();
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
    this.stopAutoPass();
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
    this.stopAutoPass();
    await this.client.concede(this.matchID, this.seatID);
    this.wakeLoop?.();
  }

  get hasPending() { return this.pending !== undefined; }
}
