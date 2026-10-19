package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.MobileCardFactories;
import mage.cards.basiclands.Forest;
import mage.cards.basiclands.Mountain;
import mage.cards.decks.Deck;
import mage.cards.g.GrizzlyBears;
import mage.cards.h.HillGiant;
import mage.cards.l.LightningBolt;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.stack.StackObject;
import mage.game.turn.*;
import mage.player.ai.ComputerPlayer6;
import mage.players.Player;
import java.lang.reflect.Field;
import java.util.*;
import java.util.function.BiFunction;

/**
 * Easier AI at skills 1 to 3: the depth curve, the seeded mistake rolls and their settings
 * (unit checks), then real upstream search, attack and block decisions on real cards.
 * JVM fixture evidence; not native, full-match, calibration or device evidence.
 */
public final class RealAIDifficultyTests {
    public static void main(String[] args) throws Exception {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,ThrowingRunnable> tests = new LinkedHashMap<>();
        tests.put("curve", RealAIDifficultyTests::curve);
        tests.put("seeded-rolls", RealAIDifficultyTests::seededRolls);
        tests.put("settings", RealAIDifficultyTests::settings);
        tests.put("copies-keep-difficulty", RealAIDifficultyTests::copiesKeepDifficulty);
        tests.put("depth-plays", RealAIDifficultyTests::depthPlays);
        tests.put("play-mistake", RealAIDifficultyTests::playMistake);
        tests.put("attack-mistake", RealAIDifficultyTests::attackMistake);
        tests.put("block-mistake", RealAIDifficultyTests::blockMistake);
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
        System.out.println("RealAIDifficultyTests: " + passed + " passed");
        System.exit(0); // Upstream's AI simulation pool threads are not daemons.
    }
    interface ThrowingRunnable { void run() throws Exception; }

    /** Skills 1 and 2 look one and two actions ahead; 3 and up keep upstream; mistakes only at 1 to 3. */
    private static void curve() {
        int[] depth = {2, 3, 4, 4, 5, 6, 7, 8, 9, 10};
        int[] mistakes = {15, 15, 10, 0, 0, 0, 0, 0, 0, 0};
        for (int skill = 1; skill <= 10; skill++) {
            eq(AIDifficulty.searchDepth(skill), depth[skill - 1]);
            eq(AIDifficulty.mistakePercent(skill), mistakes[skill - 1]);
            if (skill >= 3) eq(AIDifficulty.searchDepth(skill), Math.max(4, skill)); // upstream ComputerPlayer6
        }
        for (int invalid : new int[]{0, 11}) {
            expectIllegal(() -> AIDifficulty.searchDepth(invalid));
            expectIllegal(() -> AIDifficulty.mistakePercent(invalid));
        }
        expectIllegal(() -> new AIDifficulty(0, 0, 1));
        expectIllegal(() -> new AIDifficulty(4, 101, 1));
        expectIllegal(() -> new AIDifficulty(4, -1, 1));
    }

    /** One seed, one sequence; the rate matches the percent; 0 never and 100 always. */
    private static void seededRolls() {
        for (long seed : new long[]{0, 1, -7, Long.MIN_VALUE, 20261015}) {
            List<Boolean> first = rolls(seed, 30, 200), second = rolls(seed, 30, 200);
            eq(first, second);
            check(!first.equals(rolls(seed + 1, 30, 200)), "a different seed gives a different sequence");
        }
        for (int percent : new int[]{0, 5, 10, 15, 50, 100}) {
            long hits = rolls(42, percent, 100_000).stream().filter(Boolean::booleanValue).count();
            double rate = hits / 1000.0; // percent
            check(Math.abs(rate - percent) < 0.5, percent + "% rolls hit " + rate + "%");
            if (percent == 0) eq(hits, 0L);
            if (percent == 100) eq(hits, 100_000L);
        }
    }
    private static List<Boolean> rolls(long seed, int percent, int count) {
        List<Boolean> out = new ArrayList<>();
        long state = seed;
        for (int i = 0; i < count; i++) { state = AIDifficulty.next(state); out.add(AIDifficulty.rolls(state, percent)); }
        return out;
    }

    /** Seat settings: skill defaults, overrides for calibration, strict bounds. */
    private static void settings() {
        for (int skill = 1; skill <= 10; skill++) {
            AIDifficulty defaults = XmageEngine.aiDifficulty(Map.of(), skill);
            eq(defaults.searchDepth, AIDifficulty.searchDepth(skill));
            eq(defaults.mistakePercent, AIDifficulty.mistakePercent(skill));
        }
        AIDifficulty custom = XmageEngine.aiDifficulty(Json.map("aiSearchDepth", 7, "aiMistakePercent", 0,
            "aiSeed", new java.math.BigDecimal(Long.toString(Long.MIN_VALUE))), 1);
        eq(custom.searchDepth, 7); eq(custom.mistakePercent, 0); eq(custom.seed, Long.MIN_VALUE);
        eq(XmageEngine.aiDifficulty(Json.map("aiMistakePercent", 100), 6).mistakePercent, 100);
        for (Object[] invalid : new Object[][]{{"aiSearchDepth", 0}, {"aiSearchDepth", 11}, {"aiMistakePercent", 101},
                {"aiMistakePercent", -1}, {"aiSeed", "1"}, {"aiSeed", new java.math.BigDecimal("1e30")}}) {
            try {
                XmageEngine.aiDifficulty(Json.map((String) invalid[0], invalid[1]), 2);
                throw new AssertionError("accepted " + Arrays.toString(invalid));
            } catch (BridgeException e) { eq(e.code(), "invalid_ai_skill"); }
        }
    }

    /** XMage copies players for every projection and simulation; copies keep depth, chance and generator state. */
    private static void copiesKeepDifficulty() throws Exception {
        MobileAICancellation cancellation = new MobileAICancellation();
        Player ai = cancellation.player("AI", 2, new AIDifficulty(3, 10, 99));
        Player copy = ai.copy();
        eq(field(copy, ComputerPlayer6.class, "maxDepth"), 3);
        eq(field(copy, ai.getClass(), "mistakePercent"), 10);
        eq(field(copy, ai.getClass(), "mistakeState"), 99L);
        eq(field(copy, ComputerPlayer6.class, "maxThinkTimeSecs"), 6); // think time still follows skill
    }

    /**
     * Real search on a real board. Upstream depth 1 scores a spell while it is still on the stack, so
     * it never casts one (the reason skill 1 uses depth 2). Depth 2 and 3 cast the obvious creature.
     */
    private static void depthPlays() throws Exception {
        for (int depth : new int[]{1, 2, 3}) {
            try (Board b = new Board(new AIDifficulty(depth, 0, 1))) {
                b.permanent(b.ai, Forest::new, "Forest"); b.permanent(b.ai, Forest::new, "Forest");
                b.hand(b.ai, GrizzlyBears::new, "Grizzly Bears");
                b.aiPriority();
                eq(b.stackNames(), depth == 1 ? List.of() : List.of("Grizzly Bears"));
                eq(MobileAICancellation.mistakes(b.ai), 0);
            }
        }
    }

    /**
     * With a 100% chance the AI never makes the play its own search chose: it takes the best other play
     * that scores no worse than doing nothing, or passes. With 0% it always makes the chosen play.
     */
    private static void playMistake() throws Exception {
        for (int run = 0; run < 3; run++) {
            String chosen, chosenText, mistaken;
            try (Board b = new Board(new AIDifficulty(2, 0, run))) {
                b.boltBoard();
                b.aiPriority();
                chosen = b.stackDescription();
                chosenText = b.readable(chosen);
                check(!chosen.isEmpty(), "the search plays something");
                eq(MobileAICancellation.mistakes(b.ai), 0);
            }
            try (Board b = new Board(new AIDifficulty(2, 100, run))) {
                b.boltBoard();
                b.aiPriority();
                mistaken = b.stackDescription();
                eq(MobileAICancellation.mistakes(b.ai), 1);
                check(!mistaken.equals(chosen), "a mistake changes the play: " + chosen);
                // Never a play worse than passing: it doesn't bolt its own creature.
                check(!mistaken.contains("target=" + b.aiCreature), "no self-harm: " + mistaken);
                System.out.println("  seed " + run + ": chose [" + chosenText + "], mistake [" + b.readable(mistaken) + "]");
            }
        }
    }

    /** 100%: the AI holds back an attack it would make, unless the attack might be lethal. */
    private static void attackMistake() throws Exception {
        for (int percent : new int[]{0, 100}) {
            try (Board b = new Board(new AIDifficulty(2, percent, 5))) {
                Card giant = b.permanent(b.ai, HillGiant::new, "Hill Giant");
                b.attackStep(b.ai);
                b.ai.selectAttackers(b.game, b.ai.getId());
                boolean attacked = b.game.getCombat().getAttackers().contains(giant.getId());
                check(attacked == (percent == 0), percent + "%: attacked=" + attacked);
                eq(MobileAICancellation.mistakes(b.ai), percent == 100 ? 1 : 0);
            }
        }
        try (Board b = new Board(new AIDifficulty(2, 100, 5))) {
            Card giant = b.permanent(b.ai, HillGiant::new, "Hill Giant");
            b.human.setLife(3, b.game, null);
            b.attackStep(b.ai);
            b.ai.selectAttackers(b.game, b.ai.getId());
            check(b.game.getCombat().getAttackers().contains(giant.getId()), "a possibly lethal attack is never held back");
            eq(MobileAICancellation.mistakes(b.ai), 0);
        }
    }

    /** 100%: the AI skips a good block, unless the attack would cost it half its life or more. */
    private static void blockMistake() throws Exception {
        for (int life : new int[]{40, 4}) for (int percent : new int[]{0, 100}) {
            try (Board b = new Board(new AIDifficulty(2, percent, 5))) {
                Card giant = b.permanent(b.ai, HillGiant::new, "Hill Giant");
                Card bears = b.permanent(b.human, GrizzlyBears::new, "Grizzly Bears");
                b.ai.setLife(life, b.game, null);
                b.attackStep(b.human);
                check(b.game.getCombat().declareAttacker(bears.getId(), b.ai.getId(), b.human.getId(), b.game), "real attack");
                DeclareBlockersStep step = new DeclareBlockersStep();
                CombatPhase phase = new CombatPhase(); phase.setStep(step); b.game.getTurn().setPhase(phase);
                b.ai.selectBlockers(null, b.game, b.ai.getId());
                boolean blocked = b.game.getCombat().getBlockers().contains(giant.getId());
                boolean mistake = percent == 100 && life == 40;
                check(blocked == !mistake, "life " + life + ", " + percent + "%: blocked=" + blocked);
                eq(MobileAICancellation.mistakes(b.ai), mistake ? 1 : 0);
            }
        }
    }

    /** A two-player game in the AI's precombat main phase, with the AI holding priority. */
    private static final class Board implements AutoCloseable {
        final MobileHumanPlayer human = new MobileHumanPlayer("Human");
        final MobileAICancellation cancellation = new MobileAICancellation();
        final Player ai;
        final MobileCommanderGame game;
        UUID aiCreature;

        Board(AIDifficulty difficulty) throws Exception {
            ai = cancellation.player("AI", 1, difficulty);
            MobileCommanderMatch match = new MobileCommanderMatch();
            match.addPlayer(human, new Deck()); match.addPlayer(ai, new Deck());
            match.startMatch(); match.startGame();
            game = (MobileCommanderGame) match.getGame();
            cancellation.bind(game);
            for (Player player : List.of(human, ai)) { player.updateRange(game); player.setLife(20, game, null); }
            game.getState().setActivePlayerId(ai.getId());
            game.getState().setPriorityPlayerId(ai.getId());
            game.getPlayerList().setCurrent(ai.getId()); // the search simulates whoever this points at
            PreCombatMainPhase phase = new PreCombatMainPhase();
            phase.setStep(new PreCombatMainStep()); game.getTurn().setPhase(phase);
        }
        Card card(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = constructor.apply(owner.getId(), new CardSetInfo(name, "M10", "1", Rarity.COMMON));
            game.loadCards(new HashSet<>(List.of(card)), owner.getId());
            return card;
        }
        Card hand(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = card(owner, constructor, name);
            card.setZone(Zone.HAND, game); owner.getHand().add(card);
            return card;
        }
        Card permanent(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = hand(owner, constructor, name);
            check(owner.moveCards(card, Zone.BATTLEFIELD, null, game), "real move to battlefield");
            UUID active = game.getActivePlayerId();
            game.getState().setActivePlayerId(owner.getId());
            game.getPermanent(card.getId()).beginningOfTurn(game); // no summoning sickness
            game.getState().setActivePlayerId(active);
            return card;
        }
        /** Bolt in hand with a Mountain; a creature on each side, so there is more than one sensible target. */
        void boltBoard() {
            permanent(ai, Mountain::new, "Mountain");
            permanent(human, GrizzlyBears::new, "Grizzly Bears");
            aiCreature = permanent(ai, GrizzlyBears::new, "Grizzly Bears").getId();
            hand(ai, LightningBolt::new, "Lightning Bolt");
        }
        void aiPriority() { ai.priority(game); }
        void attackStep(Player attacker) {
            game.getState().setActivePlayerId(attacker.getId());
            CombatPhase phase = new CombatPhase(); phase.setStep(new DeclareAttackersStep()); game.getTurn().setPhase(phase);
            game.getCombat().clear();
            game.getCombat().setAttacker(attacker.getId());
            game.getCombat().setDefenders(game);
        }
        List<String> stackNames() {
            List<String> names = new ArrayList<>();
            for (StackObject object : game.getStack()) names.add(object.getName());
            return names;
        }
        /** Each stack object with its targets; empty when the AI passed. */
        String stackDescription() {
            StringBuilder out = new StringBuilder();
            for (StackObject object : game.getStack()) {
                out.append(object.getName());
                object.getStackAbility().getAllSelectedTargets().forEach(t -> t.getTargets().forEach(id -> out.append(" target=").append(id)));
                out.append(';');
            }
            return out.toString();
        }
        /** Target IDs as who they are, for the test log. */
        String readable(String description) {
            if (description.isEmpty()) return "pass";
            for (Player player : List.of(human, ai))
                description = description.replace(player.getId().toString(), player.getName());
            for (var permanent : game.getBattlefield().getAllPermanents())
                description = description.replace(permanent.getId().toString(),
                    permanent.getName() + " of " + game.getPlayer(permanent.getControllerId()).getName());
            return description;
        }
        @Override public void close() { human.closeChannel(); cancellation.close(); }
    }

    private static Object field(Object target, Class<?> owner, String name) throws Exception {
        Field field = owner.getDeclaredField(name); field.setAccessible(true); return field.get(target);
    }
    private static void expectIllegal(Runnable action) {
        try { action.run(); } catch (IllegalArgumentException expected) { return; }
        throw new AssertionError("expected IllegalArgumentException");
    }
    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("expected " + expected + " but was " + actual);
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
}
