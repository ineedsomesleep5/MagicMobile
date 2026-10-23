/**
 * Another player's profile, or your own as others see it (iOS Ranked/PublicProfileView.swift): their picture, name,
 * title and relation, Add friend / Accept / Message, their rank and its history, record, games over time, commanders,
 * colors and recent games. A human opponent's name in a game opens their profile in turn; back returns along them.
 * Report and Block sit in the ⋯ menu, each asked as a small glass question.
 *
 * Content for a centred MenuPanel. The pictures follow ProfilePage's (profile.css); ProfilePage keeps its own private,
 * so the few this page needs are drawn here.
 *
 * Left out for now: the Challenge button (friend challenges need hosting from the browser; a later phase).
 */
import { type ReactNode, type RefObject, useEffect, useId, useLayoutEffect, useRef, useState } from "react";
import { type PlayerAccount, ProfileVisibility, type PublicProfile as Profile, PublicProfile as ProfileRules } from "../../core/account";
import { colorName } from "../../core/playerRecord";
import { percent, ProfileGame, type ProfileRankPoint, type ProfileShare, ProfileSummary, type ProfileWeek, rankChartRange } from "../../core/profileSummary";
import { RankLadder, RankPosition, RankTier } from "../../core/rankLadder";
import { relationTag, TIER_TINT } from "../../core/socialText";
import { ManaSymbol } from "../arena/Symbols";
import { gameAudio } from "../audio";
import { DeckArt } from "./DeckBox";
import { Medallion, MoreMenu, SocialEmpty, SocialGlyph, SocialNotice, SocialQuestion, SocialTag, SocialWaiting, useAccountState } from "./FriendsPanel";
import { Btn, PanelHeader } from "./kit";
import { RankBadge } from "./PlayPanel";
import "./profile.css";
import "./social.css";

type Load =
  | { kind: "loading" } | { kind: "loaded"; profile: Profile } | { kind: "notFound" } | { kind: "unavailable" } | { kind: "failed"; message: string };

const MANA: Record<string, string> = { W: "#f7ebbd", U: "#4d8ce6", B: "#755c85", R: "#e34d38", G: "#52ad5c" };
const mediumDate = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
const fullDate = new Intl.DateTimeFormat(undefined, { dateStyle: "full", timeStyle: "short" });
const weekDay = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" });
const weekDayLong = new Intl.DateTimeFormat(undefined, { month: "long", day: "numeric", timeZone: "UTC" });

export function PublicProfile({ account, username, onClose, message }: {
  account: PlayerAccount;
  username: string;
  onClose: () => void;
  /** Opens a conversation with this friend; the Message button is left out without it. */
  message?: (username: string) => void;
}) {
  const state = useAccountState(account);
  /** The profiles opened one from another (an opponent's name); back returns along them. */
  const [stack, setStack] = useState<string[]>([username]);
  const [load, setLoad] = useState<Load>({ kind: "loading" });
  const [confirmBlock, setConfirmBlock] = useState(false);
  const [confirmReport, setConfirmReport] = useState(false);
  const [showAllGames, setShowAllGames] = useState(false);
  const [reloads, setReloads] = useState(0);
  const shown = stack[stack.length - 1];

  useEffect(() => { setStack([username]); }, [username]);
  useEffect(() => {
    let cancelled = false;
    setLoad({ kind: "loading" });
    void account.publicProfile(shown).then((result) => {
      if (cancelled) return;
      setLoad(result.kind === "profile" ? { kind: "loaded", profile: result.profile } : result);
    });
    return () => { cancelled = true; };
  }, [account, shown, reloads]);

  const reload = () => setReloads((n) => n + 1);
  const goBack = () => { setStack((list) => list.slice(0, -1)); setShowAllGames(false); };
  const openPlayer = (name: string) => { gameAudio.play("ui-open"); setStack((list) => [...list, name]); setShowAllGames(false); };
  const addFriend = async (profile: Profile) => { await account.addFriend(profile.username); reload(); };
  const respond = async (profile: Profile, accept: boolean) => {
    const friend = account.state.friends.find((f) => f.username === profile.username);
    if (!friend) return;
    await account.respond(friend, accept);
    reload();
  };

  const header = (profile: Profile) => (
    <div className="mcard mpublichead" data-id="publicProfile.header">
      <span className="mpublicpicture" data-id="publicProfile.picture">
        <Medallion name={profile.favoriteCommander ?? profile.summary.commanders[0]?.id} size={78} />
      </span>
      <span className="grow">
        <h1 data-id="publicProfile.name">{profile.username}</h1>
        <span className="msocialrow wrap">
          {profile.title !== undefined && <SocialTag text={profile.title} accent="ember" />}
          <SocialTag text={relationTag(profile)} />
        </span>
        {profile.online !== undefined && (
          <span className={`mpresence ${profile.online ? "on" : ""}`}><i className={`mplayerdot static ${profile.online ? "on" : ""}`} />{profile.online ? "Online" : "Offline"}</span>
        )}
      </span>
    </div>
  );

  const actions = (profile: Profile) => !ProfileRules.isSelf(profile) && (
    <div className="msocialrow mpublicactions">
      {profile.relation === "friend" ? (
        state.messagesAvailable && message && (
          <Btn kind="secondary" compact sound="ui-open" id="publicProfile.message" onClick={() => message(profile.username)}>Message</Btn>
        )
      ) : profile.relation === "outgoing" ? (
        <Btn kind="secondary" compact disabled id="publicProfile.requested">Request sent</Btn>
      ) : profile.relation === "incoming" ? (
        <>
          <Btn compact id="publicProfile.accept" onClick={() => void respond(profile, true)}>Accept request</Btn>
          <Btn kind="secondary" compact id="publicProfile.decline" onClick={() => void respond(profile, false)}>Decline</Btn>
        </>
      ) : (
        <Btn compact id="publicProfile.add" onClick={() => void addFriend(profile)}>Add friend</Btn>
      )}
      <span className="grow" />
      <MoreMenu label={`More about ${profile.username}`} id="publicProfile.more" size={17} items={[
        { title: "Report player", id: "publicProfile.more.report", destructive: true, onClick: () => setConfirmReport(true) },
        { title: "Block player", id: "publicProfile.more.block", destructive: true, onClick: () => setConfirmBlock(true) },
      ]} />
    </div>
  );

  let body: ReactNode;
  switch (load.kind) {
    case "loading":
      body = <div className="mcard msocialcard"><SocialWaiting text={`Opening ${shown}'s profile…`} /></div>;
      break;
    case "notFound":
      body = <SocialEmpty glyph="question" id="publicProfile.note" text="No player has that name, or you can't see them." />;
      break;
    case "unavailable":
      body = <SocialEmpty glyph="hourglass" id="publicProfile.note" text="Player profiles arrive with the next server update. You can still add friends and play with them." />;
      break;
    case "failed":
      body = (
        <>
          <SocialEmpty glyph="wifi" id="publicProfile.note" text={load.message} />
          <div><Btn kind="secondary" compact sound="ui-tap" id="publicProfile.retry" onClick={reload}>Try again</Btn></div>
        </>
      );
      break;
    case "loaded": {
      const profile = load.profile;
      body = profile.restricted ? (
        <>
          {header(profile)}
          <div className="mcard msocialcard mpublicrestricted" data-id="publicProfile.restricted">
            <SocialGlyph name="hand" size={30} />
            <b>{profile.visibility === "friends" ? "Only friends can open this profile." : "This profile is private."}</b>
            {!ProfileRules.isFriend(profile) && <small>You can still send {profile.username} a friend request.</small>}
          </div>
          {actions(profile)}
        </>
      ) : (
        <>
          {header(profile)}
          {ProfileRules.isSelf(profile)
            ? <SocialEmpty glyph="sparkles" id="publicProfile.selfNote" text={`This is how other players see your profile. It is ${ProfileVisibility.title(profile.visibility).toLowerCase()}.`} />
            : actions(profile)}
          <RankCard profile={profile} />
          <RecordCard profile={profile} />
          <Card>
            <SectionTitle text="Games over time" trailing="last 8 weeks" />
            {profile.summary.weeks.every((w) => w.games === 0)
              ? <EmptyNote text="Nothing played in the last eight weeks." glyph="hourglass" />
              : <WeeklyBars weeks={profile.summary.weeks} />}
          </Card>
          {profile.summary.commanders.length > 0 && (
            <Card><SectionTitle text="Most played commanders" /><CommanderTiles shares={profile.summary.commanders} /></Card>
          )}
          {profile.summary.colors.length > 0 && (
            <Card><SectionTitle text="Color identity" /><ColorPie shares={profile.summary.colors} /></Card>
          )}
          <Card id="publicProfile.history">
            <SectionTitle text="Recent games" trailing={`${profile.games.length} shown`} />
            {profile.games.length === 0 && <EmptyNote text="No recent games to show." />}
            {profile.games.slice(0, showAllGames ? 30 : 6).map((game) => <GameCard key={game.id} game={game} openPlayer={openPlayer} />)}
            {profile.games.length > 6 && (
              <div>
                <Btn kind="secondary" compact sound="ui-tap" id="publicProfile.games.more" onClick={() => setShowAllGames(!showAllGames)}>
                  {showAllGames ? "Show fewer" : "Show more"}
                </Btn>
              </div>
            )}
          </Card>
        </>
      );
      break;
    }
  }

  return (
    <div className="msocial mpublic">
      <PanelHeader title={shown} onBack={stack.length > 1 ? goBack : undefined} onClose={onClose} />
      <div className="mpublicscroll mscroll" data-id="publicProfile.scroll">{body}</div>
      {state.notice !== undefined && state.phase === "ready" && <SocialNotice text={state.notice} onDismiss={() => account.setNotice(undefined)} />}
      {confirmBlock && (
        <SocialQuestion id="publicProfile.confirmBlock" title={`Block ${shown}?`} confirm="Block"
          message="They're removed from your friends and can't send you requests. You can unblock them in Friends later."
          onCancel={() => setConfirmBlock(false)}
          onConfirm={() => { setConfirmBlock(false); void account.block(shown).then(onClose); }} />
      )}
      {confirmReport && (
        <SocialQuestion id="publicProfile.confirmReport" title={`Report ${shown}?`} confirm="Report"
          message="The developer reviews reports of a name or a profile. You can also block them."
          onCancel={() => setConfirmReport(false)}
          onConfirm={() => { setConfirmReport(false); void account.report(shown, undefined, "profile"); }} />
      )}
    </div>
  );
}

// MARK: Cards

function RankCard({ profile }: { profile: Profile }) {
  const rank = profile.rank;
  const position = rank ? ProfileRules.rankPosition(rank) : undefined;
  return (
    <Card id="publicProfile.rank">
      {rank && position ? (
        <>
          <div className="mpublicrank">
            <RankBadge position={position} size={96} />
            <span className="grow">
              <b style={{ ["--tint" as string]: TIER_TINT[position.tier] }}>{RankPosition.title(position)}</b>
              <small>Season {RankLadder.seasonName(rank.season)}</small>
              <span>Ranked {rank.wins}–{rank.losses} · Peak {RankPosition.title(RankPosition.atStep(rank.peakStep))}</span>
            </span>
          </div>
          <i className="mprofilerule" />
        </>
      ) : (
        <>
          <SectionTitle text="Rank" />
          <EmptyNote text={`${profile.username} hasn't played ranked this season.`} glyph="shield" />
        </>
      )}
      <SectionTitle text="Rank history" />
      {profile.summary.rankPoints.length === 0
        ? <EmptyNote text="No ranked games to chart yet." glyph="chart" />
        : <RankHistoryChart points={profile.summary.rankPoints} />}
    </Card>
  );
}

function RecordCard({ profile }: { profile: Profile }) {
  const summary = profile.summary;
  return (
    <Card id="publicProfile.stats">
      <SectionTitle text="Record" trailing={`${summary.games} games`} />
      {summary.games === 0 ? <EmptyNote text="No games to show yet." /> : (
        <>
          <div className="mprofilerecordrow">
            <WinRateRing wins={summary.wins} losses={summary.losses} draws={summary.draws} size={118} />
            <div className="mprofiletiles">
              <StatTile title="Wins" value={`${summary.wins}`} />
              <StatTile title="Losses" value={`${summary.losses}`} />
              <StatTile title="Draws" value={`${summary.draws}`} />
              <StatTile title="Avg. turns" value={summary.averageTurns === undefined ? "–" : summary.averageTurns.toFixed(1)} />
            </div>
          </div>
          <div className="mprofilestreaks">
            <Streak title="Streak" value={summary.currentStreak} hot={summary.currentStreak >= 3} />
            <Streak title="Best" value={summary.bestStreak} hot={false} />
          </div>
        </>
      )}
    </Card>
  );
}

// MARK: Pictures (ProfileVisuals.swift, as ProfilePage draws them)

const PICTURE_GLYPH: Record<string, string> = {
  flame: "M12 2c.5 3.5 5.5 6 5.5 11.5A5.5 5.5 0 0 1 12 22a5.5 5.5 0 0 1-5.5-5.5c0-2.8 1.6-4.4 2.5-6 .4 1.5 1.2 2.6 2.3 3C10.5 9.5 11.5 5 12 2z",
  crown: "M3 7l4.5 4L12 4l4.5 7L21 7l-2 11H5zM5.5 19.5h13V21h-13z",
  sparkle: "M12 2c.8 5.5 3 9.2 10 10-7 .8-9.2 4.5-10 10-.8-5.5-3-9.2-10-10 7-.8 9.2-4.5 10-10z",
  chart: "M3 19h18v2H3zM4 16.5l5-6 4 3.5 6-8 1.6 1.2-7.3 9.7-4-3.5-3.8 4.5z",
};

function PictureGlyph({ name, size, fill = "url(#mm-metal)", className = "" }: { name: string; size: number; fill?: string; className?: string }) {
  return <svg className={`memblem lit ${className}`} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true"><path d={PICTURE_GLYPH[name]} fill={fill} /></svg>;
}

function useWidth<T extends HTMLElement>(): [RefObject<T | null>, number] {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    setWidth(element.clientWidth);
    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));
    observer.observe(element);
    return () => observer.disconnect();
  }, []);
  return [ref, width];
}

function Card({ id, children }: { id?: string; children: ReactNode }) {
  return <section className="mcard mprofilecard" data-id={id}>{children}</section>;
}

function SectionTitle({ text, trailing }: { text: string; trailing?: string }) {
  return <header className="mprofilesection"><h3>{text.toUpperCase()}</h3>{trailing !== undefined && <small>{trailing}</small>}</header>;
}

function EmptyNote({ text, glyph = "sparkles" }: { text: string; glyph?: string }) {
  return <p className="mprofileempty">{glyph in PICTURE_GLYPH ? <PictureGlyph name={glyph} size={16} /> : <SocialGlyph name={glyph} size={16} />}{text}</p>;
}

function StatTile({ title, value }: { title: string; value: string }) {
  return <div className="mprofilestat" role="group" aria-label={`${title}: ${value}`}><b>{value}</b><small>{title.toUpperCase()}</small></div>;
}

function Streak({ title, value, hot }: { title: string; value: number; hot: boolean }) {
  return (
    <div className={`mprofilestreak ${hot ? "hot" : ""}`} role="img" aria-label={`${title}: ${value} wins in a row`}>
      <PictureGlyph name="flame" size={20} fill={value > 0 ? "url(#mpp-flame)" : "rgba(128,128,128,.5)"} />
      <span><b>{value}</b><small>{title.toUpperCase()}</small></span>
    </div>
  );
}

/** Wins in gold, draws in stone, losses in muted rose, the win rate in the middle (WinRateRing). */
function WinRateRing({ wins, losses, draws, size }: { wins: number; losses: number; draws: number; size: number }) {
  const gradient = useId();
  const total = wins + losses + draws;
  const line = size * 0.13;
  const box = size + line + 4;
  const center = box / 2, radius = size / 2, circumference = 2 * Math.PI * radius;
  const fraction = (count: number) => (total === 0 ? 0 : count / total);
  const segment = (start: number, length: number, stroke: string, key: string) => {
    if (length <= 0) return null;
    const gap = length < 1 ? 0.006 : 0;
    const drawn = Math.max(0.002, length - gap);
    return (
      <circle key={key} className="mprofileringseg" cx={center} cy={center} r={radius} fill="none" stroke={stroke} strokeWidth={line}
        strokeDasharray={`${drawn * circumference} ${circumference}`} transform={`rotate(${-90 + (start + gap / 2) * 360} ${center} ${center})`}
        style={{ ["--c" as string]: circumference }} />
    );
  };
  const rate = percent(wins, total);
  return (
    <div className="mprofilering" style={{ width: box, height: box }} role="img" data-id="publicProfile.winRate"
      aria-label={total === 0 ? "Win rate: no games yet" : `Win rate ${rate} percent: ${wins} wins, ${losses} losses, ${draws} draws`}>
      <svg width={box} height={box} viewBox={`0 0 ${box} ${box}`} aria-hidden="true">
        <defs>
          <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="var(--pwin)" /><stop offset="1" stopColor="var(--pwindeep)" /></linearGradient>
          <linearGradient id="mpp-flame" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="rgb(255,217,102)" /><stop offset="1" stopColor="rgb(237,128,56)" /></linearGradient>
        </defs>
        <circle cx={center} cy={center} r={radius} fill="none" stroke="var(--ptrack)" strokeWidth={line} />
        {total > 0 && [
          segment(0, fraction(wins), `url(#${gradient})`, "w"),
          segment(fraction(wins), fraction(draws), "var(--pdraw)", "d"),
          segment(fraction(wins) + fraction(draws), fraction(losses), "var(--loss)", "l"),
        ]}
        <circle cx={center} cy={center} r={radius + line / 2 + 1} fill="none" stroke="var(--hair)" strokeOpacity=".8" strokeWidth={1} />
      </svg>
      <span className="mprofileringtext">
        <b style={{ fontSize: size * 0.27 }}>{total === 0 ? "–" : `${rate}%`}</b>
        <small style={{ fontSize: size * 0.075 }}>WIN RATE</small>
      </span>
    </div>
  );
}

/** The last eight weeks as bars: wins in gold at the foot, other games in rose above (WeeklyBars). */
function WeeklyBars({ weeks, barHeight = 104 }: { weeks: ProfileWeek[]; barHeight?: number }) {
  const peak = Math.max(3, ...weeks.map((w) => w.games));
  return (
    <>
      <div className="mprofileweeks" data-id="publicProfile.weeks">
        {weeks.map((week) => (
          <div key={week.start} className="mprofileweek" role="img" aria-label={`Week of ${weekDayLong.format(week.start)}: ${week.games} games, ${week.wins} wins`}>
            <small>{week.games === 0 ? " " : week.games}</small>
            <span className="mprofilebar" style={{ height: barHeight }}>
              {week.games > week.wins && <i className="lost" style={{ height: ((week.games - week.wins) / peak) * barHeight }} />}
              {week.wins > 0 && <i className="won" style={{ height: (week.wins / peak) * barHeight }} />}
            </span>
            <em>{weekDay.format(week.start)}</em>
          </div>
        ))}
      </div>
      <div className="mprofilelegend" aria-hidden="true"><span><i className="won" />Won</span><span><i className="lost" />Not won</span></div>
    </>
  );
}

/** The standing after each ranked game, on the ladder's tiers (RankHistoryChart). */
function RankHistoryChart({ points, height = 150 }: { points: ProfileRankPoint[]; height?: number }) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const id = useId();
  const values = points.map((p) => p.points);
  const { low, high } = rankChartRange(values);
  const left = 26, right = 10, top = 10, bottom = 10;
  const plotWidth = Math.max(1, width - left - right), plot = height - top - bottom;
  const y = (value: number) => top + (1 - (value - low) / (high - low)) * plot;
  const x = (index: number) => (points.length === 1 ? left + plotWidth / 2 : left + (index / (points.length - 1)) * plotWidth);
  const first = points[0], last = points[points.length - 1];
  const lastTint = TIER_TINT[ProfileSummary.position(last).tier];
  const label = points.length === 1
    ? `Rank history: ${RankPosition.title(ProfileSummary.position(last))} after one ranked game`
    : `Rank history: from ${RankPosition.title(ProfileSummary.position(first))} to ${RankPosition.title(ProfileSummary.position(last))} over ${points.length} ranked games`;
  const tierSpan = RankPosition.divisions * RankPosition.pipsPerDivision;
  const linePath = values.map((v, i) => `${i === 0 ? "M" : "L"}${x(i)} ${y(v)}`).join("");
  const areaPath = `M${x(0)} ${top + plot}` + values.map((v, i) => `L${x(i)} ${y(v)}`).join("") + `L${x(values.length - 1)} ${top + plot}Z`;
  return (
    <div className="mprofilechart" role="img" aria-label={label} data-id="publicProfile.rankHistory">
      <div ref={ref} style={{ height }}>
        {width > 0 && (
          <svg width={width} height={height} aria-hidden="true">
            <defs>
              <linearGradient id={`${id}a`} x1="0" y1={top} x2="0" y2={top + plot} gradientUnits="userSpaceOnUse">
                <stop offset="0" stopColor="rgb(237,128,56)" stopOpacity=".38" /><stop offset="1" stopColor="rgb(237,128,56)" stopOpacity="0" />
              </linearGradient>
              <linearGradient id={`${id}l`} x1={left} y1="0" x2={left + plotWidth} y2="0" gradientUnits="userSpaceOnUse">
                <stop offset="0" stopColor="rgb(255,224,143)" /><stop offset="1" stopColor="rgb(237,128,56)" />
              </linearGradient>
            </defs>
            {RankTier.all.map((tier) => {
              const start = RankTier.index(tier) * tierSpan;
              const end = tier === "mythic" ? high : start + tierSpan;
              const visibleLow = Math.max(low, start), visibleHigh = Math.min(high, end);
              const tint = TIER_TINT[tier];
              return (
                <g key={tier}>
                  {start > low && start < high && (
                    <>
                      <line x1={left} x2={width - right} y1={y(start)} y2={y(start)} stroke={`rgba(${tint},.35)`} strokeDasharray="3 4" />
                      <text x={width - right} y={y(start) - 7} textAnchor="end" dominantBaseline="middle" className="mprofilecharttier" fill={`rgba(${tint},.85)`}>
                        {RankTier.name(tier)}
                      </text>
                    </>
                  )}
                  {visibleHigh - visibleLow >= 4 && (
                    <text x={10} y={y(Math.floor((visibleLow + visibleHigh) / 2))} textAnchor="middle" dominantBaseline="middle" className="mprofilechartinitial"
                      fill={`rgba(${tint},.9)`}>{RankTier.name(tier).charAt(0)}</text>
                  )}
                </g>
              );
            })}
            <path d={areaPath} fill={`url(#${id}a)`} />
            <path d={linePath} fill="none" stroke={`url(#${id}l)`} strokeWidth={2.5} strokeLinecap="round" strokeLinejoin="round" />
            {values.slice(0, -1).map((v, i) => <circle key={i} cx={x(i)} cy={y(v)} r={2.5} fill="rgb(255,230,158)" />)}
            <circle cx={x(values.length - 1)} cy={y(last.points)} r={6} fill={`rgb(${lastTint})`} stroke="rgba(255,255,255,.85)" strokeWidth={1.5}
              style={{ filter: `drop-shadow(0 0 5px rgb(${lastTint}))` }} />
          </svg>
        )}
      </div>
      {points.length > 1 && <div className="mprofilechartdates"><span>{mediumDate.format(first.date)}</span><span>{mediumDate.format(last.date)}</span></div>}
    </div>
  );
}

/** Color identity as a ring of the five colors, by games played with each (ColorPie). */
function ColorPie({ shares, size = 112 }: { shares: ProfileShare[]; size?: number }) {
  const total = Math.max(1, shares.reduce((sum, s) => sum + s.games, 0));
  const line = size * 0.26, radius = (size - line) / 2, center = size / 2;
  const gap = shares.length > 1 ? 1.2 : 0;
  let start = -90;
  const point = (degrees: number) => {
    const r = (degrees * Math.PI) / 180;
    return `${center + radius * Math.cos(r)} ${center + radius * Math.sin(r)}`;
  };
  const arcs = shares.filter((s) => s.games > 0).map((share) => {
    const sweep = (360 * share.games) / total;
    const from = start + gap, to = start + sweep - gap;
    start += sweep;
    // A full circle can't be one arc: draw it as two halves.
    const d = to - from >= 359.9
      ? `M${point(from)}A${radius} ${radius} 0 1 1 ${point(from + 180)}A${radius} ${radius} 0 1 1 ${point(from + 360)}`
      : `M${point(from)}A${radius} ${radius} 0 ${to - from > 180 ? 1 : 0} 1 ${point(to)}`;
    return <path key={share.id} d={d} fill="none" stroke={MANA[share.id] ?? "#999"} strokeWidth={line} />;
  });
  return (
    <div className="mprofilecolors" data-id="publicProfile.colors">
      <span className="mprofilepie" style={{ width: size, height: size }} aria-hidden="true">
        <svg width={size} height={size}>
          {arcs}
          <circle cx={center} cy={center} r={size / 2 - size * 0.02 - 0.5} fill="none" stroke="var(--hair)" strokeOpacity=".8" />
          <circle cx={center} cy={center} r={size / 2 - size * 0.28 - 0.5} fill="none" stroke="var(--hair)" strokeOpacity=".55" />
        </svg>
        <PictureGlyph name="sparkle" size={size * 0.2} />
      </span>
      <div className="mprofilecolorlist">
        {shares.map((share) => (
          <div key={share.id} role="img" aria-label={`${colorName(share.id)}: ${share.games} games, ${share.wins} wins`}>
            <ManaSymbol symbol={share.id} size={17} />
            <span className="grow">{colorName(share.id)}</span>
            <b>{percent(share.games, total)}%</b>
          </div>
        ))}
      </div>
    </div>
  );
}

/** The most played commanders as art tiles, the first with a crown (CommanderTiles). */
function CommanderTiles({ shares }: { shares: ProfileShare[] }) {
  return (
    <div className="mprofilecommanders" data-id="publicProfile.commanders">
      {shares.map((share, index) => (
        <div key={share.id} className="mprofilecommander" role="img" aria-label={`${share.id}: ${share.games} games, ${share.wins} won`}>
          <DeckArt name={share.id} colors={[]} />
          <i className="mprofileshade" />
          <span><b>{share.id}</b><small>{share.games} games · {Math.round(ProfileSummary.shareWinRate(share) * 100)}% won</small></span>
          {index === 0 && <PictureGlyph name="crown" size={15} className="mprofilecrown" />}
        </div>
      ))}
    </div>
  );
}

/** One finished game; a click opens its details, where a human opponent's name opens their profile (ProfileGameCard). */
function GameCard({ game, openPlayer }: { game: ProfileGame; openPlayer: (name: string) => void }) {
  const [expanded, setExpanded] = useState(false);
  const commander = ProfileGame.commander(game);
  const deck = game.deckName === "" ? (commander ?? "Deck") : game.deckName;
  const mode = ProfileGame.modeText(game);
  const opponents = ProfileGame.opponentText(game);
  const label = `${ProfileGame.resultName(game)} against ${opponents}, ${game.deckName === "" ? (commander ?? "") : game.deckName}, ${mode}, ${mediumDate.format(game.date)}`;
  return (
    <div className={`mprofilegame ${expanded ? "open" : ""}`}>
      <button type="button" className="mprofilegamehead" aria-expanded={expanded} aria-label={label} data-id={`publicProfile.game.${game.id}`}
        onClick={() => { gameAudio.play("ui-tap"); setExpanded(!expanded); }}>
        <span className="mprofilegameart"><DeckArt name={commander} colors={[]} /></span>
        <span className="grow">
          <b>vs {opponents}</b>
          <small>{deck}</small>
          <span className="mprofilegamemeta"><i className="mprofiletag">{mode.toUpperCase()}</i>{mediumDate.format(game.date)}</span>
        </span>
        <span className="mprofilegameend"><i className={`mprofilestamp ${game.outcome}`}>{ProfileGame.resultLetter(game)}</i></span>
      </button>
      {expanded && (
        <div className="mprofilegamedetails">
          {game.opponents.map((opponent, index) => (
            <div key={index} className="mprofileopponent">
              {opponent.commander && <span className="mprofileopponentart"><DeckArt name={opponent.commander} colors={[]} /></span>}
              <span className="grow">
                {!opponent.isAI && !opponent.hidden ? (
                  <button type="button" className="mpublicopponent" data-id={`publicProfile.game.${game.id}.opponent.${opponent.name}`}
                    onClick={() => openPlayer(opponent.name)}>{opponent.name}</button>
                ) : <b>{opponent.name}</b>}
                {opponent.commander && <small>{opponent.commander}</small>}
              </span>
              {opponent.isAI && <i className="mprofiletag">AI</i>}
            </div>
          ))}
          <p>{game.turns !== undefined && <span>{game.turns} turns</span>}<span>{fullDate.format(game.date)}</span></p>
          {game.opponents.length === 0 && <p className="mprofilenoopponents">Opponents weren't recorded for this game.</p>}
        </div>
      )}
    </div>
  );
}
