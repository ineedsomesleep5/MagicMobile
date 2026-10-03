import Foundation

/// One page of a "How to play" tutorial: a title, one to three short sentences and an animated
/// tavern scene chosen by `id` (HowToPlayView.swift).
struct HowToPlayPage: Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
}

/// One tutorial: a short one on how MagicMobile's table works, and a longer one on the rules of
/// Commander (Caleb, 2026-10-03). Both use the tavern's own pieces for their scenes.
struct HowToPlayTutorial: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let pages: [HowToPlayPage]
}

/// The tutorials' words: one source on iOS. Android's HowToPlayText (core,
/// io.magicmobile.android.game) holds the same strings, and both platforms' parity tests read
/// them from apps/android/core/src/test/resources/parity/tutorial-cases.json.
enum HowToPlayText {
    static let title = "How to play"
    static let back = "Back"
    static let next = "Next"
    static let skip = "Skip"
    static let done = "Done"
    /// The chooser's button on each tutorial.
    static let begin = "Begin"

    /// The progress indicator's spoken value, e.g. "Page 3 of 12".
    static func progress(page: Int, of count: Int) -> String { "Page \(page) of \(count)" }

    /// The walkthrough that opens by itself on the first visit: how the table works.
    static var pages: [HowToPlayPage] { tutorials[0].pages }

    static let tutorials: [HowToPlayTutorial] = [
        HowToPlayTutorial(id: "table", title: "How MagicMobile works", subtitle: "Twelve short pages on the table and its controls.", pages: [
            HowToPlayPage(id: "welcome", title: "Welcome to the tavern",
                          body: "Play Commander against AI opponents or your friends, right on your phone. The XMage rules engine runs on this device and handles every rule for you."),
            HowToPlayPage(id: "decks", title: "Choose your deck",
                          body: "Tap Decks to open Deck Studio. Paste, link or scan a deck list, or tap Create deck to build your own. Tap Play this deck to check it against the Commander rules; your pick then shows the Playing badge."),
            HowToPlayPage(id: "start", title: "Start a game",
                          body: "Tap Play Commander, then pick your deck, one to three AI opponents and their skill. Under Who goes first?, choose the starting player or roll a D20: the highest roll starts. Then keep your opening hand or take a mulligan."),
            HowToPlayPage(id: "board", title: "Know the table",
                          body: "Your hand rests along the bottom, with your battlefield on the mat above it. Opponents sit across the table: tap a medallion for that player's zones, counters, poison and commander damage, and swap between opponents. The plate at the top right shows the turn and the current step."),
            HowToPlayPage(id: "casting", title: "Cast a spell",
                          body: "Drag a card from your hand up onto the mat to play it. When a spell needs mana, the Pay cost tray shows what's left, so tap your lands to pay. The spell rises to the centre of the table while it waits on the stack."),
            HowToPlayPage(id: "glow", title: "Follow the glow",
                          body: "A green glow means a card can be played or chosen; a red glow marks something you can target, even when it's tapped. Tapped permanents turn grey until they untap. Your commander's medallion glows whenever you can cast it."),
            HowToPlayPage(id: "priority", title: "Pass with the hourglass",
                          body: "When you're done, tap the hourglass to pass priority and let this step continue. With a spell on the stack, respond with an instant or ability, or pass to let it resolve. Skip ends your turn or jumps to your next one, and still stops when a choice needs you."),
            HowToPlayPage(id: "combat", title: "Attack and block",
                          body: "To attack, tap each creature you want to send, then the player to attack if there's a choice, and tap Done Attacking. To block, tap your creature, then the attacker it blocks, and tap Done Blocking. Back lets you change your mind before you confirm."),
            HowToPlayPage(id: "piles", title: "Big boards",
                          body: "Once you have eight or more identical tokens, they stack into one pile with a count. Tap the pile to pick the next token, or hold it to spread them out."),
            HowToPlayPage(id: "reading", title: "Read a card",
                          body: "Press and hold any card to see it up close with its full rules text. Open the game log to look back at every play."),
            HowToPlayPage(id: "resume", title: "Leave and come back",
                          body: "Games against the AI are saved when you leave the app. Come back within 10 minutes and tap Resume to pick up at your last decision. Quitting from the game menu ends the game for good."),
            HowToPlayPage(id: "friends", title: "Play with friends",
                          body: "In game setup, choose Online to host a table and share its code, or join a friend's table with their code. Online works between iPhone and Android. On iPhone, Game Center can find players too.")
        ]),
        HowToPlayTutorial(id: "commander", title: "Commander basics", subtitle: "Nine pages on the rules of the format.", pages: [
            HowToPlayPage(id: "format", title: "The format",
                          body: "Commander is Magic for a table of friends: usually three or four players, each with a 100-card deck led by a legendary creature. Every card but basic lands is a single copy, and everyone starts at 40 life."),
            HowToPlayPage(id: "commander", title: "Your commander",
                          body: "Your commander starts in the command zone, and you can cast it from there whenever you could cast a creature. If it would leave the battlefield, you may send it back to the command zone instead. Each time you cast it again, it costs two more mana: the commander tax."),
            HowToPlayPage(id: "colors", title: "Colour identity",
                          body: "Your commander's colours decide your deck. Every card may only use mana symbols that appear on your commander, in its cost or its rules text. A colourless commander means a deck of colourless cards."),
            HowToPlayPage(id: "turn", title: "A turn",
                          body: "Each turn untaps your permanents, then you draw a card. In your main phases you may play one land and cast your spells, and combat comes between them. Then the turn passes to the player on your left."),
            HowToPlayPage(id: "mana", title: "Mana and costs",
                          body: "Lands tap for mana, shown as gems on the rail, and a card's cost sits in its corner. Creatures, sorceries and other permanents are cast in your main phase with nothing on the stack. Instants and abilities can be used whenever you have priority, even on another player's turn."),
            HowToPlayPage(id: "stack", title: "The stack",
                          body: "Spells and abilities don't happen at once: they wait on the stack, and everyone may respond. The last thing added resolves first. When every player passes in a row, the top of the stack resolves."),
            HowToPlayPage(id: "combat", title: "Combat",
                          body: "Attacking creatures tap, and each one attacks a player or a planeswalker. The defender chooses blockers, and an unblocked creature deals its damage to the player. Flying creatures can only be blocked by flying or reach, and trample pushes extra damage through a blocker."),
            HowToPlayPage(id: "permanents", title: "Permanents",
                          body: "Creatures, artifacts, enchantments, planeswalkers and lands stay on the battlefield. A creature can't attack or tap for an ability on the turn it arrives unless it has haste. Hold any card to read its keywords and rules in full."),
            HowToPlayPage(id: "winning", title: "Winning",
                          body: "A player loses at 0 life, with 10 poison counters, or when they must draw from an empty library. Taking 21 combat damage from one commander over the game loses too. The last player at the table wins.")
        ])
    ]
}

/// When the walkthrough opens by itself: once, on the first visit to the main menu after the
/// update that added it (or a later content version). UI tests, design previews, SwiftUI
/// previews and hosted unit tests never see it unless a test asks with `firstLaunchArgument`.
/// Android's HowToPlayLaunch applies the same rule to the same stored key.
enum HowToPlayLaunch {
    /// The walkthrough version the player has closed; 0 before the first time.
    static let seenVersionKey = "magicmobile.howToPlay.seenVersion"
    /// Raise to show a substantially rewritten walkthrough once more.
    static let contentVersion = 2
    /// Lets a UI test see the automatic first-launch walkthrough.
    static let firstLaunchArgument = "--how-to-play-first-launch"

    static func shouldShowAutomatically(seenVersion: Int, automated: Bool, forced: Bool) -> Bool {
        (!automated || forced) && seenVersion < contentVersion
    }

    static func isAutomated(arguments: [String], environment: [String: String]) -> Bool {
        arguments.contains("--ondevice-setup-ui-test")
            || environment["MAGICMOBILE_DESIGN_PREVIEW"] != nil
            || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            || environment["XCTestConfigurationFilePath"] != nil
    }

    static func isForced(arguments: [String]) -> Bool { arguments.contains(firstLaunchArgument) }

    /// The whole decision for this preference store and process.
    static func shouldShowAutomatically(defaults: UserDefaults,
                                        arguments: [String] = ProcessInfo.processInfo.arguments,
                                        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        shouldShowAutomatically(seenVersion: defaults.integer(forKey: seenVersionKey),
                                automated: isAutomated(arguments: arguments, environment: environment),
                                forced: isForced(arguments: arguments))
    }

    /// Closing the walkthrough (Done, Skip or a swipe down) counts as seen.
    static func markSeen(in defaults: UserDefaults) {
        if defaults.integer(forKey: seenVersionKey) < contentVersion { defaults.set(contentVersion, forKey: seenVersionKey) }
    }
}

/// The one-time offer, after the walkthrough, to save card art for offline play.
enum OfflineArtLaunch {
    static let seenKey = "magicmobile.offlineArtPrompt.seen"

    static func shouldShowAutomatically(defaults: UserDefaults,
                                        arguments: [String] = ProcessInfo.processInfo.arguments,
                                        environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        !HowToPlayLaunch.isAutomated(arguments: arguments, environment: environment)
            && defaults.integer(forKey: HowToPlayLaunch.seenVersionKey) >= HowToPlayLaunch.contentVersion
            && !defaults.bool(forKey: seenKey)
    }

    static func markSeen(in defaults: UserDefaults) { defaults.set(true, forKey: seenKey) }
}
