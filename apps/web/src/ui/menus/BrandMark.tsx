/**
 * MagicMobile's mark (iOS BrandMark): the coral card frame, the sparkle and the monogram cast in brass, with a glint every
 * 4.5 s (a quick swell of the sparkle and a warm glow behind it). `glint` false draws it still, as the top bar does.
 */
import { useId } from "react";
import { BRAND_MARK } from "./brandMarkPaths";

export function BrandMark({ size = 28, glint = false }: { size?: number; glint?: boolean }) {
  const id = useId().replace(/:/g, "");
  const { x, y } = BRAND_MARK.sparkleCenter;
  return (
    <svg className={`mbrand ${glint ? "glint" : ""}`} viewBox="0 0 1000 1000" width={size} height={size} aria-hidden="true">
      <defs>
        <linearGradient id={`brass${id}`} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor="#ffe69e" /><stop offset="1" stopColor="#d1943d" /></linearGradient>
        <radialGradient id={`glow${id}`}><stop offset="0" stopColor="#ff9d7e" /><stop offset="1" stopColor="#ff9d7e" stopOpacity="0" /></radialGradient>
      </defs>
      <path d={BRAND_MARK.cardFrame} fill="#fd6648" />
      {glint && <circle className="mbrandglow" cx={x} cy={y} r="200" fill={`url(#glow${id})`} />}
      <path className="mbrandspark" d={BRAND_MARK.sparkle} fill="#fd6648" style={{ transformOrigin: `${x}px ${y}px` }} />
      <path d={BRAND_MARK.monogram} fill={`url(#brass${id})`} />
    </svg>
  );
}
