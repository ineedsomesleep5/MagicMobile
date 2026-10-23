/**
 * Game speed (Options → Gameplay): how long the board keeps each opponent action on screen. Presentation only: the
 * engine never waits for it and nothing the player sends is delayed. Snapshots reach the board through a
 * PresentationPacer, which shows them in order no faster than the speed allows, and smart pass waits until the board
 * has caught up (BoardPresentationHold.paceUntil).
 *
 * - Fast: every snapshot as it arrives (the board before game speeds existed).
 * - Standard (the default): each opponent action (a turn starting, a land played, a spell cast or ability put on the
 *   stack, attackers or blockers declared, a permanent entering or leaving) stays on screen at least 0.6 s.
 * - Relaxed: 1.1 s per opponent action, and every step the turn passes through shows for 0.35 s.
 */
import { BoardEventDiffer, fxState, normalizedStep, revisionKey } from "./boardEvents";
import { type GameSnapshot, isCompleted } from "./models";

export type GameSpeed = "relaxed" | "standard" | "fast";
export const GAME_SPEED_KEY = "mm.web.gameSpeed";
export const GAME_SPEEDS: readonly GameSpeed[] = ["relaxed", "standard", "fast"];
export const GAME_SPEED_TITLES: Record<GameSpeed, string> = { relaxed: "Relaxed", standard: "Standard", fast: "Fast" };

/** Seconds on screen: per opponent action, and per step the turn passes through. */
export const GAME_PACE: Record<GameSpeed, { action: number; step: number }> = {
  relaxed: { action: 1.1, step: 0.35 },
  standard: { action: 0.6, step: 0 },
  fast: { action: 0, step: 0 },
};

/** The board never falls further behind the game than this: older actions are cut short to catch up (a skip can run ahead). */
export const MAX_PACE_LAG = 4;
/** At a table with people a turn clock runs, so the board may fall at most this far behind before your prompt shows. */
export const TABLE_PACE_LAG = 1.5;

export function loadGameSpeed(read: (key: string) => string | undefined): GameSpeed {
  const stored = read(GAME_SPEED_KEY);
  return GAME_SPEEDS.includes(stored as GameSpeed) ? (stored as GameSpeed) : "standard";
}

export type OpponentAction = "turn" | "cast" | "enter" | "leave" | "attack" | "block" | "take";

/** What an opponent visibly did between two snapshots of the same game (never the viewer's own actions). */
export function opponentActions(previous: GameSnapshot, next: GameSnapshot): OpponentAction[] {
  const viewer = next.viewerPlayerId;
  if (previous.id !== next.id || viewer === undefined) return [];
  const found = new Set<OpponentAction>();
  const theirTurn = next.activePlayerId !== undefined && next.activePlayerId !== viewer;
  if (theirTurn && (next.turn !== previous.turn || next.activePlayerId !== previous.activePlayerId)) found.add("turn");
  const old = fxState(previous);
  const now = fxState(next);
  // A permanent that leaves because the viewer's own spell or ability resolved is the viewer's action; one an opponent's
  // resolution took is theirs, whoever's permanent it was.
  const stillThere = new Set(now.stack.map((item) => item.id));
  const resolved = old.stack.filter((item) => !stillThere.has(item.id));
  const ownResolution = resolved.length > 0 && resolved.every((item) => item.controllerID === viewer);
  const theirResolution = resolved.some((item) => item.controllerID !== undefined && item.controllerID !== viewer);
  const owner = (id: string) => now.cards.get(id)?.playerID ?? old.cards.get(id)?.playerID;
  for (const event of BoardEventDiffer.events(old, now)) {
    switch (event.type) {
      case "spellCast": if (event.controllerID !== undefined && event.controllerID !== viewer) found.add("cast"); break;
      case "enteredBattlefield": if (event.playerID !== viewer) found.add("enter"); break;
      case "attackDeclared": if (owner(event.cardID) !== viewer) found.add("attack"); break;
      case "blockDeclared": if (owner(event.cardID) !== viewer) found.add("block"); break;
      case "leftBattlefield": if (theirResolution || (!ownResolution && (event.playerID !== viewer || theirTurn))) found.add("leave"); break;
      case "controlChanged": if (event.to !== viewer) found.add("take"); break;
      default: break;
    }
  }
  return [...found];
}

/** How long `next` stays on screen before the snapshot after it shows. */
export function presentationDwell(previous: GameSnapshot, next: GameSnapshot, speed: GameSpeed): number {
  const pace = GAME_PACE[speed];
  if ((pace.action <= 0 && pace.step <= 0) || previous.id !== next.id) return 0;
  let dwell = pace.action > 0 && opponentActions(previous, next).length > 0 ? pace.action : 0;
  if (pace.step > 0 && normalizedStep(previous.step ?? previous.phase) !== normalizedStep(next.step ?? next.phase)) dwell = Math.max(dwell, pace.step);
  return dwell;
}

/**
 * The board's queue of snapshots (times in seconds on any clock the caller passes). `offer` each snapshot the session
 * publishes, `advance` whenever time passes, and show `shown`. Snapshots without anything to dwell on pass straight
 * through, so the board only lags behind the game while an opponent's action is on screen. A new game, a finished game
 * and the Fast speed show the newest snapshot at once; nothing offered is ever reordered, and the newest is always shown
 * in the end.
 */
export class PresentationPacer {
  shown?: GameSnapshot;
  /** When the shown snapshot's time on screen ends. */
  shownUntil = 0;
  private newest?: GameSnapshot;
  private queue: { snapshot: GameSnapshot; dwell: number }[] = [];

  constructor(public speed: GameSpeed, public maxLag = MAX_PACE_LAG) {}

  /** Snapshots offered but not shown yet. */
  get behind() { return this.queue.length > 0; }

  /** When the next queued snapshot shows (undefined when none waits). */
  get nextAt(): number | undefined { return this.queue.length > 0 ? this.shownUntil : undefined; }

  offer(snapshot: GameSnapshot | undefined, now: number) {
    if (snapshot === this.newest) return;
    const previous = this.newest;
    this.newest = snapshot;
    if (!snapshot || !previous || this.speed === "fast" || previous.id !== snapshot.id || isCompleted(snapshot)) {
      this.showNow(snapshot, now);
      return;
    }
    // A refreshed copy of the same revision takes its predecessor's place in the line.
    if (revisionKey(previous) === revisionKey(snapshot)) {
      const last = this.queue.at(-1);
      if (last) last.snapshot = snapshot; else this.shown = snapshot;
      return;
    }
    this.queue.push({ snapshot, dwell: presentationDwell(previous, snapshot, this.speed) });
    this.advance(now);
  }

  /** Shows whatever is due by `now`; true when the shown snapshot changed. */
  advance(now: number): boolean {
    const before = this.shown;
    while (this.queue.length > 0 && (now >= this.shownUntil || this.settledAt(now) - now > this.maxLag)) {
      const { snapshot, dwell } = this.queue.shift()!;
      this.shown = snapshot;
      this.shownUntil = now + dwell;
    }
    return this.shown !== before;
  }

  /** When the newest snapshot offered will have shown and had its time on screen. */
  settledAt(now: number): number {
    let at = Math.max(now, this.shownUntil);
    for (const item of this.queue) at += item.dwell;
    return at;
  }

  setSpeed(speed: GameSpeed, now: number) {
    if (speed === this.speed) return;
    this.speed = speed;
    if (speed === "fast") this.showNow(this.newest, now);
  }

  private showNow(snapshot: GameSnapshot | undefined, now: number) {
    this.queue = [];
    this.shown = snapshot;
    this.shownUntil = now;
  }
}
