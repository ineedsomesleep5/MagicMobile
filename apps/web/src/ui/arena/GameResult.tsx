/**
 * The end of a game on the Arena board, as Arena shows it (iOS ArenaGameResultView, ArenaBoardViews.swift;
 * build_output/arena-game-reference/victory-*.jpg): the board dims and one word lands on a flare of light behind the
 * MagicMobile mark, orange for Victory, cold steel for Defeat, violet for a draw. A click, or a moment, lifts the word to
 * the top over your medallion, your rank, the game's numbers and the two ways on. View Battlefield lifts it all to look
 * at the final board. No trophy, flag or tavern panel, and never Arena's Planeswalker sigil.
 */
import { useEffect, useState } from "react";
import { type GameSnapshot, type PlayerGameState } from "../../core/models";
import { RankChange, RankPosition, type RankTier } from "../../core/rankLadder";
import { gameAudio } from "../audio";
import { BrandMark } from "../menus/BrandMark";
import { RankBadge } from "../menus/PlayPanel";
import { Medallion } from "./Browsers";

type Outcome = "victory" | "defeat" | "draw" | "stopped";

/** The flare behind the word (ArenaGameResultView.flare); a stopped table takes Defeat's cold steel. */
const FLARE: Record<Outcome, string> = { victory: "255,133,36", defeat: "117,148,189", draw: "158,102,245", stopped: "117,148,189" };

export interface ResultNumbers { turns: number; combatDamage: number; creaturesDestroyed: number }

export function GameResult({ snapshot, me, finished, stoppedTitle, stoppedLine, numbers, rankChange, rankNote, rematch, leave }: {
  snapshot?: GameSnapshot; me?: PlayerGameState; finished: boolean;
  /** A table that ended without a result: its word ("Game stopped") and why. */
  stoppedTitle: string; stoppedLine?: string;
  numbers: ResultNumbers;
  /** How a ranked game moved you (RankProgressPanel). */
  rankChange?: RankChange;
  /** Why a ranked win left the ladder alone, once the server says so. */
  rankNote?: string;
  rematch?: () => void; leave: () => void;
}) {
  const winners = snapshot?.winnerPlayerIds ?? [];
  const outcome: Outcome = !finished ? "stopped" : winners.length === 0 ? "draw" : winners.includes(snapshot?.viewerPlayerId ?? "") ? "victory" : "defeat";
  const word = { victory: "Victory", defeat: "Defeat", draw: "Draw", stopped: stoppedTitle }[outcome];
  const reduce = typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;
  const [landed, setLanded] = useState(reduce);
  const [settled, setSettled] = useState(false);
  const [peeking, setPeeking] = useState(false);
  useEffect(() => {
    const land = window.setTimeout(() => setLanded(true), 30);
    const settle = window.setTimeout(() => setSettled(true), reduce ? 300 : 1800);
    return () => { window.clearTimeout(land); window.clearTimeout(settle); };
  }, [reduce]);
  return (
    <div className={`aresult ${settled ? "settled" : ""} ${landed ? "landed" : ""} ${peeking ? "peek" : ""}`} data-outcome={outcome}
      style={{ ["--flare" as string]: FLARE[outcome] }} role="dialog" aria-label={`Game completed. ${word}`}
      onClick={(event) => { event.stopPropagation(); if (!peeking) setSettled(true); }}>
      {!peeking && (
        <>
          <div className="banner">
            <i className="flare" /><i className="line" />
            <span className="mark"><BrandMark size={settled ? 68 : 92} /></span>
            <h2>{word.toUpperCase()}</h2>
          </div>
          {settled && (
            <div className="details">
              {me && !rankChange && (
                <span className={`resultmed ${outcome === "victory" ? "won" : ""} ${outcome === "defeat" ? "lost" : ""}`} aria-hidden="true">
                  <Medallion player={me} viewer diameter={84} life={false} />
                </span>
              )}
              {!finished && stoppedLine && <p>{stoppedLine}</p>}
              {rankChange && <RankProgress change={rankChange} />}
              {rankNote && <p className="rnote" data-id="board.result.rankNote">{rankNote}</p>}
              {finished && numbers.turns > 0 && (
                <div className="figures">
                  <Figure value={numbers.turns} label="Turns" />
                  <Figure value={numbers.combatDamage} label="Damage" />
                  <Figure value={numbers.creaturesDestroyed} label="Destroyed" />
                </div>
              )}
              <div className="ways">
                <button type="button" className="aplaque secondary" onClick={leave}>Main Menu</button>
                {rematch && <button type="button" className="aplaque primary" data-id="board.result.rematch" onClick={rematch}>New Game</button>}
              </div>
            </div>
          )}
        </>
      )}
      <button type="button" className="aplaque secondary rview" onClick={(event) => { event.stopPropagation(); setPeeking(!peeking); }}>
        {peeking ? "Back" : "View Battlefield"}</button>
    </div>
  );
}

function Figure({ value, label }: { value: number; label: string }) {
  return <span className="figure" aria-label={`${value} ${label}`}><b>{value}</b><small>{label.toUpperCase()}</small></span>;
}

const FLAME = <path d="M10 1.5c.6 3.2 4.8 5.2 4.8 10a4.8 4.8 0 0 1-9.6 0c0-2.3 1.2-3.8 2.4-4.8-.1 1.6.5 2.8 1.6 3.3C9 7.6 8.6 4.5 10 1.5z" />;

/** RankTier.tint and .shade (RankBadgeView.swift), as RGB. */
const TINT: Record<RankTier, [string, string]> = {
  bronze: ["204,128,69", "92,46,18"], silver: ["204,212,224", "82,87,102"], gold: ["255,204,92", "122,77,15"],
  platinum: ["140,230,219", "26,87,92"], diamond: ["128,191,255", "20,51,122"], mythic: ["255,115,56", "115,18,8"],
};

/**
 * The result's rank (RankProgressPanel, Ranked/RankCeremonyView.swift), standing on its own in the middle in the medallion's
 * place, no box (Caleb, 2026-10-23): the badge in its tier's glow, then each pip filling or emptying
 * in turn so a crossing into the next division is seen, the change in words and the bonuses that earned extra pips.
 */
export function RankProgress({ change }: { change: RankChange }) {
  const from = RankPosition.points(change.before);
  const to = RankPosition.points(change.after);
  const [points, setPoints] = useState<number>();
  useEffect(() => {
    // The server's count may replace the browser's while this shows: start again from its own before.
    setPoints(undefined);
    if (from === to) return;
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) { setPoints(to); return; }
    const step = to > from ? 1 : -1;
    let value = from;
    let timer = window.setTimeout(function tick() {
      value += step;
      setPoints(value);
      gameAudio.play(step > 0 ? "counter" : "life-loss", 0, 0.7);
      if (value !== to) timer = window.setTimeout(tick, 420);
    }, 700);
    return () => window.clearTimeout(timer);
  }, [from, to]);
  const shown = RankPosition.fromPoints(points ?? from);
  const delta = RankChange.pipDelta(change);
  const highlight = points === undefined ? undefined : delta >= 0 ? shown.pips - 1 : shown.pips;
  const text = delta > 0 ? (delta === 1 ? "+1 pip" : `+${delta} pips`) : delta < 0 ? (delta === -1 ? "−1 pip" : `${delta} pips`)
    : change.outcome === "loss" ? "No pips to lose" : "No change";
  const [tint, shade] = TINT[shown.tier];
  return (
    <div className="rankstrip" style={{ ["--tint" as string]: tint, ["--shade" as string]: shade }} data-id="rank.progress"
      aria-label={`Ranked: ${RankPosition.title(change.after)}. ${text}`}>
      <span key={`${shown.tier}${shown.division}`} className="rbadge"><i className="rglow" /><RankBadge position={shown} size={96} showsPips={false} /></span>
      <div>
        <b className="rtitle">{RankPosition.title(shown)}</b>
        {shown.tier === "mythic" ? <span className="rflame"><svg viewBox="0 0 20 20" aria-hidden="true">{FLAME}</svg>{shown.pips}</span> : (
          <span className="rpips" aria-hidden="true">
            {Array.from({ length: RankPosition.pipsPerDivision }, (_, i) => <i key={i} className={`${i < shown.pips ? "on" : ""} ${i === highlight ? "hot" : ""}`} />)}
          </span>
        )}
        <small className={`rdelta ${delta > 0 ? "up" : delta < 0 ? "down" : ""}`}>{text}</small>
        {change.bonuses.length > 0 && (
          <span className="rbonus">{change.bonuses.map((bonus) => <em key={bonus}>{bonus === "streak" ? "Win streak +1" : "Underdog +1"}</em>)}</span>
        )}
      </div>
    </div>
  );
}
