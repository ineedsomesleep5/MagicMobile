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
                    Label("Friends: see who's online and join their table in one tap.", systemImage: "person.2.fill")
                    Label("Table chat with quick messages, plus mute, block and report.", systemImage: "bubble.left.and.bubble.right.fill")
                    Label("Invite links that open straight into your table.", systemImage: "link")
                    Label("Online games: one starting roll, and your opponent's commander on the versus screen.", systemImage: "checkmark.circle")
                    Label("Scryfall card art on by default, with an offer to save it for offline play.", systemImage: "photo.on.rectangle")
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
                Section {
                    LabeledContent("Card images", value: "Scryfall")
                    Link(destination: URL(string: "https://magicmobile-downloads.vercel.app/privacy/")!) {
                        Label("Privacy", systemImage: "hand.raised")
                    }
                    .accessibilityIdentifier("updates.privacy")
                } header: {
                    Text("About")
                } footer: {
                    // Same notice as the download site's footer.
                    Text("Independent fan project. Not affiliated with Wizards of the Coast. Magic: The Gathering and card artwork belong to their respective owners.")
                        .accessibilityIdentifier("updates.fanContentNotice")
                }
            }
            .tint(CommanderPresentation.accent)
            .navigationTitle("Updates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
