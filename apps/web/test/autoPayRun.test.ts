/** Auto Pay's run on the board (iOS arenaAutoPayStep): one tap per settled snapshot, its own colour question, giving up. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { MatchPoll } from "../src/core/engineClient";
import type { GameSnapshot } from "../src/core/models";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import { AutoPayRun, autoPayReady, colorChoice, paymentPrompt } from "../src/ui/arena/autoPayRun";

const fixture = (name: string): GameSnapshot => {
  const poll = new MatchPoll(JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/ios/MagicMobileTests/Fixtures/OnDevice", `${name}.json`), "utf8")));
  return OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, []);
};

describe("Auto Pay run", () => {
  it("taps the land XMage offers, waits for a pending answer, and ends when the payment is over", () => {
    const paying = fixture("2p-mana");
    expect(paymentPrompt(paying)).toBeDefined();
    expect(autoPayReady(paying)).toBe(true);
    const run = new AutoPayRun();
    expect(run.step(paying, true).kind).toBe("wait");
    const move = run.step(paying, false);
    expect(move.kind).toBe("action");
    if (move.kind === "action") expect(move.action.type).toBe("make_mana");
    // The same state a third time: Auto Pay is going in circles.
    run.step(paying, false);
    expect(run.step(paying, false)).toEqual({ kind: "stop", notice: "Auto Pay stopped: tap the rest yourself" });
    const after = fixture("2p-priority");
    const done = new AutoPayRun();
    expect(done.step(after, false).kind).toBe("stop");
  });

  it("answers the colour question its tap raised with the colour it planned", () => {
    const base = fixture("2p-mana");
    const question = { ...base, manaPayment: undefined, promptEnvelopeV2: {
      id: "colour", method: "GAME_CHOOSE_CHOICE", messageId: 9, playerId: base.viewerPlayerId!, responseKind: "choice", message: "Pick a mana color",
      choices: [{ id: "w", label: "White mana" }, { id: "g", label: "Green mana" }],
    } } as GameSnapshot;
    expect(colorChoice(question.promptEnvelopeV2!, "G")).toBe("g");
    expect(colorChoice(question.promptEnvelopeV2!, undefined)).toBe("w");
    const run = new AutoPayRun();
    run.awaitingColor = true;
    run.color = "G";
    const move = run.step(question, false);
    expect(move.kind).toBe("command");
    if (move.kind === "command") expect(move.command).toMatchObject({ type: "resolve_choice", choiceIds: ["g"], promptId: "colour", messageId: 9 });
    expect(run.answeredColor).toBe("colour:9");
    // A question nobody tapped for is the player's own.
    expect(new AutoPayRun().step(question, false).kind).toBe("stop");
  });
});
