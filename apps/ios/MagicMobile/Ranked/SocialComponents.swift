import SwiftUI

/// The small pieces the friends panel and public profiles share, in Arena's glass and gold.

/// A notice that floats at the bottom: a leather capsule in brass. Tap to dismiss.
struct SocialNotice: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            Text(text)
                .font(ArenaMenuStyle.font(13, .heavy))
                .foregroundStyle(Color(red: 1, green: 0.91, blue: 0.66))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 18).padding(.vertical, 10)
                .frame(minHeight: 44)
                .background {
                    Capsule().fill(Color.black.opacity(0.55)).padding(1.5)
                }
                .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
                .shadow(color: .black.opacity(0.6), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20).padding(.bottom, 10)
        .accessibilityLabel(text)
        .accessibilityHint(String(localized: "Dismisses this message"))
        .accessibilityIdentifier("friends.notice")
    }
}

/// A line of waiting, drawn without a system spinner: three gold pips that breathe in turn.
struct SocialWaiting: View {
    let text: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { index in
                        Circle().fill(ArenaMenuStyle.gold)
                            .frame(width: 7, height: 7)
                            .opacity(reduceMotion ? 0.8 : 0.35 + 0.65 * (0.5 + 0.5 * sin(t * 4 - Double(index) * 0.9)))
                    }
                }
            }
            Text(text).font(ArenaMenuStyle.font(13, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A player's name in a list: their commander's art in a ring (a dot for who is online), the name, a line under it, and
/// their rank. `compact` is the one-line row of Arena's social panel: a smaller picture and the rank's emblem alone.
struct SocialPlayerHeading: View {
    let username: String
    var commander: String?
    var line: String
    var online: Bool?
    var rank: RankPosition?
    var title: String?
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 10 : 12) {
            ZStack(alignment: .bottomTrailing) {
                CommanderArtMedallion(name: commander, diameter: compact ? 32 : 40).frame(width: compact ? 40 : 52, height: compact ? 40 : 52)
                if let online {
                    Circle().fill(online ? Color(red: 0.4, green: 0.85, blue: 0.4) : Color.gray.opacity(0.6)).frame(width: compact ? 10 : 12, height: compact ? 10 : 12)
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.7), lineWidth: 1.5))
                        .accessibilityHidden(true)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(username).font(ArenaMenuStyle.font(compact ? 15 : 16, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    .lineLimit(1).minimumScaleFactor(0.75)
                Text(line).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim).lineLimit(1)
            }
            Spacer(minLength: 6)
            if compact {
                Group {
                    if let rank { RankEmblem(tier: rank.tier, size: 24) }
                    else { Image(systemName: "shield.lefthalf.filled").font(.system(size: 15, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold.opacity(0.4)) }
                }
                .frame(width: 28)
                .accessibilityHidden(true)
            } else {
                VStack(spacing: 0) {
                    if let rank {
                        RankEmblem(tier: rank.tier, size: 34)
                        Text(rank.title).font(ArenaMenuStyle.font(10, .heavy)).lineLimit(1).minimumScaleFactor(0.7)
                    } else {
                        Image(systemName: "shield.lefthalf.filled").font(.system(size: 20, weight: .bold)).foregroundStyle(ArenaMenuStyle.gold.opacity(0.4))
                            .frame(width: 34, height: 34)
                        Text(String(localized: "Unranked")).font(ArenaMenuStyle.font(10, .semibold)).foregroundStyle(ArenaMenuStyle.dim)
                    }
                }
                .frame(width: 62)
                .accessibilityHidden(true)
            }
        }
        .frame(minHeight: compact ? 48 : 56)
        .contentShape(Rectangle())
    }
}

/// One player or one request in a list: a dark glass row edged with the hairline.
struct SocialRowCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.32)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 0.8).opacity(0.6))
    }
}

extension PlayerSearchResult {
    func with(relation: String) -> PlayerSearchResult {
        PlayerSearchResult(username: username, favoriteCommander: favoriteCommander, season: season, rankStep: rankStep, pips: pips,
                           visibility: visibility, relation: relation, online: relation == "friend" ? online : nil)
    }
}
