package io.magicmobile.xmage;

import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.Mana;
import mage.abilities.Ability;
import mage.abilities.common.SimpleActivatedAbility;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.MobileCardFactories;
import mage.cards.a.AmbushViper;
import mage.cards.basiclands.Forest;
import mage.cards.c.Counterspell;
import mage.cards.decks.Deck;
import mage.cards.g.GiantGrowth;
import mage.cards.g.GrizzlyBears;
import mage.cards.l.LightningBolt;
import mage.cards.p.ProdigalSorcerer;
import mage.cards.r.Rout;
import mage.cards.t.ThinkTwice;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.events.PlayerQueryEvent;
import mage.game.stack.Spell;
import mage.game.stack.StackAbility;
import mage.game.turn.CombatPhase;
import mage.game.turn.DeclareAttackersStep;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import java.util.*;
import java.util.function.BiFunction;

/**
 * Real pinned upstream cards and stack objects: `stackControllers` and the per-play
 * `respondsToStack` hint. JVM fixture evidence; not native, full-match or device evidence.
 */
public final class RealStackResponseTests {
    public static void main(String[] args) {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,Runnable> tests = new LinkedHashMap<>();
        tests.put("stack-controllers", RealStackResponseTests::stackControllers);
        tests.put("nothing-pending", RealStackResponseTests::nothingPending);
        tests.put("creature-spell", RealStackResponseTests::creatureSpell);
        tests.put("targeted-threat", RealStackResponseTests::targetedThreat);
        tests.put("untargeted-sweeper", RealStackResponseTests::untargetedSweeper);
        tests.put("combat", RealStackResponseTests::combat);
        int passed = 0;
        for (Map.Entry<String,Runnable> test : tests.entrySet()) {
            if (args.length > 0 && !args[0].equals(test.getKey())) continue;
            try {
                test.getValue().run();
                passed++;
                System.out.println("PASS " + test.getKey());
            } catch (RuntimeException | AssertionError e) {
                System.err.println("FAIL " + test.getKey());
                throw e;
            }
        }
        System.out.println("RealStackResponseTests: " + passed + " passed");
    }

    /** Spells and an activated ability from both seats; every seat sees the same public controllers. */
    private static void stackControllers() {
        try (Fixture f = new Fixture()) {
            Card sorcerer = f.battlefield(f.card(ProdigalSorcerer::new, "Prodigal Sorcerer", "M10", "69", f.opponent));
            Card bears = f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.owner));
            Spell ownerSpell = f.spell(f.card(ThinkTwice::new, "Think Twice", "TSP", "86", f.owner), f.owner, null);
            StackAbility ping = f.activate(sorcerer, f.opponent, bears.getId());
            Spell opponentSpell = f.spell(f.card(LightningBolt::new, "Lightning Bolt", "M10", "146", f.opponent), f.opponent, bears.getId());
            Map<String,Object> expected = Map.of(
                ownerSpell.getId().toString(), f.owner.getId().toString(),
                ping.getId().toString(), f.opponent.getId().toString(),
                opponentSpell.getId().toString(), f.opponent.getId().toString());
            for (String seat : f.seats.keySet()) {
                Map<String,Object> snapshot = f.snapshot(seat);
                Map<String,Object> controllers = Json.object(snapshot.get("stackControllers"));
                eq(controllers, expected);
                // Same keys as the stack the seat sees, and the values are the snapshot's own player IDs.
                eq(controllers.keySet(), new HashSet<>(Json.array(snapshot.get("stackOrder"))));
                Set<Object> players = new HashSet<>();
                for (Object player : Json.array(Json.object(snapshot.get("gameView")).get("players")))
                    players.add(Json.object(player).get("playerId"));
                check(players.containsAll(controllers.values()), "controllers are snapshot player IDs: " + players);
            }
            f.game.getStack().resolve(f.game);
            check(!Json.object(f.snapshot("owner").get("stackControllers")).containsKey(opponentSpell.getId().toString()),
                "a resolved spell leaves the map");
            f.game.getStack().resolve(f.game);
            f.game.getStack().resolve(f.game);
            eq(Json.object(f.snapshot("opponent").get("stackControllers")), Map.of());
        }
    }

    /** Main phase, empty stack, no attack: no offered play answers anything. */
    private static void nothingPending() {
        try (Fixture f = new Fixture()) {
            f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.opponent));
            Card bolt = f.hand(f.card(LightningBolt::new, "Lightning Bolt", "M10", "146", f.owner));
            Card growth = f.hand(f.card(GiantGrowth::new, "Giant Growth", "M10", "186", f.owner));
            f.mana();
            Map<String,Object> snapshot = f.snapshot("owner");
            eq(responses(snapshot, bolt.getId()), List.of(false));
            eq(responses(snapshot, growth.getId()), List.of(false));
            check(Json.object(snapshot.get("stackControllers")).isEmpty(), "empty stack has no controllers");
        }
    }

    /** An opponent's creature spell: a counter answers it; burn, a pump and a cantrip do not. */
    private static void creatureSpell() {
        try (Fixture f = new Fixture()) {
            f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.opponent));
            f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.owner));
            Card forest = f.battlefield(f.card(Forest::new, "Forest", "M10", "246", f.owner));
            Card counter = f.hand(f.card(Counterspell::new, "Counterspell", "7ED", "67", f.owner));
            Card bolt = f.hand(f.card(LightningBolt::new, "Lightning Bolt", "M10", "146", f.owner));
            Card growth = f.hand(f.card(GiantGrowth::new, "Giant Growth", "M10", "186", f.owner));
            Card cantrip = f.hand(f.card(ThinkTwice::new, "Think Twice", "TSP", "86", f.owner));
            Card viper = f.hand(f.card(AmbushViper::new, "Ambush Viper", "M10", "167", f.owner));
            f.spell(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.opponent), f.opponent, null);
            f.priorityTo(f.owner);
            f.mana();
            Map<String,Object> snapshot = f.snapshot("owner");
            eq(responses(snapshot, counter.getId()), List.of(true));
            eq(responses(snapshot, bolt.getId()), List.of(false));
            eq(responses(snapshot, growth.getId()), List.of(false));
            eq(responses(snapshot, cantrip.getId()), List.of(false));
            // A keyword-only flash creature does nothing to a spell on the stack.
            eq(responses(snapshot, viper.getId()), List.of(false));
            // Mana abilities never count (responses() checks every mana row is false).
            eq(responses(snapshot, forest.getId()), List.of());
            // The other seat sees no action metadata.
            check(!playable(f.snapshot("opponent")).containsKey(counter.getId().toString()), "owner's plays stay private");
        }
    }

    /** An opponent's ability and spell aim at the owner's creature: protecting or using it answers them. */
    private static void targetedThreat() {
        for (boolean ability : List.of(true, false)) {
            try (Fixture f = new Fixture()) {
                Card sorcerer = f.battlefield(f.card(ProdigalSorcerer::new, "Prodigal Sorcerer", "M10", "69", f.opponent));
                Card bears = f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.owner));
                Card mine = f.battlefield(f.card(ProdigalSorcerer::new, "Prodigal Sorcerer", "M10", "69", f.owner));
                Card growth = f.hand(f.card(GiantGrowth::new, "Giant Growth", "M10", "186", f.owner));
                Card counter = f.hand(f.card(Counterspell::new, "Counterspell", "7ED", "67", f.owner));
                Card cantrip = f.hand(f.card(ThinkTwice::new, "Think Twice", "TSP", "86", f.owner));
                if (ability) f.activate(sorcerer, f.opponent, bears.getId());
                else f.spell(f.card(LightningBolt::new, "Lightning Bolt", "M10", "146", f.opponent), f.opponent, bears.getId());
                f.priorityTo(f.owner);
                f.mana();
                Map<String,Object> snapshot = f.snapshot("owner");
                String what = ability ? "ability" : "spell";
                eq(responses(snapshot, growth.getId()), List.of(true));
                // Counterspell targets spells only: it answers the bolt; with only an ability on the
                // stack upstream does not offer it at all.
                if (ability) check(!playable(snapshot).containsKey(counter.getId().toString()), "no spell to counter");
                else eq(responses(snapshot, counter.getId()), List.of(true));
                eq(responses(snapshot, cantrip.getId()), List.of(false));
                // The owner's own pinger can hit the opposing source (or the targeted creature).
                check(responses(snapshot, mine.getId()).contains(true), "pinger answers the " + what);
            }
        }
    }

    /** An untargeted sweeper (Rout cast with flash): anything that can protect a permanent counts. */
    private static void untargetedSweeper() {
        try (Fixture f = new Fixture()) {
            f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.owner));
            Card growth = f.hand(f.card(GiantGrowth::new, "Giant Growth", "M10", "186", f.owner));
            Card cantrip = f.hand(f.card(ThinkTwice::new, "Think Twice", "TSP", "86", f.owner));
            Card counter = f.hand(f.card(Counterspell::new, "Counterspell", "7ED", "67", f.owner));
            f.spell(f.card(Rout::new, "Rout", "INV", "36", f.opponent), f.opponent, null);
            f.priorityTo(f.owner);
            f.mana();
            Map<String,Object> snapshot = f.snapshot("owner");
            eq(responses(snapshot, growth.getId()), List.of(true));
            eq(responses(snapshot, counter.getId()), List.of(true));
            eq(responses(snapshot, cantrip.getId()), List.of(false));
        }
    }

    /** Declared attackers with an empty stack: tricks, removal on combatants and flash blockers count. */
    private static void combat() {
        try (Fixture f = new Fixture()) {
            Card attacker = f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.opponent));
            Card home = f.battlefield(f.card(GrizzlyBears::new, "Grizzly Bears", "M10", "189", f.opponent));
            Card growth = f.hand(f.card(GiantGrowth::new, "Giant Growth", "M10", "186", f.owner));
            Card viper = f.hand(f.card(AmbushViper::new, "Ambush Viper", "M10", "167", f.owner));
            Card cantrip = f.hand(f.card(ThinkTwice::new, "Think Twice", "TSP", "86", f.owner));
            Card counter = f.hand(f.card(Counterspell::new, "Counterspell", "7ED", "67", f.owner));
            f.game.getState().setActivePlayerId(f.opponent.getId());
            CombatPhase phase = new CombatPhase();
            phase.setStep(new DeclareAttackersStep());
            f.game.getTurn().setPhase(phase);
            f.game.getCombat().setAttacker(f.opponent.getId());
            f.game.getCombat().setDefenders(f.game);
            check(f.game.getCombat().declareAttacker(attacker.getId(), f.owner.getId(), f.opponent.getId(), f.game), "real attack");
            f.priorityTo(f.owner);
            f.mana();
            Map<String,Object> snapshot = f.snapshot("owner");
            eq(responses(snapshot, growth.getId()), List.of(true));
            eq(responses(snapshot, viper.getId()), List.of(true));
            eq(responses(snapshot, cantrip.getId()), List.of(false));
            check(!playable(snapshot).containsKey(counter.getId().toString()), "no spell to counter: not offered");
            check(f.game.getPermanent(home.getId()) != null && !f.game.getPermanent(home.getId()).isAttacking(),
                "a creature that stayed home is not part of the attack");
        }
    }

    private static Map<String,Object> playable(Map<String,Object> snapshot) {
        Object actions = Json.object(snapshot.get("gameView")).get("canPlayObjects");
        return actions == null ? Map.of() : Json.object(Json.object(actions).get("objects"));
    }
    /** respondsToStack of every non-mana row the object offers, in category order. */
    private static List<Boolean> responses(Map<String,Object> snapshot, UUID objectId) {
        Object stats = playable(snapshot).get(objectId.toString());
        check(stats != null, "upstream offers " + objectId);
        List<Boolean> out = new ArrayList<>();
        for (Object rows : Json.object(stats).values())
            for (Object row : Json.array(rows)) {
                Map<String,Object> fields = Json.object(row);
                check(fields.get("respondsToStack") instanceof Boolean, "every row carries respondsToStack");
                if (Boolean.TRUE.equals(fields.get("manaAbility"))) { eq(fields.get("respondsToStack"), false); continue; }
                out.add((Boolean) fields.get("respondsToStack"));
            }
        return out;
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game;
        final MobileHumanPlayer owner = new MobileHumanPlayer("Owner");
        final MobileHumanPlayer opponent = new MobileHumanPlayer("Opponent");
        final Map<String,MobileHumanPlayer> seats = new LinkedHashMap<>();

        Fixture() {
            seats.put("owner", owner); seats.put("opponent", opponent);
            MobileCommanderMatch match = new MobileCommanderMatch();
            for (MobileHumanPlayer player : seats.values()) match.addPlayer(player, new Deck());
            match.startMatch();
            try { match.startGame(); }
            catch (mage.game.GameException e) { throw new AssertionError("match fixture initialization", e); }
            game = (MobileCommanderGame) match.getGame();
            for (MobileHumanPlayer player : seats.values()) { player.updateRange(game); player.setLife(40, game, null); }
            game.getState().setActivePlayerId(owner.getId());
            game.getState().setPriorityPlayerId(owner.getId());
            PreCombatMainPhase phase = new PreCombatMainPhase();
            phase.setStep(new PreCombatMainStep()); game.getTurn().setPhase(phase);
            game.addPlayerQueryEventListener(event -> {
                if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                throw new AssertionError("unexpected query: " + event.getMessage());
            });
        }
        Card card(BiFunction<UUID,CardSetInfo,Card> constructor, String name, String set, String number, MobileHumanPlayer owner) {
            Card card = constructor.apply(owner.getId(), new CardSetInfo(name, set, number, Rarity.COMMON));
            game.loadCards(new HashSet<>(List.of(card)), owner.getId());
            return card;
        }
        Card hand(Card card) {
            card.setZone(Zone.HAND, game); game.getPlayer(card.getOwnerId()).getHand().add(card);
            return card;
        }
        Card battlefield(Card card) {
            hand(card);
            check(game.getPlayer(card.getOwnerId()).moveCards(card, Zone.BATTLEFIELD, null, game), "real move to battlefield");
            // Controlled since its controller's turn began, so tap abilities are offered.
            UUID active = game.getActivePlayerId();
            game.getState().setActivePlayerId(card.getOwnerId());
            game.getPermanent(card.getId()).beginningOfTurn(game);
            game.getState().setActivePlayerId(active);
            return card;
        }
        /** A spell on the stack with its target chosen, as if cast; no payment prompt for the fixture. */
        Spell spell(Card card, MobileHumanPlayer controller, UUID target) {
            hand(card);
            Spell spell = new Spell(card, card.getSpellAbility().copy(), controller.getId(), Zone.HAND, game);
            if (target != null) spell.getSpellAbility().getTargets().get(0).add(target, game);
            controller.getHand().remove(card);
            card.setZone(Zone.STACK, game);
            game.getStack().push(game, spell);
            return spell;
        }
        /** The permanent's first activated ability on the stack, aimed at a target. */
        StackAbility activate(Card source, MobileHumanPlayer controller, UUID target) {
            Ability ability = game.getPermanent(source.getId()).getAbilities().stream()
                .filter(SimpleActivatedAbility.class::isInstance).findFirst().orElseThrow().copy();
            ability.newId();
            ability.setControllerId(controller.getId());
            ability.getTargets().get(0).add(target, game);
            StackAbility stackAbility = new StackAbility(ability, controller.getId());
            game.getStack().push(game, stackAbility);
            return stackAbility;
        }
        void priorityTo(MobileHumanPlayer player) { game.getState().setPriorityPlayerId(player.getId()); }
        void mana() {
            // Floating mana for the fixture; its source ability only matters for mana restrictions.
            Card source = new GrizzlyBears(owner.getId(), new CardSetInfo("Grizzly Bears", "M10", "189", Rarity.COMMON));
            owner.getManaPool().addMana(new Mana(3, 3, 3, 3, 3, 0, 0, 0), game, source.getSpellAbility());
        }
        Map<String,Object> snapshot(String seat) {
            return Json.parseObject(Json.write(ViewProjector.project(game, seats).get(seat)));
        }
        @Override public void close() { seats.values().forEach(MobileHumanPlayer::closeChannel); }
    }

    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("expected " + expected + " but was " + actual);
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
}
