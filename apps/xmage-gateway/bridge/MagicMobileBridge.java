import com.google.gson.Gson;
import com.google.gson.GsonBuilder;
import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import mage.abilities.icon.CardIcon;
import mage.cards.Card;
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
import mage.constants.Zone;
import mage.game.Game;
import mage.game.GameState;
import mage.game.PutToBattlefieldInfo;
import mage.game.permanent.Permanent;
import mage.game.match.MatchOptions;
import mage.game.turn.Phase;
import mage.game.turn.Step;
import mage.interfaces.MageClient;
import mage.interfaces.callback.ClientCallback;
import mage.interfaces.callback.ClientCallbackMethod;
import mage.players.PlayableObjectStats;
import mage.players.PlayableObjectsList;
import mage.players.Player;
import mage.players.PlayerType;
import mage.remote.Connection;
import mage.remote.Session;
import mage.remote.SessionImpl;
import mage.server.game.GameController;
import mage.server.managers.ManagerFactory;
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
import mage.util.MultiAmountMessage;

import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.lang.management.ManagementFactory;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.Collections;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicLong;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
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
    private final ScheduledExecutorService keepAliveExecutor = Executors.newSingleThreadScheduledExecutor();

    private Session session;
    private volatile String lastError = "";
    private volatile UUID lastStartedGameId;
    private volatile UUID lastStartedHumanPlayerId;
    private volatile boolean cardRepositoryReady;
    private volatile boolean bridgeConnected;
    private volatile FixtureManagerProvider fixtureManagerProvider;

    MagicMobileBridge(String xmageHost, int xmagePort, String gatewayUrl) {
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
        bridge.startHttpServer(bridgePort);
    }

    void startHttpServer(int bridgePort) throws IOException {
        HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", bridgePort), 0);
        server.createContext("/", this::handleRequest);
        server.setExecutor(null);
        server.start();
        keepAliveExecutor.scheduleAtFixedRate(this::pingIfConnected, 15, 15, TimeUnit.SECONDS);
        System.out.println("MagicMobile XMage Java bridge listening on " + bridgePort);
    }

    void setFixtureManagerProvider(FixtureManagerProvider provider) {
        this.fixtureManagerProvider = provider;
    }

    private void handleRequest(HttpExchange exchange) throws IOException {
        try {
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();
            String query = exchange.getRequestURI().getQuery();
            String queryPlayerId = null;
            if (query != null) {
                for (String param : query.split("&")) {
                    String[] pair = param.split("=");
                    if (pair.length > 0 && "playerId".equals(pair[0])) {
                        queryPlayerId = pair.length > 1 ? pair[1] : "";
                    }
                }
            }

            if ("GET".equals(method) && "/health".equals(path)) {
                writeJson(exchange, 200, health());
                return;
            }

            if ("POST".equals(method) && "/games/commander".equals(path)) {
                writeJson(exchange, 201, createCommanderGame(readJson(exchange)));
                return;
            }

            if ("POST".equals(method) && "/dev/xmage-fixtures/commander".equals(path)) {
                if (!fixturesEnabled()) {
                    JsonObject body = new JsonObject();
                    body.addProperty("error", "xmage_fixtures_disabled");
                    writeJson(exchange, 404, body);
                    return;
                }
                JsonObject fixture = readJson(exchange);
                JsonObject result = createCommanderFixtureGame(fixture);
                JsonObject harness = object(result, "fixtureHarness", null);
                boolean directStateSeeded = bool(result, "directStateSeeded", false)
                        || (harness != null && bool(harness, "directStateSeeded", false));
                writeJson(exchange, directStateSeeded ? 201 : 501, result);
                return;
            }

            String[] parts = path.split("/");
            if (parts.length >= 3 && "games".equals(parts[1])) {
                String gameId = parts[2];
                if ("GET".equals(method) && parts.length == 3) {
                    JsonObject snap = snapshot(gameId);
                    if (queryPlayerId != null && !queryPlayerId.isEmpty()) {
                        snap = obfuscateSnapshotForPlayer(snap, queryPlayerId);
                    }
                    writeJson(exchange, 200, snap);
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
                if ("DELETE".equals(method) && parts.length == 3) {
                    JsonObject request = readOptionalJson(exchange);
                    writeJson(exchange, 200, cleanupGame(gameId, string(request, "reason", "client-request")));
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

        String humanDisplayName = sanitizedDisplayName(string(config, "humanDisplayName", "TabletopPolish"));
        boolean humanJoined = session.joinTable(roomId, table.getTableId(), humanDisplayName, PlayerType.HUMAN, 1, deckFromConfig(object(config, "humanDeck")), "");
        boolean aiJoined = session.joinTable(roomId, table.getTableId(), aiName, aiType, aiSkill, deckFromConfig(object(aiConfig, "deck", object(config, "humanDeck"))), "");
        if (!humanJoined || !aiJoined) {
            throw new IllegalStateException("XMage rejected one of the Commander decks");
        }
        if (fixtureManagerProvider != null) {
            if (!startMatchWithHumanChooser(table.getTableId())) {
                throw new IllegalStateException("XMage embedded server did not start the Commander match with the human as starting-player chooser");
            }
        } else if (!session.startMatch(roomId, table.getTableId())) {
            throw new IllegalStateException("XMage did not start the Commander match");
        }

        String humanCommanderName = string(object(object(config, "humanDeck"), "commander"), "cardName", "");
        GameRecord record = waitForStartedGame(humanExternalId, aiExternalId, humanDisplayName, aiName, humanCommanderName);
        games.put(record.gameId.toString(), record);
        return snapshot(record.gameId.toString());
    }

    private boolean startMatchWithHumanChooser(UUID tableId) throws Exception {
        ManagerFactory managerFactory = fixtureManagerProvider.get();
        Object tableManager = managerFactory.tableManager();
        Object controller = tableController(tableManager, tableId);
        UUID humanPlayerId = humanPlayerIdFromTableController(controller);
        if (controller == null || humanPlayerId == null) {
            return false;
        }

        Object match = fieldValue(controller, "match");
        Method startMatch = match.getClass().getMethod("startMatch");
        startMatch.invoke(match);

        Method startGame = controller.getClass().getDeclaredMethod("startGame", UUID.class);
        startGame.setAccessible(true);
        startGame.invoke(controller, humanPlayerId);
        return true;
    }

    private Object tableController(Object tableManager, UUID tableId) throws Exception {
        if (tableManager == null || tableId == null) {
            return null;
        }
        Object controllers = fieldValue(tableManager, "controllers");
        if (!(controllers instanceof Map<?, ?>)) {
            return null;
        }
        return ((Map<?, ?>) controllers).get(tableId);
    }

    private UUID humanPlayerIdFromTableController(Object controller) throws Exception {
        if (controller == null) {
            return null;
        }
        Object userPlayerMap = fieldValue(controller, "userPlayerMap");
        if (!(userPlayerMap instanceof Map<?, ?>)) {
            return null;
        }
        for (Object value : ((Map<?, ?>) userPlayerMap).values()) {
            if (value instanceof UUID) {
                return (UUID) value;
            }
        }
        return null;
    }

    private Object fieldValue(Object instance, String name) throws Exception {
        Field field = findField(instance.getClass(), name);
        field.setAccessible(true);
        return field.get(instance);
    }

    private Field findField(Class<?> type, String name) throws NoSuchFieldException {
        Class<?> current = type;
        while (current != null) {
            try {
                return current.getDeclaredField(name);
            } catch (NoSuchFieldException ignored) {
                current = current.getSuperclass();
            }
        }
        throw new NoSuchFieldException(name);
    }

    private GameRecord waitForStartedGame(String humanExternalId, String aiExternalId, String humanName, String aiName, String humanCommanderName) throws InterruptedException {
        long deadline = System.currentTimeMillis() + TimeUnit.SECONDS.toMillis(35);
        GameRecord lastRecord = null;
        while (System.currentTimeMillis() < deadline) {
            UUID gameId = lastStartedGameId;
            if (gameId != null) {
                GameRecord existing = games.get(gameId.toString());
                existing = startupRecord(gameId, existing, humanExternalId, aiExternalId, humanName, aiName);
                if (existing.latestView != null) {
                    lastRecord = existing;
                    if (isOpeningSnapshotReady(existing, humanCommanderName)) {
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

    private GameRecord startupRecord(UUID gameId, GameRecord existing, String humanExternalId, String aiExternalId, String humanName, String aiName) {
        if (existing == null) {
            GameRecord created = new GameRecord(gameId, humanExternalId, aiExternalId, humanName, aiName);
            created.humanXmagePlayerId = lastStartedHumanPlayerId;
            games.put(gameId.toString(), created);
            return created;
        }
        boolean staleNames = !humanExternalId.equals(existing.humanExternalId)
                || !aiExternalId.equals(existing.aiExternalId)
                || !humanName.equals(existing.humanName)
                || !aiName.equals(existing.aiName);
        if (!staleNames) {
            if (existing.humanXmagePlayerId == null) {
                existing.humanXmagePlayerId = lastStartedHumanPlayerId;
            }
            return existing;
        }

        GameRecord rebound = new GameRecord(gameId, humanExternalId, aiExternalId, humanName, aiName);
        rebound.bridgeRevision.set(existing.bridgeRevision.get());
        rebound.humanXmagePlayerId = existing.humanXmagePlayerId == null ? lastStartedHumanPlayerId : existing.humanXmagePlayerId;
        rebound.latestView = existing.latestView;
        rebound.latestCycle = existing.latestCycle;
        rebound.lastProgressAt = existing.lastProgressAt;
        rebound.promptText = existing.promptText;
        rebound.choicePrompt = existing.choicePrompt;
        rebound.promptEnvelope = existing.promptEnvelope;
        rebound.startupOpeningPrompts.addAll(existing.startupOpeningPrompts);
        normalizePlayerPromptChoices(rebound.promptEnvelope, rebound, rebound.latestView);
        rebound.choicePrompt = choicePromptFromEnvelope(rebound.promptEnvelope);
        games.put(gameId.toString(), rebound);
        return rebound;
    }

    private JsonObject submitCommand(String gameId, JsonObject command) throws Exception {
        if (command == null) {
            throw new IllegalArgumentException("Command cannot be null");
        }
        ensureConnected(false);
        UUID xmageGameId = UUID.fromString(gameId);
        String type = string(command, "type", "");
        GameRecord record = games.get(gameId);
        long startRevision = record == null ? -1 : record.bridgeRevision.get();
        int startCycle = record == null ? -1 : record.latestCycle;
        long expectedRevision = longInteger(command, "expectedBridgeRevision", -1L);
        if (expectedRevision >= 0 && startRevision > expectedRevision) {
            throw new ActionNoLongerLegalException(gameId, "Action was based on stale XMage snapshot revision " + expectedRevision + "; current revision is " + startRevision);
        }
        JsonObject prompt = currentPromptForCommand(gameId, command, type);

        if ("play_land".equals(type)) {
            // Desktop XMage receives the source card UUID for normal card clicks.
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("cast_spell".equals(type)) {
            // Casts from hand/command also submit the source card UUID, not an ability UUID.
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("activate_ability".equals(type)) {
            // Validate the selected ability UUID, then use XMage's source-click
            // activation path. Real XMage desktop playables expose ability ids for
            // legality, but the callback advances when the source object is clicked.
            playableCommandUuid(gameId, command);
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("make_mana".equals(type)) {
            // Basic mana activation follows card-click behavior and submits the source card UUID.
            session.sendPlayerUUID(xmageGameId, playableSourceUuid(gameId, command));
        } else if ("undo_mana".equals(type) || "cancel_payment".equals(type) || "cancel_mana_payment".equals(type)) {
            session.sendPlayerAction(PlayerAction.UNDO, xmageGameId, null);
        } else if ("pass_priority".equals(type)) {
            session.sendPlayerBoolean(xmageGameId, false);
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
            sendPromptUuids(gameId, xmageGameId, prompt, selectionIds(command, "targetIds", "targetId", "choiceIds", "choiceId"));
        } else if ("choose_card".equals(type)) {
            sendPromptUuids(gameId, xmageGameId, prompt, selectionIds(command, "cardInstanceIds", "cardInstanceId", "choiceIds", "choiceId"));
        } else if ("choose_player".equals(type)) {
            sendPromptStringsOrUuids(gameId, xmageGameId, prompt, selectionIds(command, "playerIds", "choiceId", "choiceIds", "choiceId"));
        } else if ("choose_mode".equals(type)) {
            sendPromptStringsOrUuids(gameId, xmageGameId, prompt, selectionIds(command, "modeIds", "modeId", "choiceIds", "choiceId"));
        } else if ("play_mana".equals(type)) {
            String manaChoice = firstSelection(command, "manaType", "mana", "choiceIds", "choiceId");
            if (manaChoice.isEmpty() && prompt != null) {
                sendEmptyPromptSelection(gameId, xmageGameId, prompt);
            } else {
                validatePromptSelections(gameId, prompt, singletonSelection(manaChoice));
                session.sendPlayerManaType(xmageGameId, manaPlayerUuid(gameId), manaTypeFromRequiredSymbol(gameId, manaChoice));
            }
        } else if ("choose_mana".equals(type)) {
            String manaChoice = firstSelection(command, "manaTypes", "manaType", "choiceIds", "choiceId");
            if (manaChoice.isEmpty()) {
                sendEmptyPromptSelection(gameId, xmageGameId, prompt);
            } else {
                validatePromptSelections(gameId, prompt, singletonSelection(manaChoice));
                session.sendPlayerManaType(xmageGameId, manaPlayerUuid(gameId), manaTypeFromRequiredSymbol(gameId, manaChoice));
            }
        } else if ("choose_ability".equals(type)) {
            String abilityId = firstSelection(command, "abilityId", "abilityIdChoice", "choiceIds", "choiceId");
            if (abilityId.isEmpty()) {
                sendEmptyPromptSelection(gameId, xmageGameId, prompt);
            } else {
                validatePromptSelections(gameId, prompt, singletonSelection(abilityId));
                if (!isUuid(abilityId)) {
                    throw new ActionNoLongerLegalException(gameId, "XMage expected ability UUID but received " + abilityId);
                }
                session.sendPlayerUUID(xmageGameId, UUID.fromString(abilityId));
            }
        } else if ("choose_pile".equals(type)) {
            int pile = requiredPile(command, gameId);
            validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(pile)));
            session.sendPlayerBoolean(xmageGameId, pile == 1);
        } else if ("choose_amount".equals(type) || "play_x_mana".equals(type)) {
            int amount = requiredAmountFromCommand(command, "amount", gameId);
            validatePromptAmount(gameId, prompt, amount);
            session.sendPlayerInteger(xmageGameId, amount);
        } else if ("choose_multi_amount".equals(type)) {
            JsonArray amounts = array(command, "amounts");
            validatePromptMultiAmount(gameId, prompt, amounts);
            session.sendPlayerString(xmageGameId, joinNumbers(amounts));
        } else if ("order_triggers".equals(type) || "order_items".equals(type)) {
            sendPromptUuids(gameId, xmageGameId, prompt, selectionIds(command, "orderedIds", "orderedId", "choiceIds", "choiceId"));
        } else if ("search_select".equals(type)) {
            sendPromptUuids(gameId, xmageGameId, prompt, selectionIds(command, "cardInstanceIds", "cardInstanceId", "choiceIds", "choiceId"));
        } else if ("commander_replacement".equals(type)) {
            boolean response = requiredBooleanResponse(gameId, command, "useCommandZone");
            validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(response)));
            session.sendPlayerBoolean(xmageGameId, response);
        } else if ("pay_cost".equals(type)) {
            boolean response = requiredBooleanResponse(gameId, command, "pay");
            validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(response)));
            session.sendPlayerBoolean(xmageGameId, response);
        } else if ("answer_yes_no".equals(type)) {
            boolean response = requiredBooleanResponse(gameId, command, "confirmed");
            validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(response)));
            session.sendPlayerBoolean(xmageGameId, response);
        } else if ("generic_replacement".equals(type)) {
            sendPromptStringsOrUuids(gameId, xmageGameId, prompt, selectionIds(command, "choiceIds", "choiceId", "ids", "id"));
        } else if ("declare_attackers".equals(type) || "declare_blockers".equals(type)) {
            sendCombatSelection(gameId, xmageGameId, command, "declare_attackers".equals(type));
        } else if ("resolve_choice".equals(type)) {
            JsonArray choices = array(command, "choiceIds");
            if (choices.size() > 0) {
                validatePromptSelections(gameId, prompt, choices);
                String choice = choices.get(0).getAsString();
                if (isUuid(choice)) {
                    session.sendPlayerUUID(xmageGameId, UUID.fromString(choice));
                } else if ("true".equalsIgnoreCase(choice) || "false".equalsIgnoreCase(choice)) {
                    session.sendPlayerBoolean(xmageGameId, Boolean.parseBoolean(choice));
                } else {
                    session.sendPlayerString(xmageGameId, choice);
                }
            } else {
                if (prompt != null && isOptionalPrompt(prompt) && !hasExplicitBooleanResponse(command, "value")) {
                    // Only optional resolve-choice prompts may send the XMage "done/cancel" response.
                    sendEmptyPromptSelection(gameId, xmageGameId, prompt);
                } else {
                    boolean response = requiredBooleanResponse(gameId, command, "value");
                    validatePromptSelections(gameId, prompt, singletonSelection(String.valueOf(response)));
                    session.sendPlayerBoolean(xmageGameId, response);
                }
            }
        } else {
            throw new IllegalArgumentException("Unknown command type: " + type);
        }

        if (record != null) {
            record.lastProgressAt = System.currentTimeMillis();
        }
        return waitForUpdatedSnapshot(gameId, type, startRevision, startCycle);
    }

    private JsonObject cleanupGame(String gameId, String reason) throws Exception {
        GameRecord record = games.remove(gameId);
        JsonObject response = new JsonObject();
        response.addProperty("status", record == null ? "not_found" : "cleaned_up");
        response.addProperty("gameId", gameId);
        response.addProperty("reason", reason == null || reason.isEmpty() ? "client-request" : reason);
        response.addProperty("removed", record != null);
        response.addProperty("bridgeCleanupAttempted", record != null);
        boolean succeeded = false;
        if (record != null) {
            try {
                ensureConnected(false);
                session.sendPlayerAction(PlayerAction.CONCEDE, record.gameId, null);
                succeeded = true;
            } catch (Exception ignored) {
                succeeded = false;
            }
        }
        response.addProperty("bridgeCleanupSucceeded", succeeded);
        return response;
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

    private boolean hasText(JsonObject object, String key) {
        return object != null && object.has(key) && !object.get(key).isJsonNull() && !object.get(key).getAsString().isBlank();
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

    private boolean isPromptRespondingCommand(String type) {
        return "choose_target".equals(type)
                || "choose_card".equals(type)
                || "choose_player".equals(type)
                || "choose_mode".equals(type)
                || "play_mana".equals(type)
                || "choose_mana".equals(type)
                || "choose_ability".equals(type)
                || "choose_pile".equals(type)
                || "choose_amount".equals(type)
                || "play_x_mana".equals(type)
                || "choose_multi_amount".equals(type)
                || "order_triggers".equals(type)
                || "order_items".equals(type)
                || "search_select".equals(type)
                || "commander_replacement".equals(type)
                || "pay_cost".equals(type)
                || "answer_yes_no".equals(type)
                || "resolve_choice".equals(type);
    }

    private JsonObject currentPromptForCommand(String gameId, JsonObject command, String type) {
        GameRecord record = games.get(gameId);
        JsonObject prompt = record == null ? null : record.promptEnvelope;
        String requestedPromptId = string(command, "promptId", "");
        int requestedMessageId = integer(command, "messageId", -1);
        boolean exactPromptRequested = !requestedPromptId.isEmpty() || requestedMessageId >= 0;

        if (isPromptRespondingCommand(type)) {
            if (prompt == null) {
                throw new ActionNoLongerLegalException(gameId, "XMage prompt is no longer active for command: " + type);
            }
            String activePromptId = string(prompt, "id", "");
            int activeMessageId = integer(prompt, "messageId", -1);
            if (requiresPromptIdentity(type) && !activePromptId.isEmpty() && requestedPromptId.isEmpty()) {
                throw new ActionNoLongerLegalException(gameId, "Missing active XMage prompt id for command: " + type);
            }
            if (requiresPromptIdentity(type) && activeMessageId >= 0 && requestedMessageId < 0) {
                throw new ActionNoLongerLegalException(gameId, "Missing active XMage prompt message id for command: " + type);
            }
            if (!requestedPromptId.isEmpty() && !requestedPromptId.equals(activePromptId)) {
                throw new ActionNoLongerLegalException(gameId, "XMage prompt is no longer active: " + requestedPromptId);
            }
            if (requestedMessageId >= 0 && requestedMessageId != activeMessageId) {
                throw new ActionNoLongerLegalException(gameId, "XMage prompt message is no longer active: " + requestedMessageId);
            }
            if (!isCommandCompatibleWithPrompt(type, prompt)) {
                throw new ActionNoLongerLegalException(gameId, "Command " + type + " does not answer active XMage prompt " + activePromptId);
            }
            return prompt;
        } else {
            if (prompt == null) {
                if (exactPromptRequested) {
                    throw new ActionNoLongerLegalException(gameId, "XMage prompt is no longer active");
                }
                return null;
            }

            String activePromptId = string(prompt, "id", "");
            int activeMessageId = integer(prompt, "messageId", -1);
            if (!requestedPromptId.isEmpty() && !requestedPromptId.equals(activePromptId)) {
                throw new ActionNoLongerLegalException(gameId, "XMage prompt is no longer active: " + requestedPromptId);
            }
            if (requestedMessageId >= 0 && requestedMessageId != activeMessageId) {
                throw new ActionNoLongerLegalException(gameId, "XMage prompt message is no longer active: " + requestedMessageId);
            }

            if (exactPromptRequested && !isCommandCompatibleWithPrompt(type, prompt)) {
                throw new ActionNoLongerLegalException(gameId, "Command " + type + " does not answer active XMage prompt " + activePromptId);
            }
            return exactPromptRequested || isCommandCompatibleWithPrompt(type, prompt) ? prompt : null;
        }
    }

    private boolean isCommandCompatibleWithPrompt(String type, JsonObject prompt) {
        String responseKind = string(prompt, "responseKind", "resolve_choice");
        String promptType = commandTypeForResponseKind(responseKind);
        if (type.equals(promptType) || "resolve_choice".equals(type)) {
            return true;
        }
        if ("search_select".equals(type) && ("card".equals(responseKind) || "search".equals(responseKind))) {
            return true;
        }
        if ("choose_player".equals(type) && "player".equals(responseKind)) {
            return true;
        }
        if ("choose_mana".equals(type) && "mana".equals(responseKind)) {
            return true;
        }
        if ("answer_yes_no".equals(type) && ("confirmation".equals(responseKind) || "resolve_choice".equals(promptType))) {
            return true;
        }
        if ("order_items".equals(type) && "order".equals(responseKind)) {
            return true;
        }
        if ("choose_card".equals(type) && "search".equals(responseKind)) {
            return true;
        }
        if ("pay_cost".equals(type) || "commander_replacement".equals(type)) {
            return "resolve_choice".equals(promptType) || "commander_replacement".equals(responseKind);
        }
        return false;
    }

    private boolean requiresPromptIdentity(String type) {
        return "pay_cost".equals(type)
                || "answer_yes_no".equals(type)
                || "commander_replacement".equals(type);
    }

    private JsonArray selectionIds(JsonObject command, String pluralKey, String singularKey, String fallbackPluralKey, String fallbackSingularKey) {
        JsonArray selections = new JsonArray();
        addSelections(selections, command, pluralKey);
        addSelection(selections, string(command, singularKey, ""));
        addSelections(selections, command, fallbackPluralKey);
        addSelection(selections, string(command, fallbackSingularKey, ""));
        return selections;
    }

    private void addSelections(JsonArray selections, JsonObject command, String key) {
        JsonArray values = array(command, key);
        for (JsonElement value : values) {
            if (value == null || value.isJsonNull()) continue;
            addSelection(selections, value.getAsString());
        }
    }

    private void addSelection(JsonArray selections, String value) {
        if (value != null && !value.isEmpty()) {
            selections.add(value);
        }
    }

    private JsonArray singletonSelection(String value) {
        JsonArray selections = new JsonArray();
        addSelection(selections, value);
        return selections;
    }

    private String firstSelection(JsonObject command, String key, String fallbackKey, String fallbackPluralKey, String fallbackSingularKey) {
        String value = string(command, key, "");
        if (!value.isEmpty()) return value;
        JsonArray values = array(command, key);
        if (values.size() > 0) return values.get(0).getAsString();
        value = string(command, fallbackKey, "");
        if (!value.isEmpty()) return value;
        JsonArray fallbackValues = array(command, fallbackPluralKey);
        if (fallbackValues.size() > 0) return fallbackValues.get(0).getAsString();
        return string(command, fallbackSingularKey, "");
    }

    private int requiredAmountFromCommand(JsonObject command, String key, String gameId) {
        if (command.has(key) && !command.get(key).isJsonNull()) {
            Integer amount = exactInteger(command.get(key));
            if (amount != null) {
                return amount;
            }
            throw new ActionNoLongerLegalException(gameId, "Amount must be a finite integer");
        }
        JsonArray choices = array(command, "choiceIds");
        if (choices.size() > 0) {
            Integer amount = exactInteger(choices.get(0));
            if (amount != null) {
                return amount;
            }
        }
        throw new ActionNoLongerLegalException(gameId, "Missing explicit amount for " + string(command, "type", "XMage amount prompt"));
    }

    private int requiredPile(JsonObject command, String gameId) {
        Integer pile = null;
        if (command.has("pile") && !command.get("pile").isJsonNull()) {
            pile = exactInteger(command.get("pile"));
        }
        if (pile == null) {
            JsonArray choices = array(command, "choiceIds");
            if (choices.size() > 0) {
                pile = exactInteger(choices.get(0));
            }
        }
        if (pile == null) {
            throw new ActionNoLongerLegalException(gameId, "Missing explicit pile selection");
        }
        if (pile != 1 && pile != 2) {
            throw new ActionNoLongerLegalException(gameId, "Unsupported XMage pile selection: " + pile);
        }
        return pile;
    }

    private Integer exactInteger(JsonElement element) {
        if (element == null || element.isJsonNull()) {
            return null;
        }
        String raw;
        try {
            raw = element.getAsString();
        } catch (UnsupportedOperationException | IllegalStateException ignored) {
            return null;
        }
        if (raw == null || !raw.matches("-?\\d+")) {
            return null;
        }
        try {
            return Integer.parseInt(raw);
        } catch (NumberFormatException ignored) {
            return null;
        }
    }

    private void validatePromptAmount(String gameId, JsonObject prompt, int amount) {
        if (prompt == null) {
            return;
        }
        int min = integer(prompt, "minChoices", Integer.MIN_VALUE);
        int max = integer(prompt, "maxChoices", Integer.MAX_VALUE);
        if (amount < min || amount > max) {
            throw new ActionNoLongerLegalException(gameId, "Amount is outside active XMage prompt range: " + amount);
        }
        if (prompt.has("amounts") && prompt.get("amounts").isJsonArray() && prompt.getAsJsonArray("amounts").size() > 0) {
            boolean allowed = false;
            for (JsonElement element : prompt.getAsJsonArray("amounts")) {
                Integer candidate = exactInteger(element);
                if (candidate != null && candidate == amount) {
                    allowed = true;
                    break;
                }
            }
            if (!allowed) {
                throw new ActionNoLongerLegalException(gameId, "Amount is not valid for active XMage prompt: " + amount);
            }
        }
    }

    private void validatePromptMultiAmount(String gameId, JsonObject prompt, JsonArray amounts) {
        if (prompt == null) {
            return;
        }
        boolean required = bool(prompt, "required", true);
        JsonArray slots = array(prompt, "multiAmounts");
        if (slots.size() > 0) {
            if (!required && amounts.size() == 0) {
                return;
            }
            if (amounts.size() != slots.size()) {
                throw new ActionNoLongerLegalException(gameId, "XMage multi-amount prompt requires exactly " + slots.size() + " value(s)");
            }
            int total = 0;
            for (int i = 0; i < slots.size(); i++) {
                if (!slots.get(i).isJsonObject()) {
                    throw new ActionNoLongerLegalException(gameId, "XMage multi-amount prompt has invalid slot metadata");
                }
                JsonObject slot = slots.get(i).getAsJsonObject();
                Integer amount = exactInteger(amounts.get(i));
                if (amount == null) {
                    throw new ActionNoLongerLegalException(gameId, "Amount must be a finite integer");
                }
                int min = integer(slot, "min", 0);
                int max = integer(slot, "max", min);
                if (amount < min || amount > max) {
                    throw new ActionNoLongerLegalException(gameId, "Amount is outside XMage slot bounds: " + amount);
                }
                total += amount;
            }
            int totalMin = integer(prompt, "totalMin", integer(prompt, "minChoices", 0));
            int totalMax = integer(prompt, "totalMax", integer(prompt, "maxChoices", totalMin));
            if (total < totalMin || total > totalMax) {
                throw new ActionNoLongerLegalException(gameId, "XMage multi-amount total must be between " + totalMin + " and " + totalMax);
            }
            return;
        }
        int min = integer(prompt, "minChoices", required ? 1 : 0);
        int max = integer(prompt, "maxChoices", min);
        if (!required && amounts.size() == 0) {
            return;
        }
        if (amounts.size() < min) {
            throw new ActionNoLongerLegalException(gameId, "XMage amount prompt requires at least " + min + " value(s)");
        }
        if (max > 0 && amounts.size() > max) {
            throw new ActionNoLongerLegalException(gameId, "XMage amount prompt allows at most " + max + " value(s)");
        }
        Set<Integer> allowedAmounts = allowedPromptAmounts(prompt);
        for (JsonElement element : amounts) {
            Integer amount = exactInteger(element);
            if (amount == null) {
                throw new ActionNoLongerLegalException(gameId, "Amount must be a finite integer");
            }
            if (!allowedAmounts.isEmpty() && !allowedAmounts.contains(amount)) {
                throw new ActionNoLongerLegalException(gameId, "Amount is not valid for active XMage prompt: " + amount);
            }
        }
    }

    private Set<Integer> allowedPromptAmounts(JsonObject prompt) {
        Set<Integer> allowed = new HashSet<>();
        if (prompt == null || !prompt.has("amounts") || !prompt.get("amounts").isJsonArray()) {
            return allowed;
        }
        for (JsonElement element : prompt.getAsJsonArray("amounts")) {
            Integer amount = exactInteger(element);
            if (amount != null) {
                allowed.add(amount);
            }
        }
        return allowed;
    }

    private boolean booleanResponse(JsonObject command, String preferredKey, boolean fallback) {
        if (command.has(preferredKey) && !command.get(preferredKey).isJsonNull()) {
            return bool(command, preferredKey, fallback);
        }
        for (String key : new String[]{"value", "answer", "accepted", "confirmed", "yes", "useReplacement"}) {
            if (command.has(key) && !command.get(key).isJsonNull()) {
                return bool(command, key, fallback);
            }
        }
        JsonArray choices = array(command, "choiceIds");
        if (choices.size() > 0) {
            String choice = choices.get(0).getAsString();
            if ("true".equalsIgnoreCase(choice) || "yes".equalsIgnoreCase(choice)) return true;
            if ("false".equalsIgnoreCase(choice) || "no".equalsIgnoreCase(choice)) return false;
        }
        return fallback;
    }

    private boolean requiredBooleanResponse(String gameId, JsonObject command, String preferredKey) {
        if (!hasExplicitBooleanResponse(command, preferredKey)) {
            throw new ActionNoLongerLegalException(gameId, "Missing explicit boolean response for " + string(command, "type", "XMage prompt"));
        }
        return booleanResponse(command, preferredKey, false);
    }

    private boolean hasExplicitBooleanResponse(JsonObject command, String preferredKey) {
        if (command.has(preferredKey) && !command.get(preferredKey).isJsonNull()) {
            return true;
        }
        for (String key : new String[]{"value", "answer", "accepted", "confirmed", "yes", "useReplacement"}) {
            if (command.has(key) && !command.get(key).isJsonNull()) {
                return true;
            }
        }
        JsonArray choices = array(command, "choiceIds");
        if (choices.size() == 0) {
            return false;
        }
        String choice = choices.get(0).getAsString();
        return "true".equalsIgnoreCase(choice)
                || "yes".equalsIgnoreCase(choice)
                || "false".equalsIgnoreCase(choice)
                || "no".equalsIgnoreCase(choice);
    }

    private void validatePromptSelections(String gameId, JsonObject prompt, JsonArray selections) {
        if (prompt == null) {
            return;
        }
        boolean required = bool(prompt, "required", true);
        int min = integer(prompt, "minChoices", required ? 1 : 0);
        int max = integer(prompt, "maxChoices", min);
        if (isOptionalPrompt(prompt) && selections.size() == 0) {
            return;
        }
        if (selections.size() < min) {
            throw new ActionNoLongerLegalException(gameId, "XMage prompt requires at least " + min + " selection(s)");
        }
        if (max > 0 && selections.size() > max) {
            throw new ActionNoLongerLegalException(gameId, "XMage prompt allows at most " + max + " selection(s)");
        }
        Set<String> seen = new HashSet<>();
        for (JsonElement element : selections) {
            String id = element.getAsString();
            if (!seen.add(id)) {
                throw new ActionNoLongerLegalException(gameId, "Duplicate selection for active XMage prompt: " + id);
            }
        }
        if (!prompt.has("choices") || !prompt.get("choices").isJsonArray()) {
            return;
        }
        Set<String> allowed = new HashSet<>();
        Set<String> disabled = new HashSet<>();
        for (JsonElement element : prompt.getAsJsonArray("choices")) {
            if (!element.isJsonObject()) continue;
            JsonObject choice = element.getAsJsonObject();
            String id = string(choice, "id", "");
            if (!id.isEmpty()) {
                allowed.add(id);
                if (bool(choice, "disabled", false) || !bool(choice, "selectable", true)) {
                    disabled.add(id);
                }
            }
        }
        if (allowed.isEmpty()) {
            return;
        }
        for (JsonElement element : selections) {
            String id = element.getAsString();
            if (!allowed.contains(id)) {
                throw new ActionNoLongerLegalException(gameId, "Selection is not valid for active XMage prompt: " + id);
            }
            if (disabled.contains(id)) {
                throw new ActionNoLongerLegalException(gameId, "Selection is disabled for active XMage prompt: " + id);
            }
        }
    }

    private void sendPromptUuids(String bridgeGameId, UUID xmageGameId, JsonObject prompt, JsonArray ids) {
        validatePromptSelections(bridgeGameId, prompt, ids);
        if (ids.size() == 0) {
            sendEmptyPromptSelection(bridgeGameId, xmageGameId, prompt);
            return;
        }
        for (JsonElement id : ids) {
            String value = id.getAsString();
            if (!isUuid(value)) {
                throw new ActionNoLongerLegalException(bridgeGameId, "XMage expected UUID selection but received " + value);
            }
            session.sendPlayerUUID(xmageGameId, UUID.fromString(value));
        }
    }

    private void sendPromptStringsOrUuids(String bridgeGameId, UUID xmageGameId, JsonObject prompt, JsonArray ids) {
        validatePromptSelections(bridgeGameId, prompt, ids);
        if (ids.size() == 0) {
            sendEmptyPromptSelection(bridgeGameId, xmageGameId, prompt);
            return;
        }
        for (JsonElement id : ids) {
            String value = id.getAsString();
            if (isUuid(value)) {
                session.sendPlayerUUID(xmageGameId, UUID.fromString(value));
            } else {
                session.sendPlayerString(xmageGameId, value);
            }
        }
    }

    private void sendEmptyPromptSelection(String bridgeGameId, UUID xmageGameId, JsonObject prompt) {
        if (prompt != null && isOptionalPrompt(prompt)) {
            session.sendPlayerBoolean(xmageGameId, false);
            return;
        }
        throw new ActionNoLongerLegalException(bridgeGameId, "Missing selection for active XMage prompt");
    }

    private boolean isOptionalPrompt(JsonObject prompt) {
        if (prompt == null) {
            return false;
        }
        boolean required = bool(prompt, "required", true);
        int min = integer(prompt, "minChoices", required ? 1 : 0);
        return !required || min == 0;
    }

    private void sendCombatSelection(String bridgeGameId, UUID xmageGameId, JsonObject command, boolean attackers) {
        JsonArray ids = new JsonArray();
        JsonArray groups = array(command, attackers ? "attackers" : "blockers");
        String objectKey = attackers ? "attackerId" : "blockerId";
        for (JsonElement element : groups) {
            if (!element.isJsonObject()) continue;
            addSelection(ids, string(element.getAsJsonObject(), objectKey, ""));
        }
        addSelections(ids, command, attackers ? "attackerIds" : "blockerIds");
        if (ids.size() == 0) {
            session.sendPlayerBoolean(xmageGameId, false);
            return;
        }
        for (JsonElement id : ids) {
            String value = id.getAsString();
            if (!isUuid(value)) {
                throw new ActionNoLongerLegalException(bridgeGameId, "XMage expected combat UUID but received " + value);
            }
            session.sendPlayerUUID(xmageGameId, UUID.fromString(value));
            combatResponsePause(bridgeGameId);
        }
        session.sendPlayerBoolean(xmageGameId, false);
    }

    private void combatResponsePause(String bridgeGameId) {
        try {
            Thread.sleep(350);
        } catch (InterruptedException error) {
            Thread.currentThread().interrupt();
            throw new ActionNoLongerLegalException(bridgeGameId, "Interrupted while waiting for XMage combat response");
        }
    }

    private JsonObject waitForUpdatedSnapshot(String gameId, String commandType, long startRevision, int startCycle) throws InterruptedException {
        GameRecord record;
        long waitMs = isDirectCommand(commandType) ? 1500 : 6000;
        long deadline = System.currentTimeMillis() + waitMs;
        while (System.currentTimeMillis() < deadline) {
            record = games.get(gameId);
            if (record != null
                    && record.latestView != null
                    && (record.bridgeRevision.get() > startRevision || record.latestCycle > startCycle)) {
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
                || "make_mana".equals(type)
                || "undo_mana".equals(type)
                || "cancel_payment".equals(type)
                || "cancel_mana_payment".equals(type)
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
        snapshot.add("legalActions", pendingStatus == null ? legalActions(record, view, playerIds) : pendingLegalActions(record));
        snapshot.add("engineHealth", passiveHealth());
        if (record.choicePrompt != null) {
            snapshot.add("choicePrompt", record.choicePrompt);
        }
        if (record.promptEnvelope != null) {
            snapshot.add("promptEnvelope", record.promptEnvelope);
            snapshot.add("promptEnvelopeV2", record.promptEnvelope);
        }
        snapshot.add("startupOpeningPrompts", record.startupOpeningPrompts.deepCopy());
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

    private JsonArray pendingLegalActions(GameRecord record) {
        JsonArray actions = new JsonArray();
        actions.add(action("xmage-concede", "concede", record.humanExternalId, "Concede", null, null, null));
        return actions;
    }

    private JsonArray legalActions(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonArray actions = new JsonArray();
        String humanId = record.humanExternalId;
        if (canUndoMana(view, playerIds, humanId)) {
            actions.add(action("xmage-undo-mana", "undo_mana", humanId, "Undo mana", null, null, null));
        }

        if (isGameOverPrompt(record)) {
            actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));
            return actions;
        }

        if (isMulliganPrompt(record)) {
            actions.add(action("xmage-keep", "keep_hand", humanId, "Keep", null, null, null));
            actions.add(action("xmage-mulligan", "mulligan", humanId, "Mulligan", null, null, null));
            actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));
            markPrimary(actions, "xmage-keep", "Keep");
            return actions;
        }

        JsonArray combatActions = combatActions(record, view, playerIds);
        if (combatActions.size() > 0) {
            for (JsonElement element : combatActions) {
                actions.add(element);
            }
            actions.add(action("xmage-concede", "concede", humanId, "Concede", null, null, null));
            return actions;
        }

        if (record.choicePrompt != null && record.choicePrompt.has("choices")) {
            String choiceActionType = promptActionType(record);
            if ("choose_multi_amount".equals(choiceActionType) && array(record.promptEnvelope, "multiAmounts").size() > 0) {
                actions.add(multiAmountAction(record, humanId));
            } else {
                for (JsonElement choiceElement : record.choicePrompt.getAsJsonArray("choices")) {
                    if (!choiceElement.isJsonObject()) continue;
                    JsonObject choice = choiceElement.getAsJsonObject();
                    String choiceId = string(choice, "id", "");
                    if (choiceId.isEmpty()) continue;
                    actions.add(choiceAction(record, choiceId, choiceActionType, humanId, labelForChoice(record, playerIds, choiceId)));
                }
            }
            if (isManaPaymentPrompt(record)) {
                addPlayableObjectActions(actions, humanId, view, true);
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

        addPlayableObjectActions(actions, humanId, view, false);

        return actions;
    }

    private boolean isGameOverPrompt(GameRecord record) {
        return record != null
                && record.promptEnvelope != null
                && "game_over".equals(string(record.promptEnvelope, "responseKind", ""));
    }

    private void addPlayableObjectActions(JsonArray actions, String humanId, GameView view, boolean manaOnly) {
        PlayableObjectsList playable = view.getCanPlayObjects();
        if (playable == null || playable.isEmpty()) {
            return;
        }

        Set<UUID> handIds = new HashSet<>(view.getMyHand().keySet());
        Set<UUID> commandIds = commandIds(view);
        for (Map.Entry<UUID, PlayableObjectStats> entry : playable.getObjects().entrySet()) {
            UUID objectId = entry.getKey();
            CardView card = findVisibleCard(view, objectId);
            if (card == null) {
                continue;
            }
            PlayableObjectStats stats = entry.getValue();
            if (manaOnly && !hasManaPlayable(card, stats)) {
                continue;
            }
            if (manaOnly && handIds.contains(objectId)) {
                continue;
            }
            List<UUID> abilityIds = stats.getPlayableAbilityIds();
            List<String> abilityLabels = stats.getPlayableAbilityNames();
            boolean inCommand = commandIds.contains(objectId);
            String type = manaOnly ? "make_mana" : actionType(card, handIds.contains(objectId), inCommand);
            String sourceZone = handIds.contains(objectId) ? "hand" : inCommand ? "command" : "battlefield";
            if (abilityIds.isEmpty()) {
                actions.add(action(
                        objectId.toString(),
                        type,
                        humanId,
                        labelFor(type, card.getName()),
                        objectId.toString(),
                        sourceZone,
                        null,
                        card
                ));
            } else {
                for (int index = 0; index < abilityIds.size(); index++) {
                    String abilityLabel = index < abilityLabels.size() ? abilityLabels.get(index) : "";
                    if (manaOnly && !isManaAbility(card, abilityLabel)) {
                        continue;
                    }
                    boolean playableFromHiddenZone = handIds.contains(objectId) || inCommand;
                    String abilityType = manaOnly || (!playableFromHiddenZone && isManaAbility(card, abilityLabel))
                            ? "make_mana"
                            : actionType(card, handIds.contains(objectId), inCommand, false);
                    UUID abilityUuid = abilityIds.get(index);
                    String abilityId = abilityUuid.toString();
                    JsonObject playableAction = action(
                            abilityId,
                            abilityType,
                            humanId,
                            labelFor(abilityType, card.getName()),
                            objectId.toString(),
                            sourceZone,
                            abilityId,
                            card
                    );
                    addActivationDispatch(playableAction, abilityType, card, abilityLabel);
                    actions.add(playableAction);
                }
            }
        }
    }

    private void addActivationDispatch(JsonObject action, String type, CardView card, String abilityLabel) {
        if (!"activate_ability".equals(type)) {
            return;
        }
        String text = (String.valueOf(abilityLabel) + "\n" + rulesText(card)).toLowerCase();
        String dispatch = text.contains("target") ? "ability" : "source";
        action.addProperty("activationDispatch", dispatch);
        JsonObject template = object(action, "commandTemplate", new JsonObject());
        template.addProperty("activationDispatch", dispatch);
        action.add("commandTemplate", template);
    }

    private Set<UUID> commandIds(GameView view) {
        Set<UUID> ids = new HashSet<>();
        for (PlayerView player : view.getPlayers()) {
            for (CommandObjectView command : player.getCommandObjectList()) {
                ids.add(command.getId());
            }
        }
        return ids;
    }

    private JsonArray combatActions(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        JsonArray actions = new JsonArray();
        if (!humanHasPriority(record, view)) {
            return actions;
        }
        PlayerView human = playerByExternalId(record.humanExternalId, view, playerIds);
        if (human == null) {
            return actions;
        }
        String step = step(view.getStep());
        if ("declare-attackers".equals(step)) {
            PlayerView defender = firstOpponent(record.humanExternalId, view, playerIds);
            if (defender == null) {
                return actions;
            }
            String defenderExternalId = playerIds.get(defender.getPlayerId());
            for (PermanentView permanent : human.getBattlefield().values()) {
                if (!permanent.isCreature() || permanent.isTapped() || permanent.hasSummoningSickness()) {
                    continue;
                }
                actions.add(combatAction(
                        "xmage-attack-" + permanent.getId(),
                        "declare_attackers",
                        record.humanExternalId,
                        "Attack " + defender.getName() + " with " + permanent.getName(),
                        permanent,
                        defenderExternalId,
                        null
                ));
            }
        } else if ("declare-blockers".equals(step)) {
            JsonArray attackerChoices = combatAttackers(view);
            if (attackerChoices.size() == 0) {
                return actions;
            }
            List<PermanentView> untappedBlockers = new ArrayList<>();
            for (PermanentView permanent : human.getBattlefield().values()) {
                if (!permanent.isCreature() || permanent.isTapped()) {
                    continue;
                }
                untappedBlockers.add(permanent);
                for (JsonElement element : attackerChoices) {
                    if (!element.isJsonObject()) continue;
                    JsonObject attacker = element.getAsJsonObject();
                    String attackerId = string(attacker, "id", "");
                    if (attackerId.isEmpty()) continue;
                    actions.add(combatAction(
                            "xmage-block-" + permanent.getId() + "-" + attackerId,
                            "declare_blockers",
                            record.humanExternalId,
                            "Block " + string(attacker, "name", "attacker") + " with " + permanent.getName(),
                            permanent,
                            null,
                            attackerId
                    ));
                }
            }
            if (untappedBlockers.size() > 1) {
                for (JsonElement element : attackerChoices) {
                    if (!element.isJsonObject()) continue;
                    JsonObject attacker = element.getAsJsonObject();
                    String attackerId = string(attacker, "id", "");
                    if (attackerId.isEmpty()) continue;
                    actions.add(multiBlockAction(record.humanExternalId, string(attacker, "name", "attacker"), attackerId, untappedBlockers));
                }
            }
        }
        return actions;
    }

    private JsonArray combatAttackers(GameView view) {
        JsonArray attackers = new JsonArray();
        for (CombatGroupView group : view.getCombat()) {
            for (CardView attacker : group.getAttackers().values()) {
                JsonObject item = new JsonObject();
                item.addProperty("id", attacker.getId().toString());
                item.addProperty("name", attacker.getName());
                attackers.add(item);
            }
        }
        return attackers;
    }

    private PlayerView playerByExternalId(String externalId, GameView view, Map<UUID, String> playerIds) {
        for (PlayerView player : view.getPlayers()) {
            if (externalId.equals(playerIds.get(player.getPlayerId()))) {
                return player;
            }
        }
        return null;
    }

    private PlayerView firstOpponent(String externalId, GameView view, Map<UUID, String> playerIds) {
        for (PlayerView player : view.getPlayers()) {
            if (!externalId.equals(playerIds.get(player.getPlayerId()))) {
                return player;
            }
        }
        return null;
    }

    private JsonObject combatAction(String id, String type, String playerId, String label, PermanentView permanent, String defenderId, String attackerId) {
        JsonObject action = action(id, type, playerId, label, permanent.getId().toString(), "battlefield", null, permanent);
        JsonObject template = new JsonObject();
        template.addProperty("type", type);
        template.addProperty("cardInstanceId", permanent.getId().toString());
        template.addProperty("sourceInstanceId", permanent.getId().toString());
        template.addProperty("sourceZone", "battlefield");
        template.addProperty("cardName", permanent.getName());
        if ("declare_attackers".equals(type)) {
            JsonArray attackers = new JsonArray();
            JsonObject pair = new JsonObject();
            pair.addProperty("attackerId", permanent.getId().toString());
            if (defenderId != null) {
                pair.addProperty("defenderId", defenderId);
            }
            attackers.add(pair);
            action.add("attackers", attackers.deepCopy());
            template.add("attackers", attackers.deepCopy());
        } else if ("declare_blockers".equals(type)) {
            JsonArray blockers = new JsonArray();
            JsonObject pair = new JsonObject();
            pair.addProperty("blockerId", permanent.getId().toString());
            if (attackerId != null) {
                pair.addProperty("attackerId", attackerId);
            }
            blockers.add(pair);
            action.add("blockers", blockers.deepCopy());
            JsonArray validTargetIds = new JsonArray();
            if (attackerId != null) {
                validTargetIds.add(attackerId);
            }
            action.add("validTargetIds", validTargetIds);
            template.add("blockers", blockers.deepCopy());
        }
        action.add("commandTemplate", template);
        action.addProperty("isPrimary", true);
        return action;
    }

    private JsonObject multiBlockAction(String playerId, String attackerName, String attackerId, List<PermanentView> blockers) {
        PermanentView firstBlocker = blockers.get(0);
        JsonObject action = action(
                "xmage-block-multi-" + attackerId,
                "declare_blockers",
                playerId,
                "Block " + attackerName + " with " + blockers.size() + " creatures",
                firstBlocker.getId().toString(),
                "battlefield",
                null,
                firstBlocker
        );
        JsonObject template = new JsonObject();
        template.addProperty("type", "declare_blockers");
        template.addProperty("cardInstanceId", firstBlocker.getId().toString());
        template.addProperty("sourceInstanceId", firstBlocker.getId().toString());
        template.addProperty("sourceZone", "battlefield");
        template.addProperty("cardName", firstBlocker.getName());

        JsonArray blockerPairs = new JsonArray();
        JsonArray blockerIds = new JsonArray();
        for (PermanentView blocker : blockers) {
            JsonObject pair = new JsonObject();
            pair.addProperty("blockerId", blocker.getId().toString());
            pair.addProperty("attackerId", attackerId);
            blockerPairs.add(pair);
            blockerIds.add(blocker.getId().toString());
        }
        JsonArray validTargetIds = new JsonArray();
        validTargetIds.add(attackerId);
        action.add("blockers", blockerPairs.deepCopy());
        action.add("blockerIds", blockerIds.deepCopy());
        action.add("validTargetIds", validTargetIds);
        template.add("blockers", blockerPairs.deepCopy());
        template.add("blockerIds", blockerIds.deepCopy());
        action.add("commandTemplate", template);
        action.addProperty("isPrimary", true);
        return action;
    }

    private boolean isManaPaymentPrompt(GameRecord record) {
        if (record.promptEnvelope == null) {
            return false;
        }
        String responseKind = string(record.promptEnvelope, "responseKind", "");
        String responseType = "";
        JsonObject responseCommand = object(record.promptEnvelope, "responseCommand");
        if (responseCommand != null) {
            responseType = string(responseCommand, "type", "");
        }
        String method = string(record.promptEnvelope, "method", "");
        return "mana".equals(responseKind)
                || "pay_cost".equals(responseKind)
                || "cost".equals(responseKind)
                || "x_mana".equals(responseKind)
                || "pay_cost".equals(responseType)
                || "choose_mana".equals(responseType)
                || "play_mana".equals(responseType)
                || "play_x_mana".equals(responseType)
                || "GAME_PLAY_MANA".equals(method)
                || "GAME_PLAY_XMANA".equals(method);
    }

    private boolean canUndoMana(GameView view, Map<UUID, String> playerIds, String humanId) {
        if (view == null || view.getStack() == null || !view.getStack().isEmpty()) {
            return false;
        }
        for (PlayerView player : view.getPlayers()) {
            if (humanId.equals(playerIds.get(player.getPlayerId()))) {
                return player.getStatesSavedSize() > 0;
            }
        }
        return false;
    }

    private boolean hasManaPlayable(CardView card, PlayableObjectStats stats) {
        if (producedManaHint(card).size() > 0) {
            return true;
        }
        List<String> labels = stats.getPlayableAbilityNames();
        for (String label : labels) {
            if (isManaAbility(card, label)) {
                return true;
            }
        }
        return false;
    }

    private boolean isManaAbility(CardView card, String abilityLabel) {
        String text = cleanText((abilityLabel == null ? "" : abilityLabel) + "\n" + rulesText(card)).toLowerCase();
        return text.contains("add {")
                || text.contains("add one mana")
                || text.contains("add x mana")
                || text.contains("mana of any color");
    }

    private JsonObject action(String id, String type, String playerId, String label, String cardInstanceId, String sourceZone, String abilityId) {
        return action(id, type, playerId, label, cardInstanceId, sourceZone, abilityId, null);
    }

    private JsonObject action(String id, String type, String playerId, String label, String cardInstanceId, String sourceZone, String abilityId, CardView card) {
        JsonObject action = new JsonObject();
        action.addProperty("id", id);
        action.addProperty("type", type);
        action.addProperty("playerId", playerId);
        action.addProperty("label", label);
        action.addProperty("shortLabel", shortLabel(type, label));
        action.addProperty("requiresTarget", requiresTarget(type));
        if (card != null) {
            action.addProperty("cardName", card.getName());
            if ("cast_spell".equals(type) && card.getManaValue() > 0) {
                action.addProperty("requiresPayment", true);
            }
            if ("make_mana".equals(type)) {
                JsonArray producedMana = producedManaHint(card);
                if (producedMana.size() > 0) {
                    action.add("producedMana", producedMana);
                }
            }
        }
        if (cardInstanceId != null) {
            action.addProperty("cardInstanceId", cardInstanceId);
            action.addProperty("sourceInstanceId", cardInstanceId);
        }
        if (sourceZone != null) {
            action.addProperty("sourceZone", sourceZone);
        }
        JsonObject template = new JsonObject();
        template.addProperty("type", type);
        if (cardInstanceId != null) {
            template.addProperty("cardInstanceId", cardInstanceId);
            template.addProperty("sourceInstanceId", cardInstanceId);
        }
        if (sourceZone != null) {
            template.addProperty("sourceZone", sourceZone);
        }
        if (card != null) {
            template.addProperty("cardName", card.getName());
        }
        if (abilityId != null) {
            action.addProperty("abilityId", abilityId);
            template.addProperty("abilityId", abilityId);
        }
        if (template.size() > 1) {
            action.add("commandTemplate", template);
        }
        return action;
    }

    private JsonArray producedManaHint(CardView card) {
        JsonArray out = new JsonArray();
        if (card == null) {
            return out;
        }
        String text = (card.getName() + "\n" + rulesText(card)).toLowerCase();
        addManaHint(out, text, "{w}", "W");
        addManaHint(out, text, "{u}", "U");
        addManaHint(out, text, "{b}", "B");
        addManaHint(out, text, "{r}", "R");
        addManaHint(out, text, "{g}", "G");
        addManaHint(out, text, "{c}", "C");
        if (out.size() == 0 && text.contains("mana of any color")) {
            out.add("W");
            out.add("U");
            out.add("B");
            out.add("R");
            out.add("G");
        }
        return out;
    }

    private void addManaHint(JsonArray out, String text, String token, String symbol) {
        if (text.contains(token)) {
            out.add(symbol);
        }
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
        out.add("stack", stackObjects(view.getStack(), view, playerIds));
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

    private JsonArray stackObjects(CardsView stack, GameView view, Map<UUID, String> playerIds) {
        JsonArray out = new JsonArray();
        for (CardView card : stack.values()) {
            JsonObject item = new JsonObject();
            item.addProperty("id", card.getId().toString());
            item.addProperty("objectId", card.getId().toString());
            item.addProperty("name", card.getName());
            item.addProperty("objectType", stackObjectType(card));
            item.addProperty("sourceZone", "stack");
            String rulesText = rulesText(card);
            if (!rulesText.isEmpty()) {
                item.addProperty("rulesText", rulesText);
            }
            item.addProperty("paid", card.isPaid());
            CardView sourceCard = resolveStackSourceCard(card, view);
            if (sourceCard != null) {
                item.addProperty("sourceInstanceId", sourceCard.getId().toString());
                item.addProperty("sourceName", sourceCard.getName());
                item.add("sourceCard", zoneCard(sourceCard));
            } else {
                item.addProperty("sourceInstanceId", card.getId().toString());
                item.addProperty("sourceName", stackSourceName(card));
                item.addProperty("sourceCardUnavailableReason", "XMage exposed a synthetic stack object without source card metadata.");
            }
            UUID controllerId = optionalUuidProperty(card, "getControllerId", "getController", "getOwnerId", "getOwner");
            if (controllerId != null) {
                item.addProperty("controllerXmageId", controllerId.toString());
                item.addProperty("controllerId", playerIds.getOrDefault(controllerId, controllerId.toString()));
            }
            JsonArray targets = optionalTargetIds(card, playerIds);
            if (targets.size() > 0) {
                item.add("targetIds", targets);
            }
            out.add(item);
        }
        return out;
    }

    private CardView resolveStackSourceCard(CardView card, GameView view) {
        if (card == null || view == null) {
            return null;
        }
        if (!isSyntheticStackObject(card)) {
            return card;
        }
        UUID sourceId = optionalUuidMember(card,
                "sourceId",
                "sourceObjectId",
                "sourceCardId",
                "sourcePermanentId",
                "originalId",
                "originalCardId",
                "getSourceId",
                "getSourceObjectId",
                "getSourceCardId",
                "getSourcePermanentId",
                "getOriginalId",
                "getOriginalCardId");
        if (sourceId != null) {
            CardView byId = findVisibleCard(view, sourceId);
            if (byId != null) {
                return byId;
            }
        }
        String sourceName = stackSourceName(card);
        if (!sourceName.isEmpty() && !"ability".equalsIgnoreCase(sourceName) && !"card".equalsIgnoreCase(sourceName)) {
            return findVisibleCardByName(view, sourceName);
        }
        return null;
    }

    private boolean isSyntheticStackObject(CardView card) {
        String name = card.getName() == null ? "" : card.getName().trim();
        String type = cleanText(card.getTypeText()).trim();
        return "Ability".equalsIgnoreCase(name)
                || "Triggered ability".equalsIgnoreCase(name)
                || "Activated ability".equalsIgnoreCase(name)
                || "Card".equalsIgnoreCase(type);
    }

    private String stackObjectType(CardView card) {
        String name = card.getName() == null ? "" : card.getName().trim().toLowerCase();
        if (name.contains("trigger")) {
            return "triggered_ability";
        }
        if (name.contains("ability") || isSyntheticStackObject(card)) {
            return "ability";
        }
        return "spell";
    }

    private String stackSourceName(CardView card) {
        Object sourceName = optionalProperty(card, "getSourceName", "getSourceCardName", "getOriginalName");
        String value = sourceName == null ? "" : cleanText(sourceName.toString());
        return value.isEmpty() ? cleanText(card.getName()) : value;
    }

    private CardView findVisibleCardByName(GameView view, String name) {
        if (view == null || name == null || name.isEmpty()) {
            return null;
        }
        for (CardView card : view.getMyHand().values()) {
            if (name.equals(card.getName())) {
                return card;
            }
        }
        for (PlayerView player : view.getPlayers()) {
            CardView found = findCardByName(player.getBattlefield().values(), name);
            if (found != null) return found;
            found = findCardByName(player.getGraveyard().values(), name);
            if (found != null) return found;
            found = findCardByName(player.getExile().values(), name);
            if (found != null) return found;
            for (CommandObjectView command : player.getCommandObjectList()) {
                if (command instanceof CardView && name.equals(((CardView) command).getName())) {
                    return (CardView) command;
                }
            }
        }
        return null;
    }

    private CardView findCardByName(Iterable<? extends CardView> cards, String name) {
        for (CardView card : cards) {
            if (name.equals(card.getName())) {
                return card;
            }
        }
        return null;
    }

    private UUID optionalUuidProperty(Object object, String... methodNames) {
        Object value = optionalProperty(object, methodNames);
        if (value instanceof UUID) {
            return (UUID) value;
        }
        if (value != null && isUuid(value.toString())) {
            return UUID.fromString(value.toString());
        }
        return null;
    }

    private UUID optionalUuidMember(Object object, String... names) {
        if (object == null) {
            return null;
        }
        for (String name : names) {
            Object value = null;
            try {
                if (name.startsWith("get")) {
                    Method method = object.getClass().getMethod(name);
                    value = method.invoke(object);
                } else {
                    Field field = findField(object.getClass(), name);
                    field.setAccessible(true);
                    value = field.get(object);
                }
            } catch (ReflectiveOperationException | RuntimeException ignored) {
            }
            if (value instanceof UUID) {
                return (UUID) value;
            }
            if (value != null && isUuid(value.toString())) {
                return UUID.fromString(value.toString());
            }
        }
        return null;
    }

    private JsonArray optionalTargetIds(Object object, Map<UUID, String> playerIds) {
        JsonArray out = new JsonArray();
        Object value = optionalProperty(object, "getTargets", "getTargetIds");
        if (value instanceof Collection<?>) {
            for (Object target : (Collection<?>) value) {
                addOptionalTargetId(out, target, playerIds);
            }
        } else if (value instanceof Object[]) {
            for (Object target : (Object[]) value) {
                addOptionalTargetId(out, target, playerIds);
            }
        } else {
            addOptionalTargetId(out, value, playerIds);
        }
        return out;
    }

    private void addOptionalTargetId(JsonArray out, Object value, Map<UUID, String> playerIds) {
        if (value == null) {
            return;
        }
        UUID targetId = value instanceof UUID ? (UUID) value : null;
        if (targetId == null && isUuid(value.toString())) {
            targetId = UUID.fromString(value.toString());
        }
        if (targetId == null) {
            targetId = optionalUuidProperty(value, "getTargetId", "getId", "getFirstTarget");
        }
        if (targetId != null) {
            out.add(playerIds.getOrDefault(targetId, targetId.toString()));
        }
    }

    private Object optionalProperty(Object object, String... methodNames) {
        if (object == null) {
            return null;
        }
        for (String methodName : methodNames) {
            try {
                Method method = object.getClass().getMethod(methodName);
                return method.invoke(object);
            } catch (ReflectiveOperationException | RuntimeException ignored) {
            }
        }
        return null;
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
        Set<UUID> commandIds = commandIds(view);
        for (Map.Entry<UUID, PlayableObjectStats> entry : playable.getObjects().entrySet()) {
            UUID sourceId = entry.getKey();
            CardView card = findVisibleCard(view, sourceId);
            if (card == null) continue;
            boolean inCommand = commandIds.contains(sourceId);
            String category = playableCategory(card, handIds.contains(sourceId), inCommand);
            JsonObject item = new JsonObject();
            item.addProperty("sourceInstanceId", sourceId.toString());
            item.addProperty("sourceZone", handIds.contains(sourceId) ? "hand" : inCommand ? "command" : "battlefield");
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
                ability.addProperty("label", cleanText(i < labels.size() ? labels.get(i) : labelFor(actionType(card, handIds.contains(sourceId), inCommand), card.getName())));
                ability.addProperty("category", category);
                abilities.add(ability);
            }
            item.add("abilities", abilities);
            out.add(item);
        }
        return out;
    }

    private String playableCategory(CardView card, boolean inHand, boolean inCommand) {
        if (inHand && card.isLand()) return "play";
        if (inHand || inCommand) return "cast";
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

    private JsonObject multiAmountAction(GameRecord record, String playerId) {
        JsonObject action = action("xmage-choice-multi-amount", "choose_multi_amount", playerId, "Choose amounts", null, null, null);
        JsonObject template = new JsonObject();
        template.addProperty("type", "choose_multi_amount");
        if (record.promptEnvelope != null) {
            String promptId = string(record.promptEnvelope, "id", "");
            int messageId = integer(record.promptEnvelope, "messageId", -1);
            if (!promptId.isEmpty()) {
                action.addProperty("promptId", promptId);
                template.addProperty("promptId", promptId);
            }
            if (messageId >= 0) {
                action.addProperty("messageId", messageId);
                template.addProperty("messageId", messageId);
            }
            action.addProperty("required", bool(record.promptEnvelope, "required", true));
            action.addProperty("minChoices", integer(record.promptEnvelope, "minChoices", 1));
            action.addProperty("maxChoices", integer(record.promptEnvelope, "maxChoices", 1));
            JsonArray slots = array(record.promptEnvelope, "multiAmounts");
            if (slots.size() > 0) {
                action.add("multiAmounts", slots.deepCopy());
                template.add("multiAmounts", slots.deepCopy());
            }
        }
        action.addProperty("zoneContext", "prompt");
        action.addProperty("responseKind", "choose_multi_amount");
        action.add("commandTemplate", template);
        return action;
    }

    private JsonObject choiceAction(GameRecord record, String choiceId, String type, String playerId, String label) {
        JsonObject action = action("xmage-choice-" + choiceId, type, playerId, label, null, null, null);
        JsonObject template = new JsonObject();
        template.addProperty("type", type);
        if (record.promptEnvelope != null) {
            String promptId = string(record.promptEnvelope, "id", "");
            int messageId = integer(record.promptEnvelope, "messageId", -1);
            if (!promptId.isEmpty()) {
                action.addProperty("promptId", promptId);
                template.addProperty("promptId", promptId);
            }
            if (messageId >= 0) {
                action.addProperty("messageId", messageId);
                template.addProperty("messageId", messageId);
            }
            action.addProperty("required", bool(record.promptEnvelope, "required", true));
            action.addProperty("minChoices", integer(record.promptEnvelope, "minChoices", 1));
            action.addProperty("maxChoices", integer(record.promptEnvelope, "maxChoices", 1));
        }
        JsonArray targetIds = new JsonArray();
        targetIds.add(choiceId);
        addChoiceCommandFields(action, template, type, choiceId, targetIds);
        action.addProperty("zoneContext", "prompt");
        if (type != null) {
            action.addProperty("responseKind", type);
        }
        addPromptChoiceMetadata(record, choiceId, action);
        action.add("commandTemplate", template);
        return action;
    }

    private void addPromptChoiceMetadata(GameRecord record, String choiceId, JsonObject action) {
        JsonObject choice = promptChoiceById(record, choiceId);
        if (choice != null) {
            String label = string(choice, "label", "");
            if (!label.isEmpty()) {
                action.addProperty("cardName", label);
            }
            String cardInstanceId = string(choice, "cardInstanceId", "");
            if (!cardInstanceId.isEmpty()) {
                action.addProperty("cardInstanceId", cardInstanceId);
            }
        }
        JsonObject card = promptCardById(record, choiceId);
        if (card != null && card.has("card") && card.get("card").isJsonObject()) {
            JsonObject cardInfo = card.getAsJsonObject("card");
            String name = string(cardInfo, "name", "");
            if (!name.isEmpty()) {
                action.addProperty("cardName", name);
            }
            String typeLine = string(cardInfo, "typeLine", "");
            if (!typeLine.isEmpty()) {
                action.addProperty("typeLine", typeLine);
            }
            if (cardInfo.has("isBasicLand")) {
                action.addProperty("isBasicLand", bool(cardInfo, "isBasicLand", false));
            }
        }
    }

    private void addChoiceCommandFields(JsonObject action, JsonObject template, String type, String choiceId, JsonArray choiceIds) {
        if ("choose_target".equals(type)) {
            action.add("targetIds", choiceIds);
            action.add("validTargetIds", choiceIds.deepCopy());
            template.add("targetIds", choiceIds.deepCopy());
        } else if ("choose_card".equals(type) || "search_select".equals(type)) {
            action.add("cardInstanceIds", choiceIds);
            action.add("validCardInstanceIds", choiceIds.deepCopy());
            template.add("cardInstanceIds", choiceIds.deepCopy());
        } else if ("choose_mode".equals(type)) {
            action.add("modeIds", choiceIds);
            template.add("modeIds", choiceIds.deepCopy());
        } else if ("choose_ability".equals(type)) {
            action.addProperty("abilityId", choiceId);
            template.addProperty("abilityId", choiceId);
        } else if ("play_mana".equals(type)) {
            action.addProperty("manaType", choiceId);
            template.addProperty("manaType", choiceId);
        } else if ("choose_mana".equals(type)) {
            JsonArray manaTypes = new JsonArray();
            manaTypes.add(choiceId);
            action.add("manaTypes", manaTypes);
            template.add("manaTypes", manaTypes.deepCopy());
        } else if ("choose_player".equals(type)) {
            action.add("playerIds", choiceIds);
            action.add("validPlayerIds", choiceIds.deepCopy());
            template.add("playerIds", choiceIds.deepCopy());
        } else if ("choose_pile".equals(type)) {
            try {
                int pile = Integer.parseInt(choiceId);
                action.addProperty("pile", pile);
                template.addProperty("pile", pile);
            } catch (NumberFormatException ignored) {
                action.add("choiceIds", choiceIds);
                template.add("choiceIds", choiceIds.deepCopy());
            }
        } else if ("choose_amount".equals(type) || "play_x_mana".equals(type)) {
            try {
                action.addProperty("amount", Integer.parseInt(choiceId));
                template.addProperty("amount", Integer.parseInt(choiceId));
            } catch (NumberFormatException ignored) {
                action.addProperty("amount", choiceId);
                template.addProperty("amount", choiceId);
            }
        } else if ("choose_multi_amount".equals(type)) {
            JsonArray amounts = new JsonArray();
            try {
                amounts.add(Integer.parseInt(choiceId));
            } catch (NumberFormatException ignored) {
                amounts.add(choiceId);
            }
            action.add("amounts", amounts);
            template.add("amounts", amounts.deepCopy());
        } else if ("answer_yes_no".equals(type)) {
            boolean confirmed = !"false".equalsIgnoreCase(choiceId);
            action.addProperty("confirmed", confirmed);
            template.addProperty("confirmed", confirmed);
        } else if ("order_items".equals(type) || "order_triggers".equals(type)) {
            action.add("orderedIds", choiceIds);
            template.add("orderedIds", choiceIds.deepCopy());
        } else {
            action.add("choiceIds", choiceIds);
            template.add("choiceIds", choiceIds.deepCopy());
        }
    }

    private String promptActionType(GameRecord record) {
        if (record.promptEnvelope == null) {
            return "resolve_choice";
        }
        String responseKind = string(record.promptEnvelope, "responseKind", "resolve_choice");
        if ("target".equals(responseKind)) return "choose_target";
        if ("card".equals(responseKind)) return "choose_card";
        if ("player".equals(responseKind)) return "choose_player";
        if ("ability".equals(responseKind)) return "choose_ability";
        if ("mode".equals(responseKind)) return "choose_mode";
        if ("pile".equals(responseKind)) return "choose_pile";
        if ("amount".equals(responseKind)) return "choose_amount";
        if ("multi_amount".equals(responseKind)) return "choose_multi_amount";
        if ("mana".equals(responseKind)) return "play_mana";
        if ("x_mana".equals(responseKind)) return "play_x_mana";
        if ("order".equals(responseKind)) return "order_items";
        if ("confirmation".equals(responseKind)) return "answer_yes_no";
        if ("search".equals(responseKind)) return "search_select";
        if ("commander_replacement".equals(responseKind)) return "commander_replacement";
        if ("pay_cost".equals(responseKind)) return "pay_cost";
        return responseKind;
    }

    private String labelForChoice(GameRecord record, Map<UUID, String> playerIds, String choiceId) {
        boolean startingPlayerPrompt = isStartingPlayerPrompt(record);
        if (startingPlayerPrompt && isUuid(choiceId)) {
            UUID id = UUID.fromString(choiceId);
            String externalId = playerIds.get(id);
            if (record.humanExternalId.equals(externalId)) {
                return record.humanName + " starts";
            }
            if (record.aiExternalId.equals(externalId)) {
                return record.aiName + " starts";
            }
        }
        JsonObject promptChoice = promptChoiceById(record, choiceId);
        if (promptChoice != null) {
            String label = string(promptChoice, "label", "");
            if (!label.isEmpty() && !label.equals(choiceId)) {
                boolean bottomPrompt = record.promptText != null && record.promptText.toLowerCase().contains("bottom");
                return (bottomPrompt ? "Bottom " : "Choose ") + label;
            }
        }
        if (isUuid(choiceId)) {
            UUID id = UUID.fromString(choiceId);
            CardView card = record.latestView == null ? null : findVisibleCard(record.latestView, id);
            if (card != null) {
                boolean bottomPrompt = record.promptText != null && record.promptText.toLowerCase().contains("bottom");
                return (bottomPrompt ? "Bottom " : "Choose ") + card.getName();
            }
            String externalId = playerIds.get(id);
            if (record.humanExternalId.equals(externalId)) {
                return startingPlayerPrompt ? record.humanName + " starts" : "Choose " + record.humanName;
            }
            if (record.aiExternalId.equals(externalId)) {
                return startingPlayerPrompt ? record.aiName + " starts" : "Choose " + record.aiName;
            }
        }
        return "Choose " + choiceId;
    }

    private boolean isStartingPlayerPrompt(GameRecord record) {
        if (record == null || record.promptEnvelope == null) {
            return false;
        }
        String promptText = record.promptText == null ? "" : record.promptText.toLowerCase();
        String promptMessage = string(record.promptEnvelope, "message", "").toLowerCase();
        if (promptText.contains("starting player") || promptMessage.contains("starting player")) {
            return true;
        }
        String method = string(record.promptEnvelope, "method", "");
        String responseKind = string(record.promptEnvelope, "responseKind", "");
        return "GAME_TARGET".equals(method)
                && "player".equals(responseKind)
                && record.latestView != null
                && record.latestView.getTurn() <= 1;
    }

    private JsonObject promptChoiceById(GameRecord record, String choiceId) {
        if (record == null || record.promptEnvelope == null || !record.promptEnvelope.has("choices")) {
            return null;
        }
        for (JsonElement element : record.promptEnvelope.getAsJsonArray("choices")) {
            if (!element.isJsonObject()) continue;
            JsonObject choice = element.getAsJsonObject();
            if (choiceId.equals(string(choice, "id", ""))) {
                return choice;
            }
        }
        return null;
    }

    private JsonObject promptCardById(GameRecord record, String choiceId) {
        if (record == null || record.promptEnvelope == null || !record.promptEnvelope.has("cards")) {
            return null;
        }
        for (JsonElement element : record.promptEnvelope.getAsJsonArray("cards")) {
            if (!element.isJsonObject()) continue;
            JsonObject card = element.getAsJsonObject();
            if (choiceId.equals(string(card, "instanceId", ""))) {
                return card;
            }
        }
        return null;
    }

    private String actionType(CardView card, boolean inHand, boolean inCommand) {
        return actionType(card, inHand, inCommand, true);
    }

    private String actionType(CardView card, boolean inHand, boolean inCommand, boolean landManaDefault) {
        if (inHand && card.isLand()) {
            return "play_land";
        }
        if (inHand || inCommand) {
            return "cast_spell";
        }
        if (landManaDefault && card.isLand()) {
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

    private ManaType manaTypeFromRequiredSymbol(String gameId, String symbol) {
        String normalized = symbol == null ? "" : symbol.replace("{", "").replace("}", "").trim().toUpperCase();
        if (!"W".equals(normalized)
                && !"U".equals(normalized)
                && !"B".equals(normalized)
                && !"R".equals(normalized)
                && !"G".equals(normalized)
                && !"C".equals(normalized)) {
            throw new ActionNoLongerLegalException(gameId, "Missing explicit mana symbol W/U/B/R/G/C");
        }
        return manaTypeFromSymbol(normalized);
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

    private int parseCommanderTax(CardView card) {
        if (card.getRules() == null) return 0;
        for (String rule : card.getRules()) {
            String cleanRule = cleanText(rule).toLowerCase();
            
            // 1. Explicit tax amount, e.g. "commander tax: {2}" or "commander tax: 2"
            if (cleanRule.contains("commander tax")) {
                java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("commander tax:?\\s*\\{?(\\d+)\\}?");
                java.util.regex.Matcher matcher = pattern.matcher(cleanRule);
                if (matcher.find()) {
                    return Integer.parseInt(matcher.group(1));
                }
            }
            
            // 2. Cast count (to be multiplied by 2)
            // e.g. "casts: 1", "commander casts: 1", "casts from command zone: 1", "played from command zone: 1"
            java.util.regex.Pattern castPattern = java.util.regex.Pattern.compile(
                "(?:commander\\s+casts|casts\\s+from\\s+(?:the\\s+)?command\\s+zone|played\\s+from\\s+(?:the\\s+)?command\\s+zone|casts|number\\s+of\\s+(?:times\\s+)?cast(?:s)?)\\s*[:\\s]\\s*(\\d+)"
            );
            java.util.regex.Matcher matcher = castPattern.matcher(cleanRule);
            if (matcher.find()) {
                return Integer.parseInt(matcher.group(1)) * 2;
            }

            // e.g. "cast 1 times", "played 1 times"
            java.util.regex.Pattern castPattern2 = java.util.regex.Pattern.compile(
                "(?:cast|played)\\s+(\\d+)\\s+time"
            );
            java.util.regex.Matcher matcher2 = castPattern2.matcher(cleanRule);
            if (matcher2.find()) {
                return Integer.parseInt(matcher2.group(1)) * 2;
            }

            // e.g. "1 time played from the command zone"
            java.util.regex.Pattern castPattern3 = java.util.regex.Pattern.compile(
                "(\\d+)\\s+time(?:s)?\\s+played\\s+from\\s+(?:the\\s+)?command\\s+zone"
            );
            java.util.regex.Matcher matcher3 = castPattern3.matcher(cleanRule);
            if (matcher3.find()) {
                return Integer.parseInt(matcher3.group(1)) * 2;
            }
        }
        return 0;
    }

    private int playerCommanderTax(PlayerView player, GameView view) {
        int maxTax = 0;
        for (CommandObjectView command : player.getCommandObjectList()) {
            if (command instanceof CardView) {
                maxTax = Math.max(maxTax, parseCommanderTax((CardView) command));
            }
        }
        for (CardView card : player.getBattlefield().values()) {
            maxTax = Math.max(maxTax, parseCommanderTax(card));
        }
        for (CardView card : player.getGraveyard().values()) {
            maxTax = Math.max(maxTax, parseCommanderTax(card));
        }
        for (CardView card : player.getExile().values()) {
            maxTax = Math.max(maxTax, parseCommanderTax(card));
        }
        if (player.getPlayerId().equals(view.getMyPlayer().getPlayerId())) {
            for (CardView card : view.getMyHand().values()) {
                maxTax = Math.max(maxTax, parseCommanderTax(card));
            }
        }
        return maxTax;
    }

    private JsonArray players(GameRecord record, GameView view, Map<UUID, String> playerIds) {
        // Collect commander damage maps: recipientExternalId -> (attackerExternalId -> damageAmount)
        Map<String, Map<String, Integer>> receivedDamage = new HashMap<>();
        for (String id : playerIds.values()) {
            receivedDamage.put(id, new HashMap<>());
        }

        // Scan all cards for each player to find their commander damage logs
        for (PlayerView player : view.getPlayers()) {
            String attackerExternalId = playerIds.get(player.getPlayerId());
            if (attackerExternalId == null) continue;

            List<CardView> cardsToCheck = new java.util.ArrayList<>();
            for (CommandObjectView command : player.getCommandObjectList()) {
                if (command instanceof CardView) {
                    cardsToCheck.add((CardView) command);
                }
            }
            cardsToCheck.addAll(player.getBattlefield().values());
            cardsToCheck.addAll(player.getGraveyard().values());
            cardsToCheck.addAll(player.getExile().values());

            if (player.getPlayerId().equals(view.getMyPlayer().getPlayerId())) {
                cardsToCheck.addAll(view.getMyHand().values());
            }

            for (CardView card : cardsToCheck) {
                if (card.getRules() == null) continue;
                for (String rule : card.getRules()) {
                    String cleanRule = cleanText(rule).toLowerCase();
                    int damage = -1;
                    String targetPlayerName = null;

                    // Match pattern: "did/dealt (\d+) combat/commander damage to (?:player )?(.+)"
                    // e.g. "did 5 combat damage to player human", "dealt 5 combat damage to human"
                    java.util.regex.Pattern pattern1 = java.util.regex.Pattern.compile(
                        "(?:did|dealt|deals|has\\s+dealt)\\s+(\\d+)\\s+(?:combat|commander)\\s+damage\\s+to\\s+(?:player\\s+)?([^.]+)"
                    );
                    java.util.regex.Matcher matcher1 = pattern1.matcher(cleanRule);
                    if (matcher1.find()) {
                        damage = Integer.parseInt(matcher1.group(1));
                        targetPlayerName = matcher1.group(2).trim();
                    }

                    // Match pattern: "(\d+) (?:combat|commander) damage to (?:player )?(.+)"
                    // e.g. "5 commander damage to player human"
                    if (damage == -1) {
                        java.util.regex.Pattern pattern2 = java.util.regex.Pattern.compile(
                            "(\\d+)\\s+(?:combat|commander)\\s+damage\\s+to\\s+(?:player\\s+)?([^.]+)"
                        );
                        java.util.regex.Matcher matcher2 = pattern2.matcher(cleanRule);
                        if (matcher2.find()) {
                            damage = Integer.parseInt(matcher2.group(1));
                            targetPlayerName = matcher2.group(2).trim();
                        }
                    }

                    // Match pattern: "(?:combat\\s+)?damage\\s+dealt\\s+(?:by\\s+commander\\s+)?to\\s+([^:]+):\\s*(\\d+)"
                    // e.g. "commander damage dealt to human: 5", "combat damage dealt by commander to human: 5"
                    if (damage == -1) {
                        java.util.regex.Pattern pattern3 = java.util.regex.Pattern.compile(
                            "(?:combat\\s+)?damage\\s+dealt\\s+(?:by\\s+commander\\s+)?to\\s+([^:]+):\\s*(\\d+)"
                        );
                        java.util.regex.Matcher matcher3 = pattern3.matcher(cleanRule);
                        if (matcher3.find()) {
                            targetPlayerName = matcher3.group(1).trim();
                            damage = Integer.parseInt(matcher3.group(2));
                        }
                    }

                    // Match pattern: "commander\\s+combat\\s+damage\\s+to\\s+([^:]+):\\s*(\\d+)"
                    // e.g. "commander combat damage to human: 5"
                    if (damage == -1) {
                        java.util.regex.Pattern pattern4 = java.util.regex.Pattern.compile(
                            "commander\\s+combat\\s+damage\\s+to\\s+([^:]+):\\s*(\\d+)"
                        );
                        java.util.regex.Matcher matcher4 = pattern4.matcher(cleanRule);
                        if (matcher4.find()) {
                            targetPlayerName = matcher4.group(1).trim();
                            damage = Integer.parseInt(matcher4.group(2));
                        }
                    }

                    if (damage >= 0 && targetPlayerName != null) {
                        if (targetPlayerName.endsWith(".")) {
                            targetPlayerName = targetPlayerName.substring(0, targetPlayerName.length() - 1).trim();
                        }

                        for (PlayerView p : view.getPlayers()) {
                            String name = p.getName().toLowerCase();
                            if (name.equals(targetPlayerName) || targetPlayerName.contains(name) || name.contains(targetPlayerName)) {
                                String recipientExternalId = playerIds.get(p.getPlayerId());
                                if (recipientExternalId != null) {
                                    receivedDamage.get(recipientExternalId).put(attackerExternalId, damage);
                                }
                                break;
                            }
                        }
                    }
                }
            }
        }

        JsonArray players = new JsonArray();
        for (PlayerView player : view.getPlayers()) {
            JsonObject out = new JsonObject();
            String externalId = playerIds.get(player.getPlayerId());
            out.addProperty("playerId", externalId);
            out.addProperty("displayName", player.getName());
            out.addProperty("life", player.getLife());
            out.addProperty("poison", counterValue(player, "poison"));
            out.addProperty("commanderTax", playerCommanderTax(player, view));
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
            Map<String, Integer> attackerDamage = receivedDamage.get(externalId);
            for (String id : playerIds.values()) {
                int dmg = (attackerDamage != null && attackerDamage.containsKey(id)) ? attackerDamage.get(id) : 0;
                commanderDamage.addProperty(id, dmg);
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
            zoneCard.addProperty("summoningSickness", card.hasSummoningSickness());
            zoneCard.addProperty("isCreaturePermanent", card.isCreature());
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
        out.add("cardIcons", cardIcons(card));
        JsonObject counters = cardCounters(card);
        if (counters.size() > 0) {
            out.add("counters", counters);
        }
        return out;
    }

    private JsonObject cardCounters(CardView card) {
        JsonObject out = new JsonObject();
        if (card == null || card.getCounters() == null || card.getCounters().isEmpty()) {
            return out;
        }
        for (Object counter : card.getCounters()) {
            String name = counterName(counter);
            int count = counterCount(counter);
            if (!name.isEmpty() && count > 0) {
                out.addProperty(name, count);
            }
        }
        return out;
    }

    private String counterName(Object counter) {
        Object value = invokeNoArg(counter, "getName");
        return value == null ? "" : cleanText(value.toString());
    }

    private int counterCount(Object counter) {
        Object value = invokeNoArg(counter, "getCount");
        if (value instanceof Number) {
            return ((Number) value).intValue();
        }
        try {
            return value == null ? 0 : Integer.parseInt(value.toString());
        } catch (NumberFormatException ignored) {
            return 0;
        }
    }

    private Object invokeNoArg(Object target, String methodName) {
        if (target == null) {
            return null;
        }
        try {
            Method method = target.getClass().getMethod(methodName);
            return method.invoke(target);
        } catch (Exception ignored) {
            return null;
        }
    }

    private JsonArray cardIcons(CardView card) {
        JsonArray icons = new JsonArray();
        if (card.getCardIcons() == null || card.getCardIcons().isEmpty()) {
            return icons;
        }
        for (CardIcon icon : card.getCardIcons()) {
            if (icon == null || icon.getIconType() == null) {
                continue;
            }
            JsonObject out = new JsonObject();
            out.addProperty("iconType", icon.getIconType().name());
            out.addProperty("resourceName", icon.getIconType().getResourceName());
            out.addProperty("category", icon.getIconType().getCategory().name());
            out.addProperty("text", cleanText(icon.getText()));
            out.addProperty("hint", cleanText(icon.getHint()));
            icons.add(out);
        }
        return icons;
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

    private boolean isOpeningSnapshotReady(GameRecord record, String humanCommanderName) {
        GameView view = record.latestView;
        if (view == null) {
            return false;
        }
        if (hasHumanOpeningPrompt(record)) {
            return true;
        }
        if (!hasHumanCommandZoneCommander(record, view, humanCommanderName)) {
            return false;
        }
        if (isMulliganPrompt(record)) {
            return true;
        }
        return view.getMyHand() != null && !view.getMyHand().isEmpty();
    }

    private boolean hasHumanOpeningPrompt(GameRecord record) {
        if (record == null || record.promptEnvelope == null) {
            return false;
        }
        String playerId = string(record.promptEnvelope, "playerId", "");
        if (!playerId.isEmpty() && !record.humanExternalId.equals(playerId)) {
            return false;
        }
        return isActionablePrompt(record.promptEnvelope);
    }

    private boolean hasHumanCommandZoneCommander(GameRecord record, GameView view, String humanCommanderName) {
        if (humanCommanderName == null || humanCommanderName.isBlank()) {
            return hasCommandZoneObjects(view);
        }
        for (PlayerView player : view.getPlayers()) {
            if (record.humanXmagePlayerId != null && !player.getPlayerId().equals(record.humanXmagePlayerId)) {
                continue;
            }
            for (CommandObjectView command : player.getCommandObjectList()) {
                if (command instanceof CardView && humanCommanderName.equals(((CardView) command).getName())) {
                    return true;
                }
            }
        }
        return false;
    }

    private boolean hasCommandZoneObjects(GameView view) {
        for (PlayerView player : view.getPlayers()) {
            if (!player.getCommandObjectList().isEmpty()) {
                return true;
            }
        }
        return false;
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
        return health(true);
    }

    private JsonObject passiveHealth() {
        return health(false);
    }

    private boolean fixturesEnabled() {
        String nodeEnv = env("NODE_ENV", "");
        return "true".equalsIgnoreCase(env("ENABLE_XMAGE_FIXTURES", "false"))
                && !nodeEnv.isBlank()
                && !"production".equalsIgnoreCase(nodeEnv);
    }

    private JsonObject createCommanderFixtureGame(JsonObject fixture) throws Exception {
        FixtureManagerProvider provider = fixtureManagerProvider;
        if (provider == null) {
            return fixtureUnavailable(fixture);
        }

        JsonObject snapshot = createCommanderGame(object(fixture, "config", fixture));
        String gameId = string(snapshot, "id", "");
        GameRecord record = games.get(gameId);
        if (record == null || record.humanXmagePlayerId == null) {
            JsonObject blocked = fixtureUnavailable(fixture);
            blocked.addProperty("setupMethod", "bridge_snapshot_missing_player_identity");
            blocked.addProperty("blockedReason", "XMage started the game but the bridge did not receive a human player id to seed.");
            return blocked;
        }

        JsonArray preSeedOperations = new JsonArray();
        JsonArray preSeedErrors = new JsonArray();
        drainFixtureOpeningPrompts(gameId, preSeedOperations, preSeedErrors);

        long startRevision = record.bridgeRevision.get();
        int startCycle = record.latestCycle;
        JsonObject seedRequest = fixture.deepCopy();
        seedRequest.addProperty("gameId", gameId);
        seedRequest.addProperty("humanXmagePlayerId", record.humanXmagePlayerId.toString());
        UUID aiPlayerId = aiXmagePlayerId(record);
        if (aiPlayerId != null) {
            seedRequest.addProperty("aiXmagePlayerId", aiPlayerId.toString());
        }

        JsonObject report = seedFixtureInServerProcess(seedRequest, provider.get());
        array(report, "operationsApplied").addAll(preSeedOperations);
        array(report, "errors").addAll(preSeedErrors);
        if (!bool(report, "serverStateMutated", false)) {
            return report;
        }

        JsonArray proofCardNames = array(report, "proofCardNames");
        JsonObject seededSnapshot = waitForFixtureProofSnapshot(gameId, startRevision, startCycle, proofCardNames);
        boolean snapshotAdvanced = record.bridgeRevision.get() > startRevision || record.latestCycle > startCycle;
        boolean proofFound = snapshotContainsProof(seededSnapshot, proofCardNames);
        boolean directStateSeeded = snapshotAdvanced && proofFound;
        if (!directStateSeeded) {
            report.addProperty("error", "xmage_fixture_snapshot_proof_failed");
            report.addProperty("directStateSeeded", false);
            report.addProperty("bridgeRevision", record.bridgeRevision.get());
            report.addProperty("xmageCycle", record.latestCycle);
            report.addProperty("blockedReason", "The server Game object was mutated, but the bridge did not verify the seeded state in a refreshed real XMage GameView snapshot.");
            return report;
        }

        JsonObject harness = report.deepCopy();
        harness.remove("error");
        harness.addProperty("enabled", true);
        harness.addProperty("directStateSeeded", true);
        harness.addProperty("fallback", (String) null);
        harness.addProperty("reason", "Server-side XMage Game.cheat(...) mutation was verified by a refreshed real GameView snapshot.");
        harness.addProperty("source", "xmage-server-fixture-service");
        harness.addProperty("bridgeRevision", record.bridgeRevision.get());
        harness.addProperty("xmageCycle", record.latestCycle);
        seededSnapshot.add("fixtureHarness", harness);
        return seededSnapshot;
    }

    private JsonObject waitForFixtureProofSnapshot(String gameId, long startRevision, int startCycle, JsonArray proofCardNames) throws InterruptedException {
        JsonObject latest = waitForUpdatedSnapshot(gameId, "fixture_seed", startRevision, startCycle);
        if (snapshotContainsProof(latest, proofCardNames)) {
            return latest;
        }
        long deadline = System.currentTimeMillis() + 3000;
        while (System.currentTimeMillis() < deadline) {
            Thread.sleep(250);
            latest = snapshot(gameId);
            if (snapshotContainsProof(latest, proofCardNames)) {
                return latest;
            }
        }
        return latest;
    }

    private void drainFixtureOpeningPrompts(String gameId, JsonArray applied, JsonArray errors) {
        boolean startingChoiceAnswered = false;
        for (int attempt = 0; attempt < 8; attempt++) {
            try {
                JsonObject current = snapshot(gameId);
                JsonObject action = fixtureOpeningAction(current);
                if (action == null) {
                    if (attempt < 4 && "beginning".equals(string(current, "phase", "beginning"))) {
                        Thread.sleep(500);
                        continue;
                    }
                    return;
                }
                String type = string(action, "type", "opening_prompt");
                if (("choose_target".equals(type) || "choose_player".equals(type) || "resolve_choice".equals(type)) && startingChoiceAnswered) {
                    return;
                }
                submitCommand(gameId, commandFromLegalAction(gameId, current, action));
                applied.add("pre_seed_opening_prompt:" + type);
                if ("keep_hand".equals(type) || "mulligan".equals(type)) {
                    return;
                }
                if ("choose_target".equals(type) || "choose_player".equals(type) || "resolve_choice".equals(type)) {
                    startingChoiceAnswered = true;
                }
            } catch (Exception error) {
                errors.add("pre_seed_opening_prompt: " + error.getClass().getName() + ": " + error.getMessage());
                return;
            }
        }
        errors.add("pre_seed_opening_prompt: exhausted prompt drain attempts");
    }

    private JsonObject fixtureOpeningAction(JsonObject snapshot) {
        JsonArray actions = array(snapshot, "legalActions");
        JsonObject startingPlayer = findOpeningChoice(actions);
        if (startingPlayer != null) {
            return startingPlayer;
        }
        JsonObject keep = findAction(actions, "keep_hand", "");
        if (keep != null) {
            return keep;
        }
        JsonObject mulligan = findAction(actions, "mulligan", "");
        if (mulligan != null) {
            return mulligan;
        }
        return null;
    }

    private JsonObject findOpeningChoice(JsonArray actions) {
        for (JsonElement element : actions) {
            if (!element.isJsonObject()) {
                continue;
            }
            JsonObject action = element.getAsJsonObject();
            String type = string(action, "type", "");
            String label = string(action, "label", "").toLowerCase();
            if (
                    ("choose_target".equals(type) || "choose_player".equals(type) || "resolve_choice".equals(type))
                            && (label.contains("you start") || label.contains("tabletop") || label.contains("start"))
            ) {
                return action;
            }
        }
        return null;
    }

    private JsonObject findAction(JsonArray actions, String type, String labelContains) {
        for (JsonElement element : actions) {
            if (!element.isJsonObject()) {
                continue;
            }
            JsonObject action = element.getAsJsonObject();
            if (!type.equals(string(action, "type", ""))) {
                continue;
            }
            if (labelContains.isEmpty() || string(action, "label", "").toLowerCase().contains(labelContains.toLowerCase())) {
                return action;
            }
        }
        return null;
    }

    private JsonObject commandFromLegalAction(String gameId, JsonObject snapshot, JsonObject action) {
        JsonObject command = object(action, "commandTemplate", new JsonObject()).deepCopy();
        command.addProperty("type", string(action, "type", string(command, "type", "")));
        command.addProperty("gameId", gameId);
        command.addProperty("playerId", string(action, "playerId", string(command, "playerId", "human")));
        command.addProperty("expectedBridgeRevision", longInteger(snapshot, "bridgeRevision", -1L));
        copyIfPresent(action, command, "promptId");
        copyIfPresent(action, command, "messageId");
        copyIfPresent(action, command, "cardInstanceId");
        copyIfPresent(action, command, "sourceInstanceId");
        copyIfPresent(action, command, "abilityId");
        copyIfPresent(action, command, "targetIds");
        copyIfPresent(action, command, "cardInstanceIds");
        copyIfPresent(action, command, "choiceIds");
        copyIfPresent(action, command, "playerIds");
        copyIfPresent(action, command, "confirmed");
        copyIfPresent(action, command, "pay");
        copyIfPresent(action, command, "useCommandZone");
        return command;
    }

    private void copyIfPresent(JsonObject from, JsonObject to, String key) {
        if (from != null && from.has(key) && !from.get(key).isJsonNull()) {
            to.add(key, from.get(key));
        }
    }

    private JsonObject seedFixtureInServerProcess(JsonObject request, ManagerFactory managerFactory) {
        JsonObject report = fixtureReport(request);
        JsonArray attempted = array(report, "operationsAttempted");
        JsonArray applied = array(report, "operationsApplied");
        JsonArray unsupported = array(report, "unsupportedOperations");
        JsonArray errors = array(report, "errors");
        JsonArray proofCardNames = array(report, "proofCardNames");

        try {
            UUID gameId = UUID.fromString(string(request, "gameId", ""));
            UUID humanPlayerId = UUID.fromString(string(request, "humanXmagePlayerId", ""));
            GameController controller = waitForGameController(managerFactory, gameId);
            if (controller == null) {
                errors.add("GameController not found for " + gameId);
                report.addProperty("setupMethod", "game_controller_not_found");
                return report;
            }

            Game game = gameFromController(controller);
            Player human = game == null ? null : game.getPlayer(humanPlayerId);
            if (game == null || human == null) {
                errors.add("Game or human player not found in server process");
                report.addProperty("setupMethod", "game_or_player_not_found");
                return report;
            }

            synchronized (game) {
                JsonObject schema = object(request, "schema", object(object(request, "config"), "fixture"));
                String fixtureName = string(request, "fixtureName", string(schema, "name", "commander"));
                applyCommanderFixtureDefaults(fixtureName, schema);

                attempted.add("set_life");
                int startingLife = integer(object(request, "config"), "startingLife", 40);
                human.setLife(startingLife, game, null);
                applied.add("set_human_life");

                UUID aiPlayerId = parseUuid(string(request, "aiXmagePlayerId", ""));
                if (aiPlayerId != null && game.getPlayer(aiPlayerId) != null) {
                    game.getPlayer(aiPlayerId).setLife(startingLife, game, null);
                    applied.add("set_ai_life");
                }

                attempted.add("clear_hand_and_library");
                Map<Zone, String> reset = new LinkedHashMap<>();
                reset.put(Zone.HAND, "clear");
                reset.put(Zone.LIBRARY, "clear");
                game.cheat(humanPlayerId, reset);
                applied.add("clear_human_hand");
                applied.add("clear_human_library");

                List<Card> library = fixtureCards(humanPlayerId, array(schema, "humanLibraryTop"), proofCardNames, errors);
                List<Card> hand = fixtureCards(humanPlayerId, array(schema, "humanHand"), proofCardNames, errors);
                List<PutToBattlefieldInfo> battlefield = fixtureBattlefield(humanPlayerId, array(schema, "humanBattlefield"), proofCardNames, errors);
                List<Card> graveyard = fixtureCards(humanPlayerId, array(schema, "humanGraveyard"), proofCardNames, errors);
                List<Card> exile = fixtureCards(humanPlayerId, array(schema, "humanExile"), proofCardNames, errors);
                if (array(schema, "humanCommandZone").size() > 0) {
                    unsupported.add("humanCommandZone reseed: Commander game startup already owns command-zone commander placement");
                }

                attempted.add("game_cheat_human_zones");
                game.cheat(humanPlayerId, library, hand, battlefield, graveyard, Collections.emptyList(), exile);
                applied.add("seed_human_hand:" + hand.size());
                applied.add("seed_human_battlefield:" + battlefield.size());
                applied.add("seed_human_library:" + library.size());
                applied.add("seed_human_graveyard:" + graveyard.size());
                applied.add("seed_human_exile:" + exile.size());

                if (aiPlayerId != null && game.getPlayer(aiPlayerId) != null) {
                    List<PutToBattlefieldInfo> aiBattlefield = fixtureBattlefield(aiPlayerId, array(schema, "aiBattlefield"), proofCardNames, errors);
                    if (!aiBattlefield.isEmpty()) {
                        attempted.add("game_cheat_ai_battlefield");
                        game.cheat(aiPlayerId, Collections.emptyList(), Collections.emptyList(), aiBattlefield, Collections.emptyList(), Collections.emptyList(), Collections.emptyList());
                        applied.add("seed_ai_battlefield:" + aiBattlefield.size());
                    }
                }

                attempted.add("turn_priority");
                GameState state = game.getState();
                UUID activePlayerId = fixturePlayerId(schema, string(schema, "activePlayerId", "human"), humanPlayerId, aiPlayerId);
                UUID priorityPlayerId = fixturePlayerId(schema, string(schema, "priorityPlayerId", "human"), humanPlayerId, aiPlayerId);
                state.setActivePlayerId(activePlayerId);
                state.setPriorityPlayerId(priorityPlayerId);
                state.setTurnNum(integer(schema, "turn", 1));
                applied.add("set_active_player");
                applied.add("set_priority_player");
                applied.add("set_turn");
                seedFixtureCombat(fixtureName, game, humanPlayerId, aiPlayerId, applied, unsupported, errors);
                setFixturePhaseStep(game, state, schema, applied, unsupported, errors);

                game.applyEffects();
                invokePrivateNoArg(controller, "updateGame", errors);
                report.addProperty("serverStateMutated", true);
                report.addProperty("setupMethod", "in_server_game_cheat");
                report.addProperty("reason", "XMage server-side Game.cheat(...) mutated the real Game object under the Game monitor; bridge snapshot proof is still required.");
            }
        } catch (Exception error) {
            errors.add(error.getClass().getName() + ": " + error.getMessage());
            report.addProperty("setupMethod", "fixture_seed_exception");
        }
        return report;
    }

    private JsonObject fixtureReport(JsonObject request) {
        JsonObject body = new JsonObject();
        String fixtureName = string(request, "fixtureName", string(request, "scenario", "commander"));
        body.addProperty("error", "xmage_fixture_state_seeding_unavailable");
        body.addProperty("enabled", true);
        body.addProperty("fixtureName", fixtureName);
        body.addProperty("schemaVersion", integer(request, "schemaVersion", 1));
        body.addProperty("productionDisabled", true);
        body.addProperty("directStateSeeded", false);
        body.addProperty("serverStateMutated", false);
        body.addProperty("setupMethod", "in_server_fixture_service");
        body.addProperty("gameId", string(request, "gameId", ""));
        body.addProperty("source", "xmage-server-fixture-service");
        body.add("bridgeRevision", null);
        body.add("xmageCycle", null);
        body.add("operationsAttempted", new JsonArray());
        body.add("operationsApplied", new JsonArray());
        body.add("unsupportedOperations", new JsonArray());
        body.add("seededZones", new JsonArray());
        body.add("proofCardNames", new JsonArray());
        body.add("serverProcessEvidence", serverProcessEvidence());
        body.add("errors", new JsonArray());
        JsonObject safety = new JsonObject();
        safety.addProperty("devOnly", true);
        safety.addProperty("requiresEnableXmageFixtures", true);
        safety.addProperty("nodeEnv", env("NODE_ENV", ""));
        safety.addProperty("embeddedManagerFactory", fixtureManagerProvider != null);
        body.add("safetyMode", safety);
        return body;
    }

    private JsonObject serverProcessEvidence() {
        JsonObject evidence = new JsonObject();
        evidence.addProperty("processName", ManagementFactory.getRuntimeMXBean().getName());
        evidence.addProperty("gameControllerClassPresent", true);
        evidence.addProperty("gameCheatAvailable", true);
        evidence.addProperty("classPathContainsMageServer", System.getProperty("java.class.path", "").contains("mage-server"));
        evidence.addProperty("bridgeMode", fixtureManagerProvider == null ? "remote_session_client" : "embedded_server_same_jvm");
        return evidence;
    }

    private void setFixturePhaseStep(Game game, GameState state, JsonObject schema, JsonArray applied, JsonArray unsupported, JsonArray errors) {
        String phaseName = string(schema, "phase", "precombat-main");
        String stepName = string(schema, "step", phaseName);
        TurnPhase turnPhase = fixtureTurnPhase(phaseName);
        PhaseStep phaseStep = fixturePhaseStep(stepName);
        if (turnPhase == null) {
            unsupported.add("phase setter: unsupported fixture phase " + phaseName);
            return;
        }
        Phase phase = state.getTurn().getPhase(turnPhase);
        if (phase == null) {
            unsupported.add("phase setter: XMage turn did not expose phase " + turnPhase);
            return;
        }
        try {
            if (phaseStep != null) {
                phase.keepOnlyStep(phaseStep);
                Step requestedStep = stepFromPhase(phase, phaseStep);
                if (requestedStep != null) {
                    phase.setStep(requestedStep);
                    applied.add("set_step:" + phaseStep.name());
                } else {
                    unsupported.add("step setter: XMage phase did not expose step " + phaseStep.name());
                }
            }
            state.getTurn().setPhase(phase);
            game.getState().setActivePlayerId(state.getActivePlayerId());
            game.getState().setPriorityPlayerId(state.getPriorityPlayerId());
            applied.add("set_phase:" + turnPhase.name());
        } catch (Exception error) {
            errors.add("phase_step_fixture: " + error.getClass().getName() + ": " + error.getMessage());
            unsupported.add("phase/step exact setter failed");
        }
    }

    @SuppressWarnings("unchecked")
    private Step stepFromPhase(Phase phase, PhaseStep stepType) throws Exception {
        Step current = phase.getStep();
        if (current != null && current.getType() == stepType) {
            return current;
        }
        Field stepsField = Phase.class.getDeclaredField("steps");
        stepsField.setAccessible(true);
        Object value = stepsField.get(phase);
        if (value instanceof List<?>) {
            for (Object item : (List<?>) value) {
                if (item instanceof Step && ((Step) item).getType() == stepType) {
                    return (Step) item;
                }
            }
        }
        return null;
    }

    private TurnPhase fixtureTurnPhase(String value) {
        String normalized = fixtureEnumName(value);
        if (normalized.isEmpty()) {
            return null;
        }
        if ("MAIN".equals(normalized)) {
            normalized = "PRECOMBAT_MAIN";
        }
        if ("ENDING".equals(normalized)) {
            normalized = "END";
        }
        try {
            return TurnPhase.valueOf(normalized);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private PhaseStep fixturePhaseStep(String value) {
        String normalized = fixtureEnumName(value);
        if (normalized.isEmpty()) {
            return null;
        }
        if ("END".equals(normalized)) {
            normalized = "END_TURN";
        }
        try {
            return PhaseStep.valueOf(normalized);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private String fixtureEnumName(String value) {
        return value == null ? "" : value.trim().replace('-', '_').replace(' ', '_').toUpperCase();
    }

    private GameController waitForGameController(ManagerFactory managerFactory, UUID gameId) throws InterruptedException {
        long deadline = System.currentTimeMillis() + 10000;
        while (System.currentTimeMillis() < deadline) {
            GameController controller = managerFactory.gameManager().getGameController().get(gameId);
            if (controller != null) {
                return controller;
            }
            Thread.sleep(250);
        }
        return managerFactory.gameManager().getGameController().get(gameId);
    }

    private Game gameFromController(GameController controller) throws Exception {
        Field gameField = GameController.class.getDeclaredField("game");
        gameField.setAccessible(true);
        return (Game) gameField.get(controller);
    }

    private void invokePrivateNoArg(Object target, String methodName, JsonArray errors) {
        try {
            Method method = target.getClass().getDeclaredMethod(methodName);
            method.setAccessible(true);
            method.invoke(target);
        } catch (Exception error) {
            errors.add("Could not call GameController." + methodName + "(): " + error.getMessage());
        }
    }

    private void applyCommanderFixtureDefaults(String fixtureName, JsonObject schema) {
        if ("damage-assignment".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Plains");
            defaultBattlefield(schema, "humanBattlefield", "Defensive Formation", "Silvercoat Lion", "Savannah Lions", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            defaultBattlefield(schema, "aiBattlefield", "Metalwork Colossus");
            defaultString(schema, "phase", "combat");
            defaultString(schema, "step", "combat-damage");
            defaultString(schema, "activePlayerId", "ai-1");
            defaultString(schema, "priorityPlayerId", "human");
            schema.addProperty("turn", 1);
            return;
        }
        if ("blocker-flow".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Plains");
            defaultBattlefield(schema, "humanBattlefield", "Silvercoat Lion", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            defaultBattlefield(schema, "aiBattlefield", "Memnite");
            defaultString(schema, "phase", "combat");
            defaultString(schema, "step", "declare-blockers");
            defaultString(schema, "activePlayerId", "ai-1");
            defaultString(schema, "priorityPlayerId", "human");
            schema.addProperty("turn", 1);
            return;
        }
        if ("activated-ability-stack".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Plains");
            defaultBattlefield(schema, "humanBattlefield", "Seal of Cleansing", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            defaultBattlefield(schema, "aiBattlefield", "Sol Ring");
            schema.addProperty("turn", 1);
            return;
        }
        if ("prompt-mode".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Lavabrink Venturer");
            defaultBattlefield(schema, "humanBattlefield", "Plains", "Plains", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            defaultBattlefield(schema, "aiBattlefield", "Wastes");
            schema.addProperty("turn", 1);
            return;
        }
        if ("prompt-order".equals(fixtureName) || "prompt-variety-order".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Spirited Companion", "Plains");
            defaultBattlefield(schema, "humanBattlefield", "Soul Warden", "Plains", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            defaultBattlefield(schema, "aiBattlefield", "Wastes");
            schema.addProperty("turn", 1);
            return;
        }
        if ("prompt-amount".equals(fixtureName) || "prompt-variety-amount".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Wheel of Misfortune");
            defaultBattlefield(schema, "humanBattlefield", "Mountain", "Mountain", "Mountain");
            defaultCards(schema, "humanLibraryTop", "Mountain", "Mountain", "Mountain", "Mountain", "Mountain", "Mountain", "Mountain");
            defaultBattlefield(schema, "aiBattlefield", "Wastes");
            schema.addProperty("turn", 1);
            return;
        }
        if ("prompt-multi-amount".equals(fixtureName) || "prompt-variety-multi-amount".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Manamorphose");
            defaultBattlefield(schema, "humanBattlefield", "Mountain", "Mountain");
            defaultCards(schema, "humanLibraryTop", "Mountain");
            defaultBattlefield(schema, "aiBattlefield", "Wastes");
            schema.addProperty("turn", 1);
            return;
        }
        if ("prompt-pile".equals(fixtureName) || "prompt-variety-pile".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Fact or Fiction");
            defaultBattlefield(schema, "humanBattlefield", "Island", "Island", "Island", "Island");
            defaultCards(schema, "humanLibraryTop", "Island", "Island", "Island", "Island", "Island");
            defaultBattlefield(schema, "aiBattlefield", "Wastes");
            schema.addProperty("turn", 1);
            return;
        }
        if ("triggered-ability-stack".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Spirited Companion", "Plains");
            defaultBattlefield(schema, "humanBattlefield", "Plains", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            schema.addProperty("turn", 1);
            return;
        }
        if ("mana-rock".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Sol Ring");
            defaultBattlefield(schema, "humanBattlefield", "Plains", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            schema.addProperty("turn", 1);
            return;
        }
        if ("drag-cast-regression".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Plains", "Sol Ring", "Primal Might", "Frontier Siege", "Vandalblast");
            defaultBattlefield(schema, "humanBattlefield", "Plains", "Plains", "Mountain", "Forest");
            defaultCards(schema, "humanLibraryTop", "Plains", "Mountain", "Forest");
            defaultBattlefield(schema, "aiBattlefield", "Memnite");
            schema.addProperty("turn", 1);
            return;
        }
        if ("repeated-mulligan".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains");
            schema.addProperty("turn", 1);
            return;
        }
        if ("choose-card".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Faithless Looting");
            defaultBattlefield(schema, "humanBattlefield", "Mountain");
            defaultCards(schema, "humanLibraryTop", "Mountain", "Mountain");
            schema.addProperty("turn", 1);
            return;
        }
        if ("choose-player".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Sign in Blood");
            defaultBattlefield(schema, "humanBattlefield", "Swamp", "Swamp");
            defaultCards(schema, "humanLibraryTop", "Swamp", "Swamp");
            schema.addProperty("turn", 1);
            return;
        }
        if ("play-x-mana".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Blaze");
            defaultBattlefield(schema, "humanBattlefield", "Mountain", "Mountain", "Mountain");
            defaultCards(schema, "humanLibraryTop", "Mountain");
            defaultBattlefield(schema, "aiBattlefield", "Memnite");
            schema.addProperty("turn", 1);
            return;
        }
        if ("choose-mana".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Lotus Petal");
            defaultBattlefield(schema, "humanBattlefield", "Plains");
            defaultCards(schema, "humanLibraryTop", "Plains");
            schema.addProperty("turn", 1);
            return;
        }
        if ("generic-replacement".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Doom Blade");
            defaultBattlefield(schema, "humanBattlefield", "Swamp", "Swamp", "Leyline of the Void", "Rest in Peace");
            defaultCards(schema, "humanLibraryTop", "Swamp");
            defaultBattlefield(schema, "aiBattlefield", "Memnite");
            schema.addProperty("turn", 1);
            return;
        }
        if ("zone-movement".equals(fixtureName)) {
            defaultCards(schema, "humanHand", "Doom Blade", "Swords to Plowshares");
            defaultBattlefield(schema, "humanBattlefield", "Swamp", "Swamp", "Plains");
            defaultCards(schema, "humanLibraryTop", "Swamp");
            defaultBattlefield(schema, "aiBattlefield", "Memnite", "Memnite");
            schema.addProperty("turn", 1);
            return;
        }
        if (!"commander-gauntlet".equals(fixtureName)) {
            return;
        }
        defaultCards(schema, "humanHand", "Sol Ring", "Arcane Signet", "Fateful Absence", "Spirited Companion", "Plains", "Plains", "Evolving Wilds");
        defaultBattlefield(schema, "humanBattlefield", "Plains");
        defaultCards(schema, "humanLibraryTop", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains", "Plains");
        defaultBattlefield(schema, "aiBattlefield", "Sol Ring");
        schema.addProperty("turn", 1);
    }

    private void defaultCards(JsonObject schema, String key, String... names) {
        if (array(schema, key).size() > 0) {
            return;
        }
        JsonArray cards = new JsonArray();
        for (String name : names) {
            cards.add(name);
        }
        schema.add(key, cards);
    }

    private void defaultString(JsonObject schema, String key, String value) {
        if (!schema.has(key) || schema.get(key).isJsonNull() || string(schema, key, "").isEmpty()) {
            schema.addProperty(key, value);
        }
    }

    private UUID fixturePlayerId(JsonObject schema, String externalId, UUID humanPlayerId, UUID aiPlayerId) {
        if (externalId == null || externalId.isEmpty()) {
            return humanPlayerId;
        }
        JsonObject playerIds = object(schema, "playerIds");
        String humanExternalId = string(playerIds, "human", "human");
        if (externalId.equals(humanExternalId) || "human".equals(externalId)) {
            return humanPlayerId;
        }
        JsonArray aiExternalIds = array(playerIds, "ai");
        if (aiPlayerId != null) {
            for (JsonElement element : aiExternalIds) {
                if (element.isJsonPrimitive() && externalId.equals(element.getAsString())) {
                    return aiPlayerId;
                }
            }
            if ("ai".equals(externalId) || "ai-1".equals(externalId)) {
                return aiPlayerId;
            }
        }
        UUID parsed = parseUuid(externalId);
        if (parsed != null) {
            return parsed;
        }
        return humanPlayerId;
    }

    private void seedFixtureCombat(
            String fixtureName,
            Game game,
            UUID humanPlayerId,
            UUID aiPlayerId,
            JsonArray applied,
            JsonArray unsupported,
            JsonArray errors
    ) {
        if (!"blocker-flow".equals(fixtureName) && !"damage-assignment".equals(fixtureName)) {
            return;
        }
        if (aiPlayerId == null) {
            unsupported.add("combat seed: missing AI player id");
            return;
        }
        boolean damageAssignment = "damage-assignment".equals(fixtureName);
        UUID attackerControllerId = aiPlayerId;
        UUID defenderId = humanPlayerId;
        String attackerName = damageAssignment ? "Metalwork Colossus" : "Memnite";
        Permanent attacker = battlefieldPermanentByName(game, attackerControllerId, attackerName);
        Permanent blocker = damageAssignment ? null : battlefieldPermanentByName(game, humanPlayerId, "Silvercoat Lion");
        if (attacker == null || (!damageAssignment && blocker == null)) {
            unsupported.add("combat seed: missing seeded attacker or blocker permanent");
            return;
        }
        try {
            game.getState().getCombat().clear();
            game.getState().getCombat().setAttacker(attackerControllerId);
            game.getState().getCombat().setDefenders(game);
            boolean added = game.getState().getCombat().addAttackingCreature(attacker.getId(), game, defenderId);
            if (!added) {
                added = game.getState().getCombat().declareAttacker(attacker.getId(), defenderId, attackerControllerId, game);
            }
            if (!added) {
                added = game.getState().getCombat().addAttackerToCombat(attacker.getId(), defenderId, game);
            }
            if (added) {
                attacker.setTapped(true);
                applied.add("seed_combat_attacker:" + attacker.getName());
                if (damageAssignment) {
                    Permanent firstBlocker = battlefieldPermanentByName(game, humanPlayerId, "Silvercoat Lion");
                    Permanent secondBlocker = battlefieldPermanentByName(game, humanPlayerId, "Savannah Lions");
                    mage.game.combat.CombatGroup group = game.getState().getCombat().findGroup(attacker.getId());
                    if (group != null && firstBlocker != null && secondBlocker != null) {
                        group.addBlocker(firstBlocker.getId(), humanPlayerId, game);
                        group.addBlocker(secondBlocker.getId(), humanPlayerId, game);
                        applied.add("seed_combat_blocker:" + firstBlocker.getName());
                        applied.add("seed_combat_blocker:" + secondBlocker.getName());
                    } else {
                        unsupported.add("combat seed: missing damage-assignment blockers or combat group");
                    }
                }
            } else {
                unsupported.add("combat seed: XMage rejected seeded attacker");
            }
        } catch (Exception error) {
            errors.add("combat_seed: " + error.getClass().getName() + ": " + error.getMessage());
            unsupported.add("combat seed failed");
        }
    }

    private Permanent battlefieldPermanentByName(Game game, UUID controllerId, String name) {
        for (Permanent permanent : game.getBattlefield().getAllActivePermanents(controllerId)) {
            if (name.equalsIgnoreCase(permanent.getName())) {
                return permanent;
            }
        }
        return null;
    }

    private void defaultBattlefield(JsonObject schema, String key, String... names) {
        if (array(schema, key).size() > 0) {
            return;
        }
        JsonArray cards = new JsonArray();
        for (String name : names) {
            JsonObject card = new JsonObject();
            card.addProperty("cardName", name);
            card.addProperty("tapped", false);
            cards.add(card);
        }
        schema.add(key, cards);
    }

    private List<Card> fixtureCards(UUID ownerId, JsonArray specs, JsonArray proofCardNames, JsonArray errors) {
        List<Card> cards = new ArrayList<>();
        for (JsonElement spec : specs) {
            String cardName = fixtureCardName(spec);
            if (cardName.isBlank()) {
                continue;
            }
            Card card = createFixtureCard(ownerId, cardName, errors);
            if (card != null) {
                cards.add(card);
                proofCardNames.add(cardName);
            }
        }
        return cards;
    }

    private List<PutToBattlefieldInfo> fixtureBattlefield(UUID ownerId, JsonArray specs, JsonArray proofCardNames, JsonArray errors) {
        List<PutToBattlefieldInfo> cards = new ArrayList<>();
        for (JsonElement spec : specs) {
            String cardName = fixtureCardName(spec);
            if (cardName.isBlank()) {
                continue;
            }
            Card card = createFixtureCard(ownerId, cardName, errors);
            if (card != null) {
                boolean tapped = spec.isJsonObject() && bool(spec.getAsJsonObject(), "tapped", false);
                cards.add(new PutToBattlefieldInfo(card, tapped));
                proofCardNames.add(cardName);
            }
        }
        return cards;
    }

    private Card createFixtureCard(UUID ownerId, String cardName, JsonArray errors) {
        CardInfo info = CardRepository.instance.findPreferredCoreExpansionCard(cardName);
        if (info == null) {
            errors.add("XMage card not found: " + cardName);
            return null;
        }
        Card card = info.createCard();
        card.setOwnerId(ownerId);
        card.assignNewId();
        return card;
    }

    private String fixtureCardName(JsonElement spec) {
        if (spec == null || spec.isJsonNull()) {
            return "";
        }
        if (spec.isJsonPrimitive()) {
            return spec.getAsString();
        }
        if (spec.isJsonObject()) {
            JsonObject object = spec.getAsJsonObject();
            return string(object, "cardName", string(object, "name", ""));
        }
        return "";
    }

    private UUID aiXmagePlayerId(GameRecord record) {
        if (record == null || record.latestView == null) {
            return null;
        }
        for (PlayerView player : record.latestView.getPlayers()) {
            UUID playerId = player.getPlayerId();
            if (record.humanXmagePlayerId == null || !record.humanXmagePlayerId.equals(playerId)) {
                return playerId;
            }
        }
        return null;
    }

    private UUID parseUuid(String value) {
        try {
            return value == null || value.isBlank() ? null : UUID.fromString(value);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
    }

    private boolean snapshotContainsProof(JsonElement snapshot, JsonArray proofCardNames) {
        if (proofCardNames.size() == 0) {
            return false;
        }
        String snapshotJson = GSON.toJson(snapshot);
        for (JsonElement proof : proofCardNames) {
            if (snapshotJson.contains(proof.getAsString())) {
                return true;
            }
        }
        return false;
    }

    private JsonObject fixtureUnavailable(JsonObject fixture) {
        JsonObject body = new JsonObject();
        String fixtureName = string(fixture, "fixtureName", string(fixture, "scenario", "commander"));
        body.addProperty("error", "xmage_fixture_state_seeding_unavailable");
        body.addProperty("enabled", true);
        body.addProperty("fixtureName", fixtureName);
        body.addProperty("schemaVersion", integer(fixture, "schemaVersion", 1));
        body.addProperty("productionDisabled", true);
        body.addProperty("directStateSeeded", false);
        body.addProperty("setupMethod", "blocked_remote_session_client");
        body.add("gameId", null);
        body.addProperty("source", SOURCE);
        body.add("bridgeRevision", null);
        body.add("xmageCycle", null);
        body.add("seededZones", new JsonArray());
        body.addProperty(
                "blockedReason",
                "MagicMobileBridge runs as a mage.remote.Session client in a separate JVM from mage.server.game.GameController; the reachable Session API exposes cheatShow(gameId, playerId), but not Game.cheat(...) or zone/phase setters."
        );
        body.addProperty(
                "classProcessBoundary",
                "MagicMobileBridge JVM -> mage.remote.SessionImpl/JBoss remoting -> separate XMage server JVM owning mage.server.game.GameController and mage.game.Game."
        );
        body.addProperty(
                "nextImplementationStep",
                "Add a dev/test-only fixture service inside the XMage server process around GameController/Game.cheat(...), or embed the XMage server and bridge in one JVM before exposing direct state seeding."
        );
        return body;
    }

    private JsonObject health(boolean reconnectIfNeeded) {
        JsonObject health = new JsonObject();
        boolean ready = false;
        String reason = "XMage bridge starting.";
        try {
            if (reconnectIfNeeded) {
                ensureConnected(false);
            }
            ready = session != null && bridgeConnected && session.isConnected() && session.isServerReady();
            reason = ready
                    ? "XMage Java bridge connected to " + xmageHost + ":" + xmagePort + "."
                    : lastError == null || lastError.isEmpty() ? "XMage server is reachable but not ready." : lastError;
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

    private void pingIfConnected() {
        try {
            Session current = session;
            if (current != null && bridgeConnected && current.isConnected()) {
                current.ping();
            }
        } catch (Exception error) {
            bridgeConnected = false;
            lastError = "XMage bridge keepalive failed: " + (error.getMessage() == null ? error.toString() : error.getMessage());
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
        lastError = "XMage bridge disconnected";
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
                if (!session.joinGame(message.getGameId())) {
                    lastError = "XMage rejected game join for " + message.getGameId();
                }
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

    private void recordStartupOpeningPrompt(GameRecord record, String promptText, JsonObject promptEnvelope) {
        if (record == null || promptEnvelope == null || record.startupOpeningPrompts.size() >= 12) {
            return;
        }
        String method = string(promptEnvelope, "method", "");
        String promptId = string(promptEnvelope, "id", "");
        String message = cleanText(promptText == null || promptText.isEmpty() ? string(promptEnvelope, "message", "") : promptText);
        String signature = method + "|" + promptId + "|" + message;
        for (JsonElement element : record.startupOpeningPrompts) {
            if (element.isJsonObject() && signature.equals(string(element.getAsJsonObject(), "signature", ""))) {
                return;
            }
        }
        JsonObject item = new JsonObject();
        item.addProperty("signature", signature);
        item.addProperty("promptId", promptId);
        item.addProperty("method", method);
        item.addProperty("responseKind", string(promptEnvelope, "responseKind", ""));
        item.addProperty("message", message);
        item.addProperty("playerId", string(promptEnvelope, "playerId", ""));
        item.addProperty("bridgeRevision", record.bridgeRevision.get());
        item.addProperty("xmageCycle", record.latestCycle);
        record.startupOpeningPrompts.add(item);
    }

    private JsonObject promptEnvelope(ClientCallback callback, GameClientMessage message) {
        ClientCallbackMethod method = callback.getMethod();
        if (!isPromptMethod(method)) {
            return null;
        }
        JsonObject prompt = basePrompt(callback, responseKind(method, message.getMessage()), message.getMessage());
        int maxChoices = message.getMax();
        int inferredMaxChoices = inferredMaxChoices(message.getMessage());
        if (maxChoices <= 0 && inferredMaxChoices > 0) {
            maxChoices = inferredMaxChoices;
        }
        prompt.addProperty("required", message.isFlag());
        prompt.addProperty("minChoices", message.getMin());
        prompt.addProperty("maxChoices", maxChoices);

        JsonArray choices = new JsonArray();
        if (method == ClientCallbackMethod.GAME_ASK) {
            choices.add(promptChoice("true", "Yes", null));
            choices.add(promptChoice("false", "No", null));
            JsonObject confirmation = new JsonObject();
            confirmation.addProperty("yesLabel", "Yes");
            confirmation.addProperty("noLabel", "No");
            confirmation.addProperty("defaultValue", true);
            JsonObject yesCommand = new JsonObject();
            String responseType = commandTypeForResponseKind(string(prompt, "responseKind", "confirmation"));
            yesCommand.addProperty("type", responseType);
            yesCommand.addProperty("promptId", string(prompt, "id", ""));
            yesCommand.addProperty("confirmed", true);
            if ("pay_cost".equals(responseType)) {
                yesCommand.addProperty("pay", true);
            }
            JsonObject noCommand = new JsonObject();
            noCommand.addProperty("type", responseType);
            noCommand.addProperty("promptId", string(prompt, "id", ""));
            noCommand.addProperty("confirmed", false);
            if ("pay_cost".equals(responseType)) {
                noCommand.addProperty("pay", false);
            }
            confirmation.add("yesCommand", yesCommand);
            confirmation.add("noCommand", noCommand);
            prompt.add("confirmation", confirmation);
        } else if (method == ClientCallbackMethod.GAME_CHOOSE_PILE) {
            choices.add(promptChoice("1", "Pile 1", null));
            choices.add(promptChoice("2", "Pile 2", null));
            JsonArray piles = new JsonArray();
            addPile(piles, "1", "Pile 1", message.getCardsView1());
            addPile(piles, "2", "Pile 2", message.getCardsView2());
            prompt.add("piles", piles);
        } else if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && message.getChoice() != null) {
            addChoiceOptions(choices, message.getChoice());
            if (isKnownModeChoice(message.getChoice())) {
                setPromptResponseKind(prompt, "mode");
                prompt.add("modes", choices.deepCopy());
            } else if ("order".equals(string(prompt, "responseKind", ""))) {
                prompt.add("orderedItems", choices.deepCopy());
            } else {
                prompt.add("modes", choices.deepCopy());
            }
        } else if (method == ClientCallbackMethod.GAME_PLAY_MANA) {
            JsonArray manaChoices = new JsonArray();
            for (String symbol : manaChoicesForPrompt(callback.getObjectId(), message)) {
                String label = "Pay {" + symbol + "}";
                choices.add(promptChoice(symbol, label, null));
                JsonObject manaChoice = new JsonObject();
                manaChoice.addProperty("id", symbol);
                manaChoice.addProperty("label", label);
                manaChoice.addProperty("manaType", symbol);
                JsonObject responseCommand = new JsonObject();
                responseCommand.addProperty("type", "play_mana");
                responseCommand.addProperty("promptId", string(prompt, "id", ""));
                responseCommand.addProperty("manaType", symbol);
                manaChoice.add("responseCommand", responseCommand);
                manaChoices.add(manaChoice);
            }
            prompt.add("manaChoices", manaChoices);
        } else if (method == ClientCallbackMethod.GAME_GET_AMOUNT
                || method == ClientCallbackMethod.GAME_GET_MULTI_AMOUNT
                || method == ClientCallbackMethod.GAME_PLAY_XMANA) {
            int min = message.getMin();
            int max = message.getMax();
            int cappedMax = Math.min(max, min + 20);
            if (method == ClientCallbackMethod.GAME_GET_MULTI_AMOUNT) {
                prompt.addProperty("totalMin", min);
                prompt.addProperty("totalMax", max);
                JsonArray multiAmounts = new JsonArray();
                List<MultiAmountMessage> amountMessages = message.getMessages();
                if (amountMessages != null) {
                    for (int i = 0; i < amountMessages.size(); i++) {
                        MultiAmountMessage amountMessage = amountMessages.get(i);
                        JsonObject slot = new JsonObject();
                        slot.addProperty("id", Integer.toString(i));
                        slot.addProperty("label", cleanText(amountMessage.message));
                        slot.addProperty("min", amountMessage.min);
                        slot.addProperty("max", amountMessage.max);
                        slot.addProperty("defaultValue", amountMessage.defaultValue);
                        multiAmounts.add(slot);
                    }
                }
                prompt.add("multiAmounts", multiAmounts);
            }
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
            JsonArray players = new JsonArray();
            for (UUID target : message.getTargets()) {
                targetIds.add(target.toString());
                CardView card = message.getCardsView1() == null ? null : message.getCardsView1().get(target);
                if (card == null && message.getGameView() != null) {
                    card = findVisibleCard(message.getGameView(), target);
                }
                PlayerView player = message.getGameView() == null ? null : findPlayer(message.getGameView(), target);
                JsonObject choice = promptChoice(target.toString(), card == null ? player == null ? target.toString() : player.getName() : card.getName(), card == null ? null : target.toString());
                choices.add(choice);
                if (player == null) {
                    targets.add(choice.deepCopy());
                } else {
                    players.add(promptPlayer(player));
                }
            }
            prompt.add("targetIds", targetIds);
            if (targets.size() > 0) {
                prompt.add("targets", targets);
            }
            if (players.size() > 0) {
                prompt.add("players", players);
            }
            if (players.size() > 0 && targets.size() == 0) {
                prompt.addProperty("responseKind", "player");
                JsonObject responseCommand = object(prompt, "responseCommand", new JsonObject());
                responseCommand.addProperty("type", "choose_player");
                prompt.add("responseCommand", responseCommand);
            }
            if ("order".equals(string(prompt, "responseKind", ""))) {
                prompt.add("orderedItems", choices.deepCopy());
            }
        } else if (message.getCardsView1() != null && !message.getCardsView1().isEmpty()) {
            addCardChoices(choices, message.getCardsView1());
            prompt.add("cards", zoneCards(message.getCardsView1().values(), false));
        }

        if (choices.size() > 0) {
            prompt.add("choices", choices);
        }
        GameRecord record = games.get(callback.getObjectId().toString());
        normalizePlayerPromptChoices(prompt, record, message.getGameView());
        return prompt;
    }

    private void normalizePlayerPromptChoices(JsonObject prompt, GameRecord record, GameView view) {
        if (prompt == null || record == null || view == null) {
            return;
        }
        String responseKind = string(prompt, "responseKind", "");
        String message = string(prompt, "message", "").toLowerCase();
        if (!"player".equals(responseKind) && !message.contains("starting player")) {
            return;
        }
        Map<UUID, String> playerIds = externalPlayerIds(record, view);
        normalizePlayerChoiceArray(array(prompt, "choices"), record, playerIds);
        normalizePlayerChoiceArray(array(prompt, "players"), record, playerIds);
    }

    private void normalizePlayerChoiceArray(JsonArray choices, GameRecord record, Map<UUID, String> playerIds) {
        for (JsonElement element : choices) {
            if (!element.isJsonObject()) {
                continue;
            }
            JsonObject choice = element.getAsJsonObject();
            String choiceId = string(choice, "id", string(choice, "playerId", ""));
            String label = labelForChoice(record, playerIds, choiceId);
            if (!label.isEmpty() && !label.equals(choiceId)) {
                choice.addProperty("label", label);
            }
        }
    }

    private String[] manaChoicesForPrompt(UUID gameId, GameClientMessage message) {
        List<String> available = availableManaSymbols(gameId, message == null ? null : message.getGameView());
        if (available.isEmpty()) {
            return new String[0];
        }
        HashSet<String> symbols = new HashSet<>();
        String text = message == null || message.getMessage() == null ? "" : message.getMessage().toUpperCase();
        for (String symbol : new String[]{"W", "U", "B", "R", "G"}) {
            if (text.contains("{" + symbol + "}")) {
                symbols.add(symbol);
            }
        }
        if (text.matches(".*\\{(C|X|[0-9]+)\\}.*")) {
            symbols.addAll(available);
        }
        if (symbols.isEmpty()) {
            symbols.addAll(available);
        }
        return List.of("W", "U", "B", "R", "G", "C").stream()
                .filter(symbol -> symbols.contains(symbol) && available.contains(symbol))
                .toArray(String[]::new);
    }

    private List<String> availableManaSymbols(UUID gameId, GameView view) {
        if (gameId == null || view == null) {
            return List.of();
        }
        GameRecord record = games.get(gameId.toString());
        UUID humanId = record == null ? null : record.humanXmagePlayerId;
        Map<UUID, String> playerIds = record == null ? Map.of() : externalPlayerIds(record, view);
        for (PlayerView player : view.getPlayers()) {
            boolean isHuman = humanId != null
                    ? humanId.equals(player.getPlayerId())
                    : record != null && record.humanExternalId.equals(playerIds.get(player.getPlayerId()));
            if (!isHuman) {
                continue;
            }
            ManaPoolView pool = player.getManaPool();
            List<String> symbols = new ArrayList<>();
            if (pool.getWhite() > 0) symbols.add("W");
            if (pool.getBlue() > 0) symbols.add("U");
            if (pool.getBlack() > 0) symbols.add("B");
            if (pool.getRed() > 0) symbols.add("R");
            if (pool.getGreen() > 0) symbols.add("G");
            if (pool.getColorless() > 0) symbols.add("C");
            return symbols;
        }
        return List.of();
    }

    private int inferredMaxChoices(String message) {
        if (message == null) {
            return 0;
        }
        Matcher matcher = Pattern.compile("selected\\s+\\d+\\s+of\\s+(\\d+)", Pattern.CASE_INSENSITIVE).matcher(message);
        if (!matcher.find()) {
            return 0;
        }
        try {
            return Integer.parseInt(matcher.group(1));
        } catch (NumberFormatException ignored) {
            return 0;
        }
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
        responseCommand.addProperty("messageId", callback.getMessageId());
        prompt.add("responseCommand", responseCommand);
        return prompt;
    }

    private String commandTypeForResponseKind(String responseKind) {
        if ("target".equals(responseKind)) return "choose_target";
        if ("card".equals(responseKind)) return "choose_card";
        if ("player".equals(responseKind)) return "choose_player";
        if ("ability".equals(responseKind)) return "choose_ability";
        if ("mode".equals(responseKind)) return "choose_mode";
        if ("pile".equals(responseKind)) return "choose_pile";
        if ("amount".equals(responseKind)) return "choose_amount";
        if ("multi_amount".equals(responseKind)) return "choose_multi_amount";
        if ("mana".equals(responseKind)) return "play_mana";
        if ("x_mana".equals(responseKind)) return "play_x_mana";
        if ("order".equals(responseKind)) return "order_items";
        if ("confirmation".equals(responseKind)) return "answer_yes_no";
        if ("search".equals(responseKind)) return "search_select";
        if ("commander_replacement".equals(responseKind)) return "commander_replacement";
        if ("generic_replacement".equals(responseKind)) return "generic_replacement";
        if ("pay_cost".equals(responseKind)) return "pay_cost";
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

    private String responseKind(ClientCallbackMethod method, String message) {
        String normalizedMessage = message == null ? "" : message.toLowerCase();
        if (method == ClientCallbackMethod.GAME_TARGET && isTriggeredAbilityOrderTargetPrompt(normalizedMessage)) return "order";
        if (method == ClientCallbackMethod.GAME_TARGET) return "target";
        if (method == ClientCallbackMethod.GAME_SELECT && normalizedMessage.contains("starting player")) return "player";
        if (method == ClientCallbackMethod.GAME_SELECT) return normalizedMessage.contains("search") ? "search" : "card";
        if (method == ClientCallbackMethod.GAME_CHOOSE_ABILITY) return "ability";
        if (method == ClientCallbackMethod.GAME_CHOOSE_PILE) return "pile";
        if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && (normalizedMessage.contains("order") || normalizedMessage.contains("stack"))) {
            return "order";
        }
        if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && isKnownModeChoiceMessage(normalizedMessage)) {
            return "mode";
        }
        if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && normalizedMessage.contains("mode")) return "mode";
        if (method == ClientCallbackMethod.GAME_CHOOSE_CHOICE && (normalizedMessage.contains("replacement") || normalizedMessage.contains("apply"))) return "generic_replacement";
        if (method == ClientCallbackMethod.GAME_PLAY_MANA) return "mana";
        if (method == ClientCallbackMethod.GAME_PLAY_XMANA) return "x_mana";
        if (method == ClientCallbackMethod.GAME_GET_AMOUNT) return "amount";
        if (method == ClientCallbackMethod.GAME_GET_MULTI_AMOUNT) return "multi_amount";
        if (method == ClientCallbackMethod.GAME_OVER) return "game_over";
        if (method == ClientCallbackMethod.GAME_ASK && (normalizedMessage.contains("command zone")
                || (normalizedMessage.contains("commander") && normalizedMessage.contains("command")))) {
            return "commander_replacement";
        }
        if (method == ClientCallbackMethod.GAME_ASK && normalizedMessage.contains("pay") && normalizedMessage.contains("cost")) {
            return "pay_cost";
        }
        if (method == ClientCallbackMethod.GAME_ASK) return "confirmation";
        return "resolve_choice";
    }

    private boolean isKnownModeChoiceMessage(String normalizedMessage) {
        if (normalizedMessage == null || normalizedMessage.isEmpty()) {
            return false;
        }
        return normalizedMessage.contains("odd or even")
                || normalizedMessage.contains("even or odd")
                || normalizedMessage.contains("khans or dragons")
                || normalizedMessage.contains("dragons or khans")
                || normalizedMessage.contains("sultai or abzan")
                || normalizedMessage.contains("abzan or sultai")
                || normalizedMessage.contains("mardu or jeskai")
                || normalizedMessage.contains("jeskai or mardu")
                || normalizedMessage.contains("believe or doubt")
                || normalizedMessage.contains("doubt or believe");
    }

    private boolean isTriggeredAbilityOrderTargetPrompt(String normalizedMessage) {
        if (normalizedMessage == null || normalizedMessage.isEmpty()) {
            return false;
        }
        return normalizedMessage.contains("choose ability")
                || normalizedMessage.contains("choose triggered ability")
                || normalizedMessage.contains("pick triggered ability")
                || (normalizedMessage.contains("triggered ability") && normalizedMessage.contains("stack first"));
    }

    private boolean isKnownModeChoice(Choice choice) {
        if (choice == null || choice.getChoices() == null) {
            return false;
        }
        HashSet<String> normalized = new HashSet<>();
        for (String value : choice.getChoices()) {
            if (value != null) {
                normalized.add(value.toLowerCase());
            }
        }
        return containsPair(normalized, "odd", "even")
                || containsPair(normalized, "khans", "dragons")
                || containsPair(normalized, "sultai", "abzan")
                || containsPair(normalized, "mardu", "jeskai")
                || containsPair(normalized, "believe", "doubt");
    }

    private boolean containsPair(HashSet<String> values, String first, String second) {
        return values.contains(first) && values.contains(second);
    }

    private void setPromptResponseKind(JsonObject prompt, String responseKind) {
        prompt.addProperty("responseKind", responseKind);
        JsonObject responseCommand = object(prompt, "responseCommand", new JsonObject());
        responseCommand.addProperty("type", commandTypeForResponseKind(responseKind));
        prompt.add("responseCommand", responseCommand);
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

    private PlayerView findPlayer(GameView view, UUID id) {
        for (PlayerView player : view.getPlayers()) {
            if (player.getPlayerId().equals(id)) {
                return player;
            }
        }
        return null;
    }

    private JsonObject promptPlayer(PlayerView player) {
        JsonObject option = new JsonObject();
        option.addProperty("id", player.getPlayerId().toString());
        option.addProperty("label", player.getName());
        option.addProperty("playerId", player.getPlayerId().toString());
        option.addProperty("life", player.getLife());
        option.addProperty("selectable", true);
        JsonObject responseCommand = new JsonObject();
        responseCommand.addProperty("type", "choose_player");
        JsonArray playerIds = new JsonArray();
        playerIds.add(player.getPlayerId().toString());
        responseCommand.add("playerIds", playerIds);
        option.add("responseCommand", responseCommand);
        return option;
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
        GameRecord record = games.computeIfAbsent(gameId.toString(), id -> new GameRecord(gameId, "human", "ai-1", "TabletopPolish", "XMage AI"));
        record.latestView = view;
        record.latestCycle = view.getGameCycle();
        record.bridgeRevision.incrementAndGet();
        record.lastProgressAt = System.currentTimeMillis();
        JsonObject actionablePrompt = isActionablePrompt(promptEnvelope) ? promptEnvelope : null;
        recordStartupOpeningPrompt(record, promptText, promptEnvelope);
        record.promptText = actionablePrompt == null && promptEnvelope != null ? null : promptText == null ? null : cleanText(promptText);
        record.promptEnvelope = actionablePrompt;
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
            record.choicePrompt = choicePromptFromEnvelope(actionablePrompt);
        }
        try {
            JsonObject snap = snapshot(gameId.toString());
            pushSnapshotToGateway(gameId.toString(), snap);
        } catch (Exception ignored) {
        }
    }

    private boolean isActionablePrompt(JsonObject prompt) {
        if (prompt == null) {
            return false;
        }
        for (String key : new String[]{"choices", "cards", "targets", "players", "piles", "abilities", "modes", "amounts", "multiAmounts", "manaChoices", "orderedItems"}) {
            if (prompt.has(key) && prompt.get(key).isJsonArray() && prompt.getAsJsonArray(key).size() > 0) {
                return true;
            }
        }
        return prompt.has("confirmation") || "game_over".equals(string(prompt, "responseKind", ""));
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

    private JsonObject readOptionalJson(HttpExchange exchange) {
        try {
            return readJson(exchange);
        } catch (Exception ignored) {
            return new JsonObject();
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

    static String envValue(String name, String fallback) {
        return env(name, fallback);
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

    private static String sanitizedDisplayName(String rawName) {
        String trimmed = rawName == null ? "" : rawName.trim();
        if (trimmed.isEmpty()) {
            return "TabletopPolish";
        }
        return trimmed.length() > 24 ? trimmed.substring(0, 24) : trimmed;
    }

    private static int integer(JsonObject object, String name, int fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsInt() : fallback;
    }

    private static long longInteger(JsonObject object, String name, long fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsLong() : fallback;
    }

    private static boolean bool(JsonObject object, String name, boolean fallback) {
        JsonElement element = object == null ? null : object.get(name);
        return element != null && !element.isJsonNull() ? element.getAsBoolean() : fallback;
    }

    private static String joinNumbers(JsonArray values) {
        StringBuilder out = new StringBuilder();
        for (JsonElement value : values) {
            if (out.length() > 0) {
                out.append(' ');
            }
            out.append(value.getAsInt());
        }
        return out.toString();
    }

    private static String cleanText(String value) {
        if (value == null) {
            return "";
        }
        String text = value
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&amp;", "&")
                .replace("&nbsp;", " ")
                .replace("&quot;", "\"")
                .replace("&#39;", "'")
                .replace("&#x27;", "'");
        text = text.replaceAll("(?i)<br\\s*/?>", "\n");
        text = text.replaceAll("(?i)</p\\s*>", "\n");
        text = text.replaceAll("(?is)<hintstart>.*?(<hintend>|$)", "");
        text = text.replaceAll("(?i)</?hint(end|start)>", "");
        text = text.replaceAll("\\bICON_[A-Z_]+\\b", "");
        text = text.replaceAll("<[^>]+>", "");
        text = text.replaceAll("[ \\t\\r\\f]+", " ");
        text = text.replaceAll("\\n\\s*\\n+", "\n");
        return text.trim();
    }

    private static String slug(String value) {
        String normalized = value == null ? "zone" : value.toLowerCase().replaceAll("[^a-z0-9]+", "-");
        normalized = normalized.replaceAll("(^-+|-+$)", "");
        return normalized.isEmpty() ? "zone" : normalized;
    }

    public JsonObject obfuscateSnapshotForPlayer(JsonObject snapshot, String playerId) {
        if (snapshot == null) return null;
        JsonObject obfuscated = snapshot.deepCopy();
        
        if (obfuscated.has("players") && obfuscated.get("players").isJsonArray()) {
            JsonArray players = obfuscated.getAsJsonArray("players");
            for (JsonElement playerEl : players) {
                if (!playerEl.isJsonObject()) continue;
                JsonObject player = playerEl.getAsJsonObject();
                String extId = string(player, "playerId", "");
                if (!extId.equals(playerId)) {
                    if (player.has("zones") && player.get("zones").isJsonObject()) {
                        JsonObject zones = player.getAsJsonObject("zones");
                        if (zones.has("hand") && zones.get("hand").isJsonArray()) {
                            int handSize = zones.getAsJsonArray("hand").size();
                            zones.add("hand", hiddenCards(handSize, "hand-" + extId));
                        }
                    }
                }
                if (player.has("zones") && player.get("zones").isJsonObject()) {
                    JsonObject zones = player.getAsJsonObject("zones");
                    if (zones.has("library") && zones.get("library").isJsonArray()) {
                        int libSize = zones.getAsJsonArray("library").size();
                        zones.add("library", hiddenCards(libSize, "library-" + extId));
                    }
                }
            }
        }
        
        if (obfuscated.has("xmage") && obfuscated.get("xmage").isJsonObject()) {
            JsonObject xmage = obfuscated.getAsJsonObject("xmage");
            if (xmage.has("players") && xmage.get("players").isJsonArray()) {
                JsonArray players = xmage.getAsJsonArray("players");
                for (JsonElement playerEl : players) {
                    if (!playerEl.isJsonObject()) continue;
                    JsonObject player = playerEl.getAsJsonObject();
                    String extId = string(player, "playerId", "");
                    if (!extId.equals(playerId)) {
                        if (player.has("zones") && player.get("zones").isJsonObject()) {
                            JsonObject zones = player.getAsJsonObject("zones");
                            if (zones.has("hand") && zones.get("hand").isJsonArray()) {
                                int handSize = zones.getAsJsonArray("hand").size();
                                zones.add("hand", hiddenCards(handSize, "hand-" + extId));
                            }
                        }
                    }
                    if (player.has("zones") && player.get("zones").isJsonObject()) {
                        JsonObject zones = player.getAsJsonObject("zones");
                        if (zones.has("library") && zones.get("library").isJsonArray()) {
                            int libSize = zones.getAsJsonArray("library").size();
                            zones.add("library", hiddenCards(libSize, "library-" + extId));
                        }
                    }
                }
            }
        }
        return obfuscated;
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
        final String humanName;
        final String aiName;
        final AtomicLong bridgeRevision = new AtomicLong();
        volatile UUID humanXmagePlayerId;
        volatile GameView latestView;
        volatile int latestCycle = -1;
        volatile long lastProgressAt = System.currentTimeMillis();
        volatile String promptText;
        volatile JsonObject choicePrompt;
        volatile JsonObject promptEnvelope;
        final JsonArray startupOpeningPrompts = new JsonArray();

        GameRecord(UUID gameId, String humanExternalId, String aiExternalId, String humanName, String aiName) {
            this.gameId = gameId;
            this.humanExternalId = humanExternalId;
            this.aiExternalId = aiExternalId;
            this.humanName = humanName;
            this.aiName = aiName;
        }
    }

    interface FixtureManagerProvider {
        ManagerFactory get() throws Exception;
    }

    private static final class ActionNoLongerLegalException extends RuntimeException {
        final String gameId;

        ActionNoLongerLegalException(String gameId, String message) {
            super(message);
            this.gameId = gameId;
        }
    }
}
