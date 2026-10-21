/** The Arena browsers' reading of XMage's prompts, ported from the iOS Arena board (ArenaBoardModel, NativeGameView+Arena). */
import { describe, expect, it } from "vitest";
import type { PromptEnvelopeV2 } from "../src/core/models";
import {
  affordableX, amountValues, browserKind, choiceOptions, clampAmount, colorSymbol, headline, lethalDamage, splitName, stepAmount,
} from "../src/ui/arena/Browsers";

const prompt = (extra: Partial<PromptEnvelopeV2>): PromptEnvelopeV2 =>
  ({ id: "p", method: "GAME_CHOOSE_CHOICE", messageId: 1, playerId: "me", responseKind: "choice", message: "Choose", ...extra });

describe("arena choices", () => {
  it("pairs XMage's Remember answer twins and splits a named card from its text", () => {
    const options = choiceOptions([
      { id: "a", label: "Doubling Season [8f2]: If an effect would create tokens" },
      { id: "b", label: "Remember answer: Doubling Season [8f2]: If an effect would create tokens" },
      { id: "c", label: "Plain answer" },
    ]);
    expect(options).toHaveLength(2);
    expect(options[0]).toMatchObject({ id: "a", rememberID: "b", name: "Doubling Season", text: "If an effect would create tokens" });
    expect(options[1]).toMatchObject({ id: "c", name: undefined, text: "Plain answer" });
  });

  it("reads colours as mana symbols", () => {
    expect(colorSymbol("Red mana")).toBe("R");
    expect(colorSymbol("Colorless")).toBe("C");
    expect(colorSymbol("Purple")).toBeUndefined();
  });

  it("asks a few plain answers as a question and browses long or card-naming lists", () => {
    const onTable = () => true;
    const few = prompt({ choices: [{ id: "1", label: "Even" }, { id: "2", label: "Odd" }] });
    expect(browserKind(few, onTable)).toBe("question");
    const many = prompt({ choices: ["A", "B", "C", "D"].map((label) => ({ id: label, label })) });
    expect(browserKind(many, onTable)).toBe("choices");
    const naming = prompt({ choices: [{ id: "1", label: "Doubling Season: If an effect…" }, { id: "2", label: "Anointed Procession: If an effect…" }] });
    expect(browserKind(naming, onTable)).toBe("question");
    expect(browserKind(naming, onTable, (name) => name === "Doubling Season")).toBe("choices");
  });

  it("chooses a listed player in the player browser", () => {
    const players = prompt({ players: [{ id: "x", label: "AI 1", playerId: "ai" }] });
    expect(browserKind(players, () => true)).toBe("players");
  });
});

describe("arena question headline", () => {
  it("keeps short questions whole", () => {
    expect(headline("Pay 2 life?", "Dismember", false)).toEqual({ title: "Pay 2 life?" });
  });
  it("puts the question first and the rest under it", () => {
    const long = "Use the ability of Esper Sentinel? Whenever an opponent casts their first noncreature spell each turn, draw a card.";
    expect(headline(long, "Esper Sentinel", true)).toEqual({ title: "Use the ability of Esper Sentinel?", detail: "Whenever an opponent casts their first noncreature spell each turn, draw a card." });
  });
  it("names the ability when the long message is about its source", () => {
    const long = "Esper Sentinel: whenever an opponent casts their first noncreature spell each turn, unless that player pays X, you draw a card";
    expect(headline(long, "Esper Sentinel", true)).toEqual({ title: "Use Esper Sentinel's ability?", detail: long });
  });
});

describe("arena amount pill", () => {
  it("steps XMage's list or its bounds, held at the ends", () => {
    expect(amountValues([3, 1, 3, 2], undefined, undefined)).toEqual([1, 2, 3]);
    expect(amountValues(undefined, 0, 4)).toEqual([0, 1, 2, 3, 4]);
    expect(amountValues(undefined, 2, undefined)).toHaveLength(100);
    const values = amountValues(undefined, 0, 10);
    expect(stepAmount(values, 9, 5)).toBe(10);
    expect(stepAmount(values, 1, -5)).toBe(0);
    expect(clampAmount([0, 2, 4], 3)).toBe(2);
  });
  it("starts X at the most the mana pays", () => {
    expect(affordableX("{X}{R}", 5)).toBe(4);
    expect(affordableX("{X}{X}{2}{G}", 9)).toBe(3);
    expect(affordableX("{2}{G}", 9)).toBeUndefined();
    expect(affordableX("{X}{4}", 2)).toBe(0);
  });
});

describe("arena split", () => {
  it("names a row's card and marks lethal damage", () => {
    expect(splitName("Grizzly Bears, P/T: 2/2")).toBe("Grizzly Bears");
    expect(splitName("Grizzly Bears [8f2]")).toBe("Grizzly Bears");
    expect(lethalDamage(4, 1, false)).toBe(3);
    expect(lethalDamage(4, 0, true)).toBe(1);
    expect(lethalDamage(2, 5, false)).toBe(1);
  });
});
