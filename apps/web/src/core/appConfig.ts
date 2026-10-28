/**
 * What the server can change without a release (AppConfig.swift / .kt, mm_app_config; docs/SERVER_CONTROLS.md): a news
 * banner for the main menu, card-name fixes for deck imports, and switches for newer features. The browser keeps the last
 * copy (localStorage, wrapped like every other read here), so it applies before the server answers.
 */
import { get, isObject, type J, str } from "./json";

export interface AppNotice { id: string; text: string }
export interface AppConfig { notice?: AppNotice; nameFixes: Record<string, string>; switches: Record<string, boolean> }

const KEY = "mm.web.appConfig";
const DISMISSED_KEY = "mm.web.appConfig.dismissedNotice";
const MAX_NAME_FIXES = 500;

export const AppConfig = {
  empty: (): AppConfig => ({ nameFixes: {}, switches: {} }),
  /** mm_app_config's reply; undefined when it isn't one. */
  parse(json: J | undefined): AppConfig | undefined {
    if (!isObject(json)) return undefined;
    const config = AppConfig.empty();
    const notice = get(json, "notice"), id = str(get(notice, "id")), text = str(get(notice, "text"));
    if (id && text) config.notice = { id: id.slice(0, 80), text: text.slice(0, 280) };
    const fixes = get(json, "nameFixes");
    if (isObject(fixes)) {
      for (const [from, to] of Object.entries(fixes).slice(0, MAX_NAME_FIXES)) {
        if (typeof to === "string" && from !== "" && to !== "" && from.length <= 200 && to.length <= 200) config.nameFixes[from] = to;
      }
    }
    const switches = get(json, "switches");
    if (isObject(switches)) for (const [name, value] of Object.entries(switches)) if (typeof value === "boolean") config.switches[name] = value;
    return config;
  },
  /** A switch the server hasn't named is on, unless the feature says otherwise (voiceChat). */
  isOn: (config: AppConfig, name: string, fallback = true) => config.switches[name] ?? fallback,
};

let current: AppConfig = (() => {
  try { const raw = globalThis.localStorage?.getItem(KEY); return (raw ? AppConfig.parse(JSON.parse(raw)) : undefined) ?? AppConfig.empty(); }
  catch { return AppConfig.empty(); }
})();
const listeners = new Set<() => void>();

export const appConfig = {
  get current(): AppConfig { return current; },
  /** Keeps a reply from the server; anything else is ignored and the last copy stays. */
  store(json: J | undefined) {
    const parsed = AppConfig.parse(json);
    if (!parsed) return;
    current = parsed;
    try { globalThis.localStorage?.setItem(KEY, JSON.stringify(json)); } catch { /* the copy lasts this visit */ }
    listeners.forEach((l) => l());
  },
  isOn: (name: string, fallback = true) => AppConfig.isOn(current, name, fallback),
  /** The notice to show on the main menu, unless the player closed it. */
  shownNotice(): AppNotice | undefined {
    const notice = current.notice;
    if (!notice) return undefined;
    try { if (globalThis.localStorage?.getItem(DISMISSED_KEY) === notice.id) return undefined; } catch { /* show it */ }
    return notice;
  },
  dismiss(notice: AppNotice) {
    try { globalThis.localStorage?.setItem(DISMISSED_KEY, notice.id); } catch { /* hidden for this visit */ }
    listeners.forEach((l) => l());
  },
  subscribe(listener: () => void) { listeners.add(listener); return () => { listeners.delete(listener); }; },
};
