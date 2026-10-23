/**
 * Auto Pay's run on the board (iOS NativeGameView+ArenaActions `arenaAutoPayStep`, `ArenaAutoPayRun`): one tap per
 * settled snapshot, each the same make_mana a click on the source sends (or a play_mana for floating mana), the colour
 * question a mana of any colour raises answered with the colour the plan wanted, and a run that goes in circles stopped.
 * Checked by test/autoPayRun.test.ts.
 */
import { nextStepIn } from "../../core/autoPay";
import type { GameCommand, GameSnapshot, LegalAction, PromptEnvelopeV2 } from "../../core/models";

/** CompactPromptPopup.isManaPaymentPrompt. */
export function isManaPaymentPrompt(prompt: PromptEnvelopeV2): boolean {
  const type = prompt.responseCommand?.type?.toLowerCase() ?? "";
  const kind = prompt.responseKind.toLowerCase();
  return type === "play_mana" || type === "choose_mana" || type === "pay_cost" || type === "play_x_mana" ||
    kind === "mana" || kind === "pay_cost" || kind === "cost" || kind === "x_mana" || prompt.method === "GAME_PLAY_MANA" || prompt.method === "GAME_PLAY_XMANA";
}

/** The payment being made, when this snapshot asks for one (InlinePaymentPromptState.paymentPrompt). */
export const paymentPrompt = (snapshot: GameSnapshot) =>
  snapshot.promptEnvelopeV2 && isManaPaymentPrompt(snapshot.promptEnvelopeV2) ? snapshot.promptEnvelopeV2 : undefined;

/** Undo and cancel during a payment (CompactPromptPopup.manaUndoActions). */
export function manaUndoActions(snapshot: GameSnapshot): LegalAction[] {
  const prompt = snapshot.promptEnvelopeV2;
  return (snapshot.legalActions ?? []).filter((action) => ["undo_mana", "cancel_payment", "cancel_mana_payment"].includes(action.type) ||
    (snapshot.source === "xmage-ondevice" && prompt !== undefined && isManaPaymentPrompt(prompt) && action.type === "resolve_choice" &&
      action.choiceIds?.length === 1 && action.choiceIds[0] === "special" && action.promptId === (prompt.responseCommand?.promptId ?? prompt.id)));
}

const COLOR_NAMES: Record<string, string> = { W: "white", U: "blue", B: "black", R: "red", G: "green" };

/** The choice naming `wanted` in XMage's mana-colour question, or its first colour; undefined when it isn't one. */
export function colorChoice(prompt: PromptEnvelopeV2, wanted: string | undefined): string | undefined {
  const choices = prompt.choices ?? [];
  if (prompt.responseKind.toLowerCase() !== "choice" || choices.length === 0 ||
    !choices.every((c) => Object.values(COLOR_NAMES).some((name) => c.label.toLowerCase().includes(name)))) return undefined;
  const name = wanted ? COLOR_NAMES[wanted] : undefined;
  return (name ? choices.find((c) => c.label.toLowerCase().includes(name)) : undefined)?.id ?? choices[0].id;
}

/** Spending floating mana of one colour into this payment (GameplayAffordances.floatingManaCommand). */
export function floatingManaCommand(symbol: string, snapshot: GameSnapshot): GameCommand | undefined {
  const me = snapshot.players.find((p) => p.playerId === snapshot.viewerPlayerId);
  const prompt = snapshot.promptEnvelopeV2;
  if (!me?.manaPool || !prompt || prompt.playerId !== me.playerId || !isManaPaymentPrompt(prompt)) return undefined;
  const choice = prompt.manaChoices?.find((c) => (c.manaType ?? c.id) === symbol);
  if (!choice || (snapshot.source === "xmage-ondevice" && (choice.amount ?? 0) <= 0)) return undefined;
  if ((me.manaPool[symbol as keyof typeof me.manaPool] ?? 0) <= 0) return undefined;
  return { type: "play_mana", gameId: snapshot.id, playerId: prompt.playerId, promptId: prompt.responseCommand?.promptId ?? prompt.id,
    messageId: prompt.messageId, manaType: symbol, expectedBridgeRevision: snapshot.bridgeRevision };
}

export type AutoPayMove =
  | { kind: "action"; action: LegalAction }
  | { kind: "command"; command: GameCommand; label: string; actionID: string }
  | { kind: "stop"; notice?: string }
  | { kind: "wait" };

export class AutoPayRun {
  steps = 0;
  /** How often each payment state has been acted on: a third time means Auto Pay is going in circles. */
  signatures = new Map<string, number>();
  /** The colour to name when XMage asks what a mana of any colour should be. */
  color?: string;
  /** Auto Pay's last tap may be asking a colour: only then does it answer one, never a question a spell asks later. */
  awaitingColor = false;
  /** The colour question ("id:messageId") Auto Pay answered, kept out of the choice browser until its answer lands. */
  answeredColor?: string;
  /** Snapshots in a row without the payment: XMage can send one between answers, so only a few end the run. */
  quiet = 0;

  /** The next move for a settled snapshot; `pending` is an answer still on its way. */
  step(snapshot: GameSnapshot, pending: boolean): AutoPayMove {
    if (pending) return { kind: "wait" };
    const viewer = snapshot.viewerPlayerId;
    const asked = snapshot.promptEnvelopeV2;
    if (this.awaitingColor && asked && asked.playerId === viewer) {
      const choice = colorChoice(asked, this.color);
      if (choice) {
        this.color = undefined;
        this.awaitingColor = false;
        this.answeredColor = `${asked.id}:${asked.messageId}`;
        this.quiet = 0;
        return { kind: "command", label: "Choose mana colour", actionID: `autopay-colour-${asked.id}-${asked.messageId}`, command: {
          type: "resolve_choice", gameId: snapshot.id, playerId: asked.playerId, promptId: asked.responseCommand?.promptId ?? asked.id,
          messageId: asked.messageId, choiceIds: [choice], expectedBridgeRevision: snapshot.bridgeRevision,
        } };
      }
    }
    const prompt = paymentPrompt(snapshot);
    if (!prompt) {
      // Another question means the payment is over; a quiet snapshot or two can come between XMage's answers.
      this.quiet += 1;
      // A tap's colour question comes at once; one that comes later is the spell's own.
      if (this.quiet > 1) this.awaitingColor = false;
      return asked?.playerId === viewer || this.quiet > 3 ? { kind: "stop" } : { kind: "wait" };
    }
    // Back at the payment: the last tap asked nothing.
    this.awaitingColor = false;
    this.color = undefined;
    this.quiet = 0;
    const remaining = snapshot.manaPayment?.remainingText ?? prompt.message;
    const signature = remaining + "|" + (snapshot.legalActions ?? []).map((a) => a.id).sort().join(",");
    if ((this.signatures.get(signature) ?? 0) >= 2 || this.steps >= 30) return { kind: "stop", notice: "Auto Pay stopped: tap the rest yourself" };
    this.signatures.set(signature, (this.signatures.get(signature) ?? 0) + 1);
    this.steps += 1;
    const next = nextStepIn(snapshot);
    switch (next.kind) {
      case "tap": {
        const action = snapshot.legalActions?.find((a) => a.id === next.actionID);
        if (!action) return { kind: "stop" };
        this.color = next.color;
        this.awaitingColor = true;
        return { kind: "action", action };
      }
      case "spend": {
        const command = floatingManaCommand(next.symbol, snapshot);
        return command ? { kind: "command", command, label: `Spend floating {${next.symbol}}`, actionID: `autopay-${prompt.id}-${next.symbol}-${this.steps}` } : { kind: "stop" };
      }
      case "done": return { kind: "stop" };
      case "blocked": return { kind: "stop", notice: next.reason };
    }
  }
}

/** Whether Auto Pay can start on this payment: the button is lit (enabled) only when its plan pays the whole cost. */
export function autoPayReady(snapshot: GameSnapshot): boolean {
  if (!paymentPrompt(snapshot)) return false;
  const next = nextStepIn(snapshot);
  return next.kind === "tap" || next.kind === "spend";
}
