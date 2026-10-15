package io.magicmobile.xmage;

import io.magicmobile.core.EngineDiagnostics;
import mage.abilities.Ability;
import mage.abilities.ActivatedAbility;
import mage.abilities.common.PassAbility;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.game.Game;
import mage.game.combat.Combat;
import mage.game.combat.CombatGroup;
import mage.game.events.GameEvent;
import mage.game.permanent.Permanent;
import mage.game.stack.Spell;
import mage.game.stack.StackObject;
import mage.players.Player;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulationNode2;
import org.apache.log4j.Logger;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;
import java.util.LinkedList;
import java.util.List;
import java.util.TreeSet;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ThreadLocalRandom;
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
    /** Expert quick search: one action seen resolved (upstream depth 2), within at most 2 s. */
    static final int QUICK_DEPTH=2,QUICK_SECS=2;
    private static final int NO_PHASE=0,QUICK=1,FULL_SEARCH=2;
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
        // An unseeded seat draws its mistake seed outside XMage's RNG, so shuffles are unaffected.
        return player(name,skill,AIDifficulty.forSkill(skill,ThreadLocalRandom.current().nextLong()));
    }
    /** Think time still follows skill (skill × 3 s); depth and mistakes follow the difficulty. */
    ComputerPlayerControllableProxy player(String name,int skill,AIDifficulty difficulty) {
        if(skill<1 || skill>10) throw new IllegalArgumentException("AI skill must be 1–10");
        return new CancellablePlayer(name,skill,difficulty,this);
    }
    /** Deliberate mistakes this AI made so far (tests and calibration). */
    static int mistakes(Player player) { return player instanceof CancellablePlayer ? ((CancellablePlayer)player).mistakes : 0; }

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

    /** A root action the search scored; candidates for a deliberate mistake. */
    private record ScoredChoice(SimulationNode2 node,int score) {}

    private static final class CancellablePlayer extends ComputerPlayerControllableProxy {
        private static final long serialVersionUID=1L;
        private static final Logger logger=Logger.getLogger(CancellablePlayer.class);
        // Transient: rebound by adopt() after a checkpoint restore; never restored through copy().
        private transient MobileAICancellation cancellation;
        // Difficulty: saved with the game, so a restored match keeps its settings and its roll sequence.
        private int mistakePercent;
        private long mistakeState;
        private int mistakes;
        private boolean expert;
        // One search's root candidates. Written by the simulation thread, read after it returns.
        private transient volatile SimulationNode2 searchRoot;
        private transient List<ScoredChoice> rootChoices;
        private transient boolean searched;
        CancellablePlayer(String name,int skill,AIDifficulty difficulty,MobileAICancellation cancellation) {
            super(name,RangeOfInfluence.ALL,skill);this.cancellation=cancellation;
            maxDepth=difficulty.searchDepth;mistakePercent=difficulty.mistakePercent;mistakeState=difficulty.seed;
            expert=difficulty.expert;
        }
        private CancellablePlayer(CancellablePlayer source) {
            super(source);cancellation=source.cancellation;
            // Keep the configured upstream budgets when XMage copies this live adapter.
            maxNodes=source.maxNodes;maxThinkTimeSecs=source.maxThinkTimeSecs;
            mistakePercent=source.mistakePercent;mistakeState=source.mistakeState;mistakes=source.mistakes;
            expert=source.expert;
        }
        /** Advances the seeded generator once per decision that could go wrong. */
        private boolean rollMistake(Game game) {
            if(mistakePercent==0 || game.isSimulation()) return false;
            mistakeState=AIDifficulty.next(mistakeState);
            return AIDifficulty.rolls(mistakeState,mistakePercent);
        }
        private List<ScoredChoice> choices() {
            if(rootChoices==null) rootChoices=new ArrayList<>();
            return rootChoices;
        }
        /**
         * After a fresh search that chose to act, sometimes take the best other root action the
         * search scored instead, as long as it scores no worse than doing nothing; otherwise pass.
         * The next priority searches again, so a passed play can still come later.
         */
        @Override protected void calculateActions(Game game) {
            searched=false;
            if(expert && !game.isSimulation()) expertSearch(game); else super.calculateActions(game);
            List<ScoredChoice> candidates;
            synchronized(this) { candidates=new ArrayList<>(choices());choices().clear();searchRoot=null; }
            if(!searched || actions.isEmpty() || !rollMistake(game)) return;
            SimulationNode2 chosen=root;
            ScoredChoice alternative=null;
            for(ScoredChoice candidate:candidates)
                if(candidate.node()!=chosen && candidate.node().getAbilities()!=null && !candidate.node().getAbilities().isEmpty()
                        && !(candidate.node().getAbilities().get(0) instanceof PassAbility)
                        && candidate.score()>=currentScore && (alternative==null || candidate.score()>alternative.score()))
                    alternative=candidate;
            mistakes++;
            if(alternative==null) {
                logger.info("AI deliberate mistake for "+getName()+": pass instead of "+actions);
                actions.clear();root=null;
            } else {
                logger.info("AI deliberate mistake for "+getName()+": "+alternative.node().getAbilities()+" instead of "+actions);
                actions=new LinkedList<>(alternative.node().getAbilities());
                root=alternative.node();combat=alternative.node().getCombat();
            }
        }
        // Expert search phases. Transient: they only live inside one calculateActions call.
        private transient int searchPhase;
        private transient int phaseBudgetSecs;
        private transient boolean timedOut;
        /**
         * A quick search (QUICK_DEPTH, at most QUICK_SECS) and then the full search in the time left. When the
         * full search runs out of time before it scores any move, the quick search's move stands instead of a
         * pass; otherwise the full search decides, exactly as upstream. Total think time stays within the budget.
         */
        private void expertSearch(Game game) {
            Set<String> cache=new HashSet<>(actionCache);
            int depth=maxDepth;long started=System.nanoTime();
            searchPhase=QUICK;
            try { maxDepth=Math.min(depth,QUICK_DEPTH);super.calculateActions(game); }
            finally { maxDepth=depth;searchPhase=FULL_SEARCH; }
            try {
                if(!searched) return; // continued the plan of an earlier search: nothing was searched
                int left=phaseBudgetSecs-(int)Math.ceil((System.nanoTime()-started)/1e9);
                if(left<1) return;
                LinkedList<Ability> quick=new LinkedList<>(actions);SimulationNode2 quickRoot=root;Combat quickCombat=combat;
                actions=new LinkedList<>();root=null;combat=null;
                actionCache.clear();actionCache.addAll(cache);
                phaseBudgetSecs=left;timedOut=false;
                super.calculateActions(game);
                if(actions.isEmpty() && timedOut && !quick.isEmpty()) {
                    logger.info("AI full search ran out of time for "+getName()+"; quick search move "+quick);
                    actions=quick;root=quickRoot;combat=quickCombat;
                    for(Ability ability:quick) actionCache.add(ability.getRule()+'_'+ability.getSourceId());
                }
            } finally { searchPhase=NO_PHASE; }
        }
        /** Sometimes holds every creature back, but never when the attack might be lethal. */
        @Override public void selectAttackers(Game game,UUID attackingPlayerId) {
            if(!game.isSimulation() && isGameUnderControl() && !getAvailableAttackers(game).isEmpty()
                    && !possiblyLethal(game) && rollMistake(game)) {
                mistakes++;
                logger.info("AI deliberate mistake for "+getName()+": no attack");
                return;
            }
            CombatPlanner.Plan plan=expert && !game.isSimulation()?CombatPlanner.planAttack(this,game):null;
            if(plan==null) { super.selectAttackers(game,attackingPlayerId);return; }
            // Same events as upstream's declareAttackers, around the planner's choice.
            game.fireEvent(new GameEvent(GameEvent.EventType.DECLARE_ATTACKERS_STEP_PRE,null,null,playerId));
            if(game.replaceEvent(GameEvent.getEvent(GameEvent.EventType.DECLARING_ATTACKERS,playerId,playerId))) return;
            for(UUID attackerId:plan.attackers()) declareAttacker(attackerId,plan.defenderId(),game,true);
        }
        /** Sometimes declares no blocks, but only while the attack would cost under half its life. */
        @Override public void selectBlockers(Ability source,Game game,UUID defendingPlayerId) {
            if(!game.isSimulation() && isGameUnderControl() && !getAvailableBlockers(game).isEmpty()
                    && incomingPower(game)*2<getLife() && rollMistake(game)) {
                mistakes++;
                logger.info("AI deliberate mistake for "+getName()+": no blocks");
                return;
            }
            super.selectBlockers(source,game,defendingPlayerId);
            if(expert && !game.isSimulation()) { CombatPlanner.chumpIfLethal(this,game);CombatPlanner.doubleBlock(this,game); }
        }
        private boolean possiblyLethal(Game game) {
            int power=0;
            for(Permanent attacker:getAvailableAttackers(game)) power+=Math.max(0,attacker.getPower().getValue());
            for(UUID opponentId:game.getOpponents(playerId)) {
                Player opponent=game.getPlayer(opponentId);
                if(opponent!=null && opponent.isInGame() && opponent.getLife()<=power) return true;
            }
            return false;
        }
        private int incomingPower(Game game) {
            int power=0;
            for(CombatGroup group:game.getCombat().getGroups()) {
                Permanent defender=game.getPermanent(group.getDefenderId());
                if(!playerId.equals(group.getDefenderId()) && (defender==null || !defender.isControlledBy(playerId))) continue;
                for(UUID attackerId:group.getAttackers()) {
                    Permanent attacker=game.getPermanent(attackerId);
                    if(attacker!=null) power+=Math.max(0,attacker.getPower().getValue());
                }
            }
            return power;
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
            synchronized(this) { choices().clear();searchRoot=root; }
            searched=true;
            int configured=maxThinkTimeSecs;
            Game simulation=root==null?null:root.getGame();
            int budget=thinkBudget(configured,simulation==null || simulation.getStack().isEmpty(),cancellation.humansPlaying());
            if(searchPhase==QUICK) { phaseBudgetSecs=budget;budget=Math.min(budget,QUICK_SECS); }
            else if(searchPhase==FULL_SEARCH) budget=Math.min(budget,phaseBudgetSecs);
            maxThinkTimeSecs=budget;
            long started=System.nanoTime();
            try { return super.addActionsTimed(); }
            finally {
                maxThinkTimeSecs=configured;
                timedOut=System.nanoTime()-started>=budget*1_000_000_000L-50_000_000L;
            }
        }
        @Override protected int addActions(SimulationNode2 node,int depth,int alpha,int beta) {
            cancellation.enterSimulation();
            try {
                int score=super.addActions(node,depth,alpha,beta);
                // The search keeps only its best root action; remember how the others scored.
                if(node!=null && searchRoot!=null && node.getParent()==searchRoot)
                    synchronized(this) { if(node.getParent()==searchRoot) choices().add(new ScoredChoice(node,score)); }
                return score;
            }
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
