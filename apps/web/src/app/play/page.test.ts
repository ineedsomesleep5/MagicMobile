import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import PlayPage from "./page";

describe("PlayPage", () => {
  it("renders a game snapshot from the mock engine adapter", async () => {
    const element = await PlayPage();
    const html = renderToStaticMarkup(element);

    expect(html).toContain("Mock engine game");
    expect(html).toContain("Game mock-game-1 created");
    expect(html).toContain("Beginning");
  });
});
