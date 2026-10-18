package io.magicmobile.xmage;

import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.Card;
import mage.cards.CardSetInfo;
import mage.cards.MobileCardFactories;
import mage.cards.basiclands.Forest;
import mage.cards.basiclands.Mountain;
import mage.cards.decks.Deck;
import mage.cards.e.EvolvingWilds;
import mage.cards.f.FlametongueKavu;
import mage.cards.g.GrizzlyBears;
import mage.cards.h.HillGiant;
import mage.cards.l.LightningBolt;
import mage.cards.l.LoamingShaman;
import mage.cards.w.WoodElves;
import mage.constants.Rarity;
import mage.constants.Zone;
import mage.game.Game;
import mage.game.GameImpl;
import mage.game.stack.StackObject;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.player.ai.ComputerPlayer6;
import mage.player.ai.SimulationNode2;
import mage.players.Player;
import mage.util.RandomUtil;
import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.function.BiFunction;

/**
 * AI search memory (docs/LIGHTER_ENGINE_PLAN.md, step 3) on real cards: copies of a simulation copy their cards on
 * first use and hand out the same card states as deep copies; the search makes the same choice, scores and node
 * count with and without that and with and without searching a library search's targets one at a time; the copy cap
 * stops a search the way running out of time does; a decided search drops its copies; the memory reading.
 * JVM fixture evidence; not native, calibration or device evidence.
 */
public final class RealSearchMemoryTests {
    public static void main(String[] args) throws Exception {
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
        Map<String,ThrowingRunnable> tests = new LinkedHashMap<>();
        tests.put("lazy-cards", RealSearchMemoryTests::lazyCards);
        tests.put("same-search", RealSearchMemoryTests::sameSearch);
        tests.put("cap", RealSearchMemoryTests::cap);
        tests.put("trigger-fan-out", RealSearchMemoryTests::triggerFanOut);
        tests.put("abandoned-search-stops", RealSearchMemoryTests::abandonedSearchStops);
        tests.put("cap-counts-other-searches", RealSearchMemoryTests::capCountsOtherSearches);
        tests.put("released-after-decision", RealSearchMemoryTests::releasedAfterDecision);
        tests.put("copy-size", RealSearchMemoryTests::copySize);
        tests.put("device-memory", RealSearchMemoryTests::deviceMemory);
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
        System.out.println("RealSearchMemoryTests: " + passed + " passed");
        System.exit(0); // Upstream's AI simulation pool threads are not daemons.
    }
    interface ThrowingRunnable { void run() throws Exception; }

    /**
     * A copy of a simulation shares cards until it uses them; neither game sees the other's changes made after the
     * copy, exactly as with a deep copy. Copies of the live game, and copies made while a trigger is handled, still
     * deep-copy every card.
     */
    private static void lazyCards() throws Exception {
        try (Board b = new Board(new AIDifficulty(3, 0, 1))) {
            UUID inLibrary = b.library(b.ai, Forest::new, "Forest").getId();
            UUID inHand = b.hand(b.ai, GrizzlyBears::new, "Grizzly Bears").getId();
            UUID other = b.library(b.ai, Mountain::new, "Mountain").getId();
            Game live = b.game;
            Game liveCopy = live.copy();
            check(owned(liveCopy) == null, "a copy of the live game owns all its cards");
            check(liveCopy.getCard(inLibrary) != live.getCard(inLibrary), "and they are its own");
            Game root = live.createSimulationForAI();
            check(owned(root) == null, "the AI's root simulation is a deep copy of the live game");
            Game child = root.createSimulationForAI();
            check(owned(child) != null && owned(child).isEmpty() && owned(root).isEmpty(), "a copy of a simulation shares");
            Card childCard = child.getCard(inLibrary);
            check(childCard != null && childCard != rawCard(root, inLibrary) && child.getCard(inLibrary) == childCard,
                "the first use copies the card once");
            eq(owned(child), Set.of(inLibrary));
            UUID newOwner = UUID.randomUUID();
            childCard.setOwnerId(newOwner); // a change the copy makes to its own card
            eq(root.getCard(inLibrary).getOwnerId(), b.ai.getId());
            Game sibling = root.createSimulationForAI();
            eq(sibling.getCard(inLibrary).getOwnerId(), b.ai.getId());
            Game grandchild = child.createSimulationForAI();
            eq(grandchild.getCard(inLibrary).getOwnerId(), newOwner); // copied after the change: sees it
            // The source shares too: its change after a copy stays its own.
            Game before = root.createSimulationForAI();
            root.getCard(inHand).setOwnerId(newOwner);
            eq(before.getCard(inHand).getOwnerId(), b.ai.getId());
            // getCards hands out every card, so it copies every shared one first, in the deep copy's order.
            Game all = root.createSimulationForAI();
            List<UUID> order = new ArrayList<>();
            GameImpl.mobileLazyCards = false;
            try { for (Card card : root.createSimulationForAI().getCards()) order.add(card.getId()); }
            finally { GameImpl.mobileLazyCards = true; }
            List<UUID> lazyOrder = new ArrayList<>();
            for (Card card : all.getCards()) {
                lazyOrder.add(card.getId());
                check(card != rawCard(root, card.getId()), "getCards copies " + card.getName());
            }
            eq(lazyOrder, order);
            check(owned(all) == null && all.getCard(other) == all.getCard(other), "then it owns them all");
            // While a player handles a trigger (an AI's trigger options copy the game mid-way), copies are deep.
            Field triggering = GameImpl.class.getDeclaredField("mobileTriggering");
            triggering.setAccessible(true);
            triggering.setInt(root, 1);
            check(owned(root.createSimulationForAI()) == null, "copies during a trigger are deep");
            triggering.setInt(root, 0);
            // The equivalence switch.
            GameImpl.mobileLazyCards = false;
            try { check(owned(root.createSimulationForAI()) == null, "switch off: deep copies"); }
            finally { GameImpl.mobileLazyCards = true; }
        }
    }

    /**
     * The same search on copies of one position, with card copies on first use and the one-at-a-time library search
     * each on and off (off and off is upstream): the same move, score and node count every time. Library searches
     * (Evolving Wilds; Wood Elves' trigger) fan out over every basic land in the library.
     */
    private static void sameSearch() throws Exception {
        List<String> boards = List.of("bolt", "fetch", "trigger");
        for (String board : boards) {
            try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
                b.setUp(board);
                List<String> results = new ArrayList<>();
                String expected = null;
                for (boolean lazy : new boolean[]{false, true}) for (boolean oneAtATime : new boolean[]{false, true}) {
                    GameImpl.mobileLazyCards = lazy;
                    ComputerPlayer6.mobileSearchMemory = oneAtATime;
                    try {
                        Search search = b.search(20261018L);
                        results.add(board + " lazy=" + lazy + " one-at-a-time=" + oneAtATime + ": " + search);
                        if (expected == null) expected = search.decision();
                        eq(search.decision(), expected);
                    } finally {
                        GameImpl.mobileLazyCards = true;
                        ComputerPlayer6.mobileSearchMemory = true;
                    }
                }
                results.forEach(line -> System.out.println("  " + line));
            }
        }
    }

    /**
     * A search at its cap stops and plays the best line it had, like one out of time. Upstream's eager library search
     * holds one copy per basic land in the library and passes a 32-copy cap; one at a time, the same search stays
     * far under it.
     */
    private static void cap() throws Exception {
        DeviceMemory.install(() -> 1); // the smallest cap, AISearchMemory.MIN_COPIES
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("fetch");
            for (int i = 0; i < 40; i++) b.library(b.ai, Forest::new, "Forest");
            ComputerPlayer6.mobileSearchMemory = false;
            Search eager;
            try { eager = b.search(5L); } finally { ComputerPlayer6.mobileSearchMemory = true; }
            AISearchMemory capped = AISearchMemory.last;
            eq(capped.cap, AISearchMemory.MIN_COPIES);
            check(capped.capped, "the eager library search reaches the cap: " + eager);
            check(capped.peak >= capped.cap, "it counted the copies alive: " + capped.peak);
            check(!eager.decision().isEmpty(), "and still plays its best line so far: " + eager);
            Search oneAtATime = b.search(5L);
            AISearchMemory under = AISearchMemory.last;
            check(!under.capped && under.peak < under.cap, "one at a time stays under the cap: peak " + under.peak);
            System.out.println("  eager: " + eager + ", peak " + capped.peak + " of " + capped.cap
                + "; one at a time: " + oneAtATime + ", peak " + under.peak);
        } finally {
            DeviceMemory.install(null);
        }
    }

    /**
     * Loaming Shaman's trigger ("any number of target cards" from a graveyard) lists every set of up to four cards of
     * the graveyard, and the AI copies the whole game, cards included, for each option while it handles the trigger
     * (SimulatedPlayer2.triggerAbility), before its search enters that node. The cap counts those copies at their
     * deep size, and the search makes no copy past it: the fan-out that ran release C's calibration games out of
     * memory, where nothing counted it and nothing stopped it.
     */
    private static void triggerFanOut() throws Exception {
        DeviceMemory.install(() -> 1); // the smallest cap, AISearchMemory.MIN_COPIES
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("shaman");
            Search search = b.search(5L);
            AISearchMemory memory = AISearchMemory.last;
            check(memory.capped, "the trigger's copies reach the cap: " + search + ", peak " + memory.peak);
            check(memory.deepCopyBytes > memory.copyBytes, "a trigger's copies count at their deep size");
            // Each of the 795 options would copy the game; the search stops at the cap instead.
            check(search.copies() < 4 * memory.cap, "no copies past the cap: " + search + ", cap " + memory.cap);
            check(AISearchMemory.abandonedRunning() == 0, "nothing left running");
            System.out.println("  " + search + ", peak " + memory.peak + " of " + memory.cap);
        } finally {
            DeviceMemory.install(null);
        }
    }

    /**
     * A search the AI stopped waiting for (out of time) is abandoned: its thread makes no further game copy and
     * enters no further node, even in code that never checks the interrupt (a trigger's fan-out), and its copies are
     * freed once it has unwound and the AI has decided. The next search waits for that. A search whose task was still
     * queued never runs.
     */
    private static void abandonedSearchStops() throws Exception {
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("bolt");
            Game rootGame = b.game.createSimulationForAI();
            SimulationNode2 root = new SimulationNode2(null, rootGame, 4, b.ai.getId());
            AISearchMemory search = AISearchMemory.start(root, List::of);
            int[] made = {0};
            CountDownLatch copying = new CountDownLatch(1);
            AtomicReference<Throwable> ended = new AtomicReference<>();
            Thread thread = new Thread(() -> {
                AISearchMemory entered = null;
                try {
                    entered = AISearchMemory.enter(search, root);
                    while (true) { // copies, as a trigger's options do, without looking at the interrupt
                        rootGame.createSimulationForAI();
                        made[0]++;
                        copying.countDown();
                    }
                } catch (Throwable stop) { ended.set(stop); }
                finally { AISearchMemory.leave(entered); }
            }, "AI-SIM-MAD abandoned-search test");
            thread.start();
            check(copying.await(10, TimeUnit.SECONDS), "the search copies");
            thread.interrupt(); // upstream's only signal: ignored by the loop
            search.returned(); // the AI stopped waiting for it
            check(AISearchMemory.awaitAbandoned(5000), "it stops at its next copy");
            thread.join(5000);
            check(ended.get() instanceof AISearchMemory.Stopped, "stopped: " + ended.get());
            check(root.getGame() != null, "its copies stay until the AI decides");
            search.decided(List.of());
            check(root.getGame() == null, "then they are freed");
            // A search whose task was still queued when the AI stopped waiting.
            SimulationNode2 queuedRoot = new SimulationNode2(null, b.game.createSimulationForAI(), 4, b.ai.getId());
            AISearchMemory queued = AISearchMemory.start(queuedRoot, List::of);
            queued.returned();
            eq(AISearchMemory.abandonedRunning(), 0);
            try {
                AISearchMemory.enter(queued, queuedRoot);
                throw new AssertionError("a late task must not start");
            } catch (AISearchMemory.Stopped expected) { /* refused before touching its node */ }
            queued.decided(List.of());
            check(queuedRoot.getGame() == null, "the queued search's copy is freed");
            System.out.println("  abandoned after " + made[0] + " copies; stopped at the next one");
        }
    }

    /**
     * The cap covers every search whose copies are not freed yet, not just the one running: an abandoned search
     * still unwinding, or this decision's quick search, holds memory the new search must leave room for.
     */
    private static void capCountsOtherSearches() throws Exception {
        DeviceMemory.install(() -> 400L << 20);
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("fetch");
            Search alone = b.search(5L);
            AISearchMemory free = AISearchMemory.last;
            check(!free.capped, "alone, the search stays under its cap: " + alone + ", peak " + free.peak + " of " + free.cap);
            SimulationNode2 otherRoot = new SimulationNode2(null, b.game.createSimulationForAI(), 4, b.ai.getId());
            AISearchMemory other = AISearchMemory.start(otherRoot, List::of);
            other.heldBytes = (free.cap - free.peak / 2) * free.copyBytes; // another search holding most of the budget
            try {
                Search squeezed = b.search(5L);
                check(AISearchMemory.last.capped, "the other search's copies count: " + squeezed);
            } finally {
                other.returned();
                other.decided(List.of());
            }
            Search again = b.search(5L);
            check(!AISearchMemory.last.capped, "once they are freed, the room is back: " + again);
            eq(again.decision(), alone.decision());
        } finally {
            DeviceMemory.install(null);
        }
    }

    /** Once the AI has decided, its search tree (the plan it keeps included) holds no game copy. */
    private static void releasedAfterDecision() throws Exception {
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("fetch");
            b.ai.priority(b.game);
            SimulationNode2 kept = (SimulationNode2) field(b.ai, ComputerPlayer6.class, "root");
            check(kept != null && kept.getAbilities() != null, "the AI keeps its plan");
            for (SimulationNode2 node = kept; node != null; node = node.getParent())
                check(node.getGame() == null, "no copy above the plan");
            for (SimulationNode2 node = kept; node != null; node = node.getChildren().isEmpty() ? null : node.getChildren().get(0))
                check(node.getGame() == null, "no copy in the plan");
            AISearchMemory last = AISearchMemory.last;
            check(last.root.getGame() == null, "the search's root copy is dropped");
        }
    }

    /**
     * What one copy of a search keeps alive, against AISearchMemory's estimate: copies of a simulation that listed
     * their options (the copies a search makes), held, with the heap measured after full collections.
     */
    private static void copySize() throws Exception {
        try (Board b = new Board(new AIDifficulty(4, 0, 7))) {
            b.setUp("trigger");
            for (int i = 0; i < 60; i++) b.library(b.ai, i % 2 == 0 ? Forest::new : Mountain::new, i % 2 == 0 ? "Forest" : "Mountain");
            for (int i = 0; i < 60; i++) b.library(b.human, GrizzlyBears::new, "Grizzly Bears");
            for (int i = 0; i < 6; i++) b.permanent(b.human, HillGiant::new, "Hill Giant");
            Game root = b.game.createSimulationForAI();
            long estimate = AISearchMemory.copyBytes(root);
            Game[] held = new Game[24];
            long before = liveHeap();
            for (int i = 0; i < held.length; i++) {
                held[i] = root.createSimulationForAI();
                held[i].getPlayer(b.ai.getId()).getPlayable(held[i], true); // touches what listing options touches
            }
            long measured = (liveHeap() - before) / held.length;
            GameImpl.mobileLazyCards = false;
            Game[] deep = new Game[24];
            long deepBefore;
            try {
                held = null;
                deepBefore = liveHeap();
                for (int i = 0; i < deep.length; i++) deep[i] = root.createSimulationForAI();
            } finally { GameImpl.mobileLazyCards = true; }
            long deepMeasured = (liveHeap() - deepBefore) / deep.length;
            System.out.println("  " + b.game.getCards().size() + " cards, " + b.game.getBattlefield().getAllPermanents().size()
                + " permanents: a search copy keeps " + measured / 1024 + " KB alive (deep copy " + deepMeasured / 1024
                + " KB); estimate " + estimate / 1024 + " KB");
            check(measured < deepMeasured, "a lazy copy keeps less than a deep one");
            check(estimate >= measured, "the estimate does not undercount");
            Objects.requireNonNull(deep[0]);
        }
    }

    /** /proc/meminfo's MemAvailable, the JVM tools' stand-in, and an installed platform reading. */
    private static void deviceMemory() throws Exception {
        Path meminfo = Files.createTempFile("meminfo", ".txt");
        try {
            Files.writeString(meminfo, "MemTotal:       16000000 kB\nMemFree:         1000 kB\nMemAvailable:    2300000 kB\n");
            eq(DeviceMemory.memAvailable(meminfo), 2300000L * 1024);
            Files.writeString(meminfo, "MemTotal: 1 kB\n");
            eq(DeviceMemory.memAvailable(meminfo), -1L);
            eq(DeviceMemory.memAvailable(meminfo.resolveSibling("missing-meminfo")), -1L);
        } finally { Files.deleteIfExists(meminfo); }
        System.setProperty("magicmobile.aiAvailableMemoryMB", "1100");
        try {
            eq(DeviceMemory.availableBytes(), 1100L << 20);
            DeviceMemory.install(() -> 7L << 20);
            eq(DeviceMemory.availableBytes(), 7L << 20); // the platform's own reading wins
            DeviceMemory.install(() -> { throw new IllegalStateException("no reading"); });
            eq(DeviceMemory.availableBytes(), 1100L << 20);
        } finally {
            System.clearProperty("magicmobile.aiAvailableMemoryMB");
            DeviceMemory.install(null);
        }
        check(DeviceMemory.availableBytes() > 0, "some reading");
        // A cap never falls under the floor, and follows memory over the copy size.
        eq(new AISearchMemory(null, 1, 1 << 20, List::of).cap, AISearchMemory.MIN_COPIES);
        eq(new AISearchMemory(null, 2300L << 20, 1 << 20, List::of).cap, 575);
    }

    private static long liveHeap() {
        for (int i = 0; i < 3; i++) System.gc();
        Runtime runtime = Runtime.getRuntime();
        return runtime.totalMemory() - runtime.freeMemory();
    }
    @SuppressWarnings("unchecked")
    private static Set<UUID> owned(Game game) throws Exception {
        Field field = GameImpl.class.getDeclaredField("ownedCards");
        field.setAccessible(true);
        return (Set<UUID>) field.get(game);
    }
    @SuppressWarnings("unchecked")
    private static Card rawCard(Game game, UUID id) throws Exception {
        Field field = GameImpl.class.getDeclaredField("gameCards");
        field.setAccessible(true);
        return ((Map<UUID,Card>) field.get(game)).get(id);
    }

    /** One search's outcome: what it put on the stack, its kept line's score, nodes and copies made. */
    record Search(String stack, int score, int nodes, int copies) {
        String decision() { return stack + " score " + score + " nodes " + nodes; }
        @Override public String toString() { return decision() + " copies " + copies; }
    }

    /** A two-player game in the AI's precombat main phase, with the AI holding priority. */
    private static final class Board implements AutoCloseable {
        final MobileHumanPlayer human = new MobileHumanPlayer("Human");
        final MobileAICancellation cancellation = new MobileAICancellation();
        final Player ai;
        final MobileCommanderGame game;

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
            // Searches end by depth here, never by time.
            setField(ai, ComputerPlayer6.class, "maxThinkTimeSecs", 120);
        }
        void setUp(String board) {
            switch (board) {
                case "bolt" -> {
                    permanent(ai, Mountain::new, "Mountain");
                    permanent(human, GrizzlyBears::new, "Grizzly Bears");
                    permanent(ai, GrizzlyBears::new, "Grizzly Bears");
                    hand(ai, LightningBolt::new, "Lightning Bolt");
                    for (int i = 0; i < 20; i++) library(ai, Mountain::new, "Mountain");
                }
                case "fetch" -> {
                    permanent(ai, EvolvingWilds::new, "Evolving Wilds");
                    permanent(ai, Forest::new, "Forest");
                    hand(ai, HillGiant::new, "Hill Giant");
                    for (int i = 0; i < 12; i++) library(ai, i % 3 == 0 ? Mountain::new : Forest::new, i % 3 == 0 ? "Mountain" : "Forest");
                    for (int i = 0; i < 8; i++) library(ai, GrizzlyBears::new, "Grizzly Bears");
                }
                case "trigger" -> {
                    for (int i = 0; i < 3; i++) permanent(ai, Forest::new, "Forest");
                    for (int i = 0; i < 2; i++) permanent(ai, Mountain::new, "Mountain");
                    permanent(human, GrizzlyBears::new, "Grizzly Bears");
                    permanent(human, HillGiant::new, "Hill Giant");
                    hand(ai, WoodElves::new, "Wood Elves");
                    hand(ai, FlametongueKavu::new, "Flametongue Kavu");
                    for (int i = 0; i < 10; i++) library(ai, Forest::new, "Forest");
                }
                case "shaman" -> {
                    // 12 cards in the opponent's graveyard: 1 + 12 + 66 + 220 + 495 sets of up to four (upstream's
                    // limit), and one option for the AI's own empty graveyard.
                    for (int i = 0; i < 3; i++) permanent(ai, Forest::new, "Forest");
                    hand(ai, LoamingShaman::new, "Loaming Shaman");
                    for (int i = 0; i < 12; i++) graveyard(human, GrizzlyBears::new, "Grizzly Bears");
                    for (int i = 0; i < 10; i++) library(ai, Forest::new, "Forest");
                }
                default -> throw new IllegalArgumentException(board);
            }
        }
        Card card(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = constructor.apply(owner.getId(), new CardSetInfo(name, "M10", "1", Rarity.COMMON));
            game.loadCards(new HashSet<>(List.of(card)), owner.getId());
            return card;
        }
        Card library(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = card(owner, constructor, name);
            card.setZone(Zone.LIBRARY, game); owner.getLibrary().putOnTop(card, game);
            return card;
        }
        Card graveyard(Player owner, BiFunction<UUID,CardSetInfo,Card> constructor, String name) {
            Card card = card(owner, constructor, name);
            card.setZone(Zone.GRAVEYARD, game); owner.getGraveyard().add(card);
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
        /** The AI's search and move on a deep copy of this position, from a seeded generator. */
        Search search(long seed) {
            Game position = game.copy();
            position.getPlayerList().setCurrent(ai.getId());
            Player searcher = position.getPlayer(ai.getId());
            RandomUtil.setSeed(seed);
            int copies = GameImpl.COPIED_COUNT.get();
            searcher.priority(position);
            int made = GameImpl.COPIED_COUNT.get() - copies;
            SimulationNode2 kept = (SimulationNode2) field(searcher, ComputerPlayer6.class, "root");
            StringBuilder stack = new StringBuilder();
            for (StackObject object : position.getStack()) {
                stack.append(object.getName());
                object.getStackAbility().getAllSelectedTargets().forEach(t -> t.getTargets().forEach(id -> {
                    var target = position.getObject(id);
                    stack.append(" -> ").append(target == null ? String.valueOf(position.getPlayer(id) == null ? id : position.getPlayer(id).getName()) : target.getName());
                }));
                stack.append(';');
            }
            return new Search(stack.length() == 0 ? "pass" : stack.toString(), kept == null ? 0 : kept.getScore(),
                SimulationNode2.getCount(), made);
        }
        @Override public void close() { human.closeChannel(); cancellation.close(); }
    }

    private static Object field(Object target, Class<?> owner, String name) {
        try { Field field = owner.getDeclaredField(name); field.setAccessible(true); return field.get(target); }
        catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
    }
    private static void setField(Object target, Class<?> owner, String name, Object value) {
        try { Field field = owner.getDeclaredField(name); field.setAccessible(true); field.set(target, value); }
        catch (ReflectiveOperationException e) { throw new IllegalStateException(e); }
    }
    private static void eq(Object actual, Object expected) {
        if (!Objects.equals(actual, expected)) throw new AssertionError("expected " + expected + " but was " + actual);
    }
    private static void check(boolean value, String message) { if (!value) throw new AssertionError(message); }
}
