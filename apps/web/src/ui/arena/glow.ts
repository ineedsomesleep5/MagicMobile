/**
 * Which light a card or medallion wears on the Arena board (ArenaBattlefieldCard.glow, ArenaHeroMedallion.commanderReady
 * and GameplayAffordances.castableZones on iOS): the board's classes, kept here so they can be tested.
 */
import type { GameSnapshot, LegalAction, PlayerGameState, ZoneCard } from "../../core/models";

/** The actions XMage offers for a card, as its own card or its ability's source (GameBoardInteractionState.cardActions). */
export const cardActions = (actions: readonly LegalAction[], id: string) =>
  actions.filter((a) => a.cardInstanceId === id || a.sourceInstanceId === id);

export interface GlowContext {
  onBattlefield: boolean;
  /** The open prompt can choose this card. */
  targetable: boolean;
  /** Choosing attackers or blockers: a choosable card lights warm instead of the target cyan. */
  combatSelect: boolean;
  /** A prompt is open and no answer is on its way. */
  answering: boolean;
  /** A payment is open: only mana sources light (orange). */
  paying: boolean;
}

/**
 * The card's classes: tapped, attacking or blocking, then one light. A target or combat choice wins; while paying, mana
 * sources glow orange; a permanent with a non-mana activated ability you can use now glows yellow (`ability`, Caleb
 * 2026-10-26); anything else you can play glows cyan (`playable`). Lands keep a softer light (`landish`). A phased-out
 * permanent lights for nothing.
 */
export function glowClasses(card: ZoneCard, actions: readonly LegalAction[], context: GlowContext): string[] {
  const { onBattlefield, targetable, combatSelect, answering, paying } = context;
  const list: string[] = [];
  if (onBattlefield && card.tapped) list.push("tapped");
  const attacking = onBattlefield && card.isAttacking === true;
  const blocking = onBattlefield && (card.blocking?.length ?? 0) > 0;
  if (attacking) list.push("atk");
  if (blocking) list.push("blk");
  if (targetable) list.push(combatSelect ? "can-act" : "targetable");
  // An attacker or blocker keeps its combat light over what it could do (ArenaBattlefieldCard.arenaGlow).
  else if (answering && !attacking && !blocking && card.phasedIn !== false) {
    const own = cardActions(actions, card.instanceId);
    if (paying) { if (own.some((a) => a.type === "make_mana")) list.push("payable"); }
    else if (onBattlefield && own.some((a) => a.type === "activate_ability")) list.push("ability");
    else if (own.some((a) => a.type !== "make_mana")) list.push("playable");
  }
  // Lands you could use glow softer, so a full mana row doesn't shout (ArenaOutlineGlow strength 0.65).
  if (onBattlefield && /\bland\b/i.test(card.card.typeLine)) list.push("landish");
  return list;
}

export type CastableZone = "command" | "graveyard" | "exile" | "library";

/**
 * The zones you can cast or play a card from now (GameplayAffordances.castableZones): your command zone, graveyard,
 * exile or library holding a card with a cast or land play of yours. Your medallion glows while any is lit.
 */
export function castableZones(player: PlayerGameState, snapshot: GameSnapshot): Set<CastableZone> {
  if (player.playerId !== snapshot.viewerPlayerId) return new Set();
  const plays = (snapshot.legalActions ?? []).filter((a) => (a.type === "cast_spell" || a.type === "play_land") && a.playerId === player.playerId);
  if (plays.length === 0) return new Set();
  const zones: [CastableZone, ZoneCard[]][] = [["command", player.zones.command], ["graveyard", player.zones.graveyard],
    ["exile", player.zones.exile], ["library", player.zones.library]];
  return new Set(zones.filter(([, cards]) => cards.some((card) => cardActions(plays, card.instanceId).length > 0)).map(([zone]) => zone));
}
