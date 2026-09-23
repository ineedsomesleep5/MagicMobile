import XCTest
import MagicMobileOnDevice
#if !PROMPT_ADAPTER_SEAM
@testable import MagicMobile
#endif

final class OnDevicePromptAdapterTests: XCTestCase {
    private let viewer = "00000000-0000-0000-0000-000000000001"
    private let first = "11111111-0000-0000-0000-000000000000"
    private let second = "22222222-0000-0000-0000-000000000000"

    private func prompt(_ kind: String, types: [String], payload: [String: MagicMobileOnDevice.JSONValue] = [:], min: Int64 = 0, max: Int64 = 0, submitted: Bool = false, revision: Int64 = 37) throws -> EnginePrompt {
        var fields: [String: MagicMobileOnDevice.JSONValue] = ["message": .string("Engine question"), "required": .bool(true), "options": .object([:])]
        fields.merge(payload) { _, value in value }
        return try EnginePrompt(.object(["promptId": .string("real-prompt"), "revision": .integer(revision), "kind": .string(kind), "payload": .object(fields), "submitted": .bool(submitted), "responseTypes": .array(types.map { .string($0) }), "min": .integer(min), "max": .integer(max)]))
    }

    private func player(_ id: String, mana: [String: Int] = [:], battlefield: [[String: Any]] = [], hand: [[String: Any]] = []) throws -> PlayerGameState {
        var pool = Dictionary(uniqueKeysWithValues: ["W", "U", "B", "R", "G", "C"].map { ($0, 0) })
        pool.merge(mana) { _, value in value }
        return try JSONDecoder().decode(PlayerGameState.self, from: JSONSerialization.data(withJSONObject: [
            "playerId": id, "life": 40, "poison": 0, "commanderTax": 0, "manaPool": pool,
            "zones": ["library": [], "hand": hand, "battlefield": battlefield, "graveyard": [], "exile": [], "command": [], "stack": []]
        ]))
    }

    func testEngineHTMLMessagesAreDisplayTextWithoutChangingPromptOrAnswer() throws {
        let p = try prompt("ASK", types: ["boolean"], payload: [
            "message": .string("Mulligan <font color=#00ff00>for free</font>, draw another 7 cards?"),
            "options": .object(["UI.left.btn.text": .string("<b>Keep</b> &amp; play")])
        ])
        let original = p.payload
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.message, "Mulligan for free, draw another 7 cards?")
        XCTAssertEqual(view.envelope.confirmation?.yesLabel, "Keep & play")
        XCTAssertEqual(p.payload, original)
        XCTAssertEqual(view.envelope.id, p.id)
        let command = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer,
                                  promptId: p.id, messageId: 37, confirmed: true)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(true)))
    }

    func testEngineChoiceDisplayNeverSanitizesResponseTokens() throws {
        let token = "<b>exact&amp;token</b>"
        let p = try prompt("CHOOSE_CHOICE", types: ["string"], payload: [
            "choices": .object([token: .string("<b>Pay</b> {2/U} &amp; {G/P}")]),
            "choiceOrder": .array([.string(token)])
        ])
        let original = p.payload
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.choices?.first?.label, "Pay {2/U} & {G/P}")
        XCTAssertEqual(view.envelope.choices?.first?.id, token)
        let command = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer,
                                  promptId: p.id, messageId: 37, choiceIds: [token])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("string", .string(token)))
        XCTAssertEqual(p.payload, original)
    }

    func testDisplayTextRemovesActiveMarkupAttributesAndIsIdempotent() {
        let inputs = [
            "<script>secret<script>nested</script>still secret</script><b>Keep</b>",
            "<style>hidden</style><iframe src='https://example.invalid'>hidden</iframe>Keep",
            "<!-- hidden --><span title='not > a delimiter' onclick='bad()'>Keep</span>",
            "&amp;lt;b&amp;gt;Keep&amp;lt;/b&amp;gt;",
            "<svg><text>hidden</text></svg>Keep<img src='https://example.invalid/private' onerror='bad()'>",
            "Keep<script>unterminated hidden content",
            "<unknown data-private='do not show'>Keep</unknown>"
        ]
        for input in inputs {
            let once = EngineDisplayText.text(input)
            XCTAssertEqual(once, "Keep", input)
            XCTAssertEqual(EngineDisplayText.text(once), once, input)
        }
    }

    func testDisplayTextPreservesPunctuationEntitiesComparisonsAndRuleBreaks() {
        XCTAssertEqual(EngineDisplayText.text("<b>Urza</b>&apos;s &amp; Mishra’s &#8212; &#x221E; &bogus;"), "Urza's & Mishra’s — ∞ &bogus;")
        XCTAssertEqual(EngineDisplayText.text("2 < 3 and 5 > 4; A&B"), "2 < 3 and 5 > 4; A&B")
        XCTAssertEqual(EngineDisplayText.text("<div>First {T}.</div><div>Second {Q}.<br/>Third {E}.</div>"), "First {T}.\nSecond {Q}.\nThird {E}.")
        XCTAssertEqual(EngineDisplayText.label("<div>A</div><div>B</div>"), "A B")
        XCTAssertEqual(EngineDisplayText.label("<script>gone</script>", fallback: "Continue"), "Continue")
        XCTAssertEqual(EngineDisplayText.text("A&#0;&#x202E;B"), "AB")
        XCTAssertEqual(EngineDisplayText.text("A&#10;B&#9;C"), "A\nB C")
        XCTAssertEqual(EngineDisplayText.text("&#xD800; &#999999999999999999999;"), "&#xD800; &#999999999999999999999;")
    }

    func testDisplaySymbolsUseOnlyExplicitCanonicalAltAndPreserveManaTokens() {
        let text = "Pay {X}{2}{W/U}{G/P}; &#123;T&#125;: <img alt='{C}' src='ignored'><img alt='{Q}'><img alt='{E}'>"
        XCTAssertEqual(EngineDisplayText.text(text), "Pay {X}{2}{W/U}{G/P}; {T}: {C}{Q}{E}")
        for markup in ["<img src='https://example.invalid/W.png'>", "<img alt='hidden card name'>",
                       "<img title=\" alt='{W}'\">", "<img alt='{W}' alt='{B}'>"] {
            XCTAssertEqual(EngineDisplayText.text(markup), "")
        }
        XCTAssertEqual(EngineDisplayText.text("{W}{U}{B}{R}{G}{C}{S}{2/U}{W/U/P}{UNKNOWN}"), "{W}{U}{B}{R}{G}{C}{S}{2/U}{W/U/P}{UNKNOWN}")
    }

    func testPhaseDisplayFormatsOnlyPresentationNotHumanNames() {
        XCTAssertEqual(EngineDisplayText.phaseLabel("PRECOMBAT_MAIN"), "Precombat main")
        XCTAssertEqual(EngineDisplayText.phaseLabel("POSTCOMBAT_MAIN"), "Postcombat main")
        XCTAssertEqual(EngineDisplayText.phaseLabel("DECLARE_ATTACKERS"), "Declare attackers")
        XCTAssertEqual(EngineDisplayText.phaseLabel("FIRST_COMBAT_DAMAGE"), "First-strike damage")
        XCTAssertEqual(EngineDisplayText.phaseLabel("FUTURE_STEP"), "Future step")
        XCTAssertEqual(EngineDisplayText.phaseLabel("Alice’s draw step"), "Alice’s draw step")
        XCTAssertEqual(EngineDisplayText.phaseLabel("<b>Draw</b>"), "Draw")
        XCTAssertEqual(EngineDisplayText.phaseLabel(""), "")
    }

    func testManaMessageAndSpecialActionArePlainButCommandMetadataIsOriginal() throws {
        let message = "Pay {W}<div style='font-size:11pt'><font object_id='private-attribute'>Isamaru, Hound of Konda</font> [d80]</div>"
        let p = try prompt("PLAY_MANA", types: ["mana", "string", "boolean"], payload: [
            "message": .string(message), "manaPlayerId": .string(viewer),
            "options": .object(["specialButton": .string("<b>Convoke</b> &amp; delve")])
        ])
        let original = p.payload
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.message, "Pay {W}\nIsamaru, Hound of Konda [d80]")
        XCTAssertEqual(view.manaPayment?.remainingText, view.envelope.message)
        let action = try XCTUnwrap(view.legalActions.first { $0.type == "resolve_choice" })
        XCTAssertEqual(action.label, "Convoke & delve")
        XCTAssertEqual(action.choiceIds, ["special"])
        XCTAssertEqual(action.id, p.id + ":resolve_choice")
        XCTAssertEqual(action.messageId, 37)
        XCTAssertEqual(p.payload, original)
    }

    func testAbilityAllocationAndExplicitCardRulesAreDisplayOnly() throws {
        let ability = try prompt("CHOOSE_ABILITY", types: ["uuid"], payload: ["abilities": .array([
            .object(["id": .string(first), "label": .string("<b>{T}</b>: Add {G}.")])])])
        let view = try OnDevicePromptAdapter.presentation(ability, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.abilities?.first?.label, "{T}: Add {G}.")
        XCTAssertEqual(view.envelope.abilities?.first?.id, first)
        let allocation = try prompt("MULTI_AMOUNT", types: ["integers"], payload: ["allocations": .array([
            .object(["message": .string("<b>Damage</b> &amp; counters"), "min": .integer(0), "max": .integer(2)])])], min: 0, max: 2)
        XCTAssertEqual(try OnDevicePromptAdapter.presentation(allocation, viewerPlayerID: viewer, cards: []).envelope.multiAmounts?.first?.label, "Damage & counters")
        let card = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)]), "cards": .array([
            .object(["id": .string(first), "name": .string("<b>Known</b> card"), "rules": .array([.string("<b>{T}</b>: Add {G}."), .string("<script>hidden</script>Second ability.")])])])])
        let original = card.payload
        let cardView = try OnDevicePromptAdapter.presentation(card, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(cardView.envelope.cards?.first?.card.name, "Known card")
        XCTAssertEqual(cardView.envelope.cards?.first?.card.oracleText, "{T}: Add {G}.\nSecond ability.")
        XCTAssertEqual(cardView.envelope.cards?.map(\.id), [first])
        XCTAssertEqual(card.payload, original)
    }

    func testPlayableSnapshotLabelsAreDisplayOnlyAndPreserveManaCommand() throws {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: Self.self)
        #endif
        let url = try XCTUnwrap(bundle.url(forResource: "2p-mana", withExtension: "json", subdirectory: "OnDevice"))
        let original = try MatchPoll(MagicMobileOnDevice.JSONValue.decode(Data(contentsOf: url)))
        var raw = try XCTUnwrap(original.raw.object)
        var root = try XCTUnwrap(original.snapshot?.object)
        var view = try XCTUnwrap(root["gameView"]?.object)
        var canPlay = try XCTUnwrap(view["canPlayObjects"]?.object)
        var objects = try XCTUnwrap(canPlay["objects"]?.object)
        let source = try XCTUnwrap(objects.keys.first { objects[$0]?["basicManaAbilities"]?.array?.isEmpty == false })
        var stats = try XCTUnwrap(objects[source]?.object)
        var rows = try XCTUnwrap(stats["basicManaAbilities"]?.array)
        var row = try XCTUnwrap(rows[0].object)
        let abilityID = try XCTUnwrap(row["id"]?.string)
        row["value"] = .string("<b>{T}</b>: Add {W} &amp; {C}.")
        rows[0] = .object(row); stats["basicManaAbilities"] = .array(rows)
        objects[source] = .object(stats); canPlay["objects"] = .object(objects)
        view["canPlayObjects"] = .object(canPlay); root["gameView"] = .object(view); raw["snapshot"] = .object(root)
        let poll = try MatchPoll(.object(raw))
        let originalRaw = poll.raw
        let snapshot = try OnDeviceSnapshotAdapter.snapshot(poll, expectedSeatID: poll.seatID)
        let ability = try XCTUnwrap(snapshot.xmage?.playableObjects.first { $0.sourceInstanceId == source }?.abilities.first { $0.id == abilityID })
        XCTAssertEqual(ability.label, "{T}: Add {W} & {C}.")
        XCTAssertEqual(ability.id, abilityID)
        let action = try XCTUnwrap(snapshot.legalActions?.first { $0.type == "make_mana" && $0.sourceInstanceId == source })
        XCTAssertEqual(action.label, "{T}: Add {W} & {C}.")
        XCTAssertEqual(action.cardInstanceId, source)
        XCTAssertEqual(action.messageId, Int(original.prompt!.revision))
        XCTAssertEqual(action.id, original.prompt!.id + ":basicManaAbilities:" + source)
        let command = GameCommand(type: action.type, gameId: snapshot.id, playerId: action.playerId,
                                  sourceInstanceId: source, promptId: action.promptId, messageId: action.messageId)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: XCTUnwrap(poll.prompt), viewerPlayerID: snapshot.viewerID),
                       EnginePrompt.answer("uuid", .string(source)))
        XCTAssertEqual(poll.raw, originalRaw)
    }

    func testFloatingManaChoicesUseThePayloadPlayersPoolAndExactResponses() throws {
        let players = try [player(viewer, mana: ["R": 9]), player(first, mana: ["G": 1, "C": 2])]
        for kind in ["PLAY_MANA", "PLAY_X_MANA"] {
            let p = try prompt(kind, types: ["uuid", "boolean", "mana", "integer"], payload: ["manaPlayerId": .string(first)])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [], players: players)
            let choices = try XCTUnwrap(view.envelope.manaChoices)
            XCTAssertEqual(choices.map(\.id), ["G", "C"])
            XCTAssertEqual(choices.map(\.amount), [1, 2])
            for choice in choices {
                let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope,
                    type: "play_mana", promptId: p.id, playerId: viewer, manaType: choice.manaType))
                XCTAssertEqual(command.messageId, 37)
                XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer),
                    EnginePrompt.answer("mana", .object(["playerId": .string(first), "manaType": .string(choice.id == "G" ? "GREEN" : "COLORLESS")])))
            }
            for command in [
                GameCommand(type: "play_mana", gameId: "match", playerId: first, promptId: p.id, messageId: 37, manaType: "G"),
                GameCommand(type: "play_mana", gameId: "match", playerId: viewer, promptId: p.id, messageId: 36, manaType: "G"),
                GameCommand(type: "play_mana", gameId: "match", playerId: viewer, promptId: "old", messageId: 37, manaType: "G"),
                GameCommand(type: "play_mana", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, manaType: "GREEN")
            ] { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer)) }
            XCTAssertNil(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [], players: [players[0]]).envelope.manaChoices)
            XCTAssertTrue(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [], players: [player(first)]).envelope.manaChoices?.isEmpty == true)
        }
    }

    func testSpecialPaymentWithoutButtonMetadataUsesOnlyPinnedProtocolToken() throws {
        // Real HumanPlayer.playManaHandling supplies empty options, including for convoke.
        let p = try prompt("PLAY_MANA", types: ["uuid", "boolean", "mana", "string"], payload: ["manaPlayerId": .string(viewer)])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        let action = try XCTUnwrap(view.legalActions.first { $0.type == "resolve_choice" })
        XCTAssertEqual(action.choiceIds, ["special"])
        XCTAssertEqual(action.label, "Special payment")
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope,
            type: action.type, promptId: try XCTUnwrap(action.promptId), playerId: action.playerId, ids: try XCTUnwrap(action.choiceIds)))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("string", .string("special")))
        for tokens in [["Convoke"], ["#special"], [], ["special", "special"]] {
            let wrong = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: tokens)
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
        }
        for blocked in [
            try prompt("PLAY_MANA", types: ["uuid", "boolean", "mana"], payload: ["manaPlayerId": .string(viewer)]),
            try prompt("PLAY_X_MANA", types: ["uuid", "boolean", "mana", "integer"], payload: ["manaPlayerId": .string(viewer)]),
            try prompt("SELECT", types: ["uuid", "boolean", "string"], payload: ["selectMode": .string("priority")]),
            try prompt("PLAY_MANA", types: ["mana", "string"], payload: ["manaPlayerId": .string(viewer)], submitted: true),
            try prompt("PLAY_MANA", types: ["mana", "string"], payload: ["manaPlayerId": .string(viewer)], revision: 38)
        ] { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: blocked, viewerPlayerID: viewer)) }
        let foreign = GameCommand(type: "resolve_choice", gameId: "match", playerId: first, promptId: p.id, messageId: 37, choiceIds: ["special"])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: foreign, prompt: p, viewerPlayerID: viewer))
        for kind in ["PLAY_MANA", "PLAY_X_MANA"] {
            let withoutString = try prompt(kind, types: ["mana", "boolean"], payload: ["manaPlayerId": .string(viewer), "options": .object(["specialButton": .string("Convoke")])])
            XCTAssertFalse(try OnDevicePromptAdapter.presentation(withoutString, viewerPlayerID: viewer, cards: []).legalActions.contains { $0.type == "resolve_choice" })
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: withoutString, viewerPlayerID: viewer))
        }
    }

    func testDeclaredAttackerRemainsSelectableOnTheNextPromptWithoutAddingOtherCards() throws {
        let opponentCard = "33333333-0000-0000-0000-000000000000"
        let hiddenCard = "44444444-0000-0000-0000-000000000000"
        func card(_ id: String, attacking: Bool) -> [String: Any] {
            ["instanceId": id, "card": ["name": "Creature", "typeLine": "Creature"], "isAttacking": attacking]
        }
        let players = try [
            player(viewer, battlefield: [card(first, attacking: true), card(second, attacking: false)], hand: [card(hiddenCard, attacking: true)]),
            player(second, battlefield: [card(opponentCard, attacking: true)])
        ]
        // All attackers may already be selected: the next engine highlight list is empty.
        let p = try prompt("SELECT", types: ["uuid", "boolean"], payload: ["selectMode": .string("attackers"), "options": .object(["possibleAttackers": .array([])])], revision: 38)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [], players: players)
        XCTAssertEqual(view.envelope.targets?.map(\.id), [first])
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope,
            type: "choose_target", promptId: p.id, playerId: viewer, ids: [first]))
        XCTAssertEqual(command.messageId, 38)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
        for wrong in [
            GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first]),
            GameCommand(type: "choose_target", gameId: "match", playerId: second, promptId: p.id, messageId: 38, targetIds: [first]),
            GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 38, targetIds: [first, second])
        ] { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer)) }
        let duplicate = try prompt("SELECT", types: ["uuid", "boolean"], payload: ["selectMode": .string("attackers"), "options": .object(["possibleAttackers": .array([.string(first)])])])
        XCTAssertEqual(try OnDevicePromptAdapter.presentation(duplicate, viewerPlayerID: viewer, cards: [], players: players).envelope.targets?.map(\.id), [first])
        let target = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(second)])])
        XCTAssertEqual(try OnDevicePromptAdapter.presentation(target, viewerPlayerID: viewer, cards: [], players: players).envelope.targets?.map(\.id), [second])
    }

    func testAskRoundTripsThroughExistingCommandBuilder() throws {
        let p = try prompt("ASK", types: ["boolean"])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.id, p.id)
        XCTAssertEqual(view.envelope.messageId, 37)
        XCTAssertEqual(view.envelope.playerId, viewer)
        XCTAssertEqual(view.envelope.confirmation?.yesLabel, "Yes")
        XCTAssertEqual(view.envelope.confirmation?.noLabel, "No")
        let yes = try XCTUnwrap(view.envelope.confirmation?.yesCommand)
        XCTAssertEqual(yes.confirmed, true)
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope, type: try XCTUnwrap(yes.type), promptId: p.id, playerId: viewer, ids: ["true"]))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(true)))
    }

    func testAskUsesPlainEngineButtonLabelsWithoutChangingBooleans() throws {
        let p = try prompt("ASK", types: ["boolean"], payload: ["options": .object(["UI.left.btn.text": .string("<html><b>Mulligan</b><br>to 6 &amp; draw</html>"), "UI.right.btn.text": .string("<html><b>Keep</b> &#55;</html>")])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        let confirmation = try XCTUnwrap(view.envelope.confirmation)
        XCTAssertEqual(confirmation.yesLabel, "Mulligan to 6 & draw")
        XCTAssertEqual(confirmation.noLabel, "Keep 7")
        for (response, expected) in [(confirmation.yesCommand, true), (confirmation.noCommand, false)] {
            let response = try XCTUnwrap(response)
            XCTAssertEqual(response.confirmed, expected)
            let c = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope, type: try XCTUnwrap(response.type), promptId: p.id, playerId: viewer, ids: [expected ? "true" : "false"]))
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(expected)))
        }
    }

    func testRejectsSubmittedStaleAndOtherViewerCommands() throws {
        let p = try prompt("ASK", types: ["boolean"])
        for command in [
            GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: "old", messageId: 37, confirmed: true),
            GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 36, confirmed: true),
            GameCommand(type: "answer_yes_no", gameId: "match", playerId: "seat-1", promptId: p.id, messageId: 37, confirmed: true),
            GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, confirmed: true)
        ] { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer)) }
        let submitted = try prompt("ASK", types: ["boolean"], submitted: true)
        let command = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, confirmed: true)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: submitted, viewerPlayerID: viewer))
        XCTAssertThrowsError(try OnDevicePromptAdapter.presentation(submitted, viewerPlayerID: viewer, cards: []))
        XCTAssertThrowsError(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: "seat-1", cards: []))
    }

    func testPriorityPassAndExplicitSpecialWithoutInventedPlayActions() throws {
        let p = try prompt("SELECT", types: ["uuid", "boolean", "integer", "string", "mana"], payload: ["selectMode": .string("priority"), "manaPlayerId": .string(viewer), "options": .object(["specialButton": .string("Special action")])], min: -2147483648, max: 2147483647)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.method, "GAME_SELECT")
        XCTAssertEqual(view.legalActions.map(\.type), ["pass_priority", "resolve_choice"])
        let pass = GameCommand(type: "pass_priority", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: pass, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(true)))
        let special = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: ["special"])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: special, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("string", .string("special")))
        let card = GameCommand(type: "cast_spell", gameId: "match", playerId: viewer, cardInstanceId: first, promptId: p.id, messageId: 37)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: card, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
        let wrong = GameCommand(type: "choose_pile", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, pile: 1)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
    }

    func testModesPreserveEngineOrderAndSubmitOneUUID() throws {
        let p = try prompt("CHOOSE_MODE", types: ["uuid"], payload: ["choices": .object([first: .string("First"), second: .string("Second")]), "choiceOrder": .array([.string(second), .string(first)])], min: 2, max: 3)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.modes?.map(\.id), [second, first])
        XCTAssertEqual(view.envelope.maxChoices, 1)
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope, type: "choose_mode", promptId: p.id, playerId: viewer, ids: [second]))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(second)))
        let wrong = GameCommand(type: "choose_mode", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, modeIds: [viewer])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
    }

    func testChoiceKeysSpecialsAndOptionalCancelRemainExact() throws {
        let p = try prompt("CHOOSE_CHOICE", types: ["string"], payload: ["required": .bool(false), "choices": .object(["z": .string("Last label"), "a": .string("First label")]), "choiceOrder": .array([.string("z"), .string("a")]), "specialEnabled": .bool(true), "specialText": .string("Remember"), "specialChoices": .object(["#z": .string("Last label"), "#a": .string("First label")])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.choices?.map(\.id), ["z", "a", "#z", "#a", ""])
        for key in ["z", "#a", ""] {
            let c = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: [key])
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("string", .string(key)))
        }
        for key in ["First label", "#", "#missing"] {
            let c = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: [key])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer))
        }
    }

    func testAbilityFamiliesUseAbilityUUIDAndRetainLabels() throws {
        for kind in ["CHOOSE_ABILITY", "PICK_ABILITY"] {
            let p = try prompt(kind, types: ["uuid", "boolean"], payload: ["required": .bool(false), "abilities": .array([.object(["id": .string(first), "label": .string("Cast Fire"), "sourceId": .string(second)])])])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            XCTAssertEqual(view.envelope.abilities?.first?.label, "Cast Fire")
            let c = GameCommand(type: "choose_ability", gameId: "match", playerId: viewer, abilityId: first, promptId: p.id, messageId: 37)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
            let wrong = GameCommand(type: "choose_ability", gameId: "match", playerId: viewer, abilityId: second, promptId: p.id, messageId: 37)
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
        }
    }

    func testAbilitySourceMetadataRetainsDuplicatesAndOmitsHiddenSources() throws {
        for kind in ["CHOOSE_ABILITY", "PICK_ABILITY"] {
            let card: MagicMobileOnDevice.JSONValue = .object(["id": .string(second), "name": .string("<b>Forest</b>"),
                "cardTypes": .array([.string("LAND")]), "rules": .array([.string("{T}: Add {G}.")])])
            let row: MagicMobileOnDevice.JSONValue = .object(["id": .string(first), "label": .string("<b>Add</b> {G}"),
                "sourceId": .string(second), "sourceCard": card])
            let p = try prompt(kind, types: ["uuid"], payload: ["abilities": .array([row, row])])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            let choices = try XCTUnwrap(view.envelope.abilities)
            XCTAssertEqual(choices.map(\.id), [first, first])
            XCTAssertEqual(choices.map(\.label), ["Add {G}", "Add {G}"])
            XCTAssertEqual(choices.map(\.sourceInstanceId), [second, second])
            XCTAssertEqual(choices.first?.sourceCard?.instanceId, second)
            XCTAssertEqual(choices.first?.sourceName, "Forest")
            XCTAssertEqual(choices.first?.sourceCard?.card.oracleText, "{T}: Add {G}.")
            XCTAssertNil(choices.first?.sourceUnavailableReason)
            let command = GameCommand(type: "choose_ability", gameId: "match", playerId: viewer,
                                      abilityId: first, promptId: p.id, messageId: 37)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer),
                           EnginePrompt.answer("uuid", .string(first)))
            XCTAssertEqual(p.payload["abilities"], .array([row, row]))
            var hidden = try XCTUnwrap(card.object); hidden["hideInfo"] = .bool(true)
            let unavailable = try prompt(kind, types: ["uuid"], payload: ["abilities": .array([
                .object(["id": .string(first), "label": .string("Add {G}"), "sourceId": .string(second), "sourceCard": .object(hidden)]),
                .object(["id": .string(first), "label": .string("Add {G}"), "sourceId": .string(second)])
            ])])
            let omitted = try OnDevicePromptAdapter.presentation(unavailable, viewerPlayerID: viewer, cards: [])
            for choice in try XCTUnwrap(omitted.envelope.abilities) {
                XCTAssertNil(choice.sourceCard); XCTAssertNil(choice.sourceName)
                XCTAssertEqual(choice.sourceUnavailableReason, "Source details unavailable")
            }
        }
    }

    func testAbilitySourceMetadataRequiresMatchingSourceIdentityAndSupportsLegacyRows() throws {
        for kind in ["CHOOSE_ABILITY", "PICK_ABILITY"] {
            let card: MagicMobileOnDevice.JSONValue = .object(["id": .string(second), "name": .string("Private source")])
            let rows: [MagicMobileOnDevice.JSONValue] = [
                .object(["id": .string(first), "label": .string("Legacy ability")]),
                .object(["id": .string(first), "label": .string("Missing source ID"), "sourceCard": card]),
                .object(["id": .string(first), "label": .string("Invalid source ID"), "sourceId": .string("invalid"), "sourceCard": card]),
                .object(["id": .string(first), "label": .string("Mismatched source"), "sourceId": .string(viewer), "sourceCard": card])
            ]
            let p = try prompt(kind, types: ["uuid"], payload: ["abilities": .array(rows)])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            let choices = try XCTUnwrap(view.envelope.abilities)
            XCTAssertEqual(choices.count, rows.count)
            XCTAssertEqual(choices.map(\.sourceInstanceId), [nil, nil, nil, viewer])
            for choice in choices {
                XCTAssertEqual(choice.id, first)
                XCTAssertNil(choice.sourceCard)
                XCTAssertNil(choice.sourceName)
                XCTAssertEqual(choice.sourceUnavailableReason, "Source details unavailable")
            }
        }
    }

    func testPileSelectionTranslatesToBooleanAndMapsOnlyExplicitCards() throws {
        let p = try prompt("CHOOSE_PILE", types: ["boolean"], payload: ["pile1": .array([.object(["id": .string(first), "name": .string("Forest"), "cardTypes": .array([.string("LAND")])])]), "pile2": .array([])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.piles?.map(\.id), ["1", "2"])
        XCTAssertEqual(view.envelope.piles?.first?.cards.first?.card.name, "Forest")
        for pile in [1, 2] {
            let c = GameCommand(type: "choose_pile", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, pile: pile)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(pile == 1)))
        }
        let wrong = GameCommand(type: "choose_pile", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, pile: 0)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
    }

    func testAmountsRespectSignedEngineBounds() throws {
        let p = try prompt("AMOUNT", types: ["integer"], min: -2, max: 4)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.responseCommand?.type, "choose_amount")
        XCTAssertEqual(view.envelope.minChoices, -2)
        XCTAssertEqual(view.envelope.maxChoices, 4)
        for amount in [-2, 4, -3, 5, Int.max] {
            let c = GameCommand(type: "choose_amount", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, amount: amount)
            if (-2...4).contains(amount) { XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("integer", .integer(Int64(amount)))) }
            else { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer)) }
        }
    }

    func testAmountButtonsExposePublishedNegativeRangeWithoutInventedBounds() throws {
        let p = try prompt("AMOUNT", types: ["integer"], min: -2, max: 4)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.amounts, [-2, -1, 0, 1, 2, 3, 4])
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope, type: "choose_amount", promptId: p.id, playerId: viewer, amount: -2))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("integer", .integer(-2)))
        let wide = try prompt("AMOUNT", types: ["integer"], min: -2147483648, max: 2147483647)
        let wideView = try OnDevicePromptAdapter.presentation(wide, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(wideView.envelope.method, "GAME_GET_AMOUNT")
        XCTAssertEqual(wideView.envelope.responseCommand?.type, "choose_amount")
        XCTAssertEqual(wideView.envelope.minChoices, -2147483648)
        XCTAssertEqual(wideView.envelope.maxChoices, 2147483647)
        XCTAssertNil(wideView.envelope.amounts)
    }

    func testAllocationsEnforceRowsSumAndExplicitCancellation() throws {
        let p = try prompt("MULTI_AMOUNT", types: ["integers", "boolean"], payload: ["options": .object(["canCancel": .bool(true)]), "allocations": .array([.object(["message": .string("First"), "min": .integer(0), "max": .integer(3), "defaultValue": .integer(1)]), .object(["message": .string("Second"), "min": .integer(1), "max": .integer(4), "defaultValue": .integer(2)])])], min: 3, max: 3)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.method, "GAME_GET_MULTI_AMOUNT")
        XCTAssertEqual(view.envelope.totalMin, 3)
        XCTAssertEqual(view.envelope.multiAmounts?.map(\.defaultValue), [1, 2])
        for amounts in [[1, 2], [0, 3], [1, 1], [3, 0], [3], [Int.max, 1]] {
            let c = GameCommand(type: "choose_multi_amount", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, amounts: amounts)
            if amounts == [1, 2] || amounts == [0, 3] { XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("integers", .array(amounts.map { .integer(Int64($0)) }))) }
            else { XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer)) }
        }
        let cancel = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, confirmed: false)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: cancel, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(false)))
    }

    func testManaUsesPayloadPlayerIdentityAndExactNamedColors() throws {
        for kind in ["PLAY_MANA", "PLAY_X_MANA", "SELECT"] {
            let types = kind == "PLAY_MANA" ? ["uuid", "boolean", "mana", "string"] : ["uuid", "boolean", "mana", "integer"]
            let p = try prompt(kind, types: types, payload: ["manaPlayerId": .string(second), "selectMode": .string("priority")], min: 0, max: 2147483647)
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            if kind != "SELECT" { XCTAssertEqual(view.manaPayment?.active, true) }
            let c = GameCommand(type: "play_mana", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, manaType: "G")
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("mana", .object(["playerId": .string(second), "manaType": .string("GREEN")])))
            let wrong = GameCommand(type: "play_mana", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, manaType: "green")
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
        }
        let x = try prompt("PLAY_X_MANA", types: ["uuid", "boolean", "mana", "integer"], payload: ["manaPlayerId": .string(viewer)], min: 0, max: 2147483647)
        let c = GameCommand(type: "play_x_mana", gameId: "match", playerId: viewer, promptId: x.id, messageId: 37, amount: 5)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: x, viewerPlayerID: viewer), EnginePrompt.answer("integer", .integer(5)))
    }

    func testManaCancelUsesInlinePaymentActionAndSendsOnlyBooleanFalse() throws {
        for kind in ["PLAY_MANA", "PLAY_X_MANA"] {
            let p = try prompt(kind, types: ["uuid", "boolean", "mana"], payload: ["manaPlayerId": .string(viewer)])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            let action = try XCTUnwrap(view.legalActions.first { $0.type == "cancel_payment" })
            XCTAssertEqual(action.label, "Cancel")
            XCTAssertEqual(action.confirmed, false)
            let c = GameCommand(type: action.type, gameId: "match", playerId: action.playerId, promptId: action.promptId, messageId: action.messageId, confirmed: action.confirmed)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(false)))
            let withoutBoolean = try prompt(kind, types: ["uuid", "mana"], payload: ["manaPlayerId": .string(viewer)])
            XCTAssertFalse(try OnDevicePromptAdapter.presentation(withoutBoolean, viewerPlayerID: viewer, cards: []).legalActions.contains { $0.type == "cancel_payment" })
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: withoutBoolean, viewerPlayerID: viewer))
            let wrongPrompt = try prompt("ASK", types: ["boolean"])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: wrongPrompt, viewerPlayerID: viewer))
        }
    }

    func testCombatSelectUsesSequentialUUIDTogglesAndBooleanDone() throws {
        for mode in ["attackers", "blockers"] {
            let key = mode == "attackers" ? "possibleAttackers" : "possibleBlockers"
            let p = try prompt("SELECT", types: ["uuid", "boolean", "integer"], payload: ["selectMode": .string(mode), "options": .object([key: .array([.string(first), .string(second)])])], min: -2147483648, max: 2147483647)
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            XCTAssertEqual(view.envelope.targets?.map(\.id), [first, second])
            XCTAssertEqual(view.envelope.maxChoices, 1)
            let c = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first])
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
            let done = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, confirmed: true)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: done, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(true)))
            let batch = GameCommand(type: "declare_attackers", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, attackers: [AttackDeclaration(attackerId: first, defenderId: second)])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: batch, prompt: p, viewerPlayerID: viewer))
        }
    }

    func testTargetPromptCardsAndFaceAliasesRemainExplicit() throws {
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)]), "cards": .array([.object(["id": .string(first), "name": .string("Bala Ged Recovery"), "cardTypes": .array([.string("SORCERY")]), "rules": .array([.string("Return target card from your graveyard to your hand.")])])]), "responseAliases": .object([second: .string(first)])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.cards?.first?.id, first)
        XCTAssertEqual(view.envelope.cards?.first?.card.typeLine, "SORCERY")
        XCTAssertNil(view.envelope.cards?.first?.tapped)
        let c = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [second])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer))
        let canonical = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: canonical, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
    }

    func testTargetOrderingUsesExplicitOrderedViewsWithoutAddingZoneCards() throws {
        let firstView: MagicMobileOnDevice.JSONValue = .object(["id": .string(first), "name": .string("First card"), "cardTypes": .array([.string("LAND")])])
        let secondView: MagicMobileOnDevice.JSONValue = .object(["id": .string(second), "name": .string("Second card"), "cardTypes": .array([.string("CREATURE")])])
        let unrelated = ZoneCard(instanceId: viewer, card: CardIdentity(name: "Unrelated private card", typeLine: "LAND", oracleText: nil), tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil, power: nil, toughness: nil, isCreaturePermanent: nil, damage: nil, isAttacking: nil, blocking: nil, attachedToInstanceId: nil)
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first), .string(second)]), "cards": .array([firstView]), "options": .object(["orderedViews": .array([secondView, firstView]), "secondMessage": .string("Library order")])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [unrelated])
        XCTAssertEqual(view.envelope.cards?.map(\.id), [second, first])
        XCTAssertEqual(view.envelope.cards?.map { $0.card.name }, ["Second card", "First card"])
        XCTAssertEqual(view.envelope.targets?.count, 0)
        XCTAssertEqual(view.envelope.maxChoices, 1)
        let c = GameCommand(type: "order_items", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, orderedIds: [second])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(second)))
    }

    func testVisibleSearchCardsAreNotAllLegalTargets() throws {
        let p = try prompt("PICK_TARGET", types: ["uuid", "boolean"], payload: [
            "required": .bool(false), "candidates": .array([.string(first)]),
            "cards": .array([first, second].map { .object(["id": .string($0), "name": .string($0 == first ? "Valid land" : "Visible creature"), "cardTypes": .array([.string("CARD")])]) })
        ])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.cards?.map(\.id), [first, second])
        XCTAssertEqual(view.envelope.cards?.map(\.isPromptSelectable), [true, false])
        XCTAssertEqual(view.envelope.targetIds, [first])
        let illegal = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [second])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: illegal, prompt: p, viewerPlayerID: viewer))
    }

    func testSearchEligibilityUsesPossibleAndChosenNotBrowseableCandidates() throws {
        for possible in [true, false] {
            var options: [String: MagicMobileOnDevice.JSONValue] = ["chosenTargets": .array([])]
            if possible { options["possibleTargets"] = .array([.string(first)]) }
            let p = try prompt("PICK_TARGET", types: ["uuid", "boolean"], payload: [
                "required": .bool(false), "candidates": .array([.string(first), .string(second)]), "options": .object(options),
                "cards": .array([first, second].map { .object(["id": .string($0), "name": .string("Visible card")]) })
            ])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            XCTAssertEqual(view.envelope.cards?.map(\.isPromptSelectable), [possible, false])
            let invalid = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [second])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: invalid, prompt: p, viewerPlayerID: viewer))
            let done = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, confirmed: false)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: done, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(false)))
        }
    }

    func testHiddenPromptCardNeverExposesNameRulesOrSecondFace() throws {
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)]), "cards": .array([
            .object(["id": .string(first), "name": .string("Secret"), "hideInfo": .bool(true), "rules": .array([.string("Private rules")]),
                     "secondCardFace": .object(["id": .string(second), "name": .string("Secret reverse")])])
        ])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.cards?.count, 1)
        XCTAssertEqual(view.envelope.cards?.first?.card.name, "Face-down card")
        XCTAssertNil(view.envelope.cards?.first?.card.oracleText)
    }

    func testSearchFaceAliasIsSelectableOnlyWhenItsBaseIsLegal() throws {
        for legal in [false, true] {
            let p = try prompt("PICK_TARGET", types: ["uuid"], payload: [
                "candidates": .array([.string(first)]), "responseAliases": .object([second: .string(first)]),
                "cards": .array([.object(["id": .string(first), "name": .string("Front"),
                    "secondCardFace": .object(["id": .string(second), "name": .string("Back")])])]),
                "options": .object(["chosenTargets": .array([]), "possibleTargets": .array(legal ? [.string(first)] : [])])
            ])
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            XCTAssertEqual(view.envelope.cards?.map(\.isPromptSelectable), [legal])
            let command = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [second])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer))
            let canonical = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first])
            if legal {
                XCTAssertEqual(try OnDevicePromptAdapter.answer(for: canonical, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
            } else {
                XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: canonical, prompt: p, viewerPlayerID: viewer))
            }
        }
    }

    func testSearchChosenCardRemainsSelectableForDeselectionAndMalformedEligibilityFailsClosed() throws {
        for malformed in [false, true] {
            let p = try prompt("PICK_TARGET", types: ["uuid"], payload: [
                "candidates": .array([.string(first), .string(second)]),
                "cards": .array([.object(["id": .string(first), "name": .string("Chosen card")])]),
                "options": .object(["chosenTargets": malformed ? .string(first) : .array([.string(first)]),
                                    "possibleTargets": .array([])])
            ])
            let command = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first])
            if malformed {
                XCTAssertThrowsError(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: []))
                XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer))
            } else {
                XCTAssertEqual(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: []).envelope.targetIds, [first])
                XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
            }
        }
    }

    func testTargetWithoutCardPayloadUsesOnlyMatchingAuthorizedOffboardCard() throws {
        let graveyard = try player(viewer, hand: [["instanceId": first, "card": ["name": "Visible card", "typeLine": "Creature"]]])
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first), .string(second)])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: graveyard.zones.hand)
        XCTAssertEqual(view.envelope.cards?.map(\.id), [first])
        XCTAssertEqual(view.envelope.targets?.map(\.id), [second], "Unknown IDs must not manufacture hidden cards")
    }

    func testPlayerTargetsUseFourPlayerNamesAndStillSubmitTargetUUIDs() throws {
        let third = "33333333-0000-0000-0000-000000000000"
        let zones = PlayerZones(library: [], hand: [], battlefield: [], graveyard: [], exile: [], command: [], stack: [])
        let players = [(viewer, "Local"), (first, "Alice"), (second, "Bri"), (third, "Cam")].map { id, name in
            PlayerGameState(playerId: id, displayName: name, life: 40, poison: 0, commanderTax: 0, manaPool: nil, zones: zones, commanderDamage: nil)
        }
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([viewer, first, second, third].map { .string($0) }), "cards": .array([])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [], players: players)
        XCTAssertEqual(view.envelope.method, "GAME_PICK_TARGET")
        XCTAssertEqual(view.envelope.targets?.map(\.label), ["You", "Alice", "Bri", "Cam"])
        XCTAssertEqual(view.envelope.responseCommand?.type, "choose_target")
        let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope, type: "choose_target", promptId: p.id, playerId: viewer, ids: [third]))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(third)))
    }

    func testNativeStartingPromptFeedsRollAndAcceptsWinner() throws {
        let players = [try player(viewer), try player(first)]
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: [
            "message": .string("Select a starting player"),
            "candidates": .array([.string(viewer), .string(first)])
        ])
        let presented = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer,
                                                               cards: [], players: players)
        let snapshot = GameSnapshot(
            id: "match", source: "xmage-ondevice", activePlayerId: nil,
            phase: "beginning", step: nil, turn: 0, priorityPlayerId: nil,
            waitingOnPlayerId: viewer, promptText: presented.envelope.message,
            players: players, log: [], legalActions: presented.legalActions,
            choicePrompt: nil, promptEnvelope: nil, promptEnvelopeV2: presented.envelope,
            startupOpeningPrompts: nil, xmage: nil, engineHealth: nil,
            bridgeRevision: 37, xmageCycle: nil, pendingStatus: nil,
            manaPayment: nil, gameStatus: nil, winnerPlayerIds: nil, endReason: nil,
            viewerPlayerId: viewer
        )
        XCTAssertEqual(OnDeviceStartingPlayerChoice.candidateIDs(snapshot: snapshot), [viewer, first])
        let command = try XCTUnwrap(OnDeviceStartingPlayerChoice.command(snapshot: snapshot,
                                                                         winnerPlayerID: first))
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p,
                                                        viewerPlayerID: viewer),
                       EnginePrompt.answer("uuid", .string(first)))
    }

    func testExplicitSecondCardFaceSuppliesItsAliasLabelAndCard() throws {
        let face: MagicMobileOnDevice.JSONValue = .object(["id": .string(second), "name": .string("Bala Ged Sanctuary"), "cardTypes": .array([.string("LAND")])])
        let front: MagicMobileOnDevice.JSONValue = .object(["id": .string(first), "name": .string("Bala Ged Recovery"), "cardTypes": .array([.string("SORCERY")]), "secondCardFace": face])
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)]), "responseAliases": .object([second: .string(first)]), "cards": .array([front])])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.cards?.map(\.id), [first])
        XCTAssertEqual(view.envelope.cards?.first?.card.name, "Bala Ged Recovery")
        XCTAssertEqual(view.envelope.targets?.count, 0)
    }

    func testFaceAliasesDeduplicateAndDoNotExposePrivateCards() throws {
        let hidden = "33333333-0000-0000-0000-000000000000"
        let front: MagicMobileOnDevice.JSONValue = .object([
            "id": .string(first), "name": .string("Visible front"), "cardTypes": .array([.string("SORCERY")])
        ])
        let privateCard = ZoneCard(instanceId: hidden,
            card: CardIdentity(name: "Private card", typeLine: "CREATURE", oracleText: nil),
            tapped: nil, summoningSickness: nil, cardIcons: nil, counters: nil, power: nil,
            toughness: nil, isCreaturePermanent: nil, damage: nil, isAttacking: nil,
            blocking: nil, attachedToInstanceId: nil)
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: [
            "candidates": .array([.string(first), .string(second)]),
            "responseAliases": .object([second: .string(first)]),
            "cards": .array([front]),
            "options": .object(["chosenTargets": .array([.string(second), .string(first)])])
        ])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [privateCard])
        XCTAssertEqual(view.envelope.targetIds, [first])
        XCTAssertEqual(view.envelope.cards?.filter(\.isPromptSelectable).map(\.id), [first])
        XCTAssertEqual(view.envelope.options?["chosenTargets"]?.stringArrayValue, [first])
        XCTAssertFalse(view.envelope.cards?.contains(where: { $0.card.name == "Private card" }) ?? true)
        let alias = GameCommand(type: "choose_target", gameId: "match", playerId: viewer,
                                promptId: p.id, messageId: 37, targetIds: [second])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: alias, prompt: p, viewerPlayerID: viewer))
    }

    func testSelectIntegerResponsesRetainEngineBoundsAndResponseType() throws {
        let p = try prompt("SELECT", types: ["uuid", "boolean", "integer"], payload: ["selectMode": .string("priority")], min: -2147483648, max: 2147483647)
        let c = GameCommand(type: "choose_amount", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, amount: 0)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("integer", .integer(0)))
        let noInteger = try prompt("SELECT", types: ["uuid", "boolean"], payload: ["selectMode": .string("priority")])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: noInteger, viewerPlayerID: viewer))
        let overflow = GameCommand(type: "choose_amount", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, amount: Int.max)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: overflow, prompt: p, viewerPlayerID: viewer))
    }

    func testUnsupportedVariantsAndWrongResponseTypesFailExplicitly() throws {
        for kind in ["PERSONAL_MESSAGE", "DRAFT_PICK_CARD", "TOURNAMENT_CONSTRUCT", "FUTURE_QUERY"] {
            let p = try prompt(kind, types: ["boolean"])
            XCTAssertThrowsError(try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: []))
        }
        let emptySpecial = try prompt("CHOOSE_CHOICE", types: ["string"], payload: ["choices": .object(["a": .string("Choice")]), "choiceOrder": .array([.string("a")]), "specialEnabled": .bool(true), "specialCanBeEmpty": .bool(true)])
        let choiceView = try OnDevicePromptAdapter.presentation(emptySpecial, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(choiceView.envelope.choices?.map(\.id), ["a"])
        XCTAssertFalse(choiceView.envelope.message.contains("unsupported"))
        XCTAssertEqual(choiceView.legalActions.map(\.type), ["choose_empty_special"])
        let normal = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: emptySpecial.id, messageId: 37, choiceIds: ["a"])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: normal, prompt: emptySpecial, viewerPlayerID: viewer), EnginePrompt.answer("string", .string("a")))
        let wrongTypes = try prompt("ASK", types: ["integer"])
        let c = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: wrongTypes.id, messageId: 37, confirmed: true)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: wrongTypes, viewerPlayerID: viewer))
        XCTAssertThrowsError(try OnDevicePromptAdapter.presentation(wrongTypes, viewerPlayerID: viewer, cards: []))
    }

    func testTargetCommandReadsOnlyItsDeclaredSelectionField() throws {
        let p = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)])])
        let malformed = GameCommand(type: "choose_card", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: malformed, prompt: p, viewerPlayerID: viewer))
        let valid = GameCommand(type: "choose_card", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, cardInstanceIds: [first])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: valid, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(first)))
    }

    func testEmptySpecialHasDistinctActionAndTypedNullWithExactMetadata() throws {
        let metadata: [String: MagicMobileOnDevice.JSONValue] = ["choices": .object(["a": .string("Normal choice")]), "choiceOrder": .array([.string("a")]), "specialEnabled": .bool(true), "specialCanBeEmpty": .bool(true), "specialText": .string("<b>Choose no item</b>")]
        let p = try prompt("CHOOSE_CHOICE", types: ["string"], payload: metadata)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.choices?.map(\.id), ["a"])
        let action = try XCTUnwrap(view.legalActions.first { $0.type == "choose_empty_special" })
        XCTAssertEqual(action.label, "Choose no item")
        let c = GameCommand(type: action.type, gameId: "match", playerId: action.playerId, promptId: action.promptId, messageId: action.messageId)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: c, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("string", .null))
        for flags in [(false, true), (true, false), (false, false)] {
            var fields = metadata
            fields["specialEnabled"] = .bool(flags.0); fields["specialCanBeEmpty"] = .bool(flags.1)
            let other = try prompt("CHOOSE_CHOICE", types: ["string"], payload: fields)
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: other, viewerPlayerID: viewer))
            XCTAssertFalse(try OnDevicePromptAdapter.presentation(other, viewerPlayerID: viewer, cards: []).legalActions.contains { $0.type == "choose_empty_special" })
        }
        let wrongKind = try prompt("ASK", types: ["string"], payload: metadata)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: wrongKind, viewerPlayerID: viewer))
        let wrongType = try prompt("CHOOSE_CHOICE", types: ["boolean"], payload: metadata)
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: c, prompt: wrongType, viewerPlayerID: viewer))
        for token in ["#", ""] {
            let wrong = GameCommand(type: "resolve_choice", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: [token])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: wrong, prompt: p, viewerPlayerID: viewer))
        }
        let mixed = GameCommand(type: "choose_empty_special", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, choiceIds: ["a"])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: mixed, prompt: p, viewerPlayerID: viewer))
    }

    func testCommanderAskPreservesAuthoritativeConfirmationInsteadOfMessageHeuristic() throws {
        let p = try prompt("ASK", types: ["boolean"], payload: [
            "message": .string("Move your commander to the command zone?"),
            "options": .object(["UI.left.btn.text": .string("Move commander"), "UI.right.btn.text": .string("Leave in graveyard")])
        ])
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        // Both the compact popup and full details renderer use this decision.
        XCTAssertFalse(PromptCommandBuilder.isCommanderReplacement(view.envelope))
        let confirmation = try XCTUnwrap(view.envelope.confirmation)
        XCTAssertEqual(confirmation.yesLabel, "Move commander")
        XCTAssertEqual(confirmation.noLabel, "Leave in graveyard")
        for (provided, answer) in [(confirmation.yesCommand, true), (confirmation.noCommand, false)] {
            let provided = try XCTUnwrap(provided)
            let command = try XCTUnwrap(PromptCommandBuilder.command(gameId: "match", promptEnvelope: view.envelope,
                type: try XCTUnwrap(provided.type), promptId: try XCTUnwrap(provided.promptId), playerId: viewer,
                ids: [answer ? "true" : "false"]))
            XCTAssertEqual(command.messageId, 37)
            XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(answer)))
        }
    }

    func testTargetsUseOneUUIDPerPromptAndOnlyExplicitCandidates() throws {
        let p = try prompt("PICK_TARGET", types: ["uuid", "boolean"], payload: ["required": .bool(false), "candidates": .array([.string(first), .string(second)]), "options": .object(["chosenTargets": .array([.string(second)]), "targetZone": .string("HAND"), "UI.right.btn.text": .string("Done")])], min: 2, max: 3)
        let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
        XCTAssertEqual(view.envelope.minChoices, 1)
        XCTAssertEqual(view.envelope.maxChoices, 1)
        XCTAssertEqual(view.envelope.targets?.map(\.id), [first, second])
        let one = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [second])
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: one, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(second)))
        let batch = GameCommand(type: "choose_target", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, targetIds: [first, second])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: batch, prompt: p, viewerPlayerID: viewer))
        let done = GameCommand(type: "answer_yes_no", gameId: "match", playerId: viewer, promptId: p.id, messageId: 37, confirmed: false)
        XCTAssertEqual(try OnDevicePromptAdapter.answer(for: done, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("boolean", .bool(false)))
        let required = try prompt("PICK_TARGET", types: ["uuid"], payload: ["candidates": .array([.string(first)])])
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: done, prompt: required, viewerPlayerID: viewer))
        XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: one, prompt: required, viewerPlayerID: viewer))
    }

    func testSixSacrificeProgressRetainsRemainingAndRemovableTargetsWithExplicitCancel() throws {
        let ids = (1...7).map { String(format: "00000000-0000-0000-0000-%012d", $0) }
        for chosen in 0...5 {
            let p = try prompt("PICK_TARGET", types: ["uuid", "boolean"], payload: [
                "required": .bool(false), "message": .string("Sacrifice permanents (selected \(chosen) of 6, min 6)"),
                "candidates": .array(ids.map { .string($0) }), "cards": .array([]),
                "options": .object(["chosenTargets": .array(ids.prefix(chosen).map { .string($0) }), "targetZone": .string("BATTLEFIELD")])
            ], revision: Int64(37 + chosen))
            let view = try OnDevicePromptAdapter.presentation(p, viewerPlayerID: viewer, cards: [])
            XCTAssertEqual(view.envelope.targets?.map(\.id), ids)
            XCTAssertEqual(view.envelope.minChoices, 1)
            XCTAssertEqual(view.envelope.maxChoices, 1)
            XCTAssertEqual(view.legalActions.first { $0.type == "answer_yes_no" }?.label, "Cancel")
            for id in ids {
                let command = GameCommand(type: "choose_target", gameId: "match", playerId: viewer,
                    promptId: p.id, messageId: 37 + chosen, targetIds: [id])
                XCTAssertEqual(try OnDevicePromptAdapter.answer(for: command, prompt: p, viewerPlayerID: viewer), EnginePrompt.answer("uuid", .string(id)))
            }
            let stale = GameCommand(type: "choose_target", gameId: "match", playerId: viewer,
                promptId: p.id, messageId: 36 + chosen, targetIds: [ids[chosen]])
            XCTAssertThrowsError(try OnDevicePromptAdapter.answer(for: stale, prompt: p, viewerPlayerID: viewer))
        }
    }
}
