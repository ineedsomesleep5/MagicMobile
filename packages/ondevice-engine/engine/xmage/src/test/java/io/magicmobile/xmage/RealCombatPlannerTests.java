package io.magicmobile.xmage;

import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.MobileCardFactories;
import mage.cards.decks.Deck;
import mage.cards.g.GrizzlyBears;
import mage.cards.h.HillGiant;
import mage.cards.s.SerraAngel;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.turn.*;
import mage.players.Player;
import java.util.*;
import java.util.function.BiFunction;

/**
 * Diamond and Mythic combat (CombatPlanner): the combat arithmetic and block model as unit checks,
 * then real attack and block decisions on real cards against upstream's fixed rules.
 * JVM fixture evidence; not native, full-match, calibration or device evidence.
 */
public final class RealCombatPlannerTests {
    public static void main(String[] args) throws Exception {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,ThrowingRunnable> tests = new LinkedHashMap<>();
        tests.put("tiers", RealCombatPlannerTests::tiers);
        tests.put("fights", RealCombatPlannerTests::fights);
        tests.put("defender-model", RealCombatPlannerTests::defenderModel);
        tests.put("choices", RealCombatPlannerTests::choices);
        tests.put("swarm-attack", RealCombatPlannerTests::swarmAttack);
        tests.put("holds-back-against-crack-back", RealCombatPlannerTests::holdsBack);
        tests.put("lethal-attack", RealCombatPlannerTests::lethalAttack);
        tests.put("chump-when-lethal", RealCombatPlannerTests::chumpWhenLethal);
        int passed = 0;
        for (Map.Entry<String,ThrowingRunnable> test : tests.entrySet()) {
            if (args.length > 0 && !args[0].equals(test.getKey())) continue;
            try {
                test.getValue().run();
                passed++;
                System.out.println("PASS " + test.getKey());
            } catch (Exception | AssertionError e) {
                System.err.println("FAIL " + test.getKey());
                throw e;
            }
        }
        System.out.println("RealCombatPlannerTests: " + passed + " passed");
        System.exit(0); // Upstream's AI simulation pool threads are not daemons.
    }
    interface ThrowingRunnable { void run() throws Exception; }

    /** Only Diamond (5) and up plan combat; settings and copies carry the flag. */
    private static void tiers() {
        for (int skill = 1; skill <= 10; skill++) {
            eq(AIDifficulty.plansCombat(skill), skill >= 5);
            eq(AIDifficulty.forSkill(skill, 1).plansCombat, skill >= 5);
            eq(XmageEngine.aiDifficulty(Map.of(), skill).plansCombat, skill >= 5);
        }
        eq(new AIDifficulty(4, 0, 1).plansCombat, false);
    }

    private static CombatPlanner.Unit u(String name, int power, int toughness, int value, String keywords) {
        return new CombatPlanner.Unit(name, power, toughness, value, keywords);
    }

    /** First strike, double strike, deathtouch, trample, indestructible and lifelink in one fight. */
    private static void fights() {
        CombatPlanner.Fight f = CombatPlanner.fight(u("a", 2, 2, 1, ""), u("b", 2, 2, 1, ""));
        check(f.attackerDies() && f.blockerDies(), "2/2 into 2/2 trades");
        f = CombatPlanner.fight(u("a", 2, 2, 1, "first"), u("b", 2, 2, 1, ""));
        check(!f.attackerDies() && f.blockerDies(), "first strike kills before damage back");
        f = CombatPlanner.fight(u("a", 1, 1, 1, "deathtouch"), u("b", 5, 5, 1, ""));
        check(f.attackerDies() && f.blockerDies(), "deathtouch trades up");
        f = CombatPlanner.fight(u("a", 2, 4, 1, "double"), u("b", 3, 3, 1, ""));
        check(!f.attackerDies() && f.blockerDies(), "double strike: 2 first, then 2 more as the blocker deals 3");
        f = CombatPlanner.fight(u("a", 6, 6, 1, "trample"), u("b", 2, 2, 1, ""));
        eq(f.trampleOver(), 4);
        f = CombatPlanner.fight(u("a", 3, 3, 1, "trample deathtouch"), u("b", 2, 5, 1, ""));
        eq(f.trampleOver(), 2); // one deathtouch damage is lethal
        f = CombatPlanner.fight(u("a", 5, 5, 1, ""), u("b", 1, 1, 1, "indestructible"));
        check(!f.blockerDies() && !f.attackerDies(), "indestructible blocker lives");
        f = CombatPlanner.fight(u("a", 3, 3, 1, "lifelink"), u("b", 1, 1, 1, "lifelink"));
        eq(f.attackerGain(), 3); eq(f.blockerGain(), 1);
    }

    /** The defender kills and lives first, trades evenly, chumps only against lethal. */
    private static void defenderModel() {
        CombatPlanner.Unit giant = u("giant", 3, 3, 3000, ""), bears = u("bears", 2, 2, 2000, ""), wall = u("wall", 0, 5, 1500, "");
        // Giant into a wall: the wall lives, so it blocks.
        CombatPlanner.Outcome out = CombatPlanner.predict(List.of(giant), List.of(wall, bears), all(1, 2), 40);
        check(out.blockersUsed.contains(wall.id) && !out.blockersUsed.contains(bears.id), "wall blocks: " + out.blockersUsed);
        eq(out.damage, 0);
        // Giant against bears only: no good block, no even trade, not lethal: no block.
        out = CombatPlanner.predict(List.of(giant), List.of(bears), all(1, 1), 40);
        check(out.blockersUsed.isEmpty(), "no chump at 40 life"); eq(out.damage, 3);
        // At 3 life the same giant is lethal, so bears chump.
        out = CombatPlanner.predict(List.of(giant), List.of(bears), all(1, 1), 3);
        check(out.blockersDead.contains(bears.id), "chump at 3 life"); eq(out.damage, 0);
        // Two bears into one bears: one trade, two damage through.
        CombatPlanner.Unit b1 = u("b1", 2, 2, 2000, ""), b2 = u("b2", 2, 2, 2000, "");
        out = CombatPlanner.predict(List.of(b1, b2), List.of(bears), all(2, 1), 40);
        eq(out.damage, 2); eq(out.attackersDead.size(), 1); check(out.blockersDead.contains(bears.id), "trade");
        // Menace can't be blocked by one creature, even when lethal.
        out = CombatPlanner.predict(List.of(u("m", 3, 3, 3000, "menace")), List.of(bears), all(1, 1), 3);
        eq(out.damage, 3);
    }

    /** Whole-attack choices: swarm past one blocker, keep a blocker home when the crack-back kills. */
    private static void choices() {
        CombatPlanner.Unit b1 = u("b1", 2, 2, 2000, ""), b2 = u("b2", 2, 2, 2000, ""), theirs = u("t", 2, 2, 2000, "");
        CombatPlanner.Board board = new CombatPlanner.Board(List.of(b1, b2), List.of(theirs), all(2, 1),
            List.of(theirs), List.of(), all(1, 2), 40, 40);
        eq(CombatPlanner.choose(board), 0b11L);
        // At 4 life against two 2/2s, attacking with the only blocker loses to the swing back.
        CombatPlanner.Unit giant = u("giant", 3, 3, 3000, ""), t1 = u("t1", 2, 2, 2000, ""), t2 = u("t2", 2, 2, 2000, "");
        board = new CombatPlanner.Board(List.of(giant), List.of(), all(1, 0), List.of(t1, t2), List.of(), all(2, 1), 4, 40);
        eq(CombatPlanner.choose(board), 0L);
        // Lethal now beats any risk.
        board = new CombatPlanner.Board(List.of(giant), List.of(), all(1, 0), List.of(t1, t2), List.of(), all(2, 1), 4, 3);
        eq(CombatPlanner.choose(board), 1L);
        // Twelve attackers use hill-climbing and still find the alpha strike into an empty board.
        List<CombatPlanner.Unit> many = new ArrayList<>();
        for (int i = 0; i < 12; i++) many.add(u("x" + i, 1, 1, 1000, ""));
        board = new CombatPlanner.Board(many, List.of(), all(12, 0), List.of(), List.of(), all(0, 12), 40, 40);
        eq(CombatPlanner.choose(board), (1L << 12) - 1);
    }
    private static boolean[][] all(int rows, int cols) {
        boolean[][] out = new boolean[rows][cols];
        for (boolean[] row : out) Arrays.fill(row, true);
        return out;
    }

    /** Two bears into one: upstream's rule never attacks into an equal blocker; the planner sends both. */
    private static void swarmAttack() throws Exception {
        for (int skill : new int[]{4, 6}) {
            try (Board b = new Board(skill)) {
                Card a1 = b.permanent(b.ai, GrizzlyBears::new, "Grizzly Bears");
                Card a2 = b.permanent(b.ai, GrizzlyBears::new, "Grizzly Bears");
                b.permanent(b.human, GrizzlyBears::new, "Grizzly Bears");
                b.attackStep(b.ai);
                b.ai.selectAttackers(b.game, b.ai.getId());
                Set<UUID> attackers = b.game.getCombat().getAttackers();
                eq(attackers.contains(a1.getId()) && attackers.contains(a2.getId()), skill == 6);
                if (skill == 4) eq(attackers.size(), 0);
            }
        }
    }

    /** At 4 life, upstream sends the Hill Giant (no blocker can kill it) and dies to the swing back. */
    private static void holdsBack() throws Exception {
        for (int skill : new int[]{4, 6}) {
            try (Board b = new Board(skill)) {
                Card giant = b.permanent(b.ai, HillGiant::new, "Hill Giant");
                b.permanent(b.human, GrizzlyBears::new, "Grizzly Bears");
                b.permanent(b.human, GrizzlyBears::new, "Grizzly Bears");
                b.ai.setLife(4, b.game, null);
                b.attackStep(b.ai);
                b.ai.selectAttackers(b.game, b.ai.getId());
                eq(b.game.getCombat().getAttackers().contains(giant.getId()), skill == 4);
            }
        }
    }

    /** A flier for exactly lethal goes in even though the crack-back would kill the AI. */
    private static void lethalAttack() throws Exception {
        try (Board b = new Board(6)) {
            Card angel = b.permanent(b.ai, SerraAngel::new, "Serra Angel");
            b.permanent(b.human, HillGiant::new, "Hill Giant");
            b.permanent(b.human, HillGiant::new, "Hill Giant");
            b.ai.setLife(2, b.game, null); b.human.setLife(4, b.game, null);
            b.attackStep(b.ai);
            b.ai.selectAttackers(b.game, b.ai.getId());
            check(b.game.getCombat().getAttackers().contains(angel.getId()), "lethal flier attacks");
        }
    }

    /** Facing lethal with no blocks declared, the planner chumps the biggest attacker. */
    private static void chumpWhenLethal() throws Exception {
        try (Board b = new Board(6)) {
            Card bears = b.permanent(b.ai, GrizzlyBears::new, "Grizzly Bears");
            Card giant = b.permanent(b.human, HillGiant::new, "Hill Giant");
            b.ai.setLife(3, b.game, null);
            b.attackStep(b.human);
            check(b.game.getCombat().declareAttacker(giant.getId(), b.ai.getId(), b.human.getId(), b.game), "real attack");
            DeclareBlockersStep step = new DeclareBlockersStep();
            CombatPhase phase = new CombatPhase(); phase.setStep(step); b.game.getTurn().setPhase(phase);
            eq(CombatPlanner.chumpIfLethal(b.ai, b.game), 1);
            check(b.game.getCombat().getBlockers().contains(bears.getId()), "bears chump the giant");
            eq(CombatPlanner.chumpIfLethal(b.ai, b.game), 0); // already blocked: nothing lethal left
        }
    }

    /** A two-player game with the given AI skill, its permanents free of summoning sickness. */
    private static final class Board implements AutoCloseable {
        final MobileHumanPlayer human = new MobileHumanPlayer("Human");
        final MobileAICancellation cancellation = new MobileAICancellation();
        final Player ai;
        final MobileCommanderGame game;

        Board(int skill) throws Exception {
            ai = cancellation.player("AI", skill, AIDifficulty.forSkill(skill, 1));
            MobileCommanderMatch match = new MobileCommanderMatch();
            match.addPlayer(human, new Deck()); match.addPlayer(ai, new Deck());
            match.startMatch(); match.startGame();
            game = (MobileCommanderGame) match.getGame();
            cancellation.bind(game);
            for (Player player : List.of(human, ai)) { player.updateRange(game); player.setLife(40, game, null); }
            game.getState().setActivePlayerId(ai.getId());
            game.getState().setPriorityPlayerId(ai.getId());
            game.getPlayerList().setCurrent(ai.getId());
        }
        Card permanent(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = constructor.apply(owner.getId(), new CardSetInfo(name, "M10", "1", Rarity.COMMON));
            game.loadCards(new HashSet<>(List.of(card)), owner.getId());
            card.setZone(Zone.HAND, game); owner.getHand().add(card);
            check(owner.moveCards(card, Zone.BATTLEFIELD, null, game), "real move to battlefield");
            UUID active = game.getActivePlayerId();
            game.getState().setActivePlayerId(owner.getId());
            game.getPermanent(card.getId()).beginningOfTurn(game); // no summoning sickness
            game.getState().setActivePlayerId(active);
            return card;
        }
        void attackStep(Player attacker) {
            game.getState().setActivePlayerId(attacker.getId());
            CombatPhase phase = new CombatPhase(); phase.setStep(new DeclareAttackersStep()); game.getTurn().setPhase(phase);
            game.getCombat().clear();
            game.getCombat().setAttacker(attacker.getId());
            game.getCombat().setDefenders(game);
        }
        @Override public void close() { human.closeChannel(); cancellation.close(); }
    }

    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("expected " + expected + " but was " + actual);
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
}
