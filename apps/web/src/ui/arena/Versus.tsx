/**
 * The versus intro (iOS VersusIntroOverlay): before the first draw the two sides meet. Your commander slides in from the
 * left, theirs from the right, the VS medallion slams down with a ring, then the table shows. Purely visual: clicks pass
 * through, and it never holds the game up.
 */
import { useEffect, useState } from "react";
import { RankTier } from "../../core/rankLadder";
import { TIER_SHADE, TIER_TINT } from "../../core/socialText";
import { DeckArt } from "../menus/DeckBox";

/** `tier`: the player's ranked tier; their commander's arch is framed in its metal (Caleb, 2026-10-26). None for the AI. */
export interface VersusSeat { id: string; name: string; commander?: string; tier?: RankTier }

/** iOS's timings: in (0.45 s spring), the slam at 0.48 s, the fade 1.5 s later, gone 0.48 s after that. */
const SLAM_MS = 480, FADE_MS = 1980, DONE_MS = 2460;

export function VersusIntro({ you, opponents, finished }: { you: VersusSeat; opponents: VersusSeat[]; finished: () => void }) {
  const [phase, setPhase] = useState(0);
  useEffect(() => {
    const frame = requestAnimationFrame(() => setPhase(1));
    const timers = [setTimeout(() => setPhase(2), SLAM_MS), setTimeout(() => setPhase(3), FADE_MS), setTimeout(finished, DONE_MS)];
    return () => { cancelAnimationFrame(frame); timers.forEach(clearTimeout); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  const several = opponents.length > 1;
  return (
    <div className={`aversus p${phase}`} aria-label={`${you.name} versus ${opponents.map((o) => o.name).join(", ")}`} role="img">
      <div className="vside you"><Seat seat={you} tilt={-2} /></div>
      <div className={`vside them ${several ? "several" : ""}`}>{opponents.map((o) => <Seat key={o.id} seat={o} tilt={2} />)}</div>
      <i className="ring" aria-hidden="true" />
      <b className="vs" aria-hidden="true">VS</b>
    </div>
  );
}

/**
 * A player as Arena shows them before a match: their commander in a tall gold arch, their name on a black plate. A
 * ranked tier frames the arch in its metal instead (a bright edge over its dark, thicker the higher the tier) and glows in
 * its tint. No emblem on the arch (Caleb, 2026-10-26: badges belong on the profile).
 */
function Seat({ seat, tilt }: { seat: VersusSeat; tilt: number }) {
  const tier = seat.tier;
  const style = tier === undefined ? undefined : {
    ["--tint" as string]: TIER_TINT[tier], ["--shade" as string]: TIER_SHADE[tier], ["--rim" as string]: `${3 + RankTier.index(tier) * 0.6}px`,
  };
  return (
    <div className="vseat" style={{ transform: `rotate(${tilt}deg)` }}>
      <div className={`arch ${tier ? `tiered ${tier}` : ""}`} style={style}>
        <div className="archart"><DeckArt name={seat.commander} colors={[]} focus={0.3} /></div>
      </div>
      <span className="plate">{seat.name}</span>
    </div>
  );
}
