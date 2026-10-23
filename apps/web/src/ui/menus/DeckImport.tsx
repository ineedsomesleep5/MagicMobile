/**
 * Import (iOS DeckStudioImportScreen): paste a list or open a text file, or give a public Moxfield or Archidekt link;
 * review what was read (the commander, which can be chosen here, the counts, names the catalogue doesn't know, and
 * what each odd line became); then save it as your deck, and the builder opens on it. Nothing is dropped: unknown
 * names stay in the draft to fix later.
 */
import { useMemo, useRef, useState } from "react";
import type { DeckResolver } from "../../core/deckResolver";
import type { Catalogue } from "../../core/deckStudio/catalogue";
import { draftDeck, draftFromDeck, DraftPresentation, EditorOperations, type StudioDeck } from "../../core/deckStudio/draft";
import type { DeckLibrary, DeckLibraryRecord } from "../../core/deckStudio/library";
import { commanderSearch } from "../../core/deckStudio/search";
import { importText, type TextAnnotation } from "../../core/deckStudio/textIO";
import { Btn, Caps, Checkbox, PanelHeader, Segmented } from "./kit";
import { fetchLinkedDeck } from "./studioAdapter";

type Method = "paste" | "link";

interface Preview { deck: StudioDeck; annotations: TextAnnotation[]; sourceURL?: string }

export function ImportPanel({ library, catalogue, resolver, close, saved }: {
  library: DeckLibrary; catalogue?: Catalogue; resolver: DeckResolver; close: () => void; saved: (record: DeckLibraryRecord) => void;
}) {
  const [method, setMethod] = useState<Method>("paste");
  const [name, setName] = useState("Imported Commander Deck");
  const [text, setText] = useState("");
  const [link, setLink] = useState("");
  const [excludeSideboards, setExcludeSideboards] = useState(true);
  const [preview, setPreview] = useState<Preview>();
  const [commander, setCommander] = useState<string>();
  const [commanderQuery, setCommanderQuery] = useState("");
  const [choosing, setChoosing] = useState(false);
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  const file = useRef<HTMLInputElement>(null);

  const review = async () => {
    setError(undefined); setBusy(true);
    try {
      if (method === "paste") {
        const read = importText(text, name.trim() || "Imported Commander Deck");
        setPreview({ deck: read.deck, annotations: read.annotations });
      } else {
        const fetched = await fetchLinkedDeck(link.trim(), excludeSideboards, (card) => resolver.canonicalName(card));
        setPreview({ deck: fetched.deck, annotations: fetched.annotations, sourceURL: link.trim() });
      }
      setCommander(undefined); setCommanderQuery(""); setChoosing(false);
    } catch (failure) {
      setPreview(undefined);
      setError(failure instanceof Error ? failure.message : String(failure));
    } finally { setBusy(false); }
  };

  /** The reviewed deck with the commander chosen here leading it (startWithCommander). */
  const reviewed = useMemo(() => {
    if (!preview) return undefined;
    let draft = draftFromDeck(preview.deck);
    if (commander) draft = EditorOperations.replacePrimaryCommander(draft, commander, true);
    return draft;
  }, [preview, commander]);
  const lead = reviewed ? DraftPresentation.commanders(reviewed)[0] : undefined;
  const unresolved = useMemo(() => reviewed ? [...new Set(reviewed.rows.map((row) => row.cardName).filter((card) => resolver.canonicalName(card) === undefined))] : [],
    [reviewed, resolver]);
  const candidates = useMemo(() => (catalogue && commanderQuery.trim().length >= 2 ? commanderSearch(catalogue, commanderQuery, 8) : []), [catalogue, commanderQuery]);

  const save = () => {
    if (!reviewed) return;
    try {
      const deck = draftDeck(reviewed);
      const record = library.add(deck, preview?.sourceURL);
      const colors = DraftPresentation.colors(reviewed, catalogue);
      if (colors) library.rememberColors(record.id, colors);
      saved(record);
    } catch (failure) { setError(failure instanceof Error ? failure.message : String(failure)); }
  };

  const openFile = async (chosen: File | undefined) => {
    if (!chosen) return;
    if (chosen.size > 2 * 1024 * 1024) { setError("Choose a UTF-8 deck file of at most 2 MiB."); return; }
    setText(await chosen.text());
    setName(chosen.name.replace(/\.[^.]+$/, ""));
    setMethod("paste");
  };

  return (
    <div className="mimport mcard" data-id="deckStudio.import">
      <PanelHeader title="Import deck" onClose={close} />
      <div className="mimportbody mscroll">
        {!preview ? (
          <>
            <Segmented options={[{ value: "paste" as Method, label: "Paste" }, { value: "link" as Method, label: "Link" }]} value={method} onChange={setMethod} label="Import method" />
            {method === "paste" ? (
              <>
                <input className="mfield" value={name} onChange={(e) => setName(e.target.value)} aria-label="Deck name" placeholder="Deck name" />
                <textarea className="mfield mtextarea" value={text} onChange={(e) => setText(e.target.value)} aria-label="Decklist text" spellCheck={false}
                  placeholder={"Commander\n1 Your Commander\n\nDeck\n1 Sol Ring"} />
                <div><Btn kind="secondary" compact className="pill" onClick={() => file.current?.click()}>Open text file</Btn></div>
                <input ref={file} type="file" accept=".txt,.dek,.json,text/plain" hidden onChange={(e) => { void openFile(e.target.files?.[0]); e.target.value = ""; }} />
              </>
            ) : (
              <>
                <input className="mfield" value={link} onChange={(e) => setLink(e.target.value)} aria-label="Deck link" placeholder="Public Archidekt or Moxfield deck URL" />
                <Checkbox title="Exclude sideboard / maybeboard" on={excludeSideboards} onChange={setExcludeSideboards} />
              </>
            )}
            {error && <p className="mnote warn" role="status">{error}</p>}
            <div className="mimportfoot">
              <Btn kind="primary" id="deckStudio.import.review" disabled={busy || (method === "paste" ? text : link).trim().length === 0} onClick={() => { void review(); }}>
                {busy ? "Reading…" : "Review decklist"}
              </Btn>
            </div>
          </>
        ) : (
          <>
            <div className="mimportreview">
              <Caps text="Commander" />
              {lead && !choosing ? (
                <div className="mimportlead"><b>{lead}</b><Btn kind="secondary" compact className="pill" onClick={() => { setChoosing(true); setCommanderQuery(""); }}>Change</Btn></div>
              ) : (
                <>
                  <input className="mfield" value={commanderQuery} onChange={(e) => setCommanderQuery(e.target.value)} placeholder="Type a commander's name" aria-label="Commander" autoFocus />
                  {!catalogue && <p className="mnote">Loading cards…</p>}
                  {catalogue && commanderQuery.trim().length >= 2 && candidates.length === 0 && <p className="mnote">No legendary creature or commander matches "{commanderQuery.trim()}".</p>}
                  <div className="mcandidates">
                    {candidates.map((card) => (
                      <button key={card.name} type="button" onClick={() => { setCommander(card.name); setChoosing(false); }} aria-label={`Choose ${card.name} as commander`}>
                        <b>{card.name}</b><small>{card.typeLine}</small>
                      </button>
                    ))}
                  </div>
                </>
              )}
            </div>
            <p className="mnote strong">{reviewed ? DraftPresentation.gameCount(reviewed) : 0} main + commander cards</p>
            {unresolved.length > 0 && <p className="mnote warn">{unresolved.length} {unresolved.length === 1 ? "name" : "names"} not in this catalogue: {unresolved.slice(0, 6).join(", ")}{unresolved.length > 6 ? "…" : ""}</p>}
            {preview.annotations.length > 0 && (
              <details className="mimportnotes"><summary>{preview.annotations.length} {preview.annotations.length === 1 ? "note" : "notes"}</summary>
                {preview.annotations.map((note, i) => <p key={i} className="mnote">Line {note.line}: {note.text}</p>)}
              </details>
            )}
            {error && <p className="mnote warn" role="status">{error}</p>}
            <div className="mimportfoot">
              <Btn kind="secondary" onClick={() => { setPreview(undefined); setError(undefined); }}>Back</Btn>
              <Btn kind="primary" id="deckStudio.import.save" onClick={save}>Save deck</Btn>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
