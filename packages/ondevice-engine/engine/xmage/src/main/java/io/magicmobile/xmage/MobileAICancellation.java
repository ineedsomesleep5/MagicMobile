package io.magicmobile.xmage;

import io.magicmobile.core.EngineDiagnostics;
import mage.abilities.ActivatedAbility;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.game.Game;
import mage.players.Player;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulationNode2;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.TimeUnit;

/**
 * Shared by one match and its copies. Owns lifecycle and search budgets; every choice the
 * AI makes still comes from the upstream search.
 */
final class MobileAICancellation {
    /**
     * Think-time cap while responding to a non-empty stack (each trigger gives the AI priority
     * again), and once only AIs remain in the game and any people left are just watching.
     */
    static final int STACK_THINK_SECS=2;
    private volatile boolean closing;
    private int simulations;
    /** Concede requests from CALL threads; only the live game drains them, on its GAME thread. */
    private final ConcurrentLinkedQueue<UUID> concedes=new ConcurrentLinkedQueue<>();
    private volatile Game live;

    boolean isClosing() { return closing; }
    void bind(Game game) { live=game; }
    void requestConcede(UUID playerId) { if(!concedes.contains(playerId)) concedes.add(playerId); }
    boolean hasConcedeFor(Game game) { return game==live && !concedes.isEmpty(); }
    /** Null for copies and simulations: they must never act on a player's real concede. */
    UUID nextConcede(Game game) { return game==live ? concedes.poll() : null; }
    /** Read on the GAME thread. AI simulations replace every player, so ask the live game. */
    boolean humansPlaying() {
        Game game=live;
        if(game==null) return true;
        for(Player player:game.getState().getPlayers().values())
            if(player instanceof MobileHumanPlayer && player.isInGame()) return true;
        return false;
    }
    synchronized void close() { closing=true; }
    synchronized void runIfOpen(Runnable action) { if(!closing) action.run(); }
    private synchronized void enterSimulation() {
        // A queued upstream FutureTask can enter after its GAME thread was cancelled.
        // Reject before touching any game state, including shared upstream search counters.
        if(closing) throw new CancellationException("Mobile AI match stopped");
        simulations++;
    }
    private synchronized void leaveSimulation() { simulations--;notifyAll(); }
    synchronized boolean awaitQuiescence(long deadline) throws InterruptedException {
        while(simulations!=0) {
            long remaining=deadline-System.nanoTime();
            if(remaining<=0) return false;
            TimeUnit.NANOSECONDS.timedWait(this,remaining);
        }
        return true;
    }
    ComputerPlayerControllableProxy player(String name) { return player(name,1); }
    ComputerPlayerControllableProxy player(String name,int skill) {
        if(skill<1 || skill>10) throw new IllegalArgumentException("AI skill must be 1–10");
        return new CancellablePlayer(name,skill,this);
    }

    /** Steps where upstream ComputerPlayer7 runs a full search; every other step already passes. */
    static boolean searchesAt(PhaseStep step) {
        return step==PhaseStep.PRECOMBAT_MAIN || step==PhaseStep.DECLARE_ATTACKERS
            || step==PhaseStep.DECLARE_BLOCKERS || step==PhaseStep.POSTCOMBAT_MAIN;
    }
    static int thinkBudget(int configured,boolean stackEmpty,boolean humansPlaying) {
        return stackEmpty && humansPlaying?configured:Math.min(configured,STACK_THINK_SECS);
    }

    private static final class CancellablePlayer extends ComputerPlayerControllableProxy {
        private final transient MobileAICancellation cancellation;
        CancellablePlayer(String name,int skill,MobileAICancellation cancellation) {
            super(name,RangeOfInfluence.ALL,skill);this.cancellation=cancellation;
        }
        private CancellablePlayer(CancellablePlayer source) {
            super(source);cancellation=source.cancellation;
            // Keep the configured upstream budgets when XMage copies this live adapter.
            maxNodes=source.maxNodes;maxThinkTimeSecs=source.maxThinkTimeSecs;
        }
        @Override public CancellablePlayer copy() { return new CancellablePlayer(this); }
        @Override public boolean priority(Game game) {
            if(game.isSimulation() || !isGameUnderControl() || !actions.isEmpty()
                || !searchesAt(game.getTurnStepType()) || hasNonManaPlayable(game)) return super.priority(game);
            // Upstream search would only list Pass here (it skips mana abilities), so skip its
            // full game copy. Same observable steps as ComputerPlayer7.priorityPlay then act.
            game.resumeTimer(getTurnControlledBy());
            try {
                game.getState().setPriorityPlayerId(playerId);
                game.firePriorityEvent(playerId);
                root=null;
                pass(game);
                return true;
            } finally { game.pauseTimer(getTurnControlledBy()); }
        }
        private boolean hasNonManaPlayable(Game game) {
            for(ActivatedAbility ability:getPlayable(game,true)) if(!ability.isManaAbility()) return true;
            return false;
        }
        @Override protected Integer addActionsTimed() {
            int configured=maxThinkTimeSecs;
            Game simulation=root==null?null:root.getGame();
            maxThinkTimeSecs=thinkBudget(configured,simulation==null || simulation.getStack().isEmpty(),cancellation.humansPlaying());
            try { return super.addActionsTimed(); }
            finally { maxThinkTimeSecs=configured; }
        }
        @Override protected int addActions(SimulationNode2 node,int depth,int alpha,int beta) {
            cancellation.enterSimulation();
            try { return super.addActions(node,depth,alpha,beta); }
            catch(Throwable failure) {
                // Upstream addActionsTimed can consume the Future's ExecutionException.
                // Keep the original failure private before it crosses that boundary.
                if(!(failure instanceof CancellationException))
                    cancellation.runIfOpen(()->EngineDiagnostics.capture("ai-simulation",failure));
                throw failure;
            }
            finally { cancellation.leaveSimulation(); }
        }
    }
}
