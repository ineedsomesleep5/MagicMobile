import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { type BoardTile, type TileGlow, TableScene } from "../board/TableScene";
import { EngineDisplayText } from "../core/displayText";
import { type GameSnapshot, isCompleted, isOut, type LegalAction, type PlayerGameState, thinkingPlayerID, type ZoneCard } from "../core/models";
import { GameEmotes, TableChatFilter } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { useTable } from "./App";
import { cardImageURL, manaSymbols } from "./cardArt";
import { PromptPanel, type Send } from "./PromptPanel";

/** Landscape plate sockets (scripts/brand/tavern_layout.json). */
const SOCKETS = { opponent: { x: 118, y: 76, r: 30 }, life: { x: 118, y: 344, r: 34 }, pass: { x: 846, y: 344 }, rail: { x: 477, y: 416 } };

const phaseText = (snapshot: GameSnapshot) => EngineDisplayText.phaseLabel(snapshot.step ?? snapshot.phase);

/** Legal actions for one card, grouped by what a tap on it would do. */
const actionsFor = (snapshot: GameSnapshot, id: string) =>
  (snapshot.legalActions ?? []).filter((a) => a.cardInstanceId === id || a.sourceInstanceId === id);

export function GameScreen({ table }: { table: GameTable }) {
  useTable(table);
  const session = table.session;
  const snapshot = session?.state.snapshot;
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const sceneRef = useRef<TableScene | undefined>(undefined);
  const [layoutTick, setLayoutTick] = useState(0);
  const [menu, setMenu] = useState<{ x: number; y: number; actions: LegalAction[] }>();
  const [inspect, setInspect] = useState<{ card: ZoneCard; x: number; y: number }>();
  const [toast, setToast] = useState<string>();
  const [tab, setTab] = useState<"log" | "chat">("log");
  const [confirmConcede, setConfirmConcede] = useState(false);
  const [rollDismissed, setRollDismissed] = useState(false);
  const [, setClockTick] = useState(0);

  const viewer = snapshot?.viewerPlayerId;
  const me = snapshot?.players.find((p) => p.playerId === viewer);
  const opponents = snapshot?.players.filter((p) => p.playerId !== viewer) ?? [];
  const pending = session?.state.pendingActionID !== undefined || session?.state.working === true;
  const envelope = snapshot?.promptEnvelopeV2;
  const targetIDs = new Set([...(envelope?.targetIds ?? []), ...(envelope?.targets ?? []).map((t) => t.id)]);
  const isCombatSelect = envelope?.method === "GAME_SELECT" && envelope?.responseKind === "target";

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

  /** A tap on a card: answer a target or combat question with it, or offer its legal actions. */
  const tapCard = useCallback((id: string, at?: { x: number; y: number }) => {
    if (!snapshot || pending) return;
    if (targetIDs.has(id)) { send({ type: "choose_target", targetIds: [id] }, "Choose"); return; }
    const actions = actionsFor(snapshot, id);
    if (actions.length === 1) sendAction(actions[0]);
    else if (actions.length > 1) setMenu({ x: at?.x ?? 300, y: at?.y ?? 300, actions });
  }, [snapshot, pending, send, sendAction, targetIDs]);

  // The Three.js table lives for the whole game.
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const scene = new TableScene(canvas);
    sceneRef.current = scene;
    if (import.meta.env.DEV) Object.assign(window, { __mm: { table, scene } });
    const observer = new ResizeObserver(() => { scene.resize(); setLayoutTick((t) => t + 1); });
    observer.observe(canvas);
    return () => { observer.disconnect(); scene.dispose(); sceneRef.current = undefined; };
  }, []);

  useEffect(() => {
    const scene = sceneRef.current;
    if (!scene) return;
    scene.onTileClick = (id) => { const at = scene.screenPosition(id); tapCard(id, at); };
    scene.onTileHover = (id, card) => {
      const at = id ? scene.screenPosition(id) : undefined;
      setInspect(card && at ? { card, x: at.x, y: at.y } : undefined);
    };
  }, [tapCard]);

  useLayoutEffect(() => {
    const scene = sceneRef.current;
    if (!scene || !snapshot) return;
    const tiles: BoardTile[] = [];
    const glowFor = (card: ZoneCard): TileGlow => {
      if (targetIDs.has(card.instanceId)) return isCombatSelect ? "playable" : "target";
      if (pending) return "none";
      // Mana abilities glow only while paying, as on the phones; otherwise every land would.
      const paying = snapshot.manaPayment?.active === true;
      return actionsFor(snapshot, card.instanceId).some((a) => paying || a.type !== "make_mana") ? "playable" : "none";
    };
    if (me) for (const card of me.zones.battlefield) tiles.push({ card, owner: "me", band: 0, bands: 1, glow: glowFor(card) });
    opponents.forEach((opponent, band) => {
      for (const card of opponent.zones.battlefield) tiles.push({ card, owner: "opponent", band, bands: opponents.length, glow: glowFor(card) });
    });
    scene.update(tiles);
  });

  // Burn the rope smoothly while a clock runs.
  useEffect(() => {
    const timer = window.setInterval(() => setClockTick((t) => t + 1), 250);
    return () => window.clearInterval(timer);
  }, []);

  const scene = sceneRef.current;
  void layoutTick;
  const at = (x: number, y: number) => scene?.project(x, y) ?? { x: 0, y: 0 };
  const scale = scene?.scaleAt(SOCKETS.life.x, SOCKETS.life.y) ?? 1;
  const seatOf = (player: PlayerGameState) => Object.entries(table.state.seatNames).find(([, n]) => n === player.displayName)?.[0];
  const now = performance.now() / 1000;
  const rope = table.state.turnClock.rope(table.state.localSeatID, now);
  const waitingFor = snapshot ? (() => {
    const thinking = thinkingPlayerID(snapshot);
    if (thinking) return snapshot.players.find((p) => p.playerId === thinking)?.displayName;
    const priority = snapshot.priorityPlayerId;
    return priority && priority !== viewer ? snapshot.players.find((p) => p.playerId === priority)?.displayName : undefined;
  })() : undefined;

  const medallion = (player: PlayerGameState, socket: { x: number; y: number; r: number }, opponent: boolean, offset = 0) => {
    const point = at(socket.x, socket.y + offset);
    const size = socket.r * 2 * scale;
    const seat = seatOf(player);
    const clock = rope && rope.seat === seat ? rope : undefined;
    const targetable = targetIDs.has(player.playerId);
    const bubble = seat ? table.state.bubbles[seat] : undefined;
    const circumference = Math.PI * 2 * 46;
    return (
      <div key={player.playerId}>
        <button type="button" className={`medallion ${opponent ? "opponent" : ""} ${targetable ? "targetable" : ""} ${isOut(player) ? "out" : ""}`}
          style={{ left: point.x, top: point.y, width: size, height: size, fontSize: size * 0.42 }}
          aria-label={`${player.displayName ?? "Player"}, ${player.life} life`}
          onClick={() => targetable && send({ type: "choose_target", targetIds: [player.playerId] }, player.displayName ?? "Player")}>
          <span className="life">{player.life}</span>
          {clock && (
            <svg className="rope" viewBox="0 0 100 100" aria-hidden="true">
              <circle cx="50" cy="50" r="46" fill="none" stroke="rgba(0,0,0,.4)" strokeWidth="5" />
              <circle cx="50" cy="50" r="46" fill="none" stroke={clock.strikes > 0 ? "#ff5a2e" : "#ffb36a"} strokeWidth="5" strokeLinecap="round"
                strokeDasharray={`${circumference * clock.fraction} ${circumference}`} transform="rotate(-90 50 50)"
                style={{ filter: "drop-shadow(0 0 4px #ff8a3a)" }} />
            </svg>
          )}
        </button>
        <div className="nameplate" style={{ left: point.x, top: point.y + size / 2 + 6 }}>
          {player.displayName}{isOut(player) ? " (left)" : ""}
          <small>Hand {player.zones.handCount ?? player.zones.hand.length} · Library {player.zones.libraryCount ?? 0} · Grave {player.zones.graveyard.length}</small>
          {(player.poison > 0 || player.commanderTax > 0 || player.monarch) && (
            <div className="badge-row">
              {player.poison > 0 && <span className="tag">Poison {player.poison}</span>}
              {player.commanderTax > 0 && <span className="tag">Tax {player.commanderTax}</span>}
              {player.monarch && <span className="tag">Monarch</span>}
            </div>
          )}
          {clock && <small style={{ color: "#ffb36a" }}>{Math.ceil(clock.remaining)} s</small>}
        </div>
        {bubble && Date.now() - bubble.at < 3200 && (
          <div key={bubble.at} className="bubble" style={{ left: point.x, top: point.y - size / 2 - 6 }}>{bubble.emote.text}</div>
        )}
      </div>
    );
  };

  const stack = snapshot?.xmage?.stack ?? [];
  // The pass disc in the plate's socket answers the decision's main action: pass, resolve, done.
  const primary = (snapshot?.legalActions ?? []).find((a) => a.cardInstanceId === undefined &&
    (a.type === "pass_priority" || (a.type === "answer_yes_no" && a.confirmed === true)));
  const primaryLabel = primary?.type === "pass_priority" ? (stack.length > 0 ? "Resolve" : "Pass") : primary ? EngineDisplayText.label(primary.label) : "";
  const pool = me?.manaPool;
  const roll = table.state.roll;
  const showRoll = roll && !rollDismissed && (roll.nextSeatID !== undefined || !snapshot || (snapshot.turn <= 1 && !envelope?.message.toLowerCase().includes("mulligan")));
  useEffect(() => {
    if (roll && roll.nextSeatID === undefined) { const t = window.setTimeout(() => setRollDismissed(true), 3500); return () => window.clearTimeout(t); }
  }, [roll?.nextSeatID, roll]);

  const hand = me?.zones.hand ?? [];
  const finished = snapshot && isCompleted(snapshot);
  const won = finished && viewer !== undefined && (snapshot.winnerPlayerIds ?? []).includes(viewer);

  return (
    <div className="game">
      <div className="board">
        <canvas ref={canvasRef} aria-label="Game table" />
        <div className="overlay">
          {opponents.map((opponent, index) => medallion(opponent, SOCKETS.opponent, true, index * 86))}
          {me && medallion(me, SOCKETS.life, false)}
          {pool && (
            <div className="mana-rail" style={{ left: at(SOCKETS.rail.x, SOCKETS.rail.y).x, top: at(SOCKETS.rail.x, SOCKETS.rail.y).y }}>
              {(["W", "U", "B", "R", "G", "C"] as const).filter((s) => pool[s] > 0).map((s) => (
                <span key={s} style={{ backgroundImage: `url(/tavern/mana-${s}.webp)` }}>{pool[s]}</span>
              ))}
            </div>
          )}
          {primary && (
            <button type="button" className="pass-disc" disabled={pending}
              style={{ left: at(SOCKETS.pass.x, SOCKETS.pass.y).x, top: at(SOCKETS.pass.x, SOCKETS.pass.y).y, width: 96 * scale, height: 96 * scale, fontSize: Math.max(12, 17 * scale) }}
              onClick={() => sendAction(primary)}>{primaryLabel}</button>
          )}
          {stack.length > 0 && (
            <div className="stack-tray" style={{ left: at(477, 205).x, top: at(477, 205).y }}>
              {stack.slice(0, 3).map((item) => (
                <img key={item.id} className="stack-card" alt={item.name} title={`${item.name}\n${item.rulesText ?? ""}`}
                  src={cardImageURL(item.sourceCard?.card.name ?? item.sourceName ?? item.name, "normal")} crossOrigin="anonymous" />
              ))}
            </div>
          )}
          {inspect && (
            <div className="inspector" style={{ left: Math.min(inspect.x + 40, (canvasRef.current?.clientWidth ?? 800) - 260), top: Math.max(8, inspect.y - 200) }}>
              <img src={cardImageURL(inspect.card.card.name, "normal")} alt={inspect.card.card.name} crossOrigin="anonymous" />
            </div>
          )}
          {menu && (
            <div className="panel popover" style={{ left: menu.x, top: menu.y }} onMouseLeave={() => setMenu(undefined)}>
              {menu.actions.map((action) => (
                <button key={action.id} type="button" className="choice" onClick={() => sendAction(action)}>{action.label}</button>
              ))}
              <button type="button" className="choice" onClick={() => setMenu(undefined)}>Cancel</button>
            </div>
          )}
          {toast && <div className="toast">{toast}</div>}
          {table.state.isSuspended && <div className="toast">{table.state.status}</div>}
        </div>
      </div>

      <div className="hand" aria-label="Your hand">
        {hand.length === 0 && <span className="hand-empty">{me ? "Your hand is empty." : "Dealing…"}</span>}
        {hand.map((card) => {
          const actions = snapshot ? actionsFor(snapshot, card.instanceId) : [];
          const target = targetIDs.has(card.instanceId);
          return (
            <button key={card.instanceId} type="button" className={`hand-card ${actions.length > 0 && !pending ? "playable" : ""} ${target ? "target" : ""}`}
              aria-label={card.card.name}
              onClick={(event) => {
                const rect = (event.currentTarget.closest(".game") as HTMLElement).getBoundingClientRect();
                tapCard(card.instanceId, { x: event.clientX - rect.left, y: Math.max(20, event.clientY - rect.top - 220) });
              }}>
              <img src={cardImageURL(card.card.name, "normal")} alt="" crossOrigin="anonymous" onError={(e) => { e.currentTarget.style.display = "none"; }} />
              {manaSymbols(card.card.manaCost).length > 0 && (
                <span className="cost">{manaSymbols(card.card.manaCost).map((symbol, index) => (
                  /^[WUBRGC]$/.test(symbol)
                    ? <span key={index} className="sym" style={{ backgroundImage: `url(/tavern/mana-${symbol}.webp)` }} />
                    : <span key={index} className="sym" style={{ backgroundImage: "url(/tavern/mana-generic.webp)" }}>{symbol === "//" ? "" : symbol}</span>
                ))}</span>
              )}
            </button>
          );
        })}
      </div>

      <aside className="side">
        <div className="panel" style={{ padding: "12px 14px" }}>
          <div className="status-line">
            <span className="phase">{snapshot ? `Turn ${snapshot.turn} · ${phaseText(snapshot)}` : "Starting"}</span>
            <span className="small-print">{table.state.tableCode}</span>
          </div>
          <div className="small-print">{session?.state.errorMessage ?? (table.state.reconnecting ? "Reconnecting to the table…" : session?.state.status ?? table.state.status)}</div>
        </div>
        <div className="panel" style={{ padding: "12px 14px" }}>
          <h2 className="panel-title">{envelope ? "Your decision" : "Table"}</h2>
          {snapshot ? (
            <PromptPanel snapshot={snapshot} send={send} sendAction={sendAction} pending={pending} waitingFor={waitingFor} />
          ) : <div className="prompt-message">{table.state.stage === "starting" && <span className="thinking" />} {table.state.status}</div>}
          {session?.hasPending && !session.state.working && session.state.errorMessage && (
            <button type="button" className="plaque compact" onClick={() => session.retryPending().catch(fail)}>Retry</button>
          )}
        </div>
        {stack.length > 0 && (
          <div className="panel scroll" style={{ padding: "10px 14px", maxHeight: 160 }}>
            <h2 className="panel-title">Stack</h2>
            {stack.map((item) => <div key={item.id} className="small-print"><b>{item.name}</b> {item.rulesText ? `— ${item.rulesText.split("\n")[0]}` : ""}</div>)}
          </div>
        )}
        <div className="panel log" style={{ padding: "10px 14px" }}>
          {table.solo ? <h2 className="panel-title">Game log</h2> : (
            <div className="tabs">
              <button type="button" aria-pressed={tab === "log"} onClick={() => setTab("log")}>Game log</button>
              <button type="button" aria-pressed={tab === "chat"} onClick={() => setTab("chat")}>Chat</button>
            </div>
          )}
          <div className="scroll" style={{ flex: 1, marginTop: 8 }}>
            {tab === "log" ? (
              <ol>{[...(snapshot?.log ?? [])].reverse().map((entry) => <li key={entry.id}>{EngineDisplayText.text(entry.message)}</li>)}</ol>
            ) : (
              <ol>{table.state.chat.map((line) => (
                <li key={line.id} className={line.isLocal ? "local" : ""}><span className="who">{line.name}:</span> {line.isLocal ? line.text : TableChatFilter.filtered(line.text)}</li>
              ))}</ol>
            )}
          </div>
          {tab === "chat" && <ChatInput table={table} />}
        </div>
        <div className="row">
          <button type="button" className="plaque danger compact" onClick={() => setConfirmConcede(true)} disabled={!session || !!finished}>Concede</button>
          {(!table.solo || !session) && <button type="button" className="plaque compact" onClick={() => table.leave()}>{table.solo ? "Back to the tavern" : "Leave table"}</button>}
        </div>
      </aside>

      {showRoll && roll && (
        <div className="modal">
          <div className="panel">
            <h2 className="title">Who goes first?</h2>
            <div className="dice">
              {roll.roll.steps.map((step, index) => {
                const shown = index < roll.revealed;
                const lastRound = step.roundIndex === roll.roll.rounds.length - 1;
                const won = shown && roll.nextSeatID === undefined && lastRound && step.seatID === roll.roll.winnerSeatID;
                return (
                  <div key={index} className="die">
                    <div className={`face ${!shown && index === roll.revealed ? "rolling" : ""} ${won ? "won" : shown && roll.nextSeatID === undefined ? "lost" : ""}`}>{shown ? step.value : "?"}</div>
                    <span className="small-print">{table.state.seatNames[step.seatID] ?? step.seatID}</span>
                  </div>
                );
              })}
            </div>
            <div className="prompt-message">{roll.nextSeatID !== undefined ? roll.status
              : roll.roll.winnerSeatID === table.state.localSeatID ? "You go first." : `${table.state.seatNames[roll.roll.winnerSeatID]} goes first.`}</div>
            {roll.nextSeatID === table.state.localSeatID && (
              <button type="button" className="plaque primary" disabled={roll.hasRolled || table.state.stage !== "playing"}
                onClick={() => { try { table.rollStartingPlayer(); } catch (error) { fail(error); } }}>Roll the D20</button>
            )}
          </div>
        </div>
      )}

      {confirmConcede && (
        <div className="modal">
          <div className="panel">
            <h2 className="title">Concede?</h2>
            <p className="muted">{table.solo ? "The AI wins this game." : "You leave this game. The other players are told at once."}</p>
            <div className="row" style={{ justifyContent: "center" }}>
              <button type="button" className="plaque" onClick={() => setConfirmConcede(false)}>Keep playing</button>
              <button type="button" className="plaque danger" onClick={() => { setConfirmConcede(false); table.concede().catch(fail); }}>Concede</button>
            </div>
          </div>
        </div>
      )}

      {(finished || table.state.stage === "failed") && (
        <div className="modal result">
          <div className="panel">
            <h2 className="title">{finished ? (won ? "Victory" : "Defeat") : table.solo ? "Game stopped" : "Table closed"}</h2>
            <p className="muted">{finished ? resultText(snapshot, viewer) : table.state.status}</p>
            {table.rematch && <button type="button" className="plaque primary" onClick={() => table.rematch?.()}>Play again</button>}
            <button type="button" className={`plaque ${table.rematch ? "" : "primary"}`} onClick={() => table.leave()}>Back to the tavern</button>
          </div>
        </div>
      )}
    </div>
  );
}

/** "AI 1 won the game on turn 9." (a draw names no one). */
function resultText(snapshot: GameSnapshot, viewer: string | undefined) {
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
