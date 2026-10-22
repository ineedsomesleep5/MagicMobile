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
