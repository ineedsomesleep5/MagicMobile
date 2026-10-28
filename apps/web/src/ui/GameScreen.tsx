/**
 * The game on the horizontal Arena board (docs/ARENA_STYLE.md; the Duel Board Prototype's landscape table, artifact
 * T5NcAkjCThiA5hfd9Twwwu): the Walnut Tavern plate scaled to the window, every card a table object, the decision in
 * the corner plaques or on the table, and anything else in a full-table glass browser. Solo games and relay tables
 * share it; both answer through the same GuestSession.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { type BoardFXLevel, resolvedLevel } from "../core/boardEvents";
import { EngineDisplayText } from "../core/displayText";
import {
  type GameCommand, type GameSnapshot, isCompleted, isOut, type LegalAction, type PlayerGameState, startingPlayerHeading, thinkingPlayerID,
  type XmagePromptAbility, type ZoneCard,
} from "../core/models";
import type { RankChange } from "../core/rankLadder";
import { rollPlates } from "../core/startingRoll";
import { appConfig } from "../core/appConfig";
import { TableLeaveRules } from "../core/tableLeave";
import { DEFAULT_PUSH_TO_TALK_BIND, PUSH_TO_TALK_BIND_KEY, PUSH_TO_TALK_KEY, VOICE_SWITCH, VoiceChat } from "../core/voiceChat";
import { VoiceRoom, type VoiceTokenSource } from "../table/voiceRoom";
import { loadSmartPass, saveSmartPass, type SmartPassSettings } from "../core/smartPass";
import { GameEmotes, TableChatFilter } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { useTable } from "./App";
import { ArenaCard, type ArenaCardProps } from "./arena/ArenaCard";
import { AmountPill, Browser, browserKind, cardNamed, CommanderBrowser, type Send, StackBrowser, ZoneBrowser } from "./arena/Browsers";
import {
  ARENA, BASE_GEOMETRY, battlefieldPlaces, drops, geometry, type Geometry, handPlaces, mulliganPlaces, opponentHandPlaces, phaseStrip, type Place, scrubHand, stackPlace,
  STAGE,
} from "./arena/layout";
import { isStackAbility } from "./arena/AbilityCard";
import { AutoPayRun, autoPayReady, manaUndoActions, paymentPrompt } from "./arena/autoPayRun";
import { Check, type MenuItem, MenuCard, Panel, PhaseStops } from "./arena/Menus";
import { TalkKeyButton } from "./menus/kit";
import { Inspector } from "./arena/Inspector";
import { StatusBadge } from "./arena/StatusBadge";
import { GameResult } from "./arena/GameResult";
import { ComboLoopOverlay } from "./arena/ComboLoop";
import { ORBIT, orbitOffsets, orbitOrder, orbitShown, statusBadges } from "../core/playerStatus";
import { GameLog } from "./arena/GameLog";
import { CombatLogReasons } from "../core/gameLog";
import { TriggerPlan, type TriggerPick } from "./arena/triggerPlan";
import type { CardChoicePlan } from "../core/cardChoicePlan";
import { allAttackTargets, AttackQueue, boardTargetableIds, combatArrows, declaredCount, finishTitle } from "./arena/combat";
import { arenaStackTucked, combatPhase, commandersTaken, commanderTakenNotice, extraHandCards } from "../core/arenaBoard";
import { GameStats } from "../core/gameStats";
import { BoardFXOverlay, FXBoundary, type FXAnchors } from "./arena/BoardFX";
import { fxNow, useBoardFX } from "./arena/useBoardFX";
import { usePacedSnapshot } from "./arena/usePacedSnapshot";
import { castableZones, glowClasses } from "./arena/glow";
import { type CardReader, readProps } from "./arena/inspectGesture";
import { GAME_SPEED_KEY, GAME_SPEED_TITLES, GAME_SPEEDS, type GameSpeed, loadGameSpeed, MAX_PACE_LAG, TABLE_PACE_LAG } from "../core/gameSpeed";
import { ArenaPile } from "./arena/ArenaPile";
import { commanderName, Portrait } from "./arena/avatars";
import { VersusIntro, type VersusSeat } from "./arena/Versus";
import { ManaSymbol, RulesText } from "./arena/Symbols";
import "./arena/arena.css";
import { CardArt, cardImageURL } from "./cardArt";
import { storage } from "./storage";
import { LessonCoachCard } from "./arena/LessonViews";
import { isLessonNudge } from "../core/lessons";
import { LessonTable } from "../table/lessonTable";
import { gameAudio, SOUND_KEYS } from "./audio";

const PHASE_TITLES = ["Beginning", "Main phase 1", "Declare attackers", "Declare blockers", "Combat damage", "End of combat", "Main phase 2", "End step"];

/**
 * The phase strip (ArenaPhaseStrip): eight icons on a brass track, the part of the turn already played lit in the turn's
 * colour, the current step lit; moving on sends a spark along the track, then the icon ignites. A click opens Phase Stops.
 */
/** Voice chat's mic, on and off (the mic button and the small badge on an opponent in voice). */
const MIC = <svg viewBox="0 0 20 20"><rect x="7" y="2" width="6" height="10" rx="3" /><path d="M4.5 9a5.5 5.5 0 0 0 11 0" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M9.2 14.4h1.6V18H9.2z" /></svg>;
const MIC_OFF = <svg viewBox="0 0 20 20"><rect x="7" y="2" width="6" height="10" rx="3" /><path d="M4.5 9a5.5 5.5 0 0 0 11 0" fill="none" stroke="currentColor" strokeWidth="1.6" /><path d="M9.2 14.4h1.6V18H9.2z" /><path d="M3 2.5l14 15" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>;

/** The player card's zone icons (ArenaPlayerCard.zones). */
const ZONE_GLYPHS = {
  command: <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M2 15h16l1-9-5 4-4-6-4 6-5-4zM2 16.5h16V18H2z" /></svg>,
  graveyard: <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M17 2C8 2 3 6.5 3 12.5c0 1.6.4 3 1 4.3L2.5 18.4l1.1 1.1 1.6-1.6c1.3.8 2.8 1.2 4.3 1.2C15 19.1 18 13 17 2zM6 15.5c2.5-3.4 5.4-6 9-8-3 2.6-5.6 5.3-7.8 9.2z" /></svg>,
  exile: <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M8 1l1.6 4.6L14 7.2 9.6 8.8 8 13.4 6.4 8.8 2 7.2l4.4-1.6zM15 10l.9 2.4 2.4.9-2.4.9L15 16.6l-.9-2.4-2.4-.9 2.4-.9z" /></svg>,
  library: <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M2.5 3h3.5v14H2.5zM7 3h3.5v14H7zM11.6 4.2l3.3-1 3.6 13.3-3.3 1z" /></svg>,
  hand: <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M7 18c-2.2 0-3.6-1.4-4.4-3.4L1.4 11c-.3-.8.6-1.4 1.2-.8L4.5 12V4.2a1 1 0 0 1 2 0V9h.6V2.8a1 1 0 0 1 2 0V9h.6V3.4a1 1 0 0 1 2 0V9h.6V5a1 1 0 0 1 2 0v7c0 3.4-2.2 6-5.2 6z" /></svg>,
};

const EYE = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 4C5.5 4 2.2 7 1 10c1.2 3 4.5 6 9 6s7.8-3 9-6c-1.2-3-4.5-6-9-6zm0 9.5a3.5 3.5 0 1 1 0-7 3.5 3.5 0 0 1 0 7zm0-5.3a1.8 1.8 0 1 0 0 3.6 1.8 1.8 0 0 0 0-3.6z" /></svg>;
const EYE_OPEN = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 4C5.5 4 2.2 7 1 10c1.2 3 4.5 6 9 6s7.8-3 9-6c-1.2-3-4.5-6-9-6z" fill="none" stroke="currentColor" strokeWidth="1.6" /><circle cx="10" cy="10" r="2.6" /></svg>;
const SUN = <svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="4.2" /><path d="M10 1v3M10 16v3M1 10h3M16 10h3M3.6 3.6l2.1 2.1M14.3 14.3l2.1 2.1M3.6 16.4l2.1-2.1M14.3 5.7l2.1-2.1" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" /></svg>;
const MOON = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M13.5 2.2A8 8 0 1 0 17.8 13 6.4 6.4 0 0 1 13.5 2.2z" /></svg>;
const EYE_OFF = <svg viewBox="0 0 20 20" aria-hidden="true"><path d="M1.5 10S4.8 4 10 4s8.5 6 8.5 6-3.3 6-8.5 6S1.5 10 1.5 10z" fill="none" stroke="currentColor" strokeWidth="1.8" /><circle cx="10" cy="10" r="2.6" /><path d="M3 17L17 3" stroke="currentColor" strokeWidth="2" strokeLinecap="round" /></svg>;

function PhaseStrip({ step, side, top, onOpen }: { step?: string; side: "me" | "opp"; top: number; onOpen: () => void }) {
  const { items, current } = phaseStrip(step);
  const width = ARENA.phaseStrip.w;
  const spacing = (width - 12) / items.length;
  const x = (i: number) => 6 + spacing * (i + 0.5);
  const [spark, setSpark] = useState<{ from: number; to: number; key: number; duration: number }>();
  const [ignite, setIgnite] = useState(0);
  const previous = useRef(current);
  useEffect(() => {
    const old = previous.current;
    previous.current = current;
    if (old === undefined || current === undefined || old === current || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) { setSpark(undefined); return; }
    const duration = 0.22 + Math.min(0.26, Math.abs(x(current) - x(old)) * 0.0022);
    const key = Date.now();
    setSpark({ from: old, to: current, key, duration });
    const timer = window.setTimeout(() => { setSpark((s) => (s?.key === key ? undefined : s)); setIgnite(key); }, duration * 1000);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [current]);
  return (
    <button type="button" className="aphases" data-side={side} style={{ top }} onClick={onOpen}
      aria-label={current !== undefined ? `${PHASE_TITLES[current]}, phase stops` : "Phase stops"}>
      <i className="track" />
      {current !== undefined && current > 0 && <i className="lit" style={{ left: x(0), width: x(current) - x(0) }} />}
      {items.map(([key, icon], i) => {
        const on = i === current && spark === undefined;
        return (
          <span key={key} className={`aph ${icon === "dia" ? "small" : ""} ${on ? "on" : ""} ${on && ignite ? "ignite" : ""}`} data-ignite={on ? ignite : undefined}
            style={{ left: x(i) }}>{PHASE_ICONS[icon]}</span>
        );
      })}
      {spark && <i key={spark.key} className="spark" style={{ left: x(spark.from), ["--to" as string]: `${x(spark.to) - x(spark.from)}px`, animationDuration: `${spark.duration}s` }} />}
    </button>
  );
}

const PHASE_ICONS: Record<string, React.ReactNode> = {
  dia: <svg viewBox="0 0 20 20"><path d="M10 3.5l6.5 6.5-6.5 6.5-6.5-6.5z" /></svg>,
  card: <svg viewBox="0 0 20 20"><rect x="5" y="2.5" width="10" height="15" rx="2" /></svg>,
  sword: <svg viewBox="0 0 20 20"><path d="M17.6 2.4l-.5 3L8.6 13.9 6.1 11.4 14.6 2.9z" /><path d="M3.9 10.6l5.5 5.5-1.2 1.2-5.5-5.5z" /><path d="M5.6 15.2l-2.3 2.3-.8-.8 2.3-2.3z" /></svg>,
  swords: <svg viewBox="0 0 20 20"><path d="M17.6 2.4l-.5 3L8.6 13.9 6.1 11.4 14.6 2.9z" /><path d="M3.9 10.6l5.5 5.5-1.2 1.2-5.5-5.5z" /><path d="M2.4 2.4l3 .5 8.5 8.5-2.5 2.5L2.9 5.4z" /><path d="M16.1 10.6l-5.5 5.5 1.2 1.2 5.5-5.5z" /></svg>,
  shield: <svg viewBox="0 0 20 20"><path d="M10 2.2l6.4 2.2v5c0 4.2-2.9 6.9-6.4 8.4-3.5-1.5-6.4-4.2-6.4-8.4v-5z" /></svg>,
  burst: <svg viewBox="0 0 20 20"><path d="M10 1.6l1.9 4.8 4.9-1.9-2.2 4.7 4.3 2.7-5 .8.2 5.1-4.1-3.1-4.1 3.1.2-5.1-5-.8 4.3-2.7-2.2-4.7 4.9 1.9z" /></svg>,
};
const GEAR = <svg viewBox="0 0 24 24"><path d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zm8.6 5.1-1.9-.3a7 7 0 0 1-.6 1.5l1.1 1.6-1.9 1.9-1.6-1.1c-.5.3-1 .5-1.5.6l-.3 1.9h-2.7l-.3-1.9a7 7 0 0 1-1.5-.6l-1.6 1.1-1.9-1.9 1.1-1.6c-.3-.5-.5-1-.6-1.5l-1.9-.3v-2.7l1.9-.3c.1-.5.3-1 .6-1.5L4.1 6.9 6 5l1.6 1.1c.5-.3 1-.5 1.5-.6l.3-1.9h2.7l.3 1.9c.5.1 1 .3 1.5.6L15.5 5l1.9 1.9-1.1 1.6c.3.5.5 1 .6 1.5l1.9.3z" /></svg>;
const SCROLL = <svg viewBox="0 0 16 16"><path d="M4 2h8.5a1.5 1.5 0 0 1 0 3H12v8.5A1.5 1.5 0 0 1 10.5 15H3.5a1.5 1.5 0 0 1 0-3H4z" /></svg>;
const HOURGLASS = <svg viewBox="0 0 24 24"><path d="M6 2h12v2c0 3-2.2 5.2-4.3 8 2.1 2.8 4.3 5 4.3 8v2H6v-2c0-3 2.2-5.2 4.3-8C8.2 9.2 6 7 6 4zm2 2c0 2 1.6 3.8 4 6.6C14.4 7.8 16 6 16 4z" /></svg>;

/** Legal actions for one card, grouped by what a click on it would do. */
const actionsFor = (snapshot: GameSnapshot, id: string) =>
  (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === id || a.sourceInstanceId === id);

/** XMage's message without markup, ids or counters: one line for the middle of the table. */
const cleanMessage = (message: string | undefined) =>
  EngineDisplayText.text(message ?? "").replace(/\s*\[[0-9a-f]{3,}\]/gi, "").split("\n").map((s) => s.trim()).filter(Boolean).join(" · ");

/** The board for the window it's in, measured again whenever the window or its pane is resized. */
function useGeometry(ref: React.RefObject<HTMLDivElement | null>) {
  const [geo, setGeo] = useState<Geometry>(BASE_GEOMETRY);
  useLayoutEffect(() => {
    const element = ref.current;
    if (!element) return;
    const measure = () => {
      const w = element.clientWidth; const h = element.clientHeight;
      if (w > 0 && h > 0) setGeo(geometry(w, h));
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(element);
    return () => observer.disconnect();
  }, [ref]);
  return geo;
}

interface Plaque { label: string; subtitle?: string; style: "primary" | "secondary" | "quiet" | "danger"; want?: boolean; disabled?: boolean; onClick?: () => void }

/** The phase of a step, as the tavern's phase track counts them (TavernPhaseTrack.describe): 0 beginning … 4 end. */
function phaseIndex(step: string | undefined): number | undefined {
  switch ((step ?? "").toLowerCase().replaceAll("_", "-")) {
    case "beginning": case "untap": case "upkeep": case "draw": return 0;
    case "precombat-main": case "main1": return 1;
    case "combat": case "begin-combat": case "declare-attackers": case "declare-blockers": case "first-combat-damage": case "first-strike-damage":
    case "combat-damage": case "end-combat": return 2;
    case "postcombat-main": case "main2": return 3;
    case "ending": case "end": case "end-turn": case "cleanup": return 4;
    default: return undefined;
  }
}

/**
 * `rankChange`: how a ranked game moved you, shown on the result once the menu shell has recorded the game, and `rankNote`
 * why the server left a win off the ladder. `versus`: the
 * chosen decks for the versus intro, when the table itself doesn't know its seats' commanders (a solo game); its
 * `you.tier` frames your seat in every intro, a table's own seats included.
 */
export function GameScreen({ table, rankChange, rankNote, versus, voiceToken }: {
  table: GameTable; rankChange?: RankChange; rankNote?: string; versus?: { you: VersusSeat; opponents: VersusSeat[] };
  /** Voice chat tokens (PlayerAccount.voiceToken); without it the board has no mic. */
  voiceToken?: VoiceTokenSource;
}) {
  useTable(table);
  const session = table.session;
  /** A lesson (lessons.ts): Maren's card and her rings over the board. */
  const lesson = table instanceof LessonTable ? table : undefined;
  // While a combo loop repeats, the board shows its quiet copy without the prompts the repeats answer.
  const live = session?.state.comboRun ? session.presentedSnapshot : session?.state.snapshot;
  // Game speed (Options → Gameplay): the board shows each opponent action for its time before the next one; the live game
  // runs on. A combo loop's repeats keep their own pace.
  const [speed, setSpeed] = useState<GameSpeed>(() => loadGameSpeed(storage.get));
  // At a table with people the turn clock runs, so the board may lag less behind the game there.
  const paced = usePacedSnapshot(live, session?.state.comboRun ? "fast" : speed, table.solo ? MAX_PACE_LAG : TABLE_PACE_LAG);
  const snapshot = paced.snapshot;
  const wrapRef = useRef<HTMLDivElement>(null);
  const geo = useGeometry(wrapRef);
  /** Plate points to board points: in proportion (the middle), from the top edge (theirs), from the bottom edge (yours). */
  const Y = (y: number) => y * geo.ky;
  const T = (y: number) => y * geo.grow;
  const B = (y: number) => geo.height - (STAGE.height - y) * geo.grow;
  /** The hand card popped up whole, the one under the pointer (ArenaHandFan's liftedCardID). */
  const [popped, setPopped] = useState<string>();
  const [menu, setMenu] = useState<{ id: string; at: Place; actions: LegalAction[] }>();
  /** A failed answer or session error, up for 8 s (OnDeviceRootView.bannerError); a session error stays until dismissed. */
  const [bannerError, setBannerError] = useState<string>();
  const [dismissedError, setDismissedError] = useState<string>();
  const [panel, setPanel] = useState<"log" | "chat">();
  /** The gear's menu or the pass-ahead pill's skip choices, as a menu card on the table. */
  const [cornerMenu, setCornerMenu] = useState<"game" | "pass">();
  /** Phase Stops or Game Settings, in glass on the table. */
  const [sheet, setSheet] = useState<"stops" | "settings" | "actions">();
  /** The prompt whose player choice was opened from a medallion as a panel (several picks). */
  const [playerPanel, setPlayerPanel] = useState<string>();
  const [zone, setZone] = useState<{ title: string; cards: ZoneCard[] }>();
  /** The player whose commanders are open in the commander browser. */
  const [commanderView, setCommanderView] = useState<string>();
  const [playerCard, setPlayerCard] = useState<string>();
  const [confirmConcede, setConfirmConcede] = useState(false);
  const [rollDismissed, setRollDismissed] = useState(false);
  const [smartSettings, setSmartSettings] = useState<SmartPassSettings>(() => session?.smartPass ?? loadSmartPass(storage.get));
  const [passAfterCast, setPassAfterCast] = useState(() => storage.get("mm.web.autoPassAfterCast") !== "off");
  const [soundsOn, setSoundsOn] = useState(() => storage.get(SOUND_KEYS.effects) !== "off");
  const updateSmartPass = (next: SmartPassSettings) => {
    setSmartSettings(next);
    saveSmartPass(next, storage.set);
    session?.setSmartPass(next);
  };
  const [stackOpen, setStackOpen] = useState(false);
  /** When each stack object first showed, so its landing plays once. */
  const stackSeen = useRef(new Map<string, number>());
  // Card Frames (iOS Settings, per board mode): off by default on the Arena board, the reference game's cards.
  const [frames, setFrames] = useState(() => storage.get("mm.web.cardFrames") === "on");
  // Board effects (iOS magicmobile.boardEffectsLevel): Full by default; the system's Reduce Motion caps it at Reduced.
  const [fxSetting, setFxSetting] = useState(() => storage.get("mm.web.boardEffects") ?? "full");
  const reduceMotion = typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;
  // A long loop runs without the board's effects (BoardFXLevel.suppressedForLoop).
  const fxLevel: BoardFXLevel = session?.state.comboFast ? "off" : resolvedLevel(fxSetting, reduceMotion);
  const fx = useBoardFX(snapshot, session, fxLevel);
  // Smart pass waits for the board to catch up with the game at this speed.
  useLayoutEffect(() => { fx.hold.paceUntil = paced.paceUntil; });
  useEffect(() => () => { fx.hold.paceUntil = undefined; }, [fx.hold]);
  const combatReasons = useRef(new CombatLogReasons());
  const stageRef = useRef<HTMLDivElement>(null);
  const vignetteRef = useRef<HTMLDivElement>(null);
  // BoardImpactShake: sideways travel decaying over the hit (big hits also jolt down), and BoardHitVignette's red edge.
  useEffect(() => {
    const impact = fx.impact;
    if (!impact) return;
    const amplitude = impact.amplitude;
    const frames = Array.from({ length: 25 }, (_, i) => {
      const t = i / 24, decay = 1 - t;
      const x = Math.sin(t * Math.PI * 6) * amplitude * decay;
      const y = amplitude > 8 ? Math.abs(Math.sin(t * Math.PI * 4)) * amplitude * 0.35 * decay : 0;
      return { translate: `${x.toFixed(2)}px ${y.toFixed(2)}px` };
    });
    stageRef.current?.animate?.(frames, { duration: amplitude > 8 ? 500 : 360, easing: "linear" });
    if (impact.flare) {
      vignetteRef.current?.animate?.([{ opacity: 0 }, { opacity: 1, offset: 0.12 / 0.97, easing: "ease-in" }, { opacity: 1, offset: 0.27 / 0.97, easing: "ease-in" }, { opacity: 0 }],
        { duration: 970 });
    }
  }, [fx.impact]);
  const fxRef = useRef(fx);
  fxRef.current = fx;
  /** Where each card lies, kept after it leaves so its departure starts there; and where a card was before its last move. */
  const places = useRef(new Map<string, Place>());
  const movedFrom = useRef(new Map<string, { place: Place; at: number }>());
  /** The card being read in the inspector (a right-click, or a held press while it lasts), which holds smart pass while open. */
  const [reading, setReading] = useState<{ name: string; card?: ZoneCard; held?: boolean }>();
  /** A hand card being carried to the table: where it started and where the pointer is, in board points. */
  const [carry, setCarry] = useState<{ id: string; start: { x: number; y: number }; point: { x: number; y: number }; moved: boolean }>();
  const suppressClick = useRef(false);
  /** An opponent's spell is revealed larger toward the middle for its first 1.3 s, then settles onto the stack card. */
  const [revealID, setRevealID] = useState<string>();
  /** The stack card stepped aside for this top object (ArenaStackTuck), or was brought back while picking. */
  const [stackTuckedTop, setStackTuckedTop] = useState<string>();
  const [stackPeekTop, setStackPeekTop] = useState<string>();
  const [, setClockTick] = useState(0);
  useEffect(() => { if (session?.smartPass) setSmartSettings(session.smartPass); }, [session]);
  // Development only: the table, for checking a game from the console.
  // Development, or `?debug` on any build: the table and the board's effects, for checking a game from the console or a
  // headless driver (scripts/play.mjs).
  // `board` is the snapshot the board shows at the game speed (the session's is the live game).
  const boardRef = useRef(snapshot);
  boardRef.current = snapshot;
  useEffect(() => {
    if (import.meta.env.DEV || new URLSearchParams(window.location.search).has("debug")) Object.assign(window, { __mm: { table, fx: fxRef, board: boardRef } });
  }, [table]);

  const viewer = snapshot?.viewerPlayerId;
  const me = snapshot?.players.find((p) => p.playerId === viewer);
  const opponents = useMemo(() => snapshot?.players.filter((p) => p.playerId !== viewer) ?? [], [snapshot, viewer]);

  // The versus intro as a game opens (OnDeviceRootView.makeVersusIntro): a table's own seats when it knows them, else the
  // chosen decks, else the players the first snapshot shows. With Reduce Motion only its sound plays.
  const [versusShown, setVersusShown] = useState(!reduceMotion);
  useEffect(() => { gameAudio.play("versus"); }, []);
  const versusSeats = (() => {
    if (!versusShown) return undefined;
    const seats = table.state.tableSeats;
    const local = seats.find((seat) => seat.isLocal);
    const tier = versus?.you.tier;
    if (local && seats.length > 1) {
      return { you: { id: local.id, name: local.name, commander: local.commanders[0] ?? versus?.you.commander, tier },
        opponents: seats.filter((seat) => !seat.isLocal).slice(0, 3).map((seat) => ({ id: seat.id, name: seat.name, commander: seat.commanders[0] })) };
    }
    if (versus && versus.opponents.length > 0) return { you: versus.you, opponents: versus.opponents.slice(0, 3) };
    if (snapshot && me && opponents.length > 0) {
      return { you: { id: me.playerId, name: me.displayName ?? "You", commander: commanderName(me), tier },
        opponents: opponents.slice(0, 3).map((p) => ({ id: p.playerId, name: p.displayName ?? "Opponent", commander: commanderName(p) })) };
    }
    return undefined;
  })();
  const pending = session?.state.pendingActionID !== undefined || session?.state.working === true;
  const envelope = snapshot?.promptEnvelopeV2;
  const finished = snapshot !== undefined && isCompleted(snapshot);
  const targetIDs = new Set([...(envelope?.targetIds ?? []), ...(envelope?.targets ?? []).map((t) => t.id)]);
  // Which combat declaration the table asks for (ArenaCombatPhase): XMage's target prompt in the declare steps.
  const combat = snapshot ? combatPhase(snapshot) : undefined;
  const combatSelect = combat !== undefined;
  const paying = snapshot !== undefined && (snapshot.manaPayment?.active === true || paymentPrompt(snapshot) !== undefined);
  /** Auto Pay running: one tap per settled snapshot (ArenaAutoPayRun). */
  const autoPay = useRef<AutoPayRun | undefined>(undefined);
  const [autoPaying, setAutoPaying] = useState(false);
  /** All Attack sending one creature per answer (ArenaAttackQueue). */
  const attackQueue = useRef<AttackQueue | undefined>(undefined);
  const [attacking, setAttacking] = useState(false);
  /** Creatures you declared, in order: Take Back undoes the latest. */
  const declarationOrder = useRef<string[]>([]);
  /** A chosen trigger order answering XMage's one-at-a-time ordering prompts (arenaTriggerPlan). */
  const triggerPlan = useRef(new TriggerPlan()).current;
  const [planning, setPlanning] = useState(false);
  /** A short line that replaces the caption for a moment (arenaShowNotice: 2.4 s unless said otherwise). */
  const [notice, setNotice] = useState<{ text: string; until: number }>();
  const showNotice = useCallback((text: string, seconds = 2.4) => {
    setNotice({ text, until: fxNow() + seconds });
    window.setTimeout(() => setNotice((n) => (n && n.until <= fxNow() + 0.05 ? undefined : n)), seconds * 1000 + 50);
  }, []);
  // A player left the table and the others play on (TableLeaveRules).
  const tableNotice = table.state.tableNotice;
  useEffect(() => {
    if (!tableNotice) return;
    showNotice(tableNotice, 5);
    table.clearTableNotice?.();
  }, [tableNotice, table, showNotice]);
  const activeIsMe = snapshot?.activePlayerId !== undefined && snapshot.activePlayerId === viewer;
  const stack = snapshot?.xmage?.stack ?? [];
  // Voice chat (VoiceRoom; docs/VOICE_CHAT.md): a table with people gets a mic by your medallion once the game has its
  // channel and the server's voiceChat switch is on. Nobody is in voice until they tap it.
  const voiceOn = useSyncExternalStore(appConfig.subscribe, () => appConfig.isOn(VOICE_SWITCH, false));
  const voiceChannel = table.voiceChannel;
  const voiceAccount = VoiceChat.account(table.state.localSeatID);
  const [voice, setVoice] = useState<VoiceRoom>();
  useEffect(() => {
    if (table.solo || !voiceOn || !voiceToken || !voiceChannel || !voiceAccount) return undefined;
    const room = new VoiceRoom(voiceChannel, voiceAccount, voiceToken);
    setVoice(room);
    return () => { room.close(); setVoice(undefined); };
  }, [table.solo, voiceOn, voiceToken, voiceChannel, voiceAccount]);
  const subscribeVoice = useCallback((listener: () => void) => voice?.subscribe(listener) ?? (() => undefined), [voice]);
  const voiceState = useSyncExternalStore(subscribeVoice, () => voice?.state);
  const showMic = voiceState !== undefined && VoiceChat.shown({ switchOn: voiceOn, solo: table.solo, channel: voiceChannel !== undefined,
    account: voiceAccount !== undefined, unavailable: voiceState.stage === "unavailable" });
  // Push to talk (Options → Audio, Game Settings): the mic stays off except while the mic or the talk key is held.
  const [pushToTalk, setPushToTalk] = useState(() => storage.get(PUSH_TO_TALK_KEY) === "on");
  const [talkKey, setTalkKey] = useState(() => storage.get(PUSH_TO_TALK_BIND_KEY) ?? DEFAULT_PUSH_TO_TALK_BIND);
  useEffect(() => { void voice?.setPushToTalk(pushToTalk); }, [voice, pushToTalk]);
  useEffect(() => {
    if (!voice || !pushToTalk) return undefined;
    const typing = (target: EventTarget | null) => target instanceof HTMLElement && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));
    const down = (event: KeyboardEvent) => {
      if (event.code !== talkKey || typing(event.target) || event.metaKey || event.ctrlKey || event.altKey) return;
      event.preventDefault();
      if (!event.repeat) void voice.talk(true);
    };
    const up = (event: KeyboardEvent) => { if (event.code === talkKey) void voice.talk(false); };
    const release = () => { void voice.talk(false); };
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    window.addEventListener("blur", release);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); window.removeEventListener("blur", release); release(); };
  }, [voice, pushToTalk, talkKey]);
  const pickingOnTable = appConfig.isOn("stackAutoTuck") && snapshot !== undefined && boardTargetableIds(snapshot).size > 0;
  const stackTucked = (id: string) => revealID !== id && arenaStackTucked(id, stackTuckedTop, stackPeekTop, pickingOnTable);
  const promptActions = (snapshot?.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined);

  const fail = useCallback((error: unknown) => {
    // A lesson's turned-down move: Maren's card says so.
    if (isLessonNudge(error)) return;
    gameAudio.play("ui-error");
    const message = error instanceof Error ? error.message : String(error);
    setBannerError(message);
    window.setTimeout(() => setBannerError((current) => (current === message ? undefined : current)), 8000);
  }, []);
  const send: Send = useCallback((partial, label) => {
    if (!session || !snapshot || !envelope) return;
    session.submit({
      ...partial, gameId: snapshot.id, playerId: snapshot.viewerPlayerId!, promptId: envelope.id, messageId: envelope.messageId,
    } as never, label, `${envelope.id}:${partial.type}:${label}`).catch(fail);
  }, [session, snapshot, envelope, fail]);
  const sendAction = useCallback((action: LegalAction) => { setMenu(undefined); session?.send(action).catch(fail); }, [session, fail]);

  // Every answer from XMage steps Auto Pay once it has landed: a new revision, a new prompt, or the pending answer
  // clearing (ArenaAutoPayDriver).
  // The live game's, not the paced board's: these helpers answer the game, and the board only ever lags an opponent's action.
  const helperKey = `${live?.bridgeRevision ?? -1}|${live?.promptEnvelopeV2?.id ?? ""}|${live?.promptEnvelopeV2?.messageId ?? -1}|${session?.state.pendingActionID ?? ""}|${session?.state.working}`;
  const sendTriggerPick = useCallback((pick: TriggerPick) => {
    const current = session?.state.snapshot;
    if (!session || !current?.viewerPlayerId) return;
    session.submit({
      type: "choose_ability", gameId: current.id, playerId: current.viewerPlayerId, promptId: pick.responsePromptId, messageId: pick.messageId,
      abilityId: pick.abilityId, answerActions: pick.remember ? ["rememberTriggerFirst"] : undefined, expectedBridgeRevision: current.bridgeRevision,
    }, "Put a trigger on the stack", `${pick.promptId}-${pick.abilityId}`).catch(fail);
  }, [session, fail]);
  useEffect(() => {
    if (!planning || !session) return;
    const timer = window.setTimeout(() => {
      const current = session.state.snapshot;
      if (!current) return;
      const pick = triggerPlan.step(current, session.state.working || session.state.pendingActionID !== undefined);
      if (pick) sendTriggerPick(pick);
      if (!triggerPlan.active) setPlanning(false);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [helperKey, planning, session, triggerPlan, sendTriggerPick]);
  useEffect(() => {
    if (!attacking || !session) return;
    const timer = window.setTimeout(() => {
      const queue = attackQueue.current;
      const current = session.state.snapshot;
      if (!queue || !current?.viewerPlayerId) return;
      const move = queue.step(current, session.state.working || session.state.pendingActionID !== undefined);
      if (move.kind === "send") {
        const prompt = current.promptEnvelopeV2!;
        if (queue.done) { attackQueue.current = undefined; setAttacking(false); }
        session.submit({ type: "choose_target", gameId: current.id, playerId: current.viewerPlayerId, promptId: prompt.responseCommand?.promptId ?? prompt.id,
          messageId: prompt.messageId, targetIds: [move.id], expectedBridgeRevision: current.bridgeRevision }, "Attack", `${prompt.id}:attack:${move.id}`)
          .catch((error) => { attackQueue.current = undefined; setAttacking(false); fail(error); });
      } else if (move.kind === "end") { attackQueue.current = undefined; setAttacking(false); }
    }, 0);
    return () => window.clearTimeout(timer);
  }, [helperKey, attacking, session, fail]);
  // A drafted card choice delivered one answer per settled snapshot (iOS advanceCommittedCardChoice); the browser stays
  // closed while it runs, and an unexpected prompt hands the choice back.
  const cardPlan = useRef<CardChoicePlan | undefined>(undefined);
  const [choosing, setChoosing] = useState(false);
  const commitPlan = useCallback((plan: CardChoicePlan) => { cardPlan.current = plan; setChoosing(true); }, []);
  useEffect(() => {
    if (!choosing || !session) return;
    let done: number | undefined;
    const timer = window.setTimeout(() => {
      const plan = cardPlan.current;
      const current = session.state.snapshot;
      if (!plan || !current) return;
      const busy = session.state.working || session.state.pendingActionID !== undefined;
      // No prompt after its last answer: the choice is over once that holds for 5 s, or 30 s while a selection still owes
      // answers (a slow engine between prompts is not the end of the choice).
      if (!current.promptEnvelopeV2 && !busy && plan.lastPrompt !== undefined) {
        const last = plan.lastPrompt;
        done = window.setTimeout(() => { if (cardPlan.current?.lastPrompt === last && !session.state.snapshot?.promptEnvelopeV2) { cardPlan.current = undefined; setChoosing(false); } },
          plan.expectsMorePrompts ? 30000 : 5000);
        return;
      }
      const command = plan.next(current, busy);
      if (plan.stopped) { cardPlan.current = undefined; setChoosing(false); }
      if (command) {
        session.submit({ ...command, expectedBridgeRevision: current.bridgeRevision }, "Apply card choice", `card-plan-${command.promptId ?? ""}-${command.messageId ?? 0}`)
          .catch((error) => { plan.cancel(); cardPlan.current = undefined; setChoosing(false); fail(error); });
      }
    }, 0);
    return () => { window.clearTimeout(timer); window.clearTimeout(done); };
  }, [helperKey, choosing, session, fail]);
  const orderTriggers = useCallback((resolveOrder: XmagePromptAbility[], remember: boolean) => {
    const prompt = session?.state.snapshot?.promptEnvelopeV2;
    if (!prompt) return;
    const first = triggerPlan.start(resolveOrder, prompt, remember);
    setPlanning(true);
    if (first) sendTriggerPick(first);
  }, [session, triggerPlan, sendTriggerPick]);
  useEffect(() => {
    if (!autoPaying || !session) return;
    const timer = window.setTimeout(() => {
      const run = autoPay.current;
      const current = session.state.snapshot;
      if (!run || !current) return;
      const move = run.step(current, session.state.working || session.state.pendingActionID !== undefined);
      const end = (text?: string) => { autoPay.current = undefined; setAutoPaying(false); if (text) showNotice(text); };
      if (move.kind === "action") session.send(move.action).catch((error) => { end(); fail(error); });
      else if (move.kind === "command") session.submit(move.command, move.label, move.actionID).catch((error) => { end(); fail(error); });
      else if (move.kind === "stop") end(move.notice);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [helperKey, autoPaying, session, showNotice, fail]);
  // A stopped run forgets its state.
  useEffect(() => { if (!autoPaying) autoPay.current = undefined; }, [autoPaying]);

  // Which ids a click on the table can answer: battlefield permanents, players and your hand.
  const onTable = useMemo(() => {
    const ids = new Set<string>();
    for (const player of snapshot?.players ?? []) {
      ids.add(player.playerId);
      player.zones.battlefield.forEach((c) => ids.add(c.instanceId));
    }
    me?.zones.hand.forEach((c) => ids.add(c.instanceId));
    return (id: string) => ids.has(id);
  }, [snapshot, me]);
  // With a D20 roll the table answers XMage's starting-player question itself, so that question never shows.
  const rawBrowser = browserKind(envelope, onTable, (name) => snapshot !== undefined && cardNamed(snapshot, name) !== undefined);
  const browser = playerPanel !== undefined && playerPanel === envelope?.id ? "players"
    : rawBrowser === "players" && table.state.roll !== undefined ? undefined : rawBrowser;
  // Auto Pay answers its own colour question; it never opens the choice browser.
  const autoPayColour = autoPaying && envelope?.responseKind.toLowerCase() === "choice";
  // A chosen trigger order answers the ordering prompts it covers; the browser stays shut for them.
  const planAnswers = planning && snapshot !== undefined && triggerPlan.answers(snapshot);
  const showBrowser = browser !== undefined && browser !== "mulligan" && browser !== "amount" && !pending && !autoPayColour && !planAnswers && !choosing;
  // A decision that needs you opens with the response alert; panels open and close with their sounds.
  useEffect(() => { if (showBrowser) gameAudio.play("response-alert"); }, [showBrowser, envelope?.id]);
  const firstStack = useRef(true);
  useEffect(() => { if (firstStack.current) { firstStack.current = false; return; } gameAudio.play(stackOpen ? "ui-open" : "ui-close"); }, [stackOpen]);
  const firstPanel = useRef(true);
  useEffect(() => { if (firstPanel.current) { firstPanel.current = false; return; } gameAudio.play(panel === "log" ? "page-flip" : panel ? "ui-open" : "ui-close"); }, [panel]);
  // A number takes the button corner (ArenaAmountPill), with the board in view.
  const amountPill = browser === "amount" && !finished;

  /** A click on a card: answer a target or combat question with it, or offer its legal actions. */
  const clickCard = (id: string, at?: Place) => {
    if (suppressClick.current) { suppressClick.current = false; return; }
    if (!snapshot || pending || finished) return;
    setMenu(undefined);
    if (targetIDs.has(id)) {
      if (combatSelect) declarationOrder.current = [...declarationOrder.current.filter((x) => x !== id), id];
      send({ type: "choose_target", targetIds: [id] }, "Choose");
      return;
    }
    const actions = actionsFor(snapshot, id);
    if (actions.length === 1 && actions[0].type === "cast_spell") gameAudio.play("card-play");
    if (actions.length === 1) sendAction(actions[0]);
    else if (actions.length > 1 && at) setMenu({ id, at, actions });
  };
  /** Board points for a pointer position. */
  const toBoard = (clientX: number, clientY: number) => {
    const bounds = wrapRef.current!.getBoundingClientRect();
    return { x: (clientX - bounds.left - geo.left) / geo.scale, y: (clientY - bounds.top - geo.top) / geo.scale };
  };
  /** A click on a hand card: a target answer takes it; the popped card plays (ArenaHandFan.play); another pops first. */
  const clickHand = (id: string) => {
    if (suppressClick.current) { suppressClick.current = false; return; }
    if (!snapshot || pending || finished) return;
    setMenu(undefined);
    if (targetIDs.has(id)) { clickCard(id); return; }
    if (popped !== id) { setPopped(id); gameAudio.play("card-pickup"); return; }
    playFromHand(id);
  };
  /** Pressing a hand card may start carrying it to the table (ArenaHandFan's drag). */
  const pressHand = (id: string, event: React.PointerEvent) => {
    if (!snapshot || pending || finished || mulligan) return;
    const start = toBoard(event.clientX, event.clientY);
    setCarry({ id, start, point: start, moved: false });
  };
  // The carry as the pointer handlers last left it. The sound and the drop happen in the handlers, never inside a state
  // updater: React runs updaters while it renders, so a drop sent from one changed the table mid-render (React's "Cannot
  // update a component while rendering a different component (GameScreen)" warning).
  const carryNow = useRef(carry);
  carryNow.current = carry;
  /**
   * Reads a card in the inspector (CardInspector): a right-click keeps it open until a click elsewhere or Esc, a held press
   * until it is let go (HoldCardInspection). Hovering never opens it. A hold on a hand card ends any carry it started.
   */
  const reader: CardReader = useMemo(() => ({
    open: (target, held) => { carryNow.current = undefined; setCarry(undefined); setReading({ name: target.name, card: target.card, held }); },
    release: () => setReading((current) => (current?.held ? undefined : current)),
  }), []);
  useEffect(() => {
    if (!carry) return;
    const move = (e: PointerEvent) => {
      const c = carryNow.current;
      if (!c) return;
      const point = toBoard(e.clientX, e.clientY);
      const moved = c.moved || Math.hypot(point.x - c.start.x, point.y - c.start.y) > 6;
      if (moved && !c.moved) gameAudio.play("card-pickup");
      carryNow.current = { ...c, point, moved };
      setCarry(carryNow.current);
    };
    const up = () => {
      const c = carryNow.current;
      carryNow.current = undefined;
      setCarry(undefined);
      if (c?.moved) {
        suppressClick.current = true;
        if (drops(c.point, c.start, geo)) dropCard(c.id);
      }
    };
    const cancel = () => { carryNow.current = undefined; setCarry(undefined); };
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    window.addEventListener("pointercancel", cancel);
    return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); window.removeEventListener("pointercancel", cancel); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [carry?.id]);
  /** A card let go over the table (DragCastDropResolver): its one play goes at once, several open the choice, none says so. */
  const dropCard = (id: string) => playFromHand(id);
  const playFromHand = (id: string) => {
    if (!snapshot) return;
    const card = [...(me?.zones.hand ?? []), ...extraHand].find((c) => c.instanceId === id);
    const plays = actionsFor(snapshot, id).filter((a) => a.type === "play_land" || a.type === "cast_spell");
    if (plays.length === 1) { if (plays[0].type === "cast_spell") gameAudio.play("card-play"); sendAction(plays[0]); setPopped(undefined); }
    else if (plays.length > 1) setMenu({ id, at: { x: STAGE.width / 2, y: Y(ARENA.captionY) + 120, w: 0, h: 0, z: 0 }, actions: plays });
    else showNotice(`${card?.card.name ?? "That card"} is not currently playable`);
  };


  // An opponent's spell (not an ability) holds the reveal for its first 1.3 s, then settles (arenaBeginReveal).
  const topObject = stack[0];
  useEffect(() => {
    if (!topObject || reduceMotion || fxLevel === "off" || isStackAbility(topObject) || !topObject.controllerId || topObject.controllerId === viewer) return;
    setRevealID(topObject.id);
    const timer = window.setTimeout(() => setRevealID((id) => (id === topObject.id ? undefined : id)), 1300);
    return () => window.clearTimeout(timer);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [topObject?.id]);
  // Reading a card (the inspector open) holds smart pass, as holding a card open does on iOS.
  useEffect(() => { fx.hold.reading = reading !== undefined; }, [fx.hold, reading]);
  useEffect(() => () => { fx.hold.reading = false; }, [fx.hold]);
  // Redraw when the turn banner starts and ends, and when the wipe recap goes.
  const [, setFxTick] = useState(0);
  useEffect(() => {
    const now = fxNow();
    const marks = [fx.banner?.start, fx.banner?.end, fx.banner && fx.banner.end + 0.4, fx.recap?.until].filter((t): t is number => t !== undefined && t > now);
    const timers = marks.map((t) => window.setTimeout(() => setFxTick((v) => v + 1), (t - now) * 1000 + 20));
    return () => timers.forEach((t) => window.clearTimeout(t));
  }, [fx.banner, fx.recap]);
  const fxClock = fxNow();
  const showBanner = fx.banner !== undefined && fxClock >= fx.banner.start && fxClock < fx.banner.end + 0.35 && !showBrowser && !finished;
  const caption = notice && notice.until > fxClock ? notice.text : fx.recap && fx.recap.until > fxClock ? fx.recap.text : undefined;

  // ---------------- cards ----------------
  const now = performance.now();
  const battlefieldCard = (id: string) => snapshot?.players.flatMap((p) => p.zones.battlefield).find((c) => c.instanceId === id);
  // The resting hand's room: from the right edge of your last pile (with its count lozenge) to the controls corner.
  const handRoom = (() => {
    const P = ARENA.viewerPiles;
    const lastPile = me && me.zones.exile.length > 0 ? P.exile : P.library;
    const pileRight = ARENA.viewerMedallion.x + (lastPile.x - ARENA.viewerMedallion.x) * geo.grow + (P.size.w * geo.grow) / 2 + 12;
    return { left: pileRight, right: ARENA.primary.x - 8 };
  })();
  const handIDs = me?.zones.hand.map((c) => c.instanceId) ?? [];
  const mulligan = browser === "mulligan";
  // Cards you can play from your graveyard or exile join the fan's right end (ArenaExtraHand).
  const extraHand = snapshot && me && !mulligan ? extraHandCards(me, snapshot.legalActions ?? []) : [];
  const fanIDs = [...handIDs, ...extraHand.map((c) => c.instanceId)];
  // A card that joins the hand after the opening hand flies in from your deck, shows itself at the draw spot, then
  // joins the fan (ArenaHandFan.noteArrivals): 0 at the deck, 1 on show, 2 home; up to three, a quarter second apart.
  const [arrivals, setArrivals] = useState<ReadonlyMap<string, number>>(new Map());
  const knownHand = useRef<{ game: string; ids: Set<string> } | undefined>(undefined);
  const arrivalTimers = useRef<number[]>([]);
  useEffect(() => {
    if (!snapshot) return;
    const previous = knownHand.current;
    knownHand.current = { game: snapshot.id, ids: new Set(handIDs) };
    if (!previous || previous.game !== snapshot.id || reduceMotion || mulligan) return;
    const fresh = handIDs.filter((id) => !previous.ids.has(id));
    if (fresh.length === 0 || fresh.length > 3) return;
    const set = (id: string, phase: number | undefined) => setArrivals((current) => {
      const next = new Map(current);
      if (phase === undefined) next.delete(id); else next.set(id, phase);
      return next;
    });
    fresh.forEach((id, offset) => {
      set(id, 0);
      const delay = offset * 250 + 20;
      arrivalTimers.current.push(window.setTimeout(() => set(id, 1), delay),
        window.setTimeout(() => set(id, 2), delay + 900), window.setTimeout(() => set(id, undefined), delay + 1140));
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [handIDs.join(",")]);
  useEffect(() => () => arrivalTimers.current.forEach((t) => window.clearTimeout(t)), []);
  // A browser over the table keeps the hand resting under its veil.
  const covered = showBrowser || zone !== undefined || stackOpen || commanderView !== undefined;
  const carrying = carry?.moved === true;
  // The hand rests tucked along the bottom edge; the card under the pointer pops up whole (ArenaHandPosture: the
  // landscape board never opens the fan). A browser over the table or a carried card puts the pop down.
  const handUp = mulligan;
  const shownPop = !covered && !carrying && !mulligan && popped !== undefined && fanIDs.includes(popped) ? popped : undefined;
  const cards = new Map<string, ArenaCardProps>();
  const add = (props: ArenaCardProps) => { if (!cards.has(props.id)) cards.set(props.id, props); };
  const classFor = (card: ZoneCard, onBattlefield: boolean) => glowClasses(card, snapshot?.legalActions ?? [], {
    onBattlefield, targetable: targetIDs.has(card.instanceId), combatSelect, answering: !pending && snapshot !== undefined && envelope !== undefined, paying,
  }).join(" ");
  const clickAt = (place: Place) => (id: string) => clickCard(id, place);
  if (snapshot && me) {
    battlefieldPlaces(me.zones.battlefield, "me", undefined, geo, frames).forEach((place, id) => {
      const card = me.zones.battlefield.find((c) => c.instanceId === id)!;
      add({ id, place, view: "tile", card, frames, owner: "me", classes: classFor(card, true), onClick: clickAt(place), reader });
    });
    opponents.forEach((opponent, index) => {
      battlefieldPlaces(opponent.zones.battlefield, "opp", { index, count: opponents.length }, geo, frames).forEach((place, id) => {
        const card = opponent.zones.battlefield.find((c) => c.instanceId === id)!;
        add({ id, place, view: "tile", card, frames, owner: "opp", classes: classFor(card, true), onClick: clickAt(place), reader });
      });
      opponentHandPlaces(opponent.zones.handCount ?? opponent.zones.hand.length, { index, count: opponents.length }, geo).forEach((place, i) =>
        add({ id: `backs-${opponent.playerId}-${i}`, place, view: "back" }));
    });
    const handPlace = mulligan ? mulliganPlaces(handIDs, geo) : handPlaces(fanIDs, handUp, shownPop, geo, handRoom);
    // Past eight cards the fan is crowded: the cost shows only on the popped card (ArenaHandFan.crowded).
    const crowded = !mulligan && me.zones.hand.length + extraHand.length > 8;
    [...me.zones.hand, ...(mulligan ? [] : extraHand)].forEach((card) => {
      const home = handPlace.get(card.instanceId)!;
      const arrival = arrivals.get(card.instanceId);
      const extra = extraHand.includes(card);
      // On its way in: at the deck, then whole at the draw spot, then home.
      const P = ARENA.viewerPiles;
      const place: Place = arrival === 0
        ? { ...home, x: ARENA.viewerMedallion.x + (P.library.x - ARENA.viewerMedallion.x) * geo.grow, y: B(P.library.y), r: 0, s: (P.size.w * geo.grow) / home.w, z: 950 }
        : arrival === 1 ? { ...home, x: ARENA.draw.x, y: Y(ARENA.draw.y), r: 0, s: (ARENA.draw.w * geo.grow) / home.w, z: 950 } : home;
      add({ id: card.instanceId, place, view: "face", card, owner: "me", inHand: true,
        extraZone: extra ? actionsFor(snapshot, card.instanceId).find((a) => a.sourceZone)?.sourceZone ?? (me.zones.graveyard.includes(card) ? "graveyard" : "exile") : undefined,
        classes: `${classFor(card, false)} ${carrying && carry?.id === card.instanceId ? "carried" : ""} ${arrival !== undefined ? `arrive-${arrival}` : ""} ${mulligan ? "opening" : ""} ${crowded && card.instanceId !== shownPop ? "nocost" : ""}`,
        onClick: mulligan ? () => reader.open({ name: card.card.name, card }, false) : clickHand, onPress: mulligan ? undefined : pressHand, reader });
    });
    // Only the top of the stack stands on the table (ArenaStackCard); the tab opens the rest. Tucked, it steps aside.
    stack.slice(0, 1).filter((item) => !stackTucked(item.id)).forEach((item, depth) => {
      const name = item.sourceCard?.card.name ?? item.sourceName ?? item.name;
      const ability = isStackAbility(item);
      const source = item.sourceCard ?? (item.sourceInstanceId ? battlefieldCard(item.sourceInstanceId) : undefined);
      // A spell cast from the command zone wears a gold rim and a crown; that is its whole fanfare (ArenaStackCard).
      const commander = !ability && /command/i.test(item.sourceZone ?? "");
      const firstSeen = stackSeen.current.get(item.id) ?? now;
      stackSeen.current.set(item.id, firstSeen);
      const landing = depth === 0 && now - firstSeen < 650;
      const base = stackPlace(depth, geo);
      // Low enough that the larger card clears the opponent's piles above the stack card.
      const place = revealID === item.id ? { ...base, x: base.x - base.w * 0.8, y: base.y + base.h * 0.14, s: 1.2, z: 650 } : base;
      add({
        id: item.id, place, view: "face", name, card: item.sourceCard, label: item.name,
        ability: ability ? { source, name: item.sourceName ?? item.name, text: item.rulesText ?? item.name } : undefined,
        classes: [landing ? "landing" : "", commander ? "commander" : ""].join(" "), onClick: () => setStackOpen(true), reader,
      });
    });
  }
  // Remember where every card lies (a departure starts there) and where it was before it last moved (a steal starts there).
  {
    const at = fxNow();
    cards.forEach((props, id) => {
      const before = places.current.get(id);
      if (before && (Math.abs(before.x - props.place.x) > 2 || Math.abs(before.y - props.place.y) > 2)) movedFrom.current.set(id, { place: before, at });
      places.current.set(id, props.place);
    });
    if (places.current.size > 600) places.current = new Map([...cards].map(([id, props]) => [id, props.place]));
    if (movedFrom.current.size > 400) movedFrom.current.clear();
    // A flight stands in for its tile until it lands.
    const hidden = fx.hidden(at);
    hidden.forEach((id) => { const props = cards.get(id); if (props) cards.set(id, { ...props, classes: `${props.classes ?? ""} fx-hidden` }); });
  }
  // Your commander is cast from your medallion, as on the iOS Arena board: it glows while the commander can be cast.
  const commandActions = snapshot && me && !pending ? me.zones.command.flatMap((c) => actionsFor(snapshot, c.instanceId)) : [];

  // ---------------- corner controls ----------------
  const myCreatures = me?.zones.battlefield ?? [];
  let primary: Plaque | undefined;
  let secondary: Plaque | undefined;
  // arenaWaitingTitle: whose turn it is while you wait.
  const waitingTitle = !snapshot || activeIsMe || !snapshot.activePlayerId ? "Waiting…"
    : opponents.length > 1 ? `${snapshot.players.find((p) => p.playerId === snapshot.activePlayerId)?.displayName ?? "Opponent"}’s Turn` : "Opponent’s Turn";
  if (snapshot && !finished && envelope && !showBrowser && !mulligan && !amountPill) {
    const act = (action: LegalAction | undefined, style: Plaque["style"], label?: string, want = false): Plaque | undefined =>
      action && { label: label ?? EngineDisplayText.label(action.label), style, want, onClick: () => sendAction(action) };
    // An answer on its way: the corner waits (GameActionDockModel's waiting mode); payments and combat keep their own.
    const answering = pending && !paying && !combat;
    if (answering) {
      primary = { label: "Waiting…", style: "quiet" };
    } else if (envelope.responseKind === "priority") {
      // The reference's short words: Next to move on, End Turn late in your turn, Resolve over a stack, Pass otherwise.
      const pass = promptActions.find((a) => a.type === "pass_priority");
      const phase = phaseIndex(snapshot.step ?? snapshot.phase);
      const title: [string, string?] = stack.length > 0 ? ["Resolve"] : !activeIsMe ? ["Pass"]
        : phase === 0 ? ["Next", "To Main"] : phase === 1 ? ["Next", "To Combat"] : phase === 2 ? ["Next", "To Main 2"] : ["End Turn"];
      primary = pass ? { ...act(pass, "primary", title[0], true)!, subtitle: title[1] } : { label: waitingTitle, style: "quiet" };
      // Resolve All: one pass that keeps passing until the stack has resolved (GameplayAffordances.resolveStackCommand).
      if (pass && (snapshot.xmage?.stack.length ?? 0) >= 2 && session?.supportedAnswerActions.has("passUntilStackResolved")) {
        const command: GameCommand = { type: "pass_priority", gameId: snapshot.id, playerId: pass.playerId, promptId: pass.promptId, messageId: pass.messageId,
          expectedBridgeRevision: snapshot.bridgeRevision, answerActions: ["passUntilStackResolved"] };
        secondary = { label: "Resolve All", style: "secondary", onClick: () => session.submit(command, "Resolve the stack", `resolve-stack-${pass.promptId ?? ""}`).catch(fail) };
      }
    } else if (combat) {
      // arenaCombatButtons: the count of what you declared finishes it; All Attack before anything is declared; Take Back after.
      const declared = declaredCount(snapshot, combat);
      const done = promptActions.find((a) => a.type === "answer_yes_no" && a.confirmed !== false);
      const finish: Plaque | undefined = done && { label: finishTitle(combat, declared), style: declared === 0 ? "secondary" : "primary", want: declared > 0, onClick: () => sendAction(done) };
      const targetable = boardTargetableIds(snapshot);
      const candidates = myCreatures.filter((c) => (combat === "attackers" ? c.isAttacking === true : (c.blocking?.length ?? 0) > 0) && targetable.has(c.instanceId));
      const latest = [...declarationOrder.current].reverse().find((id) => candidates.some((c) => c.instanceId === id)) ?? candidates.at(-1)?.instanceId;
      const back: Plaque | undefined = latest !== undefined ? { label: "Take Back", style: "secondary", onClick: () => {
        declarationOrder.current = declarationOrder.current.filter((x) => x !== latest);
        send({ type: "choose_target", targetIds: [latest] }, "Take back");
        showNotice(`Took back ${myCreatures.find((c) => c.instanceId === latest)?.card.name ?? "the creature"}`);
      } } : undefined;
      const everyone = combat === "attackers" && declared === 0 && !attacking ? allAttackTargets(snapshot) : undefined;
      if (attacking) {
        primary = { label: "Attacking…", style: "primary", disabled: true };
        secondary = { label: "Stop", style: "secondary", onClick: () => { attackQueue.current = undefined; setAttacking(false); } };
      } else if (everyone && everyone.length > 0) {
        primary = { label: "All Attack", style: "primary", want: true, onClick: () => { attackQueue.current = new AttackQueue(everyone); setAttacking(true); } };
        secondary = finish;
      } else {
        primary = finish;
        secondary = declared > 0 ? back : undefined;
      }
    } else if (paying) {
      // Auto Pay (arenaPaymentButtons): lit when its plan pays the whole cost, dimmed otherwise (the sources on the table
      // still take clicks); "Paying…" and Stop while it runs; Cancel beside it.
      const cancel = manaUndoActions(snapshot).find((a) => a.type === "cancel_payment" || a.type === "cancel_mana_payment");
      if (autoPaying) {
        primary = { label: "Paying…", style: "primary", disabled: true };
        secondary = { label: "Stop", style: "secondary", onClick: () => { autoPay.current = undefined; setAutoPaying(false); } };
      } else {
        primary = { label: "Auto Pay", style: "primary", want: true, disabled: !autoPayReady(snapshot), onClick: () => {
          autoPay.current = new AutoPayRun();
          setAutoPaying(true);
        } };
        secondary = cancel && { label: "Cancel", style: "secondary", onClick: () => sendAction(cancel) };
      }
    } else {
      const confirming = (a: LegalAction) => Number(a.type === "answer_yes_no" && a.confirmed === true);
      const ordered = [...promptActions].sort((a, b) => confirming(b) - confirming(a));
      primary = act(ordered[0], "primary", undefined, true);
      secondary = act(ordered[1], "secondary");
      // A decision with nothing on the table or in the corner opens the full list (GameActionDockModel's "Choices").
      if (!primary && targetIDs.size === 0 && (snapshot.legalActions ?? []).length > 0) primary = { label: "Choices", style: "secondary", onClick: () => setSheet("actions") };
    }
  } else if (snapshot && !finished && !envelope) {
    primary = { label: waitingTitle, style: "quiet" };
  }
  // arenaCaptionText: what the table asks of you in a few words: a payment, a combat declaration, a target on the board.
  const promptLine = (() => {
    if (!snapshot) return table.state.status;
    if (!envelope || showBrowser || mulligan) return undefined;
    if (paying) {
      const clean = cleanMessage(snapshot.manaPayment?.remainingText ?? envelope.message);
      return clean.length === 0 ? "Pay the cost" : clean.startsWith("{") ? `Pay ${clean}` : clean;
    }
    const players = new Set(snapshot.players.map((p) => p.playerId));
    const attackers = new Set(snapshot.players.flatMap((p) => p.zones.battlefield).filter((c) => c.isAttacking).map((c) => c.instanceId));
    if (combat === "attackers") return [...targetIDs].some((id) => players.has(id)) ? "Choose who to attack." : "Choose attackers.";
    if (combat === "blockers") return [...targetIDs].some((id) => attackers.has(id) && !myCreatures.some((c) => c.instanceId === id)) ? "Choose the attacker to block." : "Choose blockers.";
    if (boardTargetableIds(snapshot).size > 0) return cleanMessage(envelope.message.length === 0 ? "Choose a target." : envelope.message);
    return undefined;
  })();
  const thinking = snapshot && !envelope && !finished ? thinkingPlayerID(snapshot) : undefined;
  const thinkingName = thinking && thinking !== viewer ? snapshot?.players.find((p) => p.playerId === thinking)?.displayName : undefined;

  // ---------------- the starting roll, the result ----------------
  const roll = table.state.roll;
  // The last die lands and its result shows before the opening hand (Caleb, 2026-10-26: the mulligan came up mid-roll).
  const showRoll = roll !== undefined && !rollDismissed && (roll.nextSeatID !== undefined || !snapshot || snapshot.turn <= 1);
  useEffect(() => {
    if (roll && roll.nextSeatID === undefined) { const t = window.setTimeout(() => setRollDismissed(true), 3500); return () => window.clearTimeout(t); }
  }, [roll?.nextSeatID, roll]);
  const won = finished && viewer !== undefined && (snapshot!.winnerPlayerIds ?? []).includes(viewer);
  // What happened this game, for the result screen (GameStats).
  const stats = useRef(new GameStats());
  useEffect(() => { if (snapshot) stats.current.record(snapshot); }, [snapshot]);
  useEffect(() => { if (finished) { gameAudio.duckMusic(6); gameAudio.play(won ? "victory" : "defeat", 0.25); } }, [finished, won]);
  // The in-game playlist while a game is on screen; the menus switch back to theirs (GameAudio.setScene).
  useEffect(() => { gameAudio.setScene("game"); }, []);

  // The relay's turn clock burns its rope smoothly.
  const rope = table.state.turnClock.rope(table.state.localSeatID, performance.now() / 1000);
  useEffect(() => {
    if (!rope) return;
    const timer = window.setInterval(() => setClockTick((t) => t + 1), 250);
    return () => window.clearInterval(timer);
  }, [rope]);
  const seatOf = (player: PlayerGameState) => Object.entries(table.state.seatNames).find(([, n]) => n === player.displayName)?.[0];

  // The skip choices in a few words each (ArenaPassAheadPill.items).
  const skipping = session?.state.autoPassing === true;
  const fullControl = session?.state.fullControl === true;
  const passItems: MenuItem[] = session ? [
    { id: "skip-responses", title: "To end of turn", subtitle: "Skips responses", glyph: "skipResponses", enabled: session.canStartYield("endTurnSkippingResponses"),
      action: () => session.startYield("endTurnSkippingResponses") },
    { id: "skip-to-my-turn", title: "To my turn", subtitle: "Skips responses", glyph: "toMyTurn", enabled: session.canStartYield("untilMyTurn"),
      action: () => session.startYield("untilMyTurn") },
    { id: "end-turn", title: "To end of turn", subtitle: "Stops if they respond", glyph: "endTurn", enabled: session.canStartYield("safeEndTurn"),
      action: () => session.startYield("safeEndTurn") },
    { id: "full-control", title: "Full control", subtitle: fullControl ? "On for this turn" : "Stop at every priority this turn", glyph: "fullControl", lit: fullControl,
      action: () => session.toggleFullControl() },
  ] : [];
  const canSkip = passItems.slice(0, 3).some((item) => item.enabled);
  // The gear's menu (arenaGameMenuItems).
  const gameItems: MenuItem[] = [
    { id: "log", title: "Game Log", glyph: "log", action: () => setPanel("log") },
    ...(!table.solo ? [{ id: "chat", title: "Chat", glyph: "chat", action: () => setPanel("chat") }] : []),
    ...(stack.length > 0 ? [{ id: "stack", title: `Stack (${stack.length})`, glyph: "stack", action: () => setStackOpen(true) }] : []),
    { id: "stops", title: "Phase Stops", glyph: "stops", action: () => setSheet("stops") },
    ...(session ? [{ id: "full-control", title: "Full control", subtitle: fullControl ? "On for this turn" : "Stop at every priority this turn", glyph: "fullControl",
      lit: fullControl, action: () => session.toggleFullControl() }] : []),
    // Everything you can do right now, in one list (the prompt details iOS opens from More actions).
    ...(session && (snapshot?.legalActions ?? []).length > 0 ? [{ id: "more", title: "More actions", glyph: "more", action: () => setSheet("actions") }] : []),
    ...(showMic && voiceState?.stage === "live" ? [{ id: "leave-voice", title: "Leave Voice Chat", glyph: "mic", action: () => { void voice?.leave(); } }] : []),
    { id: "settings", title: "Game Settings", glyph: "settings", action: () => setSheet("settings") },
  ];
  // Your commander on an opponent's battlefield is named, with why (ArenaCommanderSteal): 7 s in the caption.
  const taken = snapshot ? commandersTaken(snapshot).join(",") : "";
  const lastTaken = useRef<string[]>([]);
  useEffect(() => {
    const now = taken ? taken.split(",") : [];
    const fresh = now.find((entry) => !lastTaken.current.includes(entry));
    if (fresh && snapshot) showNotice(commanderTakenNotice(fresh, snapshot), 7);
    lastTaken.current = now;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [taken]);
  // The stack browser closes once the stack empties, so it doesn't reopen with the next spell.
  useEffect(() => { if (stack.length === 0) setStackOpen(false); }, [stack.length]);
  // A new prompt closes the corner menu and the player card.
  useEffect(() => { setCornerMenu(undefined); setPlayerCard(undefined); }, [envelope?.id, envelope?.messageId]);
  // A skip that stops by itself says why, in the caption.
  const autoPassStatus = session?.state.autoPassStatus;
  const wasSkipping = useRef(false);
  useEffect(() => {
    if (wasSkipping.current && !skipping && autoPassStatus && !autoPassStatus.includes("may still finish")) showNotice(autoPassStatus, 3);
    wasSkipping.current = skipping;
  }, [skipping, autoPassStatus, showNotice]);

  const medallion = (player: PlayerGameState, mine: boolean, index: number) => {
    const spot = mine ? ARENA.viewerMedallion : ARENA.opponentMedallion;
    const at = mine ? { x: spot.x, y: B(spot.y) }
      : { x: opponents.length > 1 ? 150 + (650 * (index + 0.5)) / opponents.length : spot.x, y: T(spot.y) };
    const d = spot.d * geo.grow;
    const ready = mine && commandActions.length > 0;
    // ArenaHeroMedallion.commanderReady: a breathing green-gold ring and a crown while you can cast from your command
    // zone, graveyard, exile or library (castableZones).
    const glowing = mine && !pending && snapshot !== undefined && castableZones(player, snapshot).size > 0;
    const targetable = targetIDs.has(player.playerId) && !pending;
    const seat = seatOf(player);
    const clock = rope && rope.seat === seat ? rope : undefined;
    const bubble = seat ? table.state.bubbles[seat] : undefined;
    const circumference = Math.PI * 2 * 46;
    const talking = showMic && seat !== undefined && voiceState.speaking.includes(seat);
    const inVoice = showMic && !mine && seat !== undefined && voiceState.stage === "live" && voiceState.inVoice.includes(seat);
    const quiet = seat !== undefined && (voiceState?.selfMuted.includes(seat) || voiceState?.silenced.includes(seat));
    return (
      <div key={player.playerId}>
        <button type="button" className={`amed ${targetable ? (combat === "attackers" ? "targetable attack" : "targetable") : glowing ? "ready" : ""} ${isOut(player) ? "out" : ""} ${snapshot?.activePlayerId === player.playerId ? "active" : ""}`}
          style={{ left: at.x, top: at.y, ["--d" as string]: `${d}px` }}
          aria-label={`${mine ? "You" : player.displayName ?? "Opponent"}, ${player.life} life${ready ? ", your commander can be cast" : glowing ? ", you can play from a zone" : ""}`}
          onClick={(event) => {
            event.stopPropagation();
            // A player target with several picks opens its panel (arenaSubmitPlayerTarget); one pick answers here.
            if (targetable && ((envelope?.maxChoices ?? 1) > 1 || (envelope?.minChoices ?? 1) > 1)) setPlayerPanel(envelope?.id);
            else if (targetable) send({ type: "choose_target", targetIds: [player.playerId] }, player.displayName ?? "Player");
            // Your commander ready to cast opens the commander browser: the card large, its tax, Cast under it.
            else if (ready) setCommanderView(player.playerId);
            else setPlayerCard(playerCard === player.playerId ? undefined : player.playerId);
          }}>
          {glowing && !targetable && <i className="aready" aria-hidden="true"><b>♛</b></i>}
          {talking && <i className="aspeak" aria-hidden="true" />}
          <div className="av"><Portrait player={player} viewer={mine} /></div>
          {inVoice && <i className={`avoice ${quiet ? "muted" : ""}`} aria-hidden="true">{quiet ? MIC_OFF : MIC}</i>}
          <span className={`hp ${isOut(player) ? "out" : ""}`}>{isOut(player) ? "Out" : Math.max(0, player.life)}</span>
          {clock && (
            <svg className="rope" viewBox="0 0 100 100" aria-hidden="true">
              <circle cx="50" cy="50" r="46" fill="none" stroke={clock.strikes > 0 ? "#ff5a2e" : "#ffb36a"} strokeWidth="5" strokeLinecap="round"
                strokeDasharray={`${circumference * clock.fraction} ${circumference}`} transform="rotate(-90 50 50)" />
            </svg>
          )}
        </button>
        {mine && showMic && (
          <button type="button" className={`amic ${voiceState.stage} ${voiceState.muted ? "muted" : ""} ${talking ? "speaking" : ""}`}
            style={{ left: ARENA.menu.x, top: T(ARENA.menu.y) + 36 }} data-id="board.voice.mic"
            aria-label={voiceState.stage === "off" ? "Join voice chat" : voiceState.micBlocked ? "Microphone blocked, try again"
              : pushToTalk ? `Hold to talk (or hold ${VoiceChat.keyLabel(talkKey)})` : voiceState.muted ? "Turn your microphone on" : "Turn your microphone off"}
            aria-pressed={voiceState.stage === "live" && !voiceState.muted}
            onPointerDown={(event) => { event.stopPropagation(); if (pushToTalk && voiceState.stage === "live" && !voiceState.micBlocked) { event.currentTarget.setPointerCapture(event.pointerId); void voice?.talk(true); } }}
            onPointerUp={() => { if (pushToTalk) void voice?.talk(false); }}
            onPointerCancel={() => { if (pushToTalk) void voice?.talk(false); }}
            onClick={(event) => {
              event.stopPropagation();
              if (voiceState.stage === "off") voice?.join().catch(() => showNotice("Voice chat didn't connect.", 3));
              else if (!pushToTalk || voiceState.micBlocked) void voice?.toggleMute();
            }}>
            {voiceState.stage === "live" && !voiceState.muted ? MIC : MIC_OFF}
          </button>
        )}
        {/* Several opponents need their names; iOS's one opponent seat shows none (its card names them). */}
        {!mine && opponents.length > 1 && (
          <div className="aname under" style={{ left: at.x, top: at.y + d / 2 + 4 }}>{player.displayName}{isOut(player) ? " (left)" : ""}</div>
        )}
        {/* Your poison and the worst commander damage you took, at a glance by your medallion (TavernStatusGlance). */}
        {mine && (() => {
          const pressing = statusBadges(player, snapshot ?? undefined);
          const worst = pressing.filter((b) => b.icon === "commander").sort((a, b) => (b.count ?? 0) - (a.count ?? 0))[0];
          const shown = [...pressing.filter((b) => b.icon === "poison"), ...(worst ? [worst] : [])];
          return shown.length > 0 && (
            <div className="aglance" style={{ left: at.x + d / 2 - 4, top: at.y + d / 2 - 6 }} aria-hidden="true">
              {shown.map((badge) => <StatusBadge key={badge.id} badge={badge} size={22} />)}
            </div>
          );
        })()}
        {/* Commander damage, poison, the monarch… curve round the opponent's medallion, toward the table (TavernEffectOrbitBadges). */}
        {!mine && (() => {
          const radius = d / 2 + 14 * geo.grow;
          const shown = orbitShown(statusBadges(player, snapshot ?? undefined), 5);
          const slots = orbitOffsets(shown.badges.length + (shown.more > 0 ? 1 : 0), radius, 90);
          const size = radius * ORBIT.badgeShare;
          return (
            <>
              {shown.badges.map((badge, i) => (
                <div key={badge.id} className="aorbit" style={{ left: at.x + slots[i].x, top: at.y + slots[i].y }}><StatusBadge badge={badge} size={size} /></div>
              ))}
              {shown.more > 0 && <div className="aorbit more" style={{ left: at.x + slots[slots.length - 1].x, top: at.y + slots[slots.length - 1].y, width: size * 0.8, height: size * 0.8 }}>+{shown.more}</div>}
            </>
          );
        })()}
        {bubble && Date.now() - bubble.at < 3200 && <div key={bubble.at} className="abubble" style={{ left: at.x, top: at.y - d / 2 - 4 }}>{bubble.emote.text}</div>}
      </div>
    );
  };

  const piles = (player: PlayerGameState, mine: boolean, index: number) => {
    const spots = mine ? ARENA.viewerPiles : ARENA.opponentPiles;
    const shift = !mine && opponents.length > 1 ? -index * 170 : 0;
    // Piles grow with the board, so they spread from their anchor (your medallion; their library) to keep the gaps for
    // their count lozenges (Caleb, 2026-10-21, on iOS: the badges ran over the next pile).
    const anchor = mine ? ARENA.viewerMedallion.x : ARENA.opponentPiles.library.x;
    const at = (p: { x: number; y: number }) => ({ x: anchor + (p.x - anchor) * geo.grow + shift, y: mine ? B(p.y) : T(p.y) });
    const size = { w: spots.size.w * geo.grow, h: spots.size.h * geo.grow };
    const whose = mine ? "Your" : `${player.displayName ?? "Their"}’s`;
    const open = (zone: "graveyard" | "exile") => () => setZone({ title: `${whose} ${zone}`, cards: player.zones[zone] });
    return (
      <div key={`piles-${player.playerId}`}>
        <ArenaPile {...at(spots.library)} size={size} count={player.zones.libraryCount ?? 0} kind="library" label={`${whose} library`} />
        {(() => {
          // A revealed top card (Courser of Kruphix, Future Sight…) lies face up on the deck (TopOfLibraryCard), lit when you can play it.
          const top = player.zones.library[0];
          if (!top || top.card.name === "Hidden card") return null;
          const playable = mine && !pending && actionsFor(snapshot!, top.instanceId).some((a) => a.type === "cast_spell" || a.type === "play_land");
          const spot = at(spots.library);
          return (
            <button type="button" className={`atoplib ${playable ? "playable" : ""}`} style={{ left: spot.x, top: spot.y, height: size.h, width: size.h / 1.395 }}
              aria-label={`Top of ${mine ? "your" : `${player.displayName ?? "their"}’s`} library: ${top.card.name}${playable ? ", you can play it" : ""}`}
              onClick={(e) => { e.stopPropagation(); setZone({ title: `Top of ${mine ? "your" : `${player.displayName ?? "their"}’s`} library`, cards: [top] }); }}
              {...readProps(reader, { name: top.card.name, card: top })}>
              <CardArt card={top.card} version="normal" />
              <i aria-hidden="true">{EYE}</i>
            </button>
          );
        })()}
        <ArenaPile {...at(spots.graveyard)} size={size} count={player.zones.graveyard.length} kind="graveyard" label={`${whose} graveyard`}
          top={player.zones.graveyard.at(-1)} onOpen={open("graveyard")} reader={reader} />
        {player.zones.exile.length > 0 && (
          <ArenaPile {...at(spots.exile)} size={size} count={player.zones.exile.length} kind="exile" label={`${whose} exile`}
            top={player.zones.exile.at(-1)} onOpen={open("exile")} reader={reader} />
        )}
      </div>
    );
  };

  // Where flights start and end (BoardFXAnchors): the stack card, each player's medallion and hand.
  const anchors: FXAnchors = {
    viewerID: viewer,
    stack: (() => { const p = stackPlace(0, geo); return { x: p.x, y: p.y }; })(),
    player: (id) => {
      if (id === viewer) return { x: ARENA.viewerMedallion.x, y: B(ARENA.viewerMedallion.y) };
      const index = Math.max(0, opponents.findIndex((o) => o.playerId === id));
      return { x: opponents.length > 1 ? 150 + (650 * (index + 0.5)) / opponents.length : ARENA.opponentMedallion.x, y: T(ARENA.opponentMedallion.y) };
    },
    hand: (id) => (id === viewer ? { x: (handRoom.left + handRoom.right) / 2, y: B(ARENA.hand.downY) } : { x: ARENA.opponentHand.x, y: T(ARENA.opponentHand.y) + 20 }),
  };

  const log = snapshot?.log ?? [];
  // One line of combat context under damage and deaths, decided as each entry first appears (CombatLogReasons).
  const logReasons = useMemo(() => { if (snapshot) combatReasons.current.observe(snapshot); return combatReasons.current.reasons; }, [snapshot]);
  const pool = me?.manaPool;
  const poolSymbols = pool ? (["W", "U", "B", "R", "G", "C"] as const).map((s) => [s, pool[s]] as const).filter(([, n]) => n > 0) : [];
  const stop = (event: React.MouseEvent) => event.stopPropagation();

  // The desktop keys for iOS's touches (docs/WEB_PARITY.md, Desktop input): Space taps the primary plaque and a 0.6 s hold
  // of it (or of the plaque) turns on Full control; Enter confirms a browser; Esc closes the top layer; Ctrl/Cmd+Z undoes mana.
  const undoMana = snapshot && paying && !autoPaying ? manaUndoActions(snapshot).find((a) => a.type === "undo_mana") : undefined;
  const closeTop = menu ? () => setMenu(undefined) : cornerMenu ? () => setCornerMenu(undefined)
    : playerCard ? () => setPlayerCard(undefined) : confirmConcede ? () => setConfirmConcede(false) : sheet ? () => setSheet(undefined)
    : commanderView ? () => setCommanderView(undefined) : zone ? () => setZone(undefined) : stackOpen ? () => setStackOpen(false)
    : panel ? () => setPanel(undefined) : undefined;
  const keys = useRef<{ primary?: () => void; fullControl?: () => void; undo?: () => void; close?: () => void; reading: boolean }>({ reading: false });
  keys.current = {
    primary: primary?.onClick && !primary.disabled && !(primary.style !== "quiet" && pending) ? primary.onClick : undefined,
    fullControl: session && !finished ? () => session.toggleFullControl() : undefined,
    undo: undoMana && !pending ? () => sendAction(undoMana) : undefined,
    close: closeTop, reading: reading !== undefined,
  };
  /** A hold that turned Full control on swallows the press that ends it (FullControlHold.swallowNextPass). */
  const swallowPass = useRef(0);
  const plaqueHold = useRef<number | undefined>(undefined);
  const startHold = () => {
    window.clearTimeout(plaqueHold.current);
    plaqueHold.current = window.setTimeout(() => {
      plaqueHold.current = undefined;
      keys.current.fullControl?.();
      swallowPass.current = performance.now() + 1500;
    }, 600);
  };
  /** Ends a hold; true when the press should still act (the hold had not yet turned Full control on). */
  const endHold = () => {
    const pending = plaqueHold.current !== undefined;
    window.clearTimeout(plaqueHold.current);
    plaqueHold.current = undefined;
    if (!pending && swallowPass.current > performance.now()) { swallowPass.current = 0; return false; }
    return true;
  };
  useEffect(() => {
    const typing = (target: EventTarget | null) => target instanceof HTMLElement && (target.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(target.tagName));
    const down = (event: KeyboardEvent) => {
      if (typing(event.target) || event.altKey) return;
      gameAudio.unlock();
      const current = keys.current;
      if (event.key === " " && !event.metaKey && !event.ctrlKey) {
        event.preventDefault();
        if (!event.repeat && !current.reading && (current.primary || current.fullControl)) startHold();
      } else if (event.key === "Enter" && !event.metaKey && !event.ctrlKey) {
        const confirm = [...document.querySelectorAll<HTMLButtonElement>(".bfoot .aplaque.primary")].filter((b) => !b.disabled);
        if (confirm.length === 1 && !current.reading) { event.preventDefault(); confirm[0].click(); }
      } else if (event.key === "Escape") {
        // The inspector closes itself first.
        if (!current.reading && current.close) { event.preventDefault(); current.close(); }
      } else if ((event.key === "z" || event.key === "Z") && (event.metaKey || event.ctrlKey) && !event.shiftKey && current.undo) {
        event.preventDefault();
        current.undo();
      }
    };
    const up = (event: KeyboardEvent) => {
      if (event.key !== " " || typing(event.target)) return;
      event.preventDefault();
      if (plaqueHold.current === undefined && swallowPass.current === 0) return;
      if (endHold()) keys.current.primary?.();
    };
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    return () => { window.removeEventListener("keydown", down); window.removeEventListener("keyup", up); window.clearTimeout(plaqueHold.current); };
  }, []);
  // A hidden tab neither smart-passes nor skips; showing it again picks up where the table is (scene phase on iOS).
  useEffect(() => {
    if (!session) return;
    const update = () => session.setForeground(document.visibilityState !== "hidden");
    update();
    document.addEventListener("visibilitychange", update);
    return () => document.removeEventListener("visibilitychange", update);
  }, [session]);

  return (
    <div className="arena" ref={wrapRef} data-paced={paced.behind ? "behind" : undefined} onClick={() => { setCornerMenu(undefined); setPlayerCard(undefined); setMenu(undefined); }}
      onPointerDownCapture={() => gameAudio.unlock()}
      onClickCapture={(event) => { if ((event.target as Element).closest?.(".aplaque, .aff, .acoin, .amenucard .arow, .aundo")) gameAudio.play("ui-tap"); }}
      onPointerMove={(event) => {
        // Along the resting hand the card under the pointer pops up (ArenaHandFan.panned); the popped card keeps it while
        // the pointer is on its picture; anywhere else puts it down.
        if (mulligan || covered || carrying || fanIDs.length === 0) { if (popped) setPopped(undefined); return; }
        const point = toBoard(event.clientX, event.clientY);
        const rest = handPlaces(fanIDs, false, undefined, geo, handRoom);
        const fan = [...rest.values()];
        const top = Math.min(...fan.map((p) => p.y - (p.h * (p.s ?? 1)) / 2));
        // Never over your piles.
        const left = Math.max(handRoom.left, Math.min(...fan.map((p) => p.x - p.w / 2)) - 12);
        const right = Math.max(...fan.map((p) => p.x + p.w / 2)) + 12;
        const lifted = popped ? handPlaces(fanIDs, false, popped, geo, handRoom).get(popped) : undefined;
        const onLifted = lifted !== undefined && Math.abs(point.x - lifted.x) <= (lifted.w * (lifted.s ?? 1)) / 2 &&
          Math.abs(point.y - lifted.y) <= (lifted.h * (lifted.s ?? 1)) / 2;
        let next: string | undefined;
        if (point.y >= top - 12 && point.x > left && point.x < right) next = scrubHand(fanIDs, rest, point, popped);
        else if (onLifted) next = popped;
        if (next !== popped) setPopped(next);
      }}
      onPointerLeave={() => setPopped(undefined)}>
      <div className="avignette" ref={vignetteRef} aria-hidden="true" />
      {session && !finished && <ComboLoopOverlay session={session} />}
      <div className="arena-stage" aria-label="Game table" ref={stageRef}
        style={{ height: geo.height, backgroundImage: `url(${geo.plate})`, transform: `translate(${geo.left}px, ${geo.top}px) scale(${geo.scale})`,
          // Where a full-table layer's title starts: below the opponent's medallion and its life plaque (ArenaSafeArea.top(50)).
          ["--atop" as string]: `${Math.max(50, T(ARENA.opponentMedallion.y) + ARENA.opponentMedallion.d * geo.grow * 0.6 + 6)}px` }}>
        <div className="pool-light" data-side={snapshot ? (activeIsMe ? "me" : "opp") : undefined}
          style={{ height: 220 * geo.ky, top: snapshot ? Y(activeIsMe ? 205 : 15) : undefined }} />
        <div className="lamp" />
        {me && piles(me, true, 0)}
        {opponents.map((o, i) => piles(o, false, i))}
        <div onClick={stop}>
          {[...cards.values()].map((props) => <ArenaCard key={props.id} {...props} />)}
        </div>
        {lesson && snapshot && !showBrowser && !finished && (
          // Where Maren points (LessonFocusRing): a card on the table or in hand, a player's medallion, or the corner plaque.
          <div className="alessonrings" aria-hidden="true">
            {lesson.run.focus.ids.map((id) => {
              const place = places.current.get(id);
              if (place) return <i key={id} style={{ left: place.x - place.w / 2 - 6, top: place.y - place.h / 2 - 6, width: place.w + 12, height: place.h + 12 }} />;
              if (!snapshot.players.some((p) => p.playerId === id)) return null;
              const at = anchors.player(id);
              return <i key={id} className="round" style={{ left: at.x - 34, top: at.y - 34, width: 68, height: 68 }} />;
            })}
            {lesson.run.focus.control === "primary" && (
              <i style={{ left: ARENA.primary.x - 6, top: B(ARENA.primary.y) - 6, width: ARENA.primary.w + 12, height: ARENA.primary.h + 12 }} />
            )}
            {lesson.run.focus.control === "medallion" && (
              <i className="round" style={{ left: ARENA.viewerMedallion.x - 40, top: B(ARENA.viewerMedallion.y) - 40, width: 80, height: 80 }} />
            )}
          </div>
        )}

        {snapshot && (snapshot.xmage?.combat.length ?? 0) > 0 && !showBrowser && (
          // Combat on the table (ArenaCombatArrows): red arcs from attackers to what they attack, grey once blocked, gold from
          // blockers to the attacker they hold.
          <svg className="aarrows" viewBox={`0 0 ${STAGE.width} ${geo.height}`} style={{ height: geo.height }} aria-hidden="true">
            {combatArrows(snapshot.xmage!.combat).map((arrow, index) => {
              const from = places.current.get(arrow.from);
              const target = places.current.get(arrow.to);
              const to = target ? { x: target.x, y: target.y }
                : (!arrow.toKind || arrow.toKind.toLowerCase() === "player") && snapshot.players.some((p) => p.playerId === arrow.to) ? anchors.player(arrow.to) : undefined;
              if (!from || !to) return null;
              const color = arrow.kind === "attack" ? "#ff5233" : arrow.kind === "blockedAttack" ? "#8a8a8a" : "#ffd173";
              const lift = Math.min(60, Math.hypot(to.x - from.x, to.y - from.y) * 0.25);
              const c = { x: (from.x + to.x) / 2, y: Math.min(from.y, to.y) - lift };
              const angle = Math.atan2(to.y - c.y, to.x - c.x);
              const head = (sign: number) => `${to.x - 12 * Math.cos(angle + sign * Math.PI / 6)},${to.y - 12 * Math.sin(angle + sign * Math.PI / 6)}`;
              const d = `M${from.x},${from.y} Q${c.x},${c.y} ${to.x},${to.y}`;
              return (
                <g key={index} stroke={color} fill="none" strokeLinecap="round">
                  <path d={d} strokeWidth={9} strokeOpacity={0.35} />
                  <path d={d} strokeWidth={3} strokeOpacity={0.95} />
                  <path d={`M${head(-1)} L${to.x},${to.y} L${head(1)}`} strokeWidth={3} />
                </g>
              );
            })}
          </svg>
        )}
        {snapshot && stack[0] && revealID !== stack[0].id && !showBrowser && !reading && !playerCard && !stackOpen && !zone && !commanderView && (() => {
          // The top of the stack points at its targets, a spell as well as an ability, with a reticle on each target while it
          // waits; an ability without targets points back at its source (ArenaStackArc, ArenaTargetReticle).
          const top = stack[0];
          const ability = isStackAbility(top);
          const targetIds = top.targetIds ?? [];
          const ids = targetIds.length > 0 ? targetIds : ability && top.sourceInstanceId ? [top.sourceInstanceId] : [];
          const targets = ids.flatMap((id) => {
            const place = places.current.get(id);
            if (place) return [{ x: place.x, y: place.y, size: Math.min(place.w, place.h) }];
            return snapshot.players.some((p) => p.playerId === id) ? [{ ...anchors.player(id), size: ARENA.viewerMedallion.d * geo.grow }] : [];
          });
          if (targets.length === 0) return null;
          const theirs = top.controllerId !== undefined && top.controllerId !== viewer;
          const color = theirs ? "#ff6145" : "#8cd9ff";
          const card = stackPlace(0, geo);
          const start = { x: card.x - card.w / 2, y: card.y - card.h / 2 + card.h * 0.24 };
          return (
            <svg key={top.id} className="aarcs" viewBox={`0 0 ${STAGE.width} ${geo.height}`} style={{ height: geo.height }} aria-hidden="true">
              {targets.map((t, i) => {
                const c = { x: (start.x + t.x) / 2, y: Math.min(start.y, t.y) - Math.abs(start.x - t.x) * 0.25 - 30 };
                const d = `M${start.x},${start.y} Q${c.x},${c.y} ${t.x},${t.y}`;
                return (
                  <g key={i} fill="none" strokeLinecap="round">
                    <path className="draw" d={d} pathLength={1} stroke={color} strokeOpacity={0.35} strokeWidth={9} />
                    <path className="draw" d={d} pathLength={1} stroke={color} strokeWidth={3} />
                    <path className="draw" d={d} pathLength={1} stroke="#fff" strokeOpacity={0.85} strokeWidth={1} />
                  </g>
                );
              })}
              {targetIds.length > 0 && targets.map((t, i) => {
                const r = Math.max(34, t.size * 0.62) / 2;
                return (
                  <g key={`r${i}`} className="reticle" style={{ transformOrigin: `${t.x}px ${t.y}px` }} stroke={color} fill="none">
                    <circle cx={t.x} cy={t.y} r={r} strokeWidth={7} strokeOpacity={0.35} />
                    <circle cx={t.x} cy={t.y} r={r} strokeWidth={2.2} />
                    <circle cx={t.x} cy={t.y} r={r * 0.64} stroke="#fff" strokeOpacity={0.8} strokeWidth={0.8} />
                    {[0, 90, 180, 270].map((a) => (
                      <line key={a} x1={t.x} y1={t.y - r - r * 0.2} x2={t.x} y2={t.y - r + r * 0.2} strokeWidth={2.6} transform={`rotate(${a} ${t.x} ${t.y})`} />
                    ))}
                  </g>
                );
              })}
            </svg>
          );
        })()}
        {carrying && carry && (() => {
          // The carried card follows the pointer, half again its size and leaning with the drag; over the table it settles a
          // little smaller with an ember shadow when it can be played, and the table's edge lights warm.
          const card = me?.zones.hand.find((c) => c.instanceId === carry.id);
          if (!card) return null;
          const over = drops(carry.point, carry.start, geo);
          const playable = snapshot !== undefined && actionsFor(snapshot, carry.id).some((a) => a.type === "play_land" || a.type === "cast_spell");
          const w = ARENA.hand.card.w * geo.handGrow; const h = ARENA.hand.card.h * geo.handGrow;
          const tilt = Math.max(-12, Math.min(12, (carry.point.x - carry.start.x) * 0.06));
          return (
            <>
              {over && <div className="adropglow" aria-hidden="true" />}
              <div className={`acarry ${over && playable ? "hot" : ""}`} aria-hidden="true"
                style={{ width: w, height: h, left: carry.point.x - w / 2, top: carry.point.y - 10 - h / 2, transform: `rotate(${tilt.toFixed(1)}deg) scale(${over ? 1.38 : 1.5})` }}>
                <img src={cardImageURL(card.card.name, "normal")} alt="" crossOrigin="anonymous" draggable={false} />
              </div>
            </>
          );
        })()}
        {fxLevel !== "off" && <FXBoundary><BoardFXOverlay active={fx.active} subjects={fx.director.subjects} frames={frames} anchors={anchors}
          height={geo.height} pixelRatio={geo.scale * (typeof window !== "undefined" ? window.devicePixelRatio : 1)}
          grabbed={(id) => { const moved = movedFrom.current.get(id); return moved && fxNow() - moved.at < 2 ? moved.place : undefined; }}
          stackIDs={new Set(stack.map((o) => o.id))} rect={(id) => {
            const moved = movedFrom.current.get(id);
            return moved && fxNow() - moved.at < 0.6 ? moved.place : places.current.get(id);
          }} /></FXBoundary>}
        {opponents.map((o, i) => medallion(o, false, i))}
        {snapshot && (() => {
          // Revealed and looked-at cards as two small chips between the opponent's piles and the gear (arenaRevealedChips).
          const revealed = snapshot.xmage?.revealed.flatMap((z) => z.cards) ?? [];
          const lookedAt = snapshot.xmage?.lookedAt.flatMap((z) => z.cards) ?? [];
          if (revealed.length === 0 && lookedAt.length === 0) return null;
          const pill = (label: string, cards: ZoneCard[], glyph: React.ReactNode) => (
            <button type="button" className="azonepill" aria-label={`${label}, ${cards.length === 1 ? "1 card" : `${cards.length} cards`}`}
              onClick={(e) => { e.stopPropagation(); setZone({ title: label, cards }); }}>{glyph}<b>{cards.length}</b></button>
          );
          return (
            <div className="azonepills" style={{ left: 818, top: T(12) }}>
              {revealed.length > 0 && pill("Revealed", revealed, EYE)}
              {lookedAt.length > 0 && pill("Looked at", lookedAt, EYE_OPEN)}
            </div>
          );
        })()}
        {me && medallion(me, true, 0)}
        {poolSymbols.length > 0 && (
          <div className="afloat" style={{ left: ARENA.floatingMana.x - 14, top: B(ARENA.floatingMana.y) }} onClick={stop}>
            {poolSymbols.map(([symbol, count]) => {
              const choice = envelope?.manaChoices?.find((c) => c.manaType === symbol);
              const body = <><ManaSymbol symbol={symbol} />{count > 1 && <b>{count}</b>}</>;
              return choice ? (
                <button key={symbol} type="button" className="fm" disabled={pending} aria-label={`Spend floating ${symbol} mana, ${count} available`}
                  onClick={() => send({ type: "play_mana", manaType: choice.manaType }, choice.label)}>{body}</button>
              ) : <span key={symbol} className="fm" aria-label={`${count} floating ${symbol} mana`}>{body}</span>;
            })}
          </div>
        )}
        {stack.length > 0 && stackTucked(stack[0].id) && (
          // Tucked: a slim tab at the table's edge brings the card back (ArenaStackTuck).
          <button type="button" className="astack-show" data-id="arena.stack.show" style={{ top: stackPlace(0, geo).y - 42 }}
            aria-label={`Show the stack, ${stack.length} on it`}
            onClick={(event) => { event.stopPropagation(); gameAudio.play("ui-open"); setStackTuckedTop(undefined); setStackPeekTop(stack[0].id); }}>
            <i>{EYE}</i><i>‹</i>{stack.length > 1 && <b>{stack.length}</b>}
          </button>
        )}
        {stack.length > 0 && !stackTucked(stack[0].id) && (() => {
          // A tab on the stack card's left edge opens the whole stack, with how many objects are on it; the eye under it
          // tucks the card aside (ArenaStackTuck).
          const top = stackPlace(0, geo);
          const height = stack.length > 1 ? 58 : 44;
          return (
            <button type="button" className="astack-tab" style={{ left: top.x - top.w / 2 - 26, top: top.y - height / 2, height }}
              aria-label={stack.length > 1 ? `Open the stack, ${stack.length} objects` : "Open the stack"} onClick={(event) => { event.stopPropagation(); setStackOpen(true); }}>
              {stack.length > 1 && <b>{stack.length}</b>}<i>‹</i>
            </button>
          );
        })()}
        {stack.length > 0 && !stackTucked(stack[0].id) && revealID !== stack[0].id && (() => {
          const top = stackPlace(0, geo);
          return (
            <button type="button" className="astack-tab astack-tuck" data-id="arena.stack.tuck" style={{ left: top.x - top.w / 2 - 26, top: top.y + top.h / 2 - 46, height: 40 }}
              aria-label="Tuck the stack away"
              onClick={(event) => { event.stopPropagation(); gameAudio.play("ui-close"); setStackTuckedTop(stack[0].id); setStackPeekTop(undefined); }}>
              <i>{EYE_OFF}</i>
            </button>
          );
        })()}

        {/* Above the raised hand while there is an answer to give (the prototype's controls z-index). */}
        <div className="acontrols" style={{ zIndex: (primary && primary.style !== "quiet") || secondary ? 600 : 430 }} onClick={stop}>
          <PhaseStrip step={snapshot?.step} side={activeIsMe ? "me" : "opp"} top={B(secondary ? ARENA.phaseStrip.raisedY : ARENA.phaseStrip.y) - 10}
            onOpen={() => setSheet("stops")} />
          {/* TavernTableHints: day or night as a small coin, the storm count, above the strip when they matter. */}
          {snapshot && (snapshot.dayNight || (snapshot.stormCount ?? 0) > 0) && (
            <div className="ahints" style={{ left: ARENA.phaseStrip.x + ARENA.phaseStrip.w / 2, top: B(secondary ? ARENA.phaseStrip.raisedY : ARENA.phaseStrip.y) - 18 - 9 }}>
              {snapshot.dayNight && (
                <i className={`daynight ${snapshot.dayNight === "night" ? "night" : "day"}`} role="img" aria-label={`It's ${snapshot.dayNight}`}>
                  {snapshot.dayNight === "night" ? MOON : SUN}
                </i>
              )}
              {(snapshot.stormCount ?? 0) > 0 && <b className="storm" aria-label={`Storm count ${snapshot.stormCount}`}>STORM {snapshot.stormCount}</b>}
            </div>
          )}
          {secondary && <button type="button" className={`aplaque abtn2 ${secondary.style}`} style={{ top: B(ARENA.secondary.y) }}
            disabled={(pending && secondary.label !== "Stop") || secondary.disabled} onClick={secondary.onClick}>{secondary.label}</button>}
          {primary ? (
            <button type="button" className={`aplaque abtn ${primary.style} ${primary.want ? "want" : ""} ${primary.subtitle ? "sub" : ""}`} style={{ top: B(ARENA.primary.y) }}
              disabled={(primary.style !== "quiet" && pending) || primary.disabled}
              onPointerDown={(e) => { if (e.button === 0 && session && !finished) startHold(); }}
              onPointerLeave={() => { window.clearTimeout(plaqueHold.current); plaqueHold.current = undefined; }}
              onClick={() => { if (endHold()) primary.onClick?.(); }}>
              {primary.label}{primary.subtitle && <small>{primary.subtitle}</small>}
            </button>
          ) : !finished && <div className="ahourglass" style={{ top: B(ARENA.primary.y) }}>{HOURGLASS}</div>}
          {(() => {
            // Undo the last mana while a payment allows it (ArenaBoardViews undo pill).
            const undo = snapshot && paying ? manaUndoActions(snapshot).find((a) => a.type === "undo_mana") : undefined;
            return undo && !autoPaying && (
              <button type="button" className="aundo" style={{ left: 650, top: B(343) }} disabled={pending} onClick={() => sendAction(undo)}>Undo <span aria-hidden="true">↶</span></button>
            );
          })()}
          {session && (
            // Pass ahead: the skip choices while you play, Stop while the table skips for you.
            <button type="button" className={`aff ${skipping ? "on" : ""}`} disabled={!skipping && !canSkip}
              style={{ left: ARENA.passAhead.x, top: B(ARENA.passAhead.y), width: ARENA.passAhead.w, height: ARENA.passAhead.h }}
              aria-label={skipping ? "Stop skipping" : "Skip options"} title={skipping ? autoPassStatus : undefined}
              onClick={() => (skipping ? session.stopAutoPass() : setCornerMenu("pass"))}>
              <svg viewBox="0 0 26 18"><path d="M2 2l9 7-9 7zM14 2l9 7-9 7z" /></svg>
            </button>
          )}
          {fullControl && primary && <div className="afullcontrol" style={{ left: ARENA.primary.x + ARENA.primary.w / 2, top: B(ARENA.primary.y) - 14 }}>Full control</div>}
          <button type="button" className={`acoin ${panel ? "on" : ""}`} style={{ left: ARENA.log.x - 14, top: T(ARENA.log.y) - 14 }} aria-label="Game log" onClick={() => setPanel(panel ? undefined : "log")}>{SCROLL}</button>
          <button type="button" className={`acoin ${cornerMenu === "game" ? "on" : ""}`} style={{ left: ARENA.menu.x - 14, top: T(ARENA.menu.y) - 14 }} aria-label="Game menu" onClick={() => setCornerMenu(cornerMenu === "game" ? undefined : "game")}>{GEAR}</button>
        </div>

        {caption && !showBrowser ? <div className="aprompt notice" style={{ top: Y(ARENA.captionY) }}><span>{caption}</span></div> : <>
          {promptLine && <div className="aprompt" style={{ top: Y(ARENA.captionY) }}><span><RulesText text={promptLine} /></span></div>}
          {thinkingName && <div className="aprompt" style={{ top: Y(ARENA.captionY), opacity: 0.75 }}>{thinkingName} is thinking…</div>}
        </>}
        {showBanner && fx.banner && (
          <div key={fx.banner.key} className={`abanner ${fx.banner.mine ? "mine" : "theirs"} ${fxClock >= fx.banner.end ? "out" : ""}`} style={{ top: Y(ARENA.captionY) - 20 }}
            role="status" aria-label={`${fx.banner.mine ? "Your turn" : `${fx.banner.name ?? "Opponent"}’s turn`}, turn ${snapshot?.turn ?? ""}`}>
            <i className="line" /><i className="glow" />
            <b data-text={fx.banner.mine ? "Your turn" : `${fx.banner.name ?? "Opponent"}’s turn`}>{fx.banner.mine ? "Your turn" : `${fx.banner.name ?? "Opponent"}’s turn`}</b>
          </div>
        )}

        {menu && (
          <div className="amenu glass" style={{ left: Math.min(STAGE.width - 260, Math.max(10, menu.at.x - 125)), top: Math.max(10, menu.at.y - menu.at.h / 2 - 12 - 46 * (menu.actions.length + 1)), right: "auto" }}
            onClick={stop}>
            {menu.actions.map((action) => <button key={action.id} type="button" className="arow" onClick={() => sendAction(action)}>{EngineDisplayText.label(action.label)}</button>)}
            <button type="button" className="arow" onClick={() => setMenu(undefined)}>Cancel</button>
          </div>
        )}

        {playerCard && snapshot && (() => {
          // ArenaPlayerCard: portrait, name and life; each status in words; the zones with their counts, lit where you
          // can play from; the named exile zones and revealed cards.
          const player = snapshot.players.find((p) => p.playerId === playerCard);
          if (!player) return null;
          const mine = player.playerId === viewer;
          const name = mine ? "You" : player.displayName ?? "Opponent";
          const lit: ReadonlySet<string> = mine && !pending ? castableZones(player, snapshot) : new Set();
          const zones = player.zones;
          const label = (zoneTitle: string) => (mine ? zoneTitle : `${player.displayName ?? "Opponent"} · ${zoneTitle}`);
          const icons = [
            ...(zones.command.length > 0 || (player.commanders ?? []).length > 0 ? [{ key: "command", name: "Command", glyph: ZONE_GLYPHS.command, cards: zones.command, count: zones.command.length }] : []),
            { key: "graveyard", name: "Graveyard", glyph: ZONE_GLYPHS.graveyard, cards: zones.graveyard, count: zones.graveyard.length },
            { key: "exile", name: "Exile", glyph: ZONE_GLYPHS.exile, cards: zones.exile, count: zones.exile.length },
            { key: "library", name: "Library", glyph: ZONE_GLYPHS.library, cards: zones.library, count: zones.libraryCount ?? zones.library.length },
            ...(!mine ? [{ key: "hand", name: "Hand", glyph: ZONE_GLYPHS.hand, cards: zones.hand, count: zones.handCount ?? zones.hand.length }] : []),
          ].filter((icon) => icon.count > 0 || icon.key === "command" || icon.key === "library");
          const named = snapshot.xmage ? ([["exileZones", "Exile"], ["companion", "Companion"], ["revealed", "Revealed"], ["lookedAt", "Looked at"]] as const)
            .flatMap(([kind, title]) => snapshot.xmage![kind].map((group) => ({ id: `${kind}-${group.id}`, title: EngineDisplayText.label(group.name ?? "", title), cards: group.cards }))) : [];
          const badges = orbitOrder(statusBadges(player, snapshot));
          return (
            <div className="aplayercard glass" style={mine ? { left: 40, bottom: geo.height - B(330) } : { left: 520, top: T(60) }} onClick={stop}
              role="dialog" aria-label={`${name}’s card`}>
              <header>
                <div className="portrait"><Portrait player={player} viewer={mine} /></div>
                <div><b>{name}</b><small>{isOut(player) ? "Out of the game" : `${player.life} life`}</small></div>
                <button type="button" className="close" aria-label={`Close ${name}’s card`} onClick={() => setPlayerCard(undefined)}>✕</button>
              </header>
              {badges.length > 0 && (
                <div className="statuses">{badges.map((badge) => (
                  <div key={badge.id} className={badge.nearLethal ? "lethal" : ""}><StatusBadge badge={badge} size={26} /><span>{badge.label}</span></div>
                ))}</div>
              )}
              {(() => {
                const seat = seatOf(player);
                if (mine || !showMic || voiceState.stage !== "live" || seat === undefined || !voiceState.inVoice.includes(seat)) return null;
                const silenced = voiceState.silenced.includes(seat);
                return (
                  <button type="button" className="aplaque secondary inline avoicemute" data-id="board.voice.silence"
                    onClick={() => voice?.silence(seat, !silenced)}>{silenced ? "Unmute Voice" : "Mute Voice"}</button>
                );
              })()}
              <div className="zonegrid">{icons.map((icon) => {
                const on = lit.has(icon.key);
                return (
                  <button key={icon.key} type="button" className={on ? "lit" : ""} aria-label={on ? `${icon.name}, ${icon.count}, you can play from it` : `${icon.name}, ${icon.count}`}
                    onClick={() => {
                      setPlayerCard(undefined);
                      if (icon.key === "command") setCommanderView(player.playerId);
                      else setZone({ title: label(icon.key === "library" ? (icon.cards.length > 0 ? "Library · revealed top card" : "Library") : icon.key === "hand" ? "Hand — visible cards" : icon.name), cards: icon.cards });
                    }}>
                    {icon.glyph}<b>{icon.count}</b><small>{icon.name.toUpperCase()}</small>
                  </button>
                );
              })}</div>
              {named.length > 0 && (
                <div className="named">{named.map((zone) => (
                  <button key={zone.id} type="button" onClick={() => { setPlayerCard(undefined); setZone({ title: zone.title, cards: zone.cards }); }}>
                    <span>{zone.title}</span><b>{zone.cards.length}</b>
                  </button>
                ))}</div>
              )}
            </div>
          );
        })()}

        {cornerMenu && (
          // The gear's menu under the gear; the skip choices above the corner. A click anywhere else closes it.
          <MenuCard items={cornerMenu === "game" ? gameItems : passItems} close={() => setCornerMenu(undefined)}
            style={cornerMenu === "game" ? { right: STAGE.width - ARENA.menu.x - 8, top: T(ARENA.menu.y) + 26 } : { right: 14, bottom: geo.height - Y(326) }} />
        )}
        {sheet === "stops" && (
          <Panel title="Phase Stops" close={() => setSheet(undefined)}><PhaseStops settings={smartSettings} onChange={updateSmartPass} /></Panel>
        )}
        {sheet === "actions" && snapshot && (
          <Panel title="More actions" close={() => setSheet(undefined)}>
            <div className="amore">
              {(snapshot.legalActions ?? []).map((action) => {
                const source = action.cardInstanceId ?? action.sourceInstanceId;
                const card = source ? snapshot.players.flatMap((p) => [...p.zones.battlefield, ...p.zones.hand, ...p.zones.graveyard, ...p.zones.exile, ...p.zones.command]).find((c) => c.instanceId === source) : undefined;
                return (
                  <button key={action.id} type="button" className="arow" disabled={pending} onClick={() => { setSheet(undefined); sendAction(action); }}>
                    <span><b><RulesText text={EngineDisplayText.label(action.label)} /></b>{card && <small>{card.card.name}</small>}</span>
                  </button>
                );
              })}
            </div>
          </Panel>
        )}
        {sheet === "settings" && (
          <Panel title="Game Settings" close={() => setSheet(undefined)}>
            <div className="asettings">
              <label><Check on={smartSettings.enabled} label="Smart Auto-Pass" onToggle={() => updateSmartPass({ ...smartSettings, enabled: !smartSettings.enabled })} />Smart Auto-Pass</label>
              <label><Check on={smartSettings.stopForThreats} label="Stop for Removal" onToggle={() => updateSmartPass({ ...smartSettings, stopForThreats: !smartSettings.stopForThreats })} />Stop for Removal</label>
              <label><Check on={smartSettings.stopForOwnSpells} label="Stop for My Own Spells" onToggle={() => updateSmartPass({ ...smartSettings, stopForOwnSpells: !smartSettings.stopForOwnSpells })} />Stop for My Own Spells</label>
              {session?.supportedAnswerActions.has("autoPassAfterCast") && (
                <label><Check on={passAfterCast} label="Pass After Casting" onToggle={() => {
                  const on = !passAfterCast; setPassAfterCast(on); storage.set("mm.web.autoPassAfterCast", on ? "on" : "off"); session.setAutoPassAfterCast(on);
                }} />Pass After Casting</label>
              )}
              <label><Check on={soundsOn} label="Sounds" onToggle={() => { const on = !soundsOn; setSoundsOn(on); storage.set(SOUND_KEYS.effects, on ? "on" : "off"); }} />Sounds</label>
              <label><Check on={frames} label="Card Frames" onToggle={() => { const on = !frames; setFrames(on); storage.set("mm.web.cardFrames", on ? "on" : "off"); }} />Card Frames</label>
              <label><Check on={pushToTalk} label="Push to Talk" onToggle={() => { const on = !pushToTalk; setPushToTalk(on); storage.set(PUSH_TO_TALK_KEY, on ? "on" : "off"); }} />Push to Talk</label>
              {pushToTalk && <TalkKeyButton code={talkKey} id="settings.talkKey" onChange={(code) => { setTalkKey(code); storage.set(PUSH_TO_TALK_BIND_KEY, code); }} />}
              <div className="seg" role="group" aria-label="Game speed"><span>Game speed</span>
                {GAME_SPEEDS.map((value) => (
                  <button key={value} type="button" aria-pressed={speed === value} onClick={() => { setSpeed(value); storage.set(GAME_SPEED_KEY, value); }}>
                    {GAME_SPEED_TITLES[value]}
                  </button>
                ))}
              </div>
              <div className="seg" role="group" aria-label="Effects"><span>Effects</span>
                {(["full", "reduced", "off"] as const).map((level) => (
                  <button key={level} type="button" aria-pressed={fxSetting === level} onClick={() => { setFxSetting(level); storage.set("mm.web.boardEffects", level); }}>
                    {({ full: "Full", reduced: "Reduced", off: "Off" })[level]}
                  </button>
                ))}
              </div>
              {session && (session.state.rememberedAnswers > 0 || session.state.rememberedTriggerOrders > 0) && (
                <div className="actions">
                  {session.state.rememberedAnswers > 0 && (
                    <button type="button" className="aplaque secondary inline" onClick={() => session.forgetRememberedAnswers()}>Ask Again ({session.state.rememberedAnswers} answered)</button>
                  )}
                  {session.state.rememberedTriggerOrders > 0 && (
                    <button type="button" className="aplaque secondary inline" onClick={() => session.forgetTriggerOrder()}>Ask Trigger Order Again</button>
                  )}
                </div>
              )}
              <div className="actions">
                <button type="button" className="aplaque danger inline" disabled={!session || finished} onClick={() => { setSheet(undefined); setConfirmConcede(true); }}>Concede</button>
                <button type="button" className="aplaque secondary inline" onClick={() => table.leave()}>{table.solo ? "Quit" : "Leave Table"}</button>
              </div>
            </div>
          </Panel>
        )}

        {panel && (
          <div className="apanel glass" onClick={stop}>
            <header>
              {table.solo ? <h3>Game Log</h3> : (
                <div className="tabs" style={{ flex: 1 }}>
                  <button type="button" aria-pressed={panel === "log"} onClick={() => setPanel("log")}>Game Log</button>
                  <button type="button" aria-pressed={panel === "chat"} onClick={() => setPanel("chat")}>Chat</button>
                </div>
              )}
              <button type="button" className="close" aria-label="Close" onClick={() => setPanel(undefined)}>✕</button>
            </header>
            {panel === "log" ? (
              // The public log names a printed card, not a lookup of that object's current (possibly hidden) state.
              <GameLog log={log} reasons={logReasons} inspect={(reference) => setReading({ name: reference.name })} />
            ) : (
              <>
                <ol className="alog chat">{table.state.chat.map((line) => (
                  <li key={line.id} className={line.isLocal ? "local" : ""}><span className="who">{line.name}:</span> {line.isLocal ? line.text : TableChatFilter.filtered(line.text)}</li>
                ))}</ol>
                <ChatInput table={table} />
              </>
            )}
          </div>
        )}

        {showBrowser && snapshot && envelope && (
          <div onClick={stop}>
            <Browser key={`${envelope.id}:${envelope.messageId}`} kind={browser} snapshot={snapshot} envelope={envelope} send={send} sendAction={sendAction}
              pending={pending} height={geo.height} inspect={reader} answerActions={session?.supportedAnswerActions} orderTriggers={orderTriggers}
              commitPlan={session ? commitPlan : undefined} />
          </div>
        )}
        {amountPill && snapshot && envelope && (() => {
          // The pill where the secondary plaque sits, Cancel under it where the primary does (the reference's corner).
          const cancel = promptActions.some((a) => a.type !== "choose_amount" && a.type !== "play_x_mana");
          return (
            <AmountPill key={`${envelope.id}:${envelope.messageId}`} snapshot={snapshot} envelope={envelope} send={send} sendAction={sendAction} pending={pending}
              x={Math.min(STAGE.width - 142, Math.max(142, ARENA.primary.x + ARENA.primary.w / 2))}
              y={B(ARENA.secondary.y + ARENA.secondary.h / 2 + (cancel ? 24 : 0))} />
          );
        })()}

        {mulligan && envelope?.confirmation && !showRoll && snapshot && (
          // The opening hand, Arena's mulligan screen (OpeningHandOverlay, Arena look): who goes first over a thin rule,
          // XMage's question under it, the fanned hand, the blue Mulligan pill beside the orange Keep, words only.
          <div className="amull" onClick={stop}>
            <div className="head" style={{ top: geo.height / 2 - 182 }}>
              <h2>{startingPlayerHeading(snapshot) ?? "Opening Hand"}</h2>
              <i />
              <p>{cleanMessage(envelope.message)}</p>
            </div>
            <div className="choices" style={{ top: geo.height / 2 + 110 }}>
              <button type="button" className="aplaque cool" disabled={pending} data-id="board.opening.mulligan"
                onClick={() => { gameAudio.play("shuffle"); send({ type: "answer_yes_no", confirmed: true }, envelope.confirmation?.yesLabel ?? "Mulligan"); }}>{envelope.confirmation.yesLabel ?? "Mulligan"}</button>
              <button type="button" className="aplaque primary" disabled={pending} data-id="board.opening.keep"
                onClick={() => send({ type: "answer_yes_no", confirmed: false }, envelope.confirmation?.noLabel ?? "Keep")}>{envelope.confirmation.noLabel ?? "Keep"}</button>
            </div>
          </div>
        )}

        {reading && snapshot && (
          <Inspector card={reading.card} name={reading.name} battlefield={snapshot.players.flatMap((p) => p.zones.battlefield)} height={geo.height}
            holding={reading.held} close={() => setReading(undefined)} />
        )}
        {stackOpen && snapshot && (
          <div onClick={stop}>
            <StackBrowser snapshot={snapshot} height={geo.height} inspect={reader} close={() => setStackOpen(false)}
              resolveAll={secondary?.label === "Resolve All" ? secondary.onClick : undefined}
              stopSkipping={skipping && session ? () => session.stopAutoPass() : undefined} />
          </div>
        )}

        {zone && snapshot && (
          <div onClick={stop}>
            <ZoneBrowser title={zone.title} cards={zone.cards} snapshot={snapshot} pending={pending} sendAction={sendAction} height={geo.height}
              inspect={reader} close={() => setZone(undefined)} targetIDs={targetIDs}
              chooseTarget={envelope ? (card) => send({ type: "choose_target", targetIds: [card.instanceId] }, card.card.name) : undefined} />
          </div>
        )}

        {commanderView && snapshot && (() => {
          const player = snapshot.players.find((p) => p.playerId === commanderView);
          return player && (
            <div onClick={stop}>
              <CommanderBrowser player={player} snapshot={snapshot} pending={pending} sendAction={sendAction} height={geo.height} inspect={reader}
                close={() => setCommanderView(undefined)} />
            </div>
          );
        })()}

        {versusSeats && <VersusIntro you={versusSeats.you} opponents={versusSeats.opponents} finished={() => setVersusShown(false)} />}

        {showRoll && roll && (() => {
          // The starting roll on the board (MultiplayerD20View, Arena look): the board dimmed to 0.8, one large serif line,
          // the roll or what it waits for, and glass seat plates above the hand ("?" before a seat rolls, orange for the winner).
          const name = (seat: string) => (seat === table.state.localSeatID ? "You" : table.state.seatNames[seat] ?? "Player");
          const next = roll.nextSeatID;
          const winner = roll.roll.winnerSeatID;
          const headline = next === undefined ? (winner === table.state.localSeatID ? "You go first" : `${name(winner)} goes first`)
            : next === table.state.localSeatID ? "Your roll" : `${table.state.seatNames[next] ?? "Player"}’s roll`;
          const last = roll.revealed > 0 ? roll.roll.steps[roll.revealed - 1] : undefined;
          return (
            <div className="aroll" onClick={stop} role="dialog" aria-label="Who goes first">
              <h2>{headline}</h2>
              {/* The dice's room on iOS (0.3 of the height); the web rolls no 3D dice, so the room stays empty. */}
              <div className="rollcontrol" style={{ marginTop: Math.max(100, geo.height * 0.3) }}>
                {next === table.state.localSeatID ? (
                  <button type="button" className="aplaque primary" disabled={roll.hasRolled || table.state.stage !== "playing"} data-id="multiplayerD20.tapToRoll"
                    onClick={() => { try { gameAudio.play("dice-roll"); table.rollStartingPlayer(); } catch (error) { fail(error); } }}>
                    {roll.hasRolled ? "Sharing your roll…" : "Roll D20"}</button>
                ) : next !== undefined ? <span className="chip waiting">Waiting for {table.state.seatNames[next] ?? "the next player"} to roll…</span>
                  : last && <span className="chip">Rolled {last.value}</span>}
              </div>
              <div className="plates">
                {rollPlates(roll.roll, roll.revealed).map((plate) => (
                  <div key={plate.seatID} className={`plate ${plate.winner ? "won" : ""} ${plate.out ? "out" : ""}`} data-id={`multiplayerD20.seat.${plate.seatID}`}>
                    <i className={`value ${plate.value === undefined ? "none" : ""}`} aria-hidden="true">{plate.value ?? "?"}</i>
                    <span><b>{table.state.seatNames[plate.seatID] ?? "Player"}</b>
                      <small>{plate.winner && plate.value !== undefined ? `Rolled ${plate.value} · Goes first` : plate.out ? "Out of the reroll"
                        : plate.value === undefined ? "Ready" : plate.tied ? "Tied · reroll" : `Rolled ${plate.value}`}</small></span>
                  </div>
                ))}
              </div>
            </div>
          );
        })()}

        {confirmConcede && (
          <div className="aoverlay question" onClick={stop}>
            <div className="aquestion glass">
              <h2>Concede?</h2>
              <p>{table.solo ? "The AI wins this game." : "You leave this game. The other players are told at once."}</p>
              <div style={{ display: "flex", gap: 12 }}>
                <button type="button" className="aplaque secondary" onClick={() => setConfirmConcede(false)}>Keep playing</button>
                <button type="button" className="aplaque danger" onClick={() => { setConfirmConcede(false); table.concede().catch(fail); }}>Concede</button>
              </div>
            </div>
          </div>
        )}

        {(finished || table.state.stage === "failed") && (
          // The result, Arena's (ArenaGameResultView): the word on its flare, then your medallion, rank, numbers and the ways on.
          <GameResult snapshot={snapshot} me={me} finished={finished} stoppedTitle={table.solo ? "Game stopped" : "Table closed"}
            stoppedLine={table.state.status} numbers={stats.current} rankChange={rankChange} rankNote={rankNote}
            rematch={table.rematch ? () => table.rematch?.() : undefined} rematchTitle={lesson?.nextTitle} leave={() => table.leave()} />
        )}

        {lesson && !finished && (lesson.run.coach || lesson.run.complete) && <LessonCoachCard table={lesson} />}

        {(() => {
          // The recovery banner (OnDeviceRootView.recoveryBanner): what went wrong, and Refresh, Retry response, Leave.
          const sticky = session?.state.errorMessage && session.state.errorMessage !== dismissedError ? session.state.errorMessage : undefined;
          const message = bannerError ?? sticky;
          const waiting = table.state.isSuspended || table.state.reconnecting;
          if (!message && !waiting) return null;
          return (
            <div className="arecovery" role="alert" onClick={stop}>
              {message ? (
                <div className="line">
                  <span>{message}</span>
                  <button type="button" className="seal" aria-label="Dismiss notification"
                    onClick={() => { if (message === session?.state.errorMessage) setDismissedError(message); setBannerError(undefined); }}>✕</button>
                </div>
              ) : <div className="line"><span>{table.state.status}</span></div>}
              {!message && table.state.continueVote && (
                // Everyone still at the table may vote to go on without a player who is away (TableLeaveRules).
                <div className="actions">
                  <button type="button" className="aplaque primary inline" data-id="ondevice.continueWithout" disabled={table.state.continueVote.voted}
                    onClick={() => table.voteToContinue?.()}>
                    {table.state.continueVote.voted
                      ? `Waiting for the others (${table.state.continueVote.voters.length}/${table.state.continueVote.needed})`
                      : TableLeaveRules.buttonTitle(table.state.continueVote)}
                  </button>
                </div>
              )}
              <div className="actions">
                {session && <button type="button" className="aplaque primary inline" disabled={session.state.working} onClick={() => { session.refresh().catch(fail); }}>Refresh</button>}
                {session?.hasPending && (
                  <button type="button" className="aplaque secondary inline" disabled={session.state.working} onClick={() => { session.retryPending().catch(fail); }}>Retry response</button>
                )}
                <button type="button" className="aplaque danger inline" onClick={() => table.leave()}>Leave</button>
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
}


function ChatInput({ table }: { table: GameTable }) {
  const [text, setText] = useState("");
  return (
    <>
      <form className="chat-input" onSubmit={(event) => { event.preventDefault(); table.sendChat(text); setText(""); }}>
        <input className="bsearch" value={text} maxLength={400} onChange={(e) => setText(e.target.value)} placeholder="Say something" aria-label="Chat message" />
        <button type="submit" className="aplaque primary">Send</button>
      </form>
      <div className="emotes">
        {GameEmotes.map((emote) => <button key={emote.raw} type="button" onClick={() => { gameAudio.play("emote"); table.sendEmote(emote); }}>{emote.text}</button>)}
      </div>
    </>
  );
}
