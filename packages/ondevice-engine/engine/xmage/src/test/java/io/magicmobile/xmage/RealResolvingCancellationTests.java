package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import mage.Mana;
import mage.cards.Card;
import mage.cards.f.FactOrFiction;
import mage.constants.Zone;
import mage.game.Game;
import mage.players.Player;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;

/**
 * Real production game worker, ordinary cast/priority path, genuine upstream pile choice.
 * Test-only setup moves the deck's Fact or Fiction into hand and seeds four blue mana
 * while the real worker is parked at priority. No listener, replacement worker or effect.
 * This does not prove arbitrary CPU-bound effect cancellation, native execution or iOS.
 * Compile separately with JDK21 javac --release 17 -J-Xmx384m into build/test-resolving;
 * run with -Xmx384m and build/test-resolving before build/runtime-classpath.txt.
 */
public final class RealResolvingCancellationTests {
    private static int assertions;
    public static void main(String[] args) throws Exception {
        Map<String,Object> config=Json.parseObject(Files.readString(Path.of(args.length==0?"build/match.json":args[0])));
        // Legal blue Commander deck, with one genuine registered upstream spell.
        Map<String,Object> first=Json.object(Json.array(config.get("seats")).get(0));
        first.put("deck",Json.map("name","Resolving cancellation fixture",
            "main",List.of(entry(98,"Island","CHK","291"),entry(1,"Fact or Fiction","INV","57")),
            "commanders",List.of(entry(1,"Talrand, Sky Summoner","M13","72"))));
        System.out.println("Scope: real pinned XMage JVM; seeded hand/mana, genuine Fact or Fiction resolution; no injected stall; not native/iOS");
        System.out.println("Upstream: "+XmageEngine.UPSTREAM+"; Java: "+System.getProperty("java.version")+"; max heap MiB: "+Runtime.getRuntime().maxMemory()/1024/1024);
        System.out.println("XmageEngine: "+XmageEngine.class.getProtectionDomain().getCodeSource().getLocation());
        System.out.println("FactOrFiction: "+FactOrFiction.class.getProtectionDomain().getCodeSource().getLocation());
        for(boolean close:List.of(false,true))scenario(config,close);
        System.out.println("RealResolvingCancellationTests: 2 lifecycle cases passed, 0 failed; "+assertions+" assertions");
    }
    private static Map<String,Object> entry(int n,String name,String set,String number) {
        return Json.map("count",n,"name",name,"setCode",set,"collectorNumber",number);
    }
    private static void scenario(Map<String,Object> config,boolean close) throws Exception {
        try(Rig r=new Rig(config)) {
            String id=r.start();Object running=r.running(id);
            Game game=(Game)field(running,"game");
            ExecutorService worker=(ExecutorService)field(running,"worker");
            @SuppressWarnings("unchecked") Map<String,MobileHumanPlayer> seats=(Map<String,MobileHumanPlayer>)field(running,"seats");
            String casterSeat=r.seats.get(0);UUID casterId=seats.get(casterSeat).getId();
            UUID spellId=null;Thread thread=null;boolean cast=false;
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(35);
            Map<String,Object> decision=null;
            for(int responses=0;responses<60 && System.nanoTime()<deadline;responses++) {
                decision=r.prompt(id);Map<String,Object> p=Json.object(decision.get("prompt"));
                Map<String,Object> payload=Json.object(p.get("payload"));String kind=Json.requiredString(p,"kind");
                System.out.println("Prompt: "+kind+" / "+payload.get("message"));
                if("CHOOSE_PILE".equals(kind))break;
                Object value=false;String answer="boolean";
                if("PICK_TARGET".equals(kind)) {
                    if(cast && String.valueOf(payload.get("message")).contains("first pile")) {
                        check(!casterSeat.equals(decision.get("seat")),"opponent separates the revealed cards");
                        check(Json.array(payload.get("candidates")).size()==5,"five real revealed cards available to separate");
                        // Empty first pile is a legal upstream choice; second pile contains all five.
                        check(Json.array(p.get("responseTypes")).contains("boolean"),"upstream permits finishing empty first pile");
                    } else {
                        check(!cast && String.valueOf(payload.get("message")).contains("starting player"),"only expected setup target");
                        answer="uuid";value=casterId.toString();
                    }
                } else if("ASK".equals(kind)) {
                    check(String.valueOf(payload.get("message")).toLowerCase(Locale.ROOT).contains("mulligan"),"only expected setup ASK");
                } else if("SELECT".equals(kind)) {
                    if(!cast && casterSeat.equals(decision.get("seat"))) {
                        thread=r.parkedThread(id);
                        check(has(thread.getStackTrace(),"mage.player.human.HumanPlayer","priority"),"seed only at ordinary upstream priority wait");
                        Player caster=game.getPlayer(casterId);
                        Card spell=null;
                        for(Card card:game.getCards())if(card instanceof FactOrFiction && casterId.equals(card.getOwnerId()))spell=card;
                        check(spell!=null,"deck contains real upstream FactOrFiction");spellId=spell.getId();
                        if(!caster.getHand().contains(spellId)) {
                            check(game.getState().getZone(spellId)==Zone.LIBRARY,"seeded spell comes from real library");
                            caster.getLibrary().remove(spellId,game);
                            spell.setZone(Zone.HAND,game);caster.getHand().add(spell);
                        }
                        // Fixture-only mana grant, not a claim that Fact or Fiction produces mana.
                        // Upstream requires a non-null source token for the seeded pool item.
                        caster.getManaPool().addMana(Mana.BlueMana(4),game,spell.getSpellAbility());
                        answer="uuid";value=spellId.toString();cast=true;
                    }
                } else if("PLAY_MANA".equals(kind)) {
                    answer="mana";value=Json.map("manaType","BLUE","playerId",casterId.toString());
                } else if("CHOOSE_ABILITY".equals(kind) || "PICK_ABILITY".equals(kind)) {
                    answer="uuid";value=Json.object(Json.array(payload.get("abilities")).get(0)).get("id");
                } else throw new AssertionError("Unexpected fixture prompt: "+p);
                r.respond(id,decision,answer,value);decision=null;
            }
            check(decision!=null && cast,"reached genuine pile choice within bounded response budget");
            Map<String,Object> p=Json.object(decision.get("prompt")),payload=Json.object(p.get("payload"));
            check("CHOOSE_PILE".equals(p.get("kind")),"actual encoded upstream pile prompt");
            check(casterSeat.equals(decision.get("seat")),"spell controller chooses pile");
            check(Json.array(payload.get("pile1")).isEmpty() && Json.array(payload.get("pile2")).size()==5,"legal 0/5 piles contain five real cards");
            thread=r.parkedThread(id);StackTraceElement[] stack=thread.getStackTrace();
            for(StackTraceElement frame:stack)System.out.println("  "+frame);
            check(has(stack,"mage.abilities.effects.common.RevealAndSeparatePilesEffect","doPiles"),"actual upstream pile effect on waiting worker stack");
            check(has(stack,"mage.abilities.effects.common.RevealAndSeparatePilesEffect","apply"),"actual effect apply frame");
            check(has(stack,"mage.game.stack.Spell","resolve") && has(stack,"mage.game.GameImpl","resolve"),"ordinary spell-stack resolution path");
            check(has(stack,"mage.player.human.HumanPlayer","choosePile"),"genuine player choice wait");
            check(Arrays.stream(stack).anyMatch(f->f.getClassName().equals(XmageEngine.class.getName()+"$Running") && f.getMethodName().startsWith("lambda$start$")),"production Running.start task");
            check(game.getStack().peek()!=null && spellId.equals(game.getStack().peek().getSourceId())
                && game.getCard(spellId) instanceof FactOrFiction,"top resolving spell is the exact upstream Fact or Fiction cast by this fixture");
            check(!worker.isTerminated() && !((Future<?>)field(running,"task")).isDone(),"actual worker/task live before cancellation");
            r.expect("match_limit",()->r.engine.create(config));
            check(r.running(id)==running && thread.isAlive() && !worker.isTerminated(),"rejected create retains previous live resolving worker");
            long before=System.nanoTime();
            r.call(()->{if(close)r.engine.close();else r.engine.destroy(id);return null;});
            long millis=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-before);
            check(millis<6000,"API cancellation bounded: "+millis+"ms");
            check(worker.isTerminated(),"API succeeds only after real executor termination");
            thread.join(2000);check(!thread.isAlive(),"actual GAME thread exited");
            r.expect("unknown_match",()->r.engine.poll(id,casterSeat,0));
            if(close) {
                r.expect("engine_closed",()->r.engine.create(config));
                try(Rig fresh=new Rig(config)){String next=fresh.start();fresh.prompt(next);fresh.parkedThread(next);check(!next.equals(id),"fresh engine reaches new real game prompt after close");}
            } else {
                String next=r.start();r.prompt(next);r.parkedThread(next);check(!next.equals(id),"same engine reaches new real game prompt after destroy");
            }
            System.out.println("PASS "+(close?"close":"destroy")+": genuine Fact or Fiction pile prompt cancelled, worker terminated in "+millis+"ms, new real game prompt afterward");
        }
    }
    private static boolean has(StackTraceElement[] stack,String type,String method) {
        return Arrays.stream(stack).anyMatch(f->f.getClassName().equals(type) && f.getMethodName().equals(method));
    }
    private static final class Rig implements AutoCloseable {
        final XmageEngine engine=new XmageEngine("real-resolving-cancellation-test");
        final Map<String,Object> config;final List<String> seats=new ArrayList<>();
        final List<ExecutorService> workers=new ArrayList<>();
        final ExecutorService calls=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"CALL resolving-test");t.setDaemon(true);return t;});
        Rig(Map<String,Object> config){this.config=config;for(Object s:Json.array(config.get("seats")))seats.add(Json.requiredString(Json.object(s),"seatId"));}
        <T>T call(Callable<T> action)throws Exception{return await(calls.submit(action),6);}
        String start()throws Exception {
            String id=Json.requiredString(await(calls.submit(()->engine.create(config)),30),"matchId");
            workers.add((ExecutorService)field(running(id),"worker"));return id;
        }
        Object running(String id)throws Exception{return call(()->{synchronized(engine){return ((Map<?,?>)field(engine,"matches")).get(id);}});}
        Map<String,Object> prompt(String id)throws Exception {
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            while(System.nanoTime()<end) {
                for(String seat:seats) {
                    Map<String,Object> view=call(()->engine.poll(id,seat,0));
                    check(!Set.of("failed","ended","closed").contains(view.get("phase")),"match remains live: "+view.get("failure"));
                    if(view.get("prompt")!=null && !Boolean.TRUE.equals(Json.object(view.get("prompt")).get("submitted")))
                        return Json.map("seat",seat,"prompt",view.get("prompt"));
                }
                Thread.sleep(10);
            }
            throw new AssertionError("No genuine prompt within 10 seconds");
        }
        Thread parkedThread(String id)throws Exception {
            long end=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);
            while(System.nanoTime()<end) {
                for(Thread t:Thread.getAllStackTraces().keySet())if(t.getName().equals("GAME mobile-"+id)
                    && t.getState()==Thread.State.TIMED_WAITING && has(t.getStackTrace(),MobileHumanPlayer.class.getName(),"waitForResponse"))return t;
                Thread.sleep(5);
            }
            throw new AssertionError("Real worker not waiting in its normal player channel");
        }
        void respond(String id,Map<String,Object> d,String kind,Object value)throws Exception {
            Map<String,Object> p=Json.object(d.get("prompt"));
            call(()->engine.respond(id,Json.requiredString(d,"seat"),Json.map("requestId",UUID.randomUUID().toString(),"promptId",p.get("promptId"),"promptRevision",p.get("revision"),"answer",Json.map("kind",kind,"value",value))));
        }
        void expect(String code,Callable<?> action)throws Exception {
            try{call(action);}catch(BridgeException e){check(code.equals(e.code()),"expected "+code+", got "+e.code());return;}
            throw new AssertionError("Expected "+code);
        }
        @Override public void close()throws Exception {
            try {call(()->{engine.close();return null;});}
            finally {
                try{for(ExecutorService worker:workers)check(worker.awaitTermination(5,TimeUnit.SECONDS),"finally terminates real worker");}
                finally{calls.shutdownNow();check(calls.awaitTermination(3,TimeUnit.SECONDS),"finally terminates CALL executor");}
            }
        }
    }
    private static Object field(Object o,String name)throws Exception {Field f=o.getClass().getDeclaredField(name);f.setAccessible(true);return f.get(o);}
    private static <T>T await(Future<T> future,long seconds)throws Exception {
        try{return future.get(seconds,TimeUnit.SECONDS);}
        catch(ExecutionException e){if(e.getCause() instanceof Exception)throw (Exception)e.getCause();if(e.getCause() instanceof Error)throw (Error)e.getCause();throw new AssertionError(e.getCause());}
        finally{if(!future.isDone())future.cancel(true);}
    }
    private static void check(boolean value,String message){assertions++;if(!value)throw new AssertionError(message);}
}
