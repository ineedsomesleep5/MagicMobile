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
                    Label("Edge-to-edge menus and cleaner deck covers.", systemImage: "rectangle.stack")
                    Label("Compact card rows and clearer combo steps.", systemImage: "list.number")
                    Label("Six battlefield backgrounds for both orientations.", systemImage: "photo.on.rectangle")
                    Label("Quieter error notices that dismiss automatically.", systemImage: "bell")
                    Label("Offline artwork with three quality options.", systemImage: "externaldrive")
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
