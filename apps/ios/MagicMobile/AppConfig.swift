import Foundation

/// What the server can change without a build (mm_app_config; docs/SERVER_CONTROLS.md): a news banner for the main menu,
/// card-name fixes for deck imports, and switches for newer features. The phone keeps the last copy, so it applies offline
/// too. Android's AppConfig and the web's appConfig.ts read the same reply.
struct AppConfig: Equatable, Sendable {
    struct Notice: Equatable, Sendable {
        let id: String
        let text: String
    }

    static let maxNameFixes = 500

    var notice: Notice?
    /// The name a deck site sends → the app's card name (used only when that card is in the catalogue).
    var nameFixes: [String: String] = [:]
    var switches: [String: Bool] = [:]

    /// A switch the server hasn't named is on, unless the feature says otherwise (voiceChat).
    func isOn(_ name: String, default fallback: Bool = true) -> Bool { switches[name] ?? fallback }

    /// mm_app_config's reply; nil when it isn't one.
    static func parse(_ data: Data) -> AppConfig? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var config = AppConfig()
        if let notice = root["notice"] as? [String: Any], let id = notice["id"] as? String, let text = notice["text"] as? String,
           !id.isEmpty, !text.isEmpty {
            config.notice = Notice(id: String(id.prefix(80)), text: String(text.prefix(280)))
        }
        if let fixes = root["nameFixes"] as? [String: Any] {
            for (from, to) in fixes.prefix(maxNameFixes) {
                if let to = to as? String, !from.isEmpty, !to.isEmpty, from.count <= 200, to.count <= 200 { config.nameFixes[from] = to }
            }
        }
        if let switches = root["switches"] as? [String: Any] {
            for (name, value) in switches { if let on = value as? Bool { config.switches[name] = on } }
        }
        return config
    }
}

/// The phone's copy of the server's settings (UserDefaults), readable from any thread.
final class AppConfigStore: @unchecked Sendable {
    static let shared = AppConfigStore()
    static let didChange = Notification.Name("MagicMobile.AppConfig.didChange")
    static let defaultsKey = "magicmobile.appConfig"
    /// The notice the player closed, by id: it doesn't come back.
    static let dismissedNoticeKey = "magicmobile.appConfig.dismissedNotice"

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var value: AppConfig

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = defaults.data(forKey: Self.defaultsKey).flatMap(AppConfig.parse) ?? AppConfig()
    }

    var current: AppConfig { lock.withLock { value } }

    /// Keeps a reply from the server; anything else is ignored and the last copy stays.
    func store(_ data: Data) {
        guard let parsed = AppConfig.parse(data) else { return }
        let changed = lock.withLock { () -> Bool in
            defer { value = parsed }
            return value != parsed
        }
        defaults.set(data, forKey: Self.defaultsKey)
        if changed { NotificationCenter.default.post(name: Self.didChange, object: nil) }
    }

    /// The notice to show on the main menu, unless the player closed it.
    var shownNotice: AppConfig.Notice? {
        guard let notice = current.notice, defaults.string(forKey: Self.dismissedNoticeKey) != notice.id else { return nil }
        return notice
    }

    func dismissNotice(_ notice: AppConfig.Notice) {
        defaults.set(notice.id, forKey: Self.dismissedNoticeKey)
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }
}
