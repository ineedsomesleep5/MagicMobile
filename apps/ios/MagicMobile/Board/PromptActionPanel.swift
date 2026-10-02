import SwiftUI
import PhotosUI
import UIKit

struct UniversalPromptActionPanel: View {
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    let snapshot: GameSnapshot
    let selectedCardActions: [LegalAction]
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    @State private var orderPromptId: String?
    @State private var orderedIds: [String] = []
    @State private var multiAmountPromptId: String?
    @State private var multiAmountValues: [String: Int] = [:]
    @State private var manualAmountValues: [String: Int] = [:]
    @State private var selectedSearchPromptId: String?
    @State private var selectedSearchCardIds: [String] = []
    @State private var choiceSearch = ""
    @Environment(\.dismiss) private var dismiss
    let pendingActionId: String?
    let runAction: (LegalAction) -> Void
    let runCommand: (GameCommand, String, String) -> Void
    let viewZone: (String, [ZoneCard]) -> Void
    var showsGameSurfaceSections = true

    private var passActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase"].contains($0.type)
        }
    }

    private var spellsAndLands: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["play_land", "cast_spell"].contains($0.type)
        }
    }

    private var abilitiesAndMana: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            ["activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability"].contains($0.type)
        }
    }

    private var sourceManaActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            $0.type == "make_mana" && ($0.sourceInstanceId != nil || $0.cardInstanceId != nil)
        }
    }

    private var otherActions: [LegalAction] {
        let types = ["pass_priority", "pass_until_response", "resolve_stack", "pass_until_stack_resolved", "end_turn", "pass_until_end_of_turn", "yield_until_next_turn", "pass_until_next_turn", "advance_phase",
                     "play_land", "cast_spell",
                     "activate_ability", "make_mana", "play_mana", "choose_mana", "choose_ability"]
        return (snapshot.legalActions ?? []).filter {
            !types.contains($0.type)
        }
    }

    private var promptPresentation: MobilePromptPresentation? {
        MobilePromptPresentation.make(snapshot: snapshot, legalActions: snapshot.legalActions ?? [])
    }

    @Environment(\.tavernBoard) private var tavern

    /// The tavern's leather title bar: the prompt in engraved gold, whose turn it is on a tag
    /// and a wax seal to close.
    private var tavernHeader: some View {
        HStack(spacing: 8) {
            TavernPanelTitle(text: promptPresentation?.title ?? "Prompt")
            Spacer(minLength: 4)
            TavernTag(text: priorityLabel, leather: true)
            Button {
                GameHaptics.selection()
                dismiss()
            } label: {
                TavernSealLabel()
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel prompt details")
            .accessibilityHint("Returns to the battlefield without submitting a choice")
        }
        .modifier(TavernTitleBar())
    }

    private var classicHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Text(promptPresentation?.title.uppercased() ?? "PROMPT")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.antiqueGold)
            Spacer(minLength: 4)
            Text(priorityLabel)
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Group {
                Button {
                    GameHaptics.selection()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(IconButtonStyle(small: true))
                .accessibilityLabel("Cancel prompt details")
                .accessibilityHint("Returns to the battlefield without submitting a choice")
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if tavern && TavernUIKit.available {
                tavernHeader
            } else {
                classicHeader
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let promptPresentation, snapshot.promptEnvelopeV2 == nil, snapshot.promptEnvelope == nil {
                        PromptPanelSection(title: "Choose", detail: "", isHighlighted: promptPresentation.isUnsupported) {
                            GameRulesText(source: PromptDisplayText.clean(promptPresentation.message), symbolSize: 16)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(promptPresentation.isUnsupported ? MagicPalette.warningAmber : .white.opacity(0.78))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let prompt = snapshot.promptEnvelopeV2 {
                        promptEnvelopeV2Section(prompt)
                    } else if let prompt = snapshot.promptEnvelope {
                        promptEnvelopeSection(prompt)
                    }

                    if let prompt = snapshot.choicePrompt {
                        choicePromptSection(prompt)
                    }

                    if showsGameSurfaceSections {
                        if !selectedCardActions.isEmpty, let selectedCard {
                            actionSection(
                                title: "Selected",
                                detail: selectedCard.card.name,
                                actions: selectedCardActions
                            )
                        } else if let selectedCard, selectedCardIsInHumanHand(selectedCard) {
                            selectedCardUnavailableSection(selectedCard)
                        }

                        if !spellsAndLands.isEmpty {
                            actionSection(title: "Spells & Lands", detail: "\(spellsAndLands.count)", actions: spellsAndLands)
                        }
                        if !abilitiesAndMana.isEmpty {
                            actionSection(title: "Abilities & Mana", detail: "\(abilitiesAndMana.count)", actions: abilitiesAndMana)
                        }
                        if !passActions.isEmpty {
                            actionSection(title: "Pass / Steps", detail: "\(passActions.count)", actions: passActions, compact: !spellsAndLands.isEmpty || !abilitiesAndMana.isEmpty || !selectedCardActions.isEmpty)
                        }
                        if !otherActions.isEmpty {
                            actionSection(title: "Other Actions", detail: "\(otherActions.count)", actions: otherActions)
                        }

                        MobileSurfacesPanel(
                            snapshot: snapshot,
                            selectedCard: $selectedCard,
                            inspectedCard: $inspectedCard,
                            viewZone: viewZone
                        )
                    }
                }
                .padding(.vertical, 1)
                .padding(.bottom, 10)
            }
            .accessibilityIdentifier("prompt.details.scroll")
        }
        .padding(8)
        .background(
            LinearGradient(
                colors: [MagicPalette.iron.opacity(0.88), MagicPalette.leather.opacity(0.80), MagicPalette.laneWood.opacity(0.70)],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.borderBronze.opacity(0.46), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: 8, x: -3, y: 4)
        .overlay {
            if let inspectedCard {
                CardInspector(card: inspectedCard)
                    .overlay(alignment: .topTrailing) {
                        Button("Close card") { self.inspectedCard = nil }
                            .frame(minHeight: 44).padding(8)
                    }
                    .inspectionTouchPassthrough()
            }
        }
    }

    private var priorityLabel: String {
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "YOUR PRIORITY"
        }
        return snapshot.playerLabel(snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId)
    }

    @ViewBuilder
    private func promptEnvelopeV2Section(_ prompt: PromptEnvelopeV2) -> some View {
        PromptPanelSection(title: promptPresentation?.title ?? "Choose", detail: "", isHighlighted: true,
                           isEmbedded: true) {
            GameRulesText(source: PromptDisplayText.clean(prompt.message), symbolSize: 16)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)

            if isManaOrPaymentPrompt(prompt), !sourceManaActions.isEmpty {
                sourceManaActionSection(prompt)
            }

            if isCommanderReplacement(prompt) {
                HStack(spacing: 6) {
                    promptButton(
                        label: "Command zone",
                        pendingId: "\(prompt.id)-command-zone",
                        command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: true)
                    )
                    promptButton(
                        label: "Original zone",
                        pendingId: "\(prompt.id)-original-zone",
                        command: command(type: "commander_replacement", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, useCommandZone: false)
                    )
                }
            }

            if let confirmation = prompt.confirmation, isConfirmationPrompt(prompt) {
                confirmationPicker(confirmation: confirmation, prompt: prompt)
            }

            if let choices = prompt.choices, !choices.isEmpty {
                let matchingChoices = choices.filter {
                    choices.count <= 20 || choiceSearch.isEmpty ||
                        $0.label.localizedCaseInsensitiveContains(choiceSearch)
                }
                if choices.count > 20 {
                    TextField("Search choices", text: $choiceSearch,
                              prompt: tavern ? Text("Search choices").foregroundStyle(TavernPalette.ink.opacity(0.5)) : nil)
                        .modifier(TavernFieldChrome(tavern: tavern))
                        .accessibilityIdentifier("prompt.choices.search")
                        .onAppear { choiceSearch = "" }
                        .onChange(of: "\(prompt.id):\(prompt.messageId)") { _, _ in choiceSearch = "" }
                }
                if matchingChoices.isEmpty {
                    Text("No matching choices")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("prompt.choices.noMatches")
                } else {
                    optionGrid(matchingChoices.map { ($0.id, $0.label) }, prompt: prompt,
                               fallbackType: "resolve_choice", icon: "checkmark.circle")
                }
            }

            if let targets = prompt.targets, !targets.isEmpty {
                optionGrid(targets.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "choose_target", icon: "scope")
            }

            if let players = prompt.players, !players.isEmpty {
                optionGrid(players.map { ($0.playerId, playerPromptLabel($0)) }, prompt: prompt, fallbackType: "choose_player", icon: "person.crop.circle")
            }

            if let cards = prompt.cards, !cards.isEmpty {
                if isSearchPrompt(prompt) {
                    searchSelectionPicker(cards: cards, prompt: prompt)
                } else {
                    cardPicker(cards: cards, prompt: prompt)
                }
            }

            if let modes = prompt.modes, !modes.isEmpty {
                optionGrid(modes.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "choose_mode", icon: "square.stack.3d.up")
            }

            if let abilities = prompt.abilities, !abilities.isEmpty {
                abilityPicker(abilities: abilities, prompt: prompt)
            }

            if let piles = prompt.piles, !piles.isEmpty {
                pilePicker(piles: piles, prompt: prompt)
            }

            if let amounts = prompt.amounts, !amounts.isEmpty {
                amountPicker(amounts: amounts, prompt: prompt)
            } else if let multiAmounts = prompt.multiAmounts, !multiAmounts.isEmpty {
                multiAmountPicker(slots: multiAmounts, prompt: prompt)
            } else if isAmountPrompt(prompt) {
                manualAmountPicker(prompt: prompt)
            }

            if let orderedItems = prompt.orderedItems, !orderedItems.isEmpty {
                orderPicker(
                    title: "Order",
                    prompt: prompt,
                    type: "order_items",
                    options: orderedItems.map { ($0.id, $0.label) }
                )
            }

            if let manaChoices = prompt.manaChoices, !manaChoices.isEmpty {
                manaChoicePicker(choices: manaChoices, prompt: prompt)
            }

            if prompt.manaChoices?.isEmpty != false && isChooseColorPrompt(prompt) {
                colorChoicePicker(prompt: prompt)
            } else if prompt.manaChoices?.isEmpty != false && isManaPrompt(prompt) && !availableManaSymbols.isEmpty {
                manaPicker(prompt: prompt)
            }

            if isTriggerOrderPrompt(prompt) {
                orderPicker(
                    title: "Trigger order",
                    prompt: prompt,
                    type: "order_triggers",
                    options: orderOptions(for: prompt)
                )
            }

            if isSearchPrompt(prompt), prompt.cards?.isEmpty != false, prompt.targets?.isEmpty != false {
                placeholderSubmit(
                    title: "Search/select",
                    button: "Submit exposed selection",
                    prompt: prompt,
                    type: "search_select",
                    ids: prompt.targetIds ?? []
                )
            } else if isCardSelectionPrompt(prompt), prompt.cards?.isEmpty != false, prompt.targets?.isEmpty != false {
                placeholderSubmit(
                    title: "Select card on battlefield",
                    button: "Submit selected card",
                    prompt: prompt,
                    type: prompt.responseCommand?.type ?? "choose_card",
                    ids: selectedCard.map { [$0.id] } ?? prompt.targetIds ?? []
                )
            }

            if isPlayerSelectionPrompt(prompt), prompt.players?.isEmpty != false {
                optionGrid(snapshot.players.map { ($0.playerId, snapshot.playerLabel($0.playerId)) }, prompt: prompt, fallbackType: prompt.responseCommand?.type ?? "choose_player", icon: "person.crop.circle")
            }

            if isDamageAssignmentPrompt(prompt), prompt.multiAmounts?.isEmpty != false {
                unsupportedDamageAssignment(prompt)
            }

            if !hasRenderablePromptControls(prompt) {
                Text("Unsupported prompt/action: XMage has not exposed a mobile-safe control for this route yet.")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.warningAmber.opacity(0.90))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        }
    }

    @ViewBuilder
    private func promptEnvelopeSection(_ prompt: PromptEnvelope) -> some View {
        PromptPanelSection(title: "Choose", detail: "", isHighlighted: true) {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            if let choices = prompt.choices, !choices.isEmpty {
                legacyOptionGrid(choices.map { ($0.id, $0.label) }, prompt: prompt, fallbackType: "resolve_choice")
            }

            if let targetIds = prompt.targetIds, !targetIds.isEmpty {
                legacyOptionGrid(targetIds.map { ($0, $0) }, prompt: prompt, fallbackType: "choose_target")
            }

            if prompt.choices?.isEmpty != false && prompt.targetIds?.isEmpty != false {
                unsupportedPromptFallback(method: prompt.method, responseKind: prompt.responseKind)
            }
        }
    }

    @ViewBuilder
    private func choicePromptSection(_ prompt: ChoicePrompt) -> some View {
        PromptPanelSection(title: "Choice", detail: "\(prompt.minChoices)-\(prompt.maxChoices)", isHighlighted: true) {
            Text(prompt.message)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.86))
                .lineLimit(3)
                .minimumScaleFactor(0.68)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
                ForEach(prompt.choices) { choice in
                    let action = action(for: choice, promptId: prompt.id)
                    Button {
                        if let action {
                            runAction(action)
                        } else if let command = command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) {
                            runCommand(command, choice.label, "\(prompt.id)-\(choice.id)")
                        }
                    } label: {
                        PromptButtonLabel(
                            title: choice.label,
                            systemImage: yesNoIcon(choice.label),
                            isPending: pendingActionId == action?.id || pendingActionId == "\(prompt.id)-\(choice.id)"
                        )
                    }
                    .buttonStyle(PanelActionButtonStyle(isPrimary: action?.isPrimary == true))
                    .disabled(pendingActionId != nil || (action == nil && command(type: "resolve_choice", promptId: prompt.id, playerId: prompt.playerId, ids: [choice.id]) == nil))
                }
            }
        }
    }

    @ViewBuilder
    private func actionSection(title: String, detail: String, actions: [LegalAction], compact: Bool = false) -> some View {
        PromptPanelSection(title: title, detail: detail) {
            if actions.isEmpty {
                Text("No exposed actions")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.48))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: compact ? 72 : 98), spacing: 6)], spacing: 6) {
                    ForEach(actions) { action in
                        let directlyRunnable = isDirectlyRunnable(action)
                        Button {
                            if directlyRunnable {
                                runAction(action)
                            }
                        } label: {
                            PromptButtonLabel(
                                title: GameplayActionPresentation.title(for: action, snapshot: snapshot),
                                subtitle: directlyRunnable ? action.actionDetail : "Use prompt picker",
                                systemImage: action.systemImage,
                                isPending: pendingActionId == action.id
                            )
                        }
                        .buttonStyle(PanelActionButtonStyle(isDanger: action.type == "concede", isPrimary: action.isPrimary == true || isCastOrPlay(action), compact: compact))
                        .disabled(pendingActionId != nil || !directlyRunnable)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectedCardUnavailableSection(_ card: ZoneCard) -> some View {
        PromptPanelSection(title: "Selected", detail: card.card.name) {
            Text(selectedCardBlockedReason(card))
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.72))
                .lineLimit(3)
                .minimumScaleFactor(0.72)
            Button {
                inspectedCard = card
            } label: {
                PromptButtonLabel(title: "Inspect", subtitle: "Long press cards also opens this", systemImage: "doc.text.magnifyingglass", isPending: false)
            }
            .buttonStyle(PanelActionButtonStyle())
            .disabled(pendingActionId != nil)
        }
    }

    @ViewBuilder
    private func sourceManaActionSection(_ prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel(prompt.responseCommand?.type?.lowercased() == "pay_cost" ? "Pay with sources" : "Available mana sources")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], spacing: 6) {
            ForEach(sourceManaActions) { action in
                Button {
                    runAction(action)
                } label: {
                    PromptButtonLabel(
                        title: "Tap \(sourceCardName(for: action))",
                        subtitle: producedManaLabel(for: action),
                        systemImage: "sparkles",
                        isPending: pendingActionId == action.id
                    )
                }
                .buttonStyle(PanelActionButtonStyle(isPrimary: true))
                .disabled(pendingActionId != nil)
            }
        }
    }

    @ViewBuilder
    private func optionGrid(_ options: [(String, String)], prompt: PromptEnvelopeV2, fallbackType: String, icon: String) -> some View {
        let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: fallbackType)
        // Modes and other sentence-length options get full-width rows so the whole text is readable.
        if options.contains(where: { PromptDisplayText.clean($0.1).count > 16 }) {
            VStack(spacing: 8) {
                ForEach(options, id: \.0) { option in
                    promptButton(
                        label: option.1,
                        systemImage: yesNoIcon(option.1) ?? icon,
                        pendingId: "\(prompt.id)-\(option.0)",
                        command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [option.0]),
                        large: true
                    )
                }
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(options, id: \.0) { option in
                    promptButton(
                        label: option.1,
                        systemImage: yesNoIcon(option.1) ?? icon,
                        pendingId: "\(prompt.id)-\(option.0)",
                        command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [option.0])
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func legacyOptionGrid(_ options: [(String, String)], prompt: PromptEnvelope, fallbackType: String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 6)], spacing: 6) {
            ForEach(options, id: \.0) { option in
                promptButton(
                    label: option.1,
                    systemImage: yesNoIcon(option.1),
                    pendingId: "\(prompt.id)-\(option.0)",
                    command: command(type: fallbackType, promptId: prompt.id, playerId: prompt.playerId, ids: [option.0])
                )
            }
        }
    }

    @ViewBuilder
    private func cardPicker(cards: [ZoneCard], prompt: PromptEnvelopeV2) -> some View {
        let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: isSearchPrompt(prompt) ? "search_select" : "choose_card")
        let selectedPromptCardId = PromptSelectionRules.selectedPromptCardId(selectedCard: selectedCard, validCards: cards)
        let hasValidSelection = selectedPromptCardId != nil && PromptSelectionRules.isValidSelectedCount(1, minChoices: prompt.minChoices ?? 1, maxChoices: prompt.maxChoices ?? 1)
        VStack(alignment: .leading, spacing: 7) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(cards) { card in
                        VStack(spacing: 4) {
                            CardTile(card: card, selected: selectedCard?.id == card.id || selectedCard?.instanceId == card.instanceId, legal: true, zoneName: "Prompt", width: 42, height: 59)
                                .onCardInteraction(tap: {
                                    if selectedCard?.instanceId == card.instanceId {
                                        selectedCard = nil
                                    } else {
                                        selectedCard = card
                                    }
                                    inspectedCard = nil
                                    GameHaptics.selection()
                                }, inspect: {
                                    inspectedCard = card
                                    GameHaptics.impact()
                                }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                            Text(card.card.name)
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white.opacity(0.74))
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(width: 70)
                        }
                    }
                }
            }
            HStack(spacing: 7) {
                if selectedPromptCardId != nil {
                    Button {
                        selectedCard = nil
                        GameHaptics.selection()
                    } label: {
                        PromptButtonLabel(title: "Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(PanelActionButtonStyle())
                    .disabled(pendingActionId != nil)
                    .accessibilityHint("Clears the selected card")
                }

                promptButton(
                    label: "Confirm Card",
                    subtitle: selectedPromptCardId == nil ? "Select a card first" : selectedCard?.card.name,
                    systemImage: "checkmark.circle",
                    pendingId: "\(prompt.id)-choose-card",
                    command: hasValidSelection && selectedPromptCardId != nil
                        ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [selectedPromptCardId!])
                        : nil
                )
            }
        }
    }

    @ViewBuilder
    private func searchSelectionPicker(cards: [ZoneCard], prompt: PromptEnvelopeV2) -> some View {
        let selectableIds = cards.filter(\.isPromptSelectable).map(\.instanceId)
        let selectedIds = currentSearchSelection(promptId: prompt.id, validIds: selectableIds)
        let selectedCount = selectedIds.count
        let valid = PromptSelectionRules.isValidSelectedCount(selectedCount, minChoices: prompt.minChoices, maxChoices: prompt.maxChoices)
        let type = idCommandType(preferred: prompt.responseCommand?.type, fallback: "search_select")

        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                PromptMiniLabel(searchZoneName(for: prompt))
                Spacer(minLength: 4)
                Text("\(selectedCount) selected · \(PromptSelectionRules.boundsText(minChoices: prompt.minChoices, maxChoices: prompt.maxChoices))")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(valid ? MagicPalette.legalEmerald.opacity(0.86) : MagicPalette.warningAmber.opacity(0.86))
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                if selectedCount > 0 {
                    Button("Clear") {
                        selectedSearchPromptId = prompt.id
                        selectedSearchCardIds = []
                        GameHaptics.selection()
                    }
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(pendingActionId != nil)
                    .accessibilityHint("Clears all selected cards")
                }
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 7)], spacing: 7) {
                    ForEach(cards) { card in
                        let selectable = card.isPromptSelectable
                        let isSelected = selectedIds.contains(card.instanceId)
                        Button {
                            guard selectable else { return }
                            toggleSearchSelection(promptId: prompt.id, cardId: card.instanceId, validIds: selectableIds, maxChoices: prompt.maxChoices)
                            GameHaptics.selection()
                        } label: {
                            CardTile(
                                card: card,
                                selected: isSelected,
                                legal: selectable,
                                targetable: selectable,
                                zoneName: searchZoneName(for: prompt),
                                width: 50,
                                height: 70
                            )
                            .opacity(selectable ? 1 : 0.34)
                            .overlay(alignment: .bottom) {
                                if !selectable {
                                    Text(card.disabledReason ?? "Not valid")
                                        .font(.system(size: 6, weight: .black))
                                        .foregroundStyle(.white.opacity(0.82))
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 2)
                                        .background(.black.opacity(0.72), in: Capsule())
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.55)
                                        .padding(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(pendingActionId != nil || !selectable)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 154)

            promptButton(
                label: "Submit selection",
                subtitle: valid ? "\(CardCountText.label(selectedCount)) from \(searchZoneName(for: prompt))" : "Select \(PromptSelectionRules.boundsText(minChoices: prompt.minChoices, maxChoices: prompt.maxChoices))",
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-search-select",
                command: valid ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: selectedIds) : nil
            )
        }
    }

    @ViewBuilder
    private func abilityPicker(abilities: [XmagePromptAbility], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Abilities")
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            // Occurrences are distinct rows even if XMage repeats an ability UUID.
            // Only presentation identity changes; answers retain the engine UUID.
            ForEach(Array(abilities.enumerated()), id: \.offset) { _, ability in
                let choiceCommand = command(type: "choose_ability", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [ability.id])
                VStack(alignment: .leading, spacing: 8) {
                    if let source = ability.sourceCard {
                        let selectAbility = {
                            guard pendingActionId == nil, let choiceCommand else { return }
                            inspectedCard = nil
                            runCommand(choiceCommand, "Choose ability", "\(prompt.id)-\(ability.id)")
                        }
                        CardTile(card: source, selected: false, legal: false,
                                 zoneName: "Ability source",
                                 width: verticalSizeClass == .compact ? 80 : 100,
                                 height: verticalSizeClass == .compact ? 112 : 140)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .disabled(pendingActionId != nil || choiceCommand == nil)
                        .overlay {
                            AbilityChoiceTouchSurface(
                                enabled: pendingActionId == nil && choiceCommand != nil,
                                choose: selectAbility,
                                inspect: { inspectedCard = source },
                                releaseInspection: { if inspectedCard?.id == source.id { inspectedCard = nil } }
                            ).accessibilityHidden(true)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Choose \(source.card.name) ability")
                        .accessibilityHint("Tap to choose. Hold to inspect the source card.")
                        .accessibilityAction { selectAbility() }
                        .accessibilityAction(named: Text("Inspect card")) {
                            guard pendingActionId == nil else { return }
                            inspectedCard = source
                        }
                    }
                    Text(ability.sourceName ?? "Ability")
                        .font(.subheadline.bold()).foregroundStyle(MagicPalette.parchment)
                    GameRulesText(source: ability.rulesText ?? ability.label, cardName: ability.sourceName)
                        .font(.callout).foregroundStyle(MagicPalette.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                    if ability.sourceCard == nil {
                        Text(ability.sourceUnavailableReason ?? "Source details unavailable")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                promptButton(
                    label: "Choose ability",
                    subtitle: nil,
                    systemImage: "bolt.fill",
                    pendingId: "\(prompt.id)-\(ability.id)",
                    command: choiceCommand
                )
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .background(MagicPalette.iron.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func pilePicker(piles: [XmagePromptPile], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Piles")
        VStack(alignment: .leading, spacing: 12) {
            ForEach(piles) { pile in
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(pile.label) · \(CardCountText.label(pile.cards.count))")
                        .font(.subheadline.bold())
                        .foregroundStyle(MagicPalette.parchment)
                    if pile.cards.isEmpty {
                        Text("This pile is empty.")
                            .font(.caption)
                            .foregroundStyle(MagicPalette.parchment.opacity(0.7))
                    } else {
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(pile.cards) { card in
                                    Button {
                                        inspectedCard = card
                                    } label: {
                                        VStack(spacing: 6) {
                                            CardTile(card: card, selected: false, legal: false, zoneName: pile.label, width: 76, height: 106)
                                            Text(card.card.name)
                                                .font(.caption)
                                                .multilineTextAlignment(.center)
                                            Text("Inspect")
                                                .font(.caption.bold())
                                                .frame(minHeight: 44)
                                        }
                                        .frame(width: 96)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(MagicPalette.parchment)
                                    .accessibilityLabel("Inspect \(card.card.name) in \(pile.label)")
                                }
                            }
                        }
                    }
                    promptButton(
                        label: "Choose \(pile.label)",
                        subtitle: CardCountText.label(pile.cards.count),
                        systemImage: "tray.full",
                        pendingId: "\(prompt.id)-pile-\(pile.id)",
                        command: command(type: "choose_pile", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, pile: pile.explicitPileNumber)
                    )
                }
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private func amountPicker(amounts: [Int], prompt: PromptEnvelopeV2) -> some View {
        let type = amountCommandType(preferred: prompt.responseCommand?.type)
        if type == "choose_multi_amount" {
            if let slots = prompt.multiAmounts, !slots.isEmpty {
                multiAmountPicker(slots: slots, prompt: prompt)
            } else {
                PromptMiniLabel("Multi Amount")
                Text("Unsupported prompt/action: XMage did not expose slot metadata for this multi-amount prompt.")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.warningAmber.opacity(0.90))
                    .lineLimit(3)
                    .minimumScaleFactor(0.72)
            }
        } else {
            PromptMiniLabel("Amount")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], spacing: 6) {
                ForEach(amounts, id: \.self) { amount in
                    promptButton(
                        label: "\(amount)",
                        systemImage: "number",
                        pendingId: "\(prompt.id)-amount-\(amount)",
                        command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amount: amount, amounts: [amount])
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func multiAmountPicker(slots: [XmagePromptMultiAmount], prompt: PromptEnvelopeV2) -> some View {
        let values = multiAmountArray(for: slots, promptId: prompt.id)
        let total = values.reduce(0, +)
        let valid = PromptCommandBuilder.isValidMultiAmountValues(values, slots: slots, totalMin: prompt.totalMin, totalMax: prompt.totalMax)
        let isDamageAllocation = isDamageAssignmentPrompt(prompt)

        PromptMiniLabel(isDamageAllocation ? "Damage Assignment" : "Multi Amount")
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                let value = values[index]
                HStack(spacing: 7) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(slot.label)
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("\(slot.min)-\(slot.max)")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.52))
                    }
                    Spacer(minLength: 4)
                    Button {
                        adjustMultiAmount(promptId: prompt.id, slots: slots, slot: slot, delta: -1)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(value <= slot.min ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || value <= slot.min)

                    Text("\(value)")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 28)

                    Button {
                        adjustMultiAmount(promptId: prompt.id, slots: slots, slot: slot, delta: 1)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18, weight: .black))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(value >= slot.max ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || value >= slot.max)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            }

            promptButton(
                label: isDamageAllocation ? "Assign damage" : "Submit amounts",
                subtitle: multiAmountSummary(total: total, prompt: prompt, valid: valid),
                systemImage: "number",
                pendingId: "\(prompt.id)-choose-multi-amount",
                command: valid ? command(type: "choose_multi_amount", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amounts: values) : nil
            )
        }
    }

    @ViewBuilder
    private func manaPicker(prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Mana")
        HStack(spacing: 6) {
            ForEach(availableManaSymbols, id: \.self) { mana in
                Button {
                    if let command = command(type: "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, manaType: mana) {
                        runCommand(command, mana, "\(prompt.id)-mana-\(mana)")
                    }
                } label: {
                    ManaSymbolView(symbol: mana, size: 26)
                        .overlay {
                            if pendingActionId == "\(prompt.id)-mana-\(mana)" {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Pay with \(mana) mana")
            }
        }
    }

    @ViewBuilder
    private func manaChoicePicker(choices: [XmagePromptManaChoice], prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Mana")
        HStack(spacing: 6) {
            ForEach(choices) { choice in
                let symbol = choice.manaType ?? choice.id
                Button {
                    if let command = command(type: snapshot.source == "xmage-ondevice" ? "play_mana" : prompt.responseCommand?.type ?? "play_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: [symbol], manaType: symbol) {
                        runCommand(command, choice.label, "\(prompt.id)-mana-choice-\(choice.id)")
                    }
                } label: {
                    VStack(spacing: 2) {
                        ManaSymbolView(symbol: symbol, size: 24)
                        if let amount = choice.amount {
                            Text("x\(amount)")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(.white.opacity(0.76))
                        }
                    }
                    .overlay {
                        if pendingActionId == "\(prompt.id)-mana-choice-\(choice.id)" {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .disabled(pendingActionId != nil)
                .accessibilityLabel("Pay with \(choice.label)")
            }
        }
    }


    @ViewBuilder
    private func colorChoicePicker(prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Choose Color")
        HStack(spacing: 6) {
            ForEach(["W", "U", "B", "R", "G", "C"], id: \.self) { mana in
                Button {
                    if let command = command(type: prompt.responseCommand?.type ?? "choose_mana", promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, manaType: mana) {
                        runCommand(command, mana, "\(prompt.id)-choose-color-\(mana)")
                    }
                } label: {
                    ManaSymbolView(symbol: mana, size: 26)
                        .overlay {
                            if pendingActionId == "\(prompt.id)-choose-color-\(mana)" {
                                ProgressView()
                                    .tint(.white)
                                    .scaleEffect(0.6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .disabled(pendingActionId != nil)
            }
        }
    }

    @ViewBuilder
    private func manualAmountPicker(prompt: PromptEnvelopeV2) -> some View {
        let type = amountCommandType(preferred: prompt.responseCommand?.type)
        let bounds = PromptAmountBounds(minimum: prompt.minChoices, maximum: prompt.maxChoices)
        let currentValue = bounds.clamp(manualAmountValues[prompt.id] ?? 0)
        PromptMiniLabel(type == "play_x_mana" ? "X Amount" : "Amount")
        
        HStack(spacing: 7) {
            Button {
                manualAmountValues[prompt.id] = bounds.stepping(currentValue, by: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(currentValue <= bounds.minimum ? .white.opacity(0.24) : MagicPalette.parchment)
            .disabled(pendingActionId != nil || currentValue <= bounds.minimum)

            TextField("Amount", value: Binding(get: { currentValue }, set: { manualAmountValues[prompt.id] = bounds.clamp($0) }), format: .number)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.center)
                .font(.system(size: 16, weight: .black))
                .foregroundStyle(.white)
                .frame(minWidth: 70, minHeight: 44)
                .accessibilityLabel("Amount, from \(bounds.minimum) to \(bounds.maximum)")
                .disabled(pendingActionId != nil)

            Button {
                manualAmountValues[prompt.id] = bounds.stepping(currentValue, by: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24, weight: .black))
            }
            .buttonStyle(.plain)
            .frame(minWidth: 44, minHeight: 44)
            .foregroundStyle(MagicPalette.parchment)
            .disabled(pendingActionId != nil || currentValue >= bounds.maximum)

            Spacer()

            promptButton(
                label: "Submit \(currentValue)",
                systemImage: "number",
                pendingId: "\(prompt.id)-amount-\(currentValue)",
                command: command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, amount: currentValue, amounts: [currentValue])
            )
        }
    }
    @ViewBuilder
    private func confirmationPicker(confirmation: XmagePromptConfirmation, prompt: PromptEnvelopeV2) -> some View {
        let yesCommand = explicitConfirmationCommand(confirmation.yesCommand, prompt: prompt)
        let noCommand = explicitConfirmationCommand(confirmation.noCommand, prompt: prompt)
        HStack(spacing: 6) {
            promptButton(
                label: confirmation.yesLabel ?? "Yes",
                systemImage: "checkmark.circle",
                pendingId: "\(prompt.id)-yes",
                command: yesCommand
            )
            promptButton(
                label: confirmation.noLabel ?? "No",
                systemImage: "xmark.circle",
                pendingId: "\(prompt.id)-no",
                command: noCommand
            )
        }
        if yesCommand == nil || noCommand == nil {
            Text("XMage did not expose explicit yes/no command metadata for every option, so missing choices stay disabled.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(MagicPalette.warningAmber.opacity(0.82))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
        }
    }

    private func explicitConfirmationCommand(_ confirmationCommand: XmageResponseCommand?, prompt: PromptEnvelopeV2) -> GameCommand? {
        guard let confirmationCommand,
              let type = confirmationCommand.type,
              let promptId = confirmationCommand.promptId,
              let confirmed = confirmationCommand.confirmed ?? confirmationCommand.pay
        else {
            return nil
        }
        return command(
            type: type,
            promptId: promptId,
            playerId: prompt.playerId,
            ids: [confirmed ? "true" : "false"],
            pay: confirmationCommand.pay ?? confirmed
        )
    }

    private func unsupportedPromptFallback(method: String, responseKind: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unsupported prompt/action")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(MagicPalette.warningAmber)
            Text("No default answer will be sent. Refresh or reconnect after the bridge exposes a mobile-safe response.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text("\(method) | \(responseKind)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(MagicPalette.warningAmber.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(MagicPalette.warningAmber.opacity(0.24)))
    }

    @ViewBuilder
    private func placeholderSubmit(title: String, button: String, prompt: PromptEnvelopeV2, type: String, ids: [String]) -> some View {
        let canSubmit = isOrderCommand(type) ? PromptCommandBuilder.canSubmitShownOrder(ids: ids) : !ids.isEmpty
        PromptMiniLabel(title)
        promptButton(
            label: button,
            subtitle: placeholderSubmitSubtitle(type: type, ids: ids),
            systemImage: type == "order_triggers" ? "arrow.up.arrow.down" : "magnifyingglass",
            pendingId: "\(prompt.id)-\(type)",
            command: canSubmit ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: ids) : nil
        )
    }

    @ViewBuilder
    private func unsupportedDamageAssignment(_ prompt: PromptEnvelopeV2) -> some View {
        PromptMiniLabel("Damage Assignment")
        VStack(alignment: .leading, spacing: 5) {
            Text("Unsupported prompt/action: damage assignment is not mobile-safe yet.")
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(.orange.opacity(0.9))
                .lineLimit(2)
                .minimumScaleFactor(0.72)
            Text("No default damage split will be submitted. Refresh or reconnect after the bridge exposes attacker/blocker allocation choices.")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.68))
                .lineLimit(3)
                .minimumScaleFactor(0.7)
            Text("\(prompt.method) | \(prompt.responseKind)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.46))
                .lineLimit(1)
                .minimumScaleFactor(0.64)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.orange.opacity(0.22)))
    }

    @ViewBuilder
    private func orderPicker(title: String, prompt: PromptEnvelopeV2, type: String, options: [(String, String)]) -> some View {
        let defaultIds = options.map(\.0)
        let currentIds = currentOrder(promptId: prompt.id, defaultIds: defaultIds)
        let labelById = Dictionary(uniqueKeysWithValues: options)
        let canSubmit = !currentIds.isEmpty && Set(currentIds) == Set(defaultIds) && currentIds.count == defaultIds.count

        PromptMiniLabel(title)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(currentIds.enumerated()), id: \.element) { index, id in
                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MagicPalette.antiqueGold)
                        .frame(width: 18, height: 24)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                    Text(labelById[id] ?? id)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Spacer(minLength: 4)

                    Button {
                        moveOrder(promptId: prompt.id, defaultIds: defaultIds, from: index, delta: -1)
                    } label: {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == 0 ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || index == 0)

                    Button {
                        moveOrder(promptId: prompt.id, defaultIds: defaultIds, from: index, delta: 1)
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .black))
                            .frame(width: 28, height: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == currentIds.count - 1 ? .white.opacity(0.24) : MagicPalette.parchment)
                    .disabled(pendingActionId != nil || index == currentIds.count - 1)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.08)))
            }

            promptButton(
                label: "Submit order",
                subtitle: canSubmit ? "\(currentIds.count) items" : "Order incomplete",
                systemImage: "arrow.up.arrow.down",
                pendingId: "\(prompt.id)-\(type)-ordered",
                command: canSubmit ? command(type: type, promptId: prompt.responseCommand?.promptId ?? prompt.id, playerId: prompt.playerId, ids: currentIds) : nil
            )
        }
    }

    @ViewBuilder
    private func promptButton(label: String, subtitle: String? = nil, systemImage: String? = nil, pendingId: String, command: GameCommand?,
                              large: Bool = false) -> some View {
        Button {
            if let command {
                runCommand(command, label, pendingId)
            }
        } label: {
            PromptButtonLabel(title: label, subtitle: subtitle, systemImage: systemImage, isPending: pendingActionId == pendingId, large: large)
        }
        .buttonStyle(PanelActionButtonStyle(isPrimary: true))
        .disabled(pendingActionId != nil || command == nil)
    }

    private func action(for choice: ChoicePromptOption, promptId: String) -> LegalAction? {
        let actions = snapshot.legalActions ?? []
        let choiceId = choice.id
        let suffixTarget = "-\(choiceId)"
        let composedId = "\(promptId)-\(choiceId)"
        return actions.first { action in
            if action.id == choiceId { return true }
            if action.id == composedId { return true }
            if action.targetIds?.contains(choiceId) == true { return true }
            if action.validTargetIds?.contains(choiceId) == true { return true }
            if action.id.hasSuffix(suffixTarget) { return true }
            return false
        }
    }

    private func command(
        type rawType: String,
        promptId: String,
        playerId: String,
        ids: [String] = [],
        amount: Int? = nil,
        amounts: [Int]? = nil,
        pile: Int? = nil,
        useCommandZone: Bool? = nil,
        manaType: String? = nil,
        pay: Bool? = nil
    ) -> GameCommand? {
        UniversalPromptResponseCommandBuilder.command(
            gameId: snapshot.id,
            bridgeRevision: snapshot.bridgeRevision,
            promptEnvelope: snapshot.promptEnvelopeV2,
            type: rawType,
            promptId: promptId,
            playerId: playerId,
            ids: ids,
            amount: amount,
            amounts: amounts,
            pile: pile,
            useCommandZone: useCommandZone,
            manaType: manaType,
            pay: pay
        )
    }

    private func idCommandType(preferred: String?, fallback: String) -> String {
        PromptCommandBuilder.idCommandType(preferred: preferred, fallback: fallback)
    }

    private func amountCommandType(preferred: String?) -> String {
        PromptCommandBuilder.amountCommandType(preferred: preferred)
    }

    private func playerPromptLabel(_ player: XmagePromptPlayer) -> String {
        if let life = player.life {
            return "\(player.label) (\(life))"
        }
        return player.label
    }

    private func isManaPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "play_mana" || type == "choose_mana" || type == "mana" || type == "pay_cost" || type == "cost"
    }

    private func isManaOrPaymentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? ""
        let kind = prompt.responseKind.lowercased()
        return isManaPrompt(prompt)
            || ["pay_cost", "choose_mana", "play_x_mana"].contains(type)
            || ["pay_cost", "cost", "mana", "x_mana"].contains(kind)
            || prompt.message.localizedCaseInsensitiveContains("pay")
            || prompt.message.localizedCaseInsensitiveContains("mana")
    }

    private func isConfirmationPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        if prompt.confirmation != nil { return true }
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "answer_yes_no" || type == "confirmation" || type == "pay_cost"
    }

    private func isCommanderReplacement(_ prompt: PromptEnvelopeV2) -> Bool {
        PromptCommandBuilder.isCommanderReplacement(prompt)
    }

    private func isTriggerOrderPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        (prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()) == "order_triggers"
    }

    private func isSearchPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "search_select" || prompt.method.localizedCaseInsensitiveContains("search")
    }

    private func isCardSelectionPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_card" || type == "card" || type == "choose_target" || type == "target"
    }

    private func isPlayerSelectionPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_player" || type == "player"
    }

    private func isChooseColorPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "choose_mana" || type == "choose_color"
    }

    private func isAmountPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        let type = prompt.responseCommand?.type?.lowercased() ?? prompt.responseKind.lowercased()
        return type == "play_x_mana" || type == "choose_amount"
    }

    private func isDamageAssignmentPrompt(_ prompt: PromptEnvelopeV2) -> Bool {
        PromptCommandBuilder.isCombatDamageAllocationPrompt(prompt, phase: snapshot.phase, step: snapshot.step)
    }

    private func hasRenderablePromptControls(_ prompt: PromptEnvelopeV2) -> Bool {
        if isManaOrPaymentPrompt(prompt) { return true }
        if isDamageAssignmentPrompt(prompt) { return true }
        if isCommanderReplacement(prompt) || isConfirmationPrompt(prompt) || isManaPrompt(prompt) || isTriggerOrderPrompt(prompt) || isSearchPrompt(prompt) { return true }
        if isCardSelectionPrompt(prompt) || isPlayerSelectionPrompt(prompt) || isChooseColorPrompt(prompt) || isAmountPrompt(prompt) { return true }
        if prompt.choices?.isEmpty == false || prompt.targets?.isEmpty == false || prompt.players?.isEmpty == false { return true }
        if prompt.cards?.isEmpty == false || prompt.modes?.isEmpty == false || prompt.abilities?.isEmpty == false { return true }
        if prompt.piles?.isEmpty == false || prompt.amounts?.isEmpty == false || prompt.multiAmounts?.isEmpty == false || prompt.orderedItems?.isEmpty == false || prompt.manaChoices?.isEmpty == false { return true }
        if prompt.method == "GAME_SELECT" { return true }
        return false
    }

    private func yesNoIcon(_ label: String) -> String? {
        let lower = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["yes", "ok", "accept"].contains(lower) { return "checkmark.circle" }
        if ["no", "cancel", "decline"].contains(lower) { return "xmark.circle" }
        return nil
    }

    private func isDirectlyRunnable(_ action: LegalAction) -> Bool {
        switch action.type {
        case "choose_target":
            return singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_card", "search_select":
            return singleCount(action.cardInstanceIds) || singleCount(action.validCardInstanceIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_player":
            return singleCount(action.playerIds) || singleCount(action.validPlayerIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "choose_mode":
            return singleCount(action.modeIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "resolve_choice":
            return singleCount(action.choiceIds) || singleCount(action.targetIds) || singleCount(action.validTargetIds)
        case "declare_attackers":
            return PromptCommandBuilder.hasPrebuiltCombatPayload(action)
        case "declare_blockers":
            return PromptCommandBuilder.hasPrebuiltCombatPayload(action)
        case "choose_multi_amount", "order_triggers", "order_items":
            return false
        default:
            return true
        }
    }

    private var availableManaSymbols: [String] {
        let pool = snapshot.human?.manaPool
        return ["W", "U", "B", "R", "G", "C"].filter { symbol in
            manaPoolValue(pool, symbol: symbol) > 0
        }
    }

    private func manaPoolValue(_ pool: ManaPool?, symbol: String) -> Int {
        switch symbol {
        case "W": return pool?.W ?? 0
        case "U": return pool?.U ?? 0
        case "B": return pool?.B ?? 0
        case "R": return pool?.R ?? 0
        case "G": return pool?.G ?? 0
        case "C": return pool?.C ?? 0
        default: return 0
        }
    }

    private func isOrderCommand(_ type: String) -> Bool {
        type == "order_triggers" || type == "order_items"
    }

    private func orderOptions(for prompt: PromptEnvelopeV2) -> [(String, String)] {
        if let cards = prompt.cards, !cards.isEmpty {
            return cards.map { ($0.id, $0.card.name) }
        }
        if let targets = prompt.targets, !targets.isEmpty {
            return targets.map { ($0.id, $0.label) }
        }
        if let choices = prompt.choices, !choices.isEmpty {
            return choices.map { ($0.id, $0.label) }
        }
        return []
    }

    private func currentSearchSelection(promptId: String, validIds: [String]) -> [String] {
        guard selectedSearchPromptId == promptId else { return [] }
        let validIdSet = Set(validIds)
        return selectedSearchCardIds.filter { validIdSet.contains($0) }
    }

    private func toggleSearchSelection(promptId: String, cardId: String, validIds: [String], maxChoices: Int?) {
        if selectedSearchPromptId != promptId {
            selectedSearchPromptId = promptId
            selectedSearchCardIds = []
        } else {
            let validIdSet = Set(validIds)
            selectedSearchCardIds = selectedSearchCardIds.filter { validIdSet.contains($0) }
        }

        if selectedSearchCardIds.contains(cardId) {
            selectedSearchCardIds.removeAll { $0 == cardId }
            return
        }

        if let maxChoices, selectedSearchCardIds.count >= maxChoices {
            return
        }
        selectedSearchCardIds.append(cardId)
    }

    private func searchZoneName(for prompt: PromptEnvelopeV2) -> String {
        if case .string(let zone)? = prompt.options?["zone"], !zone.isEmpty {
            return zone.capitalized
        }
        return "Library"
    }

    private func currentOrder(promptId: String, defaultIds: [String]) -> [String] {
        orderPromptId == promptId && !orderedIds.isEmpty ? orderedIds : defaultIds
    }

    private func moveOrder(promptId: String, defaultIds: [String], from index: Int, delta: Int) {
        if orderPromptId != promptId || orderedIds.isEmpty {
            orderPromptId = promptId
            orderedIds = defaultIds
        }
        orderedIds = PromptCommandBuilder.movedOrder(ids: orderedIds, from: index, to: index + delta)
    }

    private func multiAmountArray(for slots: [XmagePromptMultiAmount], promptId: String) -> [Int] {
        if multiAmountPromptId == promptId {
            return slots.map { multiAmountValues[$0.id] ?? PromptCommandBuilder.defaultMultiAmountValue(for: $0) }
        }
        return slots.map(PromptCommandBuilder.defaultMultiAmountValue)
    }

    private func adjustMultiAmount(promptId: String, slots: [XmagePromptMultiAmount], slot: XmagePromptMultiAmount, delta: Int) {
        if multiAmountPromptId != promptId {
            multiAmountPromptId = promptId
            multiAmountValues = Dictionary(uniqueKeysWithValues: slots.map { ($0.id, PromptCommandBuilder.defaultMultiAmountValue(for: $0)) })
        }
        let current = multiAmountValues[slot.id] ?? PromptCommandBuilder.defaultMultiAmountValue(for: slot)
        multiAmountValues[slot.id] = PromptCommandBuilder.adjustedMultiAmountValue(current, delta: delta, slot: slot)
    }

    private func multiAmountSummary(total: Int, prompt: PromptEnvelopeV2, valid: Bool) -> String {
        var bounds: [String] = []
        if let totalMin = prompt.totalMin {
            bounds.append("min \(totalMin)")
        }
        if let totalMax = prompt.totalMax {
            bounds.append("max \(totalMax)")
        }
        let suffix = bounds.isEmpty ? "" : " · \(bounds.joined(separator: ", "))"
        return valid ? "total \(total)\(suffix)" : "invalid total \(total)\(suffix)"
    }

    private func placeholderSubmitSubtitle(type: String, ids: [String]) -> String {
        if ids.isEmpty {
            return "Waiting for exposed ids"
        }
        if isOrderCommand(type), !PromptCommandBuilder.canSubmitShownOrder(ids: ids) {
            return "No auto-order"
        }
        return "\(ids.count) ids"
    }

    private func singleCount(_ values: [String]?) -> Bool {
        values?.count == 1
    }

    private func isCastOrPlay(_ action: LegalAction) -> Bool {
        action.type == "cast_spell" || action.type == "play_land"
    }

    private func selectedCardIsInHumanHand(_ card: ZoneCard) -> Bool {
        snapshot.human?.zones.hand.contains { $0.instanceId == card.instanceId } == true
    }

    private func selectedCardBlockedReason(_ card: ZoneCard) -> String {
        if pendingActionId != nil {
            return "Action sent. Waiting for XMage to confirm the next game state."
        }
        if snapshot.waitingOnPlayerId != nil && !snapshot.isViewer(snapshot.waitingOnPlayerId) {
            return "Waiting on \(snapshot.playerLabel(snapshot.waitingOnPlayerId)). XMage has not exposed a cast/play action for this card."
        }
        if snapshot.priorityPlayerId != nil && !snapshot.isViewer(snapshot.priorityPlayerId) {
            return "Not your priority. XMage will expose cast/play actions when this card is legal."
        }
        if snapshot.promptEnvelopeV2 != nil || snapshot.promptEnvelope != nil || snapshot.choicePrompt != nil {
            return "Answer the current XMage prompt first. This card remains inspectable, but XMage is not accepting a cast/play action for it right now."
        }
        return "XMage did not expose a cast/play action for \(card.card.name). It may need mana, timing, a target, or another required choice."
    }

    private func sourceCardName(for action: LegalAction) -> String {
        if let cardName = action.cardName, !cardName.isEmpty {
            return cardName
        }
        let id = action.sourceInstanceId ?? action.cardInstanceId
        if let id, let card = snapshot.human?.zones.battlefield.first(where: { $0.instanceId == id }) {
            return card.card.name
        }
        return action.label
    }

    private func producedManaLabel(for action: LegalAction) -> String? {
        guard let producedMana = action.producedMana, !producedMana.isEmpty else {
            return action.actionDetail
        }
        return producedMana.map { "{\($0)}" }.joined(separator: " ")
    }
}

struct MobileSurfacesPanel: View {
    let snapshot: GameSnapshot
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let viewZone: (String, [ZoneCard]) -> Void

    var body: some View {
        PromptPanelSection(title: "Zones", detail: surfaceSummary) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 5)], spacing: 5) {
                zoneButton(title: "Stack", count: stackObjectCount, systemImage: "sparkles", cards: stackCards)
                zoneButton(title: "Command", count: commandCards.count, systemImage: "crown", cards: commandCards)
                zoneButton(title: "Grave", count: graveyardCards.count, systemImage: "archivebox", cards: graveyardCards)
                zoneButton(title: "Exile", count: exileCards.count, systemImage: "moon.stars", cards: exileCards)
                SurfaceChip(title: "Library", value: "\(libraryCount)", systemImage: "books.vertical")
                if !revealedCards.isEmpty || snapshot.xmage?.panels.revealed == true {
                    zoneButton(title: "Revealed", count: revealedCards.count, systemImage: "eye", cards: revealedCards)
                }
                if !lookedAtCards.isEmpty || snapshot.xmage?.panels.lookedAt == true {
                    zoneButton(title: "Looked", count: lookedAtCards.count, systemImage: "eye.trianglebadge.exclamationmark", cards: lookedAtCards)
                }
                if let companions = snapshot.xmage?.companion, !companions.isEmpty {
                    zoneButton(title: "Companion", count: companions.flatMap(\.cards).count, systemImage: "person.crop.square", cards: companions.flatMap(\.cards))
                }
                SurfaceChip(title: "Priority", value: priorityOwner, systemImage: "hand.raised")
                SurfaceChip(title: "Actions", value: "\((snapshot.legalActions ?? []).count)", systemImage: "bolt")
            }

            if snapshot.source == "xmage-ondevice" {
                ForEach(namedInspectionZones) { group in
                    if !group.cards.isEmpty {
                        Button("\(group.name) (\(group.cards.count))") { viewZone(group.name, group.cards) }
                            .frame(minHeight: 44).buttonStyle(.plain)
                    }
                }
                DisclosureGroup("Commander tax and damage") {
                    ForEach(snapshot.players) { player in
                        ForEach(player.commanders ?? []) { commander in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(player.displayName ?? player.playerId) · \(commander.name ?? "Commander \(commander.id.prefix(8))")").font(.caption.bold())
                                Text("Command-zone casts: \(commander.castsFromCommandZone.map(String.init) ?? "unknown") · Next tax: \(commander.commanderTax.map { "{\($0)}" } ?? "unknown")").font(.caption)
                                if let damage = commander.damageToPlayers {
                                    ForEach(snapshot.players) { recipient in
                                        Text("Damage to \(snapshot.playerLabel(recipient.playerId)): \(damage[recipient.playerId] ?? 0)").font(.caption)
                                    }
                                } else { Text("Commander damage unavailable").font(.caption) }
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
                        }
                    }
                }
            }

            if let topStackObject = stackObjectNames.first {
                Text("Stack top: \(topStackObject)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(MagicPalette.priorityArcane.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.64)
            }
        }
    }

    private func zoneButton(title: String, count: Int, systemImage: String, cards: [ZoneCard]) -> some View {
        Button {
            viewZone(title == "Grave" ? "Graveyard" : title, cards)
        } label: {
            SurfaceChip(title: title, value: "\(count)", systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) zone, \(CardCountText.label(count))")
    }

    private var surfaceSummary: String {
        if snapshot.xmage?.panels.search == true {
            return "search"
        }
        if snapshot.xmage?.panels.revealed == true {
            return "revealed"
        }
        if snapshot.xmage?.panels.lookedAt == true {
            return "looked"
        }
        return priorityOwner
    }

    private var priorityOwner: String {
        if snapshot.isViewer(snapshot.priorityPlayerId) || snapshot.isViewer(snapshot.waitingOnPlayerId) || !CompactPromptPopup.compactLegalPromptActions(in: snapshot).isEmpty {
            return "You"
        }
        return snapshot.playerLabel(snapshot.priorityPlayerId ?? snapshot.waitingOnPlayerId)
    }

    private var stackCards: [ZoneCard] {
        let xmageCards = snapshot.xmage?.stack.compactMap(\.displaySourceCard) ?? []
        if !xmageCards.isEmpty { return xmageCards }
        return snapshot.players.flatMap(\.zones.stack)
    }

    private var stackObjectCount: Int {
        let xmageCount = snapshot.xmage?.stack.count ?? 0
        return max(xmageCount, stackCards.count)
    }

    private var stackObjectNames: [String] {
        snapshot.xmage?.stack.map(\.displayName).filter { !$0.isEmpty } ?? []
    }

    private var commandCards: [ZoneCard] {
        uniqueCards(snapshot.players.flatMap(\.zones.command) + (snapshot.xmage?.players.flatMap(\.command) ?? []))
    }

    private var graveyardCards: [ZoneCard] {
        uniqueCards(snapshot.players.flatMap(\.zones.graveyard) + (snapshot.xmage?.players.flatMap(\.zones.graveyard) ?? []))
    }

    private var exileCards: [ZoneCard] {
        uniqueCards(snapshot.players.flatMap(\.zones.exile) + (snapshot.xmage?.players.flatMap(\.zones.exile) ?? []) + (snapshot.xmage?.exileZones.flatMap(\.cards) ?? []))
    }

    private func uniqueCards(_ cards: [ZoneCard]) -> [ZoneCard] {
        var seen = Set<String>()
        return cards.filter { seen.insert($0.instanceId).inserted }
    }

    private var namedInspectionZones: [XmageNamedZone] {
        guard let xmage = snapshot.xmage else { return [] }
        return xmage.exileZones + xmage.revealed + xmage.lookedAt
    }

    private var libraryCount: Int {
        snapshot.players.map { $0.zones.visibleLibraryCount }.reduce(0, +)
    }

    private var revealedCards: [ZoneCard] {
        snapshot.xmage?.revealed.flatMap(\.cards) ?? []
    }

    private var lookedAtCards: [ZoneCard] {
        snapshot.xmage?.lookedAt.flatMap(\.cards) ?? []
    }
}

struct PromptPanelSection<Content: View>: View {
    let title: String
    let detail: String
    var isHighlighted = false
    var isEmbedded = false
    @ViewBuilder let content: Content
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if isEmbedded {
            VStack(alignment: .leading, spacing: 7) { content }
        } else if tavern && TavernUIKit.available {
            tavernSection
        } else {
            framedSection
        }
    }

    /// A box pressed into the tavern sheet's leather, edged with a brass hairline.
    private var tavernSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .serif))
                    .tracking(1)
                    .foregroundStyle(isHighlighted ? MagicPalette.warningAmber : Color(red: 0.96, green: 0.80, blue: 0.48))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                Text(detail.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .serif))
                    .foregroundStyle(TavernPalette.parchment.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            content
        }
        .padding(9)
        .background(Color.black.opacity(0.24), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(isHighlighted ? AnyShapeStyle(MagicPalette.warningAmber.opacity(0.7)) : AnyShapeStyle(TavernPalette.brassLine),
                          lineWidth: 1))
    }

    private var framedSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(isHighlighted ? MagicPalette.warningAmber : MagicPalette.antiqueGold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                Text(detail.uppercased())
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(isHighlighted ? MagicPalette.warningAmber.opacity(0.86) : MagicPalette.parchment.opacity(0.58))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            content
        }
        .padding(7)
        .background(
            isHighlighted ? MagicPalette.warningAmber.opacity(0.10) : MagicPalette.iron.opacity(0.42),
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isHighlighted ? MagicPalette.warningAmber.opacity(0.48) : MagicPalette.borderBronze.opacity(0.28), lineWidth: isHighlighted ? 1.5 : 1))
    }
}

struct PromptMiniLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        if tavern {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .serif))
                .tracking(0.8)
                .foregroundStyle(Color(red: 0.96, green: 0.80, blue: 0.48).opacity(0.85))
        } else {
            Text(title.uppercased())
                .font(.system(size: 7, weight: .black))
                .foregroundStyle(.white.opacity(0.54))
        }
    }
}

struct PromptButtonLabel: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    var isPending = false
    /// Replaces {this} in engine ability text.
    var cardName: String? = nil
    /// Full-width option rows: larger type and the whole text, never truncated.
    var large = false
    @Environment(\.tavernBoard) private var tavern

    var body: some View {
        HStack(spacing: large ? 10 : 6) {
            if isPending {
                ProgressView()
                    .tint(tavern ? TavernPalette.ink : .white)
                    .scaleEffect(large ? 0.8 : 0.58)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: large ? 15 : 11, weight: .black))
                    .foregroundStyle(tavern ? AnyShapeStyle(.primary) : AnyShapeStyle(MagicPalette.parchment))
            }
            VStack(alignment: .leading, spacing: 2) {
                let text = PromptDisplayText.clean(title)
                Group {
                    if text.contains("{") {
                        // Mana, tap and other symbols render as icons, never as {T}.
                        GameRulesText(source: text, cardName: cardName, symbolSize: large ? 17 : 13)
                    } else {
                        Text(text)
                    }
                }
                .font(.system(size: large ? 15 : 12, weight: large ? .semibold : .bold))
                .lineLimit(large ? 8 : 3)
                .minimumScaleFactor(large ? 0.9 : 0.7)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: large)
                if let subtitle, !subtitle.isEmpty {
                    Text(PromptDisplayText.clean(subtitle))
                        .font(.system(size: large ? 12 : 9, weight: .semibold))
                        .opacity(0.72)
                        .lineLimit(large ? 3 : 1)
                        .minimumScaleFactor(0.7)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, large ? 6 : 0)
    }
}

struct PanelActionButtonStyle: ButtonStyle {
    var isDanger = false
    var isPrimary = false
    var compact = false
    @Environment(\.tavernBoard) private var tavern
    @Environment(\.isEnabled) private var isEnabled

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if tavern && TavernUIKit.available {
            tavernBody(configuration)
        } else {
            classicBody(configuration)
        }
    }

    /// Tavern rows: a primary choice is parchment in brass trim with dark ink (choice lists mark
    /// every option primary), a plain one dark leather with a brass hairline, a dangerous one
    /// oxblood leather. Ember glass stays for the pass button and plaque buttons.
    private func tavernBody(_ configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        let parchment = isPrimary && !isDanger
        return configuration.label
            .foregroundStyle(parchment ? TavernPalette.ink : TavernPalette.parchment)
            .shadow(color: parchment ? .clear : .black.opacity(0.6), radius: 1, y: 1)
            .padding(.horizontal, compact ? 9 : 11)
            .padding(.vertical, compact ? 4 : 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background {
                Group {
                    if isDanger {
                        TavernFill(material: .leather).overlay(MagicPalette.oxblood.opacity(0.7))
                    } else if parchment {
                        TavernFill(material: .parchment)
                    } else {
                        TavernFill(material: .leather).overlay(Color.white.opacity(0.06))
                    }
                }
                .clipShape(shape)
            }
            .overlay {
                if parchment {
                    TavernBrassFrame(scale: 0.42)
                } else {
                    shape.strokeBorder(TavernPalette.brassLine, lineWidth: 1.2)
                }
            }
            .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
            .saturation(isEnabled ? 1 : 0.35)
            .opacity(isEnabled ? 1 : 0.6)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private func classicBody(_ configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, compact ? 6 : 7)
            .padding(.vertical, compact ? 4 : 5)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(background(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isPrimary && !isDanger ? MagicPalette.antiqueGold.opacity(0.95) : .white.opacity(0.10),
                                                              lineWidth: isPrimary ? 1.4 : 1))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private func background(isPressed: Bool) -> AnyShapeStyle {
        if isDanger {
            return AnyShapeStyle(isPressed ? MagicPalette.oxblood.opacity(0.68) : MagicPalette.oxblood.opacity(0.86))
        }
        if isPrimary {
            // Deep bronze keeps white labels readable (light gold behind white text was not).
            let top = Color(red: 0.56, green: 0.40, blue: 0.15), bottom = Color(red: 0.36, green: 0.24, blue: 0.08)
            return AnyShapeStyle(LinearGradient(colors: isPressed ? [bottom, bottom] : [top, bottom], startPoint: .top, endPoint: .bottom))
        }
        return AnyShapeStyle(isPressed ? MagicPalette.panelParchment.opacity(0.18) : MagicPalette.iron.opacity(0.58))
    }
}

struct SurfaceChip: View {
    let title: String
    let value: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(MagicPalette.antiqueGold.opacity(0.86))
                    .frame(width: 10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(MagicPalette.parchment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(title.uppercased())
                    .font(.system(size: 6, weight: .black))
                    .foregroundStyle(MagicPalette.parchment.opacity(0.56))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 32)
        .background(MagicPalette.iron.opacity(0.54), in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(MagicPalette.borderBronze.opacity(0.34), lineWidth: 1))
    }
}
