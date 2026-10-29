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
        // Arena's panel head: the title in large type with its actions as pills, over a gold hairline.
        HStack(spacing: 8) {
            plaque(leading).frame(minWidth: 90, alignment: .leading)
            Text(title)
                .font(ArenaMenuStyle.font(20, .bold))
                .foregroundStyle(ArenaMenuStyle.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)
            plaque(trailing).frame(minWidth: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
        .background {
            ArenaGlass.top.opacity(0.97)
                .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.6) }
                .ignoresSafeArea(edges: .top)
        }
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
            .binderOverlayHost()
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
                // Arena's Options use checkboxes.
                ArenaCheckFace(isOn: configuration.isOn)
                configuration.label
                    .foregroundStyle(ArenaMenuStyle.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
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
                    configuration.label.foregroundStyle(ArenaMenuStyle.text).multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(ArenaMenuStyle.gold)
                        .frame(width: 22, height: 22)
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
            Text(title).foregroundStyle(ArenaMenuStyle.text).frame(maxWidth: .infinity, alignment: .leading)
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
            Image(systemName: symbol).font(.system(size: 11, weight: .heavy)).foregroundStyle(ArenaMenuStyle.text)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(0.07)))
                .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                .opacity(active ? 1 : 0.4)
                .frame(width: 47, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!active)
        .accessibilityLabel(symbol == "plus" ? "Increase" : "Decrease")
        .accessibilityIdentifier(symbol == "plus" ? "Increment" : "Decrement")
    }
}

/// A choice from a menu, shown as a brass plaque naming the current choice; the choices open in the
/// binder's own menu (GrimoireBinderMenu.swift).
struct BinderMenuPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        let current = options.first { $0.0 == selection }?.1 ?? title
        BinderMenu {
            BinderMenuPick(title, selection: $selection, options: options)
        } label: {
            BinderPlaque {
                HStack(spacing: 6) {
                    Text(current).font(ArenaMenuStyle.font(14, .heavy))
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

    var body: some View {
        HStack(spacing: 4) {
            if jewel {
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
                .font(ArenaMenuStyle.font(10, .heavy)).tracking(0.8)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(material == .ember ? Color(red: 1, green: 0.95, blue: 0.82) : ArenaMenuStyle.gold)
        .padding(.leading, jewel ? 6 : 10).padding(.trailing, 10)
        .frame(minHeight: 22)
        // Arena's tags: gold capitals on dark glass, ember for the deck you play.
        .background {
            if material == .ember {
                Capsule().fill(LinearGradient(colors: [Color(red: 0.95, green: 0.45, blue: 0.18), Color(red: 0.62, green: 0.18, blue: 0.06)],
                                              startPoint: .top, endPoint: .bottom))
            } else {
                Capsule().fill(Color.black.opacity(0.7))
            }
        }
        .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.8))
        .fixedSize()
    }
}

/// A small brass coin with an engraved symbol, in a full touch target: a deck's favourite star and ⋯.
/// `lit` fills the symbol with ember (a favourite).
struct BinderCoin<Label: View>: View {
    var lit = false
    var pressed = false
    @ViewBuilder var label: Label

    var body: some View {
        // A glass circle with a gold symbol; lit is an ember symbol (a favourite).
        label
            .font(.system(size: 13, weight: .black))
            .foregroundStyle(lit ? ArenaMenuStyle.ember : ArenaMenuStyle.gold)
            .shadow(color: lit ? ArenaMenuStyle.ember.opacity(0.8) : .clear, radius: 3)
            .frame(width: 30, height: 30)
            .background(Circle().fill(Color.black.opacity(pressed ? 0.7 : 0.5)))
            .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(0.8))
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
            Text(title).font(ArenaMenuStyle.font(13, .bold)).lineLimit(1)
        }
        .foregroundStyle(chosen ? Color(red: 0.11, green: 0.06, blue: 0.03) : ArenaMenuStyle.dim)
        .padding(.horizontal, 12).frame(minHeight: 30)
        // Arena's filter chips: dark glass, filled gold when chosen.
        .background(Capsule().fill(chosen ? AnyShapeStyle(ArenaMenuStyle.goldFill) : AnyShapeStyle(Color.black.opacity(0.5))))
        .overlay(Capsule().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9).opacity(chosen ? 0 : 0.7))
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
                Text(title).font(ArenaMenuStyle.font(15, .bold)).foregroundStyle(ArenaMenuStyle.text)
                Text(message).font(ArenaMenuStyle.font(13, .regular)).foregroundStyle(ArenaMenuStyle.dim)
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
            Text(title).font(.system(size: 20, weight: .bold, design: .serif)).foregroundStyle(ArenaMenuStyle.text)
                .multilineTextAlignment(.center)
            if let message {
                Text(message).font(ArenaMenuStyle.font(14, .regular)).foregroundStyle(ArenaMenuStyle.dim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 28).padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A symbol in a glass circle (it was struck into a brass coin).
struct BinderStamp: View {
    let icon: String
    var size: CGFloat = 28

    var body: some View {
        // A gold emblem in a glass circle.
        ArenaEmblem(symbol: icon, size: size * 0.42, lit: true)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 0.9))
            .accessibilityHidden(true)
    }
}

/// Arena's checkbox face, for toggles drawn by a style (the real Toggle carries the contract).
struct ArenaCheckFace: View {
    let isOn: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isOn ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.62, blue: 0.32), Color(red: 0.74, green: 0.25, blue: 0.08)],
                                                          startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color.black.opacity(0.45)))
            RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(ArenaGlass.hairline, lineWidth: 1.2)
            if isOn {
                Image(systemName: "checkmark").font(.system(size: 12, weight: .black)).foregroundStyle(.white)
            }
        }
        .frame(width: 22, height: 22)
        .shadow(color: isOn ? ArenaMenuStyle.ember.opacity(0.6) : .clear, radius: 5)
        .animation(.easeOut(duration: 0.15), value: isOn)
        .accessibilityHidden(true)
    }
}
