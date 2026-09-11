import SwiftUI
import UniformTypeIdentifiers
import MagicMobileOnDevice

struct EngineLabView: View {
    @Bindable var model: EngineLabModel
    @State private var importing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("On-device engine lab").font(.largeTitle.bold())
                    Text("REAL XMAGE • NO REMOTE FALLBACK").font(.caption.monospaced())
                    Text(model.status)
                    if let error = model.error {
                        Label(error, systemImage: "exclamationmark.triangle").font(.callout)
                    }
                    HStack {
                        Button("Import match JSON") { importing = true }.buttonStyle(.bordered)
                        Button("Start local match") { Task { await model.start() } }
                            .buttonStyle(.borderedProminent).disabled(!model.canStart)
                    }
                    if let capabilities = model.capabilities {
                        DisclosureGroup("Engine build information") { JSONInspector(value: capabilities) }
                    }
                    if model.matchID != nil {
                        Text("Development-only: the host can inspect each seat below. Remove this selector from the consumer client.")
                            .font(.footnote)
                        Picker("Inspected seat", selection: Binding(get: { model.selectedSeat }, set: { model.chooseSeat($0) })) {
                            ForEach(model.seats, id: \.self) { Text($0).tag($0) }
                        }.pickerStyle(.segmented)
                        if let poll = model.poll {
                            Text("\(poll.phase.capitalized) • Revision \(poll.revision)").font(.caption.monospaced())
                            if let prompt = poll.prompt {
                                PromptInspector(prompt: prompt, disabled: model.isWorking || !model.isForeground, enginePlayerID: poll.snapshot?["enginePlayerId"]?.string) { kind, value in
                                    Task { await model.answer(kind, value: value, prompt: prompt) }
                                }.id(prompt.id)
                            } else { Text("Waiting for the engine or another player’s choice…") }
                            if let snapshot = poll.snapshot {
                                DisclosureGroup("Viewer-scoped game state") { JSONInspector(value: snapshot) }
                            }
                            if let failure = poll.raw["failure"], failure != .null { JSONInspector(value: failure) }
                        }
                        Button("Discard match", role: .destructive) { Task { await model.discard() } }
                            .disabled(model.isWorking)
                    }
                    Divider()
                    Text("This harness tests the embedded engine boundary. It is not the final battlefield UI, and Game Center matchmaking is not wired into this screen.")
                        .font(.footnote)
                }.padding(24)
            }.navigationTitle("MagicMobile")
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { model.importConfiguration(from: url) }
        }
    }
}
struct JSONInspector: View {
    let value: JSONValue
    var body: some View {
        Text((try? String(decoding: value.encoded(), as: UTF8.self)) ?? "Invalid JSON")
            .font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }
}
