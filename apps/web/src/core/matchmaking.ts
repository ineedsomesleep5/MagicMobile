/**
 * Playing people: friend challenges (iOS Ranked/FriendChallenges.swift, Android FriendChallenges.kt) and the ranked
 * queue (Ranked/RankedQueue.swift, Android RankedMatchmaker). The server keeps both (mm_challenge_* in
 * supabase/migrations/20261004180000_friend_challenges.sql, mm_ranked_* in 20261004120000_ranked_ladder.sql); the
 * challenger or the queue's host opens a relay table and hands its code over.
 */
import type { FriendChallenge, FriendChallengeService, RankedQueueService, RankedTicket } from "./account";
import { PlayerAccountRules } from "./account";
import { get, isUuid, type J, str } from "./json";
import type { PlayMode } from "./playerRecord";
import { type RankOutcome, RankPosition } from "./rankLadder";
import { SupabaseFailure, SupabaseLite } from "./supabaseLite";

const num = (value: J | undefined) => (typeof value === "number" && Number.isInteger(value) ? value : undefined);
const uuid = (value: J | undefined) => (isUuid(value) ? (value as string) : undefined);

/** A challenge row; undefined when the JSON isn't one. */
export function decodeChallenge(json: J): FriendChallenge | undefined {
  const id = uuid(get(json, "id")), mode = str(get(json, "mode")), status = str(get(json, "status"));
  if (!id || mode === undefined || status === undefined) return undefined;
  const optional = <T>(key: string, value: T | undefined) => (value === undefined ? {} : { [key]: value });
  return {
    id, mode, status,
    ...optional("role", str(get(json, "role"))), ...optional("challenger", str(get(json, "challenger"))),
    ...optional("challenged", str(get(json, "challenged"))), ...optional("challengerStep", num(get(json, "challengerStep"))),
    ...optional("protocol", str(get(json, "protocol"))), ...optional("tableCode", str(get(json, "tableCode"))),
    ...optional("matchId", uuid(get(json, "matchId"))),
  };
}

export const FriendChallengeRules = {
  /** A challenge waits this long for an answer (the server's limit). */
  expirySeconds: 120,
  isRanked: (challenge: FriendChallenge) => challenge.mode === "ranked",
  isPending: (challenge: FriendChallenge) => challenge.status === "pending",
  /** What a challenge reads as once nothing is known about it any more. */
  closed: (id: string): FriendChallenge => ({ id, mode: "quick", status: "cancelled" }),
  /**
   * Ranked friend games need the same tier, Gold with Gold (Caleb, 2026-10-04). A friend without a published standing
   * this season is a fresh Bronze IV, as the server reads them.
   */
  mayRank: (myStep: number, friendStep: number | undefined) => RankPosition.atStep(myStep).tier === RankPosition.atStep(friendStep ?? 0).tier,
  message(code: string): string {
    switch (code) {
      case "rank_mismatch": return "Ranked challenges need the same tier.";
      case "not_friends": return "You can only challenge friends.";
      case "challenge_closed": return "That challenge has closed.";
      case "protocol_mismatch": return "You're on different app versions. Update both phones to play.";
      default: return PlayerAccountRules.message(code);
    }
  },
};

export class SupabaseFriendChallenges implements FriendChallengeService {
  constructor(private readonly api: SupabaseLite) {}

  private challenge(json: J, id?: string): FriendChallenge {
    const decoded = decodeChallenge(json);
    if (decoded) return decoded;
    if (!id) throw new SupabaseFailure("error");
    return FriendChallengeRules.closed(id); // the server no longer shows it to this player
  }

  async send(username: string, mode: PlayMode, protocol: string, rankStep: number, tableCode: string) {
    return this.challenge(await this.api.rpc("mm_challenge_send", { p_username: username, p_mode: mode, p_protocol: protocol, p_rank_step: rankStep, p_table_code: tableCode }));
  }
  async incoming() {
    const rows = await this.api.rpc("mm_challenge_incoming");
    if (!Array.isArray(rows)) throw new SupabaseFailure("error");
    return rows.flatMap((row) => decodeChallenge(row) ?? []);
  }
  async status(id: string) { return this.challenge(await this.api.rpc("mm_challenge_status", { p_challenge: id }), id); }
  async accept(id: string, protocol: string, rankStep: number) {
    return this.challenge(await this.api.rpc("mm_challenge_accept", { p_challenge: id, p_protocol: protocol, p_rank_step: rankStep }));
  }
  async decline(id: string) { await this.api.rpc("mm_challenge_decline", { p_challenge: id }); }
  async cancel(id: string) { return this.challenge(await this.api.rpc("mm_challenge_cancel", { p_challenge: id }), id); }
}

export type ChallengeAnswer =
  | { kind: "accepted"; challenge: FriendChallenge }
  | { kind: "declined" } | { kind: "expired" } | { kind: "cancelled" }
  /** A server error code (FriendChallengeRules.message). */
  | { kind: "failed"; code: string };

type Sleep = (seconds: number) => Promise<void>;
const realSleep: Sleep = (seconds) => new Promise((resolve) => setTimeout(resolve, seconds * 1000));

/** Something the menus redraw from: a version that moves on every change. */
class Observable {
  version = 0;
  private listeners = new Set<() => void>();
  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  protected changed() { this.version += 1; for (const listener of [...this.listeners]) listener(); }
}

/**
 * Sends challenges and waits for the answer; watches for challenges sent to this player while the menus are open
 * (FriendChallengeCoordinator).
 */
export class FriendChallengeCoordinator extends Observable {
  /** How often the menu checks for challenges while a friend is online, and while none is. */
  static readonly watchSeconds = 5;
  static readonly quietWatchSeconds = 20;

  /** The challenge this player sent, while waiting for the friend. */
  outgoing?: FriendChallenge;
  /** Challenges waiting for this player, newest first. */
  incoming: FriendChallenge[] = [];
  private cancelRequested = false;
  private answered = new Set<string>();
  private watching = 0;

  constructor(public service: FriendChallengeService | undefined, private readonly sleep: Sleep = realSleep, private readonly clock = () => Date.now()) { super(); }

  get isWaiting() { return this.outgoing !== undefined; }

  /** Sends a challenge for a table this player already opened, then waits for the answer. */
  async challenge(username: string, mode: PlayMode, protocol: string, rankStep: number, tableCode: string): Promise<ChallengeAnswer> {
    const service = this.service;
    if (!service) return { kind: "failed", code: "offline" };
    if (this.outgoing) return { kind: "failed", code: "error" };
    this.cancelRequested = false;
    try {
      let current = await service.send(username, mode, protocol, rankStep, tableCode);
      this.outgoing = current; this.changed();
      try {
        const started = this.clock();
        while (FriendChallengeRules.isPending(current)) {
          if (this.cancelRequested || (this.clock() - started) / 1000 > FriendChallengeRules.expirySeconds + 5) {
            // An answer that arrived meanwhile still stands.
            const final = await service.cancel(current.id).catch(() => FriendChallengeRules.closed(current.id));
            if (final.status === "accepted") return { kind: "accepted", challenge: final };
            return { kind: this.cancelRequested ? "cancelled" : "expired" };
          }
          await this.sleep(2);
          current = await service.status(current.id);
        }
        switch (current.status) {
          case "accepted": return { kind: "accepted", challenge: current };
          case "declined": return { kind: "declined" };
          case "expired": return { kind: "expired" };
          default: return { kind: "cancelled" };
        }
      } finally { this.outgoing = undefined; this.changed(); }
    } catch (error) {
      return { kind: "failed", code: SupabaseLite.code(error) };
    }
  }

  /** Withdraws the challenge being waited on. */
  cancelOutgoing() { this.cancelRequested = true; }

  /** Checks for challenges until `stop` (while the menus show). Slower when no friend could challenge. */
  watch(friendOnline: () => boolean = () => true): () => void {
    const run = ++this.watching;
    void (async () => {
      while (run === this.watching) {
        await this.refreshIncoming();
        if (run !== this.watching) return;
        await this.sleep(friendOnline() ? FriendChallengeCoordinator.watchSeconds : FriendChallengeCoordinator.quietWatchSeconds);
      }
    })();
    return () => { if (run === this.watching) this.watching += 1; };
  }

  async refreshIncoming() {
    if (!this.service) { if (this.incoming.length > 0) { this.incoming = []; this.changed(); } return; }
    let list: FriendChallenge[];
    try { list = await this.service.incoming(); } catch { return; }
    const next = list.filter((c) => FriendChallengeRules.isPending(c) && !this.answered.has(c.id));
    // Assigned only on a change: every assignment redraws the menus.
    if (JSON.stringify(next) !== JSON.stringify(this.incoming)) { this.incoming = next; this.changed(); }
  }

  /** Accepts: the challenge with its table code (and the ranked match for ranked). */
  async accept(challenge: FriendChallenge, protocol: string, rankStep: number): Promise<FriendChallenge> {
    this.answered.add(challenge.id);
    this.incoming = this.incoming.filter((c) => c.id !== challenge.id); this.changed();
    if (!this.service) throw new SupabaseFailure("offline");
    return this.service.accept(challenge.id, protocol, rankStep);
  }

  async decline(challenge: FriendChallenge) {
    this.answered.add(challenge.id);
    this.incoming = this.incoming.filter((c) => c.id !== challenge.id); this.changed();
    await this.service?.decline(challenge.id).catch(() => undefined);
  }
}

/** A queue ticket; undefined when the JSON isn't one. */
export function decodeTicket(json: J): RankedTicket | undefined {
  const status = str(get(json, "status"));
  if (status === undefined) return undefined;
  const optional = <T>(key: string, value: T | undefined) => (value === undefined ? {} : { [key]: value });
  return {
    status, ...optional("ticket", uuid(get(json, "ticket"))), ...optional("matchId", uuid(get(json, "matchId"))),
    ...optional("role", str(get(json, "role"))), ...optional("tableCode", str(get(json, "tableCode"))),
    ...optional("opponent", str(get(json, "opponent"))), ...optional("opponentStep", num(get(json, "opponentStep"))),
  };
}

export const RankedTicketRules = {
  isMatched: (ticket: RankedTicket) => ticket.status === "matched" && ticket.matchId !== undefined,
  isHost: (ticket: RankedTicket) => ticket.role === "host",
};

export class SupabaseRankedQueue implements RankedQueueService {
  constructor(private readonly api: SupabaseLite) {}
  private ticket(json: J): RankedTicket {
    const decoded = decodeTicket(json);
    if (!decoded) throw new SupabaseFailure("error");
    return decoded;
  }
  async enqueue(protocol: string, rankStep: number, deckBracket: number) {
    return this.ticket(await this.api.rpc("mm_ranked_enqueue", { p_protocol: protocol, p_rank_step: rankStep, p_deck_bracket: deckBracket }));
  }
  async poll(ticket: string) { return this.ticket(await this.api.rpc("mm_ranked_poll", { p_ticket: ticket })); }
  async cancel(ticket: string) { return this.ticket(await this.api.rpc("mm_ranked_cancel", { p_ticket: ticket })); }
  async setTable(match: string, code: string) { await this.api.rpc("mm_ranked_set_table", { p_match: match, p_code: code }); }
  async report(match: string, outcome: RankOutcome) { await this.api.rpc("mm_ranked_report", { p_match: match, p_result: outcome }); }
}

export type RankedPhase = { kind: "idle" } | { kind: "searching"; since: number } | { kind: "matched"; ticket: RankedTicket };
export type RankedSearchOutcome = { kind: "human"; ticket: RankedTicket } | { kind: "ai" } | { kind: "cancelled" };

/**
 * Searches the ranked queue for a person for a short while; when nobody suitable is searching, an AI at your tier
 * takes the seat (RankedMatchmaker).
 */
export class RankedMatchmaker extends Observable {
  /** How long to look for a person before an AI takes the seat. */
  static readonly searchSeconds = 40;
  /** How long a guest waits for the host's table code. */
  static readonly tableCodeSeconds = 30;

  phase: RankedPhase = { kind: "idle" };
  private ticket?: string;
  private cancelled = false;
  private playAINow = false;

  constructor(public service: RankedQueueService | undefined, private readonly sleep: Sleep = realSleep, private readonly clock = () => Date.now()) { super(); }

  get isSearching() { return this.phase.kind !== "idle"; }
  private set(phase: RankedPhase) { this.phase = phase; this.changed(); }

  /** Looks for an opponent. Without a profile this is an AI game at once. */
  async search(protocol: string, rankStep: number, deckBracket: number): Promise<RankedSearchOutcome> {
    const service = this.service;
    if (!service || this.phase.kind !== "idle") return { kind: "ai" };
    this.cancelled = false; this.playAINow = false;
    const started = this.clock();
    this.set({ kind: "searching", since: started });
    const elapsed = (from: number) => (this.clock() - from) / 1000;
    try {
      let current = await service.enqueue(protocol, rankStep, deckBracket);
      this.ticket = current.ticket;
      while (!RankedTicketRules.isMatched(current)) {
        if (this.cancelled || this.playAINow || elapsed(started) >= RankedMatchmaker.searchSeconds) {
          // A match made in the meantime still goes ahead (unless the player cancelled outright).
          if (!this.ticket) { this.set({ kind: "idle" }); return { kind: this.cancelled ? "cancelled" : "ai" }; }
          const final = await service.cancel(this.ticket);
          if (RankedTicketRules.isMatched(final) && !this.cancelled) { current = final; break; }
          if (RankedTicketRules.isMatched(final) && final.matchId) await service.report(final.matchId, "loss").catch(() => undefined);
          this.ticket = undefined;
          this.set({ kind: "idle" });
          return { kind: this.cancelled ? "cancelled" : "ai" };
        }
        await this.sleep(2);
        if (!this.ticket) { this.set({ kind: "idle" }); return { kind: "ai" }; }
        current = await service.poll(this.ticket);
      }
      this.set({ kind: "matched", ticket: current });
      if (RankedTicketRules.isHost(current)) return { kind: "human", ticket: current };
      // The guest needs the host's table code.
      const waitStarted = this.clock();
      while (current.tableCode === undefined) {
        if (this.cancelled) { this.set({ kind: "idle" }); return { kind: "cancelled" }; }
        if (elapsed(waitStarted) >= RankedMatchmaker.tableCodeSeconds) { this.set({ kind: "idle" }); return { kind: "ai" }; }
        await this.sleep(1.5);
        if (!this.ticket) { this.set({ kind: "idle" }); return { kind: "ai" }; }
        current = await service.poll(this.ticket);
        this.set({ kind: "matched", ticket: current });
      }
      return { kind: "human", ticket: current };
    } catch {
      // The queue is a bonus: any server trouble means an AI game.
      this.set({ kind: "idle" });
      return { kind: this.cancelled ? "cancelled" : "ai" };
    }
  }

  /** Stops searching and goes back to the ranked screen. */
  cancel() { this.cancelled = true; }
  /** Stops searching and plays the AI now. */
  skipToAI() { this.playAINow = true; }
  /** The match is under way (or abandoned): the matchmaker is free again. */
  finish() { this.ticket = undefined; this.set({ kind: "idle" }); }

  async shareTable(match: string, code: string) { await this.service?.setTable(match, code).catch(() => undefined); }
  async report(match: string, outcome: RankOutcome) { await this.service?.report(match, outcome).catch(() => undefined); }
}
