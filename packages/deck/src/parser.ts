import type { DeckEntry, DeckList, DeckParser } from "@magicmobile/shared";

const sectionHeaders: Record<string, DeckEntry["section"]> = {
  commander: "commander",
  commanders: "commander",
  deck: "deck",
  mainboard: "deck",
  sideboard: "sideboard",
  maybeboard: "maybeboard"
};

const cleanCardName = (name: string): string =>
  name
    .replace(/\s+\([A-Z0-9]{2,5}\)\s+\d+[a-z]?$/i, "")
    .replace(/\s+\[[^\]]+\]$/i, "")
    .trim();

export class PastedDeckParser implements DeckParser {
  parse(input: string): DeckList {
    let currentSection: DeckEntry["section"] = "deck";
    const entries: DeckEntry[] = [];

    for (const rawLine of input.split(/\r?\n/)) {
      const line = rawLine.trim();
      if (!line || line.startsWith("#") || line.startsWith("//")) {
        continue;
      }

      const normalizedHeader = line.replace(/:$/, "").trim().toLowerCase();
      const nextSection = sectionHeaders[normalizedHeader];
      if (nextSection) {
        currentSection = nextSection;
        continue;
      }

      const match = line.match(/^(\d+)\s*x?\s+(.+)$/i);
      if (!match) {
        continue;
      }

      const quantity = Number.parseInt(match[1] ?? "0", 10);
      const cardName = cleanCardName(match[2] ?? "");
      if (quantity < 1 || !cardName) {
        continue;
      }

      entries.push({ cardName, quantity, section: currentSection });
    }

    const deck: DeckList = {
      name: "Imported deck",
      entries
    };
    const commander = entries.find((entry) => entry.section === "commander");

    if (commander) {
      deck.commander = commander;
    }

    return deck;
  }
}
