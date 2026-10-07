import Foundation

/// Sends this phone's finished games to the profile server (mm_record_game), so other players can see them on
/// the profile. The phone's own record is the source of truth: a game counts as sent once the server confirmed
/// it, and any recent game that is not yet confirmed is tried again whenever the app is open and online. That
/// covers going offline mid-session, a server that does not record games yet (the migration comes separately) and
/// the games played before there was a profile name. Sending never blocks play and never throws.
@MainActor
final class GameUploader {
    /// The newest games considered each time: older ones stay on the phone.
    static let window = 60
    /// At most this many go in one pass (the server allows 100 an hour).
    static let perPass = 40
    private static let keep = 400

    private let fileURL: URL?
    private var sent: [String]
    private var running = false

    init(directory: URL?) {
        fileURL = directory?.appendingPathComponent("uploaded-games.json")
        sent = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    /// The same place as the profile record: Application Support/Profile for the shipped app, a temporary folder for tests and previews.
    static let shared: GameUploader = {
        let testing = NSClassFromString("XCTestCase") != nil
        let support = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = OnDeviceAppConfiguration.entryPoint == .embedded && !testing
            ? support?.appendingPathComponent("Profile", isDirectory: true)
            : FileManager.default.temporaryDirectory.appendingPathComponent("Profile-Preview-Uploads-\(UUID().uuidString)", isDirectory: true)
        return GameUploader(directory: directory)
    }()

    /// The recent games the server hasn't confirmed, oldest first. `matches` is newest first, like the record.
    func pending(in matches: [MatchRecord]) -> [MatchRecord] {
        let confirmed = Set(sent)
        return matches.prefix(Self.window).filter { !confirmed.contains($0.id.uuidString) }.reversed()
    }

    /// Sends what is pending, oldest first, and stops at the first game that could not be sent for now.
    /// Returns how many the server confirmed. A pass already running makes this one a no-op.
    @discardableResult
    func flush(matches: [MatchRecord], send: (MatchRecord) async -> GameUploadResult) async -> Int {
        guard !running else { return 0 }
        running = true
        defer { running = false }
        var confirmed = 0
        for match in pending(in: matches).prefix(Self.perPass) {
            switch await send(match) {
            case .sent: sent.append(match.id.uuidString); confirmed += 1
            case .rejected: sent.append(match.id.uuidString)
            case .retryLater, .unavailable:
                save()
                return confirmed
            }
        }
        save()
        return confirmed
    }

    private func save() {
        guard let fileURL else { return }
        if sent.count > Self.keep { sent.removeFirst(sent.count - Self.keep) }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(sent).write(to: fileURL, options: .atomic)
        } catch {
            // A failed save only means a few games are sent again; the server stores each once.
        }
    }
}
