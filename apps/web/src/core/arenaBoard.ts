/**
 * Small pure pieces of the iOS Arena board (ArenaBoardModel.swift, CardInspector.swift): the keyword glossary, the
 * commander-taken notice, cards playable from other zones, a card's live state for the inspector, the hand's posture
 * and which combat declaration is being asked. Checked by test/arenaBoard.test.ts against parity/arena-board-cases.json.
 */
import type { GameSnapshot, LegalAction, PlayerGameState, ZoneCard } from "./models";
import { displayPower, displayToughness, isCreatureCard, playerLabel, viewerID } from "./models";

/** ArenaKeywordGlossary: what each keyword on a card means, in a sentence. */
export const GLOSSARY: [string, string][] = [
  ["Flying", "Can be blocked only by creatures with flying or reach."],
  ["Reach", "Can block creatures with flying."],
  ["Trample", "Combat damage beyond what its blockers need goes on to the player or planeswalker it's attacking."],
  ["Deathtouch", "Any damage it deals to a creature is enough to destroy it."],
  ["Lifelink", "Damage it deals also gains its controller that much life."],
  ["Vigilance", "Attacking doesn't tap it."],
  ["Haste", "It can attack and use tap abilities the turn it comes under your control."],
  ["First strike", "Deals combat damage before creatures without first strike."],
  ["Double strike", "Deals both first-strike and regular combat damage."],
  ["Menace", "Can't be blocked except by two or more creatures."],
  ["Hexproof", "Can't be the target of spells or abilities your opponents control."],
  ["Shroud", "Can't be the target of any spell or ability."],
  ["Indestructible", "Damage and \"destroy\" effects don't destroy it."],
  ["Defender", "Can't attack."],
  ["Flash", "You may cast it any time you could cast an instant."],
  ["Ward", "When it becomes the target of an opponent's spell or ability, that player pays the ward cost or it's countered."],
  ["Prowess", "Whenever you cast a noncreature spell, it gets +1/+1 until end of turn."],
  ["Flashback", "You may cast this card from your graveyard for its flashback cost. Then it's exiled."],
  ["Kicker", "You may pay an extra cost as you cast it for an extra effect."],
  ["Cycling", "Pay its cycling cost and discard it to draw a card."],
  ["Equip", "Attach it to a creature you control, any time you could cast a sorcery."],
  ["Toxic", "Players it deals combat damage to also get that many poison counters."],
  ["Infect", "Deals damage to creatures as -1/-1 counters and to players as poison counters."],
  ["Persist", "When it dies without a -1/-1 counter, it returns with one."],
  ["Undying", "When it dies without a +1/+1 counter, it returns with one."],
  ["Convoke", "Your creatures can help cast it: each one you tap pays for {1} or one mana of its colour."],
  ["Cascade", "When you cast it, reveal cards until a cheaper nonland card; you may cast that card free."],
  ["Storm", "When you cast it, copy it for each spell cast before it this turn."],
  ["Changeling", "It is every creature type."],
  ["Protection", "Can't be blocked, targeted, damaged, enchanted or equipped by anything with that quality."],
  ["Treasure", "A token artifact: tap and sacrifice it to add one mana of any colour."],
  ["Food", "A token artifact: pay {2}, tap and sacrifice it to gain 3 life."],
  ["Clue", "A token artifact: pay {2} and sacrifice it to draw a card."],
];

const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The keywords a card's rules mention, in the order they first appear, at most `limit`. */
export function glossaryEntries(rules: string, limit = 4): [string, string][] {
  const text = rules.toLowerCase();
  return GLOSSARY.flatMap(([keyword, meaning]) => {
    const match = new RegExp(`\\b${escape(keyword.toLowerCase())}\\b`).exec(text);
    return match ? [{ at: match.index, entry: [keyword, meaning] as [string, string] }] : [];
  }).sort((a, b) => a.at - b.at).slice(0, limit).map((found) => found.entry);
}

/** ArenaCommanderSteal.taken: "Name|holder id" for each of your commanders an opponent controls now. */
export function commandersTaken(snapshot: GameSnapshot): string[] {
  const viewer = snapshot.players.find((p) => p.playerId === viewerID(snapshot));
  const names = new Set((viewer?.commanders ?? []).map((c) => c.name).filter((n): n is string => !!n));
  if (names.size === 0) return [];
  return snapshot.players.filter((p) => p.playerId !== viewerID(snapshot))
    .flatMap((p) => p.zones.battlefield.filter((c) => names.has(c.card.name)).map((c) => `${c.card.name}|${p.playerId}`)).sort();
}

/** ArenaCommanderSteal.notice. */
export function commanderTakenNotice(entry: string, snapshot: GameSnapshot): string {
  const [name, holder] = entry.split("|");
  const who = holder ? playerLabel(snapshot, holder) : "An opponent";
  return `${who} took ${name || "Your commander"}. A commander goes to the command zone only after the spell that moved it finishes, so that spell could take it first.`;
}

/** One commander in the commander browser: its card where it can be seen, the times it was cast from the command zone and its next tax. */
export interface CommanderEntry {
  key: string; name: string; card?: ZoneCard;
  /** Where the card is when it isn't in the command zone ("battlefield", "graveyard", …; undefined when unseen). */
  zone?: "command" | "battlefield" | "graveyard" | "exile" | "hand" | "library";
  casts?: number; tax?: number;
}

/**
 * A player's commanders for the commander browser: the public commander list in its order (partners side by side), each
 * with its card from the command zone or wherever it can be seen now, then anything else in the command zone. Casts and
 * tax come from the commander's public state; a lone commander falls back to the player's known commander tax.
 */
export function commanderEntries(player: PlayerGameState, snapshot: GameSnapshot): CommanderEntry[] {
  // Its own command zone first; elsewhere it can be under anyone's control (a stolen commander).
  const elsewhere = ["battlefield", "graveyard", "exile", "hand", "library"] as const;
  const seen = (name: string): { card: ZoneCard; zone: NonNullable<CommanderEntry["zone"]> } | undefined => {
    const home = player.zones.command.find((c) => c.card.name === name);
    if (home) return { card: home, zone: "command" };
    for (const zone of elsewhere) {
      const card = snapshot.players.flatMap((p) => p.zones[zone]).find((c) => c.card.name === name);
      if (card) return { card, zone };
    }
    return undefined;
  };
  const listed = player.commanders ?? [];
  const entries: CommanderEntry[] = listed.map((commander, index) => {
    const name = commander.name ?? "Commander";
    const found = commander.name ? seen(commander.name) : undefined;
    const tax = commander.commanderTax ?? (listed.length === 1 && player.commanderTaxKnown ? player.commanderTax : undefined);
    return { key: commander.id || `commander-${index}`, name, card: found?.card, zone: found?.zone, casts: commander.castsFromCommandZone, tax };
  });
  const named = new Set(entries.map((e) => e.name));
  for (const card of player.zones.command) {
    if (named.has(card.card.name)) continue;
    named.add(card.card.name);
    const tax = listed.length === 0 && player.commanderTaxKnown ? player.commanderTax : undefined;
    entries.push({ key: card.instanceId, name: card.card.name, card, zone: "command", tax });
  }
  return entries;
}

/** ArenaExtraHand: cards you can play from your graveyard or exile, shown beside the hand. */
export function extraHandCards(player: PlayerGameState, actions: LegalAction[]): ZoneCard[] {
  const playable = new Set(actions.filter((a) => a.type === "cast_spell" || a.type === "play_land").flatMap((a) => [a.cardInstanceId, a.sourceInstanceId])
    .filter((id): id is string => id !== undefined));
  if (playable.size === 0) return [];
  return [...player.zones.graveyard, ...player.zones.exile].filter((c) => playable.has(c.instanceId));
}

/** The inspector's live-state notes for a card (CardInspector.liveState): its type, then what is true of it now. */
export function liveState(card: ZoneCard, battlefield: ZoneCard[]): string[] {
  const details: string[] = [];
  if (card.card.isToken === true) details.push(card.card.copySourceArtworkName === undefined ? "Token" : "Token copy");
  if (card.card.typeLine) details.push(card.card.typeLine);
  if ((card.cardIcons ?? []).some((i) => i.iconType === "COMMANDER")) details.push("Commander");
  const creature = card.isCreaturePermanent ?? isCreatureCard(card);
  const power = displayPower(card);
  const toughness = displayToughness(card);
  if (creature && power !== undefined && toughness !== undefined) details.push(`${power}/${toughness}`);
  if (card.tapped !== undefined) details.push(card.tapped ? "Tapped" : "Untapped");
  if (creature && card.summoningSickness === true) details.push("Summoning sick");
  if (card.isAttacking === true) details.push("Attacking");
  const blocking = card.blocking ?? [];
  if (blocking.length > 0) details.push(blocking.length === 1 ? "Blocking" : `Blocking ${blocking.length}`);
  if ((card.damage ?? 0) > 0) details.push(`${card.damage} damage`);
  if (card.attachedToInstanceId !== undefined) {
    const host = battlefield.find((c) => c.instanceId === card.attachedToInstanceId);
    details.push(host ? `Attached to ${host.card.name}` : "Attached");
  }
  if (card.phasedIn === false) details.push("Phased out");
  for (const [name, count] of Object.entries(card.counters ?? {})) if (count > 0) details.push(`${name} ×${count}`);
  const seen = new Set<string>();
  return details.filter((d) => { const key = d.toLowerCase(); if (seen.has(key)) return false; seen.add(key); return true; });
}

/** ArenaHandPosture.resolve: the hand rests for any decision on the board, while dragging and while spectating. */
export type HandPosture = "raised" | "resting" | "spread";
export function handPosture(s: { opened?: boolean; spread?: boolean; boardDecision?: boolean; dragging?: boolean; spectating?: boolean }): HandPosture {
  if (s.spectating || s.dragging || s.boardDecision) return "resting";
  if (s.spread) return "spread";
  return s.opened ? "raised" : "resting";
}

/** ArenaCombatPhase.current: which combat declaration the table is asking for, if any. */
export function combatPhase(snapshot: GameSnapshot): "attackers" | "blockers" | undefined {
  const actions = snapshot.legalActions ?? [];
  if (actions.some((a) => a.type === "declare_attackers")) return "attackers";
  if (actions.some((a) => a.type === "declare_blockers")) return "blockers";
  const prompt = snapshot.promptEnvelopeV2;
  if (!prompt || prompt.playerId !== viewerID(snapshot) ||
    !(prompt.responseKind.toLowerCase() === "target" || prompt.responseCommand?.type?.toLowerCase() === "choose_target")) return undefined;
  const step = (snapshot.step ?? snapshot.phase).toLowerCase().replaceAll("_", "-");
  if (step.includes("declare-attack")) return "attackers";
  if (step.includes("declare-block")) return "blockers";
  return undefined;
}
