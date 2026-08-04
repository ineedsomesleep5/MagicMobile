import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import DeckDetailPage from "./page";

describe("DeckDetailPage", () => {
  it("renders the cloud-backed deck editor for the requested deck", async () => {
    const element = await DeckDetailPage({ params: Promise.resolve({ id: "deck-123" }) });
    const html = renderToStaticMarkup(element);

    expect(html).toContain("Edit spellbook");
    expect(html).toContain("Save deck");
    expect(html).toContain("Import in seconds");
    expect(html).toContain("Live preview");
  });
});
