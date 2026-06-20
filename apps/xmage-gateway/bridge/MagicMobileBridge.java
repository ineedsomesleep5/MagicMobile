import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import mage.cards.decks.DeckCardInfo;
import mage.cards.decks.DeckCardLists;
import mage.cards.repository.CardScanner;
import mage.cards.repository.CardInfo;
import mage.cards.repository.CardRepository;
import mage.cards.repository.RepositoryUtil;
import mage.constants.MatchBufferTime;
import mage.constants.MatchTimeLimit;
import mage.constants.MultiplayerAttackOption;
import mage.constants.PhaseStep;
import mage.constants.PlayerAction;
import mage.constants.RangeOfInfluence;
import mage.constants.SkillLevel;
import mage.constants.TurnPhase;
import mage.game.match.MatchOptions;
import mage.interfaces.MageClient;
import mage.interfaces.callback.ClientCallback;
import mage.interfaces.callback.ClientCallbackMethod;
import mage.players.PlayableObjectStats;
import mage.players.PlayableObjectsList;
import mage.players.PlayerType;
import mage.remote.Connection;
import mage.remote.Session;
import mage.remote.SessionImpl;
import mage.utils.MageVersion;
import mage.view.CardView;
import mage.view.CommandObjectView;
import mage.view.GameClientMessage;
import mage.view.GameView;
import mage.view.PermanentView;
import mage.view.PlayerView;
import mage.view.TableClientMessage;
import mage.view.TableView;

import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;

public final class MagicMobileBridge implements MageClient {
    private static final Gson GSON = new GsonBuilder().disableHtmlEscaping().create();
    private static final MageVersion VERSION = new MageVersion(MagicMobileBridge.class);
    private static final String SOURCE = "xmage-java-bridge";

    private final Object connectionLock = new Object();
    private final Map<String, GameRecord> games = new ConcurrentHashMap<>();
    private final String xmageHost;
    private final int xmagePort;
    private final String gatewayUrl;

    private Session session;
    private volatile String lastError = "";
    private volatile UUID lastStartedGameId;
    private volatile UUID lastStartedHumanPlayerId;
    private volatile boolean cardRepositoryReady;
    private volatile boolean bridgeConnected;

    private MagicMobileBridge(String xmageHost, int xmagePort, String gatewayUrl) {
        this.xmageHost = xmageHost;
        this.xmagePort = xmagePort;
        this.gatewayUrl = gatewayUrl;
    }

    public static void main(String[] args) throws Exception {
        String host = env("XMAGE_HOST", "127.0.0.1");
        int xmagePort = Integer.parseInt(env("XMAGE_PORT", "17171"));
        int bridgePort = Integer.parseInt(env("BRIDGE_PORT", "17172"));
        String gatewayUrl = env("GATEWAY_URL", "http://localhost:17171");
        MagicMobileBridge bridge = new MagicMobileBridge(host, xmagePort, gatewayUrl);

        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", bridgePort), 0);
        server.createContext("/", bridge::handleRequest);
        server.setExecutor(null);
        server.start();
        System.out.println("MagicMobile XMage Java bridge listening on " + bridgePort);
    }

    private void handleRequest(HttpExchange exchange) throws IOException {
        try {
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();

            if ("GET".equals(method) && "/health".equals(path)) {
                writeJson(exchange, 200, health());
                return;
            }

            if ("POST".equals(method) && "/games/commander".equals(path)) {
                writeJson(exchange, 201, createCommanderGame(readJson(exchange)));
                return;
            }

            String[] parts = path.split("/");
            if (parts.length >= 3 && "games".equals(parts[1])) {
                String gameId = parts[2];
                if ("GET".equals(method) && parts.length == 3) {
                    writeJson(exchange, 200, snapshot(gameId));
                    return;
                }
                if ("GET".equals(method) && parts.length == 4 && "legal-actions".equals(parts[3])) {
                    writeJson(exchange, 200, legalActionsArray(gameId));
                    return;
                }
                if ("POST".equals(method) && parts.length == 4 && "commands".equals(parts[3])) {
                    writeJson(exchange, 200, submitCommand(gameId, readJson(exchange)));
                    return;
                }
            }

            JsonObject body = new JsonObject();
            body.addProperty("error", "Not found");
            writeJson(exchange, 404, body);
        } catch (Exception error) {
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
            JsonObject body = new JsonObject();
            body.addProperty("error", lastError);
            writeJson(exchange, 500, body);
        }
    }

    private JsonObject createCommanderGame(JsonObject config) throws Exception {
        ensureConnected(false);
        UUID roomId = session.getMainRoomId();
        if (roomId == null) {
            throw new IllegalStateException("XMage main room is unavailable");
        }

        String humanExternalId = string(config, "humanPlayerId", "human");
        JsonArray aiPlayers = array(config, "aiPlayers");
        JsonObject aiConfig = aiPlayers.size() > 0 && aiPlayers.get(0).isJsonObject() ? aiPlayers.get(0).getAsJsonObject() : new JsonObject();
        String aiExternalId = string(aiConfig, "playerId", "ai-1");
        String aiName = string(aiConfig, "displayName", "XMage AI");
        PlayerType aiType = playerTypeForDifficulty(string(aiConfig, "difficulty", "normal"));
        int aiSkill = skillForDifficulty(string(aiConfig, "difficulty", "normal"));

        MatchOptions options = new MatchOptions("MagicMobile Commander " + System.currentTimeMillis(), "Commander Two Player Duel", false);
        options.getPlayerTypes().add(PlayerType.HUMAN);
        options.getPlayerTypes().add(aiType);
        options.setDeckType("Variant Magic - Commander");
        options.setAttackOption(MultiplayerAttackOption.MULTIPLE);
        options.setRange(RangeOfInfluence.ONE);
        options.setWinsNeeded(1);
        options.setMatchTimeLimit(MatchTimeLimit.NONE);
        options.setMatchBufferTime(MatchBufferTime.NONE);
        options.setSkillLevel(SkillLevel.CASUAL);
        options.setRollbackTurnsAllowed(true);
        options.setSpectatorsAllowed(false);
        options.setRated(false);
        options.setQuitRatio(100);
        options.setMinimumRating(0);

        lastStartedGameId = null;
        lastStartedHumanPlayerId = null;

        TableView table = session.createTable(roomId, options);
        if (table == null) {
            ensureConnected(true);
            roomId = session.getMainRoomId();
            if (roomId == null) {
                throw new IllegalStateException("XMage main room is unavailable after reconnect");
            }
            table = session.createTable(roomId, options);
        }
        if (table == null) {
            String reason = lastError == null || lastError.isEmpty() ? "no XMage error detail returned" : lastError;
            throw new IllegalStateException("XMage did not create a Commander table: " + reason);
        }

        boolean humanJoined = session.joinTable(roomId, table.getTableId(), "TabletopPolish", PlayerType.HUMAN, 1, deckFromConfig(object(config, "humanDeck")), "");
        boolean aiJoined = session.joinTable(roomId, table.getTableId(), aiName, aiType, aiSkill, deckFromConfig(object(aiConfig, "deck", object(config, "humanDeck"))), "");
        if (!humanJoined || !aiJoined) {
            throw new IllegalStateException("XMage rejected one of the Commander decks");
        }
        if (!session.startMatch(roomId, table.getTableId())) {
            throw new IllegalStateException("XMage did not start the Commander match");
        }

        GameRecord record = waitForStartedGame(humanExternalId, aiExternalId, aiName);
        games.put(record.gameId.toString(), record);
        return snapshot(record.gameId.toString());
    }

    private GameRecord waitForStartedGame(String humanExternalId, String aiExternalId, String aiName) throws InterruptedException {
        long deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(35);
        GameRecord lastRecord = null;
        while (System.currentTimeMillis() < deadline) {
            UUID gameId = lastStartedGameId;
            if (gameId != null) {
                GameRecord existing = games.get(gameId.toString());
                if (existing == null) {
                    existing = new GameRecord(gameId, humanExternalId, aiExternalId, aiName);
                    existing.humanXmagePlayerId = lastStartedHumanPlayerId;
                    games.put(gameId.toString(), existing);
                }
                if (existing.latestView != null) {
                    lastRecord = existing;
                    return existing;
                }
            }
            Thread.sleep(250);
        }
        if (lastRecord != null) {
            return lastRecord;
        }
        throw new IllegalStateException("Timed out waiting for XMage game snapshot");
    }

    private JsonObject submitCommand(String gameId, JsonObject command) throws Exception {
        ensureConnected(false);
        UUID xmageGameId = UUID.fromString(gameId);
        String type = string(command, "type", "");

        if ("pass_priority".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("keep_hand".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, false);
        } else if ("mulligan".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("pass_until_response".equals(type) || "pass_until_next_turn".equals(type) || "advance_phase".equals(type)) {
            session.sendPlayerAction(PlayerAction.PASS_PRIORITY_UNTIL_NEXT_MAIN_PHASE, xmageGameId, null);
        } else if ("concede".equals(type)) {
            session.sendPlayerAction(PlayerAction.CONCEDE, xmageGameId, null);
        } else if ("choose_target".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "targetIds"));
        } else if ("choose_card".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "cardInstanceIds"));
        } else if ("resolve_choice".equals(type)) {
            JsonArray choices = array(command, "choiceIds");
            if (choices.size() > 0) {
                String choice = choices.get(0).getAsString();
                if (isUuid(choice)) {
                    session.sendPlayerUUID(xmageGameId, UUID.fromString(choice));
                } else {
                    session.sendPlayerString(xmageGameId, choice);
                }
            } else {
                session.sendPlayerBoolean(xmageGameId, true);
            }
        } else {
            String abilityId = string(command, "abilityId", "");
            String sourceId = string(command, "sourceInstanceId", string(command, "cardInstanceId", ""));
            session.sendPlayerUUID(xmageGameId, UUID.fromString(abilityId.isEmpty() ? sourceId : abilityId));
        }

        GameRecord record = games.get(gameId);
        if (record != null) {
            record.lastProgressAt = System.currentTimeMillis();
        }
        return waitForUpdatedSnapshot(gameId);
    }

    private void sendFirstUuid(UUID gameId, JsonArray ids) {
        if (ids.size() == 0) {
            session.sendPlayerBoolean(gameId, true);
            return;
        }
        session.sendPlayerUUID(gameId, UUID.fromString(ids.get(0).getAsString()));
    }

    private JsonObject waitForUpdatedSnapshot(String gameId) throws InterruptedException {
        GameRecord record = games.get(gameId);
        int startCycle = record == null ? -1 : record.latestCycle;
        long deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(12);
        while (System.currentTimeMillis() < deadline) {
            record = games.get(gameId);
            if (record != null && record.latestView != null && record.latestCycle != startCycle) {
                return snapshot(gameId);
            }
            Thread.sleep(200);
        }
        return snapshot(gameId);
    }

    private JsonObject snapshot(String gameId) {
        GameRecord record = games.get(gameId);
        if (record == null || record.latestView == null) {
            throw new IllegalArgumentException("Unknown XMage game: " + gameId);
        }
        GameView view = record.latestView;
        Map<UUID, String> playerIds = externalPlayerIds(record, view);

        JsonObject snapshot = new JsonObject();
        snapshot.addProperty("id", gameId);
        snapshot.addProperty("source", SOURCE);
        snapshot.addProperty("roomId", "xmage-room");
        snapshot.addProperty("phase", phase(view.getPhase()));
        snapshot.addProperty("step", step(view.getStep()));
        snapshot.addProperty("turn", view.getTurn());
        snapshot.addProperty("activePlayerId", playerIds.get(view.getActivePlayerId()));
        snapshot.addProperty("priorityPlayerId", priorityPlayerId(playerIds, view));
        snapshot.addProperty("waitingOnPlayerId", priorityPlayerId(playerIds, view));
        snapshot.addProperty("promptText", promptText(record, view));
        snapshot.add("players", players(record, view, playerIds));
        snapshot.add("log", log(record, view));
        snapshot.add("legalActions", legalActions(record, view, playerIds));
        snapshot.add("engineHealth", health());
        if (record.choicePrompt != null) {
            snapshot.add("choicePrompt", record.choicePrompt);
        }
        return snapshot;
    }

    private JsonArray legalActionsArray(String gameId) {
        GameRecord record = games.get(gameId);
        if (record == null || record.latestView == null) {
            return new JsonArray();
        }
        return legalActions(record, record.latestView, externalPlayerIds(record, record.latestView));
    }

    private JsonArray legalActions(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonArray actions = new JsonArray();
        String humanId = record.humanExternalId;

        if (isMulliganPrompt(record)) {
            actions.add(action("xmage-keep", "keep_hand", humanId, "Keep", null, null, null));
            actions.add(action("xmage-mulligan", "mulligan", humanId, "Mulligan", null, null, null));
            actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));
            markPrimary(actions, "xmage-keep", "Keep");
            return actions;
        }

        if (record.choicePrompt != null && record.choicePrompt.has("choices")) {
            for (JsonElement choiceElement : record.choicePrompt.getAsJsonArray("choices")) {
                if (!choiceElement.isJsonObject()) continue;
                JsonObject choice = choiceElement.getAsJsonObject();
                String choiceId = string(choice, "id", "");
                if (choiceId.isEmpty()) continue;
                actions.add(choiceAction(choiceId, humanId, labelForChoice(record, playerIds, choiceId)));
            }
            actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));
            return actions;
        }

        if (humanHasPriority(record, view)) {
            actions.add(action("xmage-pass", "pass_priority", humanId, "Done", null, null, null));
            actions.add(action("xmage-pass-main", "pass_until_response", humanId, "Pass until response", null, null, null));
            actions.add(action("xmage-pass-turn", "pass_until_next_turn", humanId, "Pass until next turn", null, null, null));
            markPrimary(actions, "xmage-pass", "Done");
        }
        actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));

        PlayableObjectsList playable = view.getCanPlayObjects();
        if (playable == null || playable.isEmpty()) {
            return actions;
        }

        Set<UUID> handIds = new HashSet<>(view.getMyHand().keySet());
        for (Map.Entry<UUID, PlayableObjectStats> entry : playable.getObjects().entrySet()) {
            UUID objectId = entry.getKey();
            CardView card = findVisibleCard(view, objectId);
            if (card == null) {
                continue;
            }
            List<UUID> abilityIds = entry.getValue().getPlayableAbilityIds();
            String abilityId = abilityIds.isEmpty() ? null : abilityIds.get(0).toString();
            String type = actionType(card, handIds.contains(objectId));
            String sourceZone = handIds.contains(objectId) ? "hand" : card.isLand() ? "battlefield" : "battlefield";
            actions.add(action(
                    abilityId == null ? objectId.toString() : abilityId,
                    type,
                    humanId,
                    labelFor(type, card.getName()),
                    objectId.toString(),
                    sourceZone,
                    abilityId
            ));
        }

        return actions;
    }

    private JsonObject action(String id, String type, String playerId, String label, String cardInstanceId, String sourceZone, String abilityId) {
        JsonObject action = new JsonObject();
        action.addProperty("id", id);
        action.addProperty("type", type);
        action.addProperty("playerId", playerId);
        action.addProperty("label", label);
        action.addProperty("shortLabel", shortLabel(type, label));
        action.addProperty("requiresTarget", requiresTarget(type));
        if (cardInstanceId != null) {
            action.addProperty("cardInstanceId", cardInstanceId);
            action.addProperty("sourceInstanceId", cardInstanceId);
        }
        if (sourceZone != null) {
            action.addProperty("sourceZone", sourceZone);
        }
        if (abilityId != null) {
            JsonObject template = new JsonObject();
            template.addProperty("abilityId", abilityId);
            action.add("commandTemplate", template);
        }
        return action;
    }

    private void markPrimary(JsonArray actions, String id, String shortLabel) {
        for (JsonElement element : actions) {
            if (!element.isJsonObject()) continue;
            JsonObject action = element.getAsJsonObject();
            if (id.equals(string(action, "id", ""))) {
                action.addProperty("isPrimary", true);
                action.addProperty("shortLabel", shortLabel);
            }
        }
    }

    private String shortLabel(String type, String label) {
        if ("pass_priority".equals(type)) return "Done";
        if ("pass_until_response".equals(type)) return "Pass";
        if ("pass_until_next_turn".equals(type)) return "Skip turn";
        if ("play_land".equals(type)) return "Play";
        if ("cast_spell".equals(type)) return "Cast";
        return label;
    }

    private boolean requiresTarget(String type) {
        return "choose_target".equals(type) || "declare_attackers".equals(type) || "declare_blockers".equals(type);
    }

    private JsonObject choiceAction(String choiceId, String playerId, String label) {
        JsonObject action = action("xmage-choice-" + choiceId, "resolve_choice", playerId, label, null, null, null);
        JsonArray targetIds = new JsonArray();
        targetIds.add(choiceId);
        action.add("targetIds", targetIds);
        action.add("validTargetIds", targetIds.deepCopy());
        return action;
    }

    private String labelForChoice(GameRecord record, Map<UUID, String> playerIds, String choiceId) {
        if (isUuid(choiceId)) {
            UUID id = UUID.fromString(choiceId);
            CardView card = record.latestView == null ? null : findVisibleCard(record.latestView, id);
            if (card != null) {
                boolean bottomPrompt = record.promptText != null && record.promptText.toLowerCase().contains("bottom");
                return (bottomPrompt ? "Bottom " : "Choose ") + card.getName();
            }
            String externalId = playerIds.get(id);
            boolean startingPlayerPrompt = record.promptText != null && record.promptText.toLowerCase().contains("starting player");
            if (record.humanExternalId.equals(externalId)) {
                return startingPlayerPrompt ? "You start" : "Choose you";
            }
            if (record.aiExternalId.equals(externalId)) {
                return startingPlayerPrompt ? record.aiName + " starts" : "Choose " + record.aiName;
            }
        }
        return "Choose " + choiceId;
    }

    private String actionType(CardView card, boolean inHand) {
        if (inHand && card.isLand()) {
            return "play_land";
        }
        if (inHand) {
            return "cast_spell";
        }
        if (card.isLand()) {
            return "make_mana";
        }
        return "activate_ability";
    }

    private String labelFor(String type, String name) {
        if ("play_land".equals(type)) return "Play " + name;
        if ("cast_spell".equals(type)) return "Cast " + name;
        if ("make_mana".equals(type)) return "Tap " + name;
        return "Activate " + name;
    }

    private CardView findVisibleCard(GameView view, UUID id) {
        if (view.getMyHand().containsKey(id)) return view.getMyHand().get(id);
        for (PlayerView player : view.getPlayers()) {
            if (player.getBattlefield().containsKey(id)) return player.getBattlefield().get(id);
            if (player.getGraveyard().containsKey(id)) return player.getGraveyard().get(id);
            if (player.getExile().containsKey(id)) return player.getExile().get(id);
            for (CommandObjectView command : player.getCommandObjectList()) {
                if (command.getId().equals(id) && command instanceof CardView) {
                    return (CardView) command;
                }
            }
        }
        return null;
    }

    private JsonArray players(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonArray players = new JsonArray();
        for (PlayerView player : view.getPlayers()) {
            JsonObject out = new JsonObject();
            String externalId = playerIds.get(player.getPlayerId());
            out.addProperty("playerId", externalId);
            out.addProperty("life", player.getLife());
            out.addProperty("poison", counterValue(player, "poison"));
            out.addProperty("commanderTax", 0);

            JsonObject zones = new JsonObject();
            boolean human = externalId.equals(record.humanExternalId);
            zones.add("library", hiddenCards(player.getLibraryCount(), "library-" + externalId));
            zones.add("hand", human ? zoneCards(view.getMyHand().values(), false) : hiddenCards(player.getHandCount(), "hand-" + externalId));
            zones.add("battlefield", battlefieldCards(player.getBattlefield().values()));
            zones.add("graveyard", zoneCards(player.getGraveyard().values(), false));
            zones.add("exile", zoneCards(player.getExile().values(), false));
            zones.add("command", commandCards(player.getCommandObjectList()));
            zones.add("stack", human ? zoneCards(view.getStack().values(), false) : new JsonArray());
            out.add("zones", zones);

            JsonObject commanderDamage = new JsonObject();
            for (String id : playerIds.values()) {
                commanderDamage.addProperty(id, 0);
            }
            out.add("commanderDamage", commanderDamage);
            players.add(out);
        }
        return players;
    }

    private JsonArray battlefieldCards(Iterable<PermanentView> cards) {
        JsonArray out = new JsonArray();
        for (PermanentView card : cards) {
            JsonObject zoneCard = zoneCard(card);
            zoneCard.addProperty("tapped", card.isTapped());
            zoneCard.addProperty("damage", card.getDamage());
            if (card.getAttachedTo() != null) {
                zoneCard.addProperty("attachedToInstanceId", card.getAttachedTo().toString());
            }
            out.add(zoneCard);
        }
        return out;
    }

    private JsonArray zoneCards(Iterable<CardView> cards, boolean hidden) {
        JsonArray out = new JsonArray();
        for (CardView card : cards) {
            out.add(hidden ? hiddenCard(card.getId().toString()) : zoneCard(card));
        }
        return out;
    }

    private JsonArray commandCards(List<CommandObjectView> commands) {
        JsonArray out = new JsonArray();
        for (CommandObjectView command : commands) {
            if (command instanceof CardView) {
                out.add(zoneCard((CardView) command));
            }
        }
        return out;
    }

    private JsonObject zoneCard(CardView card) {
        JsonObject out = new JsonObject();
        out.addProperty("instanceId", card.getId().toString());
        JsonObject identity = new JsonObject();
        identity.addProperty("id", card.getId().toString());
        identity.addProperty("name", card.getName());
        identity.addProperty("manaValue", card.getManaValue());
        identity.add("colorIdentity", colorIdentity(card));
        identity.addProperty("typeLine", card.getTypeText());
        if (card.getRules() != null && !card.getRules().isEmpty()) {
            identity.addProperty("oracleText", String.join("\n", card.getRules()));
        }
        identity.addProperty("isBasicLand", card.isLand() && card.getSuperTypes().toString().contains("Basic"));
        out.add("card", identity);
        Integer power = parseStat(card.getPower());
        Integer toughness = parseStat(card.getToughness());
        if (power != null) out.addProperty("power", power);
        if (toughness != null) out.addProperty("toughness", toughness);
        return out;
    }

    private JsonArray hiddenCards(int count, String prefix) {
        JsonArray out = new JsonArray();
        for (int i = 0; i < count; i++) {
            out.add(hiddenCard(prefix + "-" + i));
        }
        return out;
    }

    private JsonObject hiddenCard(String instanceId) {
        JsonObject out = new JsonObject();
        out.addProperty("instanceId", instanceId);
        JsonObject card = new JsonObject();
        card.addProperty("id", instanceId);
        card.addProperty("name", "Hidden card");
        card.addProperty("manaValue", 0);
        card.add("colorIdentity", new JsonArray());
        card.addProperty("typeLine", "Hidden");
        out.add("card", card);
        return out;
    }

    private JsonArray colorIdentity(CardView card) {
        JsonArray array = new JsonArray();
        String identity = Optional.ofNullable(card.getOriginalColorIdentity()).orElse("");
        for (String symbol : new String[]{"W", "U", "B", "R", "G", "C"}) {
            if (identity.contains(symbol)) {
                array.add(symbol);
            }
        }
        return array;
    }

    private Integer parseStat(String value) {
        try {
            if (value == null || value.trim().isEmpty()) return null;
            return Integer.parseInt(value.trim());
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private Map<UUID, String> externalPlayerIds(GameRecord record, GameView view) {
        Map<UUID, String> ids = new HashMap<>();
        UUID humanUuid = record.humanXmagePlayerId;
        for (PlayerView player : view.getPlayers()) {
            if (humanUuid == null && player.getControlled()) {
                humanUuid = player.getPlayerId();
                record.humanXmagePlayerId = humanUuid;
            }
        }
        for (PlayerView player : view.getPlayers()) {
            ids.put(player.getPlayerId(), player.getPlayerId().equals(humanUuid) ? record.humanExternalId : record.aiExternalId);
        }
        return ids;
    }

    private String priorityPlayerId(Map<UUID, String> playerIds, GameView view) {
        for (PlayerView player : view.getPlayers()) {
            if (player.hasPriority()) {
                return playerIds.get(player.getPlayerId());
            }
        }
        return null;
    }

    private boolean humanHasPriority(GameRecord record, GameView view) {
        for (PlayerView player : view.getPlayers()) {
            if (player.getPlayerId().equals(record.humanXmagePlayerId)) {
                return player.hasPriority() || player.isTimerActive();
            }
        }
        return false;
    }

    private String promptText(GameRecord record, GameView view) {
        if (record.promptText != null && !record.promptText.isEmpty()) {
            return record.promptText;
        }
        if (humanHasPriority(record, view)) {
            return "Your priority";
        }
        return "Waiting for AI";
    }

    private JsonArray log(GameRecord record, GameView view) {
        JsonArray log = new JsonArray();
        log.add(logEntry("xmage-start", "XMage Commander game connected"));
        log.add(logEntry("xmage-state", "Turn " + view.getTurn() + " - " + view.getStep()));
        if (record.promptText != null && !record.promptText.isEmpty()) {
            log.add(logEntry("xmage-prompt", record.promptText));
        }
        return log;
    }

    private boolean isOpeningSnapshotReady(GameRecord record) {
        GameView view = record.latestView;
        if (view == null) {
            return false;
        }
        if (isMulliganPrompt(record)) {
            return true;
        }
        return view.getMyHand() != null && !view.getMyHand().isEmpty();
    }

    private boolean isMulliganPrompt(GameRecord record) {
        return record.promptText != null && record.promptText.toLowerCase().contains("mulligan");
    }

    private JsonObject logEntry(String id, String message) {
        JsonObject entry = new JsonObject();
        entry.addProperty("id", id);
        entry.addProperty("message", message);
        entry.addProperty("createdAt", new Date().toInstant().toString());
        return entry;
    }

    private String phase(TurnPhase phase) {
        if (phase == null) return "beginning";
        switch (phase) {
            case BEGINNING: return "beginning";
            case PRECOMBAT_MAIN: return "precombat-main";
            case COMBAT: return "combat";
            case POSTCOMBAT_MAIN: return "postcombat-main";
            case END: return "ending";
            default: return "beginning";
        }
    }

    private String step(PhaseStep step) {
        if (step == null) return "untap";
        switch (step) {
            case UNTAP: return "untap";
            case UPKEEP: return "upkeep";
            case DRAW: return "draw";
            case PRECOMBAT_MAIN: return "precombat-main";
            case BEGIN_COMBAT: return "begin-combat";
            case DECLARE_ATTACKERS: return "declare-attackers";
            case DECLARE_BLOCKERS: return "declare-blockers";
            case FIRST_COMBAT_DAMAGE:
            case COMBAT_DAMAGE: return "combat-damage";
            case END_COMBAT: return "end-combat";
            case POSTCOMBAT_MAIN: return "postcombat-main";
            case END_TURN: return "end";
            case CLEANUP: return "cleanup";
            default: return "untap";
        }
    }

    private int counterValue(PlayerView player, String name) {
        return player.getCounters().stream()
                .filter(counter -> name.equals(counter.getName()))
                .mapToInt(counter -> counter.getCount())
                .findFirst()
                .orElse(0);
    }

    private DeckCardLists deckFromConfig(JsonObject deckConfig) {
        ensureCardRepository();

        DeckCardLists deck = new DeckCardLists();
        deck.setName(string(deckConfig, "name", "MagicMobile Commander"));
        deck.setAuthor("MagicMobile");

        JsonObject commander = object(deckConfig, "commander", null);
        boolean hasCommanderObject = commander != null;
        if (commander != null) {
            addCard(deck.getSideboard(), string(commander, "cardName", ""), 1);
        }
        for (JsonElement entryElement : array(deckConfig, "entries")) {
            if (!entryElement.isJsonObject()) continue;
            JsonObject entry = entryElement.getAsJsonObject();
            String section = string(entry, "section", "deck");
            int quantity = integer(entry, "quantity", 1);
            String name = string(entry, "cardName", "");
            if ("commander".equals(section) && !hasCommanderObject) {
                addCard(deck.getSideboard(), name, quantity);
            } else if ("deck".equals(section)) {
                addCard(deck.getCards(), name, quantity);
            }
        }
        return deck;
    }

    private void addCard(List<DeckCardInfo> cards, String cardName, int quantity) {
        if (cardName == null || cardName.trim().isEmpty()) {
            return;
        }
        CardInfo info = CardRepository.instance.findPreferredCoreExpansionCard(cardName);
        if (info == null) {
            throw new IllegalArgumentException("XMage card not found: " + cardName);
        }
        for (int i = 0; i < quantity; i++) {
            cards.add(new DeckCardInfo(info.getName(), info.getCardNumber(), info.getSetCode()));
        }
    }

    private void ensureCardRepository() {
        synchronized (connectionLock) {
            if (cardRepositoryReady) {
                return;
            }
            RepositoryUtil.bootstrapLocalDb();
            if (RepositoryUtil.CARD_DB_RECREATE_BY_CLIENT_SIDE && RepositoryUtil.isDatabaseEmpty()) {
                CardScanner.scan();
            }
            cardRepositoryReady = true;
        }
    }

    private PlayerType playerTypeForDifficulty(String difficulty) {
        if ("expert".equals(difficulty)) {
            return PlayerType.COMPUTER_MAD;
        }
        return PlayerType.COMPUTER_MAD;
    }

    private int skillForDifficulty(String difficulty) {
        if ("easy".equals(difficulty)) return 3;
        if ("hard".equals(difficulty)) return 8;
        if ("expert".equals(difficulty)) return 10;
        return 5;
    }

    private JsonObject health() {
        JsonObject health = new JsonObject();
        boolean ready = false;
        String reason = "XMage bridge starting.";
        try {
            ensureConnected(false);
            ready = session != null && bridgeConnected && session.isConnected() && session.isServerReady();
            reason = ready
                    ? "XMage Java bridge connected to " + xmageHost + ":" + xmagePort + "."
                    : "XMage server is reachable but not ready.";
        } catch (Exception error) {
            reason = error.getMessage() == null ? error.toString() : error.getMessage();
        }
        health.addProperty("status", ready ? "ready" : "starting");
        health.addProperty("reason", reason);
        health.addProperty("checkedAt", new Date().toInstant().toString());
        health.addProperty("recoveryAction", ready ? "wait" : "restart_gateway");
        return health;
    }

    private void ensureConnected(boolean forceReconnect) {
        synchronized (connectionLock) {
            if (!forceReconnect && session != null && bridgeConnected && session.isConnected() && session.isServerReady()) {
                return;
            }
            if (session != null) {
                try {
                    session.connectStop(false, false);
                } catch (Exception ignored) {
                    // The session may already be dead; reconnect below with a fresh client.
                }
            }
            bridgeConnected = false;
            lastError = "";
            session = new SessionImpl(this);
            Connection connection = new Connection();
            connection.setUsername("mm" + (System.currentTimeMillis() % 1_000_000_000L));
            connection.setHost(xmageHost);
            connection.setPort(xmagePort);
            connection.setProxyType(Connection.ProxyType.NONE);
            boolean connected = session.connectStart(connection);
            if (!connected || !bridgeConnected || !session.isServerReady()) {
                throw new IllegalStateException(lastError.isEmpty() ? "XMage server is not ready yet" : lastError);
            }
        }
    }

    @Override
    public MageVersion getVersion() {
        return VERSION;
    }

    @Override
    public void connected(String message) {
        bridgeConnected = true;
        System.out.println("XMage connected: " + message);
    }

    @Override
    public void disconnected(boolean askToReconnect, boolean keepMySessionActive) {
        bridgeConnected = false;
        System.out.println("XMage disconnected");
    }

    @Override
    public void showMessage(String message) {
        lastError = message;
        System.out.println("XMage message: " + message);
    }

    @Override
    public void showError(String message) {
        lastError = message;
        System.err.println("XMage error: " + message);
    }

    @Override
    public void onNewConnection() {
        lastStartedGameId = null;
        lastStartedHumanPlayerId = null;
    }

    @Override
    public void onCallback(ClientCallback callback) {
        try {
            callback.decompressData();
            ClientCallbackMethod method = callback.getMethod();
            Object data = callback.getData();
            if (method == ClientCallbackMethod.START_GAME && data instanceof TableClientMessage) {
                TableClientMessage message = (TableClientMessage) data;
                lastStartedGameId = message.getGameId();
                lastStartedHumanPlayerId = message.getPlayerId();
            }
            if (data instanceof GameView) {
                updateRecord(callback.getObjectId(), (GameView) data, null, null);
            }
            if (data instanceof GameClientMessage) {
                GameClientMessage message = (GameClientMessage) data;
                updateRecord(callback.getObjectId(), message.getGameView(), message.getMessage(), message.getTargets());
            }
        } catch (Exception error) {
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
            error.printStackTrace();
        }
    }

    private void updateRecord(UUID gameId, GameView view, String promptText, Set<UUID> targets) {
        if (gameId == null || view == null) {
            return;
        }
        GameRecord record = games.computeIfAbsent(gameId.toString(), id -> new GameRecord(gameId, "human", "ai-1", "XMage AI"));
        record.latestView = view;
        record.latestCycle = view.getGameCycle();
        record.lastProgressAt = System.currentTimeMillis();
        if (promptText != null) {
            record.promptText = cleanText(promptText);
        }
        if (targets != null && !targets.isEmpty()) {
            JsonObject prompt = new JsonObject();
            prompt.addProperty("id", "xmage-choice-" + gameId);
            prompt.addProperty("playerId", record.humanExternalId);
            prompt.addProperty("message", promptText == null ? "Choose target" : cleanText(promptText));
            prompt.addProperty("minChoices", 1);
            prompt.addProperty("maxChoices", 1);
            JsonArray choices = new JsonArray();
            for (UUID target : targets) {
                CardView card = findVisibleCard(view, target);
                JsonObject choice = new JsonObject();
                choice.addProperty("id", target.toString());
                choice.addProperty("label", card == null ? target.toString() : card.getName());
                choice.addProperty("cardInstanceId", target.toString());
                choices.add(choice);
            }
            prompt.add("choices", choices);
            record.choicePrompt = prompt;
        } else if (promptText != null) {
            record.choicePrompt = null;
        }
        try {
            JsonObject snap = snapshot(gameId.toString());
            pushSnapshotToGateway(gameId.toString(), snap);
        } catch (Exception ignored) {
        }
    }

    private void pushSnapshotToGateway(String gameId, JsonObject snap) {
        new Thread(() -> {
            try {
                java.net.URL url = new java.net.URL(gatewayUrl + "/api/engine/games/" + java.net.URLEncoder.encode(gameId, "UTF-8") + "/updates");
                java.net.HttpURLConnection conn = (java.net.HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setDoOutput(true);
                byte[] postData = GSON.toJson(snap).getBytes(StandardCharsets.UTF_8);
                try (java.io.OutputStream os = conn.getOutputStream()) {
                    os.write(postData);
                }
                int responseCode = conn.getResponseCode();
                if (responseCode >= 300) {
                    System.err.println("Gateway update POST failed: " + responseCode);
                }
            } catch (Exception e) {
                System.err.println("Error pushing update to gateway: " + e.getMessage());
            }
        }).start();
    }

    private JsonObject readJson(HttpExchange exchange) throws IOException {
        try (InputStreamReader reader = new InputStreamReader(exchange.getRequestBody(), StandardCharsets.UTF_8)) {
            return JsonParser.parseReader(reader).getAsJsonObject();
        }
    }

    private void writeJson(HttpExchange exchange, int status, JsonElement body) throws IOException {
        byte[] data = GSON.toJson(body).getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        exchange.sendResponseHeaders(status, data.length);
        try (OutputStream stream = exchange.getResponseBody()) {
            stream.write(data);
        }
    }

    private static String env(String name, String fallback) {
        String value = System.getenv(name);
        return value == null || value.isEmpty() ? fallback : value;
    }

    private static JsonArray array(JsonObject object, String name) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && element.isJsonArray() ? element.getAsJsonArray() : new JsonArray();
    }

    private static JsonObject object(JsonObject object, String name) {
        return object(object, name, new JsonObject());
    }

    private static JsonObject object(JsonObject object, String name, JsonObject fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && element.isJsonObject() ? element.getAsJsonObject() : fallback;
    }

    private static String string(JsonObject object, String name, String fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsString() : fallback;
    }

    private static int integer(JsonObject object, String name, int fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsInt() : fallback;
    }

    private static String cleanText(String value) {
        return value == null ? "" : value.replaceAll("<[^>]+>", "").replace("&nbsp;", " ").trim();
    }

    private static boolean isUuid(String value) {
        try {
            UUID.fromString(value);
            return true;
        } catch (Exception ignored) {
            return false;
        }
    }

    private static final class GameRecord {
        final UUID gameId;
        final String humanExternalId;
        final String aiExternalId;
        final String aiName;
        volatile UUID humanXmagePlayerId;
        volatile GameView latestView;
        volatile int latestCycle = -1;
        volatile long lastProgressAt = System.currentTimeMillis();
        volatile String promptText;
        volatile JsonObject choicePrompt;

        GameRecord(UUID gameId, String humanExternalId, String aiExternalId, String aiName) {
            this.gameId = gameId;
            this.humanExternalId = humanExternalId;
            this.aiExternalId = aiExternalId;
            this.aiName = aiName;
        }
    }
}
