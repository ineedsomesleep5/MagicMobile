"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import type { SavedDeck } from "@magicmobile/shared";

export function DeckLibraryClient() {
  const [decks, setDecks] = useState<SavedDeck[]>([]);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");
  const [message, setMessage] = useState<string>();

  const loadDecks = useCallback(async () => {
    setStatus("loading");
    setMessage(undefined);
    try {
      const response = await fetch("/api/decks", { cache: "no-store" });
      const body = await response.json() as { decks?: SavedDeck[]; error?: string };
      if (!response.ok) throw new Error(body.error ?? "Deck library could not be loaded.");
      setDecks(body.decks ?? []);
      setStatus("ready");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Deck library could not be loaded.");
      setStatus("error");
    }
  }, []);

  useEffect(() => { void loadDecks(); }, [loadDecks]);

  const deleteDeck = async (deck: SavedDeck) => {
    if (!window.confirm(`Delete ${deck.name}? This cannot be undone.`)) return;
    const response = await fetch(`/api/decks/${encodeURIComponent(deck.id)}`, { method: "DELETE" });
    if (response.ok) {
      setDecks((current) => current.filter((candidate) => candidate.id !== deck.id));
      return;
    }
    const body = await response.json().catch(() => ({})) as { error?: string };
    setMessage(body.error ?? "Deck could not be deleted.");
  };

  return (
    <section className="cloud-decks-screen">
      <header className="cloud-page-header">
        <div>
          <p>Commander library</p>
          <h1>Your decks</h1>
          <span>Build once, then play from web or iPhone.</span>
        </div>
        <Link className="home-button home-button-primary" href="/decks/new">Create or import</Link>
      </header>

      {status === "loading" ? <DeckStatus title="Opening your library…" detail="Checking your cloud collection." /> : null}
      {status === "error" ? (
        <DeckStatus title="Your library is not available" detail={message ?? "Sign in or configure Supabase to continue."}>
          <button className="home-button" type="button" onClick={() => void loadDecks()}>Try again</button>
          <Link className="home-button" href="/account">Sign in</Link>
        </DeckStatus>
      ) : null}
      {status === "ready" && decks.length === 0 ? (
        <DeckStatus title="Start your first spellbook" detail="Paste a list, upload a file, or import a public Archidekt or Moxfield deck.">
          <Link className="home-button home-button-primary" href="/decks/new">Add a deck</Link>
        </DeckStatus>
      ) : null}

      {status === "ready" && decks.length > 0 ? (
        <div className="cloud-deck-grid" aria-label="Deck library">
          {decks.map((deck) => {
            const count = deck.entries.reduce((total, entry) => total + entry.quantity, 0);
            return (
              <article className="cloud-deck-card" key={deck.id}>
                <Link href={`/decks/${deck.id}`}>
                  <span className="cloud-deck-rune" aria-hidden="true">✦</span>
                  <small>{deck.source.kind} · revision {deck.revision}</small>
                  <h2>{deck.name}</h2>
                  <p>{deck.commander?.cardName ?? "Commander not selected"}</p>
                  <div><strong>{count}</strong><span>cards</span></div>
                </Link>
                <button type="button" onClick={() => void deleteDeck(deck)}>Delete</button>
              </article>
            );
          })}
        </div>
      ) : null}
    </section>
  );
}

function DeckStatus({ title, detail, children }: { title: string; detail: string; children?: React.ReactNode }) {
  return (
    <div className="cloud-deck-status" role="status">
      <span aria-hidden="true">✧</span>
      <h2>{title}</h2>
      <p>{detail}</p>
      {children ? <div className="home-actions">{children}</div> : null}
    </div>
  );
}
