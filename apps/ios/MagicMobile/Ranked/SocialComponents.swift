import SwiftUI

/// The small pieces the friends sheet and public profiles share, in the tavern's leather and brass.

/// A notice that floats at the bottom: a leather capsule in brass. Tap to dismiss.
struct SocialNotice: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Text(text)
                .font(.system(size: 13, weight: .heavy, design: .serif))
                .foregroundStyle(Color(red: 1, green: 0.91, blue: 0.66))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background {
                    TavernFill(material: .leather).overlay(Color.black.opacity(0.25)).clipShape(Capsule()).padding(1.5)
                }
                .overlay { TavernCapsuleRim(thin: true) }
                .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 10)
        .accessibilityLabel(text)
        .accessibilityHint(String(localized: "Dismisses this message"))
        .accessibilityIdentifier("friends.notice")
    }
}

/// A line of waiting, drawn without a system spinner: three brass pips that breathe in turn.
struct SocialWaiting: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle().fill(BrandTheme.brassGradient)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion ? 0.8 : 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4 - Double(index) * 0.9)))
                    }
                }
            }
            Text(text).font(.system(size: 13, weight: .semibold, design: .serif)).opacity(0.75)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A player's name in a list: their commander's art in a brass ring (a dot for who is online), the name, a line under it.
struct SocialPlayerHeading: View {
    let username: String
    var commander: String?
    var line: String
    var online: Bool?
    var rank: RankPosition?
    var title: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                CommanderArtMedallion(name: commander, diameter: 40).frame(width: 52, height: 52)
                if let online {
                    Circle().fill(online ? Color(red: 0.4, green: 0.85, blue: 0.4) : Color.gray.opacity(0.6)).frame(width: 12, height: 12)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 1.5))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(username).font(.system(size: 16, weight: .heavy, design: .serif)).lineLimit(1).minimumScaleFactor(0.75)
                Text(line).font(.system(size: 12, design: .serif)).opacity(0.7).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(spacing: 0) {
                if let rank {
                    RankEmblem(tier: rank.tier, size: 34)
                    Text(rank.title).font(.system(size: 10, weight: .heavy, design: .serif)).lineLimit(1).minimumScaleFactor(0.7)
                } else {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 20, weight: .bold)).foregroundStyle(TavernPalette.brass.opacity(0.5))
                        .frame(width: 34, height: 34)
                    Text(String(localized: "Unranked")).font(.system(size: 10, weight: .semibold, design: .serif)).opacity(0.55)
                }
            }
            .frame(width: 62)
            .accessibilityHidden(true)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}

/// A dark leather row card, for one player or one request in a list.
struct SocialRowCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.32)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(TavernPalette.brass.opacity(0.4), lineWidth: 1))
    }
}

extension PlayerSearchResult {
    func with(relation: String) -> PlayerSearchResult {
        PlayerSearchResult(username: username, favoriteCommander: favoriteCommander, season: season, rankStep: rankStep, pips: pips,
                           visibility: visibility, relation: relation, online: relation == "friend" ? online : nil)
    }
}
