/**
 * The player's own profile as Arena's (iOS Ranked/ProfileView.swift PlayerProfileView in its sideways "wide" layout,
 * with Ranked/ProfileVisuals.swift's pictures): the player's column scrolling on the left (the name with the chosen
 * title, the season rank and the progression tiles, then the rank history with past seasons, the deck filter, the
 * record as a ring with its tiles and streaks, games over time, the most played commanders as art, color identity, the
 * trophy shelf and the recent games), the shown commander as full-height hero art on the right with the Title and
 * Portrait pills at its foot, and Arena's Overview / Customization strip along the bottom. Title and portrait are
 * chosen in a glass panel. Charts are inline SVG.
 *
 * The account sign-in and privacy cards come from the shell (`account`). Left out: the saved-history settings and the
 * match dashboard (the web keeps no detailed game records), so a game card opens its details in place.
 */
import { type ReactNode, type RefObject, useEffect, useId, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Achievement, colorName, type MatchRecord, type PlayerRecordStore } from "../../core/playerRecord";
import {
  percent, portraitChoices, ProfileGame, type ProfileRankPoint, type ProfileShare, ProfileSummary, type ProfileWeek, rankChartRange,
} from "../../core/profileSummary";
import { RankLadder, RankPosition, RankTier } from "../../core/rankLadder";
import { ManaSymbol } from "../arena/Symbols";
import { gameAudio } from "../audio";
import { DeckArt } from "./DeckBox";
import { Btn, Caps, MenuPanel, PanelHeader, Pill, Segmented } from "./kit";
import { RankBadge } from "./PlayPanel";
import { RankEmblem } from "./TopBar";
import "./profile.css";

type Chooser = "title" | "picture";
type ProfileTab = "overview" | "customization";
type ResultFilter = "all" | "wins" | "losses" | "draws";

const RESULT_FILTERS: { value: ResultFilter; title: string }[] = [
  { value: "all", title: "All" }, { value: "wins", title: "Wins" }, { value: "losses", title: "Losses" }, { value: "draws", title: "Draws" },
];
const includes = (filter: ResultFilter, match: MatchRecord) =>
  filter === "all" || (filter === "wins" ? match.outcome === "win" : filter === "losses" ? match.outcome === "loss" : match.outcome === "draw");

/** Each tier's metal (RankTier.tint), as "r,g,b". */
const TINT: Record<RankTier, string> = {
  bronze: "204,128,69", silver: "204,212,224", gold: "255,204,92", platinum: "140,230,219", diamond: "128,191,255", mythic: "255,115,56",
};
/** ProfilePalette.mana. */
const MANA: Record<string, string> = { W: "#f7ebbd", U: "#4d8ce6", B: "#755c85", R: "#e34d38", G: "#52ad5c" };

const mediumDate = new Intl.DateTimeFormat(undefined, { dateStyle: "medium" });
const fullDate = new Intl.DateTimeFormat(undefined, { dateStyle: "full", timeStyle: "short" });
const weekDay = new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", timeZone: "UTC" });
const weekDayLong = new Intl.DateTimeFormat(undefined, { month: "long", day: "numeric", timeZone: "UTC" });

// MARK: Glyphs

/** Circles as one path, for glyphs drawn from rounds. */
const rounds = (list: [number, number, number][]) => list.map(([x, y, r]) => `M${x - r} ${y}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0z`).join("");

/** The profile's own SF Symbols, drawn as filled glyphs in a 24-unit box (the menu kit keeps the shared ones). */
const PROFILE_GLYPH: Record<string, { d: string; evenOdd?: boolean }> = {
  controller: { d: "M7 7h10a5 5 0 0 1 4.9 6l-.8 4a2.5 2.5 0 0 1-4.3 1.2L14.5 16h-5l-2.3 2.2A2.5 2.5 0 0 1 2.9 17l-.8-4A5 5 0 0 1 7 7zM6 10v1.5H4.5V13H6v1.5h1.5V13H9v-1.5H7.5V10z" + rounds([[16, 11.2, 1], [18.2, 13.4, 1]]), evenOdd: true },
  pie: { d: "M11 4a9 9 0 1 0 9 9h-9zM13 2v9h9a9 9 0 0 0-9-9z" },
  trophy: { d: "M7 3h10v2h3.5v2.5c0 2.6-1.9 4.6-4.4 4.9A5.5 5.5 0 0 1 13 15.3V18h3v3H8v-3h3v-2.7a5.5 5.5 0 0 1-3.1-2.9C5.4 12.1 3.5 10.1 3.5 7.5V5H7zM5.4 7v.5c0 1.2.6 2.2 1.6 2.6V7zm11.6 0v3.1c1-.4 1.6-1.4 1.6-2.6V7z", evenOdd: true },
  flame: { d: "M12 2c.5 3.5 5.5 6 5.5 11.5A5.5 5.5 0 0 1 12 22a5.5 5.5 0 0 1-5.5-5.5c0-2.8 1.6-4.4 2.5-6 .4 1.5 1.2 2.6 2.3 3C10.5 9.5 11.5 5 12 2z" },
  crown: { d: "M3 7l4.5 4L12 4l4.5 7L21 7l-2 11H5zM5.5 19.5h13V21h-13z" },
  star: { d: "M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.6L12 17.3l-5.9 3.3 1.3-6.6-4.9-4.6 6.6-.8z" },
  shield: { d: "M12 2.5 4 5.5v6c0 5 3.4 9 8 10.5 4.6-1.5 8-5.5 8-10.5v-6zm0 2.1v15.2c-3.3-1.4-6-4.5-6-8.3V6.9z", evenOdd: true },
  hourglass: { d: "M6 2h12v2h-1v2.5c0 2-1.3 3.7-3.2 4.5v2c1.9.8 3.2 2.5 3.2 4.5V20h1v2H6v-2h1v-2.5c0-2 1.3-3.7 3.2-4.5v-2C8.3 10.2 7 8.5 7 6.5V4H6z" },
  prism: { d: rounds([[12, 5.6, 3.2], [18.4, 10.2, 3.2], [16, 17.6, 3.2], [8, 17.6, 3.2], [5.6, 10.2, 3.2]]) },
  boltShield: { d: "M12 2.5 4 5.5v6c0 5 3.4 9 8 10.5 4.6-1.5 8-5.5 8-10.5v-6zM13.2 6 8.5 13h3.2l-1 5 4.8-7.2h-3.3z", evenOdd: true },
  hare: { d: "M8.6 2c1.3 0 1.9 2.6 1.9 5.6v1.1c.5-.1 1-.2 1.5-.2.4-3 1.3-5 2.4-5 1.2 0 1.3 2.4.6 5.4 2.6 1 4.1 3.3 4.1 6.1 0 1.1-.3 2.1-.8 3l1.3 1.5V21h-4.1l-.8-1.2A7 7 0 0 1 12 20c-2.7 0-5-1.5-6-3.6L4 17.5V15l1.5-.6c.1-2.4 1.3-4.4 3.1-5.3-1-3.5-.8-7.1 0-7.1z" },
  people: { d: rounds([[9, 7.5, 3.6], [16.5, 8.4, 3]]) + "M2 20c.5-4.2 3.2-6.6 7-6.6s6.5 2.4 7 6.6zm14.5 0c-.2-2.3-1-4.2-2.4-5.4.9-.5 1.9-.7 2.8-.7 3 0 5.3 2.2 5.6 6.1z" },
  chart: { d: "M3 19h18v2H3zM4 16.5l5-6 4 3.5 6-8 1.6 1.2-7.3 9.7-4-3.5-3.8 4.5z" },
  calendar: { d: "M7 2h2v2h6V2h2v2h2.5A1.5 1.5 0 0 1 21 5.5v14a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 19.5v-14A1.5 1.5 0 0 1 4.5 4H7zM5 9v10h14V9z", evenOdd: true },
  sparkles: { d: "M10 3c.6 4 2.5 6 6.5 6.5C12.5 10 10.6 12 10 16c-.6-4-2.5-6-6.5-6.5C7.5 9 9.4 7 10 3zm8 10c.3 2 1.2 2.9 3.2 3.2-2 .3-2.9 1.2-3.2 3.2-.3-2-1.2-2.9-3.2-3.2 2-.3 2.9-1.2 3.2-3.2z" },
  sparkle: { d: "M12 2c.8 5.5 3 9.2 10 10-7 .8-9.2 4.5-10 10-.8-5.5-3-9.2-10-10 7-.8 9.2-4.5 10-10z" },
  filter: { d: "M3 6h18v2H3zm3 5h12v2H6zm3 5h6v2H9z" },
};

/** Achievement.systemImage. */
const TROPHY_GLYPH: Record<Achievement, string> = {
  firstWin: "star", firstRankedWin: "shield", silver: "crown", gold: "crown", platinum: "crown", diamond: "crown", mythic: "crown",
  streak5: "flame", veteran: "hourglass", prismatic: "prism", giantSlayer: "boltShield", quickDraw: "hare", humanWin: "people",
};

/** A glyph cast in the menus' gold metal (`lit`), or in a flat fill. */
function Glyph({ name, size, lit, fill, className = "" }: { name: string; size: number; lit?: boolean; fill?: string; className?: string }) {
  const glyph = PROFILE_GLYPH[name];
  return (
    <svg className={`${lit ? "memblem lit" : ""} ${className}`} viewBox="0 0 24 24" width={size} height={size} aria-hidden="true">
      <path d={glyph.d} fillRule={glyph.evenOdd ? "evenodd" : undefined} fill={fill ?? "url(#mm-metal)"} />
    </svg>
  );
}

/** An element's width, kept current, for charts drawn to their card. */
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

// MARK: The page

export function ProfilePage({ record, playerName, deckCommanders, onChange, account }: {
  record: PlayerRecordStore; playerName: string; deckCommanders: string[]; onChange: () => void;
  /** The account and privacy cards, which follow the games (AccountSignInCard, privacyCard). */
  account?: ReactNode;
}) {
  const [tab, setTab] = useState<ProfileTab>("overview");
  const [deckFilter, setDeckFilter] = useState<string>();
  const [resultFilter, setResultFilter] = useState<ResultFilter>("all");
  const [showAllGames, setShowAllGames] = useState(false);
  const [chooser, setChooser] = useState<Chooser>("title");
  const [choosing, setChoosing] = useState(false);

  useEffect(() => {
    const before = record.rank;
    record.refreshSeason();
    if (record.rank !== before) onChange();
  }, [record]); // once per record, as iOS refreshes on appear

  const matches = record.matches;
  const stats = record.stats;
  const unlocked = record.achievements;
  const scoped = useMemo(() => (deckFilter === undefined ? [...matches] : matches.filter((m) => m.deckID === deckFilter)), [matches, deckFilter]);
  const summary = useMemo(() => ProfileSummary.forDeck(matches, deckFilter), [matches, deckFilter]);
  const all = useMemo(() => ProfileSummary.fromMatches(matches), [matches]);

  const choose = (next: Chooser, sound = true) => {
    if (sound) gameAudio.play("ui-open");
    setChooser(next);
    setChoosing(true);
  };
  const setTitle = (value: Achievement | undefined) => {
    gameAudio.play("ui-confirm");
    record.title = value;
    setChoosing(false);
    onChange();
  };
  const setPortrait = (value: string | undefined) => {
    gameAudio.play("ui-confirm");
    record.favoriteCommander = value;
    setChoosing(false);
    onChange();
  };
  const pickDeck = (id: string | undefined) => { setDeckFilter(id); setShowAllGames(false); };
  const pickResult = (filter: ResultFilter) => { setResultFilter(filter); setShowAllGames(false); };

  const nameBlock = (
    <div className="mprofilename">
      <h1 data-id="profile.name">{playerName === "" ? "Player" : playerName}</h1>
      {record.title !== undefined && <Caps text={Achievement.title(record.title)} />}
    </div>
  );

  const rank = record.rank;
  const identity = (
    <div className="mprofileidentity">
      <Caps text={`${RankLadder.seasonName(rank.season)} · Season rank`} />
      <div className="mcard mprofilerank">
        <RankBadge position={rank.position} size={64} showsPips={false} />
        <div className="grow">
          <b className="mprofileranktitle">{RankPosition.title(rank.position)}</b>
          {rank.position.tier !== "mythic" && (
            <span className="mrankpips" style={{ ["--pip" as string]: "10px" }} aria-label={`${rank.position.pips} of ${RankPosition.pipsPerDivision} pips`}>
              {Array.from({ length: RankPosition.pipsPerDivision }, (_, i) => <i key={i} className={i < rank.position.pips ? "on" : ""} data-tier={rank.position.tier} />)}
            </span>
          )}
          <span className="mprofilerecord">{rank.wins}–{rank.losses}</span>
          {!RankPosition.equal(rank.peak, rank.position) && <span className="mprofilepeak">Peak {RankPosition.title(rank.peak)}</span>}
        </div>
      </div>
      <Caps text="Progression" className="mprofileprogresscaps" />
      <div className="mprofileprogress" data-id="profile.career">
        <ProgressTile value={`${all.games}`} label="Games" glyph="controller" />
        <ProgressTile value={all.games === 0 ? "–" : `${percent(all.wins, all.games)}%`} label="Win rate" glyph="pie" />
        <ProgressTile value={`${unlocked.size}`} label="Trophies" glyph="trophy" />
      </div>
    </div>
  );

  const deckLabel = deckFilter === undefined ? undefined : stats.decks.find((d) => d.id === deckFilter)?.label;
  const visible = scoped.filter((m) => includes(resultFilter, m));
  const shown = visible.slice(0, showAllGames ? 40 : 6);

  const story = (
    <>
      <Card id="profile.season">
        <SectionTitle text="Rank history" />
        {summary.rankPoints.length === 0
          ? <EmptyNote text="Play ranked games to chart your climb." glyph="chart" />
          : <RankHistoryChart points={summary.rankPoints} />}
        {rank.history.length > 0 && (
          <>
            <i className="mprofilerule" />
            {rank.history.slice(0, 4).map((past) => (
              <div key={past.season} className="mprofileseason">
                <RankEmblem tier={past.final.tier} size={22} />
                <span className="grow">{RankLadder.seasonName(past.season)}: {RankPosition.title(past.final)}</span>
                <small>{past.wins}–{past.losses}</small>
              </div>
            ))}
          </>
        )}
      </Card>
      {stats.decks.length > 1 && (
        <div className="mprofilechips" data-id="profile.filter.decks">
          <Pill lit={deckFilter === undefined} id="profile.filter.deck.all" onClick={() => pickDeck(undefined)}>All decks<small>{matches.length}</small></Pill>
          {stats.decks.slice(0, 8).map((deck) => (
            <Pill key={deck.id} lit={deckFilter === deck.id} id={`profile.filter.deck.${deck.id}`} onClick={() => pickDeck(deck.id)}>
              {deck.label}<small>{deck.games}</small>
            </Pill>
          ))}
        </div>
      )}
      <Card id="profile.stats">
        <SectionTitle text={deckLabel ?? "Record"} trailing={`${summary.games} games`} />
        {summary.games === 0 ? <EmptyNote text="Your games show here after you play." /> : (
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
      <Card>
        <SectionTitle text="Games over time" trailing="last 8 weeks" />
        {summary.weeks.every((w) => w.games === 0) ? <EmptyNote text="Nothing played in the last eight weeks." glyph="calendar" /> : (
          <>
            <WeeklyBars weeks={summary.weeks} />
            <div className="mprofilelegend" aria-hidden="true">
              <span><i className="won" />Won</span>
              <span><i className="lost" />Not won</span>
            </div>
          </>
        )}
      </Card>
      {summary.commanders.length > 0 && (
        <Card>
          <SectionTitle text="Most played commanders" />
          <CommanderTiles shares={summary.commanders} />
        </Card>
      )}
      {summary.colors.length > 0 && (
        <Card>
          <SectionTitle text="Color identity" />
          <ColorPie shares={summary.colors} />
        </Card>
      )}
      <Card id="profile.achievements">
        <SectionTitle text="Trophies" trailing={`${unlocked.size}/${Achievement.all.length}`} />
        <TrophyShelf unlocked={unlocked} />
      </Card>
      <Card id="profile.history">
        <SectionTitle text="Recent games" trailing={`${visible.length} shown`} />
        <div className="mprofilechips">
          {RESULT_FILTERS.map((filter) => (
            <Pill key={filter.value} lit={resultFilter === filter.value} id={`profile.filter.result.${filter.value}`} onClick={() => pickResult(filter.value)}>
              {filter.title}
            </Pill>
          ))}
        </div>
        {matches.length === 0 ? <EmptyNote text="Your games show here after you play." />
          : visible.length === 0 ? <EmptyNote text="No games match these filters." glyph="filter" /> : null}
        {shown.map((match) => <GameCard key={match.id} game={ProfileGame.from(match)} />)}
        {visible.length > 6 && (
          <div>
            <Btn kind="secondary" compact sound="ui-tap" id="profile.games.more" onClick={() => setShowAllGames(!showAllGames)}>
              {showAllGames ? "Show fewer" : "Show more"}
            </Btn>
          </div>
        )}
      </Card>
      {account}
    </>
  );

  const shownCommander = record.shownCommander;
  const hero = (
    <div className="mprofilehero mrise" style={{ animationDelay: ".08s" }}>
      <button type="button" className="mprofileheroart" data-id="profile.picture"
        aria-label={shownCommander ? `Profile picture: ${shownCommander}` : "Profile picture"} onClick={() => choose("picture")}>
        <DeckArt name={shownCommander} colors={[]} />
      </button>
      <i className="mprofileheroshade" />
      <div className="mprofileherofoot">
        {shownCommander && <em className="grow">{shownCommander}</em>}
        {!shownCommander && <span className="grow" />}
        <Pill id="profile.title" onClick={() => choose("title", false)}>Title</Pill>
        <Pill id="profile.commander" onClick={() => choose("picture", false)}>Portrait</Pill>
      </div>
    </div>
  );

  const customization = (
    <div className="mprofilecustom">
      <CustomizationTile title="Portrait" id="profile.customize.picture" className="portrait" onClick={() => choose("picture")}>
        <DeckArt name={shownCommander} colors={[]} />
      </CustomizationTile>
      <CustomizationTile title="Title" id="profile.customize.title" className="title" onClick={() => choose("title")}>
        <div className="mprofiletitleface">
          <span className={record.title === undefined ? "none" : ""}>{record.title === undefined ? "No title" : Achievement.title(record.title)}</span>
        </div>
      </CustomizationTile>
    </div>
  );

  const choices = portraitChoices(stats.commanders.map((c) => c.label), deckCommanders, record.favoriteCommander);
  const earned = Achievement.all.filter((a) => unlocked.has(a));
  const chooserTitle = chooser === "title" ? "Choose a title" : "Choose a portrait";

  return (
    <>
      <svg width="0" height="0" style={{ position: "absolute" }} aria-hidden="true">
        <defs>
          <linearGradient id="mmp-flame" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="rgb(255,217,102)" /><stop offset="1" stopColor="rgb(237,128,56)" /></linearGradient>
        </defs>
      </svg>
      <div className="mprofile">
        <div className="mprofilebody">
          {tab === "overview" ? (
            <>
              <div className="mprofileleft mscroll mrise" data-id="lobby.scroll">
                {nameBlock}
                {identity}
                {story}
              </div>
              {hero}
            </>
          ) : customization}
        </div>
        <div className="mprofiletabs">
          <Segmented label="Profile" value={tab} onChange={setTab}
            options={[{ label: "Overview", value: "overview" }, { label: "Customization", value: "customization" }]} />
        </div>
      </div>
      <div className="mprofilepanels">
        <MenuPanel open={choosing} onClose={() => setChoosing(false)} label={chooserTitle} maxWidth={620}>
          <PanelHeader title={chooserTitle} onClose={() => setChoosing(false)} />
          <div className="mprofilechooser mscroll">
            {chooser === "title" ? (
              <div className="mprofiletitlegrid">
                {[undefined, ...earned].map((value) => {
                  const on = record.title === value;
                  return (
                    <button key={value ?? "none"} type="button" className={`mprofiletitletile ${on ? "on" : ""}`} aria-pressed={on}
                      data-id={`profile.title.${value ?? "none"}`} onClick={() => setTitle(value)}>
                      {value === undefined ? "No title" : Achievement.title(value)}
                    </button>
                  );
                })}
              </div>
            ) : (
              <>
                <div className="mprofileportraitgrid">
                  <PortraitTile value={undefined} art={stats.commanders[0]?.label} on={record.favoriteCommander === undefined} choose={setPortrait} />
                  {choices.played.map((name) => <PortraitTile key={name} value={name} art={name} on={record.favoriteCommander === name} choose={setPortrait} />)}
                </div>
                {choices.decks.length > 0 && (
                  <>
                    <Caps text="Your decks" className="mprofiledeckscaps" />
                    <div className="mprofileportraitgrid">
                      {choices.decks.map((name) => <PortraitTile key={name} value={name} art={name} on={record.favoriteCommander === name} choose={setPortrait} />)}
                    </div>
                  </>
                )}
              </>
            )}
          </div>
        </MenuPanel>
      </div>
    </>
  );
}

// MARK: Pieces

/** A story card: Arena's glass (TavernLeatherCard in the Arena look). */
function Card({ id, children }: { id?: string; children: ReactNode }) {
  return <section className="mcard mprofilecard" data-id={id}>{children}</section>;
}

/** A section's title in gold capitals, a count or span on the right (ProfileSectionTitle). */
function SectionTitle({ text, trailing }: { text: string; trailing?: string }) {
  return (
    <header className="mprofilesection">
      <h3>{text.toUpperCase()}</h3>
      {trailing !== undefined && <small>{trailing}</small>}
    </header>
  );
}

/** An empty picture's note: a line saying what will fill it (ProfileEmptyNote). */
function EmptyNote({ text, glyph = "sparkles" }: { text: string; glyph?: string }) {
  return <p className="mprofileempty"><Glyph name={glyph} size={16} />{text}</p>;
}

/** One of the progression's emblem tiles: a gold emblem over its number and name. */
function ProgressTile({ value, label, glyph }: { value: string; label: string; glyph: string }) {
  return (
    <div className="mcard mprofileprogresstile" role="group" aria-label={`${label}: ${value}`}>
      <span className="mprofileprogressglyph"><Glyph name={glyph} size={22} lit /></span>
      <b>{value}</b>
      <Caps text={label} size={8.5} />
    </div>
  );
}

/** A big number over a small caption, in a dark inset tile (ProfileStatTile). */
function StatTile({ title, value }: { title: string; value: string }) {
  return <div className="mprofilestat" role="group" aria-label={`${title}: ${value}`}><b>{value}</b><small>{title.toUpperCase()}</small></div>;
}

/** A current or best streak as a flame (StreakRow). */
function Streak({ title, value, hot }: { title: string; value: number; hot: boolean }) {
  return (
    <div className={`mprofilestreak ${hot ? "hot" : ""}`} role="img" aria-label={`${title}: ${value} wins in a row`}>
      <Glyph name="flame" size={20} fill={value > 0 ? "url(#mmp-flame)" : "rgba(128,128,128,.5)"} />
      <span><b>{value}</b><small>{title.toUpperCase()}</small></span>
    </div>
  );
}

/** The record as a ring: wins in gold, draws in stone, losses in muted rose, the win rate in the middle (WinRateRing). */
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
    <div className="mprofilering" style={{ width: box, height: box }} role="img" data-id="profile.winRate"
      aria-label={total === 0 ? "Win rate: no games yet" : `Win rate ${rate} percent: ${wins} wins, ${losses} losses, ${draws} draws`}>
      <svg width={box} height={box} viewBox={`0 0 ${box} ${box}`} aria-hidden="true">
        <defs>
          <linearGradient id={gradient} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="var(--pwin)" /><stop offset="1" stopColor="var(--pwindeep)" /></linearGradient>
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
    <div className="mprofileweeks" data-id="profile.weeks">
      {weeks.map((week) => (
        <div key={week.start} className="mprofileweek" role="img"
          aria-label={`Week of ${weekDayLong.format(week.start)}: ${week.games} games, ${week.wins} wins`}>
          <small>{week.games === 0 ? " " : week.games}</small>
          <span className="mprofilebar" style={{ height: barHeight }}>
            {week.games > week.wins && <i className="lost" style={{ height: ((week.games - week.wins) / peak) * barHeight }} />}
            {week.wins > 0 && <i className="won" style={{ height: (week.wins / peak) * barHeight }} />}
          </span>
          <em>{weekDay.format(week.start)}</em>
        </div>
      ))}
    </div>
  );
}

/** Rank over time: the standing after each ranked game, on the ladder's tiers (RankHistoryChart). */
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
  const lastTier = ProfileSummary.position(last).tier;
  const summaryText = points.length === 1
    ? `Rank history: ${RankPosition.title(ProfileSummary.position(last))} after one ranked game`
    : `Rank history: from ${RankPosition.title(ProfileSummary.position(first))} to ${RankPosition.title(ProfileSummary.position(last))} over ${points.length} ranked games`;
  const tierSpan = RankPosition.divisions * RankPosition.pipsPerDivision;
  const linePath = values.map((v, i) => `${i === 0 ? "M" : "L"}${x(i)} ${y(v)}`).join("");
  const areaPath = `M${x(0)} ${top + plot}` + values.map((v, i) => `L${x(i)} ${y(v)}`).join("") + `L${x(values.length - 1)} ${top + plot}Z`;
  return (
    <div className="mprofilechart" role="img" aria-label={summaryText} data-id="profile.rankHistory">
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
              const tint = TINT[tier];
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
            <circle cx={x(values.length - 1)} cy={y(last.points)} r={6} fill={`rgb(${TINT[lastTier]})`} stroke="rgba(255,255,255,.85)" strokeWidth={1.5}
              style={{ filter: `drop-shadow(0 0 5px rgb(${TINT[lastTier]}))` }} />
          </svg>
        )}
      </div>
      {points.length > 1 && (
        <div className="mprofilechartdates"><span>{mediumDate.format(first.date)}</span><span>{mediumDate.format(last.date)}</span></div>
      )}
    </div>
  );
}

/** Color identity as a ring of the five colors, by games played with each (ColorPie). */
function ColorPie({ shares, size = 112 }: { shares: ProfileShare[]; size?: number }) {
  const total = Math.max(1, shares.reduce((sum, s) => sum + s.games, 0));
  const line = size * 0.26, radius = (size - line) / 2, center = size / 2;
  const gap = shares.length > 1 ? 1.2 : 0;
  let start = -90;
  const arcs = shares.filter((s) => s.games > 0).map((share) => {
    const sweep = (360 * share.games) / total;
    const from = start + gap, to = start + sweep - gap;
    start += sweep;
    const point = (degrees: number) => {
      const r = (degrees * Math.PI) / 180;
      return `${center + radius * Math.cos(r)} ${center + radius * Math.sin(r)}`;
    };
    // A full circle can't be one arc: draw it as two halves.
    const d = to - from >= 359.9
      ? `M${point(from)}A${radius} ${radius} 0 1 1 ${point(from + 180)}A${radius} ${radius} 0 1 1 ${point(from + 360)}`
      : `M${point(from)}A${radius} ${radius} 0 ${to - from > 180 ? 1 : 0} 1 ${point(to)}`;
    return <path key={share.id} d={d} fill="none" stroke={MANA[share.id] ?? "#999"} strokeWidth={line} />;
  });
  return (
    <div className="mprofilecolors" data-id="profile.colors">
      <span className="mprofilepie" style={{ width: size, height: size }} aria-hidden="true">
        <svg width={size} height={size}>
          {arcs}
          <circle cx={center} cy={center} r={size / 2 - size * 0.02 - 0.5} fill="none" stroke="var(--hair)" strokeOpacity=".8" />
          <circle cx={center} cy={center} r={size / 2 - size * 0.28 - 0.5} fill="none" stroke="var(--hair)" strokeOpacity=".55" />
        </svg>
        <Glyph name="sparkle" size={size * 0.2} lit />
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
    <div className="mprofilecommanders" data-id="profile.commanders">
      {shares.map((share, index) => (
        <div key={share.id} className="mprofilecommander" role="img" aria-label={`${share.id}: ${share.games} games, ${share.wins} won`}>
          <DeckArt name={share.id} colors={[]} />
          <i className="mprofileshade" />
          <span><b>{share.id}</b><small>{share.games} games · {Math.round(ProfileSummary.shareWinRate(share) * 100)}% won</small></span>
          {index === 0 && <Glyph name="crown" size={15} lit className="mprofilecrown" />}
        </div>
      ))}
    </div>
  );
}

/** The achievements as gold coins on a wooden shelf; earned ones shine, the rest wait in the dark (TrophyShelf). */
function TrophyShelf({ unlocked }: { unlocked: Set<Achievement> }) {
  const [chosen, setChosen] = useState<Achievement>();
  const rows: Achievement[][] = [];
  for (let i = 0; i < Achievement.all.length; i += 5) rows.push(Achievement.all.slice(i, i + 5));
  return (
    <div className="mprofileshelf">
      {rows.map((row, index) => (
        <div key={index} className="mprofileshelfrow">
          <div className="mprofilecoins">
            {row.map((achievement) => {
              const earned = unlocked.has(achievement);
              return (
                <button key={achievement} type="button" className={`mprofilecoin ${earned ? "earned" : ""}`} data-id={`profile.trophy.${achievement}`}
                  aria-label={`${Achievement.title(achievement)}. ${Achievement.detail(achievement)} ${earned ? "Earned" : "Locked"}`}
                  onClick={() => setChosen(achievement)} onMouseEnter={() => setChosen(achievement)} onFocus={() => setChosen(achievement)}>
                  <i><Glyph name={TROPHY_GLYPH[achievement]} size={18} fill={earned ? "rgb(77,38,10)" : "rgba(128,128,128,.55)"} /></i>
                  <span>{Achievement.title(achievement)}</span>
                </button>
              );
            })}
            {Array.from({ length: 5 - row.length }, (_, i) => <span key={`gap${i}`} className="mprofilecoin" aria-hidden="true" />)}
          </div>
          <i className="mprofileplank" />
        </div>
      ))}
      <p className="mprofiletrophynote" data-id="profile.trophyNote" aria-live="polite">
        {chosen ? `${Achievement.title(chosen)}: ${Achievement.detail(chosen)}` : ""}
      </p>
    </div>
  );
}

/** One finished game as a card: the commander's art, who it was against, the result; a click opens its details (ProfileGameCard). */
function GameCard({ game }: { game: ProfileGame }) {
  const [expanded, setExpanded] = useState(false);
  const commander = ProfileGame.commander(game);
  const deck = game.deckName === "" ? (commander ?? "Deck") : game.deckName;
  const mode = ProfileGame.modeText(game);
  const opponents = ProfileGame.opponentText(game);
  const delta = game.rankDelta;
  const label = `${ProfileGame.resultName(game)} against ${opponents}, ${game.deckName === "" ? (commander ?? "") : game.deckName}, ${mode}, ${mediumDate.format(game.date)}`
    + (delta === undefined || delta === 0 ? "" : `, ${delta > 0 ? "+" : ""}${delta} pips`);
  return (
    <div className={`mprofilegame ${expanded ? "open" : ""}`}>
      <button type="button" className="mprofilegamehead" aria-expanded={expanded} aria-label={label} data-id={`profile.game.${game.id}`}
        onClick={() => { gameAudio.play("ui-tap"); setExpanded(!expanded); }}>
        <span className="mprofilegameart"><DeckArt name={commander} colors={[]} /></span>
        <span className="grow">
          <b>vs {opponents}</b>
          <small>{deck}</small>
          <span className="mprofilegamemeta"><i className="mprofiletag">{mode.toUpperCase()}</i>{mediumDate.format(game.date)}</span>
        </span>
        <span className="mprofilegameend">
          <i className={`mprofilestamp ${game.outcome}`}>{ProfileGame.resultLetter(game)}</i>
          {delta !== undefined && delta !== 0 && <em className={delta > 0 ? "up" : "down"}>{delta > 0 ? `+${delta}` : delta}</em>}
        </span>
      </button>
      {expanded && (
        <div className="mprofilegamedetails">
          {game.opponents.map((opponent, index) => (
            <div key={index} className="mprofileopponent">
              {opponent.commander && <span className="mprofileopponentart"><DeckArt name={opponent.commander} colors={[]} /></span>}
              <span className="grow"><b>{opponent.name}</b>{opponent.commander && <small>{opponent.commander}</small>}</span>
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

/** A tile of the Customization board: what the player shows, its name at the foot; a click opens its chooser. */
function CustomizationTile({ title, id, className, onClick, children }: { title: string; id: string; className: string; onClick: () => void; children: ReactNode }) {
  return (
    <button type="button" className={`mprofilecustomtile ${className}`} aria-label={title} data-id={id} onClick={onClick}>
      {children}
      <i className="mprofileshade" />
      <b>{title}</b>
    </button>
  );
}

/** One portrait: the commander's art in the profile's arch, its name under it; "Most played" (no value) follows the games. */
function PortraitTile({ value, art, on, choose }: { value: string | undefined; art: string | undefined; on: boolean; choose: (value: string | undefined) => void }) {
  return (
    <button type="button" className={`mprofileportrait ${on ? "on" : ""}`} aria-pressed={on} aria-label={value ?? "Most played"} onClick={() => choose(value)}>
      <span className="mprofilearch"><DeckArt name={art} colors={[]} /></span>
      <span>{value ?? "Most played"}</span>
    </button>
  );
}
