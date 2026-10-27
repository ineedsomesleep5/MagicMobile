import AgoraRtcKit
import AVFAudio
import SwiftUI

/// One game's voice channel (voiceRoom.ts / VoiceRoom.kt; docs/VOICE_CHAT.md). The root view makes one per online game
/// once the game has its channel and the server's voiceChat switch is on; the Agora engine starts only when the player
/// taps the mic. Tokens come from the agora-token function; one 30 s before expiry is renewed in place.
@MainActor
final class VoiceRoom: NSObject, ObservableObject {
    typealias TokenSource = @Sendable (_ channel: String, _ account: String) async throws -> (appId: String, token: String)

    @Published private(set) var state = VoiceChatState()
    let channel: String
    let account: String
    /// The table, for its seat names: the board finds a player's seat by the name shown, as quick chat does.
    weak var table: OnDeviceMultiplayer?
    private let token: TokenSource
    private var engine: AgoraRtcEngineKit?
    /// Agora's numeric ids for the seats it has told us about.
    private var seats: [UInt: String] = [:]
    private var heard: [String: Double] = [:]
    private var fade: Task<Void, Never>?
    private var closed = false
    /// Push to talk: the microphone stays off except while talk(true) holds it open.
    private(set) var pushToTalk = false

    init(channel: String, account: String, token: @escaping TokenSource) {
        self.channel = channel
        self.account = account
        self.token = token
    }

    func seat(named name: String?) -> String? {
        guard let name else { return nil }
        return table?.seatNames.first { $0.value == name }?.key
    }

    /// Joins with the microphone on; a refused microphone still joins to listen.
    func join() async {
        guard state.stage == .off, !closed else { return }
        state.stage = .joining
        do {
            let ticket = try await token(channel, account)
            let allowed = await AVAudioApplication.requestRecordPermission()
            guard !closed else { return }
            let config = AgoraRtcEngineConfig()
            config.appId = ticket.appId
            config.channelProfile = .communication
            config.audioScenario = .chatRoom
            let engine = AgoraRtcEngineKit.sharedEngine(with: config, delegate: self)
            self.engine = engine
            engine.disableVideo()
            engine.enableAudio()
            engine.setAudioProfile(.speechStandard)
            engine.setDefaultAudioRouteToSpeakerphone(true)
            engine.enableAudioVolumeIndication(200, smooth: 3, reportVad: false)
            let options = AgoraRtcChannelMediaOptions()
            options.clientRoleType = .broadcaster
            options.publishMicrophoneTrack = allowed
            options.autoSubscribeAudio = true
            if allowed && pushToTalk { engine.muteLocalAudioStream(true) }
            let code = engine.joinChannel(byToken: ticket.token, channelId: channel, userAccount: account, mediaOptions: options)
            guard code == 0 else { throw SupabaseLite.Failure(code: "voice_join_\(code)") }
            state.stage = .live
            state.muted = !allowed || pushToTalk
            state.micBlocked = !allowed
            state.inVoice.insert(account)
            startFading()
        } catch {
            teardown()
            let unavailable = SupabaseLite.code(of: error) == "voice_not_configured"
            state = VoiceChatState(stage: unavailable ? .unavailable : .off, silenced: state.silenced)
        }
    }

    /// Your microphone off or on; with a refused microphone, points to Settings' answer instead.
    func toggleMute() {
        guard state.stage == .live, let engine else { return }
        if state.micBlocked {
            if let settings = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(settings) }
            return
        }
        state.muted.toggle()
        engine.muteLocalAudioStream(state.muted)
        heard[account] = nil
        refreshSpeaking()
    }

    /// Push to talk on or off; turning it on closes the microphone until it is held.
    func setPushToTalk(_ on: Bool) {
        pushToTalk = on
        if on, !state.muted { talk(false, force: true) }
    }

    /// Push to talk: the microphone open while the mic is held, closed on release.
    func talk(_ down: Bool, force: Bool = false) {
        guard pushToTalk || force, state.stage == .live, !state.micBlocked, let engine, state.muted == down else { return }
        state.muted = !down
        engine.muteLocalAudioStream(!down)
        heard[account] = nil
        refreshSpeaking()
    }

    /// Silences a seat for you alone (they aren't told).
    func silence(_ seat: String, _ silenced: Bool) {
        if let uid = seats.first(where: { $0.value == seat })?.key { engine?.muteRemoteAudioStream(uid, mute: silenced) }
        if silenced { state.silenced.insert(seat); heard[seat] = nil } else { state.silenced.remove(seat) }
        refreshSpeaking()
    }

    /// Leaves the channel; join() works again afterwards.
    func leave() {
        teardown()
        state = VoiceChatState(silenced: state.silenced)
    }

    /// The game is over: leaves for good.
    func close() {
        closed = true
        teardown()
    }

    private func teardown() {
        fade?.cancel()
        fade = nil
        if engine != nil {
            engine?.leaveChannel(nil)
            AgoraRtcEngineKit.destroy()
        }
        engine = nil
        seats = [:]
        heard = [:]
    }

    private func startFading() {
        fade?.cancel()
        fade = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                self?.refreshSpeaking()
            }
        }
    }

    private func refreshSpeaking() {
        let now = ProcessInfo.processInfo.systemUptime
        let speaking = Set(heard.filter { VoiceChatRules.stillSpeaking(heardAt: $0.value, now: now) && !state.silenced.contains($0.key) }.keys)
        if speaking != state.speaking { state.speaking = speaking }
    }

    private func seat(for uid: UInt) -> String? {
        if let seat = seats[uid] { return seat }
        guard let account = engine?.getUserInfo(byUid: uid, withError: nil)?.userAccount else { return nil }
        seats[uid] = account
        return account
    }

    // Delegate callbacks, already on the main thread (Agora's default).
    fileprivate func joined(uid: UInt) {
        if let seat = seat(for: uid) { state.inVoice.insert(seat) }
    }

    fileprivate func named(uid: UInt, account: String?) {
        guard let account, VoiceChatRules.account(seat: account) != nil else { return }
        seats[uid] = account
        state.inVoice.insert(account)
        if state.silenced.contains(account) { engine?.muteRemoteAudioStream(uid, mute: true) }
    }

    fileprivate func left(uid: UInt) {
        guard let seat = seats.removeValue(forKey: uid) else { return }
        heard[seat] = nil
        state.inVoice.remove(seat)
        state.speaking.remove(seat)
        state.selfMuted.remove(seat)
    }

    fileprivate func levels(_ speakers: [(uid: UInt, volume: UInt)]) {
        let now = ProcessInfo.processInfo.systemUptime
        for speaker in speakers {
            // Agora reports you as uid 0.
            let seat = speaker.uid == 0 ? account : seat(for: speaker.uid)
            guard let seat, !(seat == account && (state.muted || state.micBlocked)) else { continue }
            if VoiceChatRules.isSpeaking(level: Double(speaker.volume) / 255) { heard[seat] = now }
        }
        refreshSpeaking()
    }

    fileprivate func remoteMuted(uid: UInt, _ muted: Bool) {
        guard let seat = seat(for: uid) else { return }
        if muted { state.selfMuted.insert(seat); state.speaking.remove(seat); heard[seat] = nil } else { state.selfMuted.remove(seat) }
    }

    fileprivate func renew() {
        Task { @MainActor [weak self] in
            guard let self, let engine = self.engine, let ticket = try? await self.token(self.channel, self.account) else { return }
            engine.renewToken(ticket.token)
        }
    }

    fileprivate func expired() {
        let muted = state.muted
        leave()
        Task { @MainActor [weak self] in
            await self?.join()
            if muted, self?.pushToTalk == false, self?.state.stage == .live, self?.state.muted == false { self?.toggleMute() }
        }
    }
}

extension VoiceRoom: AgoraRtcEngineDelegate {
    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didJoinedOfUid uid: UInt, elapsed: Int) {
        Task { @MainActor in self.joined(uid: uid) }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didUserInfoUpdatedWithUserId uid: UInt, userInfo: AgoraUserInfo) {
        let account = userInfo.userAccount
        Task { @MainActor in self.named(uid: uid, account: account) }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, didOfflineOfUid uid: UInt, reason: AgoraUserOfflineReason) {
        Task { @MainActor in self.left(uid: uid) }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, reportAudioVolumeIndicationOfSpeakers speakers: [AgoraRtcAudioVolumeInfo],
                               totalVolume: Int) {
        let levels = speakers.map { (uid: $0.uid, volume: $0.volume) }
        Task { @MainActor in self.levels(levels) }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, remoteAudioStateChangedOfUid uid: UInt, state: AgoraAudioRemoteState,
                               reason: AgoraAudioRemoteReason, elapsed: Int) {
        guard reason == .remoteMuted || reason == .remoteUnmuted else { return }
        let muted = reason == .remoteMuted
        Task { @MainActor in self.remoteMuted(uid: uid, muted) }
    }

    nonisolated func rtcEngine(_ engine: AgoraRtcEngineKit, tokenPrivilegeWillExpire token: String) {
        Task { @MainActor in self.renew() }
    }

    nonisolated func rtcEngineRequestToken(_ engine: AgoraRtcEngineKit) {
        Task { @MainActor in self.expired() }
    }
}

private struct VoiceRoomKey: EnvironmentKey { static let defaultValue: VoiceRoom? = nil }

extension EnvironmentValues {
    /// Set by online games while the server's voiceChat switch is on; the board shows the mic only then.
    var voiceRoom: VoiceRoom? {
        get { self[VoiceRoomKey.self] }
        set { self[VoiceRoomKey.self] = newValue }
    }
}
