/**
 * The Hall: scrolling walks sideways past the exhibits, one per way to play.
 *
 * The act is a plain Scroll Craft pin; this module owns the rail's one transform, computed from the act's own scroll
 * position. (Letting the engine's pan move the rail while a second layer corrected it made the walk shake: the two
 * landed a frame apart.) Each exhibit gets an equal share of the scroll, and the rail slows, never stops, as an exhibit
 * reaches the middle: f - SLOW·sin(2πf)/2π. It glides a little behind the scroll so a mouse wheel's steps read as one
 * movement.
 *
 * Also here: the room light takes each commander's colour identity, the index lights its mana pips, the card, word and
 * art move at three depths, and the Ranked badge climbs Bronze to Mythic while that exhibit is in the middle.
 */
const MANA: Record<string, [number, number, number]> = {
  W: [241, 228, 173], U: [90, 162, 223], B: [154, 131, 181], R: [229, 96, 63], G: [88, 176, 108],
};
type RGB = [number, number, number];

function identity(ci: string): [RGB, RGB] {
  const cs = ci.split("").map((c) => MANA[c]).filter(Boolean);
  if (!cs.length) return [[244, 122, 28], [250, 214, 133]];
  if (cs.length >= 4) return [[232, 197, 106], cs[1]];
  return [cs[0], cs[cs.length > 1 ? 1 : 0]];
}

export function startHall(): () => void {
  const act = document.querySelector<HTMLElement>(".hall");
  const rail = document.querySelector<HTMLElement>(".rail");
  const index = document.querySelector<HTMLElement>(".index");
  if (!act || !rail || !index) return () => {};
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const exs = Array.from(act.querySelectorAll<HTMLElement>(".ex"));
  const medals = Array.from(index.querySelectorAll<HTMLButtonElement>(".medal"));
  const pips = Array.from(index.querySelectorAll<HTMLElement>(".index__pips i"));
  const ambient = act.querySelector<HTMLElement>(".room__ambient")!;
  const root = document.documentElement;
  const RANKED = exs.findIndex((ex) => ex.classList.contains("ex--ranked"));
  const SLOW = reduce ? 0 : 0.7;
  const GLIDE = reduce ? 1 : 0.3;

  type Part = { mid: number; card: HTMLElement | null; word: HTMLElement | null; img: HTMLElement | null };
  let geo: { key: string; stop: number[]; parts: Part[] } | null = null;
  let railX: number | null = null;

  function measure() {
    const vw = innerWidth;
    const over = Math.max(1, rail!.scrollWidth - vw);
    geo = {
      key: `${vw}x${innerHeight}`,
      // Where the rail stands with each exhibit in the middle (the ranked one centres on its badge).
      stop: exs.map((ex, i) => {
        let mid = ex.offsetLeft + ex.offsetWidth / 2;
        const badge = i === RANKED ? ex.querySelector<HTMLElement>(".badge") : null;
        if (badge) mid = ex.offsetLeft + badge.offsetLeft + badge.offsetWidth / 2;
        return Math.max(0, Math.min(over, mid - vw / 2));
      }),
      parts: exs.map((ex) => ({
        mid: ex.offsetLeft + Math.min(ex.offsetWidth, vw * 0.7) / 2,
        card: ex.querySelector<HTMLElement>(".ex__card"),
        word: ex.querySelector<HTMLElement>(".ex__word"),
        img: ex.querySelector<HTMLElement>(".ex__plate img"),
      })),
    };
  }
  function travel(p: number) {
    const n = exs.length, u = p * (n - 1), i = Math.min(Math.floor(u), n - 2);
    let f = u - i;
    f -= (SLOW * Math.sin(2 * Math.PI * f)) / (2 * Math.PI);
    return { u, x: geo!.stop[i] + (geo!.stop[i + 1] - geo!.stop[i]) * f };
  }
  const onResize = () => { geo = null; };
  addEventListener("resize", onResize);

  // Jump: exhibit i sits at progress i / (n - 1). Play goes to the close.
  const jumps = medals.map((m) => {
    const go = () => {
      const target = m.dataset.go!;
      const behavior: ScrollBehavior = reduce ? "auto" : "smooth";
      if (target === "play") {
        const close = document.getElementById("play");
        if (close) scrollTo({ top: close.getBoundingClientRect().top + scrollY, behavior });
        return;
      }
      const top = act.getBoundingClientRect().top + scrollY;
      scrollTo({ top: top + (Number(target) / (exs.length - 1)) * (act.offsetHeight - innerHeight), behavior });
    };
    m.addEventListener("click", go);
    return () => m.removeEventListener("click", go);
  });

  const ranked = exs[RANKED];
  const badges = ranked ? Array.from(ranked.querySelectorAll<HTMLImageElement>(".badge img")) : [];
  const tiers = ranked ? Array.from(ranked.querySelectorAll<HTMLElement>(".tiers li")) : [];
  const mythic = ranked?.querySelector<HTMLImageElement>(".badge__mythic") ?? null;
  const spin = Array.from({ length: 32 }, (_, i) => `/site/spin/m${i}.webp`);
  let shownTier = 0, shownSpin = -1, active = -1, shownGlow = "";
  const cur: [RGB, RGB] = [[232, 197, 106], [196, 90, 42]];
  let frameId = 0;

  function frame() {
    frameId = requestAnimationFrame(frame);
    const vw = innerWidth, vh = innerHeight;
    const box = act!.getBoundingClientRect();
    // The index belongs to the hall: it shows while the hall has the screen.
    index!.classList.toggle("away", !(box.top < vh * 0.5 && box.bottom > vh * 0.5));
    if (box.bottom < -vh * 0.2 || box.top > vh * 1.2) return;
    if (!geo || geo.key !== `${vw}x${vh}`) { measure(); railX = null; }
    const p = Math.max(0, Math.min(1, -box.top / Math.max(box.height - vh, 1)));
    const t = travel(p);
    railX = railX === null ? t.x : railX + (t.x - railX) * GLIDE;
    if (Math.abs(t.x - railX) < 0.3) railX = t.x;
    rail!.style.transform = `translate3d(${(-railX).toFixed(1)}px,0,0)`;

    let best = 0, bestD = 1e9;
    geo!.parts.forEach((part, k) => {
      const d = (part.mid - railX! - vw / 2) / vw;
      if (Math.abs(d) < bestD) { bestD = Math.abs(d); best = k; }
      if (reduce || d < -1.3 || d > 1.3) return;
      // Depth: the card is the nearest plane, the word the middle one, the art the far wall.
      if (part.card) part.card.style.translate = `${(d * -7).toFixed(2)}vw 0`;
      if (part.word) part.word.style.translate = `${(d * -3.5).toFixed(2)}vw 0`;
      if (part.img) part.img.style.transform = `translate3d(${(d * 3).toFixed(2)}vw,0,0)`;
    });
    if (best !== active) {
      active = best;
      medals.forEach((m, i) => m.setAttribute("aria-current", i === best ? "true" : "false"));
      const ci = exs[best].dataset.ci ?? "";
      pips.forEach((pip) => pip.classList.toggle("on", ci.includes(pip.dataset.c ?? "-")));
      ambient.style.backgroundImage = `url(${exs[best].dataset.art})`;
    }
    // The room light eases toward this commander's colours. Written only when it changes: a custom property on the
    // root restyles the whole page.
    const to = identity(exs[active].dataset.ci ?? "");
    for (let j = 0; j < 2; j++) for (let c = 0; c < 3; c++) cur[j][c] += (to[j][c] - cur[j][c]) * (reduce ? 1 : 0.08);
    const glowA = cur[0].map(Math.round).join(" "), glowB = cur[1].map(Math.round).join(" ");
    if (glowA + glowB !== shownGlow) {
      shownGlow = glowA + glowB;
      root.style.setProperty("--glow-a", glowA);
      root.style.setProperty("--glow-b", glowB);
    }

    if (!badges.length) return;
    // The badge climbs while the ranked exhibit is in the middle.
    const lp = Math.max(0, Math.min(1, (t.u - (RANKED - 0.4)) / 0.8));
    const climb = Math.min(5, Math.floor(lp * 6.2));
    if (climb !== shownTier) {
      badges.forEach((b, i) => b.classList.toggle("on", i === climb));
      tiers.forEach((tier, i) => tier.classList.toggle("on", i === climb));
      shownTier = climb;
    }
    if (reduce) return;
    if (climb < 5) badges[climb].style.transform = `scale(${(0.86 + 0.14 * Math.sin(((lp * 6.2) % 1) * Math.PI)).toFixed(3)})`;
    else if (mythic) {
      const s = Math.floor(Math.max(0, Math.min(0.999, (lp * 6.2 - 5) / 1.2)) * 32);
      if (s !== shownSpin) { mythic.src = spin[s]; shownSpin = s; }
    }
  }
  frameId = requestAnimationFrame(frame);
  return () => {
    cancelAnimationFrame(frameId);
    removeEventListener("resize", onResize);
    jumps.forEach((off) => off());
  };
}
