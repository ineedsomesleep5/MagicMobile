import { useMemo, useState, useEffect } from "react";
import {
  ActivityIndicator,
  Alert,
  Image,
  Linking,
  SafeAreaView,
  ScrollView,
  StyleSheet,
  Text,
  TextInput,
  TouchableOpacity,
  View
} from "react-native";

type AiDifficulty = "easy" | "normal" | "hard" | "expert";
type Screen = "menu" | "setup" | "decks" | "play";

interface DeckEntry {
  cardName: string;
  quantity: number;
  section: "commander" | "deck" | "sideboard" | "maybeboard";
}

interface DeckList {
  name: string;
  commander?: DeckEntry;
  entries: DeckEntry[];
}

interface LegalAction {
  id: string;
  type: string;
  playerId: string;
  label: string;
  cardInstanceId?: string;
  sourceInstanceId?: string;
  targetIds?: string[];
  commandTemplate?: Record<string, unknown>;
}

interface ZoneCard {
  instanceId: string;
  card: {
    name: string;
    typeLine: string;
    oracleText?: string;
  };
  tapped?: boolean;
  power?: number;
  toughness?: number;
}

interface PlayerGameState {
  playerId: string;
  life: number;
  poison: number;
  commanderTax: number;
  zones: Record<"library" | "hand" | "battlefield" | "graveyard" | "exile" | "command" | "stack", ZoneCard[]>;
}

interface GameSnapshot {
  id: string;
  phase: string;
  step?: string;
  turn: number;
  priorityPlayerId?: string;
  waitingOnPlayerId?: string;
  promptText?: string;
  bridgeRevision?: number;
  players: PlayerGameState[];
  legalActions?: LegalAction[];
  log: Array<{ id: string; message: string }>;
  engineHealth?: { status: string; reason: string };
}

interface GeneratedDeckResponse {
  deck: DeckList;
  validationErrors: string[];
  stats: {
    lands: number;
    ramp: number;
    draw: number;
    removal: number;
    boardWipes: number;
    averageManaValue: number;
  };
}

const humanPlayerId = "human";
const aiPlayerId = "ai-1";
const defaultServerUrl = "https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud";
const steps = ["untap", "upkeep", "draw", "precombat-main", "begin-combat", "declare-attackers", "declare-blockers", "combat-damage", "postcombat-main", "end", "cleanup"];

export default function App() {
  const [screen, setScreen] = useState<Screen>("menu");
  const [serverUrl, setServerUrl] = useState(defaultServerUrl);
  const [status, setStatus] = useState("Not connected");
  const [difficulty, setDifficulty] = useState<AiDifficulty>("normal");
  const [deckText, setDeckText] = useState("");
  const [deckSource, setDeckSource] = useState("");
  const [importedDeck, setImportedDeck] = useState<DeckList | undefined>();
  const [generatedDeck, setGeneratedDeck] = useState<GeneratedDeckResponse | undefined>();
  const [snapshot, setSnapshot] = useState<GameSnapshot | undefined>();
  const [selectedCard, setSelectedCard] = useState<ZoneCard | undefined>();
  const [busy, setBusy] = useState(false);
  const baseUrl = normalizeServerUrl(serverUrl);

  useEffect(() => {
    if (!snapshot?.id) return;
    const wsUrl = `${baseUrl.replace(/^http/, "ws")}/ws/games/${snapshot.id}`;
    console.log("WebSocket connecting to:", wsUrl);
    const ws = new WebSocket(wsUrl);

    ws.onopen = () => {
      setStatus("Connected (real-time)");
    };

    ws.onmessage = (event) => {
      try {
        const nextSnapshot = JSON.parse(event.data);
        setSnapshot(nextSnapshot);
        setSelectedCard(undefined);
      } catch (err) {
        console.error("WS parse error:", err);
      }
    };

    ws.onclose = () => {
      setStatus("WebSocket closed");
    };

    ws.onerror = (err) => {
      console.warn("WebSocket error:", err);
    };

    return () => ws.close();
  }, [snapshot?.id, baseUrl]);

  const human = snapshot?.players.find((player) => player.playerId === humanPlayerId);
  const opponent = snapshot?.players.find((player) => player.playerId !== humanPlayerId);
  const selectedActions = snapshot?.legalActions?.filter((action) => action.cardInstanceId === selectedCard?.instanceId || action.sourceInstanceId === selectedCard?.instanceId) ?? [];
  const promptActions = snapshot?.legalActions?.filter((action) => ["keep_hand", "mulligan", "resolve_choice", "pass_priority", "pass_until_response", "pass_until_next_turn", "concede"].includes(action.type)) ?? [];

  async function checkServer() {
    await withBusy(async () => {
      const health = await requestJson<{ status: string; reason: string }>(baseUrl, "/api/engine/health");
      setStatus(`${health.status}: ${health.reason}`);
    });
  }

  async function generateDeck() {
    await withBusy(async () => {
      const humanDeck = await requestJson<GeneratedDeckResponse>(baseUrl, "/api/decks/generate", {
        method: "POST",
        body: { bracket: 3, seed: `mobile-${Date.now()}`, playerId: humanPlayerId }
      });
      setGeneratedDeck(humanDeck);
      setImportedDeck(undefined);
      setStatus(`Generated ${humanDeck.deck.name}`);
    });
  }

  function importDeck() {
    const parsed = parseDeckList(deckText, deckSource || "Imported Commander Deck");
    if (!parsed) {
      Alert.alert("Deck import needs text", "Paste an Archidekt/Moxfield export list or a 100-card text list. Direct scraping is not used.");
      return;
    }
    setImportedDeck(parsed);
    setGeneratedDeck(undefined);
    setStatus(`Imported ${parsed.name}: ${totalCards(parsed)} cards`);
  }

  async function startGame() {
    await withBusy(async () => {
      const humanDeck = importedDeck ?? generatedDeck?.deck ?? (await requestJson<GeneratedDeckResponse>(baseUrl, "/api/decks/generate", {
        method: "POST",
        body: { bracket: 3, seed: `human-${Date.now()}`, playerId: humanPlayerId }
      })).deck;
      const aiDeck = (await requestJson<GeneratedDeckResponse>(baseUrl, "/api/decks/generate", {
        method: "POST",
        body: { bracket: 3, seed: `ai-${Date.now()}`, playerId: aiPlayerId }
      })).deck;

      const game = await requestJson<GameSnapshot>(baseUrl, "/api/engine/commander", {
        method: "POST",
        body: {
          roomId: `mobile-${Date.now()}`,
          humanPlayerId,
          humanDeck,
          aiPlayers: [{ playerId: aiPlayerId, displayName: "Noaddrag", difficulty, deck: aiDeck }],
          startingLife: 40,
          commanderDamageEnabled: true
        }
      });
      setSnapshot(game);
      setSelectedCard(undefined);
      setScreen("play");
      setStatus("Commander game started");
    });
  }

  async function runAction(action: LegalAction) {
    if (!snapshot) return;
    await withBusy(async () => {
      const command = commandForAction(snapshot, action);
      const next = await requestJson<GameSnapshot>(baseUrl, `/api/engine/games/${encodeURIComponent(snapshot.id)}/commands`, {
        method: "POST",
        body: command
      });
      setSnapshot(next);
      setSelectedCard(undefined);
    });
  }

  async function withBusy(work: () => Promise<void>) {
    setBusy(true);
    try {
      await work();
    } catch (error) {
      const message = error instanceof Error ? error.message : "Something went wrong";
      setStatus(message);
      Alert.alert("MagicMobile", message);
    } finally {
      setBusy(false);
    }
  }

  const deckSummary = useMemo(() => {
    const deck = importedDeck ?? generatedDeck?.deck;
    if (!deck) return "No deck selected. A valid bracket-3 Commander deck will be generated when you start.";
    return `${deck.name} - ${totalCards(deck)} cards - Commander: ${deck.commander?.cardName ?? "unknown"}`;
  }, [generatedDeck, importedDeck]);

  return (
    <SafeAreaView style={styles.safeArea}>
      <View style={styles.appFrame}>
        <Header screen={screen} status={status} busy={busy} onMenu={() => setScreen("menu")} />
        {screen === "menu" ? (
          <MenuScreen onSetup={() => setScreen("setup")} onDecks={() => setScreen("decks")} onPlay={startGame} />
        ) : null}
        {screen === "setup" ? (
          <SetupScreen
            serverUrl={serverUrl}
            setServerUrl={setServerUrl}
            difficulty={difficulty}
            setDifficulty={setDifficulty}
            deckSummary={deckSummary}
            onCheckServer={checkServer}
            onGenerateDeck={generateDeck}
            onStartGame={startGame}
            onDecks={() => setScreen("decks")}
          />
        ) : null}
        {screen === "decks" ? (
          <DeckBuilderScreen
            deckText={deckText}
            setDeckText={setDeckText}
            deckSource={deckSource}
            setDeckSource={setDeckSource}
            deckSummary={deckSummary}
            onImport={importDeck}
            onGenerate={generateDeck}
          />
        ) : null}
        {screen === "play" ? (
          <PlayScreen
            human={human}
            opponent={opponent}
            snapshot={snapshot}
            selectedCard={selectedCard}
            setSelectedCard={setSelectedCard}
            selectedActions={selectedActions}
            promptActions={promptActions}
            onRunAction={runAction}
            onNewGame={() => setScreen("setup")}
          />
        ) : null}
      </View>
    </SafeAreaView>
  );
}

function Header({ screen, status, busy, onMenu }: { screen: Screen; status: string; busy: boolean; onMenu: () => void }) {
  return (
    <View style={styles.header}>
      <TouchableOpacity style={styles.logoButton} onPress={onMenu}>
        <Text style={styles.logo}>MagicMobile</Text>
        <Text style={styles.logoSub}>{screen}</Text>
      </TouchableOpacity>
      <View style={styles.statusPanel}>
        {busy ? <ActivityIndicator color="#ffb45d" /> : null}
        <Text style={styles.statusText} numberOfLines={2}>{status}</Text>
      </View>
    </View>
  );
}

function MenuScreen({ onSetup, onDecks, onPlay }: { onSetup: () => void; onDecks: () => void; onPlay: () => void }) {
  return (
    <View style={styles.menuGrid}>
      <HeroPanel title="Commander vs AI" body="Start a real XMage-backed 100-card Commander game from your phone." action="Game setup" onPress={onSetup} />
      <HeroPanel title="Deck Builder" body="Paste Archidekt or Moxfield export text, tune your commander, or generate a bracket-3 deck." action="Build deck" onPress={onDecks} />
      <HeroPanel title="Quick Battle" body="Generate both decks and jump straight into a 1v1 game against normal AI." action="Start now" onPress={onPlay} />
    </View>
  );
}

function SetupScreen({
  serverUrl,
  setServerUrl,
  difficulty,
  setDifficulty,
  deckSummary,
  onCheckServer,
  onGenerateDeck,
  onStartGame,
  onDecks
}: {
  serverUrl: string;
  setServerUrl: (value: string) => void;
  difficulty: AiDifficulty;
  setDifficulty: (value: AiDifficulty) => void;
  deckSummary: string;
  onCheckServer: () => void;
  onGenerateDeck: () => void;
  onStartGame: () => void;
  onDecks: () => void;
}) {
  return (
    <View style={styles.twoColumn}>
      <View style={styles.panel}>
        <Text style={styles.panelTitle}>Server</Text>
        <TextInput value={serverUrl} onChangeText={setServerUrl} autoCapitalize="none" style={styles.input} placeholder="http://your-mac-ip:3000" placeholderTextColor="#74807a" />
        <Text style={styles.helpText}>Your iPhone connects to the Mac/VPS running XMage, Docker, and the web API. The phone itself only runs this client.</Text>
        <TouchableOpacity style={styles.primaryButton} onPress={onCheckServer}>
          <Text style={styles.primaryButtonText}>Check XMage bridge</Text>
        </TouchableOpacity>
      </View>
      <View style={styles.panel}>
        <Text style={styles.panelTitle}>Game Setup</Text>
        <View style={styles.segmentRow}>
          {(["easy", "normal", "hard", "expert"] as AiDifficulty[]).map((value) => (
            <TouchableOpacity key={value} style={value === difficulty ? styles.segmentActive : styles.segment} onPress={() => setDifficulty(value)}>
              <Text style={value === difficulty ? styles.segmentActiveText : styles.segmentText}>{value}</Text>
            </TouchableOpacity>
          ))}
        </View>
        <Text style={styles.deckSummary}>{deckSummary}</Text>
        <View style={styles.actionRow}>
          <TouchableOpacity style={styles.secondaryButton} onPress={onDecks}>
            <Text style={styles.secondaryButtonText}>Deck upload</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.secondaryButton} onPress={onGenerateDeck}>
            <Text style={styles.secondaryButtonText}>Generate deck</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.primaryButton} onPress={onStartGame}>
            <Text style={styles.primaryButtonText}>Start vs AI</Text>
          </TouchableOpacity>
        </View>
      </View>
    </View>
  );
}

function DeckBuilderScreen({
  deckText,
  setDeckText,
  deckSource,
  setDeckSource,
  deckSummary,
  onImport,
  onGenerate
}: {
  deckText: string;
  setDeckText: (value: string) => void;
  deckSource: string;
  setDeckSource: (value: string) => void;
  deckSummary: string;
  onImport: () => void;
  onGenerate: () => void;
}) {
  return (
    <View style={styles.twoColumn}>
      <View style={styles.panel}>
        <Text style={styles.panelTitle}>Deck Upload</Text>
        <TextInput value={deckSource} onChangeText={setDeckSource} autoCapitalize="none" style={styles.input} placeholder="Deck name, Archidekt URL, or Moxfield URL" placeholderTextColor="#74807a" />
        <TextInput
          value={deckText}
          onChangeText={setDeckText}
          multiline
          style={styles.deckInput}
          placeholder={"Commander\n1 Ezuri, Claw of Progress\n\nDeck\n1 Sol Ring\n1 Command Tower\n98 ..."}
          placeholderTextColor="#74807a"
        />
        <View style={styles.actionRow}>
          <TouchableOpacity style={styles.secondaryButton} onPress={() => Linking.openURL("https://archidekt.com/")}>
            <Text style={styles.secondaryButtonText}>Archidekt</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.secondaryButton} onPress={() => Linking.openURL("https://www.moxfield.com/")}>
            <Text style={styles.secondaryButtonText}>Moxfield</Text>
          </TouchableOpacity>
          <TouchableOpacity style={styles.primaryButton} onPress={onImport}>
            <Text style={styles.primaryButtonText}>Import text</Text>
          </TouchableOpacity>
        </View>
      </View>
      <View style={styles.panel}>
        <Text style={styles.panelTitle}>Current Deck</Text>
        <Text style={styles.deckSummary}>{deckSummary}</Text>
        <Text style={styles.helpText}>Direct website scraping is intentionally avoided. Use exported plain text from Archidekt or Moxfield, or generate a legal bracket-3 Commander deck from the server.</Text>
        <TouchableOpacity style={styles.primaryButton} onPress={onGenerate}>
          <Text style={styles.primaryButtonText}>Generate bracket-3 deck</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

function CardArt({ cardName, style }: { cardName: string; style?: any }) {
  const uri = cardName === "Hidden card"
    ? "https://gatherer.wizards.com/Images/CardBack.jpg"
    : `https://magicmobile.openclaw-is3w.srv1420950.hstgr.cloud/api/card-image?name=${encodeURIComponent(cardName)}&version=normal`;
  return (
    <Image
      source={{ uri }}
      style={[styles.cardArtImage, style]}
      resizeMode="cover"
    />
  );
}

function PlayScreen({
  human,
  opponent,
  snapshot,
  selectedCard,
  setSelectedCard,
  selectedActions,
  promptActions,
  onRunAction,
  onNewGame
}: {
  human: PlayerGameState | undefined;
  opponent: PlayerGameState | undefined;
  snapshot: GameSnapshot | undefined;
  selectedCard: ZoneCard | undefined;
  setSelectedCard: (card: ZoneCard | undefined) => void;
  selectedActions: LegalAction[];
  promptActions: LegalAction[];
  onRunAction: (action: LegalAction) => void;
  onNewGame: () => void;
}) {
  const [showLog, setShowLog] = useState(false);

  if (!snapshot || !human || !opponent) {
    return (
      <View style={styles.loadingPanel}>
        <ActivityIndicator color="#ffb45d" size="large" />
        <Text style={styles.panelTitle}>Starting Commander table...</Text>
      </View>
    );
  }

  const actions = selectedActions.length > 0 ? selectedActions : promptActions;
  
  // Split battlefield cards into Lands and non-lands
  const opponentLands = opponent.zones.battlefield.filter(c => isLand(c));
  const opponentCreatures = opponent.zones.battlefield.filter(c => !isLand(c));
  const humanCreatures = human.zones.battlefield.filter(c => !isLand(c));
  const humanLands = human.zones.battlefield.filter(c => isLand(c));

  return (
    <View style={styles.gameLayout}>
      <View style={styles.battlefieldContainer}>
        {/* 3D Tilted Battlefield */}
        <View style={styles.battlefield}>
          {/* Opponent Lands */}
          <CardRow title="Opponent Lands" cards={opponentLands} selectedCard={selectedCard} onSelect={setSelectedCard} compact />
          
          {/* Opponent Creatures */}
          <CardRow title="Opponent Creatures" cards={opponentCreatures} selectedCard={selectedCard} onSelect={setSelectedCard} />

          {/* Center River / Splitter */}
          <View style={styles.battlefieldDivider} />

          {/* Your Creatures */}
          <CardRow title="Your Creatures" cards={humanCreatures} selectedCard={selectedCard} onSelect={setSelectedCard} />

          {/* Your Lands */}
          <CardRow title="Your Lands" cards={humanLands} selectedCard={selectedCard} onSelect={setSelectedCard} compact />
        </View>

        {/* 2D HUD Overlays (circular avatars, hand, buttons) */}
        <View style={styles.hudOverlay} pointerEvents="box-none">
          {/* Opponent circular HUD */}
          <View style={styles.opponentAvatarWrap}>
            <View style={styles.circularAvatar}>
              <Text style={styles.lifeText}>{opponent.life}</Text>
            </View>
            <View style={styles.avatarLabelWrap}>
              <Text style={styles.playerName}>Noaddrag</Text>
              <Text style={styles.playerSubText}>Lib: {opponent.zones.library.length} · Hand: {opponent.zones.hand.length}</Text>
            </View>
          </View>

          {/* Center phase status banner */}
          <View style={styles.centerBanner}>
            <Text style={styles.phaseBannerText}>{snapshot.step ?? snapshot.phase}</Text>
            <Text style={styles.promptBannerText} numberOfLines={1}>{snapshot.promptText ?? "Waiting..."}</Text>
          </View>

          {/* Player circular HUD */}
          <View style={styles.humanAvatarWrap}>
            <View style={[styles.circularAvatar, styles.humanLifeBorder]}>
              <Text style={styles.lifeText}>{human.life}</Text>
            </View>
            <View style={styles.avatarLabelWrap}>
              <Text style={styles.playerName}>You</Text>
              <Text style={styles.playerSubText}>Lib: {human.zones.library.length} · Grave: {human.zones.graveyard.length}</Text>
            </View>
          </View>

          {/* Overlapping Curved Hand Fan */}
          <HandFan cards={human.zones.hand} selectedCard={selectedCard} onSelect={setSelectedCard} />

          {/* Thumb-friendly Action buttons overlay */}
          <View style={styles.actionRailContainer}>
            {actions.slice(0, 3).map((action, idx) => {
              const isPrimary = idx === 0;
              return (
                <TouchableOpacity
                  key={action.id}
                  style={isPrimary ? styles.primaryActionButton : styles.secondaryActionButton}
                  onPress={() => onRunAction(action)}
                >
                  <Text style={isPrimary ? styles.primaryActionText : styles.secondaryActionText}>
                    {action.label}
                  </Text>
                </TouchableOpacity>
              );
            })}
            <TouchableOpacity style={styles.secondaryActionButton} onPress={() => setShowLog(!showLog)}>
              <Text style={styles.secondaryActionText}>{showLog ? "Close Log" : "Show Log"}</Text>
            </TouchableOpacity>
            <TouchableOpacity style={styles.dangerButton} onPress={onNewGame}>
              <Text style={styles.dangerButtonText}>Concede</Text>
            </TouchableOpacity>
          </View>
        </View>

        {/* Slide-out floating log drawer */}
        {showLog ? (
          <View style={styles.floatingLogPanel}>
            <View style={styles.floatingLogHeader}>
              <Text style={styles.panelTitle}>Game Log</Text>
              <TouchableOpacity onPress={() => setShowLog(false)}>
                <Text style={styles.closeBtnText}>✕</Text>
              </TouchableOpacity>
            </View>
            <ScrollView style={styles.logList}>
              {snapshot.log.slice(-15).map((entry) => (
                <Text key={entry.id} style={styles.logLine}>{entry.message}</Text>
              ))}
            </ScrollView>
          </View>
        ) : null}

        {/* Floating Card Inspector overlay when tapped */}
        {selectedCard ? (
          <View style={styles.floatingInspector}>
            <TouchableOpacity style={styles.inspectorClose} onPress={() => setSelectedCard(undefined)}>
              <Text style={styles.closeBtnText}>✕</Text>
            </TouchableOpacity>
            <CardArt cardName={selectedCard.card.name} style={styles.inspectorImage} />
            <Text style={styles.inspectorTitle}>{selectedCard.card.name}</Text>
            <Text style={styles.inspectorType}>{selectedCard.card.typeLine}</Text>
            {selectedCard.card.oracleText ? (
              <Text style={styles.inspectorText} numberOfLines={4}>{selectedCard.card.oracleText}</Text>
            ) : null}
          </View>
        ) : null}
      </View>
    </View>
  );
}

function HeroPanel({ title, body, action, onPress }: { title: string; body: string; action: string; onPress: () => void }) {
  return (
    <View style={styles.heroPanel}>
      <Text style={styles.heroTitle}>{title}</Text>
      <Text style={styles.heroBody}>{body}</Text>
      <TouchableOpacity style={styles.primaryButton} onPress={onPress}>
        <Text style={styles.primaryButtonText}>{action}</Text>
      </TouchableOpacity>
    </View>
  );
}

function CardRow({
  cards,
  selectedCard,
  onSelect,
  compact = false
}: {
  title: string;
  cards: ZoneCard[];
  selectedCard: ZoneCard | undefined;
  onSelect: (card: ZoneCard) => void;
  compact?: boolean;
}) {
  return (
    <View style={styles.cardRowWrap}>
      <ScrollView horizontal contentContainerStyle={styles.cardRow}>
        {cards.map((card) => (
          <CardButton
            key={card.instanceId}
            card={card}
            selected={selectedCard?.instanceId === card.instanceId}
            onPress={() => onSelect(card)}
            compact={compact}
          />
        ))}
      </ScrollView>
    </View>
  );
}

function HandFan({
  cards,
  selectedCard,
  onSelect
}: {
  cards: ZoneCard[];
  selectedCard: ZoneCard | undefined;
  onSelect: (card: ZoneCard) => void;
}) {
  return (
    <View style={styles.handFan} pointerEvents="box-none">
      {cards.map((card, index) => {
        const rotation = (index - (cards.length - 1) / 2) * 5;
        const translationY = Math.abs(index - (cards.length - 1) / 2) * 4 - (selectedCard?.instanceId === card.instanceId ? 30 : 0);
        return (
          <TouchableOpacity
            key={card.instanceId}
            style={[
              styles.handCard,
              {
                transform: [
                  { rotate: `${rotation}deg` },
                  { translateY: translationY }
                ],
                zIndex: index + (selectedCard?.instanceId === card.instanceId ? 100 : 0)
              }
            ]}
            onPress={() => onSelect(card)}
          >
            <CardArt cardName={card.card.name} style={styles.handCardArt} />
          </TouchableOpacity>
        );
      })}
    </View>
  );
}

function CardButton({
  card,
  selected,
  onPress,
  compact = false
}: {
  card: ZoneCard;
  selected: boolean;
  onPress: () => void;
  compact?: boolean;
}) {
  return (
    <TouchableOpacity
      style={[
        compact ? styles.compactCardButton : styles.cardButton,
        selected && styles.cardButtonSelected,
        card.tapped && styles.cardTapped
      ]}
      onPress={onPress}
    >
      <CardArt cardName={card.card.name} style={styles.battleCardArt} />
      {card.power !== undefined && card.toughness !== undefined ? (
        <View style={styles.ptBadge}>
          <Text style={styles.ptBadgeText}>{card.power}/{card.toughness}</Text>
        </View>
      ) : null}
    </TouchableOpacity>
  );
}

function isLand(card: ZoneCard): boolean {
  return /\bland\b/i.test(card.card.typeLine);
}

async function requestJson<T>(baseUrl: string, path: string, options?: { method?: string; body?: unknown }): Promise<T> {
  const init: RequestInit = {
    method: options?.method ?? "GET",
    headers: { "Content-Type": "application/json" }
  };
  if (options?.body) {
    init.body = JSON.stringify(options.body);
  }
  const response = await fetch(`${baseUrl}${path}`, init);
  if (!response.ok) {
    let detail = "";
    try {
      const body = await response.json();
      detail = body.error ? `: ${body.error}` : "";
    } catch {
      detail = "";
    }
    throw new Error(`Request failed ${response.status}${detail}`);
  }
  return response.json() as Promise<T>;
}

function commandForAction(snapshot: GameSnapshot, action: LegalAction): Record<string, unknown> {
  const gameId = snapshot.id;
  const template = action.commandTemplate ?? {};
  const expected = snapshot.bridgeRevision === undefined ? {} : { expectedBridgeRevision: snapshot.bridgeRevision };
  if (action.type === "resolve_choice") {
    return { type: "resolve_choice", gameId, playerId: action.playerId, promptId: action.id, choiceIds: action.targetIds ?? [], ...expected };
  }
  if (action.type === "activate_ability" || action.type === "make_mana") {
    return { type: action.type, gameId, playerId: action.playerId, sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId, abilityId: template.abilityId ?? action.id, ...expected };
  }
  return { ...template, type: action.type, gameId, playerId: action.playerId, cardInstanceId: action.cardInstanceId, sourceInstanceId: action.sourceInstanceId, ...expected };
}

function parseDeckList(text: string, source: string): DeckList | undefined {
  const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  if (lines.length === 0) return undefined;

  let section: DeckEntry["section"] = "deck";
  const entries: DeckEntry[] = [];
  for (const line of lines) {
    const lower = line.toLowerCase();
    if (lower.includes("commander")) {
      section = "commander";
      continue;
    }
    if (lower === "deck" || lower.includes("mainboard")) {
      section = "deck";
      continue;
    }
    const match = line.match(/^(\d+)x?\s+(.+?)\s*(?:\(.+\))?$/);
    if (!match) continue;
    const quantity = Number(match[1]);
    const cardName = (match[2] ?? "").replace(/\s+#\d+$/, "").trim();
    entries.push({ cardName, quantity, section });
    if (section === "commander") section = "deck";
  }
  const commander = entries.find((entry) => entry.section === "commander") ?? entries[0];
  if (!commander) return undefined;
  return {
    name: source.startsWith("http") ? "Imported URL Deck" : source,
    commander: { cardName: commander.cardName, quantity: 1, section: "commander" },
    entries: entries.filter((entry) => entry !== commander).map((entry) => ({ ...entry, section: "deck" }))
  };
}

function totalCards(deck: DeckList): number {
  return (deck.commander?.quantity ?? 0) + deck.entries.reduce((sum, entry) => sum + entry.quantity, 0);
}

function normalizeServerUrl(value: string): string {
  return value.replace(/\/+$/, "");
}

const styles = StyleSheet.create({
  safeArea: { flex: 1, backgroundColor: "#071012" },
  landscapeShell: { flexGrow: 1 },
  appFrame: { flex: 1, padding: 8, backgroundColor: "#101817" },
  header: { height: 50, flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 },
  logoButton: { minWidth: 140 },
  logo: { color: "#fff2d8", fontSize: 20, fontWeight: "900" },
  logoSub: { color: "#ffb45d", fontSize: 10, fontWeight: "800", textTransform: "uppercase" },
  statusPanel: { flex: 1, minHeight: 38, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, paddingHorizontal: 12, flexDirection: "row", alignItems: "center", justifyContent: "flex-end", gap: 10, backgroundColor: "#0a0f0f" },
  statusText: { color: "#d7d0bf", fontSize: 12, fontWeight: "700", textAlign: "right" },
  menuGrid: { flex: 1, flexDirection: "row", gap: 12, alignItems: "stretch" },
  heroPanel: { flex: 1, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 14, justifyContent: "space-between", backgroundColor: "#14211d" },
  heroTitle: { color: "#fff2d8", fontSize: 22, fontWeight: "900" },
  heroBody: { color: "#c7c0ae", fontSize: 13, lineHeight: 18, fontWeight: "600" },
  twoColumn: { flex: 1, flexDirection: "row", gap: 12 },
  panel: { flex: 1, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 12, gap: 10, backgroundColor: "#101615" },
  panelTitle: { color: "#ffb45d", fontSize: 14, fontWeight: "900", textTransform: "uppercase" },
  input: { minHeight: 38, borderWidth: 1, borderColor: "#40534f", borderRadius: 7, paddingHorizontal: 12, color: "#fff2d8", fontWeight: "700", backgroundColor: "#080d0d" },
  deckInput: { flex: 1, minHeight: 180, borderWidth: 1, borderColor: "#40534f", borderRadius: 7, padding: 10, color: "#fff2d8", fontWeight: "700", textAlignVertical: "top", backgroundColor: "#080d0d" },
  helpText: { color: "#b7b09f", fontSize: 11, lineHeight: 16, fontWeight: "600" },
  deckSummary: { color: "#fff2d8", fontSize: 14, lineHeight: 20, fontWeight: "800" },
  actionRow: { flexDirection: "row", flexWrap: "wrap", gap: 8 },
  primaryButton: { minHeight: 38, borderRadius: 8, paddingHorizontal: 14, paddingVertical: 10, alignItems: "center", justifyContent: "center", backgroundColor: "#f57a2d" },
  primaryButtonText: { color: "#fff6e8", fontSize: 12, fontWeight: "900" },
  secondaryButton: { minHeight: 38, borderWidth: 1, borderColor: "#526964", borderRadius: 8, paddingHorizontal: 12, paddingVertical: 9, alignItems: "center", justifyContent: "center", backgroundColor: "#17221f" },
  secondaryButtonText: { color: "#fff2d8", fontSize: 12, fontWeight: "900" },
  segmentRow: { flexDirection: "row", gap: 6 },
  segment: { borderWidth: 1, borderColor: "#526964", borderRadius: 8, paddingHorizontal: 12, paddingVertical: 8 },
  segmentActive: { borderWidth: 1, borderColor: "#35c7ff", borderRadius: 8, paddingHorizontal: 12, paddingVertical: 8, backgroundColor: "#123845" },
  segmentText: { color: "#c7c0ae", fontSize: 12, fontWeight: "800" },
  segmentActiveText: { color: "#f2fbff", fontSize: 12, fontWeight: "900" },
  loadingPanel: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12 },
  
  // Play screen revamped layout styles
  gameLayout: { flex: 1, flexDirection: "row" },
  battlefieldContainer: { flex: 1, position: "relative", overflow: "hidden" },
  battlefield: { position: "absolute", inset: 0, justifyContent: "space-between", paddingVertical: 20, paddingHorizontal: 10, transform: [{ perspective: 1200 }, { rotateX: "45deg" }, { scaleY: 0.95 }] },
  battlefieldDivider: { height: 2, backgroundColor: "rgba(255,180,93,0.12)", marginHorizontal: 20, marginVertical: 0 },
  hudOverlay: { position: "absolute", inset: 0, justifyContent: "space-between", padding: 8, pointerEvents: "box-none" },
  
  opponentAvatarWrap: { position: "absolute", top: 8, left: 12, flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: "rgba(10,15,15,0.85)", paddingHorizontal: 12, paddingVertical: 4, borderRadius: 20, borderWidth: 1, borderColor: "rgba(255,180,93,0.3)" },
  humanAvatarWrap: { position: "absolute", bottom: 8, left: 12, flexDirection: "row", alignItems: "center", gap: 8, backgroundColor: "rgba(10,15,15,0.85)", paddingHorizontal: 12, paddingVertical: 4, borderRadius: 20, borderWidth: 1, borderColor: "rgba(53,199,255,0.3)" },
  avatarLabelWrap: {},
  circularAvatar: { width: 36, height: 36, borderRadius: 18, backgroundColor: "#1d2328", borderWidth: 2, borderColor: "#fff2d8", justifyContent: "center", alignItems: "center" },
  humanLifeBorder: { borderColor: "#32d4ff" },
  lifeText: { color: "#fff", fontSize: 16, fontWeight: "900" },
  playerName: { color: "#fff2d8", fontSize: 13, fontWeight: "900" },
  playerSubText: { color: "#a8b0a1", fontSize: 10, fontWeight: "700" },
  
  centerBanner: { position: "absolute", top: "45%", alignSelf: "center", backgroundColor: "rgba(10,15,15,0.9)", paddingHorizontal: 20, paddingVertical: 10, borderRadius: 16, borderWidth: 1, borderColor: "rgba(255,180,93,0.5)", shadowColor: "#ffb45d", shadowOpacity: 0.4, shadowRadius: 15 },
  phaseBannerText: { color: "#ffb45d", fontSize: 13, fontWeight: "900", textTransform: "uppercase", textAlign: "center", marginBottom: 2 },
  promptBannerText: { color: "#fff2d8", fontSize: 12, fontWeight: "800", textAlign: "center" },
  
  handFan: { position: "absolute", bottom: -15, left: "50%", transform: [{ translateX: -150 }], width: 300, height: 95, flexDirection: "row", justifyContent: "center", alignItems: "flex-end" },
  handCard: { width: 64, height: 90, marginHorizontal: -12, borderWidth: 2, borderColor: "#23c7ff", borderRadius: 6, overflow: "hidden", shadowColor: "#000", shadowOpacity: 0.5, shadowRadius: 5 },
  handCardArt: { width: "100%", height: "100%" },
  cardArtImage: { width: "100%", height: "100%" },
  
  cardRowWrap: { minHeight: 70, justifyContent: "center" },
  cardRow: { gap: 10, paddingHorizontal: 12 },
  cardButton: { width: 56, height: 78, borderRadius: 6, borderWidth: 2, borderColor: "#273633", overflow: "hidden" },
  compactCardButton: { width: 46, height: 64, borderRadius: 5, borderWidth: 1.5, borderColor: "#273633", overflow: "hidden" },
  cardButtonSelected: { borderColor: "#32d4ff" },
  cardTapped: { transform: [{ rotate: "90deg" }] },
  battleCardArt: { width: "100%", height: "100%" },
  ptBadge: { position: "absolute", bottom: 2, right: 2, backgroundColor: "rgba(0,0,0,0.85)", paddingHorizontal: 4, paddingVertical: 1, borderRadius: 3, borderWidth: 0.5, borderColor: "#ffb45d" },
  ptBadgeText: { color: "#fff", fontSize: 8, fontWeight: "900" },
  
  actionRailContainer: { position: "absolute", bottom: 8, right: 8, alignItems: "flex-end", gap: 6 },
  primaryActionButton: { minWidth: 110, minHeight: 38, borderRadius: 19, backgroundColor: "#ff7a00", justifyContent: "center", alignItems: "center", paddingHorizontal: 12, borderWidth: 1, borderColor: "#ffc83b", shadowColor: "#ff7a00", shadowOpacity: 0.5, shadowRadius: 8 },
  primaryActionText: { color: "#fff", fontSize: 11, fontWeight: "900", textTransform: "uppercase" },
  secondaryActionButton: { minWidth: 90, minHeight: 32, borderRadius: 16, backgroundColor: "rgba(23,34,31,0.9)", justifyContent: "center", alignItems: "center", paddingHorizontal: 10, borderWidth: 1, borderColor: "#526964" },
  secondaryActionText: { color: "#fff2d8", fontSize: 10, fontWeight: "800" },
  dangerButton: { minWidth: 90, minHeight: 32, borderRadius: 16, backgroundColor: "#8a231f", justifyContent: "center", alignItems: "center", paddingHorizontal: 10, borderWidth: 1, borderColor: "#b83b35" },
  dangerButtonText: { color: "#fff", fontSize: 10, fontWeight: "900" },
  
  floatingLogPanel: { position: "absolute", top: 50, right: 12, bottom: 80, width: 220, backgroundColor: "rgba(10,15,15,0.95)", borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 8, zIndex: 1000 },
  floatingLogHeader: { flexDirection: "row", justifyContent: "space-between", alignItems: "center", marginBottom: 6 },
  closeBtnText: { color: "#a8b0a1", fontSize: 16, fontWeight: "700", padding: 4 },
  logList: { flex: 1 },
  logLine: { color: "#c9c2b2", fontSize: 10, paddingVertical: 3, borderBottomWidth: 0.5, borderBottomColor: "#1d2926" },
  
  floatingInspector: { position: "absolute", top: 40, left: 12, bottom: 80, width: 180, backgroundColor: "rgba(10,15,15,0.95)", borderWidth: 1, borderColor: "#32d4ff", borderRadius: 8, padding: 8, alignItems: "center", zIndex: 1001 },
  inspectorClose: { position: "absolute", top: 4, right: 8, zIndex: 10 },
  inspectorImage: { width: 140, height: 195, borderRadius: 6, marginBottom: 6 },
  inspectorTitle: { color: "#fff2d8", fontSize: 12, fontWeight: "900", textAlign: "center" },
  inspectorType: { color: "#a8b0a1", fontSize: 10, fontWeight: "700", textAlign: "center", marginBottom: 4 },
  inspectorText: { color: "#d8d0be", fontSize: 9, lineHeight: 12, textAlign: "center" }
});
