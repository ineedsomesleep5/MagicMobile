import SwiftUI

struct DeckStudioOrganizationButton: View {
    let recordID: String?
    let title: String
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            Image(systemName: "tag").frame(width: 44, height: 44)
        }
        .disabled(recordID == nil)
        .accessibilityLabel("Deck tags, notes and import receipt")
        .accessibilityHint(recordID == nil ? "Save the draft once to add deck details" : "Open local deck details")
        .sheet(isPresented: $presented) {
            if let recordID { DeckStudioOrganizationSheet(recordID: recordID, title: title) }
        }
    }
}

private struct DeckStudioOrganizationSheet: View {
    let recordID: String
    let title: String
    @Environment(\.dismiss) private var dismiss
    @State private var history: DeckStudioEditHistory<DeckStudioOrganization>?
    @State private var revision = 0
    @State private var newTag = ""
    @State private var error: String?
    @State private var busy = false
    @State private var discardConfirmation = false
    private var isDirty: Bool { history?.isDirty ?? false }
    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(DeckStudioPalette.danger) } }
                if let history {
                    Section {
                        HStack {
                            TextField("Add a tag", text: $newTag).autocorrectionDisabled()
                            Button("Add") { addTag() }.disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        }
                        ForEach(history.value.tags, id: \.self) { tag in
                            HStack {
                                Text(tag)
                                Spacer()
                                Button(role: .destructive) { edit { $0.tags.removeAll { $0 == tag } } } label: {
                                    Image(systemName: "minus.circle").frame(width: 44, height: 44)
                                }.accessibilityLabel("Remove tag \(tag)")
                            }
                        }
                    } header: { Text("Tags") } footer: { Text("Tags are searchable in My Decks. Up to 24 tags; they never change card sections or Commander legality.") }
                    Section {
                        TextEditor(text: Binding(get: { self.history?.value.notes ?? "" }, set: { text in edit { $0.notes = text } }))
                            .frame(minHeight: 180).accessibilityLabel("Private deck-building notes")
                    } header: { Text("Building notes") } footer: { Text("Stored on this device, excluded from backups. Nothing is sent to Scryfall, EDHREC or Commander Spellbook.") }
                    Section {
                        HStack {
                            Button("Undo", systemImage: "arrow.uturn.backward") { self.history?.undo() }.disabled(!history.canUndo || busy)
                            Spacer()
                            Button("Redo", systemImage: "arrow.uturn.forward") { self.history?.redo() }.disabled(!history.canRedo || busy)
                        }
                        Text(isDirty ? "Unsaved details" : "Saved details").font(.caption).foregroundStyle(DeckStudioPalette.secondaryInk)
                    }
                    if !history.value.importAnnotations.isEmpty || history.value.importedFrom != nil || history.value.importReceiptFile != nil {
                        Section {
                            if let source = history.value.importedFrom { Text(source).font(.caption).textSelection(.enabled) }
                            DisclosureGroup("Original import annotations (\(history.value.importAnnotationCount ?? history.value.importAnnotations.count))") {
                                ForEach(Array(history.value.importAnnotations.enumerated()), id: \.offset) { _, line in
                                    Text(line).font(.caption).textSelection(.enabled)
                                }
                                if history.value.importAnnotations.isEmpty, (history.value.importAnnotationCount ?? 0) > 0 {
                                    Text("This large annotation list is preserved in the full original receipt below.").font(.caption)
                                }
                            }
                            if let url = history.value.receiptURL {
                                if FileManager.default.fileExists(atPath: url.path) {
                                    ShareLink(item: url) { Label("Export full original import receipt", systemImage: "doc.text") }
                                } else {
                                    Text("The original receipt file is unavailable on this device; any inline annotations above are still retained.").font(.caption).foregroundStyle(DeckStudioPalette.warning)
                                }
                            }
                        } header: { Text("Import receipt") } footer: { Text("These describe the original import. They are preserved as reference, not kept in sync with later card edits or interpreted as card legality.") }
                    }
                    if let json = export(history.value) {
                        ShareLink(item: json) { Label("Export these details", systemImage: "square.and.arrow.up") }
                    }
                } else if busy { ProgressView("Loading local details…") }
            }
            .disabled(busy)
            .scrollContentBackground(.hidden).background(DeckStudioPalette.background)
            .navigationTitle(title.isEmpty ? "Deck details" : title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { if isDirty { discardConfirmation = true } else { dismiss() } }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(history == nil || busy) }
            }
            .task { await load() }
            .interactiveDismissDisabled(isDirty || busy)
            .confirmationDialog("Discard unsaved deck details?", isPresented: $discardConfirmation, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) { dismiss() }
            } message: { Text("Previously saved notes, tags, import receipts and deck cards are unchanged.") }
        }.foregroundStyle(DeckStudioPalette.ink).tint(DeckStudioPalette.ink).preferredColorScheme(.light)
    }
    private func edit(_ mutate: (inout DeckStudioOrganization) -> Void) {
        guard !busy, var history else { return }
        do {
            try history.edit { value in mutate(&value); value = try value.validated() }
            self.history = history; error = nil
        } catch { self.error = error.localizedDescription }
    }
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        edit { $0.tags.append(trimmed) }
        if error == nil { newTag = "" }
    }
    private func load() async {
        guard history == nil, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let loaded = try await DeckStudioOrganizationStore.shared.load(recordID: recordID)
            try Task.checkCancellation()
            history = DeckStudioEditHistory(loaded.value); revision = loaded.revision; error = nil
        } catch is CancellationError { } catch { self.error = error.localizedDescription }
    }
    private func save() async {
        guard let history, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let saved = try await DeckStudioOrganizationStore.shared.save(history.value, recordID: recordID, expectedRevision: revision)
            self.history = DeckStudioEditHistory(saved.value); revision = saved.revision; error = nil
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
    private func export(_ value: DeckStudioOrganization) -> String? {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
