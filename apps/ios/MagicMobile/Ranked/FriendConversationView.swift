import SwiftUI

/// A conversation with a friend: parchment bubbles for theirs, brass for yours, a send box with quick replies, and new
/// messages every few seconds while it's open. Their words show with strong language masked, like table chat. Report
/// and Block sit in the header menu. Android's FriendConversationScreen matches it.
struct FriendConversationView: View {
    @ObservedObject var account: PlayerAccount
    let username: String
    let close: () -> Void

    @State private var messages: [FriendMessage] = []
    @State private var hasMore = false
    @State private var loaded = false
    @State private var failure: String?
    @State private var draft = ""
    @State private var sending = false
    @State private var loadingEarlier = false
    @State private var active = true
    @State private var confirmBlock = false
    @State private var showProfile = false
    @FocusState private var focused: Bool
    @Environment(\.scenePhase) private var scenePhase

    static var quickReplies: [String] {
        [String(localized: "Want to play?"), GameEmote.hello.text, GameEmote.goodGame.text, GameEmote.wellPlayed.text, GameEmote.thanks.text]
    }

    private var online: Bool? { account.friends.first { $0.username == username }?.online }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                TavernScreenHeader(title: username, backTitle: String(localized: "Messages"), back: close) { menu }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                if let online {
                    Text(online ? String(localized: "Online now") : String(localized: "Offline"))
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(online ? LeaderboardOnlineDot.color : TavernPalette.parchment.opacity(0.6))
                        .padding(.top, 4)
                        .accessibilityIdentifier("conversation.presence")
                }
                transcript
                composer
            }
            if let notice = account.notice, account.phase == .ready {
                SocialNotice(text: notice) { account.notice = nil }.padding(.bottom, 120)
            }
        }
        .background(BrandBackdrop(cards: false).ignoresSafeArea())
        .environment(\.tavernBoard, true)
        .preferredColorScheme(.dark)
        .foregroundStyle(TavernPalette.parchment)
        .onChange(of: scenePhase) { _, phase in active = phase == .active }
        .task {
            while !Task.isCancelled {
                if active { await refresh() }
                try? await Task.sleep(nanoseconds: FriendMessageRules.pollSeconds * 1_000_000_000)
            }
        }
        .fullScreenCover(isPresented: $showProfile) {
            PublicProfileView(account: account, username: username) { showProfile = false }
        }
        .tavernConfirmation(active: true, title: String(localized: "Block \(username)?"),
                            message: String(localized: "They're removed from your friends and this conversation closes. You can unblock them in Friends later."),
                            isPresented: $confirmBlock,
                            actions: [TavernDialogAction(title: String(localized: "Block"), destructive: true) {
                                Task { await account.block(username); close() }
                            }])
    }

    // MARK: Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if hasMore {
                        Button {
                            Task { await loadEarlier() }
                        } label: {
                            Label(String(localized: "Earlier messages"), systemImage: "arrow.up.circle")
                        }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                        .disabled(loadingEarlier)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("conversation.earlier")
                    }
                    if !loaded {
                        SocialWaiting(text: String(localized: "Opening your messages…")).padding(.top, 40)
                    } else if let failure, messages.isEmpty {
                        Label(failure, systemImage: "wifi.exclamationmark")
                            .font(.system(size: 14, weight: .semibold, design: .serif))
                            .modifier(TavernLeatherCard())
                            .accessibilityIdentifier("conversation.error")
                    } else if messages.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 30)).foregroundStyle(BrandTheme.brassGradient)
                            Text(String(localized: "Say hello to \(username). Messages stay between you two."))
                                .font(.system(size: 14, design: .serif)).multilineTextAlignment(.center).opacity(0.8)
                        }
                        .padding(.top, 40)
                        .accessibilityIdentifier("conversation.empty")
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || startsNewDay(message, after: messages[index - 1]) {
                            Text(message.sentAt.formatted(.dateTime.weekday(.wide).month().day()))
                                .font(.system(size: 11, weight: .heavy, design: .serif)).tracking(0.8).opacity(0.55)
                                .padding(.top, 10)
                        }
                        bubble(message, isLastMine: message.fromMe && message.id == messages.last(where: \.fromMe)?.id)
                            .id(message.id)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("conversation.transcript")
            .onChange(of: messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private func bubble(_ message: FriendMessage, isLastMine: Bool) -> some View {
        VStack(alignment: message.fromMe ? .trailing : .leading, spacing: 2) {
            Text(FriendMessageRules.shown(message))
                .font(.system(size: 15, design: .serif))
                .foregroundStyle(message.fromMe ? Color(red: 0.16, green: 0.08, blue: 0.03) : ArenaMenuStyle.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if message.fromMe {
                        RoundedRectangle(cornerRadius: 14).fill(BrandTheme.brassGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.1))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(message.fromMe ? 0 : 0.6))
                .shadow(color: .black.opacity(0.4), radius: 3, y: 2)
                .textSelection(.enabled)
            HStack(spacing: 4) {
                Text(message.sentAt.formatted(date: .omitted, time: .shortened))
                if isLastMine, message.read { Text("· " + String(localized: "Read")) }
            }
            .font(.system(size: 10, design: .serif)).opacity(0.55)
        }
        .frame(maxWidth: .infinity, alignment: message.fromMe ? .trailing : .leading)
        .padding(message.fromMe ? .leading : .trailing, 48)
        .accessibilityElement(children: .combine)
        .accessibilityLabel((message.fromMe ? String(localized: "You") : username) + ": " + FriendMessageRules.shown(message))
        .accessibilityIdentifier("conversation.message.\(message.id)")
    }

    private func startsNewDay(_ message: FriendMessage, after previous: FriendMessage) -> Bool {
        !Calendar.current.isDate(message.sentAt, inSameDayAs: previous.sentAt)
    }

    // MARK: Composer

    private var composer: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Self.quickReplies, id: \.self) { reply in
                        Button { send(reply) } label: {
                            Text(reply).font(.system(size: 12, weight: .heavy, design: .serif))
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .background(Capsule().fill(Color.black.opacity(0.5)))
                                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.7))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(sending)
                        .accessibilityIdentifier("conversation.quick.\(reply)")
                    }
                }
                .padding(.horizontal, 16)
            }
            HStack(spacing: 8) {
                TextField("", text: $draft, prompt: Text(String(localized: "Message \(username)")).foregroundStyle(ArenaMenuStyle.dim), axis: .vertical)
                    .lineLimit(1...4)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send(draft) }
                    .modifier(TavernFieldChrome(tavern: true))
                    .accessibilityIdentifier("conversation.field")
                Button { send(draft) } label: {
                    Image(systemName: "paperplane.fill").font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color(red: 1, green: 0.91, blue: 0.66))
                        .frame(width: 46, height: 46)
                        .background { TavernFill(material: .ember).clipShape(Circle()).padding(2) }
                        .overlay { TavernCapsuleRim().clipShape(Circle()) }
                }
                .buttonStyle(.plain)
                .disabled(sending || FriendMessageRules.sanitize(draft) == nil)
                .accessibilityLabel(String(localized: "Send"))
                .accessibilityIdentifier("conversation.send")
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.6) }
    }

    private var menu: some View {
        TavernMenu(arrowEdge: .top) {
            TavernMenuItem(title: String(localized: "View profile"), systemImage: "person.crop.circle") { showProfile = true }
            TavernMenuItem(title: String(localized: "Report \(username)"), systemImage: "exclamationmark.bubble") {
                let lastTheirs = messages.last(where: { !$0.fromMe })?.body
                Task { await account.report(username, message: lastTheirs, context: "message") }
            }
            TavernMenuItem(title: String(localized: "Block"), systemImage: "hand.raised", destructive: true) { confirmBlock = true }
        } label: {
            Image(systemName: "ellipsis").font(.system(size: 17, weight: .black)).foregroundStyle(BrandTheme.brassGradient)
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel(String(localized: "More about \(username)"))
        .accessibilityIdentifier("conversation.more")
    }

    // MARK: Loading and sending

    private func refresh() async {
        do {
            let page = try await account.thread(with: username)
            withAnimation(.easeOut(duration: 0.2)) {
                // The newest page replaces what it covers; earlier pages the player loaded stay.
                messages = FriendMessageRules.merged(messages, page.messages)
                if !loaded { hasMore = page.hasMore }
                loaded = true
                failure = nil
            }
        } catch {
            guard !Task.isCancelled else { return }
            loaded = true
            failure = PlayerAccountRules.message(for: SupabaseLite.code(of: error))
        }
    }

    private func loadEarlier() async {
        guard let first = messages.first else { return }
        loadingEarlier = true
        defer { loadingEarlier = false }
        if let page = try? await account.thread(with: username, before: first.id) {
            messages = FriendMessageRules.merged(messages, page.messages)
            hasMore = page.hasMore
        }
    }

    private func send(_ text: String) {
        guard !sending, FriendMessageRules.sanitize(text) != nil else { return }
        sending = true
        let previous = draft
        if text == draft { draft = "" }
        GameAudio.shared.play(.uiTap)
        Task {
            if let sent = await account.sendMessage(to: username, text) {
                withAnimation(.easeOut(duration: 0.2)) { messages = FriendMessageRules.merged(messages, [sent]) }
            } else if text == previous {
                draft = previous
            }
            sending = false
        }
    }
}

// MARK: - Messages list and hub

/// The Messages list: friends you've written to by their last message (newest first, unread counts in ember), then
/// friends you haven't written to yet. Shown in Friends and, through FriendMessagesHub, from the game menu.
struct FriendMessagesList: View {
    @ObservedObject var account: PlayerAccount
    let open: (String) -> Void
    @State private var conversations: [MessageConversation] = []
    @State private var loaded = false

    var body: some View {
        let friends = account.friends.filter(\.isFriend)
        let rows = FriendMessageRules.ordered(friends: friends.map(\.username), conversations: conversations)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                ArenaCaps(text: String(localized: "Messages"))
                Spacer(minLength: 6)
                if account.unreadMessages > 0 {
                    Text(String(localized: "\(account.unreadMessages) unread")).font(ArenaMenuStyle.font(11, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
                }
            }
            .padding(.top, 4)
            if !account.messagesAvailable {
                ProfileEmptyNote(text: String(localized: "Messages arrive with the next server update."), systemImage: "hourglass")
            } else if friends.isEmpty {
                ProfileEmptyNote(text: String(localized: "Add a friend to start a conversation. Messages stay between the two of you."),
                                 systemImage: "bubble.left.and.bubble.right.fill")
            } else if !loaded {
                SocialWaiting(text: String(localized: "Opening your messages…"))
            } else {
                ForEach(rows, id: \.name) { row in
                    let friend = friends.first { $0.username == row.name }
                    Button {
                        GameAudio.shared.play(.uiOpen)
                        open(row.name)
                    } label: {
                        SocialRowCard {
                            SocialPlayerHeading(username: row.name, commander: nil, line: line(row.conversation),
                                                online: friend?.online, rank: account.friendRanks[row.name], compact: true)
                        }
                        .overlay(alignment: .topTrailing) {
                            if let unread = row.conversation?.unread, unread > 0 {
                                Text("\(unread)")
                                    .font(.system(size: 11, weight: .black)).monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7).frame(minWidth: 22, minHeight: 22)
                                    .background(ArenaMenuStyle.ember, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(0.4), lineWidth: 1))
                                    .offset(x: 4, y: -6)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(BrandPressStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(accessibility(row.name, row.conversation))
                    .accessibilityIdentifier("messages.row.\(row.name)")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("messages.list")
        .task {
            while !Task.isCancelled {
                if let list = await account.conversations() { conversations = list }
                loaded = true
                try? await Task.sleep(nanoseconds: 10_000_000_000)
            }
        }
    }

    private func line(_ conversation: MessageConversation?) -> String {
        guard let last = conversation?.last else { return String(localized: "Say hello") }
        let text = FriendMessageRules.shown(last)
        return last.fromMe ? String(localized: "You: \(text)") : text
    }

    private func accessibility(_ name: String, _ conversation: MessageConversation?) -> String {
        guard let conversation else { return String(localized: "\(name), no messages yet") }
        let unread = conversation.unread > 0 ? String(localized: ", \(conversation.unread) unread") : ""
        return "\(name)\(unread), \(line(conversation))"
    }
}

/// Messages on a sheet: the list, then a conversation in its place. Opened from the game menu and from the new-message
/// banner during a game.
struct FriendMessagesHub: View {
    @ObservedObject var account: PlayerAccount
    var initial: String? = nil
    @State private var open: String?
    @State private var started = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let open {
                FriendConversationView(account: account, username: open) { self.open = nil }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        TavernPanelTitle(text: String(localized: "Messages")).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        Button { dismiss() } label: { TavernSealLabel() }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(localized: "Done"))
                            .accessibilityIdentifier("messages.done")
                    }
                    .modifier(TavernTitleBar())
                    .padding(.horizontal, 16).padding(.top, 12)
                    ScrollView {
                        FriendMessagesList(account: account) { open = $0 }
                            .padding(16)
                            .frame(maxWidth: 640)
                            .frame(maxWidth: .infinity)
                    }
                }
                .background(TavernSheetBackground())
                .environment(\.tavernBoard, true)
                .preferredColorScheme(.dark)
                .foregroundStyle(TavernPalette.parchment)
            }
        }
        .onAppear {
            guard !started else { return }
            started = true
            open = initial
        }
    }
}

/// Friend messages for views that don't hold the account (the game menu): the unread count and the hub to open.
struct FriendMessagesEntry {
    let unread: Int
    let hub: () -> AnyView
}

private struct FriendMessagesKey: EnvironmentKey { static let defaultValue: FriendMessagesEntry? = nil }

extension EnvironmentValues {
    var friendMessages: FriendMessagesEntry? {
        get { self[FriendMessagesKey.self] }
        set { self[FriendMessagesKey.self] = newValue }
    }
}

/// A friend's new message during a game: a small banner at the top; a tap opens the conversation.
struct FriendMessageBanner: View {
    let name: String
    let text: String
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.system(size: 13, weight: .black, design: .serif))
                Text(text).font(.system(size: 12, design: .serif)).lineLimit(1).opacity(0.85)
            }
            Spacer(minLength: 4)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .black)).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
        .background(Capsule().fill(Color.black.opacity(0.5)))
        .overlay(TavernCapsuleRim(thin: true))
        .shadow(color: .black.opacity(0.6), radius: 8, y: 4)
        .frame(maxWidth: 420)
        .contentShape(Capsule())
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(String(localized: "New message from \(name): \(text)"))
        .accessibilityHint(String(localized: "Opens the conversation"))
        .accessibilityIdentifier("messages.banner")
    }
}
