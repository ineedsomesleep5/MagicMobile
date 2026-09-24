package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.EngineService;
import io.magicmobile.core.Json;
import java.util.*;
import java.util.concurrent.TimeUnit;

/**
 * Real upstream concede through the production adapter. A duel ends with the opponent winning.
 * In a pod the conceding seat keeps receiving snapshots (never a prompt) while the others play on.
 * Fixture answers go only to human seats. Run in an externally bounded JVM, -Xmx768m.
 */
public final class RealConcedeTests {
    public static void main(String[] args) throws Exception {
        XmageEngine engine=new XmageEngine("jvm-concede-test");
        try {
            check(Boolean.TRUE.equals(engine.capabilities().get("concede")),"engine advertises concede");
            duel(engine,false);
            duel(engine,true);
            pod(engine);
            otherHumanConcedesWhileAsked(engine);
            service(engine);
        } finally { engine.close(); }
        System.out.println("PASS real XMage concede: duel (opening and mid-game), pod spectating, second human, service envelope");
    }

    private static void duel(XmageEngine engine,boolean midGame) throws Exception {
        String id=Json.requiredString(engine.create(config("human","ai")),"matchId");
        try {
            if(midGame) driveUntil(engine,id,List.of("human"),state->turn(state)>=2 && prompt(state)!=null);
            else driveUntil(engine,id,List.of("human"),state->prompt(state)!=null);
            expect("unauthorized_seat",()->engine.concede(id,"ai"));
            expect("unauthorized_seat",()->engine.concede(id,"nobody"));
            expect("unknown_match",()->engine.concede("missing","human"));
            engine.concede(id,"human");
            check(engine.poll(id,"human",0).get("prompt")==null,"conceding retracts the open question at once");
            Map<String,Object> end=awaitPoll(engine,id,"human",state->"ended".equals(state.get("phase")),20);
            Map<String,Object> snapshot=Json.object(end.get("snapshot"));
            Map<String,Object> outcome=Json.object(snapshot.get("outcome"));
            check(Boolean.TRUE.equals(outcome.get("ended")),"final snapshot reports the ended game");
            List<Object> winners=Json.array(outcome.get("winnerPlayerIds"));
            check(winners.size()==1 && winners.get(0).equals(playerId(snapshot,"ai")),"the opponent wins: "+winners);
            check(hasLeft(snapshot,"human"),"the conceding player has left");
            expect("match_unavailable",()->engine.concede(id,"human"));
            System.out.println("PASS duel concede "+(midGame?"mid-game":"at the opening")+" ends with the opponent winning");
        } finally { destroy(engine,id); }
    }

    private static void pod(XmageEngine engine) throws Exception {
        String id=Json.requiredString(engine.create(config("human","ai","ai2")),"matchId");
        try {
            driveUntil(engine,id,List.of("human"),state->turn(state)>=1 && prompt(state)!=null);
            engine.concede(id,"human");
            engine.concede(id,"human"); // idempotent while it is being processed
            Map<String,Object> left=awaitPoll(engine,id,"human",state->state.get("snapshot")!=null
                && hasLeft(Json.object(state.get("snapshot")),"human"),10);
            long revision=Json.integer(left.get("revision"));int turn=turn(left);
            check(!cancellation(engine,id).humansPlaying(),"only AIs remain, so they think at watching pace");
            Map<String,Object> player=player(Json.object(left.get("snapshot")),"human");
            check(Json.object(player.get("battlefield")).isEmpty(),"a player who left takes their permanents with them");
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(40);
            Map<String,Object> state=left;
            while(System.nanoTime()<deadline && (Json.integer(state.get("revision"))<revision+20 || turn(state)<=turn)) {
                state=engine.poll(id,"human",0);
                check("running".equals(state.get("phase")),"the other players keep playing: "+state.get("phase")+" "+state.get("failure"));
                check(state.get("prompt")==null,"a spectator is never asked a question");
                Thread.sleep(20);
            }
            check(turn(state)>turn,"the remaining players took another turn while the seat watched");
            check(Json.object(Json.object(state.get("snapshot")).get("gameView")).get("opponentHands") instanceof Map<?,?> hands
                && hands.isEmpty(),"spectating never reveals hands");
            System.out.println("PASS pod concede: the seat watches turn "+turn(state)+" at revision "+state.get("revision"));
        } finally { destroy(engine,id); }
    }

    private static void otherHumanConcedesWhileAsked(XmageEngine engine) throws Exception {
        String id=Json.requiredString(engine.create(config("human","human2","ai")),"matchId");
        try {
            check(cancellation(engine,id).humansPlaying(),"a live human keeps the configured AI budget");
            // Answer everything except human's own question, so the GAME thread waits on human.
            Map<String,Object> asked=driveUntil(engine,id,List.of("human","human2"),state->"human".equals(state.get("viewerId"))
                && prompt(state)!=null && turn(state)>=1);
            Map<String,Object> question=prompt(asked);
            engine.concede(id,"human2");
            Map<String,Object> updated=awaitPoll(engine,id,"human",state->state.get("snapshot")!=null
                && hasLeft(Json.object(state.get("snapshot")),"human2"),10);
            Map<String,Object> same=prompt(updated);
            check(same!=null && same.get("promptId").equals(question.get("promptId")),"the waiting player keeps the same question");
            check(engine.poll(id,"human2",0).get("prompt")==null,"the conceding seat has no question");
            engine.respond(id,"human",Json.map("requestId",UUID.randomUUID().toString(),"promptId",same.get("promptId"),
                "promptRevision",same.get("revision"),"answer",answer(same,updated)));
            Map<String,Object> next=awaitPoll(engine,id,"human",state->{
                Map<String,Object> p=prompt(state);
                return p!=null && !p.get("promptId").equals(same.get("promptId"));
            },20);
            check("running".equals(next.get("phase")),"the game continues for the remaining human and AI");
            System.out.println("PASS second human concedes while the first is asked; the first keeps playing");
        } finally { destroy(engine,id); }
    }

    private static void service(XmageEngine engine) {
        EngineService service=new EngineService(engine);
        check(service.request("{\"protocol\":1,\"op\":\"concede\",\"matchId\":\"none\",\"viewerId\":\"human\"}").contains("unknown_match"),
            "service routes concede to the engine");
        check(service.request("{\"protocol\":1,\"op\":\"concede\",\"matchId\":\"none\",\"viewerId\":\"human\",\"actor\":\"ai\"}")
            .contains("invalid_request"),"concede takes no actor field");
    }

    private interface Goal { boolean reached(Map<String,Object> state); }

    /** Answers human prompts with the simplest legal reply until a seat's poll reaches the goal. */
    private static Map<String,Object> driveUntil(XmageEngine engine,String id,List<String> humans,Goal goal) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(60);
        while(System.nanoTime()<deadline) {
            for(String seat:humans) {
                Map<String,Object> state=engine.poll(id,seat,0);
                check(!Set.of("ended","closed","failed").contains(state.get("phase")),"live game: "+state.get("failure"));
                if(goal.reached(state)) return state;
                Map<String,Object> prompt=prompt(state);
                if(prompt==null) continue;
                engine.respond(id,seat,Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),
                    "promptRevision",prompt.get("revision"),"answer",answer(prompt,state)));
            }
            Thread.sleep(2);
        }
        throw new AssertionError("Goal not reached within 60 seconds");
    }

    private static Map<String,Object> answer(Map<String,Object> prompt,Map<String,Object> state) {
        Map<String,Object> payload=Json.object(prompt.get("payload"));
        String kind=Json.requiredString(prompt,"kind");
        if(kind.equals("PICK_TARGET")) {
            Object value=Json.array(payload.get("candidates")).get(0);
            // Choose an AI to start, so the human seat is asked at a later priority.
            if(String.valueOf(payload.get("message")).contains("starting player"))
                for(Object player:Json.array(Json.object(Json.object(state.get("snapshot")).get("gameView")).get("players")))
                    if(String.valueOf(Json.object(player).get("name")).startsWith("ai")) value=Json.object(player).get("playerId");
            return Json.map("kind","uuid","value",value);
        }
        if(kind.equals("CHOOSE_CHOICE")) return Json.map("kind","string","value",Json.array(payload.get("choiceOrder")).get(0));
        check(kind.equals("SELECT")||kind.equals("ASK"),"unexpected fixture prompt: "+kind);
        return Json.map("kind","boolean","value",false);
    }

    private static Map<String,Object> awaitPoll(XmageEngine engine,String id,String seat,Goal goal,int seconds) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(seconds);
        Map<String,Object> state=engine.poll(id,seat,0);
        while(!goal.reached(state)) {
            check(System.nanoTime()<deadline,"condition not reached within "+seconds+"s: phase="+state.get("phase")+" failure="+state.get("failure"));
            check(!"failed".equals(state.get("phase")),"engine failed: "+state.get("failure"));
            Thread.sleep(10);
            state=engine.poll(id,seat,0);
        }
        return state;
    }

    private static Map<String,Object> prompt(Map<String,Object> state) {
        Object prompt=state.get("prompt");
        if(prompt==null) return null;
        Map<String,Object> p=Json.object(prompt);
        return Boolean.TRUE.equals(p.get("submitted")) ? null : p;
    }
    private static int turn(Map<String,Object> state) {
        if(state.get("snapshot")==null) return 0;
        Object turn=Json.object(Json.object(state.get("snapshot")).get("gameView")).get("turn");
        return turn==null ? 0 : (int)Json.integer(turn);
    }
    private static Map<String,Object> player(Map<String,Object> snapshot,String name) {
        for(Object player:Json.array(Json.object(snapshot.get("gameView")).get("players")))
            if(name.equals(Json.object(player).get("name"))) return Json.object(player);
        throw new AssertionError("No player "+name);
    }
    private static String playerId(Map<String,Object> snapshot,String name) { return Json.requiredString(player(snapshot,name),"playerId"); }
    private static boolean hasLeft(Map<String,Object> snapshot,String name) { return Boolean.TRUE.equals(player(snapshot,name).get("hasLeft")); }

    private static MobileAICancellation cancellation(XmageEngine engine,String id) throws Exception {
        java.lang.reflect.Field matches=XmageEngine.class.getDeclaredField("matches");matches.setAccessible(true);
        Object running=((Map<?,?>)matches.get(engine)).get(id);
        java.lang.reflect.Field field=running.getClass().getDeclaredField("cancellation");field.setAccessible(true);
        return (MobileAICancellation)field.get(running);
    }
    private static void destroy(XmageEngine engine,String id) throws InterruptedException {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
        while(true) {
            try { engine.destroy(id); return; }
            catch(BridgeException e) {
                if(!"engine_busy_shutdown".equals(e.code()) || System.nanoTime()>deadline) throw e;
                Thread.sleep(50);
            }
        }
    }
    private static void expect(String code,Runnable action) {
        try { action.run(); throw new AssertionError("Expected "+code); }
        catch(BridgeException e) { check(code.equals(e.code()),"Expected "+code+", got "+e.code()); }
    }
    private static Map<String,Object> config(String... seats) {
        List<Object> out=new ArrayList<>();
        for(String seat:seats) {
            boolean human=seat.startsWith("human");
            Map<String,Object> s=Json.map("seatId",seat,"name",seat,"controller",human?"human":"ai","deck",Json.map("name","Concede fixture",
                "main",List.of(Json.map("count",99,"name","Plains","setCode","CHK","collectorNumber","287")),
                "commanders",List.of(Json.map("count",1,"name","Isamaru, Hound of Konda","setCode","CHK","collectorNumber","19"))));
            if(!human) s.put("aiSkill",1);
            out.add(s);
        }
        return Json.map("seats",out);
    }
    private static void check(boolean value,String message) { if(!value) throw new AssertionError(message); }
}
