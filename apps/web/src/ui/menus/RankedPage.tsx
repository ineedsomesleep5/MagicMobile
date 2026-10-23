/**
 * Ranked's front room as Arena's Season Rewards (iOS Ranked/RankedHallViews.swift): "Ranked" with the season's end in
 * ember and Play Ranked beside it, a stair of tier plaques from Bronze to Mythic (what each allows, which you reached,
 * yours edged in gold), your current rank in its own column with its glow, and your past seasons. The ladder lives in
 * this browser's record until accounts arrive; then the live leaderboard joins it.
 */
import type { PlayerRecordStore } from "../../core/playerRecord";
import { RankLadder, RankPosition, type RankState, RankTier } from "../../core/rankLadder";
import { Caps, PlayButton } from "./kit";
import { RankBadge } from "./PlayPanel";
import { RankEmblem } from "./TopBar";

const TINT: Record<RankTier, string> = {
  bronze: "204,128,69", silver: "204,212,224", gold: "255,204,92", platinum: "140,230,219", diamond: "128,191,255", mythic: "255,115,56",
};

function seasonEnds(season: string) {
  const end = RankLadder.seasonEnd(season);
  if (!end) return RankLadder.seasonName(season);
  const days = Math.max(0, Math.ceil((end.getTime() - Date.now()) / 86_400_000));
  return days <= 1 ? "Season ends tomorrow" : `Season ends in ${days} days`;
}

export function RankedPage({ rank, play }: { rank: RankState; record: PlayerRecordStore; play: () => void }) {
  const tier = rank.position.tier;
  const reachedIndex = RankTier.index(tier);
  return (
    <div className="mranked">
      <header className="mrankedhead mrise">
        <div className="grow">
          <h1>Ranked</h1>
          <span className="mrankedends">{seasonEnds(rank.season)}</span>
        </div>
        <div className="mrankedplay"><PlayButton size={16} id="ranked.hall.play" onClick={play}>Play Ranked</PlayButton></div>
      </header>
      <div className="mrankedbody">
        <div className="mrankedleft mscroll">
          <div className="mtierstair" data-id="ranked.hall.tiers">
            {RankTier.all.map((step, index) => {
              const reached = index <= reachedIndex, current = step === tier;
              return (
                <div key={step} className={`mtierplaque mrise ${reached ? "" : "dim"} ${current ? "current" : ""}`}
                  style={{ width: 300 + index * 26, animationDelay: `${0.1 + index * 0.04}s` }}>
                  <RankEmblem tier={step} size={34} />
                  <span className="grow"><b>{RankTier.name(step)}</b><small>Decks up to Bracket {RankTier.maxDeckBracket(step)}</small></span>
                  {current ? <Caps text="You" size={9} /> : reached ? <i className="mtiercheck">✓</i> : null}
                </div>
              );
            })}
          </div>
          <div className="mseasons" data-id="ranked.hall.seasons">
            <Caps text="Past seasons" />
            {rank.history.length === 0 ? <p>First season</p> : (
              <div className="mseasonchips">
                {rank.history.slice(0, 6).map((season) => (
                  <div key={season.season} className="mseasonchip">
                    <RankEmblem tier={season.final.tier} size={44} />
                    <b>{RankPosition.title(season.final)}</b>
                    <small>{RankLadder.seasonName(season.season)}</small>
                    <em>{season.wins}–{season.losses}</em>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>
        <div className="mrankedright mrise" style={{ animationDelay: ".08s" }} data-id="ranked.hall.standing">
          <Caps text="Current rank" />
          <div className="mrankglowwrap">
            <i className="mrankglow" style={{ ["--tint" as string]: TINT[tier] }} />
            <RankBadge position={rank.position} size={104} />
          </div>
          <b className="mranktitle">{RankPosition.title(rank.position)}</b>
          <div className="mrankstats">
            <span><b>{rank.wins}</b><small>WINS</small></span>
            <span><b>{rank.losses}</b><small>LOSSES</small></span>
            <span><b>{RankPosition.title(rank.peak)}</b><small>PEAK</small></span>
          </div>
        </div>
      </div>
    </div>
  );
}
