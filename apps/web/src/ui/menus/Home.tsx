/**
 * The home page in Arena's layout over the tavern room (iOS Menus/ArenaHomeView.swift): the featured panel (pages turn on
 * their own every 8 s and follow a drag), three tiles beside it, your deck, rank and season as medallions on a gold rail
 * with ticks, friends in the lower left and the orange Play pill in the lower right. Nothing scrolls.
 */
import { type ReactNode, useEffect, useRef, useState } from "react";
import { gameAudio } from "../audio";
import { type DeckBoxModel, DeckArt } from "./DeckBox";
import { Emblem, PlayButton, UnreadPip } from "./kit";
import type { RankTier } from "../../core/rankLadder";
import { RankEmblem } from "./TopBar";

/** Home art shipped with the app: a commander's art crop, `focus` the point the crop keeps in view (ArenaHomeArt). */
export interface HomeArt { asset: string; focus: { x: number; y: number } }
export interface Feature { id: string; kicker: string; title: string; art: HomeArt; action: () => void }
export interface HomeTile { id: string; title: string; subtitle?: string; art: HomeArt; action: () => void }

export interface HomeRank { tier: RankTier; title: string; pips: number; pipsPerDivision: number; mythic: boolean }

export interface HomeContent {
  features: Feature[];
  tiles: HomeTile[];
  deck?: DeckBoxModel;
  rank: HomeRank;
  wins: number;
  losses: number;
  friendsOnline?: number;
  unread?: boolean;
  play: () => void;
  friends?: () => void;
  openDeck: () => void;
  openRank: () => void;
}

/** Shipped art filling its frame, cropped around its focus point rather than its centre (ArenaFocusedArt). */
export function FocusedArt({ art }: { art: HomeArt }) {
  return <div className="mfocusart" style={{ backgroundImage: `url(/menus/${art.asset}.webp)`, backgroundPosition: `${art.focus.x * 100}% ${art.focus.y * 100}%` }} />;
}

export function Home({ content, still }: { content: HomeContent; still: boolean }) {
  return (
    <div className={`mhome ${still ? "still" : ""}`}>
      <div className="mhomeblock">
        <FeaturePanel features={content.features} still={still} />
        <div className="mhometiles">{content.tiles.map((tile) => <Tile key={tile.id} tile={tile} />)}</div>
      </div>
      <div className="mhomefoot">
        <div className="mhomecorner">
          {content.friends && (
            <button type="button" className="mcorner" aria-label="Friends" data-id="menu.social" onClick={() => { gameAudio.play("ui-open"); content.friends?.(); }}>
              <i><Emblem name="friends" size={18} lit={content.unread} />{content.unread && <span className="mcornerpip"><UnreadPip /></span>}</i>
              {(content.friendsOnline ?? 0) > 0 && <b>{content.friendsOnline}</b>}
            </button>
          )}
        </div>
        <ProgressRail content={content} />
        <div className="mhomeplay"><PlayButton id="menu.play" onClick={content.play}>Play</PlayButton></div>
      </div>
    </div>
  );
}

/** The big panel: one feature at a time over its art, arrows and dots, a slow turn on its own, and a drag to turn it. */
function FeaturePanel({ features, still }: { features: Feature[]; still: boolean }) {
  const [index, setIndex] = useState(0);
  const [forward, setForward] = useState(true);
  const [drag, setDrag] = useState(0);
  const start = useRef<number | undefined>(undefined);
  const moved = useRef(false);
  const step = (delta: number) => {
    if (features.length === 0) return;
    setForward(delta > 0);
    setIndex((i) => (i + delta + features.length) % features.length);
  };
  useEffect(() => {
    if (features.length < 2 || still) return;
    const timer = window.setTimeout(() => step(1), 8000);
    return () => window.clearTimeout(timer);
  }, [index, still, features.length]);
  const feature = features[Math.min(index, features.length - 1)];
  if (!feature) return null;
  return (
    <div className="mfeature" onPointerDown={(e) => { start.current = e.clientX; moved.current = false; }}
      onPointerMove={(e) => {
        if (start.current === undefined || !(e.buttons & 1)) return;
        const dx = e.clientX - start.current;
        if (Math.abs(dx) > 12) { moved.current = true; setDrag(dx); }
      }}
      onPointerUp={(e) => {
        if (start.current !== undefined && moved.current) {
          const dx = e.clientX - start.current;
          if (dx < -60) step(1); else if (dx > 60) step(-1);
        }
        start.current = undefined; setDrag(0);
      }}
      onPointerLeave={() => { start.current = undefined; setDrag(0); }}>
      <button key={feature.id} type="button" className={`mfeaturepage ${forward ? "fwd" : "back"}`} style={drag ? { transform: `translateX(${drag}px)`, transition: "none" } : undefined}
        data-id={`home.feature.${feature.id}`} onClick={() => { if (moved.current) return; gameAudio.play("ui-open"); feature.action(); }}>
        <FocusedArt art={feature.art} />
        <i className="mband" />
        <h2>{feature.title}</h2>
      </button>
      {features.length > 1 && <>
        <button type="button" className="marrow left" aria-label="Previous" onClick={() => step(-1)}><svg viewBox="0 0 24 24"><path d="M15 5 8 12l7 7" /></svg></button>
        <button type="button" className="marrow right" aria-label="Next" onClick={() => step(1)}><svg viewBox="0 0 24 24"><path d="M9 5l7 7-7 7" /></svg></button>
        <div className="mdots" aria-hidden="true">{features.map((f, i) => <i key={f.id} className={i === index ? "on" : ""} />)}</div>
      </>}
    </div>
  );
}

/** A tile: crisp art with the title on a dark band at the bottom. */
function Tile({ tile }: { tile: HomeTile }) {
  return (
    <button type="button" className="mtile" data-id={`home.tile.${tile.id}`} onClick={() => { gameAudio.play("ui-open"); tile.action(); }}>
      <FocusedArt art={tile.art} />
      <i className="mband" />
      <span><b>{tile.title}</b>{tile.subtitle && <small>{tile.subtitle}</small>}</span>
    </button>
  );
}

/** Your deck, rank and season as medallions on a gold rail with tick marks (ArenaProgressRail). */
function ProgressRail({ content }: { content: HomeContent }) {
  const { rank, wins, losses, deck } = content;
  const pips = rank.mythic ? rank.pipsPerDivision : Math.min(rank.pipsPerDivision, rank.pips);
  const played = wins + losses;
  return (
    <div className="mrail">
      <svg className="mrailline" preserveAspectRatio="none" viewBox="0 0 800 10" aria-hidden="true">
        <path d={`M0 5H800${Array.from({ length: 9 }, (_, i) => `M${i * 100} 2V8`).join("")}`} />
      </svg>
      {deck && (
        <Medallion progress={1} title={deck.name} id="home.deck" action={content.openDeck}>
          <span className="mmedart"><DeckArt name={deck.commander} colors={deck.colors} /></span>
        </Medallion>
      )}
      <Medallion progress={pips / rank.pipsPerDivision} title={rank.title} subtitle={rank.mythic ? "Mythic" : `${pips} of ${rank.pipsPerDivision} pips`}
        id="home.rank" action={content.openRank}>
        <RankEmblem tier={rank.tier} size={32} />
      </Medallion>
      <Medallion progress={played === 0 ? 0 : wins / played} title={`Season ${wins}–${losses}`}
        subtitle={played === 0 ? "No games yet" : `${Math.round((wins / played) * 100)}% won`} id="home.season" action={content.openRank}>
        <Emblem name="laurel" size={18} lit />
      </Medallion>
    </div>
  );
}

function Medallion({ progress, title, subtitle, id, action, children }: {
  progress: number; title: string; subtitle?: string; id: string; action: () => void; children: ReactNode;
}) {
  const circumference = 2 * Math.PI * 19.5;
  return (
    <button type="button" className="mmedal" data-id={id} onClick={() => { gameAudio.play("ui-open"); action(); }}>
      <span className="mmedring">
        <svg viewBox="0 0 44 44" aria-hidden="true">
          <circle cx="22" cy="22" r="22" fill="#141210" />
          <circle cx="22" cy="22" r="19.5" fill="none" stroke="rgba(255,255,255,.12)" strokeWidth="3" />
          <circle cx="22" cy="22" r="19.5" fill="none" stroke="url(#mm-ring)" strokeWidth="3" strokeLinecap="round"
            strokeDasharray={`${Math.max(0.001, progress) * circumference} ${circumference}`} transform="rotate(-90 22 22)" />
          <defs><linearGradient id="mm-ring" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffb861" /><stop offset="1" stopColor="#ff804d" /></linearGradient></defs>
        </svg>
        <span className="mmedface">{children}</span>
      </span>
      <span className="mmedtext"><b>{title}</b>{subtitle && <small>{subtitle}</small>}</span>
    </button>
  );
}
