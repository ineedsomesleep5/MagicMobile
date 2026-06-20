import type { CSSProperties } from "react";

export interface HandFanTransform {
  x: number;
  y: number;
  rotation: number;
  zIndex: number;
}

export function getHandFanTransform(index: number, count: number): HandFanTransform {
  const center = (count - 1) / 2;
  const offset = index - center;
  const spread = count > 7 ? 66 : 78;

  return {
    x: Math.round(offset * spread),
    y: Math.round(Math.abs(offset) * 9),
    rotation: Number((offset * 5.5).toFixed(2)),
    zIndex: 20 + index
  };
}

export function getHandFanStyle(index: number, count: number, selected: boolean): CSSProperties {
  const transform = getHandFanTransform(index, count);
  const selectedLift = selected ? -54 : 0;
  const rotation = selected ? 0 : transform.rotation;

  return {
    zIndex: selected ? 80 : transform.zIndex,
    transform: `translateX(${transform.x}px) translateY(${transform.y + selectedLift}px) rotate(${rotation}deg)`
  };
}
