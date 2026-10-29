/**
 * The season's standings from the server (iOS Ranked/RankedHallViews.swift RankedLeaderboardView, in its sideways
 * layout): Everyone or Friends as a tab strip beside the live strip (who's online, how many are ranked, the season), the
 * top three on a podium of their own glass on the left, the rest down the right with your own row at its head when
 * you're off the list, a pulsing dot for who's online, places gained or lost since the last look, and a band of gold
 * light sweeping Mythic rows. Refreshes every 20 seconds while the page is visible.
 *
 * A full page under the top bar, like RankedPage. On the web it is laid out for a desktop window rather than a phone held
 * sideways (Caleb, 2026-10-23: "take up more space and look better"): one scrolling page with the podium across the
 * top, large, and the standings below as a table with Record, Win rate and Rank columns. Same data and rules as iOS.
 */
import { useEffect, useRef, useState } from "react";
import { type PlayerAccount, RankedLeaderboard, type RankedLeaderboardEntry, type RankedLeaderboardScope } from "../../core/account";
import { RankLadder, RankPosition, RankTier } from "../../core/rankLadder";
import { leaderboardLabel, onlineText, placeMoves, podiumOrder, TIER_TINT } from "../../core/socialText";
import { gameAudio } from "../audio";
import { Medallion, OnlineDot, SocialGlyph, SocialTag, SocialWaiting } from "./FriendsPanel";
import { BackChevron, Segmented } from "./kit";
import { RankEmblem } from "./TopBar";
import "./social.css";

const REFRESH_SECONDS = 20;

/** Wins out of games played this season, rounded; undefined before the first game. */
const winRate = (entry: RankedLeaderboardEntry) => {
  const played = entry.wins + entry.losses;
  return played === 0 ? undefined : Math.round((entry.wins / played) * 100);
};

type Load = { kind: "loading" } | { kind: "loaded"; board: RankedLeaderboard } | { kind: "offline" };

export function Leaderboard({ account, onBack, openProfile }: {
  account: PlayerAccount;
  onBack: () => void;
  /** Opens a player's profile from their row; rows don't open anything without it. */
  openProfile?: (username: string) => void;
}) {
  // Everyone, friends, or last season's champions (from the everyone board).
  const [tab, setTab] = useState<RankedLeaderboardScope | "champions">("everyone");
  const scope: RankedLeaderboardScope = tab === "friends" ? "friends" : "everyone";
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  /** Places gained (positive) or lost since the last refresh. */
  const [moves, setMoves] = useState<Record<string, number>>({});
  const [podiumUp, setPodiumUp] = useState(false);
  const lastPositions = useRef<Record<string, number>>({});

  useEffect(() => {
    lastPositions.current = {};
    setMoves({});
    setLoad((current) => (current.kind === "loaded" && current.board.scope !== scope ? { kind: "loading" } : current));
    let stopped = false;
    let timer: number | undefined;
    let first = true;
    const refresh = async () => {
      if (document.visibilityState === "visible" || first) {
        first = false;
        const board = await account.rankedLeaderboard(scope);
        if (stopped) return;
        if (!board) {
          // Keeps the last standings through a dropped connection.
          setLoad((current) => (current.kind === "loaded" ? current : { kind: "offline" }));
        } else {
          const { positions, moves: changed } = placeMoves(lastPositions.current, board.entries);
          lastPositions.current = positions;
          setMoves(changed);
          setLoad({ kind: "loaded", board });
        }
      }
      if (!stopped) timer = window.setTimeout(() => { void refresh(); }, REFRESH_SECONDS * 1000);
    };
    void refresh();
    return () => { stopped = true; window.clearTimeout(timer); };
  }, [account, scope]);

  const loaded = load.kind === "loaded" ? load.board : undefined;
  useEffect(() => {
    if (!loaded || podiumUp) return;
    const frame = requestAnimationFrame(() => setPodiumUp(true));
    return () => cancelAnimationFrame(frame);
  }, [loaded, podiumUp]);

  const open = (entry: RankedLeaderboardEntry) => {
    if (!openProfile) return;
    gameAudio.play("ui-open");
    openProfile(entry.username);
  };

  const podiumStep = (entry: RankedLeaderboardEntry) => {
    const place = entry.position;
    const rank = RankedLeaderboard.rank(entry);
    return (
      <button key={entry.username} type="button" className={`mpodiumstep place${Math.min(place, 3)}`} aria-label={leaderboardLabel(entry)}
        data-id={`leaderboard.row.${entry.username}`} onClick={() => open(entry)}>
        {place === 1 && <svg className="mpodiumcrown" viewBox="0 0 24 24" width="18" height="18" aria-hidden="true"><path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 11H5zM5.5 19.5h13V21h-13z" /></svg>}
        <span className="mpodiumemblem">
          {place === 1 && <i className="mrankglow" style={{ ["--tint" as string]: TIER_TINT[rank.tier], width: 132, height: 132 }} />}
          <RankEmblem tier={rank.tier} size={place === 1 ? 92 : 74} />
          {entry.online && <span className="mpodiumdot"><OnlineDot size={12} /></span>}
        </span>
        <b>{entry.username}{entry.you && <SocialTag text="YOU" />}</b>
        <em>{entry.title ?? RankPosition.title(rank)}</em>
        <span className="mpodiumrecord">{RankPosition.title(rank)} · {entry.wins}–{entry.losses}{winRate(entry) !== undefined && ` · ${winRate(entry)}%`}</span>
        <span className={`mpodiumslab ${entry.you ? "you" : ""}`} style={{ height: podiumUp ? (place === 1 ? 96 : place === 2 ? 74 : 56) : 14 }}>
          <strong>{place}</strong>
        </span>
      </button>
    );
  };

  const row = (entry: RankedLeaderboardEntry, pinned: boolean) => {
    const rank = RankedLeaderboard.rank(entry);
    const mythic = rank.tier === "mythic";
    const move = moves[entry.username];
    return (
      <button key={`${pinned ? "me" : "row"}-${entry.username}`} type="button"
        className={`mleaderrow mrise ${entry.you ? "you" : ""} ${mythic ? "mythic" : ""} ${pinned ? "pinned" : ""}`}
        aria-label={leaderboardLabel(entry)} data-id={pinned ? "leaderboard.me" : `leaderboard.row.${entry.username}`} onClick={() => open(entry)}>
        <strong className="mleaderplace">{entry.position}</strong>
        {/* Their commander's art, their rank's emblem on its rim. */}
        <span className="mleaderemblem">
          <Medallion name={entry.commander} size={40} />
          <span className="mleaderrank"><RankEmblem tier={rank.tier} size={20} /></span>
          {entry.online && <span className="mleaderdot"><OnlineDot size={9} /></span>}
        </span>
        <span className="grow">
          <span className="mleadername"><b>{entry.username}</b>{entry.you && <SocialTag text="YOU" />}</span>
          <small>{entry.title !== undefined ? `${RankPosition.title(rank)} · ${entry.title}` : RankPosition.title(rank)}</small>
        </span>
        <span className="mleaderend">
          {move !== undefined && <em className={move > 0 ? "up" : "down"}>{move > 0 ? "▲" : "▼"}{Math.abs(move)}</em>}
          {move === undefined && (entry.streak ?? 0) >= 3 && <em className="streak" aria-label={`${entry.streak} wins in a row`}>🔥{entry.streak}</em>}
          <span className="mleaderrecord">{entry.wins}–{entry.losses}</span>
          <span className="mleaderrate">{winRate(entry) === undefined ? "–" : `${winRate(entry)}%`}</span>
          {!mythic && (
            <span className="mrankpips" style={{ ["--pip" as string]: "7px" }} aria-hidden="true">
              {Array.from({ length: RankPosition.pipsPerDivision }, (_, i) => <i key={i} className={i < rank.pips ? "on" : ""} data-tier={rank.tier} />)}
            </span>
          )}
        </span>
        {mythic && <i className="mshimmer" aria-hidden="true" />}
      </button>
    );
  };

  let body;
  if (load.kind === "loading") {
    body = <div className="mcard msocialcard"><SocialWaiting text="Gathering the standings…" /></div>;
  } else if (load.kind === "offline") {
    body = (
      <p className="mcard msocialcard msocialtext" data-id="leaderboard.offline">
        <SocialGlyph name="wifi" size={16} />The leaderboard needs your profile and a connection. Sign in from your profile, then come back.
      </p>
    );
  } else if (tab === "champions") {
    const champions = load.board.champions;
    body = champions && champions.entries.length > 0 ? (
      <div className="mleaderbody mscroll" data-id="leaderboard.champions">
        <p className="mleaderchampions mrise">{RankLadder.seasonName(champions.season)} champions</p>
        <div className="mpodium mrise">{podiumOrder(champions.entries.slice(0, 3)).map(podiumStep)}</div>
      </div>
    ) : (
      <p className="mcard msocialcard msocialtext" data-id="leaderboard.champions.empty">
        <SocialGlyph name="sparkles" size={16} />The first champions are crowned when {RankLadder.seasonName(load.board.season)} ends.
      </p>
    );
  } else if (load.board.entries.length === 0) {
    body = (
      <p className="mcard msocialcard msocialtext" data-id="leaderboard.empty">
        <SocialGlyph name="sparkles" size={16} />
        {scope === "friends" ? "None of your friends has played ranked this season yet. Challenge one from Friends."
          : "Nobody has played ranked this season yet. Win a game to take the top spot."}
      </p>
    );
  } else {
    const board = load.board;
    const me = RankedLeaderboard.pinnedMe(board);
    body = (
      <div className="mleaderbody mscroll">
        <div className="mpodium mrise" data-id="leaderboard.podium">{podiumOrder(board.entries.slice(0, 3)).map(podiumStep)}</div>
        {(me || board.entries.length > 3) && (
          <div className="mleaderrows">
            <div className="mleaderhead" aria-hidden="true">
              <span className="mleaderplace">#</span><span className="grow">Player</span>
              <span className="mleaderend"><span className="mleaderrecord">Record</span><span className="mleaderrate">Win rate</span><span className="mleaderpipshead">Rank</span></span>
            </div>
            {me && row(me, true)}
            {board.entries.slice(3).map((entry, index, rest) => {
              // A tier's name over its first row.
              const tier = RankedLeaderboard.rank(entry).tier;
              const header = index === 0 || RankedLeaderboard.rank(rest[index - 1]).tier !== tier;
              return [header ? <div key={`tier-${tier}-${index}`} className="mleadertier" role="heading" aria-level={3}><span>{RankTier.name(tier)}</span></div> : null,
                row(entry, false)];
            })}
          </div>
        )}
      </div>
    );
  }

  return (
    <div className="mranked mleaderboard" data-id="leaderboard">
      <header className="mrankedhead mrise">
        <BackChevron onBack={onBack} />
        <h1 className="grow">Leaderboard</h1>
      </header>
      <div className="mleadertop">
        <div className="mleaderscope" data-id="leaderboard.scope">
          <Segmented stretch label="Leaderboard" value={tab} onChange={setTab}
            options={[{ value: "everyone" as const, label: "Everyone" }, { value: "friends" as const, label: "Friends" }, { value: "champions" as const, label: "Champions" }]} />
        </div>
        {loaded && (
          <div className="mleaderlive" data-id="leaderboard.live">
            <OnlineDot size={10} />
            <b>{onlineText(loaded.online)}</b>
            <span className="grow" />
            <small>{[`${loaded.total} ranked`, RankLadder.seasonName(loaded.season), RankLadder.seasonCountdown(loaded.season)].filter(Boolean).join(" · ")}</small>
          </div>
        )}
      </div>
      {body}
    </div>
  );
}
