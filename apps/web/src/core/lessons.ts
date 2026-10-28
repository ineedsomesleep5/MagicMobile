/**
 * The lessons (docs/LESSONS_TUTORIAL.md): short scripted games recorded from the real engine (scripts/lessons/record.py),
 * played back on the real board. LessonTransport stands where the engine would: it answers the board's polls with the
 * recorded views and accepts only the move the recording made. Port of iOS Lessons.swift (Android Lessons.kt); all three
 * read the same files. Checked by test/lessons.test.ts.
 */
import type { EngineTransport } from "./engineClient";
import { arr, bool, EngineError, EngineJson, get, int, type J, type JObject, jsonEqual, obj, str } from "./json";

export const LessonText = {
  title: "Lessons",
  coach: "Maren",
  gotIt: "Got it",
  next: "Next Lesson",
  done: "Done",
  complete: "Lesson complete",
  allComplete: "You know the basics. Play a guided game against an easy AI next, with tips as you go.",
  nudge: "Not that one. Follow the glow.",
  guided: "Guided game",
} as const;

/** The phones' words with the desktop's controls: click for tap, right-click for a long press (as Learn's pages do). */
export const forDesktop = (text: string) => text.replace(/\bPress and hold\b/g, "Right-click").replace(/\bTap\b/g, "Click").replace(/\btap\b/g, "click");

export const LESSONS_COMPLETED_KEY = "magicmobile.lessons.completed";

/** What the coach says on a frame: a title, a sentence or two, and what it points at. */
/** `desktop`: the web's own words where its board differs (everyone sits across the top, so there is no swapping). */
export interface LessonCoach { title?: string; text: string; desktop?: string; spot?: string; gesture?: string }
export interface LessonInfo { id: string; title: string }

export interface LessonFrame {
  poll: J;
  expect?: J;
  note: boolean;
  complete: boolean;
  coach?: LessonCoach;
  /** How long the board shows a frame that moves on by itself, in milliseconds. */
  hold: number;
}

const coachOf = (value: J | undefined): LessonCoach | undefined => {
  const text = str(get(value, "text"));
  return text === undefined ? undefined : { text, desktop: str(get(value, "desktop")), title: str(get(value, "title")), spot: str(get(value, "spot")),
    gesture: str(get(value, "gesture")) };
};

export const LessonCatalog = {
  parse(value: J): LessonInfo[] {
    return (arr(get(value, "lessons")) ?? []).flatMap((row) => {
      const id = str(get(row, "id")), title = str(get(row, "title"));
      return id && title ? [{ id, title }] : [];
    });
  },
  next(after: string, all: LessonInfo[]): LessonInfo | undefined {
    const index = all.findIndex((lesson) => lesson.id === after);
    return index >= 0 && index + 1 < all.length ? all[index + 1] : undefined;
  },
};

/** Something happened on the table (a spell, an attack, a life change): long enough to see it. A step passing: brief. */
export function lessonHold(poll: J, previous: J | undefined): number {
  if (previous === undefined || str(get(poll, "phase")) === "ended") return 400;
  const table = (p: J): J => {
    const view = get(get(p, "snapshot"), "gameView");
    const players = arr(get(view, "players")) ?? [];
    return [get(view, "stack") ?? null, get(view, "combat") ?? null, players.map((x) => get(x, "life") ?? null),
      players.map((x) => get(x, "battlefield") ?? null), players.map((x) => get(x, "graveyard") ?? null)];
  };
  return jsonEqual(table(poll), table(previous)) ? 350 : 1100;
}

/** One lesson file: the recorded learner's view after each change, and the moves it waits for. */
export class LessonScript {
  readonly id: string;
  readonly title: string;
  readonly capabilities: J;
  readonly create: J;
  readonly viewer: string;
  readonly frames: LessonFrame[];

  constructor(value: J) {
    const rows = arr(get(value, "frames"));
    const id = str(get(value, "id")), viewer = str(get(value, "viewer"));
    if (str(get(value, "format")) !== "magicmobile-lesson" || int(get(value, "version")) !== 1 || !rows?.length || !id || !viewer) {
      throw EngineError.invalid("This lesson file can't be read.");
    }
    this.id = id; this.viewer = viewer; this.title = str(get(value, "title")) ?? id;
    this.capabilities = get(value, "capabilities") ?? {}; this.create = get(value, "create") ?? {};
    let previous: J | undefined;
    this.frames = rows.flatMap((row) => {
      const poll = get(row, "poll");
      if (poll === undefined) return [];
      const frame: LessonFrame = { poll, expect: get(row, "expect"), note: bool(get(row, "note")) === true, complete: bool(get(row, "complete")) === true,
        coach: coachOf(get(row, "coach")), hold: lessonHold(poll, previous) };
      previous = poll;
      return [frame];
    });
  }

  get matchID() { return str(get(this.create, "matchId")) ?? ""; }
}

export interface LessonFocus { ids: string[]; control?: string }
const CONTROLS = new Set(["primary", "medallion", "yes"]);

/** What the coach's spot names on a frame: the expected card when it carries that name, else every card with it. */
export function resolveLessonSpot(spot: string | undefined, poll: J, expect: J | undefined): LessonFocus {
  if (!spot) return { ids: [] };
  if (CONTROLS.has(spot)) return { ids: [], control: spot };
  const view = get(get(poll, "snapshot"), "gameView");
  const named: string[] = [];
  for (const [id, card] of Object.entries(obj(get(view, "myHand")) ?? {})) if (str(get(card, "name")) === spot) named.push(id);
  for (const player of arr(get(view, "players")) ?? []) {
    const playerID = str(get(player, "playerId"));
    if (str(get(player, "name")) === spot && playerID) return { ids: [playerID] };
    for (const [id, card] of Object.entries(obj(get(player, "battlefield")) ?? {})) {
      if (str(get(card, "name")) === spot && bool(get(card, "tapped")) !== true) named.push(id);
    }
  }
  const expected = str(get(expect, "value"));
  return expected && named.includes(expected) ? { ids: [expected] } : { ids: named };
}

/** What the board shows for the lesson: the transport tells it each frame and each wrong move. */
export interface LessonListener {
  show(frame: LessonFrame): void;
  nudge(): void;
}

/** A move the lesson turned down: the coach card says so, so the board shows no error of its own. */
export const isLessonNudge = (error: unknown) =>
  error instanceof EngineError && (error.code === "lesson_wrong_move" || error.code === "lesson_not_now");

/** The engine's place for a lesson: recorded polls out, only the recorded move in. */
export class LessonTransport {
  private index = 0;
  private shownAt: number;
  private waitingForGotIt: boolean;
  private conceded = false;

  constructor(private readonly script: LessonScript, private readonly listener: LessonListener, private readonly clock: () => number = Date.now) {
    this.shownAt = clock();
    this.waitingForGotIt = script.frames[0].note;
    listener.show(script.frames[0]);
  }

  /** Where the lesson stands, for tests. */
  get position() {
    return { index: this.index, waitsForGotIt: this.waitingForGotIt, expect: this.script.frames[this.index].expect, count: this.script.frames.length };
  }

  release() { this.waitingForGotIt = false; this.shownAt = -Infinity; }

  request: EngineTransport = async (text) => {
    const request = EngineJson.decode(text);
    switch (str(get(request, "op"))) {
      case "capabilities": return this.reply(this.script.capabilities);
      case "create": return this.reply(this.script.create);
      case "poll": return this.reply(this.poll(int(get(request, "after")) ?? 0));
      case "respond": return this.respond(get(get(request, "command"), "answer"));
      case "concede": this.conceded = true; return this.reply({});
      case "destroy": return this.reply({});
      default: return this.failure("unknown_operation", "Lessons don't support this.");
    }
  };

  /** The current frame, stepping past frames that move on by themselves once they've been seen. */
  private poll(after: number): J {
    const frames = this.script.frames;
    while (this.index + 1 < frames.length && !this.waitingForGotIt && frames[this.index].expect === undefined && !frames[this.index].complete
      && this.clock() - this.shownAt >= frames[this.index].hold) this.advance();
    const poll = obj(frames[this.index].poll);
    if (!poll) return frames[this.index].poll;
    // Every message the board hasn't seen yet: the frames' own events since the cursor.
    const events = frames.slice(0, this.index + 1).flatMap((f) => (arr(get(f.poll, "events")) ?? []).filter((e) => (int(get(e, "revision")) ?? 0) > after));
    return { ...poll, events };
  }

  private advance() {
    this.index += 1; this.shownAt = this.clock();
    const frame = this.script.frames[this.index];
    this.waitingForGotIt = frame.note;
    this.listener.show(frame);
  }

  private respond(answer: J | undefined): string {
    const frames = this.script.frames;
    const frame = frames[this.index];
    const expected = frame.expect;
    if (expected === undefined || answer === undefined || this.conceded) return this.failure("lesson_not_now", LessonText.nudge);
    const kind = get(answer, "kind"), value = get(answer, "value");
    if (jsonEqual(kind, get(expected, "kind")) && jsonEqual(value, get(expected, "value"))) { this.advance(); return this.reply({ accepted: true }); }
    // Two cards of the same name in the same place play the same: the recording follows the one the player chose.
    const chosen = str(value), recorded = str(get(expected, "value"));
    if (jsonEqual(kind, get(expected, "kind")) && chosen && recorded && LessonTransport.interchangeable(chosen, recorded, frame.poll)) {
      for (let i = this.index; i < frames.length; i += 1) {
        frames[i].poll = LessonTransport.swap(frames[i].poll, chosen, recorded);
        if (frames[i].expect !== undefined) frames[i].expect = LessonTransport.swap(frames[i].expect!, chosen, recorded);
      }
      this.advance();
      return this.reply({ accepted: true });
    }
    this.listener.nudge();
    return this.failure("lesson_wrong_move", LessonText.nudge);
  }

  private reply(result: J) { return EngineJson.encode({ protocol: 1, ok: true, result }); }
  private failure(code: string, message: string) { return EngineJson.encode({ protocol: 1, ok: false, error: { code, message } }); }

  /** Same name, same zone, same tapped state: either card makes the same game. */
  static interchangeable(a: string, b: string, poll: J): boolean {
    const find = (id: string): string | undefined => {
      const view = get(get(poll, "snapshot"), "gameView");
      const inHand = get(get(view, "myHand"), id);
      if (inHand !== undefined) return `${str(get(inHand, "name"))}|hand|false`;
      for (const player of arr(get(view, "players")) ?? []) {
        const card = get(get(player, "battlefield"), id);
        if (card !== undefined) return `${str(get(card, "name"))}|battlefield:${str(get(player, "playerId"))}|${bool(get(card, "tapped")) === true}`;
      }
      return undefined;
    };
    const first = find(a);
    return first !== undefined && first === find(b);
  }

  /** Every use of one ID as the other and back, in keys and values alike. */
  static swap(value: J, a: string, b: string): J {
    const flip = (s: string) => (s === a ? b : s === b ? a : s);
    if (typeof value === "string") return flip(value);
    if (Array.isArray(value)) return value.map((item) => LessonTransport.swap(item, a, b));
    if (value !== null && typeof value === "object") {
      const result: JObject = {};
      for (const [key, item] of Object.entries(value)) result[flip(key)] = LessonTransport.swap(item, a, b);
      return result;
    }
    return value;
  }
}
