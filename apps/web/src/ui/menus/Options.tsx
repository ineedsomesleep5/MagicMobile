/**
 * Arena's Options (iOS ArenaOptionsView, Board/MainMenuViews.swift, SoundLabView.swift): a centred serif title, one column
 * of compact pills (Gameplay, Board, Audio, Display & Artwork, Performance) and Support and About as links along the foot.
 * Each pill opens its page in the same panel with a back chevron; the settings lie flat on the glass in columns. Sound
 * Lab opens from Audio and Phase Stops from Gameplay. Every setting is the one the board reads, saved in this browser.
 */
import { useEffect, useState } from "react";
import { loadSmartPass, saveSmartPass, type SmartPassSettings } from "../../core/smartPass";
import { GAME_SPEED_KEY, GAME_SPEED_TITLES, GAME_SPEEDS, type GameSpeed, loadGameSpeed } from "../../core/gameSpeed";
import {
  categoryKey, DEFAULT_MUSIC_VOLUME, gameAudio, MUSIC, MUSIC_STINGERS, type MusicScene, musicChoiceKey, SOUND_CATEGORIES, SOUND_KEYS, SOUND_TITLES, soundCategory,
} from "../audio";
import { PhaseStops } from "../arena/Menus";
import { storage } from "../storage";
import { performanceReport, readPerformance } from "./performanceLog";
import { BackChevron, Caps, Checkbox, CloseButton, Pill, Segmented, Slider } from "./kit";

export type OptionsPage = "gameplay" | "board" | "audio" | "display" | "performance" | "support" | "about" | "soundLab" | "phaseStops";

const TITLES: Record<OptionsPage, string> = {
  gameplay: "Gameplay", board: "Board", audio: "Audio", display: "Display & Artwork", performance: "Performance", support: "Support", about: "About",
  soundLab: "Sound Lab", phaseStops: "Phase Stops",
};
const LISTED: OptionsPage[] = ["gameplay", "board", "audio", "display", "performance"];
const PARENT: Partial<Record<OptionsPage, OptionsPage>> = { soundLab: "audio", phaseStops: "gameplay" };

export const SUPPORT = {
  url: "https://magicmobile-downloads.vercel.app/support/",
  action: "Help cover server costs",
  note: "MagicMobile is free with no ads. Tips help pay for the servers and open in your browser. Unofficial fan app, not affiliated with Wizards of the Coast.",
};

export function Options({ onClose, start, upstream }: { onClose: () => void; start?: OptionsPage; upstream?: string }) {
  const [page, setPage] = useState<OptionsPage | undefined>(start);
  useEffect(() => () => gameAudio.endPreview(), []);
  return (
    <div className="moptions">
      <header className="mpanelhead centered">
        {page ? <BackChevron onBack={() => { if (page === "soundLab") gameAudio.endPreview(); setPage(PARENT[page]); }} /> : <span className="mspacer" />}
        <h2>{page ? TITLES[page] : "Options"}</h2>
        <CloseButton onClose={onClose} id="settings.close" />
      </header>
      {page ? (
        <div className="moptionspage mscroll" data-id={`settings.page.${page}`}>
          <div className={`moptionsbody ${page}`}><Page page={page} open={setPage} upstream={upstream} /></div>
        </div>
      ) : (
        <div className="moptionsroot">
          <div className="moptionspills">
            {LISTED.map((item) => (
              <button key={item} type="button" className="moptionspill" data-id={`settings.open.${item}`} onClick={() => { gameAudio.play("ui-open"); setPage(item); }}>{TITLES[item]}</button>
            ))}
          </div>
          <div className="moptionslinks">
            {(["support", "about"] as OptionsPage[]).map((item) => (
              <button key={item} type="button" data-id={`settings.open.${item}`} onClick={() => { gameAudio.play("ui-open"); setPage(item); }}>{TITLES[item]}</button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

/** A stored on/off switch, "off" only when turned off (the iOS defaults are on unless said otherwise). */
function useSwitch(key: string, defaultOn = true): [boolean, (on: boolean) => void] {
  const [on, setOn] = useState(() => { const v = storage.get(key); return v === undefined || v === null ? defaultOn : v !== "off"; });
  return [on, (next) => { setOn(next); storage.set(key, next ? "on" : "off"); }];
}

function Page({ page, open, upstream }: { page: OptionsPage; open: (page: OptionsPage) => void; upstream?: string }) {
  switch (page) {
    case "gameplay": return <Gameplay openStops={() => open("phaseStops")} />;
    case "phaseStops": return <StopsPage />;
    case "board": return <BoardPage />;
    case "audio": return <AudioPage openLab={() => open("soundLab")} />;
    case "soundLab": return <SoundLab />;
    case "display": return <DisplayPage />;
    case "performance": return <PerformancePage />;
    case "support": return (
      <div className="mflat">
        <Caps text="Support MagicMobile" />
        <p className="mnote">{SUPPORT.note}</p>
        <Pill lit id="settings.support" onClick={() => window.open(SUPPORT.url, "_blank", "noopener")}>♥ {SUPPORT.action}</Pill>
      </div>
    );
    case "about": return (
      <div className="mflat">
        <div className="maboutrow"><span>MagicMobile</span><b>0.1.1 (web)</b></div>
        {upstream && <div className="maboutrow"><span>XMage revision</span><b>{upstream.slice(0, 12)}</b></div>}
        <p className="mnote">{SUPPORT.note}</p>
      </div>
    );
  }
}

/** Every switch flat on the glass in columns, then Phase Stops as a pill (GameplayOptions). */
function Gameplay({ openStops }: { openStops: () => void }) {
  const [smart, setSmart] = useState<SmartPassSettings>(() => loadSmartPass(storage.get));
  const update = (next: SmartPassSettings) => { setSmart(next); saveSmartPass(next, storage.set); };
  const [passAfterCast, setPassAfterCast] = useSwitch("mm.web.autoPassAfterCast");
  const [speed, setSpeed] = useState<GameSpeed>(() => loadGameSpeed(storage.get));
  return (
    <>
      <div className="mflat">
        <h3 className="mpagelabel">Game speed</h3>
        <Segmented stretch label="Game speed" value={speed} onChange={(v) => { setSpeed(v); storage.set(GAME_SPEED_KEY, v); }}
          options={GAME_SPEEDS.map((value) => ({ label: GAME_SPEED_TITLES[value], value }))} />
      </div>
      <div className="mcolumns">
        <Checkbox title="Smart Auto-Pass" on={smart.enabled} id="settings.smartAutoPass" onChange={(on) => update({ ...smart, enabled: on })}
          hint="Passes for you when you have nothing to play, and skips steps you don’t stop at." />
        <Checkbox title="Stop for My Own Spells" on={smart.stopForOwnSpells} disabled={!smart.enabled} id="settings.stopForOwnSpells"
          onChange={(on) => update({ ...smart, stopForOwnSpells: on })} hint="Off: your own spells and triggers resolve without a stop." />
        <Checkbox title="Stop for Removal" on={smart.stopForThreats} id="settings.stopForThreats" onChange={(on) => update({ ...smart, stopForThreats: on })}
          hint="An opponent's spell that destroys, exiles or takes your permanents waits for you, even when you can't answer it." />
        <Checkbox title="Pass After Casting" on={passAfterCast} id="settings.autoPassAfterCast" onChange={setPassAfterCast}
          hint="Your spell resolves without another tap. Opponents can still respond." />
      </div>
      <div className="mcenter"><Pill id="settings.phaseStops" disabled={!smart.enabled} onClick={openStops}>Phase Stops</Pill></div>
    </>
  );
}

function StopsPage() {
  const [smart, setSmart] = useState<SmartPassSettings>(() => loadSmartPass(storage.get));
  return <div className="mstops"><PhaseStops settings={smart} onChange={(next) => { setSmart(next); saveSmartPass(next, storage.set); }} /></div>;
}

/** The table's effects and card frames (BoardEffectsPicker, CardFramesToggle). The web has only the Arena board. */
function BoardPage() {
  const [level, setLevel] = useState(() => storage.get("mm.web.boardEffects") ?? "full");
  const [frames, setFrames] = useSwitch("mm.web.cardFrames", false);
  return (
    <div className="mflat">
      <h3 className="mpagelabel">Effects</h3>
      <Segmented stretch label="Effects" value={level} onChange={(v) => { setLevel(v); storage.set("mm.web.boardEffects", v); }}
        options={[{ label: "Full", value: "full" }, { label: "Reduced", value: "reduced" }, { label: "Off", value: "off" }]} />
      <Checkbox title="Card Frames" on={frames} onChange={setFrames} id="settings.cardFrames"
        hint="Tavern frames on the Arena board's battlefield cards. Off, they show the card's art without the frame." />
    </div>
  );
}

/** Sound effects and music, each with a level, applied at once (GameAudioSettings). */
function AudioPage({ openLab }: { openLab: () => void }) {
  const [effects, setEffects] = useSwitch(SOUND_KEYS.effects);
  const [effectsVolume, setEffectsVolume] = useState(() => gameAudio.volume);
  const [music, setMusicRaw] = useState(() => gameAudio.musicEnabled);
  const [musicVolume, setMusicVolume] = useState(() => gameAudio.musicVolume);
  const setMusic = (on: boolean) => {
    setMusicRaw(on);
    storage.set(SOUND_KEYS.music, on ? "on" : "off");
    // Switching music back on brings back a level you can hear.
    if (on && musicVolume <= 0.02) { setMusicVolume(DEFAULT_MUSIC_VOLUME); storage.set(SOUND_KEYS.musicVolume, String(DEFAULT_MUSIC_VOLUME)); }
    gameAudio.settingsChanged();
  };
  return (
    <div className="mflat">
      <Checkbox title="Effect Sounds" on={effects} id="settings.boardSounds" onChange={(on) => { setEffects(on); if (on) gameAudio.play("ui-toggle"); }} />
      {effects && <Slider label="Effects volume" value={effectsVolume} onChange={(v) => { setEffectsVolume(v); storage.set(SOUND_KEYS.volume, v.toFixed(2)); gameAudio.play("ui-tick"); }} />}
      <Checkbox title="Music" on={music && musicVolume > 0} id="settings.music" onChange={setMusic} />
      {music && musicVolume > 0 && <Slider label="Music volume" value={musicVolume}
        onChange={(v) => { setMusicVolume(v); storage.set(SOUND_KEYS.musicVolume, v.toFixed(2)); gameAudio.settingsChanged(); }} />}
      <div className="mright"><Pill id="settings.soundLab" onClick={openLab}>Sound Lab</Pill></div>
    </div>
  );
}

/** Every sound and music track, auditionable, a switch per group, and the credits the music licence asks for (SoundLabView). */
function SoundLab() {
  const [choices, setChoices] = useState<Record<MusicScene, string>>(() => ({
    menu: storage.get(musicChoiceKey("menu")) ?? "shuffle", game: storage.get(musicChoiceKey("game")) ?? "shuffle",
  }));
  const [previewing, setPreviewing] = useState<string>();
  const [enabled, setEnabled] = useState(() => Object.fromEntries(SOUND_CATEGORIES.map((c) => [c.id, gameAudio.categoryEnabled(c.id)])));
  const choose = (scene: MusicScene, value: string) => { setChoices((c) => ({ ...c, [scene]: value })); storage.set(musicChoiceKey(scene), value); };
  return (
    <div className="mlab">
      <Caps text="Music" />
      {(["menu", "game"] as MusicScene[]).map((scene) => (
        <div key={scene} className="mcard mlabcard">
          <h3>{MUSIC[scene].title}</h3>
          <TrackRow title="Shuffle all" selected={choices[scene] === "shuffle"} onClick={() => { choose(scene, "shuffle"); gameAudio.settingsChanged(true); }} />
          {MUSIC[scene].tracks.map((track) => (
            <TrackRow key={track.file} title={track.title} selected={choices[scene] === track.file} playing={previewing === track.file}
              onClick={() => { choose(scene, track.file); setPreviewing(track.file); gameAudio.preview(track, scene); }} />
          ))}
        </div>
      ))}
      <Caps text="Sound effects" />
      {SOUND_CATEGORIES.map((category) => (
        <div key={category.id} className="mcard mlabcard">
          <Checkbox title={category.title} on={enabled[category.id]} hint={category.detail} id={`soundlab.category.${category.id}`}
            onChange={(on) => { setEnabled((e) => ({ ...e, [category.id]: on })); storage.set(categoryKey(category.id), on ? "on" : "off"); }} />
          <div className={`mlabchips ${enabled[category.id] ? "" : "off"}`}>
            {SOUND_TITLES.filter(([sound]) => soundCategory(sound) === category.id).map(([sound, title]) => (
              <button key={sound} type="button" aria-label={`Play ${title}`} onClick={() => { gameAudio.unlock(); gameAudio.play(sound, 0, 1, undefined, true); }}>
                <i>▶</i><span>{title}</span>
              </button>
            ))}
          </div>
        </div>
      ))}
      <Caps text="Credits" />
      <div className="mcard mlabcard mcredits">
        <Caps text="Music" size={9.5} />
        {[...MUSIC.menu.tracks, ...MUSIC.game.tracks].map((t) => <p key={t.file}>“{t.title}” Kevin MacLeod (incompetech.com)</p>)}
        {MUSIC_STINGERS.map((s) => <p key={s}>“{s}” Kevin MacLeod (incompetech.com), excerpt</p>)}
        <p>Licensed under Creative Commons: By Attribution 4.0 License</p>
        <p>http://creativecommons.org/licenses/by/4.0/</p>
        <Caps text="Sound effects" size={9.5} />
        <p>Recordings from the Sonniss.com GDC Game Audio Bundles (royalty-free), by David Dumais Audio, Sound Spark LLC, Gamemaster Audio, Articulated Sounds, Airborne Sound, Double Trouble Audio, Bluezone, 3maze, Timothy McHugh, Sound Ex Machina and more.</p>
        <p>Card recordings from Kenney.nl Casino Audio (CC0).</p>
        <Caps text="Table art" size={9.5} />
        <p>3D props made with Meshy (meshy.ai). The medallion, corner ornament, candle and tankard are licensed under Creative Commons: By Attribution 4.0 License.</p>
        <p>Wood and leather textures from Poly Haven (polyhaven.com, CC0).</p>
      </div>
    </div>
  );
}

function TrackRow({ title, selected, playing, onClick }: { title: string; selected: boolean; playing?: boolean; onClick: () => void }) {
  return (
    <button type="button" className={`mtrack ${selected ? "on" : ""}`} aria-pressed={selected} onClick={onClick}>
      <i className="mdiamond" /><span className="grow">{title}</span>
      {playing !== undefined && <em aria-hidden="true">{playing ? "♪" : "▶"}</em>}
    </button>
  );
}

/**
 * Display on a desktop: the window instead of the phone's rotation. Card art always comes from Scryfall here (the
 * browser has no offline art packs), so the phone's "Scryfall live images" switch has nothing to choose.
 */
function DisplayPage() {
  const [full, setFull] = useState(() => document.fullscreenElement !== null);
  useEffect(() => {
    const change = () => setFull(document.fullscreenElement !== null);
    document.addEventListener("fullscreenchange", change);
    return () => document.removeEventListener("fullscreenchange", change);
  }, []);
  return (
    <div className="mflat">
      <Checkbox title="Full Screen" on={full} id="settings.fullScreen" onChange={(on) => {
        if (on) void document.documentElement.requestFullscreen?.().catch(() => undefined);
        else void document.exitFullscreen?.().catch(() => undefined);
      }} />
    </div>
  );
}

/** Recent games' length and memory, to compare versions; numbers only, nothing is sent (GamePerformancePanel). */
function PerformancePage() {
  const entries = readPerformance();
  const [shown, setShown] = useState(false);
  const report = performanceReport(entries);
  return (
    <div className="mflat">
      <h3 className="mpagelabel">Game Performance</h3>
      <p className="mnote strong" data-id="settings.performance.last">{entries[0] ? `Last game: ${entries[0].line}` : "Finish a game to record one."}</p>
      <Pill id="settings.performance" disabled={entries.length === 0} onClick={() => setShown(!shown)}>View and Share</Pill>
      {shown && report && (
        <div className="mreport">
          <Pill lit onClick={() => { void navigator.clipboard?.writeText(report); }}>Copy Report</Pill>
          <pre>{report}</pre>
        </div>
      )}
    </div>
  );
}
