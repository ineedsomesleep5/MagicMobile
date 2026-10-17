import SwiftUI

/// The combo loop shortcut on the board (ComboLoop): the offer after three identical rounds, the repeating card with its
/// Stop button (which also keeps stray taps off the board), and the closing line. Android's ComboLoopOverlay matches it.
struct ComboLoopOverlay: View {
    @ObservedObject var session: OnDeviceSession
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
            Text(ComboLoop.describe(round))
                .font(.system(size: 13, design: .serif)).opacity(0.85).lineLimit(2)
            Text(String(localized: "You've done this three times. Repeat it? Every step is still checked by the rules, and it stops if anything changes."))
                .font(.system(size: 12, design: .serif)).opacity(0.7).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(ComboLoop.repeatChoices, id: \.self) { count in
                    Button("\(count)×") { start(count) }
                        .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                        .accessibilityLabel(String(localized: "Repeat \(count) times"))
                        .accessibilityIdentifier("comboLoop.repeat.\(count)")
                }
                Button(String(localized: "Until they lose")) { start(nil) }
                    .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
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

    private func running(_ run: OnDeviceSession.ComboRun) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 16, weight: .bold)).foregroundStyle(BrandTheme.brassGradient)
                    .rotationEffect(.degrees(reduceMotion ? 0 : Double(run.done) * 90))
                    .animation(.easeInOut(duration: 0.3), value: run.done)
                Text(run.target.map { String(localized: "Repeating · \(run.done) of \($0)") } ?? String(localized: "Repeating · \(run.done) done"))
                    .font(.system(size: 16, weight: .black, design: .serif)).monospacedDigit()
            }
            if let target = run.target {
                ProgressView(value: Double(run.done), total: Double(max(target, 1))).tint(TavernPalette.ember)
            } else {
                Text(String(localized: "Until every opponent has lost")).font(.system(size: 12, design: .serif)).opacity(0.75)
            }
            Text(ComboLoop.describe(run.round)).font(.system(size: 12, design: .serif)).opacity(0.7).lineLimit(1)
            Button { GameAudio.shared.play(.uiBack); session.stopComboLoop() } label: {
                Label(String(localized: "Stop"), systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(TavernButtonStyle(kind: .danger, compact: false))
            .accessibilityIdentifier("comboLoop.stop")
        }
        .foregroundStyle(TavernPalette.parchment)
        .padding(16)
        .frame(maxWidth: 380)
        .modifier(TavernPanelChrome(tavern: true, cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("comboLoop.running")
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

    private func start(_ times: Int?) {
        GameAudio.shared.play(.menuPlay)
        session.startComboLoop(times: times)
    }
}
