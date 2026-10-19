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
                    Label("Message your friends from Friends, or from the game menu in the middle of a game. A banner shows a new message.", systemImage: "bubble.left.and.bubble.right.fill")
                    Label("Repeat a combo: do the same thing three times in a turn and the game offers to repeat it, as many times as you pick, until you can't, or until they lose. It waits for your triggers and keeps choosing the same kind of target.", systemImage: "arrow.triangle.2.circlepath")
                    Label("Ranked opens the Ranked Hall, with a live leaderboard of this season's players and who's online.", systemImage: "trophy.fill")
                    Label("Spread-out token piles stack back up with the Stack chip.", systemImage: "square.stack.fill")
                    Label("Keep your profile: sign in with Apple or Google on the Profile screen, and your name, friends and rank follow you to any phone.", systemImage: "person.crop.circle.badge.checkmark")
                    Label("Choose the artwork for any card in Deck Studio. Your pick shows in games and offline, survives export and import, and online images match it.", systemImage: "paintpalette.fill")
                    Label("The offline download now includes every token and emblem.", systemImage: "arrow.down.to.line.circle.fill")
                    Label("The stack is a stack of parchment slips: what resolves next, whose it is, its targets, and Resolve all.", systemImage: "square.stack.3d.up.fill")
                    Label("Don't ask again: tick it on a card's \"you may\" question and the game answers it for you for the rest of the game. Change your mind in the game menu.", systemImage: "checkmark.square.fill")
                    Label("Resolve all: one tap lets a pile of triggers on the stack resolve, and it stops if an opponent responds.", systemImage: "forward.fill")
                    Label("Your spells resolve without an extra tap. Turn off Pass After Casting in Settings to hold priority.", systemImage: "bolt.fill")
                    Label("Pick any number of cards at once with Select all, and remember which of your triggers goes first.", systemImage: "rectangle.stack.fill")
                    Label("The AI waits less while your triggers resolve, and XMage is updated with 78 new cards and many card fixes.", systemImage: "sparkles")
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
                Section {
                    Link(destination: SupportProject.url) {
                        Label(SupportProject.action, systemImage: "heart.fill")
                    }
                    .accessibilityIdentifier("updates.support")
                } header: {
                    Text("Support MagicMobile")
                } footer: {
                    Text(SupportProject.note)
                }
            }
            .tavernList()
            .navigationTitle("Updates")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .preferredColorScheme(.dark)
    }
}

/// The tip jar. Every support link opens the download site's support page in the browser (never an
/// in-app purchase or a payment page). That page (apps/site/public/support) holds the donation link,
/// so changing the provider never needs an app update.
enum SupportProject {
    static let url = URL(string: "https://magicmobile-downloads.vercel.app/support/")!
    static let dismissedKey = "magicmobile.supportBanner.dismissed"
    static let pitch = "Enjoying MagicMobile? Help cover server costs."
    static let action = "Help cover server costs"
    static let note = "MagicMobile is free with no ads. Tips help pay for the servers and open in your browser. Unofficial fan app, not affiliated with Wizards of the Coast."
}

/// A small strip at the foot of the main menu. Its x hides it for good; Settings and Updates keep the link.
struct SupportBanner: View {
    @AppStorage(SupportProject.dismissedKey) private var dismissed = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        if !dismissed {
            HStack(spacing: 0) {
                Button { openURL(SupportProject.url) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "heart.fill").foregroundStyle(TavernPalette.ember)
                        Text(SupportProject.pitch).lineLimit(1).minimumScaleFactor(0.7)
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .heavy))
                    }
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(TavernPalette.parchment.opacity(0.85))
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menu.support")
                Button { dismissed = true } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TavernPalette.parchment.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide support banner")
                .accessibilityIdentifier("menu.support.dismiss")
            }
            .padding(.leading, 14)
            .background(Capsule().fill(Color.black.opacity(0.35)))
            .overlay(Capsule().strokeBorder(TavernPalette.brass.opacity(0.35), lineWidth: 1))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
}

/// The always-on support panel at the foot of Settings.
struct SupportSettingsPanel: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TavernPanelTitle(text: "Support MagicMobile")
            Text(SupportProject.note)
                .font(.system(size: 12, design: .serif))
                .foregroundStyle(TavernPalette.parchment.opacity(0.65))
                .fixedSize(horizontal: false, vertical: true)
            Button { openURL(SupportProject.url) } label: {
                Label(SupportProject.action, systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
            .accessibilityIdentifier("settings.support")
        }
        .modifier(TavernSettingsPanel())
    }
}
