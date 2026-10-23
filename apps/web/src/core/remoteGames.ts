/**
 * Your games from every device (mm_my_games): each device sends its finished games to the profile server, and a profile
 * shows them all. This browser's record stays the source of truth for its own games; a game the server has from
 * elsewhere (the phone) joins the list by its client id, never twice. Only what the server keeps: no deck id, bracket
 * or rank change, so those games group by deck name.
 */
import { arr, get, type J, str } from "./json";
import type { MatchOpponent, MatchRecord, PlayMode } from "./playerRecord";
import type { RankOutcome } from "./rankLadder";

const MODES: readonly PlayMode[] = ["quick", "ranked", "casual"];
const OUTCOMES: readonly RankOutcome[] = ["win", "loss", "draw"];

/** The deck id a server game groups under in the profile's deck filter. */
export const remoteDeckID = (deckName: string) => `played:${deckName.trim().toLowerCase()}`;

export function parseMyGames(value: J): MatchRecord[] {
  return (arr(value) ?? []).flatMap((row): MatchRecord[] => {
    const id = str(get(row, "client_id"));
    const date = Date.parse(str(get(row, "played_at")) ?? "");
    const mode = str(get(row, "mode")) as PlayMode | undefined;
    const outcome = str(get(row, "result")) as RankOutcome | undefined;
    if (!id || !Number.isFinite(date) || !mode || !MODES.includes(mode) || !outcome || !OUTCOMES.includes(outcome)) return [];
    const deckName = str(get(row, "deck_name")) ?? "Deck";
    const commander = (arr(get(row, "commanders")) ?? []).map((c) => str(c)).find((c): c is string => !!c);
    const opponents = (arr(get(row, "opponents")) ?? []).flatMap((o): MatchOpponent[] => {
      const name = str(get(o, "name"));
      if (!name) return [];
      const foe = str(get(o, "commander"));
      return [{ name, ...(foe ? { commander: foe } : {}), isAI: get(o, "ai") !== false }];
    });
    const turns = get(row, "turns");
    return [{
      id, date, mode, opponents, deckID: remoteDeckID(deckName), deckName, ...(commander ? { commander } : {}),
      colors: (arr(get(row, "colors")) ?? []).map((c) => str(c)).filter((c): c is string => !!c),
      deckBracket: 0, outcome, turns: typeof turns === "number" ? Math.max(0, Math.trunc(turns)) : 0,
    }];
  });
}

/** This browser's games and the server's others, newest first; a game both have stays as this browser recorded it. */
export function mergeMatches(local: readonly MatchRecord[], remote: readonly MatchRecord[]): MatchRecord[] {
  const known = new Set(local.map((match) => match.id.toLowerCase()));
  return [...local, ...remote.filter((match) => !known.has(match.id.toLowerCase()))].sort((a, b) => b.date - a.date);
}
