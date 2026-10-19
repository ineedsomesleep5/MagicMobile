import SwiftUI

/// The combo loop shortcut on the board (ComboLoop): the offer after three identical rounds (what a round does, a count
/// picker, until I can't, until they lose), the repeating card with its last rounds and Stop (over a scrim that keeps
/// stray taps off the board), and the closing line. Android's ComboLoopOverlay matches it.
struct ComboLoopOverlay: View {
    @ObservedObject var session: OnDeviceSession
    @State private var count = ComboLoop.pickerDefault
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if let run = session.comboRun {
                Color.black.opacity(0.35).ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                running(run).padding(.top, 70)
            } else if let round = session.comboOffer {
                offer(round).padding(.top, 70).transition(.move(edge: .top).combined(with: .opacity))
            } else if let result = session.comboResult {
                resultLine(result).padding(.top, 70).transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: result) {
                        try? await Task.sleep(nanoseconds: 9_000_000_000)
                        if session.comboResult == result { withAnimation { session.comboResult = nil } }
                    }
            }
        }
        .padding(.horizontal, 16)
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.4, dampingFraction: 0.85), value: session.comboOffer)
        .animation(.easeOut(duration: 0.2), value: session.comboRun)
        .animation(.easeOut(duration: 0.2), value: session.comboResult)
    }

    // MARK: Offer

    private func offer(_ round: [ComboStep]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                Text(String(localized: "Loop spotted")).font(.system(size: 16, weight: .black, design: .serif))
                Spacer(minLength: 4)
                Button { GameAudio.shared.play(.uiBack); session.declineComboLoop() } label: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .black)).frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Not now"))
                .accessibilityIdentifier("comboLoop.decline")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(String(localized: "EACH ROUND")).font(.system(size: 10, weight: .heavy, design: .serif)).tracking(1.2).foregroundStyle(BrandTheme.brassGradient)
                ForEach(Array(ComboLoop.preview(round).enumerated()), id: \.offset) { _, line in
                    Label(line, systemImage: "chevron.right").labelStyle(PreviewLineStyle())
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("comboLoop.preview")
            Text(String(localized: "Every step is still checked by the rules. It waits for your own triggers, keeps the same target until it's gone, and stops if an opponent responds."))
                .font(.system(size: 11, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            picker
            HStack(spacing: 6) {
                Button(String(localized: "Repeat \(count)×")) { start(.times(count)) }
                    .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                    .accessibilityIdentifier("comboLoop.repeat")
                Button(String(localized: "Until I can't")) { start(.untilCant) }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("comboLoop.untilCant")
                Button(String(localized: "Until they lose")) { start(.untilWin) }
                    .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                    .accessibilityIdentifier("comboLoop.untilWin")
            }
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(14)
        .frame(maxWidth: 460)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comboLoop.offer")
    }

    /// − count +, with +5 and +10.
    private var picker: some View {
        HStack(spacing: 8) {
            stepButton("minus", String(localized: "One fewer"), "comboLoop.minus") { count = max(1, count - 1) }
                .disabled(count <= 1)
            Text("\(count)")
                .font(.system(size: 22, weight: .black, design: .serif)).monospacedDigit()
                .frame(minWidth: 44)
                .contentTransition(.numericText())
                .accessibilityIdentifier("comboLoop.count")
            stepButton("plus", String(localized: "One more"), "comboLoop.plus") { count = min(ComboLoop.maxRepeats, count + 1) }
                .disabled(count >= ComboLoop.maxRepeats)
            Spacer(minLength: 4)
            Button("+5") { bump(5) }.buttonStyle(TavernButtonStyle(kind: .secondary, compact: true)).accessibilityIdentifier("comboLoop.plus5")
            Button("+10") { bump(10) }.buttonStyle(TavernButtonStyle(kind: .secondary, compact: true)).accessibilityIdentifier("comboLoop.plus10")
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(String(localized: "\(count) rounds"))
    }

    private func stepButton(_ symbol: String, _ label: String, _ id: String, action: @escaping () -> Void) -> some View {
        Button {
            GameAudio.shared.play(.uiTick)
            withAnimation(.snappy) { action() }
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .black))
                .frame(width: 40, height: 40)
                .background(Circle().fill(TavernPalette.leather))
                .overlay(Circle().strokeBorder(TavernPalette.brass.opacity(0.7), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func bump(_ by: Int) {
        GameAudio.shared.play(.uiTick)
        withAnimation(.snappy) { count = min(ComboLoop.maxRepeats, count + by) }
    }

    // MARK: Running

    private func running(_ run: OnDeviceSession.ComboRun) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(run.done) * 90))
                    .animation(.easeInOut(duration: 0.3), value: run.done)
                Text(title(run)).font(.system(size: 16, weight: .black, design: .serif)).monospacedDigit()
            }
            if let target = run.mode.count {
                ProgressView(value: Double(run.done), total: Double(max(target, 1))).tint(TavernPalette.ember)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(run.lines.enumerated()), id: \.offset) { index, line in
                    Text(line).font(.system(size: 12, design: .serif)).lineLimit(1)
                        .opacity(index == run.lines.count - 1 ? 0.95 : 0.55)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("comboLoop.rounds")
            Button { GameAudio.shared.play(.uiBack); session.stopComboLoop() } label: {
                Label(String(localized: "Stop"), systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .danger, compact: false))
            .accessibilityIdentifier("comboLoop.stop")
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(16)
        .frame(maxWidth: 400)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comboLoop.running")
    }

    private func title(_ run: OnDeviceSession.ComboRun) -> String {
        switch run.mode {
        case .times(let target): return String(localized: "Repeating · \(run.done) of \(target)")
        case .untilCant: return String(localized: "Repeating until you can't · \(run.done)")
        case .untilWin: return String(localized: "Repeating until they lose · \(run.done)")
        }
    }

    private func resultLine(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 15, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
            Text(text).font(.system(size: 13, weight: .semibold, design: .serif)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button { withAnimation { session.comboResult = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .black)).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Dismiss"))
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 8)
        .frame(maxWidth: 460)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("comboLoop.result")
    }

    private func start(_ mode: ComboRepeat) {
        GameAudio.shared.play(.menuPlay)
        session.startComboLoop(mode)
    }
}

private struct PreviewLineStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.icon.font(.system(size: 8, weight: .black)).foregroundStyle(TavernPalette.brass)
            configuration.title.font(.system(size: 13, design: .serif)).lineLimit(1)
        }
    }
}
