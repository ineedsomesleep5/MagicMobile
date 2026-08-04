import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { signSocketToken, verifySocketToken } from "./socket-token.mjs";

describe("XMage socket tokens", () => {
  it("accepts a signed, unexpired token for its game", () => {
    const token = signSocketToken({ sub: "user-1", gameId: "game-1", exp: 120 }, "test-secret");
    const result = verifySocketToken(token, "game-1", "test-secret", 100);
    assert.equal(result.ok, true);
    assert.equal(result.claims?.sub, "user-1");
  });

  it("rejects expired, cross-game, and tampered tokens", () => {
    const token = signSocketToken({ sub: "user-1", gameId: "game-1", exp: 120 }, "test-secret");
    assert.equal(verifySocketToken(token, "game-1", "test-secret", 120).reason, "expired_token");
    assert.equal(verifySocketToken(token, "game-2", "test-secret", 100).reason, "wrong_game");
    assert.equal(verifySocketToken(`${token}x`, "game-1", "test-secret", 100).reason, "invalid_signature");
  });

  it("keeps local development compatible when no secret is configured", () => {
    assert.equal(verifySocketToken(undefined, "game-1", "").ok, true);
  });
});
