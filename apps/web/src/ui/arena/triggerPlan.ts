/**
 * Ordering triggers all at once (iOS arenaOrderTriggers, arenaTriggerPlanAnswers, arenaTriggerStep): the player numbers
 * the triggers in the order they resolve; XMage asks which goes on the stack first (it resolves last), so the plan is
 * the picks in reverse, and each ordering prompt gets the first planned trigger it still offers. The plan survives a
 * target question for one of them and ends at the player's next priority. Checked by test/triggerPlan.test.ts.
 */
import type { GameSnapshot, PromptEnvelopeV2, XmagePromptAbility } from "../../core/models";

/** XMage's "which triggered ability goes on the stack first" question. */
export const isTriggerOrder = (prompt: PromptEnvelopeV2) => prompt.method === "GAME_PICK_ABILITY";

export interface TriggerPick { abilityId: string; promptId: string; messageId: number; responsePromptId: string; remember: boolean }

export class TriggerPlan {
  /** Ability ids in the order they go on the stack. */
  plan: string[] = [];
  /** The ordering prompt ("id:messageId") last answered from the plan. */
  sent?: string;

  get active() { return this.plan.length > 0; }

  /** Starts a plan from the order the triggers resolve (first resolves first); returns the first pick to send now. */
  start(resolveOrder: XmagePromptAbility[], prompt: PromptEnvelopeV2, remember: boolean): TriggerPick | undefined {
    const picks = [...resolveOrder].reverse().map((a) => a.id);
    if (picks.length === 0) return undefined;
    this.plan = picks;
    this.sent = `${prompt.id}:${prompt.messageId}`;
    return { abilityId: picks[0], promptId: prompt.id, messageId: prompt.messageId, responsePromptId: prompt.responseCommand?.promptId ?? prompt.id, remember };
  }

  /** The plan answers this ordering prompt by itself (so the browser stays shut): it offers a planned trigger, unanswered. */
  answers(snapshot: GameSnapshot): boolean {
    const prompt = snapshot.promptEnvelopeV2;
    if (!this.active || !prompt || prompt.playerId !== snapshot.viewerPlayerId || !isTriggerOrder(prompt) || !prompt.abilities) return false;
    return `${prompt.id}:${prompt.messageId}` !== this.sent && prompt.abilities.some((a) => this.plan.includes(a.id));
  }

  /** The next pick for a settled snapshot, if the plan answers it; ends the plan at the player's next priority. */
  step(snapshot: GameSnapshot, pending: boolean): TriggerPick | undefined {
    const prompt = snapshot.promptEnvelopeV2;
    if (!this.active || pending || !prompt || prompt.playerId !== snapshot.viewerPlayerId) return undefined;
    const abilities = prompt.abilities ?? [];
    if (!isTriggerOrder(prompt) || abilities.length === 0) {
      if (prompt.responseKind === "priority" || prompt.responseCommand?.type === "pass_priority") { this.plan = []; this.sent = undefined; }
      return undefined;
    }
    // Triggers XMage no longer offers are on the stack.
    this.plan = this.plan.filter((id) => abilities.some((a) => a.id === id));
    const next = this.plan[0];
    if (next === undefined) { this.sent = undefined; return undefined; }
    const key = `${prompt.id}:${prompt.messageId}`;
    if (key === this.sent) return undefined;
    this.sent = key;
    return { abilityId: next, promptId: prompt.id, messageId: prompt.messageId, responsePromptId: prompt.responseCommand?.promptId ?? prompt.id, remember: false };
  }
}
