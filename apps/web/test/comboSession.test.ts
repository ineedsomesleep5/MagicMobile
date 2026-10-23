/**
 * The combo loop in the session (OnDeviceSession's ComboLoop part): three identical rounds of the player's answers are
 * offered for repeating, a count of repeats sends each round's answers again from the live choices, and the run closes
 * with its summary. Answers are stubbed; the decisions are the session's.
 */
import { describe, expect, it } from "vitest";
import { ComboRepeat, commandFromAction } from "../src/core/comboLoop";
import type { GameCommand, GameSnapshot, LegalAction, ZoneCard } from "../src/core/models";
import { GuestSession } from "../src/table/guestSession";

const card = (id: string, name: string, type: string, token = false): ZoneCard => ({ instanceId: id, card: { name, typeLine: type, ...(token ? { isToken: true } : {}) } });
const zones = (battlefield: ZoneCard[]) => ({ library: [], hand: [], battlefield, graveyard: [], exile: [], command: [], stack: [] });
const activate: LegalAction = { id: "act-77", type: "activate_ability", playerId: "me", label: "{B}, Sacrifice X Squirrels: Target creature gets +X/-X until end of turn.",
  sourceInstanceId: "chat-1", abilityId: "ab-1", promptId: "p-1", messageId: 3 };
// Chatterfang's ability is offered and its target question is up, as both are between a real round's answers.
const board: GameSnapshot = {
  id: "game-1", phase: "main1", turn: 15, log: [], viewerPlayerId: "me", bridgeRevision: 7, legalActions: [activate],
  players: [
    { playerId: "me", displayName: "Caleb", life: 20, poison: 0, commanderTax: 0, zones: zones([card("chat-1", "Chatterfang, Squirrel General", "Legendary Creature — Squirrel Warrior"),
      card("sq-9", "Squirrel Token", "Token Creature — Squirrel", true)]) },
    { playerId: "ai", displayName: "Tavern AI", life: 12, poison: 0, commanderTax: 0, zones: zones([card("cal-1", "Kinjalli's Caller", "Creature — Human Cleric")]) },
  ],
  promptEnvelopeV2: { id: "p-2", method: "GAME_TARGET", messageId: 4, playerId: "me", responseKind: "target", message: "Select a creature",
    targets: [{ id: "cal-1", label: "Kinjalli's Caller" }], responseCommand: { type: "choose_target", promptId: "p-2", messageId: 4 } },
} as unknown as GameSnapshot;

describe("combo loop in the session", () => {
  it("offers a round made three times, repeats it from the live choices, and sums it up", async () => {
    const session = new GuestSession(async () => "{}", "game-1", "player1", () => undefined, "local");
    session.comboLoopsAllowed = true;
    session.state = { ...session.state, snapshot: board, status: "Live" };
    const note = (command: GameCommand, label: string, id: string) =>
      (session as unknown as { noteComboStep: (c: GameCommand, l: string, a: string, d: GameSnapshot) => void }).noteComboStep(command, label, id, board);
    const target: GameCommand = { type: "choose_target", gameId: "game-1", playerId: "me", promptId: "p-2", messageId: 4, targetIds: ["cal-1"] };
    for (let round = 0; round < 3; round++) {
      expect(session.state.comboOffer).toBeUndefined();
      note(commandFromAction(activate, "game-1", 7), activate.label, activate.id);
      note(target, "Kinjalli's Caller", "p-2:target");
    }
    expect(session.state.comboOffer?.length).toBe(2);
    // The opponent has untapped nothing and no cards: the forecast is about life, and here it can't finish (life isn't falling).
    expect(session.state.comboWinForecast).toBeUndefined();

    const sent: GameCommand[] = [];
    session.submit = async (command: GameCommand) => { sent.push(command); };
    session.startComboLoop(ComboRepeat.times(2));
    expect(session.state.comboRun?.mode).toEqual({ kind: "times", count: 2 });
    expect(session.presentedSnapshot?.promptEnvelopeV2).toBeUndefined();
    const deadline = Date.now() + 5000;
    while (session.state.comboRun && Date.now() < deadline) await new Promise((resolve) => setTimeout(resolve, 20));
    expect(session.state.comboRun).toBeUndefined();
    expect(sent.map((c) => c.type)).toEqual(["activate_ability", "choose_target", "activate_ability", "choose_target"]);
    expect(sent[1].targetIds).toEqual(["cal-1"]);
    expect(session.state.comboResult).toBe("Repeated 2 times");
    // The round just run isn't offered again until a different one is made.
    note(commandFromAction(activate, "game-1", 7), activate.label, activate.id);
    expect(session.state.comboOffer).toBeUndefined();
  });
});
