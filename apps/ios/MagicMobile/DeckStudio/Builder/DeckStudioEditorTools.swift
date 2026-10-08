import SwiftUI

struct DeckStudioReplacementPicker: View {
    let metadata: NativeDeckMetadataCatalogue?
    let commander: Bool
    /// The commander's color identity. A replacement stays within it unless the player turns that off.
    var colors: [String]? = nil
    let replace: (String, Bool) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var keepOld = true
    @State private var constrainIdentity = true
    @State private var error: String?
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    private struct Request: Equatable { let query: String; let identity: [String]? }
    private var request: Request { Request(query: query, identity: !commander && constrainIdentity ? colors : nil) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Search exact catalogue cards", text: $query).textFieldStyle(GrimoireFieldStyle()).autocorrectionDisabled().padding(.horizontal, 20)
                if !commander, colors != nil {
                    Toggle(DeckStudioPlayText.withinIdentity, isOn: $constrainIdentity).font(.caption).padding(.horizontal, 20)
                }
                if commander {
                    Toggle("Keep replaced commander in maybeboard", isOn: $keepOld).font(.caption).padding(.horizontal, 20)
                    Text("Replaces the primary commander only. Partners remain. One matching main-deck copy is promoted; XMage still checks commander eligibility and duplicates.")
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk).padding(.horizontal, 20)
                } else { Text("Keeps the row's quantity, section and identity. Undo reverses the replacement.").font(.caption).padding(.horizontal, 20) }
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                List(results) { card in
                    Button {
                        if replace(card.name, keepOld) { dismiss() }
                        else { error = "The draft changed or this edit exceeds its limits. No partial edit was committed." }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) { Text(card.name).font(.subheadline); Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk) }
                            .frame(minHeight: 44)
                    }.listRowBackground(DeckStudioPalette.surface)
                }.scrollContentBackground(.hidden)
            }.background(GrimoirePaper())
                .binderLeaf(commander ? "Change commander" : "Replace card", leading: BinderLeafAction(title: "Cancel") { dismiss() })
                // Identity-limited searches scan several identity buckets, so they run off the main thread.
                .task(id: request) {
                    guard let metadata else { results = []; return }
                    let captured = request
                    let found = await Task.detached(priority: .userInitiated) {
                        DeckStudioCatalogueSearch.cards(in: metadata, query: captured.query, allowedIdentity: captured.identity, limit: 80)
                    }.value
                    guard !Task.isCancelled, captured == request else { return }
                    results = found
                }
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
    }
}

struct DeckStudioBasicLandsSheet: View {
    let draft: NativeDeckDraft
    let apply: ([String: Int], NativeDeckDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: Int]
    @State private var error: String?
    init(draft: NativeDeckDraft, apply: @escaping ([String: Int], NativeDeckDraft) -> Bool) {
        self.draft = draft; self.apply = apply
        _values = State(initialValue: Dictionary(uniqueKeysWithValues: NativeDeckDraft.basicLandNames.map { ($0, draft.basicLandCount($0)) }))
    }
    var body: some View {
        NavigationStack {
            GrimoireForm {
                Text("Set main-deck basic-land counts. Other sections, snow basics and nonbasic lands stay unchanged. This is your edit, not an automatic mana-base recommendation.").font(.caption)
                ForEach(NativeDeckDraft.basicLandNames, id: \.self) { name in
                    BinderStepper("\(name): \(values[name, default: 0])", value: Binding(get: { values[name, default: 0] }, set: { values[name] = $0 }), in: 0...2000)
                }
                if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
            }.binderLeaf("Basic lands", leading: BinderLeafAction(title: "Cancel") { dismiss() },
                         trailing: BinderLeafAction(title: "Apply", identifier: "deckStudio.basics.apply") {
                             if apply(values, draft) { dismiss() } else { error = "The draft changed or these counts exceed its limits. Nothing was partially applied." }
                         })
        }.tint(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
    }
}

/// Commander-first new decks: a new draft opens on this picker. Skip keeps an empty draft.
struct DeckStudioCommanderFirstPicker: View {
    let metadata: NativeDeckMetadataCatalogue?
    let choose: (String) -> Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var query = ""
    @State private var results: [NativeDeckMetadataCatalogue.Card] = []
    @State private var error: String?
    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DeckStudioPlayText.commanderFirstTitle).font(.headline)
                    Text(DeckStudioPlayText.commanderFirstCaption)
                        .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    TextField(DeckStudioPlayText.searchCommanders, text: $query).textFieldStyle(GrimoireFieldStyle()).autocorrectionDisabled()
                        .submitLabel(.search).accessibilityIdentifier("deckStudio.commanderFirst.search")
                    if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                if metadata == nil {
                    DeckStudioNotice(title: "Local catalogue unavailable", message: "Skip for now and add a commander from Add cards once the catalogue loads.")
                        .listRowBackground(Color.clear)
                } else if results.isEmpty && !query.isEmpty {
                    BinderEmptyLeaf(title: "No matching commanders", icon: "crown", message: "Try another name.")
                        .listRowBackground(Color.clear)
                }
                ForEach(results) { card in
                    Button {
                        if choose(card.name) { dismiss() }
                        else { error = "This commander could not be added. The draft is unchanged." }
                    } label: {
                        HStack(spacing: 12) {
                            if !dynamicType.isAccessibilitySize {
                                DeckStudioArtwork(name: card.name).frame(width: 40, height: 56).clipShape(RoundedRectangle(cornerRadius: 5))
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(card.name).font(.subheadline.weight(.medium))
                                Text(card.typeLine ?? "Type unavailable").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                            }
                            Spacer(minLength: 0)
                            DeckStudioColorIdentity(colors: card.colorIdentity)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).listRowBackground(DeckStudioPalette.surface)
                        .accessibilityLabel("Choose \(card.name) as commander")
                }
            }.listStyle(.plain).scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
                .background(GrimoirePaper())
                .binderLeaf(DeckStudioPlayText.chooseCommander,
                            leading: BinderLeafAction(title: DeckStudioPlayText.skip, identifier: "deckStudio.commanderFirst.skip") { dismiss() })
                .task(id: query) {
                    guard let metadata else { return }
                    let captured = query
                    do { try await Task.sleep(for: .milliseconds(120)) } catch { return }
                    let found = await Task.detached(priority: .userInitiated) {
                        DeckStudioCatalogueSearch.commanders(in: metadata, query: captured, limit: 60)
                    }.value
                    guard !Task.isCancelled, captured == query else { return }
                    results = found
                }
        }.tint(DeckStudioPalette.ink).foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
    }
}

/// Edit as text: the deck in the plain-text export format, reviewed as added and
/// removed cards before it is applied as one undo step.
struct DeckStudioTextEditorSheet: View {
    let draft: NativeDeckDraft
    let apply: (NativeDeckDraft, NativeDeckDraft) -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var review: Review?
    @State private var error: String?
    private let unsupported: Bool
    private struct Review { let draft: NativeDeckDraft; let diff: DeckStudioTextDiff; let notes: [String] }
    init(draft: NativeDeckDraft, apply: @escaping (NativeDeckDraft, NativeDeckDraft) -> Bool) {
        self.draft = draft; self.apply = apply
        var named = draft
        if named.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { named.name = "Draft" }
        if draft.rows.isEmpty { _text = State(initialValue: ""); unsupported = false }
        else if let deck = try? named.deck(), let text = try? DeckStudioTextExport.text(deck) { _text = State(initialValue: text); unsupported = false }
        else { _text = State(initialValue: ""); unsupported = true }
    }
    var body: some View {
        NavigationStack {
            Group {
                if unsupported {
                    DeckStudioNotice(title: "Plain text can't hold this draft",
                                     message: "It has custom sections or card names the text format can't keep. Edit it card by card, or export native JSON.",
                                     icon: "exclamationmark.triangle").padding(20)
                } else if let review {
                    List {
                        if review.diff.isEmpty { Text(DeckStudioPlayText.noChanges).font(.subheadline) }
                        if !review.diff.added.isEmpty {
                            Section(DeckStudioPlayText.diffAdded) {
                                ForEach(review.diff.added) { Text($0.label).font(.subheadline).foregroundStyle(DeckStudioPalette.success) }
                            }
                        }
                        if !review.diff.removed.isEmpty {
                            Section(DeckStudioPlayText.diffRemoved) {
                                ForEach(review.diff.removed) { Text($0.label).font(.subheadline).foregroundStyle(DeckStudioPalette.danger) }
                            }
                        }
                        if !review.diff.art.isEmpty {
                            Section(DeckStudioPlayText.diffArt) {
                                ForEach(review.diff.art) { Text($0.label).font(.subheadline) }
                            }
                        }
                        if !review.notes.isEmpty {
                            Section("Notes") { ForEach(review.notes, id: \.self) { Text($0).font(.caption) } }
                        }
                        if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger) }
                    }.scrollContentBackground(.hidden)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(DeckStudioPlayText.textEditorHint)
                            .font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                        TextEditor(text: $text).font(.system(.callout, design: .monospaced)).autocorrectionDisabled()
                            .textInputAutocapitalization(.never).scrollContentBackground(.hidden)
                            .padding(8).background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel("Deck list text").accessibilityIdentifier("deckStudio.textEditor")
                        if let error { Text(error).font(.caption).foregroundStyle(DeckStudioPalette.danger).textSelection(.enabled) }
                    }.padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(GrimoirePaper())
            .binderLeaf(DeckStudioPlayText.editAsText,
                        leading: review != nil ? BinderLeafAction(title: DeckStudioPlayText.keepEditing) { review = nil; error = nil }
                            : BinderLeafAction(title: "Cancel") { dismiss() },
                        trailing: review.map { review in
                            BinderLeafAction(title: DeckStudioPlayText.applyChanges, identifier: "deckStudio.textEditor.apply", disabled: review.diff.isEmpty) {
                                if apply(draft, review.draft) { dismiss() }
                                else { error = "The deck changed while you were editing, or this list exceeds its limits. Nothing was applied." }
                            }
                        } ?? (unsupported ? nil : BinderLeafAction(title: DeckStudioPlayText.reviewChanges, identifier: "deckStudio.textEditor.review") { prepareReview() }))
        }.tint(DeckStudioPalette.ink).foregroundStyle(DeckStudioPalette.ink).preferredColorScheme(.light).grimoirePage(.loose)
    }
    private func prepareReview() {
        do {
            let parsed = try DeckStudioTextDiff.draft(from: text, replacing: draft)
            review = Review(draft: parsed.draft, diff: DeckStudioTextDiff(from: draft, to: parsed.draft), notes: parsed.notes)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

/// Live quick check in the workspace header. Tapping a row issue filters the Cards list.
struct DeckStudioPreflightBar: View {
    let preflight: DeckStudioPreflight
    @Binding var filter: DeckStudioPreflight.Issue?
    let chooseCommander: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(preflight.count)/\(DeckStudioPreflight.targetCount)").font(.system(size: 17, weight: .heavy, design: .serif).monospacedDigit())
                    .foregroundStyle(DeckStudioPalette.ink)
                    .accessibilityLabel("\(CardCountText.label(preflight.count)) of \(DeckStudioPreflight.targetCount)")
                Text(preflight.summary).font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(preflight.issueCount == 0 ? DeckStudioPalette.success : DeckStudioPalette.warning)
                Spacer(minLength: 0)
            }
            // The brass gauge, as on the title plate.
            BinderGauge(count: preflight.count, target: DeckStudioPreflight.targetCount, showsCount: false)
                .accessibilityHidden(true)
            if !preflight.activeIssues.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) { ForEach(preflight.activeIssues) { chip($0) } }.padding(.vertical, 2)
                }
            }
            Text(DeckStudioPreflight.caption).font(.system(size: 12, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
        }
        .padding(.top, 16).padding(.bottom, 6).frame(maxWidth: .infinity, alignment: .leading)
        // Ruled off from the plate above it rather than boxed.
        .overlay(alignment: .top) { GrimoireRule() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deckStudio.quickCheck")
    }
    private func chip(_ issue: DeckStudioPreflight.Issue) -> some View {
        let selected = filter == issue
        return Button {
            if issue == .missingCommander { chooseCommander() }
            else { filter = selected ? nil : issue }
        } label: {
            BinderChip(title: preflight.chipTitle(issue), icon: issue == .missingCommander ? "crown" : "exclamationmark.triangle", chosen: selected)
                .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(issue == .missingCommander ? issue.title : "\(issue.title), \(CardCountText.label(preflight.rows(issue).count))")
            .accessibilityHint(issue == .missingCommander ? "Choose a commander" : (selected ? "Shows every card again" : "Shows only these cards"))
            .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Persistent Quick Add beside Add cards: type "2x Sol Ring", pick from the top five
/// local matches, and keep typing. Each add can be undone from its toast.
struct DeckStudioQuickAddBar: View {
    let metadata: NativeDeckMetadataCatalogue?
    @ObservedObject var model: DeckStudioEditorModel
    let openSearch: () -> Void
    /// At the foot of a binder page, on leather: a dark well to write in and brass plaques.
    var binder = false
    @Environment(\.dynamicTypeSize) private var dynamicType
    @State private var text = ""
    @State private var maybeboard = false
    @State private var suggestions: [NativeDeckMetadataCatalogue.Card] = []
    @State private var note: String?
    @State private var error: String?
    @State private var toast: Toast?
    @FocusState private var focused: Bool
    private struct Toast: Equatable { let message: String; let generation: UUID }
    private var parsed: DeckStudioQuickAdd? { DeckStudioQuickAdd.parse(text) { metadata?.card(named: $0) != nil } }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if focused, !suggestions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(suggestions) { card in
                        Button { commit(card) } label: {
                            HStack {
                                Text(card.name).font(.subheadline).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(card.typeLine ?? "").font(.caption2).foregroundStyle(DeckStudioPalette.secondaryInk).lineLimit(1)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).padding(.horizontal, 12)
                            .accessibilityLabel("Quick add \(parsed?.quantity ?? 1) \(card.name)")
                        if card.id != suggestions.last?.id { Divider() }
                    }
                }.background { GrimoirePaper(tone: .plate).clipShape(RoundedRectangle(cornerRadius: 12)) }
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(binder ? AnyShapeStyle(Binder.brass) : AnyShapeStyle(DeckStudioPalette.separator), lineWidth: binder ? 1.5 : 1))
                    .shadow(color: .black.opacity(binder ? 0.25 : 0), radius: 8, y: 3)
            }
            // The bar floats over the page (Caleb, 2026-10-06), so its notes are written in ink.
            if let error { Text(error).font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(DeckStudioPalette.danger) }
            else if let note { Text(note).font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk) }
            else if focused, text.isEmpty {
                Text(DeckStudioPlayText.quickAddHint)
                    .font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
            }
            if let toast {
                HStack {
                    Text(toast.message).font(.system(size: 13, weight: .bold, design: .serif)).lineLimit(2)
                        .foregroundStyle(Color(red: 0.98, green: 0.86, blue: 0.62))
                    Spacer(minLength: 8)
                    Button(DeckStudioPlayText.undo) { model.undo(); self.toast = nil }
                        .buttonStyle(BinderPlaqueButtonStyle())
                        .disabled(model.history.generation != toast.generation)
                        .accessibilityIdentifier("deckStudio.quickAdd.undo")
                }.padding(.leading, 12).padding(.trailing, 4)
                    .background {
                        ZStack { TavernFill(material: .leather); Binder.dye(Binder.oxblood, 0.4) }
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Binder.brass, lineWidth: 1.5))
                    }
                    .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
                    .accessibilityElement(children: .contain)
            }
            if dynamicType.isAccessibilitySize {
                field
                HStack { destinationToggle; Spacer(); addCardsButton }
            } else {
                HStack(spacing: 8) { field; destinationToggle; addCardsButton }
            }
        }
        .task(id: text) { await suggest() }
        .onChange(of: text) { _, value in if !value.isEmpty { error = nil; note = nil } }
        .task(id: toast) {
            guard let toast else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            if self.toast == toast { self.toast = nil }
        }
    }
    private var field: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus.magnifyingglass").foregroundStyle(binder ? Binder.brassLight : DeckStudioPalette.secondaryInk).accessibilityHidden(true)
            TextField(DeckStudioPlayText.quickAdd, text: $text,
                      prompt: binder ? Text(DeckStudioPlayText.quickAdd).foregroundStyle(TavernPalette.parchment.opacity(0.5)) : nil)
                .foregroundStyle(binder ? TavernPalette.parchment : DeckStudioPalette.ink).tint(binder ? Binder.brassLight : DeckStudioPalette.ink)
                .autocorrectionDisabled().textInputAutocapitalization(.words)
                .focused($focused).submitLabel(.done)
                .onSubmit { commit(nil); DispatchQueue.main.async { focused = true } }
                .accessibilityIdentifier("deckStudio.quickAdd")
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").frame(width: 32, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(binder ? TavernPalette.parchment.opacity(0.7) : DeckStudioPalette.secondaryInk)
                    .accessibilityLabel("Clear quick add")
            }
        }.padding(.horizontal, 10).frame(minHeight: DeckStudioMetrics.controlHeight)
            // Floating over the page's cards, the well is solid leather so nothing shows through it.
            .background {
                if binder {
                    ZStack { TavernFill(material: .leather); Binder.dye(Binder.leatherDark, 0.55) }
                        .clipShape(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).fill(DeckStudioPalette.surfaceElevated)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(binder ? Binder.brassLight.opacity(0.3) : DeckStudioPalette.separator))
    }
    private var destinationToggle: some View {
        Button { maybeboard.toggle() } label: {
            if binder {
                Text(maybeboard ? DeckStudioPlayText.quickAddMaybe : DeckStudioPlayText.quickAddMain).font(.caption.weight(.heavy))
                    .frame(minWidth: 44)
            } else {
            Text(maybeboard ? DeckStudioPlayText.quickAddMaybe : DeckStudioPlayText.quickAddMain).font(.caption.weight(.semibold)).frame(minWidth: 52, minHeight: DeckStudioMetrics.controlHeight)
                .foregroundStyle(maybeboard ? DeckStudioPalette.surfaceElevated : DeckStudioPalette.ink)
                .background(maybeboard ? DeckStudioPalette.accent : DeckStudioPalette.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
                .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(maybeboard ? .clear : DeckStudioPalette.separator))
            }
        }.buttonStyle(BinderOrPlainButtonStyle(binder: binder, on: maybeboard))
            .accessibilityLabel(DeckStudioPlayText.quickAddMaybeboard).accessibilityValue(maybeboard ? "On" : "Off")
            .accessibilityAddTraits(maybeboard ? [.isSelected] : [])
            .accessibilityIdentifier("deckStudio.quickAdd.maybeboard")
    }
    @ViewBuilder private var addCardsButton: some View {
        if binder {
            Button(action: openSearch) { Label(DeckStudioPlayText.addCards, systemImage: "plus").fixedSize(horizontal: true, vertical: false) }
                .buttonStyle(BinderPlaqueButtonStyle())
                .accessibilityIdentifier("deckStudio.addCards")
        } else {
        Button(action: openSearch) {
            Label(DeckStudioPlayText.addCards, systemImage: "plus").font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 12).frame(minHeight: DeckStudioMetrics.controlHeight)
                .foregroundStyle(DeckStudioPalette.surfaceElevated)
                .background(DeckStudioPalette.ink, in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
                .fixedSize(horizontal: true, vertical: false)
        }.buttonStyle(DeckStudioArtworkButtonStyle())
            .accessibilityIdentifier("deckStudio.addCards")
        }
    }
    private func suggest() async {
        guard let metadata, let name = parsed?.name else { suggestions = []; return }
        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        let found = await Task.detached(priority: .userInitiated) {
            DeckStudioCatalogueSearch.nameSuggestions(in: metadata, query: name, limit: 5)
        }.value
        guard !Task.isCancelled else { return }
        suggestions = found
    }
    private func commit(_ chosen: NativeDeckMetadataCatalogue.Card?) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard let parsed else { error = DeckStudioPlayText.quickAddNeedsName; return }
        guard let metadata else { error = DeckStudioPlayText.catalogueLoading; return }
        guard let card = chosen ?? metadata.card(named: parsed.name)
                ?? DeckStudioCatalogueSearch.nameSuggestions(in: metadata, query: parsed.name, limit: 1).first else {
            error = DeckStudioPlayText.noCardNamed(parsed.name); return
        }
        let board = maybeboard ? "maybeboard" : "deck"
        if model.change({ try DeckStudioEditorOperations.add(in: &$0, name: card.name, quantity: parsed.quantity, section: board) }) {
            toast = Toast(message: DeckStudioPlayText.added(parsed.quantity, card.name, maybeboard: maybeboard), generation: model.history.generation)
            note = parsed.note; error = nil; text = ""; suggestions = []
        } else { error = DeckStudioPlayText.quickAddFailed }
    }
}

/// Bottom bar for multi-select. Each action is one undo step.
struct DeckStudioBulkBar: View {
    let count: Int
    let move: (String) -> Void
    let setQuantity: () -> Void
    let remove: () -> Void
    let selectAll: () -> Void
    struct Destination: Hashable { let section: String; let title: String }
    /// "considering" rows count as maybeboard, so it is not offered separately.
    static let destinations = DeckStudioPlayText.destinations.map { Destination(section: $0.section, title: $0.title) }
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(DeckStudioPlayText.selected(count)).font(.subheadline.weight(.semibold)).monospacedDigit()
                Spacer()
                Button(DeckStudioPlayText.selectAll, action: selectAll).font(.subheadline).frame(minHeight: 44)
            }
            HStack(spacing: 8) {
                BinderMenu {
                    BinderMenuHeading(DeckStudioPlayText.moveTo)
                    ForEach(Self.destinations, id: \.section) { destination in
                        BinderMenuButton(destination.title) { move(destination.section) }
                    }
                } label: { action(DeckStudioPlayText.moveTo, "arrow.right.square", tint: DeckStudioPalette.ink) }
                Button(action: setQuantity) { action(DeckStudioPlayText.setQuantity, "number", tint: DeckStudioPalette.ink) }.buttonStyle(.plain)
                Button(action: remove) { action(DeckStudioPlayText.remove, "trash", tint: DeckStudioPalette.danger) }.buttonStyle(.plain)
            }.disabled(count == 0).opacity(count == 0 ? 0.45 : 1)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("deckStudio.bulkBar")
    }
    private func action(_ title: String, _ icon: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.body.weight(.semibold))
            Text(title).font(.caption.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
        }.foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: DeckStudioMetrics.controlHeight)
            .background(DeckStudioPalette.surfaceElevated, in: RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius))
            .overlay(RoundedRectangle(cornerRadius: DeckStudioMetrics.controlRadius).stroke(DeckStudioPalette.separator))
            .contentShape(Rectangle())
    }
}

/// The brass plaque on a binder page, the plain button elsewhere.
private struct BinderOrPlainButtonStyle: ButtonStyle {
    let binder: Bool
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        if binder {
            BinderPlaque(square: false, on: on, pressed: configuration.isPressed) { configuration.label }
        } else {
            configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
        }
    }
}
