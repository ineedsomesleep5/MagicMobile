package io.magicmobile.xmage;

import io.magicmobile.core.*;
import mage.abilities.costs.mana.GenericManaCost;
import mage.cards.*;
import mage.cards.decks.Deck;
import mage.cards.g.GrizzlyBears;
import mage.constants.*;
import mage.game.Game;
import mage.game.events.PlayerQueryEvent;
import mage.game.permanent.PermanentCard;
import mage.game.turn.PreCombatMainPhase;
import mage.game.turn.PreCombatMainStep;
import mage.players.Player;

import java.lang.reflect.*;
import java.util.*;
import java.util.concurrent.*;

/**
 * Standalone real-XMage control/privacy tests. Reflection reaches the private Running.query seam;
 * no mock engine, proxy stubs, complete games, Maven, or native builds are used.
 * From the package root after build_jvm.sh:
 * CP=$(cat build/runtime-classpath.txt)
 * javac --release 17 -cp "$CP" -d build/test-control \
 *   engine/xmage/src/main/java/io/magicmobile/xmage/MobileHumanPlayer.java \
 *   engine/xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java \
 *   engine/xmage/src/main/java/io/magicmobile/xmage/ViewProjector.java \
 *   engine/xmage/src/test/java/io/magicmobile/xmage/RealControlPrivacyTests.java
 * java -Xmx512m -cp "build/test-control:$CP" io.magicmobile.xmage.RealControlPrivacyTests
 */
public final class RealControlPrivacyTests {
    private static int passed,failed;
    public static void main(String[] args) {
        run("acted-player and controller-addressed query routing",RealControlPrivacyTests::routing);
        run("real controlled HumanPlayer input and consumed receipt",RealControlPrivacyTests::controlledInput);
        run("controlled mana prompt preserves acted-player pool identity",RealControlPrivacyTests::controlledMana);
        run("proxy state, copied channel, reset and stale rejection",RealControlPrivacyTests::proxyAndReset);
        run("controlled-hand disclosure before, during and after reset",RealControlPrivacyTests::handPrivacy);
        run("replaced controller cannot retain hand disclosure",RealControlPrivacyTests::replacedController);
        run("controlled views expose permitted hidden information only while authorized",RealControlPrivacyTests::hiddenZones);
        run("unknown and chained control fail explicitly",RealControlPrivacyTests::invalidControl);
        System.out.println("RealControlPrivacyTests: "+passed+" passed, "+failed+" failed");
        if(failed!=0) throw new AssertionError("Real control/privacy verification failed");
    }

    private static void routing() throws Exception {
        try(Rig r=new Rig()) {
            r.control("a","b");
            for(UUID recipient:List.of(r.player("b").getId(),r.player("a").getId())) {
                PlayerQueryEvent event=PlayerQueryEvent.amountEvent(recipient,"Private control decision",0,9);
                r.query(event);
                Map<String,Object> prompt=r.prompt("a");
                check(prompt!=null,"controller receives prompt");
                eq(r.prompt("b"),null);eq(r.prompt("c"),null);
                check(!Json.write(r.mailbox.poll("c",0)).contains("Private control decision"),"observer sees no private prompt text");
                Map<String,Object> command=command(prompt,"integer",7);
                expectCode("stale_prompt",()->r.mailbox.submit("b",command));
                expectCode("stale_prompt",()->r.mailbox.submit("c",command));
                // End this synthetic prompt without queuing an answer; the next query replaces it.
            }
            r.player("b").setGameUnderYourControl(r.game,true);
            r.query(PlayerQueryEvent.amountEvent(r.player("b").getId(),"After reset",0,9));
            check(r.prompt("b")!=null,"reset routes a new decision to its original seat");
        }
    }

    private static void controlledInput() throws Exception {
        try(Rig r=new Rig()) {
            r.control("a","b");
            // Wrong-seat queued data must not be consumed during control.
            r.player("b").offer(Json.map("kind","integer","value",2));
            Future<Integer> result=r.ask(r.player("b"));
            PlayerQueryEvent event=r.nextEvent();eq(event.getPlayerId(),r.player("b").getId());
            check(r.prompt("a")!=null,"acted-player event reaches controller");
            r.submit("a",7);eq(await(result),7);eq(r.prompt("a"),null);
            check(Json.write(r.mailbox.poll("a",0)).contains("prompt_consumed"),"consumption acknowledges controller mailbox");
            r.player("b").setGameUnderYourControl(r.game,true);
            result=r.ask(r.player("b"));r.nextEvent();
            eq(await(result),2); // original channel still owns its independently queued input
        }
    }

    private static void proxyAndReset() throws Exception {
        try(Rig r=new Rig()) {
            r.control("a","b");
            Card secret=r.hand("b");
            Player proxy=r.player("a").prepareControllableProxy(r.player("b"));
            check(proxy instanceof MobileHumanPlayer,"proxy retains mobile transport");
            eq(proxy.getId(),r.player("b").getId());eq(proxy.getTurnControlledBy(),r.player("a").getId());
            check(proxy.getHand().contains(secret.getId()),"proxy retains acted player's state");
            proxy.getHand().clear();check(r.player("b").getHand().contains(secret.getId()),"copied hand is independent");
            Player copy=proxy.copy();
            Future<Integer> result=r.ask(copy);r.nextEvent();
            Map<String,Object> oldCommand=command(r.prompt("a"),"integer",6);
            r.mailbox.submit("a",oldCommand);eq(await(result),6);
            r.player("b").setGameUnderYourControl(r.game,true);
            oldCommand.put("requestId",UUID.randomUUID().toString());
            expectCode("stale_prompt",()->r.mailbox.submit("a",oldCommand));
            expectCode("stale_control_proxy",()->await(r.ask(proxy)));
            r.nextEvent(); // stale proxy may emit before wait; it must never consume the former controller's input
            r.player("a").offer(Json.map("kind","integer","value",9));
            result=r.ask(r.player("b"));r.nextEvent();r.submit("b",3);eq(await(result),3);
            result=r.ask(r.player("a"));r.nextEvent();eq(await(result),9);
        }
    }

    private static void controlledMana() throws Exception {
        try(Rig r=new Rig()) {
            r.control("a","b");
            Future<Boolean> result=r.worker.submit(()->r.player("b").playMana(null,new GenericManaCost(1),"{1}",r.game));
            r.nextEvent();
            Map<String,Object> prompt=r.prompt("a");
            eq(Json.object(prompt.get("payload")).get("manaPlayerId"),r.player("b").getId().toString());
            r.mailbox.submit("a",command(prompt,"mana",Json.map("playerId",r.player("b").getId().toString(),"manaType","GREEN")));
            eq(await(result),true);
            eq(r.player("b").getManaPool().getUnlockedManaType(),ManaType.GREEN);
            eq(r.player("a").getManaPool().getUnlockedManaType(),null);eq(r.prompt("a"),null);
        }
    }

    private static void handPrivacy() throws Exception {
        try(Rig r=new Rig()) {
            Card a=r.hand("a"),b=r.hand("b"),c=r.hand("c");
            Map<String,Map<String,Object>> before=ViewProjector.project(r.game,r.seats);
            absent(before.get("a"),b);absent(before.get("a"),c);absent(before.get("c"),b);
            r.control("a","b");
            Map<String,Map<String,Object>> during=ViewProjector.project(r.game,r.seats);
            Map<String,Object> aView=gameView(during.get("a"));
            Map<String,Object> hands=Json.object(aView.get("opponentHands"));
            Map<String,Object> controlled=Json.object(hands.get(r.player("b").getName()));
            Map<String,Object> card=Json.object(controlled.get(b.getId().toString()));
            eq(card.get("expansionSetCode"),"LEA");eq(card.get("cardNumber"),"202");
            check(!card.containsKey("rules") && !card.containsKey("abilities"),"controlled hand uses upstream SimpleCardView DTO");
            check(Json.object(aView.get("myHand")).containsKey(a.getId().toString()),"controller's own hand retained");
            check(Json.object(gameView(during.get("b")).get("myHand")).containsKey(b.getId().toString()),"owner retains own hand");
            Map<String,Object> controlledView=controlledView(during.get("a"),r.player("b"));
            eq(controlledView.get("myPlayerId"),r.player("b").getId().toString());
            check(Json.object(controlledView.get("myHand")).containsKey(b.getId().toString()),"additive real GameView includes controlled hand");
            absent(during.get("a"),c);absent(during.get("c"),a);absent(during.get("c"),b);absent(during.get("b"),a);
            r.player("b").setGameUnderYourControl(r.game,true);
            Map<String,Map<String,Object>> after=ViewProjector.project(r.game,r.seats);
            absent(after.get("a"),b);absent(after.get("c"),b);
            check(Json.object(gameView(after.get("a")).get("opponentHands")).isEmpty(),"reset removes controlled hands");
            check(Json.object(after.get("a").get("controlledPlayerViews")).isEmpty(),"reset removes controlled views");
            check(r.player("a").getHand().contains(a.getId()) && r.player("b").getHand().contains(b.getId()),"projection never transfers authoritative cards");
        }
    }

    private static void replacedController() throws Exception {
        try(Rig r=new Rig()) {
            Card secret=r.hand("b");r.control("a","b");r.control("c","b");
            // Upstream's reverse set retains the previous controller until reset.
            check(r.player("a").getPlayersUnderYourControl().contains(r.player("b").getId()),"real stale reverse set reproduced");
            Map<String,Map<String,Object>> views=ViewProjector.project(r.game,r.seats);
            absent(views.get("a"),secret);
            check(Json.write(views.get("c")).contains(secret.getId().toString()),"current controller sees the hand");
            r.query(PlayerQueryEvent.amountEvent(r.player("b").getId(),"New controller",0,9));
            check(r.prompt("c")!=null,"replacement controller receives query");eq(r.prompt("a"),null);
            r.player("b").setGameUnderYourControl(r.game,true,false);
            eq(r.player("b").getTurnControlledBy(),r.player("a").getId());
            views=ViewProjector.project(r.game,r.seats);absent(views.get("c"),secret);
            check(Json.write(views.get("a")).contains(secret.getId().toString()),"partial reset restores prior controller");
        }
    }

    private static void invalidControl() throws Exception {
        try(Rig r=new Rig()) {
            expectCode("unbound_player",()->r.query(PlayerQueryEvent.selectEvent(UUID.randomUUID(),"Unknown")));
            r.player("b").setTurnControlledBy(UUID.randomUUID());
            expectCode("unbound_player",()->r.query(PlayerQueryEvent.selectEvent(r.player("b").getId(),"Unknown controller")));
            for(Map<String,Object> snapshot:ViewProjector.project(r.game,r.seats).values())
                check(Json.object(snapshot.get("controlledPlayerViews")).isEmpty(),"unknown controller discloses no additional view");
        }
        try(Rig r=new Rig()) {
            r.control("a","b");r.control("c","a");
            for(String addressed:List.of("a","b"))
                expectCode("nested_turn_control_not_supported",()->r.query(PlayerQueryEvent.selectEvent(r.player(addressed).getId(),"Chained control")));
            eq(r.prompt("a"),null);eq(r.prompt("b"),null);eq(r.prompt("c"),null);
            Card a=r.hand("a"),b=r.hand("b");
            Map<String,Map<String,Object>> snapshots=ViewProjector.project(r.game,r.seats);
            for(Map<String,Object> snapshot:snapshots.values()) {
                check(Json.object(snapshot.get("controlledPlayerViews")).isEmpty(),"chained control discloses no additional views");
                check(Json.object(gameView(snapshot).get("opponentHands")).isEmpty(),"chained control discloses no additional hands");
            }
            absent(snapshots.get("a"),b);absent(snapshots.get("c"),a);absent(snapshots.get("c"),b);
        }
    }

    private static void hiddenZones() throws Exception {
        try(Rig r=new Rig()) {
            Card library=r.hand("b"),looked=r.hand("b"),exiled=r.hand("b"),face=r.hand("b"),outside=r.hand("b"),independent=r.hand("c");
            for(Card card:List.of(library,looked,exiled,face,outside)) r.player("b").getHand().remove(card.getId());
            outside.setZone(Zone.OUTSIDE,r.game);r.player("b").getSideboard().add(outside);
            for(Card card:List.of(library,looked)) {
                card.setZone(Zone.LIBRARY,r.game);r.player("b").getLibrary().putOnTop(card,r.game);
            }
            r.game.getState().getLookedAt(r.player("b").getId()).add("Private library inspection",looked);
            exiled.setZone(Zone.EXILED,r.game);exiled.setFaceDown(true,r.game);r.game.getExile().add(exiled);
            PermanentCard permanent=new PermanentCard(face,r.player("b").getId(),r.game);
            permanent.setFaceDown(true,r.game);r.game.getBattlefield().addPermanent(permanent);r.game.setZone(face.getId(),Zone.BATTLEFIELD);
            r.control("a","b");
            Map<String,Map<String,Object>> snapshots=ViewProjector.project(r.game,r.seats);
            for(String seat:List.of("a","b","c")) absent(snapshots.get(seat),library);
            Map<String,Object> controlled=controlledView(snapshots.get("a"),r.player("b"));
            permittedHidden(controlled,looked,face,exiled);
            // The main view stays the controller's own perspective; only the additive view changes.
            for(String seat:List.of("a","c")) {
                privateHidden(gameView(snapshots.get(seat)),looked,face,exiled);
                absent(snapshots.get(seat),outside);
            }
            privateHidden(snapshots.get("c"),looked,face,exiled);
            absent(snapshots.get("a"),independent);
            permittedHidden(gameView(snapshots.get("b")),looked,face,exiled);
            check(Json.write(snapshots.get("b")).contains(outside.getId().toString()),"original player retains outside-game view");
            r.control("c","b");
            check(r.player("a").getPlayersUnderYourControl().contains(r.player("b").getId()),"stale reverse set remains");
            snapshots=ViewProjector.project(r.game,r.seats);
            check(Json.object(snapshots.get("a").get("controlledPlayerViews")).isEmpty(),"stale controller loses full view");
            privateHidden(snapshots.get("a"),looked,face,exiled);
            permittedHidden(controlledView(snapshots.get("c"),r.player("b")),looked,face,exiled);
            absent(snapshots.get("c"),outside);
            r.player("b").setGameUnderYourControl(r.game,true);
            Map<String,Map<String,Object>> reset=ViewProjector.project(r.game,r.seats);
            for(String seat:List.of("a","c")) {
                check(Json.object(reset.get(seat).get("controlledPlayerViews")).isEmpty(),"reset removes full views for both controllers");
                absent(reset.get(seat),library);absent(reset.get(seat),outside);
                privateHidden(reset.get(seat),looked,face,exiled);
            }
        }
    }

    private static Map<String,Object> controlledView(Map<String,Object> snapshot,Player controlled) {
        Map<String,Object> views=Json.object(snapshot.get("controlledPlayerViews"));
        eq(views.size(),1);
        check(views.containsKey(controlled.getId().toString()),"controlled view keyed by engine player UUID");
        return Json.object(views.get(controlled.getId().toString()));
    }

    private static void permittedHidden(Object value,Card looked,Card face,Card exiled) {
        List<Map<String,Object>> lookedViews=findViews(value,looked.getId());
        check(!lookedViews.isEmpty(),"authorized looked-at card is visible");
        for(Map<String,Object> view:lookedViews) {
            // Upstream LookedAtView intentionally identifies cards through SimpleCardView printing data.
            eq(view.get("expansionSetCode"),"LEA");eq(view.get("cardNumber"),"202");
        }
        List<Map<String,Object>> faced=findViews(value,face.getId());
        check(faced.stream().anyMatch(view->view.get("original")!=null
            && Json.write(view.get("original")).contains("Grizzly Bears")),"authorized face-down nested original is visible");
        List<Map<String,Object>> exileViews=findViews(value,exiled.getId());
        check(!exileViews.isEmpty() && Json.write(exileViews).contains("Grizzly Bears"),"upstream-authorized face-down exile identity is visible");
    }

    private static void privateHidden(Object value,Card looked,Card face,Card exiled) {
        absent(value,looked);
        List<Map<String,Object>> faced=findViews(value,face.getId());
        check(!faced.isEmpty(),"face-down permanent remains visible as a game object");
        for(Map<String,Object> view:faced) {
            check(view.get("original")==null,"opponent face-down original must not disclose card data");
            check(!Json.write(view).contains("Grizzly Bears"),"nested original/name fields remain hidden");
            check(view.get("originalColorIdentity")==null,"face-down original identity stays hidden");
        }
        List<Map<String,Object>> exileViews=findViews(value,exiled.getId());
        check(!exileViews.isEmpty(),"face-down exile remains represented");
        for(Map<String,Object> view:exileViews)
            check(!Json.write(view).contains("Grizzly Bears"),"face-down exile has no hidden card name");
    }

    private static List<Map<String,Object>> findViews(Object value,UUID id) {
        List<Map<String,Object>> found=new ArrayList<>();
        if(value instanceof Map<?,?>) {
            Map<String,Object> map=Json.object(value);
            if(id.toString().equals(map.get("id"))) found.add(map);
            for(Object child:map.values()) found.addAll(findViews(child,id));
        } else if(value instanceof List<?>) {
            for(Object child:Json.array(value)) found.addAll(findViews(child,id));
        }
        return found;
    }

    private static final class Rig implements AutoCloseable {
        final LinkedHashMap<String,MobileHumanPlayer> seats=new LinkedHashMap<>();
        final Game game;
        final Object running;
        final Method query,close;
        final MatchMailbox mailbox;
        final BlockingQueue<PlayerQueryEvent> events=new LinkedBlockingQueue<>();
        final ExecutorService worker=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"GAME control-privacy-tests");t.setDaemon(true);return t;});
        Rig() throws Exception {
            MobileCommanderMatch match=new MobileCommanderMatch();
            for(String id:List.of("a","b","c")) {
                MobileHumanPlayer p=new MobileHumanPlayer("Player "+id);seats.put(id,p);match.addPlayer(p,new Deck());
            }
            match.startMatch();match.startGame();game=match.getGame();
            seats.values().forEach(p->p.updateRange(game));
            PreCombatMainPhase phase=new PreCombatMainPhase();phase.setStep(new PreCombatMainStep());
            game.getState().getTurn().setPhase(phase);game.getState().setTurnNum(1);
            game.getState().setActivePlayerId(player("b").getId());
            Class<?> type=Class.forName("io.magicmobile.xmage.XmageEngine$Running");
            Constructor<?> constructor=type.getDeclaredConstructor(MobileCommanderMatch.class,LinkedHashMap.class);constructor.setAccessible(true);
            running=constructor.newInstance(match,seats);
            query=type.getDeclaredMethod("query",PlayerQueryEvent.class);query.setAccessible(true);
            close=type.getDeclaredMethod("close");close.setAccessible(true);
            Field field=type.getDeclaredField("mailbox");field.setAccessible(true);mailbox=(MatchMailbox)field.get(running);
            seats.forEach((id,p)->p.onConsumed(()->mailbox.consumed(id)));
            game.addPlayerQueryEventListener(e->{query(e);if(e.getQueryType()!=PlayerQueryEvent.QueryType.PERSONAL_MESSAGE) events.add(e);});
        }
        MobileHumanPlayer player(String id) {return seats.get(id);}
        void control(String controller,String controlled) {check(player(controller).controlPlayersTurn(game,player(controlled).getId(),"test"),"upstream control applied");}
        Card hand(String seat) {
            Card card=new GrizzlyBears(player(seat).getId(),new CardSetInfo("Grizzly Bears","LEA","202",Rarity.COMMON));
            game.loadCards(new HashSet<>(List.of(card)),player(seat).getId());card.setZone(Zone.HAND,game);player(seat).getHand().add(card);return card;
        }
        void query(PlayerQueryEvent event) {
            try {query.invoke(running,event);}
            catch(InvocationTargetException e) {throwCause(e.getCause());}
            catch(ReflectiveOperationException e) {throw new AssertionError(e);}
        }
        Map<String,Object> prompt(String seat) {Object p=mailbox.poll(seat,0).get("prompt");return p==null?null:Json.object(p);}
        Future<Integer> ask(Player p) {return worker.submit(()->p.getAmount(0,9,"Controlled amount",null,game));}
        PlayerQueryEvent nextEvent() throws Exception {PlayerQueryEvent e=events.poll(3,TimeUnit.SECONDS);check(e!=null,"real query emitted within deadline");return e;}
        void submit(String seat,int value) {mailbox.submit(seat,command(prompt(seat),"integer",value));}
        @Override public void close() throws Exception {
            seats.values().forEach(MobileHumanPlayer::closeChannel);worker.shutdownNow();
            check(worker.awaitTermination(2,TimeUnit.SECONDS),"query worker terminates");close.invoke(running);
        }
    }
    private static <T> T await(Future<T> task) throws Exception {
        try {return task.get(3,TimeUnit.SECONDS);}
        catch(ExecutionException e) {throwCause(e.getCause());throw new AssertionError("unreachable");}
        finally {if(!task.isDone()) task.cancel(true);}
    }
    private static void throwCause(Throwable cause) {if(cause instanceof RuntimeException) throw (RuntimeException)cause;if(cause instanceof Error) throw (Error)cause;throw new AssertionError(cause);}
    private static Map<String,Object> gameView(Map<String,Object> snapshot) {return Json.object(snapshot.get("gameView"));}
    private static void absent(Object view,Card card) {check(!Json.write(view).contains(card.getId().toString()),"private card absent from unauthorized view: "+card.getId());}
    private static Map<String,Object> command(Map<String,Object> prompt,String type,Object value) {
        check(prompt!=null,"prompt exists");
        return Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),"answer",Json.map("kind",type,"value",value));
    }
    private interface Test {void run() throws Exception;}
    private static void expectCode(String code,Test action) throws Exception {try {action.run();}catch(BridgeException e) {eq(e.code(),code);return;}throw new AssertionError("Expected "+code);}
    private static void run(String name,Test test) {try {test.run();passed++;System.out.println("PASS "+name);}catch(Throwable e) {failed++;System.err.println("FAIL "+name);e.printStackTrace();}}
    private static void check(boolean condition,String message) {if(!condition) throw new AssertionError(message);}
    private static void eq(Object actual,Object expected) {if(!Objects.equals(actual,expected)) throw new AssertionError("Expected "+expected+", got "+actual);}
}
