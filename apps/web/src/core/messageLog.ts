/**
 * Port of OnDeviceMessageLog.kt: retains only this seat's explicit informational events in memory.
 * Not a complete action log or a source of hidden details.
 */
import type { MatchPoll } from "./engineClient";
import { arr, EngineError, get, int, obj, str, utf8Length } from "./json";
import type { GameLogEntry } from "./models";

const retainedMessages = 64;
const retainedBytes = 1024 * 1024;
const AUTO_PASS_PREFIX = "local:auto-pass:";
/** The latest six labels of a run. */
const autoPassMessage = (labels: string[]) => "Auto-passed: " + labels.slice(-6).join(" · ");

export class OnDeviceMessageLog {
  private matchID?: string;
  private seatID?: string;
  private processedThrough = -1;
  entries: GameLogEntry[] = [];
  private messageBytes = 0;
  /** The steps or stack items in the current run of automatic passes (one log line per run). */
  private autoPassRun: string[] = [];

  /**
   * A quiet local line for a pass smart pass made for the player (OnDeviceMessageLog.noteAutoPass), so the game never
   * seems to move on without them. A run of passes shares one line ("Auto-passed: Upkeep · Draw · Main 1").
   */
  noteAutoPass(label: string, id: string): void {
    const next = [...this.entries];
    const last = next.at(-1);
    if (last && last.id.startsWith(AUTO_PASS_PREFIX)) {
      if (this.autoPassRun.at(-1) !== label) this.autoPassRun = [...this.autoPassRun, label];
      this.messageBytes -= utf8Length(last.message);
      next[next.length - 1] = { id: last.id, message: autoPassMessage(this.autoPassRun) };
    } else {
      this.autoPassRun = [label];
      next.push({ id: AUTO_PASS_PREFIX + id, message: autoPassMessage(this.autoPassRun) });
    }
    this.messageBytes += utf8Length(next.at(-1)!.message);
    while (next.length > retainedMessages) this.messageBytes -= utf8Length(next.shift()!.message);
    this.entries = next;
  }

  /** Validate the whole batch before changing state. Older polls never duplicate notices. */
  ingest(poll: MatchPoll): void {
    if (poll.matchID.length === 0 || poll.seatID.length === 0 || (this.matchID !== undefined && this.matchID !== poll.matchID) ||
      (this.seatID !== undefined && this.seatID !== poll.seatID)) throw EngineError.unboundPeer();
    if (poll.revision < this.processedThrough) return;
    const supplied = poll.raw.events;
    let events: unknown[] = [];
    if (supplied !== undefined) {
      const values = arr(supplied);
      if (!values || values.length > 128) throw EngineError.invalid("Malformed engine event history");
      events = values;
    }
    const next = [...this.entries];
    let bytes = this.messageBytes;
    let previous = -1;
    for (const event of events as never[]) {
      const revision = int(get(event, "revision"));
      const kind = str(get(event, "kind"));
      if (revision === undefined || revision < 0 || revision > poll.revision || revision <= previous || kind === undefined) {
        throw EngineError.invalid("Malformed engine event revision");
      }
      previous = revision;
      if (revision <= this.processedThrough || kind !== "message") continue;
      const body = obj(get(event, "body"));
      if (!body) throw EngineError.invalid("Malformed private engine notice");
      // Upstream can emit an empty informational message. Do not invent text.
      if (body.message === null) continue;
      const message = str(body.message);
      if (message === undefined) throw EngineError.invalid("Private engine notice has no text");
      if (message.length === 0) continue;
      next.push({ id: `xmage:${poll.matchID}:${poll.seatID}:${revision}`, message });
      bytes += utf8Length(message);
      // Keep the latest message intact, even when it alone exceeds the history budget.
      while (next.length > retainedMessages || (bytes > retainedBytes && next.length > 1)) bytes -= utf8Length(next.shift()!.message);
    }
    this.matchID = poll.matchID; this.seatID = poll.seatID;
    this.processedThrough = poll.revision; this.entries = next; this.messageBytes = bytes;
  }
}
