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
    if (looksLikeCsv(input)) {
      return parseCsvDeck(input);
    }

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

const looksLikeCsv = (input: string): boolean => {
  const firstLine = input.split(/\r?\n/, 1)[0]?.toLowerCase() ?? "";
  return firstLine.includes(",") && /(?:quantity|qty|count)/.test(firstLine) && /(?:card|name)/.test(firstLine);
};

const parseCsvLine = (line: string): string[] => {
  const values: string[] = [];
  let current = "";
  let quoted = false;
  for (let index = 0; index < line.length; index += 1) {
    const character = line[index];
    if (character === '"') {
      if (quoted && line[index + 1] === '"') {
        current += '"';
        index += 1;
      } else {
        quoted = !quoted;
      }
    } else if (character === "," && !quoted) {
      values.push(current.trim());
      current = "";
    } else {
      current += character;
    }
  }
  values.push(current.trim());
  return values;
};

const csvSection = (value: string | undefined): DeckEntry["section"] => {
  const normalized = value?.trim().toLowerCase() ?? "";
  if (normalized.includes("commander")) return "commander";
  if (normalized.includes("side")) return "sideboard";
  if (normalized.includes("maybe") || normalized.includes("consider")) return "maybeboard";
  return "deck";
};

export const parseCsvDeck = (input: string): DeckList => {
  const lines = input.split(/\r?\n/).filter((line) => line.trim().length > 0);
  const headers = parseCsvLine(lines[0] ?? "").map((header) => header.toLowerCase());
  const quantityIndex = headers.findIndex((header) => ["quantity", "qty", "count"].includes(header));
  const nameIndex = headers.findIndex((header) => ["card", "card name", "name"].includes(header));
  const sectionIndex = headers.findIndex((header) => ["section", "board", "category"].includes(header));
  if (quantityIndex < 0 || nameIndex < 0) {
    return { name: "Imported deck", entries: [], errors: ["CSV must contain quantity and card name columns."] };
  }

  const entries = lines.slice(1).flatMap((line): DeckEntry[] => {
    const values = parseCsvLine(line);
    const quantity = Number.parseInt(values[quantityIndex] ?? "", 10);
    const cardName = cleanCardName(values[nameIndex] ?? "");
    if (!Number.isFinite(quantity) || quantity < 1 || !cardName) return [];
    return [{ cardName, quantity, section: csvSection(values[sectionIndex]) }];
  });
  const deck: DeckList = { name: "Imported deck", entries };
  const commander = entries.find((entry) => entry.section === "commander");
  if (commander) deck.commander = commander;
  if (entries.length === 0) deck.errors = ["No valid card entries found in the CSV file."];
  return deck;
};
