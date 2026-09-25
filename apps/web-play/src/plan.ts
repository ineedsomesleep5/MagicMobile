// SPIKE ONLY. Shared game plan + metric summary for the browser bench and the JVM baseline.
import { stats, type GameResult, type GameSpec } from "./autoplay.ts";
import type { JsonObject } from "./engineClient.ts";

export type PlannedGame = { players: number; seed: number };

/** "2p:1,2p:2,4p:3" -> [{players:2,seed:1}, ...] */
export function parseGames(text: string): PlannedGame[] {
  return text.split(",").filter(Boolean).map((item) => {
    const match = /^([234])p:(\d+)$/.exec(item.trim());
    if (!match) throw new Error("Bad game spec (want e.g. 2p:1): " + item);
    return { players: Number(match[1]), seed: Number(match[2]) };
  });
}

/** Seat i plays precon (seed + i) mod N, so each seed pairs different bundled decks. */
export function gameSpec(game: PlannedGame, decks: { id: string; deck: JsonObject }[], capMs: number, aiSkill?: number): GameSpec {
  const sorted = [...decks].sort((a, b) => a.id.localeCompare(b.id));
  const chosen = Array.from({ length: game.players }, (_, i) => sorted[(game.seed + i) % sorted.length]);
  return { label: `${game.players}p seed ${game.seed}`, seed: game.seed, players: game.players, decks: chosen, capMs, aiSkill };
}

export const TARGETS = {
  engineReadyFirstMs: 45_000,
  engineReadyCachedMs: 10_000,
  fourPlayerStartMs: 10_000,
  boardUpdateMedianMs: 1_000,
  boardUpdateP95Ms: 3_000,
  aiTurnMedianMs: 5_000,
  aiTurnP95Ms: 15_000,
  mainThreadLongTaskMs: 100,
  tabMemoryBytes: 2 * 1024 ** 3,
};

export function summarize(games: GameResult[]) {
  const all = (pick: (g: GameResult) => number[]) => games.flatMap(pick);
  const fourPlayerStarts = games.filter((g) => g.players === 4 && g.firstPromptMs !== null).map((g) => g.firstPromptMs as number);
  const twoPlayerStarts = games.filter((g) => g.players === 2 && g.firstPromptMs !== null).map((g) => g.firstPromptMs as number);
  return {
    games: games.length,
    finished: games.filter((g) => g.result === "ended").length,
    timeouts: games.filter((g) => g.result === "timeout").length,
    stalled: games.filter((g) => g.result === "stalled").length,
    failed: games.filter((g) => g.result === "failed").length,
    humanWins: games.filter((g) => g.winner === "human").length,
    turns: stats(games.map((g) => g.turns)),
    gameWallMs: stats(games.map((g) => g.wallMs)),
    createMs: stats(games.map((g) => g.createMs)),
    twoPlayerStartMs: stats(twoPlayerStarts),
    fourPlayerStartMs: stats(fourPlayerStarts),
    boardUpdateMs: stats(all((g) => g.boardUpdateMs)),
    aiTurnMs: stats(all((g) => g.aiTurnMs)),
    humanTurnMs: stats(all((g) => g.humanTurnMs)),
    pollMs: stats(all((g) => g.pollMs)),
    respondMs: stats(all((g) => g.respondMs)),
    maxSnapshotBytes: Math.max(0, ...games.map((g) => g.maxSnapshotBytes)),
  };
}
