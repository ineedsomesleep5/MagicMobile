/**
 * Pictures the player chose for cards (Deck Studio's inspect, "Use my own picture"; iOS CustomCardArt.swift): kept in this
 * browser only (IndexedDB), one per card name, and laid over the card's art box wherever the card shows, so its name, cost
 * and rules stay the real card's. Opponents see the card's usual art.
 */
import { artKey } from "../core/artChoices";

const MAXIMUM_EDGE = 1200;
const DATABASE = "mm-custom-art";
const STORE = "pictures";

/** Card key to an object URL of its picture. */
const pictures = new Map<string, string>();
/** "key|version|base URL" to an object URL of the composed card, once made. */
const composed = new Map<string, string>();
const composing = new Set<string>();
let version = 0;
const listeners = new Set<() => void>();
const changed = () => { version++; listeners.forEach((listener) => listener()); };

export const customArtVersion = () => version;
export const subscribeCustomArt = (listener: () => void) => { listeners.add(listener); return () => { listeners.delete(listener); }; };
export const hasCustomArt = (name: string) => pictures.has(artKey(name));
export const customPictureURL = (name: string) => pictures.get(artKey(name));

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

/** Reads every saved picture once, at start. */
export async function loadCustomArt(): Promise<void> {
  const db = await database();
  if (!db) return;
  await new Promise<void>((resolve) => {
    const request = db.transaction(STORE, "readonly").objectStore(STORE).openCursor();
    request.onsuccess = () => {
      const cursor = request.result;
      if (!cursor) { resolve(); return; }
      if (cursor.value instanceof Blob) pictures.set(String(cursor.key), URL.createObjectURL(cursor.value));
      cursor.continue();
    };
    request.onerror = () => resolve();
  });
  if (pictures.size > 0) changed();
}

const forget = (key: string) => {
  const old = pictures.get(key);
  if (old) URL.revokeObjectURL(old);
  pictures.delete(key);
  for (const [entry, url] of composed) if (entry.startsWith(key + "|")) { URL.revokeObjectURL(url); composed.delete(entry); }
};

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
  if (!blob) return false;
  const key = artKey(name);
  if ((await transaction("readwrite", (store) => store.put(blob, key))) === undefined) return false;
  forget(key);
  pictures.set(key, URL.createObjectURL(blob));
  changed();
  return true;
}

export async function removeCustomArt(name: string): Promise<void> {
  const key = artKey(name);
  await transaction("readwrite", (store) => store.delete(key));
  forget(key);
  changed();
}

/** The art box (iOS illustrationImage's window) on a card of this size. */
export const artBox = (width: number, height: number) => ({ x: width * 0.08, y: height * 0.145, width: width * 0.84, height: height * 0.385 });

const loadImage = (url: string) => new Promise<HTMLImageElement | undefined>((resolve) => {
  const image = new Image();
  image.crossOrigin = "anonymous";
  image.onload = () => resolve(image);
  image.onerror = () => resolve(undefined);
  image.src = url;
});

/**
 * The card's picture for a full-card image: the composed card once it is made, else undefined (the caller shows the plain
 * card meanwhile, and a change notice follows when the composed one is ready).
 */
export function composedCardURL(name: string, imageVersion: string, baseURL: string): string | undefined {
  const key = artKey(name);
  const picture = pictures.get(key);
  if (!picture) return undefined;
  const entry = `${key}|${imageVersion}|${baseURL}`;
  const ready = composed.get(entry);
  if (ready || composing.has(entry)) return ready;
  composing.add(entry);
  void (async () => {
    const [card, art] = await Promise.all([loadImage(baseURL), loadImage(picture)]);
    if (card && art && pictures.get(key) === picture) {
      const canvas = document.createElement("canvas");
      canvas.width = card.naturalWidth; canvas.height = card.naturalHeight;
      const context = canvas.getContext("2d");
      if (context) {
        context.drawImage(card, 0, 0);
        const box = artBox(canvas.width, canvas.height);
        const scale = Math.max(box.width / art.naturalWidth, box.height / art.naturalHeight);
        const width = box.width / scale, height = box.height / scale;
        context.drawImage(art, (art.naturalWidth - width) / 2, (art.naturalHeight - height) / 2, width, height, box.x, box.y, box.width, box.height);
        const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.9));
        if (blob && pictures.get(key) === picture) { composed.set(entry, URL.createObjectURL(blob)); changed(); }
      }
    }
    composing.delete(entry);
  })();
  return undefined;
}
