import SwiftUI

/// One UUID per native PICK_TARGET response. XMage owns subsequent selection,
/// deselection and ordering prompts; the UI never invents a batch response.
struct BoardCardChoiceView: View {
    let snapshot: GameSnapshot
    let prompt: PromptEnvelopeV2
    let pendingActionId: String?
    let runCommand: (GameCommand, String, String) -> Void
    let runAction: (LegalAction) -> Void
    let close: () -> Void
    @State private var selectedID: String?
    @State private var search = ""
    @State private var inspected: ZoneCard?

    private var cards: [ZoneCard] { prompt.cards ?? [] }
    private var targets: [ChoicePromptOption] {
        // A duplicate target must not bypass a card's disabled state.
        var seen = Set(cards.map(\.id))
        return (prompt.targets ?? []).filter { seen.insert($0.id).inserted }
    }
    private var selected: (id: String, label: String, isCard: Bool)? {
        guard let selectedID else { return nil }
        if let card = cards.first(where: { $0.id == selectedID && $0.isPromptSelectable }) {
            return (card.id, card.card.name, true)
        }
        if let target = targets.first(where: { $0.id == selectedID }) {
            return (target.id, target.label, false)
        }
        return nil
    }
    private var chosenIDs: [String] { prompt.options?["chosenTargets"]?.stringArrayValue ?? [] }

    private func toggleSelection(_ id: String) {
        guard pendingActionId == nil,
              cards.contains(where: { $0.id == id && $0.isPromptSelectable }) || targets.contains(where: { $0.id == id }) else { return }
        selectedID = selectedID == id ? nil : id
    }

    private func selectionState(_ id: String) -> String {
        if selectedID == id { return chosenIDs.contains(id) ? "Selected to remove" : "Selected" }
        return chosenIDs.contains(id) ? "Chosen · select to remove" : "Not selected"
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = metrics(for: geometry.size)
            ZStack {
                Color.black.opacity(0.58).ignoresSafeArea()
                chooserPanel(layout)
                if let inspected { inspectionOverlay(inspected) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityAddTraits(.isModal)
    }

    private struct ChoiceLayout {
        let width: CGFloat
        let height: CGFloat
        let headerLimit: CGFloat
        let cardWidth: CGFloat
        let columns: [GridItem]
    }

    private func metrics(for size: CGSize) -> ChoiceLayout {
        let compact = (1...2).contains(cards.count)
        let height: CGFloat = max(0, min(size.height - 32, 680))
        let headerLimit: CGFloat = min(96, max(44, height * 0.25))
        // Reserve header, footer, card captions, padding and gaps. Extra
        // wrapping reduces the scroll viewport instead of shrinking cards.
        let searchHeight: CGFloat = cards.count > 6 ? 44 : 0
        let pendingHeight: CGFloat = pendingActionId != nil ? 32 : 0
        let controlsHeight: CGFloat = headerLimit + 156 + searchHeight + pendingHeight
        let maximumCardWidth: CGFloat = compact ? 180 : 130
        let heightLimitedCard: CGFloat = max(90, min(maximumCardWidth, (height - controlsHeight) / 1.4))
        let preferredWidth: CGFloat
        if compact {
            preferredWidth = cards.count == 1 ? 280 : min(420, max(350, heightLimitedCard * 2 + 60))
        } else {
            preferredWidth = 700
        }
        let width: CGFloat = max(0, min(size.width - 24, preferredWidth))
        let columnCount = compact && cards.count == 2 && width >= 240 ? 2 : 1
        let gridSpacing: CGFloat = CGFloat(columnCount - 1) * 12
        let availableCardWidth: CGFloat = (width - 48 - gridSpacing) / CGFloat(columnCount)
        let cardWidth: CGFloat = max(90, min(heightLimitedCard, availableCardWidth))
        let columns: [GridItem] = compact
            ? Array(repeating: GridItem(.fixed(cardWidth), spacing: 12), count: columnCount)
            : [GridItem(.adaptive(minimum: cardWidth), spacing: 12)]
        let panelHeight: CGFloat = compact && targets.isEmpty
            ? min(height, cardWidth * 1.4 + controlsHeight) : height
        return ChoiceLayout(width: width, height: panelHeight, headerLimit: headerLimit,
                            cardWidth: cardWidth, columns: columns)
    }

    private func chooserPanel(_ layout: ChoiceLayout) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            chooserHeader(maxHeight: layout.headerLimit)
            if cards.count > 6 {
                TextField("Find a card", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("board.choice.search")
            }
            choiceContent(layout)
            chooserFooter
            if pendingActionId != nil {
                ProgressView("Waiting for XMage…").font(.caption)
            }
        }
        .padding(16)
        .frame(width: layout.width, height: layout.height)
        .background(MagicPalette.iron, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MagicPalette.antiqueGold.opacity(0.6)))
    }

    private func chooserHeader(maxHeight: CGFloat) -> some View {
        HStack(alignment: .top) {
            ViewThatFits(in: .vertical) {
                Text(prompt.message).font(.headline).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    Text(prompt.message).font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("board.choice.message.scroll")
            }
            .frame(maxHeight: maxHeight, alignment: .topLeading)
            Spacer(minLength: 8)
            Button(action: close) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close card choices")
        }
    }

    private func choiceContent(_ layout: ChoiceLayout) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !targets.isEmpty {
                    Text("Other targets").font(.subheadline.weight(.semibold))
                    ForEach(targets) { target in targetRow(target) }
                }
                LazyVGrid(columns: layout.columns, alignment: .center, spacing: 14) {
                    ForEach(filteredCards) { card in
                        cardRow(card, width: layout.cardWidth)
                    }
                }
                if cards.allSatisfy({ !$0.isPromptSelectable }) && targets.isEmpty {
                    Text("No legal cards to select. You can still hold a card to inspect it.")
                        .font(.subheadline)
                }
            }
            .padding(8)
        }
        .accessibilityIdentifier("board.choice.cards")
    }

    private var filteredCards: [ZoneCard] {
        cards.filter { search.isEmpty || $0.card.name.localizedCaseInsensitiveContains(search) }
    }

    private func targetRow(_ target: ChoicePromptOption) -> some View {
        let isSelected = selectedID == target.id
        let isMarked = isSelected || chosenIDs.contains(target.id)
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        let background: Color = isSelected ? Color.purple.opacity(0.25) : Color.white.opacity(0.06)
        return Button { toggleSelection(target.id) } label: {
            HStack(spacing: 10) {
                Image(systemName: isMarked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.purple)
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.label).fixedSize(horizontal: false, vertical: true)
                    if isMarked { Text(selectionState(target.id)).font(.caption) }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 10)
            .background(background, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(pendingActionId != nil)
        .accessibilityLabel(Text(verbatim: target.label))
        .accessibilityValue(Text(verbatim: selectionState(target.id)))
        .accessibilityAddTraits(traits)
        .accessibilityIdentifier("board.choice.target.\(target.id)")
    }

    private func cardRow(_ card: ZoneCard, width: CGFloat) -> some View {
        VStack(spacing: 5) {
            accessibleCardTile(card, width: width)
            Text(card.card.name).font(.caption.weight(.semibold)).lineLimit(2)
            if selectedID == card.id || chosenIDs.contains(card.id) {
                Text(selectionState(card.id)).font(.caption2)
            }
        }
        .frame(width: width)
    }

    private func cardArtwork(_ card: ZoneCard, width: CGFloat) -> some View {
        let selectable = card.isPromptSelectable
        let border: Color = selectable ? .purple : .clear
        let shadow: Color = selectable ? Color.purple.opacity(0.5) : .clear
        return CardTile(card: card, selected: selectedID == card.id, legal: false,
                        zoneName: "Choice", width: width, height: width * 1.4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 3))
            .shadow(color: shadow, radius: 6)
            .opacity(selectable ? 1 : 0.48)
            .overlay(alignment: .topTrailing) {
                if selectedID == card.id || chosenIDs.contains(card.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white, .purple).font(.title2).padding(4)
                }
            }
    }

    private func accessibleCardTile(_ card: ZoneCard, width: CGFloat) -> some View {
        let isSelected = selectedID == card.id
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        let eligibility = card.isPromptSelectable ? "legal choice" : "not a legal choice"
        let label = "\(card.card.name), \(eligibility)"
        let hint = card.isPromptSelectable
            ? "Select, then confirm. Inspect card is also available."
            : "This card cannot be selected. Inspect card is available."
        let selectAction = isSelected ? "Clear selection" : "Select card"
        return cardArtwork(card, width: width)
            .contentShape(Rectangle())
            .onCardInteraction(tap: { toggleSelection(card.id) }, inspect: { inspected = card },
                               release: { if inspected?.id == card.id { inspected = nil } })
            .accessibilityLabel(Text(verbatim: label))
            .accessibilityValue(Text(verbatim: selectionState(card.id)))
            .accessibilityAddTraits(traits)
            .accessibilityHint(Text(verbatim: hint))
            .accessibilityAction { toggleSelection(card.id) }
            .accessibilityAction(named: Text(selectAction)) { toggleSelection(card.id) }
            .accessibilityAction(named: Text("Inspect card")) { inspected = card }
            .accessibilityIdentifier("board.choice.card.\(card.id)")
    }

    private var confirmationLabel: String {
        guard let selected else { return targets.isEmpty ? "Select a card" : "Select an option" }
        if chosenIDs.contains(selected.id) { return "Remove selection" }
        return selected.isCard ? "Confirm card" : "Confirm target"
    }

    private var confirmationButton: some View {
        Button(confirmationLabel, action: confirmSelection)
            .buttonStyle(PanelActionButtonStyle(isPrimary: true))
            .disabled(selected == nil || pendingActionId != nil)
            .accessibilityValue(Text(verbatim: selected?.label ?? "No selection"))
            .accessibilityIdentifier("board.choice.confirm")
    }

    private func confirmSelection() {
        guard pendingActionId == nil, let selected,
              let command = PromptCommandBuilder.command(
                gameId: snapshot.id, promptEnvelope: prompt,
                type: prompt.responseCommand?.type ?? "choose_target", promptId: prompt.id,
                playerId: prompt.playerId, ids: [selected.id]
              ) else { return }
        runCommand(command, "Choose \(selected.label)", "\(prompt.id)-card-choice")
    }

    private var completionActions: [LegalAction] {
        (snapshot.legalActions ?? []).filter {
            $0.promptId == prompt.id && $0.type == "answer_yes_no" && $0.confirmed == false
        }
    }

    private var chooserFooter: some View {
        HStack {
            confirmationButton
            ForEach(completionActions) { action in
                Button(action.label) { runAction(action) }
                    .buttonStyle(PanelActionButtonStyle())
                    .disabled(pendingActionId != nil)
                    .accessibilityIdentifier("board.choice.done")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func inspectionOverlay(_ card: ZoneCard) -> some View {
        CardInspector(card: card)
            .overlay(alignment: .topTrailing) {
                Button("Close inspection") { inspected = nil }
                    .padding(12).frame(minHeight: 44)
                    .accessibilityIdentifier("board.choice.inspection.close")
            }
            .inspectionTouchPassthrough()
    }
}
