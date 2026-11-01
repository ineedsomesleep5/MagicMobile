import SwiftUI

/// Closes a menu page shown as an Arena panel (in place of dismissing a sheet: the panel is not presented).
private struct ArenaPanelCloseKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

/// Opens the Sound Lab as a page of Options (Audio's Sound Lab button) instead of a sheet.
private struct ArenaOpenSoundLabKey: EnvironmentKey { static let defaultValue: (() -> Void)? = nil }

extension EnvironmentValues {
    var arenaPanelClose: (() -> Void)? {
        get { self[ArenaPanelCloseKey.self] }
        set { self[ArenaPanelCloseKey.self] = newValue }
    }
    var arenaOpenSoundLab: (() -> Void)? {
        get { self[ArenaOpenSoundLabKey.self] }
        set { self[ArenaOpenSoundLabKey.self] = newValue }
    }
}

/// Where a menu panel stands: centred like Arena's Options, along the leading edge like its social panel, or along the
/// trailing edge like its inbox (a blade with the burning seam on its inner side).
enum ArenaPanelPlacement { case center, leading, trailing }

extension View {
    /// A menu page as Arena's glass panel over the dimmed menu (Caleb, 2026-10-22: no iPhone sheets in the menus). A tap
    /// on the dimmed menu closes it; the page closes itself through `arenaPanelClose`.
    /// `dismissable` false: the page must be answered (the first launch's welcome); a tap beside it does nothing.
    /// `fitsContent`: a centred panel only as tall as its page (up to the screen), so a short page leaves no empty glass.
    /// Its page must report a height when asked for its ideal size (a ScrollView does; a GeometryReader does not).
    func arenaPanel<Content: View>(isPresented: Binding<Bool>, placement: ArenaPanelPlacement = .center, maxWidth: CGFloat = 680,
                                   dismissable: Bool = true, fitsContent: Bool = false, onDismiss: (() -> Void)? = nil,
                                   @ViewBuilder content: @escaping () -> Content) -> some View {
        overlay {
            ArenaMenuPanelHost(isPresented: isPresented, placement: placement, maxWidth: maxWidth, dismissable: dismissable,
                               fitsContent: fitsContent, onDismiss: onDismiss, content: content)
        }
    }
}

/// A panel as tall as its page's ideal height, never taller than `cap`; the page scrolls past that.
private struct ArenaPanelFit: Layout {
    let cap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        guard let page = subviews.first else { return CGSize(width: width, height: 0) }
        return CGSize(width: width, height: min(cap, page.sizeThatFits(ProposedViewSize(width: width, height: nil)).height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

private struct ArenaMenuPanelHost<Content: View>: View {
    @Binding var isPresented: Bool
    let placement: ArenaPanelPlacement
    let maxWidth: CGFloat
    let dismissable: Bool
    let fitsContent: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width > proxy.size.height
            // `leading` here means "an edge drawer"; `trailing` says which edge.
            let leading = placement != .center
            let trailing = placement == .trailing
            let corner: Alignment = trailing ? .topTrailing : .topLeading
            ZStack(alignment: leading ? corner : .center) {
                if isPresented {
                    Color.black.opacity(0.62)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { if dismissable { close() } }
                        .accessibilityHidden(true)
                        .transition(.opacity)
                    panel(size: proxy.size, insets: proxy.safeAreaInsets, landscape: landscape, leading: leading, trailing: trailing)
                        // Every panel stands below the top bar, which shows dimmed above it (the judge, 2026-10-22).
                        .padding(.top, ArenaMenuStyle.barHeight + (landscape && !leading ? 4 : 0))
                        .transition(reduceMotion ? .opacity
                                    : leading ? .move(edge: trailing ? .trailing : .leading).combined(with: .opacity)
                                    : .scale(scale: 0.95).combined(with: .opacity))
                }
            }
            // A drawer taller than the safe area (it runs into the home bar) keeps its top under the top bar.
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: leading ? corner : .center)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 0.88), value: isPresented)
        }
        .onChange(of: isPresented) { _, shown in if !shown { onDismiss?() } }
    }

    @ViewBuilder private func panel(size: CGSize, insets: EdgeInsets, landscape: Bool, leading: Bool, trailing: Bool) -> some View {
        let inner: CGFloat = 20
        let shape = !leading
            ? UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: inner, bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
            : trailing ? UnevenRoundedRectangle(topLeadingRadius: inner, bottomLeadingRadius: inner, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: inner, topTrailingRadius: inner, style: .continuous)
        // A panel along the edge runs from under the top bar to the screen's foot, as Arena's social panel does (the
        // whole width upright); its content keeps clear of the island and the home bar.
        let edgeInsets = EdgeInsets(top: 0, leading: leading && !trailing ? insets.leading : 0, bottom: leading ? insets.bottom : 0,
                                    // Half the margin on the right blade: its rows reach near the edge (the judge, 2026-10-22:
                                    // the full inset left a dead strip), still clear of the rounded corner.
                                    trailing: trailing ? insets.trailing * 0.5 : 0)
        let cap = size.height - ArenaMenuStyle.barHeight - (landscape ? 14 : 40)
        let width = leading ? (landscape ? min(trailing ? 400 : 360, size.width * 0.45) + edgeInsets.leading + edgeInsets.trailing
                                         : size.width + insets.leading + insets.trailing)
                            : min(size.width - 28, maxWidth)
        Group {
            if fitsContent && !leading {
                ArenaPanelFit(cap: cap) { page(edgeInsets) }.frame(width: width)
            } else if leading && !landscape {
                // Upright the drawer runs only as far down as its page (the judge, 2026-10-22: no dead glass under it).
                ArenaPanelFit(cap: size.height - ArenaMenuStyle.barHeight + edgeInsets.bottom) { page(edgeInsets) }.frame(width: width)
            } else {
                page(edgeInsets).frame(width: width, height: leading ? size.height - ArenaMenuStyle.barHeight + edgeInsets.bottom : cap)
            }
        }
        .background(LinearGradient(colors: [ArenaGlass.top.opacity(0.98), ArenaGlass.bottom.opacity(0.98)], startPoint: .top, endPoint: .bottom))
        .clipShape(shape)
        .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        // A blade on the right burns along its inner edge, as Arena's inbox and Play blade do.
        .overlay(alignment: .leading) { if trailing && landscape { ArenaSeam(vertical: true) } }
        .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
        .ignoresSafeArea(edges: leading ? [.horizontal, .bottom] : [])
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { if dismissable { close() } }
    }

    private func page(_ edgeInsets: EdgeInsets) -> some View {
        content()
            .environment(\.arenaPanelClose, close)
            .environment(\.arenaBoard, true)
            .foregroundStyle(ArenaMenuStyle.text)
            .padding(edgeInsets)
    }

    private func close() {
        GameAudio.shared.play(.uiBack)
        isPresented = false
    }
}

/// A panel's head: an optional back chevron, the title in large type, and the close button, over a gold hairline.
struct ArenaPanelHeader: View {
    let title: String
    var back: (() -> Void)? = nil
    var closeIdentifier = "panel.close"
    @Environment(\.arenaPanelClose) private var panelClose
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(spacing: 4) {
            if let back {
                Button {
                    GameAudio.shared.play(.uiBack)
                    back()
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 16, weight: .heavy)).foregroundStyle(ArenaMenuStyle.text)
                        .frame(width: 40, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Back"))
                .accessibilityIdentifier("panel.back")
            }
            Text(title).font(ArenaMenuStyle.font(22, .bold)).foregroundStyle(ArenaMenuStyle.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            ArenaCloseButton(identifier: closeIdentifier) { if let panelClose { panelClose() } else { dismiss() } }
        }
        .padding(.leading, back == nil ? 18 : 6)
        .padding(.trailing, 8)
        .padding(.top, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.45) }
    }
}

// MARK: - Options

/// Arena's Options (the judge, 2026-10-22, options-1.jpg): over the dimmed menu, a centred serif title, one centred column
/// of compact pills (Gameplay, Board, Audio, Display & Artwork, Performance) and small underlined links along the foot
/// (Support, About). Each pill opens its page in the same panel with a back chevron; the pages lay their settings flat on
/// the glass in columns, as Arena's Gameplay page does (options-gameplay-1.jpg).
struct ArenaOptionsView: View {
    @Binding var portraitModeEnabled: Bool
    var upstreamCommit: String? = nil
    @State private var page: Page?
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.arenaPanelClose) private var panelClose

    init(portraitModeEnabled: Binding<Bool>, upstreamCommit: String? = nil, startPage: Page? = nil) {
        _portraitModeEnabled = portraitModeEnabled
        self.upstreamCommit = upstreamCommit
        _page = State(initialValue: startPage)
    }

    enum Page: String, CaseIterable, Identifiable {
        case gameplay, board, audio, display, performance, support, about, soundLab, phaseStops
        var id: String { rawValue }
        /// The column of pills; Support and About are the links along the foot; the Sound Lab opens from Audio and Phase
        /// Stops from Gameplay.
        static let listed: [Page] = [.gameplay, .board, .audio, .display, .performance]
        static let links: [Page] = [.support, .about]

        var title: String {
            switch self {
            case .gameplay: return String(localized: "Gameplay")
            case .board: return String(localized: "Board")
            case .audio: return String(localized: "Audio")
            case .display: return String(localized: "Display & Artwork")
            case .performance: return String(localized: "Performance")
            case .support: return String(localized: "Support")
            case .about: return String(localized: "About")
            case .soundLab: return String(localized: "Sound Lab")
            case .phaseStops: return String(localized: "Phase Stops")
            }
        }

        /// Where the back chevron goes from this page.
        var parent: Page? {
            switch self {
            case .soundLab: return .audio
            case .phaseStops: return .gameplay
            default: return nil
            }
        }
    }

    private var wide: Bool { verticalSizeClass == .compact }

    var body: some View {
        if page == .soundLab {
            SoundLabView(back: { page = .audio })
        } else {
            options
        }
    }

    private var options: some View {
        VStack(spacing: 0) {
            header
            if let page {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) { content(page) }
                        .environment(\.arenaOptionsFlat, true)
                        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
                        .frame(maxWidth: wide ? 820 : 560)
                        .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .mask(ArenaScrollFade())
                .accessibilityIdentifier("settings.page.\(page.rawValue)")
            } else {
                root
            }
        }
        .animation(.easeOut(duration: 0.18), value: page)
    }

    /// Arena's head: a back chevron on the left (pages only), the title centred in serif, the close button on the right,
    /// over a hairline.
    private var header: some View {
        ZStack {
            Text(page?.title ?? String(localized: "Options"))
                .font(ArenaMenuStyle.font(26, .bold)).foregroundStyle(ArenaMenuStyle.text)
                .lineLimit(1).minimumScaleFactor(0.7)
                .padding(.horizontal, 56)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 0) {
                if let page {
                    Button {
                        GameAudio.shared.play(.uiBack)
                        self.page = page.parent
                    } label: {
                        Image(systemName: "chevron.left").font(.system(size: 17, weight: .heavy)).foregroundStyle(ArenaMenuStyle.text)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: "Back"))
                    .accessibilityIdentifier("panel.back")
                }
                Spacer(minLength: 0)
                ArenaCloseButton(identifier: "settings.close") { panelClose?() }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(ArenaGlass.hairline).frame(height: 1).opacity(0.45) }
    }

    /// The column of pills, then the links along the foot. Fits a phone held sideways without scrolling.
    private var root: some View {
        VStack(spacing: 0) {
            VStack(spacing: wide ? 6 : 10) {
                ForEach(Page.listed) { item in
                    Button {
                        GameAudio.shared.play(.uiOpen)
                        page = item
                    } label: {
                        Text(item.title)
                    }
                    .buttonStyle(ArenaOptionsPillStyle())
                    .accessibilityIdentifier("settings.open.\(item.rawValue)")
                }
            }
            .padding(.top, wide ? 14 : 28)
            .padding(.bottom, wide ? 14 : 36)
            HStack(spacing: 28) {
                ForEach(Page.links) { item in
                    Button {
                        GameAudio.shared.play(.uiOpen)
                        page = item
                    } label: {
                        Text(item.title)
                            .font(ArenaMenuStyle.font(13, .medium))
                            .underline()
                            .foregroundStyle(ArenaMenuStyle.text.opacity(0.75))
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.open.\(item.rawValue)")
                }
            }
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func content(_ page: Page) -> some View {
        switch page {
        case .gameplay:
            // Two columns sideways, so every label stays on one line (the judge, 2026-10-22).
            GameplayOptions(columns: wide ? 2 : 1)
                .environment(\.arenaOpenPhaseStops, { self.page = .phaseStops })
        case .phaseStops:
            PhaseStopsGrid()
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
        case .board:
            // Flat on the glass in columns, as Arena's pages are.
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 28)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            layout {
                BoardModePicker()
                BoardEffectsPicker(includesAudio: false)
            }
            ArenaTablePicker()
            CardFramesToggle()
        case .audio:
            GameAudioSettings().modifier(TavernSettingsPanel())
                .environment(\.arenaOpenSoundLab, { self.page = .soundLab })
        case .soundLab:
            EmptyView()
        case .display:
            PortraitModeToggle(isOn: $portraitModeEnabled)
            NativeArtworkPreferenceView().modifier(TavernSettingsPanel())
        case .performance:
            GamePerformancePanel()
        case .support:
            SupportSettingsPanel()
        case .about:
            VStack(alignment: .leading, spacing: 8) {
                aboutRow(String(localized: "MagicMobile"),
                         "\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—") (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"))")
                if let upstreamCommit { aboutRow(String(localized: "XMage revision"), String(upstreamCommit.prefix(12))) }
                Text(SupportProject.note).font(ArenaMenuStyle.font(12, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .modifier(TavernSettingsPanel())
        }
    }

    private func aboutRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(ArenaMenuStyle.font(14, .semibold))
            Spacer()
            Text(value).font(ArenaMenuStyle.font(13, .bold)).monospacedDigit().foregroundStyle(ArenaMenuStyle.gold)
        }
        .frame(minHeight: 32)
    }
}

/// Arena's Options pill: a compact dark capsule edged in a pale line, its word centred; brighter while pressed.
private struct ArenaOptionsPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ArenaMenuStyle.font(15, .semibold))
            .foregroundStyle(ArenaMenuStyle.text)
            .lineLimit(1).minimumScaleFactor(0.8)
            .frame(width: 230, height: 36)
            .background(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.35 : 0.6)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(configuration.isPressed ? 0.75 : 0.45), lineWidth: 1.2))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}

// MARK: - Prompt

/// A question as Arena asks one in its menus: the title, a few words, a leather plaque to decline and the ember one to
/// go ahead, in a small glass panel.
struct ArenaPromptPanel: View {
    let title: String
    let message: String
    let primary: String
    let secondary: String
    var identifier = "prompt"
    let action: () -> Void
    @Environment(\.arenaPanelClose) private var panelClose

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArenaPanelHeader(title: title, closeIdentifier: "\(identifier).close")
            Text(message).font(ArenaMenuStyle.font(14, .medium)).foregroundStyle(ArenaMenuStyle.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18).padding(.top, 14)
            HStack(spacing: 12) {
                Button(secondary) { panelClose?() }
                    .buttonStyle(ArenaPillButtonStyle())
                    .accessibilityIdentifier("\(identifier).secondary")
                Spacer(minLength: 0)
                Button(primary, action: action)
                    .buttonStyle(ArenaPlayButtonStyle(fontSize: 17))
                    .frame(width: 210, height: 44)
                    .accessibilityIdentifier("\(identifier).primary")
            }
            .padding(.horizontal, 18).padding(.vertical, 16)
        }
    }
}
