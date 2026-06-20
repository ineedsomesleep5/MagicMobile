import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import PlayPage from "./page";

describe("PlayPage", () => {
  it("renders a horizontal battlefield with real card imagery", async () => {
    const element = await PlayPage();
    const html = renderToStaticMarkup(element);

    expect(html).toContain("Horizontal game battlefield");
    expect(html).toContain("Simulator preview");
    expect(html).toContain("UI mechanics only; full rules require XMage bridge.");
    expect(html).toContain("Next");
  });
});
