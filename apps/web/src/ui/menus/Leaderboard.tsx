/**
 * The season's standings from the server (iOS Ranked/RankedHallViews.swift RankedLeaderboardView, in its sideways
 * layout): Everyone or Friends as a tab strip beside the live strip (who's online, how many are ranked, the season), the
 * top three on a podium of their own glass on the left, the rest down the right with your own row at its head when
 * you're off the list, a pulsing dot for who's online, places gained or lost since the last look, and a band of gold
 * light sweeping Mythic rows. Refreshes every 20 seconds while the page is visible.
 *
 * A full page under the top bar, like RankedPage.
 */
import { useEffect, useRef, useState } from "react";
import { type PlayerAccount, RankedLeaderboard, type RankedLeaderboardEntry, type RankedLeaderboardScope } from "../../core/account";
import { RankLadder, RankPosition } from "../../core/rankLadder";
import { leaderboardLabel, onlineText, placeMoves, podiumOrder, TIER_TINT } from "../../core/socialText";
import { gameAudio } from "../audio";
import { OnlineDot, SocialGlyph, SocialTag, SocialWaiting } from "./FriendsPanel";
import { BackChevron, Segmented } from "./kit";
import { RankEmblem } from "./TopBar";
import "./social.css";

const REFRESH_SECONDS = 20;

type Load = { kind: "loading" } | { kind: "loaded"; board: RankedLeaderboard } | { kind: "offline" };

export function Leaderboard({ account, onBack, openProfile }: {
  account: PlayerAccount;
  onBack: () => void;
  /** Opens a player's profile from their row; rows don't open anything without it. */
  openProfile?: (username: string) => void;
}) {
  const [scope, setScope] = useState<RankedLeaderboardScope>("everyone");
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
          {place === 1 && <i className="mrankglow" style={{ ["--tint" as string]: TIER_TINT[rank.tier], width: 86, height: 86 }} />}
          <RankEmblem tier={rank.tier} size={place === 1 ? 58 : 46} />
          {entry.online && <span className="mpodiumdot"><OnlineDot size={12} /></span>}
        </span>
        <b>{entry.username}</b>
        <em>{entry.title ?? RankPosition.title(rank)}</em>
        <span className={`mpodiumslab ${entry.you ? "you" : ""}`} style={{ height: podiumUp ? (place === 1 ? 72 : place === 2 ? 56 : 44) : 14 }}>
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
        <span className="mleaderemblem">
          <RankEmblem tier={rank.tier} size={40} />
          {entry.online && <span className="mleaderdot"><OnlineDot size={9} /></span>}
        </span>
        <span className="grow">
          <span className="mleadername"><b>{entry.username}</b>{entry.you && <SocialTag text="YOU" />}</span>
          <small>{entry.title !== undefined ? `${RankPosition.title(rank)} · ${entry.title}` : RankPosition.title(rank)}</small>
        </span>
        <span className="mleaderend">
          {move !== undefined && <em className={move > 0 ? "up" : "down"}>{move > 0 ? "▲" : "▼"}{Math.abs(move)}</em>}
          <span className="mleaderrecord">{entry.wins}–{entry.losses}</span>
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
      <div className="mleaderbody">
        <div className="mcard mpodium mrise" data-id="leaderboard.podium">{podiumOrder(board.entries.slice(0, 3)).map(podiumStep)}</div>
        <div className="mleaderrows mscroll">
          {me && row(me, true)}
          {board.entries.slice(3).map((entry) => row(entry, false))}
        </div>
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
          <Segmented stretch label="Leaderboard" value={scope} onChange={setScope}
            options={RankedLeaderboard.scopes.map((value) => ({ value, label: value === "everyone" ? "Everyone" : "Friends" }))} />
        </div>
        {loaded && (
          <div className="mleaderlive" data-id="leaderboard.live">
            <OnlineDot size={10} />
            <b>{onlineText(loaded.online)}</b>
            <span className="grow" />
            <small>{loaded.total} ranked · {RankLadder.seasonName(loaded.season)}</small>
          </div>
        )}
      </div>
      {body}
    </div>
  );
}
