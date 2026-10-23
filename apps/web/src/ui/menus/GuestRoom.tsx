/**
 * Waiting at a friend's relay table (iOS RelayWaitingRoomView, MatchRoomView): the table's code, who is seated, then the
 * match room with each player's commander and Ready, on a glass plate over the dimmed room. The host's phone runs the
 * game; Ready sends this browser's deck.
 */
import { useState } from "react";
import type { DeckList, DeckResolver } from "../../core/deckResolver";
import type { GuestTable } from "../../table/guestTable";
import { Btn, Caps, MetalDefs, PlayButton, useMenuZoom } from "./kit";
import { RoomBackdrop } from "./RoomBackdrop";

export function GuestRoom({ table, name, deck, resolver, leave }: { table: GuestTable; name: string; deck: DeckList; resolver: DeckResolver; leave: () => void }) {
  const [error, setError] = useState<string>();
  const state = table.state;
  const room = state.room;
  const zoom = useMenuZoom();
  const ready = () => {
    setError(undefined);
    try { table.markReady(name, resolver.resolve(deck)); } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };
  return (
    <div className="mroot" style={{ zoom }}>
      <MetalDefs />
      <RoomBackdrop dim={0.55} />
      <div className="mguest">
        <div className="mcard mguestcard">
          <h1>{state.tableCode ? `Table ${state.tableCode}` : "Online table"}</h1>
          <p className="mguestatus" aria-live="polite">{error ?? state.status}</p>
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
              </li>
            ))}
          </ul>
          {room?.aiSummary && <p className="mnote">{room.aiSummary}</p>}
          <div className="mguestactions">
            <Btn kind="secondary" onClick={leave}>Leave</Btn>
            {room && <div className="mguestready"><PlayButton size={18} disabled={room.localReady} onClick={ready}>{room.localReady ? "Ready" : "Ready up"}</PlayButton></div>}
          </div>
        </div>
      </div>
    </div>
  );
}
