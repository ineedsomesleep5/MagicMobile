/**
 * Every menu page under Arena's top bar over the tavern room, and the games they start (iOS OnDeviceRootView's Arena
 * menus): Home, the Play panel, the Custom Table, the pages behind the tabs and the panels (Options, Updates, Learn).
 * The engine starts loading when the menus open, so it is ready by the time a deck is chosen. A finished solo game is
 * recorded in this browser's player record (Ranked moves your rank), as the phones record theirs.
 */
import { useCallback, useEffect, useMemo, useRef, useState, useSyncExternalStore } from "react";
import { AIDeckPool, type AIDeck, playerDeckID } from "../../core/aiDeckPool";
import { BracketRules, type BracketRulesFile, CommanderBracket, DeckBracketPreference } from "../../core/brackets";
import { loadCatalogue } from "../../core/deckStudio/catalogue";
import { draftFromDeck, DraftPresentation } from "../../core/deckStudio/draft";
import { DeckLibrary, DeckLibraryRecord } from "../../core/deckStudio/library";
import { DeckSync, supabaseDeckSync, SyncState } from "../../core/deckStudio/sync";
import type { DeckList, DeckResolver } from "../../core/deckResolver";
import { type MatchRecord, type PlayMode, PlayerRecordStore, startingPlayerMode } from "../../core/playerRecord";
import { type RankChange, RankLadder, RankPosition, RankTier } from "../../core/rankLadder";
import { type LocalEngine, localEngine } from "../../engine/localEngine";
import type { FriendChallenge } from "../../core/account";
import { FriendChallengeRules } from "../../core/matchmaking";
import { SupabaseLite } from "../../core/supabaseLite";
import { GuestTable } from "../../table/guestTable";
import { HostTable, type HostKind } from "../../table/hostTable";
import { RELAY_ADAPTER_VERSION } from "../../table/lobby";
import { PreviewRelay } from "../../table/previewHost";
import { SoloTable, type SoloSetup } from "../../table/soloTable";
import { gameAudio } from "../audio";
import { GameScreen } from "../GameScreen";
import { storage } from "../storage";
import { AccountSignInCard, PrivacyCard } from "./AccountCards";
import { account, challenges, completeGoogleSignIn, connectRecord, rankedQueue, useAccount, useWatched } from "./accountSession";
import { ChallengeBanner } from "./ChallengeBanner";
import { GuestRoom } from "./GuestRoom";
import { Conversation } from "./Conversation";
import { CustomTable, type AIDeckGroup } from "./CustomTable";
import { FriendsPanel } from "./FriendsPanel";
import { Leaderboard } from "./Leaderboard";
import { PublicProfile } from "./PublicProfile";
import type { DeckBoxModel } from "./DeckBox";
import { DecksPage, type ShelfDeck } from "./DecksPage";
import { DeckStudioScreen, type StudioRoute } from "./DeckStudio";
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

interface ActiveGame {
  table: SoloTable; key: number; mode: PlayMode; deck: AIDeck; deckBracket: number; opponents: AIDeck[]; skill: number;
  /** A ranked game's server ticket: its result settles there with the game record. */
  ticket?: { id: string; seeded: boolean };
}

/** A relay table this browser joined or hosts, until it closes (the phones' activeMatch with their multiplayer setup). */
interface OnlineGame {
  table: GuestTable | HostTable;
  key: number;
  hosting: boolean;
  mode: PlayMode;
  deck: AIDeck;
  deckBracket: number;
  /** The ranked match both sides report to (ranked queue or a ranked challenge). */
  rankedMatchID?: string;
  /** A challenge sent from this table, waiting for the friend's answer. */
  waitingFor?: string;
}

export function MenuShell({ data, initialJoinCode = "" }: { data: MenuData; initialJoinCode?: string }) {
  const engine = localEngine();
  const engineState = useEngine(engine);
  const zoom = useMenuZoom();
  useEffect(() => { engine.start().catch(() => undefined); }, [engine]);
  const record = useMemo(() => new PlayerRecordStore(storage), []);
  const [recordVersion, setRecordVersion] = useState(0);
  useEffect(() => { record.refreshSeason(); setRecordVersion((v) => v + 1); }, [record]);
  // The player's account: a page coming back from Google finishes signing in and opens the profile; then the profile,
  // friends and rank load, and each refresh settles ranked results and sends finished games.
  const player = useAccount();
  const server = useMemo(() => connectRecord(record, () => setRecordVersion((v) => v + 1)), [record]);
  useEffect(() => {
    void completeGoogleSignIn().then((back) => {
      if (back.kind === "none") { if (account.state.phase === "idle") void account.start(); return; }
      setMenuTab("profile"); setPlayPanel(false); setCustom(false);
      setNotice(back.kind === "signedIn" ? (back.username ? `Signed in as ${back.username}` : "Signed in with Google") : back.message);
    });
    const visible = () => account.setForeground(document.visibilityState === "visible");
    visible();
    document.addEventListener("visibilitychange", visible);
    return () => document.removeEventListener("visibilitychange", visible);
  }, []);

  const { pool } = data;
  // Your own decks (DeckLibraryStore) and the bracket lists that rate them; both are read again when either changes.
  const library = useMemo(() => new DeckLibrary(storage), []);
  const [libraryVersion, setLibraryVersion] = useState(0);
  const libraryChanged = useCallback(() => setLibraryVersion((v) => v + 1), []);
  // Your decks on every phone and browser signed in to this profile (docs/DECK_SYNC.md).
  const deckSync = useMemo(() => new DeckSync(library, new SyncState(storage), supabaseDeckSync((fn, params) => account.api.rpc(fn, params))), [library]);
  const syncDecks = useCallback(async () => {
    if (account.state.phase !== "ready") return;
    const profile = await account.api.userID().catch(() => undefined);
    if (!profile) return;
    try { await deckSync.sync(profile); } catch { /* offline or refused: the next sync tries again */ }
    libraryChanged();
    // Decks from another device arrive without the colours this browser remembers; the catalogue knows them.
    if (library.decks.some((record) => record.commander && library.colors(record.id).length === 0)) {
      const catalogue = await loadCatalogue().catch(() => undefined);
      for (const record of library.decks) {
        const colors = catalogue && library.colors(record.id).length === 0 ? DraftPresentation.colors(draftFromDeck(record), catalogue) : undefined;
        if (colors) library.rememberColors(record.id, colors);
      }
      libraryChanged();
    }
  }, [deckSync, library, libraryChanged]);
  const accountReady = player.state.phase === "ready";
  useEffect(() => {
    if (!accountReady) return;
    void syncDecks();
    const every = window.setInterval(() => { if (document.visibilityState === "visible") void syncDecks(); }, 5 * 60_000);
    const back = () => { if (document.visibilityState === "visible") void syncDecks(); };
    document.addEventListener("visibilitychange", back);
    return () => { window.clearInterval(every); document.removeEventListener("visibilitychange", back); };
  }, [accountReady, player.state.username, syncDecks]);
  // A change here goes up a few seconds after the last one (only when something is waiting to go up).
  useEffect(() => {
    if (!accountReady || !(library.decks.some((record) => deckSync.isDirty(record)) || deckSync.record.tombstones.length > 0)) return;
    const timer = window.setTimeout(() => { void syncDecks(); }, 3000);
    return () => window.clearTimeout(timer);
  }, [libraryVersion, accountReady, syncDecks, deckSync, library]);
  const [bracketRules, setBracketRules] = useState(BracketRules.empty);
  useEffect(() => {
    fetch("/generated/commander-brackets.json").then((r) => (r.ok ? r.json() : Promise.reject(new Error(String(r.status)))))
      .then((file: BracketRulesFile) => setBracketRules(new BracketRules(file))).catch(() => undefined);
  }, []);
  /** A saved deck as the table plays it: rated by its list, raised by the player's own label (DeckBracketPreference). */
  const localDeck = useCallback((record: DeckLibraryRecord): AIDeck => {
    // Sideboard and maybeboard stay out of the game (DeckStudioPlayProjection); any other section reaches the resolver,
    // which names it.
    const full = DeckLibraryRecord.deckList(record);
    const deckList = { ...full, entries: full.entries.filter((entry) => !["sideboard", "maybeboard", "considering"].includes(entry.section.trim().toLowerCase())) };
    const bracket = DeckBracketPreference.effective(bracketRules.evaluateDeck(deckList).minimum, DeckBracketPreference.declared(DeckLibraryRecord.selectionID(record), storage));
    return { id: record.id, name: record.name, subtitle: CommanderBracket.name(bracket), colors: library.colors(record.id).join(""),
      commander: record.commander?.cardName ?? "", bracket, deckList };
  }, [bracketRules, library, libraryVersion]);
  // Every deck by its selection id: your decks, the precons, then the included decks (the phones' "local:…", "precon:…", "included:…").
  const deckFor = useCallback((id: string): AIDeck | undefined => {
    if (id.startsWith("local:")) { const record = library.bySelection(id); return record ? localDeck(record) : undefined; }
    return id.startsWith("precon:") ? pool.deck(id.slice(7)) : pool.playerDeck(id);
  }, [pool, library, localDeck]);
  const box = (id: string, deck: AIDeck): DeckBoxModel => ({ id, name: deck.name, commander: deck.commander || undefined, colors: [...deck.colors], subtitle: CommanderBracket.name(deck.bracket) });
  const sections: DeckSection[] = useMemo(() => [
    ...(library.decks.length > 0 ? [{ id: "mine", title: "My Decks", decks: library.decks.map((r) => box(DeckLibraryRecord.selectionID(r), localDeck(r))) }] : []),
    { id: "precons", title: "Precons", decks: pool.all.filter((d) => !d.id.startsWith("ai-")).map((d) => box(`precon:${d.id}`, d)) },
    ...CommanderBracket.all.map((bracket) => ({
      id: `included-${bracket}`, title: `Included · ${CommanderBracket.name(bracket)}`,
      decks: pool.bracketDecks.filter((d) => d.bracket === bracket).map((d) => box(playerDeckID(d), d)),
    })).filter((s) => s.decks.length > 0),
  ], [pool, library, localDeck]);

  const firstPreconID = `precon:${pool.all.filter((d) => !d.id.startsWith("ai-"))[0]?.id ?? pool.all[0].id}`;
  const [selectedDeckID, setSelectedDeckID] = useStored("mm.web.deck.selected", () => {
    const saved = storage.get("mm.web.deck.selected");
    return saved && deckFor(saved) ? saved : firstPreconID;
  });
  const deck = deckFor(selectedDeckID);
  const deckBracket = deck?.bracket;
  const [mode, setMode] = useStored<ArenaPlayMode>("mm.web.play.mode", () => (["quick", "ranked", "custom"].includes(read("mm.web.play.mode", "")) ? read("mm.web.play.mode", "") : "quick") as ArenaPlayMode);
  const [tab, setTab] = useState<PlayTab>("find");
  const [quickBracket, setQuickBracket] = useStored("mm.web.quick.bracket", () => readNumber("mm.web.quick.bracket", 0, 0, 4));
  const [quickDeckID, setQuickDeckID] = useStored("mm.web.quick.deck", () => read("mm.web.quick.deck", ""));
  const [quickSkill, setQuickSkill] = useStored("mm.web.quick.skill", () => readNumber("mm.web.quick.skill", 3, 1, 10));
  // Easy, Medium or Hard pick the AI's deck by Power and set its skill; Advanced keeps the bracket, deck and skill controls.
  const [quickLevel, setQuickLevel] = useStored("mm.web.quick.level", () => read("mm.web.quick.level", "medium"));
  const [starting, setStarting] = useStored<"roll" | "choose">("mm.web.solo.starting", () => (read("mm.web.solo.starting", "roll") === "choose" ? "choose" : "roll"));
  const [playerMode, setPlayerMode] = useStored<"ai" | "online">("mm.web.custom.players", () => (read("mm.web.custom.players", "ai") === "online" ? "online" : "ai"));
  /** How many people the table this browser hosts seats (RelayTablePanel's player count). */
  const [hostSeats, setHostSeatsRaw] = useStored("mm.web.custom.hostSeats", () => readNumber("mm.web.custom.hostSeats", 2, 2, 4));
  const setHostSeats = (seats: 2 | 3 | 4) => setHostSeatsRaw(seats);
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
  /** Deck Studio over the menus: a deck in the builder, a new deck, or the importer. */
  const [studio, setStudio] = useState<StudioRoute>();
  const [playPanel, setPlayPanel] = useState(false);
  // An invite link opens the Custom Table on Online with its code.
  const [custom, setCustom] = useState(initialJoinCode !== "");
  useEffect(() => { if (initialJoinCode) setPlayerMode("online"); }, [initialJoinCode, setPlayerMode]);
  const [panel, setPanel] = useState<"settings" | "updates" | "learn" | "bracket" | "friends">();
  /** A player's public profile or a conversation, over the menus (and over Friends when opened from it). */
  const [social, setSocial] = useState<{ kind: "profile" | "conversation"; username: string }>();
  const [leaderboard, setLeaderboard] = useState(false);
  useEffect(() => {
    const open = (event: Event) => setSocial({ kind: "profile", username: (event as CustomEvent<string>).detail });
    window.addEventListener("mm:open-profile", open);
    return () => window.removeEventListener("mm:open-profile", open);
  }, []);
  const [game, setGame] = useState<ActiveGame>();
  // Your games from the phone too (mm_my_games), read each time the profile opens and after each game.
  const [remoteGames, setRemoteGames] = useState<readonly MatchRecord[]>([]);
  useEffect(() => {
    if (menuTab !== "profile" || game || player.state.phase !== "ready" || !player.state.username) return;
    let live = true;
    void account.myGames().then((games) => { if (live && games) setRemoteGames(games); });
    return () => { live = false; };
  }, [menuTab, game, player.state.phase, player.state.username]);
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

  const begin = (gameMode: PlayMode, opponents: AIDeck[], skill: number, ticket?: { id: string; seed: bigint }) => {
    if (!deck || deckBracket === undefined) return;
    setError(undefined);
    try {
      const setup: SoloSetup = {
        name: (player.state.username ?? (name.trim() || "Player")).slice(0, 24), deck: data.resolver.resolve(deck.deckList),
        aiDecks: opponents.map((o) => data.resolver.resolve(o.deckList)), aiSkill: skill,
        startingPlayerMode: startingPlayerMode(gameMode, starting) as "roll" | "choose",
        ...(ticket ? { seed: ticket.seed } : {}),
      };
      // A rematch is a new game: a ranked one draws a new ticket through Find Match, so only the first carries this one.
      let first = true;
      const open = (key: number) => {
        const table: SoloTable = new SoloTable(engine, setup, () => setGame(undefined), () => open(key + 1));
        const carried = first && ticket ? { id: ticket.id, seeded: true } : undefined;
        first = false;
        setGame({ table, key, mode: gameMode, deck, deckBracket, opponents, skill, ticket: carried });
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
    const level = quickLevel === "advanced" ? undefined : pool.power?.quickMatch[quickLevel];
    if (level) {
      const opponent = pool.pickByPower({ target: level.power, avoidingCommander: deck.commander, recent: [...record.recentAIDecks] });
      if (opponent) { begin("quick", [opponent], level.skill); return; }
    }
    const opponentBracket = quickBracket === 0 ? Math.min(4, deckBracket) : quickBracket;
    const chosen = quickDeckID ? pool.deck(quickDeckID) : undefined;
    // "Match my deck" at Core or below meets a precon: the Core AI decks are tuned tribal lists.
    const opponent = chosen ?? pool.pick({ bracket: opponentBracket, avoidingCommander: deck.commander, recent: [...record.recentAIDecks],
      preconsOnly: quickBracket === 0 && opponentBracket <= 2 });
    if (opponent) begin("quick", [opponent], Math.min(10, Math.max(1, quickSkill)));
  };

  /**
   * Ranked: a person from the queue when one is searching near your rank (signed in), else an AI at your tier
   * (findRankedMatch).
   */
  const findRanked = () => {
    if (!deck || deckBracket === undefined || deckBracket > RankTier.maxDeckBracket(rank.position.tier)) return;
    record.refreshSeason();
    if (player.state.phase === "ready" && player.state.username) {
      void rankedQueue.search(relayProtocol, RankPosition.step(rank.position), deckBracket).then((outcome) => {
        if (outcome.kind === "ai") startRankedAI();
        else if (outcome.kind === "human") void startRankedHuman(outcome.ticket.matchId!, outcome.ticket.role === "host", outcome.ticket.tableCode, outcome.ticket.opponent);
      });
    } else startRankedAI();
  };

  const startRankedAI = () => {
    if (!deck || deckBracket === undefined) return;
    const tier = rank.position.tier;
    // The deck nearest the division's Power from the tier's bracket or lower (docs/DECK_POWER.md); by bracket if unrated.
    const target = pool.power && AIDeckPool.rankedTarget(RankTier.index(tier), rank.position.division, pool.power.rankedTiers);
    const opponent = (target !== undefined
      ? pool.pickByPower({ target, maxBracket: RankTier.maxDeckBracket(tier), avoidingCommander: deck.commander, recent: [...record.recentAIDecks] })
      : undefined) ?? pool.pick({ bracket: RankPosition.opponentBracket(rank.position), avoidingCommander: deck.commander, recent: [...record.recentAIDecks],
        preconsOnly: RankTier.preconOpponentsOnly(tier), onlyPrecons: RankTier.preconOpponentsOnly(tier) ? AIDeckPool.gentlestPrecons : undefined });
    if (!opponent) return;
    // Signed in, the server issues the game's ticket and seed so the result counts there too (startRankedAIGame).
    if (player.state.phase === "ready" && player.state.username) {
      void account.startRankedAIGame(deckBracket).then((ticket) => begin("ranked", [opponent], RankTier.aiSkill(tier), ticket ?? undefined));
    } else begin("ranked", [opponent], RankTier.aiSkill(tier));
  };

  // MARK: Tables with people (OnDeviceRootView's hostRelay / joinRelay, challenges and the ranked queue)

  const identity = useMemo(() => ({ upstreamCommit: data.resolver.upstreamCommit, catalogueHash: data.resolver.catalogueHash, adapterVersion: RELAY_ADAPTER_VERSION }), [data]);
  /** Phones share a table only with the same engine build (the ranked queue and challenges check it). */
  const relayProtocol = `${identity.upstreamCommit}/${identity.catalogueHash}/${identity.adapterVersion}`.slice(0, 200);
  const [online, setOnline] = useState<OnlineGame>();
  const onlineKey = useRef(0);
  const onlineNow = useRef<OnlineGame | undefined>(undefined);
  onlineNow.current = online;
  const [notice, setNotice] = useState<string>();
  useEffect(() => { if (!notice) return; const timer = window.setTimeout(() => setNotice(undefined), 6000); return () => window.clearTimeout(timer); }, [notice]);
  const playerName = () => (player.state.username ?? (name.trim() || "Player")).slice(0, 24);
  useWatched(challenges);
  useWatched(rankedQueue);

  /** Joins a table by its code, or opens one this browser hosts (`seats` people), with the chosen deck. */
  const openOnline = async (options: { host?: { seats: 2 | 3 | 4; kind: HostKind }; code?: string; mode: PlayMode; rankedMatchID?: string; waitingFor?: string }) => {
    if (!deck || deckBracket === undefined) return undefined;
    let resolved;
    try { resolved = data.resolver.resolve(deck.deckList); } catch (failure) { setNotice(failure instanceof Error ? failure.message : String(failure)); return undefined; }
    const preview = import.meta.env.DEV && new URLSearchParams(location.search).has("preview");
    const table = options.host ? new HostTable(identity, engine) : preview ? new GuestTable(identity, () => new PreviewRelay(identity) as never) : new GuestTable(identity);
    const game: OnlineGame = { table, key: ++onlineKey.current, hosting: options.host !== undefined, mode: options.mode, deck, deckBracket,
      rankedMatchID: options.rankedMatchID, waitingFor: options.waitingFor };
    setPlayPanel(false); setCustom(false); setPanel(undefined); setSocial(undefined);
    setOnline(game);
    if (table instanceof HostTable) {
      // Only a custom table is offered to friends; challenge and ranked tables are for one invited player.
      table.onOpenSeats = (code, openSeats) => account.setHosting(code ? { code, openSeats } : undefined);
      try { await table.host(playerName(), resolved, options.host!.seats, { kind: options.host!.kind }); } catch { /* the room shows the relay's answer */ }
    } else table.join(options.code ?? "", playerName(), resolved);
    return game;
  };

  const leaveOnline = (game: OnlineGame, message?: string) => {
    game.table.leave();
    account.setHosting(undefined);
    setOnline((current) => (current?.key === game.key ? undefined : current));
    if (message) setNotice(message);
  };

  /** A challenge or ranked table that never starts closes after 75 s; ranked then plays the AI (watchPersonTable). */
  const watchPersonTable = (game: OnlineGame, message: string, fallback?: () => void) => {
    window.setTimeout(() => {
      if (onlineNow.current?.key !== game.key || game.table.session || ["playing", "starting"].includes(game.table.state.stage)) return;
      leaveOnline(game, message);
      fallback?.();
    }, 75_000);
  };

  /** The host opens a two-seat table and shares its code; the guest joins it (startRankedHuman). */
  const startRankedHuman = async (matchID: string, host: boolean, code: string | undefined, opponent: string | undefined) => {
    const game = host ? await openOnline({ host: { seats: 2, kind: "ranked" }, mode: "ranked", rankedMatchID: matchID })
      : code ? await openOnline({ code, mode: "ranked", rankedMatchID: matchID }) : undefined;
    if (!game) { rankedQueue.finish(); startRankedAI(); return; }
    const tableCode = game.table.state.tableCode;
    if (host && tableCode) await rankedQueue.shareTable(matchID, tableCode);
    watchPersonTable(game, `${opponent ?? "Your opponent"} didn't connect. An AI took the seat.`, () => { rankedQueue.finish(); startRankedAI(); });
  };

  /** Challenges a friend: a two-seat table, its code sent, then the answer (challengeFriend). */
  const challengeFriend = async (friend: string, mode: "quick" | "ranked") => {
    if (!deck || deckBracket === undefined) return;
    record.refreshSeason();
    if (mode === "ranked" && deckBracket > RankTier.maxDeckBracket(rank.position.tier)) {
      setNotice(`${CommanderBracket.title(deckBracket)} is above ${RankTier.name(rank.position.tier)}'s limit. Choose another deck.`);
      return;
    }
    const game = await openOnline({ host: { seats: 2, kind: "challenge" }, mode, waitingFor: friend });
    if (!game) return;
    const code = game.table.state.tableCode;
    if (!code) return;
    const answer = await challenges.challenge(friend, mode, relayProtocol, RankPosition.step(rank.position), code);
    switch (answer.kind) {
      case "accepted":
        setOnline((current) => (current?.key === game.key ? { ...current, waitingFor: undefined, rankedMatchID: answer.challenge.matchId } : current));
        game.rankedMatchID = answer.challenge.matchId;
        watchPersonTable(game, `${friend} didn't connect. Try the challenge again.`);
        break;
      case "declined": leaveOnline(game, `${friend} declined your challenge.`); break;
      case "expired": leaveOnline(game, `${friend} didn't answer your challenge.`); break;
      case "cancelled": leaveOnline(game); break;
      case "failed": leaveOnline(game, FriendChallengeRules.message(answer.code)); break;
    }
  };

  /** Accepts a friend's challenge and joins their table (acceptChallenge). */
  const acceptChallenge = async (challenge: FriendChallenge) => {
    record.refreshSeason();
    const step = RankPosition.step(rank.position);
    const ranked = FriendChallengeRules.isRanked(challenge);
    if (ranked && !FriendChallengeRules.mayRank(step, challenge.challengerStep)) {
      setNotice(FriendChallengeRules.message("rank_mismatch"));
      void challenges.decline(challenge);
      return;
    }
    try {
      const accepted = await challenges.accept(challenge, relayProtocol, step);
      if (!accepted.tableCode) throw new Error("challenge_closed");
      const game = await openOnline({ code: accepted.tableCode, mode: ranked ? "ranked" : "quick", rankedMatchID: accepted.matchId });
      if (game) watchPersonTable(game, `${challenge.challenger ?? "Your friend"} didn't connect. Try the challenge again.`);
    } catch (failure) {
      setNotice(FriendChallengeRules.message(failure instanceof Error && failure.message === "challenge_closed" ? "challenge_closed" : SupabaseLite.code(failure)));
    }
  };

  // Challenges are watched while the menus show, for a player with a name and friends (watchesChallenges).
  const watching = player.state.phase === "ready" && player.state.username !== undefined && !game && !online
    && player.state.friends.some((friend) => friend.relation === "friend");
  useEffect(() => {
    if (!watching) return;
    return challenges.watch(() => (player.state.onlineFriendCount ?? 0) > 0);
  }, [watching]);

  // A table with people: the finished game goes in the record once, a ranked result goes to the server, and a table
  // that has closed (left, or the game over and left) returns to the menus.
  const recordedOnline = useRef<number | undefined>(undefined);
  useEffect(() => {
    if (!online) return;
    const { table } = online;
    let opened = table.state.stage !== "idle";
    const check = () => {
      const stage = table.state.stage;
      if (stage !== "idle") opened = true;
      if (opened && (stage === "idle" || stage === "closed")) {
        account.setHosting(undefined);
        if (online.rankedMatchID) rankedQueue.finish();
        setOnline((current) => (current?.key === online.key ? undefined : current));
        return;
      }
      const snapshot = table.session?.state.snapshot;
      if (!snapshot || snapshot.gameStatus !== "completed" || recordedOnline.current === online.key) return;
      recordedOnline.current = online.key;
      const viewer = snapshot.viewerPlayerId;
      const winners = snapshot.winnerPlayerIds ?? [];
      const outcome = winners.length === 0 ? "draw" : viewer && winners.includes(viewer) ? "win" : "loss";
      record.record({
        mode: online.mode, outcome, opponents: table.state.tableSeats.filter((seat) => !seat.isLocal).map((seat) => ({ name: seat.name, commander: seat.commanders[0], isAI: false })),
        deckID: online.deck.id, deckName: online.deck.name, commander: online.deck.commander, colors: [...online.deck.colors], deckBracket: online.deckBracket, turns: snapshot.turn,
      });
      void (async () => {
        if (online.rankedMatchID) await rankedQueue.report(online.rankedMatchID, outcome);
        await server.afterGame();
        setRecordVersion((v) => v + 1);
      })();
      setRecordVersion((v) => v + 1);
    };
    check();
    return table.subscribe(check);
  }, [online, record]);
  useEffect(() => {
    if (!online) return;
    const visibility = () => online.table.setForeground(document.visibilityState === "visible");
    const leaving = () => online.table.leave();
    document.addEventListener("visibilitychange", visibility);
    window.addEventListener("pagehide", leaving);
    return () => { document.removeEventListener("visibilitychange", visibility); window.removeEventListener("pagehide", leaving); };
  }, [online]);

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
        mode: game.mode, outcome, opponents: game.opponents.map((o) => ({ name: o.name, commander: o.commander, isAI: true })),
        opponentBracket: game.opponents[0]?.bracket, aiSkill: game.skill, deckID: game.deck.id, deckName: game.deck.name, commander: game.deck.commander,
        colors: [...game.deck.colors], deckBracket: game.deckBracket, turns: snapshot.turn, aiDeckID: game.opponents[0]?.id,
      });
      if (change) setRankChange({ key: game.key, change });
      sample.current?.finish(snapshot.turn);
      // A ranked ticket's result waits with the game's record until the server settles it; then everything goes up.
      void (async () => {
        if (game.ticket) record.addPendingRanked({ ticket: game.ticket.id, outcome, date: Date.now(), seeded: game.ticket.seeded }, await game.table.gameRecord());
        await server.afterGame();
        setRecordVersion((v) => v + 1);
      })();
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
    setMenuTab(next); setPlayPanel(false); setCustom(false); setLeaderboard(false);
  };
  const joinTable = (code: string) => { void openOnline({ code, mode: "casual" }); };

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
    friends: () => setPanel("friends"), friendsOnline: player.state.onlineFriendCount, unread: player.state.incomingCount + player.state.unreadMessages > 0,
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
    quickSkill, setQuickSkill, quickLevel, setQuickLevel, startingPlayer: starting, setStartingPlayer: setStarting, rank, playerMode, setPlayerMode,
    friendWays: player.state.username ? ["challenge", "host", "join"] : ["host", "join"], mayStart, status: error ?? engineStatus, recent,
    close: () => setPlayPanel(false), explainBracket: () => setPanel("bracket"),
    startQuick, findRanked, openCustom: () => { setPlayPanel(false); setCustom(true); },
    rankedHall: () => { setPlayPanel(false); setMenuTab("ranked"); setLeaderboard(false); }, leaderboard: () => { setPlayPanel(false); setMenuTab("ranked"); setLeaderboard(true); },
    friendWay: (way) => { if (way === "challenge") { setPlayPanel(false); setPanel("friends"); } else { setPlayerMode("online"); setPlayPanel(false); setCustom(true); } },
    search: rankedQueue.phase, cancelSearch: () => rankedQueue.cancel(), playAINow: () => rankedQueue.skipToAI(),
    chooseRecent: (g) => { setSelectedDeckID(g.deckID); setMode(g.mode === "quick" ? "quick" : g.mode === "ranked" ? "ranked" : "custom"); },
  };

  // The Decks page: your decks and the precons (DeckStudioRootView.records), with their ⋯ actions.
  const shelfDecks: ShelfDeck[] = [
    ...library.decks.map((record) => {
      const deck = localDeck(record);
      return { box: box(DeckLibraryRecord.selectionID(record), deck), local: true, updatedAt: record.updatedAt, cardCount: DeckLibraryRecord.cardCount(record), bracket: deck.subtitle };
    }),
    ...pool.all.filter((d) => !d.id.startsWith("ai-")).map((deck) => ({
      box: box(`precon:${deck.id}`, deck), local: false, cardCount: deck.deckList.entries.reduce((n, e) => n + e.quantity, 0), bracket: CommanderBracket.name(deck.bracket),
    })),
  ];
  void libraryVersion;
  const [favoritesVersion, setFavoritesVersion] = useState(0);
  void favoritesVersion;
  const [libraryError, setLibraryError] = useState<string>();
  const guarded = (run: () => void) => { try { run(); setLibraryError(undefined); } catch (failure) { setLibraryError(failure instanceof Error ? failure.message : String(failure)); } libraryChanged(); };
  const decksModel = {
    decks: shelfDecks, selectedDeckID, fallbackName: pool.deck(firstPreconID.slice(7))?.name ?? "The first precon",
    favorites: new Set(shelfDecks.map((d) => d.box.id).filter((id) => library.isFavorite(id))), notice: libraryError ?? library.notice,
    select: setSelectedDeckID,
    play: (id: string) => { setSelectedDeckID(id); openPlay(); },
    edit: (id: string) => setStudio({ kind: "deck", id }),
    create: () => setStudio({ kind: "new" }),
    importDecks: () => setStudio({ kind: "import" }),
    duplicate: (id: string) => guarded(() => {
      const record = library.bySelection(id);
      const included = record ? undefined : deckFor(id);
      const source = record ?? (included && DeckLibraryRecord.fromDeckList(included.deckList, id));
      if (!source) return;
      const copy = library.duplicate(source, `${source.name} — Copy`);
      if (!record) library.rememberColors(copy.id, [...(deckFor(id)?.colors ?? "")]);
      setStudio({ kind: "deck", id: DeckLibraryRecord.selectionID(copy) });
    }),
    remove: (id: string) => guarded(() => {
      const record = library.bySelection(id);
      if (!record) return;
      library.delete(record.id, record.revision);
      if (id === selectedDeckID) setSelectedDeckID(firstPreconID);
    }),
    toggleFavorite: (id: string) => { library.setFavorite(id, !library.isFavorite(id)); setFavoritesVersion((v) => v + 1); },
  };

  const aiGroups: AIDeckGroup[] = [
    { title: "Precons", decks: pool.all.filter((d) => !d.id.startsWith("ai-")).map((d) => ({ id: d.id, name: d.name, commander: d.commander, colors: [...d.colors], bracket: d.bracket })) },
    ...CommanderBracket.all.map((bracket) => ({ title: CommanderBracket.name(bracket), decks: pool.bracketDecks.filter((d) => d.bracket === bracket)
      .map((d) => ({ id: d.id, name: d.name, commander: d.commander, colors: [...d.colors], bracket: d.bracket })) })).filter((g) => g.decks.length > 0),
  ];

  if (game) {
    const versus = { you: { id: "you", name: player.state.username ?? (name.trim() || "You"), commander: game.deck.commander || undefined },
      opponents: game.opponents.map((deck, index) => ({ id: `ai-${index}`, name: deck.name, commander: deck.commander || undefined })) };
    return <GameScreen key={game.key} table={game.table} versus={versus} rankChange={rankChange?.key === game.key ? rankChange.change : undefined} />;
  }
  if (online) return <OnlineScreen key={online.key} game={online} name={playerName()} resolver={data.resolver} leave={() => leaveOnline(online)} cancelWait={() => challenges.cancelOutgoing()} />;

  const lit = panel === "settings" ? "settings" : panel === "updates" ? "updates" : panel === "friends" ? "messages" : undefined;
  const covered = panel !== undefined;
  const page = custom ? "custom" : menuTab;
  return (
    <div className="mroot" style={{ zoom }}>
      <MetalDefs />
      <RoomBackdrop dim={studio ? 0.72 : playPanel ? 0 : page === "home" ? (covered ? 0.55 : 0) : page === "decks" ? 0.72 : 0.55} still={covered || playPanel} />
      <div className="mpage" style={{ opacity: playPanel || studio ? 0 : 1 }}>
        {page === "custom" && (
          <CustomTable model={{
            deck: deck ? box(selectedDeckID, deck) : undefined, bracket: deckBracket, name: player.state.username ?? name, setName,
            validName: validPlayerName(player.state.username ?? (name || "Player")), nameLocked: player.state.username !== undefined,
            playerMode, setPlayerMode, seats, setSeats, aiGroups, aiSkill, setAISkill, starting, setStarting, joinCode, setJoinCode,
            status: error ?? engineStatus, mayStart, start: startCustom,
            join: () => joinTable(joinCode),
            hostSeats: hostSeats as 2 | 3 | 4, setHostSeats, host: () => { void openOnline({ host: { seats: hostSeats as 2 | 3 | 4, kind: "custom" }, mode: "casual" }); },
            changeDeck: () => openPlay("custom"), back: () => openPlay("custom"), explainBracket: () => setPanel("bracket"),
          }} />
        )}
        {page === "home" && <Home content={homeContent} still={covered} />}
        {page === "decks" && <DecksPage model={decksModel} />}
        {page === "ranked" && !leaderboard && <RankedPage rank={rank} record={record} play={() => openPlay("ranked")}
          leaderboard={() => setLeaderboard(true)} profile={() => selectTab("profile")} />}
        {page === "ranked" && leaderboard && <Leaderboard account={player} onBack={() => setLeaderboard(false)}
          openProfile={(username) => setSocial({ kind: "profile", username })} />}
        {page === "profile" && <ProfilePage record={record} remote={remoteGames} playerName={player.state.username ?? (name.trim() || "Player")}
          deckCommanders={pool.all.map((d) => d.commander)} onChange={() => { setRecordVersion((v) => v + 1); server.publish(); }}
          account={<><AccountSignInCard /><PrivacyCard /></>} />}
      </div>
      {playPanel && <PlayPanel model={playModel} />}
      {studio && (
        <DeckStudioScreen route={studio} library={library} deckFor={deckFor} resolver={data.resolver} bracketRules={bracketRules}
          close={() => { setStudio(undefined); libraryChanged(); }} changed={libraryChanged}
          open={(next) => setStudio(next)}
          play={(id) => { setStudio(undefined); libraryChanged(); setSelectedDeckID(id); openPlay(); }} />
      )}
      <TopBar selected={covered && lit ? undefined : panel === "learn" ? "learn" : custom ? undefined : menuTab} select={selectTab} lit={lit}
        rank={{ tier: rank.position.tier, title: RankPosition.title(rank.position) }} openRank={() => selectTab("ranked")}
        updates={() => setPanel("updates")} settings={() => setPanel("settings")}
        messages={() => setPanel("friends")} unread={player.state.incomingCount + player.state.unreadMessages > 0} />
      {challenges.incoming[0] && !challenges.isWaiting && (
        <ChallengeBanner challenge={challenges.incoming[0]} accept={() => { void acceptChallenge(challenges.incoming[0]); }} decline={() => { void challenges.decline(challenges.incoming[0]); }} />
      )}
      {notice && <button type="button" className="mtoast glass" role="status" onClick={() => setNotice(undefined)}>{notice}</button>}
      <MenuPanel open={panel === "friends"} onClose={() => setPanel(undefined)} placement="leading" label="Friends">
        <FriendsPanel account={player} onClose={() => setPanel(undefined)} join={joinTable}
          challenge={(friend, mode) => { window.setTimeout(() => { void challengeFriend(friend, mode); }, 300); }} myRankStep={RankPosition.step(rank.position)}
          openProfile={(username) => setSocial({ kind: "profile", username })} openConversation={(username) => setSocial({ kind: "conversation", username })} />
      </MenuPanel>
      <MenuPanel open={social?.kind === "profile"} onClose={() => setSocial(undefined)} label="Player profile" maxWidth={760}>
        {social?.kind === "profile" && <PublicProfile account={player} username={social.username} onClose={() => setSocial(undefined)}
          message={(username) => setSocial({ kind: "conversation", username })} />}
      </MenuPanel>
      <MenuPanel open={social?.kind === "conversation"} onClose={() => setSocial(undefined)} label="Conversation" maxWidth={620}>
        {social?.kind === "conversation" && <Conversation account={player} username={social.username} onClose={() => setSocial(undefined)}
          openProfile={(username) => setSocial({ kind: "profile", username })} />}
      </MenuPanel>
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

/** A table with people: its room until the game starts, then the board (App's guest view, now for hosts too). */
function OnlineScreen({ game, name, resolver, leave, cancelWait }: {
  game: OnlineGame; name: string; resolver: DeckResolver; leave: () => void; cancelWait: () => void;
}) {
  const table = game.table;
  useSyncExternalStore((listener) => table.subscribe(listener), () => table.version);
  const stage = table.state.stage;
  if (stage === "playing" || stage === "starting" || (stage === "failed" && table.session)) return <GameScreen table={table} />;
  return <GuestRoom table={table} name={name} deck={game.deck.deckList} resolver={resolver} leave={leave} hosting={game.hosting}
    waitingFor={game.waitingFor} cancelWait={cancelWait} />;
}
