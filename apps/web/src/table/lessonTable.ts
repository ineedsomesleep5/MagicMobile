/**
 * A lesson (docs/LESSONS_TUTORIAL.md): the recorded game stands in for the engine (LessonTransport), played through the same
 * GuestSession a solo game uses, with Maren's notes on the board. Nothing is saved or counted. Port of the phones' lesson
 * path in OnDeviceRootView (startLesson, nextLesson, finishLesson).
 */
import { type LessonCoach, type LessonFocus, type LessonFrame, type LessonInfo, type LessonListener, LessonScript, LessonTransport,
  LESSONS_COMPLETED_KEY, resolveLessonSpot } from "../core/lessons";
import { get, str } from "../core/json";
import { TurnClockBoard } from "../core/turnClock";
import { storage } from "../ui/storage";
import type { GameTable } from "./gameTable";
import { GuestSession } from "./guestSession";
import type { TableState } from "./guestTable";

/** Lessons finished in this browser. */
export const lessonProgress = {
  completed: (): Set<string> => new Set((storage.get(LESSONS_COMPLETED_KEY) ?? "").split(",").filter((id) => id.length > 0)),
  complete(id: string) { storage.set(LESSONS_COMPLETED_KEY, [...new Set([...lessonProgress.completed(), id])].sort().join(",")); },
};

/** The coach's state for the board (iOS LessonRun). */
export interface LessonRunState {
  coach?: LessonCoach;
  waitsForGotIt: boolean;
  complete: boolean;
  nudges: number;
  focus: LessonFocus;
}

export class LessonTable implements GameTable, LessonListener {
  readonly solo = true;
  state: TableState;
  session?: GuestSession;
  version = 0;
  run: LessonRunState = { waitsForGotIt: false, complete: false, nudges: 0, focus: { ids: [] } };
  private listeners = new Set<() => void>();
  private transport?: LessonTransport;
  private left = false;

  /** `onNext` opens the next lesson (or the guided game after the last); `onLeave` goes back to the lessons. */
  constructor(readonly lesson: LessonInfo, readonly nextTitle: string, private readonly onLeave: () => void, private readonly onNext: () => void) {
    this.state = {
      stage: "starting", status: "Opening the lesson…", tableCode: lesson.title, seatsTaken: 1, seatsWanted: 1,
      waiting: [], seatNames: {}, tableSeats: [], turnClock: new TurnClockBoard(), isSuspended: false, reconnecting: false, chat: [], bubbles: {},
    };
  }

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }
  private changed = () => { this.version += 1; this.listeners.forEach((listener) => listener()); };

  async start() {
    try {
      const response = await fetch(`/generated/lessons/lesson-${this.lesson.id}.json`);
      if (!response.ok) throw new Error(`This lesson is missing (${response.status}).`);
      const script = new LessonScript(await response.json());
      if (this.left) return;
      this.transport = new LessonTransport(script, this);
      const session = new GuestSession(this.transport.request, script.matchID, script.viewer, this.changed, "local");
      this.session = session;
      session.start();
      this.state = { ...this.state, stage: "playing", status: this.lesson.title };
      this.changed();
    } catch (error) {
      this.state = { ...this.state, stage: "failed", status: error instanceof Error ? error.message : String(error) };
      this.changed();
    }
  }

  show(frame: LessonFrame) {
    let complete = this.run.complete;
    if (frame.complete || str(get(frame.poll, "phase")) === "ended") {
      if (!complete) lessonProgress.complete(this.lesson.id);
      complete = true;
    }
    // A frame without a note of its own keeps the last one up while its move is still to make.
    const coach = frame.coach ?? (frame.expect === undefined && !frame.note ? undefined : this.run.coach);
    this.run = { ...this.run, coach, complete, waitsForGotIt: frame.note, focus: resolveLessonSpot(frame.coach?.spot, frame.poll, frame.expect) };
    this.changed();
  }

  nudge() { this.run = { ...this.run, nudges: this.run.nudges + 1 }; this.changed(); }

  gotIt() {
    if (!this.run.waitsForGotIt) return;
    this.run = { ...this.run, waitsForGotIt: false };
    this.transport?.release();
    this.session?.wake();
    this.changed();
  }

  rollStartingPlayer() { /* lessons start past the roll */ }
  async concede() { await this.session?.concede(); }
  leave() { this.stop(); this.onLeave(); }
  rematch() { this.stop(); this.onNext(); }
  private stop() { this.left = true; this.session?.stop(); }
  sendChat() { /* no one else at a lesson */ }
  sendEmote() { /* no one else at a lesson */ }
}
