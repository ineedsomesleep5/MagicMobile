/** The lessons' recordings (scripts/lessons/record.py) played through LessonTransport; iOS LessonsTests and Android LessonsTest check the same. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EngineClient } from "../src/core/engineClient";
import { EngineError, get, newUuid, str, type J } from "../src/core/json";
import { forDesktop, LessonCatalog, type LessonFrame, LessonScript, LessonTransport, resolveLessonSpot } from "../src/core/lessons";

const lessons = join(__dirname, "..", "..", "ios/MagicMobile/Resources/Lessons");
const json = (name: string): J => JSON.parse(readFileSync(join(lessons, name), "utf8"));
const script = (id: string) => new LessonScript(json(`lesson-${id}.json`));

function setup(id: string) {
  const lesson = script(id);
  let now = 0;
  const shown: LessonFrame[] = [];
  const counts = { nudges: 0 };
  const transport = new LessonTransport(lesson, { show: (f) => shown.push(f), nudge: () => { counts.nudges += 1; } }, () => now);
  return { lesson, transport, client: new EngineClient(transport.request), advance: (ms: number) => { now += ms; }, counts };
}

describe("lessons", () => {
  it("plays every lesson through with its recorded moves", async () => {
    const ids = LessonCatalog.parse(json("lessons.json")).map((l) => l.id);
    expect(ids).toEqual(["first-spells", "combat", "stack", "commander", "table"]);
    for (const id of ids) {
      const { lesson, transport, client, advance } = setup(id);
      const match = str(get(await client.call("create", { configuration: {} }), "matchId"))!;
      let moves = 0;
      for (let steps = 0; ; steps += 1) {
        expect(steps).toBeLessThan(500);
        const poll = await client.poll(match, lesson.viewer);
        const at = transport.position;
        if (poll.phase === "ended" || (at.index === at.count - 1 && at.expect === undefined && !at.waitsForGotIt)) break;
        if (at.waitsForGotIt) { transport.release(); continue; }
        if (at.expect !== undefined) {
          expect(poll.prompt, `${id} frame ${at.index}`).toBeDefined();
          await client.respond(match, lesson.viewer, poll.prompt!, at.expect, newUuid());
          moves += 1;
        } else {
          expect(poll.prompt, `${id} frame ${at.index}`).toBeUndefined();
          advance(2000);
        }
      }
      expect(moves).toBe(lesson.frames.filter((f) => f.expect !== undefined).length);
      const last = lesson.frames[lesson.frames.length - 1];
      expect(last.complete || str(get(last.poll, "phase")) === "ended").toBe(true);
    }
  });

  it("turns a wrong move down and nudges", async () => {
    const { lesson, transport, client, advance, counts } = setup("first-spells");
    const match = str(get(await client.call("create", { configuration: {} }), "matchId"))!;
    let poll = await client.poll(match, lesson.viewer);
    while (transport.position.expect === undefined) { transport.release(); advance(2000); poll = await client.poll(match, lesson.viewer); }
    const wrong = client.respond(match, lesson.viewer, poll.prompt!, { kind: "boolean", value: true }, newUuid());
    await expect(wrong).rejects.toSatisfy((error) => error instanceof EngineError && error.code === "lesson_wrong_move");
    expect(counts.nudges).toBe(1);
    expect(transport.position.expect).toBeDefined();
  });

  it("follows the player's Forest when either of two pays", async () => {
    const { lesson, transport, client, advance } = setup("first-spells");
    const match = str(get(await client.call("create", { configuration: {} }), "matchId"))!;
    for (;;) {
      const poll = await client.poll(match, lesson.viewer);
      const at = transport.position;
      if (at.waitsForGotIt) { transport.release(); continue; }
      if (at.expect === undefined || !poll.prompt) { advance(2000); continue; }
      if (poll.prompt.kind === "PLAY_MANA") {
        const recorded = str(get(at.expect, "value"))!;
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const mine = (poll.snapshot as any).gameView.players.find((p: any) => p.name === "You");
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const other = Object.entries(mine.battlefield).find(([key, card]: [string, any]) => key !== recorded && card.name === "Forest")![0];
        await client.respond(match, lesson.viewer, poll.prompt, { kind: "uuid", value: other }, newUuid());
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const next = (await client.poll(match, lesson.viewer)).snapshot as any;
        expect(next.gameView.players.find((p: { name: string }) => p.name === "You").battlefield[other].tapped).toBe(true);
        return;
      }
      await client.respond(match, lesson.viewer, poll.prompt, at.expect, newUuid());
    }
  });

  it("points at the expected card by name and speaks the desktop's words", () => {
    const frame = script("first-spells").frames.find((f) => f.coach?.spot === "Forest" && f.expect !== undefined)!;
    expect(resolveLessonSpot("Forest", frame.poll, frame.expect).ids).toEqual([str(get(frame.expect, "value"))]);
    expect(resolveLessonSpot("primary", frame.poll, undefined).control).toBe("primary");
    expect(forDesktop("Press and hold any card. Tap Next, then tap Done.")).toBe("Right-click any card. Click Next, then click Done.");
  });
});
