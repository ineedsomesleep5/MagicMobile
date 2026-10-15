package io.magicmobile.xmage;

import io.magicmobile.core.EngineDiagnostics;
import mage.MageObject;
import mage.abilities.Ability;
import mage.abilities.ActivatedAbility;
import mage.abilities.Mode;
import mage.abilities.Modes;
import mage.abilities.SpellAbility;
import mage.abilities.TriggeredAbility;
import mage.abilities.costs.mana.ManaCost;
import mage.cards.Card;
import mage.cards.Cards;
import mage.choices.Choice;
import mage.constants.MultiAmountType;
import mage.constants.Outcome;
import mage.abilities.common.PassAbility;
import mage.constants.PhaseStep;
import mage.constants.RangeOfInfluence;
import mage.game.Game;
import mage.game.combat.CombatGroup;
import mage.game.events.GameEvent;
import mage.game.permanent.Permanent;
import mage.game.stack.Spell;
import mage.game.stack.StackObject;
import mage.players.Player;
import mage.players.PlayerImpl;
import mage.player.ai.ComputerPlayerControllableProxy;
import mage.player.ai.SimulatedPlayer2;
import mage.player.ai.SimulationNode2;
import mage.target.Target;
import mage.target.TargetAmount;
import mage.target.TargetCard;
import mage.util.MultiAmountMessage;
import org.apache.log4j.Logger;
import java.io.Serializable;
import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;
import java.util.UUID;
import java.util.concurrent.CancellationException;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.TimeUnit;
import java.util.function.BiFunction;
import java.util.function.Function;
import java.util.function.Supplier;
import java.util.stream.Collectors;

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
    /** This match's game record, written or replayed on its GAME thread; null for copies outside a match. */
    private volatile GameRecorder recorder;

    void setRecorder(GameRecorder recorder) { this.recorder=recorder; }
    GameRecorder recorder() { return recorder; }
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
        // One search's root candidates. Written by the simulation thread, read after it returns.
        private transient volatile SimulationNode2 searchRoot;
        private transient List<ScoredChoice> rootChoices;
        private transient boolean searched;
        CancellablePlayer(String name,int skill,AIDifficulty difficulty,MobileAICancellation cancellation) {
            super(name,RangeOfInfluence.ALL,skill);this.cancellation=cancellation;
            maxDepth=difficulty.searchDepth;mistakePercent=difficulty.mistakePercent;mistakeState=difficulty.seed;
        }
        private CancellablePlayer(CancellablePlayer source) {
            super(source);cancellation=source.cancellation;
            // Keep the configured upstream budgets when XMage copies this live adapter.
            maxNodes=source.maxNodes;maxThinkTimeSecs=source.maxThinkTimeSecs;
            mistakePercent=source.mistakePercent;mistakeState=source.mistakeState;mistakes=source.mistakes;
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
            super.calculateActions(game);
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
        /** Sometimes holds every creature back, but never when the attack might be lethal. True when upstream declared. */
        private boolean selectAttackersLive(Game game,UUID attackingPlayerId) {
            if(!game.isSimulation() && isGameUnderControl() && !getAvailableAttackers(game).isEmpty()
                    && !possiblyLethal(game) && rollMistake(game)) {
                mistakes++;
                logger.info("AI deliberate mistake for "+getName()+": no attack");
                return false;
            }
            super.selectAttackers(game,attackingPlayerId);
            return true;
        }
        /** Sometimes declares no blocks, but only while the attack would cost under half its life. True when upstream declared. */
        private boolean selectBlockersLive(Ability source,Game game,UUID defendingPlayerId) {
            if(!game.isSimulation() && isGameUnderControl() && !getAvailableBlockers(game).isEmpty()
                    && incomingPower(game)*2<getLife() && rollMistake(game)) {
                mistakes++;
                logger.info("AI deliberate mistake for "+getName()+": no blocks");
                return false;
            }
            super.selectBlockers(source,game,defendingPlayerId);
            return true;
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
        private boolean priorityLive(Game game) {
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
            maxThinkTimeSecs=thinkBudget(configured,simulation==null || simulation.getStack().isEmpty(),cancellation.humansPlaying());
            try { return super.addActionsTimed(); }
            finally { maxThinkTimeSecs=configured; }
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

        // ---- Game record (docs/cloud/game-record.md) --------------------------------------
        // Each decision upstream asks this AI is recorded as its result plus the engine calls its
        // reasoning made (activations, passes, attack and block declarations). A replay never runs
        // the reasoning: it makes the same engine calls and returns the same result. Another
        // player's control of this AI's turn goes to the controlling human, whose answers are recorded.

        /** The record when this is a top-level decision of the live game under this AI's own control. */
        private GameRecorder recorder(Game game) {
            MobileAICancellation c=cancellation;
            GameRecorder r=c==null?null:c.recorder();
            return r!=null && r.top(game) && isGameUnderControl()?r:null;
        }
        /** Recording: AI reasoning is calling into the engine. */
        private GameRecorder effects(Game game) {
            MobileAICancellation c=cancellation;
            GameRecorder r=c==null?null:c.recorder();
            return r!=null && r.recordsEffect(game)?r:null;
        }
        private <T> T decide(Game game,char op,Supplier<T> live,Function<T,String> encode,BiFunction<GameRecorder,String,T> replay) {
            GameRecorder r=recorder(game);
            if(r==null) return live.get();
            int seat=r.seat(playerId);
            if(r.replaying) return replay.apply(r,r.take(seat,op));
            T result;
            r.enterAI(op);
            try { result=live.get(); } finally { r.exitAI(); }
            r.append(seat,op,()->encode.apply(result));
            return result;
        }
        private boolean decideTarget(Game game,char op,Target target,Ability source,Supplier<Boolean> live) {
            List<UUID> before=new ArrayList<>(target.getTargets());
            GameRecorder rec=cancellation==null?null:cancellation.recorder();
            return decide(game,op,live,result->(result?"1 ":"0 ")+rec.targetChange(before,target,game),(r,args)->{
                if(op=='N') ((TargetAmount)target).prepareAmount(source,game); // as ComputerPlayer.chooseTargetAmount
                r.applyTargets(args.substring(2),target,source,game);
                return args.charAt(0)=='1';
            });
        }
        private static String bool(boolean value) { return value?"1":"0"; }

        @Override public boolean priority(Game game) {
            GameRecorder r=recorder(game);
            if(r==null) return priorityLive(game);
            int seat=r.seat(playerId);
            if(r.replaying) return replayPriority(r,seat,game);
            boolean result;
            r.enterAI('Q');
            try { result=priorityLive(game); } finally { r.exitAI(); }
            r.append(seat,'Q',bool(result));
            return result;
        }
        /** As ComputerPlayer7.priority: the same priority event, then the recorded actions and passes. */
        private boolean replayPriority(GameRecorder r,int seat,Game game) {
            game.resumeTimer(getTurnControlledBy());
            try {
                game.getState().setPriorityPlayerId(playerId);
                game.firePriorityEvent(playerId);
                while(true) switch(r.next(seat,"Ap")) {
                    case 'A': replayAction(r,r.take(seat,'A'),game);break;
                    case 'p': r.take(seat,'p');pass(game);break;
                    default: return r.take(seat,'Q').equals("1");
                }
            } finally { game.pauseTimer(getTurnControlledBy()); }
        }
        /**
         * Rebuilds the searched action: the source's ability with the recorded modes, targets and X, using
         * upstream's own option generator when the plain ability does not match. Then does what
         * ComputerPlayer6.act does with it.
         */
        private void replayAction(GameRecorder r,String args,Game game) {
            int space=args.indexOf(' ');
            String ref=space<0?args:args.substring(0,space),want=space<0?".":args.substring(space+1);
            Ability base=r.resolveAbility(ref,game,playerId);
            Ability option=null;
            r.enterAI('A'); // rebuilding asks no one and draws nothing from the game's stream
            try {
                Ability plain=base.copy(),cleared=base.copy();
                // Upstream's option generator clears a modal ability's default mode on the ability it was given.
                cleared.getModes().clearSelectedModes();
                if(r.describe(plain,game).equals(want)) option=plain;
                else if(r.describe(cleared,game).equals(want)) option=cleared;
                else for(Ability candidate:new SimulatedPlayer2(this,true).getPlayableOptions(base.copy(),game))
                    if(r.describe(candidate,game).equals(want)) { option=candidate;break; }
            } finally { r.exitAI(); }
            if(option==null) throw r.diverged("no option "+want+" for "+ref);
            for(Target target:option.getTargets())
                for(UUID id:target.getTargets()) {
                    target.updateTarget(id,game);
                    if(!target.isNotTarget())
                        game.addSimultaneousEvent(GameEvent.getEvent(GameEvent.EventType.TARGETED,id,option,option.getControllerId()));
                }
            activateAbility((ActivatedAbility)option,game);
        }
        @Override public boolean activateAbility(ActivatedAbility ability,Game game) {
            GameRecorder r=effects(game);
            if(r==null) return super.activateAbility(ability,game);
            boolean action=r.currentOp()=='Q';
            r.append(r.seat(playerId),action?'A':'V',()->r.abilityRef(ability,game,playerId)+(action?" "+r.describe(ability,game):""));
            return r.engine(()->super.activateAbility(ability,game));
        }
        @Override public void pass(Game game) {
            GameRecorder r=effects(game);
            if(r!=null) r.append(r.seat(playerId),'p',"");
            super.pass(game);
        }
        @Override public void declareAttacker(UUID attackerId,UUID defenderId,Game game,boolean allowUndo) {
            GameRecorder r=effects(game);
            if(r==null) { super.declareAttacker(attackerId,defenderId,game,allowUndo);return; }
            r.append(r.seat(playerId),'K',()->r.name(attackerId,game)+" "+r.name(defenderId,game)+" "+bool(allowUndo));
            r.engineRun(()->super.declareAttacker(attackerId,defenderId,game,allowUndo));
        }
        @Override public void declareBlocker(UUID defenderId,UUID blockerId,UUID attackerId,Game game) {
            GameRecorder r=effects(game);
            if(r==null) { super.declareBlocker(defenderId,blockerId,attackerId,game);return; }
            r.append(r.seat(playerId),'L',()->r.name(defenderId,game)+" "+r.name(blockerId,game)+" "+r.name(attackerId,game));
            r.engineRun(()->super.declareBlocker(defenderId,blockerId,attackerId,game));
        }
        @Override public void selectAttackers(Game game,UUID attackingPlayerId) {
            GameRecorder r=recorder(game);
            if(r==null) { selectAttackersLive(game,attackingPlayerId);return; }
            int seat=r.seat(playerId);
            if(r.replaying) { replayCombat(r,seat,'S',game);return; }
            boolean declared;
            r.enterAI('S');
            try { declared=selectAttackersLive(game,attackingPlayerId); } finally { r.exitAI(); }
            r.append(seat,'S',bool(declared));
        }
        @Override public void selectBlockers(Ability source,Game game,UUID defendingPlayerId) {
            GameRecorder r=recorder(game);
            if(r==null) { selectBlockersLive(source,game,defendingPlayerId);return; }
            int seat=r.seat(playerId);
            if(r.replaying) { replayCombat(r,seat,'B',game);return; }
            boolean declared;
            r.enterAI('B');
            try { declared=selectBlockersLive(source,game,defendingPlayerId); } finally { r.exitAI(); }
            r.append(seat,'B',bool(declared));
        }
        /** As ComputerPlayer6.declareAttackers / declareBlockers when upstream declared: its events, then the recorded declarations. */
        private void replayCombat(GameRecorder r,int seat,char op,Game game) {
            boolean attack=op=='S';
            if(r.lookAhead(seat,op).equals("1")) {
                game.fireEvent(new GameEvent(attack?GameEvent.EventType.DECLARE_ATTACKERS_STEP_PRE:GameEvent.EventType.DECLARE_BLOCKERS_STEP_PRE,null,null,playerId));
                game.replaceEvent(GameEvent.getEvent(attack?GameEvent.EventType.DECLARING_ATTACKERS:GameEvent.EventType.DECLARING_BLOCKERS,playerId,playerId));
            }
            boolean blocked=false;
            for(char next=r.next(seat,attack?"K":"L");next!=0;next=r.next(seat,attack?"K":"L")) {
                String[] a=r.take(seat,next).split(" ");
                if(attack) declareAttacker(r.resolve(a[0],game),r.resolve(a[1],game),game,a[2].equals("1"));
                else { declareBlocker(r.resolve(a[0],game),r.resolve(a[1],game),r.resolve(a[2],game),game);blocked=true; }
            }
            if(blocked) game.getPlayers().resetPassed();
            r.take(seat,op);
        }
        @Override public boolean playMana(Ability ability,ManaCost unpaid,String promptText,Game game) {
            GameRecorder r=recorder(game);
            if(r==null) return super.playMana(ability,unpaid,promptText,game);
            int seat=r.seat(playerId);
            if(r.replaying) {
                payManaMode=true; // as ComputerPlayer.playMana
                try {
                    while(r.next(seat,"V")!=0) activateAbility((ActivatedAbility)r.resolveAbility(r.take(seat,'V'),game,playerId),game);
                    return r.take(seat,'Y').equals("1");
                } finally { payManaMode=false; }
            }
            boolean result;
            r.enterAI('Y');
            try { result=super.playMana(ability,unpaid,promptText,game); } finally { r.exitAI(); }
            r.append(seat,'Y',bool(result));
            return result;
        }
        @Override public boolean chooseMulligan(Game game) {
            return decide(game,'M',()->super.chooseMulligan(game),CancellablePlayer::bool,(r,a)->a.equals("1"));
        }
        @Override public boolean chooseUse(Outcome outcome,String message,Ability source,Game game) {
            return decide(game,'U',()->super.chooseUse(outcome,message,source,game),CancellablePlayer::bool,(r,a)->a.equals("1"));
        }
        @Override public boolean chooseUse(Outcome outcome,String message,String secondMessage,String trueText,String falseText,Ability source,Game game) {
            return decide(game,'U',()->super.chooseUse(outcome,message,secondMessage,trueText,falseText,source,game),CancellablePlayer::bool,(r,a)->a.equals("1"));
        }
        @Override public boolean choosePile(Outcome outcome,String message,List<? extends Card> pile1,List<? extends Card> pile2,Game game) {
            return decide(game,'P',()->super.choosePile(outcome,message,pile1,pile2,game),CancellablePlayer::bool,(r,a)->a.equals("1"));
        }
        @Override public int chooseReplacementEffect(Map<String,String> effectsMap,Map<String,MageObject> objectsMap,Game game) {
            return decide(game,'R',()->super.chooseReplacementEffect(effectsMap,objectsMap,game),String::valueOf,(r,a)->Integer.parseInt(a));
        }
        @Override public int announceX(int min,int max,String message,Game game,Ability source,boolean isManaPay) {
            return decide(game,'X',()->super.announceX(min,max,message,game,source,isManaPay),String::valueOf,(r,a)->Integer.parseInt(a));
        }
        @Override public int getAmount(int min,int max,String message,Ability source,Game game) {
            return decide(game,'I',()->super.getAmount(min,max,message,source,game),String::valueOf,(r,a)->Integer.parseInt(a));
        }
        @Override public List<Integer> getMultiAmountWithIndividualConstraints(Outcome outcome,List<MultiAmountMessage> messages,
                int totalMin,int totalMax,MultiAmountType type,Game game) {
            return decide(game,'J',()->super.getMultiAmountWithIndividualConstraints(outcome,messages,totalMin,totalMax,type,game),
                values->values==null?"-":values.stream().map(String::valueOf).collect(Collectors.joining(",")),
                (r,a)->{
                    if(a.equals("-")) return null;
                    List<Integer> values=new ArrayList<>();
                    for(String n:a.split(",")) if(!n.isEmpty()) values.add(Integer.parseInt(n));
                    return values;
                });
        }
        @Override public boolean choose(Outcome outcome,Choice choice,Game game) {
            return decide(game,'C',()->super.choose(outcome,choice,game),result->{
                String chosen=choice.isKeyChoice()?choice.getChoiceKey():choice.getChoice();
                return bool(result)+(chosen==null?"":(choice.isKeyChoice()?" k":" v")+(choice.isChosenSpecial()?"!":"")+GameRecorder.encode(chosen));
            },(r,a)->{
                if(a.length()>2) {
                    boolean special=a.length()>3 && a.charAt(3)=='!';
                    String chosen=GameRecorder.decode(a.substring(special?4:3));
                    if(a.charAt(2)=='k') choice.setChoiceByKey(chosen,special); else choice.setChoice(chosen,special);
                }
                return a.charAt(0)=='1';
            });
        }
        @Override public boolean choose(Outcome outcome,Target target,Ability source,Game game) {
            return decideTarget(game,'T',target,source,()->super.choose(outcome,target,source,game));
        }
        @Override public boolean choose(Outcome outcome,Target target,Ability source,Game game,Map<String,Serializable> options) {
            return decideTarget(game,'T',target,source,()->super.choose(outcome,target,source,game,options));
        }
        @Override public boolean chooseTarget(Outcome outcome,Target target,Ability source,Game game) {
            return decideTarget(game,'T',target,source,()->super.chooseTarget(outcome,target,source,game));
        }
        @Override public boolean choose(Outcome outcome,Cards cards,TargetCard target,Ability source,Game game) {
            return decideTarget(game,'T',target,source,()->super.choose(outcome,cards,target,source,game));
        }
        @Override public boolean chooseTarget(Outcome outcome,Cards cards,TargetCard target,Ability source,Game game) {
            return decideTarget(game,'T',target,source,()->super.chooseTarget(outcome,cards,target,source,game));
        }
        @Override public boolean chooseTargetAmount(Outcome outcome,TargetAmount target,Ability source,Game game) {
            return decideTarget(game,'N',target,source,()->super.chooseTargetAmount(outcome,target,source,game));
        }
        @Override public TriggeredAbility chooseTriggeredAbility(List<TriggeredAbility> abilities,Game game) {
            return decide(game,'G',()->super.chooseTriggeredAbility(abilities,game),
                chosen->String.valueOf(abilities.indexOf(chosen)),(r,a)->{
                    int index=Integer.parseInt(a);
                    if(index>=abilities.size()) throw r.diverged("no triggered ability "+a);
                    return index<0?null:abilities.get(index);
                });
        }
        @Override public Mode chooseMode(Modes modes,Ability source,Game game) {
            return decide(game,'D',()->super.chooseMode(modes,source,game),mode->{
                if(mode==null) return "-";
                int index=new ArrayList<>(modes.keySet()).indexOf(mode.getId());
                if(index>=0) return Integer.toString(index);
                index=modes.getAvailableModes(source,game).indexOf(mode);
                if(index<0) throw new IllegalArgumentException("mode not offered");
                return "a"+index;
            },(r,a)->{
                if(a.equals("-")) return null;
                List<Mode> offered=a.startsWith("a")?modes.getAvailableModes(source,game):new ArrayList<>(modes.values());
                int index=Integer.parseInt(a.startsWith("a")?a.substring(1):a);
                if(index>=offered.size()) throw r.diverged("no mode "+a);
                return offered.get(index);
            });
        }
        @Override public SpellAbility chooseAbilityForCast(Card card,Game game,boolean noMana) {
            return decide(game,'F',()->super.chooseAbilityForCast(card,game,noMana),chosen->{
                if(chosen==null) return "-";
                List<SpellAbility> castable=castable(card,game,noMana);
                for(int i=0;i<castable.size();i++) if(castable.get(i).getId().equals(chosen.getId())) return Integer.toString(i);
                throw new IllegalArgumentException("spell ability not castable");
            },(r,a)->{
                if(a.equals("-")) return null;
                List<SpellAbility> castable=castable(card,game,noMana);
                int index=Integer.parseInt(a);
                if(index>=castable.size()) throw r.diverged("no castable spell ability "+a);
                return castable.get(index);
            });
        }
        private List<SpellAbility> castable(Card card,Game game,boolean noMana) {
            return new ArrayList<>(PlayerImpl.getCastableSpellAbilities(game,playerId,card,game.getState().getZone(card.getId()),noMana).values());
        }
    }
}
