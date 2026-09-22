import SwiftUI

/// One UUID per native PICK_TARGET response. XMage owns subsequent selection,
/// deselection and ordering prompts; the UI never invents a batch response.
struct BoardCardChoiceView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: GameSnapshot
    let prompt: PromptEnvelopeV2
    let pendingActionId: String?
    let runCommand: (GameCommand, String, String) -> Void
    let runAction: (LegalAction) -> Void
    let commitPlan: (CardChoicePlan) -> Void
    let close: () -> Void
    @State private var selectedID: String?
    @State private var draftIDs: [String] = []
    @State private var topIDs: [String] = []
    @State private var search = ""
    @FocusState private var searchFocused: Bool
    @State private var inspected: ZoneCard?
    @State private var promptTextHeight: CGFloat = 0

    private struct PromptTextHeightKey: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

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
    private var draftKind: CardChoicePlan.Kind? {
        CardChoicePlan.supportsDraft(prompt) ? CardChoicePlan.kind(for: prompt) : nil
    }
    private var selectableIDs: [String] { cards.filter(\.isPromptSelectable).map(\.id) }
    private var draftActive: Bool { draftKind != nil }

    private func toggleSelection(_ id: String) {
        guard pendingActionId == nil,
              cards.contains(where: { $0.id == id && $0.isPromptSelectable }) || targets.contains(where: { $0.id == id }) else { return }
        if let kind = draftKind {
            if kind == .topOrder || kind == .bottomOrder {
                draftIDs = CardChoicePlan.toggled(draftIDs, id: id)
            } else if draftIDs.contains(id) {
                draftIDs = CardChoicePlan.toggled(draftIDs, id: id)
                if kind == .scry { topIDs.append(id) }
            } else {
                draftIDs = CardChoicePlan.toggled(draftIDs, id: id)
                topIDs.removeAll { $0 == id }
            }
            return
        }
        selectedID = selectedID == id ? nil : id
    }

    private func selectionState(_ id: String) -> String {
        if let kind = draftKind {
            if let index = draftIDs.firstIndex(of: id) {
                return kind == .scry ? "Put bottom, position \(index + 1)" : "Position \(index + 1)"
            }
            if kind == .scry, let index = topIDs.firstIndex(of: id) { return "Keep top, position \(index + 1)" }
            return "Keep top"
        }
        if selectedID == id { return chosenIDs.contains(id) ? "Selected to remove" : "Selected" }
        return chosenIDs.contains(id) ? "Chosen · select to remove" : "Not selected"
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = metrics(for: geometry.size)
            ZStack {
                Color.black.opacity(0.58).ignoresSafeArea().accessibilityHidden(true)
                chooserPanel(layout)
                if let inspected { inspectionOverlay(inspected) }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear {
            guard draftActive else { return }
            draftIDs = chosenIDs.filter { selectableIDs.contains($0) }
            topIDs = selectableIDs.filter { !draftIDs.contains($0) }
        }
    }

    private struct ChoiceLayout {
        let width: CGFloat
        let height: CGFloat
        let headerLimit: CGFloat
        let cardWidth: CGFloat
        let columns: [GridItem]
        let sideBySideDraft: Bool
        let orderColumnWidth: CGFloat
        let keyboardCompact: Bool
    }

    private func metrics(for size: CGSize) -> ChoiceLayout {
        let compact = (1...2).contains(cards.count)
        let landscape = size.width > size.height
        let keyboardCompact = searchFocused && cards.count > 6 && size.height < 400
        let sideBySideDraft = draftActive && size.width >= 600 && size.width > size.height &&
            !dynamicTypeSize.isAccessibilitySize && !keyboardCompact
        let height: CGFloat = max(0, min(size.height - (keyboardCompact ? 12 : 24), 680))
        let headerLimit: CGFloat = keyboardCompact ? 44 : min(72, max(44, height * 0.2))
        // Draft contents scroll under a pinned footer; landscape shares the
        // remaining height between two independently scrolling columns.
        let searchHeight: CGFloat = cards.count > 6 && !keyboardCompact ? 44 : 0
        let pendingHeight: CGFloat = pendingActionId != nil ? 32 : 0
        let controlsHeight: CGFloat = headerLimit + searchHeight +
            (keyboardCompact ? 32 : 112) + pendingHeight
        let maximumCardWidth: CGFloat = compact ? 180 : 130
        let heightLimitedCard: CGFloat = max(keyboardCompact ? 70 : 90,
            min(maximumCardWidth, (height - controlsHeight) / 1.4))
        let preferredWidth: CGFloat
        if sideBySideDraft {
            preferredWidth = 600
        } else if compact {
            preferredWidth = cards.count == 1 ? 280 : min(420, max(350, heightLimitedCard * 2 + 60))
        } else {
            preferredWidth = landscape ? 600 : 420
        }
        let width: CGFloat = max(0, min(size.width - 24, preferredWidth))
        let orderColumnWidth: CGFloat = sideBySideDraft ? min(220, max(180, width * 0.33)) : 0
        let gridWidth = width - (sideBySideDraft ? orderColumnWidth + 12 : 0)
        let columnCount = compact && cards.count == 2 && gridWidth >= 240 ? 2 : 1
        let gridSpacing: CGFloat = CGFloat(columnCount - 1) * 12
        let availableCardWidth: CGFloat = (gridWidth - 48 - gridSpacing) / CGFloat(columnCount)
        let cardWidth: CGFloat = max(90, min(heightLimitedCard, availableCardWidth))
        let columns: [GridItem] = compact
            ? Array(repeating: GridItem(.fixed(cardWidth), spacing: 12), count: columnCount)
            : [GridItem(.adaptive(minimum: cardWidth), spacing: 12)]
        let panelHeight: CGFloat = draftActive ? height : compact && targets.isEmpty
            ? min(height, cardWidth * 1.4 + controlsHeight) : height
        return ChoiceLayout(width: width, height: panelHeight, headerLimit: headerLimit,
                            cardWidth: cardWidth, columns: columns,
                            sideBySideDraft: sideBySideDraft, orderColumnWidth: orderColumnWidth,
                            keyboardCompact: keyboardCompact)
    }

    private func chooserPanel(_ layout: ChoiceLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !layout.keyboardCompact { chooserHeader(maxHeight: layout.headerLimit) }
            if cards.count > 6 {
                HStack(spacing: 8) {
                    searchField
                    if layout.keyboardCompact {
                        Button("Prompt") { searchFocused = false }
                            .frame(minHeight: 44)
                            .accessibilityLabel(Text(verbatim: "Read instruction: \(prompt.message)"))
                            .accessibilityHint("Dismiss the keyboard to read the full instruction")
                            .accessibilityIdentifier("board.choice.header")
                        Button("Done") { searchFocused = false }
                            .frame(minWidth: 44, minHeight: 44)
                        closeButton
                    }
                }
            }
            chooserBody(layout)
                .frame(maxHeight: .infinity)
            if !layout.keyboardCompact {
                chooserFooter
                if pendingActionId != nil {
                    ProgressView("Waiting for XMage…").font(.caption)
                }
            }
        }
        .padding(layout.keyboardCompact ? 8 : 12)
        .frame(width: layout.width, height: layout.height)
        .background(MagicPalette.iron, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(MagicPalette.antiqueGold.opacity(0.6)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card choice dialog")
        .accessibilityIdentifier("board.choice.dialog")
        .accessibilityAddTraits(.isModal)
    }

    private var searchField: some View {
        TextField("Name, type or rules text", text: $search)
            .textFieldStyle(.roundedBorder)
            .frame(minHeight: 44)
            .focused($searchFocused)
            .submitLabel(.done)
            .onSubmit { searchFocused = false }
            .accessibilityIdentifier("board.choice.search")
    }

    private var closeButton: some View {
        Button(action: close) {
            Image(systemName: "xmark").frame(width: 44, height: 44)
        }
        .accessibilityLabel("Close card choices")
    }

    @ViewBuilder
    private func chooserBody(_ layout: ChoiceLayout) -> some View {
        if layout.keyboardCompact {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if pendingActionId != nil {
                        ProgressView("Waiting for XMage…").font(.caption)
                    }
                    if !targets.isEmpty {
                        Text("Other targets").font(.subheadline.weight(.semibold))
                        ForEach(targets) { target in targetRow(target) }
                    }
                    ForEach(filteredCards) { card in compactCardRow(card) }
                    if draftActive { draftOrderControls }
                    if filteredCards.isEmpty && !search.isEmpty {
                        emptySearch
                    } else if cards.allSatisfy({ !$0.isPromptSelectable }) && targets.isEmpty {
                        Text("No legal cards to select. You can still hold a card to inspect it.")
                            .font(.subheadline)
                    }
                }
                .padding(6)
            }
            .accessibilityIdentifier("board.choice.cards")
        } else if layout.sideBySideDraft {
            HStack(alignment: .top, spacing: 12) {
                choiceContent(layout)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                ScrollView {
                    draftOrderControls
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(width: layout.orderColumnWidth)
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("board.choice.order.scroll")
            }
            .frame(maxHeight: .infinity)
        } else if draftActive {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    choiceItems(layout)
                    draftOrderControls
                }
                .padding(8)
            }
            .frame(maxHeight: .infinity)
            .accessibilityIdentifier("board.choice.cards")
        } else {
            choiceContent(layout)
        }
    }

    private func chooserHeader(maxHeight: CGFloat) -> some View {
        HStack(alignment: .top) {
            ScrollView {
                Text(prompt.message)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(key: PromptTextHeightKey.self, value: proxy.size.height)
                        }
                    }
                    .accessibilityIdentifier("board.choice.header")
            }
            .frame(height: min(maxHeight, max(24, promptTextHeight)))
            .accessibilityIdentifier("board.choice.message.scroll")
            .onPreferenceChange(PromptTextHeightKey.self) { measured in
                if measured.isFinite, measured > 0, abs(measured - promptTextHeight) > 0.5 {
                    promptTextHeight = measured
                }
            }
            Spacer(minLength: 8)
            closeButton
        }
    }

    private func choiceContent(_ layout: ChoiceLayout) -> some View {
        ScrollView {
            choiceItems(layout).padding(8)
        }
        .accessibilityIdentifier("board.choice.cards")
    }

    private func choiceItems(_ layout: ChoiceLayout) -> some View {
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
            if filteredCards.isEmpty && !search.isEmpty {
                emptySearch
            } else if cards.allSatisfy({ !$0.isPromptSelectable }) && targets.isEmpty {
                Text("No legal cards to select. You can still hold a card to inspect it.")
                    .font(.subheadline)
            }
        }
    }

    private var filteredCards: [ZoneCard] {
        cards.filter { PortraitInteractionPolicy.matchesCardSearch($0, query: search) }
    }

    private var emptySearch: some View {
        HStack {
            Text("No cards match your search.").font(.subheadline)
                .accessibilityIdentifier("board.choice.search.empty")
            Spacer(minLength: 8)
            Button("Clear search") { search = "" }
                .frame(minHeight: 44)
                .accessibilityIdentifier("board.choice.search.clear")
        }
    }

    private var draftOrderControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            if draftKind == .scry {
                Text("Tap cards to Put bottom or Keep top. Use arrows to set each order.")
                    .font(.caption)
                orderRows(draftIDs, title: "Put bottom · first to last", top: false)
                orderRows(topIDs, title: "Keep top · top first", top: true)
            } else {
                Text("Tap cards in order. Tap a numbered card again to remove it.")
                    .font(.caption)
                if let bounds = CardChoicePlan.selectionBounds(prompt.message) {
                    Text("\(draftIDs.count) selected · choose \(bounds.0)–\(bounds.1)")
                        .font(.caption.weight(.semibold))
                }
                orderRows(draftIDs, title: "Choice order", top: false)
            }
        }
    }

    private func orderRows(_ ids: [String], title: String, top: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            VStack(spacing: 6) {
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    HStack(spacing: 2) {
                        Text("\(index + 1). \(cards.first { $0.id == id }?.card.name ?? "Card")")
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("board.choice.order.\(top ? "top" : "bottom").\(id)")
                        Button("Move earlier", systemImage: "chevron.up") { move(id, by: -1, top: top) }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(index == 0 || pendingActionId != nil)
                        Button("Move later", systemImage: "chevron.down") { move(id, by: 1, top: top) }
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                            .disabled(index == ids.count - 1 || pendingActionId != nil)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(5)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func move(_ id: String, by delta: Int, top: Bool) {
        var ids = top ? topIDs : draftIDs
        guard let source = ids.firstIndex(of: id), ids.indices.contains(source + delta) else { return }
        ids.swapAt(source, source + delta)
        if top { topIDs = ids } else { draftIDs = ids }
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
                .accessibilityIdentifier("board.choice.caption.\(card.id)")
            if draftActive || selectedID == card.id || chosenIDs.contains(card.id) {
                Text(selectionState(card.id)).font(.caption2)
            }
        }
        .frame(width: width)
    }

    private func compactCardRow(_ card: ZoneCard) -> some View {
        let isSelected = draftIDs.contains(card.id) || selectedID == card.id
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        let eligibility = card.isPromptSelectable ? "legal choice" : "not a legal choice"
        let selectAction = isSelected ? "Clear selection" : "Select card"
        let hint = card.isPromptSelectable
            ? (draftActive ? "Tap to add or remove from the draft. Inspect card is also available." : "Select, then confirm after dismissing the keyboard. Inspect card is also available.")
            : "This card cannot be selected. Inspect card is available."
        return HStack(spacing: 10) {
            cardArtwork(card, width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.card.name).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("board.choice.caption.\(card.id)")
                Text("\(eligibility) · \(selectionState(card.id))")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .contentShape(Rectangle())
        .onCardInteraction(tap: { toggleSelection(card.id) }, inspect: { inspected = card },
                           release: { if inspected?.id == card.id { inspected = nil } })
        .accessibilityLabel(Text(verbatim: "\(card.card.name), \(eligibility)"))
        .accessibilityValue(Text(verbatim: selectionState(card.id)))
        .accessibilityAddTraits(traits)
        .accessibilityHint(Text(verbatim: hint))
        .accessibilityAction { toggleSelection(card.id) }
        .accessibilityAction(named: Text(selectAction)) { toggleSelection(card.id) }
        .accessibilityAction(named: Text("Inspect card")) { inspected = card }
        .accessibilityIdentifier("board.choice.card.\(card.id)")
    }

    private func cardArtwork(_ card: ZoneCard, width: CGFloat) -> some View {
        let selectable = card.isPromptSelectable
        let border: Color = selectable ? .purple : .clear
        let shadow: Color = selectable ? Color.purple.opacity(0.5) : .clear
        return CardTile(card: card, selected: draftIDs.contains(card.id) || selectedID == card.id, legal: false,
                        zoneName: "Choice", width: width, height: width * 1.4)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(border, lineWidth: 3))
            .shadow(color: shadow, radius: 6)
            .opacity(selectable ? 1 : 0.48)
            .overlay(alignment: .topTrailing) {
                if draftIDs.contains(card.id) || selectedID == card.id || chosenIDs.contains(card.id) {
                    Text(draftActive ? selectionState(card.id) : "✓")
                        .font(.caption2.weight(.bold)).padding(4)
                        .background(.purple, in: Capsule())
                }
            }
    }

    private func accessibleCardTile(_ card: ZoneCard, width: CGFloat) -> some View {
        let isSelected = draftIDs.contains(card.id) || selectedID == card.id
        let traits: AccessibilityTraits = isSelected ? .isSelected : []
        let eligibility = card.isPromptSelectable ? "legal choice" : "not a legal choice"
        let label = "\(card.card.name), \(eligibility)"
        let hint = card.isPromptSelectable
            ? (draftActive ? "Tap to add or remove from the draft. Inspect card is also available." : "Select, then confirm. Inspect card is also available.")
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
        Button(draftActive ? "Confirm plan" : confirmationLabel, action: confirmSelection)
            .buttonStyle(PanelActionButtonStyle(isPrimary: true))
            .disabled((!draftActive && selected == nil) || pendingActionId != nil ||
                      (draftKind == .selection && !draftCountIsValid) ||
                      (draftKind == .topOrder || draftKind == .bottomOrder) && draftIDs.count != selectableIDs.count)
            .accessibilityValue(Text(verbatim: selected?.label ?? "No selection"))
            .accessibilityIdentifier("board.choice.confirm")
    }

    private var draftCountIsValid: Bool {
        guard let bounds = CardChoicePlan.selectionBounds(prompt.message) else { return false }
        return draftIDs.count >= bounds.0 && draftIDs.count <= bounds.1
    }

    private func confirmSelection() {
        if draftActive {
            let kind = CardChoicePlan.kind(for: prompt)
            let top = kind == .scry ? topIDs : []
            commitPlan(CardChoicePlan(snapshot: snapshot, prompt: prompt, selected: draftIDs, top: top))
            return
        }
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
            ForEach(draftActive ? [] : completionActions) { action in
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
