/**
 * The Decks tab as Arena's decks page (iOS DeckStudioRootView; docs/ARENA_STYLE.md, "Decks"): search, which decks and
 * their order, and Import along the top; your decks and the precons as boxes across the page, the "+" box first (the
 * first click opens a box, a second opens it in the builder); and the chosen deck on a strip along the foot with its
 * star, its ⋯ menu, Edit Deck and Play.
 */
import { useLayoutEffect, useRef, useState } from "react";
import { gameAudio } from "../audio";
import { boxGeometry, DeckArt, DeckBox, type DeckBoxModel, NewDeckBox } from "./DeckBox";
import { Btn, PlayButton, PopMenu, type PopItem, Pips, Question, SearchField, SectionHeader } from "./kit";

/** A deck on the page: its box, whether it is yours, and what the search and sort read. */
export interface ShelfDeck {
  box: DeckBoxModel;
  local: boolean;
  /** Milliseconds; included decks have none and sort last by "Recently edited". */
  updatedAt?: number;
  cardCount: number;
  /** Short bracket name for the strip ("Core"). */
  bracket: string;
}

export interface DecksPageModel {
  decks: ShelfDeck[];
  selectedDeckID: string;
  /** The deck that takes over when the playing deck is deleted (the first precon). */
  fallbackName: string;
  favorites: ReadonlySet<string>;
  notice?: string;
  select: (id: string) => void;
  play: (id: string) => void;
  edit: (id: string) => void;
  create: () => void;
  importDecks: () => void;
  duplicate: (id: string) => void;
  remove: (id: string) => void;
  toggleFavorite: (id: string) => void;
  /** The deck as plain text, to copy; undefined while the card data is loading. */
  exportText?: (id: string) => string | undefined;
}

type Filter = "all" | "favorites" | "local" | "included";
const FILTERS: [Filter, string][] = [["all", "All"], ["favorites", "Favorites"], ["local", "My decks"], ["included", "Included"]];
type Sort = "edited" | "name" | "commander";
const SORTS: [Sort, string][] = [["edited", "Recently edited"], ["name", "Name"], ["commander", "Commander"]];

/** DeckStudioLibraryQuery.key: case and accents don't matter. */
const key = (text: string) => text.normalize("NFKD").replace(/\p{M}/gu, "").toLowerCase();

/** DeckStudioLibraryQuery.apply. */
export function shelfQuery(decks: ShelfDeck[], text: string, filter: Filter, sort: Sort, favorites: ReadonlySet<string>): ShelfDeck[] {
  const words = key(text).split(/\s+/).filter(Boolean);
  const matching = decks.filter((deck) => {
    const haystack = key([deck.box.name, deck.box.commander ?? ""].join(" "));
    if (!words.every((word) => haystack.includes(word))) return false;
    return filter === "all" || (filter === "favorites" ? favorites.has(deck.box.id) : filter === "local" ? deck.local : !deck.local);
  });
  const byName = (a: ShelfDeck, b: ShelfDeck) => {
    const x = key(a.box.name), y = key(b.box.name);
    return x === y ? (a.box.id < b.box.id ? -1 : 1) : x < y ? -1 : 1;
  };
  return matching.sort((a, b) => {
    if (sort === "edited" && (a.updatedAt ?? 0) !== (b.updatedAt ?? 0)) return (b.updatedAt ?? 0) - (a.updatedAt ?? 0);
    if (sort === "commander") {
      const x = key(a.box.commander ?? ""), y = key(b.box.commander ?? "");
      if (x !== y) return x < y ? -1 : 1;
    }
    return byName(a, b);
  });
}

const chevron = <svg className="mchev" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 9l6 6 6-6" /></svg>;

export function DecksPage({ model }: { model: DecksPageModel }) {
  const [text, setText] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const [sort, setSort] = useState<Sort>("edited");
  const [focused, setFocused] = useState<string>();
  const [deleting, setDeleting] = useState<ShelfDeck>();
  const [copied, setCopied] = useState(false);
  const shelf = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(900);
  useLayoutEffect(() => {
    const node = shelf.current;
    if (!node) return;
    const observer = new ResizeObserver(() => setWidth(node.clientWidth));
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const visible = shelfQuery(model.decks, text, filter, sort, model.favorites);
  const chosenID = focused ?? model.selectedDeckID;
  const chosen = model.decks.find((d) => d.box.id === chosenID) ?? visible[0];
  const gap = 12;
  const usable = width - 8;
  const columns = Math.max(2, Math.floor((usable + gap) / (112 + gap)));
  const boxWidth = Math.floor((usable - gap * (columns - 1)) / columns);
  const rise = boxGeometry(boxWidth).rise * 1.5;
  // Only a box open in the first row needs room above it (the "+" box takes the first place).
  const firstRowOpen = visible.findIndex((d) => d.box.id === chosen?.box.id) < columns - 1;

  const actions = (deck: ShelfDeck): PopItem[] => {
    const text = model.exportText?.(deck.box.id);
    return [
      { heading: deck.box.name },
      { label: "Play", onClick: () => model.play(deck.box.id) },
      { label: "Open deck", onClick: () => model.edit(deck.box.id) },
      { label: "Duplicate locally", onClick: () => model.duplicate(deck.box.id) },
      { divider: true },
      { label: copied ? "Copied" : "Copy list", disabled: text === undefined, onClick: () => {
        if (text === undefined) return;
        void navigator.clipboard?.writeText(text).then(() => { setCopied(true); window.setTimeout(() => setCopied(false), 1500); });
      } },
      ...(deck.local ? [{ divider: true } as PopItem, { label: "Delete local deck", danger: true, onClick: () => setDeleting(deck) } as PopItem] : []),
    ];
  };

  return (
    <div className="mdecks">
      <div className="mdecksbar">
        <div className="mdeckssearch"><SearchField placeholder="Search decks" value={text} onChange={setText} /></div>
        <PopMenu label="Show decks" id="deckStudio.library.filter" items={FILTERS.map(([value, label]) => ({ label, checked: filter === value, onClick: () => setFilter(value) }))}
          trigger={() => <span className="mbtn pill secondary">{filter === "all" ? "All decks" : FILTERS.find(([v]) => v === filter)![1]}{chevron}</span>} />
        <PopMenu label="Sort decks" items={SORTS.map(([value, label]) => ({ label, checked: sort === value, onClick: () => setSort(value) }))}
          trigger={() => <span className="mbtn pill secondary">{SORTS.find(([v]) => v === sort)![1]}{chevron}</span>} />
        <Btn kind="secondary" compact className="pill" id="deckStudio.import" onClick={model.importDecks}>Import</Btn>
      </div>
      {model.notice && <p className="mnote warn" role="status">{model.notice}</p>}
      <div ref={shelf} className="mdecksshelf mscroll">
        <SectionHeader title="My Decks" count={visible.length} />
        {visible.length === 0 && <p className="mempty">{text || filter !== "all" ? "No matching decks" : "Your next deck starts here"}</p>}
        <div className="mshelf" style={{ gridTemplateColumns: `repeat(${columns}, ${boxWidth}px)`, columnGap: gap, rowGap: rise + 10, paddingTop: firstRowOpen ? rise + 10 : 8 }}>
          <button type="button" className="mdeckbutton" aria-label="Create deck" data-id="deckStudio.create" onClick={() => { gameAudio.play("ui-open"); model.create(); }}>
            <NewDeckBox width={boxWidth} />
          </button>
          {visible.map((deck) => {
            const on = deck.box.id === chosen?.box.id;
            return (
              <button key={deck.box.id} type="button" className="mdeckbutton" data-id={`deckStudio.deck.${deck.box.id}`} aria-pressed={on}
                onClick={() => {
                  // Arena's way: the first click opens the box and shows the deck; a second opens it for editing.
                  if (on) { gameAudio.play("ui-open"); model.edit(deck.box.id); } else { gameAudio.play("ui-tap"); setFocused(deck.box.id); model.select(deck.box.id); }
                }}>
                <DeckBox deck={{ ...deck.box, tag: deck.box.id === model.selectedDeckID ? "PLAYING" : undefined }} selected={on} width={boxWidth}
                  onEdit={on ? () => model.edit(deck.box.id) : undefined} />
              </button>
            );
          })}
        </div>
      </div>
      {chosen && (
        <footer className="mdecksstrip" data-id="deckStudio.detail">
          <span className="mdecksart"><DeckArt name={chosen.box.commander} colors={chosen.box.colors} /></span>
          <span className="grow">
            <b>{chosen.box.name}</b>
            <span className="mdecksfacts"><Pips colors={chosen.box.colors} size={13} /><small className="mbracketchip">{chosen.bracket}</small></span>
          </span>
          <button type="button" className={`mcoin ${model.favorites.has(chosen.box.id) ? "on" : ""}`} aria-pressed={model.favorites.has(chosen.box.id)}
            aria-label={model.favorites.has(chosen.box.id) ? `Unfavorite ${chosen.box.name}` : `Favorite ${chosen.box.name}`}
            onClick={() => { gameAudio.play("ui-tap"); model.toggleFavorite(chosen.box.id); }}>
            <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3l2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 16.8l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z" /></svg>
          </button>
          <PopMenu label={`Options for ${chosen.box.name}`} items={actions(chosen)} align="right" up
            trigger={() => <span className="mcoin"><svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="5" cy="12" r="2" /><circle cx="12" cy="12" r="2" /><circle cx="19" cy="12" r="2" /></svg></span>} />
          <Btn kind="secondary" compact className="mdecksedit" id="deckStudio.edit" onClick={() => model.edit(chosen.box.id)}>Edit Deck</Btn>
          <div className="mdecksplay"><PlayButton size={18} id="deckStudio.library.play" onClick={() => model.play(chosen.box.id)}>Play</PlayButton></div>
        </footer>
      )}
      {deleting && (
        <Question title="Delete this local deck?" danger action={`Delete ${deleting.box.name}`}
          detail={deleting.box.id === model.selectedDeckID ? `This is your playing deck. ${model.fallbackName} will be selected instead.` : "Included decks and source websites are never changed."}
          onCancel={() => setDeleting(undefined)} onConfirm={() => { model.remove(deleting.box.id); setDeleting(undefined); setFocused(undefined); }} />
      )}
    </div>
  );
}
