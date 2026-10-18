package io.magicmobile.xmage;

import com.google.gson.Gson;
import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedCardFactory;
import mage.cards.Card;
import mage.cards.CardGraphicInfo;
import mage.cards.ExpansionSet;
import mage.cards.MobileExpansionSet;
import mage.cards.Sets;
import mage.cards.repository.ExpansionInfo;
import mage.cards.repository.ExpansionRepository;
import mage.util.RandomUtil;
import mage.view.SimpleCardView;
import mage.view.SimpleCardsView;
import java.lang.reflect.Field;
import java.lang.reflect.Modifier;
import java.util.*;

/**
 * The bundled set catalogue against the real XMage set classes, on the JVM: every set's fields, card list
 * and class lookups, the registry's iteration order, the repository's set queries, a seeded booster pack
 * from every set (Booster Tutor), every printing's card and the second faces of meld cards. With
 * "ambiguous", on a catalogue copy that lists MRD 16 twice: decks refuse it and views keep it unknown.
 * Not native or phone evidence.
 */
public final class RealSetCatalogueTests {
    private static final Set<String> CACHES = Set.of("cards", "savedCards", "savedSpecialCards", "savedReprints", "inBoosterMap");
    private static int checks;

    public static void main(String[] args) throws Exception {
        if (args.length == 1 && args[0].equals("ambiguous")) {
            ambiguous();
            return;
        }
        long started = System.nanoTime();
        XmageEngine.installCards();
        List<MobileExpansionSet> mobile = new ArrayList<>();
        for (ExpansionSet set : Sets.getInstance().values()) {
            check(set instanceof MobileExpansionSet, "registry holds only catalogue sets: " + set.getCode());
            mobile.add((MobileExpansionSet) set);
        }
        check(mobile.size() == 589, "pinned set inventory: " + mobile.size());
        // The old generated registry added the set classes in class-name order; a HashMap filled in that order
        // iterates exactly like Sets now does (CardImpl and Sets.findCardByClass depend on that order).
        List<MobileExpansionSet> registryOrder = new ArrayList<>(mobile);
        registryOrder.sort(Comparator.comparing(MobileExpansionSet::getClassName));
        Map<String, ExpansionSet> real = new HashMap<>();
        for (MobileExpansionSet set : registryOrder)
            real.put(set.getCode(), (ExpansionSet) Class.forName(set.getClassName()).getMethod("getInstance").invoke(null));
        check(new ArrayList<>(real.keySet()).equals(new ArrayList<>(Sets.getInstance().keySet())), "registry iteration order");

        int custom = 0, printings = 0;
        for (MobileExpansionSet set : mobile) {
            ExpansionSet original = real.get(set.getCode());
            check(original.getClass().getName().equals(set.getClassName()), "set class " + set.getCode());
            fields(original, set);
            List<ExpansionSet.SetCardInfo> expected = original.getSetCardInfo(), actual = set.getSetCardInfo();
            check(expected.size() == actual.size(), "card list size " + set.getCode());
            check(set.hasPrintings() == !expected.isEmpty(), "has printings " + set.getCode());
            Set<Class<?>> classes = new LinkedHashSet<>();
            Set<String> numbers = new LinkedHashSet<>();
            for (int i = 0; i < expected.size(); i++) {
                same(expected.get(i), actual.get(i), set.getCode() + " #" + i);
                check(expected.get(i).getCardClass() == actual.get(i).getCardClass(), "card class " + set.getCode() + " #" + i);
                classes.add(expected.get(i).getCardClass());
                numbers.add(expected.get(i).getCardNumber());
            }
            for (Class<?> c : classes) sameList(original.findCardInfoByClass(c), set.findCardInfoByClass(c), set.getCode() + " " + c.getName());
            for (String number : numbers) {
                List<MobileExpansionSet.Printing> found = set.printings(number);
                List<ExpansionSet.SetCardInfo> listed = expected.stream().filter(info -> info.getCardNumber().equals(number)).toList();
                check(found.size() == listed.size(), "printings " + set.getCode() + " " + number);
                for (int i = 0; i < listed.size(); i++) {
                    check(found.get(i).getClassName().equals(listed.get(i).getCardClass().getName()), "printing class");
                    same(listed.get(i), new ExpansionSet.SetCardInfo(found.get(i).getName(), found.get(i).getCardNumber(),
                            found.get(i).getRarity(), listed.get(i).getCardClass(), found.get(i).getGraphicInfo()), "printing");
                }
            }
            check(set.printings("NO-SUCH-NUMBER").isEmpty(), "unknown number");
            printings += expected.size();
            if (set.hasCustomBooster()) custom++;
        }
        check(printings == 93420, "pinned printing inventory: " + printings);
        System.out.println("PASS fields, card lists, class and number lookups of " + mobile.size() + " sets, " + printings
                + " printings; " + custom + " sets make packs in their own class");

        // Sets.findCardByClass (CardImpl's second faces): the preferred set first, then every set in registry order.
        Random sample = new Random(7);
        int lookups = 0;
        for (MobileExpansionSet set : mobile)
            for (ExpansionSet.SetCardInfo info : real.get(set.getCode()).getSetCardInfo()) {
                sameOrNull(findCardByClass(real, info.getCardClass(), set.getCode(), info.getCardNumber()),
                        Sets.findCardByClass(info.getCardClass(), set.getCode(), info.getCardNumber()), "findCardByClass");
                if (sample.nextInt(50) == 0) {
                    sameOrNull(findCardByClass(real, info.getCardClass(), set.getCode(), ""),
                            Sets.findCardByClass(info.getCardClass(), set.getCode(), ""), "findCardByClass any number");
                    sameOrNull(findCardByClass(real, info.getCardClass(), "NO-SUCH-SET", ""),
                            Sets.findCardByClass(info.getCardClass(), "NO-SUCH-SET", ""), "findCardByClass fallback");
                    sameOrNull(findCardByClass(real, info.getCardClass(), "NO-SUCH-SET", info.getCardNumber()),
                            Sets.findCardByClass(info.getCardClass(), "NO-SUCH-SET", info.getCardNumber()), "findCardByClass fallback number");
                    lookups += 3;
                }
                lookups++;
            }
        System.out.println("PASS " + lookups + " Sets.findCardByClass lookups match the set classes");

        // The repository's set queries, from the real sets as the old registry answered them.
        List<ExpansionInfo> all = ExpansionRepository.instance.getAll();
        List<ExpansionInfo> expectedAll = real.values().stream().map(ExpansionInfo::new)
                .sorted(Comparator.comparing(ExpansionInfo::getReleaseDate)).toList();
        sameInfos(expectedAll, all, "getAll");
        check(ExpansionRepository.instance.getSetCodes().equals(real.values().stream().map(ExpansionSet::getCode).toList()), "getSetCodes");
        sameInfos(real.values().stream().filter(set -> set.hasBoosters() && !set.getSetCardInfo().isEmpty()).map(ExpansionInfo::new)
                .sorted(Comparator.comparing(ExpansionInfo::getReleaseDate).reversed()).toList(),
                Arrays.asList(ExpansionRepository.instance.getWithBoostersSortedByReleaseDate()), "booster sets");
        System.out.println("PASS repository set queries match the set classes");

        // Booster Tutor opens a 15-card pack of any set: same seed, same pack, for every set. Sets with their own
        // booster code pass the request to their class; the others run ExpansionSet's code on the exported fields.
        int packs = 0, full = 0, failed = 0;
        for (MobileExpansionSet set : mobile) {
            String expected = pack(real.get(set.getCode()), 1000 + packs), actual = pack(set, 1000 + packs);
            check(expected.equals(actual), "pack " + set.getCode() + ": " + expected + " != " + actual);
            if (expected.startsWith("failed: ")) failed++;
            else if (expected.chars().filter(c -> c == ';').count() == 15) full++;
            packs++;
        }
        check(full > 300, "most sets make full packs: " + full);
        // Negative control: the comparison sees a booster setting (Dominaria's commons are its own code; M10's are not).
        MobileExpansionSet control = (MobileExpansionSet) Sets.getInstance().get("M10");
        check(!control.hasCustomBooster() && control.hasBoosters(), "control set");
        Field commons = ExpansionSet.class.getDeclaredField("numBoosterCommon");
        commons.setAccessible(true);
        commons.set(control, (Integer) commons.get(control) - 1);
        check(!pack(real.get("M10"), 99).equals(pack(control, 99)), "a changed booster field changes the pack");
        commons.set(control, (Integer) commons.get(control) + 1);
        check(pack(real.get("M10"), 99).equals(pack(control, 99)), "control restored");
        System.out.println("PASS seeded 15-card packs of all " + packs + " sets match the set classes (" + full
                + " full packs, " + failed + " sets fail identically); a changed booster field is detected");

        // Every printing builds through the catalogue lookups as DeckLoader builds it; meld cards' melded faces
        // (CardImpl.initSecondSideCard) match those found through the real set classes.
        List<String[]> melds = new ArrayList<>();
        Map<String, String> meldFaces = new LinkedHashMap<>();
        int cards = 0;
        for (MobileExpansionSet set : mobile)
            for (ExpansionSet.SetCardInfo info : real.get(set.getCode()).getSetCardInfo()) {
                List<MobileExpansionSet.Printing> found = DeckLoader.printings(set.getCode(), info.getCardNumber());
                MobileExpansionSet.Printing printing = found.stream()
                        .filter(p -> p.getClassName().equals(info.getCardClass().getName()) && p.getName().equals(info.getName()))
                        .findFirst().orElseThrow();
                Card card = GeneratedCardFactory.create(printing.getClassName(), printing.setInfo(set.getCode()));
                check(card != null && card.getClass() == info.getCardClass(), "card " + set.getCode() + " " + info.getCardNumber());
                cards++;
                if (card.getMeldsToClazz() != null) {
                    String[] key = {printing.getClassName(), set.getCode(), info.getCardNumber(), info.getName()};
                    melds.add(key);
                    meldFaces.put(String.join("|", key), face(card.getMeldsToCard()));
                }
            }
        check(!melds.isEmpty(), "meld cards found");
        Sets.getInstance().clear();
        for (MobileExpansionSet set : registryOrder) Sets.getInstance().addSet(real.get(set.getCode()));
        for (String[] key : melds) {
            ExpansionSet.SetCardInfo info = real.get(key[1]).getSetCardInfo().stream()
                    .filter(i -> i.getCardNumber().equals(key[2]) && i.getName().equals(key[3]) && i.getCardClass().getName().equals(key[0]))
                    .findFirst().orElseThrow();
            Card card = GeneratedCardFactory.create(key[0], new mage.cards.CardSetInfo(info.getName(), key[1], key[2], info.getRarity(), info.getGraphicInfo()));
            check(face(card.getMeldsToCard()).equals(meldFaces.get(String.join("|", key))), "melded face " + String.join(" ", key));
        }
        System.out.println("PASS " + cards + " printings build their card class; " + melds.size() + " meld cards find the same melded face");
        System.out.printf("PASS %d set catalogue checks in %d s (JVM only, not native or phone evidence)%n", checks,
                (System.nanoTime() - started) / 1_000_000_000L);
    }

    /** A collector number listed twice in a set: DeckLoader refuses it, printed views leave it unknown. */
    @SuppressWarnings("unchecked")
    private static void ambiguous() throws Exception {
        XmageEngine.installCards();
        check(DeckLoader.printings("MRD", "16").size() == 2, "the catalogue copy lists MRD 16 twice");
        check(DeckLoader.printings("MRD", "17").size() == 1, "other printings unchanged");
        try {
            DeckLoader.load(Json.map("main", List.of(Json.map("count", 1, "setCode", "MRD", "collectorNumber", "16")),
                    "commanders", List.of()));
            throw new AssertionError("ambiguous printing accepted");
        } catch (BridgeException expected) {
            check("ambiguous_printing".equals(expected.code()), "deck error " + expected.code());
        }
        SimpleCardsView cards = new SimpleCardsView();
        SimpleCardView ambiguous = new SimpleCardView(UUID.randomUUID(), "MRD", "16", false), unique = new SimpleCardView(UUID.randomUUID(), "MRD", "17", false);
        cards.put(ambiguous.getId(), ambiguous);
        cards.put(unique.getId(), unique);
        java.lang.reflect.Method method = ViewProjector.class.getDeclaredMethod("printedCards", SimpleCardsView.class);
        method.setAccessible(true);
        Map<String, Object> printed = Json.object(method.invoke(null, cards));
        check(Json.object(printed.get(ambiguous.getId().toString())).equals(Json.parseObject(new Gson().toJson(ambiguous))),
                "ambiguous printing stays unknown");
        check(Json.object(printed.get(unique.getId().toString())).containsKey("name"), "unique printing resolves");
        System.out.println("PASS an ambiguous collector number: deck refused (ambiguous_printing), printed view unknown");
    }

    /** Upstream Sets.findCardByClass, over the real set classes. */
    private static ExpansionSet.SetCardInfo findCardByClass(Map<String, ExpansionSet> sets, Class<?> clazz, String code, String number) {
        ExpansionSet.SetCardInfo info = null;
        if (sets.containsKey(code))
            info = sets.get(code).findCardInfoByClass(clazz).stream()
                    .filter(card -> number.isEmpty() || card.getCardNumber().equals(number)).findFirst().orElse(null);
        if (info == null)
            for (ExpansionSet set : sets.values()) {
                info = set.findCardInfoByClass(clazz).stream()
                        .filter(card -> number.isEmpty() || card.getCardNumber().equals(number)).findFirst().orElse(null);
                if (info != null) break;
            }
        return info;
    }

    private static void fields(ExpansionSet expected, ExpansionSet actual) throws Exception {
        for (Field field : ExpansionSet.class.getDeclaredFields()) {
            if (Modifier.isStatic(field.getModifiers()) || CACHES.contains(field.getName())) continue;
            field.setAccessible(true);
            Object left = field.get(expected), right = field.get(actual);
            if (left instanceof ExpansionSet) {
                check(right instanceof ExpansionSet && ((ExpansionSet) left).getCode().equals(((ExpansionSet) right).getCode()),
                        "parent set " + expected.getCode());
            } else check(Objects.equals(left, right), expected.getCode() + "." + field.getName() + ": " + left + " != " + right);
        }
        check(expected.toString().equals(actual.toString()), "toString " + expected.getCode());
        check(expected.getReleaseYear() == actual.getReleaseYear(), "release year " + expected.getCode());
    }

    private static void sameList(List<ExpansionSet.SetCardInfo> expected, List<ExpansionSet.SetCardInfo> actual, String what) {
        check(expected.size() == actual.size(), what);
        for (int i = 0; i < expected.size(); i++) {
            same(expected.get(i), actual.get(i), what);
            check(expected.get(i).getCardClass() == actual.get(i).getCardClass(), what);
        }
    }

    private static void sameOrNull(ExpansionSet.SetCardInfo expected, ExpansionSet.SetCardInfo actual, String what) {
        check((expected == null) == (actual == null), what);
        if (expected != null) {
            same(expected, actual, what);
            check(expected.getCardClass() == actual.getCardClass(), what);
        }
    }

    private static void same(ExpansionSet.SetCardInfo expected, ExpansionSet.SetCardInfo actual, String what) {
        check(expected.getName().equals(actual.getName()) && expected.getCardNumber().equals(actual.getCardNumber())
                && expected.getRarity() == actual.getRarity(), what + ": " + expected.getName() + " / " + actual.getName());
        CardGraphicInfo left = expected.getGraphicInfo(), right = actual.getGraphicInfo();
        check((left == null) == (right == null), what + " graphic info");
        if (left != null)
            check(left.getFrameStyle() == right.getFrameStyle() && left.getUsesVariousArt() == right.getUsesVariousArt()
                    && Objects.equals(left.getFrameColor(), right.getFrameColor()), what + " graphic info");
    }

    private static void sameInfos(List<ExpansionInfo> expected, List<ExpansionInfo> actual, String what) throws Exception {
        check(expected.size() == actual.size(), what + " size");
        for (int i = 0; i < expected.size(); i++)
            for (Field field : ExpansionInfo.class.getDeclaredFields()) {
                if (Modifier.isStatic(field.getModifiers())) continue;
                field.setAccessible(true);
                check(Objects.equals(field.get(expected.get(i)), field.get(actual.get(i))), what + " " + field.getName() + " #" + i);
            }
    }

    private static String pack(ExpansionSet set, long seed) {
        RandomUtil.setSeed(seed);
        try {
            StringBuilder pack = new StringBuilder();
            for (Card card : set.create15CardBooster())
                pack.append(card.getName()).append('/').append(card.getExpansionSetCode()).append('/').append(card.getCardNumber())
                        .append('/').append(card.getClass().getName()).append(';');
            return pack.append(RandomUtil.nextInt()).toString(); // also the generator's position after the pack
        } catch (RuntimeException failure) {
            return "failed: " + failure;
        }
    }

    private static String face(Card card) {
        return card == null ? "none" : String.join("/", card.getName(), card.getExpansionSetCode(), card.getCardNumber(),
                String.valueOf(card.getRarity()), card.getClass().getName(), String.valueOf(card.getFrameStyle()),
                String.valueOf(card.getUsesVariousArt()), String.valueOf(card.getFrameColor(null)));
    }

    private static void check(boolean value, String message) {
        checks++;
        if (!value) throw new AssertionError(message);
    }
}
