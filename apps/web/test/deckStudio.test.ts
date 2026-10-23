/** deck-studio-cases.json, every group (iOS ParityGoldenTests.swift, Android ParityGoldenTest.deckStudioCasesOnBothPlatforms), plus the web catalogue and import. */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import { RoleGroups, SampleHand, seededRandom, manaCurve, cardGroups, RoleClassifier, type DeckRole } from "../src/core/deckStudio/analysis";
import { Catalogue } from "../src/core/deckStudio/catalogue";
import {
  CheckKey, destinations, ListFilter, PlayRules, PlayStatus, PlayText, PlayWords, ReceiptStore, sha256, type CheckIssue, type CheckResult,
} from "../src/core/deckStudio/checks";
import {
  changeDraft, draftDeck, draftFromDeckList, draftHistory, draftToDeckList, EditorOperations, newRow, QuickAdd, type DeckDraft, type StudioDeck,
} from "../src/core/deckStudio/draft";
import { archidektDeckListEndpoint, choosingCommander, decodeArchidektDeckPage, decodeDeckLink, DeckLinkError, deckLinkSource, previewDeck } from "../src/core/deckStudio/linkImport";
import { Preflight, PreflightIssue, type PreflightCard } from "../src/core/deckStudio/preflight";
import { commanderSearch, nameSuggestions, SearchSyntax, searchCatalogue } from "../src/core/deckStudio/search";
import { exportText, importJSON, exportJSON, importText, TextDiff, TextImportError } from "../src/core/deckStudio/textIO";
import type { KeyValueStore } from "../src/core/playerRecord";

const root = join(__dirname, "..", "..", "..");
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const cases: any = JSON.parse(readFileSync(join(root, "apps/android/core/src/test/resources/parity/deck-studio-cases.json"), "utf8"));

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Raw = any;
const row = (raw: Raw) => newRow({ cardName: raw.name, quantity: raw.quantity ?? 1, section: raw.section ?? "deck", isPrimaryCommander: raw.primary ?? false });
const draftOf = (rows: Raw[]): DeckDraft => ({ name: "Case", rows: rows.map(row) });
const status = (raw: string) => { if (!["ready", "needsFixes", "notChecked"].includes(raw)) throw new Error(`Unknown status ${raw}`); return raw as PlayStatus; };
const memory = (): KeyValueStore & { values: Map<string, string> } => {
  const values = new Map<string, string>();
  return { values, get: (key) => values.get(key), set: (key, value) => { values.set(key, value); } };
};

describe("Deck Studio parity cases", () => {
  it("strings and destinations", () => {
    const known: Record<string, string> = { ...PlayText, quickCheckCaption: Preflight.caption };
    expect(Object.keys(cases.strings).sort()).toEqual(Object.keys(known).sort());
    for (const [id, text] of Object.entries(cases.strings)) expect(known[id], id).toBe(text);
    expect(destinations.map((pair) => [...pair])).toEqual(cases.destinations);
  });

  it("formatted strings", () => {
    expect(cases.formatted.length).toBeGreaterThan(0);
    for (const item of cases.formatted) {
      const a = item.args;
      const actual = ({
        checking: () => PlayWords.checking(a[0]),
        nowPlaying: () => PlayWords.nowPlaying(a[0]),
        nowPlayingStrip: () => PlayWords.nowPlayingStrip(a[0], status(a[1])),
        issues: () => PlayWords.issues(a[0]),
        blocked: () => PlayWords.issuesBlockPlay(a[0]),
        notShown: () => PlayWords.notShown(a[0]),
        excluded: () => PlayWords.excluded(a[0]),
        deletePlaying: () => PlayWords.deletePlaying(a[0]),
        showingOnly: () => PlayWords.showingOnly(a[0]),
        listFilter: () => ListFilter.title(a[0] === "needsFixes" ? { kind: "needsFixes", cards: [] } : { kind: "quickCheck", issue: a[0] }),
        selected: () => PlayWords.selected(a[0]),
        added: () => PlayWords.added(a[0], a[1], a[2]),
        noCardNamed: () => PlayWords.noCardNamed(a[0]),
        handCounts: () => PlayWords.handCounts(a[0], a[1]),
        status: () => PlayStatus.title(status(a[0])),
        setupStatus: () => PlayStatus.setup(status(a[0])),
      } as Record<string, () => string>)[item.id];
      expect(actual, `unknown formatted id ${item.id}`).toBeDefined();
      expect(actual(), `${item.id} ${JSON.stringify(a)}`).toBe(item.text);
    }
  });

  it("Quick Add", () => {
    const names = new Set<string>(cases.quickAdd.cardNames);
    for (const item of cases.quickAdd.cases) {
      const parsed = QuickAdd.parse(item.input, (name) => names.has(name));
      if (item.result === null) { expect(parsed, item.input).toBeNull(); continue; }
      expect(parsed, item.input).toEqual({ quantity: item.result.quantity, name: item.result.name, ignored: item.result.ignored });
      expect(QuickAdd.note(parsed!), item.input).toBe(item.result.note);
    }
  });

  it("quick check", () => {
    const p = cases.preflight;
    expect(Preflight.targetCount).toBe(p.targetCount);
    expect(Preflight.caption).toBe(p.caption);
    expect(Object.keys(p.issues).sort()).toEqual(["duplicate", "missingCommander", "offIdentity", "unresolved"]);
    for (const [issue, value] of Object.entries<Raw>(p.issues)) {
      expect(PreflightIssue.title(issue as PreflightIssue)).toBe(value.title);
      expect(PreflightIssue.badge(issue as PreflightIssue)).toBe(value.badge);
    }
    const cards = new Map<string, PreflightCard>(p.cards.map((raw: Raw) => [raw.name, { name: raw.name, typeLine: raw.typeLine ?? undefined,
      oracleText: raw.oracleText ?? undefined, colorIdentity: raw.colorIdentity ?? undefined }]));
    const aliases: Record<string, string> = p.aliases ?? {};
    expect(p.cases.length).toBeGreaterThan(0);
    for (const item of p.cases) {
      const draft = draftOf(item.rows);
      const catalogue = item.catalogue ?? true;
      const unresolvable: string[] | null = item.unresolvable;
      const check = new Preflight(draft, (name) => (catalogue ? cards.get(aliases[name] ?? name) : undefined),
        unresolvable ? (name) => !unresolvable.includes(name) : undefined);
      const e = item.expect;
      expect(check.count, item.name).toBe(e.count);
      expect(check.missingCommander, item.name).toBe(e.missingCommander);
      expect(check.commanderIdentity ? [...check.commanderIdentity].sort() : null, item.name).toEqual(e.commanderIdentity);
      for (const issue of ["offIdentity", "duplicate", "unresolved"] as const) {
        expect([...check.rows(issue)].sort(), `${item.name} · ${issue}`).toEqual(e.rows[issue].map((index: number) => draft.rows[index].id).sort());
      }
      expect(check.issueCount, item.name).toBe(e.issueCount);
      expect(check.summary, item.name).toBe(e.summary);
      expect(check.activeIssues.map((issue) => check.chipTitle(issue)), item.name).toEqual(e.chips);
    }
  });

  it("search syntax", () => {
    expect(cases.search).toHaveLength(27);
    for (const item of cases.search) {
      const syntax = SearchSyntax.parse(item.query);
      expect(syntax.text, item.query).toBe(item.text);
      expect(syntax.types, item.query).toEqual(item.types);
      expect(syntax.oracle, item.query).toEqual(item.oracle);
      expect(syntax.minimumManaValue ?? null, item.query).toBe(item.minimumManaValue);
      expect(syntax.maximumManaValue ?? null, item.query).toBe(item.maximumManaValue);
      expect(syntax.identity ? [...syntax.identity].sort() : null, item.query).toEqual(item.identity);
      expect(SearchSyntax.hasFilters(syntax), item.query).toBe(item.hasFilters);
    }
  });

  it("sample hand", () => {
    expect(SampleHand.handSize).toBe(cases.sampleHand.handSize);
    const random = seededRandom(7);
    for (const item of cases.sampleHand.cases) {
      const names = SampleHand.libraryNames(draftOf(item.rows));
      expect(names.length, item.name).toBe(item.library);
      let hand = SampleHand.of(names);
      item.steps.forEach((step: Raw, index: number) => {
        const at = `${item.name} · step ${index + 1} ${step.do}`;
        hand = ({ deal: () => hand.dealt(random), mulligan: () => hand.mulliganed(random), draw: () => hand.drawn(),
          bottom: () => (hand.hand[0] ? hand.puttingOnBottom(hand.hand[0].id) : hand) } as Record<string, () => SampleHand>)[step.do]();
        expect([hand.hand.length, hand.library.length, hand.mulligans, hand.toBottom, hand.turn, hand.canMulligan, hand.canDraw, hand.status], at)
          .toEqual([step.hand, step.library, step.mulligans, step.toBottom, step.turn, step.canMulligan, step.canDraw, step.status]);
      });
    }
  });

  it("role groups", () => {
    const r = cases.roleGroups;
    expect(RoleGroups.order).toEqual(r.order);
    const cards = new Map<string, Raw>(r.cards.map((raw: Raw) => [raw.name, { oracleText: undefined, types: raw.types, roles: raw.roles }]));
    const rows = r.rows.map((name: string) => newRow({ cardName: name }));
    for (const item of r.cases) {
      const overrides = new Map<string, Set<DeckRole>>(Object.entries<string[]>(item.overrides).map(([name, roles]) => [name, new Set(roles as DeckRole[])]));
      const membership = RoleGroups.membership(rows, (name) => cards.get(name), overrides);
      expect(rows.map((value: Raw) => membership.get(value.id) ?? []), item.name).toEqual(item.groups);
      expect(new Set([...membership.values()].flat()), item.name).toEqual(new Set(Object.keys(item.counts)));
      for (const [title, count] of Object.entries(item.counts)) {
        expect(RoleGroups.uniqueCards(rows.filter((value: Raw) => membership.get(value.id)?.includes(title))), `${item.name} · ${title}`).toBe(count);
      }
    }
  });

  it("check results", () => {
    const c = cases.checkResults;
    expect({ maximumResults: ReceiptStore.maximumResults, maximumPerDeck: ReceiptStore.maximumPerDeck, maximumBytes: ReceiptStore.maximumBytes,
      maximumIssues: 100 }).toEqual(c.limits);
    for (const item of c.sha256) expect(sha256(item.request), item.request).toBe(item.sha256);
    const requests = new Map<string, string>();
    const key = (raw: Raw) => { const value = CheckKey.of(raw.deck, raw.request, raw.upstream, raw.catalogue, raw.build); requests.set(value.requestSHA256, raw.request); return value; };
    const label = (value: CheckKey) => [value.deckID, requests.get(value.requestSHA256) ?? value.requestSHA256, value.upstream, value.catalogue, value.appBuild].join("|");
    const stored = (value: CheckKey, at: number, valid: boolean, summary = "Checked"): CheckResult => ({ key: value, checkedAt: at, valid,
      issues: valid ? [] : [{ index: 0, type: "OTHER", group: "Sol Ring", message: "Too many copies", cardName: "Sol Ring" }], issueCount: valid ? 0 : 1, summary });
    for (const scenario of c.store) {
      const backing = memory();
      const store = new ReceiptStore(backing);
      for (const record of scenario.records) expect(store.record(stored(key(record), record.at, record.valid)), scenario.name).toBe(true);
      expect(store.all().map((value) => label(value.key)), scenario.name).toEqual(scenario.expect);
      expect(new ReceiptStore(backing).all().map((value) => label(value.key)), `${scenario.name} · reopened`).toEqual(scenario.expect);
      for (const lookup of scenario.lookups ?? []) expect(store.status(key(lookup)), `${scenario.name} · ${JSON.stringify(lookup)}`).toBe(status(lookup.status));
    }
    for (const scenario of c.generated) {
      const backing = memory();
      const store = new ReceiptStore(backing);
      const summary = "x".repeat(scenario.summaryLength ?? 7);
      for (let deck = 0; deck < scenario.decks; deck += 1) store.record(stored(CheckKey.of(`local:${deck}`, "r1", "u1", "c1", "10"), 1000 + deck, true, summary));
      const decks = store.all().map((value) => value.key.deckID);
      if (scenario.count !== undefined) expect(decks.length, scenario.name).toBe(scenario.count);
      if (scenario.fewerThan !== undefined) expect(decks.length > 0 && decks.length < scenario.fewerThan, scenario.name).toBe(true);
      expect(decks[0], scenario.name).toBe(scenario.first);
      if (scenario.last !== undefined) expect(decks[decks.length - 1], scenario.name).toBe(scenario.last);
      for (const missing of scenario.missing ?? []) expect(decks.includes(missing), `${scenario.name} · ${missing}`).toBe(false);
      expect(new TextEncoder().encode(backing.values.get(ReceiptStore.key)!).length).toBeLessThanOrEqual(ReceiptStore.maximumBytes);
      expect(new ReceiptStore(backing).all().map((value) => value.key.deckID), `${scenario.name} · reopened`).toEqual(decks);
    }
    for (const text of c.corrupt) {
      const backing = memory();
      backing.set(ReceiptStore.key, text);
      expect(new ReceiptStore(backing).all(), `A corrupt store is a cache miss: ${text}`).toEqual([]);
    }
    for (const item of c.startResult) {
      expect(PlayRules.storesStartResult(item.valid, item.issueCards, item.deckCards, item.alreadyPassed), JSON.stringify(item)).toBe(item.stores);
    }
    for (const item of c.fixRows) {
      const rows = item.rows.map(row);
      const canonical: Record<string, string> = item.canonical ?? {};
      expect([...PlayRules.fixRows(rows, item.cards, (name) => canonical[name])].sort(), item.name)
        .toEqual(item.rowsShown.map((index: number) => rows[index].id).sort());
    }
    const entry = (raw: Raw) => ({ cardName: raw.name, quantity: raw.quantity ?? 1, section: raw.section ?? "deck" });
    for (const item of c.unplayable) {
      const known = new Set<string>(item.known);
      const deck: StudioDeck = { name: "Case", entries: item.entries.map(entry), ...(item.commander ? { commander: entry(item.commander) } : {}) };
      expect(PlayRules.unplayableCards(deck, (name) => (known.has(name) ? name : undefined)), item.name).toEqual(item.cards);
    }
    for (const item of c.groups) {
      const issues: CheckIssue[] = item.issues.map((raw: Raw, index: number) => ({ index, type: raw.type, message: raw.message,
        ...(raw.group !== null ? { group: raw.group } : {}), ...(raw.cardName !== null ? { cardName: raw.cardName } : {}) }));
      expect(PlayRules.groupedIssues(issues).map(([title, rows]) => [title, rows.length])).toEqual(item.groups);
      expect(PlayRules.issueCards({ issues })).toEqual(item.cardNames);
    }
  });
});

const fixture = Catalogue.fromJSON({
  schema: 1, catalogueHash: "c".repeat(64),
  aliases: { "Fire // Ice": "Fire", "Delver of Secrets // Insectile Aberration": "Delver of Secrets" },
  cards: [
    ["Sol Ring", "Artifact", "ARTIFACT", "{T}: Add {C}{C}.", 1, "{1}", "", "", "C21 CMM", "ramp"],
    ["Kardur, Doomscourge", "Legendary Creature — Demon Berserker", "CREATURE", "When Kardur enters, until your next turn, creatures your opponents control attack each combat if able.",
      4, "{2}{B}{R}", "BR", "BR", "KHM KHC"],
    ["Forest", "Basic Land — Forest", "LAND", "({T}: Add {G}.)", 0, "", "", "G", "M21"],
    ["Lightning Bolt", "Instant", "INSTANT", "Lightning Bolt deals 3 damage to any target.", 1, "{R}", "R", "R", "M10"],
    ["Fire", "Instant", "INSTANT", "Fire deals 2 damage divided as you choose among one or two targets.<br>Ice: Tap target permanent.", 2, "{1}{R}", "R", "UR", "MH2"],
    ["Delver of Secrets", "Creature — Human Wizard", "CREATURE", "At the beginning of your upkeep, look at the top card of your library.", 1, "{U}", "U", "U", "ISD"],
    ["Éowyn, Shieldmaiden", "Legendary Creature — Human Knight", "CREATURE", "First strike", 5, "{2}{R}{W}{W}", "RW", "RW", "LTR"],
    ["Mystery Thing", "Phenomenon", "PHENOMENON TOTALLY_NEW", null, null, null, null, null, ""],
    ["No Metadata"],
  ],
});

describe("Deck Studio catalogue and search", () => {
  it("decodes the compact catalogue", () => {
    expect(fixture.all.map((card) => card.name)[0]).toBe("Delver of Secrets");
    expect(fixture.card("Sol Ring")).toMatchObject({ types: ["ARTIFACT"], colorIdentity: [], roles: ["ramp"], setCodes: ["C21", "CMM"], manaValue: 1 });
    expect(fixture.card("Fire // Ice")?.name).toBe("Fire");
    expect(fixture.card("Ice")?.name).toBe("Fire");
    expect(fixture.card("Insectile Aberration")?.name).toBe("Delver of Secrets");
    expect(fixture.card("Fire")?.oracleText).toBe("Fire deals 2 damage divided as you choose among one or two targets.\nIce: Tap target permanent.");
    expect(fixture.card("Mystery Thing")).toMatchObject({ types: undefined, typeLine: undefined });
    expect(fixture.card("No Metadata")).toMatchObject({ setCodes: [], roles: [], colorIdentity: undefined });
    expect(fixture.card("Nope")).toBeUndefined();
    expect(() => Catalogue.fromJSON({ schema: 2, aliases: {}, cards: [] })).toThrow();
  });

  it("searches with the syntax and the sheet's filters", () => {
    expect(searchCatalogue(fixture, { query: "fire" }).map((card) => card.name)).toEqual(["Fire"]);
    expect(searchCatalogue(fixture, { query: "t:creature" }).map((card) => card.name)).toEqual(["Delver of Secrets", "Kardur, Doomscourge", "Éowyn, Shieldmaiden"]);
    expect(searchCatalogue(fixture, { query: "eowyn" }).map((card) => card.name)).toEqual([]);
    expect(searchCatalogue(fixture, { query: "t:creature eowyn" }).map((card) => card.name)).toEqual(["Éowyn, Shieldmaiden"]);
    expect(searchCatalogue(fixture, { query: "", allowedIdentity: ["B", "R"] }).map((card) => card.name))
      .toEqual(["Kardur, Doomscourge", "Lightning Bolt", "Sol Ring"]);
    expect(searchCatalogue(fixture, { query: "mv<=1", allowedIdentity: ["G"] }).map((card) => card.name)).toEqual(["Forest", "Sol Ring"]);
    expect(searchCatalogue(fixture, { query: "", setCode: "cmm" }).map((card) => card.name)).toEqual(["Sol Ring"]);
    expect(searchCatalogue(fixture, { query: "", minimumManaValue: 3, maximumManaValue: 1 })).toEqual([]);
    expect(nameSuggestions(fixture, "sol").map((card) => card.name)).toEqual(["Sol Ring"]);
    expect(commanderSearch(fixture, "").map((card) => card.name)).toEqual(["Kardur, Doomscourge", "Éowyn, Shieldmaiden"]);
  });
});

describe("Deck Studio drafts and text", () => {
  it("edits with undo and converts to a DeckList", () => {
    let history = draftHistory({ name: "New Commander Deck", rows: [] });
    history = changeDraft(history, (draft) => EditorOperations.addCopies(draft, "Sol Ring", "deck", 2));
    history = changeDraft(history, (draft) => EditorOperations.addOne(draft, "Kardur, Doomscourge"));
    history = changeDraft(history, (draft) => EditorOperations.startWithCommander(draft, "Kardur, Doomscourge"));
    expect(history.value.name).toBe("Kardur, Doomscourge");
    expect(history.value.rows.map((r) => [r.cardName, r.quantity, r.isPrimaryCommander])).toEqual([["Kardur, Doomscourge", 1, true], ["Sol Ring", 2, false]]);
    expect(() => changeDraft(history, (draft) => EditorOperations.addCopies(draft, "Forest", "deck", 1999))).toThrow();
    history = changeDraft(history, (draft) => EditorOperations.setBasicLands(draft, { Plains: 0, Island: 0, Swamp: 0, Mountain: 3, Forest: 0, Wastes: 0 }));
    expect(history.canUndo && history.isDirty).toBe(true);
    const list = draftToDeckList(history.value, "local:x");
    expect(list.entries).toEqual([{ name: "Kardur, Doomscourge", quantity: 1, section: "commanders" }, { name: "Sol Ring", quantity: 2, section: "deck" },
      { name: "Mountain", quantity: 3, section: "deck" }]);
    expect(draftFromDeckList(list).rows[0].isPrimaryCommander).toBe(true);
    const undone = history.undone().undone().undone().undone();
    expect(undone.value.rows).toEqual([]);
    expect(undone.redone().value.rows.map((r) => r.cardName)).toEqual(["Sol Ring"]);
    expect(manaCurve(history.value, fixture)).toEqual([0, 2, 0, 0, 0, 0, 0, 0]); // the commander and unknown Mountain stay out
    expect(cardGroups(history.value.rows, "Type", fixture).map((g) => [g.title, g.count])).toEqual([["Commanders", 1], ["Artifact", 2], ["Unclassified", 3]]);
  });

  it("imports and exports text as the phones do", () => {
    const result = importText("1x Emmara, Soul of the Accord (grn) *F* [Commander{top}] ^Owned,#000000^\n1x Sol Ring (clb) [Ramp]\n2x Swamp (ltr) 267 [Land]\n"
      + "1x Unknown Future Card [Maybeboard]\n1x Forest [Sideboard]", "Archidekt");
    expect(result.deck.commander?.cardName).toBe("Emmara, Soul of the Accord");
    expect(result.deck.entries.map((e) => [e.cardName, e.section, e.setCode ?? null])).toEqual([["Sol Ring", "deck", null], ["Swamp", "deck", "ltr"],
      ["Unknown Future Card", "maybeboard", null], ["Forest", "sideboard", null]]);
    expect(result.annotations).toContainEqual({ line: 1, text: "^Owned,#000000^" });
    const grouped = importText("// Unrecognized custom section\n1 Fire // Ice\n1 B.F.M. (Big Furry Monster)", "Punctuation");
    expect(grouped.deck.entries.map((e) => e.cardName)).toEqual(["Fire // Ice", "B.F.M. (Big Furry Monster)"]);
    expect(grouped.annotations).toContainEqual({ line: 1, text: "Grouping retained in deck: Unrecognized custom section" });
    for (const invalid of ["0 Forest", "1.5 Forest", "999999999999999999999 Forest", "1", "Some unknown heading", "1 Sol Ring [Ramp] [Draw]", "1 Sol Ring [Ramp{top}]"]) {
      expect(() => importText(`Deck\r\n1 Forest\r\n\r\n${invalid}`, "Invalid"), invalid).toThrow(TextImportError);
      try { importText(`Deck\r\n1 Forest\r\n\r\n${invalid}`, "Invalid"); } catch (error) { expect((error as TextImportError).line).toBe(4); }
    }
    const deck = draftDeck({ name: "Mine", rows: [newRow({ cardName: "Kardur, Doomscourge", section: "commanders", isPrimaryCommander: true }),
      newRow({ cardName: "Sol Ring", printing: { setCode: "cmm", number: "400" } }), newRow({ cardName: "Island", section: "considering" })] });
    expect(exportText(deck)).toBe("Commander\n1 Kardur, Doomscourge\n\nDeck\n1 Sol Ring (CMM) 400\n\nMaybeboard\n1 Island\n");
    expect(importJSON(exportJSON(deck))).toEqual(deck);
    expect(exportJSON({ name: "A/B", entries: [{ cardName: "Fire // Ice", quantity: 1, section: "deck" }] }))
      .toBe('{\n  "entries" : [\n    {\n      "cardName" : "Fire \\/\\/ Ice",\n      "quantity" : 1,\n      "section" : "deck"\n    }\n  ],\n  "name" : "A\\/B"\n}');
    const before: DeckDraft = { name: "Mine", rows: [newRow({ cardName: "Sol Ring" }), newRow({ cardName: "Kardur, Doomscourge", section: "commanders", isPrimaryCommander: true })] };
    const edited = TextDiff.draft("Commander\n1 Kardur, Doomscourge\nDeck\n2 Sol Ring\n1 Island", before);
    expect(edited.draft.rows.find((r) => r.cardName === "Sol Ring")?.id).toBe(before.rows[0].id);
    const diff = TextDiff.between(before, edited.draft);
    expect(diff.added.map(TextDiff.label)).toEqual(["+1 Island · Deck", "+1 Sol Ring · Deck"]);
    expect(RoleClassifier.classify("{T}: Add {G}.", ["ARTIFACT"]).map((e) => e.role)).toEqual(["ramp"]);
    expect(RoleClassifier.classify("Whenever a creature dies, draw a card.", ["ENCHANTMENT"])).toEqual([]);
  });
});

describe("Deck Studio links", () => {
  const known = new Set(["Sol Ring", "Forest", "Kardur, Doomscourge", "Fire"]);
  const canonicalName = (name: string) => (known.has(name) ? name : name === "Fire // Ice" ? "Fire" : undefined);

  it("maps public deck links to the provider APIs", () => {
    expect(deckLinkSource("https://archidekt.com/decks/123456/my-deck").provider).toBe("archidekt");
    expect(deckLinkSource("https://www.moxfield.com/decks/abcdefghijklmnopqrstuv").endpoint).toBe("https://api2.moxfield.com/v3/decks/all/abcdefghijklmnopqrstuv");
    for (const shared of ["https://archidekt.com/decks/14167342?utm_source=share&utm_medium=ios", "archidekt.com/decks/14167342"]) {
      expect(deckLinkSource(shared).endpoint).toBe("https://archidekt.com/api/decks/14167342/");
    }
    for (const bad of ["http://archidekt.com/decks/1", "https://user@archidekt.com/decks/1", "https://example.com/decks/1", "https://moxfield.com/decks/short",
      "https://archidekt.com/decks/%31", "https://archidekt.com:444/decks/1"]) expect(() => deckLinkSource(bad), bad).toThrow(DeckLinkError);
    expect(archidektDeckListEndpoint(" Caleb_F.1 ", 2)).toBe("https://archidekt.com/api/decks/v3/?ownerUsername=Caleb_F.1&pageSize=50&page=2");
    for (const bad of ["", "a b", "x/../y", "name?x=1", "a".repeat(65)]) expect(() => archidektDeckListEndpoint(bad, 1)).toThrow();
    const page = decodeArchidektDeckPage('{"count":3,"next":"https://archidekt.com/api/decks/v3/?page=2","results":[{"id":1,"name":"Edgar","size":100,'
      + '"updatedAt":"2026-10-01T12:00:00Z","private":false,"unlisted":false},{"id":2,"name":"Secret","private":true},{"id":3,"name":"Hidden","unlisted":true}]}');
    expect(page).toEqual({ decks: [{ id: 1, name: "Edgar", size: 100, updatedAt: "2026-10-01T12:00:00Z" }], hasMore: true });
    expect(() => decodeArchidektDeckPage("<html>")).toThrow();
  });

  it("decodes Moxfield and Archidekt answers", () => {
    const source = deckLinkSource("https://moxfield.com/decks/abcdefghijklmnopqrstuv");
    const json = '{"publicId":"abcdefghijklmnopqrstuv","name":"Mox","visibility":"public","boards":{'
      + '"commanders":{"cards":{"a":{"quantity":1,"card":{"name":"Kardur, Doomscourge"}}}},'
      + '"mainboard":{"cards":{"b":{"quantity":1,"card":{"name":"Sol Ring"}},"c":{"quantity":30,"card":{"name":"Forest"}}}},'
      + '"sideboard":{"cards":{"d":{"quantity":1,"card":{"name":"Forest"}}}}}}';
    expect(() => decodeDeckLink(source, json, { canonicalName })).toThrow(DeckLinkError);
    const deck = decodeDeckLink(source, json, { canonicalName, excludeSideboards: true });
    expect(deck.commander?.cardName).toBe("Kardur, Doomscourge");
    expect(deck.entries.reduce((sum, e) => sum + e.quantity, 0)).toBe(31);
    expect(() => decodeDeckLink(source, json.replace("Sol Ring", "Brand New Card"), { canonicalName, excludeSideboards: true })).toThrow(/No compiled printing/);
    const review = decodeDeckLink(source, json.replace("Sol Ring", "Brand New Card"), { canonicalName, excludeSideboards: true, reviewOnly: true });
    expect(previewDeck(review, canonicalName).unresolvedNames).toEqual(["Brand New Card"]);
    expect(() => decodeDeckLink(source, json.replace('"public"', '"private"'), { canonicalName })).toThrow(/private/);
    expect(() => decodeDeckLink(source, "{}", { canonicalName })).toThrow(/Malformed/);

    const archidekt = deckLinkSource("https://archidekt.com/decks/77");
    const answer = JSON.stringify({ id: 77, name: "Arch", private: false, unlisted: false,
      categories: [{ name: "Commander", includedInDeck: true }, { name: "Ramp", includedInDeck: true }, { name: "Maybeboard", includedInDeck: false }],
      cards: [{ quantity: 1, categories: ["Commander"], card: { oracleCard: { name: "Kardur, Doomscourge" } } },
        { quantity: 1, categories: ["Ramp"], card: { oracleCard: { name: "Fire // Ice" } } },
        { quantity: 2, categories: ["Maybeboard"], card: { oracleCard: { name: "Forest" } } }] });
    expect(() => decodeDeckLink(archidekt, answer, { canonicalName })).toThrow(/sideboard or excluded/);
    expect(decodeDeckLink(archidekt, answer, { canonicalName, excludeSideboards: true })).toEqual({ name: "Arch",
      commander: { cardName: "Kardur, Doomscourge", quantity: 1, section: "commanders" }, entries: [{ cardName: "Fire", quantity: 1, section: "main" }] });
  });

  it("puts the chosen commander first", () => {
    const marked: StudioDeck = { name: "Marked", commander: { cardName: "Forest", quantity: 1, section: "commanders" },
      entries: [{ cardName: "Kardur, Doomscourge", quantity: 1, section: "deck", setCode: "khc", collectorNumber: "10" }] };
    expect(choosingCommander("Kardur, Doomscourge", marked)).toEqual({ name: "Marked",
      commander: { cardName: "Kardur, Doomscourge", quantity: 1, section: "commanders", setCode: "khc", collectorNumber: "10" },
      entries: [{ cardName: "Forest", quantity: 1, section: "deck" }] });
    expect(choosingCommander("Forest", marked)).toBe(marked);
  });
});
