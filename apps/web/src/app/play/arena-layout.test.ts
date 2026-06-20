import { describe, expect, it } from "vitest";
import { getHandFanStyle, getHandFanTransform } from "./arena-layout";

describe("arena hand fan layout", () => {
  it.each([
    { count: 1, expectedFirst: { x: 0, y: 0, rotation: 0, zIndex: 20 } },
    { count: 3, expectedFirst: { x: -78, y: 9, rotation: -5.5, zIndex: 20 } },
    { count: 7, expectedFirst: { x: -234, y: 27, rotation: -16.5, zIndex: 20 } },
    { count: 10, expectedFirst: { x: -297, y: 41, rotation: -24.75, zIndex: 20 } }
  ])("fans $count cards from a stable bottom-center arc", ({ count, expectedFirst }) => {
    expect(getHandFanTransform(0, count)).toEqual(expectedFirst);
  });

  it("lifts and straightens the selected hand card", () => {
    expect(getHandFanStyle(2, 5, true)).toEqual({
      zIndex: 80,
      transform: "translateX(0px) translateY(-54px) rotate(0deg)"
    });
  });
});
