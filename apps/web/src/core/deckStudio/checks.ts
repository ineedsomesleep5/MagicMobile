/**
 * Play and XMage check results: DeckStudioPlayText, DeckStudioPlayRules and DeckStudioListFilter (DeckStudioPlaySelection.swift,
 * DeckStudioPreflight.swift) and the stored results (DeckStudioReceiptStore.swift; Android DeckStudioPlayFlow.kt and
 * DeckStudioReceiptStore.kt). A stored result is evidence for one exact request and install, never a flag on a deck.
 */
import type { KeyValueStore } from "../playerRecord";
import { DraftPresentation, utf8Size, type DeckDraft, type DraftRow, type StudioDeck } from "./draft";
import { cardCountLabel, PreflightIssue, type Preflight } from "./preflight";

export type PlayStatus = "ready" | "needsFixes" | "notChecked";

/** Deck Studio's wording for Play and the builder, one source per platform (deck-studio-cases.json `strings`). */
export const PlayText = {
  play: "Play this deck",
  saveAndPlay: "Save & play",
  playing: "Playing",
  playingAccessibility: "This is your playing deck",
  ready: "Ready",
  needsFixes: "Needs fixes",
  notChecked: "Not checked",
  fixDeck: "Fix deck",
  notNow: "Not now",
  setUpGame: "Set up game",
  cannotPlayTitle: "Can't play this deck yet",
  checkingTitle: "Checking your deck",
  checkingProgress: "Checking Commander rules…",
  gameLive: "Leave your current game to change decks.",
  catalogueLoading: "The local card catalogue is still loading.",
  setupReady: "Ready · checked on this device",
  setupNotChecked: "Not checked — Start will check it",
  setupNeedsFixes: "Needs fixes · Fix in Deck Studio",
  panelCaption: "Check the Commander rules on this device, then play this deck.",
  showAll: "Show all",
  /** A stored pass from a game XMage created. */
  startPassed: "Passed the installed XMage Commander validator",
  cardDetails: "Card details",
  addOne: "Add one",
  removeOne: "Remove one",
  replaceCard: "Replace card",
  moveTo: "Move to…",
  removeRow: "Remove row",
  select: "Select",
  selectCards: "Select cards",
  doneSelecting: "Done selecting",
  selectAll: "Select all",
  setQuantity: "Set quantity",
  remove: "Remove",
  removeSelectedTitle: "Remove the selected cards?",
  removeSelectedMessage: "Undo brings them back.",
  quantityMessage: "Every selected card gets this quantity, from 1 to 2,000.",
  quantityError: "Use a quantity from 1 to 2,000. Nothing was changed.",
  showAsGrid: "Show as grid",
  showAsList: "Show as list",
  quickAdd: "Quick add",
  quickAddMain: "Main",
  quickAddMaybe: "Maybe",
  quickAddMaybeboard: "Add to maybeboard",
  addCards: "Add cards",
  quickAddHint: "Type a card name, or a count first, like 2x Sol Ring. Return adds the top match.",
  quickAddNeedsName: "Type a card name, like 2x Sol Ring.",
  quickAddFailed: "Could not add this card. Check the draft's size limits.",
  undo: "Undo",
  editAsText: "Edit as text",
  copyList: "Copy list",
  listCopied: "List copied",
  reviewChanges: "Review changes",
  applyChanges: "Apply changes",
  keepEditing: "Keep editing",
  diffAdded: "Added",
  diffRemoved: "Removed",
  noChanges: "No changes to apply.",
  textEditorHint: "One card per line, like 1 Sol Ring, under Commander, Deck, Companion, Sideboard or Maybeboard headings.",
  chooseCommander: "Choose a commander",
  skip: "Skip",
  commanderFirstTitle: "Start with your commander",
  commanderFirstCaption: "Legendary creatures and cards that say they can be your commander. The deck takes its name until you rename it.",
  searchCommanders: "Search commanders",
  searchHint: "Filters work too: t:creature, o:draw, mv<=3, id:wu",
  withinIdentity: "Within commander color identity",
  sampleHand: "Sample hand",
  sampleHandCaption: "Draw seven from your main deck. Commanders stay in the command zone, and sideboard and maybeboard cards stay out.",
  sampleHandEmpty: "Add main-deck cards to draw a sample hand.",
  draw7: "Draw 7",
  newHand: "New hand",
  mulligan: "Mulligan",
  draw: "Draw",
} as const;

/** Move to… destinations: board and title. "considering" counts as maybeboard. */
export const destinations: readonly (readonly [string, string])[] = [
  ["deck", "Main deck"], ["commanders", "Commanders"], ["companions", "Companions"], ["sideboard", "Sideboard"], ["maybeboard", "Maybeboard"],
];

export const PlayStatus = {
  title: (status: PlayStatus) => ({ ready: PlayText.ready, needsFixes: PlayText.needsFixes, notChecked: PlayText.notChecked })[status],
  setup: (status: PlayStatus) => ({ ready: PlayText.setupReady, needsFixes: PlayText.setupNeedsFixes, notChecked: PlayText.setupNotChecked })[status],
};

/** DeckStudioPlayText's formatted strings. */
export const PlayWords = {
  checking: (name: string) => `XMage is checking ${name} against the Commander rules on this device.`,
  nowPlaying: (name: string) => `Now playing ${name}`,
  nowPlayingStrip: (name: string, status?: PlayStatus) => `Now playing: ${name}${status ? ` · ${PlayStatus.title(status)}` : ""}`,
  issues: (count: number) => (count === 1 ? "1 issue" : `${count} issues`),
  issuesBlockPlay: (count: number) => (count === 1 ? "1 rule issue blocks play" : `${count} rule issues block play`),
  notShown: (count: number) => `${PlayWords.issues(count)} not shown`,
  excluded: (count: number) => `Sideboard and maybeboard stay out of play (${cardCountLabel(count)}).`,
  deletePlaying: (replacement: string) => `This is your playing deck. ${replacement} will be selected instead.`,
  showingOnly: (label: string) => `Showing only: ${label}`,
  selected: (count: number) => `${count} selected`,
  added: (quantity: number, name: string, maybeboard: boolean) => `Added ${quantity} × ${name}${maybeboard ? " to maybeboard" : ""}`,
  noCardNamed: (name: string) => `No card named “${name}” in this app’s catalogue.`,
  handCounts: (hand: number, library: number) => `${cardCountLabel(hand)} in hand · ${cardCountLabel(library)} in library`,
};

/** SHA-256 as lowercase hex of the text's UTF-8 bytes, synchronous so a lookup can key on it while rendering. */
export function sha256(text: string): string {
  const k = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2]);
  const bytes = new TextEncoder().encode(text);
  const length = Math.ceil((bytes.length + 9) / 64) * 64;
  const padded = new Uint8Array(length);
  padded.set(bytes);
  padded[bytes.length] = 0x80;
  const view = new DataView(padded.buffer);
  view.setUint32(length - 8, Math.floor((bytes.length * 8) / 2 ** 32));
  view.setUint32(length - 4, (bytes.length * 8) >>> 0);
  const h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const w = new Uint32Array(64);
  const rotr = (x: number, n: number) => (x >>> n) | (x << (32 - n));
  for (let offset = 0; offset < length; offset += 64) {
    for (let i = 0; i < 16; i += 1) w[i] = view.getUint32(offset + i * 4);
    for (let i = 16; i < 64; i += 1) {
      const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = w[i - 16] + s0 + w[i - 7] + s1;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let i = 0; i < 64; i += 1) {
      const t1 = (hh + (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) + ((e & f) ^ (~e & g)) + k[i] + w[i]) >>> 0;
      const t2 = ((rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) >>> 0;
      hh = g; g = f; f = e; e = (d + t1) >>> 0; d = c; c = b; b = a; a = (t1 + t2) >>> 0;
    }
    h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }
  return [...h].map((value) => value.toString(16).padStart(8, "0")).join("");
}

/**
 * What a stored XMage check is bound to: the source deck ID, the SHA-256 of the exact resolved engine request, the engine
 * commit, the catalogue hash and the app build. A change to any of them is a different key.
 */
export interface CheckKey { deckID: string; requestSHA256: string; upstream: string; catalogue: string; appBuild: string }

export const CheckKey = {
  of: (deckID: string, request: string, upstream: string, catalogue: string, appBuild: string): CheckKey =>
    ({ deckID, requestSHA256: sha256(request), upstream, catalogue, appBuild }),
  equal: (a: CheckKey, b: CheckKey) => a.deckID === b.deckID && a.requestSHA256 === b.requestSHA256 && CheckKey.sameInstall(a, b),
  /** Results from another engine, catalogue or app build can never match again. */
  sameInstall: (a: CheckKey, b: CheckKey) => a.upstream === b.upstream && a.catalogue === b.catalogue && a.appBuild === b.appBuild,
};

/** DeckStudioValidationReceipt.Issue: one rule problem XMage reported. */
export interface CheckIssue { index: number; type: string; group?: string; message: string; cardName?: string }

/** One stored check, passed or failed. */
export interface CheckResult {
  key: CheckKey;
  /** Milliseconds since 1970. */
  checkedAt: number;
  valid: boolean;
  /** The first `maximumIssues` issues. */
  issues: CheckIssue[];
  /** Every issue XMage reported. */
  issueCount: number;
  summary: string;
}

export const maximumIssues = 100;

function decodeResult(raw: unknown): CheckResult {
  const value = raw as Record<string, unknown>;
  const fail = (): never => { throw new Error("invalid"); };
  if (typeof value !== "object" || value === null) fail();
  const text = (key: string, limit: number) => {
    const field = value[key];
    return typeof field === "string" && field.length > 0 && utf8Size(field) <= limit ? field : fail();
  };
  const optional = (row: Record<string, unknown>, key: string) => {
    const field = row[key];
    if (field === undefined || field === null) return undefined;
    return typeof field === "string" && utf8Size(field) <= 2048 ? field : fail();
  };
  const rows = Array.isArray(value.issues) ? value.issues : fail();
  const issues = rows.map((item): CheckIssue => {
    const row = (typeof item === "object" && item !== null ? item : fail()) as Record<string, unknown>;
    const type = typeof row.type === "string" && utf8Size(row.type) <= 128 ? row.type : fail();
    const message = typeof row.message === "string" && utf8Size(row.message) <= 16_384 ? row.message : fail();
    const index = Number.isInteger(row.index) ? (row.index as number) : fail();
    const issue: CheckIssue = { index, type, message };
    const group = optional(row, "group");
    const cardName = optional(row, "cardName");
    if (group !== undefined) issue.group = group;
    if (cardName !== undefined) issue.cardName = cardName;
    return issue;
  });
  const sha = text("requestSHA256", 64);
  const count = Number.isInteger(value.issueCount) ? (value.issueCount as number) : fail();
  const valid = typeof value.valid === "boolean" ? value.valid : fail();
  if (!/^[0-9a-f]{64}$/.test(sha) || issues.length > maximumIssues || count < issues.length || count > 2000 || (valid && count !== 0) || (!valid && count === 0)) fail();
  const checkedAt = Number.isInteger(value.checkedAt) ? (value.checkedAt as number) : fail();
  const summary = typeof value.summary === "string" && utf8Size(value.summary) <= 16_384 ? value.summary : fail();
  return { key: { deckID: text("deckID", 512), requestSHA256: sha, upstream: text("upstream", 256), catalogue: text("catalogue", 256),
    appBuild: text("appBuild", 64) }, checkedAt, valid, issues, issueCount: count, summary };
}

const encodeResult = (result: CheckResult) => ({
  appBuild: result.key.appBuild, catalogue: result.key.catalogue, checkedAt: result.checkedAt, deckID: result.key.deckID,
  issueCount: result.issueCount, issues: result.issues.map((issue) => ({ cardName: issue.cardName ?? null, group: issue.group ?? null,
    index: issue.index, message: issue.message, type: issue.type })),
  requestSHA256: result.key.requestSHA256, summary: result.summary, upstream: result.key.upstream, valid: result.valid,
});

/**
 * Stored check results in this browser. Lookups match the whole key, so an edit or a new engine, catalogue or app build
 * reads as Not checked. At most 200 results are kept, newest first, five per deck, in at most 2 MiB (the oldest go first),
 * and recording a result drops results from other installs. A missing or unreadable store is only a cache miss.
 */
export class ReceiptStore {
  static readonly maximumResults = 200;
  static readonly maximumPerDeck = 5;
  static readonly maximumBytes = 2 * 1024 * 1024;
  static readonly key = "deckStudio.checks.v1";

  private loaded = false;
  private results: CheckResult[] = [];

  constructor(private readonly store: KeyValueStore, private readonly storageKey = ReceiptStore.key) {}

  result(key: CheckKey): CheckResult | undefined { this.load(); return this.results.find((value) => CheckKey.equal(value.key, key)); }

  status(key: CheckKey | undefined): PlayStatus {
    const result = key ? this.result(key) : undefined;
    return result === undefined ? "notChecked" : result.valid ? "ready" : "needsFixes";
  }

  all(): readonly CheckResult[] { this.load(); return this.results; }

  /** Keeps `value` as the newest result for its key. False when the browser did not keep it. */
  record(value: CheckResult): boolean {
    this.load();
    const newest = (a: CheckResult, b: CheckResult) => b.checkedAt - a.checkedAt;
    const others = this.results.filter((item) => !CheckKey.equal(item.key, value.key) && CheckKey.sameInstall(item.key, value.key)).sort(newest);
    const sameDeck = others.filter((item) => item.key.deckID === value.key.deckID).slice(0, ReceiptStore.maximumPerDeck - 1);
    let next = [value, ...others.filter((item) => item.key.deckID !== value.key.deckID), ...sameDeck].sort(newest).slice(0, ReceiptStore.maximumResults);
    while (utf8Size(ReceiptStore.encoded(next)) > ReceiptStore.maximumBytes && next.length > 1) next = next.slice(0, -1);
    this.results = next;
    return this.write(next);
  }

  /** Forgets a deleted deck's results. */
  remove(deckID: string): void {
    this.load();
    if (!this.results.some((item) => item.key.deckID === deckID)) return;
    this.results = this.results.filter((item) => item.key.deckID !== deckID);
    this.write(this.results);
  }

  private load(): void {
    if (this.loaded) return;
    this.loaded = true;
    try {
      const text = this.store.get(this.storageKey);
      if (text === null || text === undefined) return;
      if (utf8Size(text) > ReceiptStore.maximumBytes) return;
      const payload = JSON.parse(text) as Record<string, unknown>;
      if (typeof payload !== "object" || payload === null || payload.schema !== 1 || !Array.isArray(payload.results)
        || payload.results.length > ReceiptStore.maximumResults) return;
      const decoded = payload.results.map(decodeResult);
      const keys = new Set(decoded.map((item) => JSON.stringify(item.key)));
      if (keys.size === decoded.length) this.results = decoded;
    } catch { this.results = []; }
  }

  private static encoded(values: CheckResult[]): string { return JSON.stringify({ schema: 1, results: values.map(encodeResult) }); }

  private write(values: CheckResult[]): boolean {
    try { this.store.set(this.storageKey, ReceiptStore.encoded(values)); return true; } catch { return false; }
  }
}

const nameKey = (name: string) => name.trim().toLowerCase();

/** The rules Play shares on every screen (DeckStudioPlayRules). */
export const PlayRules = {
  /** A library record's playing-deck ID: precons keep theirs, local decks are "local:<id>". */
  selectionID: (recordID: string) => (recordID.startsWith("precon:") ? recordID : `local:${recordID}`),

  /** Rows the offline resolver cannot play: unknown names and sections, and cards split between playing sections. */
  unplayableCards(deck: StudioDeck, canonical: (name: string) => string | undefined): string[] {
    const playing = new Set(["main", "deck", "commander", "commanders", "companion", "companions"]);
    const excluded = new Set(["sideboard", "maybeboard", "considering"]);
    const rows = [...(deck.commander ? [{ ...deck.commander, section: "commanders" }] : []), ...deck.entries];
    const cards = new Set<string>();
    const sections = new Map<string, Set<string>>();
    for (const row of rows) {
      const section = row.section.trim().toLowerCase();
      if (excluded.has(section)) continue;
      const name = canonical(row.cardName);
      if (!playing.has(section) || name === undefined) { cards.add(row.cardName); continue; }
      if (!sections.has(name)) sections.set(name, new Set());
      sections.get(name)!.add(DraftPresentation.normalizedSection(section));
    }
    for (const row of rows) if ((sections.get(canonical(row.cardName) ?? "")?.size ?? 0) > 1) cards.add(row.cardName);
    return [...cards];
  },

  /**
   * Whether Start's answer is stored for the player's deck. A pass always is. A rejection is not when this exact deck
   * already passed, or when an issue names a card outside the player's deck (it came from another seat's deck).
   */
  storesStartResult(valid: boolean, issueCards: readonly string[], deckCards: Iterable<string>, alreadyPassed: boolean): boolean {
    if (valid) return true;
    if (alreadyPassed) return false;
    const names = new Set([...deckCards].map(nameKey));
    return issueCards.every((card) => names.has(nameKey(card)));
  },

  /** Fix deck: the rows XMage named, by canonical name and ignoring case. Sideboard and maybeboard rows are out of play. */
  fixRows(rows: readonly DraftRow[], cards: readonly string[], canonical: (name: string) => string | undefined): Set<string> {
    const name = (value: string) => nameKey(canonical(value) ?? value);
    const wanted = new Set(cards.map(name));
    return new Set(rows.filter((row) => !["sideboard", "maybeboard"].includes(DraftPresentation.section(row)) && wanted.has(name(row.cardName)))
      .map((row) => row.id));
  },

  /** The cards XMage named, in first-seen order, for Fix deck's filter. */
  issueCards: (result: Pick<CheckResult, "issues">) =>
    [...new Set(result.issues.map((issue) => issue.cardName?.trim() ?? "").filter((name) => name.length > 0))],

  /** A group's title: XMage's group, else its issue type in words, else "Commander rules". */
  groupTitle(issue: CheckIssue): string {
    const group = issue.group?.trim();
    if (group) return group;
    const words = issue.type.replace(/_/g, " ").toLowerCase();
    return words.length === 0 ? "Commander rules" : words.charAt(0).toUpperCase() + words.slice(1);
  },

  /** Issues grouped as XMage grouped them, in the order it reported them. */
  groupedIssues(issues: readonly CheckIssue[]): [string, CheckIssue[]][] {
    const groups = new Map<string, CheckIssue[]>();
    for (const issue of issues) {
      const title = PlayRules.groupTitle(issue);
      if (!groups.has(title)) groups.set(title, []);
      groups.get(title)!.push(issue);
    }
    return [...groups];
  },
};

/**
 * What the Cards list is narrowed to (DeckStudioListFilter): one quick-check issue, or the cards XMage named (Fix deck).
 * Both read "Showing only: …" with Show all.
 */
export type ListFilter = { kind: "quickCheck"; issue: PreflightIssue } | { kind: "needsFixes"; cards: string[] };

export const ListFilter = {
  label: (filter: ListFilter) => (filter.kind === "quickCheck" ? PreflightIssue.badge(filter.issue) : PlayText.needsFixes),
  title: (filter: ListFilter) => PlayWords.showingOnly(ListFilter.label(filter)),
  rows: (filter: ListFilter, preflight: Preflight, draft: DeckDraft, canonical: (name: string) => string | undefined): ReadonlySet<string> =>
    (filter.kind === "quickCheck" ? preflight.rows(filter.issue) : PlayRules.fixRows(draft.rows, filter.cards, canonical)),
};
