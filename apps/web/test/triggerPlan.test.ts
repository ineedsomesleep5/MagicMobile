/** The trigger order plan (iOS arenaOrderTriggers / arenaTriggerStep): one order chosen, every ordering prompt answered. */
import { describe, expect, it } from "vitest";
import type { GameSnapshot, PromptEnvelopeV2 } from "../src/core/models";
import { TriggerPlan } from "../src/ui/arena/triggerPlan";

const ability = (id: string) => ({ id, label: id });
const ordering = (id: string, messageId: number, ids: string[]): PromptEnvelopeV2 => ({
  id, method: "GAME_PICK_ABILITY", messageId, playerId: "me", responseKind: "ability", message: "Pick triggered ability (goes to the stack first)",
  abilities: ids.map(ability), responseCommand: { type: "choose_ability", promptId: id },
});
const snap = (prompt: PromptEnvelopeV2): GameSnapshot => ({ id: "g", phase: "x", turn: 3, players: [], log: [], viewerPlayerId: "me", promptEnvelopeV2: prompt });

describe("trigger plan", () => {
  it("sends the last-resolving trigger first, then answers each later ordering prompt by itself", () => {
    const plan = new TriggerPlan();
    const first = ordering("p1", 1, ["a", "b", "c"]);
    // The player numbers a (resolves first), b, c: c goes on the stack first.
    expect(plan.start([ability("a"), ability("b"), ability("c")], first, true)).toMatchObject({ abilityId: "c", remember: true, promptId: "p1" });
    expect(plan.answers(snap(first))).toBe(false); // already answered: a refused pick goes back to the browser
    expect(plan.step(snap(first), false)).toBeUndefined();
    const second = ordering("p2", 2, ["a", "b"]);
    expect(plan.answers(snap(second))).toBe(true);
    expect(plan.step(snap(second), true)).toBeUndefined(); // waits for the pending answer
    expect(plan.step(snap(second), false)).toMatchObject({ abilityId: "b", remember: false });
    expect(plan.step(snap(second), false)).toBeUndefined(); // never answers one prompt twice
  });

  it("survives a target question and ends at the player's next priority", () => {
    const plan = new TriggerPlan();
    plan.start([ability("a"), ability("b"), ability("c")], ordering("p1", 1, ["a", "b", "c"]), false);
    const target: PromptEnvelopeV2 = { id: "t", method: "GAME_TARGET", messageId: 2, playerId: "me", responseKind: "target", message: "Select a target" };
    expect(plan.step(snap(target), false)).toBeUndefined();
    expect(plan.active).toBe(true);
    const priority: PromptEnvelopeV2 = { id: "pr", method: "GAME_SELECT", messageId: 3, playerId: "me", responseKind: "priority", message: "Play spells" };
    plan.step(snap(priority), false);
    expect(plan.active).toBe(false);
  });
});

describe("trigger plan shared cases", () => {
  it("runs parity/trigger-plan-cases.json as iOS does (ArenaTriggerPlan)", async () => {
    const { readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const root: any = JSON.parse(readFileSync(join(__dirname, "..", "..", "android", "core", "src", "test", "resources", "parity", "trigger-plan-cases.json"), "utf8"));
    for (const item of root.cases) {
      const plan = new TriggerPlan();
      const prompt = { id: "p1", messageId: 1, method: "GAME_PICK_ABILITY", playerId: root.viewer, responseKind: "ability", message: "" } as never;
      const start = plan.start(item.resolveOrder.map((id: string) => ({ id, label: id })), prompt, false);
      expect(plan.plan, item.name).toEqual(item.plan);
      expect(start?.abilityId, item.name).toBe(item.plan[0]);
      plan.sent = item.sent;
      for (const [index, step] of item.steps.entries()) {
        const at = `${item.name} · step ${index + 1}`;
        const p = step.prompt;
        const snapshot = { id: "g", phase: "main1", turn: 3, players: [], log: [], viewerPlayerId: root.viewer,
          promptEnvelopeV2: { id: p.id, messageId: p.messageId, playerId: p.playerId, method: p.method, responseKind: p.responseKind, message: "",
            abilities: (p.abilities ?? []).map((id: string) => ({ id, label: id })), responseCommand: { type: p.command } } } as never;
        expect(plan.answers(snapshot), `${at} · answers`).toBe(step.answers);
        expect(plan.step(snapshot, step.pending)?.abilityId ?? null, `${at} · pick`).toBe(step.pick);
        expect(plan.plan, `${at} · plan`).toEqual(step.plan);
        expect(plan.sent ?? null, `${at} · sent`).toBe(step.sent);
      }
    }
  });
});
