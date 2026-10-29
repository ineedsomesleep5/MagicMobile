/**
 * Port of apps/android/core/.../game/Json.kt (itself a port of the Swift JSONValue): the engine
 * speaks plain JSON and these helpers read it the same way. A string is never a number or a
 * boolean, and a number is an integer only when exact.
 */
export type J = null | boolean | number | string | J[] | { [key: string]: J };
export type JObject = { [key: string]: J };

export const isObject = (value: unknown): value is JObject =>
  typeof value === "object" && value !== null && !Array.isArray(value);

export const str = (value: J | undefined): string | undefined => (typeof value === "string" ? value : undefined);
export const int = (value: J | undefined): number | undefined =>
  typeof value === "number" && Number.isInteger(value) ? value : undefined;
export const bool = (value: J | undefined): boolean | undefined => (typeof value === "boolean" ? value : undefined);
export const arr = (value: J | undefined): J[] | undefined => (Array.isArray(value) ? value : undefined);
export const obj = (value: J | undefined): JObject | undefined => (isObject(value) ? value : undefined);
/** `value[key]` for an object, otherwise undefined (Kotlin `J?.get`). */
export const get = (value: J | undefined, key: string): J | undefined =>
  isObject(value) && Object.prototype.hasOwnProperty.call(value, key) ? value[key] : undefined;
/** Follows a path of object keys. */
export const at = (value: J | undefined, ...keys: string[]): J | undefined =>
  keys.reduce<J | undefined>((current, key) => get(current, key), value);

export const keysEqual = (value: JObject, keys: string[]): boolean => {
  const own = Object.keys(value);
  return own.length === keys.length && keys.every((key) => Object.prototype.hasOwnProperty.call(value, key));
};

/** Swift `JSONValue.stringValue` (numbers and booleans read as text). */
export const stringValue = (value: J | undefined): string | undefined => {
  if (typeof value === "string") return value;
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "number") return Number.isInteger(value) ? String(value) : String(value);
  return undefined;
};

/** Swift `UUID(uuidString:)`: exactly 8-4-4-4-12 hex digits. */
const uuidPattern = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/;
export const isUuid = (value: unknown): value is string => typeof value === "string" && uuidPattern.test(value);
/** Two UUID strings name the same UUID (case-insensitive). */
export const sameUuid = (a: string | undefined, b: string | undefined): boolean =>
  isUuid(a) && isUuid(b) && a.toLowerCase() === b.toLowerCase();
/** iOS encodes UUIDs uppercase (`uuidString`); every UUID this client sends does too. */
export const newUuid = (): string => crypto.randomUUID().toUpperCase();

/** Deep structural equality, insensitive to key order (Kotlin JsonElement equality). */
export const jsonEqual = (a: J | undefined, b: J | undefined): boolean => {
  if (a === b) return true;
  if (Array.isArray(a)) return Array.isArray(b) && a.length === b.length && a.every((item, index) => jsonEqual(item, b[index]));
  if (isObject(a)) {
    if (!isObject(b)) return false;
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every((key) => Object.prototype.hasOwnProperty.call(b, key) && jsonEqual(a[key], b[key]));
  }
  return false;
};

export const WireLimits = { maxJSONBytes: 4 * 1024 * 1024 } as const;

/** Port of the Swift `EngineError`. Messages match the apps word for word. */
export class EngineError extends Error {
  constructor(message: string, readonly code?: string, readonly isRejection = false) {
    super(message);
    this.name = "EngineError";
  }
  static messageTooLarge = () => new EngineError("Message exceeds the supported size.", "message_too_large");
  static invalid = (message: string) => new EngineError(message, "invalid_message");
  /** The engine or host refused the request: certain, unlike a timeout or a busy host. */
  static rejected = (code: string, message: string) => new EngineError(message, code, true);
  static incompatibleBuild = () => new EngineError("Players must use the same engine, catalogue, and protocol build.", "incompatible_build");
  static unboundPeer = () => new EngineError("This authenticated peer has not been assigned a seat.", "unbound_peer");
  static replayed = () => new EngineError("Duplicate or out-of-order transport message.", "replayed");
  static hostSuspended = () => new EngineError("The host paused input. Return the host app to the foreground.", "host_suspended");
}

const utf8 = new TextEncoder();
export const utf8Length = (text: string): number => utf8.encode(text).length;
/** Unicode scalar count (Kotlin `codePointCount`, Swift `unicodeScalars.count`). */
export const codePointCount = (text: string): number => {
  let count = 0;
  for (const _ of text) count += 1;
  return count;
};

const validated = (value: J, depth = 0): void => {
  if (depth > 64) throw EngineError.invalid("JSON nesting limit exceeded");
  if (Array.isArray(value)) value.forEach((item) => validated(item, depth + 1));
  else if (isObject(value)) Object.values(value).forEach((item) => validated(item, depth + 1));
  else if (typeof value === "number" && !Number.isFinite(value)) throw EngineError.invalid("Nonfinite number");
};

export const EngineJson = {
  validated,
  /** Keys sorted, like the Swift encoder, so equal values encode to equal text. */
  sorted(value: J): J {
    if (Array.isArray(value)) return value.map((item) => EngineJson.sorted(item));
    if (isObject(value)) {
      const result: JObject = {};
      for (const key of Object.keys(value).sort()) result[key] = EngineJson.sorted(value[key]);
      return result;
    }
    return value;
  },
  /**
   * A 64-bit integer the protocol needs exactly (a ranked game's seed), which a JS number can't hold past 2^53: a marked
   * string in the value, written as a bare JSON integer by `encode`.
   */
  integer: (value: bigint): string => `\u0000int:${value.toString()}`,
  encode(value: J): string {
    validated(value);
    const text = JSON.stringify(EngineJson.sorted(value)).replace(/"\\u0000int:(-?\d+)"/g, "$1");
    if (utf8Length(text) > WireLimits.maxJSONBytes) throw EngineError.messageTooLarge();
    return text;
  },
  decode(text: string): J {
    if (text.length === 0 || utf8Length(text) > WireLimits.maxJSONBytes) throw EngineError.messageTooLarge();
    let value: J;
    try {
      value = JSON.parse(text) as J;
    } catch {
      throw EngineError.invalid("Malformed JSON");
    }
    validated(value);
    return value;
  },
};
