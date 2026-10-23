/**
 * Arena's Play panel (iOS Menus/ArenaPlayPanel.swift): the room darkened, your decks as boxes by shelf on the left, and on
 * the right the blade, lit along its seam, with the tabs (Find Match, Friends, Recently Played), the ways to play (Quick,
 * Ranked, Custom gems), their options and the Play plaque in the footer. The shell owns the state; the panel draws it.
 */
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import type { AIDeck } from "../../core/aiDeckPool";
import { CommanderBracket } from "../../core/brackets";
import type { PlayMode } from "../../core/playerRecord";
import { RankPosition, RankTier, type RankState } from "../../core/rankLadder";
import { type RankedPhase, RankedMatchmaker } from "../../core/matchmaking";
import { gameAudio } from "../audio";
import { boxGeometry, DeckArt, DeckBox, type DeckBoxModel } from "./DeckBox";
import { Caps, CloseButton, Emblem, OptionRow, Pill, Pips, PlayButton, SectionHeader, Seam, Stepper, TabBar } from "./kit";
import { RankEmblem } from "./TopBar";

export type PlayTab = "find" | "friends" | "recent";
export type ArenaPlayMode = "quick" | "ranked" | "custom";
export type FriendWay = "challenge" | "host" | "join";

export interface DeckSection { id: string; title: string; decks: DeckBoxModel[] }

/** A game from the record, offered again from Recently Played. */
export interface RecentGame { id: string; mode: PlayMode; deckID: string; deckName: string; commander?: string; colors: string[]; detail: string; won?: boolean }

export interface PlayModel {
  sections: DeckSection[];
  selectedDeckID: string;
  selectDeck: (id: string) => void;
  deckBracket?: CommanderBracket;
  mode: ArenaPlayMode;
  setMode: (mode: ArenaPlayMode) => void;
  tab: PlayTab;
  setTab: (tab: PlayTab) => void;
  quickBracket: number;
  setQuickBracket: (value: number) => void;
  quickDeckID: string;
  setQuickDeckID: (id: string) => void;
  /** The decks Quick Match can meet at the bracket it resolves to. */
  quickPool: AIDeck[];
  quickResolvedBracket: number;
  quickSkill: number;
  setQuickSkill: (value: number) => void;
  startingPlayer: "roll" | "choose";
  setStartingPlayer: (value: "roll" | "choose") => void;
  rank: RankState;
  playerMode: "ai" | "online";
  setPlayerMode: (value: "ai" | "online") => void;
  friendWays: FriendWay[];
  mayStart: boolean;
  status?: string;
  recent: RecentGame[];
  close: () => void;
  explainBracket: () => void;
  startQuick: () => void;
  findRanked: () => void;
  openCustom: () => void;
  rankedHall: () => void;
  leaderboard: () => void;
  friendWay: (way: FriendWay) => void;
  chooseRecent: (game: RecentGame) => void;
  /** The ranked queue while it looks for a person (RankedMatchmaker.phase), with Cancel and "Play the AI now". */
  search?: RankedPhase;
  cancelSearch?: () => void;
  playAINow?: () => void;
}

const modeTitle = { quick: "Quick", ranked: "Ranked", custom: "Custom" } as const;
const tabTitle = { find: "Find Match", friends: "Friends", recent: "Recently Played" } as const;
const tabSymbol = { find: "find", friends: "friends", recent: "recent" } as const;
const friendTitle = { challenge: "Challenge a friend", host: "Host an online table", join: "Join with a code" } as const;
const friendPlay = { challenge: "Challenge", host: "Host Table", join: "Join Table" } as const;

export function PlayPanel({ model }: { model: PlayModel }) {
  return (
    <div className="mplay" data-id="play.panel">
      <div className="mplaydim" />
      <DeckPicker model={model} />
      <Blade model={model} />
    </div>
  );
}

function heading(model: PlayModel) {
  if (model.tab === "friends") return "Play with Friends";
  if (model.tab === "recent") return "Recently Played";
  return model.mode === "quick" ? "Quick Match" : model.mode === "ranked" ? "Ranked" : "Custom Table";
}

/** The left of the panel: the way to play in a few words, and every deck as a box, by shelf. */
function DeckPicker({ model }: { model: PlayModel }) {
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const scroller = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(600);
  useLayoutEffect(() => {
    const node = scroller.current;
    if (!node) return;
    const observer = new ResizeObserver(() => setWidth(node.clientWidth));
    observer.observe(node);
    setWidth(node.clientWidth);
    return () => observer.disconnect();
  }, []);
  // Once laid out, bring the chosen deck's shelf into view; a deck chosen elsewhere scrolls into view.
  useEffect(() => {
    const timer = window.setTimeout(() => {
      const node = scroller.current?.querySelector(`[data-deck="${CSS.escape(model.selectedDeckID)}"]`);
      node?.scrollIntoView({ block: "nearest", behavior: "smooth" });
    }, 250);
    return () => window.clearTimeout(timer);
  }, [model.selectedDeckID]);
  const gap = 12;
  const usable = width - 48;
  const columns = Math.max(2, Math.floor((usable + gap) / (112 + gap)));
  const boxWidth = Math.floor((usable - gap * (columns - 1)) / columns);
  const rise = boxGeometry(boxWidth).rise;
  const oneOpponent = model.mode !== "custom";
  return (
    <div className="mpicker">
      <header>
        <div className="grow">
          <h2>{heading(model)}</h2>
          <div className="mpickermeta">
            {model.tab === "find" && <Caps text={oneOpponent ? "100 cards · 1v1" : "100 cards · up to 4 players"} size={9.5} />}
            {model.deckBracket !== undefined && (
              <button type="button" className="mbracketchip" data-id="play.deck.bracket" onClick={model.explainBracket}
                aria-label={`${CommanderBracket.title(model.deckBracket)}. Bracket details`}>
                <span>{CommanderBracket.title(model.deckBracket)}</span><i>i</i>
              </button>
            )}
          </div>
        </div>
        <CloseButton onClose={model.close} id="lobby.back" />
      </header>
      {model.tab === "recent" ? <RecentShelf model={model} /> : (
        <div ref={scroller} className="mshelves mscroll">
          {model.sections.map((section) => {
            const shut = collapsed.has(section.id);
            return (
              <section key={section.id}>
                <SectionHeader title={section.title} count={section.decks.length} collapsed={shut}
                  onToggle={() => setCollapsed((set) => { const next = new Set(set); if (next.has(section.id)) next.delete(section.id); else next.add(section.id); return next; })} />
                {!shut && (
                  <div className="mshelf" style={{ gridTemplateColumns: `repeat(${columns}, ${boxWidth}px)`, columnGap: gap, rowGap: rise + 8, paddingTop: rise + 12 }}>
                    {section.decks.map((deck) => (
                      <button key={deck.id} type="button" className="mdeckbutton" data-deck={deck.id} data-id={`play.deck.${deck.id}`}
                        aria-pressed={deck.id === model.selectedDeckID}
                        onClick={() => { gameAudio.play("ui-tap"); model.selectDeck(deck.id); }}>
                        <DeckBox deck={deck} selected={deck.id === model.selectedDeckID} width={boxWidth} />
                      </button>
                    ))}
                  </div>
                )}
              </section>
            );
          })}
        </div>
      )}
    </div>
  );
}

/** Recently Played: a tall tile for each recent table, or one quiet line. */
function RecentShelf({ model }: { model: PlayModel }) {
  if (model.recent.length === 0) {
    return (
      <div className="mrecentempty" data-id="recent.empty">
        <Emblem name="recent" size={30} />
        <b>No tables yet</b>
      </div>
    );
  }
  const chosen = (game: RecentGame) => game.deckID === model.selectedDeckID
    && (game.mode === "quick" ? model.mode === "quick" : game.mode === "ranked" ? model.mode === "ranked" : model.mode === "custom");
  return (
    <div className="mrecent mscroll">
      {model.recent.map((game) => (
        <button key={game.id} type="button" className={`mrecenttile ${chosen(game) ? "on" : ""}`} data-id={`recent.${game.id}`}
          onClick={() => { gameAudio.play("ui-tap"); model.chooseRecent(game); }}>
          <span className="mrecentart"><DeckArt name={game.commander} colors={game.colors} /><span className="mrecentpips"><Pips colors={game.colors} size={14} /></span></span>
          <Caps text={game.mode === "quick" ? "Quick Match" : game.mode === "ranked" ? "Ranked" : "Custom Table"} size={9} />
          <b>{game.deckName}</b>
          <span className="mrecentline"><small>{game.detail}</small>{game.won !== undefined && <em className={game.won ? "win" : "loss"}>{game.won ? "Won" : "Lost"}</em>}</span>
        </button>
      ))}
    </div>
  );
}

/** The right of the panel: tabs, the ways to play, options, and the Play plaque. */
function Blade({ model }: { model: PlayModel }) {
  const [friendWay, setFriendWay] = useState<FriendWay>(model.friendWays[0] ?? "join");
  return (
    <aside className="mblade">
      <Seam vertical />
      <nav className="mbladetabs">
        {(["find", "friends", "recent"] as PlayTab[]).map((tab) => {
          const on = model.tab === tab;
          return (
            <button key={tab} type="button" className={on ? "on" : ""} aria-pressed={on} data-id={`play.tab.${tab}`}
              onClick={() => { gameAudio.play("ui-tap"); model.setTab(tab); }}>
              <Emblem name={tabSymbol[tab]} size={18} lit={on} /><span>{tabTitle[tab]}</span><TabBar on={on} />
            </button>
          );
        })}
      </nav>
      {model.tab === "find" && (
        <div className="mbladegems">
          {(["quick", "ranked", "custom"] as ArenaPlayMode[]).map((mode) => {
            const on = model.mode === mode;
            return (
              <button key={mode} type="button" className={on ? "on" : ""} aria-pressed={on} data-id={`play.${mode}`}
                onClick={() => { gameAudio.play("ui-tap"); model.setMode(mode); }}>
                <ModeGem mode={mode} tier={model.rank.position.tier} lit={on} /><span>{modeTitle[mode]}</span>
              </button>
            );
          })}
        </div>
      )}
      <div className="mbladeoptions mscroll">
        {model.tab === "find" && model.mode === "quick" && <QuickOptions model={model} />}
        {model.tab === "find" && model.mode === "ranked" && <RankedOptions model={model} />}
        {model.tab === "find" && model.mode === "custom" && (
          <>
            <Caps text="Players" size={9.5} className="mhead" />
            <OptionRow title="Against the AI" selected={model.playerMode === "ai"} id="custom.ai" onClick={() => model.setPlayerMode("ai")} />
            <OptionRow title="Online table" selected={model.playerMode === "online"} id="custom.online" onClick={() => model.setPlayerMode("online")} />
          </>
        )}
        {model.tab === "friends" && (
          <>
            <Caps text="With friends" size={9.5} className="mhead" />
            {model.friendWays.map((way) => <OptionRow key={way} title={friendTitle[way]} selected={friendWay === way} id={`friends.${way}`} onClick={() => setFriendWay(way)} />)}
          </>
        )}
        {model.tab === "recent" && <RecentOptions model={model} />}
      </div>
      <footer className="mbladefoot">
        {model.status && <p className="mstatus">{model.status}</p>}
        <div className="mbladeplay"><Primary model={model} friendWay={friendWay} /></div>
      </footer>
    </aside>
  );
}

function Primary({ model, friendWay }: { model: PlayModel; friendWay: FriendWay }) {
  if (model.tab === "friends") return <PlayButton size={20} id="play.friends" onClick={() => model.friendWay(friendWay)}>{friendPlay[friendWay]}</PlayButton>;
  if (model.tab === "recent" && model.recent.length === 0) return <PlayButton size={20} id="play.recent" onClick={() => model.setTab("find")}>Find Match</PlayButton>;
  if (model.mode === "quick") return <PlayButton size={20} id="quick.start" disabled={!model.mayStart} onClick={model.startQuick}>Play</PlayButton>;
  if (model.mode === "ranked" && model.search && model.search.kind !== "idle") {
    return <PlayButton size={20} cancel id="ranked.cancel" onClick={() => model.cancelSearch?.()}>Cancel</PlayButton>;
  }
  if (model.mode === "ranked") {
    const eligible = (model.deckBracket ?? 99) <= RankTier.maxDeckBracket(model.rank.position.tier);
    return <PlayButton size={20} id="ranked.find" disabled={!model.mayStart || !eligible} onClick={model.findRanked}>Find Match</PlayButton>;
  }
  return <PlayButton size={20} id="play.start" onClick={model.openCustom}>Set Up Table</PlayButton>;
}

/** Quick Match: the opponent's bracket as five gems, the opponent's deck on one row, then skill and who goes first. */
function QuickOptions({ model }: { model: PlayModel }) {
  const brackets = CommanderBracket.all.filter((b) => b !== CommanderBracket.cedh);
  const chosen = brackets.find((b) => b === model.quickBracket);
  const matched = model.deckBracket !== undefined ? `Match my deck · B${Math.min(4, model.deckBracket)}` : "Match my deck";
  const gem = (text: string, value: number, label: string) => {
    const on = model.quickBracket === value;
    return (
      <button key={value} type="button" className={`mbracketgem ${on ? "on" : ""} ${value === 0 ? "match" : ""}`} aria-label={label} aria-pressed={on}
        data-id={`quick.bracket.${value}`} onClick={() => { gameAudio.play("ui-tap"); model.setQuickBracket(value); }}>{text}</button>
    );
  };
  const roll = model.startingPlayer === "roll";
  return (
    <>
      <Caps text={chosen !== undefined ? `Opponent · ${CommanderBracket.name(chosen)}` : "Opponent · Match my deck"} size={9.5} className="mhead" />
      <div className="mbracketgems">{gem("Match", 0, matched)}{brackets.map((b) => gem(String(b), b, CommanderBracket.name(b)))}</div>
      <OpponentDeckRow model={model} />
      <div className="mquickrow">
        <Stepper title="AI skill" value={model.quickSkill} min={1} max={10} onChange={model.setQuickSkill} compact id="quick.skill" />
        <button type="button" className={`mroll ${roll ? "on" : ""}`} data-id="quick.startingPlayer" aria-label="Who goes first"
          title={roll ? "Everyone rolls a D20" : "Choose at the table"} onClick={() => { gameAudio.play("ui-tap"); model.setStartingPlayer(roll ? "choose" : "roll"); }}>
          <Emblem name="dice" size={15} lit={roll} /><span>{roll ? "D20" : "Pick"}</span>
        </button>
      </div>
    </>
  );
}

/** The opponent's deck as one of the blade's rows: a click lists the decks at that bracket in a glass pop-over. */
function OpponentDeckRow({ model }: { model: PlayModel }) {
  const [open, setOpen] = useState(false);
  const chosen = model.quickPool.find((d) => d.id === model.quickDeckID);
  const list = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!open) return;
    list.current?.querySelector(".on")?.scrollIntoView({ block: "center" });
    const close = (e: MouseEvent) => { if (!list.current?.parentElement?.contains(e.target as Node)) setOpen(false); };
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); setOpen(false); } };
    window.addEventListener("pointerdown", close);
    window.addEventListener("keydown", key, true);
    return () => { window.removeEventListener("pointerdown", close); window.removeEventListener("keydown", key, true); };
  }, [open]);
  const pick = (id: string) => { gameAudio.play("ui-tap"); model.setQuickDeckID(id); setOpen(false); };
  return (
    <div className="mopponent">
      <button type="button" className="mopponentrow" data-id="quick.deck" aria-expanded={open} aria-label={`Opponent deck, ${chosen?.name ?? "Surprise me"}`}
        onClick={() => { gameAudio.play("ui-open"); setOpen(!open); }}>
        <span>Opponent</span><em>{chosen?.name ?? "Surprise me"}</em>
        <svg className="mchev" viewBox="0 0 24 24" aria-hidden="true"><path d="M9 5l7 7-7 7" /></svg>
      </button>
      {open && (
        <div ref={list} className="mpopover glass" role="listbox">
          <button type="button" role="option" aria-selected={!chosen} className={!chosen ? "on" : ""} onClick={() => pick("")}><i />Surprise me</button>
          <Caps text={`Bracket ${model.quickResolvedBracket} decks`} size={9.5} className="mhead" />
          {model.quickPool.map((deck) => (
            <button key={deck.id} type="button" role="option" aria-selected={deck.id === chosen?.id} className={deck.id === chosen?.id ? "on" : ""}
              onClick={() => pick(deck.id)}><i />{deck.name} · {deck.commander}</button>
          ))}
        </div>
      )}
    </div>
  );
}

/** Ranked: your standing, the one format, and the ways to the season and the leaderboard side by side. */
function RankedOptions({ model }: { model: PlayModel }) {
  const { rank } = model;
  const position = rank.position;
  const eligible = (model.deckBracket ?? 99) <= RankTier.maxDeckBracket(position.tier);
  const searching = model.search !== undefined && model.search.kind !== "idle";
  return (
    <>
      <Caps text="Ranked Commander · 1v1" size={9.5} className="mhead" />
      <div className="mstanding" data-id="ranked.standing">
        <RankBadge position={position} size={searching ? 30 : 42} />
        <span><b>{RankPosition.title(position)}</b><small>{rank.wins} wins · {rank.losses} losses</small></span>
      </div>
      {searching && model.search && <RankedSearch phase={model.search} playAINow={() => model.playAINow?.()} />}
      {!searching && !eligible && model.deckBracket !== undefined && (
        <p className="mwarn" data-id="ranked.ineligible">
          {CommanderBracket.title(model.deckBracket)} is above {RankTier.name(position.tier)}'s limit (Bracket {RankTier.maxDeckBracket(position.tier)}). Choose another deck.
        </p>
      )}
      <div className="mpillrow">
        <Pill id="ranked.hall" onClick={model.rankedHall}>Season</Pill>
        <Pill id="ranked.leaderboard" onClick={model.leaderboard}>Leaderboard</Pill>
      </div>
    </>
  );
}

/** The ranked queue at work (RankedSearchFooter): the time spent and "Play the AI now" with the seconds left, then who was found. */
function RankedSearch({ phase, playAINow }: { phase: RankedPhase; playAINow: () => void }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => { const timer = window.setInterval(() => setNow(Date.now()), 1000); return () => window.clearInterval(timer); }, []);
  if (phase.kind === "matched") {
    return (
      <div className="mrankedsearch" data-id="ranked.search" aria-live="polite">
        <b>Challenger found</b><span className="gold">{phase.ticket.opponent ?? "Another player"}</span><small>Setting the table…</small>
      </div>
    );
  }
  const since = phase.kind === "searching" ? phase.since : now;
  const elapsed = Math.max(0, Math.floor((now - since) / 1000));
  const left = Math.max(0, RankedMatchmaker.searchSeconds - elapsed);
  return (
    <div className="mrankedsearch" data-id="ranked.search" aria-live="polite">
      <b>Searching… <span className="gold">{Math.floor(elapsed / 60)}:{String(elapsed % 60).padStart(2, "0")}</span></b>
      <Pill id="ranked.search.ai" onClick={playAINow}>Play the AI now · {left} s</Pill>
    </div>
  );
}

/** The chosen table's deck as an open box, the way it was played and the deck's bracket. */
function RecentOptions({ model }: { model: PlayModel }) {
  const deck = model.sections.flatMap((s) => s.decks).find((d) => d.id === model.selectedDeckID);
  return (
    <div className="mrecentoptions">
      {deck && <div style={{ paddingTop: boxGeometry(120).rise * 1.5 + 12 }}><DeckBox deck={deck} selected width={120} /></div>}
      {model.recent.length > 0 && <Caps text={model.mode === "ranked" ? "Ranked" : model.mode === "custom" ? "Custom Table" : "Quick Match"} size={10} />}
      {model.deckBracket !== undefined && <small>{CommanderBracket.title(model.deckBracket)}</small>}
    </div>
  );
}

/** A way to play as a cut gem: an ember bolt for Quick, your rank's emblem for Ranked, a table of players for Custom. */
function ModeGem({ mode, tier, lit }: { mode: ArenaPlayMode; tier: RankTier; lit: boolean }) {
  return (
    <span className={`mmodegem ${lit ? "lit" : ""}`}>
      {mode === "quick" && <svg viewBox="0 0 24 24" aria-hidden="true"><defs><linearGradient id="mm-bolt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffe08f" /><stop offset="1" stopColor="#ff804d" /></linearGradient></defs><path d="M13.5 2 5 13.5h5.5L9.5 22 19 9.5h-5.5z" fill="url(#mm-bolt)" /></svg>}
      {mode === "ranked" && <RankEmblem tier={tier} size={32} />}
      {mode === "custom" && <Emblem name="custom" size={18} lit />}
    </span>
  );
}

/** The emblem with its division and pips (RankBadge, without the spin). */
export function RankBadge({ position, size = 96, showsPips = true }: { position: RankPosition; size?: number; showsPips?: boolean }) {
  const mythic = position.tier === "mythic";
  return (
    <span className="mrankbadge" style={{ width: size }}>
      <RankEmblem tier={position.tier} size={size} />
      {showsPips && !mythic && (
        <span className="mrankpips" style={{ ["--pip" as string]: `${Math.max(6, size * 0.11)}px` }} aria-label={`${position.pips} of ${RankPosition.pipsPerDivision} pips`}>
          {Array.from({ length: RankPosition.pipsPerDivision }, (_, i) => <i key={i} className={i < position.pips ? "on" : ""} data-tier={position.tier} />)}
        </span>
      )}
    </span>
  );
}
