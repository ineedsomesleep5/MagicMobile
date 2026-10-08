package io.magicmobile.xmage;

import io.magicmobile.core.EngineDiagnostics;
import mage.abilities.ActivatedAbility;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.game.Game;
import mage.game.stack.Spell;
import mage.game.stack.StackObject;
import mage.players.Player;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulationNode2;
import java.util.ArrayList;
import java.util.List;
import java.util.TreeSet;
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
    /**
     * The situation in which a pass can be repeated without another search: an opponent's ability (not a spell) is on
     * top of the stack, in this turn and step, with this AI holding the same instant-speed options. Null otherwise.
     */
    static String repeatablePassSituation(Game game,UUID aiId,List<String> playableIds) {
        StackObject top=game.getStack().getFirstOrNull();
        if(top==null || top instanceof Spell || aiId.equals(top.getControllerId())) return null;
        return game.getTurnNum()+":"+game.getTurnStepType()+":"+String.join(",",new TreeSet<>(playableIds));
    }
    /** True when the AI already passed in this situation and the stack has only resolved since (nothing was added). */
    static boolean repeatsPass(String declined,int declinedStackSize,String situation,int stackSize) {
        return situation!=null && situation.equals(declined) && stackSize<declinedStackSize;
    }
    static int thinkBudget(int configured,boolean stackEmpty,boolean humansPlaying) {
        return stackEmpty && humansPlaying?configured:Math.min(configured,STACK_THINK_SECS);
    }

    /** A restored game's AI seats answer to this match's lifecycle; budgets are kept as read. */
    void adopt(Game game) {
        for(Player player:game.getState().getPlayers().values())
            if(player instanceof CancellablePlayer) ((CancellablePlayer)player).cancellation=this;
    }
    /**
     * Detaches each AI's retained search tree (a whole game copy that a late simulation thread
     * may still change) while a checkpoint is written on the GAME thread. The live AI keeps it.
     */
    static Runnable detachSearchTrees(Game game) {
        List<CancellablePlayer> players=new ArrayList<>();List<SimulationNode2> trees=new ArrayList<>();
        for(Player player:game.getState().getPlayers().values())
            if(player instanceof CancellablePlayer) {
                CancellablePlayer ai=(CancellablePlayer)player;
                players.add(ai);trees.add(ai.swapSearchTree(null));
            }
        return ()->{ for(int i=0;i<players.size();i++) players.get(i).swapSearchTree(trees.get(i)); };
    }

    private static final class CancellablePlayer extends ComputerPlayerControllableProxy {
        private static final long serialVersionUID=1L;
        // Transient: rebound by adopt() after a checkpoint restore; never restored through copy().
        private transient MobileAICancellation cancellation;
        CancellablePlayer(String name,int skill,MobileAICancellation cancellation) {
            super(name,RangeOfInfluence.ALL,skill);this.cancellation=cancellation;
        }
        private CancellablePlayer(CancellablePlayer source) {
            super(source);cancellation=source.cancellation;
            // Keep the configured upstream budgets when XMage copies this live adapter.
            maxNodes=source.maxNodes;maxThinkTimeSecs=source.maxThinkTimeSecs;
        }
        @Override public CancellablePlayer copy() { return new CancellablePlayer(this); }
        SimulationNode2 swapSearchTree(SimulationNode2 tree) { SimulationNode2 previous=root;root=tree;return previous; }
        // A pass the AI already chose while an opponent's triggers resolve (16 quest-counter triggers give it priority
        // 16 times). Transient: a copy or a restored game simply searches again.
        private transient String declinedSituation;
        private transient int declinedStackSize;
        @Override public boolean priority(Game game) {
            if(game.isSimulation() || !isGameUnderControl() || !actions.isEmpty() || !searchesAt(game.getTurnStepType()))
                return super.priority(game);
            List<String> playable=nonManaPlayableIds(game);
            if(!playable.isEmpty()) {
                String situation=repeatablePassSituation(game,playerId,playable);
                int stackSize=game.getStack().size();
                if(!repeatsPass(declinedSituation,declinedStackSize,situation,stackSize)) {
                    boolean result=super.priority(game);
                    // Remember only a pass, and only in a repeatable situation; any action clears it.
                    declinedSituation=isPassed()?situation:null;
                    declinedStackSize=stackSize;
                    return result;
                }
                declinedStackSize=stackSize;
            }
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
        private List<String> nonManaPlayableIds(Game game) {
            List<String> ids=new ArrayList<>();
            for(ActivatedAbility ability:getPlayable(game,true)) if(!ability.isManaAbility()) ids.add(String.valueOf(ability.getOriginalId()));
            return ids;
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
