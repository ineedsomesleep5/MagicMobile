/**
 * feedback-cases.json: the Send feedback note, its contact, and the fixed payload (iOS FeedbackTests, Android FeedbackParityTest).
 * The account test checks the RPC body against a fake server.
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { FeedbackDraft, PlayerAccountRules, webDeviceLabel } from "../src/core/account";

const root = JSON.parse(readFileSync(join(__dirname, "..", "..", "..", "apps/android/core/src/test/resources/parity/feedback-cases.json"), "utf8"));

describe("feedback-cases.json", () => {
  it("matches the server caps", () => {
    expect(FeedbackDraft.MAX_MESSAGE).toBe(root.maxMessage);
    expect(FeedbackDraft.MAX_CONTACT).toBe(root.maxContact);
  });

  it("trims notes and contacts", () => {
    for (const item of root.messages) expect(FeedbackDraft.message(item.input) ?? null, item.name).toBe(item.output);
    for (const item of root.contacts) {
      const contact = FeedbackDraft.contact(item.input);
      expect(contact.ok, item.name).toBe(item.ok);
      expect(contact.value, item.name).toBe(item.output);
    }
  });

  it("caps length and drops controls while typing", () => {
    expect(FeedbackDraft.message("a".repeat(FeedbackDraft.MAX_MESSAGE + 1))).toBeUndefined();
    expect(FeedbackDraft.message("a".repeat(FeedbackDraft.MAX_MESSAGE))).toBe("a".repeat(FeedbackDraft.MAX_MESSAGE));
    expect(FeedbackDraft.contact("a".repeat(FeedbackDraft.MAX_CONTACT + 1)).ok).toBe(false);
    expect(FeedbackDraft.contact("a".repeat(FeedbackDraft.MAX_CONTACT)).ok).toBe(true);
    expect(FeedbackDraft.chars(FeedbackDraft.cleanMessage("a".repeat(FeedbackDraft.MAX_MESSAGE + 5)))).toBe(FeedbackDraft.MAX_MESSAGE);
    expect(FeedbackDraft.chars(FeedbackDraft.cleanContact("a".repeat(FeedbackDraft.MAX_CONTACT + 10)))).toBe(FeedbackDraft.MAX_CONTACT);
    expect(FeedbackDraft.cleanMessage("a\u0001b\nc")).toBe("ab\nc");
    expect(FeedbackDraft.cleanContact("a\nb")).toBe("ab");
  });

  it("sends the note and the device only", () => {
    const keys = [...root.payloadKeys].sort();
    for (const item of root.payloads) {
      const params = FeedbackDraft.params(item.kind, item.message, item.contact, item.platform, item.version, item.build, item.device);
      if (item.ok) {
        expect(params, item.name).toBeDefined();
        expect(Object.keys(params!).sort(), item.name).toEqual(keys);
        expect(Object.keys(params!).some((key) => key.toLowerCase().includes("deck")), item.name).toBe(false);
        expect(params!.p_message, item.name).toBe(item.messageOut);
        expect(params!.p_contact, item.name).toBe(item.contactOut);
        expect(params!.p_platform, item.name).toBe(item.platform);
      } else {
        expect(params, item.name).toBeUndefined();
      }
    }
  });

  it("uses the same sentences as the account rules where the server raises them", () => {
    for (const [code, message] of Object.entries(root.notices)) expect(FeedbackDraft.notice(code), code).toBe(message);
    expect(FeedbackDraft.notice("nope")).toBe(FeedbackDraft.notice("error"));
    for (const code of ["invalid_feedback", "too_many_feedback", "not_signed_in"]) {
      expect(PlayerAccountRules.message(code), code).toBe(FeedbackDraft.notice(code));
    }
  });
});

describe("web device label", () => {
  it("names the system and the browser, and stays inside the device cap", () => {
    expect(webDeviceLabel("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.0 Safari/605.1.15")).toBe("macOS · Safari");
    expect(webDeviceLabel("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36")).toBe("Windows · Chrome");
    expect(webDeviceLabel("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Version/17.0 Mobile Safari/604.1")).toBe("iOS · Safari");
    expect(webDeviceLabel("Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36")).toBe("Android · Chrome");
    expect(webDeviceLabel("")).toBe("Web · Browser");
    expect([...webDeviceLabel("x".repeat(500))].length).toBeLessThanOrEqual(FeedbackDraft.MAX_DEVICE);
  });
});
