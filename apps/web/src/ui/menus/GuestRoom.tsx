/**
 * Waiting at a relay table, joined or hosted (iOS RelayTablePanel, RelayWaitingRoomView, MatchRoomView): the table's
 * code (in two groups of three, with the invite link to copy while you host), who is seated (the host can remove a
 * joiner while the table fills), then the match room with each player's commander and Ready, on a glass plate over the
 * dimmed room. The host's engine runs the game; Ready sends this browser's deck.
 */
import { useState } from "react";
import type { DeckList, DeckResolver } from "../../core/deckResolver";
import { TableJoinLink } from "../../core/tableChat";
import type { J } from "../../core/json";
import type { TableState } from "../../table/guestTable";
import { Btn, Caps, MetalDefs, PlayButton, Question, useMenuZoom } from "./kit";
import { RoomBackdrop } from "./RoomBackdrop";

/** What the room needs from a GuestTable or a HostTable. */
export interface RoomTable {
  state: TableState;
  localPeerID?: string;
  markReady(name: string, deck: J): void;
  /** Hosts only: removes a joiner while the table fills. */
  remove?(peerID: string): void;
}

export function GuestRoom({ table, name, deck, resolver, leave, hosting, waitingFor, cancelWait }: {
  table: RoomTable; name: string; deck: DeckList; resolver: DeckResolver; leave: () => void;
  /** This browser hosts the table. */
  hosting?: boolean;
  /** A challenge sent from this table, waiting for the friend's answer. */
  waitingFor?: string;
  cancelWait?: () => void;
}) {
  const [error, setError] = useState<string>();
  const [copied, setCopied] = useState(false);
  const [removing, setRemoving] = useState<{ id: string; name: string }>();
  const state = table.state;
  const room = state.room;
  const zoom = useMenuZoom();
  const ready = () => {
    setError(undefined);
    try { table.markReady(name, resolver.resolve(deck)); } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };
  const link = state.tableCode ? TableJoinLink.url(state.tableCode) : undefined;
  const code = state.tableCode ? `${state.tableCode.slice(0, 3)} ${state.tableCode.slice(3)}` : undefined;
  return (
    <div className="mroot" style={{ zoom }}>
      <MetalDefs />
      <RoomBackdrop dim={0.55} />
      <div className="mguest">
        <div className="mcard mguestcard" data-id={hosting ? "relay.host.room" : "relay.guest.room"}>
          <h1>{code ? `Table ${code}` : hosting ? "Opening a table…" : "Online table"}</h1>
          <p className="mguestatus" aria-live="polite">{error ?? (waitingFor ? `Waiting for ${waitingFor} to answer…` : state.status)}</p>
          {hosting && link && !room && !waitingFor && (
            <div className="mguestlink">
              <Btn kind="secondary" compact className="pill" id="relay.copyLink"
                onClick={() => { void navigator.clipboard?.writeText(link).then(() => { setCopied(true); window.setTimeout(() => setCopied(false), 1500); }); }}>
                {copied ? "Link copied" : "Copy invite link"}
              </Btn>
            </div>
          )}
          <Caps text={room ? "Match room" : "Seated"} />
          <ul className="mguestseats">
            {room ? room.players.map((player) => (
              <li key={player.id}>
                <span className="grow"><b>{player.name}</b><small>{player.commanders.join(" · ") || (player.isReady ? "Ready" : "Choosing a deck…")}</small></span>
                {player.isHost && <em>Host</em>}
                <em className={player.isReady ? "ready" : ""}>{player.isReady ? "Ready" : "Waiting"}</em>
              </li>
            )) : state.waiting.map((peer, index) => (
              <li key={peer.id}>
                <span className="grow"><b>{peer.name}</b></span>
                {index === 0 && <em>Host</em>}
                {peer.id === table.localPeerID && <em className="ready">You</em>}
                {hosting && table.remove && index > 0 && peer.id !== table.localPeerID && (
                  <Btn kind="secondary" compact className="pill" onClick={() => setRemoving({ id: peer.id, name: peer.name })}>Remove</Btn>
                )}
              </li>
            ))}
          </ul>
          {room?.aiSummary && <p className="mnote">{room.aiSummary}</p>}
          <div className="mguestactions">
            {waitingFor && cancelWait ? <Btn kind="secondary" onClick={cancelWait}>Cancel challenge</Btn> : <Btn kind="secondary" onClick={leave}>Leave</Btn>}
            {room && <div className="mguestready"><PlayButton size={18} disabled={room.localReady} onClick={ready}>{room.localReady ? "Ready" : "Ready up"}</PlayButton></div>}
          </div>
        </div>
      </div>
      {removing && (
        <Question title={`Remove ${removing.name}?`} action="Remove" danger onCancel={() => setRemoving(undefined)}
          onConfirm={() => { table.remove?.(removing.id); setRemoving(undefined); }} />
      )}
    </div>
  );
}
