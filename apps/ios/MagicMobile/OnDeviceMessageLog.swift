import Foundation
import MagicMobileOnDevice

/// Retains only this authenticated seat's explicit informational events in memory.
/// Not a complete action log, durable game save, or source of hidden card details.
struct OnDeviceMessageLog {
    private var matchID: String?
    private var seatID: String?
    private var processedThrough: Int64 = -1
    private(set) var entries: [GameLogEntry] = []
    private var messageBytes = 0
    private static let retainedMessages = 64
    private static let retainedBytes = 1024 * 1024
    private static let autoPassPrefix = "local:auto-pass:"
    /// The steps or stack items in the current run of automatic passes (one log line per run).
    private var autoPassRun: [String] = []

    /// Validate the entire batch before changing state. Duplicate/older polls do
    /// not duplicate notices, and another match or seat can never reuse this log.
    mutating func ingest(_ poll: MatchPoll) throws {
        guard !poll.matchID.isEmpty, !poll.seatID.isEmpty,
              matchID == nil || matchID == poll.matchID,
              seatID == nil || seatID == poll.seatID else { throw EngineError.unboundPeer }
        guard poll.revision >= processedThrough else { return }
        let events: [MagicMobileOnDevice.JSONValue]
        if let supplied = poll.raw["events"] {
            guard let values = supplied.array, values.count <= 128 else {
                throw EngineError.invalidMessage("Malformed engine event history")
            }
            events = values
        } else { events = [] }
        var next = entries
        var bytes = messageBytes
        var previous: Int64 = -1
        for event in events {
            guard let revision = event["revision"]?.integer, revision >= 0,
                  revision <= poll.revision, revision > previous,
                  let kind = event["kind"]?.string else {
                throw EngineError.invalidMessage("Malformed engine event revision")
            }
            previous = revision
            guard revision > processedThrough, kind == "message" else { continue }
            guard let body = event["body"]?.object else {
                throw EngineError.invalidMessage("Malformed private engine notice")
            }
            // Upstream can emit an empty informational message. Do not invent text.
            if body["message"] == .null { continue }
            guard let message = body["message"]?.string else {
                throw EngineError.invalidMessage("Private engine notice has no text")
            }
            guard !message.isEmpty else { continue }
            next.append(GameLogEntry(id: "xmage:\(poll.matchID):\(poll.seatID):\(revision)",
                                     message: message, createdAt: nil))
            bytes += message.utf8.count
            // Keep the latest message intact, even when it alone exceeds the
            // history budget. The transport already bounds each entire JSON reply.
            while next.count > Self.retainedMessages || (bytes > Self.retainedBytes && next.count > 1) {
                bytes -= next.removeFirst().message.utf8.count
            }
        }
        matchID = poll.matchID; seatID = poll.seatID
        processedThrough = poll.revision; entries = next; messageBytes = bytes
    }

    /// A quiet local line for a pass smart pass made for the player (Caleb, 2026-10-14), so the game never seems to move
    /// on without them. A run of passes shares one line ("Auto-passed: Upkeep · Draw · Main 1"). Never sent to the engine.
    mutating func noteAutoPass(_ label: String, id: String) {
        if let last = entries.last, last.id.hasPrefix(Self.autoPassPrefix) {
            if autoPassRun.last != label { autoPassRun.append(label) }
            messageBytes -= last.message.utf8.count
            entries[entries.count - 1] = GameLogEntry(id: last.id, message: Self.autoPassMessage(autoPassRun), createdAt: nil)
        } else {
            autoPassRun = [label]
            entries.append(GameLogEntry(id: Self.autoPassPrefix + id, message: Self.autoPassMessage(autoPassRun), createdAt: nil))
        }
        messageBytes += entries[entries.count - 1].message.utf8.count
        while entries.count > Self.retainedMessages { messageBytes -= entries.removeFirst().message.utf8.count }
    }

    /// The latest six labels of a run.
    static func autoPassMessage(_ labels: [String]) -> String {
        String(localized: "Auto-passed: \(labels.suffix(6).joined(separator: " · "))")
    }
}
