/**
 * The Arena board's effects clock (iOS NativeGameView.ingestBoardFX and its turn banner): every snapshot the board shows
 * goes through a BoardFXDirector at the Arena pace, the board records what it is still showing in the session's
 * BoardPresentationHold (smart pass waits for it), and the turn banner waits for the centre of the table. Times are
 * seconds on performance.now()'s clock, the one the session waits on.
 */
import { useEffect, useLayoutEffect, useRef, useState } from "react";
import {
  type ActiveBoardFX, BoardFXDirector, type BoardFXLevel, BoardFXScheduler, BoardPresentationHold, displayName, displaySourceCard, revisionKey,
  type ScheduledBoardFX, stackTopFirst, sweepRecap,
} from "../../core/boardEvents";
import type { CardIdentity, GameSnapshot } from "../../core/models";
import { BOARD_SOUNDS, boardCues, drawCues, gameAudio } from "../audio";
import type { GuestSession } from "../../table/guestSession";

export const fxNow = () => performance.now() / 1000;

/** The Arena turn banner: the reference's 0.9 s over the draw. */
export const TURN_BANNER = 0.9;

export interface TurnBanner { key: string; start: number; end: number; mine: boolean; name?: string }

export interface Impact { id: number; amplitude: number; flare: boolean }

/**
 * NativeGameView.ingestBoardFX's shakes: the viewer losing life (12 points and a red flare for five or more, else 6), a
 * hit of five or more on an opponent (5), a commander touching down (6), at most three per batch.
 */
export function boardShakes(scheduled: ScheduledBoardFX[], viewerID: string): { at: number; amplitude: number; flare: boolean }[] {
  const shakes: { at: number; amplitude: number; flare: boolean }[] = [];
  for (const fx of scheduled) {
    const event = fx.event;
    if (event.type === "lifeChanged" && event.delta < 0) {
      if (event.playerID === viewerID) shakes.push({ at: fx.delay, amplitude: event.delta <= -5 ? 12 : 6, flare: event.delta <= -5 });
      else if (event.delta <= -5) shakes.push({ at: fx.delay, amplitude: 5, flare: false });
    } else if (event.type === "enteredBattlefield" && event.entrance === "commander") {
      shakes.push({ at: fx.landing, amplitude: 6, flare: false });
    }
  }
  return shakes.slice(0, 3);
}

export interface BoardFX {
  active: ActiveBoardFX[];
  director: BoardFXDirector;
  /** What smart pass waits on; the board sets `reading` while a card is being read. */
  hold: BoardPresentationHold;
  /** Bumped whenever the set of hidden tiles or the active effects change. */
  version: number;
  banner?: TurnBanner;
  /** A board wipe's recap for the caption, with when it goes. */
  recap?: { text: string; until: number };
  /** The last hit that shakes the board (full effects): its amplitude in points, and whether it flares red. */
  impact?: Impact;
  /** Card ids whose tile a flight stands in for right now. */
  hidden(now: number): Set<string>;
}

export function useBoardFX(snapshot: GameSnapshot | undefined, session: GuestSession | undefined, level: BoardFXLevel): BoardFX {
  const director = useRef(new BoardFXDirector()).current;
  const hold = useRef(new BoardPresentationHold()).current;
  const [version, setVersion] = useState(0);
  const [banner, setBanner] = useState<TurnBanner>();
  const [recap, setRecap] = useState<{ text: string; until: number }>();
  const [impact, setImpact] = useState<Impact>();
  const shakeTimers = useRef<number[]>([]);
  const lastKey = useRef<string | undefined>(undefined);
  const lastTop = useRef<{ id: string; name: string } | undefined>(undefined);
  const bannerEnd = useRef<number | undefined>(undefined);
  const lastTurnKey = useRef<string | undefined>(undefined);
  const timers = useRef<number[]>([]);
  const lastHand = useRef<{ game: string; count: number } | undefined>(undefined);

  // The session waits on this board's hold.
  useEffect(() => {
    if (!session) return;
    session.presentationHold = hold;
    return () => { if (session.presentationHold === hold) session.presentationHold = undefined; };
  }, [session, hold]);

  // Ingest each new snapshot before it paints, so an arriving tile is hidden from its first frame.
  useLayoutEffect(() => {
    if (!snapshot) return;
    const key = revisionKey(snapshot);
    if (key === lastKey.current) return;
    lastKey.current = key;
    const now = fxNow();
    const scheduled = director.ingest(snapshot, level, now, bannerEnd.current, "arena");
    hold.record(key, director.smartPassHoldUntil);
    // The board's sounds, each timed to the effect it accompanies (BoardFXSound.play), and a draw's (GameSoundSignature).
    if (scheduled.length > 0) {
      const arrivals = new Map<string, { card: CardIdentity; isToken: boolean }>();
      for (const card of snapshot.players.flatMap((p) => p.zones.battlefield)) arrivals.set(card.instanceId, { card: card.card, isToken: card.card.isToken === true });
      const casts = new Map<string, CardIdentity>();
      for (const object of stackTopFirst(snapshot)) { const source = displaySourceCard(object); if (source) casts.set(object.id, source.card); }
      gameAudio.playCues(boardCues(scheduled, snapshot.viewerPlayerId ?? "", arrivals, casts));
    }
    // The board shakes as a hit lands, scaled to it; five or more to you flares red.
    if (level === "full") {
      for (const shake of boardShakes(scheduled, snapshot.viewerPlayerId ?? "")) {
        shakeTimers.current.push(window.setTimeout(() => setImpact((last) => ({ id: (last?.id ?? 0) + 1, amplitude: shake.amplitude, flare: shake.flare })), shake.at * 1000));
      }
    }
    const handCount = snapshot.players.find((p) => p.playerId === snapshot.viewerPlayerId)?.zones.hand.length ?? 0;
    if (lastHand.current?.game === snapshot.id) drawCues(lastHand.current.count, handCount).forEach((sound) => gameAudio.play(sound));
    else gameAudio.preload(BOARD_SOUNDS);
    lastHand.current = { game: snapshot.id, count: handCount };
    // A spell that just left the stack and took three or more permanents with it is named in the caption.
    const top = stackTopFirst(snapshot)[0];
    const resolved = lastTop.current && !stackTopFirst(snapshot).some((o) => o.id === lastTop.current!.id) ? lastTop.current.name : undefined;
    lastTop.current = top ? { id: top.id, name: displayName(top) } : undefined;
    const text = sweepRecap(resolved, scheduled.map((fx) => fx.event));
    if (text) setRecap({ text, until: now + 3.5 });
    // Re-render at every boundary where a tile's flight starts or lands, and once everything has played.
    timers.current.forEach((t) => window.clearTimeout(t));
    const marks = new Set<number>();
    for (const fx of director.active) {
      for (const at of [fx.start + fx.scheduled.delay, fx.start + fx.scheduled.landing, fx.start + fx.scheduled.end + 0.02]) {
        if (at > now) marks.add(at);
      }
    }
    timers.current = [...marks].map((at) => window.setTimeout(() => {
      director.prune(fxNow());
      hold.record(lastKey.current, director.smartPassHoldUntil);
      setVersion((v) => v + 1);
    }, (at - now) * 1000));
    setVersion((v) => v + 1);

    // A new turn: the banner waits for whatever holds the centre, then plays for 0.9 s and holds later effects that long.
    const turnKey = `${snapshot.id}:${snapshot.turn}:${snapshot.activePlayerId ?? ""}`;
    if (turnKey !== lastTurnKey.current && level !== "off") {
      const first = lastTurnKey.current === undefined;
      lastTurnKey.current = turnKey;
      if (!first || snapshot.turn > 1) {
        const busy = director.centreBusyUntil;
        const start = busy !== undefined && busy > now ? Math.min(busy, now + BoardFXScheduler.maximumHold) : now;
        bannerEnd.current = start + TURN_BANNER;
        const mine = snapshot.activePlayerId !== undefined && snapshot.activePlayerId === snapshot.viewerPlayerId;
        // A chime when your turn begins (not the first).
        if (mine) gameAudio.play("turn-you", Math.max(0, start - now));
        const name = snapshot.players.find((p) => p.playerId === snapshot.activePlayerId)?.displayName;
        setBanner({ key: turnKey, start, end: start + TURN_BANNER, mine, name });
      }
    }
  });

  useEffect(() => () => [...timers.current, ...shakeTimers.current].forEach((t) => window.clearTimeout(t)), []);

  return {
    active: director.active, director, hold, version, banner, recap, impact,
    hidden(now: number) {
      const hidden = new Set<string>();
      const motion = director.cardMotion(snapshot?.viewerPlayerId ?? "");
      motion.hidden.forEach((windows, id) => {
        if (windows.some((w) => now >= w.batch + w.from && now < w.batch + w.until)) hidden.add(id);
      });
      return hidden;
    },
  };
}
