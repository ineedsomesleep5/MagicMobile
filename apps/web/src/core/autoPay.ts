/**
 * Port of iOS ArenaAutoPay (ArenaBoardModel.swift): Auto Pay for the Arena board taps your mana sources one at a time
 * until the cost is paid, the way the reference game's Auto Pay button does. XMage leaves land payment to the client, so
 * each step sends the same `make_mana` a click on the land sends, or spends floating mana with `play_mana`. Checked by
 * test/autoPay.test.ts against parity/auto-pay-cases.json, the cases iOS runs.
 */
import type { GameSnapshot, LegalAction } from "./models";

export type AutoPayStep =
  /** `color`: the colour to name when the source makes a mana of any colour. */
  | { kind: "tap"; actionID: string; color?: string }
  | { kind: "spend"; symbol: string }
  | { kind: "done" }
  | { kind: "blocked"; reason: string };

/** What a cost still needs, read from XMage's "Pay {2}{R}" text. */
export interface Need {
  generic: number;
  /** Coloured (and {C}) pips: exactly that symbol. */
  symbols: Record<string, number>;
  /** Hybrid pips: any one of the listed colours (`generic2` marks {2/W}'s generic half). */
  hybrids: string[][];
}
export const COLORS = ["W", "U", "B", "R", "G"];
export const needIsEmpty = (need: Need) => need.generic === 0 && Object.values(need.symbols).every((n) => n <= 0) && need.hybrids.length === 0;

export function need(text: string): Need {
  const result: Need = { generic: 0, symbols: {}, hybrids: [] };
  for (const match of text.matchAll(/\{([0-9WUBRGCSXP/]+)\}/gi)) {
    const token = match[1].toUpperCase();
    if (/^\d+$/.test(token)) result.generic += Number(token);
    else if (token === "S") result.generic += 1;
    else if (token === "X") continue;
    else if (token.includes("/")) {
      const parts = token.split("/").filter((p) => p.length > 0);
      const color = parts.find((p) => COLORS.includes(p));
      // Phyrexian ({R/P}) pays with its colour here; life payment stays a manual choice.
      if (parts.includes("P") && color) result.symbols[color] = (result.symbols[color] ?? 0) + 1;
      // {2/W}: two generic or one white; pay the white when a source has it, else two generic.
      else if (parts.length > 0 && /^\d+$/.test(parts[0])) result.hybrids.push([...parts.filter((p) => COLORS.includes(p)), `generic${Number(parts[0])}`]);
      else result.hybrids.push(parts.filter((p) => COLORS.includes(p) || p === "C"));
    } else if (COLORS.includes(token) || token === "C") result.symbols[token] = (result.symbols[token] ?? 0) + 1;
  }
  return result;
}

/** What one tap of a mana action produces: one symbol list per alternative, or any colour. */
export interface Production { options: string[][]; anyColor: boolean; sacrifices: boolean }
export const productionAmount = (p: Production) => (p.anyColor ? 1 : Math.max(0, ...p.options.map((o) => o.length)));
export const productionColorCount = (p: Production) => (p.anyColor ? 5 : new Set(p.options.flat().filter((s) => COLORS.includes(s))).size);
export const colorlessOnly = (p: Production) => !p.anyColor && p.options.length > 0 && p.options.every((o) => o.every((s) => s === "C"));

const symbolsIn = (text: string) => [...text.toUpperCase().matchAll(/\{([A-Z0-9]+)\}/g)].map((m) => m[1]);

/**
 * Undefined when the ability costs more than a tap and sacrificing the source itself (life, other mana, another
 * permanent): those stay manual.
 */
export function production(action: LegalAction): Production | undefined {
  const label = action.label;
  const add = label.search(/add/i);
  let sacrifices = false;
  if (add >= 0) {
    const costPart = label.slice(0, add);
    const colon = costPart.lastIndexOf(":");
    if (colon >= 0) {
      const cost = costPart.slice(0, colon).toUpperCase().replaceAll(" ", "");
      const name = (action.cardName ?? "").toUpperCase().replaceAll(" ", "");
      // A tap, a sacrifice of the source itself, or both; anything else is a cost the player chooses to pay.
      for (const part of cost.split(",").filter((p) => p.length > 0)) {
        if (part === "{T}") continue;
        if (part.startsWith("SACRIFICE") && (part.startsWith("SACRIFICETHIS") || part === "SACRIFICEIT" || (name.length > 0 && part === "SACRIFICE" + name))) {
          sacrifices = true;
          continue;
        }
        return undefined;
      }
    }
  }
  const produced = action.producedMana?.map((s) => s.toUpperCase()) ?? [];
  if (produced.length > 0) {
    // One symbol repeated is one ability making that much ({C}{C}); different symbols are alternatives.
    return { options: new Set(produced).size === 1 ? [produced] : produced.map((s) => [s]), anyColor: false, sacrifices };
  }
  if (add < 0) return undefined;
  const effect = label.slice(add + 3);
  if (/any colou?r/i.test(effect)) return { options: [], anyColor: true, sacrifices };
  // Stop at the first sentence: reminder text and riders follow it.
  const clause = effect.split(".")[0];
  // "Add {W}, {B}, or {G}" is three choices of one mana each, not {W}{B} or {G}.
  const alternatives = clause.replaceAll(", or ", "|").replaceAll(" or ", "|").replaceAll(",", "|").split("|");
  const options = alternatives.map((part) => symbolsIn(part).filter((s) => COLORS.includes(s) || s === "C")).filter((o) => o.length > 0);
  if (options.length === 0) return undefined;
  return { options, anyColor: false, sacrifices };
}

/** What kind of permanent a mana source is, when the board says: a creature tapped for mana can't attack or block. */
export type SourceKind = "land" | "creature" | "other";

/** One way to tap a source: the action, what it makes (`*` is any colour) and what using it costs the plan. */
export interface Yield { actionID: string; symbols: string[]; cost: number }
export interface Source { key: string; yields: Yield[] }
const sourceCost = (source: Source) => Math.min(...source.yields.map((y) => y.cost));

const COLOR_COST = [0, 10, 14, 16, 16, 16];

/**
 * The order a payment spends sources in, as a cost: single-colour lands, then duals, then tri-lands and any-colour
 * lands, then creatures, and a sacrifice (Treasure) only when nothing else will do.
 */
export function sources(actions: LegalAction[], kinds: Record<string, SourceKind> = {}): Source[] {
  const byKey = new Map<string, Source>();
  for (const action of actions) {
    if (action.type !== "make_mana") continue;
    const key = action.sourceInstanceId ?? action.cardInstanceId;
    const made = production(action);
    if (key === undefined || !made) continue;
    let cost = made.anyColor ? 18 : COLOR_COST[Math.min(productionColorCount(made), 5)];
    // Colourless-only sources pay generic before any coloured one, keeping colours open.
    if (colorlessOnly(made)) cost = 9;
    if (made.sacrifices) cost = 60;
    if (kinds[key] === "creature") cost += 10;
    const yields: Yield[] = made.anyColor ? [{ actionID: action.id, symbols: ["*"], cost }] : made.options.map((symbols) => ({ actionID: action.id, symbols, cost }));
    const existing = byKey.get(key);
    if (existing) existing.yields.push(...yields);
    else byKey.set(key, { key, yields });
  }
  // Several abilities on one permanent (a dual land's two colours) make it as flexible as their colours together.
  return [...byKey.values()].map((source) => {
    const taps = source.yields.filter((y) => y.cost < 60);
    const colorsMade = new Set(taps.flatMap((y) => y.symbols).filter((s) => COLORS.includes(s))).size;
    if (taps.length > 1 && !taps.some((y) => y.symbols.includes("*"))) {
      const combined = COLOR_COST[Math.min(colorsMade, 5)] + (kinds[source.key] === "creature" ? 10 : 0);
      source.yields = source.yields.map((y) => (y.cost < 60 ? { ...y, cost: Math.max(y.cost, combined) } : y));
    }
    return source;
  });
}

/** One planned tap: the permanent, the action and, for a mana of any colour, which colour to name. */
export interface PlannedTap { key: string; actionID: string; color?: string }

const lexLess = (a: [number, string], b: [number, string]) => a[0] < b[0] || (a[0] === b[0] && a[1] < b[1]);

/**
 * The cheapest way to pay the whole cost from these sources, or undefined when they can't. Coloured pips are matched
 * first (the most constrained first), hybrids take whichever half is cheaper, and generic takes what is left; taps for
 * coloured pips come first in the plan.
 */
export function plan(want: Need, from: Source[]): PlannedTap[] | undefined {
  interface Pip { accepts: string[]; generic: number }
  const pips: Pip[] = [];
  for (const symbol of Object.keys(want.symbols).sort()) {
    for (let i = 0; i < want.symbols[symbol]; i++) pips.push({ accepts: [symbol], generic: 0 });
  }
  for (const hybrid of want.hybrids) {
    const generic = hybrid.map((h) => (h.startsWith("generic") ? Number(h.slice(7)) : undefined)).find((n) => n !== undefined) ?? 0;
    pips.push({ accepts: hybrid.filter((h) => !h.startsWith("generic")), generic });
  }
  const unitFits = (unit: string, pip: Pip) => (unit === "*" ? pip.accepts.some((a) => COLORS.includes(a)) : pip.accepts.includes(unit));
  const accepts = (y: Yield, pip: Pip) => y.symbols.some((s) => unitFits(s, pip));
  const optionCount = (pip: Pip) => from.filter((s) => s.yields.some((y) => accepts(y, pip))).length;
  // Swift's sort isn't stable; the key (options, accepted symbols) decides every order the cases reach.
  pips.sort((a, b) => (lexLess([optionCount(a), a.accepts.join("")], [optionCount(b), b.accepts.join("")]) ? -1
    : lexLess([optionCount(b), b.accepts.join("")], [optionCount(a), a.accepts.join("")]) ? 1 : 0));

  interface Use { yield: number; left: string[] }
  let best: { cost: number; uses: Map<number, Use>; colors: Map<number, string>; order: number[] } | undefined;
  const uses = new Map<number, Use>();
  const named = new Map<number, string>();
  const order: number[] = [];
  let nodes = 0;
  const spentCost = () => { let total = 0; uses.forEach((use, index) => { total += from[index].yields[use.yield].cost; }); return total; };

  const finish = (extraGeneric: number) => {
    // Generic: leftover units first, then the cheapest fill of unused sources (small knapsack on units).
    const owed = want.generic + extraGeneric;
    let leftover = 0;
    uses.forEach((use) => { leftover += use.left.length; });
    let cost = spentCost();
    let fill: { index: number; yield: number }[] = [];
    if (owed > leftover) {
      const short = owed - leftover;
      const unused = from.map((_, i) => i).filter((i) => !uses.has(i));
      const cap = short + 2;
      let dp: ({ cost: number; picks: { index: number; yield: number }[] } | undefined)[] = Array(cap + 1).fill(undefined);
      dp[0] = { cost: 0, picks: [] };
      for (const index of unused) {
        const previous = dp;
        dp = [...dp];
        from[index].yields.forEach((y, yieldIndex) => {
          for (let reached = 0; reached <= cap; reached++) {
            const current = previous[reached];
            if (!current) continue;
            const next = Math.min(cap, reached + Math.max(1, y.symbols.length));
            const candidate = { cost: current.cost + y.cost, picks: [...current.picks, { index, yield: yieldIndex }] };
            if (dp[next] === undefined || candidate.cost < dp[next]!.cost) dp[next] = candidate;
          }
        });
      }
      let pick: [number, { cost: number; picks: { index: number; yield: number }[] }] | undefined;
      for (let reached = short; reached <= cap; reached++) {
        const value = dp[reached];
        if (!value) continue;
        if (!pick || value.cost + 3 * (reached - short) < pick[1].cost + 3 * (pick[0] - short)) pick = [reached, value];
      }
      if (!pick) return;
      cost += pick[1].cost + 3 * (pick[0] - short);
      fill = pick[1].picks;
    } else {
      cost += 3 * (leftover - owed);
    }
    if (!best || cost < best.cost) {
      const all = new Map(uses);
      for (const p of fill) all.set(p.index, { yield: p.yield, left: [] });
      best = { cost, uses: all, colors: new Map(named), order: [...order, ...fill.map((p) => p.index)] };
    }
  };

  const assign = (next: number, extraGeneric: number) => {
    nodes += 1;
    if (nodes > 40_000) return;
    if (best && spentCost() >= best.cost) return;
    if (next >= pips.length) { finish(extraGeneric); return; }
    const pip = pips[next];
    // A unit left on a source already tapped costs nothing more.
    for (const index of [...uses.keys()].sort((a, b) => a - b)) {
      const use = uses.get(index)!;
      const slot = use.left.findIndex((unit) => unitFits(unit, pip));
      if (slot < 0) continue;
      const unit = use.left.splice(slot, 1)[0];
      const before = named.get(index);
      if (unit === "*") named.set(index, pip.accepts.find((a) => COLORS.includes(a))!);
      assign(next + 1, extraGeneric);
      if (before === undefined) named.delete(index); else named.set(index, before);
      use.left.splice(slot, 0, unit);
    }
    // A new source: one of each identical kind is enough to try.
    const tried = new Set<string>();
    const byCost = from.map((_, i) => i).sort((a, b) => sourceCost(from[a]) - sourceCost(from[b]) || a - b);
    for (const index of byCost) {
      if (uses.has(index)) continue;
      from[index].yields.forEach((y, yieldIndex) => {
        if (!accepts(y, pip)) return;
        const signature = from[index].yields.map((v) => `${v.cost}:${v.symbols.join("")}`).join(",") + `|${yieldIndex}`;
        if (tried.has(signature)) return;
        tried.add(signature);
        const left = [...y.symbols];
        const slot = left.findIndex((unit) => unitFits(unit, pip));
        const unit = left.splice(slot, 1)[0];
        uses.set(index, { yield: yieldIndex, left });
        if (unit === "*") named.set(index, pip.accepts.find((a) => COLORS.includes(a))!);
        order.push(index);
        assign(next + 1, extraGeneric);
        order.pop();
        named.delete(index);
        uses.delete(index);
      });
    }
    // {2/W}: pay its generic half instead.
    if (pip.generic > 0) assign(next + 1, extraGeneric + pip.generic);
  };

  assign(0, 0);
  const found = best as typeof best;
  if (!found) return undefined;
  return found.order.map((index) => {
    const source = from[index];
    const y = source.yields[found.uses.get(index)?.yield ?? 0];
    const color = y.symbols.includes("*") ? (found.colors.get(index) ?? COLORS[0]) : undefined;
    return { key: source.key, actionID: y.actionID, color };
  });
}

/**
 * The next Auto Pay step for a cost (`remainingText`), given the floating mana the prompt can spend and the legal
 * actions: floating mana first, then the first tap of the cheapest plan that pays the whole cost.
 */
export function nextStep(remainingText: string, floating: Record<string, number>, actions: LegalAction[], kinds: Record<string, SourceKind> = {}): AutoPayStep {
  const want = need(remainingText);
  if (needIsEmpty(want)) return { kind: "done" };
  // Floating mana first: it empties at the end of the step anyway.
  for (const symbol of Object.keys(want.symbols).sort()) {
    if (want.symbols[symbol] > 0 && (floating[symbol] ?? 0) > 0) return { kind: "spend", symbol };
  }
  for (const hybrid of want.hybrids) {
    const symbol = hybrid.find((s) => (floating[s] ?? 0) > 0);
    if (symbol) return { kind: "spend", symbol };
  }
  if (want.generic > 0) {
    // Generic takes floating mana that no coloured pip still wants, the most plentiful first.
    const surplus = Object.entries(floating).map(([s, n]) => [s, n - (want.symbols[s] ?? 0)] as const).filter(([, n]) => n > 0)
      .sort((a, b) => b[1] - a[1] || (a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0));
    if (surplus.length > 0) return { kind: "spend", symbol: surplus[0][0] };
  }
  const found = sources(actions, kinds);
  const taps = plan(want, found);
  if (!taps || taps.length === 0) {
    // Say what is short: a colour no source makes, or just not enough mana.
    const owed = want.generic + Object.values(want.symbols).reduce((a, b) => a + b, 0) + want.hybrids.length;
    if (found.length < owed) return { kind: "blocked", reason: "Not enough untapped mana for this cost" };
    const missing = Object.keys(want.symbols).sort().find((symbol) =>
      !found.some((s) => s.yields.some((y) => y.symbols.includes(symbol) || (y.symbols.includes("*") && COLORS.includes(symbol)))));
    if (missing) return { kind: "blocked", reason: `No untapped source makes {${missing}}` };
    return { kind: "blocked", reason: "Your untapped mana can't pay this cost" };
  }
  return { kind: "tap", actionID: taps[0].actionID, color: taps[0].color };
}

/** Lands, creatures and other permanents on the battlefield, by instance id. */
export function sourceKinds(snapshot: GameSnapshot): Record<string, SourceKind> {
  const kinds: Record<string, SourceKind> = {};
  for (const card of snapshot.players.flatMap((p) => p.zones.battlefield)) {
    const creature = card.isCreaturePermanent ?? /creature/i.test(card.card.typeLine);
    kinds[card.instanceId] = creature ? "creature" : /land/i.test(card.card.typeLine) ? "land" : "other";
  }
  return kinds;
}

/** The next Auto Pay step for the cost being paid in this snapshot (ArenaAutoPay.next(in:)). */
export function nextStepIn(snapshot: GameSnapshot): AutoPayStep {
  const envelope = snapshot.promptEnvelopeV2;
  if (snapshot.manaPayment?.active !== true && envelope?.responseKind.toLowerCase() !== "mana") return { kind: "done" };
  const remaining = snapshot.manaPayment?.remainingText ?? envelope?.message ?? "";
  const floating: Record<string, number> = {};
  for (const choice of envelope?.manaChoices ?? []) {
    const key = choice.manaType ?? choice.id;
    floating[key] = (floating[key] ?? 0) + (choice.amount ?? 0);
  }
  return nextStep(remaining, floating, snapshot.legalActions ?? [], sourceKinds(snapshot));
}
