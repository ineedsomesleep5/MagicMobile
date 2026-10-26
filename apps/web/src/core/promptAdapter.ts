/** Port of OnDevicePromptAdapter.kt (Swift OnDevicePromptAdapter.swift). */
import { EngineDisplayText } from "./displayText";
import { EnginePrompt } from "./engineClient";
import { arr, at, bool, EngineError, get, int, isUuid, type J, type JObject, obj, str, utf8Length } from "./json";
import {
  decodeEnvelope, decodeLegalAction, type GameCommand, type LegalAction, type ManaPayment, type PlayerGameState,
  type PromptEnvelopeV2, type ZoneCard,
} from "./models";
import { printedManaCost } from "./snapshotCard";

export interface PromptPresentation { envelope: PromptEnvelopeV2; legalActions: LegalAction[]; manaPayment?: ManaPayment }

const invalid = (message: string) => EngineError.invalid(message);
const plainLabel = (value: string | undefined, fallback: string) => EngineDisplayText.label(value ?? "", fallback);

const validate = (prompt: EnginePrompt, viewer: string) => {
  if (!isUuid(viewer)) throw invalid("Viewer must be the engine player UUID");
  if (prompt.submitted || prompt.id.length === 0 || prompt.revision > 2147483647) throw invalid("Prompt is submitted or invalid");
};

const single = (values: string[] | undefined): string => {
  if (values === undefined || values.length !== 1) throw invalid("Exactly one choice is required per upstream prompt");
  return values[0];
};

const targetIDs = (prompt: EnginePrompt): string[] => {
  const values = arr(prompt.payload.candidates);
  if (!values) throw invalid("Missing target candidates");
  const ids = values.map((value) => {
    if (!isUuid(value)) throw invalid("Invalid target UUID");
    return value;
  });
  for (const id of Object.keys(obj(prompt.payload.responseAliases) ?? {}).sort()) {
    if (!isUuid(id)) throw invalid("Invalid target alias");
    if (!ids.includes(id)) ids.push(id);
  }
  return ids;
};

/** Transport candidates also include browseable, nonmatching search cards. */
const selectableTargetIDs = (prompt: EnginePrompt): string[] => {
  const candidates = targetIDs(prompt);
  const options = prompt.payload.options;
  const hasCardSelection = (arr(prompt.payload.cards)?.length ?? 0) > 0 && get(options, "chosenTargets") !== undefined;
  if (get(options, "possibleTargets") === undefined && !hasCardSelection) return candidates;
  const legal = new Set<string>();
  for (const key of ["possibleTargets", "chosenTargets"]) {
    const value = get(options, key);
    if (value === undefined) continue;
    const values = arr(value);
    if (!values) throw invalid("Malformed target eligibility");
    for (const item of values) {
      if (!isUuid(item) || !candidates.includes(item)) throw invalid("Invalid selectable target");
      legal.add(item);
    }
  }
  for (const [alias, base] of Object.entries(obj(prompt.payload.responseAliases) ?? {})) {
    const id = str(base);
    if (id !== undefined && legal.has(id)) legal.add(alias);
  }
  return candidates.filter((id) => legal.has(id));
};

const choices = (prompt: EnginePrompt): [string, string][] => {
  const values = obj(prompt.payload.choices);
  const order = arr(prompt.payload.choiceOrder);
  if (!values || !order) throw invalid("Missing ordered choices");
  return order.map((item) => {
    const id = str(item);
    const label = id === undefined ? undefined : str(values[id]);
    if (id === undefined || label === undefined) throw invalid("Invalid choice key or label");
    return [id, EngineDisplayText.label(label)];
  });
};

/** Only CardViews explicitly supplied to this viewer's query enter this mapper. */
const promptCard = (value: J): JObject => {
  const id = str(get(value, "id"));
  if (!isUuid(id)) throw invalid("Unrepresentable prompt card");
  const hidden = bool(get(value, "hideInfo")) === true;
  const name = hidden ? "Face-down card" : str(get(value, "displayName")) ?? str(get(value, "name")) ?? "Card details unavailable";
  const types = hidden ? [] : (arr(get(value, "cardTypes")) ?? []).filter((t): t is string => typeof t === "string");
  const card: JObject = { name: EngineDisplayText.label(name), typeLine: types.join(" ") };
  const cost = printedManaCost(value);
  if (cost !== undefined) card.manaCost = cost;
  if (!hidden) {
    const rules = arr(get(value, "rules"));
    if (rules) card.oracleText = EngineDisplayText.text(rules.filter((r): r is string => typeof r === "string").join("\n"));
  }
  return { instanceId: id, card };
};

const checkAmount = (value: number, min: number, max: number) => {
  if (value < min || value > max) throw invalid("Amount out of engine bounds");
};

export const OnDevicePromptAdapter = {
  presentation(prompt: EnginePrompt, viewerPlayerID: string, cards: ZoneCard[], players: PlayerGameState[] = [],
    actingAttackerPlayerID?: string): PromptPresentation {
    validate(prompt, viewerPlayerID);
    const revision = prompt.revision;
    const payload = prompt.payload;
    const fields: JObject = {
      id: prompt.id, method: `GAME_${prompt.kind}`, messageId: revision, playerId: viewerPlayerID, responseKind: "unsupported",
      message: EngineDisplayText.text(str(payload.message) ?? ""), required: bool(payload.required) ?? true,
    };
    const actions: LegalAction[] = [];
    let payment: ManaPayment | undefined;
    if (payload.options !== undefined) fields.options = payload.options;
    const response = (type: string): JObject => ({ type, promptId: prompt.id, messageId: revision });
    const action = (type: string, label: string, extras: JObject = {}): LegalAction => decodeLegalAction({
      id: `${prompt.id}:${type}`, type, label: EngineDisplayText.label(label), playerId: viewerPlayerID, promptId: prompt.id,
      messageId: revision, ...extras,
    });
    const targetLabel = (id: string): string => {
      if (id === viewerPlayerID) return "You";
      return EngineDisplayText.label(players.find((p) => p.playerId === id)?.displayName ?? cards.find((c) => c.instanceId === id)?.card.name ?? id);
    };
    const has = (type: string) => prompt.responseTypes.includes(type);
    const selectMode = str(payload.selectMode);
    switch (prompt.kind) {
      case "ASK": {
        if (!has("boolean")) throw invalid("ASK requires boolean responses");
        const base = response("answer_yes_no");
        fields.responseKind = "confirmation"; fields.responseCommand = base;
        fields.confirmation = {
          yesLabel: plainLabel(str(at(payload, "options", "UI.left.btn.text")), "Yes"),
          noLabel: plainLabel(str(at(payload, "options", "UI.right.btn.text")), "No"),
          yesCommand: { ...base, confirmed: true }, noCommand: { ...base, confirmed: false },
        };
        break;
      }
      case "SELECT": {
        if (selectMode === "priority") {
          fields.responseKind = "priority"; fields.responseCommand = response("pass_priority");
          if (has("boolean")) actions.push(action("pass_priority", "Pass priority"));
        } else if (selectMode === "attackers" || selectMode === "blockers") {
          const key = selectMode === "attackers" ? "possibleAttackers" : "possibleBlockers";
          const candidates = arr(at(payload, "options", key));
          if (!has("uuid") || !candidates) throw invalid("Missing combat candidates");
          fields.responseKind = "target"; fields.responseCommand = response("choose_target");
          fields.minChoices = 1; fields.maxChoices = 1;
          const targets: [string, string][] = candidates.map((item) => {
            if (!isUuid(item)) throw invalid("Invalid combat UUID");
            return [item, targetLabel(item)];
          });
          if (key === "possibleAttackers" && actingAttackerPlayerID !== undefined) {
            if (!isUuid(actingAttackerPlayerID) || !players.some((p) => p.playerId === actingAttackerPlayerID)) throw invalid("Invalid acting attacker identity");
          }
          const attackerID = actingAttackerPlayerID ?? viewerPlayerID;
          const battlefield = key === "possibleAttackers" ? players.find((p) => p.playerId === attackerID)?.zones.battlefield ?? [] : [];
          for (const card of battlefield) {
            if (card.isAttacking !== true) continue;
            if (!isUuid(card.instanceId)) throw invalid("Invalid combat UUID");
            if (!targets.some(([id]) => id === card.instanceId)) targets.push([card.instanceId, EngineDisplayText.label(card.card.name)]);
          }
          if (key === "possibleBlockers") {
            for (const card of players.find((p) => p.playerId === viewerPlayerID)?.zones.battlefield ?? []) {
              if (!card.blocking || card.blocking.length === 0) continue;
              if (!isUuid(card.instanceId)) throw invalid("Invalid combat UUID");
              if (!targets.some(([id]) => id === card.instanceId)) targets.push([card.instanceId, EngineDisplayText.label(card.card.name)]);
            }
          }
          fields.targets = targets.map(([id, label]) => ({ id, label }));
          if (has("boolean")) actions.push(action("answer_yes_no", "Done", { confirmed: true }));
        } else throw invalid("Unsupported SELECT mode");
        const special = str(at(payload, "options", "specialButton"));
        if (has("string") && special !== undefined) actions.push(action("resolve_choice", special, { choiceIds: ["special"] }));
        break;
      }
      case "PLAY_MANA": case "PLAY_X_MANA": {
        const player = str(payload.manaPlayerId);
        if (!has("mana") || !isUuid(player)) throw invalid("Missing mana player UUID");
        const x = prompt.kind === "PLAY_X_MANA";
        fields.responseKind = x ? "x_mana" : "mana";
        fields.responseCommand = response(x ? "play_x_mana" : "play_mana");
        if (x) { fields.minChoices = prompt.minimum; fields.maxChoices = prompt.maximum; }
        const pool = players.find((p) => p.playerId === player)?.manaPool;
        if (pool) {
          fields.manaChoices = (["W", "U", "B", "R", "G", "C"] as const).filter((symbol) => pool[symbol] > 0)
            .map((symbol) => ({ id: symbol, manaType: symbol, label: `Pay {${symbol}}`, amount: pool[symbol] }));
        }
        payment = { active: true, remainingText: EngineDisplayText.text(str(payload.message) ?? "") };
        if (has("boolean")) actions.push(action("cancel_payment", "Cancel", { confirmed: false }));
        if (!x && has("string")) {
          actions.push(action("resolve_choice", str(at(payload, "options", "specialButton")) ?? "Special payment", { choiceIds: ["special"] }));
        }
        break;
      }
      case "MULTI_AMOUNT": {
        const rows = arr(payload.allocations);
        if (!has("integers") || !rows) throw invalid("Missing allocation rows");
        fields.method = "GAME_GET_MULTI_AMOUNT"; fields.responseKind = "multi_amount";
        fields.responseCommand = response("choose_multi_amount");
        fields.totalMin = prompt.minimum; fields.totalMax = prompt.maximum;
        fields.multiAmounts = rows.map((row, index) => {
          const min = int(get(row, "min")); const max = int(get(row, "max")); const label = str(get(row, "message"));
          if (min === undefined || max === undefined || min > max || label === undefined) throw invalid("Malformed allocation row");
          const value: JObject = { id: String(index), label: EngineDisplayText.label(label), min, max };
          const fallback = int(get(row, "defaultValue"));
          if (fallback !== undefined) value.defaultValue = fallback;
          return value;
        });
        if (has("boolean") && bool(at(payload, "options", "canCancel")) === true) actions.push(action("answer_yes_no", "Cancel", { confirmed: false }));
        break;
      }
      case "AMOUNT": {
        if (!has("integer")) throw invalid("Amount requires integer responses");
        fields.method = "GAME_GET_AMOUNT"; fields.responseKind = "amount"; fields.responseCommand = response("choose_amount");
        fields.minChoices = prompt.minimum; fields.maxChoices = prompt.maximum;
        if (prompt.minimum > prompt.maximum || prompt.minimum < -2147483648 || prompt.maximum > 2147483647) throw invalid("Invalid amount bounds");
        if (prompt.maximum - prompt.minimum < 64) {
          const amounts: number[] = [];
          for (let value = prompt.minimum; value <= prompt.maximum; value += 1) amounts.push(value);
          fields.amounts = amounts;
        }
        break;
      }
      case "CHOOSE_PILE": {
        const one = arr(payload.pile1); const two = arr(payload.pile2);
        if (!has("boolean") || !one || !two) throw invalid("Missing boolean pile choices");
        fields.responseKind = "pile"; fields.responseCommand = response("choose_pile");
        fields.piles = [one, two].map((pile, index) => ({ id: `${index + 1}`, label: `Pile ${index + 1}`, cards: pile.map(promptCard) }));
        break;
      }
      case "CHOOSE_ABILITY": case "PICK_ABILITY": {
        const abilities = arr(payload.abilities);
        if (!has("uuid") || !abilities) throw invalid("Missing UUID ability choices");
        fields.responseKind = "ability"; fields.responseCommand = response("choose_ability");
        fields.minChoices = 1; fields.maxChoices = 1;
        fields.abilities = abilities.map((item) => {
          const id = str(get(item, "id")); const label = str(get(item, "label"));
          if (!isUuid(id) || label === undefined) throw invalid("Malformed ability choice");
          const row: JObject = { id, label: EngineDisplayText.label(label) };
          const sourceID = str(get(item, "sourceId"));
          if (isUuid(sourceID)) {
            row.sourceInstanceId = sourceID;
            const source = get(item, "sourceCard");
            if (source !== undefined && str(get(source, "id")) === sourceID && bool(get(source, "hideInfo")) !== true) {
              row.sourceCard = promptCard(source);
              row.sourceName = EngineDisplayText.label(str(get(source, "displayName")) ?? str(get(source, "name")) ?? "Card details unavailable");
            }
          }
          if (row.sourceCard === undefined) row.sourceUnavailableReason = "Source details unavailable";
          const card = get(item, "sourceCard");
          const rules = card === undefined || bool(get(card, "hideInfo")) === true ? []
            : ((get(card, "rules") as unknown[] | undefined) ?? []).filter((rule): rule is string => typeof rule === "string");
          const rule = EngineDisplayText.abilityRule(label, rules);
          if (rule !== undefined) row.rulesText = rule;
          return row;
        });
        if (has("boolean") && bool(payload.required) === false) actions.push(action("answer_yes_no", "Cancel", { confirmed: false }));
        break;
      }
      case "CHOOSE_CHOICE": {
        if (!has("string")) throw invalid("Choice requires string responses");
        if (bool(payload.specialEnabled) === true && bool(payload.specialCanBeEmpty) === true) {
          actions.push(action("choose_empty_special", plainLabel(str(payload.specialText), "Choose no item")));
        }
        fields.responseKind = "choice"; fields.responseCommand = response("resolve_choice");
        fields.minChoices = 1; fields.maxChoices = 1;
        const rows = choices(prompt);
        if (bool(payload.specialEnabled) === true) {
          for (const [id] of [...rows]) {
            const key = `#${id}`;
            const label = str(at(payload, "specialChoices", key));
            if (label !== undefined) rows.push([key, EngineDisplayText.label(`${str(payload.specialText) ?? "Special"}: ${label}`)]);
          }
        }
        if (bool(payload.required) === false) rows.push(["", "Cancel"]);
        // Preserve engine hints, sorting, and exact choice metadata for callers.
        fields.options = payload;
        fields.choices = rows.map(([id, label]) => ({ id, label }));
        break;
      }
      case "CHOOSE_MODE": {
        if (!has("uuid")) throw invalid("Mode requires UUID responses");
        fields.responseKind = "mode"; fields.responseCommand = response("choose_mode");
        fields.minChoices = 1; fields.maxChoices = 1;
        fields.modes = choices(prompt).map(([id, label]) => ({ id, label }));
        break;
      }
      case "PICK_TARGET": {
        if (!has("uuid")) throw invalid("Target requires UUID responses");
        const candidates = selectableTargetIDs(prompt);
        const aliases = obj(payload.responseAliases) ?? {};
        const canonical = (id: string) => str(aliases[id]) ?? id;
        const canonicalCandidates: string[] = [];
        for (const id of candidates.map(canonical)) if (!canonicalCandidates.includes(id)) canonicalCandidates.push(id);
        fields.responseKind = "target"; fields.responseCommand = response("choose_target");
        fields.minChoices = 1; fields.maxChoices = 1;
        fields.targetIds = canonicalCandidates;
        // QueryEncoder serializes CardViews in payload.cards and options.orderedViews only.
        const supplied = [...(arr(at(payload, "options", "orderedViews")) ?? []), ...(arr(payload.cards) ?? [])];
        const seen = new Set<string>();
        const mapped: JObject[] = supplied.filter((value) => {
          const id = str(get(value, "id"));
          if (id === undefined) return false;
          const key = canonical(id);
          if (seen.has(key)) return false;
          seen.add(key);
          return true;
        }).map((value) => {
          const card = promptCard(value);
          const id = canonical(str(get(value, "id"))!);
          card.instanceId = id;
          const legal = canonicalCandidates.includes(id);
          card.selectable = legal;
          if (!legal) card.disabledReason = "Not a legal choice";
          return card;
        });
        // A query may supply only IDs (graveyard/hand selections). Recover only matching cards
        // from this authenticated view; battlefield targets remain direct board taps.
        const boardIDs = new Set(players.flatMap((p) => p.zones.battlefield).map((c) => c.instanceId));
        for (const card of cards) {
          const key = canonical(card.instanceId);
          if (!canonicalCandidates.includes(key) || boardIDs.has(card.instanceId) || seen.has(key)) continue;
          seen.add(key);
          const identity: JObject = { name: card.card.name, typeLine: card.card.typeLine };
          if (card.card.oracleText !== undefined) identity.oracleText = card.card.oracleText;
          if (card.card.manaCost !== undefined) identity.manaCost = card.card.manaCost;
          mapped.push({ instanceId: key, card: identity, selectable: true });
        }
        fields.cards = mapped;
        const shown = new Set(mapped.map((c) => str(c.instanceId)).filter((id): id is string => id !== undefined));
        fields.targets = canonicalCandidates.filter((id) => !shown.has(id)).map((id) => {
          const label = targetLabel(id);
          return { id, label: label === id ? "Card details unavailable" : label };
        });
        const options: JObject = { ...(obj(fields.options) ?? {}) };
        const chosen = arr(at(payload, "options", "chosenTargets"));
        if (chosen) {
          const unique: string[] = [];
          for (const id of chosen.filter((c): c is string => typeof c === "string").map(canonical)) if (!unique.includes(id)) unique.push(id);
          options.chosenTargets = unique;
        }
        fields.options = options;
        if (has("boolean") && bool(payload.required) === false) {
          actions.push(action("answer_yes_no", str(at(payload, "options", "UI.right.btn.text")) ?? "Cancel", { confirmed: false }));
        }
        break;
      }
      default:
        throw invalid(`Unsupported prompt: ${prompt.kind}`);
    }
    return { envelope: decodeEnvelope(fields), legalActions: actions, manaPayment: payment };
  },

  answer(command: GameCommand, prompt: EnginePrompt, viewerPlayerID: string): J {
    validate(prompt, viewerPlayerID);
    // messageId carries this prompt's revision, never the aggregate poll revision.
    if (command.playerId !== viewerPlayerID || command.promptId !== prompt.id || command.messageId !== prompt.revision) {
      throw invalid("Stale prompt or mismatched viewer");
    }
    const payload = prompt.payload;
    const selectMode = str(payload.selectMode) ?? "";
    const answer = (kind: string, value: J): J => {
      if (!prompt.responseTypes.includes(kind)) throw invalid(`Response type ${kind} is not accepted`);
      return EnginePrompt.answer(kind, value);
    };
    const key = `${prompt.kind}|${command.type}`;
    switch (key) {
      case "SELECT|choose_amount": {
        const value = command.amount;
        if (!["priority", "attackers", "blockers"].includes(selectMode) || value === undefined) throw invalid("Missing SELECT integer response");
        checkAmount(value, prompt.minimum, prompt.maximum);
        return answer("integer", value);
      }
      case "SELECT|choose_target": {
        if (!["attackers", "blockers"].includes(selectMode)) throw invalid("Not a combat selection");
        const id = single(command.targetIds);
        if (!isUuid(id)) throw invalid("Invalid combat UUID");
        return answer("uuid", id);
      }
      case "SELECT|answer_yes_no":
        if (!["attackers", "blockers"].includes(selectMode) || command.confirmed !== true) throw invalid("Expected combat completion");
        return answer("boolean", true);
      case "PLAY_MANA|play_mana": case "PLAY_X_MANA|play_mana": case "SELECT|play_mana": {
        const colors: Record<string, string> = { W: "WHITE", U: "BLUE", B: "BLACK", R: "RED", G: "GREEN", C: "COLORLESS" };
        const color = command.manaType === undefined ? undefined : colors[command.manaType];
        const player = str(payload.manaPlayerId);
        if (color === undefined || !isUuid(player)) throw invalid("Invalid mana symbol or missing player identity");
        return answer("mana", { playerId: player, manaType: color });
      }
      case "PLAY_X_MANA|play_x_mana": {
        const value = command.amount;
        if (value === undefined) throw invalid("Missing X amount");
        checkAmount(value, prompt.minimum, prompt.maximum);
        return answer("integer", value);
      }
      case "PLAY_MANA|cancel_payment": case "PLAY_X_MANA|cancel_payment":
        if (command.confirmed === true) throw invalid("Payment cancellation cannot confirm payment");
        return answer("boolean", false);
      case "PLAY_MANA|answer_yes_no": case "PLAY_X_MANA|answer_yes_no":
        if (command.confirmed !== false) throw invalid("Expected mana cancellation");
        return answer("boolean", false);
      case "PLAY_MANA|activate_ability": case "PLAY_X_MANA|activate_ability": case "PLAY_MANA|make_mana": case "PLAY_X_MANA|make_mana": {
        const id = command.sourceInstanceId ?? command.cardInstanceId;
        if (!isUuid(id)) throw invalid("Missing mana source UUID");
        return answer("uuid", id);
      }
      case "MULTI_AMOUNT|choose_multi_amount": {
        const values = command.amounts; const rows = arr(payload.allocations);
        if (values === undefined || rows === undefined || values.length !== rows.length) throw invalid("Allocation count mismatch");
        let sum = 0;
        values.forEach((value, index) => {
          const min = int(get(rows[index], "min")); const max = int(get(rows[index], "max"));
          if (min === undefined || max === undefined) throw invalid("Malformed allocation bounds");
          checkAmount(value, min, max);
          sum += value;
        });
        if (sum < prompt.minimum || sum > prompt.maximum) throw invalid("Allocation total out of bounds");
        return answer("integers", values);
      }
      case "MULTI_AMOUNT|answer_yes_no":
        if (command.confirmed !== false || bool(at(payload, "options", "canCancel")) !== true) throw invalid("Allocation cannot be cancelled");
        return answer("boolean", false);
      case "AMOUNT|choose_amount": {
        const amount = command.amount;
        if (amount === undefined) throw invalid("Missing amount");
        checkAmount(amount, prompt.minimum, prompt.maximum);
        return answer("integer", amount);
      }
      case "CHOOSE_PILE|choose_pile": {
        const pile = command.pile;
        if (pile !== 1 && pile !== 2) throw invalid("Pile must be 1 or 2");
        // HumanPlayer.choosePile / DoOrDie: true selects pile1, false selects pile2.
        return answer("boolean", pile === 1);
      }
      case "CHOOSE_ABILITY|choose_ability": case "PICK_ABILITY|choose_ability": {
        const id = command.abilityId;
        if (!isUuid(id) || !(arr(payload.abilities) ?? []).some((a) => str(get(a, "id")) === id)) throw invalid("Ability is not a candidate");
        return answer("uuid", id);
      }
      case "CHOOSE_CHOICE|choose_empty_special":
        if (bool(payload.specialEnabled) !== true || bool(payload.specialCanBeEmpty) !== true || command.choiceIds !== undefined) {
          throw invalid("Empty special choice is not available or contains a selected key");
        }
        return answer("string", null);
      case "CHOOSE_CHOICE|resolve_choice": {
        const choice = single(command.choiceIds);
        const normal = str(at(payload, "choices", choice)) !== undefined;
        const special = bool(payload.specialEnabled) === true && str(at(payload, "specialChoices", choice)) !== undefined;
        if (utf8Length(choice) > 8192 || !(normal || special || (choice.length === 0 && bool(payload.required) === false))) {
          throw invalid("Choice is not an exact engine key");
        }
        return answer("string", choice);
      }
      case "CHOOSE_MODE|choose_mode": {
        const id = single(command.modeIds);
        if (!isUuid(id) || str(at(payload, "choices", id)) === undefined) throw invalid("Mode is not a candidate");
        return answer("uuid", id);
      }
      case "PICK_TARGET|choose_target": case "PICK_TARGET|choose_card": case "PICK_TARGET|choose_player":
      case "PICK_TARGET|search_select": case "PICK_TARGET|order_items": {
        const selections = command.type === "choose_target" ? command.targetIds
          : command.type === "choose_card" || command.type === "search_select" ? command.cardInstanceIds
            : command.type === "choose_player" ? command.playerIds : command.orderedIds;
        const id = single(selections);
        const aliases = obj(payload.responseAliases) ?? {};
        if (!selectableTargetIDs(prompt).includes(id) || aliases[id] !== undefined) throw invalid("Target is not a canonical legal choice");
        return answer("uuid", id);
      }
      case "PICK_TARGET|answer_yes_no": case "CHOOSE_ABILITY|answer_yes_no": case "PICK_ABILITY|answer_yes_no":
        if (bool(payload.required) !== false || command.confirmed !== false) throw invalid("Target choice cannot be cancelled");
        return answer("boolean", false);
      case "ASK|answer_yes_no":
        if (command.confirmed === undefined) throw invalid("Missing confirmation");
        return answer("boolean", command.confirmed);
      case "SELECT|pass_priority":
        if (selectMode !== "priority") throw invalid("Not a priority prompt");
        return answer("boolean", true);
      case "PLAY_MANA|resolve_choice":
        if (command.choiceIds?.length !== 1 || command.choiceIds[0] !== "special") throw invalid("Invalid special payment token");
        return answer("string", "special");
      case "SELECT|resolve_choice":
        if (command.choiceIds?.length !== 1 || command.choiceIds[0] !== "special" || str(at(payload, "options", "specialButton")) === undefined) {
          throw invalid("Missing special control");
        }
        return answer("string", "special");
      case "SELECT|cast_spell": case "SELECT|play_land": case "SELECT|activate_ability": case "SELECT|make_mana": {
        const id = command.sourceInstanceId ?? command.cardInstanceId;
        if (selectMode !== "priority" || !isUuid(id)) throw invalid("Missing source UUID");
        return answer("uuid", id);
      }
      default:
        throw invalid(`Incompatible command ${command.type} for ${prompt.kind}`);
    }
  },

  /** The engine's answer actions for a command's requested ones, only where they fit this prompt (docs/PROTOCOL.md). */
  answerActions(requested: string[], command: GameCommand, prompt: EnginePrompt): J[] {
    return requested.map((type): J => {
      const options = obj(prompt.payload.options);
      if (type === "rememberAnswer" && prompt.kind === "ASK" && command.type === "answer_yes_no") {
        if (str(options?.originalId) === undefined || str(options?.autoAnswerMessage) === undefined) throw invalid("This question cannot be remembered");
        return { type, scope: "ability" };
      }
      if (type === "rememberTriggerFirst" && prompt.kind === "PICK_ABILITY" && command.type === "choose_ability") return { type };
      if (type === "passUntilStackResolved" && prompt.kind === "SELECT" && command.type === "pass_priority" && str(prompt.payload.selectMode) === "priority") {
        return { type };
      }
      throw invalid(`${type} does not fit this decision`);
    });
  },

  /** The answer with standing instructions attached; unchanged when there are none. */
  withActions(answer: J, actions: J[]): J {
    const fields = obj(answer);
    return actions.length === 0 || !fields ? answer : { ...fields, actions };
  },
};
