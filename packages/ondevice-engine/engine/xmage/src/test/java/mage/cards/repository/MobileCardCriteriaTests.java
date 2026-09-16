package mage.cards.repository;

import com.j256.ormlite.dao.Dao;
import com.j256.ormlite.dao.DaoManager;
import com.j256.ormlite.field.DatabaseField;
import com.j256.ormlite.jdbc.JdbcConnectionSource;
import com.j256.ormlite.stmt.QueryBuilder;
import com.j256.ormlite.table.TableUtils;
import mage.cards.Card;
import mage.cards.CardGraphicInfo;
import mage.cards.CardSetInfo;
import mage.cards.FrameStyle;
import mage.cards.a.AzoriusCharm;
import mage.cards.b.BalaGedRecovery;
import mage.cards.b.BriselaVoiceOfNightmares;
import mage.cards.basiclands.Forest;
import mage.cards.d.DelverOfSecrets;
import mage.cards.f.FireIce;
import mage.cards.g.GrizzlyBears;
import mage.cards.i.IsamaruHoundOfKonda;
import mage.cards.l.LightningBolt;
import mage.cards.m.Memnite;
import mage.cards.m.Murder;
import mage.cards.s.SnowCoveredForest;
import mage.constants.CardType;
import mage.constants.Rarity;
import mage.constants.SubType;
import mage.constants.SuperType;

import java.lang.reflect.Field;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;
import java.util.function.Supplier;

/**
 * Standalone oracle tests. Only a private, temporary in-memory H2 database is opened.
 * The oracle uses the pinned CardCriteria.buildQuery and ORM mapping directly; no repositories.
 * Main must first compile the generated mobile CardCriteria with its getNightCard() accessor.
 * Compile both owned files with javac -J-Xmx256m --release 8 -cp "$CP" -d "$TEST_CLASSES";
 * run java -Xmx256m -Djava.awt.headless=true -cp "$TEST_CLASSES:$CP"
 * mage.cards.repository.MobileCardCriteriaTests. No native or full-engine build is needed.
 */
public final class MobileCardCriteriaTests {
    private static final UUID OWNER = UUID.fromString("00000000-0000-0000-0000-000000000001");
    private static int checked;

    public static void main(String[] args) throws Exception {
        List<CardInfo> rows = cards();
        List<CardInfo> originalOrder = new ArrayList<>(rows);
        try (JdbcConnectionSource connection = new JdbcConnectionSource(
                "jdbc:h2:mem:mobile_criteria_" + UUID.randomUUID() + ";IGNORECASE=TRUE")) {
            TableUtils.createTable(connection, CardInfo.class);
            Dao<CardInfo, Object> dao = DaoManager.createDao(connection, CardInfo.class);
            for (CardInfo row : rows) dao.create(row);
            check(dao, rows, "default", CardCriteria::new);
            check(dao, rows, "all faces", () -> new CardCriteria().nightCard(null));
            check(dao, rows, "night faces", () -> new CardCriteria().nightCard(true));
            require(rows.stream().anyMatch(row -> row.nightCard), "real night face missing");
            require(rows.stream().anyMatch(row -> row.splitCardHalf), "real split half missing");
            require(MobileCardCriteria.find(rows, new CardCriteria().nightCard(null)).stream()
                    .noneMatch(row -> row.splitCardHalf), "split halves leaked");
            for (boolean value : new boolean[]{false, true}) {
                check(dao, rows, "double faced " + value, () -> new CardCriteria().nightCard(null).doubleFaced(value));
                check(dao, rows, "various art " + value, () -> new CardCriteria().variousArt(value));
            }
            for (String name : new String[]{"Lightning Bolt", "LIGHTNING BOLT", "lightning bolt", "missing", ""}) {
                check(dao, rows, "name " + name, () -> new CardCriteria().name(name));
            }
            // Genuine card constructors, with explicit printed-metadata edge cases below.
            for (String text : new String[]{"", "%", "_", "LI_HT%", "bolt", "\\L", "\\%", "\\_",
                    "\\\\", "\\", "'", "[", ".", "%_%%", "100\\%", "under\\_score", "İ", "i_"}) {
                check(dao, rows, "name LIKE " + text, () -> new CardCriteria().nameContains(text));
                check(dao, rows, "rules LIKE " + text, () -> new CardCriteria().rules(text));
            }
            for (String text : new String[]{"DAMAGE", "target%creature", "draw_a", "@@@", "{T}"}) {
                check(dao, rows, "rules " + text, () -> new CardCriteria().rules(text));
            }
            check(dao, rows, "set case", () -> new CardCriteria().setCodes("m10", "ISD"));
            check(dao, rows, "excluded sets", () -> new CardCriteria().ignoreSetCodes("M10", "isd"));
            check(dao, rows, "sets AND exclusion", () -> new CardCriteria().setCodes("M10", "ISD").ignoreSetCodes("m10"));
            for (Rarity rarity : Rarity.values()) check(dao, rows, "rarity " + rarity, () -> new CardCriteria().rarities(rarity));
            check(dao, rows, "rarity OR", () -> new CardCriteria().rarities(Rarity.COMMON, Rarity.RARE));
            check(dao, rows, "all rarities", () -> new CardCriteria().rarities(Rarity.values()));
            for (CardType type : CardType.values()) check(dao, rows, "type " + type, () -> new CardCriteria().types(type));
            check(dao, rows, "type OR", () -> new CardCriteria().types(CardType.CREATURE, CardType.LAND));
            check(dao, rows, "all types", () -> new CardCriteria().types(CardType.values()));
            check(dao, rows, "searchable types", () -> new CardCriteria().types(Arrays.stream(CardType.values())
                    .filter(CardType::isIncludeInSearch).toArray(CardType[]::new)));
            check(dao, rows, "seven duplicate types shortcut", () -> new CardCriteria().types(
                    CardType.ARTIFACT, CardType.ARTIFACT, CardType.ARTIFACT, CardType.ARTIFACT,
                    CardType.ARTIFACT, CardType.ARTIFACT, CardType.ARTIFACT));
            check(dao, rows, "not types AND", () -> new CardCriteria().notTypes(CardType.ARTIFACT, CardType.LAND));
            check(dao, rows, "supertypes AND", () -> new CardCriteria().supertypes(SuperType.BASIC, SuperType.SNOW));
            check(dao, rows, "not supertypes AND", () -> new CardCriteria().notSupertypes(SuperType.BASIC, SuperType.LEGENDARY));
            check(dao, rows, "subtypes AND", () -> new CardCriteria().subtypes(SubType.HUMAN, SubType.WIZARD));
            check(dao, rows, "subtype substring", () -> new CardCriteria().subtypes(SubType.BEAR));
            for (int mask = 0; mask < 64; mask++) {
                final int colors = mask;
                check(dao, rows, "colors " + mask, () -> colors(colors));
            }
            for (int mana = 0; mana <= 5; mana++) {
                final int value = mana;
                check(dao, rows, "mana " + mana, () -> new CardCriteria().manaValue(value));
            }
            check(dao, rows, "numeric card range", () -> new CardCriteria().minCardNumber(10).maxCardNumber(25));
            check(dao, rows, "reversed range", () -> new CardCriteria().minCardNumber(25).maxCardNumber(10));
            check(dao, rows, "combined creature", () -> colors(2).types(CardType.CREATURE, CardType.ARTIFACT)
                    .notTypes(CardType.LAND).subtypes(SubType.HUMAN).manaValue(1).nameContains("de%er")
                    .rules("upkeep").setCodes("isd").ignoreSetCodes("M10").maxCardNumber(100));
            check(dao, rows, "combined snow land", () -> colors(32).types(CardType.LAND)
                    .supertypes(SuperType.BASIC, SuperType.SNOW).notSupertypes(SuperType.LEGENDARY)
                    .subtypes(SubType.FOREST).rarities(Rarity.COMMON, Rarity.RARE).minCardNumber(1));

            // Compare identities within ties, not H2's unspecified tie order. Reflection here
            // deliberately derives sort coverage from upstream @DatabaseField, not adapter mapping.
            for (Field field : CardInfo.class.getDeclaredFields()) {
                if (field.getAnnotation(DatabaseField.class) != null) {
                    check(dao, rows, "sort " + field.getName(), () -> new CardCriteria().nightCard(null).setOrderBy(field.getName()));
                }
            }
            for (long start : new long[]{0, 1, 5, 100, Integer.MAX_VALUE}) {
                for (Long count : new Long[]{0L, 1L, 4L, (long) Integer.MAX_VALUE}) {
                    if (start + count > Integer.MAX_VALUE) continue; // H2 partial-sort integer overflow
                    check(dao, rows, "page " + start + "/" + count,
                            () -> new CardCriteria().setOrderBy("name").start(start).count(count));
                }
            }
            check(dao, rows, "limit only", () -> new CardCriteria().setOrderBy("cardNumberAsInt").count(4L));
            rejected(dao, rows, "offset without limit", () -> new CardCriteria().start(1L));
            rejected(dao, rows, "zero offset without limit", () -> new CardCriteria().start(0L));
            rejected(dao, rows, "limit overflow", () -> new CardCriteria().count(Long.MAX_VALUE));
            rejected(dao, rows, "offset overflow", () -> new CardCriteria().start(Long.MAX_VALUE).count(1L));
            rejected(dao, rows, "modal true", () -> new CardCriteria().modalDoubleFaced(true));
            rejected(dao, rows, "modal false", () -> new CardCriteria().modalDoubleFaced(false));
            rejected(dao, rows, "invalid sort", () -> new CardCriteria().setOrderBy("notAColumn"));
            rejected(dao, rows, "SQL sort expression", () -> new CardCriteria().setOrderBy("name DESC"));
            rejectMobile(rows, new CardCriteria().start(-1L));
            rejectMobile(rows, new CardCriteria().count(-1L));
            rejectMobile(rows, new CardCriteria().start(1L).count((long) Integer.MAX_VALUE));
            rejectMobile(Collections.emptyList(), new CardCriteria().setOrderBy("invalid"));
            rejectMobile(Collections.emptyList(), new CardCriteria().modalDoubleFaced(false));
            // Seeded LIKE combinations catch escapes next to wildcards and suffix escaping.
            Random random = new Random(9241);
            String alphabet = "liBO%_\\ .";
            for (int i = 0; i < 100; i++) {
                StringBuilder pattern = new StringBuilder();
                for (int j = 0, length = random.nextInt(7); j < length; j++) {
                    pattern.append(alphabet.charAt(random.nextInt(alphabet.length())));
                }
                String text = pattern.toString();
                check(dao, rows, "seeded LIKE " + i, () -> new CardCriteria().nameContains(text));
            }
            CardCriteria unchanged = new CardCriteria().rarities(Rarity.values()).types(CardType.values());
            MobileCardCriteria.find(rows, unchanged);
            require(unchanged.isBlack() && unchanged.getRarities().size() == Rarity.values().length
                    && unchanged.getTypes().size() == CardType.values().length, "criteria mutated");
            require(rows.equals(originalOrder), "input order mutated");
        }
        System.out.println("MobileCardCriteriaTests: " + checked + " oracle checks passed; in-memory H2 only");
    }

    private static CardCriteria colors(int mask) {
        return new CardCriteria().black((mask & 1) != 0).blue((mask & 2) != 0).green((mask & 4) != 0)
                .red((mask & 8) != 0).white((mask & 16) != 0).colorless((mask & 32) != 0);
    }

    private static List<CardInfo> query(Dao<CardInfo, Object> dao, CardCriteria criteria) throws Exception {
        QueryBuilder<CardInfo, Object> builder = dao.queryBuilder();
        criteria.buildQuery(builder);
        return dao.query(builder.prepare());
    }

    private static void check(Dao<CardInfo, Object> dao, List<CardInfo> rows, String label,
                              Supplier<CardCriteria> factory) throws Exception {
        CardCriteria criteria = factory.get();
        List<CardInfo> actual = MobileCardCriteria.find(rows, criteria);
        List<CardInfo> expected = query(dao, factory.get()); // buildQuery mutates its own criteria
        require(actual.size() == expected.size(), label + " size: " + actual + " != " + expected);
        boolean paged = criteria.getStart() != null || criteria.getCount() != null;
        if (!paged) require(identities(actual).equals(identities(expected)), label + " identities differ");
        if (criteria.getSortBy() != null) {
            Field field = CardInfo.class.getDeclaredField(criteria.getSortBy());
            field.setAccessible(true);
            for (int i = 0; i < actual.size(); i++) {
                Object a = field.get(actual.get(i)), e = field.get(expected.get(i));
                boolean same = a instanceof String && e instanceof String ? ((String) a).equalsIgnoreCase((String) e)
                        : java.util.Objects.equals(a, e);
                require(same, label + " sort key at " + i + ": " + a + " != " + e);
            }
        }
        if (paged) {
            CardCriteria unpaged = factory.get().start(null).count(null);
            Map<String, Integer> eligible = identities(query(dao, unpaged));
            for (Map.Entry<String, Integer> entry : identities(actual).entrySet()) {
                require(eligible.getOrDefault(entry.getKey(), 0) >= entry.getValue(), label + " ineligible page row");
            }
        }
        checked++;
    }

    private static Map<String, Integer> identities(List<CardInfo> rows) {
        Map<String, Integer> result = new HashMap<>();
        for (CardInfo row : rows) {
            String id = row.name + "\u0000" + row.setCode + "\u0000" + row.cardNumber + "\u0000" + row.className;
            result.put(id, result.getOrDefault(id, 0) + 1);
        }
        return result;
    }

    private static void rejected(Dao<CardInfo, Object> dao, List<CardInfo> rows, String label,
                                 Supplier<CardCriteria> factory) throws Exception {
        boolean failed = false;
        try {
            query(dao, factory.get());
        } catch (IllegalArgumentException | java.sql.SQLException expected) {
            failed = true;
        }
        require(failed, "upstream should reject " + label);
        rejectMobile(rows, factory.get());
        checked++;
    }

    private static void rejectMobile(List<CardInfo> rows, CardCriteria criteria) {
        try {
            MobileCardCriteria.find(rows, criteria);
        } catch (IllegalArgumentException expected) {
            return;
        }
        throw new AssertionError("mobile should reject invalid criteria");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    private static CardSetInfo info(String name, String set, String number, Rarity rarity) {
        return new CardSetInfo(name, set, number, rarity);
    }

    private static List<CardInfo> cards() {
        List<CardInfo> rows = new ArrayList<>();
        rows.add(new CardInfo(new LightningBolt(OWNER, info("Lightning Bolt", "M10", "146", Rarity.COMMON))));
        rows.add(new CardInfo(new GrizzlyBears(OWNER, info("Grizzly Bears", "10E", "268", Rarity.COMMON))));
        rows.add(new CardInfo(new Forest(OWNER, info("Forest", "M10", "248", Rarity.LAND))));
        rows.add(new CardInfo(new SnowCoveredForest(OWNER, info("Snow-Covered Forest", "KHM", "284", Rarity.COMMON))));
        rows.add(new CardInfo(new IsamaruHoundOfKonda(OWNER, info("Isamaru, Hound of Konda", "CHK", "19", Rarity.RARE))));
        rows.add(new CardInfo(new Murder(OWNER, info("Murder", "M13", "101", Rarity.COMMON))));
        rows.add(new CardInfo(new AzoriusCharm(OWNER, info("Azorius Charm", "RTR", "145", Rarity.UNCOMMON))));
        rows.add(new CardInfo(new Memnite(OWNER, info("Memnite", "SOM", "174", Rarity.UNCOMMON))));
        FireIce split = new FireIce(OWNER, info("Fire // Ice", "APC", "128", Rarity.UNCOMMON));
        rows.add(new CardInfo(split));
        rows.add(new CardInfo(split.getLeftHalfCard()));
        rows.add(new CardInfo(split.getRightHalfCard()));
        DelverOfSecrets delver = new DelverOfSecrets(OWNER, info("Delver of Secrets", "ISD", "51", Rarity.COMMON));
        rows.add(new CardInfo(delver));
        rows.add(new CardInfo(delver.getRightHalfCard()));
        BalaGedRecovery modal = new BalaGedRecovery(OWNER, info("Bala Ged Recovery", "ZNR", "180", Rarity.UNCOMMON));
        rows.add(new CardInfo(modal));
        rows.add(new CardInfo(modal.getRightHalfCard()));
        rows.add(new CardInfo(new BriselaVoiceOfNightmares(OWNER,
                info("Brisela, Voice of Nightmares", "EMN", "15b", Rarity.MYTHIC))));
        // These remain genuine LightningBolt cards, with controlled print names/numbers to exercise
        // SQL punctuation and numeric suffixes absent from the small real-print sample above.
        int number = 10;
        for (String name : new String[]{"100%", "under_score", "back\\slash", "ends%", "O'Brien.[x]",
                "İstanbul", "iota", "zebra", "Alpha", "lightning bolt"}) {
            Card card = new LightningBolt(OWNER, new CardSetInfo(name, "EDGE", (number++) + "b", Rarity.MYTHIC,
                    new CardGraphicInfo(FrameStyle.M15_NORMAL, true)));
            rows.add(new CardInfo(card));
        }
        return rows;
    }
}
