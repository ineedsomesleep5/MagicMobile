import Foundation

struct MagicMobileAPI {
    var baseURL: URL

    func health() async throws -> EngineHealth {
        try await get("/api/engine/health")
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

    func startCommanderGame(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty) async throws -> GameSnapshot {
        let config = commanderConfig(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty)
        return try await post("/api/engine/commander", body: config)
    }

    func startCommanderStartup(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty) async throws -> CommanderStartupResponse {
        try await post("/api/engine/commander/start", body: commanderConfig(humanDeck: humanDeck, aiDeck: aiDeck, difficulty: difficulty))
    }

    func commanderStartupStatus(startupId: String) async throws -> CommanderStartupResponse {
        try await get("/api/engine/commander/start/\(startupId)")
    }

    func snapshot(gameId: String) async throws -> GameSnapshot {
        try await get("/api/engine/games/\(gameId)")
    }

    private func commanderConfig(humanDeck: DeckList, aiDeck: DeckList, difficulty: AiDifficulty) -> CommanderGameConfig {
        let config = CommanderGameConfig(
            roomId: "ios-\(Int(Date().timeIntervalSince1970))",
            humanPlayerId: "human",
            humanDeck: humanDeck,
            aiPlayers: [
                AiPlayerConfig(playerId: "ai-1", displayName: "Noaddrag", difficulty: difficulty, deck: aiDeck)
            ],
            startingLife: 40,
            commanderDamageEnabled: true
        )
        return config
    }

    func submit(action: LegalAction, gameId: String) async throws -> GameSnapshot {
        let command = command(for: action, gameId: gameId)
        return try await post("/api/engine/games/\(gameId)/commands", body: command)
    }

    func submit(command: GameCommand, gameId: String) async throws -> GameSnapshot {
        try await post("/api/engine/games/\(gameId)/commands", body: command)
    }

    private func command(for action: LegalAction, gameId: String) -> GameCommand {
        if action.type == "resolve_choice" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                choiceIds: action.targetIds ?? []
            )
        }

        if action.type == "choose_target" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                targetIds: action.targetIds ?? action.validTargetIds ?? []
            )
        }

        if action.type == "choose_card" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                cardInstanceIds: action.cardInstanceIds ?? action.targetIds ?? action.validTargetIds ?? []
            )
        }

        if action.type == "choose_player" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                playerIds: action.playerIds ?? action.validPlayerIds ?? action.targetIds ?? action.validTargetIds ?? []
            )
        }

        if action.type == "choose_mode" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                modeIds: action.modeIds ?? action.targetIds ?? []
            )
        }

        if action.type == "play_mana" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                manaType: action.manaType ?? action.targetIds?.first ?? "C"
            )
        }

        if action.type == "choose_mana" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                manaTypes: action.manaTypes ?? [action.manaType ?? action.choiceIds?.first ?? action.targetIds?.first ?? "C"]
            )
        }

        if action.type == "choose_ability" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                abilityId: action.targetIds?.first ?? action.validTargetIds?.first ?? action.id,
                promptId: action.id
            )
        }

        if action.type == "choose_pile" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                pile: Int(action.targetIds?.first ?? "1") ?? 1
            )
        }

        if action.type == "choose_amount" || action.type == "play_x_mana" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                amount: Int(action.targetIds?.first ?? action.validTargetIds?.first ?? "0") ?? 0
            )
        }

        if action.type == "choose_multi_amount" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                amounts: (action.targetIds ?? []).compactMap(Int.init)
            )
        }

        if action.type == "search_select" || action.type == "order_triggers" || action.type == "order_items" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                cardInstanceIds: action.type == "search_select" ? action.cardInstanceIds ?? action.targetIds : nil,
                orderedIds: action.type == "order_triggers" || action.type == "order_items" ? action.targetIds ?? action.orderedIds : nil
            )
        }

        if action.type == "answer_yes_no" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                confirmed: action.confirmed ?? (action.targetIds?.first != "false")
            )
        }

        if action.type == "commander_replacement" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                promptId: action.id,
                useCommandZone: action.targetIds?.first != "graveyard"
            )
        }

        if action.type == "pay_cost" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                sourceInstanceIds: action.targetIds ?? [],
                paymentId: action.id
            )
        }

        if action.type == "activate_ability" || action.type == "make_mana" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId,
                abilityId: action.abilityId ?? action.commandTemplate?["abilityId"] ?? action.id
            )
        }

        return GameCommand(
            type: action.type,
            gameId: gameId,
            playerId: action.playerId,
            cardInstanceId: action.cardInstanceId,
            sourceInstanceId: action.sourceInstanceId,
            abilityId: action.abilityId ?? action.commandTemplate?["abilityId"]
        )
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(from: url(path))
        try validate(response: response, data: data)
        return try JSONDecoder.magicMobile.decode(T.self, from: data)
    }

    private func post<Body: Encodable, T: Decodable>(_ path: String, body: Body) async throws -> T {
        var request = URLRequest(url: url(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        request.httpBody = try JSONEncoder.magicMobile.encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder.magicMobile.decode(T.self, from: data)
    }

    private func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.magicMobile.decode(APIError.self, from: data).error)
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown server error"
            throw MagicMobileError.server(message)
        }
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
            if lower.contains("commander") {
                section = "commander"
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
            if section == "commander" {
                section = "deck"
            }
        }

        guard let commander = entries.first(where: { $0.section == "commander" }) ?? entries.first else {
            return nil
        }

        let deckEntries = entries
            .filter { $0 != commander }
            .map { DeckEntry(cardName: $0.cardName, quantity: $0.quantity, section: "deck") }

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

private struct APIError: Decodable {
    let error: String
}

struct EmptyRequest: Encodable {}

enum MagicMobileError: LocalizedError {
    case invalidServerURL
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Enter a valid MagicMobile server URL."
        case .server(let message):
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
