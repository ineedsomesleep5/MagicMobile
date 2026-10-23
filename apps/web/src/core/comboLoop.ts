/**
 * The combo loop shortcut (iOS ComboLoop.swift, Android ComboLoop.kt; roadmap release B): after the player makes the same
 * sequence of choices three times in a row in one turn, the app offers to repeat it. Each repeat is an ordinary answer the
 * engine checks, so no rule is skipped; the repeats stop the moment anything differs. Steps are kept by meaning, never by
 * ids (a token made by the loop has a new id each time round): an action by its card's name and text, a choice by the kind
 * of thing chosen (yours or an opponent's, creature or artifact, token or card), with the name as the first preference.
 * Passing priority is not a step: before a step that was taken with an empty stack, the repeats let the player's own
 * triggers resolve first. Checked by test/comboLoop.test.ts (parity/combo-loop-cases.json and the iOS ComboLoopTests).
 */
import { isLandCard } from "./boardEvents";
import {
  type AttackDeclaration, type BlockDeclaration, type CardIdentity, type GameCommand, type GameSnapshot, isOut, type LegalAction,
  type PromptEnvelopeV2, viewerID,
} from "./models";

/** Swift `GameCommand` fields the web model leaves out; a step records them and a replay sends them back. */
export interface ComboCommand extends GameCommand {
  manaTypes?: string[]; pay?: boolean; useCommandZone?: boolean; sourceZone?: string; fromZone?: string; cardName?: string;
  attackers?: AttackDeclaration[]; blockers?: BlockDeclaration[];
}

const isViewer = (snapshot: GameSnapshot, playerID: string | undefined) => playerID === viewerID(snapshot);
const visibleHandCount = (zones: GameSnapshot["players"][number]["zones"]) => zones.handCount ?? zones.hand.length;
const visibleLibraryCount = (zones: GameSnapshot["players"][number]["zones"]) => zones.libraryCount ?? zones.library.length;
/** Swift Optional array equality: both absent, or the same items in order. */
const sameList = <T>(a: readonly T[] | undefined, b: readonly T[] | undefined) =>
  a === undefined || b === undefined ? a === b : a.length === b.length && a.every((item, index) => item === b[index]);
const byKey = <V>(record: Record<string, V>) => Object.entries(record).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));

// ---- ComboTarget ----

/**
 * Something chosen in a step. Two choices are the same kind when they belong to the same side, are the same sort of
 * object and are both tokens or both cards; the name is only a preference (options like modes keep their name).
 */
export interface ComboTarget {
  name: string;
  /** "you", "opponent", or "" for options that belong to nobody (modes, choices). */
  controller: string;
  /** "creature", "planeswalker", "artifact", "enchantment", "land", "player", "card" or "option". */
  kind: string;
  token: boolean;
}

export const ComboTarget = {
  make: (name: string, controller = "", kind = "option", token = false): ComboTarget => ({ name, controller, kind, token }),
  /** Swift `==`: the same kind of thing; the name counts only for options. */
  equals: (lhs: ComboTarget, rhs: ComboTarget) =>
    lhs.controller === rhs.controller && lhs.kind === rhs.kind && lhs.token === rhs.token && (lhs.kind !== "option" || lhs.name === rhs.name),
  /** Swift `hash(into:)`: equal targets share a key. */
  key: (target: ComboTarget) => JSON.stringify([target.controller, target.kind, target.token, ...(target.kind === "option" ? [target.name] : [])]),
  /** Words for messages and the preview: "a Squirrel token", "an opponent's creature". */
  phrase(target: ComboTarget): string {
    switch (target.kind) {
      case "option": case "player": return target.name;
      default:
        if (target.controller === "opponent") return target.token ? `an opponent's ${target.kind} token` : `an opponent's ${target.kind}`;
        return target.token ? `a ${target.name} token` : `your ${target.name}`;
    }
  },
};

// ---- ComboStep ----

/** A legal action from the board (cast, activate, play, tap for mana), or an answer to a prompt. */
export type ComboStepKind = "action" | "prompt";

export interface ComboStep {
  kind: ComboStepKind;
  type: string;
  /** The source card's name, for actions. */
  source?: string;
  /** The action's text, normalized; for prompts, the prompt's method (GAME_TARGET, GAME_ASK, ...). */
  label: string;
  /** What was chosen, in order. */
  targets: ComboTarget[];
  amount?: number;
  amounts?: number[];
  pile?: number;
  manaTypes?: string[];
  confirmed?: boolean;
  pay?: boolean;
  useCommandZone?: boolean;
  /** Taken with nothing on the stack: the repeats let the player's own triggers resolve before this step. */
  stackEmpty: boolean;
  /** Mana an action makes, for tapping another source of the same mana when the original is gone. */
  producedMana?: string[];
}

export const ComboStep = {
  make: (kind: ComboStepKind, type: string, source: string | undefined, label: string, targets: ComboTarget[] = [],
    rest: Partial<Omit<ComboStep, "kind" | "type" | "source" | "label" | "targets">> = {}): ComboStep =>
    ({ kind, type, source, label, targets, stackEmpty: false, ...rest }),
  /** Swift `==`: the same step, whatever the stack and the exact mana source looked like. */
  equals: (lhs: ComboStep, rhs: ComboStep) =>
    lhs.kind === rhs.kind && lhs.type === rhs.type && lhs.source === rhs.source && lhs.label === rhs.label
    && lhs.targets.length === rhs.targets.length && lhs.targets.every((target, index) => ComboTarget.equals(target, rhs.targets[index]))
    && lhs.amount === rhs.amount && sameList(lhs.amounts, rhs.amounts) && lhs.pile === rhs.pile && sameList(lhs.manaTypes, rhs.manaTypes)
    && lhs.confirmed === rhs.confirmed && lhs.pay === rhs.pay && lhs.useCommandZone === rhs.useCommandZone,
  /** Swift `hash(into:)`: equal steps share a key. */
  key: (step: ComboStep) => JSON.stringify([step.kind, step.type, step.source ?? null, step.label, step.targets.map(ComboTarget.key)]),
};

// ---- ComboRepeat ----

/** How many rounds to repeat. */
export type ComboRepeat =
  | { kind: "times"; count: number }
  /** Until a step can't be taken any more: a normal finish. */
  | { kind: "untilCant" }
  /** Until every opponent has lost. */
  | { kind: "untilWin" };

export const ComboRepeat = {
  times: (count: number): ComboRepeat => ({ kind: "times", count }),
  untilCant: { kind: "untilCant" } as ComboRepeat,
  untilWin: { kind: "untilWin" } as ComboRepeat,
  count: (repeat: ComboRepeat): number | undefined => (repeat.kind === "times" ? repeat.count : undefined),
  /** Small counts play their effects at a pace you can follow; long runs go fast and show the board once a round. */
  watchable: (repeat: ComboRepeat) => (ComboRepeat.count(repeat) ?? Infinity) <= ComboLoop.watchableRounds,
};

// ---- ComboNote ----

/** What a player's answer means for spotting loops. */
export type ComboNote =
  | { kind: "step"; step: ComboStep }
  /** Not part of a round (passing priority): neither recorded nor breaking the rounds around it. */
  | { kind: "ignore" }
  /** Never part of a loop (combat, the opening): the rounds start over. */
  | { kind: "breaks" };

export const ComboNote = {
  step: (step: ComboStep): ComboNote => ({ kind: "step", step }),
  ignore: { kind: "ignore" } as ComboNote,
  breaks: { kind: "breaks" } as ComboNote,
};

// ---- ComboReplay ----

/** The answer a step makes now, and what it chose (so the next round can keep the same target). */
export interface ComboReplay {
  command: ComboCommand;
  label: string;
  actionID: string;
  chosenNames: string[];
  /** A target was gone and another of the same kind was chosen ("Kinjalli's Caller" → "Zacama"). */
  retargeted?: { from: string; to: string };
}

// ---- PromptCommandBuilder (the part ComboLoop uses) ----

/** Swift `Int(String)`: an optional sign and digits, nothing else. */
const swiftInt = (value: string | undefined): number | undefined => (value !== undefined && /^[+-]?[0-9]+$/.test(value) ? Number(value) : undefined);
const exactManaSymbol = (value: string | undefined) => (value !== undefined && ["W", "U", "B", "R", "G", "C"].includes(value) ? value : undefined);
const boolChoice = (value: string | undefined): boolean | undefined => {
  if (value === undefined) return undefined;
  const normalized = value.trim().toLowerCase();
  if (["true", "yes"].includes(normalized)) return true;
  if (["false", "no"].includes(normalized)) return false;
  return undefined;
};
const resolvedMessageId = (prompt: PromptEnvelopeV2 | undefined, promptId: string) => {
  if (!prompt) return undefined;
  if (prompt.id === promptId || prompt.responseCommand?.promptId === promptId) return prompt.responseCommand?.messageId ?? prompt.messageId;
  return undefined;
};

/** iOS PromptCommandBuilder.command: the answer of `type` to a prompt, or undefined when the values don't make one. */
function promptCommand(gameId: string, prompt: PromptEnvelopeV2 | undefined, rawType: string, promptId: string, playerId: string,
  options: { ids?: string[]; amount?: number; amounts?: number[]; pile?: number; useCommandZone?: boolean; manaType?: string; pay?: boolean } = {},
): ComboCommand | undefined {
  const ids = options.ids ?? [];
  const type = rawType.toLowerCase();
  const base = { type, gameId, playerId, promptId, messageId: resolvedMessageId(prompt, promptId) };
  switch (type) {
    case "resolve_choice": return { ...base, choiceIds: ids };
    case "choose_target": return { ...base, targetIds: ids };
    case "choose_card": return { ...base, cardInstanceIds: ids };
    case "choose_player": return { ...base, playerIds: ids };
    case "choose_mode": return { ...base, modeIds: ids };
    case "choose_ability": {
      const abilityId = ids[0];
      return abilityId === undefined ? undefined : { ...base, abilityId };
    }
    case "choose_pile": {
      const pile = options.pile ?? swiftInt(ids[0]);
      return pile === undefined || ![1, 2].includes(pile) ? undefined : { ...base, pile };
    }
    case "choose_amount": case "play_x_mana": {
      const amount = options.amount ?? swiftInt(ids[0]);
      return amount === undefined ? undefined : { ...base, amount };
    }
    case "choose_multi_amount": {
      const amounts = options.amounts ?? ids.map(swiftInt).filter((value): value is number => value !== undefined);
      return amounts.length === 0 || !(options.amounts !== undefined || amounts.length === ids.length) ? undefined : { ...base, amounts };
    }
    case "play_mana": {
      const manaType = exactManaSymbol(options.manaType);
      return manaType === undefined ? undefined : { ...base, manaType };
    }
    case "choose_mana": {
      const choices = options.manaType !== undefined ? [options.manaType] : ids;
      const exact = choices.map(exactManaSymbol).filter((value): value is string => value !== undefined);
      return exact.length === 0 || exact.length !== choices.length ? undefined : { ...base, manaTypes: exact };
    }
    case "search_select": return { ...base, cardInstanceIds: ids };
    case "order_triggers": case "order_items": return { ...base, orderedIds: ids };
    case "commander_replacement":
      return options.useCommandZone === undefined ? undefined : { ...base, useCommandZone: options.useCommandZone };
    case "pay_cost": {
      const shouldPay = options.pay ?? boolChoice(ids[0]);
      return shouldPay === undefined ? undefined : { ...base, confirmed: shouldPay, pay: shouldPay };
    }
    case "answer_yes_no": {
      const confirmed = boolChoice(ids[0]);
      return confirmed === undefined ? undefined : { ...base, confirmed };
    }
    default: return undefined;
  }
}

// ---- ComboLoop ----

/** Everything nameable by id: a card's name, whose it is, what sort of thing it is, and token or card. */
export interface ComboKnown { name: string; controller: string; kind: string; token: boolean }

const comboTypes = new Set(["activate_ability", "cast_spell"]);
const ignoredTypes = new Set(["pass_priority"]);
const excludedTypes = new Set(["declare_attackers", "declare_blockers", "mulligan", "keep_hand", "concede", "commander_replacement",
  "choose_starting_player"]);
/** Swift `Character.isWhitespace`: the Unicode White_Space set. */
const whitespace = new RegExp("[\\t\\n\\v\\f\\r \\u0085\\u00A0\\u1680\\u2000-\\u200A\\u2028\\u2029\\u202F\\u205F\\u3000]+");

const sourceName = (action: LegalAction, known: Map<string, ComboKnown>) => {
  const id = action.sourceInstanceId ?? action.cardInstanceId;
  return (id !== undefined ? known.get(id)?.name : undefined) ?? action.cardName;
};

export const ComboLoop = {
  /** How many identical rounds in a row make a loop worth offering. */
  repeatsToOffer: 3,
  /** The longest loop looked for, in steps. */
  maxCycleLength: 12,
  /** Steps remembered for spotting loops. */
  historyLimit: 48,
  /** The most rounds one shortcut runs, whatever was asked. */
  maxRepeats: 300,
  /** The count picker starts here. */
  pickerDefault: 5,
  /** Up to this many rounds play their effects, at a pace you can follow. */
  watchableRounds: 10,
  /** Open-ended repeats stop when this many rounds in a row change nothing visible. */
  unchangedRoundsToStop: 3,

  normalized: (label: string) => label.toLowerCase().split(whitespace).filter((part) => part.length > 0).join(" "),

  // What things are

  kind(card: CardIdentity): string {
    const type = card.typeLine.toLowerCase();
    for (const kind of ["creature", "planeswalker", "artifact", "enchantment", "land"]) if (type.includes(kind)) return kind;
    return "card";
  },

  /** Everything nameable by id: cards in every visible zone (with whose they are), players, and the prompt's options. */
  known(snapshot: GameSnapshot): Map<string, ComboKnown> {
    const known = new Map<string, ComboKnown>();
    for (const player of snapshot.players) {
      const side = isViewer(snapshot, player.playerId) ? "you" : "opponent";
      known.set(player.playerId, { name: side === "you" ? "You" : (player.displayName ?? player.playerId), controller: side, kind: "player", token: false });
      const zones = player.zones;
      for (const card of [...zones.battlefield, ...zones.hand, ...zones.graveyard, ...zones.exile, ...zones.command, ...zones.stack, ...zones.library]) {
        known.set(card.instanceId, { name: card.card.name, controller: side, kind: ComboLoop.kind(card.card), token: card.card.isToken === true });
      }
    }
    for (const object of snapshot.xmage?.stack ?? []) {
      const id = object.sourceInstanceId;
      if (id !== undefined && !known.has(id) && object.sourceName !== undefined) known.set(id, { name: object.sourceName, controller: "", kind: "card", token: false });
    }
    const prompt = snapshot.promptEnvelopeV2;
    if (prompt) {
      for (const option of [...(prompt.targets ?? []), ...(prompt.choices ?? []), ...(prompt.modes ?? []), ...(prompt.orderedItems ?? [])]) {
        if (known.has(option.id)) continue;
        const card = option.cardInstanceId !== undefined ? known.get(option.cardInstanceId) : undefined;
        if (card) { known.set(option.id, card); continue; }
        known.set(option.id, { name: option.label, controller: "", kind: "option", token: false });
      }
      for (const card of prompt.cards ?? []) {
        if (known.has(card.instanceId)) continue;
        known.set(card.instanceId, { name: card.card.name, controller: "", kind: ComboLoop.kind(card.card), token: card.card.isToken === true });
      }
      for (const player of prompt.players ?? []) {
        if (known.has(player.playerId)) continue;
        known.set(player.playerId, { name: player.label, controller: isViewer(snapshot, player.playerId) ? "you" : "opponent", kind: "player", token: false });
      }
      for (const ability of prompt.abilities ?? []) known.set(ability.id, { name: ability.label, controller: "", kind: "option", token: false });
    }
    return known;
  },

  target(id: string, known: Map<string, ComboKnown>): ComboTarget {
    const thing = known.get(id);
    if (!thing) return ComboTarget.make("?");
    return ComboTarget.make(thing.name, thing.controller, thing.kind, thing.token);
  },

  /** Nothing on the stack, anyone's. */
  stackIsEmpty: (snapshot: GameSnapshot) => (snapshot.xmage?.stack ?? []).length === 0 && snapshot.players.every((p) => p.zones.stack.length === 0),

  // Recording

  /** What a player's answer means for spotting loops. */
  note(command: ComboCommand, _label: string, actionID: string, snapshot: GameSnapshot | undefined): ComboNote {
    if (ignoredTypes.has(command.type)) return ComboNote.ignore;
    if (!snapshot || excludedTypes.has(command.type)) return ComboNote.breaks;
    const known = ComboLoop.known(snapshot);
    const chosen = (ids: string[] | undefined) => (ids ?? []).map((id) => ComboLoop.target(id, known));
    const empty = ComboLoop.stackIsEmpty(snapshot);
    const manaTypes = command.manaTypes ?? (command.manaType !== undefined ? [command.manaType] : undefined);
    const action = snapshot.legalActions?.find((a) => a.id === actionID);
    if (action) {
      return ComboNote.step({
        kind: "action", type: command.type, source: sourceName(action, known), label: ComboLoop.normalized(action.label),
        targets: [...chosen(command.targetIds), ...chosen(command.cardInstanceIds), ...chosen(command.playerIds)],
        amount: command.amount, amounts: command.amounts, pile: command.pile, manaTypes, confirmed: command.confirmed, pay: command.pay,
        useCommandZone: command.useCommandZone, stackEmpty: empty, producedMana: action.producedMana,
      });
    }
    const prompt = snapshot.promptEnvelopeV2;
    if (!prompt || !(command.promptId === prompt.id || command.promptId === prompt.responseCommand?.promptId)) return ComboNote.breaks;
    const picked = [...chosen(command.targetIds), ...chosen(command.cardInstanceIds), ...chosen(command.playerIds), ...chosen(command.choiceIds),
      ...chosen(command.modeIds), ...chosen(command.orderedIds), ...chosen(command.abilityId !== undefined ? [command.abilityId] : undefined)];
    return ComboNote.step({
      kind: "prompt", type: command.type, source: undefined, label: prompt.method, targets: picked,
      amount: command.amount, amounts: command.amounts, pile: command.pile, manaTypes, confirmed: command.confirmed, pay: command.pay,
      useCommandZone: command.useCommandZone, stackEmpty: empty,
    });
  },

  /** The step a player's answer makes, or undefined when it isn't one. */
  step(command: ComboCommand, label: string, actionID: string, snapshot: GameSnapshot | undefined): ComboStep | undefined {
    const note = ComboLoop.note(command, label, actionID, snapshot);
    return note.kind === "step" ? note.step : undefined;
  },

  // Spotting a loop

  /** A round worth repeating: something is cast or activated, and nothing in it is combat or the opening. */
  isLoopable: (round: ComboStep[]) =>
    round.some((s) => s.kind === "action" && comboTypes.has(s.type)) && !round.some((s) => excludedTypes.has(s.type)),

  /** The shortest round the last steps repeat `repeatsToOffer` times in a row, or undefined. */
  cycle(history: ComboStep[]): ComboStep[] | undefined {
    // Fewer steps than one round repeated three times: nothing to find.
    const longest = Math.min(ComboLoop.maxCycleLength, Math.floor(history.length / ComboLoop.repeatsToOffer));
    if (longest < 1) return undefined;
    for (let length = 1; length <= longest; length++) {
      const tail = history.slice(history.length - length * ComboLoop.repeatsToOffer);
      let repeats = true;
      for (let index = length; index < tail.length; index++) if (!ComboStep.equals(tail[index], tail[index - length])) { repeats = false; break; }
      if (!repeats) continue;
      const round = tail.slice(0, length);
      if (ComboLoop.isLoopable(round)) return round;
    }
    return undefined;
  },

  /** The offer's headline: the round's casts and activations. */
  describe: (round: ComboStep[]) =>
    round.filter((s) => s.kind === "action" && comboTypes.has(s.type))
      .map((step) => `${step.type === "cast_spell" ? "Cast" : "Activate"} ${step.source ?? step.label}`).join(" → "),

  /** What one round does, step by step, for the offer's preview. */
  preview: (round: ComboStep[]): string[] => round.map((step) => {
    switch (step.kind) {
      case "action": {
        const name = step.source ?? step.label;
        switch (step.type) {
          case "cast_spell": return `Cast ${name}`;
          case "activate_ability": return `Activate ${name}`;
          case "make_mana": return `Mana from ${name}`;
          case "play_land": return `Play ${name}`;
          default: return name;
        }
      }
      case "prompt": {
        if (step.type === "answer_yes_no") return step.confirmed === true ? "Answer Yes" : "Answer No";
        if (step.type === "play_mana" || step.type === "choose_mana") return `Pay {${(step.manaTypes ?? []).join("")}}`;
        const things = step.targets.map(ComboTarget.phrase).join(", ");
        return things.length === 0 ? step.label : `Choose ${things}`;
      }
    }
  }),

  // Repeating it

  /** The step must wait for the stack to clear first: it was taken with nothing on the stack. */
  waitsForStack: (step: ComboStep, snapshot: GameSnapshot) => step.stackEmpty && !ComboLoop.stackIsEmpty(snapshot),

  /** Passing priority so the player's own triggers resolve: the board's pass, when it's offered. */
  pass(snapshot: GameSnapshot): { command: ComboCommand; label: string; actionID: string } | undefined {
    const action = snapshot.legalActions?.find((a) => a.type === "pass_priority");
    if (!action) return undefined;
    return { command: commandFromAction(action, snapshot.id, snapshot.bridgeRevision), label: action.label, actionID: action.id };
  },

  /**
   * The answer this step makes now, from the current legal actions or prompt; undefined when it isn't available. Each
   * chosen thing prefers the name `prefer` gives for its place (last round's choice, so a shrinking creature stays the
   * target until it dies), then the recorded name, then anything of the same kind.
   */
  command(step: ComboStep, snapshot: GameSnapshot, prefer: string[] = []): ComboReplay | undefined {
    const known = ComboLoop.known(snapshot);
    switch (step.kind) {
      case "action": {
        const actions = snapshot.legalActions ?? [];
        let match = actions.find((a) => a.type === step.type && ComboLoop.normalized(a.label) === step.label && sourceName(a, known) === step.source);
        // The same mana from another source when the original is gone (a sacrificed Treasure).
        const mana = step.producedMana;
        if (match === undefined && step.type === "make_mana" && mana !== undefined && mana.length > 0) {
          match = actions.find((a) => a.type === "make_mana" && mana.every((m) => (a.producedMana ?? []).includes(m)));
        }
        if (match === undefined) return undefined;
        return { command: commandFromAction(match, snapshot.id, snapshot.bridgeRevision), label: match.label, actionID: match.id, chosenNames: [] };
      }
      case "prompt": {
        const prompt = snapshot.promptEnvelopeV2;
        if (!prompt || prompt.method !== step.label || !isViewer(snapshot, prompt.playerId)) return undefined;
        const pool: { id: string; target: ComboTarget }[] = [];
        for (const option of [...(prompt.targets ?? []), ...(prompt.choices ?? []), ...(prompt.modes ?? []), ...(prompt.orderedItems ?? [])]) {
          pool.push({ id: option.id, target: ComboLoop.target(option.id, known) });
        }
        for (const card of prompt.cards ?? []) pool.push({ id: card.instanceId, target: ComboLoop.target(card.instanceId, known) });
        for (const player of prompt.players ?? []) pool.push({ id: player.playerId, target: ComboLoop.target(player.playerId, known) });
        for (const ability of prompt.abilities ?? []) pool.push({ id: ability.id, target: ComboLoop.target(ability.id, known) });
        const ids: string[] = [], names: string[] = [];
        let retargeted: { from: string; to: string } | undefined;
        for (const [place, wanted] of step.targets.entries()) {
          const preferred = place < prefer.length ? prefer[place] : wanted.name;
          const at = (test: (target: ComboTarget) => boolean) => { const index = pool.findIndex((p) => test(p.target)); return index < 0 ? undefined : index; };
          const found = at((t) => ComboTarget.equals(t, wanted) && t.name === preferred)
            ?? at((t) => ComboTarget.equals(t, wanted) && t.name === wanted.name)
            ?? at((t) => ComboTarget.equals(t, wanted));
          if (found === undefined) return undefined;
          const [picked] = pool.splice(found, 1);
          if (picked.target.name !== preferred && wanted.kind !== "option" && wanted.controller === "opponent" && retargeted === undefined) {
            retargeted = { from: preferred, to: picked.target.name };
          }
          ids.push(picked.id); names.push(picked.target.name);
        }
        const promptID = prompt.responseCommand?.promptId ?? prompt.id;
        if (step.type === "answer_yes_no" || step.type === "pay_cost") {
          const confirmed = step.confirmed ?? step.pay;
          if (confirmed === undefined) return undefined;
          return {
            command: { type: step.type, gameId: snapshot.id, playerId: viewerID(snapshot), promptId: promptID,
              messageId: prompt.responseCommand?.messageId ?? prompt.messageId, confirmed, pay: step.type === "pay_cost" ? confirmed : undefined },
            label: step.type, actionID: `combo-loop-${promptID}`, chosenNames: names,
          };
        }
        const command = promptCommand(snapshot.id, prompt, step.type, promptID, viewerID(snapshot), {
          ids, amount: step.amount, amounts: step.amounts, pile: step.pile, useCommandZone: step.useCommandZone,
          manaType: step.manaTypes?.[0], pay: step.pay,
        });
        if (!command) return undefined;
        return { command, label: step.type, actionID: `combo-loop-${promptID}`, chosenNames: names, retargeted };
      }
    }
  },

  /**
   * The parts of the game a loop changes: life, poison, every permanent's power, toughness, damage, counters and tapped
   * state, zone sizes, mana and spells cast. A round that leaves all of it unchanged did nothing visible.
   */
  digest: (snapshot: GameSnapshot): string =>
    [...snapshot.players].sort((a, b) => (a.playerId < b.playerId ? -1 : a.playerId > b.playerId ? 1 : 0)).map((player) => {
      const zones = player.zones;
      const pool = player.manaPool ? `${player.manaPool.W},${player.manaPool.U},${player.manaPool.B},${player.manaPool.R},${player.manaPool.G},${player.manaPool.C}` : "";
      const permanents = zones.battlefield.map((card) => {
        const counters = byKey(card.counters ?? {}).map(([key, value]) => `${key}${value}`).join("");
        return `${card.card.name}/${card.power ?? -99}/${card.toughness ?? -99}/${card.damage ?? 0}/${card.tapped === true ? 1 : 0}/${counters}`;
      }).sort().join(",");
      const counters = byKey(player.counters ?? {}).map(([key, value]) => `${key}${value}`).join("");
      return `${player.playerId}:${player.life}:${player.poison}:${visibleHandCount(zones)}:${visibleLibraryCount(zones)}:`
        + `${zones.graveyard.length}:${zones.exile.length}:${counters}:${pool}:[${permanents}]`;
    }).join("|") + `|storm:${snapshot.stormCount ?? 0}`,

  /** An opponent put something on the stack: their spell, or an ability of one of their permanents. */
  opponentResponded(snapshot: GameSnapshot): boolean {
    const opponents = snapshot.players.filter((p) => !isViewer(snapshot, p.playerId));
    if (opponents.some((p) => p.zones.stack.length > 0)) return true;
    const theirs = new Set(opponents.flatMap((p) => p.zones.battlefield.map((c) => c.instanceId)));
    return (snapshot.xmage?.stack ?? []).some((object) => {
      const controller = object.controllerId;
      if (controller !== undefined && controller.length > 0 && !isViewer(snapshot, controller)
        && snapshot.players.some((p) => p.playerId === controller)) return true;
      return object.sourceInstanceId !== undefined ? theirs.has(object.sourceInstanceId) : false;
    });
  },

  /** One round on the running card: "Round 3 · Activate Chatterfang → Kinjalli's Caller". */
  roundLine(round: number, cycle: ComboStep[], chosen: string[]): string {
    const at = chosen.length > 0 ? ` → ${chosen[0]}` : "";
    return `Round ${round} · ${ComboLoop.describe(cycle)}${at}`;
  },

  /** The closing line: how many rounds ran and whose life changed. */
  summary(rounds: number, before: GameSnapshot, after: GameSnapshot): string {
    const parts = [rounds === 1 ? "Repeated once" : `Repeated ${rounds} times`];
    for (const player of after.players) {
      const old = before.players.find((p) => p.playerId === player.playerId);
      if (!old || old.life === player.life) continue;
      const name = isViewer(after, player.playerId) ? "You" : (player.displayName ?? "Opponent");
      parts.push(`${name} ${old.life} → ${player.life}`);
    }
    return parts.join(" · ");
  },

  /** Why a step couldn't be taken, in words: "no Squirrel token to choose", "Chatterfang isn't available". */
  missing(step: ComboStep): string {
    switch (step.kind) {
      case "action": return `${step.source ?? step.label} isn't available`;
      case "prompt": {
        const thing = step.targets[0];
        if (thing === undefined || thing.kind === "option") return "the next choice isn't offered";
        if (thing.controller === "opponent") return thing.token ? `no opponent's ${thing.kind} token left to choose` : `no opponent's ${thing.kind} left to choose`;
        return thing.token ? `no ${thing.name} token left` : `${thing.name} isn't there to choose`;
      }
    }
  },
};

// ---- ComboWinForecast ----

/** Life and poison of one opponent at the start of a round (Swift `ComboWinForecast.Standing`). */
export interface ComboStanding { life: number; poison: number }

/**
 * Whether repeating a round ends the game, read from the rounds the player made: every opponent lost the same life (or
 * got the same poison) each round, so the rounds still needed can be counted; and whether an opponent can visibly answer
 * (cards in hand and an untapped land). A hidden instant can still stop the loop: the rules check every step.
 */
export class ComboWinForecast {
  constructor(
    /** Rounds until every opponent has lost. */
    readonly rounds: number,
    /** An opponent holds cards and has an untapped land. */
    readonly opponentsCanRespond: boolean,
  ) {}

  get canFinish() { return !this.opponentsCanRespond; }

  /**
   * `starts`: each opponent's standing at the start of the last rounds, oldest first (at least three). Only round starts
   * count: the latest round's drain can still be waiting on the stack (Blood Artist, Impact Tremors) when the loop is
   * offered. `rounds` is what's still needed once that latest round has finished.
   */
  static forecast(starts: Record<string, ComboStanding>[], opponentsCanRespond: boolean, cap: number = ComboLoop.maxRepeats): ComboWinForecast | undefined {
    const last = starts[starts.length - 1];
    if (starts.length < 3 || last === undefined || Object.keys(last).length === 0) return undefined;
    let needed = 0;
    for (const [player, standing] of Object.entries(last)) {
      const history = starts.flatMap((start) => (Object.hasOwn(start, player) ? [start[player]] : []));
      if (history.length !== starts.length) return undefined;
      const lifeLoss = history.slice(1).map((next, index) => history[index].life - next.life);
      const poisonGain = history.slice(1).map((next, index) => next.poison - history[index].poison);
      let rounds: number;
      const loss = lifeLoss[0], gain = poisonGain[0];
      if (loss !== undefined && loss > 0 && lifeLoss.every((value) => value === loss)) {
        rounds = Math.max(0, Math.trunc((standing.life + loss - 1) / loss) - 1);
      } else if (gain !== undefined && gain > 0 && poisonGain.every((value) => value === gain)) {
        rounds = Math.max(0, Math.trunc((10 - standing.poison + gain - 1) / gain) - 1);
      } else {
        return undefined;
      }
      needed = Math.max(needed, rounds);
    }
    if (needed > cap) return undefined;
    return new ComboWinForecast(needed, opponentsCanRespond);
  }

  /** Each opponent's life and poison in a snapshot. */
  static standings(snapshot: GameSnapshot): Record<string, ComboStanding> {
    return Object.fromEntries(snapshot.players.filter((p) => !isViewer(snapshot, p.playerId) && !isOut(p))
      .map((p) => [p.playerId, { life: p.life, poison: p.poison }]));
  }

  /** An opponent holds cards and has an untapped land: they could answer. */
  static opponentsCanRespond(snapshot: GameSnapshot): boolean {
    return snapshot.players.filter((p) => !isViewer(snapshot, p.playerId) && !isOut(p)).some((player) =>
      visibleHandCount(player.zones) > 0 && player.zones.battlefield.some((card) => isLandCard(card.card) && card.tapped !== true));
  }
}

// ---- ComboLoopStop ----

/** Why repeating a loop stopped. */
export type ComboLoopStop =
  | { kind: "finished" }
  | { kind: "gameOver" }
  | { kind: "stepMissing"; why: string }
  | { kind: "opponentResponded" }
  | { kind: "nothingChanged" }
  | { kind: "reachedLimit" }
  /** "Until they lose" ran the rounds its forecast needed, and a few more, without ending the game. */
  | { kind: "didNotFinish"; rounds: number }
  | { kind: "stoppedByPlayer" }
  | { kind: "failed"; reason: string };

export const ComboLoopStop = {
  finished: { kind: "finished" } as ComboLoopStop,
  gameOver: { kind: "gameOver" } as ComboLoopStop,
  stepMissing: (why: string): ComboLoopStop => ({ kind: "stepMissing", why }),
  opponentResponded: { kind: "opponentResponded" } as ComboLoopStop,
  nothingChanged: { kind: "nothingChanged" } as ComboLoopStop,
  reachedLimit: { kind: "reachedLimit" } as ComboLoopStop,
  didNotFinish: (rounds: number): ComboLoopStop => ({ kind: "didNotFinish", rounds }),
  stoppedByPlayer: { kind: "stoppedByPlayer" } as ComboLoopStop,
  failed: (reason: string): ComboLoopStop => ({ kind: "failed", reason }),
  message(stop: ComboLoopStop): string {
    switch (stop.kind) {
      case "finished": return "Done.";
      case "gameOver": return "The game is over.";
      case "stepMissing": return `Stopped: ${stop.why}.`;
      case "opponentResponded": return "An opponent responded, so it's your turn to choose.";
      case "nothingChanged": return "The loop stopped changing the game.";
      case "reachedLimit": return `Stopped after ${ComboLoop.maxRepeats} rounds.`;
      case "didNotFinish": return `Stopped after ${stop.rounds} rounds: the loop didn't end the game.`;
      case "stoppedByPlayer": return "Stopped.";
      case "failed": return stop.reason;
    }
  },
};

// ---- GameCommand and GameSnapshot extensions ----

/** The command a board action sends (Swift `GameCommand(action:gameId:bridgeRevision:)`, OnDeviceSession.send(action:)). */
export const commandFromAction = (action: LegalAction, gameId: string, bridgeRevision: number | undefined): ComboCommand => ({
  type: action.type, gameId, playerId: action.playerId,
  cardInstanceId: action.cardInstanceId, sourceInstanceId: action.sourceInstanceId,
  abilityId: action.abilityId, promptId: action.promptId, messageId: action.messageId,
  choiceIds: action.choiceIds, targetIds: action.targetIds, cardInstanceIds: action.cardInstanceIds,
  modeIds: action.modeIds, pile: action.pile, amount: action.amount, amounts: action.amounts,
  orderedIds: action.orderedIds, useCommandZone: action.useCommandZone,
  manaType: action.manaType, manaTypes: action.manaTypes, playerIds: action.playerIds,
  confirmed: action.confirmed, pay: action.pay, sourceZone: action.sourceZone,
  fromZone: action.sourceZone, cardName: action.cardName, attackers: action.attackers,
  blockers: action.blockers, expectedBridgeRevision: bridgeRevision,
});

/** The board's copy while a loop repeats: the prompts the repeats answer are not shown. */
export const withoutPrompts = (snapshot: GameSnapshot): GameSnapshot =>
  ({ ...snapshot, legalActions: undefined, promptEnvelopeV2: undefined, manaPayment: undefined });
