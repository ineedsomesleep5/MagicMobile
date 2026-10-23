/**
 * The tavern room behind the menus (iOS BrandBackdrop + TavernRoomBackdrop): the rendered 3D room in three depth layers
 * that slide against each other, warm glows breathing over its flames, ember sparks rising from the hearth, a hearth
 * glow below and a vignette. On the desktop the pointer stands in for the phone's tilt. `dim` darkens it behind a page;
 * `still` holds it while a panel covers the menu (brandAmbientMotion).
 */
import { useEffect, useRef, useState } from "react";

interface Light { x: number; y: number; layer: "back" | "mid" | "front"; kind: string; radius: number }
interface Shot { width: number; height: number; lights: Light[] }
type Scene = { portrait: Shot; landscape: Shot };

const LAYERS = ["back", "mid", "front"] as const;
/** How far each layer slides: nearer moves more, which reads as depth (TavernRoomScene.Layer.depth). */
const DEPTH = { back: 0.3, mid: 0.65, front: 1 };
/** Each layer is drawn this much larger than the screen so a slide never shows its edge. */
const OVERSCAN = 1.08;
/** The furthest the nearest layer slides, in points (DeviceTilt.reach). */
const REACH = 16;

let scenePromise: Promise<Scene | undefined> | undefined;
const loadScene = () => (scenePromise ??= fetch("/menus/tavern-room.json").then((r) => (r.ok ? r.json() : undefined)).catch(() => undefined));

const frac = (v: number) => v - Math.floor(v);

export function RoomBackdrop({ dim = 0, still = false }: { dim?: number; still?: boolean }) {
  const host = useRef<HTMLDivElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const [scene, setScene] = useState<Scene>();
  const [size, setSize] = useState({ width: window.innerWidth, height: window.innerHeight });
  const offset = useRef({ x: 0, y: 0, tx: 0, ty: 0 });
  const reduce = typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  const moving = !still && !reduce;

  useEffect(() => { let live = true; loadScene().then((s) => { if (live) setScene(s); }); return () => { live = false; }; }, []);
  useEffect(() => {
    const resize = () => setSize({ width: window.innerWidth, height: window.innerHeight });
    window.addEventListener("resize", resize);
    return () => window.removeEventListener("resize", resize);
  }, []);
  useEffect(() => {
    if (!moving) { offset.current.tx = 0; offset.current.ty = 0; return; }
    const move = (e: PointerEvent) => {
      const dx = Math.max(-1, Math.min(1, (e.clientX / window.innerWidth - 0.5) * 2));
      const dy = Math.max(-1, Math.min(1, (e.clientY / window.innerHeight - 0.5) * 2));
      offset.current.tx = -dx * REACH; offset.current.ty = -dy * REACH;
    };
    window.addEventListener("pointermove", move);
    return () => window.removeEventListener("pointermove", move);
  }, [moving]);

  const orientation = size.height >= size.width ? "portrait" : "landscape";
  const shot = scene?.[orientation];

  // One canvas for the flame glows and the sparks, at 30 frames a second while moving; one still frame otherwise.
  useEffect(() => {
    const node = canvas.current;
    if (!node) return;
    const context = node.getContext("2d");
    if (!context) return;
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    node.width = Math.round(size.width * ratio); node.height = Math.round(size.height * ratio);
    const start = performance.now();
    let frame = 0; let last = 0;
    const layerNodes = host.current ? [...host.current.querySelectorAll<HTMLElement>(".mroomlayer")] : [];
    const draw = (now: number) => {
      const t = moving ? (now - start) / 1000 : 0;
      const o = offset.current;
      o.x = o.x * 0.8 + o.tx * 0.2; o.y = o.y * 0.8 + o.ty * 0.2;
      for (const layer of layerNodes) {
        const depth = DEPTH[layer.dataset.layer as keyof typeof DEPTH] ?? 0;
        layer.style.transform = `translate(${(o.x * depth).toFixed(2)}px, ${(o.y * depth).toFixed(2)}px)`;
      }
      try {
        context.setTransform(ratio, 0, 0, ratio, 0, 0);
        context.clearRect(0, 0, size.width, size.height);
        context.globalCompositeOperation = "lighter";
        if (shot) {
          const scale = Math.max(size.width * OVERSCAN / shot.width, size.height * OVERSCAN / shot.height);
          const drawnWidth = shot.width * scale, drawnHeight = shot.height * scale;
          shot.lights.forEach((light, index) => {
            const depth = DEPTH[light.layer] ?? 0.3;
            const cx = (size.width - drawnWidth) / 2 + light.x * drawnWidth + o.x * depth;
            const cy = (size.height - drawnHeight) / 2 + light.y * drawnHeight + o.y * depth;
            const seed = index * 1.618;
            const flicker = 0.78 + 0.14 * Math.sin(t * (7.1 + seed) + seed) + 0.08 * Math.sin(t * (13.3 + seed * 0.7));
            const radius = Math.max(8, light.radius * scale * shot.height * (light.kind === "hearth" ? 1.2 : 1.6)) * (0.94 + 0.06 * flicker);
            const warm = light.kind === "hearth" ? "255,115,31" : "255,158,71";
            const gradient = context.createRadialGradient(cx, cy, 0, cx, cy, radius);
            gradient.addColorStop(0, `rgba(${warm},${0.42 * flicker})`);
            gradient.addColorStop(0.5, `rgba(${warm},${0.12 * flicker})`);
            gradient.addColorStop(1, `rgba(${warm},0)`);
            context.fillStyle = gradient;
            context.beginPath(); context.arc(cx, cy, radius, 0, Math.PI * 2); context.fill();
          });
        }
        // Ember sparks rising from the hearth (BrandBackdrop.draw).
        for (let i = 0; i < 42; i++) {
          const seed = i * 12.9898;
          const r1 = frac(Math.sin(seed) * 43758.5453), r2 = frac(Math.sin(seed * 1.7) * 24634.6345), r3 = frac(Math.sin(seed * 2.3) * 93245.1);
          const life = frac(t * (0.03 + 0.045 * r1) + r2);
          const x = size.width * r3 + Math.sin(t * (0.35 + r1) + seed) * 20;
          const y = size.height * (1.04 - life * 1.08);
          const radius = 0.7 + 1.7 * r1 * (1 - life * 0.5);
          const alpha = Math.max(0, Math.sin(Math.PI * life) * (0.4 + 0.35 * Math.sin(t * 2.6 + seed)) * (1 - life * 0.4));
          context.fillStyle = i % 5 === 0 ? `rgba(255,157,126,${alpha})` : `rgba(255,128,88,${alpha})`;
          context.beginPath(); context.arc(x, y, radius, 0, Math.PI * 2); context.fill();
        }
        context.globalCompositeOperation = "source-over";
      } catch { /* a failed frame leaves the room as it was */ }
    };
    const loop = (now: number) => {
      frame = requestAnimationFrame(loop);
      if (now - last < 1000 / 30 || document.hidden) return;
      last = now;
      draw(now);
    };
    if (moving) frame = requestAnimationFrame(loop); else draw(start);
    return () => cancelAnimationFrame(frame);
  }, [moving, shot, size.width, size.height]);

  return (
    <div ref={host} className="mroom" aria-hidden="true">
      {LAYERS.map((layer) => (
        <div key={`${orientation}-${layer}`} className="mroomlayer" data-layer={layer}
          style={{ backgroundImage: `url(/menus/tavern-room-${orientation}-${layer}.webp)` }} />
      ))}
      <div className="mroomglow" />
      <canvas ref={canvas} className="mroomcanvas" />
      <div className="mroomvignette" />
      <div className="mroomdim" style={{ opacity: dim }} />
    </div>
  );
}
