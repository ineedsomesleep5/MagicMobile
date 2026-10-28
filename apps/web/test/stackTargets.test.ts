/** Target questions recorded from the real engine (target-*.json, iOS ArenaBoardModelTests): where each one's choices are. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { stackChoices } from "../src/core/arenaBoard";
import { MatchPoll } from "../src/core/engineClient";
import type { GameSnapshot } from "../src/core/models";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import { browserKind } from "../src/ui/arena/Browsers";

const fixture = (name: string): GameSnapshot => {
  const poll = new MatchPoll(JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/ios/MagicMobileTests/Fixtures/OnDevice", `${name}.json`), "utf8")));
  return OnDeviceSnapshotAdapter.snapshot(poll, poll.seatID, []);
};
const targetable = (snapshot: GameSnapshot) => new Set(snapshot.promptEnvelopeV2?.targetIds ?? []);
const onTable = (snapshot: GameSnapshot) => (id: string) =>
  snapshot.players.some((p) => p.playerId === id || p.zones.battlefield.some((c) => c.instanceId === id));

describe("target questions the table can't show", () => {
  it("chooses Gogo's copy among the abilities on the stack, named by their source", () => {
    const snapshot = fixture("target-stack-ability");
    expect(new Set(stackChoices(snapshot, targetable(snapshot)))).toEqual(targetable(snapshot));
    expect(new Set((snapshot.promptEnvelopeV2?.targets ?? []).map((t) => t.label)))
      .toEqual(new Set(["Zur the Enchanter’s ability", "Gogo, Master of Mimicry’s ability"]));
  });
  it("chooses a Counterspell's spell on the stack, the one that resolves next first", () => {
    const snapshot = fixture("target-stack-spell");
    const names = stackChoices(snapshot, targetable(snapshot)).map((id) => snapshot.xmage?.stack.find((s) => s.id === id)?.name);
    expect(names).toEqual(["Shock", "Lightning Bolt"]);
  });
  it("leaves graveyard cards to the card browser", () => {
    for (const name of ["target-graveyard", "target-any-graveyard"]) {
      const snapshot = fixture(name);
      expect(stackChoices(snapshot, targetable(snapshot))).toEqual([]);
      expect(browserKind(snapshot.promptEnvelopeV2, onTable(snapshot))).toBe("cards");
    }
  });
  it("answers four-player targets on the table, where every opponent shows", () => {
    const snapshot = fixture("target-four-player-creature");
    expect(stackChoices(snapshot, targetable(snapshot))).toEqual([]);
    expect(browserKind(snapshot.promptEnvelopeV2, onTable(snapshot))).toBeUndefined();
  });
});
