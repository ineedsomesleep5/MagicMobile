import Foundation

/// One page of the "How to play" walkthrough: a title, one to three short sentences and a
/// drawn illustration chosen by `id` (HowToPlayView.swift).
struct HowToPlayPage: Equatable, Identifiable {
    let id: String
    let title: String
    let body: String
}

/// The walkthrough's words: one source on iOS. Android's HowToPlayText (core,
/// io.magicmobile.android.game) holds the same strings, and both platforms' parity tests read
/// them from apps/android/core/src/test/resources/parity/tutorial-cases.json.
enum HowToPlayText {
    static let title = "How to play"
    static let back = "Back"
    static let next = "Next"
    static let skip = "Skip"
    static let done = "Done"

    /// The progress indicator's spoken value, e.g. "Page 3 of 10".
    static func progress(page: Int, of count: Int) -> String { "Page \(page) of \(count)" }

    static let pages: [HowToPlayPage] = [
        HowToPlayPage(id: "welcome", title: "Welcome to MagicMobile",
                      body: "Play Commander against AI opponents right on your phone. The XMage rules engine runs on this device and handles the rules for you."),
        HowToPlayPage(id: "decks", title: "Choose your deck",
                      body: "Tap Decks to open Deck Studio. Paste, link or scan a deck list, or tap Create deck to build your own. Tap Play this deck to check it against the Commander rules; your pick then shows the Playing badge."),
        HowToPlayPage(id: "start", title: "Start a game",
                      body: "Tap Play Commander, then pick your deck, one to three AI opponents and their skill. Under Who goes first?, choose the starting player or roll a D20: the highest roll starts. Then keep your opening hand or take a mulligan."),
        HowToPlayPage(id: "board", title: "Know the board",
                      body: "Your hand runs along the bottom, with your battlefield above it. Opponents and their life totals sit at the top; with more than one, tap the people button to watch another. The turn bar shows whose turn it is and the current step."),
        HowToPlayPage(id: "casting", title: "Play your cards",
                      body: "Drag a card from your hand up onto the battlefield to play it. When a spell needs mana, the Pay cost tray shows what's left, so tap your lands to pay. If it needs a target, tap a highlighted card or player."),
        HowToPlayPage(id: "priority", title: "Pass priority",
                      body: "When you're done, tap Pass Priority to let this step continue. With a spell on the stack, respond with an instant or ability, or pass to let it resolve. Skip ends your turn or jumps to your next one, and still stops when a choice needs you."),
        HowToPlayPage(id: "combat", title: "Attack and block",
                      body: "To attack, tap each creature you want to send, then the player to attack if there's a choice. Tap Done Attacking when you're ready. To block, tap your creature, then the attacker it blocks, and tap Done Blocking."),
        HowToPlayPage(id: "reading", title: "Read the cards",
                      body: "Press and hold any card to see it up close with its full rules text. Open the game log to look back at every play."),
        HowToPlayPage(id: "resume", title: "Leave and come back",
                      body: "Games against the AI are saved when you leave the app. Come back within 10 minutes and tap Resume to pick up at your last decision. Quitting from the game menu ends the game for good."),
        HowToPlayPage(id: "friends", title: "Play with friends",
                      body: "In game setup, choose Online to host a table and share its code, or join a friend's table with their code. Online works between iPhone and Android. On iPhone, Game Center can find players too.")
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
    static let contentVersion = 1
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
