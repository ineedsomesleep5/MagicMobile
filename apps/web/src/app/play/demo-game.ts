import type { CommanderGameConfig, DeckList } from "@magicmobile/shared";

export const humanPlayerId = "human";
export const aiPlayerId = "ai-1";

export const arenaDemoCardNames = [
  "Ezuri, Claw of Progress",
  "Arboreal Grazer",
  "Island",
  "Forest",
  "Hydroid Krasis",
  "Growth Spiral",
  "Hinterland Harbor",
  "Llanowar Elves",
  "Time Wipe",
  "Mountain",
  "Sacred Foundry",
  "Swiftblade Vindicator",
  "Light of the Legion",
  "Battlefield Forge"
];

const arenaDemoDeck: DeckList = {
  name: "Arena Demo Commander",
  commander: { cardName: "Ezuri, Claw of Progress", quantity: 1, section: "commander" },
  entries: arenaDemoCardNames
    .filter((cardName) => cardName !== "Ezuri, Claw of Progress")
    .map((cardName) => ({ cardName, quantity: cardName === "Forest" ? 8 : 1, section: "deck" as const }))
};

export function createArenaDemoConfig(): CommanderGameConfig {
  return {
    roomId: "arena-demo",
    humanPlayerId,
    humanDeck: arenaDemoDeck,
    aiPlayers: [
      {
        playerId: aiPlayerId,
        displayName: "Noaddrag",
        difficulty: "normal",
        deck: arenaDemoDeck
      }
    ],
    startingLife: 40,
    commanderDamageEnabled: true,
    simulatorPreset: "arena-battlefield"
  };
}
