/**
 * What a player is carrying besides life (iOS PlayerStatusSummary, BoardPlayerStatus, TavernEffectOrbit): counters
 * (poison first), the monarch, the initiative, designations, and each opposing commander's damage, as badges; the order
 * they take round a medallion; and where each sits on that orbit. Checked by test/playerStatus.test.ts.
 */
import type { GameSnapshot, PlayerGameState, ZoneCard } from "./models";

export type BadgeIcon = "poison" | "energy" | "experience" | "rad" | "ticket" | "counter" | "monarch" | "initiative" | "designation" | "commander";
export interface StatusBadge {
  id: string; icon: BadgeIcon; tint: string; count?: number; label: string;
  /** Close to losing to it: seven poison, fifteen commander damage. */
  nearLethal: boolean;
  /** A commander's card, for its art. */
  card?: ZoneCard;
}

/** BoardPlayerStatus.counters: the player's counters with poison folded in, poison first, then by name. */
export function playerCounters(player: PlayerGameState): { name: string; count: number }[] {
  const values: Record<string, number> = { ...(player.counters ?? {}) };
  if (player.poison > 0 && !Object.keys(values).some((k) => k.toLowerCase() === "poison")) values.Poison = player.poison;
  return Object.entries(values).filter(([, n]) => n > 0)
    .sort(([a], [b]) => (a.toLowerCase() === "poison" ? -1 : b.toLowerCase() === "poison" ? 1 : a < b ? -1 : a > b ? 1 : 0))
    .map(([name, count]) => ({ name, count }));
}

const capitalized = (name: string) => name.split(" ").map((w) => (w ? w[0].toUpperCase() + w.slice(1).toLowerCase() : w)).join(" ");

export function statusBadges(player: PlayerGameState, snapshot?: GameSnapshot): StatusBadge[] {
  const badges: StatusBadge[] = playerCounters(player).map(({ name, count }) => {
    const key = name.toLowerCase();
    const [icon, tint]: [BadgeIcon, string] = key === "poison" ? ["poison", "#8ce659"] : key === "energy" ? ["energy", "#ffd14d"]
      : key === "experience" ? ["experience", "#faebb3"] : key === "rad" ? ["rad", "#bfff66"] : key === "ticket" ? ["ticket", "#ff8066"] : ["counter", "#efe4cf"];
    return { id: `counter-${key}`, icon, tint, count, label: `${capitalized(name)} ${count}`, nearLethal: key === "poison" && count >= 7 };
  });
  if (player.monarch) badges.push({ id: "monarch", icon: "monarch", tint: "#ffcc66", label: "Monarch", nearLethal: false });
  if (player.initiative) badges.push({ id: "initiative", icon: "initiative", tint: "#f28c59", label: "Has the initiative", nearLethal: false });
  for (const designation of player.designations ?? []) {
    if (designation) badges.push({ id: `designation-${designation}`, icon: "designation", tint: "#f2d98c", label: designation, nearLethal: false });
  }
  for (const owner of snapshot?.players ?? []) {
    if (owner.playerId === player.playerId) continue;
    for (const commander of owner.commanders ?? []) {
      const damage = commander.damageToPlayers?.[player.playerId] ?? 0;
      if (damage <= 0) continue;
      const zones = owner.zones;
      const card = [...zones.command, ...zones.battlefield, ...zones.graveyard, ...zones.exile, ...zones.hand].find((c) => c.instanceId === commander.id);
      badges.push({ id: `commander-${commander.id}`, icon: "commander", tint: "#ff8c3a", count: damage, card,
        label: `${commander.name ?? "Commander"} dealt ${damage} commander damage`, nearLethal: damage >= 15 });
    }
  }
  return badges;
}

/** The order badges take round a medallion: commander damage first (the worst on top), then poison, then the rest. */
export function orbitOrder(badges: StatusBadge[]): StatusBadge[] {
  const commanders = badges.filter((b) => b.icon === "commander").sort((a, b) => (b.count ?? 0) - (a.count ?? 0));
  return [...commanders, ...badges.filter((b) => b.icon === "poison"), ...badges.filter((b) => b.icon !== "commander" && b.icon !== "poison")];
}

export const ORBIT = { stepDegrees: 25, badgeShare: 0.42 } as const;

/** TavernEffectOrbit.shown: the badges an orbit of `limit` slots shows, and how many more ("+N" in the last slot). */
export function orbitShown(badges: StatusBadge[], limit: number): { badges: StatusBadge[]; more: number } {
  const orbit = orbitOrder(badges);
  if (orbit.length <= limit) return { badges: orbit, more: 0 };
  const kept = orbit.slice(0, limit - 1);
  return { badges: kept, more: orbit.length - kept.length };
}

/** TavernEffectOrbit.offsets: each slot's centre from the medallion's, alternating either side of the bearing. */
export function orbitOffsets(count: number, radius: number, bearingDegrees: number): { x: number; y: number }[] {
  return Array.from({ length: Math.max(0, count) }, (_, index) => {
    const side = index % 2 === 1 ? 1 : -1;
    const angle = ((bearingDegrees + side * Math.floor((index + 1) / 2) * ORBIT.stepDegrees) * Math.PI) / 180;
    return { x: radius * Math.cos(angle), y: radius * Math.sin(angle) };
  });
}
