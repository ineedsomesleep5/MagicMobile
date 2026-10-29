/**
 * The web port must adapt the same engine polls and prompt cases to exactly what iOS produces
 * (apps/android/core/src/test/resources/parity/golden, written by ParityGoldenTests.swift).
 */
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EnginePrompt, MatchPoll } from "../src/core/engineClient";
import { EngineJson, get, type J, str } from "../src/core/json";
import { OnDeviceMessageLog } from "../src/core/messageLog";
import { decodePlayer } from "../src/core/models";
import { OnDevicePromptAdapter } from "../src/core/promptAdapter";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import * as Summary from "./paritySummary";

export const repo = join(__dirname, "..", "..", "..");
export const parity = join(repo, "apps/android/core/src/test/resources/parity");
const fixtures = join(repo, "apps/ios/MagicMobileTests/Fixtures/OnDevice");
const golden = (name: string): J => JSON.parse(readFileSync(join(parity, "golden", name), "utf8"));

describe("parity goldens", () => {
  const names = readdirSync(fixtures).filter((name) => name.endsWith(".json") && name !== "manifest.json").sort();

  it("has fixtures", () => expect(names.length).toBeGreaterThan(0));

  for (const name of names) {
    it(`adapts ${name} exactly like iOS`, () => {
      const poll = new MatchPoll(EngineJson.decode(readFileSync(join(fixtures, name), "utf8")));
      const log = new OnDeviceMessageLog();
      log.ingest(poll);
      const snapshot = OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, log.entries);
      const summary: Record<string, J> = Summary.snapshot(snapshot);
      summary.answers = Summary.answers(snapshot, poll.prompt);
      expect(summary).toEqual(golden(`fixture-${name}`));
    });
  }

  it("presents prompt-cases.json exactly like iOS", () => {
    const root = JSON.parse(readFileSync(join(parity, "prompt-cases.json"), "utf8")) as J;
    const viewer = str(get(root, "viewer"))!;
    const players = (get(root, "players") as J[]).map(decodePlayer);
    const cards = players.flatMap((p) => [...p.zones.hand, ...p.zones.battlefield, ...p.zones.graveyard, ...p.zones.exile, ...p.zones.command]);
    const results = (get(root, "cases") as J[]).map((item) => {
      const prompt = new EnginePrompt(get(item, "prompt")!);
      const result: Record<string, J> = { name: get(item, "name") ?? "" };
      try {
        const view = OnDevicePromptAdapter.presentation(prompt, viewer, cards, players);
        result.envelope = Summary.envelope(view.envelope);
        result.actions = view.legalActions.map(Summary.action);
        result.manaPayment = view.manaPayment ? { active: view.manaPayment.active, remainingText: view.manaPayment.remainingText ?? null } : null;
      } catch (error) {
        result.error = Summary.message(error);
      }
      result.answers = ((get(item, "commands") as J[] | undefined) ?? []).map((fields) =>
        Summary.answer(Summary.commandFrom(fields, "match", viewer, prompt.id, prompt.revision), prompt, viewer));
      return result;
    });
    expect({ cases: results }).toEqual(golden("prompt-cases.json"));
  });
});
