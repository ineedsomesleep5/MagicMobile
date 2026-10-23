/**
 * Port of StartingRoll.kt (OnDeviceStartingRoll.swift): the host-recorded D20 result every device
 * animates. Animation timing never decides who starts. A guest decodes the host's plan, advances
 * only its own steps, and answers XMage's starting-player question with the shared winner.
 */
import { arr, EngineError, get, int, type J, keysEqual, obj, str } from "./json";
import type { GameCommand, GameSnapshot } from "./models";

export interface RollStep { roundIndex: number; seatID: string; value: number }

export class OnDeviceStartingRoll {
  private constructor(readonly rounds: Map<string, number>[], readonly winnerSeatID: string, readonly seatOrder: string[]) {}

  get steps(): RollStep[] {
    return this.rounds.flatMap((round, roundIndex) => this.seatOrder.filter((seat) => round.has(seat))
      .map((seatID) => ({ roundIndex, seatID, value: round.get(seatID)! })));
  }

  private validate(seatIDs: string[]) {
    if (seatIDs.join("\u0000") !== this.seatOrder.join("\u0000") || seatIDs.length < 2 || seatIDs.length > 4 ||
      new Set(seatIDs).size !== seatIDs.length || this.rounds.length === 0 || this.rounds.length > 32) {
      throw EngineError.invalid("Invalid starting-roll roster.");
    }
    let contenders = new Set(seatIDs);
    this.rounds.forEach((round, index) => {
      const values = [...round.values()];
      const highest = values.length === 0 ? undefined : Math.max(...values);
      const keys = [...round.keys()];
      if (keys.length !== contenders.size || !keys.every((k) => contenders.has(k)) || !values.every((v) => v >= 1 && v <= 20) || highest === undefined) {
        throw EngineError.invalid("Starting-roll round does not match the roster.");
      }
      contenders = new Set(keys.filter((k) => round.get(k) === highest));
      if (contenders.size <= 1 && index !== this.rounds.length - 1) throw EngineError.invalid("Starting roll continues after a winner.");
    });
    if (contenders.size !== 1 || !contenders.has(this.winnerSeatID)) throw EngineError.invalid("Starting-roll winner does not match the dice.");
  }

  /** OnDeviceStartingRoll.generate: everyone rolls a D20, the highest starts, ties reroll among the tied. */
  static generate(seatIDs: string[], draw: () => number = () => 1 + Math.floor(Math.random() * 20)): OnDeviceStartingRoll {
    if (seatIDs.length < 2 || seatIDs.length > 4 || new Set(seatIDs).size !== seatIDs.length || seatIDs.some((id) => id.length === 0)) {
      throw EngineError.invalid("A starting roll needs 2–4 distinct seats.");
    }
    let contenders = seatIDs;
    const rounds: Map<string, number>[] = [];
    // An extremely unlikely run of ties must fail visibly, not loop forever.
    for (let round = 0; round < 32; round += 1) {
      const rolls = new Map<string, number>();
      for (const seat of contenders) {
        const value = draw();
        if (!Number.isInteger(value) || value < 1 || value > 20) throw EngineError.invalid("Invalid D20 value.");
        rolls.set(seat, value);
      }
      rounds.push(rolls);
      const high = Math.max(...rolls.values());
      contenders = contenders.filter((seat) => rolls.get(seat) === high);
      if (contenders.length === 1) {
        const roll = new OnDeviceStartingRoll(rounds, contenders[0], seatIDs);
        roll.validate(seatIDs);
        return roll;
      }
    }
    throw EngineError.invalid("The starting roll tied too many times. Try the match again.");
  }

  static decode(value: J, seatIDs: string[]): OnDeviceStartingRoll {
    const fields = obj(value);
    const rows = arr(get(value, "rounds"));
    const winner = str(get(value, "winnerSeatId"));
    if (!fields || !keysEqual(fields, ["rounds", "winnerSeatId"]) || !rows || rows.length === 0 || rows.length > 32 || winner === undefined) {
      throw EngineError.invalid("Invalid shared starting roll.");
    }
    const rounds = rows.map((row) => {
      const entries = arr(row);
      if (!entries || entries.length > 4) throw EngineError.invalid("Invalid shared starting roll round.");
      const result = new Map<string, number>();
      for (const entry of entries) {
        const item = obj(entry);
        const seat = str(get(entry, "seatId"));
        const number = int(get(entry, "value"));
        if (!item || !keysEqual(item, ["seatId", "value"]) || seat === undefined || number === undefined || number < 1 || number > 20 || result.has(seat)) {
          throw EngineError.invalid("Invalid shared D20 value.");
        }
        result.set(seat, number);
      }
      return result;
    });
    const roll = new OnDeviceStartingRoll(rounds, winner, seatIDs);
    roll.validate(seatIDs);
    return roll;
  }
}

/** One shared cursor through the host's result. Humans advance only their own turn; the host advances AI turns. */
export class OnDeviceStartingRollProgress {
  revealedCount = 0;
  constructor(readonly roll: OnDeviceStartingRoll, readonly humanSeatIDs: Set<string>) {}

  get nextSeatID(): string | undefined { return this.roll.steps[this.revealedCount]?.seatID; }
  get isComplete(): boolean { return this.revealedCount === this.roll.steps.length; }

  acceptHostAdvance(index: number) {
    if (index !== this.revealedCount || this.nextSeatID === undefined) throw EngineError.replayed();
    this.revealedCount += 1;
  }
}

/**
 * Port of OnDeviceStartingPlayerChoice: converts the shared pregame winner into the exact current
 * XMage prompt answer. Ambiguity or a changed prompt fails closed.
 */
export const OnDeviceStartingPlayerChoice = {
  candidateIDs(snapshot: GameSnapshot): string[] | undefined {
    const prompt = snapshot.promptEnvelopeV2;
    const candidates = prompt?.targetIds;
    if (!prompt || !candidates) return undefined;
    if (snapshot.source !== "xmage-ondevice" || prompt.playerId !== (snapshot.viewerPlayerId ?? "human") ||
      !["GAME_PICK_TARGET", "PICK_TARGET"].includes(prompt.method) || !prompt.message.toLowerCase().includes("starting player") ||
      prompt.responseCommand?.type !== "choose_target" || prompt.responseCommand?.promptId !== prompt.id ||
      prompt.responseCommand?.messageId !== prompt.messageId || candidates.length < 2 || candidates.length > 4 ||
      new Set(candidates).size !== candidates.length || !candidates.every((id) => snapshot.players.some((p) => p.playerId === id)) ||
      snapshot.bridgeRevision === undefined) return undefined;
    return candidates;
  },

  commandForName(snapshot: GameSnapshot, winnerName: string): GameCommand | undefined {
    const matches = snapshot.players.filter((p) => p.displayName === winnerName);
    if (matches.length !== 1) return undefined;
    return OnDeviceStartingPlayerChoice.commandForPlayerID(snapshot, matches[0].playerId);
  },

  /** An AI game's local roll names XMage's own player IDs (OnDeviceStartingPlayerChoice.command(winnerPlayerID:)). */
  commandForPlayerID(snapshot: GameSnapshot, winnerPlayerID: string): GameCommand | undefined {
    const candidates = OnDeviceStartingPlayerChoice.candidateIDs(snapshot);
    const prompt = snapshot.promptEnvelopeV2;
    if (!candidates || !prompt || snapshot.bridgeRevision === undefined || !candidates.includes(winnerPlayerID)) return undefined;
    return {
      type: "choose_target", gameId: snapshot.id, playerId: snapshot.viewerPlayerId ?? "human", promptId: prompt.id,
      messageId: prompt.messageId, targetIds: [winnerPlayerID], expectedBridgeRevision: snapshot.bridgeRevision,
    };
  },
};
