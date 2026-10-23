/**
 * The Decks tab as Arena's decks page (docs/ARENA_STYLE.md, "Decks"): search and a filter over every deck as a box across
 * the page, the chosen one open, and the chosen deck on a one-row strip along the foot with Play. Your own decks, the
 * builder and import come with Deck Studio; until then the shelf holds the precons and the included decks.
 */
import { useLayoutEffect, useRef, useState } from "react";
import { gameAudio } from "../audio";
import { boxGeometry, DeckArt, DeckBox } from "./DeckBox";
import { Pill, Pips, PlayButton, SearchField, SectionHeader } from "./kit";
import type { DeckSection } from "./PlayPanel";

type Filter = "all" | "precons" | "included";
const FILTERS: { value: Filter; label: string }[] = [{ value: "all", label: "All decks" }, { value: "precons", label: "Precons" }, { value: "included", label: "Included" }];

export function DecksPage({ sections, selectedDeckID, select, play }: { sections: DeckSection[]; selectedDeckID: string; select: (id: string) => void; play: () => void }) {
  const [text, setText] = useState("");
  const [filter, setFilter] = useState<Filter>("all");
  const shelf = useRef<HTMLDivElement>(null);
  const [width, setWidth] = useState(900);
  useLayoutEffect(() => {
    const node = shelf.current;
    if (!node) return;
    const observer = new ResizeObserver(() => setWidth(node.clientWidth));
    observer.observe(node);
    return () => observer.disconnect();
  }, []);
  const query = text.trim().toLowerCase();
  const shown = sections.filter((s) => filter === "all" || (filter === "precons" ? s.id === "precons" : s.id !== "precons"))
    .map((s) => ({ ...s, decks: s.decks.filter((d) => !query || d.name.toLowerCase().includes(query) || (d.commander ?? "").toLowerCase().includes(query)) }))
    .filter((s) => s.decks.length > 0);
  const chosen = sections.flatMap((s) => s.decks).find((d) => d.id === selectedDeckID);
  const gap = 12;
  const usable = width - 8;
  const columns = Math.max(2, Math.floor((usable + gap) / (112 + gap)));
  const boxWidth = Math.floor((usable - gap * (columns - 1)) / columns);
  const rise = boxGeometry(boxWidth).rise;
  return (
    <div className="mdecks">
      <div className="mdecksbar">
        <div className="mdeckssearch"><SearchField placeholder="Search decks" value={text} onChange={setText} /></div>
        {FILTERS.map((f) => <Pill key={f.value} lit={filter === f.value} onClick={() => setFilter(f.value)}>{f.label}</Pill>)}
      </div>
      <div ref={shelf} className="mdecksshelf mscroll">
        {shown.length === 0 && <p className="mempty">No matching decks</p>}
        {shown.map((section) => (
          <section key={section.id}>
            <SectionHeader title={section.title} count={section.decks.length} />
            <div className="mshelf" style={{ gridTemplateColumns: `repeat(${columns}, ${boxWidth}px)`, columnGap: gap, rowGap: rise + 8, paddingTop: rise + 12 }}>
              {section.decks.map((deck) => (
                <button key={deck.id} type="button" className="mdeckbutton" data-id={`decks.deck.${deck.id}`} aria-pressed={deck.id === selectedDeckID}
                  onClick={() => { gameAudio.play("ui-tap"); select(deck.id); }}>
                  <DeckBox deck={deck} selected={deck.id === selectedDeckID} width={boxWidth} />
                </button>
              ))}
            </div>
          </section>
        ))}
      </div>
      {chosen && (
        <footer className="mdecksstrip">
          <span className="mdecksart"><DeckArt name={chosen.commander} colors={chosen.colors} /></span>
          <span className="grow"><b>{chosen.name}</b><small>{chosen.subtitle}</small></span>
          <Pips colors={chosen.colors} size={16} />
          <div className="mdecksplay"><PlayButton size={18} id="decks.play" onClick={play}>Play</PlayButton></div>
        </footer>
      )}
    </div>
  );
}
