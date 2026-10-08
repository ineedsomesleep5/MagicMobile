import SwiftUI

/// The binder's own drop-down menus and confirmations, in place of the system's (Caleb, 2026-10-06: the
/// filter menu still looked like the iPhone's Liquid Glass; "make sure there's no old UI still in there").
/// A host on each binder screen and loose leaf (`binderScreen()`, `binderLeaf`) draws them over the page:
/// a parchment card in a brass edge, anchored under (or over) the plaque that opened it. Every row is a
/// real button, so VoiceOver and the UI tests find them by their titles. Android: StudioMenu in
/// studio/StudioTheme.kt.

/// What the host is showing.
@MainActor
final class BinderOverlayHost: ObservableObject {
    struct Menu: Identifiable {
        let id = UUID()
        let anchor: CGRect
        let content: AnyView
    }
    struct Dialog: Identifiable {
        let id = UUID()
        let title: String
        let message: String?
        let actions: AnyView
        let cancel: Bool
        let dismissed: () -> Void
    }
    @Published var menu: Menu?
    @Published var dialog: Dialog?
    private var shownAt = Date.distantPast

    func show(anchor: CGRect, content: AnyView) {
        shownAt = Date()
        menu = Menu(anchor: anchor, content: content)
    }
    /// False while a menu is open or just after one opened: the lift of the long press that opened a menu must not
    /// also tap what is under it (SwiftUI's buttons still fire then).
    var tapAllowed: Bool { menu == nil && Date().timeIntervalSince(shownAt) > 0.7 }
    func dismissMenu() { menu = nil }
    func dismissDialog() {
        let finished = dialog?.dismissed
        dialog = nil
        finished?()
    }
}

private struct BinderOverlayHostKey: EnvironmentKey { static let defaultValue: BinderOverlayHost? = nil }
private struct BinderMenuDismissKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
    var binderOverlayHost: BinderOverlayHost? {
        get { self[BinderOverlayHostKey.self] }
        set { self[BinderOverlayHostKey.self] = newValue }
    }
    /// Closes the menu a row belongs to.
    var binderMenuDismiss: () -> Void {
        get { self[BinderMenuDismissKey.self] }
        set { self[BinderMenuDismissKey.self] = newValue }
    }
}

extension View {
    /// Draws the binder's menus and confirmations for everything inside.
    func binderOverlayHost() -> some View { modifier(BinderOverlayHostModifier()) }
}

private struct BinderOverlayHostModifier: ViewModifier {
    @StateObject private var host = BinderOverlayHost()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .environment(\.binderOverlayHost, host)
            .overlay {
                GeometryReader { proxy in
                    let origin = proxy.frame(in: .global).origin
                    let size = proxy.size
                    ZStack(alignment: .topLeading) {
                        if let menu = host.menu {
                            Color.black.opacity(0.06)
                                .contentShape(Rectangle())
                                .onTapGesture { host.dismissMenu() }
                                .accessibilityHidden(true)
                            BinderMenuCard(menu: menu, origin: origin, container: size)
                                .environment(\.binderMenuDismiss) { host.dismissMenu() }
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                        if let dialog = host.dialog {
                            Color.black.opacity(0.35)
                                .contentShape(Rectangle())
                                .onTapGesture { if dialog.cancel { host.dismissDialog() } }
                                .accessibilityHidden(true)
                            BinderDialogCard(dialog: dialog, dismiss: { host.dismissDialog() })
                                .frame(width: min(size.width - 40, 380))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
                        }
                    }
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: host.menu?.id)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: host.dialog?.id)
                }
                .ignoresSafeArea()
                .allowsHitTesting(host.menu != nil || host.dialog != nil)
            }
    }
}

/// The open menu: parchment in a brass edge, under its plaque when there is room below, else over it, and
/// lined up with the plaque's nearer edge. A long menu scrolls inside the card.
private struct BinderMenuCard: View {
    let menu: BinderOverlayHost.Menu
    let origin: CGPoint
    let container: CGSize
    @Environment(\.binderMenuDismiss) private var dismiss

    var body: some View {
        let anchor = menu.anchor.offsetBy(dx: -origin.x, dy: -origin.y)
        let width = min(max(anchor.width, 250), container.width - 16)
        let trailing = anchor.midX > container.width / 2
        let x = min(max(8, trailing ? anchor.maxX - width : anchor.minX), container.width - width - 8)
        let below = container.height - anchor.maxY
        let downward = below >= 280 || below >= anchor.minY
        let room = max(120, (downward ? below : anchor.minY) - 24)
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        // As tall as its rows, or as tall as there is room for and scrolling beyond that.
        let card = BinderMenuHeight(width: width, maxHeight: room) {
            rows.hidden().accessibilityHidden(true)
            ScrollView { rows }.scrollBounceBehavior(.basedOnSize)
        }
        .background { GrimoirePaper(tone: .plate) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Binder.brass, lineWidth: 1.6))
        .overlay(shape.inset(by: 3).stroke(Binder.brassDeep.opacity(0.25), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { dismiss() }

        return Group {
            if downward {
                card.offset(x: x, y: anchor.maxY + 6)
            } else {
                card.frame(height: anchor.minY - 6, alignment: .bottom).offset(x: x)
            }
        }
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) { menu.content }
            .padding(.vertical, 6)
    }
}

/// Measures its first child (the rows, hidden) and gives its second (the rows in a scroll view) that height, or
/// `maxHeight` if the rows are taller.
private struct BinderMenuHeight: Layout {
    let width: CGFloat
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
        return CGSize(width: width, height: min(rows, maxHeight))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: 0))
        subviews[1].place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// A plaque (or any label) that opens a binder menu under it. Without a host it falls back to the
/// system menu, so it always works.
struct BinderMenu<Label: View, Content: View>: View {
    var accessibilityLabel: String? = nil
    var identifier: String? = nil
    @ViewBuilder var content: () -> Content
    @ViewBuilder var label: () -> Label
    @Environment(\.binderOverlayHost) private var host
    @State private var frame: CGRect = .zero

    init(accessibilityLabel: String? = nil, identifier: String? = nil,
         @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> Label) {
        self.accessibilityLabel = accessibilityLabel; self.identifier = identifier
        self.content = content; self.label = label
    }

    var body: some View {
        Group {
            if let host {
                Button { host.show(anchor: frame, content: AnyView(content())) } label: { label() }
                    .buttonStyle(.plain)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            } else {
                SwiftUI.Menu { content() } label: { label() }
            }
        }
        .modifier(BinderMenuAccessibility(label: accessibilityLabel, identifier: identifier))
    }
}

private struct BinderMenuAccessibility: ViewModifier {
    let label: String?
    let identifier: String?
    func body(content: Content) -> some View {
        content
            .modifier(OptionalLabel(label: label))
            .modifier(OptionalIdentifier(identifier: identifier))
    }
    private struct OptionalLabel: ViewModifier {
        let label: String?
        func body(content: Content) -> some View { if let label { content.accessibilityLabel(label) } else { content } }
    }
    private struct OptionalIdentifier: ViewModifier {
        let identifier: String?
        func body(content: Content) -> some View { if let identifier { content.accessibilityIdentifier(identifier) } else { content } }
    }
}

extension View {
    /// A long press opens a binder menu at this view (in place of the system's context menu).
    func binderContextMenu<Content: View>(enabled: Bool = true, @ViewBuilder _ content: @escaping () -> Content) -> some View {
        modifier(BinderContextMenu(enabled: enabled, menu: content))
    }
}

private struct BinderContextMenu<Menu: View>: ViewModifier {
    let enabled: Bool
    let menu: () -> Menu
    @Environment(\.binderOverlayHost) private var host
    @State private var frame: CGRect = .zero

    func body(content: Content) -> some View {
        if let host, enabled {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
                // A UIKit recognizer, as the system's context menu uses: once the press is long enough it cancels
                // the touch for the buttons underneath (a card's add and remove halves), so they never fire.
                .background(BinderLongPressWatcher {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    host.show(anchor: frame, content: AnyView(menu()))
                })
        } else if enabled {
            content.contextMenu { menu() }
        } else {
            content
        }
    }
}

/// Watches for a long press inside its own frame from the window, like the system's context menu: when it fires it
/// cancels the touch for everything under it. A touch that lands on something presented over this view (a sheet)
/// is not its own, so it is ignored.
private struct BinderLongPressWatcher: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> WatcherView { WatcherView() }
    func updateUIView(_ view: WatcherView, context: Context) { view.action = action }
    static func dismantleUIView(_ view: WatcherView, coordinator: ()) { view.detach() }

    final class WatcherView: UIView, UIGestureRecognizerDelegate {
        var action: () -> Void = {}
        private var recognizer: UILongPressGestureRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            guard let window else { return }
            let press = UILongPressGestureRecognizer(target: self, action: #selector(fire(_:)))
            press.minimumPressDuration = 0.45
            press.cancelsTouchesInView = true
            press.delegate = self
            window.addGestureRecognizer(press)
            recognizer = press
        }

        func detach() {
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            recognizer = nil
        }

        @objc private func fire(_ press: UILongPressGestureRecognizer) {
            guard press.state == .began else { return }
            cancelOthers(at: press.location(in: window))
            action()
        }

        /// Cancels the gestures already tracking this touch (the card's tap halves, the scroll view) by switching
        /// them off and on, so the press opens the menu and nothing else.
        private func cancelOthers(at point: CGPoint) {
            guard let window, var view = window.hitTest(point, with: nil) else { return }
            while true {
                for other in view.gestureRecognizers ?? [] where other !== recognizer && other.isEnabled {
                    other.isEnabled = false
                    other.isEnabled = true
                }
                guard let parent = view.superview, parent !== window else { break }
                view = parent
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let window, !isHidden, bounds.width > 0 else { return false }
            let point = touch.location(in: window)
            guard convert(bounds, to: window).contains(point) else { return false }
            // Only a touch on this view's own layer of the window, not on a sheet or menu presented over it.
            var root: UIView = self
            while let parent = root.superview, parent !== window { root = parent }
            return window.hitTest(point, with: nil)?.isDescendant(of: root) ?? false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

// MARK: - Rows

/// One row of a binder menu: an engraved symbol, its title in the book's hand, and a check when chosen.
struct BinderMenuRowLabel: View {
    let title: String
    var systemImage: String? = nil
    /// A mana symbol (W, U, B, R, G, C) in place of the engraved symbol.
    var mana: String? = nil
    var checked = false
    var destructive = false

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let mana { ManaSymbolView(symbol: mana, size: 20) }
                else if let systemImage { Image(systemName: systemImage).font(.system(size: 14, weight: .semibold)) }
                else { Color.clear }
            }
            .frame(width: 22)
            .foregroundStyle(destructive ? DeckStudioPalette.danger : Binder.brassDeep)
            Text(title)
                .font(.system(size: 16, weight: checked ? .bold : .regular, design: .serif))
                .foregroundStyle(destructive ? DeckStudioPalette.danger : DeckStudioPalette.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if checked {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .heavy)).foregroundStyle(DeckStudioPalette.accent)
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

private struct BinderMenuRowStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DeckStudioPalette.ink.opacity(0.08) : .clear)
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A row that does something and closes the menu.
struct BinderMenuButton: View {
    let title: String
    var systemImage: String? = nil
    var mana: String? = nil
    var role: ButtonRole? = nil
    var checked = false
    let action: () -> Void
    @Environment(\.binderMenuDismiss) private var dismiss

    init(_ title: String, systemImage: String? = nil, mana: String? = nil, role: ButtonRole? = nil, checked: Bool = false,
         action: @escaping () -> Void) {
        self.title = title; self.systemImage = systemImage; self.mana = mana; self.role = role; self.checked = checked; self.action = action
    }

    var body: some View {
        Button(role: role) { dismiss(); action() } label: {
            BinderMenuRowLabel(title: title, systemImage: systemImage, mana: mana, checked: checked, destructive: role == .destructive)
        }
        .buttonStyle(BinderMenuRowStyle())
        .accessibilityLabel(title)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

/// A choice of one value: its title as a small heading, then a row for each option with a check on the
/// chosen one.
struct BinderMenuPick<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(Value, String)]

    init(_ title: String, selection: Binding<Value>, options: [(Value, String)]) {
        self.title = title; _selection = selection; self.options = options
    }

    var body: some View {
        BinderMenuHeading(title)
        ForEach(options, id: \.0) { option in
            BinderMenuButton(option.1, checked: option.0 == selection) { selection = option.0 }
        }
    }
}

/// The colour filter: any colour, or one colour shown by its mana symbol.
struct BinderMenuColorPick: View {
    @Binding var selection: String
    private static let colors = [("W", "White"), ("U", "Blue"), ("B", "Black"), ("R", "Red"), ("G", "Green"), ("C", "Colorless")]
    var body: some View {
        BinderMenuHeading("Card color")
        BinderMenuButton("Any color", systemImage: "circle.hexagongrid", checked: selection.isEmpty) { selection = "" }
        ForEach(Self.colors, id: \.0) { color in
            BinderMenuButton(color.1, mana: color.0, checked: selection == color.0) { selection = color.0 }
        }
    }
}

/// A switch in a menu: a row with a brass check when on.
struct BinderMenuToggle: View {
    let title: String
    @Binding var isOn: Bool
    init(_ title: String, isOn: Binding<Bool>) { self.title = title; _isOn = isOn }
    var body: some View {
        BinderMenuButton(title, systemImage: isOn ? "checkmark.square.fill" : "square", checked: false) { isOn.toggle() }
            .accessibilityValue(isOn ? "On" : "Off")
    }
}

/// A small heading over a group of rows.
struct BinderMenuHeading: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title).textCase(.uppercase)
            .font(.system(size: 11, weight: .heavy, design: .serif)).tracking(1)
            .foregroundStyle(DeckStudioPalette.accent)
            .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A thin inked rule between groups.
struct BinderMenuDivider: View {
    var body: some View {
        Rectangle().fill(DeckStudioPalette.ink.opacity(0.15)).frame(height: 0.8)
            .padding(.horizontal, 12).padding(.vertical, 4)
            .accessibilityHidden(true)
    }
}

/// A line of explanation that is not a choice.
struct BinderMenuNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 13, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A share row (the system share sheet opens from it).
struct BinderMenuShare: View {
    let title: String
    let systemImage: String
    let item: String
    @Environment(\.binderMenuDismiss) private var dismiss
    var body: some View {
        ShareLink(item: item) { BinderMenuRowLabel(title: title, systemImage: systemImage) }
            .buttonStyle(BinderMenuRowStyle())
            .simultaneousGesture(TapGesture().onEnded { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismiss() } })
            .accessibilityLabel(title)
    }
}

/// A plain button whose action is skipped while a binder menu is opening over it (`BinderOverlayHost.tapAllowed`).
/// Use it for anything a long press also opens a menu on.
struct BinderGuardedButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: () -> Label
    @Environment(\.binderOverlayHost) private var host
    var body: some View {
        Button { if host?.tapAllowed ?? true { action() } } label: { label() }
    }
}

/// Rows that open in place under their title (in place of a nested system menu).
struct BinderMenuSubmenu<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content
    @State private var open = false

    init(_ title: String, systemImage: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title; self.systemImage = systemImage; self.content = content
    }

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } } label: {
            HStack(spacing: 0) {
                BinderMenuRowLabel(title: title, systemImage: systemImage)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .heavy)).foregroundStyle(Binder.brassDeep)
                    .rotationEffect(.degrees(open ? 180 : 0)).padding(.trailing, 14)
            }
        }
        .buttonStyle(BinderMenuRowStyle())
        .accessibilityLabel(title)
        .accessibilityValue(open ? "Expanded" : "Collapsed")
        if open {
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.leading, 18)
        }
    }
}

// MARK: - Confirmations

extension View {
    /// A confirmation on a parchment card (in place of the system's confirmation dialog). Its actions are
    /// Buttons; a destructive role draws oxblood, a cancel role a plain plaque. `cancel` adds Cancel.
    func binderConfirm<Actions: View>(_ title: String, isPresented: Binding<Bool>, message: String? = nil, cancel: Bool = true,
                                      @ViewBuilder actions: @escaping () -> Actions) -> some View {
        modifier(BinderConfirmModifier(title: title, isPresented: isPresented, message: message, cancel: cancel, actions: actions))
    }
}

private struct BinderConfirmModifier<Actions: View>: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String?
    let cancel: Bool
    let actions: () -> Actions
    @Environment(\.binderOverlayHost) private var host

    func body(content: Content) -> some View {
        if let host {
            content
                .onChange(of: isPresented, initial: true) { _, shown in
                    if shown {
                        host.dialog = .init(title: title, message: message, actions: AnyView(actions()), cancel: cancel,
                                            dismissed: { isPresented = false })
                    } else if host.dialog?.title == title {
                        host.dialog = nil
                    }
                }
        } else {
            content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) { actions() } message: {
                if let message { Text(message) }
            }
        }
    }
}

private struct BinderDialogCard: View {
    let dialog: BinderOverlayHost.Dialog
    let dismiss: () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        VStack(spacing: 12) {
            Text(dialog.title)
                .font(.system(size: 19, weight: .bold, design: .serif)).foregroundStyle(DeckStudioPalette.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message = dialog.message {
                Text(message).font(.system(size: 14, design: .serif)).foregroundStyle(DeckStudioPalette.secondaryInk)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            GrimoireRule()
            VStack(spacing: 8) {
                dialog.actions
                if dialog.cancel {
                    Button("Cancel", role: .cancel) {}
                }
            }
            .buttonStyle(BinderDialogButtonStyle(dismiss: dismiss))
        }
        .padding(18)
        .background { GrimoirePaper(tone: .plate).clipShape(shape) }
        .overlay(shape.strokeBorder(Binder.brass, lineWidth: 2))
        .overlay { BinderCorners(size: 18, style: .leaf).allowsHitTesting(false) }
        .shadow(color: .black.opacity(0.45), radius: 20, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if dialog.cancel { dismiss() } }
    }
}

/// A dialog's buttons: brass for the main choice, oxblood leather for a destructive one, a quiet plaque
/// for Cancel. Pressing any closes the dialog after its action.
private struct BinderDialogButtonStyle: PrimitiveButtonStyle {
    let dismiss: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        Button { configuration.trigger(); dismiss() } label: {
            configuration.label
                .font(.system(size: 16, weight: .heavy, design: .serif))
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(configuration.role == .destructive ? TavernPalette.parchment : Binder.engraved)
                .background {
                    switch configuration.role {
                    case .destructive?: ZStack { TavernFill(material: .leather); Binder.dye(Binder.oxblood, 0.7) }.clipShape(shape)
                    case .cancel?: shape.fill(DeckStudioPalette.ink.opacity(0.06))
                    default: shape.fill(Binder.brass)
                    }
                }
                .overlay(shape.strokeBorder(configuration.role == .cancel ? DeckStudioPalette.ink.opacity(0.2) : Binder.brassDeep.opacity(0.7), lineWidth: 1))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
    }
}
