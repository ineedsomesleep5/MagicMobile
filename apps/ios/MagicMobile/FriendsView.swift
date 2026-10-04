import SwiftUI

/// Your profile name, friends with who's online, requests, and joining a friend's table in one tap.
/// Android's FriendsSheet (FriendsView.kt) matches it.
struct FriendsView: View {
    @ObservedObject var account: PlayerAccount
    /// Joins a friend's open table by its code (the same path as an invite link).
    let join: (String) -> Void
    @State private var nameDraft = ""
    @State private var editingName = false
    @State private var friendDraft = ""
    @State private var confirmDelete = false
    @State private var confirmBlock: PlayerFriend?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if account.phase == .unavailable {
                    Section {
                        Text(account.notice ?? PlayerAccountRules.message(for: "offline")).font(.callout)
                        Button("Try again") { Task { await account.start() } }
                    }
                } else if account.phase != .ready {
                    Section { HStack { ProgressView(); Text("Loading your profile…").foregroundStyle(.secondary) } }
                } else if account.username == nil || editingName {
                    nameSection
                } else {
                    profileSection
                    addSection
                    let incoming = account.friends.filter(\.isIncoming)
                    if !incoming.isEmpty {
                        Section("Requests") { ForEach(incoming) { requestRow($0) } }
                    }
                    let friends = account.friends.filter(\.isFriend)
                    Section {
                        if friends.isEmpty {
                            Text("Add friends by their player name to see when they're online and join their tables.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(friends) { friendRow($0) }
                    } header: {
                        Text(friends.isEmpty ? "Friends" : "Friends · \(account.onlineFriendCount) online")
                    }
                    let outgoing = account.friends.filter { $0.relation == "outgoing" }
                    if !outgoing.isEmpty {
                        Section("Sent") {
                            ForEach(outgoing) { friend in
                                HStack {
                                    Text(friend.username)
                                    Spacer()
                                    Button("Cancel") { Task { await account.remove(friend) } }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    if !account.blocked.isEmpty {
                        Section("Blocked") {
                            ForEach(account.blocked, id: \.self) { name in
                                HStack {
                                    Text(name)
                                    Spacer()
                                    Button("Unblock") { Task { await account.unblock(name) } }.buttonStyle(.borderless)
                                }
                            }
                        }
                    }
                    Section {
                        Button("Delete my profile", role: .destructive) { confirmDelete = true }
                            .accessibilityIdentifier("friends.deleteAccount")
                    } footer: {
                        Text("Deletes your player name, friends and blocks from MagicMobile's server. Your decks and games on this phone stay.")
                    }
                }
            }
            .tavernList()
            .navigationTitle("Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .refreshable { await account.refresh() }
            .safeAreaInset(edge: .bottom) {
                if let notice = account.notice, account.phase == .ready {
                    Text(notice)
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                        .onTapGesture { account.notice = nil }
                        .accessibilityIdentifier("friends.notice")
                }
            }
            .task { if account.phase == .ready { await account.refresh() } else { await account.start() } }
            .confirmationDialog("Delete your profile?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete profile", role: .destructive) { Task { if await account.deleteAccount() { dismiss() } } }
            } message: {
                Text("Your player name, friends and blocks are removed for good. A new profile starts the next time you open Friends.")
            }
            .confirmationDialog("Block \(confirmBlock?.username ?? "")?", isPresented: Binding(
                get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }), titleVisibility: .visible) {
                if let friend = confirmBlock {
                    Button("Block", role: .destructive) { Task { await account.block(friend.username) } }
                }
            } message: {
                Text("They're removed from your friends and can't send you requests. You can unblock them here later.")
            }
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Player name", text: $nameDraft)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .onChange(of: nameDraft) { _, value in
                    let clean = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(20))
                    if clean != value { nameDraft = clean }
                }
                .accessibilityIdentifier("friends.nameField")
            Button(editingName ? "Save name" : "Choose name") {
                Task { if await account.claim(nameDraft) { editingName = false } }
            }
            .disabled(!PlayerAccountRules.isValidUsername(nameDraft))
            .accessibilityIdentifier("friends.saveName")
            if editingName { Button("Cancel") { editingName = false } }
        } header: {
            Text("Your player name")
        } footer: {
            Text("Used at every table, and friends add you by it. 3–20 letters, numbers or underscores.")
        }
    }

    private var profileSection: some View {
        Section {
            HStack {
                Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(BrandTheme.ember)
                VStack(alignment: .leading) {
                    Text(account.username ?? "").font(.headline)
                    Text("Your name at every table").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Change") { nameDraft = account.username ?? ""; editingName = true }.buttonStyle(.borderless)
            }
        }
    }

    private var addSection: some View {
        Section("Add a friend") {
            HStack {
                TextField("Their player name", text: $friendDraft)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.send)
                    .onSubmit(addFriend)
                    .accessibilityIdentifier("friends.addField")
                Button("Add", action: addFriend)
                    .buttonStyle(.borderless)
                    .disabled(friendDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("friends.add")
            }
        }
    }

    private func addFriend() {
        let name = friendDraft
        friendDraft = ""
        Task { await account.addFriend(name) }
    }

    private func requestRow(_ friend: PlayerFriend) -> some View {
        HStack {
            Text(friend.username)
            Spacer()
            Button("Accept") { Task { await account.respond(to: friend, accept: true) } }.buttonStyle(.borderedProminent).tint(BrandTheme.ember)
            Button("Decline") { Task { await account.respond(to: friend, accept: false) } }.buttonStyle(.borderless)
        }
    }

    private func friendRow(_ friend: PlayerFriend) -> some View {
        HStack(spacing: 12) {
            Circle().fill(friend.online ? Color.green : Color.gray.opacity(0.5)).frame(width: 10, height: 10)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.username).font(.body.weight(.semibold))
                Text(status(friend)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let code = friend.joinableCode {
                Button("Join") { join(code); dismiss() }
                    .buttonStyle(.borderedProminent).tint(BrandTheme.ember)
                    .accessibilityIdentifier("friends.join.\(friend.username)")
            }
        }
        .accessibilityElement(children: .combine)
        .swipeActions {
            Button("Remove", role: .destructive) { Task { await account.remove(friend) } }
            Button("Block") { confirmBlock = friend }.tint(.orange)
        }
        .contextMenu {
            Button("Remove friend", systemImage: "person.fill.xmark", role: .destructive) { Task { await account.remove(friend) } }
            Button("Block", systemImage: "hand.raised") { confirmBlock = friend }
        }
    }

    private func status(_ friend: PlayerFriend) -> String {
        if friend.joinableCode != nil {
            let seats = friend.hostingOpenSeats ?? 1
            return seats == 1 ? String(localized: "Hosting a table · 1 seat open") : String(localized: "Hosting a table · \(seats) seats open")
        }
        if friend.online { return String(localized: "Online") }
        guard let seen = friend.lastSeenAt else { return String(localized: "Offline") }
        return String(localized: "Last seen \(seen.formatted(.relative(presentation: .named)))")
    }
}
