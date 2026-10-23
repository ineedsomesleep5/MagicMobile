/**
 * Every menu page under Arena's top bar over the tavern room, and the games they start (iOS OnDeviceRootView's Arena
 * menus): Home, the Play panel, the Custom Table, the pages behind the tabs and the panels (Options, Updates, Learn).
 * The engine starts loading when the menus open, so it is ready by the time a deck is chosen. A finished solo game is
 * recorded in this browser's player record (Ranked moves your rank), as the phones record theirs.
 */
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { AIDeckPool, type AIDeck, playerDeckID } from "../../core/aiDeckPool";
import { CommanderBracket } from "../../core/brackets";
import type { DeckList, DeckResolver } from "../../core/deckResolver";
import { type PlayMode, PlayerRecordStore, startingPlayerMode } from "../../core/playerRecord";
import { type RankChange, RankLadder, RankPosition, RankTier } from "../../core/rankLadder";
import { type LocalEngine, localEngine } from "../../engine/localEngine";
import { SoloTable, type SoloSetup } from "../../table/soloTable";
import { gameAudio } from "../audio";
import { GameScreen } from "../GameScreen";
import { storage } from "../storage";
import { CustomTable, type AIDeckGroup } from "./CustomTable";
import type { DeckBoxModel } from "./DeckBox";
import { DecksPage } from "./DecksPage";
import { Home, type HomeContent } from "./Home";
import { MenuPanel, MetalDefs, PanelHeader, useMenuZoom } from "./kit";
import { LearnPanel } from "./Learn";
import { Options } from "./Options";
import { startPerformanceSample } from "./performanceLog";
import { type ArenaPlayMode, type DeckSection, PlayPanel, type PlayModel, type PlayTab, type RecentGame } from "./PlayPanel";
import { ProfilePage } from "./ProfilePage";
import { RankedPage } from "./RankedPage";
import { RoomBackdrop } from "./RoomBackdrop";
import { type MenuTab, TopBar } from "./TopBar";
import { UpdatesPanel } from "./Updates";
import "./menus.css";

export interface MenuData { resolver: DeckResolver; precons: DeckList[]; pool: AIDeckPool }

const read = (key: string, fallback: string) => storage.get(key) ?? fallback;
const readNumber = (key: string, fallback: number, min: number, max: number) => {
  const value = Number.parseInt(storage.get(key) ?? "", 10);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
};
/** A value kept in this browser like the phones' @AppStorage: read once, written on every change. */
function useStored<T extends string | number>(key: string, initial: () => T): [T, (value: T) => void] {
  const [value, setValue] = useState<T>(initial);
  return [value, useCallback((next: T) => { setValue(next); storage.set(key, String(next)); }, [key])];
}

const useEngine = (engine: LocalEngine) => {
  useSyncExternalStore((listener) => engine.subscribe(listener), () => engine.version);
  return engine.state;
};

/** A name the table accepts (OnDeviceSetupModel.playerName): 1–24 characters once trimmed. */
const validPlayerName = (name: string) => name.trim().length >= 1 && name.trim().length <= 24;

interface ActiveGame { table: SoloTable; key: number; mode: PlayMode; deck: AIDeck; deckBracket: number; opponents: AIDeck[]; skill: number }

export function MenuShell({ data, onJoin, initialJoinCode = "" }: {
  data: MenuData; onJoin: (code: string, name: string, deck: DeckList) => void; initialJoinCode?: string;
}) {
  const engine = localEngine();
  const engineState = useEngine(engine);
  const zoom = useMenuZoom();
  useEffect(() => { engine.start().catch(() => undefined); }, [engine]);
  const record = useMemo(() => new PlayerRecordStore(storage), []);
  const [recordVersion, setRecordVersion] = useState(0);
  useEffect(() => { record.refreshSeason(); setRecordVersion((v) => v + 1); }, [record]);

  const { pool } = data;
  // Every deck by its selection id: the precons, then the included decks (the phones' "precon:…" and "included:…").
  const deckFor = useCallback((id: string): AIDeck | undefined =>
    id.startsWith("precon:") ? pool.deck(id.slice(7)) : pool.playerDeck(id), [pool]);
  const box = (id: string, deck: AIDeck): DeckBoxModel => ({ id, name: deck.name, commander: deck.commander, colors: [...deck.colors], subtitle: CommanderBracket.name(deck.bracket) });
  const sections: DeckSection[] = useMemo(() => [
    { id: "precons", title: "Precons", decks: pool.all.filter((d) => !d.id.startsWith("ai-")).map((d) => box(`precon:${d.id}`, d)) },
    ...CommanderBracket.all.map((bracket) => ({
      id: `included-${bracket}`, title: `Included · ${CommanderBracket.name(bracket)}`,
      decks: pool.bracketDecks.filter((d) => d.bracket === bracket).map((d) => box(playerDeckID(d), d)),
    })).filter((s) => s.decks.length > 0),
  ], [pool]);

  const [selectedDeckID, setSelectedDeckID] = useStored("mm.web.deck.selected", () => {
    const saved = storage.get("mm.web.deck.selected");
    return saved && deckFor(saved) ? saved : sections[0].decks[0].id;
  });
  const deck = deckFor(selectedDeckID);
  const deckBracket = deck?.bracket;
  const [mode, setMode] = useStored<ArenaPlayMode>("mm.web.play.mode", () => (["quick", "ranked", "custom"].includes(read("mm.web.play.mode", "")) ? read("mm.web.play.mode", "") : "quick") as ArenaPlayMode);
  const [tab, setTab] = useState<PlayTab>("find");
  const [quickBracket, setQuickBracket] = useStored("mm.web.quick.bracket", () => readNumber("mm.web.quick.bracket", 0, 0, 4));
  const [quickDeckID, setQuickDeckID] = useStored("mm.web.quick.deck", () => read("mm.web.quick.deck", ""));
  const [quickSkill, setQuickSkill] = useStored("mm.web.quick.skill", () => readNumber("mm.web.quick.skill", 3, 1, 10));
  const [starting, setStarting] = useStored<"roll" | "choose">("mm.web.solo.starting", () => (read("mm.web.solo.starting", "roll") === "choose" ? "choose" : "roll"));
  const [playerMode, setPlayerMode] = useStored<"ai" | "online">("mm.web.custom.players", () => (read("mm.web.custom.players", "ai") === "online" ? "online" : "ai"));
  const [aiSkill, setAISkill] = useStored("mm.web.solo.aiSkill", () => readNumber("mm.web.solo.aiSkill", 2, 1, 10));
  const [seats, setSeatsRaw] = useState<string[]>(() => {
    const saved = read("mm.web.custom.seats", "").split(",").filter((id) => pool.deck(id));
    return saved.length >= 1 && saved.length <= 3 ? saved : [pool.all[1 % pool.all.length].id];
  });
  const setSeats = (next: string[]) => { setSeatsRaw(next); storage.set("mm.web.custom.seats", next.join(",")); };
  const [name, setNameRaw] = useState(() => storage.get("mm.web.name") ?? "");
  const setName = (value: string) => { setNameRaw(value); storage.set("mm.web.name", value.trim()); };
  const [joinCode, setJoinCode] = useState(initialJoinCode);

  const [menuTab, setMenuTab] = useState<MenuTab>("home");
  const [playPanel, setPlayPanel] = useState(false);
  // An invite link opens the Custom Table on Online with its code.
  const [custom, setCustom] = useState(initialJoinCode !== "");
  useEffect(() => { if (initialJoinCode) setPlayerMode("online"); }, [initialJoinCode, setPlayerMode]);
  const [panel, setPanel] = useState<"settings" | "updates" | "learn" | "bracket">();
  const [game, setGame] = useState<ActiveGame>();
  /** What the last Ranked game did to your rank, for the result's rank strip. */
  const [rankChange, setRankChange] = useState<{ key: number; change: RankChange }>();
  const [error, setError] = useState<string>();

  useEffect(() => { if (!game) gameAudio.setScene("menu"); }, [game]);
  // Browsers start audio on the first press; the menu's music waits for it.
  useEffect(() => {
    const unlock = () => gameAudio.unlock();
    window.addEventListener("pointerdown", unlock, { capture: true });
    window.addEventListener("keydown", unlock, { capture: true });
    return () => { window.removeEventListener("pointerdown", unlock, { capture: true }); window.removeEventListener("keydown", unlock, { capture: true }); };
  }, []);

  const mismatch = engineState.manifest && (engineState.manifest.catalogueHash !== data.resolver.catalogueHash || engineState.manifest.upstream !== data.resolver.upstreamCommit);
  const engineReady = engineState.stage === "ready" && !mismatch;
  const engineStatus = mismatch ? "This page’s cards don’t match the engine. Reload the page."
    : engineState.stage === "downloading" ? `Downloading the engine… ${engineState.total > 0 ? Math.min(100, Math.floor((engineState.loaded / engineState.total) * 100)) : 0}%`
    : engineState.stage === "failed" ? `The engine could not start. ${engineState.error ?? ""}`
    : engineState.stage !== "ready" ? "Starting the engine…" : undefined;
  const mayStart = engineReady && validPlayerName(name || "Player") && deck !== undefined && !game;

  const rank = record.rank;
  void recordVersion;

  // MARK: Starting and recording games

  const begin = (gameMode: PlayMode, opponents: AIDeck[], skill: number) => {
    if (!deck || deckBracket === undefined) return;
    setError(undefined);
    try {
      const setup: SoloSetup = {
        name: (name.trim() || "Player").slice(0, 24), deck: data.resolver.resolve(deck.deckList),
        aiDecks: opponents.map((o) => data.resolver.resolve(o.deckList)), aiSkill: skill,
        startingPlayerMode: startingPlayerMode(gameMode, starting) as "roll" | "choose",
      };
      const open = (key: number) => {
        const table: SoloTable = new SoloTable(engine, setup, () => setGame(undefined), () => open(key + 1));
        setGame({ table, key, mode: gameMode, deck, deckBracket, opponents, skill });
        void table.start();
      };
      setPlayPanel(false); setCustom(false);
      open((game?.key ?? 0) + 1);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
    }
  };

  const startQuick = () => {
    if (!deck || deckBracket === undefined) return;
    const opponentBracket = quickBracket === 0 ? Math.min(4, deckBracket) : quickBracket;
    const chosen = quickDeckID ? pool.deck(quickDeckID) : undefined;
    // "Match my deck" at Core or below meets a precon: the Core AI decks are tuned tribal lists.
    const opponent = chosen ?? pool.pick({ bracket: opponentBracket, avoidingCommander: deck.commander, recent: [...record.recentAIDecks],
      preconsOnly: quickBracket === 0 && opponentBracket <= 2 });
    if (opponent) begin("quick", [opponent], Math.min(10, Math.max(1, quickSkill)));
  };

  /** Ranked against the AI at your tier (the person queue arrives with accounts). */
  const findRanked = () => {
    if (!deck || deckBracket === undefined || deckBracket > RankTier.maxDeckBracket(rank.position.tier)) return;
    record.refreshSeason();
    const tier = rank.position.tier;
    const opponent = pool.pick({ bracket: RankPosition.opponentBracket(rank.position), avoidingCommander: deck.commander, recent: [...record.recentAIDecks],
      preconsOnly: RankTier.preconOpponentsOnly(tier), onlyPrecons: RankTier.preconOpponentsOnly(tier) ? AIDeckPool.gentlestPrecons : undefined });
    if (opponent) begin("ranked", [opponent], RankTier.aiSkill(tier));
  };

  const startCustom = () => {
    const opponents = seats.map((id) => pool.deck(id)).filter((d): d is AIDeck => d !== undefined);
    if (opponents.length > 0) begin("casual", opponents, aiSkill);
  };

  // The finished game goes in the record once, as the phones record theirs.
  const recorded = useRef<number | undefined>(undefined);
  const sample = useRef<ReturnType<typeof startPerformanceSample> | undefined>(undefined);
  useEffect(() => {
    if (!game) return;
    sample.current?.cancel();
    sample.current = startPerformanceSample(game.mode, game.skill);
    const check = () => {
      const snapshot = game.table.session?.state.snapshot;
      if (!snapshot || snapshot.gameStatus !== "completed" || recorded.current === game.key) return;
      recorded.current = game.key;
      const viewer = snapshot.viewerPlayerId;
      const winners = snapshot.winnerPlayerIds ?? [];
      const outcome = winners.length === 0 ? "draw" : viewer && winners.includes(viewer) ? "win" : "loss";
      const change = record.record({
        mode: game.mode, outcome, opponents: game.opponents.map((o, i) => ({ name: `AI ${i + 1}`, commander: o.commander, isAI: true })),
        opponentBracket: game.opponents[0]?.bracket, aiSkill: game.skill, deckID: game.deck.id, deckName: game.deck.name, commander: game.deck.commander,
        colors: [...game.deck.colors], deckBracket: game.deckBracket, turns: snapshot.turn, aiDeckID: game.opponents[0]?.id,
      });
      if (change) setRankChange({ key: game.key, change });
      sample.current?.finish(snapshot.turn);
      setRecordVersion((v) => v + 1);
    };
    const unsubscribe = game.table.subscribe(check);
    return () => { unsubscribe(); };
  }, [game, record]);

  // MARK: Pages

  const openPlay = (playMode?: ArenaPlayMode) => {
    if (playMode) { setMode(playMode); setTab("find"); }
    setCustom(false); setPlayPanel(true);
  };
  const selectTab = (next: MenuTab) => {
    if (next === "learn") { setPanel("learn"); return; }
    setMenuTab(next); setPlayPanel(false); setCustom(false);
  };

  const homeContent: HomeContent = {
    features: [
      { id: "ranked", kicker: "Ranked season", title: `Ranked · ${RankLadder.seasonName(rank.season)}`, art: { asset: "home-art-ur-dragon", focus: { x: 0.62, y: 0.3 } }, action: () => selectTab("ranked") },
      { id: "board", kicker: "New", title: "The Arena board", art: { asset: "home-art-edgar-markov", focus: { x: 0.55, y: 0.22 } }, action: () => setPanel("updates") },
      { id: "support", kicker: "Support", title: "Enjoying MagicMobile?", art: { asset: "home-art-atraxa", focus: { x: 0.5, y: 0.2 } },
        action: () => window.open("https://magicmobile-downloads.vercel.app/support/", "_blank", "noopener") },
    ],
    tiles: [
      { id: "quick", title: "Quick Match", art: { asset: "home-art-krenko", focus: { x: 0.5, y: 0.38 } }, action: () => openPlay("quick") },
      { id: "ranked", title: "Ranked", art: { asset: "home-art-miirym", focus: { x: 0.55, y: 0.4 } }, action: () => openPlay("ranked") },
      { id: "learn", title: "How to Play", art: { asset: "home-art-giada", focus: { x: 0.6, y: 0.3 } }, action: () => setPanel("learn") },
    ],
    deck: deck ? box(selectedDeckID, deck) : undefined,
    rank: { tier: rank.position.tier, title: RankPosition.title(rank.position), pips: rank.position.pips, pipsPerDivision: RankPosition.pipsPerDivision, mythic: rank.position.tier === "mythic" },
    wins: rank.wins, losses: rank.losses,
    play: () => openPlay(), openDeck: () => openPlay(), openRank: () => selectTab("ranked"),
  };

  const quickResolvedBracket = quickBracket === 0 ? Math.min(4, deckBracket ?? 2) : quickBracket;
  const recent: RecentGame[] = useMemo(() => {
    const seen = new Set<string>();
    return [...record.matches].sort((a, b) => b.date - a.date).flatMap((match) => {
      const key = `${match.mode}|${match.deckID}`;
      const id = deckFor(match.deckID) ? match.deckID : sections.flatMap((s) => s.decks).find((d) => d.id.endsWith(`:${match.deckID}`))?.id;
      if (!id || seen.has(key)) return [];
      seen.add(key);
      return [{ id: match.id, mode: match.mode, deckID: id, deckName: match.deckName, commander: match.commander, colors: match.colors,
        detail: `vs ${match.opponents[0]?.name ?? "the table"}`, won: match.outcome === "draw" ? undefined : match.outcome === "win" }];
    }).slice(0, 6);
  }, [record, recordVersion, deckFor, sections]);

  const playModel: PlayModel = {
    sections, selectedDeckID, selectDeck: setSelectedDeckID, deckBracket, mode, setMode, tab, setTab,
    quickBracket, setQuickBracket, quickDeckID, setQuickDeckID, quickPool: pool.pool(quickResolvedBracket), quickResolvedBracket,
    quickSkill, setQuickSkill, startingPlayer: starting, setStartingPlayer: setStarting, rank, playerMode, setPlayerMode,
    friendWays: ["join"], mayStart, status: error ?? engineStatus, recent,
    close: () => setPlayPanel(false), explainBracket: () => setPanel("bracket"),
    startQuick, findRanked, openCustom: () => { setPlayPanel(false); setCustom(true); },
    rankedHall: () => { setPlayPanel(false); setMenuTab("ranked"); }, leaderboard: () => { setPlayPanel(false); setMenuTab("ranked"); },
    friendWay: () => { setPlayerMode("online"); setPlayPanel(false); setCustom(true); },
    chooseRecent: (g) => { setSelectedDeckID(g.deckID); setMode(g.mode === "quick" ? "quick" : g.mode === "ranked" ? "ranked" : "custom"); },
  };

  const aiGroups: AIDeckGroup[] = [
    { title: "Precons", decks: pool.all.filter((d) => !d.id.startsWith("ai-")).map((d) => ({ id: d.id, name: d.name, commander: d.commander, colors: [...d.colors], bracket: d.bracket })) },
    ...CommanderBracket.all.map((bracket) => ({ title: CommanderBracket.name(bracket), decks: pool.bracketDecks.filter((d) => d.bracket === bracket)
      .map((d) => ({ id: d.id, name: d.name, commander: d.commander, colors: [...d.colors], bracket: d.bracket })) })).filter((g) => g.decks.length > 0),
  ];

  if (game) return <GameScreen key={game.key} table={game.table} rankChange={rankChange?.key === game.key ? rankChange.change : undefined} />;

  const lit = panel === "settings" ? "settings" : panel === "updates" ? "updates" : undefined;
  const covered = panel !== undefined;
  const page = custom ? "custom" : menuTab;
  return (
    <div className="mroot" style={{ zoom }}>
      <MetalDefs />
      <RoomBackdrop dim={playPanel ? 0 : page === "home" ? (covered ? 0.55 : 0) : page === "decks" ? 0.72 : 0.55} still={covered || playPanel} />
      <div className="mpage" style={{ opacity: playPanel ? 0 : 1 }}>
        {page === "custom" && (
          <CustomTable model={{
            deck: deck ? box(selectedDeckID, deck) : undefined, bracket: deckBracket, name, setName, validName: validPlayerName(name || "Player"),
            playerMode, setPlayerMode, seats, setSeats, aiGroups, aiSkill, setAISkill, starting, setStarting, joinCode, setJoinCode,
            status: error ?? engineStatus, mayStart, start: startCustom,
            join: () => { if (deck) onJoin(joinCode, (name.trim() || "Player").slice(0, 24), deck.deckList); },
            changeDeck: () => openPlay("custom"), back: () => openPlay("custom"), explainBracket: () => setPanel("bracket"),
          }} />
        )}
        {page === "home" && <Home content={homeContent} still={covered} />}
        {page === "decks" && <DecksPage sections={sections} selectedDeckID={selectedDeckID} select={setSelectedDeckID} play={() => openPlay()} />}
        {page === "ranked" && <RankedPage rank={rank} record={record} play={() => openPlay("ranked")} />}
        {page === "profile" && <ProfilePage record={record} playerName={name.trim() || "Player"} deckCommanders={pool.all.map((d) => d.commander)}
          onChange={() => setRecordVersion((v) => v + 1)} />}
      </div>
      {playPanel && <PlayPanel model={playModel} />}
      <TopBar selected={covered && lit ? undefined : panel === "learn" ? "learn" : custom ? undefined : menuTab} select={selectTab} lit={lit}
        rank={{ tier: rank.position.tier, title: RankPosition.title(rank.position) }} openRank={() => selectTab("ranked")}
        updates={() => setPanel("updates")} settings={() => setPanel("settings")} />
      <MenuPanel open={panel === "settings"} onClose={() => setPanel(undefined)} label="Options" maxWidth={560} fits>
        <Options onClose={() => setPanel(undefined)} upstream={data.resolver.upstreamCommit} />
      </MenuPanel>
      <MenuPanel open={panel === "updates"} onClose={() => setPanel(undefined)} placement="trailing" label="Updates">
        <UpdatesPanel onClose={() => setPanel(undefined)} />
      </MenuPanel>
      <MenuPanel open={panel === "learn"} onClose={() => setPanel(undefined)} label="How to Play" maxWidth={680} fits>
        <LearnPanel onClose={() => setPanel(undefined)} />
      </MenuPanel>
      <MenuPanel open={panel === "bracket"} onClose={() => setPanel(undefined)} label="Bracket" maxWidth={560} fits>
        <PanelHeader title={deck?.name ?? "Bracket"} onClose={() => setPanel(undefined)} />
        {deckBracket !== undefined && (
          <div className="mbracketsheet">
            <b>{CommanderBracket.title(deckBracket)}</b>
            <p>{CommanderBracket.blurb(deckBracket)}</p>
          </div>
        )}
      </MenuPanel>
    </div>
  );
}
