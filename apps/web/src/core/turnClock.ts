/**
 * The online turn timer (port of TurnClock.kt / TurnClock.swift; parity/turn-clock-cases.json).
 * The host runs the clocks; a guest only parses the host's `clock` packet and burns the rope.
 * Times are seconds on the local monotonic clock.
 */
import { EnginePrompt, type MatchPoll } from "./engineClient";
import { arr, bool, EngineError, get, int, type J, keysEqual, obj, str } from "./json";

export const TurnClockRules = { decision: 60, rope: 20, grace: 20, strikesToForfeit: 3, resumeFloor: 10 } as const;

export interface TurnClockPrompt { id: string; revision: number }
export type TurnClockTimeout = "answer" | "grace" | "forfeit";
export interface TurnClockEntry { seat: string; remaining: number; limit: number; strikes: number }

const samePrompt = (a: TurnClockPrompt | undefined, b: TurnClockPrompt | undefined) =>
  a === b || (a !== undefined && b !== undefined && a.id === b.id && a.revision === b.revision);

interface Running { prompt: TurnClockPrompt; deadline: number; limit: number; frozen?: number; handled: boolean }

/** The host's clock for every human seat (a hosting browser runs it; parity cases in test/). */
export class TurnClock {
  private running = new Map<string, Running>();
  private strikeCounts = new Map<string, number>();
  private answeredByClock = new Map<string, TurnClockPrompt>();
  paused = false;

  strikes(seat: string) { return this.strikeCounts.get(seat) ?? 0; }

  private sortedRunning(): [string, Running][] { return [...this.running.entries()].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)); }

  observe(seat: string, prompt: TurnClockPrompt | undefined, now: number): boolean {
    const current = this.running.get(seat);
    if (current && samePrompt(current.prompt, prompt)) return false;
    if (!current && !prompt) return false;
    if (current) {
      if (!samePrompt(this.answeredByClock.get(seat), current.prompt)) this.strikeCounts.delete(seat);
      this.answeredByClock.delete(seat);
    }
    if (!prompt) this.running.delete(seat);
    else this.running.set(seat, {
      prompt, deadline: now + TurnClockRules.decision, limit: TurnClockRules.decision,
      frozen: this.paused ? TurnClockRules.decision : undefined, handled: false,
    });
    return true;
  }

  setPaused(value: boolean, now: number): boolean {
    if (value === this.paused) return false;
    this.paused = value;
    for (const clock of this.running.values()) {
      if (value) clock.frozen = Math.max(0, clock.deadline - now);
      else { clock.deadline = now + Math.max(clock.frozen ?? 0, Math.min(TurnClockRules.resumeFloor, clock.limit)); clock.frozen = undefined; }
    }
    return true;
  }

  expired(now: number): [string, TurnClockPrompt][] {
    if (this.paused) return [];
    return this.sortedRunning().filter(([, c]) => !c.handled && now >= c.deadline).map(([seat, c]) => [seat, c.prompt]);
  }

  timeout(seat: string, prompt: TurnClockPrompt, hasDefault: boolean, now: number): TurnClockTimeout | undefined {
    const clock = this.running.get(seat);
    if (!clock || !samePrompt(clock.prompt, prompt) || clock.handled) return undefined;
    const count = this.strikes(seat) + 1;
    this.strikeCounts.set(seat, count);
    if (count >= TurnClockRules.strikesToForfeit) { clock.handled = true; return "forfeit"; }
    if (hasDefault) { clock.handled = true; this.answeredByClock.set(seat, prompt); return "answer"; }
    clock.deadline = now + TurnClockRules.grace; clock.limit = TurnClockRules.grace;
    return "grace";
  }

  answerFailed(seat: string, prompt: TurnClockPrompt, now: number) {
    const clock = this.running.get(seat);
    if (!clock || !samePrompt(clock.prompt, prompt)) return;
    clock.handled = false; clock.deadline = now + TurnClockRules.grace; clock.limit = TurnClockRules.grace;
    this.answeredByClock.delete(seat);
  }

  clear() { this.running.clear(); this.strikeCounts.clear(); this.answeredByClock.clear(); this.paused = false; }

  entries(now: number): TurnClockEntry[] {
    return this.sortedRunning().filter(([, c]) => !c.handled).map(([seat, c]) => ({
      seat, remaining: c.frozen ?? Math.max(0, c.deadline - now), limit: c.limit, strikes: this.strikes(seat),
    }));
  }

  /** The answer passing would give, or undefined when the question has none. */
  static defaultAnswer(prompt: EnginePrompt): J | undefined {
    if (!prompt.responseTypes.includes("boolean")) return undefined;
    switch (prompt.kind) {
      case "SELECT":
        return ["priority", "attackers", "blockers"].includes(str(prompt.payload.selectMode) ?? "") ? EnginePrompt.answer("boolean", true) : undefined;
      case "PLAY_MANA": return EnginePrompt.answer("boolean", false);
      case "PICK_TARGET": case "CHOOSE_ABILITY": case "PICK_ABILITY":
        return bool(prompt.payload.required) === false ? EnginePrompt.answer("boolean", false) : undefined;
      default: return undefined;
    }
  }

  static prompt(poll: MatchPoll): TurnClockPrompt | undefined {
    const prompt = poll.prompt;
    return prompt && !prompt.submitted && poll.phase === "running" ? { id: prompt.id, revision: prompt.revision } : undefined;
  }
}

/** The host's `clock` packet. Remaining time travels instead of a deadline, so clocks never need to agree. */
export const TurnClockWire = {
  MAX_LIMIT_MILLIS: 120_000,

  packet(epoch: string, paused: boolean, entries: TurnClockEntry[]): J {
    return {
      type: "clock", epoch, paused,
      clocks: entries.map((e) => ({
        seat: e.seat, remainingMillis: Math.round(e.remaining * 1000), limitMillis: Math.round(e.limit * 1000), strikes: e.strikes,
      })),
    };
  },

  /** Strict: exactly these keys, at most four seats, each once, with sane times. */
  parse(value: J): { paused: boolean; entries: TurnClockEntry[] } {
    const fields = obj(value);
    const paused = bool(get(value, "paused"));
    const clocks = arr(get(value, "clocks"));
    const fail = () => EngineError.invalid("Invalid turn clock.");
    if (!fields || !keysEqual(fields, ["type", "epoch", "paused", "clocks"]) || str(fields.type) !== "clock" || paused === undefined ||
      !clocks || clocks.length > 4) throw fail();
    const entries = clocks.map((item) => {
      const entry = obj(item);
      const seat = str(get(item, "seat")); const remaining = int(get(item, "remainingMillis"));
      const limit = int(get(item, "limitMillis")); const strikes = int(get(item, "strikes"));
      if (!entry || !keysEqual(entry, ["seat", "remainingMillis", "limitMillis", "strikes"]) || seat === undefined ||
        !/^player[1-4]$/.test(seat) || limit === undefined || limit < 1 || limit > TurnClockWire.MAX_LIMIT_MILLIS ||
        remaining === undefined || remaining < 0 || remaining > limit || strikes === undefined || strikes < 0 || strikes > 3) throw fail();
      return { seat, remaining: remaining / 1000, limit: limit / 1000, strikes };
    });
    if (new Set(entries.map((e) => e.seat)).size !== entries.length) throw fail();
    return { paused, entries };
  },
};

export interface TurnClockBoardClock { seat: string; deadline: number; limit: number; strikes: number }
export interface TurnClockRope { seat: string; isLocal: boolean; remaining: number; fraction: number; strikes: number }

/** What a phone shows: the clocks with deadlines on its own clock. */
export class TurnClockBoard {
  constructor(readonly paused = false, readonly clocks: TurnClockBoardClock[] = []) {}

  static from(paused: boolean, entries: TurnClockEntry[], now: number): TurnClockBoard {
    return new TurnClockBoard(paused, entries.map((e) => ({ seat: e.seat, deadline: now + e.remaining, limit: e.limit, strikes: e.strikes })));
  }

  private pick(localSeat: string | undefined): TurnClockBoardClock | undefined {
    return this.clocks.find((c) => c.seat === localSeat) ??
      this.clocks.reduce<TurnClockBoardClock | undefined>((best, c) => (best === undefined || c.deadline < best.deadline ? c : best), undefined);
  }

  /** The one rope to burn: the local seat's own decision first, otherwise the clock that runs out soonest. */
  rope(localSeat: string | undefined, now: number): TurnClockRope | undefined {
    if (this.paused) return undefined;
    const pick = this.pick(localSeat);
    if (!pick) return undefined;
    const remaining = Math.max(0, pick.deadline - now);
    const window = Math.min(TurnClockRules.rope, pick.limit);
    if (remaining > window || remaining <= 0) return undefined;
    return { seat: pick.seat, isLocal: pick.seat === localSeat, remaining, fraction: remaining / window, strikes: pick.strikes };
  }

  secondsUntilRope(localSeat: string | undefined, now: number): number | undefined {
    if (this.paused) return undefined;
    const pick = this.pick(localSeat);
    if (!pick) return undefined;
    const remaining = pick.deadline - now;
    if (remaining <= 0) return undefined;
    return Math.max(0, remaining - Math.min(TurnClockRules.rope, pick.limit));
  }

  /** Seconds left on a seat's clock, for the medallion countdown. */
  remaining(seat: string, now: number): number | undefined {
    const clock = this.clocks.find((c) => c.seat === seat);
    return clock === undefined ? undefined : Math.max(0, clock.deadline - now);
  }
}
