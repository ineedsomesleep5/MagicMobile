import SwiftUI

/// Voice chat on the Arena board (VoiceRoom; docs/VOICE_CHAT.md; the web board's .amic, .aspeak and .avoice). Each view
/// observes the room itself, so speaking levels redraw these small views and never the board.
enum ArenaVoice {
    static let talking = Color(red: 0.55, green: 1, blue: 0.65)
    static let muted = Color(red: 1, green: 0.54, blue: 0.48)
}

/// The mic by your medallion: tap to join voice (mic on), then to turn your microphone off and on.
struct ArenaVoiceMic: View {
    @ObservedObject var room: VoiceRoom
    @AppStorage(VoiceChatRules.pushToTalkKey, store: MagicMobilePreferences.current) private var pushToTalk = false

    var body: some View {
        Group {
            // The server without the Agora certificate answers once; the mic then goes for this game.
            if room.state.stage != .unavailable {
                // Push to talk while live: held, the microphone is open; let go, it closes.
                if pushToTalk, room.state.stage == .live, !room.state.micBlocked {
                    label
                        .gesture(DragGesture(minimumDistance: 0).onChanged { _ in room.talk(true) }.onEnded { _ in room.talk(false) })
                        .accessibilityElement()
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Hold to talk")
                        .accessibilityIdentifier("board.voice.mic")
                } else {
                    mic
                }
            }
        }
        .onChange(of: pushToTalk, initial: true) { _, on in room.setPushToTalk(on) }
    }

    private var mic: some View {
        let state = room.state
        return Button {
            if state.stage == .off { Task { await room.join() } } else { room.toggleMute() }
        } label: {
            label
        }
        .buttonStyle(.plain)
        .disabled(state.stage == .joining)
        .accessibilityLabel(state.stage == .off ? "Join voice chat" : state.micBlocked ? "Microphone not allowed, open Settings"
                            : state.muted ? "Turn your microphone on" : "Turn your microphone off")
        .accessibilityIdentifier("board.voice.mic")
    }

    private var label: some View {
        let state = room.state
        let live = state.stage == .live
        let talking = live && state.speaking.contains(room.account)
        return Image(systemName: live && !state.muted ? "mic.fill" : "mic.slash.fill")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(talking ? ArenaVoice.talking : live && state.muted ? ArenaVoice.muted
                             : live ? ArenaMenuStyle.gold : ArenaMenuStyle.gold.opacity(0.7))
            .frame(width: 30, height: 30)
            .background(Circle().fill(LinearGradient(colors: [ArenaGlass.top, ArenaGlass.bottom], startPoint: .top, endPoint: .bottom)))
            .overlay(Circle().strokeBorder(talking ? AnyShapeStyle(ArenaVoice.talking) : live && state.muted ? AnyShapeStyle(ArenaVoice.muted.opacity(0.85))
                                           : AnyShapeStyle(ArenaGlass.hairline), lineWidth: 1))
            .shadow(color: talking ? ArenaVoice.talking.opacity(0.6) : .black.opacity(0.5), radius: talking ? 6 : 2, y: talking ? 0 : 1)
            .opacity(state.stage == .joining ? 0.5 : 1)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
}

/// A green halo round a player who is talking, and on an opponent in voice a small mic (red when muted).
struct ArenaVoiceHalo: View {
    @ObservedObject var room: VoiceRoom
    let seat: String
    let diameter: CGFloat
    var badge = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let state = room.state
        let talking = state.speaking.contains(seat)
        let quiet = state.selfMuted.contains(seat) || state.silenced.contains(seat)
        ZStack {
            if talking {
                Circle()
                    .strokeBorder(ArenaVoice.talking.opacity(0.9), lineWidth: 2)
                    .frame(width: diameter * 1.16, height: diameter * 1.16)
                    .shadow(color: ArenaVoice.talking.opacity(0.6), radius: diameter * 0.12)
                    .opacity(pulse || reduceMotion ? 1 : 0.6)
                    .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.45).repeatForever()) { pulse = true } } }
                    .onDisappear { pulse = false }
            }
            if badge, state.stage == .live, state.inVoice.contains(seat) {
                Image(systemName: quiet ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: diameter * 0.18, weight: .bold))
                    .foregroundStyle(quiet ? ArenaVoice.muted : ArenaMenuStyle.gold)
                    .frame(width: diameter * 0.34, height: diameter * 0.34)
                    .background(Circle().fill(ArenaGlass.bottom))
                    .overlay(Circle().strokeBorder(ArenaGlass.hairline, lineWidth: 1))
                    .offset(x: diameter * 0.4, y: -diameter * 0.4)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Mute Voice / Unmute Voice on an opponent's player card, for you alone.
struct ArenaVoiceSilenceButton: View {
    @ObservedObject var room: VoiceRoom
    let seat: String

    var body: some View {
        if room.state.stage == .live, room.state.inVoice.contains(seat) {
            let silenced = room.state.silenced.contains(seat)
            Button(silenced ? "Unmute Voice" : "Mute Voice") { room.silence(seat, !silenced) }
                .buttonStyle(ArenaButtonStyle(kind: .secondary, compact: true))
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("board.voice.silence")
        }
    }
}
