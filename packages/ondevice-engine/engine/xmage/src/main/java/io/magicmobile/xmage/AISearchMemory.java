package io.magicmobile.xmage;

import mage.game.Game;
import mage.player.ai.MobileSearchNodes;
import mage.player.ai.SimulationNode2;
import mage.players.Player;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Set;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;

/**
 * One AI search's game copies (docs/LIGHTER_ENGINE_PLAN.md, step 3). A search keeps (copies alive at once) x (size of
 * a copy) in memory, and that count follows the search's widest fan-out and its depth, not its node count or its
 * time. So the searches alive may keep at most {@link #cap} copies together: a share of the memory the phone has
 * available when a search starts (DeviceMemory), divided by the estimated size of one copy of this game. When a new
 * copy would reach the cap, the search stops and the AI plays the best line found so far, as when its time runs out.
 * Once the AI has decided, the search's copies are dropped; continuing its plan does not read them.
 *
 * Copies alive are counted exactly: the search's nodes (each holds one copy) reachable from its root, from the nodes
 * whose search is running, from the node whose game is being copied (a trigger's options hang under a node before
 * its search enters it) and from the root alternatives kept for deliberate mistakes, plus the copies listing one
 * node's options makes. Upstream's search keeps each node's best line in its children (ComputerPlayer6 patch
 * MOBILE_SEARCH_MEMORY), so nothing it holds is missed. A copy that holds its own copy of every card (the root, and
 * copies made while a trigger is handled) counts at its larger size. Other searches whose copies are not released
 * yet count too: every AI shares upstream's five search threads, and a search the AI stopped waiting for (out of
 * time) can still be running on one of them.
 *
 * A search the AI stopped waiting for is abandoned: from then on it makes no game copy and enters no node, so it
 * unwinds at once (Stopped) and frees its copies, and the next search waits for that first (awaitAbandoned). A
 * search at its cap makes no more copies either. Interrupting the thread, upstream's only signal, leaves code that
 * never checks it running: a trigger whose target is "any number of cards" in a graveyard lists thousands of
 * options, and the AI copies the whole game for each (SimulatedPlayer2.triggerAbility), which ran release C's
 * calibration games out of memory.
 */
final class AISearchMemory {
    /** The share of the available memory the searches alive may keep in game copies. */
    static final double SHARE=0.25;
    /** Never fewer: depth 10 with a best line at each level. */
    static final int MIN_COPIES=32;
    /** Copies alive outside the tree: listing a node's options copies it, and that copy twice more (PlayerImpl). */
    static final int LISTING_COPIES=3;
    /** How long a new search waits for abandoned searches to stop (they stop at their next copy or node). */
    static final long ABANDONED_WAIT_MILLIS=2000;
    /**
     * Estimated retained size of one copy a search makes (RealSearchMemoryTests measures it on the JVM): the game
     * state with every permanent, and the cards it copies on first use, which are mostly not in libraries.
     */
    static final long BASE_BYTES=320L<<10,PERMANENT_BYTES=14L<<10,CARD_BYTES=9L<<10,LIBRARY_CARD_BYTES=1L<<10;

    private static final ThreadLocal<AISearchMemory> CURRENT=new ThreadLocal<>();
    /** Searches whose copies are not released yet, in this process (any match, any AI). */
    private static final Set<AISearchMemory> LIVE=ConcurrentHashMap.newKeySet();
    /** Notified when a search ends. Never taken while holding a search's own lock. */
    private static final Object ENDED=new Object();
    /** The most recent search started (measurement tools). */
    static volatile AISearchMemory last;

    final SimulationNode2 root;
    /** copyBytes: a copy that shares the cards it has not used; deepCopyBytes: one that holds every card. */
    final long availableBytes,copyBytes,deepCopyBytes;
    /** In copies of copyBytes; a deep copy counts as deepCopyBytes / copyBytes of them. */
    final int cap;
    private final Supplier<Collection<SimulationNode2>> alternatives;
    // The search thread's own state.
    private final ArrayDeque<SimulationNode2> running=new ArrayDeque<>();
    /** Copies made, and the most copies alive at once (of any size, listing included). */
    volatile int copies,peak;
    /** What this search's copies take, as last counted on its thread; 0 once released. Other searches read it. */
    volatile long heldBytes;
    /** Set on the search thread when the cap stopped the search, with the root's best line at that moment. */
    volatile boolean capped;
    private volatile List<SimulationNode2> bestAtCap;
    /** Set on the GAME thread when it stopped waiting for this search while the search still ran (timed out). */
    volatile boolean abandoned;
    // Lifecycle, changed under this search's lock: started on its thread, ended there (or never started), decided by the AI.
    private boolean started,decided,released;
    private volatile boolean ended;
    private List<SimulationNode2> kept=List.of();

    AISearchMemory(SimulationNode2 root,long availableBytes,long copyBytes,Supplier<Collection<SimulationNode2>> alternatives) {
        this(root,availableBytes,copyBytes,copyBytes,alternatives);
    }
    AISearchMemory(SimulationNode2 root,long availableBytes,long copyBytes,long deepCopyBytes,
                   Supplier<Collection<SimulationNode2>> alternatives) {
        this.root=root;this.availableBytes=availableBytes;this.copyBytes=Math.max(1,copyBytes);
        this.deepCopyBytes=Math.max(this.copyBytes,deepCopyBytes);this.alternatives=alternatives;
        cap=(int)Math.max(MIN_COPIES,Math.min(Integer.MAX_VALUE,(long)(availableBytes*SHARE)/this.copyBytes));
    }

    /** GAME thread, as the search starts: memory available now, and the size of a copy of the search's game. */
    static AISearchMemory start(SimulationNode2 root,Supplier<Collection<SimulationNode2>> alternatives) {
        Game game=root.getGame();
        long copy=copyBytes(game);
        AISearchMemory memory=new AISearchMemory(root,DeviceMemory.availableBytes(),copy,copy+libraryCards(game)*(CARD_BYTES-LIBRARY_CARD_BYTES),alternatives);
        memory.heldBytes=memory.deepCopyBytes; // the root, a deep copy of the live game
        LIVE.add(memory);
        last=memory;
        return memory;
    }

    static long copyBytes(Game game) {
        int other=game.getStack().size()+game.getExile().getAllCards(game).size();
        for(Player player:game.getState().getPlayers().values()) other+=player.getHand().size()+player.getGraveyard().size();
        int library=libraryCards(game);
        return BASE_BYTES+PERMANENT_BYTES*game.getBattlefield().getAllPermanents().size()+CARD_BYTES*other+LIBRARY_CARD_BYTES*library;
    }
    private static int libraryCards(Game game) {
        int library=0;
        for(Player player:game.getState().getPlayers().values()) library+=player.getLibrary().size();
        return library;
    }

    /** Unwinds a stopped search's thread: thrown at its next game copy or node, never on the GAME thread. */
    static final class Stopped extends CancellationException {
        private static final long serialVersionUID=1L;
        Stopped(String reason) { super(reason); }
        @Override public synchronized Throwable fillInStackTrace() { return this; }
    }

    /**
     * Search thread, as upstream's addActions starts on a node. The top call (on the root) makes this the thread's
     * search. Returns the search to pass to {@link #leave}, or null when this is no tracked search. Throws Stopped in
     * an abandoned search, before it touches its node.
     */
    static AISearchMemory enter(AISearchMemory expected,SimulationNode2 node) {
        AISearchMemory memory=CURRENT.get();
        if(memory==null) {
            if(expected==null || expected.root!=node) return null;
            synchronized(expected) {
                // A queued task can start after the AI stopped waiting for it.
                if(expected.abandoned) throw new Stopped("AI search abandoned before it started");
                expected.started=true;
            }
            memory=expected;CURRENT.set(memory);
        } else if(memory.abandoned) throw new Stopped("AI search abandoned");
        memory.running.push(node);
        return memory;
    }
    static void leave(AISearchMemory memory) {
        if(memory==null) return;
        memory.running.pop();
        if(memory.running.isEmpty()) {
            CURRENT.remove();
            memory.heldBytes=memory.aliveBytes(null); // what the finished search keeps: its best line until the AI decides
            memory.ended();
        }
    }

    /** Every game copy made while a search runs on this thread (MobileCommanderGame's copy constructor). */
    static void copied(Game source) {
        AISearchMemory memory=CURRENT.get();
        if(memory!=null) memory.onCopy(source.getCustomData() instanceof SimulationNode2?(SimulationNode2)source.getCustomData():null);
    }
    private void onCopy(SimulationNode2 copying) {
        copies++;
        // Unwinding from the cap or a timeout needs no copy; code that never checks the interrupt is stopped here.
        if(abandoned) throw new Stopped("AI search abandoned");
        if(capped) throw new Stopped("AI search at its copy cap");
        int[] games=liveGames(copying);
        long alive=bytes(games)+LISTING_COPIES*copyBytes;
        heldBytes=alive;
        if(games[0]+LISTING_COPIES>peak) peak=games[0]+LISTING_COPIES;
        if(alive+others()>=cap*copyBytes) {
            bestAtCap=new ArrayList<>(root.getChildren());
            capped=true;
            Thread.currentThread().interrupt(); // as upstream's timeout: the search unwinds and scores what it has
        }
    }
    /** Copies the search holds now (search thread), with the node whose game is being copied: all, and deep ones. */
    private int[] liveGames(SimulationNode2 copying) {
        List<SimulationNode2> from=new ArrayList<>(running);
        from.add(root);
        if(copying!=null) from.add(copying);
        from.addAll(alternatives.get());
        return MobileSearchNodes.liveGames(from);
    }
    private long aliveBytes(SimulationNode2 copying) { return bytes(liveGames(copying)); }
    private long bytes(int[] games) { return (games[0]-games[1])*copyBytes+games[1]*deepCopyBytes; }
    /** What the other searches alive hold, as each last counted it. */
    private long others() {
        long sum=0;
        for(AISearchMemory other:LIVE) if(other!=this) sum+=other.heldBytes;
        return sum;
    }

    /** GAME thread, after a capped search returned: its best line when it stopped, like a timed-out search's. */
    void restoreBestLine() {
        List<SimulationNode2> best=bestAtCap;
        if(best==null) return;
        root.getChildren().clear();root.getChildren().addAll(best);
    }

    /**
     * GAME thread, once it stopped waiting for the search: one still running is abandoned (it stops at its next copy
     * or node), and one that never started never will (its task was cancelled in the queue).
     */
    void returned() {
        boolean neverStarted;
        synchronized(this) {
            if(ended) return;
            abandoned=true;neverStarted=!started;
        }
        if(neverStarted) ended(); // enter() now refuses it, so no thread can start it
    }
    /** Abandoned searches still running, in this process. */
    static int abandonedRunning() {
        int count=0;
        for(AISearchMemory memory:LIVE) if(memory.abandoned && !memory.ended) count++;
        return count;
    }
    /**
     * GAME thread, before a search starts: waits up to millis for abandoned searches (any AI's, since the search
     * threads are shared) to stop. True when none is still running; otherwise the new search counts their copies.
     */
    static boolean awaitAbandoned(long millis) {
        long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(millis);
        synchronized(ENDED) {
            while(abandonedRunning()>0) {
                long left=deadline-System.nanoTime();
                if(left<=0) return false;
                try { TimeUnit.NANOSECONDS.timedWait(ENDED,left); }
                catch(InterruptedException e) { Thread.currentThread().interrupt();return false; }
            }
        }
        return true;
    }

    private void ended() {
        synchronized(this) { ended=true;releaseWhenDone(); }
        synchronized(ENDED) { ENDED.notifyAll(); }
    }
    /** GAME thread: the AI decided; it keeps only its plan's line (abilities and combat), which needs no copies. */
    synchronized void decided(List<SimulationNode2> kept) { decided=true;this.kept=kept;releaseWhenDone(); }
    private void releaseWhenDone() {
        // A timed-out search can still be running on its thread: free its copies only once it has stopped.
        if(!ended || !decided || released) return;
        released=true;
        List<SimulationNode2> from=new ArrayList<>(kept);
        from.add(root);
        MobileSearchNodes.releaseGames(from);
        heldBytes=0;
        LIVE.remove(this);
    }
}
