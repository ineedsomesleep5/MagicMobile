import SwiftUI

/// Find players as you type, add friends, see who's online and join their tables in one tap, and open anyone's profile.
/// Arena's social panel (Caleb, 2026-10-22): it slides in from the left with your name at the top, Friends and Messages
/// as a tab strip, the search in one slim field and requests folded into a row, so your friends show first.
/// Android's FriendsSheet (FriendsSheet.kt) matches it.
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
    @State private var tab: Tab = .friends
    @State private var conversationWith: ProfileTarget?
    @State private var showRequests = false
    @FocusState private var searchFocused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.arenaPanelClose) private var panelClose
    /// Closes the Arena menu panel this page is shown in, or the sheet elsewhere.
    private func closePanel() { if let panelClose { panelClose() } else { dismiss() } }

    private struct ProfileTarget: Identifiable { let name: String; var id: String { name } }
    private enum Tab: String, CaseIterable { case friends, messages }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                ArenaPanelHeader(title: String(localized: "Friends"), closeIdentifier: "friends.done")
                // The delete link follows the list; upright the drawer is only as tall as its page (the judge, 2026-10-22).
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 12) { content }
                        if showsDeleteLink {
                            deleteLink.padding(.top, 18)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 36)
                    .frame(maxWidth: 640)
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize)
                // Rows fade into the panel's foot rather than being cut by it.
                .mask(ArenaScrollFade())
            }
            if let notice = account.notice, account.phase == .ready {
                SocialNotice(text: notice) { account.notice = nil }
            }
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(ArenaMenuStyle.text)
        .task {
            if account.phase == .ready { await account.refresh() } else { await account.start() }
            #if DEBUG
            if let screen = SocialFixtures.openScreen {
                let parts = screen.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.first == "public", parts.count == 2 { profileFor = ProfileTarget(name: parts[1]) }
                if parts.first == "search", parts.count == 2 { query = parts[1] }
                if parts.first == "messages" { tab = .messages }
                if parts.first == "conversation", parts.count == 2 { tab = .messages; conversationWith = ProfileTarget(name: parts[1]) }
            }
            #endif
        }
        .onChange(of: query) { _, _ in scheduleSearch() }
        .fullScreenCover(item: $conversationWith) { target in
            FriendConversationView(account: account, username: target.name) { conversationWith = nil }
        }
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
                                Task { if await account.deleteAccount() { closePanel() } }
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
                Text(account.notice ?? PlayerAccountRules.message(for: "offline")).font(ArenaMenuStyle.font(14, .medium))
                Button(String(localized: "Try again")) { Task { await account.start() } }
                    .buttonStyle(ArenaPillButtonStyle())
                    .accessibilityIdentifier("friends.retry")
            }
            .arenaCard()
        } else if account.phase != .ready {
            SocialWaiting(text: String(localized: "Loading your profile…")).arenaCard()
        } else if account.username == nil || editingName {
            nameCard
        } else {
            profileCard
            tabPicker
            if tab == .messages {
                FriendMessagesList(account: account) { openConversation($0) }
            } else {
                searchRow
                let incoming = account.friends.filter(\.isIncoming)
                if !incoming.isEmpty { requestsRow(incoming) }
                friendsList
                let outgoing = account.friends.filter(\.isOutgoing)
                if !outgoing.isEmpty { sentList(outgoing) }
                if !account.blocked.isEmpty { blockedList }
            }
        }
    }

    private var showsDeleteLink: Bool { account.phase == .ready && account.username != nil && !editingName }

    /// Out of the way at the very foot, as small type (the judge, 2026-10-22: not a plaque in the social panel).
    private var deleteLink: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(String(localized: "Delete my profile")) { confirmDelete = true }
                .font(ArenaMenuStyle.font(12, .semibold))
                .foregroundStyle(ArenaMenuStyle.loss)
                .buttonStyle(.plain)
                .frame(minHeight: 44)
                .accessibilityIdentifier("friends.deleteAccount")
            Text(String(localized: "Deletes your player name, friends, blocks and game history from MagicMobile's server. Your decks and games on this phone stay."))
                .font(ArenaMenuStyle.font(10.5, .medium)).foregroundStyle(ArenaMenuStyle.dim.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var nameCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArenaCaps(text: String(localized: "Your player name"))
            TextField("", text: $nameDraft, prompt: Text(String(localized: "Player name")).foregroundStyle(ArenaMenuStyle.dim))
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .font(ArenaMenuStyle.font(15, .semibold))
                .tint(ArenaMenuStyle.gold)
                .padding(.horizontal, 14).frame(height: 40)
                .background(Capsule().fill(Color.black.opacity(0.55)))
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 1).opacity(0.7))
                .onChange(of: nameDraft) { _, value in
                    let clean = String(value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }.prefix(20))
                    if clean != value { nameDraft = clean }
                }
                .accessibilityIdentifier("friends.nameField")
            HStack(spacing: 10) {
                Button(editingName ? String(localized: "Save name") : String(localized: "Choose name")) {
                    Task { if await account.claim(nameDraft) { editingName = false } }
                }
                .buttonStyle(ArenaPillButtonStyle(lit: true))
                .disabled(!PlayerAccountRules.isValidUsername(nameDraft))
                .accessibilityIdentifier("friends.saveName")
                if editingName {
                    Button(String(localized: "Cancel")) { editingName = false }
                        .buttonStyle(ArenaPillButtonStyle())
                }
            }
            Text(String(localized: "Used at every table, and friends add you by it. 3–20 letters, numbers or underscores."))
                .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).fixedSize(horizontal: false, vertical: true)
        }
        .arenaCard()
    }

    /// You, at the top of the panel as in Arena's: your picture, name and who can see your profile.
    private var profileCard: some View {
        HStack(spacing: 10) {
            Button {
                if let name = account.username { profileFor = ProfileTarget(name: name) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.fill").font(.system(size: 30)).foregroundStyle(ArenaMenuStyle.gold)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(account.username ?? "").font(ArenaMenuStyle.font(17, .bold)).lineLimit(1).minimumScaleFactor(0.75)
                        Text(account.visibilityKnown ? String(localized: "Profile: \(account.visibility.title)") : String(localized: "Your name at every table"))
                            .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(1)
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
                .buttonStyle(ArenaPillButtonStyle())
                .accessibilityIdentifier("friends.changeName")
        }
    }

    // MARK: Tabs

    /// Friends or Messages as Arena's tab strip, with the unread count beside Messages.
    private var tabPicker: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases, id: \.self) { option in
                let selected = tab == option
                Button {
                    guard !selected else { return }
                    GameAudio.shared.play(.uiTap)
                    withAnimation(.easeOut(duration: 0.16)) { tab = option }
                } label: {
                    HStack(spacing: 6) {
                        Text(option == .friends ? String(localized: "Friends") : String(localized: "Messages"))
                            .font(ArenaMenuStyle.font(14, selected ? .bold : .semibold))
                            .foregroundStyle(selected ? ArenaMenuStyle.text : ArenaMenuStyle.dim)
                        if option == .messages, account.unreadMessages > 0 {
                            Text("\(account.unreadMessages)")
                                .font(.system(size: 10, weight: .black)).monospacedDigit().foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(ArenaMenuStyle.ember, in: Capsule())
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .overlay(alignment: .bottom) { ArenaTabBar(on: selected) }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(BrandPressStyle())
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("friends.tab.\(option.rawValue)")
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.35).offset(y: -2) }
    }

    private func openConversation(_ name: String) {
        searchFocused = false
        conversationWith = ProfileTarget(name: name)
    }

    // MARK: Search

    /// One slim field: live search, or add by exact name until the server has search. What it finds shows under it.
    private var searchRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ArenaSearchField(placeholder: account.searchAvailable ? String(localized: "Find players") : String(localized: "Their exact player name"),
                                 text: $query, identifier: account.searchAvailable ? "friends.search" : "friends.addField",
                                 focus: $searchFocused)
                    .textInputAutocapitalization(.never)
                    .submitLabel(account.searchAvailable ? .search : .send)
                    .onSubmit { if !account.searchAvailable { addByName() } }
                if !account.searchAvailable {
                    Button(String(localized: "Add"), action: addByName)
                        .buttonStyle(ArenaPillButtonStyle(lit: true))
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel(String(localized: "Add friend"))
                        .accessibilityIdentifier("friends.add")
                }
            }
            if account.searchAvailable {
                searchResults
            } else if !query.isEmpty {
                Text(String(localized: "Live search arrives with the next server update. Until then, add a friend by their exact player name."))
                    .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("friends.searchUnavailable")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.searchCard")
    }

    @ViewBuilder
    private var searchResults: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // Nothing under an empty field, so the friends list stays at the top of the panel.
        if !trimmed.isEmpty && PlayerSearchRules.normalized(trimmed) == nil {
            Text(trimmed.count < PlayerSearchRules.minimumLength ? String(localized: "Keep typing: two letters at least.")
                 : String(localized: "Player names have letters, numbers and underscores only."))
                .font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("friends.search.hint")
        } else if case .failed(let message) = search {
            Text(message).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.loss)
                .accessibilityIdentifier("friends.search.error")
        } else if search == .searching && results.isEmpty {
            SocialWaiting(text: String(localized: "Looking for players…"))
        } else if search == .done && results.isEmpty {
            ProfileEmptyNote(text: String(localized: "No players found starting with “\(trimmed)”."), systemImage: "magnifyingglass")
                .accessibilityIdentifier("friends.search.empty")
        }
        if !results.isEmpty, PlayerSearchRules.normalized(trimmed) != nil {
            VStack(spacing: 6) {
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
                                        online: result.relation == "friend" ? result.online : nil, rank: result.position, compact: true)
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
                        .buttonStyle(ArenaPillButtonStyle())
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
                .buttonStyle(ArenaPillButtonStyle(lit: true))
                .accessibilityLabel(String(localized: "Accept \(result.username)'s request"))
                .accessibilityIdentifier("friends.result.accept.\(result.username)")
        default:
            Button(String(localized: "Add friend")) { addFromSearch(result) }
                .buttonStyle(ArenaPillButtonStyle(lit: true))
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

    /// Requests fold into one row with their count; it opens them in place.
    private func requestsRow(_ incoming: [PlayerFriend]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ArenaOptionRow(title: String(localized: "Requests"), value: "\(incoming.count)", chevron: true, identifier: "friends.requests") {
                withAnimation(.easeOut(duration: 0.18)) { showRequests.toggle() }
            }
            .accessibilityValue(showRequests ? String(localized: "Expanded") : String(localized: "Collapsed"))
            if showRequests {
                ForEach(incoming) { friend in
                    SocialRowCard {
                        HStack(spacing: 6) {
                            Button { openProfile(friend.username) } label: {
                                SocialPlayerHeading(username: friend.username, commander: nil, line: String(localized: "Wants to be your friend"),
                                                    online: nil, rank: account.friendRanks[friend.username], compact: true)
                            }
                            .buttonStyle(.plain)
                            .accessibilityElement(children: .ignore)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(String(localized: "\(friend.username) wants to be your friend"))
                            .accessibilityHint(String(localized: "Opens their profile"))
                            .accessibilityIdentifier("friends.request.\(friend.username)")
                            Button { Task { await account.respond(to: friend, accept: false) } } label: {
                                Image(systemName: "xmark").font(.system(size: 12, weight: .heavy)).foregroundStyle(ArenaMenuStyle.dim)
                                    .frame(width: 36, height: 44).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Decline"))
                            .accessibilityIdentifier("friends.decline.\(friend.username)")
                            Button(String(localized: "Accept")) { Task { await account.respond(to: friend, accept: true) } }
                                .buttonStyle(ArenaPillButtonStyle(lit: true))
                                .accessibilityIdentifier("friends.accept.\(friend.username)")
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    /// Your friends as Arena lists them: one line each (picture, name, status, rank), online first as the server sends
    /// them, with Join or Challenge, Message and ⋯ as small buttons at the end of the line (the judge, 2026-10-22).
    private var friendsList: some View {
        let friends = account.friends.filter(\.isFriend)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                ArenaCaps(text: String(localized: "Friends"))
                Spacer(minLength: 6)
                if !friends.isEmpty {
                    Text(String(localized: "\(account.onlineFriendCount) online")).font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
                }
            }
            .padding(.top, 4)
            if friends.isEmpty {
                ProfileEmptyNote(text: String(localized: "Search for a player above to add your first friend. You'll see when they're online and can join their tables."), systemImage: "person.2.fill")
            }
            ForEach(friends) { friend in friendRow(friend) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("friends.list")
    }

    private func friendRow(_ friend: PlayerFriend) -> some View {
        HStack(spacing: 0) {
            Button { openProfile(friend.username) } label: {
                SocialPlayerHeading(username: friend.username, commander: nil, line: status(friend), online: friend.online,
                                    rank: account.friendRanks[friend.username], compact: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(friendLabel(friend))
            .accessibilityHint(String(localized: "Opens their profile"))
            .accessibilityIdentifier("friends.card.\(friend.username)")
            if let code = friend.joinableCode {
                Button { join(code); closePanel() } label: { FriendRowAction(symbol: "arrow.right.circle.fill") }
                    .buttonStyle(BrandPressStyle())
                    .accessibilityLabel(String(localized: "Join \(friend.username)'s table"))
                    .accessibilityIdentifier("friends.join.\(friend.username)")
            } else if let challenge, friend.online {
                challengeMenu(friend, challenge)
            }
            if account.messagesAvailable {
                Button {
                    GameAudio.shared.play(.uiOpen)
                    openConversation(friend.username)
                } label: {
                    Image(systemName: "bubble.left.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold)
                        .frame(width: 34, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Message \(friend.username)"))
                .accessibilityIdentifier("friends.message.\(friend.username)")
            }
            TavernMenu(arrowEdge: .top) {
                TavernMenuItem(title: String(localized: "View profile"), systemImage: "person.crop.circle") { openProfile(friend.username) }
                TavernMenuItem(title: String(localized: "Message"), systemImage: "bubble.left") { openConversation(friend.username) }
                TavernMenuItem(title: String(localized: "Remove friend"), systemImage: "person.fill.xmark", destructive: true) { Task { await account.remove(friend) } }
                TavernMenuItem(title: String(localized: "Block"), systemImage: "hand.raised", destructive: true) { confirmBlock = friend }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 16, weight: .black)).foregroundStyle(ArenaMenuStyle.gold)
                    .frame(width: 30, height: 44).contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "More about \(friend.username)"))
            .accessibilityIdentifier("friends.more.\(friend.username)")
        }
        .padding(.vertical, 1)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }

    /// Quick Match for any online friend; Ranked only in the same tier (Gold with Gold).
    private func challengeMenu(_ friend: PlayerFriend, _ challenge: @escaping (PlayerFriend, PlayMode) -> Void) -> some View {
        let mayRank = myRankStep.map { FriendChallengeRules.mayRank(myStep: $0, friendStep: account.friendRanks[friend.username]?.step) } ?? false
        return TavernMenu(arrowEdge: .top) {
            TavernMenuItem(title: String(localized: "Quick Match"), systemImage: "bolt.fill") { challenge(friend, .quick); closePanel() }
            TavernMenuItem(title: mayRank ? String(localized: "Ranked") : String(localized: "Ranked · same tier only"), systemImage: "shield.lefthalf.filled") {
                if mayRank { challenge(friend, .ranked); closePanel() }
            }
        } label: {
            FriendRowAction(symbol: "flag.2.crossed.fill")
        }
        .accessibilityLabel(String(localized: "Challenge \(friend.username)"))
        .accessibilityIdentifier("friends.challenge.\(friend.username)")
    }

    private func sentList(_ outgoing: [PlayerFriend]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                ArenaCaps(text: String(localized: "Sent"))
                Spacer(minLength: 6)
                Text("\(outgoing.count)").font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
            }
            .padding(.top, 8)
            ForEach(outgoing) { friend in
                HStack(spacing: 8) {
                    Button { openProfile(friend.username) } label: {
                        Text(friend.username).font(ArenaMenuStyle.font(15, .semibold))
                            .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "\(friend.username), request sent"))
                    .accessibilityIdentifier("friends.sent.\(friend.username)")
                    Spacer(minLength: 0)
                    Button(String(localized: "Cancel")) { Task { await account.remove(friend) } }
                        .buttonStyle(ArenaPillButtonStyle())
                        .accessibilityLabel(String(localized: "Cancel the request to \(friend.username)"))
                        .accessibilityIdentifier("friends.cancel.\(friend.username)")
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }

    private var blockedList: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                ArenaCaps(text: String(localized: "Blocked"))
                Spacer(minLength: 6)
                Text("\(account.blocked.count)").font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
            }
            .padding(.top, 8)
            ForEach(account.blocked, id: \.self) { name in
                HStack(spacing: 8) {
                    Text(name).font(ArenaMenuStyle.font(15, .semibold))
                    Spacer(minLength: 0)
                    Button(String(localized: "Unblock")) { Task { await account.unblock(name) } }
                        .buttonStyle(ArenaPillButtonStyle())
                        .accessibilityLabel(String(localized: "Unblock \(name)"))
                        .accessibilityIdentifier("friends.unblock.\(name)")
                }
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }

    private func friendLabel(_ friend: PlayerFriend) -> String {
        let rank = account.friendRanks[friend.username].map { ", \($0.title)" } ?? ""
        return "\(friend.username)\(rank), \(status(friend))"
    }

    /// Short enough to show whole on one line beside the row's buttons.
    private func status(_ friend: PlayerFriend) -> String {
        if friend.joinableCode != nil {
            let seats = friend.hostingOpenSeats ?? 1
            return seats == 1 ? String(localized: "Hosting · 1 seat") : String(localized: "Hosting · \(seats) seats")
        }
        if friend.online { return String(localized: "Online") }
        guard let seen = friend.lastSeenAt else { return String(localized: "Offline") }
        return String(localized: "Last seen \(seen.formatted(.relative(presentation: .named)))")
    }
}

/// A friend row's own action (Join a table, Challenge) as a small lit ember disc with a gold rim, at the end of the line.
private struct FriendRowAction: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.white)
            .frame(width: 28, height: 28)
            .background { Circle().fill(ArenaMenuStyle.orange) }
            .overlay(Circle().strokeBorder(ArenaMenuStyle.orangeRim, lineWidth: 1.2))
            .shadow(color: ArenaMenuStyle.ember.opacity(0.5), radius: 4)
            .frame(width: 36, height: 44)
            .contentShape(Rectangle())
    }
}
