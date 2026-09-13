package mage.cards.repository;

import mage.constants.CardType;
import mage.constants.Rarity;
import mage.constants.SubType;
import mage.constants.SuperType;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.function.Function;
import java.util.function.Predicate;

/**
 * Pure metadata selection matching the pinned CardCriteria/H2 IGNORECASE=TRUE query.
 * Uses stored columns, including serialized rules/types, rather than reconstructing cards.
 * Requires getNightCard() on the generated mobile CardCriteria copy. Does not mutate criteria
 * (upstream optimize's redundant filters are omitted without its observable mutations).
 */
public final class MobileCardCriteria {
    private MobileCardCriteria() {
    }

    public static List<CardInfo> find(List<CardInfo> rows, CardCriteria criteria) {
        Objects.requireNonNull(rows, "rows");
        Objects.requireNonNull(criteria, "criteria");
        if (criteria.getModalDoubleFaced() != null) {
            throw new IllegalArgumentException("Unknown upstream CardInfo column: modalDoubleFacedCard");
        }
        Long start = criteria.getStart();
        Long count = criteria.getCount();
        if ((start != null && start < 0) || (count != null && count < 0)) {
            throw new IllegalArgumentException("Offset and count must be nonnegative");
        }
        if (start != null && count == null) {
            throw new IllegalArgumentException("H2 requires a limit when offset is specified");
        }
        if ((start != null && start > Integer.MAX_VALUE) || (count != null && count > Integer.MAX_VALUE)) {
            throw new IllegalArgumentException("H2 offset and count must fit a signed integer");
        }
        // H2 1.4.197 overflows its partial-sort end index for these windows, returning
        // query-plan-dependent unsorted pages. Reject rather than claim portable parity.
        if (start != null && start + count > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("H2 pagination end exceeds a signed integer");
        }
        Function<CardInfo, ?> order = criteria.getSortBy() == null ? null : column(criteria.getSortBy());
        List<Predicate<CardInfo>> filters = new ArrayList<>();
        filters.add(row -> !row.splitCardHalf);
        Boolean night = criteria.getNightCard();
        if (night != null) filters.add(row -> row.nightCard == night);
        if (criteria.getName() != null) filters.add(row -> equal(row.name, criteria.getName()));
        addLike(filters, row -> row.name, criteria.getNameContains(), false);
        addLike(filters, row -> row.rules, criteria.getRules(), false);
        if (criteria.getVariousArt() != null) filters.add(row -> row.variousArt == criteria.getVariousArt());
        if (criteria.getDoubleFaced() != null) filters.add(row -> row.doubleFaced == criteria.getDoubleFaced());
        if (!criteria.getRarities().isEmpty()
                && !criteria.getRarities().containsAll(Arrays.asList(Rarity.values()))) {
            filters.add(row -> criteria.getRarities().contains(row.rarity));
        }
        if (!criteria.getSetCodes().isEmpty()) {
            filters.add(row -> criteria.getSetCodes().stream().anyMatch(code -> equal(row.setCode, code)));
        }
        for (String code : criteria.getIgnoreSetCodes()) {
            filters.add(row -> row.setCode != null && !equal(row.setCode, code));
        }
        boolean allSearchTypes = Arrays.stream(CardType.values()).filter(CardType::isIncludeInSearch)
                .allMatch(criteria.getTypes()::contains);
        // Preserve the separate, historical size==7 shortcut in buildQuery, including duplicates.
        if (!criteria.getTypes().isEmpty() && criteria.getTypes().size() != 7 && !allSearchTypes) {
            List<Like> types = new ArrayList<>();
            for (CardType type : criteria.getTypes()) types.add(new Like(type.name()));
            filters.add(row -> types.stream().anyMatch(type -> type.matches(row.types)));
        }
        for (CardType type : criteria.getNotTypes()) addLike(filters, row -> row.types, type.name(), true);
        for (SuperType type : criteria.getSupertypes()) addLike(filters, row -> row.supertypes, type.name(), false);
        for (SuperType type : criteria.getNotSupertypes()) addLike(filters, row -> row.supertypes, type.name(), true);
        for (SubType type : criteria.getSubtypes()) addLike(filters, row -> row.subtypes, type.toString(), false);
        if (criteria.getManaValue() != null) filters.add(row -> row.manaValue == criteria.getManaValue());
        boolean black = criteria.isBlack(), blue = criteria.isBlue(), green = criteria.isGreen();
        boolean red = criteria.isRed(), white = criteria.isWhite(), colorless = criteria.isColorless();
        if ((black || blue || green || red || white || colorless)
                && !(black && blue && green && red && white && colorless)) {
            filters.add(row -> (black && row.black) || (blue && row.blue) || (green && row.green)
                    || (red && row.red) || (white && row.white)
                    || (colorless && !row.black && !row.blue && !row.green && !row.red && !row.white));
        }
        if (criteria.getMinCardNumber() != Integer.MIN_VALUE) {
            filters.add(row -> row.cardNumberAsInt >= criteria.getMinCardNumber());
        }
        if (criteria.getMaxCardNumber() != Integer.MAX_VALUE) {
            filters.add(row -> row.cardNumberAsInt <= criteria.getMaxCardNumber());
        }
        List<CardInfo> result = new ArrayList<>();
        for (CardInfo row : rows) {
            if (filters.stream().allMatch(filter -> filter.test(row))) result.add(row);
        }
        if (order != null) result.sort((left, right) -> compare(order.apply(left), order.apply(right)));
        int from = start == null ? 0 : (int) Math.min(start, result.size());
        int length = count == null ? result.size() - from : (int) Math.min(count, result.size() - from);
        return new ArrayList<>(result.subList(from, from + length));
    }

    private static boolean equal(String left, String right) {
        return left != null && right != null && left.equalsIgnoreCase(right);
    }

    private static void addLike(List<Predicate<CardInfo>> filters, Function<CardInfo, String> field,
                                String value, boolean negate) {
        if (value == null) return;
        Like pattern = new Like(value);
        // SQL NOT LIKE NULL remains UNKNOWN, not true.
        filters.add(row -> field.apply(row) != null && (pattern.matches(field.apply(row)) != negate));
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    private static int compare(Object left, Object right) {
        if (left == right) return 0;
        if (left == null) return -1; // H2 default ascending NULLS FIRST
        if (right == null) return 1;
        if (left instanceof String) return ((String) left).compareToIgnoreCase((String) right);
        return ((Comparable) left).compareTo(right);
    }

    // Explicit persisted-field mapping avoids reflection/native reachability and rejects SQL expressions.
    private static Function<CardInfo, ?> column(String name) {
        switch (name) {
            case "name": return row -> row.name;
            case "setCode": return row -> row.setCode;
            case "cardNumber": return row -> row.cardNumber;
            case "cardNumberAsInt": return row -> row.cardNumberAsInt;
            case "className": return row -> row.className;
            case "power": return row -> row.power;
            case "toughness": return row -> row.toughness;
            case "startingLoyalty": return row -> row.startingLoyalty;
            case "startingDefense": return row -> row.startingDefense;
            case "manaValue": return row -> row.manaValue;
            case "rarity": return row -> row.rarity == null ? null : row.rarity.name();
            case "types": return row -> row.types;
            case "subtypes": return row -> row.subtypes;
            case "supertypes": return row -> row.supertypes;
            case "manaCosts": return row -> row.manaCosts;
            case "rules": return row -> row.rules;
            case "black": return row -> row.black;
            case "blue": return row -> row.blue;
            case "green": return row -> row.green;
            case "red": return row -> row.red;
            case "white": return row -> row.white;
            case "frameColor": return row -> row.frameColor;
            case "frameStyle": return row -> row.frameStyle;
            case "variousArt": return row -> row.variousArt;
            case "splitCard": return row -> row.splitCard;
            case "splitCardFuse": return row -> row.splitCardFuse;
            case "splitCardAftermath": return row -> row.splitCardAftermath;
            case "splitCardHalf": return row -> row.splitCardHalf;
            case "flipCard": return row -> row.flipCard;
            case "doubleFaced": return row -> row.doubleFaced;
            case "nightCard": return row -> row.nightCard;
            case "meldCard": return row -> row.meldCard;
            case "flipCardName": return row -> row.flipCardName;
            case "secondSideName": return row -> row.secondSideName;
            case "cardWithSpellOption": return row -> row.cardWithSpellOption;
            case "spellOptionCardName": return row -> row.spellOptionCardName;
            case "doubleFacedCard": return row -> row.doubleFacedCard;
            case "doubleFacedSecondSideName": return row -> row.doubleFacedSecondSideName;
            case "meldsToCardName": return row -> row.meldsToCardName;
            case "isExtraDeckCard": return row -> row.isExtraDeckCard;
            default: throw new IllegalArgumentException("Unknown upstream CardInfo column: " + name);
        }
    }

    /** H2 1.4.197 LIKE: UTF-16 units, % and _, and backslash escaping any next character. */
    private static final class Like {
        private final char[] chars;
        private final int[] kinds; // literal, one, many
        private int size;

        Like(String contains) {
            String pattern = '%' + contains + '%';
            chars = new char[pattern.length()];
            kinds = new int[pattern.length()];
            for (int i = 0; i < pattern.length(); i++) {
                char c = pattern.charAt(i);
                int kind = 0;
                if (c == '\\') c = pattern.charAt(++i); // final appended % always supplies a character
                else if (c == '%') kind = 2;
                else if (c == '_') kind = 1;
                if (kind == 2 && size > 0 && kinds[size - 1] == 2) continue;
                chars[size] = c;
                kinds[size++] = kind;
            }
        }

        boolean matches(String value) {
            if (value == null) return false;
            // H2's no-collation LIKE shortcuts use regionMatches, unlike its general
            // matcher (uppercase chars only). Preserve the distinction for Unicode.
            int first = kinds[0] == 2 ? 1 : 0;
            int last = kinds[size - 1] == 2 ? size - 1 : size;
            boolean literal = true;
            for (int i = first; i < last; i++) if (kinds[i] != 0) literal = false;
            if (literal && last > first) {
                String text = new String(chars, first, last - first);
                if (first == 0) return value.regionMatches(true, 0, text, 0, text.length());
                if (last == size) return value.regionMatches(true, value.length() - text.length(), text, 0, text.length());
                char lower = Character.toLowerCase(text.charAt(0)), upper = Character.toUpperCase(text.charAt(0));
                for (int i = value.length() - text.length(); i >= 0; i--) {
                    char c = value.charAt(i);
                    if ((c == lower || c == upper) && value.regionMatches(true, i, text, 0, text.length())) return true;
                }
                return false;
            }
            int p = 0, v = 0, star = -1, retry = 0;
            while (v < value.length()) {
                if (p < size && kinds[p] == 2) {
                    star = p++;
                    retry = v;
                } else if (p < size && (kinds[p] == 1
                        || Character.toUpperCase(chars[p]) == Character.toUpperCase(value.charAt(v)))) {
                    p++;
                    v++;
                } else if (star >= 0) {
                    p = star + 1;
                    v = ++retry;
                } else return false;
            }
            while (p < size && kinds[p] == 2) p++;
            return p == size;
        }
    }
}
