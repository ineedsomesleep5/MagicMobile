/**
 * Deck Studio's builder as Arena's (iOS DeckStudioWorkspaceScreen.arenaBuilder; docs/ARENA_STYLE.md, "Deck builder"):
 * over the dimmed room, the cards to add fill the left under one filter line (Deck/All, a short "Search", the mana
 * values 0–7+, then Filter, undo and redo); a deck that can't be edited shows its own cards there. The deck stands on
 * the right as a 330 px column: Save (or Edit a copy) and ⋯ at its head, the chapters (Cards · Ideas · Analysis), the
 * commander's round art, name and quick check, the cards by type with − and + on each line, the gold mana curve, and
 * Done beside Play at its foot. Ideas and Analysis take the left pane while the deck stays on the right.
 */
import { useEffect, useMemo, useState } from "react";
import type { AIDeck } from "../../core/aiDeckPool";
import { bracketReasons, type BracketRules, CommanderBracket } from "../../core/brackets";
import { averageManaValue, cardGroups, manaCurve, RoleGroups, SampleHand, statistics } from "../../core/deckStudio/analysis";
import type { DeckResolver } from "../../core/deckResolver";
import { type Catalogue, type CatalogueCard, loadCatalogue } from "../../core/deckStudio/catalogue";
import {
  changeDraft, type DeckDraft, draftDeck, draftFromDeck, draftFromDeckList, draftHistory, DraftPresentation, type DraftRow,
  EditorOperations, emptyDraft,
} from "../../core/deckStudio/draft";
import { type DeckLibrary, DeckLibraryRecord } from "../../core/deckStudio/library";
import { gameAudio } from "../audio";
import { cardImageURL, manaSymbols } from "../cardArt";
import { ManaSymbol } from "../arena/Symbols";
import { DeckArt } from "./DeckBox";
import { ImportPanel } from "./DeckImport";
import { Btn, Caps, PlayButton, PopMenu, type PopItem, SearchField, Segmented } from "./kit";
import { deckCurve, deckGroups, deckText, preflightOf, searchCards, type CardFilters } from "./studioAdapter";

export type StudioRoute = { kind: "deck"; id: string } | { kind: "new" } | { kind: "import" };

type Chapter = "Cards" | "Ideas" | "Analysis";
const CHAPTERS: Chapter[] = ["Cards", "Ideas", "Analysis"];
const TYPES = ["Creature", "Artifact", "Enchantment", "Instant", "Sorcery", "Land", "Planeswalker", "Battle"];
const COLORS: [string, string][] = [["W", "White"], ["U", "Blue"], ["B", "Black"], ["R", "Red"], ["G", "Green"], ["C", "Colorless"]];

interface Props {
  route: StudioRoute;
  library: DeckLibrary;
  deckFor: (id: string) => AIDeck | undefined;
  resolver: DeckResolver;
  bracketRules: BracketRules;
  close: () => void;
  changed: () => void;
  open: (route: StudioRoute) => void;
  play: (selectionID: string) => void;
}

export function DeckStudioScreen(props: Props) {
  const [catalogue, setCatalogue] = useState<Catalogue>();
  const [loadError, setLoadError] = useState<string>();
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let live = true;
    setLoadError(undefined);
    loadCatalogue().then((value) => { if (live) setCatalogue(value); }, () => { if (live) setLoadError("The card catalogue didn't load. Check your connection and try again."); });
    return () => { live = false; };
  }, [attempt]);
  return (
    <div className="mstudio" role="dialog" aria-label="Deck Studio">
      {props.route.kind === "import" ? (
        <ImportPanel library={props.library} catalogue={catalogue} resolver={props.resolver} close={props.close}
          saved={(record) => { props.changed(); props.open({ kind: "deck", id: DeckLibraryRecord.selectionID(record) }); }} />
      ) : (
        <Workspace key={props.route.kind === "deck" ? props.route.id : "new"} {...props} catalogue={catalogue}
          loadError={loadError} retry={() => setAttempt((n) => n + 1)} />
      )}
    </div>
  );
}

/** The deck being edited, its saved record (for the revision check) and whether it can be changed. */
function startingDraft(props: Props): { draft: DeckDraft; recordID?: string; readOnly: boolean; selection?: string } {
  if (props.route.kind !== "deck") return { draft: emptyDraft(), readOnly: false };
  const record = props.library.bySelection(props.route.id);
  if (record) return { draft: draftFromDeck(record), recordID: record.id, readOnly: false, selection: props.route.id };
  const included = props.deckFor(props.route.id);
  return { draft: included ? draftFromDeckList(included.deckList) : emptyDraft(), readOnly: true, selection: props.route.id };
}

function Workspace(props: Props & { catalogue?: Catalogue; loadError?: string; retry: () => void }) {
  const { catalogue, library } = props;
  const start = useMemo(() => startingDraft(props), []);
  const [history, setHistory] = useState(() => draftHistory(start.draft));
  const [recordID, setRecordID] = useState(start.recordID);
  const readOnly = start.readOnly;
  const draft = history.value;
  const [chapter, setChapter] = useState<Chapter>("Cards");
  const [shelf, setShelf] = useState<"all" | "deck">(readOnly ? "deck" : "all");
  const [filters, setFilters] = useState<CardFilters>({ query: "", type: "", color: "", mana: new Set(), withinIdentity: true });
  const [error, setError] = useState<string>();
  const [checkOpen, setCheckOpen] = useState(false);
  const [asking, setAsking] = useState<"close" | "rename">();
  const [inspect, setInspect] = useState<string>();
  const [copied, setCopied] = useState(false);

  const colors = DraftPresentation.colors(draft, catalogue);
  const commanders = DraftPresentation.commanders(draft);
  const check = useMemo(() => preflightOf(draft, catalogue, (name) => props.resolver.canonicalName(name)), [draft, catalogue, props.resolver]);
  const groups = useMemo(() => deckGroups(draft, catalogue), [draft, catalogue]);
  const record = recordID ? library.record(recordID) : undefined;
  const dirty = history.isDirty || (!readOnly && !recordID);

  const edit = (operation: (value: DeckDraft) => DeckDraft) => {
    if (readOnly) return;
    try { setHistory((h) => changeDraft(h, operation)); setError(undefined); }
    catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };

  /** DeckStudioEditorModel.save: a new deck is added, a saved one updated against its revision. */
  const save = (): string | undefined => {
    if (readOnly) return start.selection;
    try {
      const deck = draftDeck(draft);
      const saved = recordID ? library.update(recordID, deck, record?.revision ?? 0) : library.add(deck);
      if (colors) library.rememberColors(saved.id, colors);
      setRecordID(saved.id);
      setHistory(draftHistory(draftFromDeck(saved)));
      setError(undefined);
      props.changed();
      return DeckLibraryRecord.selectionID(saved);
    } catch (failure) {
      setError(failure instanceof Error ? failure.message : String(failure));
      return undefined;
    }
  };

  const editCopy = () => {
    try {
      const deck = draftDeck(draft);
      const copy = library.add({ ...deck, name: `${deck.name} — Copy` });
      const included = start.selection ? props.deckFor(start.selection) : undefined;
      library.rememberColors(copy.id, colors ?? [...(included?.colors ?? "")]);
      props.changed();
      props.open({ kind: "deck", id: DeckLibraryRecord.selectionID(copy) });
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };

  const done = () => { if (dirty && !readOnly) setAsking("close"); else props.close(); };
  const playDeck = () => {
    const id = readOnly ? start.selection : history.isDirty || !recordID ? save() : DeckLibraryRecord.selectionID({ id: recordID });
    if (id) props.play(id);
  };

  const text = useMemo(() => deckText(draft), [draft]);
  const more: PopItem[] = [
    { label: "Validate deck", onClick: () => setCheckOpen(true) },
    { label: "Rename deck", disabled: readOnly, onClick: () => setAsking("rename") },
    { divider: true },
    { label: copied ? "List copied" : "Copy list", disabled: text === undefined, onClick: () => {
      if (text) void navigator.clipboard?.writeText(text).then(() => { setCopied(true); window.setTimeout(() => setCopied(false), 1500); });
    } },
  ];

  const countHere = (name: string) => EditorOperations.cardCount(draft, name, "deck");

  return (
    <div className="mbuilder">
      <section className="mbuilderleft mcard">
        {chapter === "Cards" ? (
          <>
            <div className="mfilterline">
              {!readOnly && (
                <div className="mshelfswitch" role="radiogroup" aria-label="Cards to show">
                  <button type="button" role="radio" aria-checked={shelf === "deck"} className={shelf === "deck" ? "on" : ""} onClick={() => setShelf("deck")}>Deck</button>
                  <button type="button" role="radio" aria-checked={shelf === "all"} className={shelf === "all" ? "on" : ""} onClick={() => setShelf("all")}>All</button>
                </div>
              )}
              <div className="mfiltersearch"><SearchField placeholder="Search" value={filters.query} onChange={(query) => setFilters({ ...filters, query })} /></div>
              <div className="mmanacoins" role="group" aria-label="Mana value">
                {[0, 1, 2, 3, 4, 5, 6, 7].map((value) => {
                  const on = filters.mana.has(value);
                  return (
                    <button key={value} type="button" className={`mmanacoin ${on ? "on" : ""}`} aria-pressed={on} aria-label={value === 7 ? "Mana value 7 or more" : `Mana value ${value}`}
                      onClick={() => { const mana = new Set(filters.mana); if (on) mana.delete(value); else mana.add(value); setFilters({ ...filters, mana }); }}>
                      {value === 7 ? "7+" : value}
                    </button>
                  );
                })}
              </div>
              <PopMenu label="Filters" id="deckStudio.cards.filter"
                items={[
                  { heading: "Card type" },
                  ...["", ...TYPES].map((type) => ({ label: type || "All types", checked: filters.type === type, onClick: () => setFilters({ ...filters, type }) })),
                  { heading: "Color" },
                  ...[["", "Any color"] as [string, string], ...COLORS].map(([code, name]) => ({ label: name, checked: filters.color === code, onClick: () => setFilters({ ...filters, color: code }) })),
                  ...(colors ? [{ divider: true } as PopItem, { label: "Within commander colors", checked: filters.withinIdentity, onClick: () => setFilters({ ...filters, withinIdentity: !filters.withinIdentity }) } as PopItem] : []),
                  { divider: true },
                  { label: "Clear filters", onClick: () => setFilters({ query: filters.query, type: "", color: "", mana: new Set(), withinIdentity: true }) },
                ]}
                trigger={() => <span className={`mtoolcoin ${filters.type || filters.color || !filters.withinIdentity ? "on" : ""}`}>
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 5h18l-7 8v6l-4 2v-8z" /></svg></span>} />
              {!readOnly && <>
                <button type="button" className="mtoolcoin" aria-label="Undo deck edit" disabled={!history.canUndo} onClick={() => setHistory(history.undone())}>
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 7 4 12l5 5M4 12h10a6 6 0 0 1 0 12" transform="translate(0 -3)" /></svg></button>
                <button type="button" className="mtoolcoin" aria-label="Redo deck edit" disabled={!history.canRedo} onClick={() => setHistory(history.redone())}>
                  <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 7 5 5-5 5M20 12H10a6 6 0 0 0 0 12" transform="translate(0 -3)" /></svg></button>
              </>}
            </div>
            <div className="mbuildergrid mscroll">
              {!catalogue ? (
                props.loadError ? <div className="mempty"><p>{props.loadError}</p><Btn kind="secondary" compact onClick={props.retry}>Try again</Btn></div>
                  : <p className="mempty">Loading cards…</p>
              ) : shelf === "all" && !readOnly ? (
                <CatalogueShelf catalogue={catalogue} filters={filters} identity={filters.withinIdentity ? colors : undefined}
                  count={countHere} add={(name) => edit((d) => EditorOperations.addOne(d, name))}
                  remove={(name) => edit((d) => EditorOperations.removeOne(d, name, "deck"))} inspect={setInspect} />
              ) : (
                <DeckShelf draft={draft} catalogue={catalogue} filters={filters} readOnly={readOnly}
                  change={(row, delta) => edit((d) => EditorOperations.changeQuantity(d, row.id, delta))} inspect={setInspect} />
              )}
            </div>
          </>
        ) : chapter === "Analysis" ? (
          <Analysis draft={draft} catalogue={catalogue} bracketRules={props.bracketRules} inspect={setInspect} />
        ) : (
          <Ideas commanders={commanders} />
        )}
      </section>

      <section className="mbuildercol mcard" data-id="deckStudio.deckColumn">
        <header className="mbuilderhead">
          {readOnly ? <Btn kind="secondary" compact className="pill" id="deckStudio.copy" onClick={editCopy}>Edit a copy</Btn>
            : <Btn kind="secondary" compact className="pill" id="deckStudio.save" disabled={!history.isDirty && !!recordID} onClick={() => { save(); }}>Save</Btn>}
          <span className="grow" />
          <PopMenu label="More" id="deckStudio.more" align="right" items={more}
            trigger={() => <span className="mtoolcoin"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg></span>} />
        </header>
        <div className="mbuildertabs"><Segmented options={CHAPTERS.map((c) => ({ value: c, label: c }))} value={chapter} onChange={setChapter} stretch label="Deck chapters" /></div>
        <div className="mbuilderdeck" data-id="deckStudio.deckHeader">
          <span className="mcommanderart"><DeckArt name={commanders[0]} colors={colors ?? []} /></span>
          <span className="grow">
            <b>{draft.name || "Untitled draft"}</b>
            <small>{commanders.join(" • ")}</small>
          </span>
          <button type="button" className={`mcheckchip ${check.issueCount === 0 ? "" : "warn"} ${checkOpen ? "on" : ""}`} aria-expanded={checkOpen}
            aria-label={`Quick check: ${check.summary}`} onClick={() => setCheckOpen(!checkOpen)}>
            {check.issueCount === 0 ? "No issues" : `${check.issueCount} to check`}
          </button>
        </div>
        {checkOpen && (
          <div className="mcheckpanel">
            <p>{check.summary}</p>
            {check.lines.map((line) => <p key={line} className="mnote">{line}</p>)}
          </div>
        )}
        {error && <p className="mnote warn" role="status">{error}</p>}
        <div className="mdecklist mscroll">
          {draft.rows.length === 0 && <p className="mempty">Add your commander and cards from the left.</p>}
          {groups.map((group) => (
            <div key={group.title}>
              <div className="mdeckgroup"><Caps text={group.title} size={9.5} /><b>{group.count}</b></div>
              {group.rows.map((row) => (
                <div key={row.id} className="mdeckline">
                  <button type="button" className="grow" onClick={() => setInspect(row.cardName)} aria-label={`Inspect ${row.cardName}, quantity ${row.quantity}`}>
                    <b>{row.quantity}</b><span>{row.cardName}</span>
                    <Cost cost={catalogue?.card(row.cardName)?.manaCost} />
                  </button>
                  {!readOnly && <>
                    <button type="button" className="mstep" aria-label={`Remove one ${row.cardName}`} onClick={() => edit((d) => EditorOperations.changeQuantity(d, row.id, -1))}>−</button>
                    <button type="button" className="mstep" aria-label={`Add one ${row.cardName}`} onClick={() => edit((d) => EditorOperations.changeQuantity(d, row.id, 1))}>+</button>
                  </>}
                </div>
              ))}
            </div>
          ))}
          {draft.rows.length > 0 && <>
            <Caps text="Mana curve" size={9.5} className="mcurvehead" />
            <Curve bins={deckCurve(draft, catalogue)} />
          </>}
        </div>
        <footer className="mbuilderfoot">
          <Btn kind="secondary" compact className="mbuilderdone" id="deckStudio.close" onClick={done}>Done</Btn>
          <div className="mbuilderplay"><PlayButton size={17} id="deckStudio.play" onClick={playDeck} disabled={draft.rows.length === 0}>Play</PlayButton></div>
        </footer>
      </section>

      {inspect && <Inspect name={inspect} card={catalogue?.card(inspect)} close={() => setInspect(undefined)} />}
      {asking === "close" && (
        <div className="mquestionlayer" onPointerDown={(e) => { if (e.target === e.currentTarget) setAsking(undefined); }}>
          <div className="mquestion glass" role="alertdialog" aria-label="Save your changes?">
            <b>Save your changes?</b>
            <div>
              <Btn kind="secondary" compact onClick={() => setAsking(undefined)}>Cancel</Btn>
              <Btn kind="danger" compact onClick={() => { setAsking(undefined); props.close(); }}>Discard</Btn>
              <Btn kind="primary" compact onClick={() => { if (save()) { setAsking(undefined); props.close(); } else setAsking(undefined); }}>Save and close</Btn>
            </div>
          </div>
        </div>
      )}
      {asking === "rename" && <Rename name={draft.name} close={() => setAsking(undefined)} rename={(name) => edit((d) => ({ ...d, name }))} />}
    </div>
  );
}

/** Every catalogue card the filter line lets through, in sleeves with + and − (DeckStudioBinderCatalogue). */
function CatalogueShelf({ catalogue, filters, identity, count, add, remove, inspect }: {
  catalogue: Catalogue; filters: CardFilters; identity?: string[]; count: (name: string) => number;
  add: (name: string) => void; remove: (name: string) => void; inspect: (name: string) => void;
}) {
  const [results, setResults] = useState<CatalogueCard[]>([]);
  // A short pause so typing doesn't search on every key (the phone waits 150 ms).
  useEffect(() => {
    const timer = window.setTimeout(() => setResults(searchCards(catalogue, filters, identity)), 150);
    return () => window.clearTimeout(timer);
  }, [catalogue, filters, identity?.join("")]);
  return (
    <>
      {results.length === 0 && <p className="mempty">No matching cards</p>}
      <div className="msleeves">
        {results.map((card) => (
          <Sleeve key={card.name} name={card.name} quantity={count(card.name)} add={() => add(card.name)} remove={() => remove(card.name)} inspect={() => inspect(card.name)} />
        ))}
      </div>
      {results.length > 0 && <p className="mnote mcentre">{results.length >= 120 ? "The first 120 cards · search or filter to narrow" : `${results.length} cards`}</p>}
    </>
  );
}

/** The deck's own cards as sleeves; a read-only deck shows them all, an editable one with its + and −. */
function DeckShelf({ draft, catalogue, filters, readOnly, change, inspect }: {
  draft: DeckDraft; catalogue: Catalogue; filters: CardFilters; readOnly: boolean; change: (row: DraftRow, delta: number) => void; inspect: (name: string) => void;
}) {
  const rows = draft.rows.filter((row) => {
    const card = catalogue.card(row.cardName);
    return searchCards.matches(card ?? { name: row.cardName, setCodes: [], roles: [] }, filters);
  });
  return (
    <>
      {rows.length === 0 && <p className="mempty">{draft.rows.length === 0 ? "No cards yet" : "No matching cards"}</p>}
      <div className="msleeves">
        {rows.map((row) => (
          <Sleeve key={row.id} name={row.cardName} quantity={row.quantity} add={readOnly ? undefined : () => change(row, 1)}
            remove={readOnly ? undefined : () => change(row, -1)} inspect={() => inspect(row.cardName)} />
        ))}
      </div>
    </>
  );
}

/** A card in its sleeve: the image, its copies as ◆ above it, and − and + while it can be changed. */
function Sleeve({ name, quantity, add, remove, inspect }: { name: string; quantity: number; add?: () => void; remove?: () => void; inspect: () => void }) {
  return (
    <div className={`msleeve ${quantity > 0 ? "in" : ""}`}>
      <div className="mcopies" aria-hidden="true">{Array.from({ length: 4 }, (_, i) => <i key={i} className={i < quantity ? "on" : ""} />)}
        {quantity > 4 && <b>{quantity}</b>}</div>
      <button type="button" className="msleevecard" aria-label={add ? `Add ${name} to deck` : `Inspect ${name}`}
        onClick={() => { if (add) { gameAudio.play("ui-tap"); add(); } else inspect(); }}
        onContextMenu={(e) => { e.preventDefault(); inspect(); }}>
        <img src={cardImageURL(name, "normal")} alt={name} crossOrigin="anonymous" loading="lazy" draggable={false} />
      </button>
      {(add || remove) && (
        <div className="msleevesteps">
          <button type="button" aria-label={`Remove one ${name} from deck`} disabled={quantity === 0} onClick={() => remove?.()}>−</button>
          <button type="button" aria-label={`Inspect ${name}`} onClick={inspect}>i</button>
          <button type="button" aria-label={`Add ${name} to deck`} onClick={() => add?.()}>+</button>
        </div>
      )}
    </div>
  );
}

function Cost({ cost }: { cost?: string }) {
  if (!cost) return null;
  return <span className="mcost">{manaSymbols(cost).map((symbol, i) => <ManaSymbol key={i} symbol={symbol} size={13} />)}</span>;
}

/** Arena's small mana curve under the list: the main deck's nonland cards by mana value, 0 to 7+. */
function Curve({ bins }: { bins: number[] }) {
  const top = Math.max(1, ...bins);
  return (
    <div className="mcurve" role="img" aria-label={`Mana curve: ${bins.map((n, i) => `${i === 7 ? "7 or more" : i}: ${n}`).join(", ")}`}>
      {bins.map((count, bin) => (
        <div key={bin}>
          <small style={{ opacity: count === 0 ? 0 : 1 }}>{count}</small>
          <i style={{ height: Math.max(2, (30 * count) / top) }} />
          <b>{bin === 7 ? "7+" : bin}</b>
        </div>
      ))}
    </div>
  );
}

/** The card, large, with its words (DeckStudio inspect). */
function Inspect({ name, card, close }: { name: string; card?: CatalogueCard; close: () => void }) {
  useEffect(() => {
    const key = (e: KeyboardEvent) => { if (e.key === "Escape") { e.stopPropagation(); close(); } };
    window.addEventListener("keydown", key, true);
    return () => window.removeEventListener("keydown", key, true);
  }, [close]);
  return (
    <div className="mquestionlayer" onPointerDown={(e) => { if (e.target === e.currentTarget) close(); }}>
      <div className="minspect glass" role="dialog" aria-label={name}>
        <img src={cardImageURL(name, "large")} alt={name} crossOrigin="anonymous" />
        <div>
          <b>{name}</b>
          {card?.typeLine && <small>{card.typeLine}</small>}
          {card?.oracleText && <p>{card.oracleText.replace(/<br>/g, "\n")}</p>}
          <Btn kind="secondary" compact onClick={close}>Close</Btn>
        </div>
      </div>
    </div>
  );
}

function Rename({ name, close, rename }: { name: string; close: () => void; rename: (name: string) => void }) {
  const [value, setValue] = useState(name);
  const ok = value.trim().length > 0 && new TextEncoder().encode(value).length <= 512;
  return (
    <div className="mquestionlayer" onPointerDown={(e) => { if (e.target === e.currentTarget) close(); }}>
      <form className="mquestion glass" aria-label="Rename deck" onSubmit={(e) => { e.preventDefault(); if (ok) { rename(value.trim()); close(); } }}>
        <b>Rename deck</b>
        <input className="mfield" value={value} autoFocus onChange={(e) => setValue(e.target.value)} aria-label="Deck name" />
        <div>
          <Btn kind="secondary" compact onClick={close}>Cancel</Btn>
          <Btn kind="primary" compact disabled={!ok} onClick={() => { rename(value.trim()); close(); }}>Rename</Btn>
        </div>
      </form>
    </div>
  );
}

/**
 * The deck at a glance (DeckStudioAnalysisContent): counts, the curve and the coloured symbols; its roles
 * (RoleInsights); and a goldfish sample hand (DeckStudioSampleHand). Facts from the catalogue, not a legality check.
 */
function Analysis({ draft, catalogue, bracketRules, inspect }: { draft: DeckDraft; catalogue?: Catalogue; bracketRules: BracketRules; inspect: (name: string) => void }) {
  const deck = useMemo(() => { try { return draftDeck({ ...draft, name: draft.name || "Draft" }); } catch { return undefined; } }, [draft]);
  const stats = useMemo(() => (catalogue && deck ? statistics(catalogue, deck) : undefined), [catalogue, deck]);
  const roles = useMemo(() => {
    const groups = cardGroups(draft.rows, "Role", catalogue);
    return groups.filter((group) => group.title !== "Commanders" && RoleGroups.order.includes(group.title));
  }, [draft, catalogue]);
  const report = useMemo(() => bracketRules.evaluate(draft.rows.filter((row) => ["deck", "commanders"].includes(DraftPresentation.section(row))).map((row) => row.cardName)), [draft, bracketRules]);
  const [hand, setHand] = useState(() => SampleHand.of(SampleHand.libraryNames(draft)).dealt());
  useEffect(() => { setHand(SampleHand.of(SampleHand.libraryNames(draft)).dealt()); }, [draft]);
  if (!catalogue) return <div className="mbuilderpage"><p className="mempty">Loading cards…</p></div>;
  const average = stats ? averageManaValue(stats) : undefined;
  const symbols = stats ? [...stats.manaSymbolCounts.entries()].filter(([symbol]) => /^[WUBRGC]$/.test(symbol)).sort((a, b) => "WUBRGC".indexOf(a[0]) - "WUBRGC".indexOf(b[0])) : [];
  return (
    <div className="mbuilderpage mscroll manalysis">
      <section>
        <Caps text="At a glance" />
        <div className="mstats">
          <span><b>{stats?.cardCount ?? 0}</b><small>MAIN DECK</small></span>
          <span><b>{stats?.landCount ?? 0}</b><small>LANDS</small></span>
          <span><b>{average === undefined ? "–" : average.toFixed(2)}</b><small>AVERAGE MANA VALUE</small></span>
          <span><b>{CommanderBracket.name(report.minimum)}</b><small>BRACKET AT LEAST</small></span>
        </div>
        {bracketReasons(report).map((line) => <p key={line} className="mnote">{line}</p>)}
        <div className="manalysiscurve"><Curve bins={manaCurve(draft, catalogue)} /></div>
        {symbols.length > 0 && (
          <div className="msymbols">{symbols.map(([symbol, count]) => <span key={symbol}><ManaSymbol symbol={symbol} size={16} /><b>{count}</b></span>)}</div>
        )}
      </section>
      <section>
        <Caps text="Roles" />
        <div className="mroles">
          {roles.map((group) => (
            <details key={group.title}>
              <summary><span>{group.title}</span><b>{RoleGroups.uniqueCards(group.rows)}</b></summary>
              <div>{[...new Set(group.rows.map((row) => row.cardName))].map((name) => <button key={name} type="button" onClick={() => inspect(name)}>{name}</button>)}</div>
            </details>
          ))}
        </div>
      </section>
      <section>
        <div className="mhandhead">
          <Caps text="Sample hand" />
          <small>{hand.status}</small>
          <span className="grow" />
          <Btn kind="secondary" compact className="pill" disabled={!hand.canMulligan} onClick={() => setHand(hand.mulliganed())}>Mulligan</Btn>
          <Btn kind="secondary" compact className="pill" disabled={!hand.canDraw} onClick={() => setHand(hand.drawn())}>Draw</Btn>
          <Btn kind="secondary" compact className="pill" onClick={() => setHand(hand.dealt())}>New hand</Btn>
        </div>
        <div className="mhand">
          {hand.hand.map((card) => (
            <button key={card.id} type="button" className="msleevecard" aria-label={hand.toBottom > 0 ? `Put ${card.name} on the bottom` : `Inspect ${card.name}`}
              onClick={() => (hand.toBottom > 0 ? setHand(hand.puttingOnBottom(card.id)) : inspect(card.name))}>
              <img src={cardImageURL(card.name, "normal")} alt={card.name} crossOrigin="anonymous" loading="lazy" draggable={false} />
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

/**
 * Ideas: the commander's page on EDHREC (its link from Scryfall's record, as the phone finds it: no guessed slug) and
 * its combos on Commander Spellbook, each in a new tab. The phone shows them inside the app; this page is cross-origin
 * isolated, so it can't.
 */
function Ideas({ commanders }: { commanders: string[] }) {
  const [busy, setBusy] = useState<string>();
  const [error, setError] = useState<string>();
  const openEDHREC = async (name: string) => {
    setBusy(name); setError(undefined);
    // Opened before the lookup so the browser treats it as the click's own window.
    const tab = window.open("about:blank", "_blank");
    try {
      const response = await fetch(`https://api.scryfall.com/cards/named?exact=${encodeURIComponent(name)}`, { headers: { Accept: "application/json" } });
      const card = response.ok ? await response.json() as { related_uris?: { edhrec?: string } } : undefined;
      const url = card?.related_uris?.edhrec;
      if (!url || !/^https:\/\/edhrec\.com\//.test(url)) throw new Error("no link");
      if (tab) tab.location.href = url; else window.open(url, "_blank", "noopener");
    } catch {
      tab?.close();
      setError("Could not find this commander's EDHREC page. Browse EDHREC or copy the name instead.");
    } finally { setBusy(undefined); }
  };
  if (commanders.length === 0) return <div className="mbuilderpage"><p className="mempty">Choose a commander first</p></div>;
  return (
    <div className="mbuilderpage mscroll mideas">
      {commanders.map((name) => (
        <section key={name} className="mideacard">
          <img src={cardImageURL(name, "art_crop")} alt="" crossOrigin="anonymous" />
          <div>
            <b>{name}</b>
            <div className="mideabuttons">
              <Btn kind="secondary" compact className="pill" disabled={busy === name} onClick={() => { void openEDHREC(name); }}>EDHREC</Btn>
              <Btn kind="secondary" compact className="pill" onClick={() => window.open(`https://commanderspellbook.com/search/?q=${encodeURIComponent(`card:"${name}"`)}`, "_blank", "noopener")}>Combos</Btn>
            </div>
          </div>
        </section>
      ))}
      {error && <p className="mnote warn" role="status">{error}</p>}
    </div>
  );
}
