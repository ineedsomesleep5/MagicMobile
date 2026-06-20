import Link from "next/link";
import { Button } from "@magicmobile/ui";
import { PageHeader } from "@/components/PageHeader";
import { decks } from "@/lib/mock-data";

export default function DecksPage() {
  return (
    <>
      <PageHeader
        title="Decks"
        kicker="Commander library"
        actions={
          <Link href="/decks/new">
            <Button tone="primary">New Deck</Button>
          </Link>
        }
      />
      <section className="list" aria-label="Deck list">
        {decks.map((deck) => (
          <Link className="list-row" href={`/decks/${deck.id}`} key={deck.id}>
            <div>
              <h2>{deck.name}</h2>
              <p>{deck.commander} · Bracket {deck.bracket} · {deck.colors.join("")}</p>
            </div>
            <strong>{deck.games} games</strong>
          </Link>
        ))}
      </section>
    </>
  );
}
