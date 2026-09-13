package io.magicmobile.xmage;

import io.magicmobile.core.*;
import io.magicmobile.generated.GeneratedCardFactory;
import io.magicmobile.generated.GeneratedSetRegistry;
import mage.cards.MobileCardFactories;
import mage.constants.*;
import mage.game.*;
import mage.game.events.PlayerQueryEvent;
import mage.players.Player;
import java.util.*;
import java.util.concurrent.*;

/**
 * In-process engine; no SessionImpl, HTTP, Docker, remote XMage server or desktop client.
 * This adapter must pass the real-engine and native build gates before being released.
 */
public final class XmageEngine implements EnginePort {
    public static final String UPSTREAM="8aea65ae9ae3c89970fe865e1316105539e097ca";
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
        Running(MobileCommanderMatch match,LinkedHashMap<String,Player> players,LinkedHashMap<String,MobileHumanPlayer> seats,MobileAICancellation cancellation) {
            this.match=match;this.game=match.getGame();this.players=players;this.seats=seats;
            this.cancellation=cancellation;((MobileCommanderGame)game).setCancellation(cancellation);
            mailbox=new MatchMailbox(game.getId().toString(),seats.keySet());
            worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME mobile-"+game.getId());t.setDaemon(true);return t;});
        }
        String seatFor(UUID engineId) {
            for(Map.Entry<String,MobileHumanPlayer> s:seats.entrySet()) if(s.getValue().getId().equals(engineId))return s.getKey();
            throw new BridgeException("unbound_player","Engine asked an unbound player for input");
        }
        void snapshot() {
            if(cancellation.isClosing()) return;
            Map<String,Map<String,Object>> views=ViewProjector.project(game,seats);
            cancellation.runIfOpen(()->mailbox.publishSnapshots(views));
        }
        void query(PlayerQueryEvent e) {
            if(cancellation.isClosing()) return;
            mage.players.Player acting=game.getPlayer(e.getPlayerId());
            if(acting==null) throw new BridgeException("unbound_player","Engine queried a player outside this game");
            mage.players.Player controller=game.getPlayer(acting.getTurnControlledBy());
            if(controller==null) throw new BridgeException("unbound_player","Engine queried a player with an unknown controller");
            // Some events already name the controller; resolve once, never follow control chains.
            if(!controller.getId().equals(controller.getTurnControlledBy())
                    || (!acting.getId().equals(controller.getId()) && !acting.getPlayersUnderYourControl().isEmpty()))
                throw new BridgeException("nested_turn_control_not_supported","Chained turn control has no unambiguous mobile recipient");
            if(!(controller instanceof MobileHumanPlayer)) {
                // MAD publishes priority SELECT notifications, then decides internally.
                if(e.getQueryType()!=PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) snapshot();
                return;
            }
            String seat=seatFor(controller.getId());
            if(e.getQueryType()==PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) {
                cancellation.runIfOpen(()->mailbox.inform(seat,Json.map("message",e.getMessage())));return;
            }
            snapshot();
            cancellation.runIfOpen(()->mailbox.ask(seat,QueryEncoder.encode(e,game),
                answer->cancellation.runIfOpen(()->seats.get(seat).offer(answer))));
        }
        void start() {
            for(Map.Entry<String,MobileHumanPlayer> s:seats.entrySet())
                s.getValue().onConsumed(()->cancellation.runIfOpen(()->mailbox.consumed(s.getKey())));
            game.addPlayerQueryEventListener(this::query);
            task=worker.submit(()->{
                try {
                    game.start(seats.values().iterator().next().getId());
                    if(cancellation.isClosing()) return;
                    if(game.hasEnded()) {match.endGame();snapshot();mailbox.finish();}
                    else mailbox.fail("engine_stopped","XMage returned before ending the match");
                } catch(CancellationException ignored) {
                    // Expected on destroy; a stopped match never claims to have completed.
                } catch(Throwable e) {
                    EngineDiagnostics.capture("game-worker",e);
                    // Explicit developer opt-in only; exceptions can contain private card data.
                    if(Boolean.getBoolean("magicmobile.debug")) e.printStackTrace(System.err);
                    mailbox.fail(e instanceof BridgeException?((BridgeException)e).code():"engine_failure","The local engine stopped. This match cannot continue.");
                } finally { worker.shutdown(); }
            });
        }
        boolean close() {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
            cancellation.close();
            seats.values().forEach(MobileHumanPlayer::closeChannel);
            if(task!=null) task.cancel(true);
            worker.shutdownNow();mailbox.close();
            try {
                if(!worker.awaitTermination(Math.max(0,deadline-System.nanoTime()),TimeUnit.NANOSECONDS)) return false;
                return cancellation.awaitQuiescence(deadline);
            }
            catch(InterruptedException e) {Thread.currentThread().interrupt();return false;}
            // No unsafe game.end()/cleanUp() from a UI thread while XMage may still be executing.
        }
    }
    public XmageEngine(String execution) {
        this.execution=Objects.requireNonNull(execution);
        MobileCardFactories.install(GeneratedCardFactory::create);
        GeneratedSetRegistry.install();
    }
    @Override public synchronized Map<String,Object> create(Map<String,Object> configuration) {
        if(closed) throw new BridgeException("engine_closed","Engine is closed");
        Json.onlyKeys(configuration,Set.of("seats"));
        // One active match limits engine threads, memory, and static upstream interactions on a phone.
        if(!matches.isEmpty()) throw new BridgeException("match_limit","Destroy the active match before starting another");
        List<Object> configSeats=Json.array(configuration.get("seats"));
        if(configSeats.size()<2 || configSeats.size()>4) throw new BridgeException("invalid_seats","Need 2–4 seats");
        LinkedHashMap<String,MobileHumanPlayer> seats=new LinkedHashMap<>();
        LinkedHashMap<String,Player> players=new LinkedHashMap<>();
        MobileAICancellation cancellation=new MobileAICancellation();
        MobileCommanderMatch match=new MobileCommanderMatch();
        for(Object value:configSeats) {
            Map<String,Object> s=Json.object(value);Json.onlyKeys(s,Set.of("seatId","name","controller","deck"));String id=Json.requiredString(s,"seatId");
            if(id.isEmpty() || id.length()>128 || players.containsKey(id)) throw new BridgeException("invalid_seat","Seat IDs must be unique and nonempty");
            String controller=Json.optionalString(s,"controller","human");
            Player player;
            if(controller.equals("human")) {
                MobileHumanPlayer human=new MobileHumanPlayer(Json.requiredString(s,"name"));
                player=human;seats.put(id,human);
            } else if(controller.equals("ai")) {
                player=cancellation.player(Json.requiredString(s,"name"));
            } else throw new BridgeException("invalid_controller","Controller must be human or ai");
            match.addPlayer(player,DeckLoader.load(Json.object(s.get("deck"))));players.put(id,player);
        }
        if(seats.isEmpty()) throw new BridgeException("invalid_seats","Need at least one human seat");
        try {match.startMatch();match.startGame();}
        catch(GameException e) {throw new BridgeException("match_initialization_failed","XMage could not initialize this match");}
        Running running=new Running(match,players,seats,cancellation);String id=match.getGame().getId().toString();
        matches.put(id,running);running.start();
        return Json.map("matchId",id,"seats",new ArrayList<>(players.keySet()),"engine",capabilities());
    }
    private synchronized Running match(String id) {
        Running r=matches.get(id);if(r==null) throw new BridgeException("unknown_match","Match does not exist");return r;
    }
    @Override public Map<String,Object> poll(String id,String seat,long after) {return match(id).mailbox.poll(seat,after);}
    @Override public Map<String,Object> respond(String id,String seat,Map<String,Object> c) {return match(id).mailbox.submit(seat,c);}
    @Override public synchronized void destroy(String id) {
        Running r=matches.get(id);if(r==null) throw new BridgeException("unknown_match","Match does not exist");
        if(!r.close()) throw new BridgeException("engine_busy_shutdown","The old game or AI simulation has not stopped; retry destroy before creating another match");
        matches.remove(id);
    }
    @Override public Map<String,Object> capabilities() {
        return Json.map("protocol",1,"engine","xmage","execution",execution,"upstream",UPSTREAM,
            "catalogueHash",GeneratedCardFactory.CATALOGUE_HASH,"maxPlayers",4,
            "nativeDeviceValidated",false,"aiEnabled",false,"hostMigration",false,
            "saveResume",false,"experimental",true);
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
