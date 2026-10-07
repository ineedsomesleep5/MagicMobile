import SwiftUI
import PhotosUI
import UIKit

struct CompactZoneInspectorOverlay: View {
    @Environment(\.tavernBoard) private var tavern
    let title: String
    let cards: [ZoneCard]
    let legalActions: [LegalAction]
    let pendingActionId: String?
    @Binding var selectedCard: ZoneCard?
    @Binding var inspectedCard: ZoneCard?
    let runAction: (LegalAction) -> Void
    let closeAction: () -> Void
    var targetableIDs: Set<String> = []
    var runTargetAction: ((ZoneCard) -> Void)? = nil
    var availableHeight: CGFloat = 410

    private func perform(_ action: LegalAction) {
        guard pendingActionId == nil, legalActions.contains(where: { $0.id == action.id }) else { return }
        if GameplayAffordances.dismissesZone(action: action) {
            selectedCard = nil
            inspectedCard = nil
            closeAction()
        }
        runAction(action)
    }

    var body: some View {
        VStack(spacing: 8) {
            // Title Bar
            HStack {
                Text("\(title) · \(cards.count)")
                    .font(.system(size: 14, weight: .bold, design: .serif))
                    .foregroundStyle(MagicPalette.antiqueGold)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button(action: closeAction) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MagicPalette.parchment.opacity(0.6))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close \(title)")
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()
                .background(MagicPalette.antiqueGold.opacity(0.18))

            // Scrollable Grid of Cards
            ScrollView {
                if cards.isEmpty {
                    Text(title.contains("Library") ? "The library is face down. Only a revealed top card shows here." : "No cards here.")
                        .font(.system(size: 14, design: .serif).italic())
                        .foregroundStyle(MagicPalette.parchment.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)], alignment: .leading, spacing: 12) {
                        ForEach(cards) { card in
                            let cardActions = GameBoardInteractionState.cardActions(for: card, actions: legalActions)
                            let targetable = runTargetAction != nil && (targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id))
                            VStack(spacing: 8) {
                                CardTile(card: card, selected: selectedCard?.id == card.id, legal: !cardActions.isEmpty || targetable, zoneName: title, width: 76, height: 106)
                                    .onCardInteraction(tap: {
                                        selectedCard = card
                                        inspectedCard = nil
                                    }, inspect: {
                                        inspectedCard = card
                                    }, release: { if inspectedCard?.id == card.id { inspectedCard = nil } })
                                if targetable {
                                    Button {
                                        guard pendingActionId == nil,
                                              targetableIDs.contains(card.instanceId) || targetableIDs.contains(card.id) else { return }
                                        runTargetAction?(card)
                                    } label: {
                                        Label("Target", systemImage: "scope")
                                            .font(.system(size: 13, weight: .bold, design: .serif))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
                                    .disabled(pendingActionId != nil)
                                    .accessibilityLabel("Target \(card.card.name)")
                                }
                                if let action = cardActions.first, cardActions.count == 1 {
                                    Button {
                                        perform(action)
                                    } label: {
                                        Text(action.displayLabel)
                                            .font(.system(size: 13, weight: .bold, design: .serif))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.center)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .buttonStyle(PanelActionButtonStyle(isPrimary: true, compact: true))
                                    .disabled(pendingActionId != nil)
                                }
                                if cardActions.count > 1 {
                                    // The tavern's own leather pop-over, not the system menu.
                                    TavernMenu(arrowEdge: .bottom) {
                                        ForEach(cardActions) { action in
                                            TavernMenuItem(title: action.displayLabel, systemImage: "sparkles") { perform(action) }
                                        }
                                    } label: {
                                        Text("Actions")
                                            .font(.system(size: 13, weight: .bold, design: .serif))
                                            .foregroundStyle(MagicPalette.parchment)
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(pendingActionId != nil)
                                }
                                Button {
                                    inspectedCard = card
                                } label: {
                                    Text("Inspect")
                                        .font(.system(size: 13, weight: .semibold, design: .serif))
                                        .foregroundStyle(MagicPalette.parchment.opacity(0.85))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Inspect \(card.card.name)")
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .frame(maxWidth: 360)
        .frame(height: min(availableHeight, cards.isEmpty ? 150 : (cards.count <= 3 ? 290 : 410)))
        .modifier(TavernPanelChrome(tavern: tavern))
        .shadow(color: .black.opacity(0.45), radius: 16, y: 8)
    }
}
