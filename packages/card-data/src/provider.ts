import type { CardDataProvider } from "@magicmobile/shared";
import type { MagicMobileCard } from "./models";
import { seedCards } from "./seed";

const normalizeName = (name: string) => name.trim().toLowerCase();

export class SeedCardDataProvider implements CardDataProvider {
  private readonly cards: MagicMobileCard[];

  constructor(cards: MagicMobileCard[] = seedCards) {
    this.cards = cards;
  }

  async searchCards(query: string): Promise<MagicMobileCard[]> {
    const normalizedQuery = normalizeName(query);
    return this.cards.filter((card) => normalizeName(card.name).includes(normalizedQuery));
  }

  async getCardByName(name: string): Promise<MagicMobileCard | undefined> {
    const normalizedName = normalizeName(name);
    return this.cards.find((card) => normalizeName(card.name) === normalizedName);
  }

  async getSeedCards(): Promise<MagicMobileCard[]> {
    return [...this.cards];
  }
}
