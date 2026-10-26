/**
 * Season badges (iOS Ranked/RankBadgeView.swift's SeasonBadgeView and SeasonBadgeShelf; Caleb, 2026-10-26): the emblem
 * of the tier a season peaked at, on a ribbon naming the season. Season 1 wears a gold founder ribbon with a star and a
 * soft gold glow; the season in play is dimmed under a dashed ring until it ends. Styles in profile.css.
 */
import { RankLadder, RankPosition, RankTier, SeasonBadge } from "../../core/rankLadder";
import { TIER_SHADE, TIER_TINT } from "../../core/socialText";
import { RankEmblem } from "./TopBar";

const ribbonText = (badge: SeasonBadge) => {
  if (badge.inProgress) return "IN PLAY";
  const number = SeasonBadge.number(badge);
  if (number === undefined) return RankTier.name(badge.peak.tier).toUpperCase();
  return SeasonBadge.founder(badge) ? "SEASON 1 ★" : `SEASON ${number}`;
};

const label = (badge: SeasonBadge) => {
  const name = RankLadder.seasonName(badge.season), peak = RankPosition.title(badge.peak);
  if (badge.inProgress) return `${name}, in play: peak so far ${peak}`;
  return SeasonBadge.founder(badge) ? `Season 1 founder, ${name}: peaked at ${peak}` : `${name}: peaked at ${peak}`;
};

/** One season's badge: the emblem, the ribbon under it, the season's name. */
export function SeasonBadgeView({ badge, size = 64, pinned = false }: { badge: SeasonBadge; size?: number; pinned?: boolean }) {
  const tier = badge.peak.tier;
  const classes = ["mseasonbadge", badge.inProgress ? "inplay" : "", SeasonBadge.founder(badge) ? "founder" : "", pinned ? "pinned" : ""].filter(Boolean).join(" ");
  return (
    <div className={classes} role="img" aria-label={label(badge)} data-id={`seasonBadge.${badge.season}`}
      style={{ width: size * 1.55, ["--size" as string]: `${size}px`, ["--tint" as string]: TIER_TINT[tier], ["--shade" as string]: TIER_SHADE[tier] }}>
      <span className="mseasonbadgeemblem"><RankEmblem tier={tier} size={size} /></span>
      <b className="mseasonribbon">{ribbonText(badge)}</b>
      <small>{RankLadder.seasonName(badge.season)}</small>
      {pinned && (
        <svg className="mseasonpin" viewBox="0 0 24 24" aria-hidden="true">
          <path d="M8 2h8l-1.5 2v5.2l3.5 3.3V15h-5v6l-1 1.5-1-1.5v-6H6v-2.5l3.5-3.3V4z" />
        </svg>
      )}
    </div>
  );
}

/** A row of season badges, newest first, the best finished one pinned at the front, slightly larger. */
export function SeasonBadgeShelf({ badges, size = 60 }: { badges: readonly SeasonBadge[]; size?: number }) {
  const best = SeasonBadge.best(badges);
  const rest = badges.filter((badge) => badge !== best);
  return (
    <div className="mseasonshelf" data-id="seasonBadges">
      {best && <SeasonBadgeView badge={best} size={size * 1.2} pinned />}
      {best && badges.length > 1 && <i className="mseasonshelfrule" style={{ height: size }} aria-hidden="true" />}
      {rest.map((badge) => <SeasonBadgeView key={badge.season} badge={badge} size={size} />)}
    </div>
  );
}
