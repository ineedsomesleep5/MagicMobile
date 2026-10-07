import SwiftUI

/// Find players as you type, add friends, see who's online and join their tables in one tap, and open anyone's profile.
/// All in the tavern's leather and brass. Android's FriendsSheet (FriendsSheet.kt) matches it.
struct FriendsView: View {
    @ObservedObject var account: PlayerAccount
    /// Joins a friend's open table by its code (the same path as an invite link).
    let join: (String) -> Void
    /// Your ranked step this season: Ranked challenges need a friend in the same tier.
    var myRankStep: Int? = nil
    /// Challenges a friend to a Quick Match or a Ranked game (nil hides the button).
    var challenge: ((PlayerFriend, PlayMode) -> Void)? = nil

    private enum Search: Equatable {
        case idle
        case searching
        case done
        case failed(String)
    }

    @State private var nameDraft = ""
    @State private var editingName = false
    @State private var query = ""
    @State private var results: [PlayerSearchResult] = []
    @State private var search: Search = .idle
    @State private var searchTask: Task<Void, Never>?
    @State private var confirmDelete = false
    @State private var confirmBlock: PlayerFriend?
    @State private var profileFor: ProfileTarget?
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private struct ProfileTarget: Identifiable { let name: String; var id: String { name } }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    TavernPanelTitle(text: String(localized: "Friends"))
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: 8)
                    Button { dismiss() } label: { TavernSealLabel() }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Done"))
                        .accessibilityIdentifier("friends.done")
                }
                .modifier(TavernTitleBar())
                .padding(.horizontal, 16).padding(.top, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) { content }
                        .padding(16)
                        .frame(maxWidth: 640)
                        .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            if let notice = account.notice, account.phase == .ready {
                SocialNotice(text: notice) { account.notice = nil }
            }
        }
        .background(TavernSheetBackground())
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
        .foregroundStyle(TavernPalette.parchment)
        .task {
            if account.phase == .ready { await account.refresh() } else { await account.start() }
            #if DEBUG
            if let screen = SocialFixtures.openScreen {
                let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.first == "public", parts.count == 2 { profileFor = ProfileTarget(name: parts[1]) }
                if parts.first == "search", parts.count == 2 { query = parts[1] }
            }
            #endif
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .fullScreenCover(item: $profileFor) { target in
            PublicProfileView(account: account, username: target.name, challenge: challenge.map { handler in
                { name, mode in
                    if let friend = account.friends.first(where: { $0.username == name }) { handler(friend, mode) }
                }
            }, myRankStep: myRankStep) { profileFor = nil }
        }
        .tavernConfirmation(active: true, title: String(localized: "Delete your profile?"),
                            message: String(localized: "Your player name, friends and blocks are removed for good. A new profile starts the next time you open Friends."),
                            isPresented: $confirmDelete,
                            actions: [TavernDialogAction(title: String(localized: "Delete profile"), destructive: true) {
                                Task { if await account.deleteAccount() { dismiss() } }
                            }])
        .tavernConfirmation(active: true, title: String(localized: "Block \(confirmBlock?.username ?? "")?"),
                            message: String(localized: "They're removed from your friends and can't send you requests. You can unblock them here later."),
                            isPresented: Binding(get: { confirmBlock != nil }, set: { if !$0 { confirmBlock = nil } }),
                            actions: confirmBlock.map { friend in
                                [TavernDialogAction(title: String(localized: "Block"), destructive: true) { Task { await account.block(friend.username) } }]
                            } ?? [])
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if account.phase == .unavailable {
            VStack(alignment: .leading, spacing: 12) {
                Text(account.notice ?? PlayerAccountRules.message(for: "offline")).font(.system(size: 14, design: .serif))
                Button(String(localized: "Try again")) { Task { await account.start() } }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("friends.retry")
            }
            .modifier(TavernLeatherCard())
        } else if account.phase != .ready {
            SocialWaiting(text: String(localized: "Loading your profile…")).modifier(TavernLeatherCard())
        } else if account.username == nil || editingName {
            nameCard
        } else {
            profileCard
            searchCard
            let incoming = account.friends.filter(\.isIncoming)
            if !incoming.isEmpty { requestsCard(incoming) }
            friendsCard
            let outgoing = account.friends.filter(\.isOutgoing)
            if !outgoing.isEmpty { sentCard(outgoing) }
            if !account.blocked.isEmpty { blockedCard }
            VStack(alignment: .leading, spacing: 10) {
                Button(String(localized: "Delete my profile")) { confirmDelete = true }
                    .buttonStyle(TavernButtonStyle(kind: .danger, compact: true))
                    .accessibilityIdentifier("friends.deleteAccount")
                Text(String(localized: "Deletes your player name, friends, blocks and game history from MagicMobile's server. Your decks and games on this phone stay."))
                    .font(.system(size: 11, design: .serif)).opacity(0.6).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: String(localized: "Your player name"))
            TextField("", text: $nameDraft, prompt: Text(String(localized: "Player name")).foregroundStyle(TavernPalette.ink.opacity(0.5)))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .modifier(TavernFieldChrome(tavern: true))
                .onChange(of: nameDraft) { _, value in
                    let clean = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(20))
                    if clean != value { nameDraft = clean }
                }
                .accessibilityIdentifier("friends.nameField")
            HStack(spacing: 10) {
                Button(editingName ? String(localized: "Save name") : String(localized: "Choose name")) {
                    Task { if await account.claim(nameDraft) { editingName = false } }
                }
                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                .disabled(!PlayerAccountRules.isValidUsername(nameDraft))
                .accessibilityIdentifier("friends.saveName")
                if editingName {
                    Button(String(localized: "Cancel")) { editingName = false }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                }
            }
            Text(String(localized: "Used at every table, and friends add you by it. 3–20 letters, numbers or underscores."))
                .font(.system(size: 12, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
        }
        .modifier(TavernLeatherCard())
    }

    private var profileCard: some View {
        HStack(spacing: 12) {
            Button {
                if let name = account.username { profileFor = ProfileTarget(name: name) }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 30)).foregroundStyle(BrandTheme.brassGradient)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.username ?? "").font(.system(size: 18, weight: .black, design: .serif))
                        Text(account.visibilityKnown ? String(localized: "Profile: \(account.visibility.title)") : String(localized: "Your name at every table"))
                            .font(.system(size: 12, design: .serif)).opacity(0.7)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Your profile, \(account.username ?? "")"))
            .accessibilityHint(String(localized: "Opens your profile as others see it"))
            .accessibilityIdentifier("friends.myProfile")
            Button(String(localized: "Change")) { nameDraft = account.username ?? ""; editingName = true }
                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                .accessibilityIdentifier("friends.changeName")
        }
        .modifier(TavernLeatherCard())
    }

    // MARK: Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProfileSectionTitle(text: account.searchAvailable ? String(localized: "Find players") : String(localized: "Add a friend"))
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14, weight: .bold)).foregroundStyle(TavernPalette.ink.opacity(0.7))
                TextField("", text: $query, prompt: Text(account.searchAvailable ? String(localized: "Start typing a player name") : String(localized: "Their exact player name"))
                    .foregroundStyle(TavernPalette.ink.opacity(0.5)))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(account.searchAvailable ? .search : .send)
                    .focused($searchFocused)
                    .onSubmit { if !account.searchAvailable { addByName() } }
                    .accessibilityIdentifier(account.searchAvailable ? "friends.search" : "friends.addField")
                if !query.isEmpty {
                    Button { query = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(TavernPalette.ink.opacity(0.55))
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Clear search"))
                    .accessibilityIdentifier("friends.search.clear")
                }
            }
            .modifier(TavernFieldChrome(tavern: true))
            if account.searchAvailable {
                searchResults
            } else {
                HStack(spacing: 10) {
                    Button(String(localized: "Add friend"), action: addByName)
                        .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityIdentifier("friends.add")
                }
                Text(String(localized: "Live search arrives with the next server update. Until then, add a friend by their exact player name."))
                    .font(.system(size: 12, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("friends.searchUnavailable")
            }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.searchCard")
    }

    @ViewBuilder
    private var searchResults: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || PlayerSearchRules.normalized(trimmed) == nil {
            Text(trimmed.isEmpty ? String(localized: "Type two or more letters of a player's name to see who's out there.")
                 : (trimmed.count < PlayerSearchRules.minimumLength ? String(localized: "Keep typing: two letters at least.")
                    : String(localized: "Player names have letters, numbers and underscores only.")))
                .font(.system(size: 12, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("friends.search.hint")
        } else if case .failed(let message) = search {
            Text(message).font(.system(size: 13, weight: .semibold, design: .serif)).foregroundStyle(ProfilePalette.win)
                .accessibilityIdentifier("friends.search.error")
        } else if search == .searching && results.isEmpty {
            SocialWaiting(text: String(localized: "Looking for players…"))
        } else if search == .done && results.isEmpty {
            ProfileEmptyNote(text: String(localized: "No players found starting with “\(trimmed)”."), systemImage: "magnifyingglass")
                .accessibilityIdentifier("friends.search.empty")
        }
        if !results.isEmpty, PlayerSearchRules.normalized(trimmed) != nil {
            VStack(spacing: 8) {
                ForEach(results) { result in resultRow(result) }
            }
            .opacity(search == .searching ? 0.6 : 1)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("friends.search.results")
        }
    }

    private func resultRow(_ result: PlayerSearchResult) -> some View {
        SocialRowCard {
            VStack(spacing: 8) {
                Button { openProfile(result.username) } label: {
                    SocialPlayerHeading(username: result.username, commander: result.favoriteCommander, line: resultLine(result),
                                        online: result.relation == "friend" ? result.online : nil, rank: result.position)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(resultLabel(result))
                .accessibilityHint(String(localized: "Opens their profile"))
                .accessibilityIdentifier("friends.result.\(result.username)")
                HStack(spacing: 8) {
                    if result.visibility != .public { TavernTag(text: result.visibility == .friends ? String(localized: "FRIENDS ONLY") : String(localized: "PRIVATE"), leather: true) }
                    Spacer(minLength: 0)
                    Button(String(localized: "Profile")) { openProfile(result.username) }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                        .accessibilityLabel(String(localized: "View \(result.username)'s profile"))
                        .accessibilityIdentifier("friends.result.profile.\(result.username)")
                    relationAction(result)
                }
            }
        }
    }

    @ViewBuilder
    private func relationAction(_ result: PlayerSearchResult) -> some View {
        switch result.relation {
        case "friend":
            TavernTag(text: String(localized: "FRIENDS"), leather: true, accent: result.online == true ? Color(red: 0.4, green: 0.85, blue: 0.4) : nil)
        case "outgoing":
            TavernTag(text: String(localized: "REQUESTED"), leather: true)
        case "incoming":
            Button(String(localized: "Accept")) { acceptFromSearch(result) }
                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                .accessibilityLabel(String(localized: "Accept \(result.username)'s request"))
                .accessibilityIdentifier("friends.result.accept.\(result.username)")
        default:
            Button(String(localized: "Add friend")) { addFromSearch(result) }
                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                .accessibilityLabel(String(localized: "Add \(result.username) as a friend"))
                .accessibilityIdentifier("friends.result.add.\(result.username)")
        }
    }

    private func resultLine(_ result: PlayerSearchResult) -> String {
        if let commander = result.favoriteCommander { return commander }
        return result.visibility == .public ? String(localized: "No games to show yet") : String(localized: "Profile hidden")
    }

    private func resultLabel(_ result: PlayerSearchResult) -> String {
        let rank = result.position.map { ", \($0.title)" } ?? ", unranked"
        let relation: String
        switch result.relation {
        case "friend": relation = ", friend" + (result.online == true ? ", online" : "")
        case "outgoing": relation = ", request sent"
        case "incoming": relation = ", wants to be your friend"
        default: relation = ""
        }
        return "\(result.username)\(rank)\(relation)"
    }

    /// Typing: wait a moment after the last key, and drop the request a newer one replaced.
    private func scheduleSearch() {
        searchTask?.cancel()
        guard account.searchAvailable, let text = PlayerSearchRules.normalized(query) else {
            results = []; search = .idle; return
        }
        search = .searching
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                let found = try await account.search(text)
                guard !Task.isCancelled, PlayerSearchRules.normalized(query) == text else { return }
                results = found
                search = .done
            } catch is CancellationError {
                // A newer search took over.
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                // Without the server's search the field turns into a plain "add by name" one.
                search = account.searchAvailable ? .failed(PlayerAccountRules.message(for: SupabaseLite.code(of: error))) : .idle
            }
        }
    }

    private func addByName() {
        let name = query
        query = ""
        Task { await account.addFriend(name) }
    }

    private func addFromSearch(_ result: PlayerSearchResult) {
        results = results.map { $0.username == result.username ? $0.with(relation: "outgoing") : $0 }
        Task {
            await account.addFriend(result.username)
            await account.refresh()
            // A request they had already sent you makes you friends at once.
            if let now = account.friends.first(where: { $0.username == result.username }) {
                results = results.map { $0.username == result.username ? $0.with(relation: now.relation) : $0 }
            }
        }
    }

    private func acceptFromSearch(_ result: PlayerSearchResult) {
        guard let friend = account.friends.first(where: { $0.username == result.username }) else { return }
        results = results.map { $0.username == result.username ? $0.with(relation: "friend") : $0 }
        Task { await account.respond(to: friend, accept: true) }
    }

    private func openProfile(_ name: String) {
        GameAudio.shared.play(.uiOpen)
        searchFocused = false
        profileFor = ProfileTarget(name: name)
    }

    // MARK: Requests and friends

    private func requestsCard(_ incoming: [PlayerFriend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle(text: String(localized: "Requests"), trailing: "\(incoming.count)")
            ForEach(incoming) { friend in
                SocialRowCard {
                    VStack(spacing: 8) {
                        Button { openProfile(friend.username) } label: {
                            SocialPlayerHeading(username: friend.username, commander: nil, line: String(localized: "Wants to be your friend"),
                                                online: nil, rank: account.friendRanks[friend.username])
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .ignore)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(String(localized: "\(friend.username) wants to be your friend"))
                        .accessibilityHint(String(localized: "Opens their profile"))
                        .accessibilityIdentifier("friends.request.\(friend.username)")
                        HStack(spacing: 8) {
                            Spacer(minLength: 0)
                            Button(String(localized: "Decline")) { Task { await account.respond(to: friend, accept: false) } }
                                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                                .accessibilityIdentifier("friends.decline.\(friend.username)")
                            Button(String(localized: "Accept")) { Task { await account.respond(to: friend, accept: true) } }
                                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                                .accessibilityIdentifier("friends.accept.\(friend.username)")
                        }
                    }
                }
            }
        }
        .modifier(TavernLeatherCard())
    }

    private var friendsCard: some View {
        let friends = account.friends.filter(\.isFriend)
        return VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle(text: String(localized: "Friends"), trailing: friends.isEmpty ? nil : String(localized: "\(account.onlineFriendCount) online"))
            if friends.isEmpty {
                ProfileEmptyNote(text: String(localized: "Search for a player above to add your first friend. You'll see when they're online and can join their tables."), systemImage: "person.2.fill")
            }
            ForEach(friends) { friend in friendRow(friend) }
        }
        .modifier(TavernLeatherCard())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.list")
    }

    private func friendRow(_ friend: PlayerFriend) -> some View {
        SocialRowCard {
            VStack(spacing: 8) {
                Button { openProfile(friend.username) } label: {
                    SocialPlayerHeading(username: friend.username, commander: nil, line: status(friend), online: friend.online,
                                        rank: account.friendRanks[friend.username])
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(friendLabel(friend))
                .accessibilityHint(String(localized: "Opens their profile"))
                .accessibilityIdentifier("friends.card.\(friend.username)")
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    if let code = friend.joinableCode {
                        Button(String(localized: "Join")) { join(code); dismiss() }
                            .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                            .accessibilityIdentifier("friends.join.\(friend.username)")
                    } else if let challenge, friend.online {
                        challengeMenu(friend, challenge)
                    }
                    TavernMenu(arrowEdge: .top) {
                        TavernMenuItem(title: String(localized: "View profile"), systemImage: "person.crop.circle") { openProfile(friend.username) }
                        TavernMenuItem(title: String(localized: "Remove friend"), systemImage: "person.fill.xmark", destructive: true) { Task { await account.remove(friend) } }
                        TavernMenuItem(title: String(localized: "Block"), systemImage: "hand.raised", destructive: true) { confirmBlock = friend }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 17, weight: .black)).foregroundStyle(BrandTheme.brassGradient)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(String(localized: "More about \(friend.username)"))
                    .accessibilityIdentifier("friends.more.\(friend.username)")
                }
            }
        }
    }

    /// Quick Match for any online friend; Ranked only in the same tier (Gold with Gold).
    private func challengeMenu(_ friend: PlayerFriend, _ challenge: @escaping (PlayerFriend, PlayMode) -> Void) -> some View {
        let mayRank = myRankStep.map { FriendChallengeRules.mayRank(myStep: $0, friendStep: account.friendRanks[friend.username]?.step) } ?? false
        return TavernMenu(arrowEdge: .top) {
            TavernMenuItem(title: String(localized: "Quick Match"), systemImage: "bolt.fill") { challenge(friend, .quick); dismiss() }
            TavernMenuItem(title: mayRank ? String(localized: "Ranked") : String(localized: "Ranked · same tier only"), systemImage: "shield.lefthalf.filled") {
                if mayRank { challenge(friend, .ranked); dismiss() }
            }
        } label: {
            Text(String(localized: "Challenge")).font(.system(size: 12, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 1, green: 0.91, blue: 0.66))
                .padding(.horizontal, 16).frame(minHeight: 44)
                .background { TavernFill(material: .ember).clipShape(Capsule()).padding(3) }
                .overlay { TavernCapsuleRim() }
        }
        .accessibilityLabel(String(localized: "Challenge \(friend.username)"))
        .accessibilityIdentifier("friends.challenge.\(friend.username)")
    }

    private func sentCard(_ outgoing: [PlayerFriend]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle(text: String(localized: "Sent"), trailing: "\(outgoing.count)")
            ForEach(outgoing) { friend in
                SocialRowCard {
                    HStack(spacing: 8) {
                        Button { openProfile(friend.username) } label: {
                            Text(friend.username).font(.system(size: 15, weight: .heavy, design: .serif)).underline(color: TavernPalette.brass.opacity(0.6))
                                .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "\(friend.username), request sent"))
                        .accessibilityIdentifier("friends.sent.\(friend.username)")
                        Spacer(minLength: 0)
                        Button(String(localized: "Cancel")) { Task { await account.remove(friend) } }
                            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                            .accessibilityLabel(String(localized: "Cancel the request to \(friend.username)"))
                            .accessibilityIdentifier("friends.cancel.\(friend.username)")
                    }
                }
            }
        }
        .modifier(TavernLeatherCard())
    }

    private var blockedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProfileSectionTitle(text: String(localized: "Blocked"), trailing: "\(account.blocked.count)")
            ForEach(account.blocked, id: \.self) { name in
                SocialRowCard {
                    HStack(spacing: 8) {
                        Text(name).font(.system(size: 15, weight: .heavy, design: .serif))
                        Spacer(minLength: 0)
                        Button(String(localized: "Unblock")) { Task { await account.unblock(name) } }
                            .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                            .accessibilityLabel(String(localized: "Unblock \(name)"))
                            .accessibilityIdentifier("friends.unblock.\(name)")
                    }
                }
            }
        }
        .modifier(TavernLeatherCard())
    }

    private func friendLabel(_ friend: PlayerFriend) -> String {
        let rank = account.friendRanks[friend.username].map { ", \($0.title)" } ?? ""
        return "\(friend.username)\(rank), \(status(friend))"
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
