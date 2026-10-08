import AuthenticationServices
import CryptoKit
import SwiftUI
import UIKit

/// Google Cloud project "magicmobile" (docs/social/PROFILES.md, "Signing in with Google or Apple"). Client IDs are public; there is no secret in the app.
enum AccountSignInConfig {
    static let googleIOSClientID = "917754280625-p38au9m1r2mg0k3ubob2batpdot9gdlb.apps.googleusercontent.com"
    /// Google's iOS redirect: the client ID reversed, as a custom scheme only this app's sign-in sheet listens for.
    static var googleRedirectScheme: String {
        "com.googleusercontent.apps." + googleIOSClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
    }
}

/// A one-time value for an ID token: the provider gets its SHA-256, Supabase gets the raw value and checks they match.
struct SignInNonce {
    let raw: String
    var hashed: String { SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined() }

    static func make() -> SignInNonce {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return SignInNonce(raw: Data(bytes).base64EncodedString().replacingOccurrences(of: "[^A-Za-z0-9]", with: "", options: .regularExpression))
    }
}

/// Google sign-in in Google's own secure sheet (ASWebAuthenticationSession), authorization code with PKCE, then the
/// code exchanged for an ID token. No Google SDK, and no secret: an iOS OAuth client is a public client.
@MainActor
final class GoogleNativeSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func signIn() async throws -> (idToken: String, nonce: String) {
        let nonce = SignInNonce.make(), verifier = SignInNonce.make().raw + SignInNonce.make().raw
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let redirect = AccountSignInConfig.googleRedirectScheme + ":/oauthredirect"
        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            .init(name: "client_id", value: AccountSignInConfig.googleIOSClientID), .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"), .init(name: "scope", value: "openid email profile"),
            .init(name: "code_challenge", value: challenge), .init(name: "code_challenge_method", value: "S256"),
            .init(name: "nonce", value: nonce.hashed), .init(name: "prompt", value: "select_account"),
        ]
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: auth.url!, callbackURLScheme: AccountSignInConfig.googleRedirectScheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: SupabaseLite.Failure(code: "sign_in_cancelled"))
                } else { continuation.resume(throwing: error ?? SupabaseLite.Failure(code: "error")) }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw SupabaseLite.Failure(code: "sign_in_cancelled")
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = [.init(name: "code", value: code), .init(name: "client_id", value: AccountSignInConfig.googleIOSClientID),
                           .init(name: "redirect_uri", value: redirect), .init(name: "grant_type", value: "authorization_code"),
                           .init(name: "code_verifier", value: verifier)]
        request.httpBody = form.percentEncodedQuery?.data(using: .utf8)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let idToken = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["id_token"] as? String else {
            throw SupabaseLite.Failure(code: "error")
        }
        return (idToken, nonce.raw)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
    }
}

/// Sign in with Apple (required next to Google on iPhone), with a nonce.
@MainActor
final class AppleNativeSignIn: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<String, Error>?

    func signIn() async throws -> (idToken: String, nonce: String) {
        let nonce = SignInNonce.make()
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.email]
        request.nonce = nonce.hashed
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        let token = try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            controller.performRequests()
        }
        return (token, nonce.raw)
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let token = (authorization.credential as? ASAuthorizationAppleIDCredential)?.identityToken.flatMap { String(data: $0, encoding: .utf8) }
        Task { @MainActor in
            if let token { continuation?.resume(returning: token) } else { continuation?.resume(throwing: SupabaseLite.Failure(code: "error")) }
            continuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        let cancelled = (error as? ASAuthorizationError)?.code == .canceled
        Task { @MainActor in
            continuation?.resume(throwing: SupabaseLite.Failure(code: cancelled ? "sign_in_cancelled" : "error"))
            continuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first ?? ASPresentationAnchor()
        }
    }
}

/// The profile's "Keep your profile" card: sign in with Apple or Google so the name, friends and rank follow the player
/// to any phone; signed in, it shows the account and a sign-out. Walnut Tavern leather like the cards around it.
struct AccountSignInCard: View {
    @ObservedObject var account: PlayerAccount
    @State private var google = GoogleNativeSignIn()
    @State private var apple = AppleNativeSignIn()
    @State private var confirmingSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: account.linkedIdentities.isEmpty ? String(localized: "Keep your profile") : String(localized: "Your account"))
            if account.linkedIdentities.isEmpty {
                Text("Sign in to keep your name, friends and rank on every phone. Your profile on this phone comes with you.")
                    .font(.system(size: 13, design: .serif)).opacity(0.85).fixedSize(horizontal: false, vertical: true)
                Button { run(provider: "apple") { try await apple.signIn() } } label: {
                    Label(String(localized: "Continue with Apple"), systemImage: "apple.logo")
                }
                .buttonStyle(TavernButtonStyle(kind: .primary, fullWidth: true))
                .accessibilityIdentifier("profile.account.apple")
                Button { run(provider: "google") { try await google.signIn() } } label: {
                    Label(String(localized: "Continue with Google"), systemImage: "g.circle.fill")
                }
                .buttonStyle(TavernButtonStyle(kind: .secondary, fullWidth: true))
                .accessibilityIdentifier("profile.account.google")
            } else {
                ForEach(account.linkedIdentities) { identity in
                    Label(identity.email.map { "\(identity.title) · \($0)" } ?? identity.title,
                          systemImage: identity.provider == "apple" ? "apple.logo" : "g.circle.fill")
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                }
                Button(String(localized: "Sign Out")) { confirmingSignOut = true }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("profile.account.signOut")
            }
            if account.isSigningIn { ProgressView().tint(TavernPalette.parchment) }
        }
        .disabled(account.isSigningIn || account.phase == .loading)
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("profile.accountCard")
        .confirmationDialog(String(localized: "Sign out on this phone?"), isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button(String(localized: "Sign Out"), role: .destructive) { Task { await account.signOut() } }
        } message: {
            Text("Your profile stays on your account. This phone starts a new one until you sign in again.")
        }
    }

    private func run(provider: String, _ flow: @escaping () async throws -> (idToken: String, nonce: String)) {
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
