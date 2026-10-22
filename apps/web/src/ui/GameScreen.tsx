/**
 * The game on the horizontal Arena board (docs/ARENA_STYLE.md; the Duel Board Prototype's landscape table, artifact
 * T5NcAkjCThiA5hfd9Twwwu): the Walnut Tavern plate scaled to the window, every card a table object, the decision in
 * the corner plaques or on the table, and anything else in a full-table glass browser. Solo games and relay tables
 * share it; both answer through the same GuestSession.
 */
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { type BoardFXLevel, resolvedLevel } from "../core/boardEvents";
import { EngineDisplayText } from "../core/displayText";
import { type GameSnapshot, isCompleted, isOut, type LegalAction, type PlayerGameState, thinkingPlayerID, type ZoneCard } from "../core/models";
import { defaultSmartPass } from "../core/smartPass";
import { GameEmotes, TableChatFilter } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { useTable } from "./App";
import { ArenaCard, type ArenaCardProps } from "./arena/ArenaCard";
import { AmountPill, Browser, browserKind, cardNamed, type Inspect, type Send, StackBrowser, ZoneBrowser } from "./arena/Browsers";
import {
  ARENA, BASE_GEOMETRY, battlefieldPlaces, geometry, type Geometry, handPlaces, mulliganPlaces, opponentHandPlaces, phaseStrip, type Place, stackPlace,
  STAGE,
} from "./arena/layout";
import { isStackAbility } from "./arena/AbilityCard";
import { BoardFXOverlay, type FXAnchors } from "./arena/BoardFX";
import { fxNow, useBoardFX } from "./arena/useBoardFX";
import { ArenaPile } from "./arena/ArenaPile";
import { AVATAR } from "./arena/avatars";
import { ManaSymbol, RulesText } from "./arena/Symbols";
import "./arena/arena.css";
import { cardImageURL } from "./cardArt";
import { storage } from "./storage";

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
  const [handRaised, setHandRaised] = useState(false);
  const [menu, setMenu] = useState<{ id: string; at: Place; actions: LegalAction[] }>();
  const [toast, setToast] = useState<string>();
  const [panel, setPanel] = useState<"log" | "chat">();
  const [gear, setGear] = useState(false);
  const [zone, setZone] = useState<{ title: string; cards: ZoneCard[] }>();
  const [playerCard, setPlayerCard] = useState<string>();
  const [confirmConcede, setConfirmConcede] = useState(false);
  const [rollDismissed, setRollDismissed] = useState(false);
  /** A card under the pointer in a browser (the table's own hover is `hovered`). */
  const [browseZoom, setBrowseZoom] = useState<{ name: string; left: boolean }>();
  const [smart, setSmart] = useState(session?.smartPass?.enabled ?? false);
  const [stackOpen, setStackOpen] = useState(false);
  /** When each stack object first showed, so its landing plays once. */
  const stackSeen = useRef(new Map<string, number>());
  // Card Frames (iOS Settings, per board mode): off by default on the Arena board, the reference game's cards.
  const [frames, setFrames] = useState(() => storage.get("mm.web.cardFrames") === "on");
  // Board effects (iOS magicmobile.boardEffectsLevel): Full by default; the system's Reduce Motion caps it at Reduced.
  const [fxSetting, setFxSetting] = useState(() => storage.get("mm.web.boardEffects") ?? "full");
  const reduceMotion = typeof window !== "undefined" && window.matchMedia?.("(prefers-reduced-motion: reduce)").matches === true;
  const fxLevel: BoardFXLevel = resolvedLevel(fxSetting, reduceMotion);
  const fx = useBoardFX(snapshot, session, fxLevel);
  const fxRef = useRef(fx);
  fxRef.current = fx;
  /** Where each card lies, kept after it leaves so its departure starts there; and where a card was before its last move. */
  const places = useRef(new Map<string, Place>());
  const movedFrom = useRef(new Map<string, { place: Place; at: number }>());
  /** An opponent's spell is revealed larger toward the middle for its first 1.3 s, then settles onto the stack card. */
  const [revealID, setRevealID] = useState<string>();
  const [, setClockTick] = useState(0);
  useEffect(() => { setSmart(session?.smartPass?.enabled ?? false); }, [session]);
  // Development only: the table, for checking a game from the console.
  useEffect(() => { if (import.meta.env.DEV) Object.assign(window, { __mm: { table, fx: fxRef } }); }, [table]);

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
  const rawBrowser = browserKind(envelope, onTable, (name) => snapshot !== undefined && cardNamed(snapshot, name) !== undefined);
  const browser = rawBrowser === "players" && table.state.roll !== undefined ? undefined : rawBrowser;
  const showBrowser = browser !== undefined && browser !== "mulligan" && browser !== "amount" && !pending;
  // A number takes the button corner (ArenaAmountPill), with the board in view.
  const amountPill = browser === "amount" && !finished;
  const inspect: Inspect = setBrowseZoom;
  // A zoom from a browser goes when the browser does.
  useEffect(() => setBrowseZoom(undefined), [envelope?.id, envelope?.messageId, zone, stackOpen]);

  /** A click on a card: answer a target or combat question with it, or offer its legal actions. */
  const clickCard = (id: string, at?: Place) => {
    if (!snapshot || pending || finished) return;
    setMenu(undefined);
    if (targetIDs.has(id)) { send({ type: "choose_target", targetIds: [id] }, "Choose"); return; }
    const actions = actionsFor(snapshot, id);
    if (actions.length === 1) sendAction(actions[0]);
    else if (actions.length > 1 && at) setMenu({ id, at, actions });
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
  // Reading the spell on the stack card (the pointer on it) holds smart pass, as holding a card open does on iOS.
  const readingStack = hovered !== undefined && stack.some((o) => o.id === hovered);
  useEffect(() => { fx.hold.reading = readingStack; }, [fx.hold, readingStack]);
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
  const notice = fx.recap && fx.recap.until > fxClock ? fx.recap.text : undefined;

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
  // As on Arena's desktop client the hand rests low, showing the top of each card, and fans up while the pointer is on
  // it; the prototype raised it whenever you could play (a touch screen's answer), which covered your lands.
  // A decision on the table (paying, choosing a permanent or player, combat) keeps the hand resting (ArenaHandPosture).
  const boardDecision = paying || combatSelect || (envelope !== undefined && targetIDs.size > 0 && !(me?.zones.hand ?? []).some((c) => targetIDs.has(c.instanceId)));
  // A browser over the table keeps the hand resting under its veil.
  const covered = showBrowser || zone !== undefined || stackOpen;
  const handUp = mulligan || (handRaised && !boardDecision && !covered);
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
    // Lands you could use glow softer, so a full mana row doesn't shout (ArenaOutlineGlow strength 0.65).
    if (onBattlefield && /\bland\b/i.test(card.card.typeLine)) list.push("landish");
    return list.join(" ");
  };
  const clickAt = (place: Place) => (id: string) => clickCard(id, place);
  if (snapshot && me) {
    battlefieldPlaces(me.zones.battlefield, "me", undefined, geo, frames).forEach((place, id) => {
      const card = me.zones.battlefield.find((c) => c.instanceId === id)!;
      add({ id, place, view: "tile", card, frames, owner: "me", classes: classFor(card, true), onClick: clickAt(place), onHover: setHovered });
    });
    opponents.forEach((opponent, index) => {
      battlefieldPlaces(opponent.zones.battlefield, "opp", { index, count: opponents.length }, geo, frames).forEach((place, id) => {
        const card = opponent.zones.battlefield.find((c) => c.instanceId === id)!;
        add({ id, place, view: "tile", card, frames, owner: "opp", classes: classFor(card, true), onClick: clickAt(place), onHover: setHovered });
      });
      opponentHandPlaces(opponent.zones.handCount ?? opponent.zones.hand.length, { index, count: opponents.length }, geo).forEach((place, i) =>
        add({ id: `backs-${opponent.playerId}-${i}`, place, view: "back" }));
    });
    const handPlace = mulligan ? mulliganPlaces(handIDs, geo) : handPlaces(handIDs, handUp, hovered, geo, handRoom);
    me.zones.hand.forEach((card) => {
      const place = handPlace.get(card.instanceId)!;
      add({ id: card.instanceId, place, view: "face", card, owner: "me", inHand: true, classes: classFor(card, false),
        onClick: mulligan ? undefined : clickAt(place), onHover: mulligan ? undefined : setHovered });
    });
    // Only the top of the stack stands on the table (ArenaStackCard); the tab opens the rest.
    stack.slice(0, 1).forEach((item, depth) => {
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
        classes: [landing ? "landing" : "", commander ? "commander" : ""].join(" "), onHover: setHovered, onClick: () => setStackOpen(true),
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
  if (snapshot && !finished && envelope && !showBrowser && !mulligan && !amountPill) {
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
    const spot = mine ? ARENA.viewerMedallion : ARENA.opponentMedallion;
    const at = mine ? { x: spot.x, y: B(spot.y) }
      : { x: opponents.length > 1 ? 150 + (650 * (index + 0.5)) / opponents.length : spot.x, y: T(spot.y) };
    const d = spot.d * geo.grow;
    const ready = mine && commandActions.length > 0;
    const targetable = targetIDs.has(player.playerId) && !pending;
    const seat = seatOf(player);
    const clock = rope && rope.seat === seat ? rope : undefined;
    const bubble = seat ? table.state.bubbles[seat] : undefined;
    const circumference = Math.PI * 2 * 46;
    return (
      <div key={player.playerId}>
        <button type="button" className={`amed ${targetable ? "targetable" : ready ? "ready" : ""} ${isOut(player) ? "out" : ""}`}
          style={{ left: at.x, top: at.y, ["--d" as string]: `${d}px` }}
          aria-label={`${mine ? "You" : player.displayName ?? "Opponent"}, ${player.life} life${ready ? ", your commander can be cast" : ""}`}
          onClick={(event) => {
            event.stopPropagation();
            if (targetable) send({ type: "choose_target", targetIds: [player.playerId] }, player.displayName ?? "Player");
            else if (ready) setMenu({ id: "commander", at: { x: at.x + 110, y: at.y, w: d, h: d, z: 0 }, actions: commandActions });
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
          <div className="aname under" style={{ left: at.x, top: at.y + d / 2 + 4 }}>
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
    const spots = mine ? ARENA.viewerPiles : ARENA.opponentPiles;
    const shift = !mine && opponents.length > 1 ? -index * 170 : 0;
    // Piles grow with the board, so they spread from their anchor (your medallion; their library) to keep the gaps for
    // their count lozenges (Caleb, 2026-10-21, on iOS: the badges ran over the next pile).
    const anchor = mine ? ARENA.viewerMedallion.x : ARENA.opponentPiles.library.x;
    const at = (p: { x: number; y: number }) => ({ x: anchor + (p.x - anchor) * geo.grow + shift, y: mine ? B(p.y) : T(p.y) });
    const size = { w: spots.size.w * geo.grow, h: spots.size.h * geo.grow };
    const whose = mine ? "Your" : `${player.displayName ?? "Their"}’s`;
    const open = (zone: "graveyard" | "exile") => () => setZone({ title: `${whose} ${zone}`, cards: player.zones[zone] });
    const hover = (name: string | undefined) => setHovered(name ? `zone:${name}` : undefined);
    return (
      <div key={`piles-${player.playerId}`}>
        <ArenaPile {...at(spots.library)} size={size} count={player.zones.libraryCount ?? 0} kind="library" label={`${whose} library`} />
        <ArenaPile {...at(spots.graveyard)} size={size} count={player.zones.graveyard.length} kind="graveyard" label={`${whose} graveyard`}
          top={player.zones.graveyard.at(-1)?.card.name} onOpen={open("graveyard")} onHover={hover} />
        {player.zones.exile.length > 0 && (
          <ArenaPile {...at(spots.exile)} size={size} count={player.zones.exile.length} kind="exile" label={`${whose} exile`}
            top={player.zones.exile.at(-1)?.card.name} onOpen={open("exile")} onHover={hover} />
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

  // The card under the pointer, large, away from the side it sits on (never for the hand, which pops up instead).
  const inspected = (() => {
    if (browseZoom) return browseZoom;
    if (!hovered || !snapshot) return undefined;
    if (hovered.startsWith("zone:")) return { name: hovered.slice(5), left: false };
    if (handIDs.includes(hovered)) return undefined;
    const item = cards.get(hovered);
    if (!item || item.view === "back") return undefined;
    return { name: item.name ?? item.card?.card.name ?? "", left: item.place.x > 560 };
  })();

  const log = snapshot?.log ?? [];
  const pool = me?.manaPool;
  const poolSymbols = pool ? (["W", "U", "B", "R", "G", "C"] as const).map((s) => [s, pool[s]] as const).filter(([, n]) => n > 0) : [];
  const stop = (event: React.MouseEvent) => event.stopPropagation();

  return (
    <div className="arena" ref={wrapRef} onClick={() => { setGear(false); setPlayerCard(undefined); setMenu(undefined); }}
      onPointerMove={(event) => {
        // The hand rises while the pointer is over it: below the top of the fan as it stands, within its width.
        if (mulligan || covered || handIDs.length === 0) return;
        const bounds = wrapRef.current!.getBoundingClientRect();
        const x = (event.clientX - bounds.left - geo.left) / geo.scale;
        const y = (event.clientY - bounds.top - geo.top) / geo.scale;
        const fan = [...handPlaces(handIDs, handRaised, undefined, geo, handRoom).values()];
        const top = Math.min(...fan.map((p) => p.y - (p.h * (p.s ?? 1)) / 2)) - 6;
        // Never over your piles: a click on the graveyard raised the hand over it.
        const left = Math.max(handRoom.left, Math.min(...fan.map((p) => p.x - p.w / 2)) - 12);
        const right = Math.max(...fan.map((p) => p.x + p.w / 2)) + 12;
        const over = y > top && x > left && x < right;
        if (over !== handRaised) setHandRaised(over);
      }}
      onPointerLeave={() => setHandRaised(false)}>
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
        {fxLevel !== "off" && <BoardFXOverlay active={fx.active} subjects={fx.director.subjects} frames={frames} anchors={anchors}
          stackIDs={new Set(stack.map((o) => o.id))} rect={(id) => {
            const moved = movedFrom.current.get(id);
            return moved && fxNow() - moved.at < 0.6 ? moved.place : places.current.get(id);
          }} />}
        {opponents.map((o, i) => medallion(o, false, i))}
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
        {stack.length > 0 && (() => {
          // A tab on the stack card's left edge opens the whole stack, with how many objects are on it.
          const top = stackPlace(0, geo);
          const height = stack.length > 1 ? 58 : 44;
          return (
            <button type="button" className="astack-tab" style={{ left: top.x - top.w / 2 - 26, top: top.y - height / 2, height }}
              aria-label={stack.length > 1 ? `Open the stack, ${stack.length} objects` : "Open the stack"} onClick={(event) => { event.stopPropagation(); setStackOpen(true); }}>
              {stack.length > 1 && <b>{stack.length}</b>}<i>‹</i>
            </button>
          );
        })()}

        {/* Above the raised hand while there is an answer to give (the prototype's controls z-index). */}
        <div className="acontrols" style={{ zIndex: (primary && primary.style !== "label") || secondary ? 600 : 430 }} onClick={stop}>
          <div className="aphases" data-side={activeIsMe ? "me" : "opp"} style={{ top: B(secondary ? ARENA.phaseStrip.raisedY : ARENA.phaseStrip.y) - 10 }} aria-hidden="true">
            <div className="track" />
            {strip.items.map(([key, icon]) => <span key={key} className={`aph ${icon === "dia" ? "small" : ""} ${strip.current === key ? "on" : ""}`}>{PHASE_ICONS[icon]}</span>)}
          </div>
          {secondary && <button type="button" className={`aplaque abtn2 ${secondary.style}`} style={{ top: B(ARENA.secondary.y) }} disabled={pending} onClick={secondary.onClick}>{secondary.label}</button>}
          {primary ? (
            <button type="button" className={`aplaque abtn ${primary.style} ${primary.want ? "want" : ""}`} style={{ top: B(ARENA.primary.y) }} disabled={primary.style !== "label" && pending}
              onClick={primary.onClick}>{primary.label}</button>
          ) : !finished && <div className="ahourglass" style={{ top: B(ARENA.primary.y) }}>{HOURGLASS}</div>}
          {session && (
            <button type="button" className={`aff ${smart ? "on" : ""}`} aria-pressed={smart} onClick={toggleSmart}
              style={{ left: ARENA.passAhead.x, top: B(ARENA.passAhead.y), width: ARENA.passAhead.w, height: ARENA.passAhead.h }}
              title={smart ? "Smart pass is on: routine priority passes by itself" : "Smart pass is off: you pass every step"}>
              <svg viewBox="0 0 26 18"><path d="M2 2l9 7-9 7zM14 2l9 7-9 7z" /></svg>
            </button>
          )}
          <button type="button" className={`acoin ${panel ? "on" : ""}`} style={{ left: ARENA.log.x - 14, top: T(ARENA.log.y) - 14 }} aria-label="Game log" onClick={() => setPanel(panel ? undefined : "log")}>{SCROLL}</button>
          <button type="button" className={`acoin ${gear ? "on" : ""}`} style={{ left: ARENA.menu.x - 14, top: T(ARENA.menu.y) - 14 }} aria-label="Menu" onClick={() => setGear(!gear)}>{GEAR}</button>
        </div>

        {notice && !showBrowser ? <div className="aprompt notice" style={{ top: Y(ARENA.captionY) }}><span>{notice}</span></div> : <>
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

        {inspected && (
          <div className="ainspect" style={{
            left: inspected.left ? 250 - (ARENA.zoom.w * Math.min(geo.grow, 1.2)) / 2 : ARENA.zoom.x - (ARENA.zoom.w * Math.min(geo.grow, 1.2)) / 2,
            top: Math.max(6, Y(ARENA.zoom.y) - (ARENA.zoom.h * Math.min(geo.grow, 1.2)) / 2), width: ARENA.zoom.w * Math.min(geo.grow, 1.2),
          }}>
            {/* A card Scryfall can't find by name (most tokens) shows nothing rather than a broken image. */}
            <img src={cardImageURL(inspected.name, "normal")} alt="" crossOrigin="anonymous" onError={(e) => { e.currentTarget.style.visibility = "hidden"; }}
              onLoad={(e) => { e.currentTarget.style.visibility = "visible"; }} />
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
            <div className="amenu glass" style={mine ? { left: 40, top: B(250), right: "auto" } : { left: 520, top: T(60), right: "auto" }} onClick={stop}>
              <h3 className="panel-title" style={{ margin: 0 }}>{mine ? "You" : player.displayName}</h3>
              <div className="small-print" style={{ color: "#efe4cf" }}>
                Life {player.life} · Hand {player.zones.handCount ?? player.zones.hand.length} · Library {player.zones.libraryCount ?? 0}<br />
                Graveyard {player.zones.graveyard.length} · Exile {player.zones.exile.length}
                {player.poison > 0 && <><br />Poison {player.poison}</>}
                {player.commanderTax > 0 && <><br />Commander tax {player.commanderTax}</>}
                {Object.entries(player.commanderDamage ?? {}).filter(([, n]) => n > 0).map(([id, n]) => <span key={id}><br />Commander damage {n}</span>)}
              </div>
              {player.zones.command.length > 0 && (
                <button type="button" className="arow" onClick={() => setZone({ title: `${mine ? "Your" : `${player.displayName ?? "Their"}’s`} command zone`, cards: player.zones.command })}>
                  <span>Command zone<span className="sub">{player.zones.command.map((c) => c.card.name).join(", ")}</span></span>
                </button>
              )}
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
            <button type="button" className="arow" onClick={() => { const on = !frames; setFrames(on); storage.set("mm.web.cardFrames", on ? "on" : "off"); }}>
              <span>Card frames: {frames ? "on" : "off"}<span className="sub">On: tavern frames. Off: the reference game's cards (the default).</span></span>
            </button>
            <button type="button" className="arow" onClick={() => {
              const next = ({ full: "reduced", reduced: "off", off: "full" } as Record<string, string>)[fxSetting] ?? "full";
              setFxSetting(next); storage.set("mm.web.boardEffects", next);
            }}>
              <span>Effects: {({ full: "Full", reduced: "Reduced", off: "Off" } as Record<string, string>)[fxSetting] ?? "Full"}</span>
            </button>
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

        {showBrowser && snapshot && envelope && (
          <div onClick={stop}>
            <Browser key={`${envelope.id}:${envelope.messageId}`} kind={browser} snapshot={snapshot} envelope={envelope} send={send} sendAction={sendAction}
              pending={pending} height={geo.height} inspect={inspect} />
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

        {mulligan && envelope?.confirmation && !showRoll && (
          <div className="amull" onClick={stop}>
            {/* Below the opponent's medallion, above the cards. */}
            <h2 className="title" style={{ top: Y(62) }}>{(() => {
              // XMage names the active player only once the first turn begins; the roll knows sooner.
              const first = roll?.roll.winnerSeatID ?? snapshot?.activePlayerId;
              if (!first) return "Your opening hand";
              if (first === viewer || first === table.state.localSeatID) return "You go first";
              const name = table.state.seatNames[first] ?? snapshot?.players.find((p) => p.playerId === first)?.displayName;
              return name ? `${name} goes first` : "Your opening hand";
            })()}</h2>
            <p style={{ top: Y(62) + 36 }}>{cleanMessage(envelope.message)}</p>
            <div className="tips" style={{ top: B(352) }}><span>Click a card to play it</span><span>Click a land for mana while paying</span><span>Hover a card to read it</span></div>
            <button type="button" className="aplaque leather" style={{ left: 716, top: B(340) }} disabled={pending}
              onClick={() => send({ type: "answer_yes_no", confirmed: true }, envelope.confirmation?.yesLabel ?? "Mulligan")}>{envelope.confirmation.yesLabel ?? "Mulligan"}</button>
            <button type="button" className="aplaque ember want" style={{ left: 716, top: B(388) }} disabled={pending}
              onClick={() => send({ type: "answer_yes_no", confirmed: false }, envelope.confirmation?.noLabel ?? "Keep")}>{envelope.confirmation.noLabel ?? "Keep"}</button>
          </div>
        )}

        {stackOpen && snapshot && (
          <div onClick={stop}>
            <StackBrowser snapshot={snapshot} height={geo.height} inspect={inspect} close={() => setStackOpen(false)} />
          </div>
        )}

        {zone && snapshot && (
          <div onClick={stop}>
            <ZoneBrowser title={zone.title} cards={zone.cards} snapshot={snapshot} pending={pending} sendAction={sendAction} height={geo.height}
              inspect={inspect} close={() => setZone(undefined)} />
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
