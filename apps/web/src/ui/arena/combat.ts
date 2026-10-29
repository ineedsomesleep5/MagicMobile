/**
 * Combat on the Arena board (iOS arenaCombatButtons, arenaAllAttackTargets, arenaAttackStep, CombatArrowModel): the
 * on-device engine asks for attackers one creature at a time (a target prompt in the declare attackers step), so All
 * Attack queues every offered creature and sends the next once XMage has taken the last. Checked by test/combat.test.ts.
 */
import { combatPhase } from "../../core/arenaBoard";
import type { GameSnapshot, XmageCombatGroup, ZoneCard } from "../../core/models";
import { viewerID } from "../../core/models";

/** The ids XMage lets you pick now (GameBoardInteractionState.boardTargetableIds): a target prompt's choices, never a payment's. */
export function boardTargetableIds(snapshot: GameSnapshot): Set<string> {
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt || snapshot.manaPayment?.active === true) return new Set();
  const kind = prompt.responseKind.toLowerCase();
  const type = prompt.responseCommand?.type?.toLowerCase() ?? kind;
  if (["mana", "pay_cost", "cost", "x_mana"].includes(kind) || prompt.method === "GAME_PLAY_MANA" || prompt.method === "GAME_PLAY_XMANA") return new Set();
  if (!(type === "choose_target" || kind === "target" || /target/i.test(prompt.method))) return new Set();
  return new Set([...(prompt.targetIds ?? []), ...(prompt.targets ?? []).map((t) => t.id)]);
}

const mine = (snapshot: GameSnapshot): ZoneCard[] => snapshot.players.find((p) => p.playerId === viewerID(snapshot))?.zones.battlefield ?? [];
const opponents = (snapshot: GameSnapshot) => snapshot.players.filter((p) => p.playerId !== viewerID(snapshot) && p.hasLeft !== true);

/** The creatures All Attack sends: every creature the prompt offers, with one opponent to attack; undefined otherwise. */
export function allAttackTargets(snapshot: GameSnapshot): string[] | undefined {
  if (opponents(snapshot).length !== 1 || combatPhase(snapshot) !== "attackers") return undefined;
  const targetable = boardTargetableIds(snapshot);
  return mine(snapshot).filter((c) => c.isAttacking !== true && targetable.has(c.instanceId)).map((c) => c.instanceId);
}

/** How many of your creatures are declared: attacking, or blocking. */
export const declaredCount = (snapshot: GameSnapshot, phase: "attackers" | "blockers") =>
  mine(snapshot).filter((c) => (phase === "attackers" ? c.isAttacking === true : (c.blocking ?? []).length > 0)).length;

/** "No Attacks" / "1 Attacker" / "N Attackers", "No Blocks" / "1 Blocker" / "N Blockers". */
export function finishTitle(phase: "attackers" | "blockers", count: number): string {
  if (phase === "attackers") return count === 0 ? "No Attacks" : count === 1 ? "1 Attacker" : `${count} Attackers`;
  return count === 0 ? "No Blocks" : count === 1 ? "1 Blocker" : `${count} Blockers`;
}

/** All Attack's queue (ArenaAttackQueue): the next creature to send for a settled snapshot. */
export class AttackQueue {
  constructor(public remaining: string[]) {}
  get done() { return this.remaining.length === 0; }

  /** The next attacker to send, `wait` to let XMage answer first, or `end`. */
  step(snapshot: GameSnapshot, pending: boolean): { kind: "send"; id: string } | { kind: "wait" } | { kind: "end" } {
    if (pending) return { kind: "wait" };
    if (combatPhase(snapshot) !== "attackers") {
      // A snapshot between XMage's answers can lack the attacker prompt: only leaving the step ends the queue.
      const step = (snapshot.step ?? snapshot.phase).toLowerCase().replaceAll("_", "-");
      return step.includes("declare-attack") ? { kind: "wait" } : { kind: "end" };
    }
    const targetable = boardTargetableIds(snapshot);
    if (targetable.size === 0) return { kind: "wait" };
    const creatures = mine(snapshot);
    // XMage asking which defender (a planeswalker or battle in play) offers none of your creatures: wait for it.
    if (!creatures.some((c) => targetable.has(c.instanceId))) return { kind: "wait" };
    // The rest: still yours, not yet attacking, and offered now.
    this.remaining = this.remaining.filter((id) => targetable.has(id) && creatures.some((c) => c.instanceId === id && c.isAttacking !== true));
    const next = this.remaining.shift();
    return next === undefined ? { kind: "end" } : { kind: "send", id: next };
  }
}

export type ArrowKind = "attack" | "blockedAttack" | "block";
export interface CombatArrow { kind: ArrowKind; from: string; to: string; toKind?: string }

/** CombatArrowModel.arrows: attackers to what they attack (grey once blocked), blockers to the attacker they hold. */
export function combatArrows(groups: XmageCombatGroup[]): CombatArrow[] {
  return groups.flatMap((group) => [
    ...group.attackers.map((a): CombatArrow => ({ kind: group.blocked ? "blockedAttack" : "attack", from: a.instanceId, to: group.defenderId, toKind: group.defenderKind })),
    ...group.blockers.flatMap((b) => group.attackers.map((a): CombatArrow => ({ kind: "block", from: b.instanceId, to: a.instanceId }))),
  ]);
}
