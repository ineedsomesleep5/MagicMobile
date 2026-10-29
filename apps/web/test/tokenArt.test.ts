/** Token artwork (NativeAssetStore.matchTokenArtwork, NativeArtworkCatalogue.accept): the iOS tests' cases on the web port. */
import { describe, expect, it } from "vitest";
import { matchTokenArtwork, safeTokenSearchName, type TokenArtwork, tokenImage, tokenSearchQuery, tokensFromSearch } from "../src/core/tokenArt";

const token = (id: string, fields: Partial<TokenArtwork>): TokenArtwork => ({ id, name: "Zombie", images: { normal: `https://cards.scryfall.io/normal/${id}.jpg` }, ...fields });

describe("token artwork", () => {
  it("matches Oracle's self-reference wording to the engine's", () => {
    const treasure = token("t1", { name: "Treasure", typeLine: "Token Artifact — Treasure", oracleText: "{T}, Sacrifice this token: Add one mana of any color.", colors: [] });
    const identity = { name: "Treasure Token", typeLine: "Artifact — Treasure", oracleText: "{T}, Sacrifice this artifact: Add one mana of any color.", power: "0", toughness: "0", colors: [] };
    expect(matchTokenArtwork([treasure], identity)).toBe(treasure);
    expect(matchTokenArtwork([treasure], { ...identity, oracleText: "{T}, Sacrifice this artifact: Add {C}." })).toBeUndefined();
    const food = token("f1", { name: "Food", typeLine: "Token Artifact — Food", oracleText: "{2}, {T}, Sacrifice this token: You gain 3 life.", colors: [] });
    expect(matchTokenArtwork([food], { name: "Food Token", typeLine: "Artifact — Food", oracleText: "{2}, {T}, Sacrifice Food Token: You gain 3 life.",
      power: "0", toughness: "0", colors: [] })).toBe(food);
  });

  it("picks the exact printed size beside a variable one, and never a different token", () => {
    const zombie = token("b", { typeLine: "Token Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"] });
    const second = token("a", { typeLine: "Token Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"] });
    const variable = token("c", { typeLine: "Token Creature — Zombie", oracleText: "", power: "*", toughness: "*", colors: ["B"] });
    const identity = { name: "Zombie Token", typeLine: "Creature — Zombie", oracleText: "", power: "2", toughness: "2", colors: ["B"] };
    expect(matchTokenArtwork([zombie, variable, second], identity)).toBe(second);
    expect(matchTokenArtwork([zombie, variable], { ...identity, oracleText: "Decayed" })).toBeUndefined();
    // Pumped to 3/3: every printing is 2/2, so it is still that token; with a */* beside it, it is not decided.
    expect(matchTokenArtwork([zombie], { ...identity, power: "3", toughness: "3" })).toBe(zombie);
    expect(matchTokenArtwork([zombie, variable], { ...identity, power: "3", toughness: "3" })).toBeUndefined();
  });

  it("reads Scryfall rows: the front of a double-faced token, its back, only card images", () => {
    const rows = [
      { id: "d1", name: "Soldier // Angel", layout: "double_faced_token", card_faces: [
        { name: "Soldier", type_line: "Token Creature — Soldier", oracle_text: "Vigilance", power: "1", toughness: "1", colors: ["W"],
          image_uris: { normal: "https://cards.scryfall.io/normal/front/d1.jpg", art_crop: "https://evil.example/x.jpg" } },
        { name: "Angel", type_line: "Token Creature — Angel", oracle_text: "Flying", power: "4", toughness: "4", colors: ["W"], image_uris: { normal: "https://cards.scryfall.io/normal/back/d1.jpg" } },
      ] },
      { id: "x", name: "Not a token", layout: "normal" },
    ];
    const tokens = tokensFromSearch(rows);
    expect(tokens.map((t) => [t.name, t.face, t.power, t.images])).toEqual([
      ["Soldier", undefined, "1", { normal: "https://cards.scryfall.io/normal/front/d1.jpg" }],
      ["Angel", "back", "4", { normal: "https://cards.scryfall.io/normal/back/d1.jpg" }],
    ]);
    const soldier = matchTokenArtwork(tokens, { name: "Soldier Token", typeLine: "Creature — Soldier", oracleText: "Vigilance", power: "1", toughness: "1", colors: ["W"] })!;
    expect(tokenImage(tokens, soldier, "normal")).toBe("https://cards.scryfall.io/normal/front/d1.jpg");
    expect(tokenImage(tokens, soldier, "art_crop")).toBeUndefined();
  });

  it("searches only safe exact names", () => {
    expect(tokenSearchQuery("Zombie Token")).toBe("!\"Zombie\" t:token");
    expect([safeTokenSearchName("Zombie"), safeTokenSearchName("Bad\"name"), safeTokenSearchName("")]).toEqual([true, false, false]);
  });
});
