import SwiftUI

/// Badges in memory, over BadgeArtStore's copies on the phone.
@MainActor
enum BadgeImages {
    /// The small copies are 192 px, sharp up to this size on a phone.
    static let smallUpTo: CGFloat = 64
    private static let memory = NSCache<NSString, UIImage>()

    private static func key(_ url: URL, small: Bool) -> NSString { "\(small):\(url.absoluteString)" as NSString }

    /// Right now, for a view's first frame: from memory or the phone, never the network.
    static func ready(_ url: URL, small: Bool = true) -> UIImage? {
        if let image = memory.object(forKey: key(url, small: small)) { return image }
        guard let data = BadgeArtStore.shared.stored(url, small: small), let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key(url, small: small))
        return image
    }

    static func load(_ url: URL, small: Bool = true) async -> UIImage? {
        if let image = ready(url, small: small) { return image }
        await BadgeArtStore.shared.refresh(url, small: small)
        return ready(url, small: small)
    }

    /// Fills the phone's copies ahead of time. A coin that changed shows on its next load.
    static func prefetch(_ urls: [URL], small: Bool = true) async {
        for url in await BadgeArtStore.shared.prefetch(Array(Set(urls)), small: small) {
            memory.removeObject(forKey: key(url, small: small))
        }
    }
}

/// A badge's art, or `placeholder` until there is any. A big one starts from the small copy, then sharpens.
struct BadgeImage<Placeholder: View>: View {
    let url: URL?
    var large = false
    var earned = true
    @ViewBuilder var placeholder: () -> Placeholder
    @State private var loaded: (url: URL, image: UIImage)?

    private var shown: UIImage? {
        if let loaded, loaded.url == url { return loaded.image }
        return url.flatMap { BadgeImages.ready($0) }
    }

    var body: some View {
        Group {
            if let shown {
                Image(uiImage: shown).resizable().scaledToFit().saturation(earned ? 1 : 0).opacity(earned ? 1 : 0.32)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else { return }
            if let image = await BadgeImages.load(url) { loaded = (url, image) }
            if large, let image = await BadgeImages.load(url, small: false) { loaded = (url, image) }
        }
    }
}

/// An award's art, or a star medal in its tint when it has none or it can't load.
struct AwardMedal: View {
    let award: Award
    var size: CGFloat = 60

    var body: some View {
        BadgeImage(url: award.imageURL, large: size > BadgeImages.smallUpTo) { drawn }
        .frame(width: size, height: size)
        .shadow(color: award.rarity > 1 ? award.tint.opacity(award.rarity == 3 ? 0.8 : 0.45) : .clear, radius: size * (award.rarity == 3 ? 0.2 : 0.12))
        // Flattened once, with room for the glow: a shadow on a picture is otherwise worked out again every frame it scrolls.
        .padding(size * 0.3)
        .drawingGroup()
        .padding(-size * 0.3)
        .accessibilityHidden(true)
    }

    private var drawn: some View {
        let metal = LinearGradient(colors: [Color(red: 1, green: 0.93, blue: 0.68), Award.gold, Color(red: 0.55, green: 0.36, blue: 0.12)],
                                   startPoint: .top, endPoint: .bottom)
        return ZStack {
            Circle().fill(RadialGradient(colors: [award.tint, award.tint.opacity(0.45), .black], center: .center, startRadius: 0, endRadius: size * 0.56))
            Circle().strokeBorder(award.rarity == 3 ? AnyShapeStyle(metal) : AnyShapeStyle(award.tint.opacity(0.8)), lineWidth: size * 0.05)
            Image(systemName: "star.fill").font(.system(size: size * 0.44, weight: .black)).foregroundStyle(metal)
        }
    }
}

/// A row of awards, best first. Tapping one opens it.
struct AwardShelf: View {
    let awards: [Award]
    var size: CGFloat = 60
    @State private var open: Award?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(awards) { award in
                    Button { GameAudio.shared.play(.uiOpen); open = award } label: {
                        VStack(spacing: size * 0.08) {
                            AwardMedal(award: award, size: size)
                            Text(award.name).font(ArenaMenuStyle.font(max(10, size * 0.18), .semibold)).multilineTextAlignment(.center)
                                .lineLimit(2).minimumScaleFactor(0.8)
                        }
                        .frame(width: size * 1.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(award.name)
                    .accessibilityHint(award.detail)
                    .accessibilityIdentifier("award.\(award.id)")
                }
            }
            .padding(.horizontal, 2).padding(.vertical, size * 0.1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("awards")
        .fullScreenCover(item: $open) { award in
            AwardCeremony(award: award) { open = nil }.presentationBackground(.clear)
        }
    }
}

/// One award, large: over the menu when it is new, or opened from a shelf. Only Continue closes it.
struct AwardCeremony: View {
    let award: Award
    var isNew = false
    let close: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 12) {
                Spacer(minLength: 0)
                if isNew { ArenaCaps(text: String(localized: "New award")) }
                AwardMedal(award: award, size: 170).scaleEffect(shown ? 1 : 0.6).opacity(shown ? 1 : 0).padding(.vertical, 14)
                Text(award.name).font(.system(size: 28, weight: .black, design: .serif)).multilineTextAlignment(.center)
                    .foregroundStyle(LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.62), award.tint], startPoint: .top, endPoint: .bottom))
                    .accessibilityAddTraits(.isHeader)
                if !award.detail.isEmpty {
                    Text(award.detail).font(ArenaMenuStyle.font(15, .medium)).foregroundStyle(ArenaGlass.text).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !award.caption.isEmpty {
                    Text(award.caption).font(ArenaMenuStyle.font(12, .semibold)).foregroundStyle(ArenaMenuStyle.dim).multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
                Button { GameAudio.shared.play(.uiClose); close() } label: { Text(String(localized: "Continue")).frame(minWidth: 180) }
                    .buttonStyle(ArenaButtonStyle(kind: .primary, fontSize: 18))
                    .accessibilityIdentifier("award.ceremony.continue")
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("award.ceremony")
        .task {
            if isNew { GameAudio.shared.play(.victory, volume: 0.6) }
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.5, dampingFraction: 0.6)) { shown = true }
        }
    }
}

/// Keeps the player's awards fresh on the menu and opens a new one there, never over a game.
struct AwardCeremonyHost: ViewModifier {
    @ObservedObject var account: PlayerAccount
    /// A game, or anything else that must not be covered.
    let busy: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if !busy, let award = account.awards.first(where: { !$0.seen }) {
                    AwardCeremony(award: award, isNew: true) { account.markAwardSeen(award) }.id(award.id).transition(.opacity)
                }
            }
            .task(id: "\(account.phase == .ready)|\(busy)") { if !busy { await account.refreshAwards() } }
    }
}
