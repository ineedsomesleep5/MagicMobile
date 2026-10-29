/** auto-pay-cases.json: Auto Pay's reading of costs and mana abilities, its plan and its next step, as iOS runs them. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { type AutoPayStep, colorlessOnly, need, nextStep, nextStepIn, plan, production, productionAmount, sources, type SourceKind } from "../src/core/autoPay";
import { MatchPoll } from "../src/core/engineClient";
import type { LegalAction } from "../src/core/models";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/auto-pay-cases.json"), "utf8"));
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const actions = new Map<string, LegalAction>(cases.actions.map((a: any) => [a.id, {
  id: a.id, type: "make_mana", playerId: "p1", label: a.label, sourceInstanceId: a.source, cardInstanceId: a.source, cardName: a.card, producedMana: a.produced,
}]));
const named = (ids: string[]) => ids.map((id) => actions.get(id)!);
const summary = (step: AutoPayStep) => {
  switch (step.kind) {
    case "tap": return `tap:${step.actionID}${step.color ? `:${step.color}` : ""}`;
    case "spend": return `spend:${step.symbol}`;
    case "done": return "done";
    case "blocked": return `blocked:${step.reason}`;
  }
};

describe("auto-pay-cases.json", () => {
  it("reads costs like the apps", () => {
    for (const item of cases.need) {
      const value = need(item.text);
      expect({ generic: value.generic, symbols: value.symbols, hybrids: value.hybrids }, item.text)
        .toEqual({ generic: item.generic, symbols: item.symbols, hybrids: item.hybrids });
    }
  });
  it("reads mana abilities like the apps", () => {
    for (const item of cases.production) {
      const value = production(actions.get(item.action)!);
      if (item.none) { expect(value, item.action).toBeUndefined(); continue; }
      expect(value, item.action).toBeDefined();
      expect({ options: value!.options, anyColor: value!.anyColor, sacrifices: value!.sacrifices, amount: productionAmount(value!), colorlessOnly: colorlessOnly(value!) }, item.action)
        .toEqual({ options: item.options, anyColor: item.anyColor, sacrifices: item.sacrifices, amount: item.amount, colorlessOnly: item.colorlessOnly });
    }
  });
  it("plans and steps like the apps", () => {
    for (const item of cases.next) {
      const kinds = (item.kinds ?? {}) as Record<string, SourceKind>;
      if ("step" in item) expect(summary(nextStep(item.text, item.floating ?? {}, named(item.actions), kinds)), item.name).toBe(item.step);
      const planned = plan(need(item.text), sources(named(item.actions), kinds));
      if ("plan" in item) {
        expect(planned?.map((t) => t.key).sort() ?? null, item.name).toEqual(item.plan === null ? null : [...item.plan].sort());
      }
      if (item.colors) for (const [key, color] of Object.entries(item.colors)) expect(planned?.find((t) => t.key === key)?.color, item.name).toBe(color);
      if (item.planExcludes) for (const key of item.planExcludes) expect(planned?.some((t) => t.key === key), item.name).toBe(false);
      if (item.planActions) expect(planned?.map((t) => t.actionID).sort(), item.name).toEqual([...item.planActions].sort());
    }
  });
  it("taps a land XMage offers for the real cost (fixture 2p-mana)", () => {
    const poll = new MatchPoll(JSON.parse(readFileSync(join(root, "apps/ios/MagicMobileTests/Fixtures/OnDevice/2p-mana.json"), "utf8")));
    const snapshot = OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, []);
    expect(snapshot.manaPayment?.active).toBe(true);
    expect(need(snapshot.manaPayment!.remainingText!).symbols).toEqual({ W: 1 });
    const step = nextStepIn(snapshot);
    expect(step.kind).toBe("tap");
    const action = snapshot.legalActions!.find((a) => step.kind === "tap" && a.id === step.actionID)!;
    expect(action.type).toBe("make_mana");
    const land = snapshot.players.flatMap((p) => p.zones.battlefield).find((c) => c.instanceId === action.sourceInstanceId);
    expect(land?.card.typeLine).toContain("Plains");
  });
});
