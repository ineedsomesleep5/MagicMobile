/**
 * Guest side of OnDeviceMultiplayerLobby (OnDeviceMultiplayer.kt / .swift). Peer IDs come only
 * from the relay's stamps, never from packet fields. The browser never hosts in this milestone.
 */
import { arr, codePointCount, EngineError, EngineJson, get, int, isUuid, type J, jsonEqual, type JObject, keysEqual, obj, str, utf8Length } from "../core/json";
import { OnDeviceStartingRoll } from "../core/startingRoll";

export interface BuildIdentity { upstreamCommit: string; catalogueHash: string; adapterVersion: string }
/** The phones' relay adapter string (OnDeviceRootView.swift `relayIdentity`). */
export const RELAY_ADAPTER_VERSION = "ondevice-0.1/relay-1/rollstep-2/room-1/concede-1/emote-1/chat-1/clock-1";
export const identityJSON = (identity: BuildIdentity): JObject => ({
  protocolVersion: 1, upstreamCommit: identity.upstreamCommit, catalogueHash: identity.catalogueHash, adapterVersion: identity.adapterVersion,
});

export class HandshakeFailure extends Error {
  static differentBuild = () => new HandshakeFailure("Players have different MagicMobile builds. Update every device to the same build and try again.", "build");
  static differentSettings = () => new HandshakeFailure("The host’s AI settings changed or a peer did not confirm them. Start a new match.", "settings");
  constructor(message: string, readonly kind: "build" | "settings") { super(message); }
}

/** Swift CharacterSet.controlCharacters: general categories Cc and Cf. */
export const hasControlCharacters = (text: string) => /[\p{Cc}\p{Cf}]/u.test(text);
/** Case- and diacritic-insensitive comparison key (Foundation's folding options). */
const foldedKey = (text: string) => text.normalize("NFD").replace(/\p{M}+/gu, "").toLowerCase();

const invalidSettings = () => EngineError.invalid("A table needs 2–4 total human and AI seats, with AI skill from 1–10.");

export const Lobby = {
  validateSubmission(value: J) {
    const fields = obj(value);
    const name = str(get(value, "name"));
    const deck = obj(get(value, "deck"));
    const main = arr(get(deck ?? null, "main"));
    const commanders = arr(get(deck ?? null, "commanders"));
    if (utf8Length(EngineJson.encode(value)) > 64 * 1024 || !fields || !keysEqual(fields, ["name", "deck"]) || name === undefined ||
      name.trim().length === 0 || codePointCount(name) > 40 || hasControlCharacters(name) || !deck ||
      !Object.keys(deck).every((k) => ["name", "main", "commanders", "companions"].includes(k)) || !main || !commanders) {
      throw EngineError.invalid("Invalid player name or resolved deck. Names must contain 1–40 characters.");
    }
    if (deck.name !== undefined && (str(deck.name) === undefined || codePointCount(str(deck.name)!) > 200)) throw EngineError.invalid("Invalid deck name.");
    if (deck.companions !== undefined && !arr(deck.companions)) throw EngineError.invalid("Invalid companion list.");
    // Resource bounds only; XMage owns Commander legality, including special deck sizes.
    const rows = [...main, ...commanders, ...(arr(deck.companions) ?? [])];
    if (rows.length > 2000) throw EngineError.messageTooLarge();
    let total = 0;
    for (const row of rows) {
      const entry = obj(row);
      const count = int(get(row, "count")); const set = str(get(row, "setCode")); const number = str(get(row, "collectorNumber"));
      if (!entry || !Object.keys(entry).every((k) => ["name", "setCode", "collectorNumber", "count"].includes(k)) || count === undefined ||
        count < 1 || count > 2000 || !set || utf8Length(set) > 64 || !number || utf8Length(number) > 64) {
        throw EngineError.invalid("Deck must contain resolved compiled printings.");
      }
      if (entry.name !== undefined && (str(entry.name) === undefined || utf8Length(str(entry.name)!) > 512)) throw EngineError.invalid("Invalid printing name.");
      total += count;
      if (total > 2000) throw EngineError.messageTooLarge();
    }
  },

  validateAISettings(value: J, humanCount: number) {
    const fields = obj(value);
    const count = int(get(value, "count"));
    const seats = arr(get(value, "seats"));
    if (!fields || !keysEqual(fields, ["count", "seats"]) || count === undefined || !seats || count !== seats.length ||
      humanCount < 2 || humanCount > 4 || humanCount + seats.length > 4) throw invalidSettings();
    for (const seat of seats) {
      const row = obj(seat);
      const deck = get(seat, "deck"); const skill = int(get(seat, "skill"));
      if (!row || !keysEqual(row, ["deck", "skill"]) || deck === undefined || skill === undefined || skill < 1 || skill > 10) {
        throw EngineError.invalid("Invalid AI seat deck or skill.");
      }
      Lobby.validateSubmission({ name: "AI", deck });
    }
  },

  validatedSeatNames(value: J | undefined, totalSeats: number): Map<string, string> {
    const fields = obj(value);
    const expected = Array.from({ length: totalSeats }, (_, i) => `player${i + 1}`);
    if (!fields || !keysEqual(fields, expected)) throw EngineError.incompatibleBuild();
    const seen = new Set<string>();
    const result = new Map<string, string>();
    for (const seat of expected) {
      const name = str(fields[seat]);
      if (name === undefined || name.length === 0 || name !== name.trim() || codePointCount(name) > 40 || hasControlCharacters(name)) {
        throw EngineError.incompatibleBuild();
      }
      const key = foldedKey(name);
      if (seen.has(key)) throw EngineError.incompatibleBuild();
      seen.add(key);
      result.set(seat, name);
    }
    return result;
  },

  commanderNames(submission: J | undefined): string[] {
    return (arr(get(get(submission ?? null, "deck"), "commanders")) ?? []).map((row) => str(get(row, "name")))
      .filter((name): name is string => name !== undefined && name.length > 0 && codePointCount(name) <= 200 && !hasControlCharacters(name));
  },
};

export class GuestLobby {
  readonly peerIDs: string[];
  aiSettings: J = { count: 0, seats: [] };
  acceptedHostSettings = false;

  constructor(peerIDs: string[], readonly localPeerID: string) {
    this.peerIDs = [...peerIDs].sort();
    if (this.peerIDs.length < 2 || this.peerIDs.length > 4 || new Set(this.peerIDs).size !== this.peerIDs.length ||
      this.peerIDs.some((id) => id.length === 0 || utf8Length(id) > 256) || !this.peerIDs.includes(localPeerID)) {
      throw EngineError.invalid("A table needs 2–4 distinct connected players.");
    }
    if (this.hostID === localPeerID) throw EngineError.invalid("This browser cannot host a table yet.");
  }

  get hostID() { return this.peerIDs[0]; }

  seatID(authenticatedPeerID: string): string {
    const index = this.peerIDs.indexOf(authenticatedPeerID);
    if (index < 0) throw EngineError.unboundPeer();
    return `player${index + 1}`;
  }

  get aiSeatCount() { return arr(get(this.aiSettings, "seats"))?.length ?? 0; }

  /** Checks an `offer` or `start` from the host, returning its epoch. */
  verifyHandshake(value: J, from: string, identity: BuildIdentity, epoch: string | undefined): string {
    this.seatID(from);
    const fields = obj(value);
    if (!fields) throw EngineError.incompatibleBuild();
    const type = str(fields.type);
    if (type !== "offer" && type !== "start" && type !== "submission") throw EngineError.incompatibleBuild();
    const keys = type === "submission" ? ["type", "epoch", "build", "roster", "aiSettings", "player"]
      : type === "start" ? ["type", "epoch", "build", "roster", "aiSettings", "matchId", "seatNames", "roll"]
        : ["type", "epoch", "build", "roster", "aiSettings"];
    const incomingEpoch = str(fields.epoch);
    if (!keysEqual(fields, keys) || !jsonEqual(fields.roster, this.peerIDs) || !isUuid(incomingEpoch) ||
      !(epoch !== undefined ? epoch.toLowerCase() === incomingEpoch.toLowerCase() : type === "offer")) throw EngineError.incompatibleBuild();
    // A guest only ever hears handshakes from the host; a submission is for the host alone.
    if (type === "submission" || from !== this.hostID) throw EngineError.unboundPeer();
    const build = obj(fields.build);
    if (!build || !keysEqual(build, ["protocolVersion", "upstreamCommit", "catalogueHash", "adapterVersion"]) ||
      int(build.protocolVersion) === undefined || str(build.upstreamCommit) === undefined || str(build.catalogueHash) === undefined ||
      str(build.adapterVersion) === undefined) throw EngineError.incompatibleBuild();
    const proposedSettings = fields.aiSettings;
    Lobby.validateAISettings(proposedSettings, this.peerIDs.length);
    if (type === "start") {
      if (!isUuid(str(fields.matchId))) throw EngineError.incompatibleBuild();
      const names = Lobby.validatedSeatNames(fields.seatNames, this.peerIDs.length + (arr(get(proposedSettings, "seats"))?.length ?? 0));
      OnDeviceStartingRoll.decode(fields.roll, Array.from({ length: names.size }, (_, i) => `player${i + 1}`));
    }
    // Only a well-formed handshake from the expected peer and epoch may end the lobby with a mismatch explanation.
    if (!jsonEqual(fields.build, identityJSON(identity))) throw HandshakeFailure.differentBuild();
    if (type !== "offer" || this.acceptedHostSettings) {
      if (!this.acceptedHostSettings || !jsonEqual(proposedSettings, this.aiSettings)) throw HandshakeFailure.differentSettings();
    }
    return incomingEpoch;
  }

  acceptHostOffer(value: J) {
    const settings = get(value, "aiSettings");
    if (settings === undefined) throw EngineError.unboundPeer();
    if (this.acceptedHostSettings && !jsonEqual(settings, this.aiSettings)) throw HandshakeFailure.differentSettings();
    this.aiSettings = settings; this.acceptedHostSettings = true;
  }

  get hostAISeatSummary(): string {
    const seats = arr(get(this.aiSettings, "seats"));
    if (!seats || seats.length === 0) return "Host chose no AI seats.";
    const details = seats.map((seat, index) => {
      const title = str(get(get(seat, "deck"), "name"))?.trim() ?? "";
      return `AI ${index + 1}: ${title.length > 0 && !hasControlCharacters(title) ? title : "selected deck"}, skill ${int(get(seat, "skill")) ?? 0}`;
    });
    return `Host chose ${seats.length} AI seat${seats.length === 1 ? "" : "s"}: ${details.join("; ")}.`;
  }

  /** Host → guests: who has readied up and their commanders. */
  acceptReadyPacket(value: J, from: string): Map<string, string[]> {
    const fields = obj(value);
    const players = arr(get(value, "players"));
    if (from !== this.hostID || !fields || !keysEqual(fields, ["type", "epoch", "players"]) || !players || players.length > this.peerIDs.length) {
      throw EngineError.unboundPeer();
    }
    const result = new Map<string, string[]>();
    for (const player of players) {
      const row = obj(player);
      const id = str(get(player, "id"));
      const commanders = arr(get(player, "commanders"));
      if (!row || !keysEqual(row, ["id", "commanders"]) || id === undefined || !this.peerIDs.includes(id) || result.has(id) ||
        !commanders || commanders.length > 4) throw EngineError.unboundPeer();
      const names = commanders.map(str).filter((n): n is string => n !== undefined);
      if (names.length !== commanders.length || !names.every((n) => n.length > 0 && codePointCount(n) <= 200 && !hasControlCharacters(n))) {
        throw EngineError.unboundPeer();
      }
      result.set(id, names);
    }
    return result;
  }

  /** The packet a guest sends the host when it readies up. */
  submissionPacket(epoch: string, identity: BuildIdentity, player: J): J {
    return {
      type: "submission", epoch, build: identityJSON(identity), roster: this.peerIDs, aiSettings: this.aiSettings, player,
    };
  }
}
