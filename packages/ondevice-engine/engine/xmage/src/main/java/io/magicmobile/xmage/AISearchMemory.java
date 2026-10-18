package io.magicmobile.xmage;

import mage.game.Game;
import mage.player.ai.MobileSearchNodes;
import mage.player.ai.SimulationNode2;
import mage.players.Player;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.function.Supplier;

/**
 * One AI search's game copies (docs/LIGHTER_ENGINE_PLAN.md, step 3). A search keeps (copies alive at once) x (size of
 * a copy) in memory, and that count follows the search's widest fan-out and its depth, not its node count or its
 * time. So a search may keep at most {@link #cap} copies alive: a share of the memory the phone has available when it
 * starts (DeviceMemory), divided by the estimated size of one copy of this game. When a new copy would reach the cap,
 * the search stops and the AI plays the best line found so far, as when its time runs out. Once the AI has decided,
 * the search's copies are dropped; continuing its plan does not read them.
 *
 * Copies alive are counted exactly: the search's nodes (each holds one copy) reachable from its root, from the nodes
 * whose search is running and from the root alternatives kept for deliberate mistakes, plus the copies listing one
 * node's options makes. Upstream's search keeps each node's best line in its children (ComputerPlayer6 patch
 * MOBILE_SEARCH_MEMORY), so nothing it holds is missed.
 */
final class AISearchMemory {
    /** The share of the available memory one search may keep in game copies. */
    static final double SHARE=0.25;
    /** Never fewer: depth 10 with a best line at each level. */
    static final int MIN_COPIES=32;
    /** Copies alive outside the tree: listing a node's options copies it, and that copy twice more (PlayerImpl). */
    static final int LISTING_COPIES=3;
    /**
     * Estimated retained size of one copy a search makes (RealSearchMemoryTests measures it on the JVM): the game
     * state with every permanent, and the cards it copies on first use, which are mostly not in libraries.
     */
    static final long BASE_BYTES=320L<<10,PERMANENT_BYTES=14L<<10,CARD_BYTES=9L<<10,LIBRARY_CARD_BYTES=1L<<10;

    private static final ThreadLocal<AISearchMemory> CURRENT=new ThreadLocal<>();
    /** The most recent search started (measurement tools). */
    static volatile AISearchMemory last;

    final SimulationNode2 root;
    final long availableBytes,copyBytes;
    final int cap;
    private final Supplier<Collection<SimulationNode2>> alternatives;
    // The search thread's own state.
    private final ArrayDeque<SimulationNode2> running=new ArrayDeque<>();
    volatile int copies,peak;
    /** Set on the search thread when the cap stopped the search, with the root's best line at that moment. */
    volatile boolean capped;
    private volatile List<SimulationNode2> bestAtCap;
    // Releasing the copies, once the search has ended and the AI has decided (either thread).
    private boolean ended,decided,released;
    private List<SimulationNode2> kept=List.of();

    AISearchMemory(SimulationNode2 root,long availableBytes,long copyBytes,Supplier<Collection<SimulationNode2>> alternatives) {
        this.root=root;this.availableBytes=availableBytes;this.copyBytes=Math.max(1,copyBytes);this.alternatives=alternatives;
        cap=(int)Math.max(MIN_COPIES,Math.min(Integer.MAX_VALUE,(long)(availableBytes*SHARE)/this.copyBytes));
    }

    /** GAME thread, as the search starts: memory available now, and the size of a copy of the search's game. */
    static AISearchMemory start(SimulationNode2 root,Supplier<Collection<SimulationNode2>> alternatives) {
        AISearchMemory memory=new AISearchMemory(root,DeviceMemory.availableBytes(),copyBytes(root.getGame()),alternatives);
        last=memory;
        return memory;
    }

    static long copyBytes(Game game) {
        int library=0,other=game.getStack().size()+game.getExile().getAllCards(game).size();
        for(Player player:game.getState().getPlayers().values()) {
            library+=player.getLibrary().size();
            other+=player.getHand().size()+player.getGraveyard().size();
        }
        return BASE_BYTES+PERMANENT_BYTES*game.getBattlefield().getAllPermanents().size()+CARD_BYTES*other+LIBRARY_CARD_BYTES*library;
    }

    /**
     * Search thread, as upstream's addActions starts on a node. The top call (on the root) makes this the thread's
     * search. Returns the search to pass to {@link #leave}, or null when this is no tracked search.
     */
    static AISearchMemory enter(AISearchMemory expected,SimulationNode2 node) {
        AISearchMemory memory=CURRENT.get();
        if(memory==null) {
            if(expected==null || expected.root!=node) return null;
            memory=expected;CURRENT.set(memory);
        }
        memory.running.push(node);
        return memory;
    }
    static void leave(AISearchMemory memory) {
        if(memory==null) return;
        memory.running.pop();
        if(memory.running.isEmpty()) { CURRENT.remove();memory.ended(); }
    }

    /** Every game copy made while a search runs on this thread (MobileCommanderGame's copy constructor). */
    static void copied() {
        AISearchMemory memory=CURRENT.get();
        if(memory!=null) memory.onCopy();
    }
    private void onCopy() {
        copies++;
        if(capped) return;
        int alive=alive()+LISTING_COPIES;
        if(alive>peak) peak=alive;
        if(alive>=cap) {
            bestAtCap=new ArrayList<>(root.getChildren());
            capped=true;
            Thread.currentThread().interrupt(); // as upstream's timeout: the search unwinds and scores what it has
        }
    }
    /** Copies the search holds now (search thread). */
    int alive() {
        List<SimulationNode2> from=new ArrayList<>(running);
        from.add(root);
        from.addAll(alternatives.get());
        return MobileSearchNodes.liveGames(from);
    }

    /** GAME thread, after a capped search returned: its best line when it stopped, like a timed-out search's. */
    void restoreBestLine() {
        List<SimulationNode2> best=bestAtCap;
        if(best==null) return;
        root.getChildren().clear();root.getChildren().addAll(best);
    }

    private synchronized void ended() { ended=true;releaseWhenDone(); }
    /** GAME thread: the AI decided; it keeps only its plan's line (abilities and combat), which needs no copies. */
    synchronized void decided(List<SimulationNode2> kept) { decided=true;this.kept=kept;releaseWhenDone(); }
    private void releaseWhenDone() {
        // A timed-out search can still be running on its thread: free its copies only once it has stopped.
        if(!ended || !decided || released) return;
        released=true;
        List<SimulationNode2> from=new ArrayList<>(kept);
        from.add(root);
        MobileSearchNodes.releaseGames(from);
    }
}
