/**
 * One game's voice channel (VoiceRoom.swift / .kt; docs/VOICE_CHAT.md). The Agora SDK loads only when a player taps the
 * mic, so tables without voice never download it. Tokens come from the agora-token function (supabase/functions); one
 * 30 s before expiry is renewed in place.
 */
import type { IAgoraRTCClient, IAgoraRTCRemoteUser, IMicrophoneAudioTrack, UID } from "agora-rtc-sdk-ng";
import { VoiceChat, type VoiceState } from "../core/voiceChat";

export interface VoiceToken { appId: string; token: string }
/** The agora-token function; rejects with a SupabaseFailure ("voice_not_configured", "offline"…). */
export type VoiceTokenSource = (channel: string, account: string) => Promise<VoiceToken>;

/** The slice of AgoraRTC this room uses, so tests can stand in for it. */
export interface VoiceSDK {
  createClient(config: { mode: "rtc"; codec: "vp8" }): IAgoraRTCClient;
  createMicrophoneAudioTrack(config: { AEC: boolean; ANS: boolean; AGC: boolean }): Promise<IMicrophoneAudioTrack>;
  setLogLevel?(level: number): void;
}

const loadAgora = async (): Promise<VoiceSDK> => {
  const sdk = (await import("agora-rtc-sdk-ng")).default;
  sdk.setLogLevel(3);
  return sdk as unknown as VoiceSDK;
};

const now = () => performance.now() / 1000;
const without = (list: string[], seat: string) => list.filter((s) => s !== seat);
const adding = (list: string[], seat: string) => (list.includes(seat) ? list : [...list, seat]);

export class VoiceRoom {
  state: VoiceState = VoiceChat.initial();
  version = 0;
  private listeners = new Set<() => void>();
  private client?: IAgoraRTCClient;
  private mic?: IMicrophoneAudioTrack;
  private remote = new Map<string, IAgoraRTCRemoteUser>();
  private heard = new Map<string, number>();
  private ticker?: ReturnType<typeof setInterval>;
  private closed = false;

  constructor(readonly channel: string, readonly account: string, private token: VoiceTokenSource,
    private load: () => Promise<VoiceSDK> = loadAgora) {}

  subscribe(listener: () => void) { this.listeners.add(listener); return () => { this.listeners.delete(listener); }; }

  private set(patch: Partial<VoiceState>) {
    this.state = { ...this.state, ...patch };
    this.version += 1;
    this.listeners.forEach((l) => l());
  }

  /** Joins with the microphone on; a refused microphone still joins to listen. */
  async join(): Promise<void> {
    if (this.state.stage !== "off" || this.closed) return;
    this.set({ stage: "joining" });
    try {
      const [sdk, ticket] = await Promise.all([this.load(), this.token(this.channel, this.account)]);
      if (this.closed) return;
      const client = sdk.createClient({ mode: "rtc", codec: "vp8" });
      this.client = client;
      this.listen(client);
      await client.join(ticket.appId, this.channel, ticket.token, this.account);
      if (this.closed) { await client.leave().catch(() => undefined); return; }
      client.enableAudioVolumeIndicator();
      this.ticker = setInterval(() => this.fade(), 200);
      this.set({ stage: "live", inVoice: adding(this.state.inVoice, this.account) });
      try {
        this.mic = await sdk.createMicrophoneAudioTrack({ AEC: true, ANS: true, AGC: true });
        if (this.closed) { this.mic.close(); return; }
        await client.publish(this.mic);
        this.set({ muted: false, micBlocked: false });
      } catch {
        this.set({ muted: true, micBlocked: true });
      }
    } catch (error) {
      await this.teardown();
      const code = (error as { code?: string } | undefined)?.code;
      // The server without the Agora certificate, or the switch off there: hide the mic for this game.
      this.set({ ...VoiceChat.initial(), stage: code === "voice_not_configured" ? "unavailable" : "off" });
      throw error;
    }
  }

  private listen(client: IAgoraRTCClient) {
    client.on("user-joined", (user) => { const seat = String(user.uid); this.remote.set(seat, user); this.set({ inVoice: adding(this.state.inVoice, seat) }); });
    client.on("user-left", (user) => {
      const seat = String(user.uid);
      this.remote.delete(seat); this.heard.delete(seat);
      this.set({ inVoice: without(this.state.inVoice, seat), speaking: without(this.state.speaking, seat), selfMuted: without(this.state.selfMuted, seat) });
    });
    client.on("user-published", async (user, mediaType) => {
      if (mediaType !== "audio") return;
      const seat = String(user.uid);
      this.remote.set(seat, user);
      try {
        await client.subscribe(user, "audio");
        if (!this.state.silenced.includes(seat)) user.audioTrack?.play();
      } catch { /* the next publish tries again */ }
      this.set({ inVoice: adding(this.state.inVoice, seat), selfMuted: without(this.state.selfMuted, seat) });
    });
    client.on("user-info-updated", (uid: UID, message: string) => {
      const seat = String(uid);
      if (message === "mute-audio") this.set({ selfMuted: adding(this.state.selfMuted, seat), speaking: without(this.state.speaking, seat) });
      else if (message === "unmute-audio") this.set({ selfMuted: without(this.state.selfMuted, seat) });
    });
    client.on("volume-indicator", (levels: { uid: UID; level: number }[]) => {
      const at = now();
      for (const { uid, level } of levels) {
        const seat = String(uid);
        if (seat === this.account && (this.state.muted || this.state.micBlocked)) continue;
        if (VoiceChat.isSpeaking(level / 100)) this.heard.set(seat, at);
      }
      this.fade();
    });
    client.on("token-privilege-will-expire", async () => {
      try { await client.renewToken((await this.token(this.channel, this.account)).token); } catch { /* did-expire rejoins */ }
    });
    client.on("token-privilege-did-expire", () => { void this.rejoin(); });
  }

  /** Recomputes who is lit from the last loud reports. */
  private fade() {
    const at = now();
    const speaking = [...this.heard.entries()].filter(([seat, heardAt]) => VoiceChat.stillSpeaking(heardAt, at) && !this.state.silenced.includes(seat))
      .map(([seat]) => seat).sort();
    if (speaking.join() !== this.state.speaking.join()) this.set({ speaking });
  }

  private async rejoin() {
    const muted = this.state.muted;
    await this.teardown();
    this.set({ ...VoiceChat.initial(), silenced: this.state.silenced });
    await this.join().catch(() => undefined);
    if (muted && this.state.stage === "live") await this.toggleMute();
  }

  /** Your microphone off or on; with a refused microphone, asks again. */
  async toggleMute(): Promise<void> {
    if (this.state.stage !== "live" || !this.client) return;
    if (this.state.micBlocked) {
      try {
        const sdk = await this.load();
        this.mic = await sdk.createMicrophoneAudioTrack({ AEC: true, ANS: true, AGC: true });
        await this.client.publish(this.mic);
        this.set({ muted: false, micBlocked: false });
      } catch { /* still refused */ }
      return;
    }
    const muted = !this.state.muted;
    await this.mic?.setMuted(muted);
    this.heard.delete(this.account);
    this.set({ muted });
    this.fade();
  }

  /** Silences a seat for you alone (they aren't told). */
  silence(seat: string, silenced: boolean) {
    const track = this.remote.get(seat)?.audioTrack;
    if (silenced) { track?.stop(); this.heard.delete(seat); } else track?.play();
    this.set({ silenced: silenced ? adding(this.state.silenced, seat) : without(this.state.silenced, seat) });
    this.fade();
  }

  /** Leaves the channel; join() works again afterwards. */
  async leave(): Promise<void> {
    await this.teardown();
    this.set({ ...VoiceChat.initial(), silenced: this.state.silenced });
  }

  /** The game is over: leaves for good. */
  close() {
    this.closed = true;
    void this.teardown();
  }

  private async teardown() {
    if (this.ticker !== undefined) clearInterval(this.ticker);
    this.ticker = undefined;
    this.mic?.close();
    this.mic = undefined;
    const client = this.client;
    this.client = undefined;
    client?.removeAllListeners();
    this.remote.clear(); this.heard.clear();
    await client?.leave().catch(() => undefined);
  }
}
