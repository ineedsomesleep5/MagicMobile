import SwiftUI

/// The first thing a player without a name sees (Caleb, 2026-10-29: "make them have to login"): a name for every table,
/// or sign in to the account that already has one. Covers the menus until the profile has a name; offline, or with the
/// profile server down, the app plays as before (PlayerAccount.needsName is false).
struct NameGateView: View {
    @ObservedObject var account: PlayerAccount
    @State private var name = ""
    @State private var saving = false
    @State private var google = GoogleNativeSignIn()
    @State private var apple = AppleNativeSignIn()
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.88).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    Image("LaunchMark").resizable().scaledToFit().frame(width: 72, height: 72).accessibilityHidden(true)
                    Text(String(localized: "Choose your name"))
                        .font(ArenaMenuStyle.title(26, .bold)).foregroundStyle(ArenaMenuStyle.gold)
                    VStack(spacing: 12) {
                        TextField("", text: $name, prompt: Text(String(localized: "Player name")).foregroundStyle(ArenaMenuStyle.dim))
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .font(ArenaMenuStyle.font(17, .semibold)).foregroundStyle(ArenaGlass.text).tint(ArenaMenuStyle.gold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16).frame(height: 48)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                            .focused($focused)
                            .submitLabel(.go)
                            .onSubmit(save)
                            .onChange(of: name) { _, value in
                                let clean = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(20))
                                if clean != value { name = clean }
                            }
                            .accessibilityIdentifier("nameGate.field")
                        Text(account.notice ?? String(localized: "3–20 letters, numbers or underscores"))
                            .font(ArenaMenuStyle.font(12, .medium))
                            .foregroundStyle(account.notice == nil ? ArenaMenuStyle.dim : ArenaMenuStyle.loss)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        Button(String(localized: "Continue"), action: save)
                            .buttonStyle(ArenaButtonStyle(kind: .primary, fullWidth: true))
                            .disabled(!PlayerAccountRules.isValidUsername(name) || saving || account.isSigningIn)
                            .accessibilityIdentifier("nameGate.continue")
                    }
                    .arenaCard(padding: 18)
                    VStack(spacing: 10) {
                        ArenaCaps(text: String(localized: "Already have a profile?"))
                        Button { signIn("apple") { try await apple.signIn() } } label: {
                            Label(String(localized: "Continue with Apple"), systemImage: "apple.logo")
                        }
                        .buttonStyle(ArenaButtonStyle(kind: .secondary, fullWidth: true))
                        .accessibilityIdentifier("nameGate.apple")
                        Button { signIn("google") { try await google.signIn() } } label: {
                            Label(String(localized: "Continue with Google"), systemImage: "g.circle.fill")
                        }
                        .buttonStyle(ArenaButtonStyle(kind: .secondary, fullWidth: true))
                        .accessibilityIdentifier("nameGate.google")
                        if account.isSigningIn { ProgressView().tint(ArenaMenuStyle.gold) }
                    }
                    .disabled(saving || account.isSigningIn)
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 24).padding(.vertical, 40)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .onAppear { account.notice = nil; focused = true }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nameGate")
    }

    private func save() {
        guard PlayerAccountRules.isValidUsername(name), !saving else { return }
        saving = true
        Task { _ = await account.claim(name); saving = false }
    }

    private func signIn(_ provider: String, _ flow: @escaping () async throws -> (idToken: String, nonce: String)) {
        Task {
            do {
                let result = try await flow()
                await account.signIn(provider: provider, idToken: result.idToken, nonce: result.nonce)
            } catch {
                account.notice = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
            }
        }
    }
}
