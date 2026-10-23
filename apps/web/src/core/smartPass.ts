/**
 * Port of OnDeviceSmartPass.kt (iOS OnDeviceYieldPolicy.swift) and the parts of OnDeviceYieldPolicy it needs.
 * Arena-style smart pass (Caleb, 2026-10-11): when this seat has ordinary priority and nothing it could do, or
 * nothing it asked to stop for, the session passes on its behalf. Local scheduling of the same ordinary pass a
 * tap sends; XMage stays the authority for what is playable. Checked by test/smartPass.test.ts (the Kotlin cases).
 */
import { stackTopFirst } from "./boardEvents";
import type { MatchPoll } from "./engineClient";
import { arr, bool, get, int, type J, obj, str } from "./json";
import type { GameSnapshot } from "./models";

export interface YieldPrompt { id: string; revision: number; kind: string; selectMode?: string; allowsBoolean: boolean; submitted: boolean; manaPlayerID?: string }

export interface YieldContext {
  matchID: string; seatID: string; viewerID: string; activePlayerID?: string; turn: number; phase: string;
  localHumanEnabled: boolean; foreground: boolean; emptyStack: boolean; selfAuthority: boolean; resyncRequired: boolean;
  prompt?: YieldPrompt;
  /** An opponent's spell or ability on the stack threatens what you control and you asked to stop for those: even a skip that passes responses stops. */
  threatToMe?: boolean;
}

/** OnDeviceYieldPolicy.ordinaryPriority: the seat's own plain priority, which a pass answers without choosing anything. */
export const ordinaryPriority = (prompt: YieldPrompt, viewer: string) =>
  prompt.id.length > 0 && prompt.revision >= 0 && prompt.kind === "SELECT" && prompt.selectMode === "priority" &&
  prompt.allowsBoolean && prompt.manaPlayerID === viewer;

/** Action IDs of passes the session sends for the player: smart pass, and the skip modes. */
export const SMART_PASS_ACTION_PREFIX = "smart-pass-";
export const YIELD_PASS_ACTION_PREFIX = "auto-pass-";
/** A pass the player didn't tap: it answers only ordinary priority, so no waiting pop-up shows for it. */
export const isAutomaticPass = (actionID: string | undefined) =>
  actionID !== undefined && (actionID.startsWith(SMART_PASS_ACTION_PREFIX) || actionID.startsWith(YIELD_PASS_ACTION_PREFIX));

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
  /** Stop for an opponent's spell or ability that threatens your permanents, response or not (Stop for Removal, on). */
  stopForThreats: boolean;
}
export const defaultSmartPass: SmartPassSettings = { enabled: true, stops: defaultStops, stopForOwnSpells: false, stopForThreats: true };

/** Where the settings live (the iOS UserDefaults keys' web names). */
export const SMART_PASS_KEYS = {
  enabled: "mm.web.smartAutoPass", stops: "mm.web.phaseStops", stopForOwnSpells: "mm.web.stopForOwnSpells", stopForThreats: "mm.web.stopForThreats",
} as const;

/** Settings.load: smart pass on, Stop for Own Spells off, Stop for Removal on, the default stops unless some were saved. */
export function loadSmartPass(read: (key: string) => string | undefined): SmartPassSettings {
  return {
    enabled: read(SMART_PASS_KEYS.enabled) !== "off", stops: decodeStops(read(SMART_PASS_KEYS.stops)),
    stopForOwnSpells: read(SMART_PASS_KEYS.stopForOwnSpells) === "on", stopForThreats: read(SMART_PASS_KEYS.stopForThreats) !== "off",
  };
}

export function saveSmartPass(settings: SmartPassSettings, write: (key: string, value: string) => void) {
  write(SMART_PASS_KEYS.enabled, settings.enabled ? "on" : "off");
  write(SMART_PASS_KEYS.stops, encodeStops(settings.stops));
  write(SMART_PASS_KEYS.stopForOwnSpells, settings.stopForOwnSpells ? "on" : "off");
  write(SMART_PASS_KEYS.stopForThreats, settings.stopForThreats ? "on" : "off");
}

/** Stored stops: a sorted comma list; nothing stored means the defaults, an empty string means no stops. */
export const encodeStops = (stops: ReadonlySet<string>) => [...stops].sort().join(",");
export const decodeStops = (raw: string | undefined | null): Set<string> =>
  raw === undefined || raw === null ? new Set(defaultStops) : new Set(raw.split(",").filter((s) => s.length > 0));

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
  /** The top of the stack is an opponent's and threatens what you control (`threatensViewer`). */
  threatensMe?: boolean;
}

/** The prompt to pass, or undefined when the player should decide. */
export function passPrompt(value: Situation, settings: SmartPassSettings): YieldPrompt | undefined {
  const { context } = value;
  const active = context.activePlayerID;
  const prompt = context.prompt;
  if (!settings.enabled || !context.localHumanEnabled || !context.foreground || context.phase !== "running" || context.turn <= 0 ||
    !context.selfAuthority || context.resyncRequired || !active || !prompt || prompt.submitted ||
    !ordinaryPriority(prompt, context.viewerID) || value.manaFloating) return undefined;
  // An opponent's removal or sweeper waits for you to read it and let it resolve, answer or not.
  if (!context.emptyStack && value.threatensMe === true && settings.stopForThreats && value.topStackIsMine !== true) return undefined;
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

const SWEEPS = ["destroy all", "exile all", "destroy each", "exile each", "return all", "all creatures", "each creature",
  "all nonland permanents", "each nonland permanent", "all other creatures", "sacrifices", "gain control of all", "gains control of all"];

/**
 * Whether the top of the stack is an opponent's spell or ability that would destroy, exile, bounce, damage or take what
 * you control: it targets one of your permanents (or you, when it is a spell), or it is an untargeted sweeper, edict or
 * steal by its rules text. A hint for when to stop and let you read, never a rules decision.
 */
export function threatensViewer(snapshot: GameSnapshot): boolean {
  const top = stackTopFirst(snapshot)[0];
  const viewerID = snapshot.viewerPlayerId ?? "human";
  const isViewer = (id: string) => id === viewerID;
  const viewer = snapshot.players.find((p) => isViewer(p.playerId));
  if (!top || top.controllerId === undefined || isViewer(top.controllerId) || !viewer) return false;
  const mine = new Set(viewer.zones.battlefield.map((c) => c.instanceId));
  const targets = new Set(top.targetIds ?? []);
  if ([...targets].some((t) => mine.has(t))) return true;
  const isSpell = (top.objectType ?? "").toUpperCase() === "SPELL";
  if (isSpell && (targets.has(viewer.playerId) || targets.has(viewerID))) return true;
  if (targets.size > 0 || mine.size === 0) return false;
  const text = (top.rulesText ?? "").toLowerCase();
  return SWEEPS.some((phrase) => text.includes(phrase));
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
export function yieldContext(poll: MatchPoll, foreground: boolean, threatToMe = false): YieldContext | undefined {
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
    threatToMe: Object.keys(stack).length > 0 && threatToMe,
  };
}

/** The whole situation for smart pass from one poll; `snapshot` is the adapted board (for the threat check). */
export function situation(poll: MatchPoll, foreground: boolean, snapshot?: GameSnapshot): Situation | undefined {
  const context = yieldContext(poll, foreground);
  if (!context) return undefined;
  const view = get(poll.snapshot, "gameView");
  const owner = arr(get(view, "players"))?.find((p) => str(get(p, "playerId")) === context.viewerID);
  return {
    context, step: str(get(view, "step")), hasPlay: hasPlay(view), manaFloating: manaFloating(owner),
    topStackIsMine: topStackIsMine(poll.snapshot, context.viewerID), hasResponse: hasResponse(view),
    threatensMe: !context.emptyStack && snapshot !== undefined && threatensViewer(snapshot),
  };
}

// ---------------- the skip modes (OnDeviceYieldPolicy) ----------------

/** Local scheduling only: every pass still answers an ordinary engine prompt. No skip commands, inferred choices or rules. */
export type YieldMode = "safeEndTurn" | "endTurnSkippingResponses" | "untilMyTurn";
export const YieldModes: Record<YieldMode, { duration: number; passLimit: number; status: string }> = {
  safeEndTurn: { duration: 60, passLimit: 64, status: "Auto-passing routine priority this turn. Stop at any time." },
  endTurnSkippingResponses: { duration: 120, passLimit: 256,
    status: "Skipping responses this turn, including the stack. Stops for choices or after 120 seconds / 256 passes." },
  untilMyTurn: { duration: 180, passLimit: 256,
    status: "Skipping responses until your next turn, including the stack. Stops for choices or after 180 seconds / 256 passes." },
};
export type StopReason = "unavailable" | "turnChanged" | "controlChanged" | "stack" | "decision" | "interrupted" | "limit" | "threat";
export const STOP_MESSAGES: Record<StopReason, string> = {
  unavailable: "Auto-pass stopped. Pass priority manually.",
  turnChanged: "Auto-pass stopped. The turn changed.",
  controlChanged: "Auto-pass stopped. Player control changed.",
  stack: "Auto-pass stopped. Check the stack.",
  decision: "Auto-pass stopped. A choice needs your attention.",
  interrupted: "Auto-pass stopped. Review the current game state.",
  limit: "Auto-pass stopped after its safety limit.",
  threat: "Auto-pass stopped. An opponent's spell threatens your permanents.",
};
export type YieldDecision = { kind: "wait" } | { kind: "pass"; prompt: YieldPrompt } | { kind: "stop"; reason: StopReason };

export class YieldPolicy {
  private anchor?: YieldContext;
  private mode: YieldMode = "safeEndTurn";
  private expiresAt = 0;
  private attempted = new Set<string>();
  private latestRevision = -1;
  get isActive() { return this.anchor !== undefined; }
  get currentMode() { return this.mode; }

  static canStart(value: YieldContext, mode: YieldMode = "safeEndTurn"): boolean {
    const active = value.activePlayerID;
    if (!value.localHumanEnabled || !value.foreground || value.phase !== "running" || value.turn <= 0 || !active || !value.selfAuthority ||
      value.resyncRequired) return false;
    if (!(mode === "untilMyTurn" || active === value.viewerID) || !(mode !== "safeEndTurn" || value.emptyStack)) return false;
    // Waiting on an opponent is safe to arm; it does not authorize an answer.
    if (!value.prompt) return mode === "untilMyTurn";
    if (value.prompt.submitted) return false;
    return ordinaryPriority(value.prompt, value.viewerID);
  }

  start(value: YieldContext, now: number, mode: YieldMode = "safeEndTurn"): boolean {
    if (!YieldPolicy.canStart(value, mode)) return false;
    this.mode = mode;
    this.anchor = value; this.expiresAt = now + YieldModes[mode].duration; this.attempted.clear(); this.latestRevision = -1;
    return true;
  }

  stop() { this.anchor = undefined; this.attempted.clear(); this.latestRevision = -1; }

  evaluate(value: YieldContext, now: number): YieldDecision {
    const anchor = this.anchor;
    if (!anchor) return { kind: "wait" };
    const turnBoundary = this.mode === "untilMyTurn"
      ? value.activePlayerID === value.viewerID && (value.turn !== anchor.turn || anchor.activePlayerID !== anchor.viewerID)
      : value.turn !== anchor.turn || value.activePlayerID !== anchor.activePlayerID;
    const prompt = value.prompt;
    let reason: StopReason | undefined;
    if (!value.localHumanEnabled || value.phase !== "running") reason = "unavailable";
    else if (!value.foreground || value.resyncRequired) reason = "interrupted";
    else if (value.matchID !== anchor.matchID || value.seatID !== anchor.seatID || value.viewerID !== anchor.viewerID || !value.selfAuthority) reason = "controlChanged";
    else if (value.turn < anchor.turn || !value.activePlayerID) reason = "interrupted";
    else if (turnBoundary) reason = "turnChanged";
    else if (this.mode === "safeEndTurn" && !value.emptyStack) reason = "stack";
    else if (value.threatToMe === true && !value.emptyStack) reason = "threat";
    else if (now >= this.expiresAt || this.attempted.size >= YieldModes[this.mode].passLimit) reason = "limit";
    else if (prompt && prompt.manaPlayerID !== value.viewerID && prompt.kind === "SELECT" && prompt.selectMode === "priority") reason = "controlChanged";
    else if (prompt && !ordinaryPriority(prompt, value.viewerID)) reason = "decision";
    if (reason) { this.stop(); return { kind: "stop", reason }; }
    if (!prompt || prompt.submitted || this.attempted.has(prompt.id) || prompt.revision <= this.latestRevision) return { kind: "wait" };
    return { kind: "pass", prompt };
  }

  /** Reserve before dispatch, including uncertain or failed responses. Never auto-retry. */
  recordPass(prompt: YieldPrompt) {
    if (!this.isActive || this.attempted.size >= YieldModes[this.mode].passLimit) return;
    this.attempted.add(prompt.id); this.latestRevision = Math.max(this.latestRevision, prompt.revision);
  }
}
