import { SafeAreaView, ScrollView, StyleSheet, Text, TextInput, TouchableOpacity, View } from "react-native";

const decks = [
  { name: "Rhys Wide Table", commander: "Rhys the Redeemed", bracket: 3 },
  { name: "Mizzix Storm Lessons", commander: "Mizzix of the Izmagnus", bracket: 4 }
];

export default function App() {
  return (
    <SafeAreaView style={styles.safeArea}>
      <ScrollView contentContainerStyle={styles.screen}>
        <View style={styles.header}>
          <Text style={styles.title}>MagicMobile</Text>
          <Text style={styles.subtitle}>Commander tables from your phone.</Text>
        </View>

        <View style={styles.panel}>
          <Text style={styles.panelTitle}>Login placeholder</Text>
          <TextInput placeholder="Display name" placeholderTextColor="#7c8176" style={styles.input} />
          <TouchableOpacity style={styles.primaryButton}>
            <Text style={styles.primaryButtonText}>Continue Locally</Text>
          </TouchableOpacity>
        </View>

        <View style={styles.panel}>
          <Text style={styles.panelTitle}>Decks</Text>
          {decks.map((deck) => (
            <View key={deck.name} style={styles.deckRow}>
              <View>
                <Text style={styles.deckName}>{deck.name}</Text>
                <Text style={styles.muted}>{deck.commander}</Text>
              </View>
              <Text style={styles.bracket}>B{deck.bracket}</Text>
            </View>
          ))}
        </View>

        <View style={styles.room}>
          <Text style={styles.panelTitle}>Game room placeholder</Text>
          <Text style={styles.muted}>Room join, realtime seats, and engine state connect in later workstreams.</Text>
          <View style={styles.cameraSeat}>
            <Text style={styles.cameraText}>Phone camera seat</Text>
          </View>
          <TouchableOpacity style={styles.secondaryButton}>
            <Text style={styles.secondaryButtonText}>Open Camera Seat Stub</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  safeArea: {
    flex: 1,
    backgroundColor: "#f7f3ea"
  },
  screen: {
    gap: 16,
    padding: 18
  },
  header: {
    gap: 6
  },
  title: {
    color: "#182119",
    fontSize: 38,
    fontWeight: "900",
    letterSpacing: 0
  },
  subtitle: {
    color: "#657060",
    fontSize: 16
  },
  panel: {
    gap: 12,
    borderColor: "#d8d2c4",
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: "#fffdf8",
    padding: 16
  },
  panelTitle: {
    color: "#182119",
    fontSize: 20,
    fontWeight: "800"
  },
  input: {
    minHeight: 48,
    borderColor: "#d8d2c4",
    borderRadius: 8,
    borderWidth: 1,
    paddingHorizontal: 12,
    color: "#182119"
  },
  primaryButton: {
    alignItems: "center",
    borderRadius: 8,
    backgroundColor: "#2f6b42",
    padding: 14
  },
  primaryButtonText: {
    color: "#ffffff",
    fontWeight: "800"
  },
  deckRow: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    borderTopColor: "#d8d2c4",
    borderTopWidth: 1,
    paddingTop: 12
  },
  deckName: {
    color: "#182119",
    fontSize: 16,
    fontWeight: "800"
  },
  muted: {
    color: "#657060",
    lineHeight: 20
  },
  bracket: {
    color: "#2f6b42",
    fontWeight: "900"
  },
  room: {
    gap: 12,
    borderColor: "#b9852b",
    borderRadius: 8,
    borderWidth: 1,
    backgroundColor: "#fffdf8",
    padding: 16
  },
  cameraSeat: {
    minHeight: 170,
    alignItems: "center",
    justifyContent: "center",
    borderRadius: 8,
    backgroundColor: "#9a3d2f"
  },
  cameraText: {
    color: "#ffffff",
    fontSize: 18,
    fontWeight: "900"
  },
  secondaryButton: {
    alignItems: "center",
    borderColor: "#d8d2c4",
    borderRadius: 8,
    borderWidth: 1,
    padding: 14
  },
  secondaryButtonText: {
    color: "#182119",
    fontWeight: "800"
  }
});
