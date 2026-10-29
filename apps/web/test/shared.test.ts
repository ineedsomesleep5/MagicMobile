/** chat-cases.json and turn-clock-cases.json: the same cases iOS and Android run. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EnginePrompt } from "../src/core/engineClient";
import type { J } from "../src/core/json";
import { TableChatFilter, TableChatText, TableJoinLink } from "../src/core/tableChat";
import { TurnClock, TurnClockBoard, TurnClockRules, TurnClockWire } from "../src/core/turnClock";

const parity = join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const load = (name: string): any => JSON.parse(readFileSync(join(parity, name), "utf8"));

describe("chat-cases.json", () => {
  const root = load("chat-cases.json");
  it("sanitizes like the apps", () => {
    expect(TableChatText.MAX_CODE_POINTS).toBe(root.maxScalars);
    for (const item of root.sanitize) expect(TableChatText.sanitize(item.input) ?? null, item.name).toBe(item.output);
  });
  it("filters like the apps", () => {
    for (const item of root.filter) expect(TableChatFilter.filtered(item.input), item.input).toBe(item.output);
  });
  it("reads invite links like the apps", () => {
    for (const item of root.links) expect(TableJoinLink.code(item.link) ?? null, item.link).toBe(item.code);
    expect(TableJoinLink.url(root.shareLink.code)).toBe(root.shareLink.url);
    expect(TableJoinLink.url("nope")).toBeUndefined();
  });
});

describe("turn-clock-cases.json", () => {
  const root = load("turn-clock-cases.json");
  const prompt = (value: string | undefined | null) => (typeof value === "string" ? { id: value, revision: 1 } : undefined);

  it("uses the shared rules", () => expect({ ...TurnClockRules }).toEqual(root.rules));

  it("plays every scenario like the apps", () => {
    for (const scenario of root.scenarios) {
      const clock = new TurnClock();
      for (const step of scenario.steps) {
        const label = `${scenario.name} @ ${step.at}`;
        if (step.observe) {
          const changed = clock.observe(step.observe.seat, prompt(step.observe.prompt), step.at);
          if ("changed" in step) expect(changed, label).toBe(step.changed);
        }
        if ("pause" in step) {
          const changed = clock.setPaused(step.pause, step.at);
          if ("changed" in step) expect(changed, label).toBe(step.changed);
        }
        if (step.timeout) {
          const result = clock.timeout(step.timeout.seat, prompt(step.timeout.prompt)!, step.timeout.hasDefault, step.at);
          expect(result ?? null, label).toBe(step.result);
        }
        if (step.answerFailed) clock.answerFailed(step.answerFailed.seat, prompt(step.answerFailed.prompt)!, step.at);
        if (step.expired) expect(clock.expired(step.at).map(([seat]) => seat), label).toEqual(step.expired);
        if (step.entries) expect(clock.entries(step.at), label).toEqual(step.entries);
        if (step.strikes) for (const [seat, count] of Object.entries(step.strikes)) expect(clock.strikes(seat), `${label} ${seat}`).toBe(count);
      }
    }
  });

  it("answers timeouts like the apps", () => {
    for (const item of root.defaultAnswers) {
      const value = new EnginePrompt({ ...item.prompt, promptId: "p", revision: 1, submitted: false, min: 0, max: 1 } as J);
      expect(TurnClock.defaultAnswer(value) ?? null, item.name).toEqual(item.answer);
    }
  });

  it("reads and writes the clock packet like the apps", () => {
    for (const item of root.wire.valid) {
      const { paused, entries } = TurnClockWire.parse(item.packet);
      expect(TurnClockWire.packet("E", paused, entries), item.name).toEqual(item.packet);
    }
    for (const item of root.wire.invalid) expect(() => TurnClockWire.parse(item.packet), item.name).toThrow();
  });

  it("burns the same rope", () => {
    for (const item of root.ropes) {
      const board = new TurnClockBoard(item.board.paused, item.board.clocks);
      const rope = board.rope(item.local ?? undefined, item.now);
      if (item.rope === null) expect(rope, item.name).toBeUndefined();
      else {
        expect(rope?.seat, item.name).toBe(item.rope.seat);
        expect(rope?.isLocal, item.name).toBe(item.rope.isLocal);
        expect(rope?.remaining, item.name).toBeCloseTo(item.rope.remaining, 9);
        expect(rope?.fraction, item.name).toBeCloseTo(item.rope.fraction, 9);
        expect(rope?.strikes, item.name).toBe(item.rope.strikes);
      }
      const until = board.secondsUntilRope(item.local ?? undefined, item.now);
      if (item.untilRope === null) expect(until, item.name).toBeUndefined();
      else expect(until, item.name).toBeCloseTo(item.untilRope, 9);
    }
  });
});
