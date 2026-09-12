package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import mage.game.Game;
import mage.game.events.TableEvent;
import mage.player.ai.ComputerPlayer6;
import java.lang.reflect.Field;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Real production interface; fixture answers are only ever sent to human seats.
 * Default: one human plus AI. Optional "two-humans": two humans plus AI.
 * Compile fresh adapter sources with AI and AI.MAD target/classes ahead of the baseline
 * runtime classpath; run this main in an externally bounded 120-second JVM, -Xmx768m.
 */
public final class RealAILifecycleTests {
    public static void main(String[] args) throws Exception {
        boolean twoHumans=args.length>0;
        Map<String,Object> configuration=config(twoHumans);
        try(XmageEngine engine=new XmageEngine("jvm-ai-lifecycle-test")) {
            Map<String,Object> created=engine.create(configuration);
            String id=Json.requiredString(created,"matchId");
            check(!Boolean.TRUE.equals(engine.capabilities().get("aiEnabled")),"native AI capability remains unvalidated");
            engine.poll(id,"human",0);
            try {engine.poll(id,"ai",0);throw new AssertionError("AI must not be a response recipient");}
            catch(BridgeException e){check("unauthorized_seat".equals(e.code()),"AI recipient rejected");}
            engine.destroy(id);
            System.out.println("PASS real MAD seat accepted; human-only recipient; destroy");
            expect("invalid_seats",()->engine.create(Json.map("seats",List.of(seat("a","ai"),seat("b","ai")))));
            expect("invalid_seat",()->engine.create(Json.map("seats",List.of(seat("same","ai"),seat("same","human")))));
            expect("invalid_controller",()->engine.create(Json.map("seats",List.of(seat("human","human"),seat("ai","hard")))));
            expect("invalid_seats",()->engine.create(Json.map("seats",List.of(seat("human","human")))));
            List<Object> maximum=new ArrayList<>(Json.array(configuration.get("seats")));
            for(int n=maximum.size();n<4;n++)maximum.add(seat("extra"+n,"ai"));
            String four=Json.requiredString(engine.create(Json.map("seats",maximum)),"matchId");
            engine.destroy(four);
            maximum.add(seat("fifth","ai"));
            expect("invalid_seats",()->engine.create(Json.map("seats",maximum)));
            System.out.println("PASS seat bounds and duplicate/controller validation; human recipients="+(twoHumans?2:1));
            String playing=Json.requiredString(engine.create(configuration),"matchId");
            drive(engine,playing,twoHumans,false);
            engine.destroy(playing);
            for(boolean close:List.of(false,true)) {
                String active=Json.requiredString(engine.create(configuration),"matchId");
                Game game=game(engine,active); // read-only observation of upstream errors and worker identity
                AtomicInteger errors=new AtomicInteger();
                game.addTableEventListener(e->{if(e.getEventType()==TableEvent.EventType.ERROR
                    && !(e.getException() instanceof CancellationException))errors.incrementAndGet();});
                Thread worker=drive(engine,active,twoHumans,true);
                long start=System.nanoTime();
                if(close)engine.close();else engine.destroy(active);
                worker.join(1000);
                check(!worker.isAlive(),"shutdown joins actual GAME worker");
                check(errors.get()==0,"cancel must not enter upstream error-recovery loop: errors="+errors.get());
                expect("unknown_match",()->engine.poll(active,"human",0));
                if(close)expect("engine_closed",()->engine.create(configuration));
                awaitIdlePool();
                System.out.println("PASS active MAD "+(close?"close":"destroy")+" in "+TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-start)+"ms; game worker exited, simulations idle");
            }
        }
        try(XmageEngine fresh=new XmageEngine("jvm-ai-recreate-test")) {
            String id=Json.requiredString(fresh.create(configuration),"matchId");
            drive(fresh,id,twoHumans,true);
            fresh.destroy(id);
            awaitIdlePool();
            System.out.println("PASS fresh engine reaches real MAD simulation after prior close");
        }
    }
    private static Thread drive(XmageEngine engine,String id,boolean twoHumans,boolean stopAtSimulation)throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(40);
        List<String> humans=twoHumans?List.of("human","human2"):List.of("human");
        boolean land=false,cast=false,attack=false;
        while(System.nanoTime()<deadline) {
            Map<Thread,StackTraceElement[]> threads=Thread.getAllStackTraces();
            boolean simulationActive=threads.entrySet().stream().anyMatch(entry->entry.getKey().getName().startsWith("AI-SIM-MAD")
                && Arrays.stream(entry.getValue()).anyMatch(f->f.getClassName().equals(ComputerPlayer6.class.getName())&&f.getMethodName().equals("addActions")));
            if(stopAtSimulation && simulationActive)for(Map.Entry<Thread,StackTraceElement[]> entry:threads.entrySet())
                if(entry.getKey().getName().equals("GAME mobile-"+id)
                    && Arrays.stream(entry.getValue()).anyMatch(f->f.getClassName().equals("mage.player.ai.ComputerPlayer6")
                        && f.getMethodName().equals("addActionsTimed"))) {
                    System.out.println("OBSERVED real upstream simulation and waiting GAME worker "+id);
                    return entry.getKey();
                }
            for(String seat:humans) {
                Map<String,Object> state=engine.poll(id,seat,0);
                check(!Set.of("ended","closed","failed").contains(state.get("phase")),"live game: "+state.get("failure"));
                if(state.get("snapshot")!=null) {
                    Map<String,Object> snapshot=Json.object(state.get("snapshot"));
                    Map<String,Object> view=Json.object(snapshot.get("gameView"));
                    check(Json.array(view.get("players")).size()==humans.size()+1,"snapshot includes all players");
                    check(Json.object(view.get("opponentHands")).isEmpty(),"ordinary human snapshot hides opponent hands");
                    Set<String> aiPermanents=new HashSet<>();
                    for(Object player:Json.array(view.get("players")))if("ai".equals(Json.object(player).get("name"))) {
                        Map<String,Object> battlefield=Json.object(Json.object(player).get("battlefield"));
                        aiPermanents.addAll(battlefield.keySet());
                        for(Object permanent:battlefield.values())if("Plains".equals(Json.object(permanent).get("name")))land=true;
                    }
                    for(Object spell:Json.object(view.get("stack")).values())
                        if("Isamaru, Hound of Konda".equals(Json.object(spell).get("name")))cast=true;
                    for(Object group:Json.array(view.get("combat")))
                        if(Json.object(Json.object(group).get("attackers")).keySet().stream().anyMatch(aiPermanents::contains))attack=true;
                    if(!stopAtSimulation && land&&cast&&attack) {
                        System.out.println("PASS human snapshot observes upstream AI land, commander cast, attack; turn="+view.get("turn"));
                        return null;
                    }
                }
                if(state.get("prompt")==null)continue;
                Map<String,Object> prompt=Json.object(state.get("prompt"));
                if(Boolean.TRUE.equals(prompt.get("submitted")))continue;
                Map<String,Object> payload=Json.object(prompt.get("payload"));
                String kind=Json.requiredString(prompt,"kind"),answer="boolean";Object value=false;
                if(kind.equals("PICK_TARGET")) {
                    answer="uuid";value=Json.array(payload.get("candidates")).get(0);
                    if(String.valueOf(payload.get("message")).contains("starting player")) {
                        Map<String,Object> view=Json.object(Json.object(state.get("snapshot")).get("gameView"));
                        for(Object player:Json.array(view.get("players")))
                            if("ai".equals(Json.object(player).get("name")))value=Json.object(player).get("playerId");
                    }
                } else if(kind.equals("CHOOSE_CHOICE")) {
                    answer="string";value=Json.array(payload.get("choiceOrder")).get(0);
                } else check(kind.equals("SELECT")||kind.equals("ASK"),"unexpected fixture prompt: "+kind);
                engine.respond(id,seat,Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),
                    "promptRevision",prompt.get("revision"),"answer",Json.map("kind",answer,"value",value)));
            }
            Thread.sleep(1);
        }
        throw new AssertionError("Did not observe goal within 40 seconds: simulation="+stopAtSimulation+" land="+land+" cast="+cast+" attack="+attack);
    }
    private static void awaitIdlePool()throws Exception {
        Field field=ComputerPlayer6.class.getDeclaredField("threadPoolSimulations");field.setAccessible(true);
        ThreadPoolExecutor pool=(ThreadPoolExecutor)field.get(null); // read-only; no mutation of upstream pool
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
        while((pool.getActiveCount()!=0||!pool.getQueue().isEmpty()) && System.nanoTime()<deadline)Thread.sleep(5);
        check(pool.getActiveCount()==0&&pool.getQueue().isEmpty(),"simulation pool has no remaining work");
    }
    private static void expect(String code,Runnable action) {
        try{action.run();throw new AssertionError("Expected "+code);}
        catch(BridgeException e){check(code.equals(e.code()),"Expected "+code+", got "+e.code());}
    }
    private static Game game(XmageEngine engine,String id)throws Exception {
        Field matches=XmageEngine.class.getDeclaredField("matches");matches.setAccessible(true);
        Object running=((Map<?,?>)matches.get(engine)).get(id);
        Field game=running.getClass().getDeclaredField("game");game.setAccessible(true);
        return (Game)game.get(running);
    }
    private static Map<String,Object> config(boolean twoHumans) {
        List<Object> seats=new ArrayList<>();
        seats.add(seat("human","human"));
        if(twoHumans)seats.add(seat("human2","human"));
        seats.add(seat("ai","ai"));
        return Json.map("seats",seats);
    }
    private static Map<String,Object> seat(String id,String controller) {
        return Json.map("seatId",id,"name",id,"controller",controller,"deck",Json.map("name","Legal AI lifecycle fixture",
            "main",List.of(Json.map("count",99,"name","Plains","setCode","CHK","collectorNumber","287")),
            "commanders",List.of(Json.map("count",1,"name","Isamaru, Hound of Konda","setCode","CHK","collectorNumber","19"))));
    }
    private static void check(boolean value,String message){if(!value)throw new AssertionError(message);}
}
