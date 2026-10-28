/**
 * Your own face-down cards (iOS OnDeviceSnapshotAdapterTests.testOwnFaceDownCardShowsItsRealFace, Android
 * OnDeviceFaceDownTest): the owner sees the real card from CardView's `secondCardFace`, marked face down; anyone else, or a
 * face-down card without that face, gets the hidden placeholder, whose names never look up art. Also the inspector's
 * notes and tabs for it.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { liveState, rulesReminder } from "../src/core/arenaBoard";
import { MatchPoll } from "../src/core/engineClient";
import type { J, JObject } from "../src/core/json";
import type { CardIdentity, ZoneCard } from "../src/core/models";
import { OnDeviceSnapshotAdapter } from "../src/core/snapshotAdapter";
import { inspectorTabs } from "../src/ui/arena/Inspector";
import { permitsArtLookup, permitsArtName } from "../src/ui/cardArt";

const raw = (): JObject => JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/ios/MagicMobileTests/Fixtures/OnDevice", "2p-priority.json"), "utf8"));

/** The fixture's first hand card, edited, as the adapter reads it. */
function handCard(edit: (card: JObject, real: JObject) => void): CardIdentity {
  const poll = raw();
  const hand = ((poll.snapshot as JObject).gameView as JObject).myHand as JObject;
  const key = Object.keys(hand).sort()[0];
  const real = hand[key] as JObject;
  const card: JObject = { ...real };
  edit(card, real);
  hand[key] = card;
  const match = new MatchPoll(poll as J);
  const snapshot = OnDeviceSnapshotAdapter.snapshot(match, match.seatID, []);
  return snapshot.players.flatMap((p) => p.zones.hand).find((c) => c.instanceId === real.id)!.card;
}

/** Regal Behemoth as CardView's second face of a face-down card. */
const behemoth = (real: JObject): JObject => ({
  ...real, name: "Regal Behemoth", displayName: "Regal Behemoth", cardTypes: ["CREATURE"], superTypes: [], subTypes: ["Dragon"],
  rules: ["Trample", "Monarch"], manaCostLeftStr: ["{5}", "{G}"], manaCostRightStr: [], faceDown: false,
});

describe("face-down cards", () => {
  it("shows its owner the real card, marked face down", () => {
    const own = handCard((card, real) => {
      Object.assign(card, { name: "Face Down: Regal Behemoth", displayName: "Face Down: Regal Behemoth", faceDown: true, hideInfo: false,
        cardTypes: [], subTypes: [], rules: [], manaCostLeftStr: [], secondCardFace: behemoth(real) });
    });
    expect(own.name).toBe("Regal Behemoth");
    expect(own.faceDown).toBe(true);
    expect(own.typeLine).toBe("Creature — Dragon");
    expect(own.oracleText).toBe("Trample\nMonarch");
    expect(own.manaCost).toBe("{5}{G}");
  });

  it("keeps it hidden from an opponent, and without a named second face", () => {
    const theirs = handCard((card) => { Object.assign(card, { name: "Morph", displayName: "Morph", faceDown: true, hideInfo: false, secondCardFace: null }); });
    expect([theirs.name, theirs.typeLine, theirs.oracleText, theirs.faceDown, theirs.manaCost]).toEqual(["Face-down card", "", "", undefined, undefined]);
    const unnamed = handCard((card, real) => {
      Object.assign(card, { name: "Face Down: Regal Behemoth", faceDown: true, hideInfo: false, secondCardFace: { ...behemoth(real), name: null } });
    });
    expect([unnamed.name, unnamed.faceDown]).toEqual(["Face-down card", undefined]);
    // Redacted outright, even with the face attached.
    const redacted = handCard((card, real) => { Object.assign(card, { faceDown: true, hideInfo: true, secondCardFace: behemoth(real) }); });
    expect([redacted.name, redacted.faceDown]).toEqual(["Face-down card", undefined]);
  });

  it("looks up art for your own face-down card, never for a placeholder's name", () => {
    const icon = { iconType: "OTHER_FACEDOWN" };
    const zone = (card: CardIdentity, icons = [icon]): ZoneCard => ({ instanceId: "x", card, cardIcons: icons });
    expect(permitsArtLookup(zone({ name: "Regal Behemoth", typeLine: "Creature", faceDown: true }))).toBe(true);
    expect(permitsArtLookup(zone({ name: "Regal Behemoth", typeLine: "Creature" }))).toBe(false);
    expect(permitsArtLookup(zone({ name: "Regal Behemoth", typeLine: "Creature" }, []))).toBe(true);
    for (const name of ["Face-down card", "Face Down: Regal Behemoth", "face down: x", "Hidden card", ""]) expect(permitsArtName(name), name).toBe(false);
  });

  it("says so in the inspector", () => {
    const card: ZoneCard = { instanceId: "x", card: { name: "Regal Behemoth", typeLine: "Creature — Dragon", faceDown: true } };
    expect(liveState(card, [])[0]).toBe("Face down");
    expect(rulesReminder(card)).toBe("Face down: only you can see it. A card exiled face down is played through the card that exiled it: for Hideaway, use that card's own ability once its condition is met.");
    expect(rulesReminder({ ...card, card: { ...card.card, faceDown: undefined } })).toBeUndefined();
  });
});

describe("inspector tabs", () => {
  const card = (id: string, attachedTo?: string): ZoneCard => ({ instanceId: id, card: { name: id, typeLine: "" }, ...(attachedTo ? { attachedToInstanceId: attachedTo } : {}) });
  const table = [card("bear"), card("aura", "bear"), card("sword", "bear"), card("elf")];

  it("puts what a card is attached to first, then the card, then what it carries; one card has none", () => {
    expect(inspectorTabs(table[0], table).map((c) => c.instanceId)).toEqual(["bear", "aura", "sword"]);
    expect(inspectorTabs(table[1], table).map((c) => c.instanceId)).toEqual(["bear", "aura"]);
    expect(inspectorTabs(table[3], table).map((c) => c.instanceId)).toEqual(["elf"]);
    expect(inspectorTabs(card("gone", "missing"), table).map((c) => c.instanceId)).toEqual(["gone"]);
  });
});
