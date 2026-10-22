import SwiftUI

/// What a deck box shows: its name, commander and colours, and a line about it for VoiceOver (its bracket).
struct ArenaDeckBoxModel: Identifiable, Equatable {
    /// The deck's selection id ("precon:…", "included:…", "local:…").
    let id: String
    let name: String
    let commander: String?
    let colors: [String]
    let subtitle: String
    /// A word on the box's corner ("PLAYING", "FIX").
    var tag: String? = nil
}

/// A deck as Arena's deck box (Caleb, 2026-10-22: "very similar to how Magic Arena does it"): a black box seen almost
/// straight on, the commander's art on its front under a lid band stamped with the name, a dark side with a clasp, the
/// colours just above a black name plate and never under it. Choosing the deck opens the box: the lid lifts, the front
/// folds down to half height and the commander card rises out in front of the deck's card backs.
struct ArenaDeckBox: View {
    let deck: ArenaDeckBoxModel
    var selected = false
    var width: CGFloat = 120
    /// The plate's pencil: open the deck in Deck Studio.
    var edit: (() -> Void)? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var openness: CGFloat = 0

    var body: some View {
        let g = ArenaBoxGeometry(width: width)
        VStack(spacing: 0) {
            ArenaBoxBody(geometry: g, openness: openness, colors: deck.colors) {
                ArenaArt(name: deck.commander ?? "", colors: deck.colors)
            } inside: {
                ArenaBoxContents(geometry: g, commander: deck.commander, colors: deck.colors)
            }
            .overlay(alignment: .topLeading) {
                // On a shut box only: an open one shows its cards, and the chosen deck says so beside the boxes.
                if let tag = deck.tag, openness < 0.05 {
                    Text(tag)
                        .font(ArenaMenuStyle.font(8.5, .heavy)).tracking(0.8)
                        .foregroundStyle(ArenaMenuStyle.gold)
                        .padding(.horizontal, 5).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.78)))
                        .padding(.leading, 5)
                        .padding(.top, g.top + g.lidBand + 4 + g.cut * openness)
                }
            }
            ArenaNamePlate(title: deck.name, selected: selected, width: width, edit: edit)
                .padding(.top, -g.plateOverlap)
        }
        .frame(width: width)
        .onAppear { openness = selected ? 1 : 0 }
        .onChange(of: selected) { _, isSelected in
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.74)) { openness = isSelected ? 1 : 0 }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(deck.commander.map { "\(deck.name), \($0)" } ?? deck.name)
        .accessibilityValue(deck.subtitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}

/// Arena's "+" tile for a new deck: a dark rounded square with a glowing plus, as tall as a deck box.
struct ArenaNewDeckBox: View {
    var width: CGFloat = 120

    var body: some View {
        let g = ArenaBoxGeometry(width: width)
        ZStack {
            RoundedRectangle(cornerRadius: width * 0.07, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.14, green: 0.135, blue: 0.15), Color(red: 0.06, green: 0.06, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: width * 0.07, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            Image(systemName: "plus")
                .font(.system(size: width * 0.36, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.93, blue: 1))
                .shadow(color: Color(red: 0.62, green: 0.52, blue: 1).opacity(0.9), radius: 7)
                .shadow(color: Color(red: 0.62, green: 0.52, blue: 1).opacity(0.5), radius: 16)
        }
        .frame(width: width - g.side * 0.5, height: g.boxHeight + g.plateHeight - g.plateOverlap)
        .frame(width: width)
        .shadow(color: .black.opacity(0.6), radius: 6, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "New deck"))
    }
}

/// The box's proportions from the reference: the front 1.34 times as wide as tall, a narrow side, a thin top.
struct ArenaBoxGeometry {
    let width: CGFloat
    var side: CGFloat { width * 0.095 }
    var top: CGFloat { width * 0.035 }
    var frontWidth: CGFloat { width - side }
    var frontHeight: CGFloat { frontWidth / 1.34 }
    var boxHeight: CGFloat { top + frontHeight }
    /// The lid's front edge across the top of the front.
    var lidBand: CGFloat { frontHeight * 0.1 }
    /// How far the front folds down when the box opens.
    var cut: CGFloat { frontHeight * 0.48 }
    /// How far the lid and the back rise when the box opens.
    var rise: CGFloat { frontHeight * 0.36 }
    var plateHeight: CGFloat { max(24, width * 0.17) }
    var plateOverlap: CGFloat { width * 0.05 }
    var pip: CGFloat { max(13, width * 0.115) }
}

/// The box: back wall, lid, what's inside, the front and the side, drawn for `openness` 0 (shut) to 1 (open).
private struct ArenaBoxBody<Art: View, Inside: View>: View {
    let geometry: ArenaBoxGeometry
    let openness: CGFloat
    let colors: [String]
    @ViewBuilder let art: () -> Art
    @ViewBuilder let inside: () -> Inside

    var body: some View {
        let g = geometry
        let rise = g.rise * openness
        let frontTop = g.top + g.lidBand + (g.cut - g.lidBand) * openness
        ZStack(alignment: .topLeading) {
            // The back wall: the box's dark inside, seen once the lid is up.
            UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.10, green: 0.10, blue: 0.11), Color(red: 0.02, green: 0.02, blue: 0.025)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: g.width - g.side * 0.5, height: g.boxHeight - g.top + rise)
                .offset(x: g.side * 0.5, y: -rise)
                .opacity(Double(min(1, openness * 3)))
            // Shut: the lid's top and its front band, stamped like Arena's. Open: the band gives way to the lid
            // standing raised and tilted back on the back wall, the deck's art on its top.
            ArenaBoxLid(geometry: g, art: art)
                .opacity(Double(max(0, 1 - openness * 2)))
            art()
                .frame(width: g.frontWidth, height: g.frontHeight * 0.34)
                .clipped()
                .overlay(Color.black.opacity(0.38))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.85)).frame(height: 2) }
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.25)).frame(height: 1) }
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0, z: 0), anchor: .bottom, perspective: 0.55)
                .offset(x: g.side * 0.5, y: -rise - g.frontHeight * 0.34 + 1)
                .opacity(Double(openness))
            // The deck itself, risen out of the box when open.
            inside()
                .offset(y: (1 - openness) * g.frontHeight * 0.55)
                .opacity(Double(min(1, openness * 2.5)))
            // The front: the art below the lid, folding down to half height as the box opens.
            ZStack(alignment: .bottom) {
                art()
                    .frame(width: g.frontWidth, height: g.frontHeight)
                LinearGradient(stops: [.init(color: .clear, location: 0.5), .init(color: .black.opacity(0.6), location: 1)],
                               startPoint: .top, endPoint: .bottom)
                ArenaPips(colors: colors, size: g.pip)
                    .padding(.bottom, g.plateOverlap + g.width * 0.025)
            }
            .frame(width: g.frontWidth, height: g.frontHeight)
            .mask(alignment: .bottom) {
                Rectangle().frame(height: g.boxHeight - frontTop)
            }
            // The folded edge of the open front: a lit lip with its shadow under it.
            .overlay(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 3)
                    LinearGradient(colors: [Color.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 5)
                }
                .padding(.top, frontTop - g.top)
                .opacity(Double(openness))
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 3, bottomTrailingRadius: 2, style: .continuous))
            .offset(y: g.top)
            // The right side with its clasp, following the lid up.
            ArenaBoxSide(openness: openness, cut: g.cut, rise: g.rise, top: g.top)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.13, blue: 0.14), Color(red: 0.03, green: 0.03, blue: 0.035)],
                                     startPoint: .leading, endPoint: .trailing))
                .frame(width: g.side, height: g.boxHeight)
                .overlay {
                    Capsule().fill(Color.black.opacity(0.75))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
                        .frame(width: g.side * 0.24, height: g.frontHeight * 0.34)
                        .offset(x: -g.side * 0.04, y: g.frontHeight * 0.16)
                }
                .offset(x: g.frontWidth)
        }
        .frame(width: g.width, height: g.boxHeight, alignment: .topLeading)
        .shadow(color: .black.opacity(0.65), radius: 6, y: 5)
    }
}

/// The lid: its thin top face and the black band across the front with the MagicMobile stamp.
private struct ArenaBoxLid<Art: View>: View {
    let geometry: ArenaBoxGeometry
    @ViewBuilder let art: () -> Art

    var body: some View {
        let g = geometry
        ZStack(alignment: .topLeading) {
            ArenaBoxTop(side: g.side)
                .fill(LinearGradient(colors: [Color(red: 0.22, green: 0.22, blue: 0.23), Color(red: 0.09, green: 0.09, blue: 0.10)],
                                     startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.22)).frame(height: 1) }
                .frame(width: g.width, height: g.top)
            ZStack {
                LinearGradient(colors: [Color(red: 0.11, green: 0.11, blue: 0.12), Color(red: 0.04, green: 0.04, blue: 0.045)],
                               startPoint: .top, endPoint: .bottom)
                Text("MAGICMOBILE")
                    .font(.system(size: max(5, g.lidBand * 0.62), weight: .heavy, design: .serif))
                    .tracking(g.lidBand * 0.18)
                    .foregroundStyle(Color(red: 0.42, green: 0.41, blue: 0.40))
                    .shadow(color: .black, radius: 0, y: -0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, g.frontWidth * 0.18)
            }
            .frame(width: g.frontWidth, height: g.lidBand)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.black.opacity(0.8)).frame(height: 1) }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 2.5, style: .continuous))
            .offset(y: g.top)
        }
        .frame(width: g.width, height: g.top + g.lidBand, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

/// What stands in the open box: three card backs, and the commander card in front of them.
private struct ArenaBoxContents: View {
    let geometry: ArenaBoxGeometry
    let commander: String?
    let colors: [String]

    var body: some View {
        let g = geometry
        let height = g.frontHeight * 1.12
        let cardWidth = height * 0.716
        ZStack(alignment: .top) {
            // Two backs fanned behind the commander, one to each side of it, and one standing behind.
            ForEach([(-0.30, -7.0), (0.16, 5.0), (0.30, 9.0)], id: \.0) { offset, angle in
                ArenaCardBack()
                    .frame(width: cardWidth * 0.92, height: height * 0.92)
                    .rotationEffect(.degrees(angle), anchor: .bottom)
                    .offset(x: g.frontWidth * offset, y: 3)
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
            }
            NativeCardArtworkView(name: commander ?? "", variant: .board, contentMode: .fit) { _, _ in
                ArenaColorGlass(colors: colors)
                    .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.05))
            }
            .frame(width: cardWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: cardWidth * 0.05))
            .rotationEffect(.degrees(-4), anchor: .bottom)
            .offset(x: -g.frontWidth * 0.12, y: -g.rise * 0.1)
            .shadow(color: .black.opacity(0.7), radius: 4, y: 2)
        }
        .frame(width: g.frontWidth, height: height, alignment: .top)
        .offset(x: g.side * 0.5, y: g.top + g.lidBand * 0.5 - g.rise)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The box's thin top: a parallelogram running back and to the right.
private struct ArenaBoxTop: Shape {
    let side: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.maxY))
        path.addLine(to: CGPoint(x: side, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX - side, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The right side: its front edge drops with the folding front, its back edge rises with the lid.
private struct ArenaBoxSide: Shape {
    var openness: CGFloat
    let cut: CGFloat
    let rise: CGFloat
    let top: CGFloat

    var animatableData: CGFloat {
        get { openness }
        set { openness = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: top + cut * openness))
        path.addLine(to: CGPoint(x: rect.maxX, y: -rise * openness))
        // The far edge a little shorter than the near one: the side recedes.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - top * 2.2))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The plate under a deck box: black, the name on one line (cut short with an ellipsis), and Arena's pencil.
struct ArenaNamePlate: View {
    let title: String
    var selected = false
    var width: CGFloat
    var edit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(ArenaMenuStyle.font(max(11, width * 0.098), .bold))
                .foregroundStyle(Color.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity)
            if let edit {
                Button(action: edit) {
                    Image(systemName: "pencil")
                        .font(.system(size: max(10, width * 0.085), weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Edit \(title)"))
            }
        }
        .padding(.leading, edit == nil ? 8 : 10)
        .padding(.trailing, edit == nil ? 8 : 2)
        .frame(width: width, height: ArenaBoxGeometry(width: width).plateHeight)
        .background(Capsule().fill(Color.black.opacity(0.92)))
        .overlay(Capsule().strokeBorder(selected ? AnyShapeStyle(Color(red: 1, green: 0.88, blue: 0.56)) : AnyShapeStyle(Color.white.opacity(0.1)),
                                        lineWidth: selected ? 1.4 : 0.8))
        .shadow(color: selected ? Color(red: 1, green: 0.78, blue: 0.36).opacity(0.55) : .clear, radius: 6)
    }
}

/// A deck's colours as mana symbols, W U B R G order; colourless when it has none.
struct ArenaPips: View {
    let colors: [String]
    var size: CGFloat = 15

    var body: some View {
        HStack(spacing: 2) {
            let shown = ["W", "U", "B", "R", "G"].filter(colors.contains)
            if shown.isEmpty {
                ManaSymbolView(symbol: "C", size: size)
            } else {
                ForEach(shown, id: \.self) { ManaSymbolView(symbol: $0, size: size) }
            }
        }
        // Arena's pips are saturated; Scryfall's symbols are pale.
        .saturation(1.9)
        .shadow(color: .black.opacity(0.8), radius: 1.5, y: 1)
        .accessibilityHidden(true)
    }
}
