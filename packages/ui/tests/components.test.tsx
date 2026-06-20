import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Button, DigitalSeat, RuleZeroCard } from "../src";

describe("@magicmobile/ui components", () => {
  it("renders a primary button", () => {
    const html = renderToStaticMarkup(<Button tone="primary">Start Game</Button>);
    expect(html).toContain("Start Game");
    expect(html).toContain("mm-button-primary");
  });

  it("renders distinct seat copy", () => {
    const html = renderToStaticMarkup(<DigitalSeat name="Caleb" status="ready" />);
    expect(html).toContain("Digital battlefield");
    expect(html).toContain("mm-seat-digital");
  });

  it("renders Rule 0 talking points", () => {
    const html = renderToStaticMarkup(<RuleZeroCard headline="Casual bracket three" talkingPoints={["No fast combo"]} />);
    expect(html).toContain("Casual bracket three");
    expect(html).toContain("No fast combo");
  });
});
