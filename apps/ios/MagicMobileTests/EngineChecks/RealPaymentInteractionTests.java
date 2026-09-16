package io.magicmobile.xmage;

import io.magicmobile.core.*;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.Mana;
import mage.abilities.Ability;
import mage.abilities.costs.common.SacrificeTargetCost;
import mage.abilities.costs.mana.GenericManaCost;
import mage.abilities.costs.mana.ManaCostsImpl;
import mage.abilities.keyword.MenaceAbility;
import mage.cards.*;
import mage.cards.basiclands.*;
import mage.cards.c.ConclaveTribunal;
import mage.cards.g.GrizzlyBears;
import mage.cards.j.JasperaSentinel;
import mage.cards.s.SolRing;
import mage.cards.s.SelesnyaSignet;
import mage.cards.a.ArcaneSignet;
import mage.cards.b.BoggartBrute;
import mage.cards.decks.Deck;
import mage.constants.*;
import mage.filter.StaticFilters;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.PermanentCard;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import java.util.*;
import java.util.function.Function;

/** Real upstream actions + mailbox transport. No game.start(), native build or device claim. */
public final class RealPaymentInteractionTests {
    public static void main(String[] args) {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,Runnable> tests = new LinkedHashMap<>();
        tests.put("rocks", RealPaymentInteractionTests::rocks);
        tests.put("jaspera", RealPaymentInteractionTests::jaspera);
        tests.put("convoke", RealPaymentInteractionTests::convoke);
        tests.put("sacrifice-six", () -> sacrifice(false));
        tests.put("sacrifice-cancel", () -> sacrifice(true));
        tests.put("menace", RealPaymentInteractionTests::menace);
        tests.put("affordability", RealPaymentInteractionTests::affordability);
        if (args.length > 0 && !tests.containsKey(args[0])) throw new AssertionError("Unknown test");
        int passed = 0;
        List<String> failed = new ArrayList<>();
        for (var test : tests.entrySet()) if (args.length == 0 || args[0].equals(test.getKey())) {
            try { test.getValue().run(); passed++; System.out.println("PASS " + test.getKey()); }
            catch (RuntimeException | AssertionError e) { failed.add(test.getKey()); System.err.println("FAIL " + test.getKey()); e.printStackTrace(); }
        }
        if (!failed.isEmpty()) throw new AssertionError("Failed cases: " + failed);
        System.out.println("RealPaymentInteractionTests: " + passed + " passed (JVM, not native/device)");
    }

    private static void rocks() {
        for (int kind = 0; kind < 3; kind++) try (Fixture f = new Fixture()) {
            Card rock = kind == 0 ? new SolRing(f.player.getId(), info("Sol Ring"))
                : kind == 1 ? new SelesnyaSignet(f.player.getId(), info("Selesnya Signet"))
                : new ArcaneSignet(f.player.getId(), info("Arcane Signet"));
            Card spell = f.bear(); f.hand(spell);
            if (kind == 2) f.game.addCommander(spell, f.player); // Seed green identity, not deck-legality evidence.
            PermanentCard permanent = f.board(rock);
            if (kind == 1) f.player.getManaPool().addMana(Mana.ColorlessMana(1), f.game, spell.getSpellAbility());
            f.manaRow(rock, true);
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(rock.getId()); });
            check(f.player.playMana(spell.getSpellAbility(), new GenericManaCost(1), "{1}", f.game), "source response handled");
            check(permanent.isTapped(), "real rock activated and tapped");
            if (kind == 0) eq(f.player.getManaPool().get(ManaType.COLORLESS), 2);
            if (kind == 1) {
                eq(f.player.getManaPool().get(ManaType.COLORLESS), 0);
                eq(f.player.getManaPool().get(ManaType.WHITE), 1);
                eq(f.player.getManaPool().get(ManaType.GREEN), 1);
            }
            if (kind == 2) eq(f.player.getManaPool().get(ManaType.GREEN), 1);
            f.manaRow(rock, false); f.drained();
        }
    }

    private static void jaspera() {
        try (Fixture f = new Fixture()) {
            Card sentinel = new JasperaSentinel(f.player.getId(), info("Jaspera Sentinel"));
            PermanentCard permanent = f.board(sentinel); permanent.removeSummoningSickness();
            Card partner = f.bear(); PermanentCard companion = f.board(partner);
            Card extra = f.bear(); f.board(extra); // Two targets prevent automatic target choice.
            Card spell = f.bear(); f.hand(spell);
            f.manaRow(sentinel, true);
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(sentinel.getId()); });
            f.reply(s -> { eq(s.kind, "PICK_TARGET"); check(candidates(s).contains(partner.getId().toString()), "tap-cost candidate"); return uuid(partner.getId()); });
            f.reply(s -> {
                eq(s.kind, "CHOOSE_CHOICE");
                Map<String,Object> choices = Json.object(s.payload.get("choices"));
                String green = choices.entrySet().stream().filter(e -> e.getValue().toString().toLowerCase().contains("green"))
                    .map(Map.Entry::getKey).findFirst().orElseThrow();
                return answer("string", green);
            });
            // Two unpaid colors require an explicit ChoiceColor instead of upstream's
            // auto-selection for a generic-only or single-color remaining cost.
            check(f.player.playMana(spell.getSpellAbility(), new ManaCostsImpl<>("{G}{W}"), "{G}{W}", f.game), "Jaspera response handled");
            check(permanent.isTapped() && companion.isTapped(), "both actual tap costs paid");
            f.drained();
            check(f.game.getPlayer(f.player.getId()).getManaPool().get(ManaType.GREEN) == 1,
                "actual Jaspera pool: " + f.game.getPlayer(f.player.getId()).getManaPool());
            f.manaRow(sentinel, false); f.drained();
        }
    }

    private static void sacrifice(boolean cancel) {
        try (Fixture f = new Fixture()) {
            List<Card> cards = new ArrayList<>();
            for (int n = 0; n < 7; n++) {
                Card card = n < 2 ? f.bear() : new Forest(f.player.getId(), info("Forest"));
                f.board(card); cards.add(card);
            }
            Card spell = f.bear(); f.hand(spell);
            SacrificeTargetCost cost = new SacrificeTargetCost(6, StaticFilters.FILTER_CONTROLLED_PERMANENT);
            Ability ability = spell.getSpellAbility(); ability.addCost(cost);
            // Exercise selected-2 -> deselect -> reselect -> the remaining four land UUIDs.
            List<Integer> sequence = cancel ? List.of(0, 1) : List.of(0, 1, 0, 0, 2, 3, 4, 5);
            Set<String> chosen = new LinkedHashSet<>();
            for (int index : sequence) {
                Set<String> before = Set.copyOf(chosen);
                f.reply(s -> {
                    eq(s.kind, "PICK_TARGET");
                    eq(new HashSet<>(candidates(s)), new HashSet<>(cards.stream().map(c -> c.getId().toString()).toList()));
                    eq(new HashSet<>(Json.array(Json.object(s.payload.get("options")).get("chosenTargets"))), before);
                    check(Json.requiredString(s.payload, "message").contains("selected " + before.size() + " of 6, min 6"), "aggregate target progress");
                    for (Card card : cards) check(f.game.getPermanent(card.getId()) != null, "no sacrifice before complete payment");
                    return uuid(cards.get(index).getId());
                });
                String id = cards.get(index).getId().toString();
                if (!chosen.remove(id)) chosen.add(id);
            }
            if (cancel) f.reply(s -> { eq(s.kind, "PICK_TARGET"); return answer("boolean", false); });
            eq(cost.pay(ability, f.game, ability, f.player.getId(), false, cost), !cancel);
            for (int n = 0; n < 7; n++)
                eq(f.game.getState().getZone(cards.get(n).getId()), !cancel && n < 6 ? Zone.GRAVEYARD : Zone.BATTLEFIELD);
            f.drained();
        }
    }

    private static void convoke() {
        try (Fixture f = new Fixture()) {
            Card tribunal = new ConclaveTribunal(f.player.getId(), info("Conclave Tribunal")); f.hand(tribunal);
            Card rock = new SolRing(f.player.getId(), info("Sol Ring")); PermanentCard ring = f.board(rock);
            Card land = new Plains(f.player.getId(), info("Plains")); PermanentCard plains = f.board(land);
            Card creature = f.bear(); PermanentCard convoker = f.board(creature);
            f.board(f.bear()); // More than one convoke option: require the real target prompt.
            check(convoker.hasSummoningSickness(), "convoke permits a newly controlled creature");
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(rock.getId()); });
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(land.getId()); });
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return answer("string", "special"); });
            f.reply(s -> {
                eq(s.kind, "CHOOSE_ABILITY");
                Map<String,Object> choice = Json.array(s.payload.get("abilities")).stream().map(Json::object)
                    .filter(a -> a.get("label").toString().toLowerCase().contains("convoke")).findFirst().orElseThrow();
                return answer("uuid", choice.get("id"));
            });
            f.reply(s -> { eq(s.kind, "PICK_TARGET"); check(candidates(s).contains(creature.getId().toString()), "actual convoke candidate"); return uuid(creature.getId()); });
            check(f.player.cast(tribunal.getSpellAbility(), f.game, false, null), "real Tribunal cast with rock, land and convoke");
            check(ring.isTapped() && plains.isTapped() && convoker.isTapped(), "all actual payment sources tapped");
            eq(f.game.getState().getZone(tribunal.getId()), Zone.STACK);
            check(f.game.getStack().getSpell(tribunal.getId()) != null, "paid spell present on stack");
            f.drained();
        }
    }

    private static void menace() {
        try (Fixture f = new Fixture()) {
            Card card = f.bear(); PermanentCard permanent = f.board(card);
            f.menaceIcon(card, false);
            permanent.addAbility(new MenaceAbility(), permanent.getId(), f.game);
            f.menaceIcon(card, true);
            permanent.removeAllAbilities(UUID.randomUUID(), f.game);
            f.menaceIcon(card, false);
            permanent.addAbility(new MenaceAbility(), permanent.getId(), f.game);
            permanent.setFaceDown(true, f.game);
            f.menaceIcon(card, false);
            Card printed = new BoggartBrute(f.player.getId(), info("Boggart Brute"));
            PermanentCard innate = f.board(printed);
            f.menaceIcon(printed, true);
            innate.removeAllAbilities(UUID.randomUUID(), f.game);
            f.menaceIcon(printed, false); // Printed keyword remains; current ability is gone.
            Card secret = new BoggartBrute(f.player.getId(), info("Boggart Brute")); f.hand(secret);
            check(!Json.write(ViewProjector.project(f.game, f.seats).get("other")).contains(secret.getId().toString()), "no hidden hand menace disclosure");
        }
    }

    private static void affordability() {
        try (Fixture f = new Fixture()) {
            Card tribunal = new ConclaveTribunal(f.player.getId(), info("Conclave Tribunal")); f.hand(tribunal);
            Card plains = new Plains(f.player.getId(), info("Plains")); f.board(plains);
            Card forest = new Forest(f.player.getId(), info("Forest")); f.board(forest);
            check(!f.playable(tribunal), "two lands alone do not offer four-mana spell");
            PermanentCard sentinel = f.board(new JasperaSentinel(f.player.getId(), info("Jaspera Sentinel")));
            sentinel.removeSummoningSickness();
            // Characterize pinned upstream's optimistic estimator, not a guarantee of payment.
            check(f.playable(tribunal), "pinned estimator offers Tribunal with two lands and Jaspera");
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(plains.getId()); });
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return uuid(forest.getId()); });
            f.reply(s -> { eq(s.kind, "PLAY_MANA"); return answer("string", "special"); });
            f.reply(s -> {
                eq(s.kind, "CHOOSE_ABILITY");
                Map<String,Object> choice = Json.array(s.payload.get("abilities")).stream().map(Json::object)
                    .filter(a -> a.get("label").toString().toLowerCase().contains("convoke")).findFirst().orElseThrow();
                return answer("uuid", choice.get("id"));
            });
            f.reply(s -> {
                eq(s.kind, "PLAY_MANA");
                check(sentinel.isTapped(), "Jaspera already used for convoke");
                check(Json.requiredString(s.payload, "message").contains("{1}"), "one mana still unpaid after all three resources");
                return answer("boolean", false);
            });
            check(!f.player.cast(f.game.getCard(tribunal.getId()).getSpellAbility(), f.game, false, null), "explicit cancel aborts attempted cast");
            eq(f.game.getState().getZone(tribunal.getId()), Zone.HAND);
            check(f.game.getStack().isEmpty(), "no unpaid spell left on stack");
            f.drained();
        }
    }

    private static final class Fixture implements AutoCloseable {
        final MobileHumanPlayer player = new MobileHumanPlayer("Payment owner"), other = new MobileHumanPlayer("Other seat");
        final MobileCommanderGame game;
        final Map<String,MobileHumanPlayer> seats = Map.of("owner", player, "other", other);
        final MatchMailbox mailbox = new MatchMailbox(UUID.randomUUID().toString(), List.of("owner", "other"));
        final Deque<Function<DecisionSpec,Map<String,Object>>> replies = new ArrayDeque<>();
        Fixture() {
            MobileCommanderMatch match = new MobileCommanderMatch();
            match.addPlayer(player, new Deck()); match.addPlayer(other, new Deck()); match.startMatch();
            try { match.startGame(); } catch (mage.game.GameException e) { throw new AssertionError(e); }
            game = (MobileCommanderGame) match.getGame();
            for (MobileHumanPlayer p : seats.values()) { p.updateRange(game); p.setLife(40, game, null); }
            game.getState().setActivePlayerId(player.getId()); game.getState().setPriorityPlayerId(player.getId());
            // Game.start normally initializes this turn-order cursor. Seed only that
            // fixture state so actual cast cancellation can use GameImpl.restoreState.
            try {
                var order = mage.game.GameImpl.class.getDeclaredField("playerList");
                order.setAccessible(true); order.set(game, game.getState().getPlayerList(player.getId()));
            } catch (ReflectiveOperationException e) { throw new AssertionError("fixture turn order", e); }
            PreCombatMainPhase phase = new PreCombatMainPhase(); phase.setStep(new PreCombatMainStep()); game.getTurn().setPhase(phase);
            player.getManaPool().setAutoPayment(true); player.getManaPool().setAutoPaymentRestricted(false);
            player.onConsumed(() -> mailbox.consumed("owner"));
            game.addPlayerQueryEventListener(event -> {
                if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                check(!replies.isEmpty(), "unexpected query " + event.getQueryType() + ": " + event.getMessage());
                DecisionSpec spec = QueryEncoder.encode(event, game);
                Map<String,Object> response = replies.remove().apply(spec);
                mailbox.ask("owner", spec, player::offer);
                var prompt = Json.object(mailbox.poll("owner", 0).get("prompt"));
                eq(mailbox.poll("other", 0).get("prompt"), null);
                Map<String,Object> command = Json.map("requestId", UUID.randomUUID().toString(), "promptId", prompt.get("promptId"),
                    "promptRevision", prompt.get("revision"), "answer", response);
                try { mailbox.submit("other", command); throw new AssertionError("cross-seat reply accepted"); }
                catch (BridgeException expected) { eq(expected.code(), "stale_prompt"); }
                eq(mailbox.submit("owner", command).get("status"), "queued");
            });
        }
        Card bear() { return new GrizzlyBears(player.getId(), info("Grizzly Bears")); }
        void hand(Card c) { game.loadCards(new HashSet<>(List.of(c)), player.getId()); c.setZone(Zone.HAND, game); player.getHand().add(c); }
        PermanentCard board(Card c) {
            game.loadCards(new HashSet<>(List.of(c)), player.getId());
            PermanentCard p = new PermanentCard(c, player.getId(), game);
            game.getBattlefield().addPermanent(p); game.setZone(c.getId(), Zone.BATTLEFIELD); return p;
        }
        boolean playable(Card c) { return player.getPlayable(game, true, Zone.ALL, false).stream().anyMatch(a -> c.getId().equals(a.getSourceId())); }
        void manaRow(Card c, boolean expected) {
            Map<String,Map<String,Object>> views = ViewProjector.project(game, seats);
            Map<String,Object> objects = Json.object(Json.object(Json.object(views.get("owner").get("gameView")).get("canPlayObjects")).get("objects"));
            Map<String,Object> stats = objects.containsKey(c.getId().toString()) ? Json.object(objects.get(c.getId().toString())) : Map.of();
            boolean found = stats.values().stream().flatMap(v -> Json.array(v).stream()).anyMatch(v -> Boolean.TRUE.equals(Json.object(v).get("manaAbility")));
            eq(found, expected);
            check(!Json.write(views.get("other")).contains("\"manaAbility\":true"), "other seat gets no owned playable mana metadata");
        }
        void menaceIcon(Card c, boolean expected) {
            for (Map<String,Object> snapshot : ViewProjector.project(game, seats).values()) {
                List<Object> players = Json.array(Json.object(snapshot.get("gameView")).get("players"));
                Map<String,Object> view = players.stream().map(Json::object).map(p -> Json.object(p.get("battlefield")))
                    .filter(p -> p.containsKey(c.getId().toString())).map(p -> Json.object(p.get(c.getId().toString()))).findFirst().orElseThrow();
                eq(Json.array(view.get("cardIcons")).stream().map(Json::object).anyMatch(i -> "ABILITY_MENACE".equals(i.get("cardIconType"))), expected);
            }
        }
        void reply(Function<DecisionSpec,Map<String,Object>> reply) { replies.add(reply); }
        void drained() { check(replies.isEmpty(), "all actual queries consumed"); eq(mailbox.poll("owner", 0).get("prompt"), null); }
        public void close() { mailbox.close(); player.closeChannel(); other.closeChannel(); }
    }
    private static CardSetInfo info(String name) { return new CardSetInfo(name, "TST", "1", Rarity.COMMON); }
    private static Map<String,Object> answer(String kind, Object value) { return Json.map("kind", kind, "value", value); }
    private static Map<String,Object> uuid(UUID id) { return answer("uuid", id.toString()); }
    private static List<Object> candidates(DecisionSpec s) { return Json.array(s.payload.get("candidates")); }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void eq(Object actual, Object expected) { if (!Objects.equals(actual, expected)) throw new AssertionError("Expected " + expected + ", got " + actual); }
}
