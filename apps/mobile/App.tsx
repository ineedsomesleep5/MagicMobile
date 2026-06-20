import { useMemo, useState } from "react";
import {
  ActivityIndicator,
  Alert,
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
  commandTemplate?: Record<string, string>;
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
const defaultServerUrl = "http://192.168.68.168:3000";
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
  const human = snapshot?.players.find((player) => player.playerId === humanPlayerId);
  const opponent = snapshot?.players.find((player) => player.playerId !== humanPlayerId);
  const selectedActions = snapshot?.legalActions?.filter((action) => action.cardInstanceId === selectedCard?.instanceId || action.sourceInstanceId === selectedCard?.instanceId) ?? [];
  const promptActions = snapshot?.legalActions?.filter((action) => ["keep_hand", "mulligan", "resolve_choice", "pass_priority", "pass_until_response", "concede"].includes(action.type)) ?? [];

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
      const command = commandForAction(snapshot.id, action);
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
      <ScrollView horizontal contentContainerStyle={styles.landscapeShell}>
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
      </ScrollView>
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
  if (!snapshot || !human || !opponent) {
    return (
      <View style={styles.loadingPanel}>
        <ActivityIndicator color="#ffb45d" />
        <Text style={styles.panelTitle}>Starting Commander table...</Text>
      </View>
    );
  }

  const actions = selectedActions.length > 0 ? selectedActions : promptActions;
  return (
    <View style={styles.gameLayout}>
      <View style={styles.battlefield}>
        <PlayerRail player={opponent} label="Noaddrag" />
        <CardRow title="Opponent Battlefield" cards={opponent.zones.battlefield} selectedCard={selectedCard} onSelect={setSelectedCard} />
        <View style={styles.centerPrompt}>
          <Text style={styles.phaseText}>{snapshot.step ?? snapshot.phase}</Text>
          <Text style={styles.promptText}>{snapshot.promptText ?? "Waiting for XMage"}</Text>
          <Text style={styles.promptMeta}>Turn {snapshot.turn} - Priority {snapshot.priorityPlayerId ?? "none"}</Text>
        </View>
        <CardRow title="Your Battlefield" cards={human.zones.battlefield} selectedCard={selectedCard} onSelect={setSelectedCard} />
        <HandFan cards={human.zones.hand} selectedCard={selectedCard} onSelect={setSelectedCard} />
        <PlayerRail player={human} label="TabletopPolish" active />
      </View>
      <View style={styles.sidePanel}>
        <Text style={styles.panelTitle}>Stages</Text>
        <View style={styles.stageGrid}>
          {steps.map((step) => (
            <Text key={step} style={step === snapshot.step ? styles.stageActive : styles.stage}>{step.replace("-", " ")}</Text>
          ))}
        </View>
        <Text style={styles.panelTitle}>Actions</Text>
        <ScrollView style={styles.actionList}>
          {actions.map((action) => (
            <TouchableOpacity key={action.id} style={styles.contextButton} onPress={() => onRunAction(action)}>
              <Text style={styles.contextButtonText}>{action.label}</Text>
            </TouchableOpacity>
          ))}
          <TouchableOpacity style={styles.secondaryButton} onPress={onNewGame}>
            <Text style={styles.secondaryButtonText}>New game</Text>
          </TouchableOpacity>
        </ScrollView>
        <CardInspector card={selectedCard} />
        <Text style={styles.panelTitle}>Log</Text>
        <ScrollView style={styles.logList}>
          {snapshot.log.slice(-10).map((entry) => (
            <Text key={entry.id} style={styles.logLine}>{entry.message}</Text>
          ))}
        </ScrollView>
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

function PlayerRail({ player, label, active = false }: { player: PlayerGameState; label: string; active?: boolean }) {
  const commander = player.zones.command[0]?.card.name ?? "No commander";
  return (
    <View style={styles.playerRail}>
      <View style={active ? styles.lifeActive : styles.life}><Text style={styles.lifeText}>{player.life}</Text></View>
      <Text style={styles.playerName}>{label}</Text>
      <Text style={styles.zoneText}>Library {player.zones.library.length}  Grave {player.zones.graveyard.length}  Exile {player.zones.exile.length}</Text>
      <Text style={styles.zoneText}>Commander: {commander}  Tax {player.commanderTax}</Text>
    </View>
  );
}

function CardRow({ title, cards, selectedCard, onSelect }: { title: string; cards: ZoneCard[]; selectedCard: ZoneCard | undefined; onSelect: (card: ZoneCard) => void }) {
  return (
    <View style={styles.cardRowWrap}>
      <Text style={styles.rowTitle}>{title}</Text>
      <ScrollView horizontal contentContainerStyle={styles.cardRow}>
        {cards.length === 0 ? <Text style={styles.emptyText}>No permanents</Text> : null}
        {cards.map((card) => (
          <CardButton key={card.instanceId} card={card} selected={selectedCard?.instanceId === card.instanceId} onPress={() => onSelect(card)} />
        ))}
      </ScrollView>
    </View>
  );
}

function HandFan({ cards, selectedCard, onSelect }: { cards: ZoneCard[]; selectedCard: ZoneCard | undefined; onSelect: (card: ZoneCard) => void }) {
  return (
    <View style={styles.handFan}>
      {cards.map((card, index) => (
        <TouchableOpacity
          key={card.instanceId}
          style={[
            styles.handCard,
            { transform: [{ rotate: `${(index - (cards.length - 1) / 2) * 4}deg` }, { translateY: selectedCard?.instanceId === card.instanceId ? -20 : Math.abs(index - (cards.length - 1) / 2) * 3 }] }
          ]}
          onPress={() => onSelect(card)}
        >
          <Text style={styles.cardName} numberOfLines={2}>{card.card.name}</Text>
          <Text style={styles.cardType} numberOfLines={1}>{card.card.typeLine}</Text>
        </TouchableOpacity>
      ))}
    </View>
  );
}

function CardButton({ card, selected, onPress }: { card: ZoneCard; selected: boolean; onPress: () => void }) {
  return (
    <TouchableOpacity style={[styles.cardButton, selected && styles.cardButtonSelected, card.tapped && styles.cardTapped]} onPress={onPress}>
      <Text style={styles.cardName} numberOfLines={2}>{card.card.name}</Text>
      <Text style={styles.cardType} numberOfLines={2}>{card.card.typeLine}</Text>
      {card.power !== undefined || card.toughness !== undefined ? <Text style={styles.ptBadge}>{card.power ?? "*"}/{card.toughness ?? "*"}</Text> : null}
    </TouchableOpacity>
  );
}

function CardInspector({ card }: { card: ZoneCard | undefined }) {
  return (
    <View style={styles.inspector}>
      <Text style={styles.inspectorKicker}>Selected</Text>
      <Text style={styles.inspectorTitle}>{card?.card.name ?? "Tap a card"}</Text>
      <Text style={styles.inspectorType}>{card?.card.typeLine ?? "Inspect hand, battlefield, command, graveyard, or exile cards."}</Text>
      <Text style={styles.inspectorText}>{card?.card.oracleText ?? ""}</Text>
    </View>
  );
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

function commandForAction(gameId: string, action: LegalAction): Record<string, unknown> {
  const template = action.commandTemplate ?? {};
  if (action.type === "resolve_choice") {
    return { type: "resolve_choice", gameId, playerId: action.playerId, promptId: action.id, choiceIds: action.targetIds ?? [] };
  }
  if (action.type === "activate_ability" || action.type === "make_mana") {
    return { type: action.type, gameId, playerId: action.playerId, sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId, abilityId: template.abilityId ?? action.id };
  }
  return { ...template, type: action.type, gameId, playerId: action.playerId, cardInstanceId: action.cardInstanceId, sourceInstanceId: action.sourceInstanceId };
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
  landscapeShell: { minWidth: 940, flexGrow: 1 },
  appFrame: { flex: 1, minWidth: 940, minHeight: 520, padding: 12, backgroundColor: "#101817" },
  header: { height: 62, flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12 },
  logoButton: { minWidth: 180 },
  logo: { color: "#fff2d8", fontSize: 24, fontWeight: "900" },
  logoSub: { color: "#ffb45d", fontSize: 12, fontWeight: "800", textTransform: "uppercase" },
  statusPanel: { flex: 1, minHeight: 46, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, paddingHorizontal: 12, flexDirection: "row", alignItems: "center", justifyContent: "flex-end", gap: 10, backgroundColor: "#0a0f0f" },
  statusText: { color: "#d7d0bf", fontWeight: "700", textAlign: "right" },
  menuGrid: { flex: 1, flexDirection: "row", gap: 12, alignItems: "stretch" },
  heroPanel: { flex: 1, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 18, justifyContent: "space-between", backgroundColor: "#14211d" },
  heroTitle: { color: "#fff2d8", fontSize: 28, fontWeight: "900" },
  heroBody: { color: "#c7c0ae", fontSize: 16, lineHeight: 23, fontWeight: "600" },
  twoColumn: { flex: 1, flexDirection: "row", gap: 12 },
  panel: { flex: 1, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 14, gap: 12, backgroundColor: "#101615" },
  panelTitle: { color: "#ffb45d", fontSize: 16, fontWeight: "900", textTransform: "uppercase" },
  input: { minHeight: 44, borderWidth: 1, borderColor: "#40534f", borderRadius: 7, paddingHorizontal: 12, color: "#fff2d8", fontWeight: "700", backgroundColor: "#080d0d" },
  deckInput: { flex: 1, minHeight: 260, borderWidth: 1, borderColor: "#40534f", borderRadius: 7, padding: 12, color: "#fff2d8", fontWeight: "700", textAlignVertical: "top", backgroundColor: "#080d0d" },
  helpText: { color: "#b7b09f", lineHeight: 20, fontWeight: "600" },
  deckSummary: { color: "#fff2d8", fontSize: 17, lineHeight: 24, fontWeight: "800" },
  actionRow: { flexDirection: "row", flexWrap: "wrap", gap: 10 },
  primaryButton: { minHeight: 44, borderRadius: 8, paddingHorizontal: 16, paddingVertical: 12, alignItems: "center", justifyContent: "center", backgroundColor: "#f57a2d" },
  primaryButtonText: { color: "#fff6e8", fontWeight: "900" },
  secondaryButton: { minHeight: 44, borderWidth: 1, borderColor: "#526964", borderRadius: 8, paddingHorizontal: 14, paddingVertical: 11, alignItems: "center", justifyContent: "center", backgroundColor: "#17221f" },
  secondaryButtonText: { color: "#fff2d8", fontWeight: "900" },
  segmentRow: { flexDirection: "row", gap: 8 },
  segment: { borderWidth: 1, borderColor: "#526964", borderRadius: 8, paddingHorizontal: 14, paddingVertical: 10 },
  segmentActive: { borderWidth: 1, borderColor: "#35c7ff", borderRadius: 8, paddingHorizontal: 14, paddingVertical: 10, backgroundColor: "#123845" },
  segmentText: { color: "#c7c0ae", fontWeight: "800" },
  segmentActiveText: { color: "#f2fbff", fontWeight: "900" },
  loadingPanel: { flex: 1, alignItems: "center", justifyContent: "center", gap: 12 },
  gameLayout: { flex: 1, flexDirection: "row", gap: 10 },
  battlefield: { flex: 1, borderWidth: 1, borderColor: "#344d37", borderRadius: 8, padding: 10, justifyContent: "space-between", backgroundColor: "#20371e" },
  sidePanel: { width: 286, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 10, gap: 8, backgroundColor: "#0b1010" },
  playerRail: { minHeight: 54, flexDirection: "row", alignItems: "center", gap: 10 },
  life: { width: 44, height: 44, borderRadius: 22, borderWidth: 2, borderColor: "#e6dac2", alignItems: "center", justifyContent: "center", backgroundColor: "#514b3f" },
  lifeActive: { width: 44, height: 44, borderRadius: 22, borderWidth: 2, borderColor: "#35c7ff", alignItems: "center", justifyContent: "center", backgroundColor: "#2e4c5c" },
  lifeText: { color: "#fff2d8", fontSize: 20, fontWeight: "900" },
  playerName: { minWidth: 110, color: "#fff2d8", fontWeight: "900" },
  zoneText: { color: "#d1cab9", fontWeight: "700" },
  cardRowWrap: { minHeight: 82, gap: 4 },
  rowTitle: { color: "#ffb45d", fontSize: 11, fontWeight: "900", textTransform: "uppercase" },
  cardRow: { gap: 8, alignItems: "center" },
  cardButton: { width: 76, height: 106, borderRadius: 7, borderWidth: 2, borderColor: "#273633", padding: 6, justifyContent: "space-between", backgroundColor: "#d5c5a3" },
  cardButtonSelected: { borderColor: "#32d4ff", shadowColor: "#32d4ff", shadowOpacity: 0.7, shadowRadius: 10 },
  cardTapped: { transform: [{ rotate: "10deg" }] },
  cardName: { color: "#17130d", fontSize: 11, fontWeight: "900" },
  cardType: { color: "#31271b", fontSize: 9, fontWeight: "700" },
  ptBadge: { alignSelf: "flex-end", color: "#17130d", fontWeight: "900" },
  emptyText: { color: "#a8b0a1", fontWeight: "700" },
  centerPrompt: { alignSelf: "center", minWidth: 420, borderRadius: 8, padding: 10, alignItems: "center", backgroundColor: "rgba(5,8,8,0.72)" },
  phaseText: { color: "#ffb45d", fontSize: 18, fontWeight: "900", textTransform: "uppercase" },
  promptText: { color: "#fff2d8", fontSize: 16, fontWeight: "900", textAlign: "center" },
  promptMeta: { color: "#b7b09f", fontWeight: "800" },
  handFan: { height: 120, flexDirection: "row", alignItems: "flex-end", justifyContent: "center", gap: -12 },
  handCard: { width: 82, height: 112, marginHorizontal: -5, borderWidth: 2, borderColor: "#23c7ff", borderRadius: 7, padding: 7, justifyContent: "space-between", backgroundColor: "#d9c8a7" },
  stageGrid: { flexDirection: "row", flexWrap: "wrap", gap: 5 },
  stage: { width: 82, borderWidth: 1, borderColor: "#283733", borderRadius: 6, padding: 5, color: "#b9b2a1", fontSize: 10, fontWeight: "800", textAlign: "center" },
  stageActive: { width: 82, borderWidth: 1, borderColor: "#ffb45d", borderRadius: 6, padding: 5, color: "#fff2d8", fontSize: 10, fontWeight: "900", textAlign: "center", backgroundColor: "#59391d" },
  actionList: { maxHeight: 132 },
  contextButton: { minHeight: 38, borderRadius: 7, paddingHorizontal: 10, paddingVertical: 9, marginBottom: 6, backgroundColor: "#69391f" },
  contextButtonText: { color: "#fff2d8", fontWeight: "900", textAlign: "center" },
  inspector: { minHeight: 110, borderWidth: 1, borderColor: "#30413c", borderRadius: 8, padding: 9, backgroundColor: "#111817" },
  inspectorKicker: { color: "#ffb45d", fontSize: 10, fontWeight: "900", textTransform: "uppercase" },
  inspectorTitle: { color: "#fff2d8", fontSize: 15, fontWeight: "900" },
  inspectorType: { color: "#d8d0be", fontSize: 11, fontWeight: "800" },
  inspectorText: { color: "#bcb5a6", fontSize: 11, lineHeight: 15 },
  logList: { flex: 1 },
  logLine: { color: "#c9c2b2", fontSize: 11, lineHeight: 16, fontWeight: "700", borderBottomWidth: 1, borderBottomColor: "#1d2926", paddingVertical: 4 }
});
