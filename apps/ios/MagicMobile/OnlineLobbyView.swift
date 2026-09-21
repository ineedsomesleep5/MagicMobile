import SwiftUI

struct OnlineLobbyView: View {
    @ObservedObject var online: OnlineSession
    let mayEnter: Bool
    let enter: (String?) -> Void
    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var createAccount = false
    @State private var confirmLeave = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !online.available {
                Label("Online play is coming soon", systemImage: "network.slash")
                    .font(.headline)
                Text("Cross-platform play is being prepared. Use Game Center to play with iPhone friends, or play against AI.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else if online.userID == nil {
                Text("One account. Every device.").font(.headline)
                TextField("Email", text: $email).textContentType(.emailAddress)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onlineField()
                SecureField("Password", text: $password)
                    .textContentType(createAccount ? .newPassword : .password).onlineField()
                Button(createAccount ? "Create account" : "Sign in") {
                    Task { await online.signIn(email: email, password: password, create: createAccount); password = "" }
                }.buttonStyle(CommanderActionStyle())
                    .disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)
                Button(createAccount ? "Already have an account? Sign in" : "New here? Create an account") {
                    createAccount.toggle()
                }.font(.subheadline)
            } else if let lobby = online.lobby {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LOBBY CODE").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        Text(lobby.code).font(.title2.monospaced().bold()).textSelection(.enabled)
                    }
                    Spacer()
                    ShareLink(item: "Join my MagicMobile game with lobby code \(lobby.code).") {
                        Image(systemName: "square.and.arrow.up").font(.title3)
                    }.accessibilityLabel("Share lobby code")
                }
                ForEach(lobby.players) { player in
                    HStack {
                        Image(systemName: player.ready ? "checkmark.circle.fill" : "person.circle")
                            .foregroundStyle(player.ready ? Color.green : .secondary)
                        Text(player.name).font(.body.weight(.medium))
                        if player.userId == online.userID { Text("You").font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Text(player.ready ? "Ready" : "Choosing deck").font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if lobby.players.count < lobby.playerCount {
                    Text("Waiting for \(lobby.playerCount - lobby.players.count) more \(lobby.playerCount - lobby.players.count == 1 ? "player" : "players")")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if lobby.status == "interrupted" {
                    Text("This game could not be restored. Leave this lobby to start a new one.")
                        .font(.subheadline).foregroundStyle(.orange)
                } else if ["waiting", "ready"].contains(lobby.status) {
                    let ready = lobby.players.first { $0.userId == online.userID }?.ready ?? false
                    Button(ready ? "Not ready" : "Ready to play") { Task { await online.ready(!ready) } }
                        .buttonStyle(CommanderActionStyle(primary: !ready))
                    if lobby.hostUserId == online.userID {
                        Button("Start game") { Task { await online.start() } }
                            .buttonStyle(CommanderActionStyle())
                            .disabled(lobby.players.count != lobby.playerCount || !lobby.players.allSatisfy { $0.ready && $0.deckSubmitted })
                    }
                }
                Button("Leave lobby", role: .destructive) { confirmLeave = true }.font(.subheadline)
            } else {
                Text("Play together on iPhone and Android.").font(.subheadline).foregroundStyle(.secondary)
                Button("Create lobby") { enter(nil) }.buttonStyle(CommanderActionStyle()).disabled(!mayEnter)
                HStack(spacing: 10) {
                    TextField("Lobby code", text: $code).textInputAutocapitalization(.characters)
                        .autocorrectionDisabled().onlineField()
                        .onChange(of: code) { _, value in code = String(value.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }.prefix(6)) }
                    Button("Join") { enter(code) }.buttonStyle(.borderedProminent)
                        .tint(CommanderPresentation.accent).disabled(!mayEnter || code.count != 6)
                }
                HStack {
                    Text(online.email ?? "Signed in").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Sign out") { Task { await online.signOut() } }.font(.caption)
                }
            }
            if online.busy { ProgressView().frame(maxWidth: .infinity) }
            if let error = online.error {
                Text(error).font(.subheadline).foregroundStyle(.orange).accessibilityLabel("Online error: \(error)")
            } else if online.available {
                Text(online.status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(online.busy)
        .task { if online.available { await online.restore() } }
        .confirmationDialog("Leave this lobby?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Leave lobby", role: .destructive) { Task { await online.leaveLobby() } }
        } message: { Text("If the game has started, leaving ends it for every player.") }
    }
}

private extension View {
    func onlineField() -> some View {
        padding(12).background(CommanderPresentation.canvas, in: RoundedRectangle(cornerRadius: 10))
    }
}
