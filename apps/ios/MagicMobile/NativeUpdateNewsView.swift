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
                    Label("When you can see the top of your library (Conspicuous Snoop, Future Sight, Courser of Kruphix), it sits beside your portrait. Tap it to see it large and cast or play it.", systemImage: "eye.fill")
                    Label("Your portrait glows when you can cast from your graveyard, exile or the top of your library, not only your commander, and the zone menu says which.", systemImage: "sparkles")
                    Label("A small sun or moon shows when it's day or night, the storm count shows under the turn plate, and City's Blessing shows on your medallion.", systemImage: "moon.stars")
                    Label("The starting roll has more table: the header sits at the top and the dice get the room below it.", systemImage: "dice")
                    Label("Pages turn like real paper: drag a page by its edge and it curls under your finger.", systemImage: "hand.draw.fill")
                    Label("The starting roll happens on the tavern table: every player's d20 tumbles across it and lands.", systemImage: "dice")
                    Label("Your profile shows your games at a glance: win rate, favourite commanders, colours and rank history. Your game history lives there now.", systemImage: "chart.bar.fill")
                    Label("Find friends as you type their name, and open any player's profile. Choose whether yours is public, friends only or private.", systemImage: "person.2.fill")
                    Label("Deck Studio's menus and prompts are the binder's own, and held sideways both pages fill the binder with Add cards floating over the page.", systemImage: "list.bullet.rectangle.portrait")
                    Label("Decks is a spell book that opens into a leather card binder: chapters are stitched leather index tabs, and every card sits in a sleeve with a minus and a plus beneath it. Held sideways it lies open as two pages.", systemImage: "book.fill")
                    Label("Switch between your deck and every card you can add, and filter both by mana value with the brass coins.", systemImage: "books.vertical.fill")
                    Label("Easier on your battery: the game rests while it waits for you, and the app is a smaller download.", systemImage: "battery.100")
                    Label("Challenge a friend to a Quick Match, or to Ranked when you're in the same tier. Friend ranked games count.", systemImage: "figure.fencing")
                    Label("A real 3D tavern room behind the menu that shifts as you tilt your phone, with flickering candles.", systemImage: "flame.fill")
                    Label("Your profile picture is your favorite commander's art.", systemImage: "person.crop.circle")
                    Label("The menu fits on one screen, and Downloads matches the tavern.", systemImage: "rectangle.stack.fill")
                    Label("Smoother rank badge turns and lighter menu animations.", systemImage: "sparkles")
                    Label("Ranked: climb from Bronze to Mythic in monthly seasons, against players near your rank or an AI at your tier.", systemImage: "shield.lefthalf.filled")
                    Label("Quick Match: one AI at your deck's bracket, or choose its bracket, deck and skill.", systemImage: "bolt.fill")
                    Label("Every deck shows its Commander bracket, with the Game Changers and combos behind it.", systemImage: "checkmark.seal")
                    Label("Your profile: rank, season history, stats, achievements, titles and match history.", systemImage: "person.crop.circle")
                    Label("21 new included decks from Bracket 1 to 4, for you and for the AI.", systemImage: "rectangle.stack.fill")
                    Label("The Walnut Tavern: a new table, menus and painted card frames, in portrait and landscape.", systemImage: "table.furniture")
                    Label("Every spell is cast with its own moment at the centre of the table; your commander gets the big one.", systemImage: "sparkles")
                    Label("Tap a player's medallion for their counters, poison and commander damage, and swap between opponents.", systemImage: "person.crop.circle")
                    Label("Big boards run smoother: identical tokens stack once there are eight.", systemImage: "square.stack.3d.up")
                    Label("A Back button while declaring attackers and blockers.", systemImage: "arrow.uturn.backward")
                    Label("Friends, table chat and invite links that open straight into your table.", systemImage: "person.2.fill")
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
            .tavernList()
            .navigationTitle("Updates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}
