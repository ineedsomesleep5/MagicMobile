/**
 * Which printing's art a card shows (iOS CardArtChoices.swift, Android CardArtChoices): the player picks it per deck row in
 * Deck Studio, and everywhere a card is drawn by name the choice is found here. The playing deck's choices come first, then
 * those of the saved decks, the most recently saved first. A card the playing deck holds keeps its default art when that
 * row has no choice, whatever other decks chose.
 */
import type { DeckLibraryRecord, LibraryEntry } from "./deckStudio/library";

export interface ChosenPrinting { setCode: string; collectorNumber: string }

export const artKey = (name: string) => name.split(" // ")[0].trim().toLowerCase();

export function chosenPrintings(decks: readonly DeckLibraryRecord[], playingID?: string): Map<string, ChosenPrinting> {
  const ordered = [...decks].sort((a, b) => b.updatedAt - a.updatedAt);
  const index = playingID === undefined ? -1 : ordered.findIndex((d) => d.id === playingID);
  if (index > 0) ordered.unshift(...ordered.splice(index, 1));
  const chosen = new Map<string, ChosenPrinting>();
  const decided = new Set<string>();
  ordered.forEach((deck, position) => {
    const playing = position === 0 && deck.id === playingID;
    const held = new Set<string>();
    for (const entry of [...(deck.commander ? [deck.commander] : []), ...deck.entries] as LibraryEntry[]) {
      const key = artKey(entry.cardName);
      if (decided.has(key)) continue;
      held.add(key);
      if (entry.setCode && entry.collectorNumber && !chosen.has(key)) {
        chosen.set(key, { setCode: entry.setCode, collectorNumber: entry.collectorNumber });
      }
    }
    for (const key of held) if (playing || chosen.has(key)) decided.add(key);
  });
  return chosen;
}
