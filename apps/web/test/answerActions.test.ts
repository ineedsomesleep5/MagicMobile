/** answer-action-cases.json: which standing instructions a decision can carry, as iOS runs them (ParityGoldenTests). */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { EnginePrompt } from "../src/core/engineClient";
import type { GameCommand } from "../src/core/models";
import { OnDevicePromptAdapter } from "../src/core/promptAdapter";
import { canRememberAnswer } from "../src/ui/arena/Browsers";
import { isTriggerOrder } from "../src/ui/arena/triggerPlan";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
const root: any = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/answer-action-cases.json"), "utf8"));

describe("answer-action-cases.json", () => {
  it("attaches only the actions that fit, like the apps", () => {
    for (const item of root.cases) {
      const prompt = new EnginePrompt({ promptId: "real-prompt", revision: 37, kind: item.prompt.kind, submitted: false, responseTypes: item.prompt.types, min: 0, max: 0,
        payload: { message: "Engine question", required: true, options: {}, ...item.prompt.payload } });
      const command: GameCommand = { gameId: "match", playerId: root.viewer, promptId: prompt.id, messageId: 37, ...item.command };
      const envelope = OnDevicePromptAdapter.presentation(prompt, root.viewer, []).envelope;
      if ("canRemember" in item) expect(canRememberAnswer(envelope), item.name).toBe(item.canRemember);
      if ("triggerOrder" in item) expect(isTriggerOrder(envelope), item.name).toBe(item.triggerOrder);
      if (item.error) { expect(() => OnDevicePromptAdapter.answerActions(item.requested, command, prompt), item.name).toThrow(); continue; }
      const actions = OnDevicePromptAdapter.answerActions(item.requested, command, prompt);
      expect(actions, item.name).toEqual(item.actions);
      expect(OnDevicePromptAdapter.withActions(OnDevicePromptAdapter.answer(command, prompt, root.viewer), actions), item.name).toEqual(item.answer);
    }
  });
});
