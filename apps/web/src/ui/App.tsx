import { useEffect, useMemo, useState, useSyncExternalStore } from "react";
import { AIDeckPool } from "../core/aiDeckPool";
import { DeckResolver } from "../core/deckResolver";
import { TableJoinLink } from "../core/tableChat";
import type { GameTable } from "../table/gameTable";
import { setArtResolver } from "./cardArt";
import { BrandMark } from "./menus/BrandMark";
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

/** The menus; a /join/CODE link opens the Custom Table on Online with its code, and the menus join or host tables. */
function Root({ data }: { data: MenuData }) {
  const code = useMemo(initialCode, []);
  return <MenuShell data={data} initialJoinCode={code} />;
}
