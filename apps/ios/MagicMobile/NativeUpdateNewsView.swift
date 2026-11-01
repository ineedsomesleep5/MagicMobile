import SwiftUI

/// Bundled release notes remain readable offline. Upstream links never imply installed support.
/// Arena's inbox (the judge, 2026-10-22, against inbox-1.png): a blade on the right over the dimmed menu, one column of
/// messages, each a ◆, its title and its date, the newest tagged New in orange; a tap opens the message in place.
/// The build, XMage news and the links sit in the last message, About & links.
struct NativeUpdateNewsView: View {
    let upstreamCommit: String?
    @State private var expanded: String?

    private static let aboutID = "about"

    var body: some View {
        VStack(spacing: 0) {
            ArenaPanelHeader(title: String(localized: "Inbox"), closeIdentifier: "updates.close")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ArenaCaps(text: String(localized: "What's new"), size: 9.5)
                        .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 6)
                    // Not lazy, so the panel can size itself to the messages.
                    ForEach(Array(UpdateNews.messages.enumerated()), id: \.element.id) { index, message in
                        row(id: message.id, title: message.title, date: message.date, new: index == 0) {
                            ArenaInboxMessage(message: message)
                        }
                    }
                    row(id: Self.aboutID, title: String(localized: "About & links"), date: nil, new: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            installedBuild
                            linkSections
                        }
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .mask(ArenaScrollFade())
        }
        .labelStyle(ArenaNewsLabelStyle())
        .tint(ArenaMenuStyle.gold)
        .preferredColorScheme(.dark)
    }

    /// One message: a ◆ (lit gold while it is the newest), New in orange over its title, its date, and the message itself
    /// opening under it when tapped.
    private func row<Body: View>(id: String, title: String, date: String?, new: Bool, @ViewBuilder content: () -> Body) -> some View {
        let open = expanded == id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                GameAudio.shared.play(open ? .uiBack : .uiOpen)
                withAnimation(.easeOut(duration: 0.22)) { expanded = open ? nil : id }
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    Rectangle()
                        .fill(new ? AnyShapeStyle(ArenaMenuStyle.goldFill) : AnyShapeStyle(Color.clear))
                        .frame(width: 9, height: 9)
                        .overlay(Rectangle().strokeBorder(new ? ArenaMenuStyle.gold : ArenaMenuStyle.text.opacity(0.55), lineWidth: 1.3))
                        .rotationEffect(.degrees(45))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        if new {
                            Text(String(localized: "New")).font(ArenaMenuStyle.font(11, .bold)).foregroundStyle(ArenaMenuStyle.ember)
                        }
                        Text(title).font(ArenaMenuStyle.font(14.5, new || open ? .bold : .semibold))
                            .foregroundStyle(ArenaMenuStyle.text)
                            .fixedSize(horizontal: false, vertical: true)
                        if let date {
                            Text(date).font(ArenaMenuStyle.font(11, .semibold))
                                .foregroundStyle(new ? ArenaMenuStyle.ember : ArenaMenuStyle.dim)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .background(open ? Color.white.opacity(0.06) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(BrandPressStyle())
            .accessibilityAddTraits(open ? [.isSelected] : [])
            .accessibilityHint(open ? String(localized: "Closes the message") : String(localized: "Opens the message"))
            .accessibilityIdentifier("updates.inbox.\(id)")
            if open {
                content()
                    .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 16)
                    .transition(.opacity)
            }
            Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.35)
        }
    }

    private var installedBuild: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ArenaCaps(text: String(localized: "Installed build"))
            Spacer(minLength: 8)
            Text("MagicMobile \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                .font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
        }
    }

    @ViewBuilder private var linkSections: some View {
        ArenaNewsSection(title: String(localized: "XMage news"),
                         footer: String(localized: "Opens GitHub. Upstream changes are not installed automatically. New cards and abilities become available only after a compatible MagicMobile build is tested and released.")) {
            Link(destination: URL(string: "https://github.com/magefree/mage/releases")!) {
                Label("XMage release notes", systemImage: "arrow.up.right")
            }
            Link(destination: URL(string: "https://github.com/magefree/mage/commits/master/")!) {
                Label("Latest upstream changes", systemImage: "arrow.up.right")
            }
        }
        ArenaNewsSection(title: String(localized: "About"),
                         footer: String(localized: "Independent fan project. Not affiliated with Wizards of the Coast. Magic: The Gathering and card artwork belong to their respective owners."),
                         footerIdentifier: "updates.fanContentNotice") {
            Text(String(localized: "Card images from Scryfall"))
            Link(destination: URL(string: "https://magicmobile-downloads.vercel.app/privacy/")!) {
                Label("Privacy", systemImage: "arrow.up.right")
            }
            .accessibilityIdentifier("updates.privacy")
        }
        ArenaNewsSection(title: String(localized: "Support MagicMobile"), footer: SupportProject.note) {
            Link(destination: SupportProject.url) {
                Label(SupportProject.action, systemImage: "arrow.up.right")
            }
            .accessibilityIdentifier("updates.support")
        }
    }
}

/// A message's art crop, the large image so a banner across the blade stays sharp (the judge, 2026-10-22); until it
/// arrives, a plain dark band.
struct UpdateNewsArt: View {
    let name: String
    var colors: [String] = []

    var body: some View {
        GeometryReader { proxy in
            NativeCardArtworkView(name: name, variant: .inspection, contentMode: .fill, artOnly: true) { _, _ in
                ArenaColorGlass(colors: colors)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

/// An open message, under its row: its art as a banner the width of the row, then all it brought.
struct ArenaInboxMessage: View {
    let message: UpdateNewsMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UpdateNewsArt(name: message.art, colors: message.colors)
                .frame(height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
            Text(message.lede).font(ArenaMenuStyle.font(13.5, .medium)).foregroundStyle(ArenaMenuStyle.text.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(message.notes.enumerated()), id: \.offset) { _, note in
                Text(note).font(ArenaMenuStyle.font(13, .medium)).foregroundStyle(ArenaMenuStyle.text.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("updates.message.\(message.id)")
    }
}

/// One release's message in the inbox: a card's art, the title and the day it came, and what it brought.
struct UpdateNewsMessage: Identifiable {
    let id: String
    let title: String
    /// The day in `month` of 2026 the release notes were written.
    let day: Int
    var month = 10
    let art: String
    let colors: [String]
    let lede: String
    let notes: [String]

    var date: String {
        let components = DateComponents(calendar: Calendar(identifier: .gregorian), year: 2026, month: month, day: day)
        return components.date?.formatted(date: .long, time: .omitted) ?? ""
    }
}

/// The releases' notes, newest first, dated by the day they were written (git history of this file).
enum UpdateNews {
    static let messages: [UpdateNewsMessage] = [
        UpdateNewsMessage(id: "trophies-placements", title: String(localized: "Placements and trophies"), day: 1, month: 11,
                          art: "Trophy Mage", colors: ["U"],
                          lede: String(localized: "Every season now starts with five placement matches, and there are twelve new trophies to earn."),
                          notes: [
                            String(localized: "A placement win climbs two divisions and a loss costs nothing. The highest start is Gold II, or Platinum IV if you made Mythic last season."),
                            String(localized: "Games you already played this season count toward your placements."),
                            String(localized: "New trophies wait on your profile, dark until you earn them."),
                          ]),
        UpdateNewsMessage(id: "living-worlds", title: String(localized: "Living worlds"), day: 1, month: 11,
                          art: "Valakut, the Molten Pinnacle", colors: ["R"],
                          lede: String(localized: "Four new tables that move, sound alive and answer the game: Volcano, Utopia, Halloween and Radio Night."),
                          notes: [
                            String(localized: "Every game draws a table at random. To pick one, choose Advanced in Quick Match or set up a Custom Table."),
                            String(localized: "Tap a lit corner of the table and it answers."),
                            String(localized: "World Sounds has its own switch in Options, under Audio."),
                          ]),
        UpdateNewsMessage(id: "own-art", title: String(localized: "Your own card art"), day: 27,
                          art: "Zur the Enchanter", colors: ["W", "U", "B"],
                          lede: String(localized: "Put your own picture on any card in Deck Studio. It becomes the whole card, follows you to every phone and browser you sign in on, and only you see it."),
                          notes: [
                            String(localized: "The art you chose shows from a game's first moment, without the default art swapping in."),
                            String(localized: "Smart Auto-Pass waits on your own trigger when you have an ability that can use it, like Gogo copying Zur's attack trigger."),
                            String(localized: "The starting roll says \"You roll\" when it's your turn to roll."),
                          ]),
        UpdateNewsMessage(id: "arena-menus", title: String(localized: "The menus follow the Arena board"), day: 22,
                          art: "Rhystic Study", colors: ["U"],
                          lede: String(localized: "Every menu now matches the Arena board: Play opens a panel beside your deck boxes, and the boxes open when you choose one."),
                          notes: [
                            String(localized: "Your decks stand in boxes with the commander on the front; the one you choose opens and its commander rises out."),
                            String(localized: "Play is a panel on the right with Find Match, Friends and Recently Played, and a search waits in it with a timer."),
                            String(localized: "Decks, Options, Updates, Downloads and How to Play open as panels over the room."),
                            String(localized: "Held sideways, the deck builder shows the cards to add beside your deck as a list."),
                          ]),
        UpdateNewsMessage(id: "messages", title: String(localized: "Messages and the Ranked Hall"), day: 17,
                          art: "Kynaios and Tiro of Meletis", colors: ["W", "U", "R", "G"],
                          lede: String(localized: "Message your friends from Friends, or from the game menu in the middle of a game. A banner shows a new message."),
                          notes: [
                            String(localized: "Repeat a combo: do the same thing three times in a turn and the game offers to repeat it, as many times as you pick, until you can't, or until they lose. It waits for your triggers and keeps choosing the same kind of target."),
                            String(localized: "Ranked opens the Ranked Hall, with a live leaderboard of this season's players and who's online."),
                            String(localized: "Spread-out token piles stack back up with the Stack chip."),
                          ]),
        UpdateNewsMessage(id: "sign-in", title: String(localized: "Keep your profile"), day: 8,
                          art: "Atraxa, Praetors' Voice", colors: ["W", "U", "B", "G"],
                          lede: String(localized: "Sign in with Apple or Google on the Profile screen, and your name, friends and rank follow you to any phone."),
                          notes: []),
        UpdateNewsMessage(id: "turns", title: String(localized: "Smoother turns"), day: 7,
                          art: "Thousand-Year Storm", colors: ["U", "R"],
                          lede: String(localized: "Your spells resolve without an extra tap. Turn off Pass After Casting in Options to hold priority."),
                          notes: [
                            String(localized: "Don't ask again: tick it on a card's \"you may\" question and the game answers it for you for the rest of the game. Change your mind in the game menu."),
                            String(localized: "Resolve all: one tap lets a pile of triggers on the stack resolve, and it stops if an opponent responds."),
                            String(localized: "Pick any number of cards at once with Select all, and remember which of your triggers goes first."),
                            String(localized: "The AI waits less while your triggers resolve, and XMage is updated with 78 new cards and many card fixes."),
                          ]),
        UpdateNewsMessage(id: "table", title: String(localized: "More on the table"), day: 7,
                          art: "Courser of Kruphix", colors: ["G"],
                          lede: String(localized: "When you can see the top of your library, it sits beside your portrait. Tap it to see it large and cast or play it."),
                          notes: [
                            String(localized: "The stack shows what resolves next, whose it is, its targets, and Resolve all."),
                            String(localized: "Your portrait glows when you can cast from your graveyard, exile or the top of your library, not only your commander, and the zone menu says which."),
                            String(localized: "A small sun or moon shows when it's day or night, the storm count shows under the turn plate, and City's Blessing shows on your medallion."),
                            String(localized: "The starting roll has more table: the header sits at the top and the dice get the room below it."),
                          ]),
        UpdateNewsMessage(id: "art", title: String(localized: "Choose your card art"), day: 7,
                          art: "Krenko, Mob Boss", colors: ["R"],
                          lede: String(localized: "Choose the artwork for any card in Deck Studio. Your pick shows in games and offline, survives export and import, and online images match it."),
                          notes: [String(localized: "The offline download now includes every token and emblem.")]),
        UpdateNewsMessage(id: "profile", title: String(localized: "Your games at a glance"), day: 6,
                          art: "Edgar Markov", colors: ["W", "B", "R"],
                          lede: String(localized: "Your profile shows win rate, favourite commanders, colours and rank history. Your game history lives there now."),
                          notes: [
                            String(localized: "Find friends as you type their name, and open any player's profile. Choose whether yours is public, friends only or private."),
                            String(localized: "The starting roll happens on the table: every player's d20 tumbles across it and lands."),
                          ]),
        UpdateNewsMessage(id: "battery", title: String(localized: "Easier on your battery"), day: 5,
                          art: "Lightning Greaves", colors: [],
                          lede: String(localized: "The game rests while it waits for you, and the app is a smaller download."),
                          notes: []),
        UpdateNewsMessage(id: "ranked", title: String(localized: "Ranked seasons"), day: 4,
                          art: "Elesh Norn, Grand Cenobite", colors: ["W"],
                          lede: String(localized: "Climb from Bronze to Mythic in monthly seasons, against players near your rank or an AI at your tier."),
                          notes: [
                            String(localized: "Quick Match: one AI at your deck's bracket, or choose its bracket, deck and skill."),
                            String(localized: "Challenge a friend to a Quick Match, or to Ranked when you're in the same tier. Friend ranked games count."),
                            String(localized: "Every deck shows its Commander bracket, with the Game Changers and combos behind it."),
                            String(localized: "Your profile: rank, season history, stats, achievements, titles and match history. Your profile picture is your favorite commander's art."),
                            String(localized: "21 new included decks from Bracket 1 to 4, for you and for the AI."),
                            String(localized: "A real 3D tavern room behind the menu that shifts as you tilt your phone, with flickering candles."),
                          ]),
        UpdateNewsMessage(id: "tavern", title: String(localized: "A new table"), day: 3,
                          art: "Prossh, Skyraider of Kher", colors: ["B", "R", "G"],
                          lede: String(localized: "A new table with painted card frames, in portrait and landscape, and every spell cast with its own moment at the centre of it."),
                          notes: [
                            String(localized: "Tap a player's medallion for their counters, poison and commander damage, and swap between opponents."),
                            String(localized: "Big boards run smoother: identical tokens stack once there are eight."),
                            String(localized: "A Back button while declaring attackers and blockers."),
                            String(localized: "Friends, table chat and invite links that open straight into your table."),
                          ]),
    ]
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
                    .font(ArenaMenuStyle.font(13, .semibold))
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

/// The always-on support panel on the Options' Support page.
struct SupportSettingsPanel: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArenaCaps(text: "Support MagicMobile")
            Text(SupportProject.note)
                .font(ArenaMenuStyle.font(12, .medium))
                .foregroundStyle(ArenaMenuStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
            Button { openURL(SupportProject.url) } label: {
                Label(SupportProject.action, systemImage: "heart.fill")
            }
            .buttonStyle(ArenaPillButtonStyle(lit: true))
            .accessibilityIdentifier("settings.support")
        }
        .modifier(TavernSettingsPanel())
    }
}

/// A section of the news panel: gold capitals over its rows on a lighter pane, and a line under it.
struct ArenaNewsSection<Content: View>: View {
    let title: String
    var footer: String? = nil
    var footerIdentifier: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArenaCaps(text: title)
            VStack(alignment: .leading, spacing: 0) {
                Group { content }
                    .font(ArenaMenuStyle.font(14, .medium))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            }
            .padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.55))
            if let footer {
                Text(footer).font(ArenaMenuStyle.font(11.5, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(footerIdentifier ?? "")
            }
        }
    }
}

/// A link in the news panel: the words, and its arrow in gold at the end of the line.
struct ArenaNewsLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.title.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            configuration.icon.font(.system(size: 12, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
        }
        .frame(minHeight: 28)
    }
}
