import com.google.gson.*;
import mage.cards.repository.CardCriteria;
import mage.cards.repository.CardInfo;
import mage.cards.repository.MobileCardCatalogue;
import mage.constants.CardType;
import mage.constants.Rarity;
import java.nio.file.*;
import java.util.*;

/** Real metadata dependency probe only: no factories, engine startup or game acceptance. */
public final class CardCatalogueProbe {
    private static final Gson GSON = new Gson();
    private static void check(boolean value, String label) {
        if (!value) throw new AssertionError(label);
    }
    private static void rows(List<CardInfo> actual, JsonArray expected, String label) {
        check(GSON.toJsonTree(actual).equals(expected), label);
        System.out.println("PASS " + label + " rows=" + actual.size());
    }
    public static void main(String[] args) throws Exception {
        check(!Files.exists(Path.of("db")), "isolated working directory required");
        JsonObject expected;
        try (java.io.Reader reader = Files.newBufferedReader(Path.of(args[0]))) {
            expected = JsonParser.parseReader(reader).getAsJsonObject();
        }
        for (Map.Entry<String, JsonElement> category : expected.getAsJsonObject("names").entrySet()) {
            Set<String> names = new TreeSet<>();
            category.getValue().getAsJsonArray().forEach(value -> names.add(value.getAsString()));
            Set<String> actual = MobileCardCatalogue.names(category.getKey());
            check(actual.equals(names), "exact exported names: " + category.getKey());
            actual.clear();
            check(MobileCardCatalogue.names(category.getKey()).equals(names), "names defensive copy");
            System.out.println("PASS " + category.getKey() + " names=" + names.size());
        }
        try {
            MobileCardCatalogue.names("missing-category");
            throw new AssertionError("unknown category accepted");
        } catch (IllegalArgumentException correct) { }
        JsonObject lookups = expected.getAsJsonObject("lookups");
        for (Map.Entry<String, JsonElement> lookup : lookups.entrySet()) {
            boolean half = lookup.getKey().equals("Fire");
            rows(MobileCardCatalogue.find(lookup.getKey(), 0, half), lookup.getValue().getAsJsonArray(), lookup.getKey());
        }
        rows(MobileCardCatalogue.find("Fire", 0, false), lookups.getAsJsonArray("Fire // Ice"), "split parent");
        rows(MobileCardCatalogue.find("pItHiNg NeEdLe", 1, false),
                expected.getAsJsonArray("needleOne"), "case insensitive limit");
        JsonObject printing = expected.getAsJsonObject("printing");
        String set = printing.get("setCode").getAsString().toLowerCase(Locale.ROOT);
        String number = printing.get("cardNumber").getAsString();
        CardInfo card = MobileCardCatalogue.printing(set, number, true);
        check(GSON.toJsonTree(card).equals(printing), "exact printing fields and enum");
        card.setTypes(List.of(CardType.CREATURE));
        check(GSON.toJsonTree(MobileCardCatalogue.printing(set, number, true)).equals(printing), "printing defensive copy");
        check(MobileCardCatalogue.printing("MISSING", "-1", false) == null, "absent printing");
        CardCriteria criteria = new CardCriteria().name("island").types(CardType.LAND);
        List<CardInfo> islands = MobileCardCatalogue.find(criteria);
        rows(islands, expected.getAsJsonArray("islands"), "name and land criteria");
        check(!islands.isEmpty(), "island inventory");
        islands.get(0).setTypes(List.of(CardType.ARTIFACT));
        islands.clear();
        rows(MobileCardCatalogue.find(criteria), expected.getAsJsonArray("islands"), "criteria defensive copy");
        rows(MobileCardCatalogue.find(new CardCriteria().rarities(Rarity.MYTHIC)
                .setOrderBy("name").start(1L).count(3L)), expected.getAsJsonArray("mythics"), "rarity sorted pagination");
        check(MobileCardCatalogue.classNames().size() == expected.get("rows").getAsInt(), "full metadata row count");
        check(!Files.exists(Path.of("db")), "no desktop database created");
        System.out.println("PASS real catalogue dependency regression; no engine or device acceptance");
    }
}
