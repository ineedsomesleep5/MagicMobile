import SwiftUI

/// Analysis remains independent of the saved deck/engine DTO. Preferences are
/// local to the deck, with explicit source labels and no opaque quality score.
struct DeckStudioRoleInsightsView: View {
    let draft: NativeDeckDraft
    let metadata: NativeDeckMetadataCatalogue?
    let contextID: String?
    let inspect: (String) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var preferences = DeckStudioRolePreferences()
    @State private var loadedKey: String?
    @State private var blocked = false
    @State private var error: String?
    @State private var selectedRole: DeckStudioRole?
    @State private var review: RoleReview?
    @State private var showTargets = false
    private let defaults = UserDefaults.standard
    private var key: String { "deckStudio.roles.v1." + (contextID ?? "new") }
    private struct RoleReview: Identifiable {
        let name: String
        let roles: Set<DeckStudioRole>
        let key: String
        var id: String { name }
    }
    private var analysis: DeckStudioRoleAnalysis? {
        let rows = draft.rows.filter { DeckStudioDraftPresentation.section($0) == "deck" }
        return try? DeckStudioRoleAnalysis(entries: rows.map { row in
            let card = metadata?.card(named: row.cardName)
            return .init(name: row.cardName, quantity: row.quantity, text: card?.oracleText, types: card?.types,
                         curated: (card?.roles ?? []).compactMap(DeckStudioRole.init(rawValue:)))
        }, overrides: preferences.overrides)
    }
    private func sourceLabel(_ source: DeckStudioRoleEvidence.Source) -> String {
        switch source {
        case .reviewed: return "Your tag"
        case .curated: return "Curated tag"
        case .textPattern: return "Text-pattern hint"
        }
    }
    var body: some View {
        DeckStudioPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("What your cards do").font(.system(.title2, design: .serif).weight(.semibold))
                Text("Card roles · reviewable, not a deck score")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                Text("Roles come from Scryfall's community-curated oracle tags, bundled with this build and used offline. Cards those tags miss fall back to conservative rules-text patterns, which leave triggered and conditional effects unclassified. Draw includes cantrips, not just net card advantage. Your own tags override everything here.")
                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.warning) }
                if contextID == nil { Text("Save this draft once to customize role tags and target ranges for this deck.").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk) }
                if let analysis {
                    ForEach(DeckStudioRole.allCases) { role in
                        Button { selectedRole = selectedRole == role ? nil : role } label: {
                            HStack(alignment: .firstTextBaseline) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(role.title).font(.subheadline.weight(.medium))
                                    if let target = preferences.targets[role], let comparison = target.comparison(analysis.count(role)) {
                                        Text("\(comparison) · \(target.lower)–\(target.upper)")
                                            .font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk)
                                    }
                                }
                                Spacer()
                                Text("\(analysis.count(role))").font(.subheadline.monospacedDigit())
                                Image(systemName: selectedRole == role ? "chevron.up" : "chevron.down").font(.caption2)
                            }.frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityLabel("\(role.title), \(analysis.count(role)) cards. Review detected cards.")
                        if selectedRole == role {
                            let matching = analysis.cards.filter { $0.evidence.contains { $0.role == role } }
                            if matching.isEmpty {
                                Text("No cards tagged for this role. Curated tags and text patterns are not exhaustive, so check the cards yourself before concluding your deck lacks the effect.")
                                    .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            }
                            ForEach(matching) { card in
                                VStack(alignment: .leading, spacing: 5) {
                                    Button { inspect(card.name) } label: {
                                        HStack(spacing: 10) {
                                            if !dynamicType.isAccessibilitySize {
                                                DeckStudioArtwork(name: card.name).frame(width: 40, height: 56)
                                                    .clipShape(RoundedRectangle(cornerRadius: 5))
                                            }
                                            Text("\(card.quantity) × \(card.name)").font(.subheadline)
                                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                            Spacer(minLength: 0)
                                        }
                                    }.frame(minHeight: 44)
                                    ForEach(card.evidence.filter { $0.role == role }, id: \.role) { evidence in
                                        Text("\(sourceLabel(evidence.source)): \(evidence.explanation)")
                                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                    }
                                }.padding(.leading, 12)
                            }
                        }
                    }
                    Divider()
                    Text("\(analysis.unclassifiedCount) of \(analysis.mainCount) main-deck cards have no role tag. \(analysis.missingMetadataCount) have incomplete metadata. Counts include quantities; one card can have multiple roles. Lands can be tagged but do not count as automatic ramp.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    Button("Set my target ranges", systemImage: "slider.horizontal.3") { showTargets = true }
                        .frame(minHeight: 44).disabled(blocked || contextID == nil)
                    DisclosureGroup("Review or assign card roles") {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(analysis.cards) { card in
                                Button {
                                    review = RoleReview(name: card.name, roles: Set(card.evidence.map(\.role)), key: key)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(card.name).font(.subheadline)
                                        Text(card.evidence.isEmpty ? "Unclassified" : card.evidence.map(\.role.title).joined(separator: " · "))
                                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                                        if card.userReviewed { Text("Your reviewed tags").font(.caption2) }
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                }.buttonStyle(.plain).disabled(blocked || contextID == nil)
                            }
                        }.padding(.top, 8)
                    }
                } else {
                    Text("Role analysis is unavailable for malformed or oversized draft data. Your deck is unchanged.").font(.caption)
                }
            }
        }
        .task(id: key) { load() }
        .sheet(item: $review) { selection in
            DeckStudioRoleReviewSheet(name: selection.name, original: selection.roles) { tags in
                guard selection.key == key else { return false }
                return change { value in
                    if let tags { value.overrides[selection.name] = tags }
                    else { value.overrides.removeValue(forKey: selection.name) }
                }
            }
        }
        .sheet(isPresented: $showTargets) {
            DeckStudioRoleTargetsSheet(original: preferences.targets, save: { targets in change { $0.targets = targets } })
        }
    }
    private func load() {
        guard loadedKey != key else { return }
        review = nil; showTargets = false
        do {
            preferences = contextID == nil ? DeckStudioRolePreferences() : try DeckStudioRolePreferences.load(key: key, defaults: defaults)
            loadedKey = key; blocked = false; error = nil
        } catch {
            loadedKey = key; blocked = true; preferences = DeckStudioRolePreferences()
            self.error = "Analysis preferences need recovery. The stored data is preserved and editing these settings is paused; deck editing still works."
        }
    }
    private func change(_ edit: (inout DeckStudioRolePreferences) -> Void) -> Bool {
        guard contextID != nil, !blocked, loadedKey == key else { return false }
        var changed = preferences; edit(&changed)
        do {
            try changed.save(key: key, defaults: defaults)
            preferences = changed; error = nil; return true
        } catch { self.error = error.localizedDescription; return false }
    }
}

private struct DeckStudioRoleReviewSheet: View {
    let name: String
    let save: (Set<DeckStudioRole>?) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<DeckStudioRole>
    init(name: String, original: Set<DeckStudioRole>, save: @escaping (Set<DeckStudioRole>?) -> Bool) {
        self.name = name; self.save = save; _selected = State(initialValue: original)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(DeckStudioRole.allCases) { role in
                        Toggle(role.title, isOn: Binding(get: { selected.contains(role) }, set: { enabled in
                            if enabled { selected.insert(role) } else { selected.remove(role) }
                        }))
                    }
                } header: { Text(name) } footer: { Text("These are your functional tags, not XMage legality or EDHREC statistics. An empty selection explicitly clears automatic hints for this card.") }
                Button("Use automatic hints again") { if save(nil) { dismiss() } }
            }.navigationTitle("Review roles").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if save(selected) { dismiss() } } }
                }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}

private struct DeckStudioRoleTargetsSheet: View {
    let save: ([DeckStudioRole: DeckStudioRolePreferences.Target]) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var targets: [DeckStudioRole: DeckStudioRolePreferences.Target]
    init(original: [DeckStudioRole: DeckStudioRolePreferences.Target], save: @escaping ([DeckStudioRole: DeckStudioRolePreferences.Target]) -> Bool) {
        self.save = save; _targets = State(initialValue: original)
    }
    var body: some View {
        NavigationStack {
            Form {
                Text("Choose your own ranges. All targets start off; there is no universal ideal Commander deck. These targets compare tagged main-deck quantities, not unrecognized effects.").font(.caption)
                ForEach(DeckStudioRole.allCases) { role in
                    Section(role.title) {
                        Toggle("Compare with my target", isOn: Binding(get: { targets[role]?.enabled ?? false }, set: {
                            targets[role, default: .init()].enabled = $0
                        }))
                        if targets[role]?.enabled == true {
                            Stepper("Minimum: \(targets[role]?.lower ?? 0)", value: Binding(get: { targets[role]?.lower ?? 0 }, set: {
                                targets[role, default: .init()].lower = $0
                                targets[role, default: .init()].upper = max($0, targets[role]?.upper ?? 0)
                            }), in: 0...2000)
                            Stepper("Maximum: \(targets[role]?.upper ?? 0)", value: Binding(get: { targets[role]?.upper ?? 0 }, set: {
                                targets[role, default: .init()].upper = $0
                                targets[role, default: .init()].lower = min($0, targets[role]?.lower ?? 0)
                            }), in: 0...2000)
                        }
                    }
                }
            }.navigationTitle("My target ranges").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") { if save(targets) { dismiss() } } }
                }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
}
