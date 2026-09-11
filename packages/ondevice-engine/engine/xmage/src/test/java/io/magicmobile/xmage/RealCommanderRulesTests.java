package io.magicmobile.xmage;

import io.magicmobile.core.DecisionSpec;
import io.magicmobile.core.Json;
import mage.Mana;
import mage.abilities.SpellAbility;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.g.GrizzlyBears;
import mage.cards.i.IsamaruHoundOfKonda;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.GameCommanderImpl;
import mage.game.combat.CombatGroup;
import mage.game.events.PlayerQueryEvent;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.watchers.common.CommanderInfoWatcher;
import mage.watchers.common.CommanderPlaysCountWatcher;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.*;

/**
 * Focused real-XMage rules fixtures, NOT full games, native-backend, or phone evidence.
 * Fixture setup loads real cards, registers real commander effects/watchers, and seeds mana/life.
 * Moves, paid casts, damage, choices, and state-based actions execute upstream implementations.
 * Run from package root with JDK 21, production build/engine FIRST in runtimeCP:
 * javac -J-Xmx384m --release 17 -cp "$runtimeCP" -d build/test-commander <this file>
 * java -Xmx384m -Djava.awt.headless=true -cp "$runtimeCP:build/test-commander" io.magicmobile.xmage.RealCommanderRulesTests
 */
public final class RealCommanderRulesTests {
    private static final int TOTAL = 10;
    private static int passed;

    public static void main(String[] args) throws Exception {
        System.out.println("FIXTURE SCOPE: real pinned XMage rules; no game startup, full-game, native, or phone validation");
        System.out.println("Production adapter: " + MobileCommanderGame.class.getProtectionDomain().getCodeSource().getLocation());
        run("graveyard return accepted after actual zone entry", () -> returnChoice(Zone.GRAVEYARD, true));
        run("exile return accepted after actual zone entry", () -> returnChoice(Zone.EXILED, true));
        run("graveyard return declined once, offered again after re-entry", () -> returnChoice(Zone.GRAVEYARD, false));
        run("exile return declined once, offered again after re-entry", () -> returnChoice(Zone.EXILED, false));
        run("paid command-zone casts cost W, 2W, 4W; hand cast untaxed", RealCommanderRulesTests::recastTax);
        run("20 commander combat damage survives; 21 loses at positive life", RealCommanderRulesTests::commanderDamage);
        run("21 noncombat damage from commander does not eliminate", () -> ordinaryDamage(true));
        run("21 combat damage from noncommander does not eliminate", () -> ordinaryDamage(false));
        run("combat damage from different commanders is not combined", RealCommanderRulesTests::differentCommanders);
        run("real blocked combat trades creatures without player damage", RealCommanderRulesTests::blockedCombat);
        System.out.println("RealCommanderRulesTests: " + passed + " passed, 0 failed, 0 not run");
    }

    private static void returnChoice(Zone destination, boolean accept) throws Exception {
        try (Fixture f = new Fixture()) {
            Card commander = f.commander();
            f.battlefield(commander);
            check(f.game.getPermanent(commander.getId()).moveToZone(destination, null, f.game, true), "real zone move");
            eq(f.game.getState().getZone(commander.getId()), destination);
            check(f.inZone(commander, destination), "card must actually enter destination before SBA choice");
            f.answerReturn(accept);
            f.sba();
            eq(f.game.getState().getZone(commander.getId()), accept ? Zone.COMMAND : destination);
            eq(f.inZone(commander, destination), !accept);
            if (!accept) {
                f.sba(); // No response queued: a repeated prompt for the same object fails immediately.
                eq(f.queryCount, 1);
                f.battlefield(commander);
                check(f.game.getPermanent(commander.getId()).moveToZone(destination, null, f.game, true), "re-entry");
                f.answerReturn(true);
                f.sba();
                eq(f.game.getState().getZone(commander.getId()), Zone.COMMAND);
                check(!f.inZone(commander, destination), "accepted re-entry removes old-zone card");
            }
            eq(f.queryCount, accept ? 1 : 2);
            f.drained();
        }
    }

    private static void recastTax() throws Exception {
        try (Fixture f = new Fixture()) {
            Card commander = f.commander();
            f.owner.getManaPool().setAutoPayment(true);
            f.owner.getManaPool().setAutoPaymentRestricted(false);
            for (int cast = 0; cast < 3; cast++) {
                f.paidCast(commander, Zone.COMMAND, 1 + 2 * cast);
                eq(f.plays().getPlaysCount(commander.getId()), cast + 1);
                f.game.getStack().resolve(f.game);
                check(f.game.getPermanent(commander.getId()) != null, "commander resolved to battlefield");
                if (cast < 2) {
                    check(f.game.getPermanent(commander.getId()).moveToZone(Zone.GRAVEYARD, null, f.game, true), "commander died");
                    f.answerReturn(true);
                    f.sba();
                    eq(f.game.getState().getZone(commander.getId()), Zone.COMMAND);
                }
            }
            // A normal hand cast must neither pay tax nor increment command-zone play count.
            f.answerReturn(false);
            check(f.game.getPermanent(commander.getId()).moveToZone(Zone.HAND, null, f.game, true), "return to hand");
            eq(f.game.getState().getZone(commander.getId()), Zone.HAND);
            f.paidCast(commander, Zone.HAND, 1);
            eq(f.plays().getPlaysCount(commander.getId()), 3);
            f.game.getStack().resolve(f.game);
            check(f.game.getPermanent(commander.getId()) != null, "untaxed hand cast resolved");
            f.drained();
        }
    }

    private static void commanderDamage() throws Exception {
        try (Fixture f = new Fixture()) {
            Card commander = f.commander();
            f.battlefield(commander);
            f.damage(commander, 20, true);
            f.sba();
            eq(f.damageCount(commander), 20);
            eq(f.opponent.getLife(), 20);
            check(!f.opponent.hasLost(), "20 commander damage is below threshold");
            f.damage(commander, 1, true);
            f.sba();
            eq(f.damageCount(commander), 21);
            eq(f.opponent.getLife(), 19);
            check(f.opponent.hasLost(), "21 commander damage eliminates despite positive life");
            f.drained();
        }
    }

    private static void ordinaryDamage(boolean fromCommander) throws Exception {
        try (Fixture f = new Fixture()) {
            Card commander = f.commander();
            f.battlefield(commander);
            Card source = fromCommander ? commander : f.bear(f.owner);
            if (!fromCommander) f.battlefield(source);
            f.damage(source, 21, !fromCommander);
            f.sba();
            eq(f.opponent.getLife(), 19);
            eq(f.damageCount(commander), 0);
            check(!f.opponent.hasLost(), "ordinary damage must not trigger commander elimination");
            f.drained();
        }
    }

    private static void differentCommanders() throws Exception {
        try (Fixture f = new Fixture()) {
            // Deliberately seeded two-commander state; not evidence of legal partner/deck construction.
            Card first = f.commander(), second = f.commander();
            f.battlefield(first);
            f.battlefield(second);
            f.damage(first, 11, true);
            f.damage(second, 10, true);
            // Avoid an unrelated legend-rule choice: move one to hand, declining replacement.
            f.answerReturn(false);
            check(f.game.getPermanent(second.getId()).moveToZone(Zone.HAND, null, f.game, true), "remove duplicate legend");
            f.sba();
            eq(f.damageCount(first), 11);
            eq(f.damageCount(second), 10);
            eq(f.opponent.getLife(), 19);
            check(!f.opponent.hasLost(), "separate commanders do not combine to 21");
            f.drained();
        }
    }

    private static void blockedCombat() throws Exception {
        try (Fixture f = new Fixture()) {
            Card commander = f.commander(), blocker = f.bear(f.opponent);
            f.battlefield(commander);
            f.battlefield(blocker);
            // Seed declared combat, then use upstream damage assignment and SBA destruction.
            f.game.getCombat().setAttacker(f.owner.getId());
            f.game.getCombat().setDefenders(f.game);
            check(f.game.getCombat().addAttackerToCombat(commander.getId(), f.opponent.getId(), f.game), "attacker added");
            CombatGroup group = f.game.getCombat().getGroups().get(0);
            group.addBlocker(blocker.getId(), f.opponent.getId(), f.game);
            check(group.getBlockers().contains(blocker.getId()), "real blocker registered");
            group.assignDamageToBlockers(false, f.game);
            group.assignDamageToAttackers(false, f.game);
            group.applyDamage(f.game);
            eq(f.game.getPermanent(commander.getId()).getDamage(), 2);
            eq(f.game.getPermanent(blocker.getId()).getDamage(), 2);
            eq(f.opponent.getLife(), 40);
            eq(f.damageCount(commander), 0);
            f.sba(); // Lethal damage moves both real 2/2 creatures into their graveyards.
            eq(f.game.getState().getZone(commander.getId()), Zone.GRAVEYARD);
            eq(f.game.getState().getZone(blocker.getId()), Zone.GRAVEYARD);
            f.answerReturn(true);
            f.sba(); // Commander return is a subsequent state-based action.
            eq(f.game.getState().getZone(commander.getId()), Zone.COMMAND);
            f.drained();
        }
    }

    private static final class Fixture implements AutoCloseable {
        final MobileCommanderGame game = new MobileCommanderGame();
        final MobileHumanPlayer owner = new MobileHumanPlayer("Commander owner");
        final MobileHumanPlayer opponent = new MobileHumanPlayer("Opponent");
        final Deque<Boolean> replies = new ArrayDeque<>();
        int queryCount;

        Fixture() {
            game.getState().addPlayer(owner);
            game.getState().addPlayer(opponent);
            owner.updateRange(game);
            opponent.updateRange(game);
            owner.setLife(40, game, null);
            opponent.setLife(40, game, null);
            game.getState().setActivePlayerId(owner.getId());
            game.getState().setPriorityPlayerId(owner.getId());
            PreCombatMainPhase phase = new PreCombatMainPhase();
            phase.setStep(new PreCombatMainStep());
            game.getTurn().setPhase(phase);
            game.getState().addWatcher(new CommanderPlaysCountWatcher());
            game.addPlayerQueryEventListener(event -> {
                if (event.getQueryType() == PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) return;
                check(event.getPlayerId().equals(owner.getId()), "only owner may choose commander return");
                check(!replies.isEmpty(), "Unexpected/repeated query: " + event.getQueryType() + " " + event.getMessage());
                DecisionSpec spec = QueryEncoder.encode(event, game);
                eq(spec.kind, "ASK");
                check(Json.requiredString(spec.payload, "message").contains("command zone"), "commander-return question");
                queryCount++;
                owner.offer(spec.validate(Json.map("kind", "boolean", "value", replies.remove())));
            });
        }

        Card commander() {
            Card card = new IsamaruHoundOfKonda(owner.getId(), new CardSetInfo("Isamaru, Hound of Konda", "CHK", "19", Rarity.RARE));
            hand(card, owner);
            game.addCommander(card, owner);
            game.initCommander(card, owner);
            eq(game.getState().getZone(card.getId()), Zone.COMMAND);
            return card;
        }
        Card bear(MobileHumanPlayer player) {
            Card card = new GrizzlyBears(player.getId(), new CardSetInfo("Grizzly Bears", "LEA", "202", Rarity.COMMON));
            hand(card, player);
            return card;
        }
        void hand(Card card, MobileHumanPlayer player) {
            game.loadCards(new HashSet<>(List.of(card)), player.getId());
            card.setZone(Zone.HAND, game);
            player.getHand().add(card);
        }
        void battlefield(Card card) {
            check(card.moveToZone(Zone.BATTLEFIELD, null, game, true), "real battlefield entry");
            check(game.getPermanent(card.getId()) != null, "real permanent exists");
        }
        boolean inZone(Card card, Zone zone) {
            return zone == Zone.GRAVEYARD ? owner.getGraveyard().contains(card.getId()) : game.getExile().getCard(card.getId(), game) != null;
        }
        void answerReturn(boolean value) { replies.add(value); }
        CommanderPlaysCountWatcher plays() { return game.getState().getWatcher(CommanderPlaysCountWatcher.class); }
        int damageCount(Card card) {
            return game.getState().getWatcher(CommanderInfoWatcher.class, card.getId()).getDamageToPlayer().getOrDefault(opponent.getId(), 0);
        }
        void damage(Card source, int amount, boolean combat) {
            eq(opponent.damage(amount, source.getId(), null, game, combat, true), amount);
        }
        void paidCast(Card card, Zone from, int expectedCost) {
            int before = owner.getManaPool().getMana().count();
            owner.getManaPool().addMana(new Mana(10, 0, 0, 0, 0, 0, 0, 0), game, card.getSpellAbility());
            SpellAbility ability = from == Zone.COMMAND ? (SpellAbility) card.getSpellAbility().copyWithZone(Zone.COMMAND) : card.getSpellAbility();
            check(owner.cast(ability, game, false, null), "real paid cast from " + from);
            eq(game.getState().getZone(card.getId()), Zone.STACK);
            eq(before + 10 - owner.getManaPool().getMana().count(), expectedCost);
        }
        void sba() throws Exception {
            // Expose one upstream SBA pass without running game-over/match cleanup on a seeded fixture.
            // No replacement implementation: virtual dispatch executes the real Commander game method.
            Method method = GameCommanderImpl.class.getDeclaredMethod("checkStateBasedActions");
            method.setAccessible(true);
            try { method.invoke(game); }
            catch (InvocationTargetException e) {
                if (e.getCause() instanceof Exception) throw (Exception) e.getCause();
                if (e.getCause() instanceof Error) throw (Error) e.getCause();
                throw e;
            }
        }
        void drained() { check(replies.isEmpty(), "all scripted owner decisions consumed"); }
        @Override public void close() { owner.closeChannel(); opponent.closeChannel(); }
    }

    private interface Test { void run() throws Exception; }
    private static void run(String name, Test test) throws Exception {
        try {
            test.run();
            passed++;
            System.out.println("PASS " + name);
        } catch (Exception | AssertionError e) {
            System.err.println("FAIL " + name);
            System.err.println("RealCommanderRulesTests: " + passed + " passed, 1 failed, " + (TOTAL - passed - 1) + " not run (fail-fast)");
            throw e;
        }
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("Expected " + expected + ", got " + actual);
    }
}
