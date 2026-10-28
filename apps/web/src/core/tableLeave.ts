/**
 * When a player leaves a table with people, the others play on (TableLeaveRules.swift / .kt; Caleb, 2026-10-26: one
 * player had to go and the game couldn't continue for the other two). A guest who taps Leave, or whose connection the
 * relay gives up on, is conceded at once. A guest who is away (dropped or a hidden tab) is waited for; after
 * VOTE_AFTER_SECONDS everyone still at the table may vote to go on without them, and when they all agree the host concedes
 * the seat. Only the host runs the game, so the host leaving still ends it. Shared cases: parity/table-leave-cases.json.
 */
import { arr, EngineError, int, type J, keysEqual, obj, str } from "./json";

export const TableLeaveRules = {
  VOTE_AFTER_SECONDS: 15,
  /** Everyone still at the table agrees. */
  passes: (yes: number, eligible: number) => eligible > 0 && yes >= eligible,
  leftNotice: (name: string) => `${name} left. The game goes on.`,
  LEFT_BEHIND_MESSAGE: "The others went on without you after you left the table.",
  /** "Continue without Jed (1/2)". */
  buttonTitle: (vote: TableContinueVote) => `Continue without ${vote.name} (${vote.voters.length}/${vote.needed})`,
};

/**
 * The vote to go on without one away player: the seats that said yes and how many must. The host sends it to the guests
 * in a `vote` packet whenever it changes; seat "" with needed 0 means no vote is open.
 */
export interface TableContinueVote {
  seatID: string;
  name: string;
  voters: string[];
  needed: number;
  /** This seat already voted yes. */
  voted: boolean;
}

const SEATS = new Set(["player1", "player2", "player3", "player4"]);

export const NO_VOTE: TableContinueVote = { seatID: "", name: "", voters: [], needed: 0, voted: false };

export function votePacket(vote: TableContinueVote, epoch: string): J {
  return { type: "vote", epoch, seat: vote.seatID, voters: [...vote.voters], needed: vote.needed };
}

/** A host's `vote` packet; undefined when no vote is open. Throws on anything malformed. */
export function parseVote(value: J, names: Record<string, string>, localSeat?: string): TableContinueVote | undefined {
  const fields = obj(value);
  const seat = str(fields?.seat);
  const raw = arr(fields?.voters);
  const needed = int(fields?.needed);
  if (!fields || !keysEqual(fields, ["type", "epoch", "seat", "voters", "needed"]) || seat === undefined || !raw || raw.length > 4 ||
    typeof fields.needed !== "number" || needed === undefined || needed < 0 || needed > 4) throw EngineError.invalid("Invalid table vote.");
  const voters = raw.map((v) => str(v));
  if (voters.some((v) => v === undefined || !SEATS.has(v)) || (seat !== "" && !SEATS.has(seat)) || (seat === "") !== (needed === 0)) {
    throw EngineError.invalid("Invalid table vote.");
  }
  if (seat === "") return undefined;
  const list = voters as string[];
  return { seatID: seat, name: names[seat] ?? "A player", voters: list, needed, voted: localSeat !== undefined && list.includes(localSeat) };
}
