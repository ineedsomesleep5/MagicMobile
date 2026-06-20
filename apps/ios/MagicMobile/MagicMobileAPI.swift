import Foundation

struct MagicMobileAPI {
    var baseURL: URL

    func health() async throws -> EngineHealth {
        try await get("/api/engine/health")
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

    private func command(for action: LegalAction, gameId: String) -> GameCommand {
        if action.type == "resolve_choice" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: nil,
                sourceInstanceId: nil,
                abilityId: nil,
                promptId: action.id,
                choiceIds: action.targetIds ?? []
            )
        }

        if action.type == "activate_ability" || action.type == "make_mana" {
            return GameCommand(
                type: action.type,
                gameId: gameId,
                playerId: action.playerId,
                cardInstanceId: nil,
                sourceInstanceId: action.sourceInstanceId ?? action.cardInstanceId,
                abilityId: action.commandTemplate?["abilityId"] ?? action.id,
                promptId: nil,
                choiceIds: nil
            )
        }

        return GameCommand(
            type: action.type,
            gameId: gameId,
            playerId: action.playerId,
            cardInstanceId: action.cardInstanceId,
            sourceInstanceId: action.sourceInstanceId,
            abilityId: action.commandTemplate?["abilityId"],
            promptId: nil,
            choiceIds: nil
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
