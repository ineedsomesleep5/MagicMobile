/**
 * Port of iOS BoardEventTimeline.swift (Board FX phase 1 and the Arena pace): successive public snapshots become
 * presentation events, scheduled at the reference game's pace, and the board's hold that smart pass waits on. XMage stays
 * the source of truth: these events only decorate a transition the board has already applied. Checked by
 * test/arenaPace.test.ts against parity/arena-pace-cases.json and the beats of combat-cases.json, the cases iOS runs.
 * Times are seconds.
 */
import type { CardIdentity, GameSnapshot, XmageCardIcon, XmageStackObject, ZoneCard } from "./models";

export type BoardFXZone = "hand" | "library" | "battlefield" | "graveyard" | "exile" | "command" | "stack";
export type BoardFXTint = "white" | "blue" | "black" | "red" | "green" | "multicolor" | "colorless";

const ORDER = ["W", "U", "B", "R", "G"] as const;

/** A card's colours in WUBRG order: from its mana cost, else (a token) its printed colours. */
export function cardColors(card: CardIdentity): string[] {
  const found = new Set<string>();
  const cost = card.manaCost?.toUpperCase();
  if (cost) for (const symbol of ORDER) if (cost.includes(symbol)) found.add(symbol);
  if (found.size === 0) {
    for (const color of card.tokenColors ?? []) {
      const symbol = ({ w: "W", white: "W", u: "U", blue: "U", b: "B", black: "B", r: "R", red: "R", g: "G", green: "G" } as Record<string, string>)[color.toLowerCase()];
      if (symbol) found.add(symbol);
    }
  }
  return ORDER.filter((symbol) => found.has(symbol));
}

export function tintOf(card: CardIdentity): BoardFXTint {
  const colors = cardColors(card);
  if (colors.length === 0) return "colorless";
  if (colors.length > 1) return "multicolor";
  return ({ W: "white", U: "blue", B: "black", R: "red" } as Record<string, BoardFXTint>)[colors[0]] ?? "green";
}

/** Printed mana value from a visible cost such as "{3}{B}{B}". X counts as zero. */
export function manaValue(cost: string | undefined): number {
  if (!cost) return 0;
  let total = 0;
  for (const match of cost.matchAll(/\{([^}]+)\}/g)) {
    const symbol = match[1].toUpperCase();
    if (/^\d+$/.test(symbol)) total += Number(symbol);
    else if (symbol === "X" || symbol === "Y" || symbol === "Z") continue;
    // {2/W} costs two; other hybrid and Phyrexian symbols cost one.
    else total += symbol.startsWith("2/") ? 2 : 1;
  }
  return total;
}

const typeParts = (typeLine: string) => {
  const parts = typeLine.toLowerCase().replaceAll(" - ", "—").split("—");
  const words = (text: string) => text.split(/[^\p{L}]+/u).filter(Boolean);
  return { types: words(parts[0]), subtypes: words(parts.slice(1).join(" ")) };
};

/** What a card arriving on the battlefield sounds like (BoardFXArrivalSound). */
export type ArrivalSound =
  | { kind: "basicLand"; land: string } | { kind: "otherLand" } | { kind: "creature"; heavy: boolean; voice?: string }
  | { kind: "artifact" } | { kind: "enchantment" } | { kind: "planeswalker" } | { kind: "other" };

export const BASIC_LAND_TYPES = ["plains", "island", "swamp", "mountain", "forest"];
/** Creature subtype to its voice slot (a `creature-<slot>` sound); a card plays the first of its subtypes listed. */
export const CREATURE_VOICES: Record<string, string> = {
  human: "human", goblin: "goblin", elf: "elf", dragon: "dragon", drake: "dragon", sliver: "sliver",
  squirrel: "squirrel", orc: "orc", ogre: "orc", troll: "orc", giant: "giant", bear: "bear",
  dinosaur: "dinosaur", beast: "beast", hydra: "beast", horror: "horror", demon: "horror", wurm: "horror",
  boar: "horror", rat: "rat", mouse: "rat", rabbit: "critter", fox: "critter", otter: "critter",
  weasel: "critter", hamster: "critter", faerie: "faerie", angel: "angel", archon: "angel",
  vampire: "vampire", bat: "vampire", zombie: "zombie", skeleton: "zombie", wolf: "wolf", werewolf: "wolf",
  dog: "wolf", jackal: "wolf", cat: "cat", bird: "bird", phoenix: "bird", ooze: "ooze", wizard: "wizard",
  insect: "insect", spider: "insect", scorpion: "insect", eldrazi: "eldrazi",
};

export function arrivalSound(card: CardIdentity, isToken: boolean, commander: boolean): ArrivalSound {
  const { types, subtypes } = typeParts(card.typeLine);
  if (types.includes("land")) {
    const land = subtypes.find((s) => BASIC_LAND_TYPES.includes(s));
    return land ? { kind: "basicLand", land } : { kind: "otherLand" };
  }
  if (types.includes("creature")) {
    const heavy = commander || (!isToken && manaValue(card.manaCost) >= 5);
    return { kind: "creature", heavy, voice: subtypes.map((s) => CREATURE_VOICES[s]).find(Boolean) };
  }
  if (types.includes("planeswalker")) return { kind: "planeswalker" };
  if (types.includes("artifact")) return { kind: "artifact" };
  if (types.includes("enchantment")) return { kind: "enchantment" };
  return { kind: "other" };
}

/** The sound of a spell being cast: by card type, never colour. */
export function castSound(card: CardIdentity | undefined): "instant" | "sorcery" | "permanent" {
  const { types } = typeParts(card?.typeLine ?? "");
  if (types.includes("instant")) return "instant";
  if (types.includes("sorcery")) return "sorcery";
  return "permanent";
}

// ---------------- combat keywords (BoardCardPresentation.swift CombatKeyword) ----------------

export const COMBAT_KEYWORDS = ["doubleStrike", "firstStrike", "deathtouch", "trample", "lifelink", "indestructible", "menace", "flying", "reach", "vigilance"] as const;
export type CombatKeyword = (typeof COMBAT_KEYWORDS)[number];
const KEYWORD_LABEL: Record<CombatKeyword, string> = {
  doubleStrike: "Double strike", firstStrike: "First strike", deathtouch: "Deathtouch", trample: "Trample", lifelink: "Lifelink",
  indestructible: "Indestructible", menace: "Menace", flying: "Flying", reach: "Reach", vigilance: "Vigilance",
};
const iconType = (keyword: CombatKeyword) => "ABILITY_" + keyword.replace(/([A-Z])/g, "_$1").toUpperCase();

export const CombatKeywords = {
  label: (keyword: CombatKeyword) => KEYWORD_LABEL[keyword],
  /** Keywords from engine icons and from rules lines made only of keywords; sentences that mention one never count. */
  of(icons: XmageCardIcon[] | undefined, rules: string | undefined): CombatKeyword[] {
    const found = new Set<CombatKeyword>();
    for (const icon of icons ?? []) {
      const keyword = COMBAT_KEYWORDS.find((k) => iconType(k) === icon.iconType.toUpperCase());
      if (keyword) found.add(keyword);
    }
    for (const raw of (rules ?? "").split(/\r\n|[\n\v\f\r\u0085\u2028\u2029]/)) {
      const line = raw.replace(/<[^>]*>/g, "").replace(/\([^)]*\)/g, "").replace(/^[\s.]+|[\s.]+$/g, "");
      if (!line) continue;
      const words = line.split(",").map((w) => w.trim().toLowerCase());
      const keywords = words.map((w) => COMBAT_KEYWORDS.find((k) => KEYWORD_LABEL[k].toLowerCase() === w));
      if (keywords.every(Boolean)) keywords.forEach((k) => found.add(k!));
    }
    return COMBAT_KEYWORDS.filter((k) => found.has(k));
  },
  strikesFirst: (keywords: ReadonlySet<CombatKeyword>) => keywords.has("firstStrike") || keywords.has("doubleStrike"),
  strikesInRegularStep: (keywords: ReadonlySet<CombatKeyword>) => !keywords.has("firstStrike") || keywords.has("doubleStrike"),
};

export const isInCombat = (card: ZoneCard) => card.isAttacking === true || (card.blocking ?? []).length > 0;
export const isLandCard = (card: CardIdentity) => /land/i.test(card.typeLine);

/** The stack, top first (GameSnapshot.stackTopFirst). */
export const stackTopFirst = (snapshot: GameSnapshot): XmageStackObject[] => {
  const objects = snapshot.xmage?.stack ?? [];
  return snapshot.source === "xmage-ondevice" ? objects : [...objects].reverse();
};
const isSyntheticPlaceholder = (card: ZoneCard) => {
  const name = card.card.name.trim().toLowerCase();
  return name === "ability" || name === "activated ability" || name === "triggered ability" || card.card.typeLine.trim().toLowerCase() === "card";
};
export const displaySourceCard = (object: XmageStackObject) =>
  object.sourceCard && !isSyntheticPlaceholder(object.sourceCard) ? object.sourceCard : undefined;
export const displayName = (object: XmageStackObject) => (object.name.length === 0 ? "Stack object" : object.name);

// ---------------- state and events ----------------

export interface FXCard {
  id: string; playerID: string; zone: BoardFXZone; name: string; tint: BoardFXTint; damage: number; counters: number; attacking: boolean;
  blocking: string[]; isLand: boolean; isToken: boolean; keywords: ReadonlySet<CombatKeyword>; counterKinds: Record<string, number>;
  power?: number; toughness?: number; phasedOut: boolean;
}
export interface FXStackItem { id: string; name: string; controllerID?: string; tint: BoardFXTint; isAbility: boolean; manaValue: number }
export interface FXState {
  gameID: string; step: string; lives: Record<string, number>; cards: Map<string, FXCard>; stack: FXStackItem[];
  /** Attacker instance ID to the defending player or permanent ID (public combat groups). */
  defenders: Record<string, string>;
  /** Non-token card names currently in any command zone (commanders). */
  commandNames: Set<string>;
  /** Attackers whose combat group is blocked, even if every blocker has since left. */
  blockedAttackers: Set<string>;
}

export const normalizedStep = (raw: string) => raw.toLowerCase().replaceAll("_", "-");

/** BoardFXState(snapshot:): the minimal public board state used for diffing. */
export function fxState(snapshot: GameSnapshot): FXState {
  const cards = new Map<string, FXCard>();
  const commandNames = new Set<string>();
  const lives: Record<string, number> = {};
  for (const player of snapshot.players) {
    if (!(player.playerId in lives)) lives[player.playerId] = player.life;
    const zones: [BoardFXZone, ZoneCard[]][] = [["hand", player.zones.hand], ["library", player.zones.library],
      ["battlefield", player.zones.battlefield], ["graveyard", player.zones.graveyard], ["exile", player.zones.exile],
      ["command", player.zones.command], ["stack", player.zones.stack]];
    for (const [zone, list] of zones) {
      for (const card of list) {
        if (cards.has(card.instanceId)) continue;
        const onField = zone === "battlefield";
        cards.set(card.instanceId, {
          id: card.instanceId, playerID: player.playerId, zone, name: card.card.name, tint: tintOf(card.card), damage: card.damage ?? 0,
          counters: Object.values(card.counters ?? {}).reduce((a, b) => a + b, 0), attacking: card.isAttacking === true,
          blocking: card.blocking ?? [], isLand: isLandCard(card.card), isToken: card.card.isToken === true,
          keywords: new Set(onField && isInCombat(card) ? CombatKeywords.of(card.cardIcons, card.card.oracleText) : []),
          counterKinds: onField ? { ...(card.counters ?? {}) } : {}, power: onField ? card.power : undefined,
          toughness: onField ? card.toughness : undefined, phasedOut: onField && card.phasedIn === false,
        });
      }
    }
    for (const card of player.zones.command) if (card.card.isToken !== true) commandNames.add(card.card.name);
  }
  const stack = stackTopFirst(snapshot).map((object): FXStackItem => {
    const source = displaySourceCard(object);
    const name = displayName(object);
    return {
      id: object.id, name, controllerID: object.controllerId, tint: object.sourceCard ? tintOf(object.sourceCard.card) : "colorless",
      isAbility: /ability/i.test(object.objectType ?? "") || /ability/i.test(name), manaValue: manaValue(source?.card.manaCost),
    };
  });
  const defenders: Record<string, string> = {};
  const blockedAttackers = new Set<string>();
  for (const group of snapshot.xmage?.combat ?? []) {
    for (const attacker of group.attackers) {
      defenders[attacker.instanceId] = group.defenderId;
      if (group.blocked) blockedAttackers.add(attacker.instanceId);
    }
  }
  return { gameID: snapshot.id, step: normalizedStep(snapshot.step ?? snapshot.phase), lives, cards, stack, defenders, commandNames, blockedAttackers };
}

/** Which counter moment plays: +1/+1, -1/-1, loyalty, or any other counter. */
export type CounterKind = "plusOne" | "minusOne" | "loyalty" | "other";
export function counterKind(name: string): CounterKind {
  switch (name.toLowerCase().replaceAll(" ", "")) {
    case "+1/+1": case "p1p1": return "plusOne";
    case "-1/-1": case "m1m1": return "minusOne";
    case "loyalty": return "loyalty";
    default: return "other";
  }
}
const counterStats = (kind: CounterKind) => (kind === "plusOne" ? 1 : kind === "minusOne" ? -1 : 0);
/** What the counters do, not how many arrived: two -1/-1 counters read "-2/-2", never "+2". */
export function counterLabel(kind: CounterKind, delta: number): string {
  const signed = (value: number) => (value >= 0 ? `+${value}` : `${value}`);
  if (kind === "plusOne" || kind === "minusOne") return `${signed(counterStats(kind) * delta)}/${signed(counterStats(kind) * delta)}`;
  return signed(delta);
}

export type SpellWeight = "ability" | "spell" | "big" | "commander";
export type Entrance = "plain" | "showcase" | "commander";
export type StrikeTarget = { card: string } | { player: string };

export type BoardFXEvent =
  | { type: "spellCast"; stackID: string; name: string; controllerID?: string; tint: BoardFXTint; weight: SpellWeight }
  | { type: "attackDeclared"; cardID: string; tint: BoardFXTint }
  | { type: "blockDeclared"; cardID: string; attackerID: string }
  | { type: "firstStrikeBeat" }
  | { type: "combatStrike"; attackerID: string; target: StrikeTarget; tint: BoardFXTint; firstStrike: boolean }
  | { type: "damageMarked"; cardID: string; amount: number }
  | { type: "leftBattlefield"; cardID: string; playerID: string; to?: BoardFXZone; tint: BoardFXTint }
  | { type: "enteredBattlefield"; cardID: string; playerID: string; from?: BoardFXZone; tint: BoardFXTint; entrance: Entrance }
  | { type: "countersChanged"; cardID: string; kind: CounterKind; delta: number }
  | { type: "statsChanged"; cardID: string; power: number; toughness: number }
  | { type: "phased"; cardID: string; out: boolean }
  | { type: "transformed"; cardID: string; name: string }
  | { type: "controlChanged"; cardID: string; from: string; to: string }
  | { type: "lifeChanged"; playerID: string; delta: number };

/** Presentation order inside one snapshot transition. */
export function eventOrder(event: BoardFXEvent): number {
  switch (event.type) {
    case "spellCast": return 0;
    case "attackDeclared": return 1;
    case "blockDeclared": return 2;
    case "firstStrikeBeat": return 3;
    case "combatStrike": return event.firstStrike ? 4 : 5;
    case "damageMarked": return 6;
    case "leftBattlefield": return 7;
    case "phased": return event.out ? 7 : 8;
    case "enteredBattlefield": case "transformed": case "controlChanged": return 8;
    case "countersChanged": case "statsChanged": return 9;
    case "lifeChanged": return 10;
  }
}

export const FIRST_STRIKE_SUBJECT = "first-strike";
/** Card, stack object or player the effect is about. */
export function subjectID(event: BoardFXEvent): string {
  switch (event.type) {
    case "spellCast": return event.stackID;
    case "combatStrike": return event.attackerID;
    case "lifeChanged": return event.playerID;
    case "firstStrikeBeat": return FIRST_STRIKE_SUBJECT;
    default: return event.cardID;
  }
}
/** Life totals and the first-strike label are always shown; they carry game information. */
const isEssential = (event: BoardFXEvent) => event.type === "lifeChanged" || event.type === "firstStrikeBeat";
const isRegularStrike = (event: BoardFXEvent) => event.type === "combatStrike" && !event.firstStrike;

const byID = <T extends { id: string }>(a: T, b: T) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);

export const BoardEventDiffer = {
  /** Steps before combat damage; leaving them with attackers present means damage was dealt. */
  preDamageSteps: new Set(["combat", "begin-combat", "declare-attackers", "declare-blockers"]),
  /** Spells at or above this printed mana value get the big-spell flash. */
  bigSpellManaValue: 6,
  /** XMage's first-strike combat damage step, normalized like FXState.step. */
  firstStrikeStep: "first-combat-damage",

  events(old: FXState, next: FXState, commanders: ReadonlySet<string> = new Set()): BoardFXEvent[] {
    // A new game, reconnect to another match or design preview swap is a cut, not a transition.
    if (old.gameID !== next.gameID) return [];
    const events: BoardFXEvent[] = [];
    const oldStackIDs = new Set(old.stack.map((item) => item.id));
    const castNames = new Set<string>();
    for (const item of next.stack) {
      if (oldStackIDs.has(item.id)) continue;
      const weight: SpellWeight = item.isAbility ? "ability" : commanders.has(item.name) ? "commander"
        : item.manaValue >= BoardEventDiffer.bigSpellManaValue ? "big" : "spell";
      if (!item.isAbility) castNames.add(item.name);
      events.push({ type: "spellCast", stackID: item.id, name: item.name, controllerID: item.controllerID, tint: item.tint, weight });
    }
    // A permanent spell that was on the stack flies from there, without a second showcase.
    const resolvedNames = new Set([...old.stack.filter((item) => !item.isAbility).map((item) => item.name), ...castNames]);

    const claimed = new Set<string>();
    for (const card of [...old.cards.values()].sort(byID)) {
      if (card.zone !== "battlefield") continue;
      const after = next.cards.get(card.id);
      if (after) {
        if (after.zone !== "battlefield") events.push({ type: "leftBattlefield", cardID: card.id, playerID: card.playerID, to: after.zone, tint: card.tint });
        continue;
      }
      // XMage can assign a new object ID when a card changes zones: match the same name arriving in a public zone of the
      // same player; otherwise unknown.
      const arrival = [...next.cards.values()]
        .filter((c) => c.playerID === card.playerID && c.name === card.name && !old.cards.has(c.id) && !claimed.has(c.id))
        .filter((c) => c.zone === "graveyard" || c.zone === "exile" || c.zone === "command").sort(byID)[0];
      if (arrival) claimed.add(arrival.id);
      events.push({ type: "leftBattlefield", cardID: card.id, playerID: card.playerID, to: arrival?.zone, tint: card.tint });
    }

    for (const card of [...next.cards.values()].sort(byID)) {
      if (card.zone !== "battlefield") continue;
      const previous = old.cards.get(card.id);
      if (!previous || previous.zone !== "battlefield") {
        let source = previous?.zone;
        let entrance: Entrance;
        if (!card.isToken && commanders.has(card.name) && resolvedNames.has(card.name)) {
          // Its cast was the commander's big moment: coming off the stack it simply flies to its place.
          entrance = "plain"; source = "stack";
        } else if (!card.isToken && commanders.has(card.name)) {
          // Put onto the battlefield without a visible cast: the ceremony plays here.
          entrance = "commander";
        } else if (resolvedNames.has(card.name) && source !== "hand") {
          entrance = "plain"; source = "stack";
        } else if (!card.isLand && !card.isToken && (source === undefined || source === "hand")) {
          // Cast and resolved between two snapshots: nobody saw it on the stack.
          entrance = "showcase";
        } else {
          entrance = "plain";
        }
        events.push({ type: "enteredBattlefield", cardID: card.id, playerID: card.playerID, from: source, tint: card.tint, entrance });
        continue;
      }
      if (card.attacking && !previous.attacking) events.push({ type: "attackDeclared", cardID: card.id, tint: card.tint });
      if (card.blocking.length > 0 && previous.blocking.length === 0) events.push({ type: "blockDeclared", cardID: card.id, attackerID: card.blocking[0] });
      if (card.damage > previous.damage) events.push({ type: "damageMarked", cardID: card.id, amount: card.damage - previous.damage });
      events.push(...BoardEventDiffer.permanentChanges(previous, card));
    }

    events.push(...BoardEventDiffer.combatStrikes(old, next));

    for (const playerID of Object.keys(next.lives).sort()) {
      const previous = old.lives[playerID];
      if (previous !== undefined && previous !== next.lives[playerID]) events.push({ type: "lifeChanged", playerID, delta: next.lives[playerID] - previous });
    }
    return events.map((event, offset) => ({ event, offset }))
      .sort((a, b) => eventOrder(a.event) - eventOrder(b.event) || a.offset - b.offset).map((item) => item.event);
  },

  /**
   * Combat damage, one beat per damage step. Entering XMage's first-strike step plays the "First strike" beat with the
   * attackers that strike first; leaving it plays the regular strikes. A transition that skips the first-strike snapshot
   * plays both beats, first strikers first.
   */
  combatStrikes(old: FXState, next: FXState): BoardFXEvent[] {
    const firstStep = BoardEventDiffer.firstStrikeStep;
    const pre = BoardEventDiffer.preDamageSteps;
    const afterDamage = !pre.has(next.step) && next.step !== firstStep;
    const attackers = [...old.cards.values()].sort(byID).filter((c) => c.zone === "battlefield" && c.attacking);
    const strikes = (cards: FXCard[], firstStrike: boolean): BoardFXEvent[] => cards.flatMap((attacker) => {
      const target = BoardEventDiffer.strikeTarget(attacker, old, next);
      return target ? [{ type: "combatStrike" as const, attackerID: attacker.id, target, tint: attacker.tint, firstStrike }] : [];
    });
    const keywords = (id: string) => BoardEventDiffer.keywords(id, old, next);
    const first = attackers.filter((c) => CombatKeywords.strikesFirst(keywords(c.id)));
    const regular = attackers.filter((c) => CombatKeywords.strikesInRegularStep(keywords(c.id)));
    if (pre.has(old.step) && next.step === firstStep) return [{ type: "firstStrikeBeat" }, ...strikes(first, true)];
    if (old.step === firstStep && afterDamage) return strikes(regular, false);
    if (!(pre.has(old.step) && afterDamage)) return [];
    const firstStrikes = strikes(first, true);
    if (firstStrikes.length === 0) return strikes(attackers, false);
    return [{ type: "firstStrikeBeat" }, ...firstStrikes, ...strikes(regular, false)];
  },

  /** What changed on a permanent that stayed: controller, face, phasing, counters by kind, power/toughness beyond counters. */
  permanentChanges(previous: FXCard, card: FXCard): BoardFXEvent[] {
    const events: BoardFXEvent[] = [];
    if (card.playerID !== previous.playerID) events.push({ type: "controlChanged", cardID: card.id, from: previous.playerID, to: card.playerID });
    if (card.name !== previous.name) events.push({ type: "transformed", cardID: card.id, name: card.name });
    if (card.phasedOut !== previous.phasedOut) events.push({ type: "phased", cardID: card.id, out: card.phasedOut });
    const byKind = new Map<CounterKind, number>();
    for (const name of new Set([...Object.keys(previous.counterKinds), ...Object.keys(card.counterKinds)])) {
      const delta = (card.counterKinds[name] ?? 0) - (previous.counterKinds[name] ?? 0);
      if (delta !== 0) byKind.set(counterKind(name), (byKind.get(counterKind(name)) ?? 0) + delta);
    }
    // A snapshot without counter names still shows the total going up (older fixtures).
    if (byKind.size === 0 && Object.keys(card.counterKinds).length === 0 && Object.keys(previous.counterKinds).length === 0 && card.counters !== previous.counters) {
      byKind.set("other", card.counters - previous.counters);
    }
    for (const kind of ["plusOne", "minusOne", "loyalty", "other"] as const) {
      const delta = byKind.get(kind);
      if (delta !== undefined && delta !== 0) events.push({ type: "countersChanged", cardID: card.id, kind, delta });
    }
    // A new face has new printed stats, so only the same face reports a change.
    if (card.name === previous.name && card.power !== undefined && card.toughness !== undefined && previous.power !== undefined && previous.toughness !== undefined) {
      let fromCounters = 0;
      byKind.forEach((delta, kind) => { fromCounters += counterStats(kind) * delta; });
      const dPower = card.power - previous.power - fromCounters;
      const dToughness = card.toughness - previous.toughness - fromCounters;
      if (dPower !== 0 || dToughness !== 0) events.push({ type: "statsChanged", cardID: card.id, power: dPower, toughness: dToughness });
    }
    return events;
  },

  keywords(id: string, old: FXState, next: FXState): Set<CombatKeyword> {
    return new Set([...(old.cards.get(id)?.keywords ?? []), ...(next.cards.get(id)?.keywords ?? [])]);
  },

  /** Blocker first, then the public combat defender, then the first opponent. A blocked attacker whose blockers all left deals no damage unless it tramples. */
  strikeTarget(attacker: FXCard, old: FXState, next: FXState): StrikeTarget | undefined {
    const blocking = (state: FXState) => [...state.cards.values()].filter((c) => c.zone === "battlefield" && c.blocking.includes(attacker.id)).map((c) => c.id);
    const blockers = [...blocking(old), ...blocking(next)].sort();
    if (blockers.length > 0) return { card: blockers[0] };
    if ((old.blockedAttackers.has(attacker.id) || next.blockedAttackers.has(attacker.id)) && !BoardEventDiffer.keywords(attacker.id, old, next).has("trample")) {
      return undefined;
    }
    const defender = old.defenders[attacker.id] ?? next.defenders[attacker.id];
    if (defender !== undefined) {
      if (old.lives[defender] !== undefined) return { player: defender };
      if (old.cards.has(defender)) return { card: defender };
    }
    const opponent = Object.keys(old.lives).sort().find((id) => id !== attacker.playerID);
    return { player: opponent ?? attacker.playerID };
  },
};

// ---------------- scheduling ----------------

export type BoardFXLevel = "full" | "reduced" | "off";
export const BOARD_FX_LEVELS: BoardFXLevel[] = ["full", "reduced", "off"];
/** Reduce Motion always caps the level at reduced; effects are off while a combo loop repeats. */
export const resolvedLevel = (stored: string | undefined, reduceMotion: boolean, suppressedForLoop = false): BoardFXLevel => {
  if (suppressedForLoop) return "off";
  const level: BoardFXLevel = stored === "reduced" || stored === "off" ? stored : "full";
  return reduceMotion && level === "full" ? "reduced" : level;
};

/** Whose clock the board's effects keep: the Hearth board reads every spell at the centre; the Arena board keeps the reference game's pace. */
export type BoardFXPace = "hearth" | "arena";

export class ScheduledBoardFX {
  constructor(readonly id: number, readonly event: BoardFXEvent, readonly delay: number, readonly duration: number,
    /** Particles, shake and large motion are omitted when false. */
    readonly usesMotion: boolean, readonly pace: BoardFXPace = "hearth") {}

  get end() { return this.delay + this.duration; }

  /** When a card arriving with this effect lands in its slot (the tile appears). */
  get landing(): number {
    if (!this.usesMotion) return this.delay;
    const event = this.event;
    if (event.type === "enteredBattlefield") {
      // The Arena board flies every arrival plainly from the stack card.
      return this.delay + this.duration * BoardFXScheduler.landingFraction(this.pace === "arena" ? "plain" : event.entrance);
    }
    if (event.type === "controlChanged") return this.delay + this.duration * BoardFXScheduler.stealLandingFraction;
    return this.delay;
  }

  /** When the next group of effects may begin. */
  get handoff(): number {
    const event = this.event;
    const motion = this.usesMotion;
    if (event.type === "spellCast") {
      if (!motion) return this.delay + 0.4;
      if (this.pace === "arena") return event.weight === "ability" ? this.delay + 0.3 : this.end - Math.min(0.3, this.duration * 0.3);
      return event.weight === "ability" ? this.delay + 0.55 : this.end - 0.3;
    }
    if (event.type === "combatStrike" && motion) return this.delay + this.duration * BoardFXScheduler.strikeImpactFraction;
    if (event.type === "firstStrikeBeat") return this.delay + (motion ? 0.15 : 0.06);
    if (event.type === "enteredBattlefield" && motion && event.entrance !== "plain" && this.pace === "hearth") return this.landing;
    return this.delay + (motion ? 0.16 : 0.06);
  }

  /** When the effects after this one may begin: a spell is read to the end and a card leaving play finishes first. */
  get release(): number {
    const event = this.event;
    if (event.type === "spellCast" && event.weight !== "ability") return this.end;
    if (event.type === "leftBattlefield") return this.end;
    return this.handoff;
  }

  /** Until when a later snapshot's effects wait. */
  get holdsLaterBatchesUntil(): number | undefined {
    if (this.event.type === "firstStrikeBeat") return this.end;
    if (this.release !== this.handoff) return this.release;
    return this.isSequential ? this.handoff : undefined;
  }

  /** Showcases share the centre of the board, so they play one after another. */
  get isSequential(): boolean {
    if (!this.usesMotion) return false;
    const event = this.event;
    // The reference's strikes land one after another, each with its own number.
    if (this.pace === "arena" && event.type === "combatStrike") return true;
    if (event.type === "spellCast") return event.weight !== "ability";
    if (event.type === "enteredBattlefield") return event.entrance !== "plain";
    return false;
  }

  /** Smart pass waits for this effect before the game moves on: a spell read, a showcase arrival, a card leaving, a hit. */
  get holdsSmartPass(): boolean {
    const event = this.event;
    switch (event.type) {
      case "spellCast": return event.weight !== "ability";
      case "enteredBattlefield": return event.entrance !== "plain";
      case "leftBattlefield": case "combatStrike": case "firstStrikeBeat": return true;
      default: return false;
    }
  }
}

export const BoardFXScheduler = {
  /** Decorative effects per transition; board wipes collapse to the first few. */
  decorativeLimit: 10,
  stagger: 0.07,
  /** A board wipe on the Arena board (three or more permanents leaving at once) leaves one card after another. */
  sweepStep: 0.16,
  sweepSpread: 1.2,
  sweepMinimum: 3,
  /** Effects never wait more than this for a showcase from an earlier snapshot. */
  maximumHold: 4,
  /** The gap between the reference's strikes: 11–13 frames at 30 fps. */
  arenaStrikeSpacing: 0.38,
  arrivalFlightFraction: 0.42,
  strikeImpactFraction: 0.42,
  stealHookFraction: 0.28,
  stealLandingFraction: 0.72,

  landingFraction(entrance: Entrance): number {
    return entrance === "plain" ? BoardFXScheduler.arrivalFlightFraction : entrance === "showcase" ? 0.82 : 0.8;
  },

  schedule(events: BoardFXEvent[], level: BoardFXLevel, firstID = 0, hold = 0, pace: BoardFXPace = "hearth", viewerID?: string): ScheduledBoardFX[] {
    if (level === "off") return [];
    const motion = level === "full";
    let decorative = 0;
    const kept: BoardFXEvent[] = [];
    for (const event of events) {
      if (isEssential(event)) kept.push(event);
      else if (decorative < BoardFXScheduler.decorativeLimit) { decorative += 1; kept.push(event); }
    }
    const result: ScheduledBoardFX[] = [];
    const departures = kept.filter((e) => e.type === "leftBattlefield").length;
    const sweepGap = pace === "arena" && motion && departures >= BoardFXScheduler.sweepMinimum
      ? Math.min(BoardFXScheduler.sweepStep, BoardFXScheduler.sweepSpread / (departures - 1)) : undefined;
    let departureIndex = 0;
    let groupStart = Math.min(Math.max(hold, 0), BoardFXScheduler.maximumHold);
    let cursor = groupStart;
    let previousOrder: number | undefined;
    let indexInGroup = 0;
    for (const event of kept) {
      if (previousOrder !== undefined && previousOrder !== eventOrder(event)) {
        groupStart = result.length > 0 ? Math.max(...result.map((fx) => fx.release)) : groupStart;
        // Regular damage waits a short beat after the first strikers' hits.
        if (isRegularStrike(event)) {
          const beat = BoardFXScheduler.firstStrikeBeatEnd(result, motion);
          if (beat !== undefined) groupStart = Math.max(groupStart, beat);
        }
        cursor = groupStart;
        indexInGroup = 0;
      }
      previousOrder = eventOrder(event);
      const duration = BoardFXScheduler.duration(event, motion, pace, viewerID);
      const id = firstID + result.length;
      const probe = new ScheduledBoardFX(id, event, 0, duration, motion, pace);
      let fx: ScheduledBoardFX;
      if (probe.isSequential) {
        fx = new ScheduledBoardFX(id, event, cursor, duration, motion, pace);
        cursor = pace === "arena" && event.type === "combatStrike" ? fx.delay + BoardFXScheduler.arenaStrikeSpacing : fx.handoff + 0.1;
      } else if (sweepGap !== undefined && event.type === "leftBattlefield") {
        fx = new ScheduledBoardFX(id, event, groupStart + departureIndex * sweepGap, duration, motion, pace);
        departureIndex += 1;
      } else {
        fx = new ScheduledBoardFX(id, event, groupStart + indexInGroup * (motion ? BoardFXScheduler.stagger : 0.02), duration, motion, pace);
        indexInGroup += 1;
      }
      result.push(fx);
    }
    // The label spans its beat, so a later snapshot's regular damage waits for it too.
    const index = result.findIndex((fx) => fx.event.type === "firstStrikeBeat");
    if (index >= 0) {
      const label = result[index];
      const end = BoardFXScheduler.firstStrikeBeatEnd(result, motion) ?? label.end;
      result[index] = new ScheduledBoardFX(label.id, label.event, label.delay, Math.max(label.duration, end - label.delay), motion, pace);
    }
    return result;
  },

  firstStrikeBeatPause: (motion: boolean) => (motion ? 0.3 : 0.15),

  /** When the first-strike beat is over: a short pause after its strikes (and its damage and deaths when alone). */
  firstStrikeBeatEnd(scheduled: ScheduledBoardFX[], motion: boolean): number | undefined {
    const combined = scheduled.some((fx) => isRegularStrike(fx.event));
    const beat = scheduled.filter((fx) => (fx.event.type === "combatStrike" && fx.event.firstStrike) ||
      ((fx.event.type === "damageMarked" || fx.event.type === "leftBattlefield") && !combined));
    if (!scheduled.some((fx) => fx.event.type === "firstStrikeBeat") || beat.length === 0) return undefined;
    return Math.max(...beat.map((fx) => fx.end)) + BoardFXScheduler.firstStrikeBeatPause(motion);
  },

  duration(event: BoardFXEvent, motion: boolean, pace: BoardFXPace = "hearth", viewerID?: string): number {
    if (pace === "arena") return BoardFXScheduler.arenaDuration(event, motion, viewerID);
    switch (event.type) {
      case "spellCast":
        switch (event.weight) {
          case "ability": return motion ? 1.3 : 1.1;
          case "spell": return motion ? 2.4 : 1.5;
          case "big": return motion ? 2.7 : 1.5;
          case "commander": return motion ? 3.1 : 1.6;
        }
        break;
      case "enteredBattlefield":
        if (!motion) return 0.9;
        return event.entrance === "plain" ? 1.0 : event.entrance === "showcase" ? 2.5 : 3.1;
      case "leftBattlefield": return motion ? 0.95 : 0.9;
      case "damageMarked": return 0.8;
      case "countersChanged": return motion ? 1.0 : 0.7;
      case "statsChanged": return motion ? 1.0 : 0.8;
      case "phased": return motion ? 1.1 : 0.7;
      case "transformed": return motion ? 0.9 : 0.6;
      case "controlChanged": return motion ? 1.5 : 0.7;
      case "attackDeclared": return motion ? 0.7 : 0.6;
      case "blockDeclared": return motion ? 0.8 : 0.6;
      case "combatStrike": return motion ? 0.95 : 0.6;
      case "firstStrikeBeat": return motion ? 1.2 : 1.0;
      case "lifeChanged": return motion ? 1.3 : 0.9;
    }
    return 0;
  },

  /**
   * The reference game's beats (GAP_ANALYSIS.md §2, 30 fps): your spell drops onto the stack card in 8–10 frames; an
   * opponent's is revealed for about 1.6 s (smart pass waits for it); a trigger grows and flares in 15; a card lands in
   * under 8 plus its settle; a strike is 12–14 frames; attack and block marks drop in at once.
   */
  arenaDuration(event: BoardFXEvent, motion: boolean, viewerID?: string): number {
    switch (event.type) {
      case "spellCast": {
        const yours = event.controllerID === undefined || event.controllerID === viewerID;
        if (event.weight === "ability") return motion ? 0.5 : 0.4;
        if (event.weight === "commander") return yours ? (motion ? 1.0 : 0.6) : (motion ? 1.6 : 1.2);
        return yours ? (motion ? 0.35 : 0.3) : (motion ? 1.6 : 1.2);
      }
      case "enteredBattlefield": return motion ? 0.6 : 0.5;
      case "leftBattlefield": return motion ? 0.8 : 0.7;
      case "damageMarked": return 0.6;
      case "countersChanged": return motion ? 0.8 : 0.6;
      case "statsChanged": return motion ? 0.8 : 0.6;
      case "phased": return motion ? 0.9 : 0.6;
      case "transformed": return motion ? 0.8 : 0.6;
      case "controlChanged": return motion ? 1.2 : 0.7;
      case "attackDeclared": return 0.25;
      case "blockDeclared": return 0.3;
      case "combatStrike": return motion ? 0.45 : 0.4;
      case "firstStrikeBeat": return motion ? 1.0 : 0.8;
      case "lifeChanged": return motion ? 1.0 : 0.8;
    }
  },
};

// ---------------- the director and the hold ----------------

export interface ActiveBoardFX { scheduled: ScheduledBoardFX; start: number }
const endOf = (fx: ActiveBoardFX) => fx.start + fx.scheduled.end;

/** Card motion for the board's tiles: hide cards while a flight stands in for them, lunge new attackers, hold combat stances. */
export interface BoardFXCardMotion {
  hidden: Map<string, { batch: number; from: number; until: number }[]>;
  lunges: Map<string, { token: number; direction: number }>;
  stances: Map<string, { kind: "attacking" | "blocking"; direction: number; moves: boolean }>;
  flips: Map<string, number>;
}

/** The revision key the board records each snapshot under (BoardFXRevisionKey). */
export const revisionKey = (snapshot: GameSnapshot) =>
  [snapshot.id, snapshot.bridgeRevision ?? "", snapshot.xmage?.xmageCycle ?? "", snapshot.turn, snapshot.players.map((p) => p.life).join(",")].join("|");

/** Owns the previous FX state and the effects playing. The board feeds it every accepted snapshot (BoardFXDirector). */
export class BoardFXDirector {
  previous?: FXState;
  active: ActiveBoardFX[] = [];
  /** Card faces for flights, keyed by event subject; departed cards come from the previous snapshot. */
  subjects = new Map<string, ZoneCard>();
  /** Every commander name seen in a command zone this game. */
  commanderNames = new Set<string>();
  level: BoardFXLevel = "full";
  private previousBattlefield = new Map<string, ZoneCard>();
  private nextID = 0;
  static readonly renderGrace = 2;

  /** Returns only the newly scheduled effects. `holdUntil`: the centre is taken (the turn banner) until then. */
  ingest(snapshot: GameSnapshot, level: BoardFXLevel, now: number, holdUntil?: number, pace: BoardFXPace = "hearth"): ScheduledBoardFX[] {
    const state = fxState(snapshot);
    const battlefield = new Map(snapshot.players.flatMap((p) => p.zones.battlefield).map((c) => [c.instanceId, c] as const));
    const departed = this.previousBattlefield;
    this.level = level;
    try {
      this.prune(now - BoardFXDirector.renderGrace);
      const previous = this.previous;
      if (!previous || previous.gameID !== state.gameID) {
        this.active = []; this.subjects = new Map(); this.commanderNames = new Set(state.commandNames);
        return [];
      }
      state.commandNames.forEach((name) => this.commanderNames.add(name));
      const events = BoardEventDiffer.events(previous, state, this.commanderNames);
      // Let a showcase or first-strike beat from an earlier snapshot finish before this batch plays.
      const ends = this.active.flatMap((fx) => (fx.scheduled.holdsLaterBatchesUntil === undefined ? [] : [fx.start + fx.scheduled.holdsLaterBatchesUntil]));
      const hold = Math.max(ends.length > 0 ? Math.max(...ends) - now : 0, holdUntil !== undefined ? holdUntil - now : 0);
      const scheduled = BoardFXScheduler.schedule(events, level, this.nextID, hold, pace, snapshot.viewerPlayerId);
      this.nextID += scheduled.length;
      this.active.push(...scheduled.map((fx) => ({ scheduled: fx, start: now })));
      const stack = stackTopFirst(snapshot);
      for (const fx of scheduled) {
        const event = fx.event;
        const set = (id: string, card: ZoneCard | undefined) => { if (card) this.subjects.set(id, card); else this.subjects.delete(id); };
        switch (event.type) {
          case "enteredBattlefield": set(event.cardID, battlefield.get(event.cardID)); break;
          case "leftBattlefield": set(event.cardID, departed.get(event.cardID)); break;
          // The flip shows the old face turning over to the new one.
          case "transformed": set(event.cardID, departed.get(event.cardID)); break;
          case "combatStrike": set(event.attackerID, departed.get(event.attackerID) ?? battlefield.get(event.attackerID)); break;
          case "controlChanged": set(event.cardID, battlefield.get(event.cardID)); break;
          case "spellCast": { const object = stack.find((o) => o.id === event.stackID); set(event.stackID, object && displaySourceCard(object)); break; }
          default: break;
        }
      }
      return scheduled;
    } finally {
      this.previous = state;
      this.previousBattlefield = battlefield;
    }
  }

  /** Until when a showcase holds the centre, or a spell, departure or hit is still playing (the turn banner waits). */
  get centreBusyUntil(): number | undefined {
    const ends = this.active.filter((fx) => fx.scheduled.isSequential || fx.scheduled.holdsSmartPass).map(endOf);
    return ends.length > 0 ? Math.max(...ends) : undefined;
  }

  /** Until when smart pass waits, so the board finishes what it is showing first. */
  get smartPassHoldUntil(): number | undefined {
    const ends = this.active.filter((fx) => fx.scheduled.holdsSmartPass).map(endOf);
    return ends.length > 0 ? Math.max(...ends) : undefined;
  }

  get latestEnd(): number | undefined {
    return this.active.length > 0 ? Math.max(...this.active.map(endOf)) : undefined;
  }

  prune(now: number) {
    this.active = this.active.filter((fx) => endOf(fx) > now);
    const live = new Set(this.active.map((fx) => subjectID(fx.scheduled.event)));
    for (const key of [...this.subjects.keys()]) if (!live.has(key)) this.subjects.delete(key);
  }

  cardMotion(viewerID: string): BoardFXCardMotion {
    const motion: BoardFXCardMotion = { hidden: new Map(), lunges: new Map(), stances: new Map(), flips: new Map() };
    if (this.level === "off") return motion;
    const hide = (id: string, window: { batch: number; from: number; until: number }) => motion.hidden.set(id, [...(motion.hidden.get(id) ?? []), window]);
    for (const effect of this.active) {
      const fx = effect.scheduled;
      if (!fx.usesMotion) continue;
      const event = fx.event;
      if (event.type === "enteredBattlefield" && this.subjects.has(event.cardID)) hide(event.cardID, { batch: effect.start, from: 0, until: fx.landing });
      // A double striker flies twice; each strike hides its tile only while it flies.
      else if (event.type === "combatStrike" && this.subjects.has(event.attackerID)) hide(event.attackerID, { batch: effect.start, from: fx.delay, until: fx.end });
      else if (event.type === "attackDeclared") {
        const owner = this.previous?.cards.get(event.cardID)?.playerID;
        motion.lunges.set(event.cardID, { token: fx.id, direction: owner === viewerID ? -1 : 1 });
      } else if (event.type === "transformed") motion.flips.set(event.cardID, fx.id);
      // The dragged card stands in for the tile until it lands on the taker's side.
      else if (event.type === "controlChanged" && this.subjects.has(event.cardID)) hide(event.cardID, { batch: effect.start, from: 0, until: fx.landing });
    }
    for (const card of [...(this.previous?.cards.values() ?? [])].sort(byID)) {
      if (card.zone !== "battlefield") continue;
      const direction = card.playerID === viewerID ? -1 : 1;
      if (card.attacking) motion.stances.set(card.id, { kind: "attacking", direction, moves: this.level === "full" });
      else if (card.blocking.length > 0) motion.stances.set(card.id, { kind: "blocking", direction, moves: this.level === "full" });
    }
    return motion;
  }
}

/**
 * What the board is still showing, for smart pass to wait on (BoardPresentationHold). The board records each snapshot it
 * takes in; the session only reads. XMage never waits on it except through the pass the session holds back.
 */
export class BoardPresentationHold {
  /** Smart pass never waits longer than this for one prompt, so the board can't stall the game. */
  static readonly maximumWait = 5;
  /** How long smart pass gives the board to take in a newly published snapshot. */
  static readonly ingestWait = 1;
  /** How long smart pass waits while you read a card: long, but a bound. */
  static readonly readingWait = 60;
  ingested?: string;
  until?: number;
  /** The player is reading a card (the inspector is open): smart pass waits until it closes. */
  reading = false;
  record(key: string | undefined, until: number | undefined) { this.ingested = key; this.until = until; }
}

/** A board wipe's recap for the caption (ArenaSweepRecap): the spell that resolved and what left, three or more at once. */
export function sweepRecap(spell: string | undefined, events: BoardFXEvent[]): string | undefined {
  let graveyard = 0; let exile = 0; let other = 0;
  for (const event of events) {
    if (event.type !== "leftBattlefield") continue;
    if (event.to === "graveyard") graveyard += 1;
    else if (event.to === "exile") exile += 1;
    else other += 1;
  }
  if (graveyard + exile + other < BoardFXScheduler.sweepMinimum) return undefined;
  const what = [graveyard > 0 ? `${graveyard} to the graveyard` : undefined, exile > 0 ? `${exile} exiled` : undefined,
    other > 0 ? `${other} returned or moved` : undefined].filter(Boolean).join(", ");
  return spell !== undefined ? `${spell}: ${what}` : `${graveyard + exile + other} permanents left the battlefield: ${what}`;
}
