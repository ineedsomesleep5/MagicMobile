import SwiftUI

/// Send feedback (Options and About): Bug or Feature idea, the note, an optional contact. The account attaches the
/// build and the phone. Success and failure stay on this page; a failure keeps the note so it can be sent again.
struct FeedbackForm: View {
    var send: (String, String, String) async -> String
    @State private var kind = "bug"
    @State private var message = ""
    @State private var contact = ""
    @State private var sending = false
    @State private var outcome: String?

    private var sent: Bool { outcome == "sent" }
    private var canSend: Bool { !sending && !sent && FeedbackDraft.message(message) != nil && FeedbackDraft.contact(contact).ok }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if sent {
                Text(FeedbackDraft.notice(for: "sent"))
                    .font(ArenaMenuStyle.font(15, .semibold))
                    .foregroundStyle(ArenaMenuStyle.gold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("feedback.status")
                Button(String(localized: "Send another")) { outcome = nil; message = ""; contact = "" }
                    .buttonStyle(ArenaPillButtonStyle())
                    .accessibilityIdentifier("feedback.another")
            } else {
                ArenaSegmented(options: [(String(localized: "Bug"), "bug"), (String(localized: "Feature idea"), "feature")],
                               selection: $kind, identifier: "feedback.kind", stretch: true)
                note
                contactField
                if let outcome, outcome != "sent" {
                    Text(FeedbackDraft.notice(for: outcome))
                        .font(ArenaMenuStyle.font(13, .semibold))
                        .foregroundStyle(ArenaMenuStyle.ember)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("feedback.status")
                }
                Button(sending ? String(localized: "Sending…") : String(localized: "Send")) { submit() }
                    .buttonStyle(ArenaPillButtonStyle(lit: true))
                    .disabled(!canSend)
                    .accessibilityIdentifier("feedback.send")
            }
        }
        .modifier(TavernSettingsPanel())
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                if message.isEmpty {
                    Text(String(localized: "What happened, or what should MagicMobile do?"))
                        .font(ArenaMenuStyle.font(14, .medium))
                        .foregroundStyle(ArenaMenuStyle.dim)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(get: { message }, set: { message = FeedbackDraft.cleanMessage($0); clearError() }))
                    .font(ArenaMenuStyle.font(14, .medium))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .scrollContentBackground(.hidden)
                    .tint(ArenaMenuStyle.gold)
                    .frame(minHeight: 140)
                    .accessibilityLabel(String(localized: "Message"))
                    .accessibilityIdentifier("feedback.message")
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
            Text("\(FeedbackDraft.chars(message))/\(FeedbackDraft.maxMessage)")
                .font(ArenaMenuStyle.font(11, .semibold))
                .foregroundStyle(ArenaMenuStyle.dim)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var contactField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("", text: Binding(get: { contact }, set: { contact = FeedbackDraft.cleanContact($0); clearError() }),
                      prompt: Text(String(localized: "Email or handle, if you want a reply")).foregroundStyle(ArenaMenuStyle.dim))
                .font(ArenaMenuStyle.font(14, .medium))
                .foregroundStyle(ArenaMenuStyle.text)
                .tint(ArenaMenuStyle.gold)
                .textFieldStyle(.plain)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(minHeight: 40)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .accessibilityLabel(String(localized: "Contact"))
                .accessibilityIdentifier("feedback.contact")
            if !FeedbackDraft.contact(contact).ok {
                Text(FeedbackDraft.notice(for: "invalid_contact"))
                    .font(ArenaMenuStyle.font(12, .semibold))
                    .foregroundStyle(ArenaMenuStyle.ember)
            }
        }
    }

    private func clearError() { if outcome != "sent" { outcome = nil } }

    private func submit() {
        guard canSend else { return }
        sending = true
        let chosenKind = kind
        let chosenMessage = message
        let chosenContact = contact
        Task { @MainActor in
            let code = await send(chosenKind, chosenMessage, chosenContact)
            sending = false
            outcome = code
        }
    }
}
