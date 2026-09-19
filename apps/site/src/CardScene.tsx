import { useEffect, useRef, useState, type CSSProperties } from "react";
import * as THREE from "three";
import { RoundedBoxGeometry } from "three/examples/jsm/geometries/RoundedBoxGeometry.js";
import { ArrowsClockwise, Pause, Play } from "@phosphor-icons/react";
import "./CardScene.css";
import { cards as cardArt } from "./cards";

export default function CardScene({ actId = "cards" }: { actId?: string }) {
  const host = useRef<HTMLDivElement>(null);
  const flipped = useRef(false);
  const paused = useRef(false);
  const wakeRef = useRef<() => void>(() => {});
  const [ready, setReady] = useState(false);
  const [failed, setFailed] = useState(false);
  const [isPaused, setPaused] = useState(false);
  const [isFlipped, setFlipped] = useState(false);

  useEffect(() => {
    const element = host.current!;
    const act = document.getElementById(actId);
    const motion = matchMedia("(prefers-reduced-motion: reduce)");
    let reduced = motion.matches;
    let renderer: THREE.WebGLRenderer;
    try {
      renderer = new THREE.WebGLRenderer({
        antialias: true,
        alpha: true,
        powerPreference: "low-power",
      });
    } catch {
      setFailed(true);
      return;
    }
    renderer.setPixelRatio(Math.min(devicePixelRatio, 1.5));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.setClearColor(0, 0);
    element.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(34, 1, 0.1, 60);
    const hand = new THREE.Group();
    scene.add(hand);
    const bodyGeometry = new RoundedBoxGeometry(2.5, 3.5, 0.055, 2, 0.075);
    const faceGeometry = new THREE.PlaneGeometry(2.43, 3.43);
    const edge = new THREE.MeshBasicMaterial({ color: 0x11100f });
    const materials: THREE.Material[] = [edge];
    const textures: THREE.Texture[] = [];
    const cards: THREE.Group[] = [];
    let disposed = false,
      loaded = false,
      visible = true,
      frame = 0,
      last = 0,
      lastPaint = -100,
      elapsed = 0,
      turn = 0;
    const pointer = { x: 0, y: 0 };

    const draw = (now: number) => {
      frame = 0;
      if (disposed || !visible || document.hidden || !loaded) return;
      if (now - lastPaint < 1000 / 30) {
        frame = requestAnimationFrame(draw);
        return;
      }
      lastPaint = now;
      const delta = Math.min((now - last) / 1000, 0.05);
      last = now;
      if (!paused.current && !reduced) elapsed += delta;
      const raw = act
        ? Number.parseFloat(getComputedStyle(act).getPropertyValue("--sc-p")) ||
          0
        : 0;
      const progress = reduced ? 0.35 : THREE.MathUtils.clamp(raw, 0, 1);
      const spread = 0.6 + progress * 0.5;
      const targetTurn = flipped.current ? Math.PI : 0;
      turn = reduced
        ? targetTurn
        : THREE.MathUtils.damp(turn, targetTurn, 10, delta);
      hand.rotation.set(
        reduced ? 0.04 : -0.06 - pointer.y * 0.09,
        reduced ? 0 : pointer.x * 0.13,
        -0.055 + progress * 0.08,
      );
      cards.forEach((card, index) => {
        const offset = index - 3;
        const middle = offset === 0;
        card.position.set(
          offset * 1.14 * spread,
          middle
            ? 0.44
            : -Math.abs(offset) * 0.2 +
                Math.sin(elapsed * 0.65 + index * 0.8) * 0.035,
          // Parallel background cards form a strict stack; the center has
          // clearance for its entire rotation without crossing that stack.
          middle ? 1.5 : -0.4 + index * 0.06,
        );
        card.rotation.set(
          middle ? -0.035 : 0,
          middle ? turn - 0.11 + (reduced ? 0 : progress * Math.PI * 2) : 0,
          middle ? -0.035 : -offset * (0.13 + progress * 0.025),
        );
      });
      renderer.render(scene, camera);
      if ((!paused.current && !reduced) || Math.abs(turn - targetTurn) > 0.001)
        frame = requestAnimationFrame(draw);
    };
    const wake = () => {
      if (!frame && !disposed && visible && !document.hidden) {
        last = performance.now();
        frame = requestAnimationFrame(draw);
      }
    };
    wakeRef.current = wake;
    const loader = new THREE.TextureLoader();
    const load = (path: string) =>
      new Promise<THREE.Texture>((resolve, reject) => {
        const texture = loader.load(path, resolve, undefined, reject);
        textures.push(texture);
      });
    Promise.all([...cardArt.map((card) => load(card.image)), load("/magic-card-back.webp")])
      .then((images) => {
        if (disposed) {
          textures.forEach((texture) => texture.dispose());
          return;
        }
        for (const texture of images) {
          texture.colorSpace = THREE.SRGBColorSpace;
          texture.anisotropy = Math.min(
            4,
            renderer.capabilities.getMaxAnisotropy(),
          );
        }
        const fronts = images.slice(0, 7).map((map) => new THREE.MeshBasicMaterial({ map }));
        const backMaterial = new THREE.MeshBasicMaterial({ map: images[7] });
        materials.push(...fronts, backMaterial);
        for (let index = 0; index < 7; index++) {
          const card = new THREE.Group();
          card.add(new THREE.Mesh(bodyGeometry, edge));
          const face = new THREE.Mesh(
            faceGeometry,
            fronts[index],
          );
          face.position.z = 0.031;
          const reverse = new THREE.Mesh(faceGeometry, backMaterial);
          reverse.position.z = -0.031;
          reverse.rotation.y = Math.PI;
          card.add(face, reverse);
          hand.add(card);
          cards.push(card);
        }
        loaded = true;
        // Paint the complete hand before exposing the canvas; never expose half-loaded textures.
        draw(performance.now());
        setReady(true);
        wake();
      })
      .catch(() => {
        if (!disposed) setFailed(true);
      });
    const resize = () => {
      const { width, height } = element.getBoundingClientRect();
      if (!width || !height) return;
      renderer.setSize(width, height);
      camera.aspect = width / height;
      camera.position.z = Math.max(
        10.8,
        5.5 / (Math.tan((17 * Math.PI) / 180) * camera.aspect),
      );
      camera.position.y = 0.1;
      camera.updateProjectionMatrix();
      wake();
    };
    const observer = new ResizeObserver(resize);
    observer.observe(element);
    const intersection = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting;
      if (visible) wake();
      else {
        cancelAnimationFrame(frame);
        frame = 0;
      }
    });
    intersection.observe(element);
    const move = (event: PointerEvent) => {
      if (reduced || event.pointerType === "touch") return;
      const bounds = element.getBoundingClientRect();
      pointer.x = THREE.MathUtils.clamp(
        ((event.clientX - bounds.left) / bounds.width) * 2 - 1,
        -1,
        1,
      );
      pointer.y = THREE.MathUtils.clamp(
        ((event.clientY - bounds.top) / bounds.height) * 2 - 1,
        -1,
        1,
      );
      wake();
    };
    const leave = () => {
      pointer.x = 0;
      pointer.y = 0;
      wake();
    };
    const visibility = () => {
      if (document.hidden) {
        cancelAnimationFrame(frame);
        frame = 0;
      } else wake();
    };
    const motionChange = () => {
      reduced = motion.matches;
      wake();
    };
    const lost = (event: Event) => {
      event.preventDefault();
      setFailed(true);
      loaded = false;
      cancelAnimationFrame(frame);
      frame = 0;
    };
    element.addEventListener("pointermove", move);
    element.addEventListener("pointerleave", leave);
    window.addEventListener("scroll", wake, { passive: true });
    document.addEventListener("visibilitychange", visibility);
    motion.addEventListener("change", motionChange);
    renderer.domElement.addEventListener("webglcontextlost", lost);
    resize();
    return () => {
      disposed = true;
      cancelAnimationFrame(frame);
      wakeRef.current = () => {};
      observer.disconnect();
      intersection.disconnect();
      element.removeEventListener("pointermove", move);
      element.removeEventListener("pointerleave", leave);
      window.removeEventListener("scroll", wake);
      document.removeEventListener("visibilitychange", visibility);
      motion.removeEventListener("change", motionChange);
      renderer.domElement.removeEventListener("webglcontextlost", lost);
      bodyGeometry.dispose();
      faceGeometry.dispose();
      materials.forEach((material) => material.dispose());
      textures.forEach((texture) => texture.dispose());
      renderer.dispose();
      renderer.domElement.remove();
    };
  }, [actId]);

  return (
    <div className="hand-experience">
      <div
        ref={host}
        className={`hand-canvas ${ready && !failed ? "hand-ready" : ""}`}
        aria-hidden="true"
      />
      {(!ready || failed) && (
        <div
          className="hand-fallback"
          aria-label="A seven-card hand with Black Lotus at its center"
        >
          {[0, 1, 2, 4, 5, 6, 3].map((index) => (
            <img
              key={index}
              style={{ "--hand-index": index - 3 } as CSSProperties}
              className={index === 3 ? "hand-center" : ""}
              src={
                index === 3 && isFlipped
                  ? "/magic-card-back.webp"
                  : cardArt[index].image
              }
              alt={
                index === 3 && isFlipped
                  ? "Magic: The Gathering card back"
                  : `${cardArt[index].name} card`
              }
              width="488"
              height="680"
            />
          ))}
        </div>
      )}
      <div className="hand-tools">
        <span className="hand-label">Your opening hand</span>
        <button
          aria-label={
            isFlipped ? "Show Black Lotus front" : "Turn Black Lotus over"
          }
          onClick={() => {
            flipped.current = !flipped.current;
            setFlipped(flipped.current);
            wakeRef.current();
          }}
        >
          <ArrowsClockwise size={16} />
          <span>Flip card</span>
        </button>
        <button
          aria-label={
            isPaused
              ? "Resume ambient card motion"
              : "Pause ambient card motion"
          }
          aria-pressed={isPaused}
          onClick={() => {
            paused.current = !paused.current;
            setPaused(paused.current);
            wakeRef.current();
          }}
        >
          {isPaused ? <Play size={16} /> : <Pause size={16} />}
        </button>
      </div>
    </div>
  );
}
