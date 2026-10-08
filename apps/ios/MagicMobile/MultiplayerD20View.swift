import SwiftUI
import UIKit

/// A presentation of authoritative starting-roll data. The match coordinator owns
/// the dice values, tie rounds, and winner; this view only plays them back, on the tavern table:
/// each seat's d20 is thrown onto the board's leather mat, tumbles, bounces off the rail and settles
/// on the number the game decided (StartingRollTableView.swift, docs/STARTING_ROLL.md).
struct MultiplayerD20View: View {
    let roll: OnDeviceStartingRoll
    let seatNames: [String: String]
    let isLocalWinner: Bool
    let revealedStepCount: Int
    let localSeatID: String?
    let rollPending: Bool
    let onRollTap: () -> Void
    let onStepPlayed: () -> Void
    let onDismiss: () -> Void

    init(roll: OnDeviceStartingRoll, seatNames: [String: String], isLocalWinner: Bool,
         revealedStepCount: Int, localSeatID: String?, rollPending: Bool = false,
         onRollTap: @escaping () -> Void, onStepPlayed: @escaping () -> Void = {},
         onDismiss: @escaping () -> Void) {
        self.roll = roll
        self.seatNames = seatNames
        self.isLocalWinner = isLocalWinner
        self.revealedStepCount = revealedStepCount
        self.localSeatID = localSeatID
        self.rollPending = rollPending
        self.onRollTap = onRollTap
        self.onStepPlayed = onStepPlayed
        self.onDismiss = onDismiss
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var shownRoundIndex: Int?
    @State private var activeSeatID: String?
    @State private var activeValue: Int?
    @State private var settledRolls: [String: Int] = [:]
    @State private var landed = false
    @State private var edgeHitTurn: Int?
    @State private var reboundTurn: Int?
    @State private var restTurn: Int?
    @State private var playbackFinished = false
    @State private var spinTurns = 0
    @State private var skipAnimation = false
    @State private var playedStepCount = 0
    @State private var unlockedStepCount = 0
    @State private var didAutoDismiss = false
    // The dice on the table: the round they belong to, the ones at rest and the one in the air.
    @State private var tableRound = 0
    @State private var tableResting: [String: Int] = [:]
    @State private var tableThrow: D20TableState.Throw?
    @State private var rollRegion: CGRect = .zero

    private var rounds: [[String: Int]] { roll.rounds.map(\.rolls) }
    private var steps: [OnDeviceStartingRoll.Step] { roll.steps }
    private var playerIDs: [String] {
        let ids = Set(rounds.first.map { Array($0.keys) } ?? Array(seatNames.keys))
        // The roll's own order (the viewer first), which is also the table's lane order.
        let ordered = roll.seatOrder.filter(ids.contains)
        return ordered + ids.subtracting(ordered).sorted()
    }

    private var playbackKey: PlaybackKey {
        PlaybackKey(seatNames: seatNames, rounds: rounds, winnerID: roll.winnerSeatID,
                    reduceMotion: reduceMotion, skipAnimation: skipAnimation)
    }

    private var tableState: D20TableState {
        D20TableState(seatOrder: playerIDs, round: tableRound, resting: tableResting, throwing: tableThrow,
                      highlighted: playbackFinished ? roll.winnerSeatID : nil)
    }

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height && geometry.size.width >= 560
            let columnCount = dynamicTypeSize.isAccessibilitySize ? 1 : (wide ? playerIDs.count : 2)
            let columns = Array(repeating: GridItem(.flexible(), spacing: wide ? 10 : 12), count: max(1, columnCount))
            // Upright the roll area takes everything the header, the result and the seat plates leave, so the throw
            // runs its full length across the table (Caleb, 2026-10-07: the dice had too little room).
            let plateRows = CGFloat((playerIDs.count + max(1, columnCount) - 1) / max(1, columnCount))
            let plates = plateRows * 66 + max(0, plateRows - 1) * 12
            let uprightRoll = max(260, geometry.size.height - 128 - 64 - plates - 18 * 3 - 12)
            ScrollView {
                VStack(alignment: .leading, spacing: wide ? 8 : 18) {
                    header(wide: wide)
                    // The roll area stays, so the dice stay in view under the result; it only speaks while rolling.
                    rollArea(height: wide ? max(120, geometry.size.height - 178) : uprightRoll)
                    resultAndRollControl(wide: wide)
                    LazyVGrid(columns: columns, spacing: wide ? 10 : 12) {
                        ForEach(playerIDs, id: \.self) { playerID in
                            seatPlate(playerID, compact: wide)
                        }
                    }
                }
                .frame(maxWidth: wide ? 900 : 620)
                .frame(maxWidth: .infinity)
                // The header sits at the top of the screen, not floating in the middle.
                .frame(minHeight: geometry.size.height, alignment: .top)
                .padding(.top, wide ? 4 : 8)
                .padding(.horizontal, wide ? 24 : 18)
            }
            .scrollIndicators(.hidden)
        }
        .onPreferenceChange(RollRegionKey.self) { region in
            if region.width > 1, region.height > 1 { rollRegion = region }
        }
        .background { tableLayer }
        .onAppear { unlockedStepCount = min(revealedStepCount, steps.count) }
        .onChange(of: revealedStepCount) { _, count in unlockedStepCount = min(count, steps.count) }
        .task(id: playbackKey) { await playSuppliedRounds() }
    }

    /// The tavern table fills the whole screen behind the controls; its camera frames the roll area.
    private var tableLayer: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            D20TableView(size: proxy.size, region: rollRegion.offsetBy(dx: -origin.x, dy: -origin.y),
                         state: tableState, reduceMotion: reduceMotion,
                         onEdgeHit: { turn in
                             guard turn == spinTurns, edgeHitTurn != turn else { return }
                             edgeHitTurn = turn
                             UIImpactFeedbackGenerator(style: .light).impactOccurred()
                         },
                         onRebound: { turn in
                             guard turn == spinTurns else { return }
                             reboundTurn = turn
                         },
                         onRest: { turn in
                             guard turn == spinTurns else { return }
                             restTurn = turn
                         })
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("multiplayerD20.physicsArena")
    }

    private func rollArea(height: CGFloat) -> some View {
        Color.clear
            .frame(height: height)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: RollRegionKey.self, value: proxy.frame(in: .global))
            })
            .modifier(RollAreaAccessibility(active: !playbackFinished,
                                            value: reboundTurn == spinTurns
                                                ? "Rebounded from screen edge"
                                                : edgeHitTurn == spinTurns ? "Touched screen edge" : "Rolling"))
    }

    private func resultAndRollControl(wide: Bool) -> some View {
        ZStack {
            if landed, let activeValue {
                Text("Rolled \(activeValue)")
                    .font(.system(.title2, design: .serif, weight: .heavy).monospacedDigit())
                    .foregroundStyle(Ink.brown)
                    .padding(.horizontal, 26)
                    .frame(minHeight: 46)
                    .background { TavernFill(material: .parchment).clipShape(Capsule()).padding(3) }
                    .overlay { TavernCapsuleRim() }
                    .shadow(color: .black.opacity(0.5), radius: 5, y: 3)
                    .fixedSize()
                    .accessibilityIdentifier("multiplayerD20.result")
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
            } else if let nextSeat = nextWaitingSeatID {
                if nextSeat == localSeatID {
                    Button(rollPending ? "Sharing your roll…" : "Tap to roll D20", action: onRollTap)
                        .buttonStyle(TavernButtonStyle(kind: .primary, fontSize: 17, fullWidth: true))
                        .disabled(rollPending)
                        .accessibilityIdentifier("multiplayerD20.tapToRoll")
                } else {
                    Text("Waiting for \(seatNames[nextSeat] ?? "the next player") to roll…")
                        .font(.system(.subheadline, design: .serif, weight: .bold))
                        .foregroundStyle(Ink.brass)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 36)
                        .background { TavernFill(material: .leather).clipShape(Capsule()).padding(1.5) }
                        .overlay { TavernCapsuleRim(thin: true) }
                        .accessibilityIdentifier("multiplayerD20.waiting")
                }
            }
        }
        .frame(maxWidth: wide ? 340 : 440)
        .frame(maxWidth: .infinity)
        .frame(height: wide ? 48 : 64)
    }

    private var nextWaitingSeatID: String? {
        guard activeSeatID == nil, !playbackFinished, playedStepCount == unlockedStepCount,
              steps.indices.contains(playedStepCount) else { return nil }
        return steps[playedStepCount].seatID
    }

    /// The title plate: leather in a brass frame, the skip plaque riveted at its corner. In landscape it is one
    /// line tall so the table keeps the room.
    private func header(wide: Bool) -> some View {
        Group {
            if wide {
                HStack(alignment: .center, spacing: 12) {
                    BinderTag(text: "STARTING ROLL", material: .ember, jewel: true)
                    VStack(alignment: .leading, spacing: 1) {
                        headlineText(wide: true)
                        detailText
                    }
                    Spacer(minLength: 8)
                    skipPlaque
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        BinderTag(text: "STARTING ROLL", material: .ember, jewel: true)
                        Spacer(minLength: 8)
                        skipPlaque
                    }
                    headlineText(wide: false)
                    detailText
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, wide ? 4 : 12)
        .background { TavernFill(material: .leather).clipShape(RoundedRectangle(cornerRadius: 12)).padding(2) }
        .overlay { TavernBrassFrame(scale: 0.5) }
        .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
    }

    private func headlineText(wide: Bool) -> some View {
        Text(headline)
            .font(.system(wide ? .headline : .title2, design: .serif, weight: .heavy))
            .foregroundStyle(Ink.cream)
            .shadow(color: .black.opacity(0.7), radius: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .accessibilityAddTraits(.isHeader)
    }

    private var detailText: some View {
        Text(detail)
            .font(.system(.subheadline, design: .serif, weight: .medium))
            .foregroundStyle(Ink.muted)
            .lineLimit(2)
            .minimumScaleFactor(0.8)
    }

    @ViewBuilder private var skipPlaque: some View {
        if !playbackFinished && !reduceMotion {
            Button { skipAnimation = true } label: { Text("Skip") }
                .buttonStyle(BinderPlaqueButtonStyle())
                .accessibilityLabel("Skip animation")
                .accessibilityIdentifier("multiplayerD20.skipAnimation")
        }
    }

    private var headline: String {
        if playbackFinished, let winnerName {
            return isLocalWinner ? "You go first" : "\(winnerName) goes first"
        }
        if let activeSeatID { return "\(seatNames[activeSeatID] ?? "Player") rolls" }
        if let nextWaitingSeatID {
            return nextWaitingSeatID == localSeatID ? "Your roll" : "\(seatNames[nextWaitingSeatID] ?? "Player")'s roll"
        }
        if let shownRoundIndex, shownRoundIndex > 0 { return "Tie. Roll again." }
        return "Who goes first?"
    }

    private var detail: String {
        guard let shownRoundIndex else {
            return nextWaitingSeatID == localSeatID
                ? "Tap to roll D20. Highest starts; ties reroll."
                : "Waiting for the next player to roll."
        }
        if playbackFinished, winnerName != nil { return "Round \(shownRoundIndex + 1) of \(rounds.count) · D20" }
        return "Round \(shownRoundIndex + 1) of \(rounds.count) · Highest roll starts. Ties reroll."
    }

    private var winnerName: String? {
        guard playerIDs.contains(roll.winnerSeatID) else { return nil }
        return seatNames[roll.winnerSeatID] ?? "Player"
    }

    /// A seat's name plate: parchment, with the rolled number struck on a brass coin. The winner's
    /// plate is ember glass; a seat that is out of the reroll goes dark.
    private func seatPlate(_ playerID: String, compact: Bool) -> some View {
        let name = seatNames[playerID] ?? "Player"
        let value = settledRolls[playerID]
        let isRolling = activeSeatID == playerID
        let isWinner = playbackFinished && roll.winnerSeatID == playerID
        let isOut = shownRoundIndex.map { $0 > 0 && rounds[$0][playerID] == nil && value != nil } ?? false
        let ink = isWinner ? Ink.cream : (isOut ? Ink.muted : Ink.brown)
        let secondary = isWinner ? Ink.cream.opacity(0.85) : (isOut ? Ink.muted.opacity(0.8) : Ink.brownSoft)

        return HStack(spacing: compact ? 8 : 12) {
            SeatCoin(value: isRolling ? nil : value, size: compact ? 38 : 46, lit: isWinner)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(compact ? .subheadline : .body, design: .serif, weight: .heavy))
                    .foregroundStyle(ink)
                    .lineLimit(2)
                Text(status(for: playerID, value: value, isRolling: isRolling, isOut: isOut, isWinner: isWinner))
                    .font(.system(.caption, design: .serif, weight: .semibold))
                    .foregroundStyle(secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 12 : 14)
        .padding(.vertical, compact ? 5 : 10)
        .frame(maxWidth: .infinity, minHeight: compact ? 50 : 66, alignment: .leading)
        .background {
            TavernFill(material: isWinner ? .ember : (isOut ? .leather : .parchment))
                .clipShape(RoundedRectangle(cornerRadius: 10)).padding(2)
        }
        .overlay { TavernBrassFrame(scale: 0.5) }
        .shadow(color: isWinner ? TavernPalette.ember.opacity(0.6) : .black.opacity(0.45), radius: isWinner ? 10 : 5, y: 3)
        .opacity(isOut ? 0.78 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription(for: playerID, name: name,
                                                     displayedValue: value, isRolling: isRolling,
                                                     isOut: isOut, isWinner: isWinner))
        .accessibilityIdentifier("multiplayerD20.seat.\(playerID)")
    }

    private func status(for playerID: String, value: Int?, isRolling: Bool,
                        isOut: Bool, isWinner: Bool) -> String {
        if isWinner, let value { return "Rolled \(value) · Goes first" }
        if isOut { return "Out of the reroll" }
        if isRolling { return "Rolling…" }
        guard let value else { return "Ready" }
        if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
           tiedLeaders(in: shownRoundIndex).contains(playerID) { return "Tied · reroll" }
        return "Rolled \(value)"
    }

    private func accessibilityDescription(for playerID: String, name: String, displayedValue: Int?,
                                          isRolling: Bool, isOut: Bool, isWinner: Bool) -> String {
        if isRolling { return "\(name) is rolling a twenty-sided die" }
        guard let displayedValue else { return "\(name), waiting to roll" }
        let suffix: String
        if isWinner { suffix = "goes first" }
        else if isOut { suffix = "out of the reroll" }
        else if let shownRoundIndex, shownRoundIndex < rounds.count - 1,
                tiedLeaders(in: shownRoundIndex).contains(playerID) {
            suffix = "tied for highest; rerolling"
        } else { suffix = "result" }
        return "\(name) rolled \(displayedValue) on a twenty-sided die; \(suffix)"
    }

    private func tiedLeaders(in index: Int) -> Set<String> {
        guard rounds.indices.contains(index), let highest = rounds[index].values.max() else { return [] }
        let leaders = rounds[index].filter { $0.value == highest }
        return leaders.count > 1 ? Set(leaders.map(\.key)) : []
    }

    @MainActor
    private func playSuppliedRounds() async {
        guard !steps.isEmpty else {
            shownRoundIndex = nil
            activeSeatID = nil
            settledRolls = [:]
            playbackFinished = false
            playedStepCount = 0
            tableResting = [:]
            tableThrow = nil
            return
        }
        playbackFinished = false
        while playedStepCount < steps.count {
            guard !Task.isCancelled else { return }
            guard playedStepCount < unlockedStepCount else {
                try? await Task.sleep(for: .milliseconds(80))
                continue
            }
            let step = steps[playedStepCount]
            let seat = step.seatID
            let value = step.value
            shownRoundIndex = step.roundIndex
            // A reroll starts with a bare table: the dice come up and the tied seats throw again.
            if step.roundIndex != tableRound {
                tableRound = step.roundIndex
                tableResting = [:]
                tableThrow = nil
                if !(reduceMotion || skipAnimation) {
                    try? await Task.sleep(for: .milliseconds(380))
                    guard !Task.isCancelled else { return }
                }
            }
            if reduceMotion || skipAnimation {
                // No tumble: the die lies on its number and the roll moves on.
                tableThrow = nil
                tableResting[seat] = value
                settledRolls[seat] = value
                activeSeatID = nil
                activeValue = nil
                landed = false
                playedStepCount += 1
                onStepPlayed()
                continue
            }
            settledRolls.removeValue(forKey: seat)
            tableResting.removeValue(forKey: seat)
            activeSeatID = seat
            activeValue = value
            landed = false
            edgeHitTurn = nil
            reboundTurn = nil
            restTurn = nil
            spinTurns += 1
            tableThrow = D20TableState.Throw(seatID: seat, value: value, turn: spinTurns)
            GameAudio.shared.play(.diceRoll)
            // The recording decides the path, never the result. Wait for the die to come to rest, with
            // a bounded recovery if rendering pauses (or a build has no dice assets).
            let tableReady = D20Assets.shared != nil
            for _ in 0..<(tableReady ? 90 : 6) where restTurn != spinTurns {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
            }
            tableResting[seat] = value
            tableThrow = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.58)) { landed = true }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            GameAudio.shared.play(.diceLand)
            // Give each player long enough to read the result before the roll moves on, including
            // when VoiceOver is not active.
            try? await Task.sleep(for: .milliseconds(1900))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                settledRolls[seat] = value
                activeSeatID = nil
                landed = false
            }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            playedStepCount += 1
            onStepPlayed()
        }
        withAnimation(.easeOut(duration: 0.28)) { playbackFinished = true }
        await dismissAfterResult()
    }

    @MainActor
    private func dismissAfterResult() async {
        guard winnerName != nil else { return }
        try? await Task.sleep(for: .milliseconds(reduceMotion || skipAnimation ? 1200 : 1900))
        guard !Task.isCancelled, !didAutoDismiss else { return }
        didAutoDismiss = true
        onDismiss()
    }

    private struct PlaybackKey: Equatable {
        let seatNames: [String: String]
        let rounds: [[String: Int]]
        let winnerID: String?
        let reduceMotion: Bool
        let skipAnimation: Bool
    }

    private struct RollAreaAccessibility: ViewModifier {
        let active: Bool
        let value: String

        func body(content: Content) -> some View {
            if active {
                content
                    .accessibilityElement()
                    .accessibilityLabel("D20 roll area")
                    .accessibilityValue(value)
                    .accessibilityIdentifier("multiplayerD20.rollArea")
            } else {
                content.accessibilityHidden(true)
            }
        }
    }

    private struct RollRegionKey: PreferenceKey {
        static let defaultValue: CGRect = .zero
        static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
            let next = nextValue()
            if next.width > 1 { value = next }
        }
    }

    /// The Walnut Tavern inks: cream and brass on leather, brown on parchment.
    private enum Ink {
        static let cream = Color(red: 0.98, green: 0.92, blue: 0.80)
        static let muted = Color(red: 0.84, green: 0.72, blue: 0.52)
        static let brass = Color(red: 0.98, green: 0.82, blue: 0.48)
        static let brown = Color(red: 0.24, green: 0.12, blue: 0.05)
        static let brownSoft = Color(red: 0.42, green: 0.27, blue: 0.14)
    }
}

/// The number a seat rolled, struck on a brass coin; blank (a dash) before the seat has rolled.
private struct SeatCoin: View {
    let value: Int?
    var size: CGFloat = 44
    var lit = false

    var body: some View {
        ZStack {
            if let image = UIImage(named: "tavern-ui-coin") {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Circle().fill(TavernPalette.brass)
            }
            Text(value.map(String.init) ?? "–")
                .font(.system(size: size * (value.map { $0 >= 10 } ?? false ? 0.46 : 0.54), weight: .black, design: .serif))
                .monospacedDigit()
                .foregroundStyle(Color(red: 0.25, green: 0.12, blue: 0.04).opacity(value == nil ? 0.45 : 1))
                .shadow(color: .white.opacity(0.35), radius: 0, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: lit ? TavernPalette.ember.opacity(0.9) : .clear, radius: 6)
    }
}

private struct StartingRollVisibleKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// The starting roll covers the table. The roll answers XMage's starting-player question
    /// itself (OnDeviceRootView.submitStartingChoiceIfNeeded), so the board keeps its compact
    /// prompt, the dock's "Open Choice" and the decision chime quiet until it is dismissed.
    var startingRollVisible: Bool {
        get { self[StartingRollVisibleKey.self] }
        set { self[StartingRollVisibleKey.self] = newValue }
    }
}

/// The starting roll's full-screen cover: the board's opaque canvas, so nothing behind it
/// (such as "Select a starting player") shows through, and a modal for VoiceOver.
struct StartingRollCover<Content: View>: View {
    /// Dark walnut, the room around the tavern table the roll draws over it (it also keeps the board
    /// behind from showing through while the table loads).
    static var canvas: Color { Color(red: 0.09, green: 0.05, blue: 0.03) }
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Self.canvas.ignoresSafeArea()
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    /// What the starting roll covers: hidden from VoiceOver, with its prompts quiet.
    func startingRollCovered(_ visible: Bool) -> some View {
        accessibilityHidden(visible)
            .environment(\.startingRollVisible, visible)
    }
}
