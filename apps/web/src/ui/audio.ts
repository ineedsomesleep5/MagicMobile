/**
 * The game's sounds (iOS GameAudio.swift, BoardFXSound in BoardFXOverlay.swift): the same recordings (built into
 * public/generated/audio by scripts/prepare_data.py, .caf converted to .m4a), the same mix levels, cooldowns, voices,
 * variants and pitch wobble, played with Web Audio on one clock so cues due together land together. Board cues follow
 * the scheduled effects (BoardFXSound.cues). Checked by test/audio.test.ts.
 */
import { arrivalSound, type ArrivalSound, type BoardFXEvent, castSound, type ScheduledBoardFX } from "../core/boardEvents";
import type { CardIdentity } from "../core/models";
import { storage } from "./storage";

export type GameSound =
  | "ui-tap" | "ui-confirm" | "ui-back" | "ui-open" | "ui-close" | "ui-toggle" | "ui-tick" | "ui-error" | "response-alert" | "menu-play" | "page-flip" | "emote"
  | "card-draw" | "card-pickup" | "card-play" | "shuffle" | "land-drop" | "counter" | "ability" | "steal"
  | "arrive-creature" | "arrive-creature-heavy" | "arrive-artifact" | "arrive-enchantment" | "arrive-planeswalker"
  | `creature-${string}` | "land-plains" | "land-island" | "land-swamp" | "land-mountain" | "land-forest"
  | "cast-instant" | "cast-sorcery" | "cast-permanent" | "spell-big" | "commander-cast"
  | "attack" | "block" | "strike" | "player-hit" | "death" | "exile" | "life-gain" | "life-loss"
  | "turn-you" | "versus" | "victory" | "defeat" | "dice-roll" | "dice-land";

const isVoice = (sound: GameSound) => sound.startsWith("creature-");
const UI_QUIET = new Set(["ui-tap", "ui-tick", "ui-toggle", "ui-back", "ui-open", "ui-close"]);

/** GameSound.volume: the mix (files are loudness-matched): interface quiet, the board clear, big moments on top. */
export function soundVolume(sound: GameSound): number {
  if (UI_QUIET.has(sound)) return 0.5;
  if (["ui-confirm", "ui-error", "page-flip", "emote"].includes(sound)) return 0.65;
  if (["response-alert", "menu-play"].includes(sound)) return 0.8;
  if (["card-draw", "card-pickup", "counter", "ability"].includes(sound)) return 0.7;
  if (["spell-big", "commander-cast", "attack", "block", "strike", "player-hit", "turn-you", "versus", "victory", "defeat"].includes(sound)) return 0.9;
  if (["death", "exile", "life-gain", "life-loss", "steal"].includes(sound)) return 0.75;
  return 0.85;
}

/** GameSound.cooldown: twelve triggers resolving together read as a flurry, not a wall of identical sounds. */
export function soundCooldown(sound: GameSound): number {
  switch (sound) {
    case "ui-tick": return 0.08;
    case "card-draw": case "ui-tap": return 0.1;
    case "counter": case "life-gain": return 0.3;
    case "cast-instant": case "cast-sorcery": case "cast-permanent": return 0.25;
    case "ability": return 0.8;
    case "response-alert": return 1.2;
    case "turn-you": case "versus": case "victory": case "defeat": return 1.5;
    default: return 0.12;
  }
}

/** GameSound.variants: how many recordings a cue picks from (file `<name>-<n>`); giants share the orc voices' first two. */
export function soundFile(sound: GameSound, pick: (n: number) => number = (n) => 1 + Math.floor(Math.random() * n)): string {
  const variants: Record<string, number> = {
    attack: 3, "creature-giant": 2, "creature-faerie": 2, "creature-zombie": 2, "creature-cat": 2, "creature-ooze": 2, "creature-wizard": 2,
    "creature-insect": 2, "creature-dragon": 3, "creature-squirrel": 3, "creature-orc": 3, "creature-horror": 3,
  };
  const base = sound === "creature-giant" ? "creature-orc" : sound;
  const n = variants[sound] ?? 1;
  return n > 1 ? `${base}-${pick(n)}` : base;
}

const PITCHED = new Set(["card-draw", "card-pickup", "card-play", "land-drop", "strike", "player-hit", "death", "attack", "block", "counter", "shuffle",
  "dice-land", "arrive-creature", "arrive-creature-heavy", "arrive-artifact"]);

/** One board sound: when it starts (seconds after the batch), how loud, and for a creature's voice when it must end. */
export interface Cue { sound: GameSound; at: number; volume: number; endsBy?: number }

/** BoardFXSound.arrivalCues: a basic land's place; a creature's voice, or a card set down; one sound per kind of card. */
export function arrivalCue(plan: ArrivalSound): GameSound {
  switch (plan.kind) {
    case "basicLand": return (`land-${plan.land}` as GameSound);
    case "otherLand": return "land-drop";
    case "creature": return plan.voice ? (`creature-${plan.voice}` as GameSound) : plan.heavy ? "arrive-creature-heavy" : "arrive-creature";
    case "artifact": return "arrive-artifact";
    case "enchantment": return "arrive-enchantment";
    case "planeswalker": return "arrive-planeswalker";
    case "other": return "arrive-creature";
  }
}

/**
 * BoardFXSound.cues: sounds for one board transition, each timed to the effect it accompanies. Casts sound like their card
 * type (`casts`: stack object id to its card); arrivals like what arrived (`arrivals`: card id to its card and token flag).
 */
export function boardCues(scheduled: ScheduledBoardFX[], viewerID: string, arrivals: Map<string, { card: CardIdentity; isToken: boolean }>,
  casts: Map<string, CardIdentity>): Cue[] {
  const hasStrike = scheduled.some((fx) => fx.event.type === "combatStrike");
  const cues: Cue[] = [];
  const add = (sound: GameSound, at: number, volume = 1, endsBy?: number) => cues.push({ sound, at, volume, ...(endsBy !== undefined ? { endsBy } : {}) });
  for (const fx of scheduled) {
    const event: BoardFXEvent = fx.event;
    switch (event.type) {
      case "spellCast": {
        const cast = (`cast-${castSound(casts.get(event.stackID))}`) as GameSound;
        // Opponents' spells sit a little further back in the mix.
        const level = event.controllerID === viewerID ? 1 : 0.75;
        if (event.weight === "ability") { if (event.controllerID === viewerID) add("ability", fx.delay); }
        else if (event.weight === "commander") add("commander-cast", fx.delay, level);
        else if (event.weight === "big") { add(cast, fx.delay, level); add("spell-big", fx.delay + 0.05, level); }
        else add(cast, fx.delay, level);
        break;
      }
      case "attackDeclared": add("attack", fx.delay); break;
      case "blockDeclared": add("block", fx.delay); break;
      case "combatStrike": add("player" in event.target && event.target.player === viewerID ? "player-hit" : "strike", fx.handoff); break;
      case "firstStrikeBeat": break;
      case "damageMarked": if (!hasStrike) add("strike", fx.delay, 0.7); break;
      case "leftBattlefield":
        if (event.to === "exile") add("exile", fx.delay);
        else if (event.to === "hand" || event.to === "library") add("card-pickup", fx.delay);
        else add("death", fx.delay);
        break;
      case "enteredBattlefield": {
        const arrival = arrivals.get(event.cardID) ?? { card: { name: "", typeLine: "" }, isToken: false };
        const sound = arrivalCue(arrivalSound(arrival.card, arrival.isToken, event.entrance === "commander"));
        // A creature's voice plays while its card comes in and finishes as it lands.
        if (isVoice(sound)) add(sound, fx.delay, 1, fx.landing); else add(sound, fx.landing);
        break;
      }
      case "countersChanged": add("counter", fx.delay, event.delta > 0 ? 1 : 0.5); break;
      case "statsChanged": add("counter", fx.delay, 0.4); break;
      case "phased": add("exile", fx.delay, 0.55); break;
      case "transformed": add("card-play", fx.delay); break;
      case "controlChanged": add("steal", fx.delay + fx.duration * 0.28); break;
      case "lifeChanged":
        if (event.delta > 0) add("life-gain", fx.delay, event.playerID === viewerID ? 1 : 0.55);
        else if (event.playerID === viewerID && !hasStrike) add("life-loss", fx.delay);
        break;
    }
  }
  return cues;
}

/** GameSoundSignature.cues: at most two draw sounds for a big draw. */
export const drawCues = (oldHand: number, newHand: number): GameSound[] => (newHand > oldHand ? Array(Math.min(2, newHand - oldHand)).fill("card-draw") : []);

export const SOUND_KEYS = { effects: "mm.web.boardSoundsEnabled", volume: "mm.web.effectsVolume", music: "mm.web.musicEnabled" } as const;

/** The player's audio: one Web Audio context, decoded recordings, cooldowns and voices per cue. */
class Audio {
  private context?: AudioContext;
  private buffers = new Map<string, Promise<AudioBuffer | undefined>>();
  private lastPlayed = new Map<GameSound, number>();
  get enabled() { return storage.get(SOUND_KEYS.effects) !== "off"; }
  get volume() { const v = Number(storage.get(SOUND_KEYS.volume) ?? "0.9"); return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.9; }

  /** Browsers start audio only after the player touches the page: called on the first press. */
  unlock() {
    if (typeof window === "undefined" || typeof AudioContext === "undefined") return;
    this.context ??= new AudioContext();
    if (this.context.state === "suspended") void this.context.resume();
  }

  private buffer(file: string): Promise<AudioBuffer | undefined> {
    let found = this.buffers.get(file);
    if (!found) {
      const context = this.context!;
      found = fetch(`/generated/audio/${file}.m4a`).then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(new Error(String(r.status)))))
        .then((data) => context.decodeAudioData(data)).catch(() => undefined);
      this.buffers.set(file, found);
    }
    return found;
  }

  /** Decodes the board's sounds when a game appears, so the first cast is instant (GameAudio.preload). */
  preload(sounds: GameSound[]) {
    if (!this.context) return;
    for (const sound of sounds) void this.buffer(soundFile(sound, () => 1));
  }

  /** Plays a cue `delay` seconds from now; with `within`, late enough to end that long after `delay` (a voice ends as its card lands). */
  play(sound: GameSound, delay = 0, volume = 1, within?: number) {
    const context = this.context;
    if (!context || context.state !== "running" || !this.enabled || this.volume <= 0) return;
    const at = context.currentTime + Math.max(0, delay);
    const last = this.lastPlayed.get(sound);
    if (last !== undefined && Math.abs(at - last) < soundCooldown(sound)) return;
    this.lastPlayed.set(sound, at);
    void this.buffer(soundFile(sound)).then((buffer) => {
      if (!buffer) return;
      const source = context.createBufferSource();
      source.buffer = buffer;
      if (PITCHED.has(sound)) source.playbackRate.value = 1 + (Math.random() * 2 - 1) * 0.04;
      const gain = context.createGain();
      gain.gain.value = Math.min(1, soundVolume(sound) * this.volume * volume);
      source.connect(gain).connect(context.destination);
      const wait = within !== undefined ? Math.max(0, within - buffer.duration / source.playbackRate.value) : 0;
      source.start(Math.max(context.currentTime, at + wait));
    });
  }

  /** Board cues for one batch, all on the audio clock. */
  playCues(cues: Cue[]) {
    for (const cue of cues) this.play(cue.sound, cue.at, cue.volume, cue.endsBy !== undefined ? cue.endsBy - cue.at : undefined);
  }
}

export const gameAudio = new Audio();

/** The cues the board uses in a game's first seconds (GameAudio.boardSounds). */
export const BOARD_SOUNDS: GameSound[] = ["card-draw", "card-pickup", "card-play", "land-drop", "cast-instant", "cast-sorcery", "cast-permanent", "ability",
  "attack", "block", "strike", "player-hit", "death", "exile", "arrive-creature", "ui-tap", "ui-open", "ui-close", "turn-you"];
