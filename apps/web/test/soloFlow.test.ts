/**
 * A solo game against a scripted local engine: create → XMage's starting-player question → the D20 roll →
 * the roll's winner answered → concede → leave destroys the match. The starting-player prompt was recorded from
 * the Web Image engine (2026-10-21) and laid over the recorded 2-player poll the apps' fixtures use.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { DeckResolver } from "../src/core/deckResolver";
import { EngineJson, get, type J, type JObject, str } from "../src/core/json";
import { OnDeviceStartingRoll } from "../src/core/startingRoll";
import type { LocalEngine, WorkerTransport } from "../src/engine/localEngine";
import { AI_NAME, AI_SEAT, SOLO_SEAT, soloConfiguration, SoloTable, type SoloSetup } from "../src/table/soloTable";

const repo = join(__dirname, "..", "..", "..");
const recorded = JSON.parse(readFileSync(join(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice/2p-initial-player-1.json"), "utf8")) as JObject;
const MATCH = str(recorded.matchId)!;
const VIEWER = "83c51f38-1926-4c78-a744-ca1ec0b4048a";
const OPPONENT = "8d3bec80-e9fa-409e-8960-4918885793cb";

/** XMage's opening question as the Web Image engine sent it, for this fixture's two players. */
const startingPrompt: J = {
  kind: "PICK_TARGET", max: 0, min: 0, promptId: "845e01e4-6f27-47cb-bcb0-2e9c5efc669e", responseTypes: ["uuid"], revision: 5, submitted: false,
  payload: {
    candidates: [VIEWER, OPPONENT], cards: [], message: "Select a starting player", required: true, responseAliases: {},
    options: { chosenTargets: [], queryType: "PICK_TARGET", targetZone: null },
  },
};

const decks = () => {
  const resolver = new DeckResolver(readFileSync(join(__dirname, "..", "public/generated/printings.tsv"), "utf8"));
  const precons = JSON.parse(readFileSync(join(__dirname, "..", "public/generated/precons.json"), "utf8"));
  return { deck: resolver.resolve(precons.decks[0]), aiDeck: resolver.resolve(precons.decks[4]) };
};

/** The engine's side of the protocol: answers each request from a script, recording what the page sent. */
class ScriptedEngine {
  requests: JObject[] = [];
  answered?: J;
  conceded = false;
  destroyed = false;
  transport = {
    failure: undefined,
    request: async (text: string) => {
      const request = EngineJson.decode(text) as JObject;
      this.requests.push(request);
      return EngineJson.encode({ protocol: 1, ok: true, result: this.reply(request) });
    },
  } as unknown as WorkerTransport;

  private reply(request: JObject): J {
    switch (request.op) {
      case "create": return { matchId: MATCH };
      case "poll": {
        if (this.conceded) return { ...recorded, viewerId: SOLO_SEAT, revision: 9, phase: "ended", prompt: null, events: [] };
        if (this.answered) return { ...recorded, viewerId: SOLO_SEAT, revision: 6, events: [] };
        return { ...recorded, viewerId: SOLO_SEAT, revision: 5, prompt: startingPrompt, events: [] };
      }
      case "respond": this.answered = get(request.command, "answer") ?? null; return { accepted: true, revision: 6 };
      case "capabilities": return { protocol: 1, answerActions: ["rememberAnswer", "rememberTriggerFirst", "passUntilStackResolved", "autoPassAfterCast"] };
      case "concede": this.conceded = true; return {};
      case "destroy": this.destroyed = true; return {};
      default: throw new Error("unexpected " + String(request.op));
    }
  }

  engine(): LocalEngine {
    return { start: async () => this.transport, subscribe: () => () => undefined, state: { stage: "ready", loaded: 0, total: 0 } } as unknown as LocalEngine;
  }
}

const until = async (check: () => boolean, millis = 5_000) => {
  const deadline = Date.now() + millis;
  while (!check()) {
    if (Date.now() > deadline) throw new Error("timed out");
    await new Promise((resolve) => setTimeout(resolve, 20));
  }
};

describe("solo table", () => {
  it("builds the phones' AI configuration: one human seat, one AI seat with its skill, no seeds", () => {
    const { deck, aiDeck } = decks();
    const setup: SoloSetup = { name: "Caleb", deck, aiDeck, aiSkill: 4, startingPlayerMode: "roll" };
    expect(soloConfiguration(setup)).toEqual({
      seats: [
        { seatId: SOLO_SEAT, name: "Caleb", controller: "human", deck },
        { seatId: AI_SEAT, name: AI_NAME, controller: "ai", deck: aiDeck, aiSkill: 4 },
      ],
    });
    expect(() => soloConfiguration({ ...setup, aiSkill: 11 })).toThrow(/1–10/);
  });

  it("rolls for the starting player, answers XMage with the winner, concedes and destroys the match", async () => {
    const script = new ScriptedEngine();
    let left = false;
    const table = new SoloTable(script.engine(), { name: "Caleb", ...decks(), aiSkill: 2, startingPlayerMode: "roll" }, () => { left = true; });
    await table.start();
    expect(table.state.stage).toBe("playing");
    // The engine's answer actions first (capabilities), then the match.
    expect(script.requests.slice(0, 2).map((r) => r.op)).toEqual(["capabilities", "create"]);

    // XMage asks the human (seat player1 chooses) who starts: the table rolls instead, the player first.
    await until(() => table.state.roll !== undefined);
    expect(table.state.localSeatID).toBe(VIEWER);
    expect(table.state.roll!.nextSeatID).toBe(VIEWER);
    expect(table.state.seatNames[VIEWER]).toBe("You");
    table.rollStartingPlayer();
    // The AI's die reveals itself, the winner shows, then the answer goes to XMage.
    await until(() => script.answered !== undefined, 8_000);
    const winner = table.state.roll!.roll.winnerSeatID;
    expect([VIEWER, OPPONENT]).toContain(winner);
    // The player's standing preference (pass after casting, on) rides on their first answer.
    expect(script.answered).toEqual({ kind: "uuid", value: winner, actions: [{ type: "autoPassAfterCast", enabled: true }] });
    expect(table.state.roll!.revealed).toBe(table.state.roll!.roll.steps.length);

    await table.concede();
    expect(script.conceded).toBe(true);
    await until(() => table.session?.state.phase === "ended");
    table.leave();
    expect(left).toBe(true);
    await until(() => script.destroyed);
    expect(script.requests.filter((r) => r.op === "concede")).toHaveLength(1); // an ended game is not conceded again
  }, 15_000);

  it("generates valid rolls that reroll ties among the tied seats", () => {
    const draws = [7, 7, 3, 12];
    const roll = OnDeviceStartingRoll.generate(["a", "b"], () => draws.shift()!);
    expect(roll.rounds.map((round) => [...round.values()])).toEqual([[7, 7], [3, 12]]);
    expect(roll.winnerSeatID).toBe("b");
    expect(() => OnDeviceStartingRoll.generate(["a"])).toThrow();
    expect(() => OnDeviceStartingRoll.generate(["a", "b"], () => 21)).toThrow();
  });
});
