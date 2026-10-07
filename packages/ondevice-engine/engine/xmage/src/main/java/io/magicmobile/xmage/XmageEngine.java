package io.magicmobile.xmage;

import io.magicmobile.core.*;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.MobileCardFactories;
import mage.constants.*;
import mage.game.*;
import mage.game.events.Listener;
import mage.game.events.PlayerQueryEvent;
import mage.game.events.TableEvent;
import mage.players.Player;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/**
 * In-process engine; no SessionImpl, HTTP, Docker, remote XMage server or desktop client.
 * This adapter must pass the real-engine and native build gates before being released.
 */
public final class XmageEngine implements EnginePort {
    public static final String UPSTREAM="dac400ba1380f17492c9ad6a65ab60f12f28cd97";
    private final Map<String,Running> matches=new HashMap<>();
    private final String execution;
    private boolean closed;
    private static final class Running {
        final MobileCommanderMatch match;
        final Game game;
        final LinkedHashMap<String,Player> players;
        final LinkedHashMap<String,MobileHumanPlayer> seats;
        final MobileAICancellation cancellation;
        final MatchMailbox mailbox;
        final ExecutorService worker;
        volatile Future<?> task;
        /** Null unless this solo match saves checkpoints; see docs/PROTOCOL.md. */
        final Path checkpointPath;
        final List<Map<String,Object>> seatSummary;
        final boolean resumed;
        private long checkpointSequence; // GAME thread
        private long failedCheckpoints; // GAME thread
        volatile Map<String,Object> checkpointInfo,checkpointFailure;
        // Saves happen only on request (docs/PROTOCOL.md, "When the engine saves"). The GAME thread
        // records where it is parked; a CALL thread arms a request and waits for the GAME thread's
        // write. Guarded by saveLock.
        private final Object saveLock=new Object();
        private boolean saveRequested,atSafePoint,awaitingPlayer,writing,lastWriteSaved,humanLeft;
        private long safePointGeneration,savedGeneration=-1,writeAttempts;
        private String stopped; // ended, failed or closed
        Running(MobileCommanderMatch match,LinkedHashMap<String,Player> players,LinkedHashMap<String,MobileHumanPlayer> seats,
                MobileAICancellation cancellation,Path checkpointPath,List<Map<String,Object>> seatSummary,long checkpointSequence,boolean resumed) {
            this.match=match;this.game=match.getGame();this.players=players;this.seats=seats;
            this.checkpointPath=checkpointPath;this.seatSummary=seatSummary;this.checkpointSequence=checkpointSequence;this.resumed=resumed;
            this.cancellation=cancellation;((MobileCommanderGame)game).setCancellation(cancellation);
            mailbox=new MatchMailbox(game.getId().toString(),seats.keySet());
            worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME mobile-"+game.getId());t.setDaemon(true);return t;});
            game.addTableEventListener(new TableListener());
        }
        // Named listeners: upstream Listener is Serializable, so a method reference would be a
        // serializable lambda, which native checkpoint metadata must not need (docs/NATIVE_METADATA.md).
        // Game keeps them only in transient event sources; they are never written to a checkpoint.
        private final class TableListener implements Listener<TableEvent> {
            @Override public void event(TableEvent event) { tableEvent(event); }
        }
        private final class QueryListener implements Listener<PlayerQueryEvent> {
            @Override public void event(PlayerQueryEvent event) { query(event); }
        }
        void tableEvent(TableEvent event) {
            if(event.getGame()!=game || (event.getEventType()!=TableEvent.EventType.INFO
                    && event.getEventType()!=TableEvent.EventType.STATUS)) return;
            String message=event.getMessage();
            if(message==null || message.isEmpty()) return;
            cancellation.runIfOpen(()->{
                for(String seat:seats.keySet()) mailbox.inform(seat,Json.map("message",message));
            });
        }
        String seatFor(UUID engineId) {
            for(Map.Entry<String,MobileHumanPlayer> s:seats.entrySet()) if(s.getValue().getId().equals(engineId))return s.getKey();
            throw new BridgeException("unbound_player","Engine asked an unbound player for input");
        }
        void snapshot() {
            if(cancellation.isClosing()) return;
            Map<String,Map<String,Object>> views=ViewProjector.project(game,seats);
            // A seat whose player left (conceded or lost in a pod) only watches from here on.
            List<String> left=new ArrayList<>();
            for(Map.Entry<String,MobileHumanPlayer> s:seats.entrySet()) {
                Player player=game.getPlayer(s.getValue().getId());
                if(player==null || player.hasLeft()) left.add(s.getKey());
            }
            if(checkpointPath!=null && left.size()==seats.size()) synchronized(saveLock) {humanLeft=true;saveLock.notifyAll();}
            cancellation.runIfOpen(()->{mailbox.publishSnapshots(views);left.forEach(mailbox::retract);});
        }
        void concede(String seat) {
            MobileHumanPlayer human=seats.get(seat);
            if(human==null) throw new BridgeException("unauthorized_seat","Unknown or unbound player seat");
            // Queued for the GAME thread; its open question can no longer be answered.
            cancellation.runIfOpen(()->{mailbox.retract(seat);((MobileCommanderGame)game).requestConcede(human.getId());});
        }
        void query(PlayerQueryEvent e) {
            if(cancellation.isClosing()) return;
            mage.players.Player acting=game.getPlayer(e.getPlayerId());
            if(acting==null) throw new BridgeException("unbound_player","Engine queried a player outside this game");
            mage.players.Player controller=game.getPlayer(acting.getTurnControlledBy());
            if(controller==null) throw new BridgeException("unbound_player","Engine queried a player with an unknown controller");
            if(!controller.getId().equals(controller.getTurnControlledBy())
                    || (!acting.getId().equals(controller.getId()) && !acting.getPlayersUnderYourControl().isEmpty()))
                throw new BridgeException("nested_turn_control_not_supported","Chained turn control has no unambiguous mobile recipient");
            if(!(controller instanceof MobileHumanPlayer)) {
                if(e.getQueryType()!=PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) snapshot();
                return;
            }
            String seat=seatFor(controller.getId());
            if(e.getQueryType()==PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) {
                cancellation.runIfOpen(()->mailbox.inform(seat,Json.map("message",e.getMessage())));return;
            }
            // Safe point: the first question of this seat's own priority() call, between actions.
            boolean firstPriorityQuestion=((MobileHumanPlayer)controller).takeFirstPriorityQuestion();
            if(checkpointPath!=null) {
                asked(firstPriorityQuestion && acting==controller
                    && e.getQueryType()==PlayerQueryEvent.QueryType.SELECT && game.getStep()!=null
                    && game.getStep().getStepPart()==mage.game.turn.Step.StepPart.PRIORITY);
                // A request armed before this safe point is written before the prompt is published,
                // so the file always matches a published decision.
                checkpoint();
            }
            snapshot();
            cancellation.runIfOpen(()->mailbox.ask(seat,QueryEncoder.encode(e,game),
                answer->cancellation.runIfOpen(()->seats.get(seat).offer(answer))));
        }
        /** GAME thread, before a question to the human seat is published. */
        private void asked(boolean safePoint) {
            synchronized(saveLock) {
                awaitingPlayer=true;atSafePoint=safePoint;
                if(safePoint) safePointGeneration++;
            }
        }
        /** GAME thread: the human's question was answered or retracted, or a concede changed the board. */
        private void leftDecision(boolean answered) {
            synchronized(saveLock) {atSafePoint=false;if(answered) awaitingPlayer=false;}
        }
        /**
         * GAME thread, at a published safe point (from query or the idle hook): writes when a save is
         * requested and this safe point is not saved yet. Never ends or blocks the game: a failed write
         * is recorded for polls, diagnostics and the waiting request.
         */
        private void checkpoint() {
            long generation;
            synchronized(saveLock) {
                if(!atSafePoint || !saveRequested || savedGeneration==safePointGeneration || cancellation.isClosing()) return;
                generation=safePointGeneration;writing=true;
            }
            boolean saved=false;
            try {
                LinkedHashMap<String,UUID> seatPlayers=new LinkedHashMap<>();
                players.forEach((seat,player)->seatPlayers.put(seat,player.getId()));
                Checkpoints.Written written=Checkpoints.write(checkpointPath,(MobileCommanderGame)game,seatPlayers,
                    new ArrayList<>(seats.keySet()),seatSummary,checkpointSequence+1);
                checkpointSequence=written.sequence;
                checkpointInfo=Collections.unmodifiableMap(Json.map("sequence",written.sequence,"savedAtMillis",written.savedAtMillis,
                    "turn",written.turn,"bytes",written.bytes,"writeMillis",written.writeMillis));
                checkpointFailure=null;failedCheckpoints=0;saved=true;
            } catch(Throwable failure) {
                EngineDiagnostics.capture("checkpoint-write",failure);
                failedCheckpoints++;
                checkpointFailure=Collections.unmodifiableMap(Json.map("code","checkpoint_write_failed",
                    "message","The game could not be saved; it continues without a new checkpoint.",
                    "atMillis",System.currentTimeMillis(),"failedWrites",failedCheckpoints));
            } finally {
                synchronized(saveLock) {
                    // One attempt answers the request, saved or not; a failure is not retried until asked again.
                    writing=false;saveRequested=false;lastWriteSaved=saved;writeAttempts++;
                    if(saved) savedGeneration=generation;
                    saveLock.notifyAll();
                }
            }
        }
        /**
         * CALL thread (the checkpoint op). Arms a save and waits up to waitMillis for the GAME thread
         * to write it. A request that is still pending stays armed for the human's next safe point.
         */
        Map<String,Object> requestCheckpoint(long waitMillis) {
            if(checkpointPath==null) throw new BridgeException("checkpoint_unavailable","This match does not save games");
            long deadline=System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(waitMillis);
            synchronized(saveLock) {
                Map<String,Object> settled=settled();
                if(settled!=null) return settled;
                long attempts=writeAttempts;
                saveRequested=true;
                while(true) {
                    if(writeAttempts>attempts) return lastWriteSaved?Json.map("state","saved","checkpoint",checkpointInfo)
                        :Json.map("state","failed","checkpointFailure",checkpointFailure);
                    settled=settled();
                    if(settled!=null) return settled;
                    long remaining=deadline-System.nanoTime();
                    // The human must first answer a non-priority question (targets, payment, mulligan,
                    // attackers); otherwise the engine is still on its way to the next safe point.
                    if(remaining<=0) return Json.map("state","pending","waitingFor",awaitingPlayer && !atSafePoint?"player":"engine");
                    try { TimeUnit.NANOSECONDS.timedWait(saveLock,remaining); }
                    catch(InterruptedException e) { Thread.currentThread().interrupt();deadline=System.nanoTime(); }
                }
            }
        }
        /** Under saveLock: the reply that needs no new write, or null. */
        private Map<String,Object> settled() {
            if(cancellation.isClosing() || "failed".equals(stopped) || "closed".equals(stopped))
                throw new BridgeException("match_unavailable","The match has stopped");
            if(stopped!=null || humanLeft) return Json.map("state","over");
            if(atSafePoint && savedGeneration==safePointGeneration) return Json.map("state","saved","checkpoint",checkpointInfo);
            return null;
        }
        /** Clears an armed request. A write already under way finishes first (at most about a second). */
        void cancelCheckpoint() {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(1);
            synchronized(saveLock) {
                saveRequested=false;
                while(writing) {
                    long remaining=deadline-System.nanoTime();
                    if(remaining<=0) break;
                    try { TimeUnit.NANOSECONDS.timedWait(saveLock,remaining); }
                    catch(InterruptedException e) { Thread.currentThread().interrupt();break; }
                }
            }
        }
        private void stop(String how) {
            synchronized(saveLock) {if(stopped==null) stopped=how;saveLock.notifyAll();}
        }
        void start() {
            for(Map.Entry<String,MobileHumanPlayer> s:seats.entrySet()) {
                s.getValue().onConsumed(()->{leftDecision(true);cancellation.runIfOpen(()->mailbox.consumed(s.getKey()));});
                s.getValue().onRetracted(()->{leftDecision(true);cancellation.runIfOpen(()->mailbox.retract(s.getKey()));});
                s.getValue().onBoardChanged(()->{leftDecision(false);snapshot();});
                if(checkpointPath!=null) s.getValue().onIdle(this::checkpoint);
            }
            game.addPlayerQueryEventListener(new QueryListener());
            task=worker.submit(()->{
                try {
                    // A restored game re-asks the checkpointed priority decision (upstream
                    // GameImpl.resume -> playPriority(resuming=true)).
                    if(resumed) game.resume();
                    else game.start(seats.values().iterator().next().getId());
                    if(cancellation.isClosing()) return;
                    if(game.hasEnded()) {match.endGame();snapshot();mailbox.finish();stop("ended");}
                    else mailbox.fail("engine_stopped","XMage returned before ending the match");
                } catch(CancellationException ignored) {
                } catch(Throwable e) {
                    EngineDiagnostics.capture("game-worker",e);
                    if(Boolean.getBoolean("magicmobile.debug")) e.printStackTrace(System.err);
                    mailbox.fail(e instanceof BridgeException?((BridgeException)e).code():"engine_failure","The local engine stopped. This match cannot continue.");
                } finally { stop(game.hasEnded()?"ended":"failed");worker.shutdown(); }
            });
        }
        boolean close() {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
            stop("closed");
            cancellation.close();
            seats.values().forEach(MobileHumanPlayer::closeChannel);
            if(task!=null) task.cancel(true);
            worker.shutdownNow();mailbox.close();
            try {
                if(!worker.awaitTermination(Math.max(0,deadline-System.nanoTime()),TimeUnit.NANOSECONDS)) return false;
                if(!mailbox.awaitDeliveryTermination(deadline)) return false;
                return cancellation.awaitQuiescence(deadline);
            }
            catch(InterruptedException e) {Thread.currentThread().interrupt();return false;}
        }
    }
    public XmageEngine(String execution) {
        this.execution=Objects.requireNonNull(execution);
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
    }
    /** Same compiled loader/Commander validator as create, without starting a game or AI. */
    @Override public synchronized Map<String,Object> validateDeck(Map<String,Object> deck) {
        if(closed) throw new BridgeException("engine_closed","Engine is closed");
        if(!matches.isEmpty()) throw new BridgeException("engine_busy","Finish the active game before validating a deck");
        DeckLoader.load(deck);
        return Json.map("valid",true,"validator","Commander","issues",List.of(),
            "upstream",UPSTREAM,"catalogueHash",GeneratedCardFactory.CATALOGUE_HASH);
    }
    @Override public synchronized Map<String,Object> create(Map<String,Object> configuration) {
        if(closed) throw new BridgeException("engine_closed","Engine is closed");
        Json.onlyKeys(configuration,Set.of("seats","checkpoint"));
        if(!matches.isEmpty()) throw new BridgeException("match_limit","Destroy the active match before starting another");
        List<Object> configSeats=Json.array(configuration.get("seats"));
        if(configSeats.size()<2 || configSeats.size()>4) throw new BridgeException("invalid_seats","Need 2–4 seats");
        Path checkpointPath=null;
        if(configuration.containsKey("checkpoint")) {
            // Solo games against AI only: a checkpoint holds every hidden zone of the match.
            checkpointPath=newCheckpointPath(configuration.get("checkpoint"));
            long humans=configSeats.stream().filter(s->s instanceof Map
                && "human".equals(((Map<?,?>)s).containsKey("controller")?((Map<?,?>)s).get("controller"):"human")).count();
            if(humans!=1) throw new BridgeException("invalid_configuration","Checkpoints need exactly one human seat");
            if(!Checkpoints.available()) throw new BridgeException("checkpoint_unavailable","This engine build cannot save games");
        }
        LinkedHashMap<String,MobileHumanPlayer> seats=new LinkedHashMap<>();
        LinkedHashMap<String,Player> players=new LinkedHashMap<>();
        List<Map<String,Object>> seatSummary=new ArrayList<>();
        MobileAICancellation cancellation=new MobileAICancellation();
        MobileCommanderMatch match=new MobileCommanderMatch();
        for(Object value:configSeats) {
            Map<String,Object> s=Json.object(value);Json.onlyKeys(s,Set.of("seatId","name","controller","deck","aiSkill"));String id=Json.requiredString(s,"seatId");
            if(id.isEmpty() || id.length()>128 || players.containsKey(id)) throw new BridgeException("invalid_seat","Seat IDs must be unique and nonempty");
            String controller=Json.optionalString(s,"controller","human");
            Player player;
            if(controller.equals("human")) {
                if(s.containsKey("aiSkill")) throw new BridgeException("invalid_ai_skill","AI skill applies only to AI seats");
                MobileHumanPlayer human=new MobileHumanPlayer(Json.requiredString(s,"name"));
                player=human;seats.put(id,human);
            } else if(controller.equals("ai")) {
                player=cancellation.player(Json.requiredString(s,"name"),aiSkill(s));
            } else throw new BridgeException("invalid_controller","Controller must be human or ai");
            match.addPlayer(player,DeckLoader.load(Json.object(s.get("deck"))));players.put(id,player);
            seatSummary.add(Json.map("seatId",id,"name",player.getName(),"controller",controller));
        }
        if(seats.isEmpty()) throw new BridgeException("invalid_seats","Need at least one human seat");
        try {match.startMatch();match.startGame();}
        catch(GameException e) {throw new BridgeException("match_initialization_failed","XMage could not initialize this match");}
        Running running=new Running(match,players,seats,cancellation,checkpointPath,seatSummary,0,false);
        String id=match.getGame().getId().toString();
        matches.put(id,running);running.start();
        return Json.map("matchId",id,"seats",new ArrayList<>(players.keySet()),"engine",capabilities());
    }
    /** Absolute file path inside an existing directory. The app owns the file; the engine never deletes it. */
    private static Path checkpointPath(Object value,String code) {
        Map<String,Object> checkpoint;String text;
        try {
            checkpoint=Json.object(value);
            if(!checkpoint.keySet().equals(Set.of("path"))) throw new BridgeException(code,"A checkpoint has exactly one path");
            text=Json.requiredString(checkpoint,"path");
        } catch(BridgeException e) {
            if(e.code().equals(code)) throw e;
            throw new BridgeException(code,"A checkpoint needs an absolute file path");
        }
        Path path;
        try { path=text.isEmpty() || text.length()>4096 || text.indexOf('\0')>=0 ? null : Path.of(text); }
        catch(java.nio.file.InvalidPathException e) { path=null; }
        if(path==null || !path.isAbsolute() || path.getFileName()==null || path.getParent()==null)
            throw new BridgeException(code,"A checkpoint needs an absolute file path");
        return path.normalize();
    }
    private static Path newCheckpointPath(Object value) {
        Path path=checkpointPath(value,"invalid_configuration");
        if(!Files.isDirectory(path.getParent())) throw new BridgeException("invalid_configuration","The checkpoint directory does not exist");
        if(Files.isDirectory(path)) throw new BridgeException("invalid_configuration","The checkpoint path is a directory");
        return path;
    }
    /**
     * Restores a solo match saved by this engine build. Every check and the whole read happen
     * before any match or thread exists, so a failure leaves nothing running.
     */
    @Override public synchronized Map<String,Object> restore(Map<String,Object> request) {
        if(closed) throw new BridgeException("engine_closed","Engine is closed");
        if(!Checkpoints.available()) throw new BridgeException("checkpoint_unavailable","This engine build cannot restore games");
        Path path=checkpointPath(request,"invalid_request");
        if(!matches.isEmpty()) throw new BridgeException("match_limit","Destroy the active match before starting another");
        Checkpoints.Loaded loaded=Checkpoints.read(path);
        Checkpoints.Payload payload=loaded.payload;
        MobileCommanderGame game=payload.game;
        LinkedHashMap<String,Player> players=new LinkedHashMap<>();
        LinkedHashMap<String,MobileHumanPlayer> seats=new LinkedHashMap<>();
        List<Map<String,Object>> seatSummary=new ArrayList<>();
        MobileAICancellation cancellation=new MobileAICancellation();
        MobileCommanderMatch match;
        try {
            if(game==null || payload.seats==null || payload.humanSeats==null || payload.random==null
                    || payload.humanSeats.size()!=1 || payload.seats.size()<2 || payload.seats.size()>4 || game.hasEnded())
                throw new IllegalStateException("Checkpoint does not describe a live solo match");
            List<Object> headerSeats=Json.array(loaded.header.get("seats"));
            if(headerSeats.size()!=payload.seats.size()) throw new IllegalStateException("Checkpoint seats differ from its header");
            int index=0;
            for(Map.Entry<String,UUID> seat:payload.seats.entrySet()) {
                Player player=game.getPlayer(seat.getValue());
                Map<String,Object> summary=Json.object(headerSeats.get(index++));
                boolean human=payload.humanSeats.contains(seat.getKey());
                if(player==null || !seat.getKey().equals(summary.get("seatId")) || human!=(player instanceof MobileHumanPlayer)
                        || !(human?"human":"ai").equals(summary.get("controller")))
                    throw new IllegalStateException("Checkpoint seat binding is inconsistent");
                players.put(seat.getKey(),player);
                if(human) seats.put(seat.getKey(),(MobileHumanPlayer)player);
                seatSummary.add(Json.map("seatId",seat.getKey(),"name",player.getName(),"controller",human?"human":"ai"));
            }
            cancellation.adopt(game);
            Checkpoints.rehydrateSingletons(game);
            match=MobileCommanderMatch.restored(game);
        } catch(RuntimeException | LinkageError e) {
            throw Checkpoints.corrupt("The checkpoint could not be restored",e);
        }
        Running running=new Running(match,players,seats,cancellation,path,seatSummary,loaded.sequence(),true);
        // The file just read is the latest checkpoint until a requested save writes the next one.
        running.checkpointInfo=Collections.unmodifiableMap(Json.map("sequence",loaded.sequence(),"savedAtMillis",loaded.savedAtMillis(),
            "turn",(long)loaded.turn(),"bytes",loaded.bytes,"writeMillis",0L));
        String id=game.getId().toString();
        matches.put(id,running);
        // Last, so the restored game draws exactly what the saved process would have drawn next.
        mage.util.RandomUtil.restoreRandom(payload.random);
        running.start();
        return Json.map("matchId",id,"seats",new ArrayList<>(players.keySet()),"engine",capabilities(),
            "restored",Json.map("turn",loaded.turn(),"savedAtMillis",loaded.savedAtMillis(),"sequence",loaded.sequence()));
    }
    static int aiSkill(Map<String,Object> seat) {
        if(!seat.containsKey("aiSkill")) return 1; // Preserve existing callers' upstream budget.
        long skill;
        try { skill=Json.integer(seat.get("aiSkill")); }
        catch(BridgeException invalid) { throw new BridgeException("invalid_ai_skill","AI skill must be an integer from 1 to 10"); }
        if(skill<1 || skill>10) throw new BridgeException("invalid_ai_skill","AI skill must be an integer from 1 to 10");
        return (int)skill;
    }
    private synchronized Running match(String id) {
        Running r=matches.get(id);if(r==null) throw new BridgeException("unknown_match","Match does not exist");return r;
    }
    @Override public Map<String,Object> poll(String id,String seat,long after) {
        Running running=match(id);
        Map<String,Object> result=running.mailbox.poll(seat,after);
        // Local metadata only; the checkpoint file itself never enters a poll.
        Map<String,Object> saved=running.checkpointInfo,failure=running.checkpointFailure;
        if(saved!=null) result.put("checkpoint",saved);
        if(failure!=null) result.put("checkpointFailure",failure);
        return result;
    }
    @Override public Map<String,Object> respond(String id,String seat,Map<String,Object> c) {return match(id).mailbox.submit(seat,c);}
    /** Unsynchronized: waits up to waitMillis for the GAME thread's write without holding the engine. */
    @Override public Map<String,Object> checkpoint(String id,long waitMillis) {
        if(waitMillis<0 || waitMillis>EngineService.MAX_CHECKPOINT_WAIT_MILLIS)
            throw new BridgeException("invalid_request","waitMillis must be 0 to "+EngineService.MAX_CHECKPOINT_WAIT_MILLIS);
        return match(id).requestCheckpoint(waitMillis);
    }
    @Override public Map<String,Object> cancelCheckpoint(String id) {
        match(id).cancelCheckpoint();
        return Json.map("cancelled",true);
    }
    @Override public void concede(String id,String seat) {match(id).concede(seat);}
    @Override public synchronized void destroy(String id) {
        Running r=matches.get(id);if(r==null) throw new BridgeException("unknown_match","Match does not exist");
        if(!r.close()) throw new BridgeException("engine_busy_shutdown","The old game or AI simulation has not stopped; retry destroy before creating another match");
        matches.remove(id);
    }
    @Override public Map<String,Object> capabilities() {
        return Json.map("protocol",1,"engine","xmage","execution",execution,"upstream",UPSTREAM,
            "catalogueHash",GeneratedCardFactory.CATALOGUE_HASH,"maxPlayers",4,"deckValidation",true,
            "nativeDeviceValidated",false,"aiEnabled",false,"hostMigration",false,
            // True only when this build passes its checkpoint round trip (native needs serialization metadata).
            // It saves only when asked (the checkpoint op), never at every decision.
            "saveResume",Checkpoints.available(),"checkpointOnDemand",Checkpoints.available(),
            "concede",true,"experimental",true,
            // Optional standing instructions an answer may carry (AnswerActions, docs/PROTOCOL.md).
            "answerActions",AnswerActions.TYPES);
    }
    @Override public synchronized void close() {
        closed=true;
        Iterator<Running> iterator=matches.values().iterator();
        while(iterator.hasNext()) {
            if(iterator.next().close()) iterator.remove();
        }
        if(!matches.isEmpty())
            throw new BridgeException("engine_busy_shutdown","The game or AI simulation has not stopped; retry shutdown");
    }
}
