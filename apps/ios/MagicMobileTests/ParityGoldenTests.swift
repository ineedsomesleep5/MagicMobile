import XCTest
import MagicMobileOnDevice
@testable import MagicMobile

/// Android parity goldens. The Android port in apps/android/core (package
/// io.magicmobile.android.game) adapts the same engine polls and prompt cases and must
/// produce these exact summaries (ParityGoldenTest.kt). After an intended iOS change, rerun
/// with MAGICMOBILE_WRITE_PARITY_GOLDENS=1, commit the goldens, then port the change until
/// the Android tests pass again.
final class ParityGoldenTests: XCTestCase {
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    private var parityDirectory: URL { Self.root.appendingPathComponent("apps/android/core/src/test/resources/parity") }
    private var fixtureDirectory: URL { Self.root.appendingPathComponent("apps/ios/MagicMobileTests/Fixtures/OnDevice") }

    func testEngineFixturesMatchAndroidGoldens() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: fixtureDirectory.path)
            .filter { $0.hasSuffix(".json") && $0 != "manifest.json" }.sorted()
        XCTAssertFalse(names.isEmpty)
        for name in names {
            let poll = try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: fixtureDirectory.appendingPathComponent(name))))
            var log = OnDeviceMessageLog()
            try log.ingest(poll)
            let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID, log: log.entries)
            var summary = ParitySummary.snapshot(snapshot)
            summary["answers"] = ParitySummary.answers(snapshot: snapshot, prompt: poll.prompt)
            try check(summary, name: "fixture-" + name)
        }
    }

    func testPromptCasesMatchAndroidGoldens() throws {
        let data = try Data(contentsOf: parityDirectory.appendingPathComponent("prompt-cases.json"))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let viewer = try XCTUnwrap(root["viewer"] as? String)
        let players = try JSONDecoder().decode([PlayerGameState].self, from: JSONSerialization.data(withJSONObject: XCTUnwrap(root["players"])))
        let cards = players.flatMap { $0.zones.hand + $0.zones.battlefield + $0.zones.graveyard + $0.zones.exile + $0.zones.command }
        var results: [[String: Any]] = []
        for item in try XCTUnwrap(root["cases"] as? [[String: Any]]) {
            let prompt = try EnginePrompt(MagicMobileOnDevice.JSONValue.decode(JSONSerialization.data(withJSONObject: XCTUnwrap(item["prompt"]))))
            var result: [String: Any] = ["name": item["name"] ?? ""]
            do {
                let view = try OnDevicePromptAdapter.presentation(prompt, viewerPlayerID: viewer, cards: cards, players: players)
                result["envelope"] = ParitySummary.envelope(view.envelope)
                result["actions"] = view.legalActions.map(ParitySummary.action)
                result["manaPayment"] = ParitySummary.o(view.manaPayment.map { ["active": $0.active, "remainingText": ParitySummary.o($0.remainingText)] as [String: Any] })
            } catch { result["error"] = ParitySummary.message(error) }
            result["answers"] = (item["commands"] as? [[String: Any]] ?? []).map { fields -> Any in
                let command = ParitySummary.command(fields, gameId: "match", playerId: viewer, promptId: prompt.id, messageId: Int(prompt.revision))
                return ParitySummary.answer(command, prompt: prompt, viewer: viewer)
            }
            results.append(result)
        }
        try check(["cases": results], name: "prompt-cases.json")
    }

    private func check(_ summary: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes])
        let directory = parityDirectory.appendingPathComponent("golden")
        let url = directory.appendingPathComponent(name)
        if ProcessInfo.processInfo.environment["MAGICMOBILE_WRITE_PARITY_GOLDENS"] == "1" {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url)
            return
        }
        let golden = try Data(contentsOf: url)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), String(decoding: golden, as: UTF8.self),
                       "\(name) changed: rerun with MAGICMOBILE_WRITE_PARITY_GOLDENS=1 and port the change to Android")
    }
}

/// The summary written for each case. ParitySummary.kt builds the identical structure.
enum ParitySummary {
    static func o<T>(_ value: T?) -> Any { value.map { $0 as Any } ?? NSNull() }

    static func message(_ error: Error) -> String {
        (error as? MagicMobileOnDevice.EngineError)?.errorDescription ?? "decoding failed"
    }

    static func card(_ c: ZoneCard) -> [String: Any] {
        [
            "instanceId": c.instanceId, "name": c.card.name, "typeLine": c.card.typeLine, "oracleText": o(c.card.oracleText),
            "manaCost": o(c.card.manaCost), "isToken": o(c.card.isToken), "tokenColors": o(c.card.tokenColors),
            "copySourceArtworkName": o(c.card.copySourceArtworkName),
            "tokenArtwork": o(c.card.tokenArtwork.map { ["name": $0.name, "typeLine": $0.typeLine, "oracleText": $0.oracleText,
                                                            "power": o($0.power), "toughness": o($0.toughness), "colors": $0.colors] as [String: Any] }),
            "tapped": o(c.tapped), "summoningSickness": o(c.summoningSickness), "damage": o(c.damage), "phasedIn": o(c.phasedIn),
            "isAttacking": o(c.isAttacking), "blocking": o(c.blocking), "attachedToInstanceId": o(c.attachedToInstanceId),
            "reportedPower": o(c.reportedPower), "reportedToughness": o(c.reportedToughness), "counters": o(c.counters),
            "icons": (c.cardIcons ?? []).map { ["iconType": $0.iconType, "category": o($0.category), "text": o($0.text), "hint": o($0.hint)] as [String: Any] },
            "visibleIcons": c.visibleXmageIcons.map(\.iconType),
            "selectable": o(c.selectable), "disabledReason": o(c.disabledReason),
            "displayPower": o(c.displayPower), "displayToughness": o(c.displayToughness)
        ]
    }

    static func player(_ p: PlayerGameState) -> [String: Any] {
        let z = p.zones
        return [
            "playerId": p.playerId, "displayName": o(p.displayName), "life": p.life, "poison": p.poison,
            "commanderTax": p.commanderTax, "commanderTaxKnown": o(p.commanderTaxKnown), "hasLeft": o(p.hasLeft),
            "isHuman": o(p.isHuman), "monarch": o(p.monarch), "initiative": o(p.initiative), "counters": o(p.counters),
            "commanderDamage": o(p.commanderDamage),
            "commanders": (p.commanders ?? []).map { ["id": $0.id, "name": o($0.name), "ownerPlayerId": $0.ownerPlayerId,
                                                      "commanderTax": o($0.commanderTax), "castsFromCommandZone": o($0.castsFromCommandZone),
                                                      "damageToPlayers": o($0.damageToPlayers)] as [String: Any] },
            "manaPool": o(p.manaPool.map { ["W": $0.W, "U": $0.U, "B": $0.B, "R": $0.R, "G": $0.G, "C": $0.C] }),
            "handCount": o(z.handCount), "libraryCount": o(z.libraryCount),
            "hand": z.hand.map(card), "battlefield": z.battlefield.map(card), "graveyard": z.graveyard.map(card),
            "exile": z.exile.map(card), "command": z.command.map(card), "library": z.library.map(card), "stack": z.stack.map(card)
        ]
    }

    static func snapshot(_ s: GameSnapshot) -> [String: Any] {
        var result: [String: Any] = [
            "id": s.id, "source": o(s.source), "activePlayerId": o(s.activePlayerId), "phase": s.phase, "step": o(s.step),
            "turn": s.turn, "priorityPlayerId": o(s.priorityPlayerId), "waitingOnPlayerId": o(s.waitingOnPlayerId),
            "promptText": o(s.promptText), "bridgeRevision": o(s.bridgeRevision), "xmageCycle": o(s.xmageCycle),
            "pendingStatus": o(s.pendingStatus), "gameStatus": o(s.gameStatus.map { $0 == .completed ? "completed" : "in_progress" }),
            "winnerPlayerIds": o(s.winnerPlayerIds), "viewerPlayerId": o(s.viewerPlayerId), "isSpectating": s.isSpectating,
            "thinkingPlayerID": o(s.thinkingPlayerID), "log": s.log.map { ["id": $0.id, "message": $0.message] },
            "players": s.players.map(player), "legalActions": (s.legalActions ?? []).map(action),
            "promptEnvelopeV2": o(s.promptEnvelopeV2.map(envelope)),
            "manaPayment": o(s.manaPayment.map { ["active": $0.active, "remainingText": o($0.remainingText)] as [String: Any] })
        ]
        if let x = s.xmage {
            result["xmage"] = [
                "gameId": x.gameId, "bridgeRevision": x.bridgeRevision, "xmageCycle": o(x.xmageCycle),
                "stack": x.stack.map { ["id": $0.id, "objectType": o($0.objectType), "name": $0.name, "rulesText": o($0.rulesText),
                                         "sourceInstanceId": o($0.sourceInstanceId), "sourceName": o($0.sourceName),
                                         "sourceCard": o($0.sourceCard.map(card)), "targetIds": o($0.targetIds), "paid": o($0.paid)] as [String: Any] },
                "combat": x.combat.map { ["defenderId": $0.defenderId, "defenderName": $0.defenderName, "defenderKind": o($0.defenderKind),
                                          "blocked": $0.blocked, "attackers": $0.attackers.map(card), "blockers": $0.blockers.map(card)] as [String: Any] },
                "players": x.players.map { ["playerId": $0.playerId, "name": $0.name, "active": $0.active, "hasPriority": $0.hasPriority,
                                            "timerActive": $0.timerActive, "passedTurn": $0.skipState.passedTurn,
                                            "passedAllTurns": $0.skipState.passedAllTurns, "sideboard": $0.zones.sideboard.map(card)] as [String: Any] },
                "playableObjects": x.playableObjects.map { ["sourceInstanceId": $0.sourceInstanceId, "sourceZone": o($0.sourceZone), "cardName": $0.cardName,
                                                            "categories": $0.categories,
                                                            "abilities": $0.abilities.map { ["id": $0.id, "label": $0.label, "category": $0.category] }] as [String: Any] },
                "zones": (x.exileZones + x.revealed + x.lookedAt + x.companion).map { ["id": $0.id, "name": $0.name, "cards": $0.cards.map(card)] as [String: Any] },
                "panels": ["stack": x.panels.stack, "command": x.panels.command, "graveyard": x.panels.graveyard, "exile": x.panels.exile,
                           "revealed": x.panels.revealed, "lookedAt": x.panels.lookedAt, "search": x.panels.search]
            ] as [String: Any]
        } else { result["xmage"] = NSNull() }
        return result
    }

    static func action(_ a: LegalAction) -> [String: Any] {
        [
            "id": a.id, "type": a.type, "playerId": a.playerId, "label": a.label, "promptId": o(a.promptId), "messageId": o(a.messageId),
            "cardInstanceId": o(a.cardInstanceId), "sourceInstanceId": o(a.sourceInstanceId), "sourceZone": o(a.sourceZone),
            "cardName": o(a.cardName), "abilityId": o(a.abilityId), "confirmed": o(a.confirmed), "choiceIds": o(a.choiceIds),
            "compactPromptTitle": a.compactPromptTitle
        ]
    }

    static func envelope(_ e: PromptEnvelopeV2) -> [String: Any] {
        func options(_ values: [ChoicePromptOption]?) -> Any { o(values?.map { ["id": $0.id, "label": $0.label] }) }
        func command(_ c: XmageResponseCommand?) -> Any {
            o(c.map { ["type": o($0.type), "promptId": o($0.promptId), "messageId": o($0.messageId), "confirmed": o($0.confirmed), "pay": o($0.pay)] as [String: Any] })
        }
        var chosen: Any = NSNull()
        if case .array(let values)? = e.options?["chosenTargets"] { chosen = values.compactMap(\.stringValue) }
        return [
            "id": e.id, "method": e.method, "messageId": e.messageId, "playerId": e.playerId, "responseKind": e.responseKind,
            "message": e.message, "required": o(e.required), "minChoices": o(e.minChoices), "maxChoices": o(e.maxChoices),
            "totalMin": o(e.totalMin), "totalMax": o(e.totalMax), "targetIds": o(e.targetIds), "choices": options(e.choices),
            "responseCommand": command(e.responseCommand), "cards": o(e.cards?.map(card)), "targets": options(e.targets),
            "players": o(e.players?.map { ["id": $0.id, "label": $0.label, "playerId": $0.playerId] }),
            "piles": o(e.piles?.map { ["id": $0.id, "label": $0.label, "cards": $0.cards.map(card), "number": o($0.explicitPileNumber)] as [String: Any] }),
            "abilities": o(e.abilities?.map { ["id": $0.id, "label": $0.label, "sourceInstanceId": o($0.sourceInstanceId),
                                               "sourceName": o($0.sourceName), "sourceUnavailableReason": o($0.sourceUnavailableReason),
                                               "sourceCard": o($0.sourceCard.map(card))] as [String: Any] }),
            "modes": options(e.modes), "amounts": o(e.amounts),
            "multiAmounts": o(e.multiAmounts?.map { ["id": $0.id, "label": $0.label, "min": $0.min, "max": $0.max, "defaultValue": o($0.defaultValue)] as [String: Any] }),
            "manaChoices": o(e.manaChoices?.map { ["id": $0.id, "label": $0.label, "manaType": o($0.manaType), "amount": o($0.amount)] as [String: Any] }),
            "orderedItems": options(e.orderedItems),
            "confirmation": o(e.confirmation.map { ["yesLabel": o($0.yesLabel), "noLabel": o($0.noLabel),
                                                     "yesCommand": command($0.yesCommand), "noCommand": command($0.noCommand)] as [String: Any] }),
            "optionKeys": o(e.options.map { Array($0.keys).sorted() }), "chosenTargets": chosen,
            "kind": "\(MobilePromptPresentation.kind(for: e))"
        ]
    }

    static func command(_ f: [String: Any], gameId: String, playerId: String, promptId: String, messageId: Int) -> GameCommand {
        GameCommand(type: f["type"] as? String ?? "", gameId: gameId, playerId: playerId,
                    cardInstanceId: f["cardInstanceId"] as? String, sourceInstanceId: f["sourceInstanceId"] as? String,
                    abilityId: f["abilityId"] as? String, promptId: promptId, messageId: messageId,
                    choiceIds: f["choiceIds"] as? [String], targetIds: f["targetIds"] as? [String],
                    cardInstanceIds: f["cardInstanceIds"] as? [String], modeIds: f["modeIds"] as? [String],
                    pile: f["pile"] as? Int, amount: f["amount"] as? Int, amounts: f["amounts"] as? [Int],
                    orderedIds: f["orderedIds"] as? [String], manaType: f["manaType"] as? String,
                    playerIds: f["playerIds"] as? [String], confirmed: f["confirmed"] as? Bool)
    }

    static func answer(_ command: GameCommand, prompt: EnginePrompt, viewer: String) -> Any {
        do {
            let value = try OnDevicePromptAdapter.answer(for: command, prompt: prompt, viewerPlayerID: viewer)
            return try JSONSerialization.jsonObject(with: value.encoded(), options: [.fragmentsAllowed])
        } catch { return ["error": message(error)] }
    }

    /// Every offered action, sent the way OnDeviceSession.send(action:) builds it, plus each
    /// target and confirmation the prompt shows.
    static func answers(snapshot: GameSnapshot, prompt: EnginePrompt?) -> [Any] {
        guard let prompt, !prompt.submitted else { return [] }
        var commands: [GameCommand] = (snapshot.legalActions ?? []).map { a in
            GameCommand(type: a.type, gameId: snapshot.id, playerId: a.playerId, cardInstanceId: a.cardInstanceId,
                        sourceInstanceId: a.sourceInstanceId, abilityId: a.abilityId, promptId: a.promptId, messageId: a.messageId,
                        choiceIds: a.choiceIds, targetIds: a.targetIds, cardInstanceIds: a.cardInstanceIds, modeIds: a.modeIds,
                        pile: a.pile?.value, amount: a.amount, amounts: a.amounts, orderedIds: a.orderedIds,
                        useCommandZone: a.useCommandZone, manaType: a.manaType, manaTypes: a.manaTypes, playerIds: a.playerIds,
                        confirmed: a.confirmed, pay: a.pay, sourceZone: a.sourceZone, fromZone: a.sourceZone, cardName: a.cardName,
                        attackers: a.attackers, blockers: a.blockers, expectedBridgeRevision: snapshot.bridgeRevision)
        }
        if let envelope = snapshot.promptEnvelopeV2 {
            for target in envelope.targets ?? [] {
                commands.append(GameCommand(type: "choose_target", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, targetIds: [target.id]))
            }
            for confirmed in envelope.confirmation == nil ? [] : [true, false] {
                commands.append(GameCommand(type: "answer_yes_no", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, confirmed: confirmed))
            }
            for choice in envelope.manaChoices ?? [] {
                commands.append(GameCommand(type: "play_mana", gameId: snapshot.id, playerId: snapshot.viewerID,
                                            promptId: envelope.id, messageId: envelope.messageId, manaType: choice.manaType))
            }
        }
        return commands.map { ["type": $0.type, "answer": answer($0, prompt: prompt, viewer: snapshot.viewerID)] as [String: Any] }
    }
}
