/**
 * A card choice drafted on the board and delivered as XMage asks for it (iOS CardChoicePlan.swift): one card per
 * native PICK_TARGET answer, then Done; scry's bottom and top orders; an order of the top or bottom of a library. Each
 * answer goes only against a fresh prompt that still matches the draft; anything unexpected stops the plan and hands the
 * prompt back to the player. Checked by test/cardChoicePlan.test.ts (the iOS CardChoicePlanTests cases).
 */
import type { GameCommand, GameSnapshot, PromptEnvelopeV2 } from "./models";

export type CardChoiceKind = "selection" | "scry" | "topOrder" | "bottomOrder";

const selectable = (prompt: PromptEnvelopeV2) => (prompt.cards ?? []).filter((c) => c.selectable !== false).map((c) => c.instanceId);
const chosenTargets = (prompt: PromptEnvelopeV2): string[] | undefined => {
  const value = prompt.options?.chosenTargets;
  return Array.isArray(value) && value.every((v) => typeof v === "string") ? (value as string[]) : undefined;
};
const sameSet = (a: Iterable<string>, b: Iterable<string>) => { const x = new Set(a), y = new Set(b); return x.size === y.size && [...x].every((v) => y.has(v)); };
const subset = (a: Iterable<string>, b: ReadonlySet<string>) => [...a].every((v) => b.has(v));

export const CardChoicePlanRules = {
  kind(prompt: PromptEnvelopeV2): CardChoiceKind {
    const text = prompt.message.toLowerCase();
    if (text.includes("card order to put") && text.includes("top of your library") && text.includes("last one chosen will be topmost")) return "topOrder";
    if (text.includes("card order to put") && text.includes("bottom of your library") && text.includes("last one chosen will be bottommost")) return "bottomOrder";
    if (text.includes("(scry)") && text.includes("bottom of your library")) return "scry";
    return "selection";
  },
  context: (prompt: PromptEnvelopeV2) => prompt.message.replace(/\s*\(selected \d+(?: of \d+)?(?:, min \d+)?\)/g, ""),
  /** The selection range XMage states: "(selected 1 of 3, min 1)"; no "of <max>" means any number. */
  selectionBounds(message: string): [number, number] | undefined {
    const match = /\(selected\s+(\d+)(?:\s+of\s+(\d+))?(?:,\s*min\s+(\d+))?\)/i.exec(message);
    if (!match) return undefined;
    return [match[3] !== undefined ? Number(match[3]) : 0, match[2] !== undefined ? Number(match[2]) : Number.MAX_SAFE_INTEGER];
  },
  isUnbounded: (bounds: [number, number]) => bounds[1] === Number.MAX_SAFE_INTEGER,
  supportsDraft(prompt: PromptEnvelopeV2): boolean {
    const kind = CardChoicePlanRules.kind(prompt);
    return prompt.responseCommand?.type === "choose_target" &&
      ((kind !== "selection" && kind !== "scry") || (chosenTargets(prompt) !== undefined && (kind === "scry" || CardChoicePlanRules.selectionBounds(prompt.message) !== undefined))) &&
      selectable(prompt).length > 0 && (prompt.targets ?? []).length === 0;
  },
  toggled: (ids: string[], id: string) => (ids.includes(id) ? ids.filter((x) => x !== id) : [...ids, id]),
};

export class CardChoicePlan {
  readonly gameID: string; readonly playerID: string; readonly turn: number; readonly activePlayerID?: string;
  readonly phase: string; readonly step?: string; readonly kind: CardChoiceKind; readonly universe: ReadonlySet<string>;
  /** Bottom first for scry. */
  readonly selected: string[];
  /** The desired top, top first. */
  readonly top: string[];
  readonly context: string; readonly minimumSelection?: number; readonly maximumSelection?: number;
  stopped = false;
  lastPrompt?: string;
  private expectedChosen?: Set<string>;
  private remainingOrder?: string[];
  private orderKind?: CardChoiceKind;
  private orderContext?: string;
  private doneSent = false;

  constructor(snapshot: GameSnapshot, prompt: PromptEnvelopeV2, selected: string[], top: string[] = []) {
    this.gameID = snapshot.id; this.playerID = prompt.playerId; this.turn = snapshot.turn;
    this.activePlayerID = snapshot.activePlayerId; this.phase = snapshot.phase; this.step = snapshot.step;
    this.kind = CardChoicePlanRules.kind(prompt);
    this.universe = new Set(selectable(prompt));
    this.selected = selected; this.top = top;
    this.context = CardChoicePlanRules.context(prompt);
    const bounds = CardChoicePlanRules.selectionBounds(prompt.message);
    this.minimumSelection = bounds?.[0]; this.maximumSelection = bounds?.[1];
  }

  cancel() { this.stopped = true; }

  /** A cleared pending answer with the same prompt has not authorized another reply. */
  submittedPromptIsUnchanged(snapshot: GameSnapshot): boolean {
    const prompt = snapshot.promptEnvelopeV2;
    return this.lastPrompt !== undefined && prompt !== undefined && this.lastPrompt === `${prompt.id}:${prompt.messageId}`;
  }

  private stop(): undefined { this.stopped = true; return undefined; }

  /** The next answer, or undefined to wait, finish, or hand an unexpected prompt back to the player. */
  next(snapshot: GameSnapshot, pending: boolean): GameCommand | undefined {
    if (this.stopped) return undefined;
    if (snapshot.id !== this.gameID || snapshot.turn !== this.turn || snapshot.phase !== this.phase ||
      (this.activePlayerID !== undefined && snapshot.activePlayerId !== this.activePlayerID) ||
      (this.step !== undefined && snapshot.step !== this.step) || snapshot.gameStatus === "completed") return this.stop();
    const prompt = snapshot.promptEnvelopeV2;
    if (pending || !prompt) return undefined;
    const key = `${prompt.id}:${prompt.messageId}`;
    if (key === this.lastPrompt) return undefined;
    if (prompt.playerId !== this.playerID || prompt.responseCommand?.type !== "choose_target" || snapshot.viewerPlayerId !== this.playerID ||
      (prompt.targets ?? []).length > 0) return this.stop();
    const currentKind = CardChoicePlanRules.kind(prompt);
    const candidates = new Set(selectable(prompt));
    const { selected, top, universe } = this;
    if (candidates.size === 0 || !subset(candidates, universe) || new Set(selected).size !== selected.length || new Set(top).size !== top.length ||
      !subset(selected, universe) || !subset(top, universe)) return this.stop();
    if (this.kind === "scry") {
      if (selected.some((id) => top.includes(id)) || !sameSet([...selected, ...top], universe)) return this.stop();
    }

    if (currentKind === "topOrder" || currentKind === "bottomOrder") {
      let desired: string[];
      if (this.kind === "scry") {
        if (!(this.doneSent || (this.expectedChosen !== undefined && sameSet(this.expectedChosen, selected)))) return this.stop();
        desired = currentKind === "topOrder" ? top : selected;
        const order = this.orderKind;
        if (!((currentKind === "bottomOrder" && (order === undefined || order === "bottomOrder")) ||
          (currentKind === "topOrder" && (order === "topOrder" || order === "bottomOrder" || (order === undefined && selected.length <= 1))))) return this.stop();
      } else if (this.kind === currentKind) desired = selected;
      else return this.stop();
      if (this.orderKind !== currentKind) {
        if ((this.remainingOrder?.length ?? 0) > 1 || !sameSet(candidates, desired)) return this.stop();
        this.orderKind = currentKind;
        this.orderContext = CardChoicePlanRules.context(prompt);
        this.remainingOrder = currentKind === "topOrder" ? [...desired].reverse() : [...desired];
      }
      if (this.orderContext !== CardChoicePlanRules.context(prompt)) return this.stop();
      const remaining = this.remainingOrder;
      const id = remaining?.[0];
      if (!remaining || id === undefined || !sameSet(candidates, remaining)) return this.stop();
      this.remainingOrder = remaining.slice(1);
      this.lastPrompt = key;
      return this.command(prompt, id);
    }

    const bounds = CardChoicePlanRules.selectionBounds(prompt.message);
    const boundsMatch = bounds?.[0] === this.minimumSelection && bounds?.[1] === this.maximumSelection;
    const chosenArray = chosenTargets(prompt);
    if (!(this.kind === "selection" || this.kind === "scry") || this.orderKind !== undefined || this.doneSent || currentKind !== this.kind ||
      CardChoicePlanRules.context(prompt) !== this.context || !(this.kind === "scry" ? (this.maximumSelection === undefined || boundsMatch) : boundsMatch) ||
      !chosenArray || new Set(chosenArray).size !== chosenArray.length) return this.stop();
    const chosen = new Set(chosenArray);
    if (!subset(chosen, universe) || (this.expectedChosen !== undefined && !sameSet(this.expectedChosen, chosen))) return this.stop();
    const removal = [...chosen].filter((id) => !selected.includes(id)).sort()[0];
    const addition = selected.find((id) => !chosen.has(id));
    const id = removal ?? addition;
    if (id !== undefined) {
      if (!candidates.has(id)) return this.stop();
      const expected = new Set(chosen);
      if (expected.has(id)) expected.delete(id); else expected.add(id);
      this.expectedChosen = expected;
      this.lastPrompt = key;
      return this.command(prompt, id);
    }
    // False is Done only when the engine labels it Done.
    if (this.kind === "selection") {
      if (this.minimumSelection === undefined || this.maximumSelection === undefined ||
        selected.length < this.minimumSelection || selected.length > this.maximumSelection) return this.stop();
    }
    const done = (snapshot.legalActions ?? []).some((a) => a.promptId === prompt.id && a.messageId === prompt.messageId && a.type === "answer_yes_no" &&
      a.confirmed === false && a.label.toLowerCase() === "done");
    if (!done) return this.stop();
    this.doneSent = true;
    this.lastPrompt = key;
    return { type: "answer_yes_no", gameId: this.gameID, playerId: this.playerID, promptId: prompt.id, messageId: prompt.messageId, confirmed: false } as GameCommand;
  }

  private command(prompt: PromptEnvelopeV2, id: string): GameCommand {
    return { type: "choose_target", gameId: this.gameID, playerId: prompt.playerId, promptId: prompt.id, messageId: prompt.messageId, targetIds: [id] } as GameCommand;
  }
}
