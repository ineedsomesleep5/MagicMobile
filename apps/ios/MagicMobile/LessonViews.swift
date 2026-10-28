import SwiftUI

/// What the lesson's coach points at on the board (Lessons.swift): cards and players by ID, or a control.
struct LessonFocus: Equatable {
    var ids: Set<String> = []
    var control: String?
    var isEmpty: Bool { ids.isEmpty && control == nil }
}

private struct LessonFocusKey: EnvironmentKey { static let defaultValue = LessonFocus() }
/// The board tells a lesson which opponent it shows (a swap step waits for one).
private struct LessonFocusReportKey: EnvironmentKey { static let defaultValue: ((String) -> Void)? = nil }

extension EnvironmentValues {
    var lessonFocus: LessonFocus {
        get { self[LessonFocusKey.self] }
        set { self[LessonFocusKey.self] = newValue }
    }
    var lessonFocusReport: ((String) -> Void)? {
        get { self[LessonFocusReportKey.self] }
        set { self[LessonFocusReportKey.self] = newValue }
    }
}

/// Hands the run's focus to the board as it changes.
struct LessonFocusProvider: ViewModifier {
    @ObservedObject var run: LessonRun
    func body(content: Content) -> some View {
        content.environment(\.lessonFocus, LessonFocus(ids: run.spotIDs, control: run.spotControl))
            .environment(\.lessonFocusReport, { run.boardFocused($0) })
    }
}

/// The lesson's focus on the board while a lesson is on the table.
struct LessonFocusIfAny: ViewModifier {
    let run: LessonRun?
    func body(content: Content) -> some View {
        if let run { content.modifier(LessonFocusProvider(run: run)) } else { content }
    }
}

/// The ring the coach draws around what to touch next: a brass glow that breathes.
struct LessonFocusRing: View {
    let rect: CGRect
    var circle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    var body: some View {
        let shape = circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        shape
            .stroke(ArenaMenuStyle.gold, lineWidth: 3)
            .shadow(color: ArenaMenuStyle.gold.opacity(0.9), radius: breathe ? 12 : 5)
            .frame(width: rect.width + 12, height: rect.height + 12)
            .scaleEffect(breathe && !reduceMotion ? 1.05 : 1)
            .position(x: rect.midX, y: rect.midY)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { breathe = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Maren's note at the top of the table: the moment's title and a sentence or two; Got it on a note, and Next Lesson
/// and Done once the lesson is over. A wrong move shakes the card and says so.
struct LessonCoachCard: View {
    @ObservedObject var run: LessonRun
    /// Next Lesson, or after the last one the guided game.
    let nextTitle: String
    let next: (() -> Void)?
    let done: () -> Void
    @State private var shake: CGFloat = 0
    @State private var nudged = false

    var body: some View {
        Group {
            if run.complete || run.coach != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TavernTag(text: LessonText.coach.uppercased(), accent: TavernPalette.ember)
                        TavernPanelTitle(text: run.complete ? LessonText.complete : run.coach?.title ?? run.script.title)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(nudged ? LessonText.nudge : run.complete && run.coach == nil ? LessonText.allComplete : run.coach?.text ?? "")
                        .font(.system(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(TavernPalette.parchment)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("lesson.coach.text")
                    if run.complete {
                        HStack(spacing: 10) {
                            Button(LessonText.done, action: done)
                                .buttonStyle(TavernButtonStyle(kind: .secondary, compact: true))
                                .accessibilityIdentifier("lesson.done")
                            Spacer(minLength: 0)
                            if let next {
                                Button(nextTitle, action: next)
                                    .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                                    .accessibilityIdentifier("lesson.next")
                            }
                        }
                    } else if run.waitsForGotIt {
                        HStack {
                            Spacer(minLength: 0)
                            Button(LessonText.gotIt) { run.gotIt() }
                                .buttonStyle(TavernButtonStyle(kind: .primary, compact: true))
                                .accessibilityIdentifier("lesson.gotIt")
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: 420, alignment: .leading)
                .modifier(TavernPanelChrome(tavern: true, cornerRadius: 12))
                .shadow(color: .black.opacity(0.55), radius: 10, y: 4)
                .offset(x: shake)
                .padding(.horizontal, 16)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("lesson.coach")
            }
        }
        .onChange(of: run.nudges) { _, _ in
            nudged = true
            withAnimation(.interpolatingSpring(stiffness: 900, damping: 9)) { shake = 10 }
            withAnimation(.interpolatingSpring(stiffness: 900, damping: 9).delay(0.08)) { shake = 0 }
        }
        .onChange(of: run.coach) { _, _ in nudged = false }
    }
}

/// The lessons in order, a check on each one finished, then the guided game.
struct LessonListView: View {
    let play: (String) -> Void
    let playGuided: (() -> Void)?
    let back: () -> Void
    @State private var completed = LessonProgress.completed(in: MagicMobilePreferences.current)

    var body: some View {
        VStack(spacing: 0) {
            ArenaPanelHeader(title: LessonText.title, back: back, closeIdentifier: "lessons.close")
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(LessonCatalog.all.enumerated()), id: \.element.id) { index, lesson in
                        row(number: "\(index + 1)", title: lesson.title, done: completed.contains(lesson.id),
                            next: lesson.id == firstUnfinished) { play(lesson.id) }
                            .accessibilityIdentifier("lessons.\(lesson.id)")
                    }
                    if let playGuided {
                        row(number: "\(LessonCatalog.all.count + 1)", title: LessonText.guided, done: false,
                            next: firstUnfinished == nil, action: playGuided)
                            .accessibilityIdentifier("lessons.guided")
                    }
                }
                .padding(16)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var firstUnfinished: String? { LessonCatalog.all.first { !completed.contains($0.id) }?.id }

    private func row(number: String, title: String, done: Bool, next: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.black.opacity(0.7))
                    Circle().strokeBorder(next ? AnyShapeStyle(ArenaMenuStyle.gold) : AnyShapeStyle(ArenaGlass.hairline), lineWidth: next ? 1.5 : 0.9)
                    if done {
                        Image(systemName: "checkmark").font(.system(size: 15, weight: .black)).foregroundStyle(ArenaMenuStyle.gold)
                    } else {
                        Text(number).font(ArenaMenuStyle.font(17, .bold)).foregroundStyle(ArenaMenuStyle.text)
                    }
                }
                .frame(width: 38, height: 38)
                Text(title)
                    .font(ArenaMenuStyle.font(18, .bold))
                    .foregroundStyle(ArenaMenuStyle.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HowToPlayPlaque(text: done ? "Replay" : "Play", icon: "chevron.right", primary: next)
            }
            .padding(12)
            .background(shape.fill(Color.black.opacity(0.45)))
            .clipShape(shape)
            .overlay(shape.strokeBorder(ArenaGlass.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "\(title), finished" : title)
    }
}
