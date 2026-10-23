/**
 * What happened in one game, gathered from consecutive snapshots for the result screen (iOS GameStats.swift). Only public
 * information: life totals, combat groups and zone contents. Checked by test/gameStats.test.ts (game-summary-cases.json).
 */
import { displayPower, type GameSnapshot, isCreatureCard, viewerID, type ZoneCard } from "./models";

interface Attack { defender: string; attackers: { name: string; power: number; card: ZoneCard }[] }
/** Creatures on each battlefield (id → name) and each graveyard's card ids. */
interface Capture { life: Record<string, number>; creatures: Record<string, Map<string, string>>; graveyards: Record<string, Set<string>>; attacks: Attack[] }

/** A token's art name, without its " Token" suffix (NativeAssetStore.tokenArtworkName). */
export const tokenArtworkName = (name: string) => {
  const trimmed = name.trim();
  return trimmed.length > 6 && trimmed.toLowerCase().endsWith(" token") ? trimmed.slice(0, -6).trim() : trimmed;
};

export class GameStats {
  gameID = "";
  turns = 0;
  startingLife?: number;
  finalLife?: number;
  /** Combat damage your unblocked attackers dealt to players. */
  combatDamage = 0;
  /** The largest combat hit you landed on one player at once. */
  biggestHit = 0;
  damageByCard = new Map<string, number>();
  cardByName = new Map<string, ZoneCard>();
  creaturesDestroyed = 0;
  creaturesLost = 0;
  private previous?: Capture;

  record(snapshot: GameSnapshot) {
    if (snapshot.id !== this.gameID) { Object.assign(this, new GameStats()); this.gameID = snapshot.id; }
    this.turns = Math.max(this.turns, snapshot.turn);
    const viewer = viewerID(snapshot);
    const me = snapshot.players.find((p) => p.playerId === viewer);
    if (me) { this.startingLife ??= me.life; this.finalLife = me.life; }
    const yours = new Map((me?.zones.battlefield ?? []).map((c) => [c.instanceId, c] as const));
    const capture: Capture = {
      life: Object.fromEntries(snapshot.players.map((p) => [p.playerId, p.life])),
      creatures: Object.fromEntries(snapshot.players.map((p) => [p.playerId,
        new Map(p.zones.battlefield.filter((c) => c.isCreaturePermanent ?? isCreatureCard(c)).map((c) => [c.instanceId, c.card.name] as const))])),
      graveyards: Object.fromEntries(snapshot.players.map((p) => [p.playerId, new Set(p.zones.graveyard.map((c) => c.instanceId))])),
      attacks: (snapshot.xmage?.combat ?? []).flatMap((group) => {
        if (group.blocked || group.defenderId === viewer) return [];
        const mine = group.attackers.flatMap((attacker) => {
          const card = yours.get(attacker.instanceId);
          if (!card) return [];
          const shown = Number.parseInt(displayPower(attacker) ?? "", 10);
          const power = Math.max(0, Number.isFinite(shown) ? shown : attacker.power ?? 0);
          return power > 0 ? [{ name: attacker.card.name, power, card }] : [];
        });
        return mine.length > 0 ? [{ defender: group.defenderId, attackers: mine }] : [];
      }),
    };
    if (this.previous) this.compare(this.previous, capture, snapshot);
    this.previous = capture;
  }

  private compare(old: Capture, next: Capture, snapshot: GameSnapshot) {
    // Credit a defender's life loss to the unblocked attackers that were swinging at them.
    for (const attack of old.attacks) {
      const before = old.life[attack.defender]; const after = next.life[attack.defender];
      if (before === undefined || after === undefined || after >= before) continue;
      const total = attack.attackers.reduce((n, a) => n + a.power, 0);
      const credited = Math.min(total, before - after);
      if (total <= 0 || credited <= 0) continue;
      this.combatDamage += credited;
      this.biggestHit = Math.max(this.biggestHit, credited);
      for (const attacker of attack.attackers) {
        this.damageByCard.set(attacker.name, (this.damageByCard.get(attacker.name) ?? 0) + Math.round((attacker.power * credited) / total));
        this.cardByName.set(attacker.name, attacker.card);
      }
    }
    // A creature that left the battlefield for its owner's graveyard died (tokens just vanish). XMage can give a card a new
    // object ID as it changes zones, so a new graveyard card of the same name counts too (BoardEventDiffer does the same).
    for (const player of snapshot.players) {
      const before = old.creatures[player.playerId] ?? new Map<string, string>();
      const after = next.creatures[player.playerId] ?? new Map<string, string>();
      const gone = [...before].filter(([id]) => !after.has(id));
      if (gone.length === 0) continue;
      const earlier = old.graveyards[player.playerId] ?? new Set<string>();
      const graveyard = new Set(player.zones.graveyard.map((c) => c.instanceId));
      const arrivals = player.zones.graveyard.filter((c) => !earlier.has(c.instanceId) && !before.has(c.instanceId)).map((c) => c.card.name);
      const died = gone.filter(([id, name]) => {
        if (graveyard.has(id)) return true;
        const index = arrivals.indexOf(name);
        if (index >= 0) arrivals.splice(index, 1);
        return index >= 0;
      }).length;
      if (player.playerId === viewerID(snapshot)) this.creaturesLost += died; else this.creaturesDestroyed += died;
    }
  }

  /** The card of yours that dealt the most combat damage to players; a token's name without " Token". */
  get topCard(): { name: string; damage: number; card?: ZoneCard } | undefined {
    let top: [string, number] | undefined;
    for (const entry of this.damageByCard) if (!top || entry[1] > top[1] || (entry[1] === top[1] && entry[0] < top[0])) top = entry;
    if (!top || top[1] <= 0) return undefined;
    const card = this.cardByName.get(top[0]);
    return { name: card?.card.isToken === true ? tokenArtworkName(top[0]) : top[0], damage: top[1], card };
  }
}
