/**
 * The bar's D20, as the app's starting roll draws it (apps/ios/MagicMobile/StartingRollDice.swift and
 * StartingRollTableView.swift; Android ondevice/StartingRollDice.kt): the real model (d20.glb), its face map (d20.json)
 * and one of the app's recorded throws (d20-throws.json, 60 fps). The recording is relabelled by one of the
 * icosahedron's symmetries so it ends on 20, and a little yaw over the last stretch stands the numeral upright.
 *
 * In the bar it turns with the scroll. While the roll act is pinned it leaves the bar and plays the throw, scrubbed by
 * the scroll: the recording's run from the rail to its resting spot carries it from the bar to the middle of the
 * screen, and its height reads as nearness. It rests on 20 and glows, then goes back to the bar showing its 20.
 *
 * Until Three.js and the model arrive (it loads after the page), and wherever WebGL is missing, the bar shows a flat
 * die that does the same moves.
 */
import type * as THREE_NS from "three";

// The pinned roll's progress: leave the bar by GROW, land at REST, head back at BACK. The box is RATIO die diameters,
// so the winner's glow has room around the die.
const GROW = 0.08, REST = 0.7, BACK = 0.9, RATIO = 2.6;
const clamp = (x: number, a: number, b: number) => Math.max(a, Math.min(b, x));
const sm = (t: number) => { t = clamp(t, 0, 1); return t * t * (3 - 2 * t); };

type Face = { number: number; normal: number[]; cornerDirections: number[][] };
type Model = { faces: Face[]; inradius: number };
type Throw = { frames: number; faceUp: number; railTime: number; position: number[]; orientation: number[] };

export function startBarDie(): () => void {
  const die = document.querySelector<HTMLElement>(".die");
  const slot = document.querySelector<HTMLElement>(".die-slot");
  const act = document.querySelector<HTMLElement>("[data-roll]");
  if (!die || !slot || !act) return () => {};
  const canvas = die.querySelector("canvas")!;
  const flatSvg = die.querySelector("svg")!;
  const num = die.querySelector("text")!;
  const caps = Array.from(act.querySelectorAll<HTMLElement>(".roll__cap"));
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let stopped = false, frameId = 0;

  function peak() {
    const r = act!.getBoundingClientRect(), run = Math.max(r.height - innerHeight, 1);
    return { q: clamp(-r.top / run, 0, 1), before: r.top > 0, after: -r.top >= run };
  }
  // The box is small while the die sits in the bar and large while it is out, so the bar doesn't draw a big canvas.
  let box = 0;
  function layout(out: boolean, small: number) {
    const diameter = out ? Math.min(innerWidth * 0.5, innerHeight * 0.32) : small;
    const want = Math.round(diameter * RATIO);
    if (Math.abs(want - box) <= 1) return false;
    box = want; die!.style.width = die!.style.height = `${box}px`;
    return true;
  }
  function place(cx: number, cy: number, diameter: number) {
    die!.style.transform = `translate3d(${(cx - box / 2).toFixed(1)}px,${(cy - box / 2).toFixed(1)}px,0) scale(${((diameter * RATIO) / box).toFixed(4)})`;
  }
  // The caption under the die follows the roll: who goes first, highest roll starts, you go first.
  function captions(q: number) {
    for (const c of caps) {
      const from = Number(c.dataset.from), to = Number(c.dataset.to);
      c.style.opacity = (sm((q - from) / 0.03) * (1 - sm((q - to) / 0.03))).toFixed(3);
    }
  }
  function path(q: number, k: number, lift: number) {
    const s = slot!.getBoundingClientRect(), sx = s.left + s.width / 2, sy = s.top + s.height / 2;
    const big = Math.min(innerWidth * 0.5, innerHeight * 0.32), e = sm(k);
    layout(k > 0.001, s.width);
    place(sx + (innerWidth / 2 - sx) * e, sy + (innerHeight * 0.42 - sy) * e, (s.width + (big - s.width) * e) * (1 + 0.14 * lift));
    captions(q);
  }

  // ---- the flat die, Cut to Play's: numbers tick with the scroll ----
  let flat = true, spinDeg = 0, lastY = scrollY, face = 20;
  function flatFrame() {
    if (!flat || stopped) return;
    frameId = requestAnimationFrame(flatFrame);
    const y = scrollY, dy = y - lastY; lastY = y;
    const pk = peak(), inPeak = !pk.before && !pk.after, q = pk.q;
    const k = !inPeak ? 0 : reduce ? 1 : q < GROW ? q / GROW : q > BACK ? (1 - q) / (1 - BACK) : 1;
    const settle = inPeak && q > REST;
    spinDeg = reduce ? 0 : spinDeg + (settle ? -spinDeg * 0.18 : dy * (inPeak ? 1.6 : 0.5));
    if (settle || pk.after) face = 20;
    else if (Math.abs(dy) > 0.5) face = 1 + (Math.floor(Math.abs(y / (inPeak ? 38 : 120))) % 19);
    num.textContent = String(face);
    die!.classList.toggle("landed", settle);
    flatSvg.style.transform = `rotate(${(spinDeg % 360).toFixed(1)}deg)`;
    path(q, k, 0);
  }
  frameId = requestAnimationFrame(flatFrame);

  // ---- the real die, once the page has loaded ----
  const begin = () => { if (!stopped) loadThree().catch(() => { /* the flat die stays */ }); };
  if (document.readyState === "complete") setTimeout(begin, 300);
  else addEventListener("load", () => setTimeout(begin, 300), { once: true });

  async function loadThree() {
    if (!("WebGLRenderingContext" in window)) return;
    const [THREE, { GLTFLoader }] = await Promise.all([import("three"), import("three/examples/jsm/loaders/GLTFLoader.js")]);
    const json = (url: string) => fetch(url).then((r) => { if (!r.ok) throw new Error(url); return r.json(); });
    const loader = new GLTFLoader();
    const [model, bank, body, glowGltf] = await Promise.all([
      json("/site/d20/d20.json") as Promise<Model>,
      json("/site/d20/d20-throws.json") as Promise<{ throws: Throw[] }>,
      loader.loadAsync("/site/d20/d20.glb"),
      loader.loadAsync("/site/d20/d20-glow.glb"),
    ]);
    if (stopped) return;
    let renderer: THREE_NS.WebGLRenderer;
    try { renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true }); } catch { return; }
    renderer.setPixelRatio(Math.min(devicePixelRatio || 1, 2));
    run(THREE, renderer, model, bank.throws[0], body.scene.children[0] as THREE_NS.Mesh, glowGltf.scene.children[0] as THREE_NS.Mesh);
  }

  function run(THREE: typeof THREE_NS, renderer: THREE_NS.WebGLRenderer, model: Model, rec: Throw, body: THREE_NS.Mesh, glow: THREE_NS.Mesh) {
    const scene = new THREE.Scene();
    // Looking down at the die as the app's table camera does (18° off straight down), framed so the die's diameter
    // (about 2 units) is 1 / RATIO of the box.
    const camera = new THREE.PerspectiveCamera(30, 1, 1, 100);
    const pitch = ((90 - 18) * Math.PI) / 180, dist = (1.03 * RATIO) / Math.tan((15 * Math.PI) / 180);
    camera.position.set(0, dist * Math.sin(pitch), dist * Math.cos(pitch));
    camera.lookAt(0, 0, 0);

    // The app's lights: one warm lamp up and to the left, a dim room, and the small painted room the resin reflects.
    // (Current Three.js lights are physical; π and no falloff match the app's unitless lamp.)
    const lamp = new THREE.PointLight(0xffd19e, 1.25 * Math.PI, 0, 0);
    lamp.position.set(-7, 13, -2);
    scene.add(lamp, new THREE.AmbientLight(0x9e6b4d, 0.32 * Math.PI));
    const room = document.createElement("canvas");
    room.width = 256; room.height = 128;
    const g = room.getContext("2d")!;
    const sky = g.createLinearGradient(0, 0, 0, 128);
    sky.addColorStop(0, "rgb(107,77,56)"); sky.addColorStop(0.5, "rgb(77,46,28)"); sky.addColorStop(1, "rgb(20,11,8)");
    g.fillStyle = sky; g.fillRect(0, 0, 256, 128);
    const glowGrad = g.createRadialGradient(56, 24, 0, 56, 24, 44);
    glowGrad.addColorStop(0, "rgba(255,219,158,1)"); glowGrad.addColorStop(1, "rgba(255,179,102,0)");
    g.fillStyle = glowGrad; g.fillRect(0, 0, 256, 128);
    const roomTex = new THREE.CanvasTexture(room);
    roomTex.mapping = THREE.EquirectangularReflectionMapping;
    roomTex.colorSpace = THREE.SRGBColorSpace;
    scene.environment = new THREE.PMREMGenerator(renderer).fromEquirectangular(roomTex).texture;

    body.traverse((o) => {
      const m = (o as THREE_NS.Mesh).material as THREE_NS.MeshStandardMaterial | undefined;
      if (m) m.envMapIntensity = 0.55;
    });
    const glowMat = glow.material as THREE_NS.MeshBasicMaterial;
    glowMat.transparent = true; glowMat.depthWrite = false; glow.renderOrder = -6;
    // The glow quad is 4.6 units across; at 1.1 it stays inside the box (the app's 1.6 would be cut off by its edge).
    glow.position.set(0, -model.inradius + 0.03, 0);
    glow.scale.setScalar(1.1);
    scene.add(body, glow);

    // ---- D20Landing and D20ThrowPlan ----
    const V = (a: number[]) => new THREE.Vector3(a[0], a[1], a[2]);
    const basis = (normal: THREE_NS.Vector3, corner: THREE_NS.Vector3) => {
      const n = normal.clone().normalize();
      const u = corner.clone().sub(n.clone().multiplyScalar(corner.dot(n))).normalize();
      return new THREE.Matrix4().makeBasis(n, u, new THREE.Vector3().crossVectors(n, u));
    };
    /** The rotation (in the die's frame) that turns face `target` into face `resting`, corner 0 onto corner k. */
    const symmetry = (target: Face, resting: Face, k: number) => {
      const a = basis(V(target.normal), V(target.cornerDirections[0]));
      const b = basis(V(resting.normal), V(resting.cornerDirections[k % resting.cornerDirections.length]));
      return new THREE.Quaternion().setFromRotationMatrix(b.multiply(a.transpose()));
    };
    const yawBetween = (a: THREE_NS.Vector3, b: THREE_NS.Vector3) => {
      let t = Math.atan2(b.x, b.z) - Math.atan2(a.x, a.z);
      while (t > Math.PI) t -= 2 * Math.PI;
      while (t <= -Math.PI) t += 2 * Math.PI;
      return t;
    };
    const quat = (j: number) => { j = clamp(j, 0, rec.frames - 1) * 4; const o = rec.orientation; return new THREE.Quaternion(o[j], o[j + 1], o[j + 2], o[j + 3]); };
    const pos = (j: number) => { j = clamp(j, 0, rec.frames - 1) * 3; const p = rec.position; return new THREE.Vector3(p[j], p[j + 1], p[j + 2]); };

    const target = model.faces.find((f) => f.number === 20) ?? model.faces[0];
    const resting = model.faces[rec.faceUp], finish = quat(rec.frames - 1);
    let best = { yaw: 0, s: new THREE.Quaternion() }, bestSet = false;
    for (let k = 0; k < 3; k++) {
      const s = symmetry(target, resting, k);
      const up = V(target.cornerDirections[0]).applyQuaternion(s).applyQuaternion(finish); up.y = 0;
      const yaw = yawBetween(up, new THREE.Vector3(0, 0, -1));
      if (!bestSet || Math.abs(yaw) < Math.abs(best.yaw)) { best = { yaw, s }; bestSet = true; }
    }
    const dur = (rec.frames - 1) / 60, z0 = pos(0).z, z1 = pos(rec.frames - 1).z;
    const Y = new THREE.Vector3(0, 1, 0);
    function pose(time: number) {
      const t = clamp(time, 0, dur), exact = t * 60, i = Math.floor(exact), f = exact - i;
      const p = pos(i).lerp(pos(i + 1), f);
      const q0 = quat(i), q1 = quat(i + 1);
      if (q0.dot(q1) < 0) q1.set(-q1.x, -q1.y, -q1.z, -q1.w);
      const q = q0.slerp(q1, f);
      // The extra yaw comes in over the last stretch, after the final hard bounce.
      const settleStart = Math.max(rec.railTime + 0.3, dur - 0.75);
      const e = sm((t - settleStart) / Math.max(dur - settleStart, 0.001));
      const yaw = new THREE.Quaternion().setFromAxisAngle(Y, best.yaw * e);
      return { p, q: yaw.multiply(q.multiply(best.s)).normalize() };
    }
    const landed = pose(dur).q;
    // In the bar the die turns with the page: a turn about a tipped axis per 1000 px, from its 20.
    const AXIS = new THREE.Vector3(1, 0.35, 0.6).normalize();
    const idle = (y: number) => new THREE.Quaternion().setFromAxisAngle(AXIS, y * 0.0063).multiply(landed);

    flat = false;
    cancelAnimationFrame(frameId);
    die!.classList.add("three");
    die!.classList.remove("landed");
    flatSvg.style.transform = "";
    let lastKey = "", lastBox = 0;

    function tick() {
      if (stopped) return;
      frameId = requestAnimationFrame(tick);
      const pk = peak(), q = pk.q, inPeak = !pk.before && !pk.after;
      let orient: THREE_NS.Quaternion, k = 0, lift = 0, shine = 0;
      // Reduced motion: no throw; the die simply stands on its 20 in the middle while the roll holds.
      if (reduce) { orient = landed; k = inPeak ? 1 : 0; shine = inPeak && q >= REST ? 1 : 0; }
      else if (pk.before) orient = idle(scrollY);
      else if (pk.after) orient = landed;
      else if (q < GROW) {
        // Leaving the bar: the scroll's turn hands over to the throw's first frame.
        const a = idle(scrollY), b = pose(0).q;
        if (a.dot(b) < 0) b.set(-b.x, -b.y, -b.z, -b.w);
        orient = a.slerp(b, sm(q / GROW));
      } else if (q < REST) {
        const ps = pose(((q - GROW) / (REST - GROW)) * dur);
        orient = ps.q;
        k = Math.abs(z1 - z0) > 0.01 ? clamp((ps.p.z - z0) / (z1 - z0), 0, 1) : (q - GROW) / (REST - GROW);
        lift = clamp((ps.p.y - model.inradius) / 3, 0, 1);
      } else {
        orient = landed;
        k = q < BACK ? 1 : 1 - (q - BACK) / (1 - BACK);
        shine = sm((q - REST) / 0.03) * (1 - sm((q - (BACK - 0.02)) / 0.04));
      }
      path(q, k, lift);
      if (box !== lastBox) { lastBox = box; renderer.setSize(box, box, false); lastKey = ""; }
      // Draw only when the die turns or glows.
      const key = `${orient.x.toFixed(4)}${orient.y.toFixed(4)}${orient.z.toFixed(4)}${orient.w.toFixed(4)}${shine.toFixed(3)}`;
      if (key === lastKey) return;
      lastKey = key;
      body.quaternion.copy(orient);
      glow.visible = shine > 0.001;
      glowMat.opacity = shine;
      renderer.render(scene, camera);
    }
    frameId = requestAnimationFrame(tick);
  }

  return () => { stopped = true; cancelAnimationFrame(frameId); };
}
