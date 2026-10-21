/**
 * The game on the horizontal Arena board (docs/ARENA_STYLE.md; the Duel Board Prototype's landscape table, artifact
 * T5NcAkjCThiA5hfd9Twwwu): the Walnut Tavern plate scaled to the window, every card a table object, the decision in
 * the corner plaques or on the table, and anything else in a full-table glass browser. Solo games and relay tables
 * share it; both answer through the same GuestSession.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { EngineDisplayText } from "../core/displayText";
import { type GameSnapshot, isCompleted, isOut, type LegalAction, type PlayerGameState, thinkingPlayerID, type ZoneCard } from "../core/models";
import { defaultSmartPass } from "../core/smartPass";
import { GameEmotes, TableChatFilter } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { useTable } from "./App";
import { ArenaCard, type ArenaCardProps } from "./arena/ArenaCard";
import { Browser, browserKind, type Send } from "./arena/Browsers";
import {
  BASE_GEOMETRY, battlefieldPlaces, geometry, type Geometry, handPlaces, mulliganPlaces, opponentHandPlaces, phaseStrip, type Place, POOL, POS, SIZE,
  stackPlace, STAGE, TILT,
} from "./arena/layout";
import "./arena/arena.css";
import { cardImageURL } from "./cardArt";

const AVATAR = {
  me: (
    <svg viewBox="0 0 100 100" aria-hidden="true">
      <defs><radialGradient id="avMe" cx=".5" cy=".75" r=".8"><stop offset="0" stopColor="#ffb36a" /><stop offset=".55" stopColor="#8a2a12" /><stop offset="1" stopColor="#2a0c06" /></radialGradient></defs>
      <rect width="100" height="100" fill="url(#avMe)" /><path d="M50 18c-18 0-28 16-28 34v48h56V52c0-18-10-34-28-34z" fill="#1b0c06" />
      <path d="M50 30c-9 0-15 10-15 21h30c0-11-6-21-15-21z" fill="#2c140a" /><circle cx="44" cy="50" r="2.6" fill="#ffb070" /><circle cx="56" cy="50" r="2.6" fill="#ffb070" />
      <circle cx="50" cy="86" r="5" fill="#ff8a3d" opacity=".8" />
    </svg>
  ),
  opp: (
    <svg viewBox="0 0 100 100" aria-hidden="true">
      <defs><radialGradient id="avOpp" cx=".5" cy=".65" r=".8"><stop offset="0" stopColor="#a8dcff" /><stop offset=".55" stopColor="#2a5a96" /><stop offset="1" stopColor="#0a1830" /></radialGradient></defs>
      <rect width="100" height="100" fill="url(#avOpp)" /><path d="M24 100c2-18 12-26 26-26s24 8 26 26z" fill="#0b1b33" /><circle cx="50" cy="52" r="16" fill="#0b1b33" />
      <path d="M33 38l6 10 11-12 11 12 6-10v12H33z" fill="#dba34c" /><circle cx="44" cy="53" r="2.2" fill="#c8eaff" /><circle cx="56" cy="53" r="2.2" fill="#c8eaff" />
    </svg>
  ),
};
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

interface Plaque { label: string; style: "ember" | "leather" | "label" | "oxblood"; want?: boolean; onClick?: () => void }

export function GameScreen({ table }: { table: GameTable }) {
  useTable(table);
  const session = table.session;
  const snapshot = session?.state.snapshot;
  const wrapRef = useRef<HTMLDivElement>(null);
  const geo = useGeometry(wrapRef);
  /** Plate points to board points: in proportion (the middle), from the top edge (theirs), from the bottom edge (yours). */
  const Y = (y: number) => y * geo.ky;
  const T = (y: number) => y * geo.grow;
  const B = (y: number) => geo.height - (STAGE.height - y) * geo.grow;
  const [hovered, setHovered] = useState<string>();
  const [menu, setMenu] = useState<{ id: string; at: Place; actions: LegalAction[] }>();
  const [toast, setToast] = useState<string>();
  const [panel, setPanel] = useState<"log" | "chat">();
  const [gear, setGear] = useState(false);
  const [zone, setZone] = useState<{ title: string; cards: ZoneCard[] }>();
  const [playerCard, setPlayerCard] = useState<string>();
  const [confirmConcede, setConfirmConcede] = useState(false);
  const [rollDismissed, setRollDismissed] = useState(false);
  const [steppedAside, setSteppedAside] = useState<string>();
  const [smart, setSmart] = useState(session?.smartPass?.enabled ?? false);
  const [, setClockTick] = useState(0);
  useEffect(() => { setSmart(session?.smartPass?.enabled ?? false); }, [session]);
  // Development only: the table, for checking a game from the console.
  useEffect(() => { if (import.meta.env.DEV) Object.assign(window, { __mm: { table } }); }, [table]);

  const viewer = snapshot?.viewerPlayerId;
  const me = snapshot?.players.find((p) => p.playerId === viewer);
  const opponents = useMemo(() => snapshot?.players.filter((p) => p.playerId !== viewer) ?? [], [snapshot, viewer]);
  const pending = session?.state.pendingActionID !== undefined || session?.state.working === true;
  const envelope = snapshot?.promptEnvelopeV2;
  const finished = snapshot !== undefined && isCompleted(snapshot);
  const targetIDs = new Set([...(envelope?.targetIds ?? []), ...(envelope?.targets ?? []).map((t) => t.id)]);
  const combatSelect = envelope?.method === "GAME_SELECT" && envelope?.responseKind === "target";
  const paying = snapshot?.manaPayment?.active === true;
  const activeIsMe = snapshot?.activePlayerId !== undefined && snapshot.activePlayerId === viewer;
  const stack = snapshot?.xmage?.stack ?? [];
  const promptActions = (snapshot?.legalActions ?? []).filter((a) => a.cardInstanceId === undefined && a.sourceInstanceId === undefined);

  const fail = useCallback((error: unknown) => {
    setToast(error instanceof Error ? error.message : String(error));
    window.setTimeout(() => setToast(undefined), 4000);
  }, []);
  const send: Send = useCallback((partial, label) => {
    if (!session || !snapshot || !envelope) return;
    session.submit({
      ...partial, gameId: snapshot.id, playerId: snapshot.viewerPlayerId!, promptId: envelope.id, messageId: envelope.messageId,
    } as never, label, `${envelope.id}:${partial.type}:${label}`).catch(fail);
  }, [session, snapshot, envelope, fail]);
  const sendAction = useCallback((action: LegalAction) => { setMenu(undefined); session?.send(action).catch(fail); }, [session, fail]);

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
  const rawBrowser = browserKind(envelope, onTable);
  const browser = rawBrowser === "players" && table.state.roll !== undefined ? undefined : rawBrowser;
  const showBrowser = browser !== undefined && browser !== "mulligan" && steppedAside !== envelope?.id && !pending;

  /** A click on a card: answer a target or combat question with it, or offer its legal actions. */
  const clickCard = (id: string, at?: Place) => {
    if (!snapshot || pending || finished) return;
    setMenu(undefined);
    if (targetIDs.has(id)) { send({ type: "choose_target", targetIds: [id] }, "Choose"); return; }
    const actions = actionsFor(snapshot, id);
    if (actions.length === 1) sendAction(actions[0]);
    else if (actions.length > 1 && at) setMenu({ id, at, actions });
  };

  // ---------------- cards ----------------
  const handIDs = me?.zones.hand.map((c) => c.instanceId) ?? [];
  const mulligan = browser === "mulligan";
  const handPlayable = snapshot !== undefined && (me?.zones.hand ?? []).some((c) => actionsFor(snapshot, c.instanceId).length > 0 || targetIDs.has(c.instanceId));
  const handUp = mulligan || (envelope !== undefined && !pending && handPlayable && !paying);
  const cards = new Map<string, ArenaCardProps>();
  const add = (props: ArenaCardProps) => { if (!cards.has(props.id)) cards.set(props.id, props); };
  const classFor = (card: ZoneCard, onBattlefield: boolean) => {
    const list: string[] = [];
    if (onBattlefield && card.tapped) list.push("tapped");
    if (onBattlefield && card.isAttacking) list.push("atk");
    if (onBattlefield && (card.blocking?.length ?? 0) > 0) list.push("blk");
    if (targetIDs.has(card.instanceId)) list.push(combatSelect ? "can-act" : "targetable");
    else if (!pending && snapshot && envelope) {
      const actions = actionsFor(snapshot, card.instanceId);
      if (paying) { if (actions.some((a) => a.type === "make_mana")) list.push("payable"); }
      else if (actions.some((a) => a.type !== "make_mana")) list.push("playable");
    }
    return list.join(" ");
  };
  const clickAt = (place: Place) => (id: string) => clickCard(id, place);
  if (snapshot && me) {
    battlefieldPlaces(me.zones.battlefield, "me", undefined, geo).forEach((place, id) => {
      const card = me.zones.battlefield.find((c) => c.instanceId === id)!;
      add({ id, place, view: "tile", card, owner: "me", classes: classFor(card, true), onClick: clickAt(place), onHover: setHovered });
    });
    opponents.forEach((opponent, index) => {
      battlefieldPlaces(opponent.zones.battlefield, "opp", { index, count: opponents.length }, geo).forEach((place, id) => {
        const card = opponent.zones.battlefield.find((c) => c.instanceId === id)!;
        add({ id, place, view: "tile", card, owner: "opp", classes: classFor(card, true), onClick: clickAt(place), onHover: setHovered });
      });
      opponentHandPlaces(opponent.zones.handCount ?? opponent.zones.hand.length, { index, count: opponents.length }, geo).forEach((place, i) =>
        add({ id: `backs-${opponent.playerId}-${i}`, place, view: "back" }));
    });
    const handPlace = mulligan ? mulliganPlaces(handIDs, geo) : handPlaces(handIDs, handUp, hovered, geo);
    me.zones.hand.forEach((card) => {
      const place = handPlace.get(card.instanceId)!;
      add({ id: card.instanceId, place, view: "face", card, owner: "me", inHand: true, classes: classFor(card, false),
        onClick: mulligan ? undefined : clickAt(place), onHover: mulligan ? undefined : setHovered });
    });
    stack.slice(0, 4).forEach((item, depth) => {
      const name = item.sourceCard?.card.name ?? item.sourceName ?? item.name;
      add({ id: item.id, place: stackPlace(depth, geo), view: "face", name, card: item.sourceCard, label: item.name, onHover: setHovered });
    });
    const command = (player: PlayerGameState, mine: boolean, index: number) => player.zones.command.forEach((card, i) => {
      const at = mine ? POS.cmdMe : POS.cmdOpp;
      const base = mine ? SIZE.pile : SIZE.opile;
      const size = { w: base.w * geo.grow, h: base.h * geo.grow };
      const x = mine ? at.x - i * 48 : at.x + i * 42 + (opponents.length > 1 ? -index * 90 : 0);
      const place: Place = { x, y: mine ? B(at.y) : T(at.y), ...size, r: 0, s: 1, tx: mine ? TILT : 0, z: 12 };
      add({ id: card.instanceId, place, view: "face", card, owner: mine ? "me" : "opp", classes: classFor(card, false), onClick: mine ? clickAt(place) : undefined, onHover: setHovered });
    });
    command(me, true, 0);
    opponents.forEach((opponent, index) => command(opponent, false, index));
  }

  // ---------------- corner controls ----------------
  const myCreatures = me?.zones.battlefield ?? [];
  let primary: Plaque | undefined;
  let secondary: Plaque | undefined;
  if (snapshot && !finished && envelope && !showBrowser && !mulligan) {
    const act = (action: LegalAction | undefined, style: Plaque["style"], label?: string, want = false): Plaque | undefined =>
      action && { label: label ?? EngineDisplayText.label(action.label), style, want, onClick: () => sendAction(action) };
    if (envelope.responseKind === "priority") {
      primary = act(promptActions.find((a) => a.type === "pass_priority"), "ember", stack.length > 0 ? "Resolve" : "Pass", true);
    } else if (combatSelect) {
      const attacking = /attack/i.test(envelope.message);
      const declared = attacking ? myCreatures.some((c) => c.isAttacking) : myCreatures.some((c) => (c.blocking?.length ?? 0) > 0);
      primary = act(promptActions.find((a) => a.type === "answer_yes_no"), "ember", attacking ? (declared ? "Attack" : "No Attacks") : (declared ? "Done" : "No Blocks"), true);
      secondary = act(promptActions.find((a) => a.type === "resolve_choice"), "leather");
    } else if (paying) {
      primary = act(promptActions.find((a) => a.type === "cancel_payment"), "leather", "Cancel");
      secondary = act(promptActions.find((a) => a.type === "resolve_choice"), "leather");
    } else {
      const confirming = (a: LegalAction) => Number(a.type === "answer_yes_no" && a.confirmed === true);
      const ordered = [...promptActions].sort((a, b) => confirming(b) - confirming(a));
      primary = act(ordered[0], "ember", undefined, true);
      secondary = act(ordered[1], "leather");
    }
  } else if (snapshot && !finished && !envelope) {
    primary = { label: activeIsMe ? "Resolving…" : "Opponent’s Turn", style: "label" };
  }
  const strip = phaseStrip(snapshot?.step);
  const promptLine = snapshot && envelope && !showBrowser && !mulligan && envelope.responseKind !== "priority"
    ? cleanMessage(paying ? snapshot.manaPayment?.remainingText ?? envelope.message : envelope.message) : !snapshot ? table.state.status : undefined;
  const thinking = snapshot && !envelope && !finished ? thinkingPlayerID(snapshot) : undefined;
  const thinkingName = thinking && thinking !== viewer ? snapshot?.players.find((p) => p.playerId === thinking)?.displayName : undefined;

  // ---------------- the starting roll, the result ----------------
  const roll = table.state.roll;
  const showRoll = roll !== undefined && !rollDismissed &&
    (roll.nextSeatID !== undefined || !snapshot || (snapshot.turn <= 1 && !envelope?.message.toLowerCase().includes("mulligan")));
  useEffect(() => {
    if (roll && roll.nextSeatID === undefined) { const t = window.setTimeout(() => setRollDismissed(true), 3500); return () => window.clearTimeout(t); }
  }, [roll?.nextSeatID, roll]);
  const won = finished && viewer !== undefined && (snapshot!.winnerPlayerIds ?? []).includes(viewer);

  // The relay's turn clock burns its rope smoothly.
  const rope = table.state.turnClock.rope(table.state.localSeatID, performance.now() / 1000);
  useEffect(() => {
    if (!rope) return;
    const timer = window.setInterval(() => setClockTick((t) => t + 1), 250);
    return () => window.clearInterval(timer);
  }, [rope]);
  const seatOf = (player: PlayerGameState) => Object.entries(table.state.seatNames).find(([, n]) => n === player.displayName)?.[0];

  const toggleSmart = () => {
    if (!session) return;
    const on = !smart;
    session.smartPass = on ? defaultSmartPass : { ...defaultSmartPass, enabled: false };
    setSmart(on);
    if (on) session.wake();
  };

  const medallion = (player: PlayerGameState, mine: boolean, index: number) => {
    const at = mine ? { x: POS.faceMe.x, y: B(POS.faceMe.y) }
      : { x: opponents.length > 1 ? 170 + (560 * (index + 0.5)) / opponents.length : POS.faceOpp.x, y: Y(POS.faceOpp.y + 3) };
    const d = (mine ? 58 : 50) * geo.grow;
    const targetable = targetIDs.has(player.playerId) && !pending;
    const seat = seatOf(player);
    const clock = rope && rope.seat === seat ? rope : undefined;
    const bubble = seat ? table.state.bubbles[seat] : undefined;
    const circumference = Math.PI * 2 * 46;
    return (
      <div key={player.playerId}>
        <button type="button" className={`amed ${targetable ? "targetable" : ""} ${isOut(player) ? "out" : ""}`}
          style={{ left: at.x, top: at.y, ["--d" as string]: `${d}px` }} aria-label={`${mine ? "You" : player.displayName ?? "Opponent"}, ${player.life} life`}
          onClick={(event) => {
            event.stopPropagation();
            if (targetable) send({ type: "choose_target", targetIds: [player.playerId] }, player.displayName ?? "Player");
            else setPlayerCard(playerCard === player.playerId ? undefined : player.playerId);
          }}>
          <div className="av">{mine ? AVATAR.me : AVATAR.opp}</div>
          <span className="hp">{Math.max(0, player.life)}</span>
          {clock && (
            <svg className="rope" viewBox="0 0 100 100" aria-hidden="true">
              <circle cx="50" cy="50" r="46" fill="none" stroke={clock.strikes > 0 ? "#ff5a2e" : "#ffb36a"} strokeWidth="5" strokeLinecap="round"
                strokeDasharray={`${circumference * clock.fraction} ${circumference}`} transform="rotate(-90 50 50)" />
            </svg>
          )}
        </button>
        {!mine && (
          <div className="aname" style={{ left: at.x + d / 2 + 8, top: at.y }}>
            {player.displayName}{isOut(player) ? " (left)" : ""}
            <small>Hand {player.zones.handCount ?? player.zones.hand.length} · Library {player.zones.libraryCount ?? 0}</small>
            {(player.poison > 0 || player.monarch) && <div className="badges">{player.poison > 0 && <span>Poison {player.poison}</span>}{player.monarch && <span>Monarch</span>}</div>}
          </div>
        )}
        {bubble && Date.now() - bubble.at < 3200 && <div key={bubble.at} className="abubble" style={{ left: at.x, top: at.y - d / 2 - 4 }}>{bubble.emote.text}</div>}
      </div>
    );
  };

  const piles = (player: PlayerGameState, mine: boolean, index: number) => {
    const shift = !mine && opponents.length > 1 ? -index * 90 : 0;
    const lib = mine ? { x: POS.libMe.x, y: B(POS.libMe.y) } : { x: POS.libOpp.x + shift, y: T(POS.libOpp.y) };
    const gy = mine ? { x: POS.gyMe.x, y: B(POS.gyMe.y) } : { x: POS.gyOpp.x + shift, y: T(POS.gyOpp.y) };
    const base = mine ? SIZE.pile : SIZE.opile;
    const size = { w: base.w * geo.grow, h: base.h * geo.grow };
    const top = player.zones.graveyard.at(-1);
    const box = (at: { x: number; y: number }) => ({ left: at.x - size.w / 2, top: at.y - size.h / 2, width: size.w, height: size.h });
    const whose = mine ? "Your" : `${player.displayName ?? "Their"}’s`;
    return (
      <div key={`piles-${player.playerId}`}>
        <div className={`apile ${mine ? "" : "opp"}`} style={box(lib)} aria-label={`Library, ${player.zones.libraryCount ?? 0} cards`}>
          <div className="deck" /><span className="cnt">{player.zones.libraryCount ?? 0}</span>
        </div>
        <button type="button" className={`apile grave ${mine ? "" : "opp"}`} style={box(gy)} aria-label={`${whose} graveyard, ${player.zones.graveyard.length} cards`}
          onClick={(event) => { event.stopPropagation(); setZone({ title: `${whose} graveyard`, cards: player.zones.graveyard }); }}
          onMouseEnter={() => top && setHovered(`grave:${top.card.name}`)} onMouseLeave={() => setHovered(undefined)}>
          {top && <img src={cardImageURL(top.card.name, "normal")} alt="" crossOrigin="anonymous" />}
          {player.zones.graveyard.length > 0 && <span className="cnt">{player.zones.graveyard.length}</span>}
        </button>
      </div>
    );
  };

  // The card under the pointer, large, away from the side it sits on (never for the hand, which pops up instead).
  const inspected = (() => {
    if (!hovered || !snapshot) return undefined;
    if (hovered.startsWith("grave:")) return { name: hovered.slice(6), left: true };
    if (handIDs.includes(hovered)) return undefined;
    const item = cards.get(hovered);
    if (!item || item.view === "back") return undefined;
    return { name: item.name ?? item.card?.card.name ?? "", left: item.place.x > 560 };
  })();

  const log = snapshot?.log ?? [];
  const pool = me?.manaPool;
  const poolSymbols = pool ? (["W", "U", "B", "R", "G", "C"] as const).flatMap((s) => Array.from({ length: Math.min(pool[s], 6) }, () => s)) : [];
  const stop = (event: React.MouseEvent) => event.stopPropagation();

  return (
    <div className="arena" ref={wrapRef} onClick={() => { setGear(false); setPlayerCard(undefined); setMenu(undefined); }}>
      <div className="arena-stage" aria-label="Game table"
        style={{ height: geo.height, backgroundImage: `url(${geo.plate})`, transform: `translate(${geo.left}px, ${geo.top}px) scale(${geo.scale})` }}>
        <div className="pool-light" data-side={snapshot ? (activeIsMe ? "me" : "opp") : undefined}
          style={{ height: 220 * geo.ky, top: snapshot ? Y(activeIsMe ? 205 : 15) : undefined }} />
        <div className="lamp" />
        {me && piles(me, true, 0)}
        {opponents.map((o, i) => piles(o, false, i))}
        <div onClick={stop}>
          {[...cards.values()].map((props) => <ArenaCard key={props.id} {...props} />)}
        </div>
        {opponents.map((o, i) => medallion(o, false, i))}
        {me && medallion(me, true, 0)}
        {poolSymbols.map((symbol, i) => {
          const choice = envelope?.manaChoices?.find((c) => c.manaType === symbol);
          return (
            <button key={`${symbol}-${i}`} type="button" className={`mana-orb ${choice && !pending ? "payable" : ""}`} disabled={!choice || pending}
              style={{ left: POOL.x + i * POOL.dx, top: B(POOL.y), backgroundImage: `url(/tavern/mana-${symbol}.webp)` }} aria-label={`${symbol} mana in your pool`}
              onClick={(event) => { event.stopPropagation(); if (choice) send({ type: "play_mana", manaType: choice.manaType }, choice.label); }} />
          );
        })}
        {stack.length > 1 && (() => {
          const top = stackPlace(0, geo);
          return <div className="astack-count" style={{ left: top.x + top.w / 2 - 14, top: top.y - top.h / 2 - 8 }}>{stack.length}</div>;
        })()}

        {/* Above the raised hand while there is an answer to give (the prototype's controls z-index). */}
        <div className="acontrols" style={{ zIndex: (primary && primary.style !== "label") || secondary ? 600 : 430 }} onClick={stop}>
          <div className="aphases" data-side={activeIsMe ? "me" : "opp"} style={{ top: B(secondary ? 304 : 360) }} aria-hidden="true">
            <div className="track" />
            {strip.items.map(([key, icon]) => <span key={key} className={`aph ${icon === "dia" ? "small" : ""} ${strip.current === key ? "on" : ""}`}>{PHASE_ICONS[icon]}</span>)}
          </div>
          {secondary && <button type="button" className={`aplaque abtn2 ${secondary.style}`} style={{ top: B(335) }} disabled={pending} onClick={secondary.onClick}>{secondary.label}</button>}
          {primary ? (
            <button type="button" className={`aplaque abtn ${primary.style} ${primary.want ? "want" : ""}`} style={{ top: B(388) }} disabled={primary.style !== "label" && pending}
              onClick={primary.onClick}>{primary.label}</button>
          ) : !finished && <div className="ahourglass" style={{ top: B(388) }}>{HOURGLASS}</div>}
          {session && (
            <button type="button" className={`aff ${smart ? "on" : ""}`} style={{ top: B(392) }} aria-pressed={smart} onClick={toggleSmart}
              title={smart ? "Smart pass is on: routine priority passes by itself" : "Smart pass is off: you pass every step"}>
              <svg viewBox="0 0 26 18"><path d="M2 2l9 7-9 7zM14 2l9 7-9 7z" /></svg>
            </button>
          )}
          <button type="button" className={`acoin ${panel ? "on" : ""}`} style={{ left: 829, top: T(9) }} aria-label="Game log" onClick={() => setPanel(panel ? undefined : "log")}>{SCROLL}</button>
          <button type="button" className={`acoin ${gear ? "on" : ""}`} style={{ left: 862, top: T(9) }} aria-label="Menu" onClick={() => setGear(!gear)}>{GEAR}</button>
        </div>

        {promptLine && <div className="aprompt" style={{ top: Y(combatSelect && !/attack/i.test(envelope?.message ?? "") ? 205 : 187) }}>{promptLine}</div>}
        {thinkingName && <div className="aprompt" style={{ top: Y(187), opacity: 0.75 }}>{thinkingName} is thinking…</div>}

        {inspected && (
          <div className="ainspect" style={{
            left: inspected.left ? 250 - (POS.zoom.w * Math.min(geo.grow, 1.2)) / 2 : POS.zoom.x - (POS.zoom.w * Math.min(geo.grow, 1.2)) / 2,
            top: Math.max(6, Y(POS.zoom.y) - (POS.zoom.h * Math.min(geo.grow, 1.2)) / 2), width: POS.zoom.w * Math.min(geo.grow, 1.2),
          }}>
            <img src={cardImageURL(inspected.name, "normal")} alt={inspected.name} crossOrigin="anonymous" />
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
          const player = snapshot.players.find((p) => p.playerId === playerCard);
          if (!player) return null;
          const mine = player.playerId === viewer;
          return (
            <div className="amenu glass" style={{ left: 520, top: Y(mine ? 230 : 50), right: "auto" }} onClick={stop}>
              <h3 className="panel-title" style={{ margin: 0 }}>{mine ? "You" : player.displayName}</h3>
              <div className="small-print" style={{ color: "#efe4cf" }}>
                Life {player.life} · Hand {player.zones.handCount ?? player.zones.hand.length} · Library {player.zones.libraryCount ?? 0}<br />
                Graveyard {player.zones.graveyard.length} · Exile {player.zones.exile.length}
                {player.poison > 0 && <><br />Poison {player.poison}</>}
                {player.commanderTax > 0 && <><br />Commander tax {player.commanderTax}</>}
                {Object.entries(player.commanderDamage ?? {}).filter(([, n]) => n > 0).map(([id, n]) => <span key={id}><br />Commander damage {n}</span>)}
              </div>
              {player.zones.exile.length > 0 && (
                <button type="button" className="arow" onClick={() => setZone({ title: `${mine ? "Your" : `${player.displayName ?? "Their"}’s`} exile`, cards: player.zones.exile })}>View exile</button>
              )}
            </div>
          );
        })()}

        {gear && (
          <div className="amenu glass" onClick={stop}>
            <button type="button" className="arow" onClick={() => { setPanel("log"); setGear(false); }}>Game log</button>
            {!table.solo && <button type="button" className="arow" onClick={() => { setPanel("chat"); setGear(false); }}>Chat</button>}
            {session && (
              <button type="button" className="arow" onClick={toggleSmart}>
                <span>Smart pass: {smart ? "on" : "off"}<span className="sub">Passes routine priority; stops in your main phases, and at their attacks and end step when you can play.</span></span>
              </button>
            )}
            <button type="button" className="arow oxblood" disabled={!session || finished} onClick={() => { setConfirmConcede(true); setGear(false); }}>Concede</button>
            <button type="button" className="arow" onClick={() => table.leave()}>
              <span>{table.solo ? "Leave the game" : "Leave table"}{table.solo && !finished && <span className="sub">Concedes the game in progress.</span>}</span>
            </button>
          </div>
        )}

        {panel && (
          <div className="apanel glass" onClick={stop}>
            <header>
              {table.solo ? <h3>Game log</h3> : (
                <div className="tabs" style={{ flex: 1 }}>
                  <button type="button" aria-pressed={panel === "log"} onClick={() => setPanel("log")}>Game log</button>
                  <button type="button" aria-pressed={panel === "chat"} onClick={() => setPanel("chat")}>Chat</button>
                </div>
              )}
              <button type="button" className="close" aria-label="Close" onClick={() => setPanel(undefined)}>✕</button>
            </header>
            {panel === "log" ? (
              <ol className="alog">
                {[...log].reverse().map((entry) => {
                  const text = EngineDisplayText.text(entry.message);
                  const kind = /^TURN \d+/i.test(text) ? "turn" : entry.id.startsWith("local:auto-pass:") ? "auto" : "";
                  return <li key={entry.id} className={kind}>{text}</li>;
                })}
              </ol>
            ) : (
              <>
                <ol className="alog">{table.state.chat.map((line) => (
                  <li key={line.id} className={line.isLocal ? "local" : ""}><span className="who">{line.name}:</span> {line.isLocal ? line.text : TableChatFilter.filtered(line.text)}</li>
                ))}</ol>
                <ChatInput table={table} />
              </>
            )}
          </div>
        )}

        {showBrowser && snapshot && envelope && browser !== undefined && (
          <div onClick={stop}>
            <Browser kind={browser} snapshot={snapshot} envelope={envelope} send={send} sendAction={sendAction} pending={pending} onHide={() => setSteppedAside(envelope.id)} />
          </div>
        )}
        {browser !== undefined && steppedAside === envelope?.id && (
          <button type="button" className="aplaque ember" style={{ left: 708, top: B(290), width: 176, height: 34, zIndex: 700 }}
            onClick={(event) => { event.stopPropagation(); setSteppedAside(undefined); }}>Back to the choice</button>
        )}

        {mulligan && envelope?.confirmation && !showRoll && (
          <div className="amull" onClick={stop}>
            <h2 className="title">{(() => {
              // XMage names the active player only once the first turn begins; the roll knows sooner.
              const first = roll?.roll.winnerSeatID ?? snapshot?.activePlayerId;
              if (!first) return "Your opening hand";
              if (first === viewer || first === table.state.localSeatID) return "You go first";
              const name = table.state.seatNames[first] ?? snapshot?.players.find((p) => p.playerId === first)?.displayName;
              return name ? `${name} goes first` : "Your opening hand";
            })()}</h2>
            <p style={{ top: Y(52) }}>{cleanMessage(envelope.message)}</p>
            <div className="tips" style={{ top: B(352) }}><span>Click a card to play it</span><span>Click a land for mana while paying</span><span>Hover a card to read it</span></div>
            <button type="button" className="aplaque leather" style={{ left: 716, top: B(340) }} disabled={pending}
              onClick={() => send({ type: "answer_yes_no", confirmed: true }, envelope.confirmation?.yesLabel ?? "Mulligan")}>{envelope.confirmation.yesLabel ?? "Mulligan"}</button>
            <button type="button" className="aplaque ember want" style={{ left: 716, top: B(388) }} disabled={pending}
              onClick={() => send({ type: "answer_yes_no", confirmed: false }, envelope.confirmation?.noLabel ?? "Keep")}>{envelope.confirmation.noLabel ?? "Keep"}</button>
          </div>
        )}

        {zone && (
          <div className="aoverlay dim" onClick={(event) => { event.stopPropagation(); setZone(undefined); }}>
            <div className="abrowser">
              <h2>{zone.title}</h2>
              <p className="instr">{zone.cards.length === 0 ? "Nothing here yet." : `${zone.cards.length} card${zone.cards.length === 1 ? "" : "s"}, newest last.`}</p>
              <div className="cards">{zone.cards.map((card) => (
                <div key={card.instanceId} className="bcard"><img src={cardImageURL(card.card.name, "normal")} alt={card.card.name} crossOrigin="anonymous" /></div>
              ))}</div>
              <div className="answers"><button type="button" className="aplaque ember" onClick={() => setZone(undefined)}>Done</button></div>
            </div>
          </div>
        )}

        {showRoll && roll && (
          <div className="aoverlay question" onClick={stop}>
            <div className="aroll glass">
              <h2 className="title">Who goes first?</h2>
              <div className="dice">
                {roll.roll.steps.map((step, index) => {
                  const shown = index < roll.revealed;
                  const lastRound = step.roundIndex === roll.roll.rounds.length - 1;
                  const winner = shown && roll.nextSeatID === undefined && lastRound && step.seatID === roll.roll.winnerSeatID;
                  return (
                    <div key={index} className="die">
                      <div className={`face ${!shown && index === roll.revealed ? "rolling" : ""} ${winner ? "won" : shown && roll.nextSeatID === undefined ? "lost" : ""}`}>{shown ? step.value : "?"}</div>
                      <span className="small-print" style={{ color: "#efe4cf" }}>{table.state.seatNames[step.seatID] ?? step.seatID}</span>
                    </div>
                  );
                })}
              </div>
              <p style={{ margin: 0, font: "600 14px/1.35 var(--serif)" }}>{roll.nextSeatID !== undefined ? roll.status
                : roll.roll.winnerSeatID === table.state.localSeatID ? "You go first." : `${table.state.seatNames[roll.roll.winnerSeatID]} goes first.`}</p>
              {roll.nextSeatID === table.state.localSeatID && (
                <button type="button" className="aplaque ember want" disabled={roll.hasRolled || table.state.stage !== "playing"}
                  onClick={() => { try { table.rollStartingPlayer(); } catch (error) { fail(error); } }}>Roll the D20</button>
              )}
            </div>
          </div>
        )}

        {confirmConcede && (
          <div className="aoverlay question" onClick={stop}>
            <div className="aquestion glass">
              <h2>Concede?</h2>
              <p>{table.solo ? "The AI wins this game." : "You leave this game. The other players are told at once."}</p>
              <div style={{ display: "flex", gap: 12 }}>
                <button type="button" className="aplaque leather" onClick={() => setConfirmConcede(false)}>Keep playing</button>
                <button type="button" className="aplaque oxblood" onClick={() => { setConfirmConcede(false); table.concede().catch(fail); }}>Concede</button>
              </div>
            </div>
          </div>
        )}

        {(finished || table.state.stage === "failed") && (
          <div className="aresult" data-win={won ? "true" : "false"} onClick={stop}>
            <div className="glory" />
            <div className="box glass">
              <div className="medal"><div className="av">{AVATAR.me}</div></div>
              <h2 className="title">{finished ? (won ? "Victory" : "Defeat") : table.solo ? "Game stopped" : "Table closed"}</h2>
              <div className="rule" />
              <p>{finished ? resultLine(snapshot!, viewer) : table.state.status}</p>
              <div className="answers">
                {table.rematch && <button type="button" className="aplaque ember" onClick={() => table.rematch?.()}>Play again</button>}
                <button type="button" className={`aplaque ${table.rematch ? "leather" : "ember"}`} onClick={() => table.leave()}>Back to the tavern</button>
              </div>
            </div>
          </div>
        )}

        {(toast || session?.state.errorMessage || table.state.isSuspended || table.state.reconnecting) && (
          <div className="atoast">{toast ?? session?.state.errorMessage ?? table.state.status}</div>
        )}
        {session?.hasPending && !session.state.working && session.state.errorMessage && (
          <button type="button" className="aplaque leather" style={{ left: 708, top: B(250), width: 176, height: 34, zIndex: 700 }}
            onClick={(event) => { event.stopPropagation(); session.retryPending().catch(fail); }}>Retry</button>
        )}
      </div>
    </div>
  );
}

/** "AI 1 won the game on turn 9." (a draw names no one). */
function resultLine(snapshot: GameSnapshot, viewer: string | undefined) {
  const winners = (snapshot.winnerPlayerIds ?? []).map((id) => (id === viewer ? "You" : snapshot.players.find((p) => p.playerId === id)?.displayName)).filter(Boolean);
  const turn = snapshot.turn > 0 ? ` on turn ${snapshot.turn}` : "";
  if (winners.length === 0) return `The game ended in a draw${turn}.`;
  return `${winners.join(", ")} won the game${turn}.`;
}

function ChatInput({ table }: { table: GameTable }) {
  const [text, setText] = useState("");
  return (
    <>
      <form className="chat-input" onSubmit={(event) => { event.preventDefault(); table.sendChat(text); setText(""); }}>
        <input className="slot" value={text} maxLength={400} onChange={(e) => setText(e.target.value)} placeholder="Say something" aria-label="Chat message" />
        <button type="submit" className="plaque compact">Send</button>
      </form>
      <div className="emotes">
        {GameEmotes.map((emote) => <button key={emote.raw} type="button" onClick={() => table.sendEmote(emote)}>{emote.text}</button>)}
      </div>
    </>
  );
}
