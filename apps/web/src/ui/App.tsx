import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { DeckResolver, type DeckList } from "../core/deckResolver";
import { TableJoinLink } from "../core/tableChat";
import { GuestTable } from "../table/guestTable";
import { RELAY_ADAPTER_VERSION } from "../table/lobby";
import { setArtResolver } from "./cardArt";
import { GameScreen } from "./GameScreen";
import { PreviewRelay } from "../table/previewHost";

interface Loaded { resolver: DeckResolver; decks: DeckList[] }

const storage = {
  get: (key: string) => { try { return localStorage.getItem(key) ?? undefined; } catch { return undefined; } },
  set: (key: string, value: string) => { try { localStorage.setItem(key, value); } catch { /* private window */ } },
};

/** A code from /join/CODE, ?code=CODE or a pasted link. */
const initialCode = () => {
  const path = /\/join\/([A-Za-z0-9]{6})\/?$/.exec(location.pathname)?.[1];
  return TableJoinLink.normalized(path ?? new URLSearchParams(location.search).get("code") ?? "") ?? "";
};

export const useTable = (table: GuestTable) => {
  useSyncExternalStore((listener) => table.subscribe(listener), () => table.version);
  return table;
};

export function App() {
  const [loaded, setLoaded] = useState<Loaded>();
  const [loadError, setLoadError] = useState<string>();
  useEffect(() => {
    Promise.all([fetch("/generated/printings.tsv").then((r) => r.text()), fetch("/generated/precons.json").then((r) => r.json())])
      .then(([tsv, precons]) => {
        const resolver = new DeckResolver(tsv);
        setArtResolver(resolver);
        setLoaded({ resolver, decks: precons.decks });
      })
      .catch((error) => setLoadError(error instanceof Error ? error.message : String(error)));
  }, []);
  if (loadError) return <div className="screen"><div className="panel join"><h1 className="title">MagicMobile</h1><p className="error">{loadError}</p></div></div>;
  if (!loaded) return <div className="screen"><div className="panel join"><h1 className="title">MagicMobile</h1><p className="muted">Opening the card catalogue…</p></div></div>;
  return <Table loaded={loaded} />;
}

function Table({ loaded }: { loaded: Loaded }) {
  const table = useMemo(() => {
    const identity = { upstreamCommit: loaded.resolver.upstreamCommit, catalogueHash: loaded.resolver.catalogueHash, adapterVersion: RELAY_ADAPTER_VERSION };
    const preview = import.meta.env.DEV && new URLSearchParams(location.search).has("preview");
    return preview ? new GuestTable(identity, () => new PreviewRelay(identity) as never) : new GuestTable(identity);
  }, [loaded]);
  useTable(table);
  const [name, setName] = useState(storage.get("mm.web.name") ?? "");
  const [deckID, setDeckID] = useState(storage.get("mm.web.deck") ?? loaded.decks[0].id);
  const deck = loaded.decks.find((d) => d.id === deckID) ?? loaded.decks[0];

  useEffect(() => {
    const visibility = () => table.setForeground(document.visibilityState === "visible");
    const leaving = () => table.leave();
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pagehide", leaving);
    return () => { document.removeEventListener("visibilitychange", visibility); window.removeEventListener("pagehide", leaving); };
  }, [table]);

  const stage = table.state.stage;
  if (stage === "playing" || stage === "starting" || (stage === "failed" && table.session)) {
    return <GameScreen table={table} />;
  }
  if (stage === "room") return <RoomScreen table={table} name={name} deck={deck} resolver={loaded.resolver} decks={loaded.decks} setDeckID={setDeckID} />;
  return (
    <JoinScreen table={table} decks={loaded.decks} resolver={loaded.resolver} name={name} setName={setName} deckID={deck.id}
      setDeckID={(id) => { setDeckID(id); storage.set("mm.web.deck", id); }} />
  );
}

function JoinScreen({ table, decks, resolver, name, setName, deckID, setDeckID }: {
  table: GuestTable; decks: DeckList[]; resolver: DeckResolver; name: string; setName: (v: string) => void; deckID: string; setDeckID: (v: string) => void;
}) {
  const [code, setCode] = useState(initialCode);
  const [error, setError] = useState<string>();
  const state = table.state;
  const busy = state.stage === "joining" || state.stage === "waiting";
  const join = () => {
    setError(undefined);
    try {
      const deck = decks.find((d) => d.id === deckID)!;
      storage.set("mm.web.name", name.trim());
      table.join(code, name, resolver.resolve(deck));
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };
  return (
    <div className="screen">
      <form className="panel join" onSubmit={(event) => { event.preventDefault(); if (!busy) join(); }}>
        <header><img src="/tavern/seal.webp" alt="" /><div><h1 className="title">MagicMobile</h1><div className="muted">Join a friend’s table from your desktop</div></div></header>
        {busy ? (
          <>
            <div className="prompt-message">{state.status}</div>
            <ul className="seats">
              {state.waiting.map((peer, index) => (
                <li key={peer.id}><span className="grow">{peer.name}</span>{index === 0 && <span className="tag">Host</span>}{peer.id === table.localPeerID && <span className="tag parchment">You</span>}</li>
              ))}
            </ul>
            <button type="button" className="plaque" onClick={() => table.leave()}>Leave table</button>
          </>
        ) : (
          <>
            <label className="field"><span className="label">Your name</span>
              <input className="slot" value={name} maxLength={40} autoComplete="nickname" onChange={(e) => setName(e.target.value)} placeholder="Name at the table" required /></label>
            <label className="field"><span className="label">Table code</span>
              <input className="slot" value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="ABC234" spellCheck={false} required
                style={{ letterSpacing: ".2em", fontWeight: 800 }} /></label>
            <label className="field"><span className="label">Deck</span>
              <select className="slot" value={deckID} onChange={(e) => setDeckID(e.target.value)}>
                {decks.map((d) => <option key={d.id} value={d.id}>{d.name}{d.subtitle ? ` — ${d.subtitle}` : ""}</option>)}
              </select></label>
            {(error || state.stage === "failed") && <div className="error">{error ?? state.status}</div>}
            <button type="submit" className="plaque primary" disabled={name.trim().length === 0 || code.trim().length === 0}>Join table</button>
            <p className="small-print">The host’s phone runs the game. Ask them for the six-letter code on their table screen, and keep this tab in front while you play.</p>
          </>
        )}
      </form>
      {window.innerWidth < 900 && <div className="toast narrow-note">MagicMobile on the web is built for a desktop browser window.</div>}
    </div>
  );
}

function RoomScreen({ table, name, deck, resolver, decks, setDeckID }: {
  table: GuestTable; name: string; deck: DeckList; resolver: DeckResolver; decks: DeckList[]; setDeckID: (id: string) => void;
}) {
  const room = table.state.room;
  const [error, setError] = useState<string>();
  const ready = () => {
    setError(undefined);
    try { table.markReady(name, resolver.resolve(deck)); } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };
  return (
    <div className="screen">
      <div className="panel join">
        <h2 className="panel-title">Match room · {table.state.tableCode}</h2>
        <ul className="seats">
          {room?.players.map((player) => (
            <li key={player.id}>
              <span className="grow">{player.name}<br /><span className="small-print">{player.commanders.join(" · ") || (player.isReady ? "Ready" : "Choosing a deck…")}</span></span>
              {player.isHost && <span className="tag">Host</span>}
              {player.isReady ? <span className="tag ember">Ready</span> : <span className="tag">Waiting</span>}
            </li>
          ))}
        </ul>
        {room?.aiSummary && <div className="small-print">{room.aiSummary}</div>}
        <label className="field"><span className="label">Your deck</span>
          <select className="slot" value={deck.id} disabled={room?.localReady} onChange={(e) => setDeckID(e.target.value)}>
            {decks.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
          </select></label>
        {error && <div className="error">{error}</div>}
        <div className="prompt-message">{table.state.status}</div>
        <div className="row">
          <button type="button" className="plaque" onClick={() => table.leave()}>Leave</button>
          <button type="button" className="plaque primary" style={{ flex: 1 }} disabled={room?.localReady} onClick={ready}>{room?.localReady ? "Ready" : "Ready up"}</button>
        </div>
      </div>
    </div>
  );
}
