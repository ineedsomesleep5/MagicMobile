import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import DeckDetailPage from "./page";

describe("DeckDetailPage", () => {
  it("shows package-backed deck stats and mock recommendation cards", async () => {
    const element = await DeckDetailPage({ params: Promise.resolve({ id: "atraxa-counters" }) });
    const html = renderToStaticMarkup(element);

    expect(html).toContain("Atraxa Counter Table");
    expect(html).toContain("Deck Stats");
    expect(html).toContain("Recommendations");
    expect(html).toContain("Command Tower");
    expect(html).toContain("Open commander page on EDHREC");
  });
});
