/**
 * Port of OnDeviceSmartPass.kt (iOS OnDeviceYieldPolicy.swift) and the parts of OnDeviceYieldPolicy it needs.
 * Arena-style smart pass (Caleb, 2026-10-11): when this seat has ordinary priority and nothing it could do, or
 * nothing it asked to stop for, the session passes on its behalf. Local scheduling of the same ordinary pass a
 * tap sends; XMage stays the authority for what is playable. Checked by test/smartPass.test.ts (the Kotlin cases).
 */
import type { MatchPoll } from "./engineClient";
import { arr, bool, get, int, type J, obj, str } from "./json";

export interface YieldPrompt { id: string; revision: number; kind: string; selectMode?: string; allowsBoolean: boolean; submitted: boolean; manaPlayerID?: string }

export interface YieldContext {
  matchID: string; seatID: string; viewerID: string; activePlayerID?: string; turn: number; phase: string;
  localHumanEnabled: boolean; foreground: boolean; emptyStack: boolean; selfAuthority: boolean; resyncRequired: boolean;
  prompt?: YieldPrompt;
}

/** OnDeviceYieldPolicy.ordinaryPriority: the seat's own plain priority, which a pass answers without choosing anything. */
export const ordinaryPriority = (prompt: YieldPrompt, viewer: string) =>
  prompt.id.length > 0 && prompt.revision >= 0 && prompt.kind === "SELECT" && prompt.selectMode === "priority" &&
  prompt.allowsBoolean && prompt.manaPlayerID === viewer;

/** Action IDs of passes the session sends for the player (OnDeviceYieldPolicy.SMART_PASS_ACTION_PREFIX). */
export const SMART_PASS_ACTION_PREFIX = "smart-pass-";

/** The steps where a player can receive priority, in turn order. `key` matches iOS's raw values. */
export const Step = {
  UPKEEP: { key: "upkeep", title: "Upkeep" }, DRAW: { key: "draw", title: "Draw" }, MAIN1: { key: "main1", title: "Main 1" },
  BEGIN_COMBAT: { key: "beginCombat", title: "Beginning of combat" }, DECLARE_ATTACKERS: { key: "declareAttackers", title: "Declare attackers" },
  DECLARE_BLOCKERS: { key: "declareBlockers", title: "Declare blockers" }, COMBAT_DAMAGE: { key: "combatDamage", title: "Combat damage" },
  END_COMBAT: { key: "endCombat", title: "End of combat" }, MAIN2: { key: "main2", title: "Main 2" }, END: { key: "end", title: "End step" },
} as const;
export type StepValue = (typeof Step)[keyof typeof Step];

/** The engine's step name (`PRECOMBAT_MAIN`, `precombat-main`, …); undefined for a step that is unknown. */
export function stepFromEngine(raw: string | undefined): StepValue | undefined {
  switch (raw?.toLowerCase().replaceAll("_", "-")) {
    case "upkeep": return Step.UPKEEP;
    case "draw": return Step.DRAW;
    case "precombat-main": case "main1": return Step.MAIN1;
    case "begin-combat": case "combat": return Step.BEGIN_COMBAT;
    case "declare-attackers": return Step.DECLARE_ATTACKERS;
    case "declare-blockers": return Step.DECLARE_BLOCKERS;
    case "first-combat-damage": case "first-strike-damage": case "combat-damage": return Step.COMBAT_DAMAGE;
    case "end-combat": return Step.END_COMBAT;
    case "postcombat-main": case "main2": return Step.MAIN2;
    case "end-turn": case "end": case "ending": case "cleanup": return Step.END;
    default: return undefined;
  }
}

/** A stop on one step of your turns or of your opponents' turns, stored as "mine.main1" / "theirs.end". */
export const stopKey = (step: StepValue, myTurn: boolean) => (myTurn ? "mine." : "theirs.") + step.key;

/** Your main phases, and your opponents' attacks and end step: where instants usually matter. */
export const defaultStops: ReadonlySet<string> = new Set([stopKey(Step.MAIN1, true), stopKey(Step.MAIN2, true),
  stopKey(Step.DECLARE_ATTACKERS, false), stopKey(Step.END, false)]);

export interface SmartPassSettings {
  enabled: boolean;
  stops: ReadonlySet<string>;
  /** Stop for your own spells and triggers on the stack when you could respond to them (off, as on Arena). */
  stopForOwnSpells: boolean;
}
export const defaultSmartPass: SmartPassSettings = { enabled: true, stops: defaultStops, stopForOwnSpells: false };

/** What the latest poll says beyond the yield context. */
export interface Situation {
  context: YieldContext;
  step?: string;
  /** A land, spell or non-mana ability XMage offers this seat right now. */
  hasPlay: boolean;
  /** Mana floating in this seat's pool: passing would empty it, so the player decides. */
  manaFloating: boolean;
  /** The top of the stack is this seat's own (engine `stackControllers`); undefined when the engine doesn't say. */
  topStackIsMine?: boolean;
  /** Some non-mana play could answer the stack or a pending attack (engine `respondsToStack`, missing means yes). */
  hasResponse: boolean;
}

/** The prompt to pass, or undefined when the player should decide. */
export function passPrompt(value: Situation, settings: SmartPassSettings): YieldPrompt | undefined {
  const { context } = value;
  const active = context.activePlayerID;
  const prompt = context.prompt;
  if (!settings.enabled || !context.localHumanEnabled || !context.foreground || context.phase !== "running" || context.turn <= 0 ||
    !context.selfAuthority || context.resyncRequired || !active || !prompt || prompt.submitted ||
    !ordinaryPriority(prompt, context.viewerID) || value.manaFloating) return undefined;
  if (!value.hasPlay) return prompt;
  // Something on the stack: your own spell or trigger resolves (unless you asked to stop for those);
  // otherwise stop only when you hold a play that actually answers it.
  if (!context.emptyStack) {
    if (value.topStackIsMine === true && !settings.stopForOwnSpells) return prompt;
    return value.hasResponse ? undefined : prompt;
  }
  const step = stepFromEngine(value.step);
  if (!step) return undefined;
  // During an attack, a stop is worth making only with a play that answers it (a trick, a flash blocker).
  if ((step === Step.DECLARE_ATTACKERS || step === Step.DECLARE_BLOCKERS || step === Step.COMBAT_DAMAGE) && !value.hasResponse) return prompt;
  return settings.stops.has(stopKey(step, active === context.viewerID)) ? undefined : prompt;
}

const playableRows = (gameView: J | undefined): [string, J][] => {
  const objects = obj(get(get(gameView, "canPlayObjects"), "objects"));
  if (!objects) return [];
  return Object.values(objects).flatMap((stats) => Object.entries(obj(stats) ?? {})
    .flatMap(([category, rows]) => (arr(rows) ?? []).map((row) => [category, row] as [string, J])));
};
const isManaRow = (category: string, row: J) => bool(get(row, "manaAbility")) ?? (category === "basicManaAbilities");

/** Reads the engine's own playable list: lands, spells and non-mana abilities count, mana abilities don't. */
export const hasPlay = (gameView: J | undefined) => playableRows(gameView).some(([category, row]) => !isManaRow(category, row));

/** Whether some non-mana play could answer what is pending (engine `respondsToStack`, missing means yes). */
export const hasResponse = (gameView: J | undefined) =>
  playableRows(gameView).some(([category, row]) => !isManaRow(category, row) && bool(get(row, "respondsToStack")) !== false);

/** Whether the top stack object is the viewer's own; undefined when the engine doesn't send controllers. */
export function topStackIsMine(root: J | undefined, viewer: string): boolean | undefined {
  const controllers = obj(get(root, "stackControllers"));
  const top = str(arr(get(root, "stackOrder"))?.[0]);
  if (!controllers || top === undefined) return undefined;
  const controller = str(controllers[top]);
  return controller === undefined ? undefined : controller === viewer;
}

/** Whether this seat's raw player view shows mana in its pool. */
export const manaFloating = (player: J | undefined) => Object.values(obj(get(player, "manaPool")) ?? {}).some((amount) => (int(amount) ?? 0) > 0);

/** OnDeviceSession.yieldContext: the seat's view of the poll, or undefined when it isn't a plain local-human view. */
export function yieldContext(poll: MatchPoll, foreground: boolean): YieldContext | undefined {
  const root = poll.snapshot;
  const view = get(root, "gameView");
  const viewer = str(get(root, "enginePlayerId"));
  const turn = int(get(view, "turn"));
  const active = str(get(view, "activePlayerId"));
  const stack = obj(get(view, "stack"));
  const controls = obj(get(root, "controlledPlayerViews"));
  const owner = arr(get(view, "players"))?.find((p) => str(get(p, "playerId")) === viewer);
  const priority = bool(get(owner, "hasPriority"));
  const timer = bool(get(owner, "timerActive"));
  if (!viewer || str(get(view, "myPlayerId")) !== viewer || turn === undefined || !active || !stack || !controls || !owner ||
    bool(get(owner, "isHuman")) !== true || priority === undefined || timer === undefined) return undefined;
  const raw = poll.prompt;
  const prompt: YieldPrompt | undefined = raw && {
    id: raw.id, revision: raw.revision, kind: raw.kind, selectMode: str(raw.payload.selectMode), allowsBoolean: raw.responseTypes.includes("boolean"),
    submitted: raw.submitted, manaPlayerID: str(raw.payload.manaPlayerId),
  };
  // `controlled` is only a viewer marker upstream. A routed self-priority prompt and an active timer are required.
  const selfAuthority = Object.keys(controls).length === 0 && (!priority || timer) && (prompt === undefined || priority);
  return {
    matchID: poll.matchID, seatID: poll.seatID, viewerID: viewer, activePlayerID: active, turn, phase: poll.phase, localHumanEnabled: true,
    foreground, emptyStack: Object.keys(stack).length === 0, selfAuthority, resyncRequired: poll.resyncRequired, prompt,
  };
}

/** The whole situation for smart pass from one poll. */
export function situation(poll: MatchPoll, foreground: boolean): Situation | undefined {
  const context = yieldContext(poll, foreground);
  if (!context) return undefined;
  const view = get(poll.snapshot, "gameView");
  const owner = arr(get(view, "players"))?.find((p) => str(get(p, "playerId")) === context.viewerID);
  return {
    context, step: str(get(view, "step")), hasPlay: hasPlay(view), manaFloating: manaFloating(owner),
    topStackIsMine: topStackIsMine(poll.snapshot, context.viewerID), hasResponse: hasResponse(view),
  };
}
