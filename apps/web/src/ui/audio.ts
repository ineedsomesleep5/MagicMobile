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

export const SOUND_KEYS = { effects: "mm.web.boardSoundsEnabled", volume: "mm.web.effectsVolume", music: "mm.web.musicEnabled", musicVolume: "mm.web.musicVolume" } as const;

/** The Sound Lab's groups, each with its own switch (GameSoundCategory). */
export type SoundCategory = "interface" | "cards" | "spells" | "combat" | "moments";
export const SOUND_CATEGORIES: { id: SoundCategory; title: string; detail: string }[] = [
  { id: "interface", title: "Menus & alerts", detail: "Confirm buttons, sheets, “your decision” and emotes." },
  { id: "cards", title: "Cards & board", detail: "Drawing, playing, lands, creatures and their kinds, artifacts and counters." },
  { id: "spells", title: "Spells", detail: "Instants, sorceries, other spells, big spells and your commander." },
  { id: "combat", title: "Combat & life", detail: "Attacks, blocks, hits, deaths, exile and life changes." },
  { id: "moments", title: "Big moments", detail: "Your turn, the versus reveal, victory, defeat and dice." },
];
export const categoryKey = (category: SoundCategory) => `mm.web.sfx.${category}`;

/** GameSound.category. */
export function soundCategory(sound: GameSound): SoundCategory {
  if (sound.startsWith("ui-") || ["response-alert", "menu-play", "page-flip", "emote"].includes(sound)) return "interface";
  if (["cast-instant", "cast-sorcery", "cast-permanent", "spell-big", "commander-cast"].includes(sound)) return "spells";
  if (["attack", "block", "strike", "player-hit", "death", "exile", "life-gain", "life-loss"].includes(sound)) return "combat";
  if (["turn-you", "versus", "victory", "defeat", "dice-roll", "dice-land"].includes(sound)) return "moments";
  return "cards";
}

/** Every sound by its Sound Lab name, in GameSound's order (GameSound.title). */
export const SOUND_TITLES: [GameSound, string][] = [
  ["ui-tap", "Game button"], ["ui-confirm", "Confirm"], ["ui-back", "Back"], ["ui-open", "Open a panel"], ["ui-close", "Close a panel"],
  ["ui-toggle", "Switch"], ["ui-tick", "Slider tick"], ["ui-error", "Not allowed"], ["response-alert", "Your decision"], ["menu-play", "Play"],
  ["page-flip", "Page turn"], ["emote", "Emote"],
  ["card-draw", "Draw a card"], ["card-pickup", "Pick up a card"], ["card-play", "Play a card"], ["shuffle", "Shuffle (mulligan)"], ["land-drop", "Land"],
  ["counter", "Counter"], ["ability", "Your ability"], ["steal", "Stolen permanent"], ["arrive-creature", "Creature lands"],
  ["arrive-creature-heavy", "Big creature lands"], ["arrive-artifact", "Artifact"], ["arrive-enchantment", "Enchantment"], ["arrive-planeswalker", "Planeswalker"],
  ["creature-human", "Human"], ["creature-goblin", "Goblin"], ["creature-elf", "Elf"], ["creature-dragon", "Dragon"], ["creature-sliver", "Sliver"],
  ["creature-squirrel", "Squirrel"], ["creature-orc", "Orc, ogre, troll"], ["creature-giant", "Giant"], ["creature-bear", "Bear"],
  ["creature-dinosaur", "Dinosaur"], ["creature-beast", "Beast, hydra"], ["creature-horror", "Horror, demon, wurm"], ["creature-critter", "Small critter"],
  ["creature-faerie", "Faerie"], ["creature-angel", "Angel"], ["creature-vampire", "Vampire"], ["creature-zombie", "Zombie"], ["creature-wolf", "Wolf, dog"],
  ["creature-cat", "Cat"], ["creature-bird", "Bird"], ["creature-ooze", "Ooze"], ["creature-wizard", "Wizard"], ["creature-insect", "Insect, spider"],
  ["creature-rat", "Rat, mouse"], ["creature-eldrazi", "Eldrazi"], ["land-plains", "Plains"], ["land-island", "Island"], ["land-swamp", "Swamp"],
  ["land-mountain", "Mountain"], ["land-forest", "Forest"],
  ["cast-instant", "Instant"], ["cast-sorcery", "Sorcery"], ["cast-permanent", "Permanent spell"], ["spell-big", "Big spell"], ["commander-cast", "Commander"],
  ["attack", "Attack"], ["block", "Block"], ["strike", "Creature hit"], ["player-hit", "You’re hit"], ["death", "Creature dies"], ["exile", "Exile"],
  ["life-gain", "Life gain"], ["life-loss", "Life loss"],
  ["turn-you", "Your turn"], ["versus", "Versus"], ["victory", "Victory"], ["defeat", "Defeat"], ["dice-roll", "Dice roll"], ["dice-land", "Die lands"],
];

/** Music plays as a playlist per scene, whole tracks one after another (GameMusic; Kevin MacLeod, CC BY 4.0). */
export type MusicScene = "menu" | "game";
export interface MusicTrack { file: string; title: string }
export const MUSIC: Record<MusicScene, { title: string; level: number; tracks: MusicTrack[] }> = {
  menu: { title: "Lobby music", level: 0.6, tracks: [
    { file: "music-menu-1", title: "Midnight Tale" }, { file: "music-menu-2", title: "Industrious Ferret" },
    { file: "music-menu-3", title: "Village Consort" }, { file: "music-menu-4", title: "Thatched Villagers" }] },
  game: { title: "In-game music", level: 0.42, tracks: [
    { file: "music-game-1", title: "Teller of the Tales" }, { file: "music-game-2", title: "Lord of the Land" },
    { file: "music-game-3", title: "Suonatore di Liuto" }, { file: "music-game-4", title: "Pippin the Hunchback" }] },
};
export const musicChoiceKey = (scene: MusicScene) => `mm.web.music.${scene}`;
export const DEFAULT_MUSIC_VOLUME = 0.6;
/** Orchestral stingers cut from Kevin MacLeod pieces, credited with the tracks (MusicCredits). */
export const MUSIC_STINGERS = ["Discovery Hit", "Greta Sting", "Danse Macabre - Big Hit 1"];

/** The player's audio: one Web Audio context, decoded recordings, cooldowns and voices per cue. */
class Audio {
  private context?: AudioContext;
  private buffers = new Map<string, Promise<AudioBuffer | undefined>>();
  private lastPlayed = new Map<GameSound, number>();
  get enabled() { return storage.get(SOUND_KEYS.effects) !== "off"; }
  get volume() { const v = Number(storage.get(SOUND_KEYS.volume) ?? "0.9"); return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : 0.9; }
  categoryEnabled(category: SoundCategory) { return storage.get(categoryKey(category)) !== "off"; }
  /** A music level of zero is the same as music switched off. */
  get musicVolume() { const v = Number(storage.get(SOUND_KEYS.musicVolume) ?? String(DEFAULT_MUSIC_VOLUME)); return Number.isFinite(v) ? Math.min(1, Math.max(0, v)) : DEFAULT_MUSIC_VOLUME; }
  get musicEnabled() { return storage.get(SOUND_KEYS.music) !== "off" && this.musicVolume > 0; }
  private music?: { element: HTMLAudioElement; gain: GainNode; track: MusicTrack };
  private scene?: MusicScene;
  private previewing = false;
  private lastTrack: Partial<Record<MusicScene, string>> = {};
  private duckedUntil = 0;

  /** Browsers start audio only after the player touches the page: called on the first press. */
  unlock() {
    if (typeof window === "undefined" || typeof AudioContext === "undefined") return;
    const first = !this.context;
    this.context ??= new AudioContext();
    if (this.context.state === "suspended") void this.context.resume();
    // The scene's music waited for this first press.
    if (first && this.scene && this.musicEnabled && !this.music) this.start(this.nextTrack(this.scene), this.scene, 2);
  }

  private nextTrack(scene: MusicScene): MusicTrack {
    const choice = storage.get(musicChoiceKey(scene)) ?? "shuffle";
    const picked = MUSIC[scene].tracks.find((t) => t.file === choice);
    if (picked) return picked;
    const others = MUSIC[scene].tracks.filter((t) => t.file !== this.lastTrack[scene]);
    return others[Math.floor(Math.random() * others.length)] ?? MUSIC[scene].tracks[0];
  }

  private target(scene: MusicScene) {
    const ducked = (this.context?.currentTime ?? 0) < this.duckedUntil;
    return MUSIC[scene].level * Math.max(this.musicVolume, this.previewing ? 0.5 : 0) * (ducked ? 0.25 : 1);
  }

  private start(track: MusicTrack, scene: MusicScene, fadeIn: number) {
    const context = this.context;
    this.stopMusic(1.2);
    if (!context) return;
    const element = new window.Audio(`/generated/audio/${track.file}.m4a`);
    element.crossOrigin = "anonymous";
    const gain = context.createGain();
    gain.gain.value = 0;
    context.createMediaElementSource(element).connect(gain).connect(context.destination);
    element.onended = () => {
      if (this.music?.element !== element || !this.scene || !this.musicEnabled) return;
      this.previewing = false;
      this.start(this.nextTrack(this.scene), this.scene, 1);
    };
    void element.play().catch(() => undefined);
    gain.gain.setTargetAtTime(this.target(scene), context.currentTime, fadeIn / 3);
    this.music = { element, gain, track };
    this.lastTrack[scene] = track.file;
  }

  private stopMusic(fade = 0.8) {
    const music = this.music;
    if (!music || !this.context) return;
    this.music = undefined;
    music.element.onended = null;
    music.gain.gain.setTargetAtTime(0, this.context.currentTime, fade / 3);
    window.setTimeout(() => { music.element.pause(); music.gain.disconnect(); }, (fade + 0.1) * 1000);
  }

  /** Which playlist belongs on screen: the menus' or a game's (GameAudio.setScene). Plays once audio is unlocked. */
  setScene(scene: MusicScene) {
    this.previewing = false;
    if (this.scene === scene && this.music) return;
    this.scene = scene;
    if (this.musicEnabled && this.context) this.start(this.nextTrack(scene), scene, 2);
  }

  /** Lowers the music under a fanfare, then restores it (GameAudio.duckMusic). */
  duckMusic(seconds: number) {
    const music = this.music, context = this.context, scene = this.scene;
    if (!music || !context || !scene) return;
    this.duckedUntil = context.currentTime + seconds;
    music.gain.gain.setTargetAtTime(this.target(scene), context.currentTime, 0.4 / 3);
    window.setTimeout(() => { if (this.music === music) music.gain.gain.setTargetAtTime(this.target(scene), this.context!.currentTime, 1.5 / 3); }, seconds * 1000);
  }

  /** Applies changed settings (switches, levels or a new track pick) at once. */
  settingsChanged(trackPickChanged = false) {
    if (!this.musicEnabled && !this.previewing) { this.stopMusic(0.4); return; }
    const scene = this.scene;
    if (!scene || !this.context) return;
    if (this.music && !trackPickChanged) this.music.gain.gain.setTargetAtTime(this.target(scene), this.context.currentTime, 0.1);
    else if (!this.previewing) this.start(this.nextTrack(scene), scene, 1.2);
  }

  /** Sound Lab: hear one track now; the scene's playlist returns with `endPreview`. */
  preview(track: MusicTrack, scene: MusicScene) {
    this.unlock();
    this.previewing = true;
    this.scene ??= scene;
    this.start(track, this.scene, 0.6);
  }

  endPreview() {
    if (!this.previewing) return;
    this.previewing = false;
    if (!this.scene || !this.musicEnabled) { this.stopMusic(); return; }
    this.start(this.nextTrack(this.scene), this.scene, 1.5);
  }

  get nowPlaying() { return this.music?.track; }

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
  play(sound: GameSound, delay = 0, volume = 1, within?: number, audition = false) {
    const context = this.context;
    if (!context || context.state !== "running" || !this.enabled || this.volume <= 0) return;
    if (!audition && !this.categoryEnabled(soundCategory(sound))) return;
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
