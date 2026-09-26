// Test entry for `wrangler dev --local`: the relay, with its storage held to a production limit
// that local SQLite does not enforce. SQLite-backed Durable Objects refuse a key and value over
// 2 MB (https://developers.cloudflare.com/durable-objects/platform/limits/); locally the same
// write succeeds, so without this guard a test would pass where the deployed relay loses packets.
import relay, { TableRoom as Relay } from "../src/index.js";

const MAX_ENTRY_BYTES = 2_000_000;
const encoder = new TextEncoder();

/** An upper bound on a stored value's size: V8 keeps a string at 1 byte per Latin-1 unit, else 2 per UTF-16 unit. */
function storedBytes(value) {
  const text = typeof value === "string" ? value : JSON.stringify(value) ?? "";
  return /[^\u0000-ÿ]/.test(text) ? text.length * 2 : text.length;
}

function check(key, value) {
  const bytes = encoder.encode(key).length + storedBytes(value);
  if (bytes > MAX_ENTRY_BYTES) throw new RangeError(`Storage entry ${key} is ${bytes} bytes; the limit is ${MAX_ENTRY_BYTES}.`);
}

export class TableRoom extends Relay {
  constructor(ctx, env) {
    const storage = ctx.storage;
    const put = storage.put.bind(storage);
    storage.put = (...args) => {
      if (typeof args[0] === "string") check(args[0], args[1]);
      else for (const [key, value] of Object.entries(args[0])) check(key, value);
      return put(...args);
    };
    super(ctx, env);
  }
}

export default relay;
