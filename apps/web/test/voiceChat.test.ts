/** Voice chat (docs/VOICE_CHAT.md): the shared rules (parity/voice-cases.json, iOS VoiceChatRulesTests, Android
 * VoiceChatRulesTest) and VoiceRoom against a stand-in for the Agora SDK. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it, vi } from "vitest";
import { AppConfig } from "../src/core/appConfig";
import { VOICE_SWITCH, VoiceChat } from "../src/core/voiceChat";
import { type VoiceSDK, VoiceRoom } from "../src/table/voiceRoom";

const cases = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/voice-cases.json"), "utf8"));

describe("voice chat rules", () => {
  it("matches the parity cases", () => {
    expect(VoiceChat.speakingLevel).toBe(cases.speakingLevel);
    expect(VoiceChat.holdSeconds).toBe(cases.holdSeconds);
    for (const c of cases.channel) expect(VoiceChat.channel(c.epoch ?? undefined) ?? null).toBe(c.channel);
    for (const c of cases.account) expect(VoiceChat.account(c.seat ?? undefined) ?? null).toBe(c.account);
    for (const c of cases.level) expect(VoiceChat.isSpeaking(c.level)).toBe(c.speaking);
    for (const c of cases.hold) expect(VoiceChat.stillSpeaking(c.heardAt ?? undefined, c.now)).toBe(c.speaking);
    for (const c of cases.shown) expect(VoiceChat.shown(c)).toBe(c.shown);
  });

  it("stays off until the server names the switch", () => {
    expect(AppConfig.isOn(AppConfig.empty(), VOICE_SWITCH, false)).toBe(false);
    expect(AppConfig.isOn(AppConfig.parse({ switches: { voiceChat: true } })!, VOICE_SWITCH, false)).toBe(true);
  });
});

/** A stand-in for AgoraRTC: one client whose events the test fires. */
function fakeAgora(options: { micRefused?: boolean } = {}) {
  const handlers = new Map<string, (...args: unknown[]) => unknown>();
  const mic = { setMuted: vi.fn(async () => undefined), close: vi.fn() };
  const client = {
    on: (event: string, handler: (...args: unknown[]) => unknown) => { handlers.set(event, handler); },
    join: vi.fn(async () => "player1"),
    leave: vi.fn(async () => undefined),
    publish: vi.fn(async () => undefined),
    subscribe: vi.fn(async () => undefined),
    renewToken: vi.fn(async () => undefined),
    enableAudioVolumeIndicator: vi.fn(),
    removeAllListeners: vi.fn(),
  };
  const sdk = {
    createClient: () => client,
    createMicrophoneAudioTrack: vi.fn(async () => { if (options.micRefused) throw new Error("NotAllowedError"); return mic; }),
  } as unknown as VoiceSDK;
  const fire = async (event: string, ...args: unknown[]) => { await handlers.get(event)?.(...args); };
  return { sdk, client, mic, fire };
}

const channel = "mm-1b9d6bcd-bbfd-4b2d-9b5d-ab8dfbbd4bed";

describe("voice room", () => {
  it("joins with the mic on, lights who talks, mutes and leaves", async () => {
    const agora = fakeAgora();
    const token = vi.fn(async () => ({ appId: "app", token: "007abc" }));
    const room = new VoiceRoom(channel, "player1", token, async () => agora.sdk);
    await room.join();
    expect(token).toHaveBeenCalledWith(channel, "player1");
    expect(agora.client.join).toHaveBeenCalledWith("app", channel, "007abc", "player1");
    expect(agora.client.publish).toHaveBeenCalledWith(agora.mic);
    expect(room.state).toMatchObject({ stage: "live", muted: false, micBlocked: false, inVoice: ["player1"] });

    const audio = { play: vi.fn(), stop: vi.fn() };
    const jed = { uid: "player2", audioTrack: audio };
    await agora.fire("user-joined", jed);
    await agora.fire("user-published", jed, "audio");
    expect(agora.client.subscribe).toHaveBeenCalledWith(jed, "audio");
    expect(audio.play).toHaveBeenCalled();
    await agora.fire("volume-indicator", [{ uid: "player2", level: 40 }, { uid: "player1", level: 2 }]);
    expect(room.state.speaking).toEqual(["player2"]);
    expect(room.state.inVoice).toEqual(["player1", "player2"]);

    room.silence("player2", true);
    expect(audio.stop).toHaveBeenCalled();
    expect(room.state).toMatchObject({ silenced: ["player2"], speaking: [] });

    await agora.fire("user-info-updated", "player2", "mute-audio");
    expect(room.state.selfMuted).toEqual(["player2"]);

    await room.toggleMute();
    expect(agora.mic.setMuted).toHaveBeenCalledWith(true);
    expect(room.state.muted).toBe(true);
    // Your own level while muted never lights you.
    await agora.fire("volume-indicator", [{ uid: "player1", level: 90 }]);
    expect(room.state.speaking).toEqual([]);

    await agora.fire("token-privilege-will-expire");
    expect(agora.client.renewToken).toHaveBeenCalledWith("007abc");

    await room.leave();
    expect(agora.mic.close).toHaveBeenCalled();
    expect(agora.client.leave).toHaveBeenCalled();
    expect(room.state).toMatchObject({ stage: "off", inVoice: [], silenced: ["player2"] });
  });

  it("listens when the microphone is refused, and hides the mic when the server isn't set up", async () => {
    const refused = fakeAgora({ micRefused: true });
    const room = new VoiceRoom(channel, "player2", async () => ({ appId: "app", token: "t" }), async () => refused.sdk);
    await room.join();
    expect(room.state).toMatchObject({ stage: "live", muted: true, micBlocked: true });
    expect(refused.client.publish).not.toHaveBeenCalled();

    const unset = new VoiceRoom(channel, "player2", async () => { throw Object.assign(new Error("voice_not_configured"), { code: "voice_not_configured" }); },
      async () => fakeAgora().sdk);
    await expect(unset.join()).rejects.toThrow();
    expect(unset.state.stage).toBe("unavailable");
  });
});
