import SwiftUI

/// The binder's own controls for everything in Deck Studio that the system would otherwise draw in the
/// phone's own style (Caleb, 2026-10-06: no top tabs or headers that look like the iPhone's; every piece
/// of text sits on the parchment or in one of our own parts). Each control is drawn and touched as our own
/// part, and VoiceOver and the UI tests see the system control it stands for (accessibilityRepresentation).
/// Android: studio/GrimoireBinder.kt.

/// An action on a leaf's head, drawn as a brass plaque.
struct BinderLeafAction {
    let title: String
    var identifier: String? = nil
    var disabled = false
    let action: () -> Void
}

/// The head of a loose leaf (a sheet): its name in the book's hand on the parchment over an inked rule,
/// with brass plaques for its actions, in place of the system navigation bar.
struct BinderLeafHead: View {
    let title: String
    var leading: BinderLeafAction? = nil
    var trailing: BinderLeafAction? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                plaque(leading).frame(minWidth: 90, alignment: .leading)
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(DeckStudioPalette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                plaque(trailing).frame(minWidth: 90, alignment: .trailing)
            }
            GrimoireRule()
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
        .background(GrimoirePaper().ignoresSafeArea(edges: .top))
    }

    @ViewBuilder private func plaque(_ item: BinderLeafAction?) -> some View {
        if let item {
            Button(item.title, action: item.action)
                .buttonStyle(BinderPlaqueButtonStyle())
                .disabled(item.disabled)
                .modifier(BinderIdentifier(identifier: item.identifier))
        } else {
            Color.clear.frame(width: 1, height: 44)
        }
    }
}

private struct BinderIdentifier: ViewModifier {
    let identifier: String?
    func body(content: Content) -> some View {
        if let identifier { content.accessibilityIdentifier(identifier) } else { content }
    }
}

extension View {
    /// A Deck Studio sheet as a loose leaf with the binder's own head instead of the system navigation bar.
    /// Apply it to the content inside the sheet's NavigationStack.
    func binderLeaf(_ title: String, leading: BinderLeafAction? = nil, trailing: BinderLeafAction? = nil) -> some View {
        toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) { BinderLeafHead(title: title, leading: leading, trailing: trailing) }
            .binderControls()
    }

    /// The binder's own switches and disclosures for every Toggle and DisclosureGroup inside.
    func binderControls() -> some View {
        toggleStyle(BinderToggleStyle()).disclosureGroupStyle(BinderDisclosureStyle())
    }
}

/// A switch in the tavern's brass (TavernSwitchFace) beside its label in ink. The whole row is one button;
/// VoiceOver and the UI tests see the system switch it stands for. (A nearly invisible system control laid
/// over the face did not take taps inside a form's rows.)
struct BinderToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 12) {
                configuration.label
                    .foregroundStyle(DeckStudioPalette.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                TavernSwitchFace(isOn: configuration.isOn)
                    .frame(width: 51, height: 31)
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}

/// A disclosure in the book's hand: its label in ink and a brass chevron that turns as it opens.
struct BinderDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { configuration.isExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    configuration.label.foregroundStyle(DeckStudioPalette.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).foregroundStyle(Binder.engraved)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Binder.brass)).overlay(Circle().stroke(Binder.brassDeep, lineWidth: 0.8))
                        .rotationEffect(.degrees(configuration.isExpanded ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}

/// A count with brass minus and plus coins, each a real button ("Decrease" and "Increase") inside one
/// element named for the count.
struct BinderStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, value: Binding<Int>, in range: ClosedRange<Int>) {
        self.title = title; _value = value; self.range = range
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(DeckStudioPalette.ink).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                coin("minus", active: value > range.lowerBound) { value = max(range.lowerBound, value - 1) }
                coin("plus", active: value < range.upperBound) { value = min(range.upperBound, value + 1) }
            }
            .frame(width: 94, height: 32)
        }
        .frame(minHeight: 44)
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func coin(_ symbol: String, active: Bool, step: @escaping () -> Void) -> some View {
        Button(action: step) {
            Image(systemName: symbol).font(.system(size: 12, weight: .black)).foregroundStyle(Binder.engraved)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Binder.brass))
                .overlay(Circle().stroke(Binder.brassDeep, lineWidth: 0.8))
                .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
                .opacity(active ? 1 : 0.45)
                .frame(width: 47, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!active)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
        .accessibilityIdentifier(symbol == "plus" ? "Increment" : "Decrement")
    }
}

/// A choice from a menu, shown as a brass plaque naming the current choice (in place of the system's
/// tinted menu button).
struct BinderMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        let current = options.first { $0.0 == selection }?.1 ?? title
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) }
            }
        } label: {
            BinderPlaque {
                HStack(spacing: 6) {
                    Text(current).font(.system(size: 14, weight: .heavy, design: .serif))
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold))
                }
            }
        }
        .accessibilityLabel(title).accessibilityValue(current)
    }
}

// MARK: - Tags, coins, notes and empty pages

/// A small tag in a thin brass rim on one of the kit's materials, in place of the system's tinted
/// capsules: the deck chosen for play is ember glass with Play's jewel; a deck check is leather with a
/// coloured jewel. It is sized exactly like the bracket's TavernTag beside it on a deck (Caleb, 2026-10-06:
/// the two must be the same height, and Playing no bigger).
struct BinderTag: View {
    let text: String
    var material: TavernFill.Material = .leather
    /// Play's ember jewel (the Meshy-made tavern-binder-jewel) before the words.
    var jewel = false
    /// A little coloured jewel that keeps a status's colour cue.
    var accent: Color? = nil
    private static let jewelArt = UIImage(named: "tavern-binder-jewel")

    var body: some View {
        HStack(spacing: 4) {
            if jewel, let art = Self.jewelArt {
                Image(uiImage: art).resizable().interpolation(.high).frame(width: 14, height: 14)
            } else if jewel {
                Image(systemName: "flame.fill").font(.system(size: 8, weight: .heavy))
            }
            if let accent {
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.9), accent, accent.opacity(0.6)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 5))
                    .frame(width: 8, height: 8)
                    .shadow(color: accent.opacity(0.9), radius: 3)
            }
            Text(text)
                .font(.system(size: 10, weight: .heavy, design: .serif)).tracking(0.8)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(ink)
        .padding(.leading, jewel ? 5 : 12).padding(.trailing, 12)
        .frame(minHeight: 22)
        .background { TavernFill(material: material).clipShape(Capsule()).padding(1.5) }
        .overlay { TavernCapsuleRim(thin: true) }
        .fixedSize()
    }

    private var ink: Color {
        switch material {
        case .ember: return Color(red: 1, green: 0.94, blue: 0.80)
        case .leather: return Color(red: 0.98, green: 0.82, blue: 0.48)
        case .parchment: return Color(red: 0.24, green: 0.12, blue: 0.05)
        }
    }
}

/// A small brass coin with an engraved symbol, in a full touch target: a deck's favourite star and ⋯.
/// `lit` fills the symbol with ember (a favourite).
struct BinderCoin<Label: View>: View {
    var lit = false
    var pressed = false
    @ViewBuilder var label: Label

    var body: some View {
        label
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(lit ? Color(red: 0.72, green: 0.20, blue: 0.06) : Binder.engraved)
            .shadow(color: lit ? TavernPalette.ember.opacity(0.8) : Binder.brassLight.opacity(0.7), radius: lit ? 2 : 0, y: lit ? 0 : 1)
            .frame(width: 30, height: 30)
            .background(Circle().fill(pressed ? Binder.brassPressed : Binder.brass))
            .overlay(Circle().inset(by: 2.5).stroke(Binder.brassDeep.opacity(0.55), lineWidth: 0.8))
            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.8))
            .shadow(color: .black.opacity(pressed ? 0.15 : 0.4), radius: pressed ? 1 : 2, y: pressed ? 0 : 1.5)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

struct BinderCoinButtonStyle: ButtonStyle {
    var lit = false
    func makeBody(configuration: Configuration) -> some View {
        BinderCoin(lit: lit, pressed: configuration.isPressed) { configuration.label }
    }
}

/// A chip that narrows what a page shows: dark leather in a thin brass rim, ember glass when chosen.
struct BinderChip: View {
    let title: String
    var icon: String? = nil
    var chosen = false

    var body: some View {
        HStack(spacing: 5) {
            if let icon { Image(systemName: icon).font(.system(size: 11, weight: .bold)) }
            Text(title).font(.system(size: 13, weight: .bold, design: .serif)).lineLimit(1)
        }
        .foregroundStyle(chosen ? Color(red: 1, green: 0.94, blue: 0.80) : Color(red: 0.98, green: 0.82, blue: 0.48))
        .shadow(color: .black.opacity(0.7), radius: 0, y: 1)
        .padding(.horizontal, 12).frame(minHeight: 32)
        .background { TavernFill(material: chosen ? .ember : .leather).clipShape(Capsule()).padding(1.5) }
        .overlay { TavernCapsuleRim(thin: true) }
        .shadow(color: .black.opacity(chosen ? 0.2 : 0.35), radius: chosen ? 1 : 2, y: chosen ? 0 : 1)
    }
}

/// Something to tell the player, written on the page: a brass-stamped symbol, a title in the book's hand
/// and a line beneath it.
struct BinderNote: View {
    let title: String
    let message: String
    var icon = "info.circle"

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            BinderStamp(icon: icon, size: 28).padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold, design: .serif)).foregroundStyle(DeckStudioPalette.ink)
                Text(message).font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// An empty page in the book's hand, in place of the system's empty-state view: a brass-stamped symbol,
/// a title in ink and a line of explanation.
struct BinderEmptyLeaf: View {
    let title: String
    let icon: String
    var message: String? = nil

    var body: some View {
        VStack(spacing: 10) {
            BinderStamp(icon: icon, size: 56)
            Text(title).font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(DeckStudioPalette.ink)
                .multilineTextAlignment(.center)
            if let message {
                Text(message).font(.system(size: 14, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 28).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A symbol struck into a brass coin.
struct BinderStamp: View {
    let icon: String
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: icon).font(.system(size: size * 0.44, weight: .bold)).foregroundStyle(Binder.engraved)
            .shadow(color: Binder.brassLight.opacity(0.7), radius: 0, y: 1)
            .frame(width: size, height: size)
            .background(Circle().fill(Binder.brass))
            .overlay(Circle().inset(by: size * 0.08).stroke(Binder.brassDeep.opacity(0.55), lineWidth: 0.8))
            .overlay(Circle().stroke(.black.opacity(0.5), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            .accessibilityHidden(true)
    }
}
