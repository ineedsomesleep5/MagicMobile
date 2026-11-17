import Foundation

/// A note a player sends from Send feedback (mm_send_feedback). The message and an optional contact,
/// nothing else they saved: the payload keys are fixed, and a deck list is not one of them.
/// parity/feedback-cases.json checks this against Android and the web.
enum FeedbackDraft {
    static let maxMessage = 4000
    static let maxContact = 120
    static let maxVersion = 40
    static let maxDevice = 80

    struct Contact: Equatable {
        var value: String?
        var ok: Bool
    }

    /// What the player reads after a send, including the offline and success lines the screen shows.
    static func notice(for code: String) -> String {
        switch code {
        case "sent": return String(localized: "Thanks. Your note was sent.")
        case "offline": return String(localized: "You're offline, so this note stayed here. Try again when you're back online.")
        case "invalid_feedback": return String(localized: "Write a note first, up to 4,000 characters.")
        case "invalid_contact": return String(localized: "Keep an email or handle to 120 characters.")
        case "too_many_feedback": return String(localized: "You've sent a few notes already. Try again in a little while.")
        case "not_signed_in": return String(localized: "This app isn't signed in yet. Open it online and try again.")
        case "feature_unavailable": return String(localized: "Feedback isn't on the server yet. Try again after the next update.")
        default: return String(localized: "This note couldn't be sent. Try again.")
        }
    }

    static func chars(_ text: String) -> Int { text.unicodeScalars.count }

    /// The field as the player types it: controls dropped (a line break stays in the note), then the cap.
    static func cleanMessage(_ raw: String) -> String { clip(keeping(raw, newlines: true), maxMessage) }

    static func cleanContact(_ raw: String) -> String { clip(keeping(raw, newlines: false), maxContact) }

    /// Trimmed note, or nil when it is blank, too long, or still has a control character.
    static func message(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, chars(trimmed) <= maxMessage, !forbidden(trimmed, newlines: true) else { return nil }
        return trimmed
    }

    /// Blank contact is left out. A contact that is too long or has a control character is refused.
    static func contact(_ raw: String) -> Contact {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return Contact(value: nil, ok: true) }
        guard chars(trimmed) <= maxContact, !forbidden(trimmed, newlines: false) else { return Contact(value: nil, ok: false) }
        return Contact(value: trimmed, ok: true)
    }

    /// The RPC body, or nil when it should not be sent. Version, build and device are clipped to the server's caps.
    static func params(kind: String, message rawMessage: String, contact rawContact: String, platform: String, version: String, build: String, device: String) -> [String: Any]? {
        guard kind == "bug" || kind == "feature", platform == "ios" || platform == "android" || platform == "web" else { return nil }
        guard let body = message(rawMessage) else { return nil }
        let who = contact(rawContact)
        guard who.ok, let appVersion = meta(version, maxVersion), let appBuild = meta(build, maxVersion), let model = meta(device, maxDevice) else { return nil }
        return [
            "p_kind": kind, "p_message": body, "p_contact": who.value ?? NSNull(), "p_platform": platform,
            "p_app_version": appVersion, "p_build": appBuild, "p_device": model,
        ]
    }

    private static func meta(_ raw: String, _ max: Int) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !forbidden(trimmed, newlines: false) else { return nil }
        let clipped = clip(trimmed, max)
        return clipped.isEmpty ? nil : clipped
    }

    private static func clip(_ text: String, _ max: Int) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars.prefix(max) { scalars.append(scalar) }
        return String(scalars)
    }

    private static func keeping(_ raw: String, newlines: Bool) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars where allowed(scalar, newlines: newlines) {
            scalars.append(scalar)
        }
        return String(scalars)
    }

    private static func allowed(_ scalar: Unicode.Scalar, newlines: Bool) -> Bool {
        let value = scalar.value
        if value == 10 || value == 9 { return newlines }
        return value >= 32 && value != 127
    }

    private static func forbidden(_ text: String, newlines: Bool) -> Bool {
        text.unicodeScalars.contains { !allowed($0, newlines: newlines) }
    }
}
