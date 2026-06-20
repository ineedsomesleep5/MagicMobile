"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import * as THREE from "three";

export interface BattlefieldVisualCard {
  id: string;
  name: string;
  imageUrl?: string;
  zone: "opponent-land" | "opponent-creature" | "player-creature" | "player-land" | "hand";
  tapped?: boolean;
  power?: number;
  toughness?: number;
}

export interface ThreeBattlefieldProps {
  cards: BattlefieldVisualCard[];
  activePlayerName: string;
  phase: string;
}

const zoneLayout: Record<BattlefieldVisualCard["zone"], { y: number; z: number; scale: number }> = {
  "opponent-land": { y: 3.05, z: -0.18, scale: 0.92 },
  "opponent-creature": { y: 1.54, z: 0.16, scale: 1.04 },
  "player-creature": { y: -1.08, z: 0.16, scale: 1.12 },
  "player-land": { y: -2.52, z: -0.08, scale: 0.96 },
  hand: { y: -4, z: 0.42, scale: 1.24 }
};

const cardWidth = 0.94;
const cardHeight = 1.32;

export function ThreeBattlefield({ cards, activePlayerName, phase }: ThreeBattlefieldProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const [selectedName, setSelectedName] = useState(cards.find((card) => card.zone === "hand")?.name ?? "None");
  const renderCards = useMemo(() => cards, [cards]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const parent = canvas?.parentElement;
    if (!canvas || !parent) return;

    const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true, preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    const scene = new THREE.Scene();
    scene.fog = new THREE.Fog("#1f292a", 10, 20);

    const camera = new THREE.PerspectiveCamera(39, 1, 0.1, 100);
    camera.position.set(0, -7.45, 8.15);
    camera.lookAt(0, -0.15, 0);

    const ambient = new THREE.AmbientLight("#eef6f1", 1.85);
    scene.add(ambient);

    const phaseLight = new THREE.PointLight(phase === "Combat" ? "#ff9a38" : "#35c7ff", 42, 18);
    phaseLight.position.set(3.5, -3.2, 4);
    scene.add(phaseLight);

    const board = new THREE.Mesh(
      new THREE.PlaneGeometry(12.8, 8.2, 16, 10),
      new THREE.MeshStandardMaterial({
        color: "#3f4b4c",
        roughness: 0.78,
        metalness: 0.04,
        emissive: "#152122",
        emissiveIntensity: 0.28
      })
    );
    board.rotation.x = -Math.PI / 2;
    scene.add(board);

    const grid = new THREE.GridHelper(13, 18, "#6f7b79", "#334242");
    grid.position.y = 0.03;
    scene.add(grid);

    const loader = new THREE.TextureLoader();
    loader.setCrossOrigin("anonymous");
    const cardMeshes: THREE.Mesh[] = [];
    const disposableMeshes: THREE.Mesh[] = [];
    const byZone = groupByZone(renderCards);

    for (const card of renderCards) {
      const zoneCards = byZone.get(card.zone) ?? [];
      const zoneIndex = zoneCards.indexOf(card);
      const layout = zoneLayout[card.zone];
      const spread = card.zone === "hand" ? 1.05 : 0.9;
      const x = (zoneIndex - (zoneCards.length - 1) / 2) * spread;
      const yFan = card.zone === "hand" ? Math.abs(zoneIndex - (zoneCards.length - 1) / 2) * -0.08 : 0;
      const glowColor = card.zone === "hand" ? "#31cfff" : card.zone.includes("creature") ? "#e8d28b" : "#1fd093";
      const backing = new THREE.Mesh(
        new THREE.PlaneGeometry(cardWidth * layout.scale + 0.09, cardHeight * layout.scale + 0.09),
        new THREE.MeshBasicMaterial({ color: glowColor, transparent: true, opacity: card.zone === "hand" ? 0.58 : 0.42 })
      );
      backing.position.set(x, layout.y + yFan, layout.z - 0.012 + zoneIndex * 0.002);
      backing.rotation.x = -0.18;
      backing.rotation.z =
        (card.tapped ? -Math.PI / 2 : 0) +
        (card.zone === "hand" ? (zoneIndex - (zoneCards.length - 1) / 2) * 0.08 : 0);
      scene.add(backing);
      disposableMeshes.push(backing);

      const material = new THREE.MeshBasicMaterial({
        color: "#fff9ed",
        map: createFallbackCardTexture(card),
        side: THREE.DoubleSide
      });

      if (card.imageUrl) {
        loader.load(
          card.imageUrl,
          (texture) => {
            texture.colorSpace = THREE.SRGBColorSpace;
            material.map = texture;
            material.needsUpdate = true;
          },
          undefined,
          () => {
            material.map = createFallbackCardTexture(card);
            material.needsUpdate = true;
          }
        );
      }

      const mesh = new THREE.Mesh(new THREE.PlaneGeometry(cardWidth * layout.scale, cardHeight * layout.scale), material);
      mesh.position.set(x, layout.y + yFan, layout.z + zoneIndex * 0.002);
      mesh.rotation.x = -0.18;
      mesh.rotation.z =
        (card.tapped ? -Math.PI / 2 : 0) +
        (card.zone === "hand" ? (zoneIndex - (zoneCards.length - 1) / 2) * 0.08 : 0);
      mesh.userData = { card, glow: backing };
      scene.add(mesh);
      cardMeshes.push(mesh);

      if (card.power !== undefined && card.toughness !== undefined) {
        const badge = new THREE.Mesh(
          new THREE.PlaneGeometry(0.42 * layout.scale, 0.18 * layout.scale),
          new THREE.MeshBasicMaterial({ map: createStatTexture(`${card.power}/${card.toughness}`), transparent: true })
        );
        badge.position.set(x + 0.23 * layout.scale, layout.y + yFan - 0.49 * layout.scale, layout.z + 0.03 + zoneIndex * 0.002);
        badge.rotation.x = -0.18;
        badge.rotation.z = mesh.rotation.z;
        scene.add(badge);
        disposableMeshes.push(badge);
      }
    }

    const raycaster = new THREE.Raycaster();
    const pointer = new THREE.Vector2();
    let hovered: THREE.Mesh | undefined;
    let animationFrame = 0;

    const resize = () => {
      const rect = parent.getBoundingClientRect();
      renderer.setSize(rect.width, rect.height, false);
      camera.aspect = rect.width / rect.height;
      camera.updateProjectionMatrix();
    };

    const animate = () => {
      animationFrame = requestAnimationFrame(animate);
      const boardMaterial = board.material;
      boardMaterial.emissiveIntensity = 0.35 + Math.sin(Date.now() / 900) * 0.08;
      renderer.render(scene, camera);
    };

    const updatePointer = (event: PointerEvent) => {
      const rect = canvas.getBoundingClientRect();
      pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      pointer.y = -((event.clientY - rect.top) / rect.height) * 2 + 1;
      raycaster.setFromCamera(pointer, camera);
      const next = raycaster.intersectObjects(cardMeshes)[0]?.object as THREE.Mesh | undefined;

      if (hovered && hovered !== next) {
        hovered.scale.setScalar(1);
        const previousGlow = hovered.userData.glow as THREE.Mesh | undefined;
        if (previousGlow) previousGlow.scale.setScalar(1);
      }
      hovered = next;
      if (hovered) {
        hovered.scale.setScalar(1.12);
        const nextGlow = hovered.userData.glow as THREE.Mesh | undefined;
        if (nextGlow) nextGlow.scale.setScalar(1.12);
      }
    };

    const selectCard = () => {
      const card = hovered?.userData.card as BattlefieldVisualCard | undefined;
      if (card) setSelectedName(card.name);
    };

    resize();
    animate();
    canvas.addEventListener("pointermove", updatePointer);
    canvas.addEventListener("pointerdown", selectCard);
    const observer = new ResizeObserver(resize);
    observer.observe(parent);

    return () => {
      cancelAnimationFrame(animationFrame);
      observer.disconnect();
      canvas.removeEventListener("pointermove", updatePointer);
      canvas.removeEventListener("pointerdown", selectCard);
      renderer.dispose();
      board.geometry.dispose();
      board.material.dispose();
      for (const mesh of [...cardMeshes, ...disposableMeshes]) {
        mesh.geometry.dispose();
        if (Array.isArray(mesh.material)) {
          for (const material of mesh.material) material.dispose();
        } else {
          mesh.material.dispose();
        }
      }
    };
  }, [activePlayerName, phase, renderCards]);

  return (
    <div className="three-battlefield" data-testid="three-battlefield">
      <canvas ref={canvasRef} aria-label="3D Commander battlefield" className="three-battlefield-canvas" />
      <div className="three-battlefield-overlay">
        <span>Priority: {activePlayerName}</span>
        <strong>{phase}</strong>
        <span>Selected: {selectedName}</span>
      </div>
    </div>
  );
}

function createFallbackCardTexture(card: BattlefieldVisualCard): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 488;
  canvas.height = 680;
  const context = canvas.getContext("2d");
  if (!context) return new THREE.CanvasTexture(canvas);

  const gradient = context.createLinearGradient(0, 0, canvas.width, canvas.height);
  gradient.addColorStop(0, card.zone.includes("land") ? "#d9c18b" : "#d8ede2");
  gradient.addColorStop(1, card.zone.includes("creature") ? "#24433a" : "#26373b");
  context.fillStyle = "#171311";
  context.fillRect(0, 0, canvas.width, canvas.height);
  roundRect(context, 22, 22, canvas.width - 44, canvas.height - 44, 26);
  context.fillStyle = gradient;
  context.fill();
  context.strokeStyle = "#0c0c0c";
  context.lineWidth = 18;
  context.stroke();

  context.fillStyle = "rgba(255, 248, 224, 0.9)";
  roundRect(context, 46, 48, canvas.width - 92, 62, 12);
  context.fill();
  context.fillStyle = "#151210";
  context.font = "700 30px serif";
  fitText(context, card.name, 64, 90, canvas.width - 128);

  context.fillStyle = "rgba(12, 18, 18, 0.68)";
  roundRect(context, 58, 146, canvas.width - 116, 300, 18);
  context.fill();
  context.fillStyle = "rgba(255,255,255,0.2)";
  context.fillRect(92, 194, canvas.width - 184, 10);
  context.fillRect(92, 232, canvas.width - 184, 10);
  context.fillRect(92, 270, canvas.width - 184, 10);

  context.fillStyle = "rgba(255, 248, 224, 0.9)";
  roundRect(context, 46, 474, canvas.width - 92, 98, 12);
  context.fill();
  context.fillStyle = "#151210";
  context.font = "600 24px serif";
  context.fillText(card.zone.includes("land") ? "Land" : "Creature", 64, 515);
  context.font = "500 20px sans-serif";
  context.fillText("Image loading...", 64, 548);

  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function createStatTexture(text: string): THREE.CanvasTexture {
  const canvas = document.createElement("canvas");
  canvas.width = 192;
  canvas.height = 84;
  const context = canvas.getContext("2d");
  if (!context) return new THREE.CanvasTexture(canvas);
  context.fillStyle = "#f9eed7";
  roundRect(context, 10, 10, 172, 64, 24);
  context.fill();
  context.strokeStyle = "#241b12";
  context.lineWidth = 8;
  context.stroke();
  context.fillStyle = "#1a130d";
  context.font = "800 38px sans-serif";
  context.textAlign = "center";
  context.textBaseline = "middle";
  context.fillText(text, 96, 42);
  const texture = new THREE.CanvasTexture(canvas);
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

function roundRect(context: CanvasRenderingContext2D, x: number, y: number, width: number, height: number, radius: number) {
  context.beginPath();
  context.moveTo(x + radius, y);
  context.arcTo(x + width, y, x + width, y + height, radius);
  context.arcTo(x + width, y + height, x, y + height, radius);
  context.arcTo(x, y + height, x, y, radius);
  context.arcTo(x, y, x + width, y, radius);
  context.closePath();
}

function fitText(context: CanvasRenderingContext2D, text: string, x: number, y: number, maxWidth: number) {
  let display = text;
  while (context.measureText(display).width > maxWidth && display.length > 10) {
    display = `${display.slice(0, -2)}...`;
  }
  context.fillText(display, x, y);
}

function groupByZone(cards: BattlefieldVisualCard[]): Map<BattlefieldVisualCard["zone"], BattlefieldVisualCard[]> {
  const groups = new Map<BattlefieldVisualCard["zone"], BattlefieldVisualCard[]>();
  for (const card of cards) {
    groups.set(card.zone, [...(groups.get(card.zone) ?? []), card]);
  }
  return groups;
}
