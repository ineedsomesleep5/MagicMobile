import type { DeckEntry, DeckList, DeckParser } from "@magicmobile/shared";

const sectionHeaders: Record<string, DeckEntry["section"]> = {
  commander: "commander",
  commanders: "commander",
  deck: "deck",
  main: "deck",
  mainboard: "deck",
  sideboard: "sideboard",
  maybeboard: "maybeboard",
  considering: "maybeboard"
};

export const cleanCardName = (name: string): string => {
  let clean = name.trim();
  // Remove trailing Moxfield tags (e.g. #tag)
  clean = clean.replace(/#.*$/, "").trim();
  // Remove foil/alter/etc markers (e.g. *F*, *NF*, *A*)
  clean = clean.replace(/\*[^*]+\*/g, "").trim();
  // Remove category brackets (e.g. [Category])
  clean = clean.replace(/\[[^\]]+\]/g, "").trim();
  // Remove set codes and collector numbers like (2XM) 220 or (CMM) or (2XM) 220a
  clean = clean.replace(/\s*\([a-zA-Z0-9-]{2,6}\)(?:\s+\S+)?$/i, "").trim();
  // Also remove set codes in brackets like [2XM] 220
  clean = clean.replace(/\s*\[[a-zA-Z0-9-]{2,6}\](?:\s+\S+)?$/i, "").trim();
  return clean;
};

export class PastedDeckParser implements DeckParser {
  parse(input: string): DeckList {
    let currentSection: DeckEntry["section"] = "deck";
    const entries: DeckEntry[] = [];
    const errors: string[] = [];

    // Check for direct website scraping URL
    if (/https?:\/\//i.test(input) || /moxfield\.com/i.test(input) || /archidekt\.com/i.test(input)) {
      errors.push("Direct website scraping is not supported. Please paste the exported plain text of your deck list.");
    }

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
      let quantity = 1;
      let cardName = "";

      if (match) {
        quantity = Number.parseInt(match[1] ?? "1", 10);
        cardName = cleanCardName(match[2] ?? "");
      } else {
        cardName = cleanCardName(line);
      }

      if (quantity < 1 || !cardName) {
        continue;
      }

      entries.push({ cardName, quantity, section: currentSection });
    }

    if (entries.length === 0 && errors.length === 0) {
      errors.push("No valid card entries found in the pasted text.");
    }

    const deck: DeckList = {
      name: "Imported deck",
      entries
    };

    if (errors.length > 0) {
      deck.errors = errors;
    }

    const commander = entries.find((entry) => entry.section === "commander");
    if (commander) {
      deck.commander = commander;
    }

    return deck;
  }
}

