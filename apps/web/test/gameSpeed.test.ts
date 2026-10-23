/** Game speed (core/gameSpeed.ts): which changes are an opponent's action, and the board's pacer on an injected clock. */
import { describe, expect, it } from "vitest";
import { GAME_PACE, loadGameSpeed, MAX_PACE_LAG, opponentActions, PresentationPacer, presentationDwell, TABLE_PACE_LAG } from "../src/core/gameSpeed";
import type { GameSnapshot, PromptEnvelopeV2, XmageStackObject, ZoneCard } from "../src/core/models";
import { commanderEntries } from "../src/core/arenaBoard";
import { HOLD_INSPECT, HoldPress } from "../src/ui/arena/inspectGesture";
import { BoardPresentationHold, revisionKey } from "../src/core/boardEvents";
import { GuestSession } from "../src/table/guestSession";

const card = (id: string, name: string, typeLine = "Creature — Bear", extra: Partial<ZoneCard> = {}): ZoneCard => ({ instanceId: id, card: { name, typeLine }, ...extra });
const zones = (battlefield: ZoneCard[] = [], more: Partial<Record<"graveyard" | "command" | "hand", ZoneCard[]>> = {}) => ({
  library: [], hand: more.hand ?? [], battlefield, graveyard: more.graveyard ?? [], exile: [], command: more.command ?? [], stack: [], handCount: 3, libraryCount: 50,
});

let revision = 0;
/** A two-player snapshot: "me" (the viewer) and "ai". */
function snap(o: {
  turn?: number; active?: string; step?: string; mine?: ZoneCard[]; theirs?: ZoneCard[]; stack?: XmageStackObject[]; prompt?: boolean; id?: string;
  completed?: boolean; theirGraveyard?: ZoneCard[];
} = {}): GameSnapshot {
  revision += 1;
  return {
    id: o.id ?? "game", source: "xmage-ondevice", phase: "PRECOMBAT_MAIN", step: o.step ?? "PRECOMBAT_MAIN", turn: o.turn ?? 2, activePlayerId: o.active ?? "ai",
    viewerPlayerId: "me", log: [], bridgeRevision: revision, gameStatus: o.completed ? "completed" : "in_progress",
    players: [
      { playerId: "me", displayName: "You", life: 40, poison: 0, commanderTax: 0, zones: zones(o.mine) },
      { playerId: "ai", displayName: "AI", life: 40, poison: 0, commanderTax: 0, zones: zones(o.theirs, { graveyard: o.theirGraveyard }) },
    ],
    xmage: { schemaVersion: 1, gameId: o.id ?? "game", bridgeRevision: revision, callbackCoverage: [], stack: o.stack ?? [], combat: [], players: [], exileZones: [],
      revealed: [], lookedAt: [], companion: [], playableObjects: [], panels: {} as never },
    promptEnvelopeV2: o.prompt ? ({ id: `p${revision}`, messageId: revision, playerId: "me", responseKind: "priority", method: "GAME_SELECT", message: "" } as unknown as PromptEnvelopeV2) : undefined,
  } as GameSnapshot;
}
const spell = (id: string, name: string, controllerId: string): XmageStackObject => ({ id, name, controllerId, objectType: "SPELL", sourceCard: card(`${id}-card`, name, "Sorcery") });

describe("opponent actions", () => {
  it("sees an opponent's land, spell, creature, attack and turn, never the viewer's own", () => {
    const base = snap();
    expect(opponentActions(base, snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")] }))).toEqual(["enter"]);
    expect(opponentActions(base, snap({ stack: [spell("s1", "Shock", "ai")] }))).toEqual(["cast"]);
    expect(opponentActions(base, snap({ stack: [spell("s1", "Shock", "me")] }))).toEqual([]);
    expect(opponentActions(base, snap({ mine: [card("m1", "Grizzly Bears")] }))).toEqual([]);
    const ready = snap({ theirs: [card("c1", "Bear")] });
    expect(opponentActions(ready, snap({ theirs: [card("c1", "Bear", undefined, { isAttacking: true })] }))).toEqual(["attack"]);
    expect(opponentActions(snap({ turn: 3, active: "me" }), snap({ turn: 4, active: "ai" }))).toEqual(["turn"]);
    expect(opponentActions(snap({ turn: 4, active: "ai" }), snap({ turn: 5, active: "me" }))).toEqual([]);
  });

  it("counts a permanent leaving unless the viewer's own spell took it on the viewer's turn", () => {
    const before = snap({ active: "me", theirs: [card("c1", "Bear")], stack: [spell("s1", "Murder", "me")] });
    expect(opponentActions(before, snap({ active: "me", theirGraveyard: [card("c1", "Bear")] }))).toEqual([]);
    const theirs = snap({ active: "me", mine: [card("m1", "Bear")], stack: [spell("s2", "Murder", "ai")] });
    expect(opponentActions(theirs, snap({ active: "me" }))).toEqual(["leave"]);
  });

  it("holds an opponent action at the speed's pace; Relaxed also shows every step", () => {
    const before = snap();
    const land = snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")] });
    expect(presentationDwell(before, land, "fast")).toBe(0);
    expect(presentationDwell(before, land, "standard")).toBe(GAME_PACE.standard.action);
    expect(presentationDwell(before, land, "relaxed")).toBe(GAME_PACE.relaxed.action);
    const step = snap({ step: "BEGIN_COMBAT" });
    expect(presentationDwell(before, step, "standard")).toBe(0);
    expect(presentationDwell(before, step, "relaxed")).toBe(GAME_PACE.relaxed.step);
    expect(presentationDwell(snap({ id: "a" }), snap({ id: "b", stack: [spell("s1", "Shock", "ai")] }), "relaxed")).toBe(0);
  });

  it("reads the stored speed, Standard by default", () => {
    expect(loadGameSpeed(() => undefined)).toBe("standard");
    expect(loadGameSpeed(() => "relaxed")).toBe("relaxed");
    expect(loadGameSpeed(() => "warp")).toBe("standard");
  });
});

describe("PresentationPacer", () => {
  it("Fast shows every snapshot as it arrives", () => {
    const pacer = new PresentationPacer("fast");
    const a = snap(); const b = snap({ stack: [spell("s1", "Shock", "ai")] }); const c = snap({ theirs: [card("x", "Bear")] });
    pacer.offer(a, 0); pacer.offer(b, 0.01); pacer.offer(c, 0.02);
    expect(pacer.shown).toBe(c);
    expect(pacer.behind).toBe(false);
  });

  it("Standard keeps each opponent action on screen 0.6 s, in order, and never drops the newest", () => {
    const pacer = new PresentationPacer("standard");
    const start = snap();
    const land = snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")] });
    const cast = snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")], stack: [spell("s1", "Shock", "ai")] });
    const prompt = snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")], stack: [spell("s1", "Shock", "ai")], prompt: true });
    pacer.offer(start, 0);
    pacer.offer(land, 0.1);
    expect(pacer.shown).toBe(land);
    pacer.offer(cast, 0.2);
    pacer.offer(prompt, 0.3);
    expect(pacer.shown).toBe(land);
    expect(pacer.behind).toBe(true);
    expect(pacer.nextAt).toBeCloseTo(0.7);
    expect(pacer.settledAt(0.3)).toBeCloseTo(1.3);
    pacer.advance(0.69);
    expect(pacer.shown).toBe(land);
    pacer.advance(0.7);
    expect(pacer.shown).toBe(cast);
    pacer.advance(1.29);
    expect(pacer.shown).toBe(cast);
    // The prompt (nothing new on the table) shows the moment the spell's time is up, and nothing waits behind it.
    pacer.advance(1.3);
    expect(pacer.shown).toBe(prompt);
    expect(pacer.behind).toBe(false);
  });

  it("lets the viewer's own actions through without a hold", () => {
    const pacer = new PresentationPacer("relaxed");
    const start = snap({ active: "me" });
    pacer.offer(start, 0);
    const mine = snap({ active: "me", stack: [spell("s1", "Shock", "me")] });
    pacer.offer(mine, 0.05);
    expect(pacer.shown).toBe(mine);
    const resolved = snap({ active: "me", mine: [card("m1", "Bear")] });
    pacer.offer(resolved, 0.1);
    expect(pacer.shown).toBe(resolved);
    expect(pacer.settledAt(0.1)).toBeCloseTo(0.1);
  });

  it("shows a finished game, a new game or a switch to Fast at once", () => {
    const pacer = new PresentationPacer("relaxed");
    pacer.offer(snap(), 0);
    pacer.offer(snap({ stack: [spell("s1", "Shock", "ai")] }), 0.1);
    const queued = snap({ stack: [spell("s2", "Bolt", "ai"), spell("s1", "Shock", "ai")] });
    pacer.offer(queued, 0.2);
    expect(pacer.shown).not.toBe(queued);
    const over = snap({ completed: true });
    pacer.offer(over, 0.25);
    expect(pacer.shown).toBe(over);
    const next = snap({ id: "rematch", stack: [spell("s9", "Shock", "ai")] });
    pacer.offer(next, 0.3);
    expect(pacer.shown).toBe(next);
    pacer.offer(snap({ id: "rematch", theirs: [card("x", "Bear")] }), 0.4);
    const last = snap({ id: "rematch", theirs: [card("x", "Bear"), card("y", "Bear")] });
    pacer.offer(last, 0.5);
    pacer.setSpeed("fast", 0.6);
    expect(pacer.shown).toBe(last);
    expect(pacer.behind).toBe(false);
  });

  it("never falls more than the lag cap behind the game", () => {
    const pacer = new PresentationPacer("relaxed");
    pacer.offer(snap(), 0);
    const permanents: ZoneCard[] = [];
    for (let i = 0; i < 12; i++) {
      permanents.push(card(`t${i}`, "Bear"));
      pacer.offer(snap({ theirs: [...permanents] }), 0.01 * i);
    }
    expect(pacer.settledAt(0.12) - 0.12).toBeLessThanOrEqual(MAX_PACE_LAG + GAME_PACE.relaxed.action);
  });

  it("falls at most 1.5 s behind at a table with people, where a turn clock runs", () => {
    const pacer = new PresentationPacer("relaxed", TABLE_PACE_LAG);
    pacer.offer(snap(), 0);
    const permanents: ZoneCard[] = [];
    for (let i = 0; i < 12; i++) {
      permanents.push(card(`t${i}`, "Bear"));
      pacer.offer(snap({ theirs: [...permanents] }), 0.01 * i);
    }
    expect(pacer.settledAt(0.12) - 0.12).toBeLessThanOrEqual(TABLE_PACE_LAG + GAME_PACE.relaxed.action);
  });

  it("replaces a refreshed copy of the same revision where it stands", () => {
    const pacer = new PresentationPacer("standard");
    pacer.offer(snap(), 0);
    const land = snap({ theirs: [card("l1", "Forest", "Basic Land — Forest")] });
    pacer.offer(land, 0.1);
    const copy = { ...land, promptEnvelopeV2: undefined };
    pacer.offer(copy, 0.2);
    expect(pacer.shown).toBe(copy);
    expect(pacer.behind).toBe(false);
  });
});

describe("press and hold to read", () => {
  /** A fake timer: `tick` runs what is due. */
  function clock() {
    let now = 0; let next = 0;
    const timers = new Map<number, { at: number; run: () => void }>();
    return {
      schedule: (run: () => void, millis: number) => { next += 1; timers.set(next, { at: now + millis, run }); return next; },
      cancel: (id: unknown) => { timers.delete(id as number); },
      tick(millis: number) { now += millis; for (const [id, t] of [...timers]) if (t.at <= now) { timers.delete(id); t.run(); } },
    };
  }

  it("opens after a still hold and closes on release", () => {
    const c = clock();
    const press = new HoldPress(c.schedule, c.cancel);
    let opened = 0;
    press.down(100, 100, () => { opened += 1; });
    c.tick(HOLD_INSPECT.millis - 1);
    expect(opened).toBe(0);
    press.move(103, 104);
    c.tick(1);
    expect(opened).toBe(1);
    expect(press.up()).toBe(true);
  });

  it("never opens for a click or a drag", () => {
    const c = clock();
    const press = new HoldPress(c.schedule, c.cancel);
    let opened = 0;
    press.down(0, 0, () => { opened += 1; });
    c.tick(200);
    expect(press.up()).toBe(false);
    press.down(0, 0, () => { opened += 1; });
    press.move(HOLD_INSPECT.slop + 1, 0);
    c.tick(1000);
    expect(press.up()).toBe(false);
    expect(opened).toBe(0);
  });
});

describe("commander browser entries", () => {
  it("lists partners in order with their casts and tax, wherever each card is", () => {
    const snapshot = snap();
    const me = snapshot.players[0];
    me.zones.command = [card("k1", "Kraum, Ludevic's Opus", "Legendary Creature — Zombie Horror")];
    me.zones.battlefield = [card("t1", "Tymna the Weaver", "Legendary Creature — Human Cleric")];
    me.commanders = [
      { id: "c-tymna", name: "Tymna the Weaver", ownerPlayerId: "me", castsFromCommandZone: 1, commanderTax: 2 },
      { id: "c-kraum", name: "Kraum, Ludevic's Opus", ownerPlayerId: "me", castsFromCommandZone: 0, commanderTax: 0 },
    ];
    const entries = commanderEntries(me, snapshot);
    expect(entries.map((e) => [e.name, e.zone, e.casts, e.tax, e.card?.instanceId])).toEqual([
      ["Tymna the Weaver", "battlefield", 1, 2, "t1"],
      ["Kraum, Ludevic's Opus", "command", 0, 0, "k1"],
    ]);
  });

  it("falls back to the command zone's cards and the player's known tax", () => {
    const snapshot = snap();
    const me = snapshot.players[0];
    me.zones.command = [card("k1", "Atraxa, Praetors' Voice", "Legendary Creature — Phyrexian Angel Horror")];
    me.commanderTaxKnown = true;
    me.commanderTax = 4;
    expect(commanderEntries(me, snapshot).map((e) => [e.name, e.zone, e.tax])).toEqual([["Atraxa, Praetors' Voice", "command", 4]]);
  });
});

describe("smart pass waits for a paced board", () => {
  const seconds = () => performance.now() / 1000;
  const waiting = (hold: BoardPresentationHold, snapshot: GameSnapshot) => {
    const session = new GuestSession(async () => "{}", "game", "me", () => undefined, "local");
    session.state = { ...session.state, snapshot };
    session.presentationHold = hold;
    return (session as unknown as { waitForBoardPresentation(): Promise<void> }).waitForBoardPresentation();
  };

  it("goes at once at the Fast speed once the board has the snapshot", async () => {
    const snapshot = snap();
    const hold = new BoardPresentationHold();
    hold.record(revisionKey(snapshot), undefined);
    const start = seconds();
    await waiting(hold, snapshot);
    expect(seconds() - start).toBeLessThan(0.1);
  });

  it("waits until the board has shown the snapshot and its pace has run out", async () => {
    const snapshot = snap();
    const hold = new BoardPresentationHold();
    const start = seconds();
    hold.paceUntil = start + 0.3;
    // The board is behind: it shows this snapshot only at 0.15 s, then its own action holds it to 0.3 s.
    setTimeout(() => hold.record(revisionKey(snapshot), undefined), 150);
    await waiting(hold, snapshot);
    expect(seconds() - start).toBeGreaterThanOrEqual(0.29);
    expect(seconds() - start).toBeLessThan(0.6);
  });
});
