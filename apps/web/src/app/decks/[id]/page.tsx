import { DeckEditorClient } from "../DeckEditorClient";

export default async function DeckDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <DeckEditorClient deckId={id} />;
}
