// SPIKE ONLY. Transport-agnostic game driver: one scripted human seat against XMage AI seats.
// Runs unchanged in the browser (CheerpJ worker) and in Node against the JVM EngineCli,
// so the two can be compared on the same machine. It answers only from the options in the
// current prompt; legality stays in XMage. Seeds drive deck order and this driver's choices;
// XMage's own shuffles and AI scheduling are not seeded.
import { EngineError, type Answer, type EngineClient, type EnginePrompt, type JsonObject, type MatchEvent } from "./engineClient.ts";

export type GameSpec = {
  label: string;
  seed: number;
  players: number; // 2–4; seat 0 is the scripted human, the rest are XMage AI
  decks: { id: string; deck: JsonObject }[]; // one per seat
  aiSkill?: number;
  capMs: number; // wall-time cap for the whole game
  stallMs?: number; // no engine progress for this long counts as a stall
};

export type GameResult = {
  label: string;
  seed: number;
  players: number;
  deckIds: string[];
  result: "ended" | "timeout" | "stalled" | "failed";
  failure?: string;
  winner: "human" | "ai" | "none" | null;
  wallMs: number;
  createMs: number;
  firstPromptMs: number | null; // create request -> first human prompt ("game start")
  turns: number;
  humanResponses: number;
  promptKinds: Record<string, number>;
  boardUpdateMs: number[]; // respond -> next snapshot/prompt/end event for the human seat
  aiTurnMs: number[]; // wall time of each completed AI turn (first to last observation)
  humanTurnMs: number[];
  pollMs: number[];
  respondMs: number[];
  maxSnapshotBytes: number;
  destroyMs: number | null;
};

// Deterministic PRNG (mulberry32) for driver choices and deck order.
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));
const now = () => performance.now();

export function configuration(spec: GameSpec): JsonObject {
  const random = rng(spec.seed);
  const seats = spec.decks.slice(0, spec.players).map(({ deck }, index) => {
    const copy = JSON.parse(JSON.stringify(deck)) as JsonObject;
    const main = copy.main as JsonObject[];
    for (let i = main.length - 1; i > 0; i--) {
      const j = Math.floor(random() * (i + 1));
      [main[i], main[j]] = [main[j], main[i]];
    }
    const seat: JsonObject = { seatId: `seat-${index}`, name: index === 0 ? "Bench Human" : `XMage AI ${index}`, deck: copy };
    if (index === 0) seat.controller = "human";
    else {
      seat.controller = "ai";
      if (spec.aiSkill !== undefined) seat.aiSkill = spec.aiSkill;
    }
    return seat;
  });
  return { seats };
}

type TurnState = { turn: number; activePlayerId: string; landTried: boolean; castTried: Set<string>; attacked: boolean; prompts: number };

/** Scripted human: play a land, cast what XMage says is castable, attack with everything, never block. */
class Policy {
  private readonly random: () => number;
  private manaTried = new Set<string>();
  turnState: TurnState = { turn: -1, activePlayerId: "", landTried: false, castTried: new Set(), attacked: false, prompts: 0 };

  constructor(seed: number) {
    this.random = rng(seed ^ 0x5eed);
  }

  private pick<T>(items: T[]): T {
    return items[Math.floor(this.random() * items.length)];
  }

  answer(prompt: EnginePrompt, snapshot: JsonObject): Answer {
    const view = snapshot.gameView as JsonObject;
    const me = snapshot.enginePlayerId as string;
    const turn = Number(view.turn ?? 0);
    const active = String(view.activePlayerId ?? "");
    if (turn !== this.turnState.turn || active !== this.turnState.activePlayerId) {
      this.turnState = { turn, activePlayerId: active, landTried: false, castTried: new Set(), attacked: false, prompts: 0 };
    }
    this.turnState.prompts++;
    const payload = prompt.payload;
    const message = String(payload.message ?? "").toLowerCase();
    const options = (payload.options ?? {}) as JsonObject;
    const types = new Set(prompt.responseTypes);
    const pass: Answer = { kind: "boolean", value: false };
    // Loop guard: a runaway turn (e.g. a payment XMage keeps re-asking) degrades to passing.
    const runaway = this.turnState.prompts > 400;
    if (prompt.kind !== "PLAY_MANA") this.manaTried.clear();
    switch (prompt.kind) {
      case "ASK":
        // "Mana will be lost. Pass anyway?" must be confirmed or XMage re-asks forever.
        if (message.includes("pass anyway")) return { kind: "boolean", value: true };
        return pass; // keep opening hands, decline optional costs
      case "SELECT": {
        const mode = payload.selectMode;
        if (mode === "attackers") {
          if (!runaway && !this.turnState.attacked && "specialButton" in options && types.has("string")) {
            this.turnState.attacked = true;
            return { kind: "string", value: "special" }; // "attack with all"
          }
          return pass;
        }
        if (mode === "blockers" || runaway || active !== me) return pass;
        const playable = (((view.canPlayObjects ?? {}) as JsonObject).objects ?? {}) as JsonObject;
        const entries = Object.entries(playable) as [string, JsonObject][];
        if (!this.turnState.landTried) {
          const land = entries.find(([, abilities]) => Array.isArray(abilities.basicPlayAbilities) && abilities.basicPlayAbilities.length > 0);
          if (land) {
            this.turnState.landTried = true;
            return { kind: "uuid", value: land[0] };
          }
        }
        const castable = entries.filter(
          ([id, abilities]) => !this.turnState.castTried.has(id) && Array.isArray(abilities.basicCastAbilities) && abilities.basicCastAbilities.length > 0,
        );
        if (castable.length && this.turnState.castTried.size < 6) {
          const [id] = this.pick(castable);
          this.turnState.castTried.add(id);
          return { kind: "uuid", value: id };
        }
        return pass;
      }
      case "PLAY_MANA": {
        const player = ((view.players ?? []) as JsonObject[]).find((p) => p.playerId === me);
        const lands = Object.values((player?.battlefield ?? {}) as JsonObject)
          .map((card) => card as JsonObject)
          .filter((card) => !card.tapped && ((card.cardTypes ?? []) as string[]).includes("LAND") && !this.manaTried.has(String(card.id)));
        if (runaway || !lands.length) {
          this.manaTried.clear();
          return pass; // cancel the payment; XMage rolls the spell back
        }
        // Prefer a land that makes a colour the message still asks for ("Pay {1}{G}").
        const needed = [...String(payload.message ?? "").matchAll(/\{([WUBRGC])\}/g)].map((m) => m[1]);
        const score = (card: JsonObject) => {
          const rules = JSON.stringify(card.rules ?? []);
          if (needed.some((c) => rules.includes(`{${c}}`))) return 2;
          return rules.includes("any color") ? 1 : 0;
        };
        const land = [...lands].sort((a, b) => (needed.length ? score(b) - score(a) : score(a) - score(b)))[0];
        this.manaTried.add(String(land.id));
        return { kind: "uuid", value: String(land.id) };
      }
      case "PLAY_X_MANA":
        return pass;
      case "PICK_TARGET": {
        const candidates = (payload.candidates ?? []) as string[];
        const chosen = new Set(((options.chosenTargets ?? []) as string[]).map(String));
        if (message.includes("starting player") && candidates.includes(me)) return { kind: "uuid", value: me };
        const open = candidates.filter((id) => !chosen.has(id));
        if ((!open.length || runaway) && types.has("boolean")) return pass;
        const pool = open.length ? open : candidates;
        if (!pool.length) throw new EngineError("bench_policy", "Target prompt without candidates");
        return { kind: "uuid", value: this.pick(pool) };
      }
      case "CHOOSE_CHOICE": {
        const order = (payload.choiceOrder ?? []) as string[];
        if (order.length) return { kind: "string", value: this.pick(order) };
        return { kind: "string", value: "" };
      }
      case "CHOOSE_MODE":
        return { kind: "uuid", value: ((payload.choiceOrder ?? []) as string[])[0] };
      case "CHOOSE_ABILITY":
      case "PICK_ABILITY":
        return { kind: "uuid", value: String((((payload.abilities ?? []) as JsonObject[])[0] ?? {}).id) };
      case "AMOUNT":
        return { kind: "integer", value: prompt.min };
      case "MULTI_AMOUNT": {
        const rows = (payload.allocations ?? []) as JsonObject[];
        const values = rows.map((row) => Number(row.min));
        let total = values.reduce((a, b) => a + b, 0);
        for (let i = 0; i < rows.length && total < prompt.min; i++) {
          const add = Math.min(Number(rows[i].max) - values[i], prompt.min - total);
          values[i] += add;
          total += add;
        }
        return { kind: "integers", value: values };
      }
      case "CHOOSE_PILE":
        return { kind: "boolean", value: true };
      default:
        if (types.has("boolean")) return pass;
        throw new EngineError("bench_policy", "Unhandled prompt kind " + prompt.kind);
    }
  }
}

export async function playGame(
  client: EngineClient,
  spec: GameSpec,
  onProgress?: (text: string) => void,
  trace?: (prompt: EnginePrompt, answer: Answer, snapshot: JsonObject) => void,
): Promise<GameResult> {
  const policy = new Policy(spec.seed);
  const stallMs = spec.stallMs ?? 180_000;
  const result: GameResult = {
    label: spec.label, seed: spec.seed, players: spec.players, deckIds: spec.decks.slice(0, spec.players).map((d) => d.id),
    result: "failed", winner: null, wallMs: 0, createMs: 0, firstPromptMs: null, turns: 0, humanResponses: 0,
    promptKinds: {}, boardUpdateMs: [], aiTurnMs: [], humanTurnMs: [], pollMs: [], respondMs: [], maxSnapshotBytes: 0, destroyMs: null,
  };
  const started = now();
  const created = await client.create(configuration(spec));
  result.createMs = now() - started;
  const matchId = String(created.matchId);
  const seat = "seat-0";
  const deadline = started + spec.capMs;
  let cursor = 0;
  let lastProgress = now();
  let pendingUpdate: { sentAt: number; revision: number } | null = null;
  let answered = new Set<string>();
  let turnKey = "";
  let turnStart = 0;
  let turnIsAI = false;
  let idle = 0;
  const closeTurn = (at: number) => {
    if (turnKey) (turnIsAI ? result.aiTurnMs : result.humanTurnMs).push(at - turnStart);
  };
  try {
    while (true) {
      if (now() > deadline) {
        result.result = "timeout";
        break;
      }
      const pollStart = now();
      const state = await client.poll(matchId, seat, cursor);
      const polledAt = now();
      result.pollMs.push(polledAt - pollStart);
      if (state.revision > cursor) {
        lastProgress = polledAt;
        idle = 0;
      }
      const events: MatchEvent[] = state.events ?? [];
      if (pendingUpdate && events.some((e) => e.revision > pendingUpdate!.revision && e.kind !== "prompt_consumed" && e.kind !== "message")) {
        result.boardUpdateMs.push(polledAt - pendingUpdate.sentAt);
        pendingUpdate = null;
      }
      cursor = Math.max(cursor, state.revision);
      if (state.snapshot) {
        const bytes = JSON.stringify(state.snapshot).length;
        result.maxSnapshotBytes = Math.max(result.maxSnapshotBytes, bytes);
        const view = state.snapshot.gameView as JsonObject;
        const key = `${view.turn}:${view.activePlayerId}`;
        result.turns = Math.max(result.turns, Number(view.turn ?? 0));
        if (key !== turnKey && view.activePlayerId) {
          closeTurn(polledAt);
          turnKey = key;
          turnStart = polledAt;
          turnIsAI = view.activePlayerId !== state.snapshot.enginePlayerId;
          onProgress?.(`${spec.label}: turn ${view.turn} (${turnIsAI ? "AI" : "human"})`);
        }
      }
      if (state.phase === "failed") {
        result.result = "failed";
        result.failure = JSON.stringify(state.failure);
        break;
      }
      if (state.phase === "ended") {
        closeTurn(polledAt);
        turnKey = "";
        result.result = "ended";
        const outcome = (state.snapshot?.outcome ?? {}) as JsonObject;
        const winners = (outcome.winnerPlayerIds ?? []) as string[];
        result.winner = winners.length === 0 ? "none" : winners.includes(String(state.snapshot?.enginePlayerId)) ? "human" : "ai";
        break;
      }
      const prompt = state.prompt;
      if (prompt && !prompt.submitted && !answered.has(prompt.promptId) && state.snapshot) {
        if (result.firstPromptMs === null) result.firstPromptMs = polledAt - started;
        answered.add(prompt.promptId);
        if (answered.size > 4096) answered = new Set([prompt.promptId]);
        result.promptKinds[prompt.kind] = (result.promptKinds[prompt.kind] ?? 0) + 1;
        const answer = policy.answer(prompt, state.snapshot);
        trace?.(prompt, answer, state.snapshot);
        const sentAt = now();
        try {
          const receipt = await client.respond(matchId, seat, prompt, answer);
          result.respondMs.push(now() - sentAt);
          result.humanResponses++;
          pendingUpdate = { sentAt, revision: Number(receipt.revision) };
        } catch (error) {
          // A prompt replaced between poll and respond is normal; anything else is a real failure.
          if (!(error instanceof EngineError) || (error.code !== "stale_prompt" && error.code !== "response_pending")) throw error;
        }
        continue; // poll again immediately: the engine usually answers within milliseconds on the JVM
      }
      if (now() - lastProgress > stallMs) {
        result.result = "stalled";
        break;
      }
      // Back off while XMage (usually an AI) is thinking; every poll costs engine time in CheerpJ.
      idle++;
      await sleep(idle < 4 ? 10 : idle < 20 ? 50 : 150);
    }
  } catch (error) {
    result.result = "failed";
    result.failure = String((error as Error)?.message ?? error);
  } finally {
    result.wallMs = now() - started;
    const destroyStart = now();
    for (let attempt = 0; attempt < 100; attempt++) {
      try {
        await client.destroy(matchId);
        result.destroyMs = now() - destroyStart;
        break;
      } catch (error) {
        if (error instanceof EngineError && error.code === "engine_busy_shutdown") {
          await sleep(200);
          continue;
        }
        if (error instanceof EngineError && error.code === "unknown_match") break;
        result.failure = (result.failure ? result.failure + "; " : "") + "destroy: " + String((error as Error)?.message ?? error);
        break;
      }
    }
  }
  return result;
}

export function stats(values: number[]) {
  if (!values.length) return { n: 0, median: null, p95: null, max: null, mean: null };
  const sorted = [...values].sort((a, b) => a - b);
  const at = (q: number) => sorted[Math.min(sorted.length - 1, Math.ceil(q * sorted.length) - 1)];
  const round = (v: number) => Math.round(v * 10) / 10;
  return {
    n: sorted.length,
    median: round(at(0.5)),
    p95: round(at(0.95)),
    max: round(sorted[sorted.length - 1]),
    mean: round(sorted.reduce((a, b) => a + b, 0) / sorted.length),
  };
}
