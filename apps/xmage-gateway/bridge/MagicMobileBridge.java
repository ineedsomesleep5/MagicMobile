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
import mage.choices.Choice;
import mage.constants.MatchBufferTime;
import mage.constants.MatchTimeLimit;
import mage.constants.ManaType;
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
import mage.view.AbilityPickerView;
import mage.view.CardsView;
import mage.view.CombatGroupView;
import mage.view.CommandObjectView;
import mage.view.ExileView;
import mage.view.GameClientMessage;
import mage.view.GameView;
import mage.view.LookedAtView;
import mage.view.ManaPoolView;
import mage.view.PermanentView;
import mage.view.PlayerView;
import mage.view.RevealedView;
import mage.view.SimpleCardView;
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
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.stream.Collectors;

public final class MagicMobileBridge implements MageClient {
    private static final Gson GSON = new GsonBuilder().disableHtmlEscaping().create();
    private static final MageVersion VERSION = new MageVersion(MagicMobileBridge.class);
    private static final String SOURCE = "xmage-java-bridge";

    private final Object connectionLock = new Object();
    private final Map<String, GameRecord> games = new ConcurrentHashMap<>();
    private final String xmageHost;
    private final int xmagePort;
    private final String gatewayUrl;
    private final ExecutorService updateExecutor = Executors.newSingleThreadExecutor();

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
        } catch (ActionNoLongerLegalException error) {
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
            JsonObject body = new JsonObject();
            body.addProperty("error", "action_no_longer_legal");
            body.addProperty("message", lastError);
            try {
                body.add("snapshot", snapshot(error.gameId));
            } catch (Exception ignored) {
            }
            writeJson(exchange, 409, body);
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
                    if (isOpeningSnapshotReady(existing)) {
                        return existing;
                    }
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
        GameRecord record = games.get(gameId);
        long startRevision = record == null ? -1 : record.bridgeRevision.get();

        if ("play_land".equals(type)) {
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("cast_spell".equals(type) || "activate_ability".equals(type)) {
            session.sendPlayerUUID(xmageGameId, playableCommandUuid(gameId, command));
        } else if ("make_mana".equals(type)) {
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("pass_priority".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("keep_hand".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, false);
        } else if ("mulligan".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("pass_until_response".equals(type) || "pass_until_next_turn".equals(type) || "advance_phase".equals(type)) {
            PlayerAction playerAction = "pass_until_next_turn".equals(type)
                    ? PlayerAction.PASS_PRIORITY_UNTIL_NEXT_TURN
                    : PlayerAction.PASS_PRIORITY_UNTIL_NEXT_MAIN_PHASE;
            session.sendPlayerAction(playerAction, xmageGameId, null);
        } else if ("concede".equals(type)) {
            session.sendPlayerAction(PlayerAction.CONCEDE, xmageGameId, null);
        } else if ("choose_target".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "targetIds"));
        } else if ("choose_card".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "cardInstanceIds"));
        } else if ("choose_mode".equals(type)) {
            sendFirstStringOrUuid(xmageGameId, array(command, "modeIds"));
        } else if ("play_mana".equals(type)) {
            session.sendPlayerManaType(xmageGameId, manaPlayerUuid(gameId), manaTypeFromSymbol(string(command, "manaType", "C")));
        } else if ("choose_ability".equals(type)) {
            String abilityId = string(command, "abilityId", string(command, "abilityIdChoice", ""));
            session.sendPlayerUUID(xmageGameId, abilityId.isEmpty() ? null : UUID.fromString(abilityId));
        } else if ("choose_pile".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, integer(command, "pile", 1) == 1);
        } else if ("choose_amount".equals(type) || "play_x_mana".equals(type)) {
            session.sendPlayerInteger(xmageGameId, integer(command, "amount", 0));
        } else if ("choose_multi_amount".equals(type)) {
            session.sendPlayerString(xmageGameId, joinNumbers(array(command, "amounts")));
        } else if ("order_triggers".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "orderedIds"));
        } else if ("search_select".equals(type)) {
            sendFirstUuid(xmageGameId, array(command, "cardInstanceIds"));
        } else if ("commander_replacement".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, bool(command, "useCommandZone", true));
        } else if ("pay_cost".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("declare_attackers".equals(type) || "declare_blockers".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, true);
        } else if ("resolve_choice".equals(type)) {
            JsonArray choices = array(command, "choiceIds");
            if (choices.size() > 0) {
                String choice = choices.get(0).getAsString();
                if (isUuid(choice)) {
                    session.sendPlayerUUID(xmageGameId, UUID.fromString(choice));
                } else if ("true".equalsIgnoreCase(choice) || "false".equalsIgnoreCase(choice)) {
                    session.sendPlayerBoolean(xmageGameId, Boolean.parseBoolean(choice));
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

        if (record != null) {
            record.lastProgressAt = System.currentTimeMillis();
        }
        return waitForUpdatedSnapshot(gameId, type, startRevision);
    }

    private UUID playableSourceUuid(String gameId, JsonObject command) {
        GameRecord record = games.get(gameId);
        if (record == null || record.latestView == null) {
            throw new ActionNoLongerLegalException(gameId, "XMage game snapshot is not available");
        }

        String sourceId = string(command, "sourceInstanceId", string(command, "cardInstanceId", ""));
        if (sourceId.isEmpty()) {
            throw new ActionNoLongerLegalException(gameId, "Missing source/card id for " + string(command, "type", "command"));
        }

        UUID sourceUuid = UUID.fromString(sourceId);
        PlayableObjectsList playable = record.latestView.getCanPlayObjects();
        PlayableObjectStats stats = playable == null ? null : playable.getObjects().get(sourceUuid);
        if (stats == null) {
            throw new ActionNoLongerLegalException(gameId, "Action is no longer legal for " + sourceId);
        }
        return sourceUuid;
    }

    private UUID playableCommandUuid(String gameId, JsonObject command) {
        GameRecord record = games.get(gameId);
        if (record == null || record.latestView == null) {
            throw new ActionNoLongerLegalException(gameId, "XMage game snapshot is not available");
        }

        String sourceId = string(command, "sourceInstanceId", string(command, "cardInstanceId", ""));
        String abilityId = string(command, "abilityId", "");
        if (sourceId.isEmpty()) {
            throw new ActionNoLongerLegalException(gameId, "Missing source/card id for " + string(command, "type", "command"));
        }

        UUID sourceUuid = UUID.fromString(sourceId);
        PlayableObjectsList playable = record.latestView.getCanPlayObjects();
        PlayableObjectStats stats = playable == null ? null : playable.getObjects().get(sourceUuid);
        if (stats == null) {
            throw new ActionNoLongerLegalException(gameId, "Action is no longer legal for " + sourceId);
        }

        List<UUID> abilityIds = stats.getPlayableAbilityIds();
        if (abilityIds.isEmpty()) {
            if (!abilityId.isEmpty() && !abilityId.equals(sourceId)) {
                throw new ActionNoLongerLegalException(gameId, "Ability is no longer legal for " + sourceId);
            }
            return sourceUuid;
        }

        if (abilityId.isEmpty()) {
            throw new ActionNoLongerLegalException(gameId, "Missing XMage ability id for " + sourceId);
        }

        UUID abilityUuid = UUID.fromString(abilityId);
        if (!abilityIds.contains(abilityUuid)) {
            throw new ActionNoLongerLegalException(gameId, "Ability is no longer legal for " + sourceId);
        }
        return abilityUuid;
    }

    private ManaType manaTypeForCommand(String gameId, JsonObject command) {
        GameRecord record = games.get(gameId);
        String sourceId = string(command, "sourceInstanceId", string(command, "cardInstanceId", ""));
        if (record == null || record.latestView == null || sourceId.isEmpty()) {
            return ManaType.COLORLESS;
        }

        CardView card = findVisibleCard(record.latestView, UUID.fromString(sourceId));
        if (card == null) {
            return ManaType.COLORLESS;
        }

        String rules = card.getRules() == null ? "" : String.join(" ", card.getRules());
        String text = (card.getName() + " " + card.getTypeText() + " " + rules).toLowerCase();
        if (text.contains("add {w}") || text.contains("plains")) return ManaType.WHITE;
        if (text.contains("add {u}") || text.contains("island")) return ManaType.BLUE;
        if (text.contains("add {b}") || text.contains("swamp")) return ManaType.BLACK;
        if (text.contains("add {r}") || text.contains("mountain")) return ManaType.RED;
        if (text.contains("add {g}") || text.contains("forest")) return ManaType.GREEN;
        if (text.contains("add {c}") || text.contains("add {c}{c}") || text.contains("colorless")) return ManaType.COLORLESS;
        return ManaType.COLORLESS;
    }

    private void sendFirstUuid(UUID gameId, JsonArray ids) {
        if (ids.size() == 0) {
            session.sendPlayerBoolean(gameId, true);
            return;
        }
        session.sendPlayerUUID(gameId, UUID.fromString(ids.get(0).getAsString()));
    }

    private void sendFirstStringOrUuid(UUID gameId, JsonArray ids) {
        if (ids.size() == 0) {
            session.sendPlayerBoolean(gameId, true);
            return;
        }
        String value = ids.get(0).getAsString();
        if (isUuid(value)) {
            session.sendPlayerUUID(gameId, UUID.fromString(value));
        } else {
            session.sendPlayerString(gameId, value);
        }
    }

    private JsonObject waitForUpdatedSnapshot(String gameId, String commandType, long startRevision) throws InterruptedException {
        GameRecord record;
        long waitMs = isDirectCommand(commandType) ? 1500 : 6000;
        long deadline = System.currentTimeMillis() + waitMs;
        while (System.currentTimeMillis() < deadline) {
            record = games.get(gameId);
            if (record != null && record.latestView != null && record.bridgeRevision.get() > startRevision) {
                return snapshot(gameId);
            }
            Thread.sleep(200);
        }
        return snapshot(gameId, "waiting_for_xmage");
    }

    private boolean isDirectCommand(String type) {
        return "keep_hand".equals(type)
                || "mulligan".equals(type)
                || "play_land".equals(type)
                || "cast_spell".equals(type)
                || "make_mana".equals(type)
                || "play_mana".equals(type)
                || "activate_ability".equals(type)
                || "choose_target".equals(type)
                || "choose_card".equals(type)
                || "choose_mode".equals(type)
                || "choose_ability".equals(type)
                || "choose_pile".equals(type)
                || "choose_amount".equals(type)
                || "choose_multi_amount".equals(type)
                || "play_x_mana".equals(type)
                || "order_triggers".equals(type)
                || "search_select".equals(type)
                || "commander_replacement".equals(type)
                || "pay_cost".equals(type)
                || "resolve_choice".equals(type);
    }

    private JsonObject snapshot(String gameId) {
        return snapshot(gameId, null);
    }

    private JsonObject snapshot(String gameId, String pendingStatus) {
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
        snapshot.addProperty("bridgeRevision", record.bridgeRevision.get());
        snapshot.addProperty("xmageCycle", record.latestCycle);
        if (pendingStatus != null) {
            snapshot.addProperty("pendingStatus", pendingStatus);
        }
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
        if (record.promptEnvelope != null) {
            snapshot.add("promptEnvelope", record.promptEnvelope);
            snapshot.add("promptEnvelopeV2", record.promptEnvelope);
        }
        snapshot.add("xmage", xmageMobileSnapshot(record, view, playerIds));
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
            String choiceActionType = promptActionType(record);
            for (JsonElement choiceElement : record.choicePrompt.getAsJsonArray("choices")) {
                if (!choiceElement.isJsonObject()) continue;
                JsonObject choice = choiceElement.getAsJsonObject();
                String choiceId = string(choice, "id", "");
                if (choiceId.isEmpty()) continue;
                actions.add(choiceAction(choiceId, choiceActionType, humanId, labelForChoice(record, playerIds, choiceId)));
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
            String type = actionType(card, handIds.contains(objectId));
            String sourceZone = handIds.contains(objectId) ? "hand" : card.isLand() ? "battlefield" : "battlefield";
            if (abilityIds.isEmpty()) {
                actions.add(action(
                        objectId.toString(),
                        type,
                        humanId,
                        labelFor(type, card.getName()),
                        objectId.toString(),
                        sourceZone,
                        null
                ));
            } else {
                for (UUID abilityUuid : abilityIds) {
                    String abilityId = abilityUuid.toString();
                    actions.add(action(
                            abilityId,
                            type,
                            humanId,
                            labelFor(type, card.getName()),
                            objectId.toString(),
                            sourceZone,
                            abilityId
                    ));
                }
            }
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
            action.addProperty("abilityId", abilityId);
            JsonObject template = new JsonObject();
            template.addProperty("abilityId", abilityId);
            action.add("commandTemplate", template);
        }
        return action;
    }

    private JsonObject xmageMobileSnapshot(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonObject out = new JsonObject();
        out.addProperty("schemaVersion", 1);
        out.addProperty("gameId", record.gameId.toString());
        out.addProperty("bridgeRevision", record.bridgeRevision.get());
        out.addProperty("xmageCycle", record.latestCycle);
        JsonArray coverage = new JsonArray();
        if (record.promptEnvelope != null && record.promptEnvelope.has("method")) {
            coverage.add(string(record.promptEnvelope, "method", ""));
        }
        out.add("callbackCoverage", coverage);
        out.add("stack", stackObjects(view.getStack()));
        out.add("combat", combatGroups(view, playerIds));
        out.add("players", xmagePlayers(record, view, playerIds));
        out.add("exileZones", exileZones(view.getExile()));
        out.add("revealed", revealedZones(view.getRevealed()));
        out.add("lookedAt", lookedAtZones(view.getLookedAt()));
        out.add("companion", revealedZones(view.getCompanion()));
        out.add("playableObjects", playableObjects(view));
        out.add("panels", xmagePanels(view));
        return out;
    }

    private JsonArray xmagePlayers(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonArray out = new JsonArray();
        for (PlayerView player : view.getPlayers()) {
            String externalId = playerIds.get(player.getPlayerId());
            JsonObject item = new JsonObject();
            item.addProperty("playerId", externalId);
            item.addProperty("xmagePlayerId", player.getPlayerId().toString());
            item.addProperty("name", player.getName());
            item.addProperty("active", player.isActive());
            item.addProperty("hasPriority", player.hasPriority());
            item.addProperty("timerActive", player.isTimerActive());
            item.add("skipState", skipState(player));
            item.add("manaPool", manaPool(player.getManaPool()));
            item.add("command", commandCards(player.getCommandObjectList()));
            JsonObject zones = new JsonObject();
            zones.add("battlefield", battlefieldCards(player.getBattlefield().values()));
            zones.add("graveyard", zoneCards(player.getGraveyard().values(), false));
            zones.add("exile", zoneCards(player.getExile().values(), false));
            zones.add("sideboard", zoneCards(player.getSideboard().values(), false));
            item.add("zones", zones);
            out.add(item);
        }
        return out;
    }

    private JsonObject skipState(PlayerView player) {
        JsonObject out = new JsonObject();
        out.addProperty("passedTurn", player.isPassedTurn());
        out.addProperty("passedUntilEndOfTurn", player.isPassedUntilEndOfTurn());
        out.addProperty("passedUntilNextMain", player.isPassedUntilNextMain());
        out.addProperty("passedUntilStackResolved", player.isPassedUntilStackResolved());
        out.addProperty("passedAllTurns", player.isPassedAllTurns());
        out.addProperty("passedUntilEndStepBeforeMyTurn", player.isPassedUntilEndStepBeforeMyTurn());
        return out;
    }

    private JsonArray stackObjects(CardsView stack) {
        JsonArray out = new JsonArray();
        for (CardView card : stack.values()) {
            JsonObject item = new JsonObject();
            item.addProperty("id", card.getId().toString());
            item.addProperty("name", card.getName());
            String rulesText = rulesText(card);
            if (!rulesText.isEmpty()) {
                item.addProperty("rulesText", rulesText);
            }
            item.addProperty("paid", card.isPaid());
            item.add("sourceCard", zoneCard(card));
            out.add(item);
        }
        return out;
    }

    private JsonArray combatGroups(GameView view, Map<UUID, String> playerIds) {
        JsonArray out = new JsonArray();
        for (CombatGroupView group : view.getCombat()) {
            JsonObject item = new JsonObject();
            String defenderId = playerIds.getOrDefault(group.getDefenderId(), group.getDefenderId().toString());
            item.addProperty("defenderId", defenderId);
            item.addProperty("defenderName", cleanText(group.getDefenderName()));
            item.addProperty("blocked", group.isBlocked());
            item.add("attackers", zoneCards(group.getAttackers().values(), false));
            item.add("blockers", zoneCards(group.getBlockers().values(), false));
            out.add(item);
        }
        return out;
    }

    private JsonArray exileZones(List<ExileView> zones) {
        JsonArray out = new JsonArray();
        for (ExileView zone : zones) {
            JsonObject item = new JsonObject();
            item.addProperty("id", zone.getId().toString());
            item.addProperty("name", cleanText(zone.getName()));
            item.add("cards", zoneCards(zone.values(), false));
            out.add(item);
        }
        return out;
    }

    private JsonArray revealedZones(List<RevealedView> zones) {
        JsonArray out = new JsonArray();
        for (RevealedView zone : zones) {
            JsonObject item = new JsonObject();
            item.addProperty("id", slug(zone.getName()));
            item.addProperty("name", cleanText(zone.getName()));
            item.add("cards", zoneCards(zone.getCards().values(), false));
            out.add(item);
        }
        return out;
    }

    private JsonArray lookedAtZones(List<LookedAtView> zones) {
        JsonArray out = new JsonArray();
        for (LookedAtView zone : zones) {
            JsonObject item = new JsonObject();
            item.addProperty("id", slug(zone.getName()));
            item.addProperty("name", cleanText(zone.getName()));
            JsonArray cards = new JsonArray();
            for (SimpleCardView card : zone.getCards().values()) {
                cards.add(simpleZoneCard(card));
            }
            item.add("cards", cards);
            out.add(item);
        }
        return out;
    }

    private JsonArray playableObjects(GameView view) {
        JsonArray out = new JsonArray();
        PlayableObjectsList playable = view.getCanPlayObjects();
        if (playable == null || playable.isEmpty()) {
            return out;
        }
        Set<UUID> handIds = new HashSet<>(view.getMyHand().keySet());
        for (Map.Entry<UUID, PlayableObjectStats> entry : playable.getObjects().entrySet()) {
            UUID sourceId = entry.getKey();
            CardView card = findVisibleCard(view, sourceId);
            if (card == null) continue;
            String category = playableCategory(card, handIds.contains(sourceId));
            JsonObject item = new JsonObject();
            item.addProperty("sourceInstanceId", sourceId.toString());
            item.addProperty("sourceZone", handIds.contains(sourceId) ? "hand" : "battlefield");
            item.addProperty("cardName", card.getName());
            JsonArray categories = new JsonArray();
            categories.add(category);
            item.add("categories", categories);
            JsonArray abilities = new JsonArray();
            List<UUID> ids = entry.getValue().getPlayableAbilityIds();
            List<String> labels = entry.getValue().getPlayableAbilityNames();
            for (int i = 0; i < ids.size(); i++) {
                JsonObject ability = new JsonObject();
                ability.addProperty("id", ids.get(i).toString());
                ability.addProperty("label", cleanText(i < labels.size() ? labels.get(i) : labelFor(actionType(card, handIds.contains(sourceId)), card.getName())));
                ability.addProperty("category", category);
                abilities.add(ability);
            }
            item.add("abilities", abilities);
            out.add(item);
        }
        return out;
    }

    private String playableCategory(CardView card, boolean inHand) {
        if (inHand && card.isLand()) return "play";
        if (inHand) return "cast";
        if (card.isLand()) return "mana";
        return "ability";
    }

    private JsonObject xmagePanels(GameView view) {
        JsonObject out = new JsonObject();
        out.addProperty("stack", !view.getStack().isEmpty());
        boolean hasCommand = false;
        boolean hasGraveyard = false;
        boolean hasExile = !view.getExile().isEmpty();
        for (PlayerView player : view.getPlayers()) {
            hasCommand = hasCommand || !player.getCommandObjectList().isEmpty();
            hasGraveyard = hasGraveyard || !player.getGraveyard().isEmpty();
            hasExile = hasExile || !player.getExile().isEmpty();
        }
        out.addProperty("command", hasCommand);
        out.addProperty("graveyard", hasGraveyard);
        out.addProperty("exile", hasExile);
        out.addProperty("revealed", !view.getRevealed().isEmpty());
        out.addProperty("lookedAt", !view.getLookedAt().isEmpty());
        out.addProperty("search", false);
        return out;
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
        if ("make_mana".equals(type) || "play_mana".equals(type)) return "Mana";
        if ("choose_ability".equals(type)) return "Ability";
        if ("choose_pile".equals(type)) return "Pile";
        if ("choose_amount".equals(type) || "choose_multi_amount".equals(type) || "play_x_mana".equals(type)) return label;
        if ("search_select".equals(type)) return "Choose";
        if ("commander_replacement".equals(type)) return "Command";
        return label;
    }

    private boolean requiresTarget(String type) {
        return "choose_target".equals(type) || "declare_attackers".equals(type) || "declare_blockers".equals(type);
    }

    private JsonObject choiceAction(String choiceId, String type, String playerId, String label) {
        JsonObject action = action("xmage-choice-" + choiceId, type, playerId, label, null, null, null);
        JsonArray targetIds = new JsonArray();
        targetIds.add(choiceId);
        action.add("targetIds", targetIds);
        action.add("validTargetIds", targetIds.deepCopy());
        action.addProperty("zoneContext", "prompt");
        if (type != null) {
            action.addProperty("responseKind", type);
        }
        return action;
    }

    private String promptActionType(GameRecord record) {
        if (record.promptEnvelope == null) {
            return "resolve_choice";
        }
        String responseKind = string(record.promptEnvelope, "responseKind", "resolve_choice");
        if ("target".equals(responseKind)) return "choose_target";
        if ("card".equals(responseKind)) return "choose_card";
        if ("ability".equals(responseKind)) return "choose_ability";
        if ("pile".equals(responseKind)) return "choose_pile";
        if ("amount".equals(responseKind)) return "choose_amount";
        if ("multi_amount".equals(responseKind)) return "choose_multi_amount";
        if ("mana".equals(responseKind)) return "play_mana";
        if ("x_mana".equals(responseKind)) return "play_x_mana";
        if ("search".equals(responseKind)) return "search_select";
        if ("commander_replacement".equals(responseKind)) return "commander_replacement";
        return responseKind;
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

    private ManaType manaTypeFromSymbol(String symbol) {
        String normalized = symbol == null ? "" : symbol.replace("{", "").replace("}", "").trim().toUpperCase();
        if ("W".equals(normalized) || "WHITE".equals(normalized)) return ManaType.WHITE;
        if ("U".equals(normalized) || "BLUE".equals(normalized)) return ManaType.BLUE;
        if ("B".equals(normalized) || "BLACK".equals(normalized)) return ManaType.BLACK;
        if ("R".equals(normalized) || "RED".equals(normalized)) return ManaType.RED;
        if ("G".equals(normalized) || "GREEN".equals(normalized)) return ManaType.GREEN;
        return ManaType.COLORLESS;
    }

    private UUID manaPlayerUuid(String gameId) {
        GameRecord record = games.get(gameId);
        if (record == null || record.latestView == null) {
            throw new ActionNoLongerLegalException(gameId, "XMage game snapshot is not available");
        }
        if (record.humanXmagePlayerId != null) {
            return record.humanXmagePlayerId;
        }
        Map<UUID, String> playerIds = externalPlayerIds(record, record.latestView);
        for (PlayerView player : record.latestView.getPlayers()) {
            if (record.humanExternalId.equals(playerIds.get(player.getPlayerId()))) {
                record.humanXmagePlayerId = player.getPlayerId();
                return player.getPlayerId();
            }
        }
        throw new ActionNoLongerLegalException(gameId, "XMage human player id is not available for mana selection");
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
            out.add("manaPool", manaPool(player.getManaPool()));

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

    private JsonObject manaPool(ManaPoolView pool) {
        JsonObject out = new JsonObject();
        out.addProperty("W", pool == null ? 0 : pool.getWhite());
        out.addProperty("U", pool == null ? 0 : pool.getBlue());
        out.addProperty("B", pool == null ? 0 : pool.getBlack());
        out.addProperty("R", pool == null ? 0 : pool.getRed());
        out.addProperty("G", pool == null ? 0 : pool.getGreen());
        out.addProperty("C", pool == null ? 0 : pool.getColorless());
        return out;
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
        identity.addProperty("typeLine", cleanText(card.getTypeText()));
        if (card.getRules() != null && !card.getRules().isEmpty()) {
            identity.addProperty(
                    "oracleText",
                    card.getRules().stream().map(MagicMobileBridge::cleanText).filter(rule -> !rule.isEmpty()).collect(Collectors.joining("\n"))
            );
        }
        identity.addProperty("isBasicLand", card.isLand() && card.getSuperTypes().toString().contains("Basic"));
        out.add("card", identity);
        Integer power = parseStat(card.getPower());
        Integer toughness = parseStat(card.getToughness());
        if (power != null) out.addProperty("power", power);
        if (toughness != null) out.addProperty("toughness", toughness);
        return out;
    }

    private JsonObject simpleZoneCard(SimpleCardView card) {
        JsonObject out = new JsonObject();
        out.addProperty("instanceId", card.getId().toString());
        JsonObject identity = new JsonObject();
        identity.addProperty("id", card.getId().toString());
        identity.addProperty("name", "Card " + card.getExpansionSetCode() + " " + card.getCardNumber());
        identity.addProperty("manaValue", 0);
        identity.add("colorIdentity", new JsonArray());
        identity.addProperty("typeLine", "Card");
        identity.addProperty("oracleText", "");
        identity.addProperty("isBasicLand", false);
        out.add("card", identity);
        return out;
    }

    private String rulesText(CardView card) {
        if (card == null || card.getRules() == null || card.getRules().isEmpty()) {
            return "";
        }
        return card.getRules()
                .stream()
                .map(MagicMobileBridge::cleanText)
                .filter(rule -> !rule.isEmpty())
                .collect(Collectors.joining("\n"));
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
                updateRecord(callback.getObjectId(), (GameView) data, null, null, null);
            }
            if (data instanceof GameClientMessage) {
                GameClientMessage message = (GameClientMessage) data;
                updateRecord(
                        callback.getObjectId(),
                        message.getGameView(),
                        message.getMessage(),
                        message.getTargets(),
                        promptEnvelope(callback, message)
                );
            }
            if (data instanceof AbilityPickerView) {
                AbilityPickerView picker = (AbilityPickerView) data;
                updateRecord(
                        callback.getObjectId(),
                        picker.getGameView(),
                        picker.getMessage(),
                        null,
                        promptEnvelope(callback, picker)
                );
            }
        } catch (Exception error) {
            lastError = error.getMessage() == null ? error.toString() : error.getMessage();
            error.printStackTrace();
        }
    }

    private JsonObject promptEnvelope(ClientCallback callback, GameClientMessage message) {
        ClientCallbackMethod method = callback.getMethod();
        if (!isPromptMethod(method)) {
            return null;
        }
        JsonObject prompt = basePrompt(callback, responseKind(method), message.getMessage());
        prompt.addProperty("required", message.isFlag());
        prompt.addProperty("minChoices", message.getMin());
        prompt.addProperty("maxChoices", message.getMax());

        JsonArray choices = new JsonArray();
        if (method == ClientCallbackMethod.GAME_CHOOSE_PILE) {
            choices.add(promptChoice("1", "Pile 1", null));
            choices.add(promptChoice("2", "Pile 2", null));
            JsonArray piles = new JsonArray();
            addPile(piles, "1", "Pile 1", message.getCardsView1());
            addPile(piles, "2", "Pile 2", message.getCardsView2());
            prompt.add("piles", piles);
        } else if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && message.getChoice() != null) {
            addChoiceOptions(choices, message.getChoice());
            prompt.add("modes", choices.deepCopy());
        } else if (method == ClientCallbackMethod.GAME_PLAY_MANA) {
            for (String symbol : new String[]{"W", "U", "B", "R", "G", "C"}) {
                choices.add(promptChoice(symbol, "Pay {" + symbol + "}", null));
            }
        } else if (method == ClientCallbackMethod.GAME_GET_AMOUNT || method == ClientCallbackMethod.GAME_PLAY_XMANA) {
            int min = message.getMin();
            int max = message.getMax();
            int cappedMax = Math.min(max, min + 20);
            JsonArray amounts = new JsonArray();
            for (int value = min; value <= cappedMax; value++) {
                choices.add(promptChoice(Integer.toString(value), Integer.toString(value), null));
                amounts.add(value);
            }
            prompt.add("amounts", amounts);
        }

        if (message.getTargets() != null && !message.getTargets().isEmpty()) {
            JsonArray targetIds = new JsonArray();
            JsonArray targets = new JsonArray();
            for (UUID target : message.getTargets()) {
                targetIds.add(target.toString());
                CardView card = message.getCardsView1() == null ? null : message.getCardsView1().get(target);
                if (card == null && message.getGameView() != null) {
                    card = findVisibleCard(message.getGameView(), target);
                }
                JsonObject choice = promptChoice(target.toString(), card == null ? target.toString() : card.getName(), target.toString());
                choices.add(choice);
                targets.add(choice.deepCopy());
            }
            prompt.add("targetIds", targetIds);
            prompt.add("targets", targets);
        } else if (message.getCardsView1() != null && !message.getCardsView1().isEmpty()) {
            addCardChoices(choices, message.getCardsView1());
            prompt.add("cards", zoneCards(message.getCardsView1().values(), false));
        }

        if (choices.size() > 0) {
            prompt.add("choices", choices);
        }
        return prompt;
    }

    private JsonObject promptEnvelope(ClientCallback callback, AbilityPickerView picker) {
        JsonObject prompt = basePrompt(callback, "ability", picker.getMessage());
        prompt.addProperty("required", true);
        prompt.addProperty("minChoices", 1);
        prompt.addProperty("maxChoices", 1);
        JsonArray choices = new JsonArray();
        JsonArray abilities = new JsonArray();
        for (Map.Entry<UUID, String> choice : picker.getChoices().entrySet()) {
            JsonObject option = promptChoice(choice.getKey().toString(), cleanText(choice.getValue()), null);
            choices.add(option);
            JsonObject ability = new JsonObject();
            ability.addProperty("id", choice.getKey().toString());
            ability.addProperty("label", cleanText(choice.getValue()));
            abilities.add(ability);
        }
        prompt.add("choices", choices);
        prompt.add("abilities", abilities);
        return prompt;
    }

    private JsonObject basePrompt(ClientCallback callback, String responseKind, String message) {
        JsonObject prompt = new JsonObject();
        prompt.addProperty("id", "xmage-prompt-" + callback.getMessageId());
        prompt.addProperty("method", callback.getMethod().name());
        prompt.addProperty("messageId", callback.getMessageId());
        prompt.addProperty("playerId", "human");
        prompt.addProperty("responseKind", responseKind);
        prompt.addProperty("message", cleanText(message == null ? callback.getMethod().name() : message));
        JsonObject responseCommand = new JsonObject();
        responseCommand.addProperty("type", commandTypeForResponseKind(responseKind));
        responseCommand.addProperty("promptId", "xmage-prompt-" + callback.getMessageId());
        prompt.add("responseCommand", responseCommand);
        return prompt;
    }

    private String commandTypeForResponseKind(String responseKind) {
        if ("target".equals(responseKind)) return "choose_target";
        if ("card".equals(responseKind)) return "choose_card";
        if ("ability".equals(responseKind)) return "choose_ability";
        if ("pile".equals(responseKind)) return "choose_pile";
        if ("amount".equals(responseKind)) return "choose_amount";
        if ("multi_amount".equals(responseKind)) return "choose_multi_amount";
        if ("mana".equals(responseKind)) return "play_mana";
        if ("x_mana".equals(responseKind)) return "play_x_mana";
        if ("game_over".equals(responseKind)) return "game_over";
        return "resolve_choice";
    }

    private boolean isPromptMethod(ClientCallbackMethod method) {
        return method == ClientCallbackMethod.GAME_ASK
                || method == ClientCallbackMethod.GAME_TARGET
                || method == ClientCallbackMethod.GAME_SELECT
                || method == ClientCallbackMethod.GAME_CHOOSE_ABILITY
                || method == ClientCallbackMethod.GAME_CHOOSE_PILE
                || method == ClientCallbackMethod.GAME_CHOOSE_CHOICE
                || method == ClientCallbackMethod.GAME_PLAY_MANA
                || method == ClientCallbackMethod.GAME_PLAY_XMANA
                || method == ClientCallbackMethod.GAME_GET_AMOUNT
                || method == ClientCallbackMethod.GAME_GET_MULTI_AMOUNT
                || method == ClientCallbackMethod.GAME_OVER;
    }

    private String responseKind(ClientCallbackMethod method) {
        if (method == ClientCallbackMethod.GAME_TARGET) return "target";
        if (method == ClientCallbackMethod.GAME_SELECT) return "card";
        if (method == ClientCallbackMethod.GAME_CHOOSE_ABILITY) return "ability";
        if (method == ClientCallbackMethod.GAME_CHOOSE_PILE) return "pile";
        if (method == ClientCallbackMethod.GAME_PLAY_MANA) return "mana";
        if (method == ClientCallbackMethod.GAME_PLAY_XMANA) return "x_mana";
        if (method == ClientCallbackMethod.GAME_GET_AMOUNT) return "amount";
        if (method == ClientCallbackMethod.GAME_GET_MULTI_AMOUNT) return "multi_amount";
        if (method == ClientCallbackMethod.GAME_OVER) return "game_over";
        return "resolve_choice";
    }

    private void addCardChoices(JsonArray choices, CardsView cards) {
        for (CardView card : cards.values()) {
            choices.add(promptChoice(card.getId().toString(), card.getName(), card.getId().toString()));
        }
    }

    private void addPile(JsonArray piles, String id, String label, CardsView cards) {
        JsonObject pile = new JsonObject();
        pile.addProperty("id", id);
        pile.addProperty("label", label);
        pile.add("cards", cards == null ? new JsonArray() : zoneCards(cards.values(), false));
        piles.add(pile);
    }

    private void addChoiceOptions(JsonArray choices, Choice choice) {
        if (choice.isKeyChoice()) {
            for (Map.Entry<String, String> entry : choice.getKeyChoices().entrySet()) {
                choices.add(promptChoice(entry.getKey(), cleanText(entry.getValue()), null));
            }
            return;
        }
        for (String value : choice.getChoices()) {
            choices.add(promptChoice(value, cleanText(value), null));
        }
        if (!choice.isRequired()) {
            choices.add(promptChoice("false", "Cancel", null));
        }
    }

    private JsonObject promptChoice(String id, String label, String cardInstanceId) {
        JsonObject choice = new JsonObject();
        choice.addProperty("id", id);
        choice.addProperty("label", label == null || label.isEmpty() ? id : label);
        if (cardInstanceId != null) {
            choice.addProperty("cardInstanceId", cardInstanceId);
        }
        return choice;
    }

    private JsonObject choicePromptFromEnvelope(JsonObject promptEnvelope) {
        if (promptEnvelope == null || !promptEnvelope.has("choices")) {
            return null;
        }
        JsonObject prompt = new JsonObject();
        prompt.addProperty("id", string(promptEnvelope, "id", "xmage-prompt"));
        prompt.addProperty("playerId", string(promptEnvelope, "playerId", "human"));
        prompt.addProperty("message", string(promptEnvelope, "message", "Choose"));
        prompt.addProperty("minChoices", integer(promptEnvelope, "minChoices", 1));
        prompt.addProperty("maxChoices", integer(promptEnvelope, "maxChoices", 1));
        prompt.add("choices", promptEnvelope.getAsJsonArray("choices").deepCopy());
        return prompt;
    }

    private void updateRecord(UUID gameId, GameView view, String promptText, Set<UUID> targets, JsonObject promptEnvelope) {
        if (gameId == null || view == null) {
            return;
        }
        GameRecord record = games.computeIfAbsent(gameId.toString(), id -> new GameRecord(gameId, "human", "ai-1", "XMage AI"));
        record.latestView = view;
        record.latestCycle = view.getGameCycle();
        record.bridgeRevision.incrementAndGet();
        record.lastProgressAt = System.currentTimeMillis();
        record.promptText = promptText == null ? null : cleanText(promptText);
        record.promptEnvelope = promptEnvelope;
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
        } else {
            record.choicePrompt = choicePromptFromEnvelope(promptEnvelope);
        }
        try {
            JsonObject snap = snapshot(gameId.toString());
            pushSnapshotToGateway(gameId.toString(), snap);
        } catch (Exception ignored) {
        }
    }

    private void pushSnapshotToGateway(String gameId, JsonObject snap) {
        updateExecutor.submit(() -> {
            try {
                java.net.URL url = new java.net.URL(gatewayUrl + "/api/engine/games/" + java.net.URLEncoder.encode(gameId, "UTF-8") + "/updates");
                java.net.HttpURLConnection conn = (java.net.HttpURLConnection) url.openConnection();
                conn.setRequestMethod("POST");
                conn.setRequestProperty("Content-Type", "application/json");
                conn.setRequestProperty("X-Request-Id", UUID.randomUUID().toString());
                conn.setConnectTimeout(3000);
                conn.setReadTimeout(5000);
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
        });
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

    private static boolean bool(JsonObject object, String name, boolean fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsBoolean() : fallback;
    }

    private static String joinNumbers(JsonArray values) {
        StringBuilder out = new StringBuilder();
        for (JsonElement value : values) {
            if (out.length() > 0) {
                out.append(',');
            }
            out.append(value.getAsInt());
        }
        return out.toString();
    }

    private static String cleanText(String value) {
        return value == null ? "" : value.replaceAll("<[^>]+>", "").replace("&nbsp;", " ").trim();
    }

    private static String slug(String value) {
        String normalized = value == null ? "zone" : value.toLowerCase().replaceAll("[^a-z0-9]+", "-");
        normalized = normalized.replaceAll("(^-+|-+$)", "");
        return normalized.isEmpty() ? "zone" : normalized;
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
        final AtomicLong bridgeRevision = new AtomicLong();
        volatile UUID humanXmagePlayerId;
        volatile GameView latestView;
        volatile int latestCycle = -1;
        volatile long lastProgressAt = System.currentTimeMillis();
        volatile String promptText;
        volatile JsonObject choicePrompt;
        volatile JsonObject promptEnvelope;

        GameRecord(UUID gameId, String humanExternalId, String aiExternalId, String aiName) {
            this.gameId = gameId;
            this.humanExternalId = humanExternalId;
            this.aiExternalId = aiExternalId;
            this.aiName = aiName;
        }
    }

    private static final class ActionNoLongerLegalException extends RuntimeException {
        final String gameId;

        ActionNoLongerLegalException(String gameId, String message) {
            super(message);
            this.gameId = gameId;
        }
    }
}
