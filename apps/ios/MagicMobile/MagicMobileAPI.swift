import Foundation

struct MagicMobileAPI {
    var baseURL: URL

    func health() async throws -> EngineHealth {
        try await get(route(web: "/api/engine/health", gateway: "/health"))
    }

    func cardCacheMetadata() async throws -> CardCacheMetadata {
        try await get("/api/card-cache")
    }

    func syncCardCache() async throws -> CardCacheMetadata {
        try await post("/api/card-cache", body: EmptyRequest())
    }

    func cardImageManifest() async throws -> CardImageManifestResponse {
        try await get("/api/card-cache/images")
    }

    func symbolManifest() async throws -> SymbolManifestResponse {
        try await get("/api/card-cache/symbols")
    }

    func generateDeck(seed: String, playerId: String) async throws -> GeneratedDeckResponse {
        try await post(
            "/api/decks/generate",
            body: GenerateDeckRequest(bracket: 3, seed: seed, playerId: playerId)
        )
    }

    func startCommanderGame(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty, humanDisplayName: String? = nil) async throws -> GameSnapshot {
        let config = commanderConfig(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty, humanDisplayName: humanDisplayName)
        return try await post(route(web: "/api/engine/commander", gateway: "/games/commander"), body: config)
    }

    func startCommanderStartup(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty, humanDisplayName: String? = nil) async throws -> CommanderStartupResponse {
        if usesDirectGatewayRoutes {
            let snapshot = try await startCommanderGame(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty, humanDisplayName: humanDisplayName)
            return CommanderStartupResponse(
                startupId: "direct-gateway:\(snapshot.id)",
                status: "ready",
                snapshot: snapshot,
                message: "XMage table ready.",
                error: nil
            )
        }
        return try await post("/api/engine/commander/start", body: commanderConfig(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty, humanDisplayName: humanDisplayName))
    }

    func commanderStartupStatus(startupId: String) async throws -> CommanderStartupResponse {
        try await get("/api/engine/commander/start/\(startupId)")
    }

    func startCommanderFixture(scenario: String = "commander-gauntlet") async throws -> GameSnapshot {
        let data = try await postData("/dev/xmage-fixtures/commander", body: CommanderFixtureRequest(scenario: scenario))
        return try Self.decodeCommanderFixtureSnapshot(from: data)
    }

    func snapshot(gameId: String) async throws -> GameSnapshot {
        try await get(gamePath(gameId: gameId))
    }

    func resumeGame(gameId: String, playerId: String = "human") async throws -> GameSnapshot {
        if usesDirectJavaBridgeRoutes {
            let snapshot: GameSnapshot = try await get(
                gamePath(gameId: gameId),
                queryItems: [URLQueryItem(name: "playerId", value: playerId)]
            )
            guard snapshot.players.contains(where: { $0.playerId == playerId }) else {
                throw MagicMobileError.server("This saved game belongs to a different XMage player.")
            }
            return snapshot
        }
        return try await post("\(gamePath(gameId: gameId))/resume", body: ResumeGameRequest(playerId: playerId))
    }

    func cleanupGame(gameId: String, reason: String = "ios-client-request") async throws -> CleanupGameResponse {
        try await delete(gamePath(gameId: gameId), body: CleanupGameRequest(reason: reason))
    }

    func protocolDebug(gameId: String) async throws -> XmageProtocolDebug {
        try await get("\(gamePath(gameId: gameId))/debug")
    }

    private func commanderConfig(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty, humanDisplayName: String?) -> CommanderGameConfig {
        let cleanDisplayName = Self.cleanPlayerName(humanDisplayName)
        let config = CommanderGameConfig(
            roomId: "ios-\(Int(Date().timeIntervalSince1970))",
            humanPlayerId: "human",
            humanDisplayName: cleanDisplayName,
            humanDeck: humanDeck,
            aiPlayers: [
                AiPlayerConfig(playerId: "ai-1", displayName: "AI", difficulty: difficulty, deck: aiDeck)
            ],
            startingLife: 40,
            commanderDamageEnabled: true
        )
        return config
    }

    static func cleanPlayerName(_ rawName: String?) -> String? {
        let trimmed = rawName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(24))
    }

    func submit(action: LegalAction, gameId: String, expectedBridgeRevision: Int?) async throws -> GameSnapshot {
        let command = try preparedCommand(for: action, gameId: gameId, expectedBridgeRevision: expectedBridgeRevision)
        return try await post(commandPath(gameId: gameId), body: command)
    }

    func preparedCommand(for action: LegalAction, gameId: String, expectedBridgeRevision: Int?) throws -> GameCommand {
        Self.withExpectedBridgeRevision(
            mergeCommandTemplate(try command(for: action, gameId: gameId), action: action, gameId: gameId),
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    func submit(command: GameCommand, gameId: String, expectedBridgeRevision: Int?) async throws -> GameSnapshot {
        try await post(
            commandPath(gameId: gameId),
            body: Self.withExpectedBridgeRevision(command, expectedBridgeRevision: expectedBridgeRevision)
        )
    }

    func command(for action: LegalAction, gameId: String) throws -> GameCommand {
        let promptId = promptId(for: action)
        let messageId = messageId(for: action)
        if ["keep_hand", "mulligan", "pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase", "concede", "undo_mana", "cancel_payment", "cancel_mana_payment"].contains(action.type) {
            return GameCommand(type: action.type, gameId: gameId, playerId: action.playerId)
        }

        if action.type == "play_land" || action.type == "cast_spell" || action.type == "play" {
            let cardInstanceId = templateString(action, "cardInstanceId") ?? action.cardInstanceId ?? action.sourceInstanceId
            let sourceInstanceId = templateString(action, "sourceInstanceId") ?? action.sourceInstanceId ?? cardInstanceId
            let cardName = templateString(action, "cardName") ?? action.cardName
            guard cardInstanceId != nil || sourceInstanceId != nil || cardName != nil else {
                throw missingActionData(action, "card id")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: cardInstanceId,
                sourceInstanceId: sourceInstanceId,
                abilityId: templateString(action, "abilityId") ?? action.abilityId,
                sourceZone: templateString(action, "sourceZone") ?? action.sourceZone,
                fromZone: templateString(action, "fromZone") ?? templateString(action, "sourceZone") ?? action.sourceZone,
                cardName: cardName
            )
        }

        if action.type == "tap_permanent" || action.type == "untap_permanent" {
            guard let cardInstanceId = templateString(action, "cardInstanceId") ?? action.cardInstanceId ?? action.sourceInstanceId else {
                throw missingActionData(action, "card id")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: cardInstanceId,
                sourceInstanceId: templateString(action, "sourceInstanceId") ?? action.sourceInstanceId
            )
        }

        if action.type == "declare_attackers" {
            let attackers = action.attackers ?? templateAttackers(action)
            let isFinishingCombat = templateBool(action, "combatComplete") == true
            guard let attackers, !attackers.isEmpty || isFinishingCombat else {
                throw missingActionData(action, "attacker pair")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: templateString(action, "cardInstanceId") ?? action.cardInstanceId,
                sourceInstanceId: templateString(action, "sourceInstanceId") ?? action.sourceInstanceId,
                attackers: attackers,
                combatComplete: templateBool(action, "combatComplete") ?? false
            )
        }

        if action.type == "declare_blockers" {
            let blockers = action.blockers ?? templateBlockers(action)
            let isFinishingCombat = templateBool(action, "combatComplete") == true
            guard let blockers, !blockers.isEmpty || isFinishingCombat else {
                throw missingActionData(action, "blocker pair")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: templateString(action, "cardInstanceId") ?? action.cardInstanceId,
                sourceInstanceId: templateString(action, "sourceInstanceId") ?? action.sourceInstanceId,
                blockers: blockers,
                combatComplete: templateBool(action, "combatComplete") ?? false
            )
        }

        if action.type == "resolve_choice" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                choiceIds: action.targetIds ?? []
            )
        }

        if action.type == "choose_target" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                targetIds: action.targetIds ?? action.validTargetIds ?? []
            )
        }

        if action.type == "choose_card" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                cardInstanceIds: action.cardInstanceIds ?? action.validCardInstanceIds ?? action.targetIds ?? action.validTargetIds ?? templateStringArray(action, "cardInstanceIds") ?? []
            )
        }

        if action.type == "choose_player" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                playerIds: action.playerIds ?? action.validPlayerIds ?? action.targetIds ?? action.validTargetIds ?? []
            )
        }

        if action.type == "choose_mode" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                modeIds: action.modeIds ?? action.targetIds ?? []
            )
        }

        if action.type == "play_mana" {
            guard let manaType = exactManaType(templateString(action, "manaType") ?? action.manaType ?? action.targetIds?.first ?? action.validTargetIds?.first ?? action.choiceIds?.first) else {
                throw missingActionData(action, "mana type")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                manaType: manaType
            )
        }

        if action.type == "choose_mana" {
            let manaTypes = exactManaTypes(action.manaTypes ?? templateStringArray(action, "manaTypes"))
                ?? exactManaType(templateString(action, "manaType") ?? action.manaType ?? action.choiceIds?.first ?? action.targetIds?.first ?? action.validTargetIds?.first).map { [$0] }
            guard let manaTypes, !manaTypes.isEmpty else {
                throw missingActionData(action, "mana choice")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                manaTypes: manaTypes
            )
        }

        if action.type == "choose_ability" {
            guard let abilityId = action.abilityId ?? templateString(action, "abilityId") ?? action.targetIds?.first ?? action.validTargetIds?.first else {
                throw missingActionData(action, "ability id")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                abilityId: abilityId,
                promptId: promptId,
                messageId: messageId
            )
        }

        if action.type == "choose_pile" {
            guard let pile = exactPile(action) else {
                throw missingActionData(action, "pile choice")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                pile: pile
            )
        }

        if action.type == "choose_amount" || action.type == "play_x_mana" {
            guard let amount = action.amount ?? templateInt(action, "amount") ?? (action.targetIds?.first ?? action.validTargetIds?.first ?? action.choiceIds?.first).flatMap(Int.init) else {
                throw missingActionData(action, "amount")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                amount: amount
            )
        }

        if action.type == "choose_multi_amount" {
            let amounts = action.amounts ?? templateIntArray(action, "amounts") ?? (action.targetIds ?? action.validTargetIds ?? action.choiceIds ?? []).compactMap(Int.init)
            guard !amounts.isEmpty else {
                throw missingActionData(action, "amount choices")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                amounts: amounts
            )
        }

        if action.type == "search_select" || action.type == "order_triggers" || action.type == "order_items" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                cardInstanceIds: action.type == "search_select" ? action.cardInstanceIds ?? action.validCardInstanceIds ?? action.targetIds : nil,
                orderedIds: action.type == "order_triggers" || action.type == "order_items" ? action.orderedIds ?? action.targetIds : nil
            )
        }

        if action.type == "answer_yes_no" {
            guard let confirmed = action.confirmed ?? templateBool(action, "confirmed") ?? boolFromTarget(action.targetIds?.first ?? action.validTargetIds?.first ?? action.choiceIds?.first) else {
                throw missingActionData(action, "yes/no choice")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                confirmed: confirmed
            )
        }

        if action.type == "commander_replacement" {
            guard let useCommandZone = action.useCommandZone ?? templateBool(action, "useCommandZone") ?? templateBool(action, "confirmed") ?? boolFromCommanderReplacementChoice(action.targetIds?.first ?? action.validTargetIds?.first ?? action.choiceIds?.first) else {
                throw missingActionData(action, "commander replacement choice")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                useCommandZone: useCommandZone
            )
        }

        if action.type == "pay_cost" {
            guard let pay = action.pay ?? action.confirmed ?? templateBool(action, "pay") ?? templateBool(action, "confirmed") else {
                throw missingActionData(action, "payment choice")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: promptId,
                messageId: messageId,
                sourceInstanceIds: action.targetIds ?? [],
                paymentId: action.id,
                confirmed: action.confirmed ?? templateBool(action, "confirmed") ?? templateBool(action, "pay"),
                pay: pay
            )
        }

        if action.type == "make_mana" {
            guard let sourceInstanceId = templateString(action, "sourceInstanceId") ?? action.sourceInstanceId ?? action.cardInstanceId else {
                throw missingActionData(action, "mana source id")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                sourceInstanceId: sourceInstanceId,
                abilityId: action.abilityId ?? templateString(action, "abilityId")
            )
        }

        if action.type == "activate_ability" {
            guard let sourceInstanceId = templateString(action, "sourceInstanceId") ?? action.sourceInstanceId ?? action.cardInstanceId else {
                throw missingActionData(action, "source id")
            }
            guard let abilityId = action.abilityId ?? templateString(action, "abilityId") else {
                throw missingActionData(action, "ability id")
            }
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                sourceInstanceId: sourceInstanceId,
                abilityId: abilityId
            )
        }

        throw MagicMobileError.server("Unsupported XMage action route: \(action.type). Refresh the game state and try again.")
    }

    private func mergeCommandTemplate(_ command: GameCommand, action: LegalAction, gameId: String) -> GameCommand {
        guard action.commandTemplate != nil else { return command }
        return GameCommand(
            type: templateString(action, "type") ?? command.type,
            gameId: gameId,
            playerId: action.playerId,
            cardInstanceId: templateString(action, "cardInstanceId") ?? command.cardInstanceId,
            sourceInstanceId: templateString(action, "sourceInstanceId") ?? command.sourceInstanceId,
            abilityId: templateString(action, "abilityId") ?? command.abilityId,
            promptId: templateString(action, "promptId") ?? command.promptId,
            messageId: templateInt(action, "messageId") ?? action.messageId ?? command.messageId,
            choiceIds: templateStringArray(action, "choiceIds") ?? command.choiceIds,
            targetIds: templateStringArray(action, "targetIds") ?? command.targetIds,
            cardInstanceIds: templateStringArray(action, "cardInstanceIds") ?? command.cardInstanceIds,
            modeIds: templateStringArray(action, "modeIds") ?? command.modeIds,
            sourceInstanceIds: templateStringArray(action, "sourceInstanceIds") ?? command.sourceInstanceIds,
            paymentId: templateString(action, "paymentId") ?? command.paymentId,
            abilityIdChoice: templateString(action, "abilityIdChoice") ?? command.abilityIdChoice,
            pile: templateInt(action, "pile") ?? command.pile,
            amount: templateInt(action, "amount") ?? command.amount,
            amounts: templateIntArray(action, "amounts") ?? command.amounts,
            orderedIds: templateStringArray(action, "orderedIds") ?? command.orderedIds,
            useCommandZone: templateBool(action, "useCommandZone") ?? command.useCommandZone,
            manaType: templateString(action, "manaType") ?? command.manaType,
            manaTypes: templateStringArray(action, "manaTypes") ?? command.manaTypes,
            playerIds: templateStringArray(action, "playerIds") ?? command.playerIds,
            confirmed: templateBool(action, "confirmed") ?? command.confirmed,
            pay: templateBool(action, "pay") ?? command.pay,
            sourceZone: templateString(action, "sourceZone") ?? command.sourceZone,
            fromZone: templateString(action, "fromZone") ?? command.fromZone,
            cardName: templateString(action, "cardName") ?? command.cardName,
            attackers: templateAttackers(action) ?? action.attackers ?? command.attackers,
            blockers: templateBlockers(action) ?? action.blockers ?? command.blockers,
            combatComplete: templateBool(action, "combatComplete") ?? command.combatComplete,
            expectedBridgeRevision: templateInt(action, "expectedBridgeRevision") ?? command.expectedBridgeRevision
        )
    }

    static func withExpectedBridgeRevision(_ command: GameCommand, expectedBridgeRevision: Int?) -> GameCommand {
        guard let expectedBridgeRevision else { return command }
        return GameCommand(
            type: command.type,
            gameId: command.gameId,
            playerId: command.playerId,
            cardInstanceId: command.cardInstanceId,
            sourceInstanceId: command.sourceInstanceId,
            abilityId: command.abilityId,
            promptId: command.promptId,
            messageId: command.messageId,
            choiceIds: command.choiceIds,
            targetIds: command.targetIds,
            cardInstanceIds: command.cardInstanceIds,
            modeIds: command.modeIds,
            sourceInstanceIds: command.sourceInstanceIds,
            paymentId: command.paymentId,
            abilityIdChoice: command.abilityIdChoice,
            pile: command.pile,
            amount: command.amount,
            amounts: command.amounts,
            orderedIds: command.orderedIds,
            useCommandZone: command.useCommandZone,
            manaType: command.manaType,
            manaTypes: command.manaTypes,
            playerIds: command.playerIds,
            confirmed: command.confirmed,
            pay: command.pay,
            sourceZone: command.sourceZone,
            fromZone: command.fromZone,
            cardName: command.cardName,
            attackers: command.attackers,
            blockers: command.blockers,
            combatComplete: command.combatComplete,
            expectedBridgeRevision: expectedBridgeRevision
        )
    }

    private func promptId(for action: LegalAction) -> String {
        templateString(action, "promptId") ?? action.promptId ?? action.id
    }

    private func messageId(for action: LegalAction) -> Int? {
        templateInt(action, "messageId") ?? action.messageId
    }

    private func templateString(_ action: LegalAction, _ key: String) -> String? {
        action.commandTemplate?[key]?.stringValue
    }

    private func templateStringArray(_ action: LegalAction, _ key: String) -> [String]? {
        action.commandTemplate?[key]?.stringArrayValue
    }

    private func templateInt(_ action: LegalAction, _ key: String) -> Int? {
        guard let value = action.commandTemplate?[key] else { return nil }
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let string):
            return Int(string)
        case .bool(let bool):
            return bool ? 1 : 0
        case .array, .object, .null:
            return nil
        }
    }

    private func templateIntArray(_ action: LegalAction, _ key: String) -> [Int]? {
        guard let value = action.commandTemplate?[key] else { return nil }
        switch value {
        case .array(let values):
            let ints = values.compactMap { item -> Int? in
                switch item {
                case .number(let number):
                    return Int(number)
                case .string(let string):
                    return Int(string)
                case .bool(let bool):
                    return bool ? 1 : 0
                case .array, .object, .null:
                    return nil
                }
            }
            return ints.count == values.count ? ints : nil
        case .number(let number):
            return [Int(number)]
        case .string(let string):
            return Int(string).map { [$0] }
        case .bool(let bool):
            return [bool ? 1 : 0]
        case .object, .null:
            return nil
        }
    }

    private func templateBool(_ action: LegalAction, _ key: String) -> Bool? {
        action.commandTemplate?[key]?.boolValue
    }

    private func templateAttackers(_ action: LegalAction) -> [AttackDeclaration]? {
        guard let value = action.commandTemplate?["attackers"] else { return nil }
        return attackDeclarations(from: value)
    }

    private func templateBlockers(_ action: LegalAction) -> [BlockDeclaration]? {
        guard let value = action.commandTemplate?["blockers"] else { return nil }
        return blockDeclarations(from: value)
    }

    private func attackDeclarations(from value: JSONValue) -> [AttackDeclaration]? {
        guard case .array(let values) = value else { return nil }
        let declarations = values.compactMap { item -> AttackDeclaration? in
            guard case .object(let object) = item,
                  let attackerId = object["attackerId"]?.stringValue
            else { return nil }
            return AttackDeclaration(attackerId: attackerId, defenderId: object["defenderId"]?.stringValue)
        }
        return declarations.count == values.count ? declarations : nil
    }

    private func blockDeclarations(from value: JSONValue) -> [BlockDeclaration]? {
        guard case .array(let values) = value else { return nil }
        let declarations = values.compactMap { item -> BlockDeclaration? in
            guard case .object(let object) = item,
                  let blockerId = object["blockerId"]?.stringValue
            else { return nil }
            return BlockDeclaration(blockerId: blockerId, attackerId: object["attackerId"]?.stringValue)
        }
        return declarations.count == values.count ? declarations : nil
    }

    private func boolFromTarget(_ value: String?) -> Bool? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "command", "command_zone", "command-zone"].contains(normalized) { return true }
        if ["false", "no", "original", "original_zone", "original-zone"].contains(normalized) { return false }
        return nil
    }

    private func boolFromCommanderReplacementChoice(_ value: String?) -> Bool? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["true", "yes", "command", "command_zone", "command-zone"].contains(normalized) { return true }
        if ["false", "no", "graveyard", "original", "original_zone", "original-zone"].contains(normalized) { return false }
        return nil
    }

    private func exactPile(_ action: LegalAction) -> Int? {
        let raw = action.targetIds?.first ?? action.validTargetIds?.first ?? action.choiceIds?.first
        let pile = templateInt(action, "pile") ?? action.pile?.value ?? raw.flatMap(Int.init)
        return pile == 1 || pile == 2 ? pile : nil
    }

    private func exactManaType(_ value: String?) -> String? {
        guard let value else { return nil }
        return ["W", "U", "B", "R", "G", "C"].contains(value) ? value : nil
    }

    private func exactManaTypes(_ values: [String]?) -> [String]? {
        guard let values, !values.isEmpty else { return nil }
        let parsed = values.compactMap(exactManaType)
        return parsed.count == values.count ? parsed : nil
    }

    private func missingActionData(_ action: LegalAction, _ field: String) -> MagicMobileError {
        MagicMobileError.server("XMage action \(action.type) is missing \(field). Refresh the game state and try again.")
    }

    private var session: URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120.0
        config.timeoutIntervalForResource = 180.0
        return URLSession(configuration: config)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await session.data(from: url(path))
        try validate(response: response, data: data)
        return try decode(T.self, from: data, response: response)
    }

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem]) async throws -> T {
        guard var components = URLComponents(url: url(path), resolvingAgainstBaseURL: false) else {
            throw MagicMobileError.invalidServerURL
        }
        components.queryItems = queryItems
        guard let requestURL = components.url else {
            throw MagicMobileError.invalidServerURL
        }
        let (data, response) = try await session.data(from: requestURL)
        try validate(response: response, data: data)
        return try decode(T.self, from: data, response: response)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        let data = try await postData(path, body: body)
        return try decode(T.self, from: data)
    }

    private func postData<Body: Encodable>(_ path: String, body: Body) async throws -> Data {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONEncoder.magicMobile.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return data
    }

    private func delete<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONEncoder.magicMobile.encode(body)
        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decode(T.self, from: data)
    }

    static func decodeCommanderFixtureSnapshot(from data: Data) throws -> GameSnapshot {
        if let snapshot = try? JSONDecoder.magicMobile.decode(GameSnapshot.self, from: data) {
            return snapshot
        }
        let response = try JSONDecoder.magicMobile.decode(CommanderFixtureResponse.self, from: data)
        guard let snapshot = response.playableSnapshot else {
            throw MagicMobileError.server(response.statusMessage)
        }
        return snapshot
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private var usesDirectGatewayRoutes: Bool {
        baseURL.port == 17171 || baseURL.port == 17172
    }

    private var usesDirectJavaBridgeRoutes: Bool {
        baseURL.port == 17172
    }

    private func route(web: String, gateway: String) -> String {
        usesDirectGatewayRoutes ? gateway : web
    }

    private func gamePath(gameId: String) -> String {
        var allowedPathSegment = CharacterSet.urlPathAllowed
        allowedPathSegment.remove(charactersIn: "/")
        let encoded = gameId.addingPercentEncoding(withAllowedCharacters: allowedPathSegment) ?? gameId
        return usesDirectGatewayRoutes ? "/games/\(encoded)" : "/api/engine/games/\(encoded)"
    }

    private func commandPath(gameId: String) -> String {
        "\(gamePath(gameId: gameId))/commands"
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            if let apiError = try? JSONDecoder.magicMobile.decode(APIError.self, from: data) {
                if apiError.category == "expired_game" || apiError.error == "game_expired" {
                    throw MagicMobileError.gameExpired(apiError.displayMessage ?? "Game is no longer available.")
                }
                if let rejection = apiError.actionRejection {
                    throw MagicMobileError.actionRejected(rejection)
                }
            }
            let message = Self.sanitizedServerMessage(
                data: data,
                statusCode: http?.statusCode,
                contentType: http?.value(forHTTPHeaderField: "Content-Type")
            )
            throw MagicMobileError.server(message)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data, response: URLResponse? = nil) throws -> T {
        do {
            return try JSONDecoder.magicMobile.decode(type, from: data)
        } catch {
            let http = response as? HTTPURLResponse
            if Self.responseLooksLikeHTML(data: data, contentType: http?.value(forHTTPHeaderField: "Content-Type")) {
                throw MagicMobileError.server(Self.webPageResponseMessage(statusCode: http?.statusCode))
            }
            throw error
        }
    }

    static func sanitizedServerMessage(data: Data, statusCode: Int?, contentType: String?) -> String {
        if let apiMessage = try? JSONDecoder.magicMobile.decode(APIError.self, from: data).displayMessage,
           !apiMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return apiMessage
        }
        if responseLooksLikeHTML(data: data, contentType: contentType) {
            return webPageResponseMessage(statusCode: statusCode)
        }
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, !text.isEmpty {
            return String(text.prefix(320))
        }
        return "MagicMobile server returned an empty error response."
    }

    private static func responseLooksLikeHTML(data: Data, contentType: String?) -> Bool {
        if contentType?.localizedCaseInsensitiveContains("text/html") == true {
            return true
        }
        let prefix = String(data: data.prefix(180), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return prefix.hasPrefix("<!doctype html") || prefix.hasPrefix("<html") || prefix.contains("<head")
    }

    private static func webPageResponseMessage(statusCode: Int?) -> String {
        let statusText = statusCode.map { "HTTP \($0). " } ?? ""
        return "\(statusText)MagicMobile expected a JSON XMage gateway response, but the server returned a web page. Check that the Server URL points to the MagicMobile gateway/API host and that XMage is running, then tap Refresh or start a new game."
    }
}

struct DeckImporter {
    static func parse(text: String, source: String) -> DeckList? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return nil }

        var section = "deck"
        var entries: [DeckEntry] = []

        for line in lines {
            let lower = line.lowercased()
            if lower == "commander" || lower == "commanders" || lower.contains("commander deck") {
                section = "commander"
                continue
            }
            if lower == "companion" || lower == "sideboard" {
                section = "sideboard"
                continue
            }
            if lower == "deck" || lower.contains("mainboard") {
                section = "deck"
                continue
            }

            let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let quantityText = parts[0].replacingOccurrences(of: "x", with: "")
            guard let quantity = Int(quantityText) else { continue }

            let name = parts[1]
                .replacingOccurrences(of: #"\s+#\d+$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+\(.+\)$"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            entries.append(DeckEntry(cardName: name, quantity: quantity, section: section))
        }

        guard let commander = entries.first(where: { $0.section == "commander" }) ?? entries.first else {
            return nil
        }

        let deckEntries = entries
            .filter { $0 != commander }
            .map { DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: $0.section) }

        return DeckList(
            name: source.hasPrefix("http") ? "Imported URL Deck" : source,
            commander: DeckEntry(cardName: commander.cardName, quantity: 1, section: "commander"),
            entries: deckEntries
        )
    }
}

private struct GenerateDeckRequest: Encodable {
    let bracket: Int
    let seed: String
    let playerId: String
}

private struct CommanderFixtureRequest: Encodable {
    let scenario: String
}

private struct ResumeGameRequest: Encodable {
    let playerId: String
}

struct CommanderDeckValidationIssue: Decodable {
    let code: String
    let message: String
    let cardName: String?
}

struct CommanderDeckValidationError: Decodable {
    let seat: String
    let deckName: String
    let issues: [CommanderDeckValidationIssue]

    static func summarizedMessage(for deckErrors: [CommanderDeckValidationError]) -> String {
        let details = deckErrors.flatMap { deck in
            deck.issues.map { issue in
                let card = issue.cardName.map { "\($0): " } ?? ""
                return "\(deck.seat.capitalized) deck \(deck.deckName) — \(card)\(issue.message)"
            }
        }
        let visible = details.prefix(4).joined(separator: "\n")
        let remaining = max(0, details.count - 4)
        return remaining > 0 ? "\(visible)\nPlus \(remaining) more deck issue\(remaining == 1 ? "" : "s")." : visible
    }
}

private struct APIError: Decodable {
    let error: String?
    let serverMessage: String?
    let category: String?
    let rejectionCategory: String?
    let blockedReason: String?
    let nextImplementationStep: String?
    let snapshot: GameSnapshot?
    let deckErrors: [CommanderDeckValidationError]?
    let validationErrors: [String]?

    enum CodingKeys: String, CodingKey {
        case error
        case serverMessage = "message"
        case category
        case rejectionCategory
        case blockedReason
        case nextImplementationStep
        case snapshot
        case deckErrors
        case validationErrors
    }

    var displayMessage: String? {
        if let deckErrors, !deckErrors.isEmpty {
            return CommanderDeckValidationError.summarizedMessage(for: deckErrors)
        }
        if let validationErrors, !validationErrors.isEmpty {
            let visible = validationErrors.prefix(4).joined(separator: "\n")
            let remaining = max(0, validationErrors.count - 4)
            return remaining > 0 ? "\(visible)\nPlus \(remaining) more deck issue\(remaining == 1 ? "" : "s")." : visible
        }
        if let serverMessage, !serverMessage.isEmpty {
            return serverMessage
        }
        if let blockedReason, !blockedReason.isEmpty {
            return nextImplementationStep.map { "\(blockedReason) Next: \($0)" } ?? blockedReason
        }
        return error
    }

    var actionRejection: MagicMobileActionRejection? {
        let rawCategory = rejectionCategory ?? category ?? error
        let normalizedError = error?.lowercased() ?? ""
        if category == "invalid_deck" || normalizedError == "deck_validation_failed" {
            return nil
        }
        guard snapshot != nil || category != nil || rejectionCategory != nil || normalizedError == "action_no_longer_legal" else {
            return nil
        }
        return MagicMobileActionRejection(
            category: MagicMobileActionRejection.category(from: rawCategory),
            message: displayMessage ?? error ?? "XMage rejected the action.",
            snapshot: snapshot
        )
    }
}

struct EmptyRequest: Encodable {}

enum MagicMobileError: LocalizedError {
    case invalidServerURL
    case server(String)
    case actionRejected(MagicMobileActionRejection)
    case gameExpired(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid MagicMobile server URL."
        case .server(let message):
            return message
        case .actionRejected(let rejection):
            return rejection.shortMessage
        case .gameExpired(let message):
            return message
        }
    }
}

extension JSONDecoder {
    static var magicMobile: JSONDecoder {
        JSONDecoder()
    }
}

extension JSONEncoder {
    static var magicMobile: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
