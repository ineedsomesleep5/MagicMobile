/**
 * Behind the result (GameResultBackdrop): a warm gold wash with slow rays and motes rising across the whole screen for
 * a win; a deep red wash with ash drifting down for a loss. Still under reduced motion.
 */
import { useEffect, useRef } from "react";
import { noise } from "./fxPainter";

const GOLD = "rgb(255,204,92)";

export function ResultBackdrop({ victory }: { victory: boolean }) {
  const ref = useRef<HTMLCanvasElement>(null);
  useEffect(() => {
    const canvas = ref.current;
    const ctx = canvas?.getContext("2d");
    if (!canvas || !ctx || window.matchMedia?.("(prefers-reduced-motion: reduce)").matches) return;
    const start = performance.now();
    let frame = 0;
    const draw = () => {
      // A frame that can't be drawn is skipped; the backdrop keeps going.
      try { paintFrame(); } catch (error) { console.warn("result backdrop frame skipped", error); }
      frame = requestAnimationFrame(draw);
    };
    const paintFrame = () => {
      const ratio = Math.min(2, window.devicePixelRatio || 1);
      const w = canvas.clientWidth, h = canvas.clientHeight;
      if (canvas.width !== Math.round(w * ratio) || canvas.height !== Math.round(h * ratio)) { canvas.width = Math.round(w * ratio); canvas.height = Math.round(h * ratio); }
      ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
      ctx.clearRect(0, 0, w, h);
      const t = (performance.now() - start) / 1000;
      const intro = Math.min(1, t / 0.8);
      const cx = w / 2, cy = h * 0.42, reach = Math.hypot(w, h);
      if (victory) {
        // BoardFXPainter.rays: fourteen soft rays turning slowly about the centre.
        ctx.save();
        ctx.globalCompositeOperation = "lighter";
        ctx.globalAlpha = 0.5;
        const radius = reach * 0.7;
        const gradient = ctx.createRadialGradient(cx, cy, 0, cx, cy, radius);
        gradient.addColorStop(0, "rgba(255,204,92,.9)"); gradient.addColorStop(1, "rgba(255,204,92,0)");
        ctx.fillStyle = gradient;
        for (let i = 0; i < 14; i++) {
          const angle = (i / 14) * 2 * Math.PI + t * 0.6 * 0.35;
          ctx.beginPath(); ctx.moveTo(cx, cy);
          ctx.lineTo(cx + Math.cos(angle - 0.09) * radius, cy + Math.sin(angle - 0.09) * radius);
          ctx.lineTo(cx + Math.cos(angle + 0.09) * radius, cy + Math.sin(angle + 0.09) * radius);
          ctx.closePath(); ctx.fill();
        }
        // Motes rise across the whole screen, not a band.
        for (let i = 0; i < 70; i++) {
          const speed = 0.05 + 0.08 * noise(9, i, 1);
          const life = (t * speed + noise(9, i, 2)) % 1;
          const x = w * noise(9, i, 3) + Math.sin(t * 0.8 + i) * 14;
          const y = h * (1.02 - 1.08 * life);
          const r = 1.2 + 2.4 * noise(9, i, 4);
          ctx.globalAlpha = Math.max(0, intro * Math.sin(Math.PI * life) * (0.55 + 0.45 * Math.sin(t * 3 + i)));
          ctx.fillStyle = i % 3 === 0 ? "#fff" : GOLD;
          ctx.beginPath(); ctx.arc(x, y, r, 0, Math.PI * 2); ctx.fill();
        }
        ctx.restore();
      } else {
        ctx.save();
        ctx.fillStyle = "rgb(191,179,173)";
        for (let i = 0; i < 60; i++) {
          const life = (t * (0.06 + 0.08 * noise(3, i, 1)) + noise(3, i, 2)) % 1;
          const x = w * noise(3, i, 3) + Math.sin(t + i) * 12;
          const y = h * (1.08 * life - 0.04);
          ctx.globalAlpha = Math.max(0, 0.5 * Math.sin(Math.PI * life) * intro);
          ctx.beginPath(); ctx.ellipse(x + 1.5, y + 1.5, 1.5, 1.5, 0, 0, Math.PI * 2); ctx.fill();
        }
        ctx.restore();
      }
    };
    frame = requestAnimationFrame(draw);
    return () => cancelAnimationFrame(frame);
  }, [victory]);
  return (
    <div className={`abackdrop ${victory ? "win" : "loss"}`} aria-hidden="true">
      <canvas ref={ref} />
    </div>
  );
}
