/**
 * The Three.js table: the landscape Walnut Tavern plate (956 x 440 design points, as on the phones)
 * seen through a pitched camera, with every permanent lying on it as a framed tile. Your rows sit in
 * the lower half, opponents' in the upper half; lands at the outer edges, creatures near the middle
 * (the Duel Board Prototype's arrangement). Tapped tiles tilt and dim; glows mark what you can do.
 * Renders on demand: only while something moves or a texture arrives.
 */
import * as THREE from "three";
import type { ZoneCard } from "../core/models";
import { frameKind, type FrameKind, glowCanvas, paintTile, TILE, tileKey } from "./tileArt";

export type TileGlow = "none" | "playable" | "target" | "selected" | "attacking" | "blocking" | "chosen";

export interface BoardTile {
  card: ZoneCard;
  owner: "me" | "opponent";
  /** Which opponent band (0-based) for multiplayer tables. */
  band: number;
  bands: number;
  glow: TileGlow;
}

const PLATE = { width: 956, height: 440 } as const;
/** The play mat on the landscape plate (scripts/brand/tavern_layout.json, top-left origin). */
const MAT = { left: 172, top: 8, right: 782, bottom: 400 } as const;
const toWorld = (x: number, y: number) => new THREE.Vector3(x - PLATE.width / 2, PLATE.height / 2 - y, 0);
const MAT_MID = PLATE.height / 2 - (MAT.top + MAT.bottom) / 2;
const TILE_W = 64;
const TILE_H = TILE_W * (TILE.height / TILE.width);
const glowColors: Record<Exclude<TileGlow, "none">, number> = {
  playable: 0x7ff0ff, target: 0xc6f8ff, selected: 0xffe08f, attacking: 0xff5a2e, blocking: 0xffd38a, chosen: 0xffe08f,
};

interface TileObject {
  group: THREE.Group;
  face: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>;
  halo: THREE.Mesh<THREE.PlaneGeometry, THREE.MeshBasicMaterial>;
  key: string;
  target: THREE.Vector3;
  rotation: number;
  tapped: boolean;
}

/** Creatures in the front row near the middle; lands, artifacts and enchantments behind them. */
const rowOf = (card: ZoneCard): 0 | 1 => (/creature/i.test(card.card.typeLine) || card.isCreaturePermanent ? 0 : 1);

export class TableScene {
  private renderer: THREE.WebGLRenderer;
  private scene = new THREE.Scene();
  private camera = new THREE.PerspectiveCamera(32, 16 / 9, 10, 4000);
  private tiles = new Map<string, TileObject>();
  private textures = new Map<string, { texture: THREE.CanvasTexture; users: number }>();
  private glows = new Map<FrameKind, THREE.CanvasTexture>();
  private raycaster = new THREE.Raycaster();
  private pointer = new THREE.Vector2();
  private frame = 0;
  private animating = false;
  private disposed = false;
  private hovered?: string;
  onTileClick?: (instanceId: string) => void;
  onTileHover?: (instanceId: string | undefined, card: ZoneCard | undefined) => void;
  private cards = new Map<string, ZoneCard>();

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: false });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.outputColorSpace = THREE.SRGBColorSpace;
    this.scene.background = new THREE.Color(0x1b120b);
    const loader = new THREE.TextureLoader();
    const plateTexture = loader.load("/tavern/table.webp", () => this.invalidate());
    plateTexture.colorSpace = THREE.SRGBColorSpace;
    plateTexture.anisotropy = this.renderer.capabilities.getMaxAnisotropy();
    const plate = new THREE.Mesh(new THREE.PlaneGeometry(PLATE.width, PLATE.height), new THREE.MeshBasicMaterial({ map: plateTexture }));
    this.scene.add(plate);
    // Warm lamplight pooled over the middle of the table.
    const lampCanvas = document.createElement("canvas");
    lampCanvas.width = 256; lampCanvas.height = 128;
    const lctx = lampCanvas.getContext("2d")!;
    const gradient = lctx.createRadialGradient(128, 64, 4, 128, 64, 128);
    gradient.addColorStop(0, "rgba(255,196,120,0.22)"); gradient.addColorStop(0.55, "rgba(255,160,80,0.06)"); gradient.addColorStop(1, "rgba(0,0,0,0)");
    lctx.fillStyle = gradient; lctx.fillRect(0, 0, 256, 128);
    const lamp = new THREE.Mesh(new THREE.PlaneGeometry(PLATE.width * 0.9, PLATE.height * 0.9),
      new THREE.MeshBasicMaterial({ map: new THREE.CanvasTexture(lampCanvas), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false }));
    lamp.position.z = 0.5;
    this.scene.add(lamp);
    canvas.addEventListener("pointermove", this.pointerMove);
    canvas.addEventListener("pointerleave", this.pointerLeave);
    canvas.addEventListener("click", this.click);
    document.addEventListener("visibilitychange", this.visibility);
    this.resize();
  }

  /** Fits the plate to the canvas: a pitched view that keeps the whole table in frame. */
  resize() {
    const width = this.canvas.clientWidth || 1;
    const height = this.canvas.clientHeight || 1;
    this.renderer.setSize(width, height, false);
    this.camera.aspect = width / height;
    const pitch = THREE.MathUtils.degToRad(20);
    const vFov = THREE.MathUtils.degToRad(this.camera.fov);
    // The plate's outer wood may crop a little at the sides; the mat and every socket stay in view.
    const needH = PLATE.height * 1.0;
    const needW = PLATE.width * 0.95;
    const distH = (needH / 2) / Math.tan(vFov / 2);
    const distW = (needW / 2) / (Math.tan(vFov / 2) * this.camera.aspect);
    const distance = Math.max(distH, distW);
    this.camera.position.set(0, -Math.sin(pitch) * distance, Math.cos(pitch) * distance);
    this.camera.lookAt(0, 6, 0);
    this.camera.updateProjectionMatrix();
    // project() runs before the next frame renders, so the view matrix must be current now.
    this.camera.updateMatrixWorld();
    this.invalidate();
  }

  private texture(card: ZoneCard): THREE.CanvasTexture {
    const key = tileKey(card);
    const cached = this.textures.get(key);
    if (cached) { cached.users += 1; return cached.texture; }
    const canvas = document.createElement("canvas");
    canvas.width = TILE.width; canvas.height = TILE.height;
    const texture = new THREE.CanvasTexture(canvas);
    texture.colorSpace = THREE.SRGBColorSpace;
    texture.anisotropy = this.renderer.capabilities.getMaxAnisotropy();
    this.textures.set(key, { texture, users: 1 });
    paintTile(canvas, card, () => { texture.needsUpdate = true; this.invalidate(); });
    return texture;
  }

  private glowTexture(kind: FrameKind): THREE.CanvasTexture {
    let texture = this.glows.get(kind);
    if (!texture) {
      const made: THREE.CanvasTexture = new THREE.CanvasTexture(glowCanvas(kind, () => { made.needsUpdate = true; this.invalidate(); }));
      texture = made;
      this.glows.set(kind, texture);
    }
    return texture;
  }

  private release(key: string) {
    const entry = this.textures.get(key);
    if (!entry) return;
    entry.users -= 1;
    if (entry.users <= 0) { entry.texture.dispose(); this.textures.delete(key); }
  }

  /** Places every permanent; new tiles drop in, moved ones glide, gone ones leave. */
  update(tiles: BoardTile[]) {
    const seen = new Set<string>();
    this.cards.clear();
    // Rows per side and band: creatures (0), then lands (from the left) and other permanents (1).
    const groups = new Map<string, BoardTile[]>();
    const ordered = [...tiles].sort((a, b) => Number(/land/i.test(b.card.card.typeLine)) - Number(/land/i.test(a.card.card.typeLine)));
    for (const tile of ordered) {
      const key = `${tile.owner}|${tile.band}|${rowOf(tile.card)}`;
      groups.set(key, [...(groups.get(key) ?? []), tile]);
    }
    for (const [groupKey, row] of groups) {
      const [owner, bandText, rowText] = groupKey.split("|");
      const band = Number(bandText); const rowIndex = Number(rowText);
      const bands = row[0].bands;
      const sign = owner === "me" ? -1 : 1;
      const rowY = MAT_MID + sign * [52, 140][rowIndex];
      const matLeft = MAT.left - PLATE.width / 2 + 8;
      const matWidth = MAT.right - MAT.left - 16;
      const left = owner === "me" ? matLeft : matLeft + (matWidth / bands) * band;
      const width = owner === "me" ? matWidth : matWidth / bands;
      const spacing = Math.min(TILE_W + 6, (width - TILE_W) / Math.max(1, row.length - 1));
      const used = spacing * (row.length - 1) + TILE_W;
      const start = left + (width - used) / 2 + TILE_W / 2;
      row.forEach((tile, index) => {
        const id = tile.card.instanceId;
        seen.add(id);
        this.cards.set(id, tile.card);
        const key = tileKey(tile.card);
        let object = this.tiles.get(id);
        if (object && object.key !== key) {
          this.release(object.key);
          object.face.material.map = this.texture(tile.card);
          object.face.material.needsUpdate = true;
          object.key = key;
        }
        if (!object) {
          const face = new THREE.Mesh(new THREE.PlaneGeometry(TILE_W, TILE_H), new THREE.MeshBasicMaterial({ map: this.texture(tile.card), transparent: true }));
          face.position.z = 1.2;
          const halo = new THREE.Mesh(new THREE.PlaneGeometry(TILE_W * 1.3, TILE_H * 1.3),
            new THREE.MeshBasicMaterial({ color: 0xffffff, map: this.glowTexture(frameKind(tile.card)), transparent: true, opacity: 0,
              blending: THREE.AdditiveBlending, depthWrite: false }));
          halo.position.z = 0.9;
          const shadow = new THREE.Mesh(new THREE.PlaneGeometry(TILE_W * 0.96, TILE_H * 0.96),
            new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45, depthWrite: false }));
          shadow.position.set(1.5, -2.5, 0.6);
          const group = new THREE.Group();
          group.add(shadow, halo, face);
          face.userData.instanceId = id;
          group.position.set(start + spacing * index, rowY + sign * -40, 30);
          this.scene.add(group);
          object = { group, face, halo, key, target: new THREE.Vector3(), rotation: 0, tapped: false };
          this.tiles.set(id, object);
        }
        object.target.set(start + spacing * index, rowY, tile.card.isAttacking ? 6 : 0);
        // Opponents' attackers lean toward you; tapped permanents tilt 12° and dim (Caleb's prototype rule).
        const tapped = tile.card.tapped === true && tile.card.isAttacking !== true;
        object.tapped = tapped;
        object.rotation = tapped ? -THREE.MathUtils.degToRad(12) : 0;
        object.face.material.color.setScalar(tapped ? 0.6 : tile.card.phasedIn === false ? 0.35 : 1);
        const glow = tile.glow === "none" && tile.card.isAttacking ? "attacking" : tile.glow === "none" && (tile.card.blocking?.length ?? 0) > 0 ? "blocking" : tile.glow;
        if (glow === "none") object.halo.material.opacity = 0;
        else {
          object.halo.material.map = this.glowTexture(frameKind(tile.card));
          object.halo.material.color.setHex(glowColors[glow]); object.halo.material.opacity = glow === "playable" ? 0.8 : 1;
        }
        object.face.userData.glow = glow;
      });
    }
    for (const [id, object] of this.tiles) {
      if (seen.has(id)) continue;
      this.scene.remove(object.group);
      object.face.geometry.dispose(); object.face.material.dispose(); object.halo.geometry.dispose(); object.halo.material.dispose();
      this.release(object.key);
      this.tiles.delete(id);
    }
    this.animate();
  }

  /** A plate point (design points, top-left origin) on the page, for sockets the HTML overlay fills. */
  project(x: number, y: number): { x: number; y: number } {
    const point = toWorld(x, y).project(this.camera);
    return { x: (point.x + 1) / 2 * this.canvas.clientWidth, y: (1 - point.y) / 2 * this.canvas.clientHeight };
  }

  /** Design points to page pixels near a plate point (the camera's scale there). */
  scaleAt(x: number, y: number): number {
    const a = this.project(x - 50, y); const b = this.project(x + 50, y);
    return Math.hypot(b.x - a.x, b.y - a.y) / 100;
  }

  /** Where a tile sits on the page, for arrows and pop-overs. */
  screenPosition(instanceId: string): { x: number; y: number } | undefined {
    const object = this.tiles.get(instanceId);
    if (!object) return undefined;
    const point = object.group.position.clone().project(this.camera);
    return { x: (point.x + 1) / 2 * this.canvas.clientWidth, y: (1 - point.y) / 2 * this.canvas.clientHeight };
  }

  private animate() {
    if (this.disposed) return;
    // A hidden tab gets no animation frames: settle everything and draw once, so the table is current when it returns.
    if (document.visibilityState !== "visible") {
      for (const object of this.tiles.values()) {
        object.group.position.copy(object.target);
        object.group.rotation.z = object.rotation;
      }
      this.renderer.render(this.scene, this.camera);
      return;
    }
    if (this.animating) return;
    this.animating = true;
    const step = () => {
      if (this.disposed) return;
      let moving = false;
      for (const object of this.tiles.values()) {
        const position = object.group.position;
        position.lerp(object.target, 0.22);
        if (position.distanceTo(object.target) > 0.05) moving = true; else position.copy(object.target);
        const dr = object.rotation - object.group.rotation.z;
        if (Math.abs(dr) > 0.001) { object.group.rotation.z += dr * 0.25; moving = true; } else object.group.rotation.z = object.rotation;
        const lift = this.hovered === object.face.userData.instanceId ? 1.06 : 1;
        const ds = lift - object.group.scale.x;
        if (Math.abs(ds) > 0.002) { object.group.scale.setScalar(object.group.scale.x + ds * 0.3); moving = true; }
      }
      this.renderer.render(this.scene, this.camera);
      if (moving) this.frame = requestAnimationFrame(step);
      else this.animating = false;
    };
    this.frame = requestAnimationFrame(step);
  }

  invalidate() { this.animate(); }

  private hit(event: MouseEvent): string | undefined {
    const rect = this.canvas.getBoundingClientRect();
    this.pointer.set(((event.clientX - rect.left) / rect.width) * 2 - 1, -((event.clientY - rect.top) / rect.height) * 2 + 1);
    this.raycaster.setFromCamera(this.pointer, this.camera);
    const faces = [...this.tiles.values()].map((t) => t.face);
    const hit = this.raycaster.intersectObjects(faces, false)[0];
    return hit?.object.userData.instanceId as string | undefined;
  }

  private pointerMove = (event: PointerEvent) => {
    const id = this.hit(event);
    if (id === this.hovered) return;
    this.hovered = id;
    this.canvas.style.cursor = id ? "pointer" : "default";
    this.onTileHover?.(id, id ? this.cards.get(id) : undefined);
    this.animate();
  };

  private pointerLeave = () => {
    if (this.hovered === undefined) return;
    this.hovered = undefined;
    this.onTileHover?.(undefined, undefined);
    this.animate();
  };

  private visibility = () => { this.animating = false; cancelAnimationFrame(this.frame); this.animate(); };

  private click = (event: MouseEvent) => {
    const id = this.hit(event);
    if (id) this.onTileClick?.(id);
  };

  dispose() {
    this.disposed = true;
    cancelAnimationFrame(this.frame);
    this.canvas.removeEventListener("pointermove", this.pointerMove);
    this.canvas.removeEventListener("pointerleave", this.pointerLeave);
    this.canvas.removeEventListener("click", this.click);
    document.removeEventListener("visibilitychange", this.visibility);
    for (const entry of this.textures.values()) entry.texture.dispose();
    for (const texture of this.glows.values()) texture.dispose();
    this.renderer.dispose();
  }
}
