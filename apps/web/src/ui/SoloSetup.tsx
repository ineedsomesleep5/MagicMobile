/**
 * Solo against the XMage AI, run on this computer: pick a precon for each side, the AI's skill and who goes
 * first, as on the phones' AI setup (OnDeviceRootView), then play on the same table a relay guest uses.
 * The engine starts loading as soon as this screen opens, so it is usually ready by the time the decks are chosen.
 */
import { useEffect, useState, useSyncExternalStore } from "react";
import type { DeckList } from "../core/deckResolver";
import { type LocalEngine, localEngine } from "../engine/localEngine";
import { SoloTable, type SoloSetup, type StartingPlayerMode } from "../table/soloTable";
import type { Loaded } from "./App";
import { cardImageURL } from "./cardArt";
import { GameScreen } from "./GameScreen";
import { storage } from "./storage";

const useEngine = (engine: LocalEngine) => {
  useSyncExternalStore((listener) => engine.subscribe(listener), () => engine.version);
  return engine.state;
};

export function Solo({ loaded, onJoin }: { loaded: Loaded; onJoin: () => void }) {
  const engine = localEngine();
  const [game, setGame] = useState<{ table: SoloTable; key: number }>();
  const begin = (setup: SoloSetup) => {
    const open = (key: number) => {
      const table: SoloTable = new SoloTable(engine, setup, () => setGame(undefined), () => open(key + 1));
      setGame({ table, key });
      void table.start();
    };
    open((game?.key ?? 0) + 1);
  };
  if (game) return <GameScreen key={game.key} table={game.table} />;
  return <SetupScreen loaded={loaded} engine={engine} onStart={begin} onJoin={onJoin} />;
}

/** What each AI skill does (packages/ondevice-engine/docs/PROTOCOL.md, AI seats). */
const skillText = (skill: number) => {
  const think = `Thinks up to ${skill * 3} s a decision.`;
  if (skill === 1) return `Looks one action ahead and makes deliberate mistakes (15%). ${think}`;
  if (skill === 2) return `Looks two actions ahead and makes deliberate mistakes (10%). ${think}`;
  if (skill === 3) return `Looks three actions ahead; deliberate mistakes 5%. ${think}`;
  if (skill === 4) return `Full search, no deliberate mistakes. ${think}`;
  return `Expert: plans its attacks and blocks. ${think}`;
};

const startingText: Record<StartingPlayerMode, string> = {
  choose: "XMage asks you who starts.",
  roll: "You and the AI each roll a D20. Highest starts; ties roll again.",
};

const savedNumber = (key: string, fallback: number, min: number, max: number) => {
  const value = Number.parseInt(storage.get(key) ?? "", 10);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
};

function SetupScreen({ loaded, engine, onStart, onJoin }: {
  loaded: Loaded; engine: LocalEngine; onStart: (setup: SoloSetup) => void; onJoin: () => void;
}) {
  const decks = loaded.decks;
  const pick = (key: string, fallback: string) => decks.find((d) => d.id === storage.get(key))?.id ?? fallback;
  const [deckID, setDeckID] = useState(() => pick("mm.web.solo.deck", decks[0].id));
  const [aiDeckID, setAIDeckID] = useState(() => pick("mm.web.solo.aiDeck", decks[1 % decks.length].id));
  // The phones' default skill is 2.
  const [aiSkill, setAISkill] = useState(() => savedNumber("mm.web.solo.aiSkill", 2, 1, 10));
  const [starting, setStarting] = useState<StartingPlayerMode>(() => (storage.get("mm.web.solo.starting") === "choose" ? "choose" : "roll"));
  const [name, setName] = useState(() => storage.get("mm.web.name") ?? "");
  const [error, setError] = useState<string>();
  const state = useEngine(engine);

  useEffect(() => { engine.start().catch(() => { /* shown by the engine status */ }); }, [engine]);

  const mismatch = state.manifest && (state.manifest.catalogueHash !== loaded.resolver.catalogueHash || state.manifest.upstream !== loaded.resolver.upstreamCommit)
    ? "This page’s card catalogue does not match the engine’s build. Rebuild the engine or the page data so they come from the same XMage commit."
    : undefined;
  const ready = state.stage === "ready" && !mismatch;

  const start = () => {
    setError(undefined);
    const deck = decks.find((d) => d.id === deckID)!;
    const aiDeck = decks.find((d) => d.id === aiDeckID)!;
    try {
      storage.set("mm.web.solo.deck", deckID);
      storage.set("mm.web.solo.aiDeck", aiDeckID);
      storage.set("mm.web.solo.aiSkill", String(aiSkill));
      storage.set("mm.web.solo.starting", starting);
      storage.set("mm.web.name", name.trim());
      onStart({ name: name.trim() || "Player", deck: loaded.resolver.resolve(deck), aiDeck: loaded.resolver.resolve(aiDeck), aiSkill, startingPlayerMode: starting });
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    }
  };

  return (
    <div className="screen">
      <div className="panel setup">
        <header className="setup-header">
          <img src="/tavern/seal.webp" alt="" />
          <div className="grow">
            <h1 className="title">MagicMobile</h1>
            <div className="muted">Play the XMage AI. The whole game runs on this computer.</div>
          </div>
          <button type="button" className="plaque compact" onClick={onJoin}>Join a friend’s table</button>
        </header>

        <section>
          <h2 className="panel-title">Your deck</h2>
          <DeckShelf decks={decks} selected={deckID} onSelect={setDeckID} label="Your deck" />
        </section>
        <section>
          <h2 className="panel-title">The AI’s deck</h2>
          <DeckShelf decks={decks} selected={aiDeckID} onSelect={setAIDeckID} label="The AI’s deck" />
        </section>

        <div className="setup-options">
          <label className="option">
            <span className="option-head"><span className="label">Your name</span></span>
            <input className="slot" value={name} maxLength={40} autoComplete="nickname" placeholder="Player" onChange={(e) => setName(e.target.value)} />
          </label>
          <div className="option">
            <div className="option-head">
              <span className="label">AI skill: {aiSkill}</span>
              <div className="stepper">
                <button type="button" aria-label="Lower AI skill" disabled={aiSkill <= 1} onClick={() => setAISkill(Math.max(1, aiSkill - 1))}>−</button>
                <output aria-live="polite">{aiSkill}</output>
                <button type="button" aria-label="Raise AI skill" disabled={aiSkill >= 10} onClick={() => setAISkill(Math.min(10, aiSkill + 1))}>+</button>
              </div>
            </div>
            <div className="small-print">{skillText(aiSkill)}</div>
          </div>
          <div className="option">
            <div className="option-head">
              <span className="label">Who goes first?</span>
              <div className="segmented" role="group" aria-label="Who goes first?">
                <button type="button" aria-pressed={starting === "choose"} onClick={() => setStarting("choose")}>Choose</button>
                <button type="button" aria-pressed={starting === "roll"} onClick={() => setStarting("roll")}>Roll D20</button>
              </div>
            </div>
            <div className="small-print">{startingText[starting]}</div>
          </div>
        </div>

        <EngineStatus engine={engine} mismatch={mismatch} />
        {error && <div className="error">{error}</div>}
        <button type="button" className="plaque primary wide" disabled={!ready} onClick={start}>{ready ? "Start the game" : startLabel(state.stage, state.loaded, state.total)}</button>
      </div>
      {window.innerWidth < 760 && <div className="toast narrow-note">MagicMobile on the web is built for a desktop browser window.</div>}
    </div>
  );
}

const megabytes = (bytes: number) => Math.round(bytes / 1_000_000);
const percent = (loaded: number, total: number) => (total > 0 ? Math.min(100, Math.floor((loaded / total) * 100)) : 0);

function startLabel(stage: string, loaded: number, total: number) {
  if (stage === "downloading") return `Downloading the engine… ${percent(loaded, total)}%`;
  if (stage === "failed") return "The engine could not start";
  return "Starting the engine…";
}

function DeckShelf({ decks, selected, onSelect, label }: { decks: DeckList[]; selected: string; onSelect: (id: string) => void; label: string }) {
  return (
    <div className="deck-shelf" role="radiogroup" aria-label={label}>
      {decks.map((deck) => {
        const commander = deck.entries.find((e) => e.section === "commanders")?.name ?? deck.name;
        return (
          <button key={deck.id} type="button" role="radio" aria-checked={deck.id === selected} className="deck-tile" onClick={() => onSelect(deck.id)}
            title={`${deck.name}: ${commander}`}>
            <img src={cardImageURL(commander, "art_crop")} alt="" crossOrigin="anonymous" loading="lazy" />
            <span className="deck-body">
              <span className="deck-name">{deck.name}</span>
              <span className="pips">{[...(deck.colors ?? "")].map((c) => <span key={c} className="pip" style={{ backgroundImage: `url(/tavern/mana-${c}.webp)` }} />)}</span>
              <span className="small-print">{deck.subtitle}</span>
            </span>
          </button>
        );
      })}
    </div>
  );
}

function EngineStatus({ engine, mismatch }: { engine: LocalEngine; mismatch?: string }) {
  const state = useEngine(engine);
  const total = state.total || state.manifest?.wasm.bytes || 0;
  let title: string;
  let detail: string | undefined;
  let bar: number | "busy" | undefined;
  switch (state.stage) {
    case "idle": case "manifest": case "checking":
      title = "Preparing the rules engine…"; bar = "busy"; break;
    case "downloading":
      title = `Downloading the XMage rules engine: ${megabytes(state.loaded)} of ${megabytes(total)} MB`;
      detail = "First visit only. It stays on this computer for next time.";
      bar = percent(state.loaded, total); break;
    case "verifying": title = "Checking the download…"; bar = 100; break;
    case "storing": title = "Keeping the engine on this computer…"; bar = 100; break;
    case "compiling":
      title = "Starting the engine…";
      detail = state.cached ? "Loaded from this computer." : undefined;
      bar = "busy"; break;
    case "ready": {
      const seconds = state.timings ? (state.timings.totalMs / 1000).toFixed(1) : undefined;
      title = "The XMage rules engine is ready.";
      detail = [state.cached ? "Loaded from this computer" : "Downloaded", seconds ? `started in ${seconds} s` : undefined].filter(Boolean).join(", ") + ".";
      break;
    }
    default:
      title = "The engine could not start.";
  }
  const kept = state.persisted === true ? "The browser keeps it until you clear this site’s data."
    : state.persisted === false ? "The browser may clear it when the disk is nearly full." : undefined;
  return (
    <div className={`engine-status ${state.stage === "failed" || mismatch ? "failed" : ""}`} aria-live="polite">
      <div className="row" style={{ justifyContent: "space-between" }}>
        <span className="prompt-message">{mismatch ? "The engine and the card catalogue disagree." : title}</span>
        {state.manifest && <span className="small-print" title={state.manifest.engineBuild}>XMage {state.manifest.upstream.slice(0, 7)}</span>}
      </div>
      {bar !== undefined && (
        <div className={`progress ${bar === "busy" ? "busy" : ""}`} role="progressbar" aria-valuemin={0} aria-valuemax={100}
          aria-valuenow={bar === "busy" ? undefined : bar}>
          <span style={bar === "busy" ? undefined : { width: `${bar}%` }} />
        </div>
      )}
      {mismatch && <div className="small-print">{mismatch}</div>}
      {state.stage === "failed" && (
        <>
          <div className="small-print">{state.error}</div>
          <button type="button" className="plaque compact" onClick={() => { engine.reset(); engine.start().catch(() => undefined); }}>Try again</button>
        </>
      )}
      {(detail || kept) && state.stage !== "failed" && <div className="small-print">{[detail, state.stage === "ready" || state.stage === "downloading" ? kept : undefined].filter(Boolean).join(" ")}</div>}
      {state.warning && <div className="small-print">{state.warning}</div>}
    </div>
  );
}
