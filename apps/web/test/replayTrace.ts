/** The replay trace (test/replay.test.ts): per poll, the prompt, smart pass's decision, Auto Pay's next step, board events. */
import { nextStepIn } from "../src/core/autoPay";
import { BoardEventDiffer, fxState } from "../src/core/boardEvents";
import { MatchPoll } from "../src/core/engineClient";
import { defaultSmartPass, passPrompt, situation } from "../src/core/smartPass";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import { arenaSummary } from "./paceCases";

export function replayTrace(polls: unknown[]): Record<string, unknown>[] {
  const trace: Record<string, unknown>[] = [];
  let previous: ReturnType<typeof fxState> | undefined;
  const commanders = new Set<string>();
  for (const raw of polls) {
    const poll = new MatchPoll(raw as never);
    const snapshot = poll.snapshot !== undefined ? OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, []) : undefined;
    const prompt = poll.prompt;
    const decision = situation(poll, true, snapshot);
    const paying = snapshot && (snapshot.manaPayment?.active === true || snapshot.promptEnvelopeV2?.responseKind.toLowerCase() === "mana");
    const step = paying ? nextStepIn(snapshot!) : undefined;
    let events: string[] = [];
    if (snapshot) {
      const state = fxState(snapshot);
      state.commandNames.forEach((name) => commanders.add(name));
      if (previous && previous.gameID === state.gameID) events = BoardEventDiffer.events(previous, state, commanders).map(arenaSummary);
      previous = state;
    }
    trace.push({
      revision: poll.revision, phase: poll.phase, prompt: prompt ? prompt.kind : null,
      smartPass: decision ? (passPrompt(decision, defaultSmartPass) ? "pass" : "stop") : null,
      autoPay: step === undefined ? null : step.kind === "tap" ? `tap ${step.actionID}${step.color ? ` ${step.color}` : ""}`
        : step.kind === "spend" ? `spend ${step.symbol}` : step.kind === "blocked" ? `blocked ${step.reason}` : "done",
      events,
    });
  }
  return trace;
}
