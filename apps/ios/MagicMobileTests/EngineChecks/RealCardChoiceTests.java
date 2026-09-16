package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.DecisionSpec;
import io.magicmobile.core.Json;
import io.magicmobile.core.MatchMailbox;
import mage.abilities.Ability;
import mage.abilities.effects.keyword.ScryEffect;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.basiclands.Forest;
import mage.cards.c.Cultivate;
import mage.cards.g.GrizzlyBears;
import mage.cards.t.TempleOfPlenty;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.filter.common.FilterLandCard;
import mage.game.events.PlayerQueryEvent;
import mage.target.common.TargetCardInLibrary;

import java.util.ArrayDeque;
import java.util.Arrays;
import java.util.Deque;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.UUID;
import java.util.function.Function;
import java.util.stream.Collectors;

/**
 * Application interaction regressions against compiled, pinned XMage production classes.
 * Reuses RealQueryTests' minimal fixture pattern (its nested Fixture is private).
 * No simulated rules, game.start(), native build, or changes to guarded engine sources.
 * Every actual query also exercises MatchMailbox recipient isolation and exact responses.
 * This does not test XmageEngine.Running's separate seat/controller routing or GameView privacy.
 */
public final class RealCardChoiceTests {
    public static void main(String[] args) {
        run("Temple scry 1 keep", () -> scryOne(false));
        run("Temple scry 1 bottom", () -> scryOne(true));
        run("scry multiple: deselect, bottom order, top order", RealCardChoiceTests::scryMultiple);
        run("filtered search: visible nonmatch rejected by HumanPlayer", RealCardChoiceTests::filteredSearch);
        run("filtered search: decline despite a match", RealCardChoiceTests::declineSearch);
        run("zero-match search: disclosed cards, absent possibleTargets", () -> restrictedSearch(0, false));
        run("restricted search: only permitted pool disclosed", () -> restrictedSearch(2, true));
        run("restricted zero-match search: deeper match stays private", () -> restrictedSearch(2, false));
        System.out.println("RealCardChoiceTests: 8 passed (real JVM; no native/device acceptance)");
    }

    private static void scryOne(boolean bottom) {
        try (Fixture f = new Fixture()) {
            Card top = f.bear(), tail = f.forest();
            f.library(top, tail);
            Card temple = new TempleOfPlenty(f.player.getId(), info("Temple of Plenty", "BNG", "165"));
            f.hand(temple);
            Ability source = temple.getAbilities().stream()
                    .filter(a -> a.getEffects().stream().anyMatch(ScryEffect.class::isInstance))
                    .findFirst().orElseThrow();
            source.setControllerId(f.player.getId());
            ScryEffect effect = (ScryEffect) source.getEffects().stream()
                    .filter(ScryEffect.class::isInstance).findFirst().orElseThrow();
            f.reply(s -> {
                prompt(s, List.of(top), List.of(top), List.of(), Zone.LIBRARY, false);
                check(Json.requiredString(s.payload, "message").contains("BOTTOM"), "scry instruction");
                absent(s, tail);
                return bottom ? uuid(top) : done();
            });
            check(effect.apply(f.game, source), "actual Temple ScryEffect completed");
            f.order(bottom ? List.of(tail, top) : List.of(top, tail));
            f.drained();
        }
    }

    private static void scryMultiple() {
        try (Fixture f = new Fixture()) {
            Card a = f.bear(), b = f.forest(), c = f.bear(), d = f.forest(), e = f.bear(), tail = f.forest();
            List<Card> visible = List.of(a, b, c, d, e);
            f.library(a, b, c, d, e, tail);
            f.pick(visible, visible, List.of(), Zone.LIBRARY, false, a);
            f.pick(visible, List.of(b, c, d, e), List.of(a), Zone.LIBRARY, false, a); // deselect
            f.pick(visible, visible, List.of(), Zone.LIBRARY, false, b);
            f.pick(visible, List.of(a, c, d, e), List.of(b), Zone.LIBRARY, false, d);
            f.reply(s -> {
                prompt(s, visible, List.of(a, c, e), List.of(b, d), Zone.LIBRARY, false);
                absent(s, tail);
                return done();
            });
            // These are upstream's sequential one-card ordering queries, not array answers.
            f.pick(List.of(b, d), List.of(b, d), List.of(), Zone.ALL, true, d);
            f.pick(List.of(a, c, e), List.of(a, c, e), List.of(), Zone.ALL, true, c);
            f.pick(List.of(a, e), List.of(a, e), List.of(), Zone.ALL, true, e);
            check(f.player.scry(5, null, f.game), "real multi-card scry completed");
            f.order(List.of(a, e, c, tail, d, b));
            f.drained();
        }
    }

    private static void filteredSearch() {
        try (Fixture f = new Fixture()) {
            Card bear = f.bear(), forest = f.forest();
            f.library(bear, forest);
            TargetCardInLibrary target = new TargetCardInLibrary(new FilterLandCard());
            f.pick(List.of(bear, forest), List.of(forest), List.of(), Zone.LIBRARY, false, bear);
            // The broad transport candidates accept the visible nonmatch. Real HumanPlayer
            // must ignore that selection and repeat with an unchanged chosenTargets set.
            f.pick(List.of(bear, forest), List.of(forest), List.of(), Zone.LIBRARY, false, forest);
            check(f.player.searchLibrary(target, f.searchSource(), f.game), "real filtered search completed");
            eq(target.getTargets(), List.of(forest.getId()));
            f.order(List.of(bear, forest)); // search selects; the effect moves/shuffles afterward
            f.drained();
        }
    }

    private static void declineSearch() {
        try (Fixture f = new Fixture()) {
            Card bear = f.bear(), forest = f.forest();
            f.library(bear, forest);
            TargetCardInLibrary target = new TargetCardInLibrary(new FilterLandCard());
            f.reply(s -> {
                prompt(s, List.of(bear, forest), List.of(forest), List.of(), Zone.LIBRARY, false);
                return done();
            });
            check(f.player.searchLibrary(target, f.searchSource(), f.game), "declined search completed");
            eq(target.getTargets(), List.of());
            f.order(List.of(bear, forest));
            f.drained();
        }
    }

    private static void restrictedSearch(int limit, boolean matchInPool) {
        try (Fixture f = new Fixture()) {
            Card first = f.bear(), second = matchInPool ? f.forest() : f.bear();
            Card deeper = limit == 0 ? f.bear() : f.forest();
            f.library(first, second, deeper);
            TargetCardInLibrary target = new TargetCardInLibrary(new FilterLandCard());
            // Use upstream's public restricted-pool mechanism. This tests the actual
            // searchLibrary -> copied TargetCardInLibrary -> HumanPlayer flow; it does
            // not claim to test Aven Mindcensor's replacement-effect installation.
            if (limit != 0) target.setCardLimit(limit);
            List<Card> pool = limit == 0 ? List.of(first, second, deeper) : List.of(first, second);
            f.reply(s -> {
                prompt(s, pool, matchInPool ? List.of(second) : List.of(), List.of(), Zone.LIBRARY, false);
                if (limit != 0) absent(s, deeper);
                if (!matchInPool) {
                    check(!Json.object(s.payload.get("options")).containsKey("possibleTargets"),
                            "pinned HumanPlayer omits empty possibleTargets; do not enable all visible cards");
                }
                return matchInPool ? uuid(second) : done();
            });
            check(f.player.searchLibrary(target, f.searchSource(), f.game), "real restricted/zero-match search completed");
            eq(target.getTargets(), matchInPool ? List.of(second.getId()) : List.of());
            f.order(List.of(first, second, deeper));
            f.drained();
        }
    }

    private static void prompt(DecisionSpec spec, List<Card> visible, List<Card> possible,
                               List<Card> chosen, Zone zone, boolean required) {
        eq(spec.kind, "PICK_TARGET");
        Map<String,Object> options = Json.object(spec.payload.get("options"));
        eq(options.get("targetZone"), zone.toString());
        eq(spec.payload.get("required"), required);
        eq(ids(Json.array(options.get("chosenTargets"))), cardIDs(chosen));
        if (possible.isEmpty()) {
            check(!options.containsKey("possibleTargets"), "empty legal set is omitted by pinned HumanPlayer");
        } else {
            eq(ids(Json.array(options.get("possibleTargets"))), cardIDs(possible));
        }
        eq(ids(Json.array(spec.payload.get("candidates"))), cardIDs(visible));
        List<Object> views = Json.array(spec.payload.get("cards"));
        eq(views.size(), visible.size());
        eq(views.stream().map(Json::object).map(v -> Json.requiredString(v, "id")).collect(Collectors.toSet()), cardIDs(visible));
        for (Card card : visible) {
            Map<String,Object> view = views.stream().map(Json::object)
                    .filter(v -> card.getId().toString().equals(v.get("id"))).findFirst().orElseThrow();
            eq(view.get("name"), card.getName());
        }
        eq(ids(Json.array(spec.describe().get("responseTypes"))), required ? Set.of("uuid") : Set.of("uuid", "boolean"));
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game = new MobileCommanderGame();
        final MobileHumanPlayer player = new MobileHumanPlayer("Card choice player");
        final MatchMailbox mailbox = new MatchMailbox(UUID.randomUUID().toString(), List.of("owner", "other"));
        final Deque<Function<DecisionSpec,Map<String,Object>>> replies = new ArrayDeque<>();
        int queries;

        Fixture() {
            game.getState().addPlayer(player);
            player.updateRange(game);
            player.onConsumed(() -> mailbox.consumed("owner"));
            game.addPlayerQueryEventListener(event -> {
                if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                eq(event.getPlayerId(), player.getId());
                check(!replies.isEmpty(), "Unexpected/repeated real query: " + event.getMessage());
                DecisionSpec spec = QueryEncoder.encode(event, game);
                Map<String,Object> answer = replies.remove().apply(spec);
                mailbox.ask("owner", spec, player::offer);
                Map<String,Object> prompt = Json.object(mailbox.poll("owner", 0).get("prompt"));
                eq(prompt.get("payload"), spec.payload);
                Map<String,Object> other = mailbox.poll("other", 0);
                eq(other.get("prompt"), null);
                for (Object card : Json.array(spec.payload.get("cards"))) {
                    check(!Json.write(other).contains(Json.requiredString(Json.object(card), "id")),
                            "private prompt card must not appear in the other seat's poll/events");
                }
                Map<String,Object> command = Json.map("requestId", UUID.randomUUID().toString(),
                        "promptId", prompt.get("promptId"), "promptRevision", prompt.get("revision"), "answer", answer);
                try {
                    mailbox.submit("other", command);
                    throw new AssertionError("other seat accepted owner's prompt token");
                } catch (BridgeException expected) { eq(expected.code(), "stale_prompt"); }
                eq(mailbox.submit("owner", command).get("status"), "queued");
                queries++;
            });
        }

        Card bear() { Card c = new GrizzlyBears(player.getId(), info("Grizzly Bears", "LEA", "202")); hand(c); return c; }
        Card forest() { Card c = new Forest(player.getId(), info("Forest", "LEA", "298")); hand(c); return c; }
        Ability searchSource() {
            Card card = new Cultivate(player.getId(), info("Cultivate", "M11", "168"));
            hand(card);
            return card.getSpellAbility(); // real search text also prevents upstream auto-targeting
        }
        void hand(Card card) {
            game.loadCards(new HashSet<>(List.of(card)), player.getId());
            card.setZone(Zone.HAND, game); player.getHand().add(card);
        }
        void library(Card... cards) {
            for (Card card : cards) {
                player.getHand().remove(card.getId());
                player.getLibrary().putOnBottom(card, game);
            }
            order(Arrays.asList(cards));
        }
        void reply(Function<DecisionSpec,Map<String,Object>> callback) { replies.add(callback); }
        void pick(List<Card> visible, List<Card> possible, List<Card> chosen, Zone zone, boolean required, Card card) {
            reply(s -> { prompt(s, visible, possible, chosen, zone, required); return uuid(card); });
        }
        void order(List<Card> cards) { eq(player.getLibrary().getCardList(), cards.stream().map(Card::getId).toList()); }
        void drained() {
            check(queries > 0, "must exercise actual HumanPlayer callbacks");
            check(replies.isEmpty(), "all scripted real queries consumed");
            eq(mailbox.poll("owner", 0).get("prompt"), null);
            eq(mailbox.poll("owner", 0).get("failure"), null);
        }
        @Override public void close() { mailbox.close(); player.closeChannel(); }
    }

    private static CardSetInfo info(String name, String set, String number) { return new CardSetInfo(name, set, number, Rarity.COMMON); }
    private static Set<String> cardIDs(List<Card> cards) { return cards.stream().map(c -> c.getId().toString()).collect(Collectors.toSet()); }
    private static Set<String> ids(List<Object> values) { return values.stream().map(Json::string).collect(Collectors.toSet()); }
    private static Map<String,Object> uuid(Card card) { return Json.map("kind", "uuid", "value", card.getId().toString()); }
    private static Map<String,Object> done() { return Json.map("kind", "boolean", "value", false); }
    private static void absent(DecisionSpec spec, Card card) { check(!Json.write(spec.describe()).contains(card.getId().toString()), "undisclosed card ID leaked"); }
    private static void check(boolean condition, String message) { if (!condition) throw new AssertionError(message); }
    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("Expected " + expected + ", got " + actual);
    }
    private static void run(String name, Runnable test) { test.run(); System.out.println("PASS " + name); }
}
