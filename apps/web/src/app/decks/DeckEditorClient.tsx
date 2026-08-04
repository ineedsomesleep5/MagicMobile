"use client";

import Link from "next/link";
import { useEffect, useMemo, useRef, useState } from "react";
import { PastedDeckParser } from "@magicmobile/deck";
import type { SavedDeck } from "@magicmobile/shared";

const exampleList = "Commander\n1 Atraxa, Praetors' Voice\n\nDeck\n1 Sol Ring\n1 Command Tower";

export function DeckEditorClient({ deckId }: { deckId?: string }) {
  const [name, setName] = useState("Untitled spellbook");
  const [rawList, setRawList] = useState("");
  const [sourceURL, setSourceURL] = useState("");
  const [revision, setRevision] = useState<number>();
  const [status, setStatus] = useState<"ready" | "loading" | "saving" | "error" | "saved">(deckId ? "loading" : "ready");
  const [message, setMessage] = useState<string>();
  const fileInput = useRef<HTMLInputElement>(null);
  const parsed = useMemo(() => rawList.trim() ? new PastedDeckParser().parse(rawList) : undefined, [rawList]);
  const count = parsed?.entries.reduce((total, entry) => total + entry.quantity, 0) ?? 0;

  useEffect(() => {
    if (!deckId) return;
    let active = true;
    void fetch(`/api/decks/${encodeURIComponent(deckId)}`, { cache: "no-store" })
      .then(async (response) => {
        const body = await response.json() as { deck?: SavedDeck; error?: string };
        if (!response.ok || !body.deck) throw new Error(body.error ?? "Deck could not be opened.");
        return body.deck;
      })
      .then((deck) => {
        if (!active) return;
        setName(deck.name);
        setRevision(deck.revision);
        setRawList(serializeDeckList(deck));
        setStatus("ready");
      })
      .catch((error) => {
        if (!active) return;
        setMessage(error instanceof Error ? error.message : "Deck could not be opened.");
        setStatus("error");
      });
    return () => { active = false; };
  }, [deckId]);

  const save = async () => {
    if (!parsed || parsed.errors?.length || parsed.entries.length === 0) {
      setMessage(parsed?.errors?.[0] ?? "Add at least one card before saving.");
      setStatus("error");
      return;
    }
    setStatus("saving");
    setMessage(undefined);
    const endpoint = deckId ? `/api/decks/${encodeURIComponent(deckId)}` : "/api/decks";
    const body = {
      name: name.trim(),
      entries: parsed.entries,
      commander: parsed.commander,
      rawList,
      ...(deckId ? { revision } : {})
    };
    const response = await fetch(endpoint, {
      method: deckId ? "PUT" : "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    });
    const result = await response.json().catch(() => ({})) as { deck?: SavedDeck; error?: string };
    if (!response.ok || !result.deck) {
      setMessage(result.error ?? "Deck could not be saved.");
      setStatus("error");
      return;
    }
    setRevision(result.deck.revision);
    setStatus("saved");
    if (!deckId) window.location.assign(`/decks/${result.deck.id}`);
  };

  const importURL = async () => {
    if (!sourceURL.trim()) return;
    setStatus("saving");
    setMessage(undefined);
    const response = await fetch("/api/decks/import", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ name: name.trim(), sourceURL: sourceURL.trim() })
    });
    const result = await response.json().catch(() => ({})) as { deck?: SavedDeck; error?: string };
    if (!response.ok || !result.deck) {
      setMessage(result.error ?? "Deck URL could not be imported.");
      setStatus("error");
      return;
    }
    window.location.assign(`/decks/${result.deck.id}`);
  };

  const openFile = async (file?: File) => {
    if (!file) return;
    if (!/\.(txt|dec|csv)$/i.test(file.name)) {
      setMessage("Choose a .txt, .dec, or .csv deck export.");
      setStatus("error");
      return;
    }
    if (file.size > 2 * 1024 * 1024) {
      setMessage("Deck files must be smaller than 2 MB.");
      setStatus("error");
      return;
    }
    setRawList(await file.text());
    if (name === "Untitled spellbook") setName(file.name.replace(/\.(txt|dec|csv)$/i, ""));
    setStatus("ready");
  };

  return (
    <section className="cloud-editor-screen">
      <header className="cloud-editor-header">
        <Link href="/decks">← Library</Link>
        <div>
          <p>{deckId ? "Edit spellbook" : "New spellbook"}</p>
          <input aria-label="Deck name" value={name} maxLength={100} onChange={(event) => setName(event.target.value)} />
        </div>
        <button className="home-button home-button-primary" type="button" disabled={status === "saving" || status === "loading" || !name.trim() || !parsed?.entries.length} onClick={() => void save()}>
          {status === "saving" ? "Saving…" : status === "saved" ? "Saved" : "Save deck"}
        </button>
      </header>

      <div className="cloud-editor-layout">
        <aside className="cloud-import-panel">
          <p className="home-eyebrow">Bring your deck</p>
          <h2>Import in seconds</h2>
          <label>Public Archidekt or Moxfield URL<input value={sourceURL} onChange={(event) => setSourceURL(event.target.value)} placeholder="https://www.moxfield.com/decks/…" /></label>
          <button className="home-button" type="button" disabled={!sourceURL.trim() || status === "saving"} onClick={() => void importURL()}>Import URL</button>
          <div className="cloud-divider"><span>or</span></div>
          <input ref={fileInput} hidden type="file" accept=".txt,.dec,.csv,text/plain,text/csv" onChange={(event) => void openFile(event.target.files?.[0])} />
          <button className="home-button" type="button" onClick={() => fileInput.current?.click()}>Choose deck file</button>
          <p className="cloud-help">Supported: .txt, .dec, and .csv up to 2 MB.</p>
        </aside>

        <main className="cloud-list-editor">
          <div className="cloud-editor-summary">
            <span><strong>{count}</strong> / 100 cards</span>
            <span>{parsed?.commander?.cardName ?? "No commander section"}</span>
          </div>
          <label htmlFor="deck-list">Deck list</label>
          <textarea id="deck-list" value={rawList} onChange={(event) => { setRawList(event.target.value); setStatus("ready"); }} placeholder={exampleList} spellCheck={false} />
          {parsed?.errors?.map((error) => <p className="cloud-error" key={error}>{error}</p>)}
          {message ? <p className={status === "saved" ? "cloud-success" : "cloud-error"} role="alert">{message}</p> : null}
        </main>

        <aside className="cloud-card-list">
          <p className="home-eyebrow">Live preview</p>
          <h2>Cards</h2>
          {parsed?.entries.length ? parsed.entries.map((entry, index) => (
            <div key={`${entry.section}-${entry.cardName}-${index}`}>
              <span>{entry.quantity}</span><strong>{entry.cardName}</strong><small>{entry.section}</small>
            </div>
          )) : <p className="cloud-help">Paste a list to preview it here.</p>}
        </aside>
      </div>
    </section>
  );
}

function serializeDeckList(deck: SavedDeck): string {
  const labels: Record<string, string> = {
    commander: "Commander",
    deck: "Deck",
    sideboard: "Sideboard",
    maybeboard: "Maybeboard"
  };
  const sections = ["commander", "deck", "sideboard", "maybeboard"] as const;
  return sections.flatMap((section) => {
    const entries = deck.entries.filter((entry) => entry.section === section);
    return entries.length
      ? [labels[section] ?? section, ...entries.map((entry) => `${entry.quantity} ${entry.cardName}`), ""]
      : [];
  }).join("\n").trim();
}
