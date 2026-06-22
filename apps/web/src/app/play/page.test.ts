import React from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it, vi } from "vitest";
import PlayPage from "./page";

vi.mock("@/lib/scryfall-cards", () => ({
  fetchCardVisuals: vi.fn(async () => new Map())
}));

vi.mock("@/lib/engine", () => ({
  createRuntimeEngineAdapter: vi.fn(() => ({
    getHealth: vi.fn(async () => ({
      status: "unavailable",
      reason: "XMage gateway unavailable in test",
      checkedAt: new Date(0).toISOString(),
      recoveryAction: "restart_gateway"
    }))
  }))
}));

describe("PlayPage", () => {
  it("requires XMage for the production play route", async () => {
    const element = await PlayPage();
    const html = renderToStaticMarkup(element);

    expect(html).toContain("Horizontal game battlefield");
    expect(html).toContain("XMage setup required");
    expect(html).toContain("docker compose up --build xmage-bridge xmage-gateway");
    expect(html).not.toContain("Simulator preview");
  });
});
