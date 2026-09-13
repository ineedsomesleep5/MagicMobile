package mage.cards.repository;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;
import mage.cards.ExpansionSet;
import mage.cards.Sets;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.Predicate;
import java.util.stream.Collectors;
import java.util.zip.GZIPInputStream;

/** Immutable, build-generated XMage metadata. No JDBC, writable database or service. */
public final class MobileCardCatalogue {
    private static final Gson GSON = new Gson();
    private static final String PREFIX = "/mage/mobile/";
    private MobileCardCatalogue() {}

    private static BufferedReader resource(String name) throws IOException {
        InputStream stream = MobileCardCatalogue.class.getResourceAsStream(PREFIX + name);
        if (stream == null) throw new IOException("Missing bundled XMage catalogue: " + name);
        try {
            return new BufferedReader(new InputStreamReader(new GZIPInputStream(stream), StandardCharsets.UTF_8));
        } catch (IOException failure) {
            stream.close();
            throw failure;
        }
    }

    private static final class Names {
        static final Map<String, Set<String>> VALUES = load();
        private static Map<String, Set<String>> load() {
            try (BufferedReader input = resource("card-names.json.gz")) {
                JsonObject document = JsonParser.parseReader(input).getAsJsonObject();
                if (document.get("format").getAsInt() != 1) throw new IOException("Unknown card-name format");
                Map<String, Set<String>> result = new HashMap<>();
                for (Map.Entry<String, JsonElement> entry : document.getAsJsonObject("names").entrySet()) {
                    Set<String> names = new TreeSet<>();
                    for (JsonElement value : entry.getValue().getAsJsonArray()) names.add(value.getAsString());
                    if (names.isEmpty()) throw new IOException("Empty card-name category: " + entry.getKey());
                    result.put(entry.getKey(), Collections.unmodifiableSet(names));
                }
                if (result.size() != 9) throw new IOException("Incomplete card-name categories");
                return Collections.unmodifiableMap(result);
            } catch (IOException failure) { throw new IllegalStateException("Cannot load XMage card names", failure); }
        }
    }

    public static Set<String> names(String category) {
        Set<String> names = Names.VALUES.get(category);
        if (names == null) throw new IllegalArgumentException("Unknown card-name category: " + category);
        // Upstream choices may mutate their set; they must not mutate the bundled catalogue.
        return new TreeSet<>(names);
    }

    private static final class Rows {
        static final List<CardInfo> VALUES = load();
        static final Field[] FIELDS = Arrays.stream(CardInfo.class.getDeclaredFields())
                .filter(field -> !Modifier.isStatic(field.getModifiers())).toArray(Field[]::new);
        static {
            for (Field field : FIELDS) {
                if (!field.getType().isPrimitive() && field.getType() != String.class && !field.getType().isEnum())
                    throw new IllegalStateException("Review mutable catalogue field: " + field.getName());
                field.setAccessible(true);
            }
        }
        private static List<CardInfo> load() {
            try (BufferedReader input = resource("card-metadata.jsonl.gz")) {
                JsonObject header = JsonParser.parseString(input.readLine()).getAsJsonObject();
                if (header.get("format").getAsInt() != 1) throw new IOException("Unknown card metadata format");
                int expected = header.get("rows").getAsInt();
                if (expected <= 0) throw new IOException("Empty card metadata inventory");
                List<CardInfo> result = new ArrayList<>(expected);
                for (String line; (line = input.readLine()) != null;) {
                    CardInfo row = GSON.fromJson(line, CardInfo.class);
                    if (row == null || row.name == null || row.setCode == null || row.cardNumber == null
                            || row.className == null || row.rarity == null)
                        throw new IOException("Incomplete card metadata row");
                    result.add(row);
                }
                if (result.size() != expected) throw new IOException("Incomplete card metadata inventory");
                return Collections.unmodifiableList(result);
            } catch (IOException failure) { throw new IllegalStateException("Cannot load XMage card metadata", failure); }
        }
    }

    private static CardInfo copy(CardInfo row) {
        CardInfo result = new CardInfo();
        try {
            for (Field field : Rows.FIELDS) field.set(result, field.get(row));
        } catch (IllegalAccessException failure) { throw new IllegalStateException("Cannot copy catalogue metadata", failure); }
        return result;
    }
    private static List<CardInfo> copies(List<CardInfo> rows) {
        return rows.stream().map(MobileCardCatalogue::copy).collect(Collectors.toList());
    }
    private static boolean same(String left, String right) {
        return left != null && right != null && left.equalsIgnoreCase(right); // H2 IGNORECASE=TRUE
    }
    private static List<CardInfo> select(Predicate<CardInfo> predicate, long limit) {
        return Rows.VALUES.stream().filter(predicate).limit(limit > 0 ? limit : Long.MAX_VALUE)
                .collect(Collectors.toList());
    }

    public static CardInfo printing(String set, String number, boolean ignoreNight) {
        List<CardInfo> selected = select(row -> same(row.setCode, set) && same(row.cardNumber, number)
                && (!ignoreNight || !row.nightCard), 0);
        selected.sort(Comparator.comparing(row -> row.nightCard));
        return selected.isEmpty() ? null : copy(selected.get(0));
    }
    public static List<String> classNames() {
        return Rows.VALUES.stream().map(CardInfo::getClassName).collect(Collectors.toList());
    }
    public static List<CardInfo> missing(List<String> names) {
        Set<String> excluded = new TreeSet<>(String.CASE_INSENSITIVE_ORDER);
        excluded.addAll(names);
        return copies(select(row -> !excluded.contains(row.className), 0));
    }
    public static List<CardInfo> byClass(String name) {
        return copies(select(row -> same(row.className, name), 0));
    }
    public static List<CardInfo> find(CardCriteria criteria) {
        return copies(MobileCardCriteria.find(Rows.VALUES, criteria));
    }
    public static List<CardInfo> find(String name, long limit, boolean returnSplitHalf) {
        Objects.requireNonNull(name);
        List<CardInfo> result = select(row -> same(row.name, name), limit);
        if (name.contains(" // ")) {
            if (result.isEmpty()) {
                String front = name.split(" // ", 2)[0];
                result = select(row -> same(row.name, front), limit);
            }
        } else if (result.isEmpty()) {
            result = select(row -> same(row.flipCardName, name) || same(row.secondSideName, name)
                    || same(row.spellOptionCardName, name) || same(row.doubleFacedSecondSideName, name), limit);
        } else if (result.get(0).splitCardHalf && !returnSplitHalf) {
            CardInfo first = result.get(0);
            List<CardInfo> parents = select(row -> same(row.setCode, first.setCode)
                    && same(row.cardNumber, first.cardNumber) && row.splitCard, 1);
            if (parents.isEmpty()) return new ArrayList<>();
            result = select(row -> same(row.name, parents.get(0).name), limit);
        }
        return copies(result);
    }

    private static Collection<ExpansionSet> registeredSets() {
        Collection<ExpansionSet> sets = Sets.getInstance().values();
        if (sets.isEmpty()) throw new IllegalStateException("Generated XMage set registry was not installed");
        return sets;
    }
    public static List<ExpansionInfo> sets() {
        return registeredSets().stream().map(ExpansionInfo::new)
                .sorted(Comparator.comparing(ExpansionInfo::getReleaseDate)).collect(Collectors.toList());
    }
    public static List<String> setCodes() {
        return registeredSets().stream().map(ExpansionSet::getCode).collect(Collectors.toList());
    }
    public static ExpansionInfo set(String value, boolean byName) {
        return registeredSets().stream().filter(set -> same(byName ? set.getName() : set.getCode(), value))
                .findFirst().map(ExpansionInfo::new).orElse(null);
    }
    public static List<ExpansionInfo> blockSets(String block) {
        return sets().stream().filter(set -> same(set.getBlockName(), block)).collect(Collectors.toList());
    }
    public static List<ExpansionInfo> basicLandSets() {
        return sets().stream().filter(ExpansionInfo::hasBasicLands)
                .sorted(Comparator.comparing(ExpansionInfo::getReleaseDate).reversed()).collect(Collectors.toList());
    }
    public static ExpansionInfo[] boosterSets() {
        return registeredSets().stream().filter(set -> set.hasBoosters() && !set.getSetCardInfo().isEmpty())
                .map(ExpansionInfo::new).sorted(Comparator.comparing(ExpansionInfo::getReleaseDate).reversed())
                .toArray(ExpansionInfo[]::new);
    }
}
