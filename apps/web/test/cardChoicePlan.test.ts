/** CardChoicePlan: the iOS CardChoicePlanTests cases on the web port (one answer per fresh matching prompt, then Done). */
import { describe, expect, it } from "vitest";
import { CardChoicePlan, CardChoicePlanRules } from "../src/core/cardChoicePlan";
import type { GameSnapshot } from "../src/core/models";

const player = "00000000-0000-0000-0000-000000000001";
const ids = Array.from({ length: 7 }, (_, i) => `10000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);

function snapshot(message: string, revision: number, candidates: string[], options: { chosen?: string[]; promptID?: string; turn?: number; done?: boolean;
  phase?: string; activePlayerID?: string; step?: string } = {}): GameSnapshot {
  const promptID = options.promptID ?? "prompt";
  return {
    id: "game", phase: options.phase ?? "MAIN", turn: options.turn ?? 1, players: [], log: [], viewerPlayerId: player,
    activePlayerId: options.activePlayerID, step: options.step,
    legalActions: options.done ? [{ id: `done-${revision}`, type: "answer_yes_no", playerId: player, label: "Done", promptId: promptID, messageId: revision, confirmed: false }] : [],
    promptEnvelopeV2: {
      id: promptID, method: "game_get_choice", messageId: revision, playerId: player, responseKind: "target", message,
      responseCommand: { type: "choose_target" }, targets: [], options: options.chosen ? { chosenTargets: options.chosen } : {},
      cards: candidates.map((id) => ({ instanceId: id, card: { name: `Card ${id.slice(-2)}`, typeLine: "Creature" }, selectable: true })),
    },
  } as unknown as GameSnapshot;
}
const plan = (first: GameSnapshot, selected: string[], top: string[] = []) => new CardChoicePlan(first, first.promptEnvelopeV2!, selected, top);

describe("card choice plan", () => {
  it("reads selection bounds and toggles a draft", () => {
    expect(CardChoicePlanRules.selectionBounds("Select targets (selected 0 of 3)")?.[0]).toBe(0);
    expect(CardChoicePlanRules.selectionBounds("Select targets (selected 2 of 6, min 3)")?.[0]).toBe(3);
    expect(CardChoicePlanRules.selectionBounds("Select up to one target")).toBeUndefined();
    expect(CardChoicePlanRules.selectionBounds("Select Goblin cards (selected 1)")).toEqual([0, Number.MAX_SAFE_INTEGER]);
    expect(CardChoicePlanRules.isUnbounded(CardChoicePlanRules.selectionBounds("Select cards (selected 0, min 2)")!)).toBe(true);
    expect(CardChoicePlanRules.isUnbounded(CardChoicePlanRules.selectionBounds("Select targets (selected 0 of 3)")!)).toBe(false);
    expect(CardChoicePlanRules.selectionBounds("Select targets (selected 2, min 1)")?.[0]).toBe(1);
    expect(CardChoicePlanRules.toggled([ids[0], ids[1]], ids[0])).toEqual([ids[1]]);
    expect(CardChoicePlanRules.toggled([ids[1]], ids[0])).toEqual([ids[1], ids[0]]);
    expect(CardChoicePlanRules.supportsDraft(snapshot("Select up to one target", 1, [ids[0]], { chosen: [] }).promptEnvelopeV2!)).toBe(false);
  });

  it("stops when the maximum, phase, player or step changes", () => {
    const first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, { chosen: [], activePlayerID: player, step: "PRECOMBAT_MAIN" });
    const bounds = plan(first, [ids[0], ids[1]]);
    expect(bounds.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(bounds.next(snapshot("Choose (selected 1 of 7, min 2)", 2, ids, { chosen: [ids[0]], activePlayerID: player, step: "PRECOMBAT_MAIN" }), false)).toBeUndefined();
    expect(bounds.stopped).toBe(true);
    const phase = plan(first, [ids[0], ids[1]]);
    expect(phase.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(phase.next(snapshot("Choose (selected 1 of 6, min 2)", 2, ids, { chosen: [ids[0]], phase: "COMBAT", activePlayerID: player, step: "BEGIN_COMBAT" }), false)).toBeUndefined();
    expect(phase.stopped).toBe(true);
    for (const [activePlayerID, step] of [[undefined, "PRECOMBAT_MAIN"], [player, undefined]] as const) {
      const p = plan(first, [ids[0], ids[1]]);
      expect(p.next(first, false)?.targetIds).toEqual([ids[0]]);
      expect(p.next(snapshot("Choose (selected 1 of 6, min 2)", 2, ids, { chosen: [ids[0]], activePlayerID, step }), false)).toBeUndefined();
      expect(p.stopped).toBe(true);
    }
  });

  it("answers six selections against fresh matching prompts, then Done", () => {
    const first = snapshot("Choose (selected 0 of 6, min 6)", 1, ids, { chosen: [] });
    const p = plan(first, ids.slice(0, 6));
    for (let count = 0; count < 6; count++) {
      const current = snapshot(`Choose (selected ${count} of 6, min 6)`, count + 1, ids, { chosen: ids.slice(0, count) });
      expect(p.next(current, false)?.targetIds).toEqual([ids[count]]);
      expect(p.next(current, false)).toBeUndefined();
      expect(p.next(current, true)).toBeUndefined();
    }
    const complete = snapshot("Choose (selected 6 of 6, min 6)", 7, ids, { chosen: ids.slice(0, 6), done: true });
    expect(p.next(complete, false)?.confirmed).toBe(false);
    expect(p.next(complete, false)).toBeUndefined();
  });

  it("discards fourteen in the chosen order without Done", () => {
    const hand = Array.from({ length: 16 }, (_, i) => `20000000-0000-0000-0000-${String(i + 1).padStart(12, "0")}`);
    const order = [...hand].reverse().slice(0, 14);
    const first = snapshot("Select a card to discard (selected 0 of 14, min 14)", 1, hand, { chosen: [] });
    const p = plan(first, order);
    for (let count = 0; count < 14; count++) {
      const current = snapshot(`Select a card to discard (selected ${count} of 14, min 14)`, count + 1, hand, { chosen: order.slice(0, count) });
      expect(p.expectsMorePrompts).toBe(true);
      expect(p.next(current, false)?.targetIds).toEqual([order[count]]);
      expect(p.next(current, false)).toBeUndefined();
      expect(p.stopped).toBe(false);
    }
    expect(p.expectsMorePrompts).toBe(false);
  });

  it("owes a Done below its maximum, and nothing after it", () => {
    const first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, { chosen: [] });
    const p = plan(first, [ids[0], ids[1]]);
    expect(p.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(p.next(snapshot("Choose (selected 1 of 6, min 2)", 2, ids, { chosen: [ids[0]] }), false)?.targetIds).toEqual([ids[1]]);
    expect(p.expectsMorePrompts).toBe(true);
    expect(p.next(snapshot("Choose (selected 2 of 6, min 2)", 3, ids, { chosen: [ids[0], ids[1]], done: true }), false)?.confirmed).toBe(false);
    expect(p.expectsMorePrompts).toBe(false);
  });

  it("needs the player when a pending answer clears with the same prompt; stops on a changed context", () => {
    const first = snapshot("Choose (selected 0 of 6, min 2)", 1, ids, { chosen: [] });
    const p = plan(first, [ids[0], ids[1]]);
    expect(p.submittedPromptIsUnchanged(first)).toBe(false);
    expect(p.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(p.submittedPromptIsUnchanged(first)).toBe(true);
    expect(p.submittedPromptIsUnchanged(snapshot("Choose (selected 1 of 6, min 2)", 2, ids, { chosen: [ids[0]] }))).toBe(false);
    const deselect = snapshot("Choose (selected 2 of 3)", 1, ids, { chosen: [ids[0], ids[1]] });
    const q = plan(deselect, [ids[1]]);
    expect(q.next(deselect, false)?.targetIds).toEqual([ids[0]]);
    expect(q.next(snapshot("Choose something else", 2, ids, { chosen: [ids[1]] }), false)).toBeUndefined();
    expect(q.stopped).toBe(true);
  });

  it("scries: the bottom picks, Done, the bottom order, then the top order reversed", () => {
    const message = "Cards (scry): choose cards to put on the bottom of your library";
    const scry = snapshot(message, 1, ids.slice(0, 4), { chosen: [] });
    const p = plan(scry, [ids[1], ids[0]], [ids[2], ids[3]]);
    expect(p.next(scry, false)?.targetIds).toEqual([ids[1]]);
    expect(p.next(snapshot(message, 2, ids.slice(0, 4), { chosen: [ids[1]] }), false)?.targetIds).toEqual([ids[0]]);
    expect(p.next(snapshot(message, 3, ids.slice(0, 4), { chosen: [ids[1], ids[0]], done: true }), false)?.confirmed).toBe(false);
    const bottom = "Select card order to put on bottom of your library (last one chosen will be bottommost)";
    expect(p.next(snapshot(bottom, 4, [ids[0], ids[1]]), false)?.targetIds).toEqual([ids[1]]);
    expect(p.next(snapshot(bottom, 5, [ids[0]]), false)?.targetIds).toEqual([ids[0]]);
    const top = "Select card order to put on top of your library (last one chosen will be topmost)";
    expect(p.next(snapshot(top, 6, [ids[2], ids[3]]), false)?.targetIds).toEqual([ids[3]]);
    expect(p.next(snapshot(top, 7, [ids[2]]), false)?.targetIds).toEqual([ids[2]]);
  });

  it("scries one to the bottom (no bottom order) and none (straight to the top order)", () => {
    const message = "Cards (scry): choose cards to put on the bottom of your library";
    const topMessage = "Select card order to put on top of your library (last one chosen will be topmost)";
    const first = snapshot(message, 1, ids.slice(0, 4), { chosen: [] });
    const one = plan(first, [ids[0]], [ids[1], ids[2], ids[3]]);
    expect(one.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(one.next(snapshot(message, 2, ids.slice(0, 4), { chosen: [ids[0]], done: true }), false)?.confirmed).toBe(false);
    expect(one.next(snapshot(topMessage, 3, [ids[1], ids[2], ids[3]]), false)?.targetIds).toEqual([ids[3]]);
    expect(one.next(snapshot(topMessage, 4, [ids[1], ids[2]]), false)?.targetIds).toEqual([ids[2]]);
    const zero = plan(first, [], ids.slice(0, 4));
    expect(zero.next(snapshot(message, 1, ids.slice(0, 4), { chosen: [], done: true }), false)?.confirmed).toBe(false);
    expect(zero.next(snapshot(topMessage, 2, ids.slice(0, 4)), false)?.targetIds).toEqual([ids[3]]);
  });

  it("orders the top of a library and stops on another effect's order", () => {
    const message = "Select card order to put on top of your library (last one chosen will be topmost)";
    const first = snapshot(message, 1, ids.slice(0, 4));
    const p = plan(first, ids.slice(0, 4));
    for (let count = 0; count < 4; count++) expect(p.next(snapshot(message, count + 1, ids.slice(0, 4 - count)), false)?.targetIds).toEqual([ids[3 - count]]);
    expect(p.next(snapshot(`${message} for another effect`, 5, [ids[0]]), false)).toBeUndefined();
  });

  it("never retries a stale prompt and stops on a new turn", () => {
    const first = snapshot("Choose", 1, ids, { chosen: [] });
    const p = plan(first, [ids[0]]);
    expect(p.next(first, false)?.targetIds).toEqual([ids[0]]);
    expect(p.next(first, false)).toBeUndefined();
    expect(p.next(snapshot("Choose", 2, ids, { chosen: [ids[0]], turn: 2 }), false)).toBeUndefined();
    expect(p.stopped).toBe(true);
  });
});
