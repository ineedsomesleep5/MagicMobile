/**
 * Pictures the player chose for cards (Deck Studio's inspect, "Use my own picture"; iOS CustomCardArt.swift): kept in this
 * browser (IndexedDB), one per card name, synced to the player's other phones and browsers (core/cardArtSync.ts), and
 * worn as the whole card face wherever the card shows. A picture is usually a card of its own (name, cost, rules drawn
 * on it), so nothing of the printed card shows through. Opponents see the card's usual art.
 */
import { artKey } from "../core/artChoices";
import { type CardArtLocal, pictureHash } from "../core/cardArtSync";

const MAXIMUM_EDGE = 1200;
const DATABASE = "mm-custom-art";
const STORE = "pictures";
/** A card's width over its height (63 × 88 mm). */
const CARD_ASPECT = 63 / 88;

/** Card key to its picture's bytes, object URL and hash (once worked out). */
const pictures = new Map<string, { blob: Blob; url: string; hash?: string }>();
/** "key|version|base URL" (or "key|crop") to an object URL of the composed card or art crop, once made. */
const composed = new Map<string, string>();
const composing = new Set<string>();
let version = 0;
const listeners = new Set<() => void>();
const changed = () => { version++; listeners.forEach((listener) => listener()); };
/** Told when the player removes a card's picture here (the sync sends the removal). */
let onRemoved: ((cardKey: string) => void) | undefined;
/** Told when the player sets a picture here (the sync sends it a moment later). */
let onSaved: (() => void) | undefined;
export const setCustomArtListeners = (removed?: (cardKey: string) => void, saved?: () => void) => { onRemoved = removed; onSaved = saved; };

export const customArtVersion = () => version;
export const subscribeCustomArt = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
export const hasCustomArt = (name: string) => pictures.has(artKey(name));

function database(): Promise<IDBDatabase | undefined> {
  return new Promise((resolve) => {
    try {
      const request = indexedDB.open(DATABASE, 1);
      request.onupgradeneeded = () => request.result.createObjectStore(STORE);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => resolve(undefined);
    } catch { resolve(undefined); }
  });
}

async function transaction<T>(mode: IDBTransactionMode, work: (store: IDBObjectStore) => IDBRequest<T>): Promise<T | undefined> {
  const db = await database();
  if (!db) return undefined;
  return new Promise((resolve) => {
    const request = work(db.transaction(STORE, mode).objectStore(STORE));
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => resolve(undefined);
  });
}

let loaded: Promise<void> | undefined;
/** Reads every saved picture once, at start. */
export function loadCustomArt(): Promise<void> {
  loaded ??= (async () => {
    const db = await database();
    if (!db) return;
    await new Promise<void>((resolve) => {
      const request = db.transaction(STORE, "readonly").objectStore(STORE).openCursor();
      request.onsuccess = () => {
        const cursor = request.result;
        if (!cursor) { resolve(); return; }
        if (cursor.value instanceof Blob) pictures.set(String(cursor.key), { blob: cursor.value, url: URL.createObjectURL(cursor.value) });
        cursor.continue();
      };
      request.onerror = () => resolve();
    });
    if (pictures.size > 0) changed();
  })();
  return loaded;
}

const forget = (key: string) => {
  const old = pictures.get(key);
  if (old) URL.revokeObjectURL(old.url);
  pictures.delete(key);
  for (const [entry, url] of composed) if (entry.startsWith(key + "|")) { URL.revokeObjectURL(url); composed.delete(entry); }
};

/** Keeps `blob` as the card's picture. False when the browser couldn't store it. */
async function keep(key: string, blob: Blob): Promise<boolean> {
  if ((await transaction("readwrite", (store) => store.put(blob, key))) === undefined) return false;
  forget(key);
  pictures.set(key, { blob, url: URL.createObjectURL(blob) });
  changed();
  return true;
}

async function drop(key: string) {
  await transaction("readwrite", (store) => store.delete(key));
  forget(key);
  changed();
}

/** Saves a picture for the card from a chosen file, scaled down and kept as JPEG. False when it can't be read. */
export async function saveCustomArt(name: string, file: Blob): Promise<boolean> {
  const bitmap = await createImageBitmap(file).catch(() => undefined);
  if (!bitmap) return false;
  const scale = Math.min(1, MAXIMUM_EDGE / Math.max(bitmap.width, bitmap.height));
  const canvas = document.createElement("canvas");
  canvas.width = Math.max(1, Math.round(bitmap.width * scale));
  canvas.height = Math.max(1, Math.round(bitmap.height * scale));
  canvas.getContext("2d")?.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
  bitmap.close();
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.85));
  if (!blob || !(await keep(artKey(name), blob))) return false;
  onSaved?.();
  return true;
}

export async function removeCustomArt(name: string): Promise<void> {
  const key = artKey(name);
  await drop(key);
  onRemoved?.(key);
}

/** This browser's pictures for the sync (core/cardArtSync.ts). */
export const localCardArt: CardArtLocal = {
  keys: () => [...pictures.keys()],
  async hash(key) {
    const entry = pictures.get(key);
    if (!entry) return undefined;
    entry.hash ??= await pictureHash(entry.blob);
    return entry.hash;
  },
  bytes: async (key) => pictures.get(key)?.blob,
  async store(key, bytes) { await keep(key, bytes.type === "image/jpeg" ? bytes : new Blob([bytes], { type: "image/jpeg" })); },
  remove: (key) => drop(key),
};

/** The art box (iOS illustrationImage's window) on a card of this size. */
export const artBox = (width: number, height: number) => ({ x: width * 0.08, y: height * 0.145, width: width * 0.84, height: height * 0.385 });

/** The picture as a card face: the largest card-shaped window in its middle. */
const cardFace = (width: number, height: number) => {
  const faceWidth = Math.min(width, height * CARD_ASPECT), faceHeight = faceWidth / CARD_ASPECT;
  return { x: (width - faceWidth) / 2, y: (height - faceHeight) / 2, width: faceWidth, height: faceHeight };
};

const loadImage = (url: string) => new Promise<HTMLImageElement | undefined>((resolve) => {
  const image = new Image();
  image.crossOrigin = "anonymous";
  image.onload = () => resolve(image);
  image.onerror = () => resolve(undefined);
  image.src = url;
});

/** Draws `entry` once into an object URL, then announces it; undefined meanwhile. */
function compose(key: string, entry: string, picture: string, draw: (art: HTMLImageElement) => HTMLCanvasElement | undefined): string | undefined {
  const ready = composed.get(entry);
  if (ready || composing.has(entry)) return ready;
  composing.add(entry);
  void (async () => {
    const art = await loadImage(picture);
    const canvas = art && pictures.get(key)?.url === picture ? draw(art) : undefined;
    const blob = canvas ? await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.9)) : null;
    if (blob && pictures.get(key)?.url === picture) { composed.set(entry, URL.createObjectURL(blob)); changed(); }
    composing.delete(entry);
  })();
  return undefined;
}

/**
 * The card's picture for a full-card image: the picture filling the whole card (Scryfall's size for that version), once
 * made; undefined meanwhile (the caller shows the plain card, and a change notice follows).
 */
export function composedCardURL(name: string, imageVersion: string): string | undefined {
  const key = artKey(name);
  const picture = pictures.get(key)?.url;
  if (!picture) return undefined;
  return compose(key, `${key}|${imageVersion}`, picture, (art) => {
    // Scryfall's normal and large images are 488 × 680 and 672 × 936.
    const canvas = document.createElement("canvas");
    canvas.width = imageVersion === "large" ? 672 : 488;
    canvas.height = imageVersion === "large" ? 936 : 680;
    const face = cardFace(art.naturalWidth, art.naturalHeight);
    canvas.getContext("2d")?.drawImage(art, face.x, face.y, face.width, face.height, 0, 0, canvas.width, canvas.height);
    return canvas;
  });
}

/** The picture's art box (where a card's illustration sits), for places that show only the art. */
export function customArtCropURL(name: string): string | undefined {
  const key = artKey(name);
  const picture = pictures.get(key)?.url;
  if (!picture) return undefined;
  return compose(key, `${key}|crop`, picture, (art) => {
    const face = cardFace(art.naturalWidth, art.naturalHeight);
    const box = artBox(face.width, face.height);
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(box.width));
    canvas.height = Math.max(1, Math.round(box.height));
    canvas.getContext("2d")?.drawImage(art, face.x + box.x, face.y + box.y, box.width, box.height, 0, 0, canvas.width, canvas.height);
    return canvas;
  });
}
