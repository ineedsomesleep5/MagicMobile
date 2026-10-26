/**
 * Port of OnDeviceSnapshotAdapter.kt (Swift OnDeviceSnapshotAdapter.swift). Converts only the
 * engine's authenticated, seat-scoped client DTO. Never reconstructs hidden cards.
 */
import { EngineDisplayText } from "./displayText";
import type { EnginePrompt, MatchPoll } from "./engineClient";
import { arr, at, bool, EngineError, get, int, isUuid, type J, type JObject, obj, str } from "./json";
import {
  capitalizedWords, decodeLegalAction, decodePlayer, decodeXmage, type GameLogEntry, type GameSnapshot, XmageIcons, type ZoneCard,
} from "./models";
import { OnDevicePromptAdapter } from "./promptAdapter";
import { printedManaCost } from "./snapshotCard";

const sortedEntries = (value: J | undefined): [string, J][] => Object.entries(obj(value) ?? {}).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
const cardValues = (value: J | undefined): J[] => arr(value) ?? sortedEntries(value).map(([, item]) => item);
const stringsOf = (value: J | undefined): string[] => (arr(value) ?? []).filter((s): s is string => typeof s === "string");
const colorNames: [string, string][] = [["white", "W"], ["blue", "U"], ["black", "B"], ["red", "R"], ["green", "G"]];

/** Swift `NativeDeckArtwork.permitsSourceName`. */
export const permitsSourceName = (name: string) =>
  !["", "hidden card", "face-down card", "face down card", "face-down", "face down", "card details unavailable"].includes(name.trim().toLowerCase());

const card = (value: J): J => {
  const id = str(get(value, "id"));
  if (!isUuid(id)) throw EngineError.invalid("Card view has no engine UUID");
  // Do not consult original, source images, or a catalogue to undo an upstream redaction.
  // A face-down card its owner may look at carries the real card as `secondCardFace` (CardView: "Face Down: <name>");
  // anyone else gets the face-down placeholder.
  const faceDown = bool(get(value, "faceDown")) === true;
  const second = get(value, "secondCardFace");
  const ownFace = faceDown && bool(get(value, "hideInfo")) !== true && str(get(second, "name")) !== undefined ? second : undefined;
  const hidden = bool(get(value, "hideInfo")) === true || (faceDown && ownFace === undefined);
  const face = ownFace ?? value;
  const name = hidden ? "Face-down card" : str(get(face, "displayName")) ?? str(get(face, "name")) ?? "Card details unavailable";
  const strings = (key: string) => (hidden ? [] : stringsOf(get(face, key)));
  let typeLine = [...strings("superTypes"), ...strings("cardTypes")].map(capitalizedWords).join(" ");
  const subs = strings("subTypes");
  if (subs.length > 0) typeLine += " — " + subs.map(capitalizedWords).join(" ");
  const rules = hidden ? "" : stringsOf(get(face, "rules")).join("\n");
  const tokenIdentityVisible = !hidden && bool(get(value, "faceDown")) !== true;
  const isToken = bool(get(value, "isToken")) === true;
  const hasTokenColors = tokenIdentityVisible && isToken && colorNames.every(([color]) => bool(at(value, "color", color)) !== undefined);
  const tokenColors: J = hasTokenColors ? colorNames.filter(([color]) => bool(at(value, "color", color)) === true).map(([, s]) => s) : null;
  const sourceArt: J = tokenIdentityVisible && isToken && bool(get(value, "copy")) === true && str(get(value, "copySourceArtworkName")) === name &&
    str(get(value, "name")) === name && permitsSourceName(name) ? name : null;
  const template = get(value, "tokenArtwork");
  const baseName = str(get(template, "name"));
  const baseStrings = (key: string) => stringsOf(get(template, key));
  const hasBaseColors = colorNames.every(([color]) => bool(at(template, "color", color)) !== undefined);
  const baseColors = colorNames.filter(([color]) => bool(at(template, "color", color)) === true).map(([, s]) => s);
  let baseTypeLine = [...baseStrings("superTypes"), ...baseStrings("cardTypes")].map(capitalizedWords).join(" ");
  const baseSubs = baseStrings("subTypes");
  if (baseSubs.length > 0) baseTypeLine += " — " + baseSubs.map(capitalizedWords).join(" ");
  const baseArt: J = tokenIdentityVisible && isToken && baseName === name && hasBaseColors && baseTypeLine.length > 0 &&
    arr(get(template, "rules")) !== undefined && str(get(template, "power")) !== undefined && str(get(template, "toughness")) !== undefined
    ? {
      name, typeLine: baseTypeLine, oracleText: baseStrings("rules").join("\n"),
      power: get(template, "power") ?? null, toughness: get(template, "toughness") ?? null, colors: baseColors,
    } : null;
  const result: JObject = {
    instanceId: id,
    card: {
      name, typeLine, oracleText: rules, manaCost: (ownFace !== undefined ? printedManaCost(ownFace) : undefined) ?? printedManaCost(value) ?? null,
      faceDown: ownFace !== undefined ? true : null,
      isToken: tokenIdentityVisible ? bool(get(value, "isToken")) ?? null : null,
      tokenColors, copySourceArtworkName: sourceArt, tokenArtwork: baseArt,
    },
  };
  for (const key of ["tapped", "summoningSickness", "damage", "phasedIn"]) {
    const item = get(value, key);
    if (item !== undefined) result[key] = item;
  }
  const attached = get(value, "attachedTo");
  if (attached !== undefined) result.attachedToInstanceId = attached;
  result.cardIcons = (arr(get(value, "cardIcons")) ?? []).map((icon) => {
    const type = str(get(icon, "cardIconType")) ?? "";
    return {
      iconType: get(icon, "cardIconType") ?? "", category: get(icon, "category") ?? XmageIcons.nativeCategory(type) ?? null,
      resourceName: get(icon, "resourceName") ?? null, text: get(icon, "text") ?? null, hint: get(icon, "hint") ?? null,
    };
  });
  if (!hidden) {
    const power = str(get(value, "power"));
    if (power) result.reportedPower = power;
    const toughness = str(get(value, "toughness"));
    if (toughness) result.reportedToughness = toughness;
  }
  const counters = arr(get(value, "counters"));
  if (counters) {
    const mapped: JObject = {};
    for (const counter of counters) {
      const counterName = str(get(counter, "name"));
      if (counterName !== undefined) mapped[counterName] = get(counter, "count") ?? null;
    }
    result.counters = mapped;
  }
  return result;
};

const cards = (value: J | undefined): J[] => cardValues(value).map(card);

/** Combat membership comes only from the public GameView groups, never card-type guesses. */
const combatCards = (list: J[], groups: J | undefined): J[] => list.map((item) => {
  const id = str(get(item, "instanceId"));
  const fields = obj(item);
  if (id === undefined || !fields) return item;
  let attacking = false;
  const blocking = new Set<string>();
  for (const group of arr(groups) ?? []) {
    const attackers = cardValues(get(group, "attackers")).map((a) => str(get(a, "id"))).filter((a): a is string => a !== undefined);
    attacking = attacking || attackers.includes(id);
    if (cardValues(get(group, "blockers")).some((b) => str(get(b, "id")) === id)) attackers.forEach((a) => blocking.add(a));
  }
  return { ...fields, isAttacking: attacking, blocking: [...blocking].sort() };
});

const namedZones = (value: J | undefined, prefix: string): J[] => (arr(value) ?? []).map((zone, index) => ({
  id: get(zone, "id") ?? `${prefix}:${index}`, name: get(zone, "name") ?? capitalizedWords(prefix), cards: cards(get(zone, "cards")),
}));

const disclosedGroups = (value: J | undefined, prefix: string): J[] =>
  sortedEntries(value).map(([name, contents]) => ({ id: `${prefix}:${name}`, name, cards: cards(contents) }));

const manaPool = (value: J | undefined): J => {
  const result: JObject = {};
  for (const [symbol, name] of [["W", "white"], ["U", "blue"], ["B", "black"], ["R", "red"], ["G", "green"], ["C", "colorless"]]) {
    result[symbol] = get(value, name) ?? 0;
  }
  return result;
};

/**
 * XMage shortens playable-ability labels ("… only to cast a crea..."). When the shortened text
 * starts exactly one line of the card's visible rules, show that whole line.
 */
export const fullAbilityLabel = (raw: string, rules: string | undefined): string => {
  const label = EngineDisplayText.label(raw);
  let stem: string;
  if (label.endsWith("...")) stem = label.slice(0, -3);
  else if (label.endsWith("…")) stem = label.slice(0, -1);
  else return label;
  stem = stem.trim();
  if (stem.length < 4 || rules === undefined) return label;
  const lines = rules.split(/[\n\r]/).filter((line) => line.length > 0).map((line) => EngineDisplayText.label(line));
  const matches = lines.filter((line) => line.length > stem.length && line.startsWith(stem));
  return matches.length === 1 ? matches[0] : label;
};

const playableObjects = (view: J | undefined, players: J[], extraZones: [string, J[]][], prompt: EnginePrompt | undefined,
  viewer: string): [J[], J[]] => {
  const objects: J[] = [];
  const actions: J[] = [];
  const known = new Map<string, [J, string]>();
  for (const player of players) {
    for (const [zone, contents] of Object.entries(obj(get(player, "zones")) ?? {})) {
      for (const item of arr(contents) ?? []) {
        const id = str(get(item, "instanceId"));
        if (id !== undefined) known.set(id, [item, zone]);
      }
    }
  }
  for (const [zone, list] of extraZones) for (const item of list) {
    const id = str(get(item, "instanceId"));
    if (id !== undefined && !known.has(id)) known.set(id, [item, zone]);
  }
  const categories: [string, string][] = [["basicPlayAbilities", "play_land"], ["basicCastAbilities", "cast_spell"],
    ["basicManaAbilities", "make_mana"], ["other", "activate_ability"]];
  for (const [id, stats] of sortedEntries(at(view, "canPlayObjects", "objects"))) {
    const entry = known.get(id);
    if (!entry) continue;
    const [cardValue, zone] = entry;
    const abilities: J[] = [];
    const activeCategories: J[] = [];
    for (const [category, commandType] of categories) {
      const rows = arr(get(stats, category)) ?? [];
      if (rows.length > 0) activeCategories.push(category);
      for (const row of rows) {
        const abilityID = str(get(row, "id")); const label = str(get(row, "value"));
        if (abilityID === undefined || label === undefined) throw EngineError.invalid("Incomplete engine playable ability");
        abilities.push({ id: abilityID, label: EngineDisplayText.label(label), category });
      }
      if (rows.length === 0 || prompt === undefined || prompt.submitted || !prompt.responseTypes.includes("uuid")) continue;
      const priority = prompt.kind === "SELECT" && str(prompt.payload.selectMode) === "priority";
      const paying = prompt.kind === "PLAY_MANA" || prompt.kind === "PLAY_X_MANA";
      // New native payloads distinguish mana abilities inside `other`. Never guess from a label.
      const isMana = (row: J) => bool(get(row, "manaAbility")) ?? category === "basicManaAbilities";
      const isSpell = (row: J) => bool(get(row, "spellAbility")) ?? category === "basicCastAbilities";
      const manaRows = rows.filter(isMana);
      const nonmanaRows = rows.filter((row) => !isMana(row));
      const spellRows = nonmanaRows.filter(isSpell);
      const otherRows = nonmanaRows.filter((row) => !isSpell(row));
      for (const [actionType, actionRows] of [["make_mana", manaRows], ["cast_spell", spellRows], [commandType, otherRows]] as [string, J[]][]) {
        if (actionRows.length === 0 || !(priority || (paying && actionType === "make_mana"))) continue;
        const baseID = `${prompt.id}:${category}:${id}` + (actionType === commandType ? "" : `:${actionType}`);
        // One action per ability, carrying the engine's ability ID so the session can answer XMage's
        // follow-up "which ability" prompt (MDFC land/spell, split halves, adventures) itself.
        for (const row of actionRows) {
          const abilityID = str(get(row, "id"))!;
          actions.push({
            id: actionRows.length > 1 ? `${baseID}:${abilityID}` : baseID, type: actionType, playerId: viewer,
            label: fullAbilityLabel(str(get(row, "value"))!, str(at(cardValue, "card", "oracleText"))),
            cardInstanceId: id, sourceInstanceId: id, sourceZone: zone, cardName: at(cardValue, "card", "name") ?? "Card",
            promptId: prompt.id, messageId: prompt.revision, abilityId: abilityID,
          });
        }
      }
    }
    if (abilities.length > 0) {
      objects.push({ sourceInstanceId: id, sourceZone: zone, cardName: at(cardValue, "card", "name") ?? "Card", categories: activeCategories, abilities });
    }
  }
  return [objects, actions];
};

/** Day or night and the storm count, read from XMage's helper emblems (their hint lines). */
const tableHints = (emblems: J | undefined): [string | undefined, number | undefined] => {
  let dayNight: string | undefined;
  let storm: number | undefined;
  for (const emblem of Object.values(obj(emblems) ?? {})) {
    for (const rule of stringsOf(get(emblem, "rules"))) {
      const text = rule.replace(/<[^>]+>/g, "").trim();
      if (text.startsWith("It's currently day")) dayNight = "day";
      else if (text.startsWith("It's currently night")) dayNight = "night";
      else if (text.startsWith("Spells cast this turn:")) {
        const count = text.slice("Spells cast this turn:".length).trim();
        if (/^[+-]?\d+$/.test(count)) storm = Number.parseInt(count, 10);
      }
    }
  }
  return [dayNight, storm];
};

export const OnDeviceSnapshotAdapter = {
  snapshot(poll: MatchPoll, expectedSeatID: string, log: GameLogEntry[] = []): GameSnapshot {
    const root = poll.snapshot;
    const view = get(root, "gameView");
    const viewer = str(get(root, "enginePlayerId"));
    const rawPlayers = arr(get(view, "players"));
    if (poll.seatID !== expectedSeatID || root === undefined || str(get(root, "schema")) !== "xmage-gameview-v1" || view === undefined ||
      !isUuid(viewer) || str(get(view, "myPlayerId")) !== viewer || rawPlayers === undefined || rawPlayers.length < 2 || rawPlayers.length > 4) {
      throw EngineError.invalid("Missing or mismatched seat-scoped game view");
    }
    const ids = rawPlayers.map((p) => str(get(p, "playerId"))).filter((id): id is string => id !== undefined);
    if (ids.length !== rawPlayers.length || new Set(ids).size !== ids.length || !ids.includes(viewer) || !ids.every(isUuid)) {
      throw EngineError.invalid("Invalid engine player identities");
    }
    const combatGroups = get(view, "combat");
    const players: J[] = [];
    const enginePlayers: J[] = [];
    for (const player of rawPlayers) {
      const id = str(get(player, "playerId"))!;
      if (int(get(player, "life")) === undefined || int(get(player, "handCount")) === undefined || int(get(player, "libraryCount")) === undefined ||
        str(get(player, "name")) === undefined) throw EngineError.invalid("Incomplete player state");
      const hand = id === viewer ? get(view, "myHand") : at(root, "controlledPlayerViews", id, "myHand");
      const zones: JObject = {};
      for (const zone of ["battlefield", "graveyard", "exile"]) {
        const mapped = cards(get(player, zone));
        zones[zone] = zone === "battlefield" ? combatCards(mapped, combatGroups) : mapped;
      }
      zones.command = cards(get(player, "commandList"));
      zones.hand = cards(hand);
      // Only a revealed top card is ever visible; the rest of the library stays face down.
      const top = get(player, "topCard");
      zones.library = top === undefined || top === null ? [] : [card(top)];
      zones.stack = [];
      zones.handCount = get(player, "handCount") ?? null;
      zones.libraryCount = get(player, "libraryCount") ?? null;
      const poison = (arr(get(player, "counters")) ?? []).find((c) => str(get(c, "name"))?.toLowerCase() === "poison");
      const poisonCount = get(poison, "count") ?? 0;
      const commanders: J[] = [];
      for (const [cardID, metadata] of sortedEntries(get(root, "commanders"))) {
        const fields = obj(metadata);
        if (str(get(metadata, "ownerPlayerId")) !== id || !fields) continue;
        const copy: JObject = { ...fields, id: cardID };
        if (copy.name === undefined) {
          const visible = Object.values(zones).flatMap((z) => arr(z) ?? []).find((c) => str(get(c, "instanceId")) === cardID);
          const visibleName = at(visible, "card", "name");
          if (visibleName !== undefined) copy.name = visibleName;
        }
        commanders.push(copy);
      }
      // Partners have independent tax and damage. Never combine them into one HUD value.
      const singleCommander = commanders.length === 1 ? commanders[0] : undefined;
      const counters: JObject = {};
      for (const counter of arr(get(player, "counters")) ?? []) {
        const counterName = str(get(counter, "name")); const count = int(get(counter, "count"));
        if (counterName !== undefined && count !== undefined) counters[counterName] = count;
      }
      const fields: JObject = {
        playerId: id, displayName: get(player, "name")!, life: get(player, "life")!, poison: poisonCount,
        commanderTax: get(singleCommander, "commanderTax") ?? 0, counters,
        monarch: get(player, "monarch") ?? null, initiative: get(player, "initiative") ?? null,
        commanderTaxKnown: int(get(singleCommander, "commanderTax")) !== undefined,
        commanderDamage: get(singleCommander, "damageToPlayers") ?? null, commanders,
        manaPool: manaPool(get(player, "manaPool")), zones,
        hasLeft: get(player, "hasLeft") ?? false, isHuman: get(player, "isHuman") ?? null, designations: get(player, "designationNames") ?? [],
      };
      players.push(fields);
      const skips: JObject = {};
      for (const key of ["passedTurn", "passedUntilEndOfTurn", "passedUntilNextMain", "passedUntilStackResolved", "passedAllTurns", "passedUntilEndStepBeforeMyTurn"]) {
        skips[key] = get(player, key) ?? false;
      }
      enginePlayers.push({
        playerId: id, xmagePlayerId: id, name: get(player, "name")!, active: get(player, "isActive") ?? false,
        hasPriority: get(player, "hasPriority") ?? false, timerActive: get(player, "timerActive") ?? false, skipState: skips,
        manaPool: manaPool(get(player, "manaPool")), command: zones.command,
        zones: { battlefield: zones.battlefield, graveyard: zones.graveyard, exile: zones.exile, sideboard: cards(get(player, "sideboard")) },
      });
    }
    const stackMap = obj(get(view, "stack")) ?? {};
    const stackKeys = Object.keys(stackMap);
    const suppliedOrder = arr(get(root, "stackOrder"));
    const order = suppliedOrder ? suppliedOrder.filter((s): s is string => typeof s === "string")
      : stackKeys.length <= 1 ? stackKeys : [];
    if (order.length !== stackKeys.length || new Set(order).size !== stackKeys.length || !order.every((id) => id in stackMap)) {
      throw EngineError.invalid("The engine did not supply an unambiguous stack order");
    }
    const stack: J[] = order.map((id) => {
      const item = stackMap[id];
      const isSpell = str(get(item, "mageObjectType")) === "SPELL";
      const source = get(item, "sourceCard") ?? (isSpell ? item : null);
      const fields: JObject = {
        id, objectId: id, objectType: get(item, "mageObjectType") ?? null,
        name: get(item, "displayName") ?? get(item, "name") ?? "Stack object",
        rulesText: stringsOf(get(item, "rules")).join("\n"), targetIds: get(item, "targets") ?? [], paid: get(item, "paid") ?? null,
        controllerId: at(root, "stackControllers", id) ?? null,
      };
      if (source !== null) {
        fields.sourceCard = card(source);
        const sourceName = get(source, "displayName") ?? get(source, "name");
        if (sourceName !== undefined) fields.sourceName = sourceName;
        // A spell's stack UUID is not necessarily its physical card UUID.
        const sourceID = get(source, "id");
        if (!isSpell && sourceID !== undefined) fields.sourceInstanceId = sourceID;
      }
      return fields;
    });
    const combat: J[] = (arr(combatGroups) ?? []).map((group, index) => {
      // An attacked planeswalker or battle that leaves combat leaves its attackers attacking nothing.
      const missing = str(get(group, "defenderId")) === undefined;
      const defender = str(get(group, "defenderId")) ?? `no-defender-${index}`;
      const kind: J = missing ? "none" : ids.includes(defender) ? "player" : null;
      const name: J = missing ? "No defender" : get(group, "defenderName") ?? defender;
      return {
        defenderId: defender, defenderName: name, defenderKind: kind, blocked: get(group, "isBlocked") ?? false,
        attackers: combatCards(cards(get(group, "attackers")), combatGroups), blockers: combatCards(cards(get(group, "blockers")), combatGroups),
      };
    });
    const exileZones = namedZones(get(root, "namedExiles"), "exile");
    const revealed = namedZones(get(view, "revealed"), "revealed");
    const companions = namedZones(get(view, "companion"), "companion");
    const lookedAt = [...disclosedGroups(get(root, "authorizedLookedAt"), "looked-at"), ...disclosedGroups(get(root, "authorizedOpponentHands"), "controlled-hand")];
    const extraZones: [string, J[]][] = [
      ...([["exile", exileZones], ["revealed", revealed], ["looked_at", lookedAt], ["companion", companions]] as [string, J[]][])
        .map(([zoneName, groups]): [string, J[]] => [zoneName, groups.flatMap((g) => arr(get(g, "cards")) ?? [])]),
      ["stack", stack.map((s) => get(s, "sourceCard")).filter((c): c is J => c !== undefined)],
    ];
    const [playable, cardActionValues] = playableObjects(view, players, extraZones, poll.prompt, viewer);
    const xmage = decodeXmage({
      schemaVersion: 1, gameId: poll.matchID, bridgeRevision: poll.revision, xmageCycle: get(view, "gameCycle") ?? null,
      callbackCoverage: [], players: enginePlayers, stack, combat, exileZones, revealed, lookedAt, companion: companions,
      playableObjects: playable,
      panels: {
        stack: stack.length > 0, command: true, graveyard: true, exile: true, revealed: revealed.length > 0,
        lookedAt: lookedAt.length > 0, search: lookedAt.length > 0,
      },
    });
    const priority = str(get(rawPlayers.find((p) => bool(get(p, "hasPriority")) === true), "playerId"));
    const decodedPlayers = players.map(decodePlayer);
    const allCards: ZoneCard[] = [
      ...decodedPlayers.flatMap((p) => [...p.zones.hand, ...p.zones.battlefield, ...p.zones.graveyard, ...p.zones.exile, ...p.zones.command, ...p.zones.library]),
      ...xmage.stack.map((s) => s.sourceCard).filter((c): c is ZoneCard => c !== undefined),
      ...[...xmage.exileZones, ...xmage.revealed, ...xmage.lookedAt, ...xmage.companion].flatMap((z) => z.cards),
    ];
    const prompt = poll.prompt && !poll.prompt.submitted ? poll.prompt : undefined;
    let presentation;
    if (prompt) {
      let attackerID: string | undefined;
      if (prompt.kind === "SELECT" && str(prompt.payload.selectMode) === "attackers") {
        const active = str(get(view, "activePlayerId"));
        const controlled = at(root, "controlledPlayerViews", active ?? "");
        if (active === undefined || !ids.includes(active) ||
          !(active === viewer || (str(get(controlled, "myPlayerId")) === active && str(get(controlled, "activePlayerId")) === active))) {
          throw EngineError.invalid("Missing or unauthorized acting attacker identity");
        }
        attackerID = active;
      }
      presentation = OnDevicePromptAdapter.presentation(prompt, viewer, allCards, decodedPlayers, attackerID);
    }
    const cardActions = cardActionValues.map(decodeLegalAction);
    const [dayNight, stormCount] = tableHints(get(view, "myHelperEmblems"));
    const winners = arr(at(root, "outcome", "winnerPlayerIds"));
    return {
      id: poll.matchID, source: "xmage-ondevice", activePlayerId: str(get(view, "activePlayerId")),
      phase: str(get(view, "phase")) ?? poll.phase, step: str(get(view, "step")), turn: int(get(view, "turn")) ?? 0,
      priorityPlayerId: priority, waitingOnPlayerId: prompt === undefined ? undefined : viewer, promptText: presentation?.envelope.message,
      players: decodedPlayers, log, legalActions: [...cardActions, ...(presentation?.legalActions ?? [])],
      promptEnvelopeV2: presentation?.envelope, xmage, bridgeRevision: poll.revision, xmageCycle: int(get(view, "gameCycle")),
      pendingStatus: poll.prompt?.submitted === true ? "waiting_for_xmage" : undefined, manaPayment: presentation?.manaPayment,
      gameStatus: bool(at(root, "outcome", "ended")) === true ? "completed" : "in_progress",
      winnerPlayerIds: winners?.filter((w): w is string => typeof w === "string"), viewerPlayerId: viewer, dayNight, stormCount,
    };
  },
};
