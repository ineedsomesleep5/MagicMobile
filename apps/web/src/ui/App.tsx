import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { AIDeckPool } from "../core/aiDeckPool";
import { DeckResolver, type DeckList } from "../core/deckResolver";
import { TableJoinLink } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { GuestTable } from "../table/guestTable";
import { RELAY_ADAPTER_VERSION } from "../table/lobby";
import { PreviewRelay } from "../table/previewHost";
import { setArtResolver } from "./cardArt";
import { GameScreen } from "./GameScreen";
import { BrandMark } from "./menus/BrandMark";
import { GuestRoom } from "./menus/GuestRoom";
import { type MenuData, MenuShell } from "./menus/MenuShell";
import "./menus/menus.css";

/** A code from /join/CODE, ?code=CODE or a pasted link. */
const initialCode = () => {
  const path = /\/join\/([A-Za-z0-9]{6})\/?$/.exec(location.pathname)?.[1];
  return TableJoinLink.normalized(path ?? new URLSearchParams(location.search).get("code") ?? "") ?? "";
};

export const useTable = (table: GameTable) => {
  useSyncExternalStore((listener) => table.subscribe(listener), () => table.version);
  return table;
};

export function App() {
  const [data, setData] = useState<MenuData>();
  const [loadError, setLoadError] = useState<string>();
  useEffect(() => {
    Promise.all([
      fetch("/generated/printings.tsv").then((r) => r.text()),
      fetch("/generated/precons.json").then((r) => r.json()),
      fetch("/generated/ai-decks.json").then((r) => r.json()),
    ]).then(([tsv, precons, aiDecks]) => {
      const resolver = new DeckResolver(tsv);
      setArtResolver(resolver);
      setData({ resolver, precons: precons.decks, pool: new AIDeckPool(aiDecks, precons) });
    }).catch((error) => setLoadError(error instanceof Error ? error.message : String(error)));
  }, []);
  if (!data) return <Loading error={loadError} />;
  return <Root data={data} />;
}

/** The mark on the room's colour while the cards load, as the phones' launch screen. */
function Loading({ error }: { error?: string }) {
  return (
    <div className="mroot mloading">
      <BrandMark size={96} glint />
      {error && <p>{error}</p>}
    </div>
  );
}

interface Joining { code: string; name: string; deck: DeckList }

/** The menus, or a friend's relay table joined from them (or from a /join/CODE link). */
function Root({ data }: { data: MenuData }) {
  const [joining, setJoining] = useState<Joining>();
  const code = useMemo(initialCode, []);
  if (joining) return <Guest data={data} joining={joining} leave={() => setJoining(undefined)} />;
  return <MenuShell data={data} initialJoinCode={code} onJoin={(join, name, deck) => setJoining({ code: join, name, deck })} />;
}

function Guest({ data, joining, leave }: { data: MenuData; joining: Joining; leave: () => void }) {
  const table = useMemo(() => {
    const identity = { upstreamCommit: data.resolver.upstreamCommit, catalogueHash: data.resolver.catalogueHash, adapterVersion: RELAY_ADAPTER_VERSION };
    const preview = import.meta.env.DEV && new URLSearchParams(location.search).has("preview");
    return preview ? new GuestTable(identity, () => new PreviewRelay(identity) as never) : new GuestTable(identity);
  }, [data]);
  useTable(table);
  useEffect(() => {
    try { table.join(joining.code, joining.name, data.resolver.resolve(joining.deck)); } catch { /* the room shows the failure */ }
    const visibility = () => table.setForeground(document.visibilityState === "visible");
    const leaving = () => table.leave();
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pagehide", leaving);
    return () => { document.removeEventListener("visibilitychange", visibility); window.removeEventListener("pagehide", leaving); };
  }, [table, joining, data]);
  const stage = table.state.stage;
  // A closed table (left, or the game over and left) returns to the menus.
  useEffect(() => { if (stage === "idle" && table.state.status === "Match closed.") leave(); }, [stage, table, leave]);
  if (stage === "playing" || stage === "starting" || (stage === "failed" && table.session)) return <GameScreen table={table} />;
  return <GuestRoom table={table} name={joining.name} deck={joining.deck} resolver={data.resolver} leave={() => { table.leave(); leave(); }} />;
}
