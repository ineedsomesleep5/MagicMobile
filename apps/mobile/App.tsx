import { useEffect, useState } from "react";
import { Image, SafeAreaView, ScrollView, StyleSheet, Text, TouchableOpacity, View } from "react-native";

interface MobileCard {
  name: string;
  imageUrl?: string;
}

interface ScryfallCard {
  name: string;
  image_uris?: {
    normal?: string;
    border_crop?: string;
  };
  card_faces?: Array<{
    image_uris?: {
      normal?: string;
      border_crop?: string;
    };
  }>;
}

const hand = ["Growth Spiral", "Hinterland Harbor", "Llanowar Elves", "Arboreal Grazer", "Time Wipe"];
const battlefield = ["Ezuri, Claw of Progress", "Hydroid Krasis", "Llanowar Elves", "Command Tower"];

export default function App() {
  const [cards, setCards] = useState<Record<string, MobileCard>>({});

  useEffect(() => {
    let cancelled = false;

    async function loadCards() {
      try {
        const names = [...battlefield, ...hand];
        const response = await fetch("https://api.scryfall.com/cards/collection", {
          method: "POST",
          headers: {
            Accept: "application/json",
            "Content-Type": "application/json",
            "User-Agent": "MagicMobile/0.1 mobile-development"
          },
          body: JSON.stringify({ identifiers: names.map((name) => ({ name })) })
        });
        const payload = (await response.json()) as { data?: ScryfallCard[] };
        const nextCards: Record<string, MobileCard> = Object.fromEntries(
          (payload.data ?? []).map((card) => {
            const imageUris = card.image_uris ?? card.card_faces?.find((face) => face.image_uris)?.image_uris;
            const imageUrl = imageUris?.normal ?? imageUris?.border_crop;
            return [card.name, imageUrl ? { name: card.name, imageUrl } : { name: card.name }];
          })
        );

        if (!cancelled) {
          setCards(nextCards);
        }
      } catch {
        if (!cancelled) {
          setCards({});
        }
      }
    }

    void loadCards();

    return () => {
      cancelled = true;
    };
  }, []);

  return (
    <SafeAreaView style={styles.safeArea}>
      <ScrollView horizontal contentContainerStyle={styles.landscapeScreen}>
        <View style={styles.table}>
          <View style={styles.topHud}>
            <PlayerBadge name="Noaddrag" life={20} />
            <Text style={styles.phase}>Combat</Text>
          </View>

          <View style={styles.boardRow}>
            {battlefield.map((name) => (
              <CardPreview card={cards[name] ?? { name }} key={name} />
            ))}
          </View>

          <View style={styles.centerRail}>
            <Text style={styles.railText}>Priority: TabletopPolish</Text>
            <TouchableOpacity style={styles.nextButton}>
              <Text style={styles.nextButtonText}>Next</Text>
            </TouchableOpacity>
          </View>

          <View style={styles.hand}>
            {hand.map((name) => (
              <CardPreview card={cards[name] ?? { name }} key={name} small />
            ))}
          </View>

          <View style={styles.bottomHud}>
            <PlayerBadge name="TabletopPolish" life={4} active />
            <Text style={styles.cardStatus}>{Object.keys(cards).length}/9 real card images</Text>
          </View>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

function PlayerBadge({ name, life, active = false }: { name: string; life: number; active?: boolean }) {
  return (
    <View style={styles.playerBadge}>
      <Text style={active ? styles.activeLife : styles.life}>{life}</Text>
      <Text style={styles.playerName}>{name}</Text>
    </View>
  );
}

function CardPreview({ card, small = false }: { card: MobileCard; small?: boolean }) {
  return (
    <View style={small ? styles.smallCard : styles.card}>
      {card.imageUrl ? (
        <Image accessibilityLabel={`${card.name} card`} source={{ uri: card.imageUrl }} style={styles.cardImage} />
      ) : (
        <Text style={styles.missingCardText}>{card.name}</Text>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: "#090d0e"
  },
  landscapeScreen: {
    minWidth: 920,
    flexGrow: 1
  },
  table: {
    flex: 1,
    minWidth: 920,
    minHeight: 520,
    justifyContent: "space-between",
    padding: 16,
    backgroundColor: "#111819"
  },
  topHud: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between"
  },
  bottomHud: {
    flexDirection: "row",
    alignItems: "flex-end",
    justifyContent: "space-between"
  },
  playerBadge: {
    gap: 4
  },
  life: {
    width: 48,
    height: 48,
    borderWidth: 2,
    borderColor: "#f5ecd8",
    borderRadius: 24,
    color: "#f5ecd8",
    fontSize: 22,
    fontWeight: "900",
    lineHeight: 44,
    textAlign: "center"
  },
  activeLife: {
    width: 48,
    height: 48,
    borderWidth: 2,
    borderColor: "#35c7ff",
    borderRadius: 24,
    color: "#f5ecd8",
    fontSize: 22,
    fontWeight: "900",
    lineHeight: 44,
    textAlign: "center"
  },
  playerName: {
    color: "#f5ecd8",
    fontWeight: "800"
  },
  phase: {
    color: "#ffb45d",
    fontSize: 18,
    fontWeight: "900",
    textTransform: "uppercase"
  },
  boardRow: {
    flexDirection: "row",
    justifyContent: "center",
    gap: 14
  },
  centerRail: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    gap: 16
  },
  railText: {
    color: "#d9d3c3",
    fontWeight: "800"
  },
  nextButton: {
    borderRadius: 999,
    backgroundColor: "#ff6b22",
    paddingHorizontal: 28,
    paddingVertical: 12
  },
  nextButtonText: {
    color: "#fff8e8",
    fontWeight: "900"
  },
  hand: {
    flexDirection: "row",
    justifyContent: "center",
    gap: 10
  },
  card: {
    width: 108,
    height: 151,
    overflow: "hidden",
    borderWidth: 2,
    borderColor: "#d8ccb3",
    borderRadius: 8,
    backgroundColor: "#1f2525"
  },
  smallCard: {
    width: 92,
    height: 129,
    overflow: "hidden",
    borderWidth: 2,
    borderColor: "#35c7ff",
    borderRadius: 8,
    backgroundColor: "#1f2525"
  },
  cardImage: {
    width: "100%",
    height: "100%"
  },
  missingCardText: {
    color: "#f5ecd8",
    padding: 8,
    fontWeight: "900",
    textAlign: "center"
  },
  cardStatus: {
    color: "#aeb7b3",
    fontWeight: "800"
  }
});
