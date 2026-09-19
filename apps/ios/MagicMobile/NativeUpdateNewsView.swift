import SwiftUI

/// Bundled release notes remain readable offline. Upstream links never imply installed support.
struct NativeUpdateNewsView: View {
    let upstreamCommit: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Installed build") {
                    LabeledContent("MagicMobile", value: "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                    if let upstreamCommit {
                        LabeledContent("XMage revision", value: String(upstreamCommit.prefix(12)))
                            .font(.caption.monospaced())
                    }
                }
                Section("What's new") {
                    Label("A new commander-led menu with charcoal surfaces and clean, borderless controls.", systemImage: "rectangle.stack")
                    Label("A refreshed Deck Studio with larger artwork, clearer tabs and a calm ivory workspace.", systemImage: "square.grid.2x2")
                    Label("See your deck and opponent deck together before starting a game.", systemImage: "person.2")
                    Label("Quick transitions and responsive controls, with Reduce Motion support.", systemImage: "sparkles")
                    Label("Portrait deck tabs pin at the top while the header scrolls away for more card space.", systemImage: "pin")
                    Label("Hold a game card to inspect it; release to return to the table.", systemImage: "hand.point.up")
                    Label("New Downloads menu checks offline artwork, with full-catalogue or deck downloads, tokens, alternate faces and three image-quality choices.", systemImage: "externaldrive")
                }
                Section {
                    Link(destination: URL(string: "https://github.com/magefree/mage/releases")!) {
                        Label("XMage release notes", systemImage: "arrow.up.right.square")
                    }
                    Link(destination: URL(string: "https://github.com/magefree/mage/commits/master/")!) {
                        Label("Latest upstream changes", systemImage: "arrow.up.right.square")
                    }
                } header: {
                    Text("XMage news")
                } footer: {
                    Text("Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.")
                }
            }
            .tint(CommanderPresentation.accent)
            .navigationTitle("Updates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
