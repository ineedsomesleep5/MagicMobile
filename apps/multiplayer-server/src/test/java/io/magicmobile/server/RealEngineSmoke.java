package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.net.http.*;
import java.nio.file.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;

/** Real XMage + loopback HTTP only. Auth/lobby backend is synthetic; not phone or hosted evidence. */
public final class RealEngineSmoke {
    static final HttpClient HTTP=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).build();
    static int checks;
    static final class Lobby implements MultiplayerServer.Backend {
        final String id=UUID.randomUUID().toString();final List<Map<String,Object>> players=new ArrayList<>();String status="waiting";long count;
        public String authenticate(String token){if(!token.matches("seat-[0-3]"))throw MultiplayerServer.fail("unauthorized","Test identity");return token;}
        public Map<String,Object> rpc(String token,String operation,Map<String,Object> p){switch(operation){
            case "create_lobby":count=Json.integer(p.get("p_player_count"));
            case "join_lobby":players.add(Json.map("user_id",token,"display_name",p.get("p_display_name"),"seat",(long)players.size(),"ready",false));break;
            case "set_ready":players.stream().filter(v->token.equals(v.get("user_id"))).forEach(v->v.put("ready",true));break;
            case "start":status="active";break;
            case "leave_match":status="abandoned";break;
        }return Map.of("match_id",id);}
        public Map<String,Object> match(String token,String id){return Json.map("status",status,"host_user_id","seat-0","player_count",count,"join_code","ABC123");}
        public List<Map<String,Object>> players(String token,String id){return new ArrayList<>(players);}
    }
    public static void main(String[] args)throws Exception{
        if(args.length!=0&&args.length!=5)throw new IllegalArgumentException("Pass no decks for basic smoke or five resolved included-deck JSON paths");
        List<Map<String,Object>> included=new ArrayList<>();
        for(String file:args)included.add(Json.parseObject(Files.readString(Path.of(file))));
        Supplier<EnginePort> engines=()->{try{return (EnginePort)Class.forName("io.magicmobile.xmage.XmageEngine").getConstructor(String.class).newInstance("server-smoke");}catch(Exception e){throw new IllegalStateException(e);}};
        Map<String,Object> identity;try(EnginePort e=engines.get()){var c=e.capabilities();identity=Json.map("protocolVersion",1L,"upstreamCommit",c.get("upstream"),"catalogueHash",c.get("catalogueHash"),"adapterVersion","server-smoke");}
        Map<String,Object> deck=Json.map("name","Server smoke","main",List.of(Json.map("count",99L,"name","Plains","setCode","CHK","collectorNumber","287")),"commanders",List.of(Json.map("count",1L,"name","Isamaru, Hound of Konda","setCode","CHK","collectorNumber","19")));
        for(int n:List.of(2,4)){
            List<Map<String,Object>> playing=new ArrayList<>();
            for(int i=0;i<n;i++)playing.add(included.isEmpty()?deck:included.get(n==2?i+3:i));
            System.out.println("START real XMage "+n+" human seats; decks="+playing.stream().map(d->d.get("name")).toList()+"; maxHeapMiB="+Runtime.getRuntime().maxMemory()/1024/1024);
            Lobby lobby=new Lobby();try(var server=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),lobby,engines,identity,"https://example.supabase.co","fixture",1)){
                server.start();int port=server.port();
                for(int i=0;i<n;i++){
                    Map<String,Object> p=Json.map("name","Player "+i,"platform",i%2==0?"ios":"android","identity",identity,"deck",playing.get(i));
                    if(i==0)p.put("playerCount",(long)n);else p.put("code","ABC123");
                    request(port,"seat-"+i,i==0?"/v1/lobbies":"/v1/lobbies/join",p);
                    request(port,"seat-"+i,"/v1/lobbies/"+lobby.id+"/ready",Map.of("ready",true));
                }
                Map<String,Object> started=request(port,"seat-0","/v1/lobbies/"+lobby.id+"/start",Map.of());String game=Json.requiredString(started,"matchId");
                openingDecisions(port,game,n);
                request(port,"seat-0","/v1/lobbies/"+lobby.id+"/leave",Map.of());
                System.out.println("PASS real XMage "+n+"-human-seat HTTP opening keep decisions, private hand/prompt isolation, viewer tampering, idempotent retry and stale/reused request rejection, close; synthetic Auth/lobby, no device acceptance");
            }
        }
        System.out.println("PASS "+checks+" real-engine HTTP assertions; opening flow only, not a completed game or phone acceptance");
    }
    static void openingDecisions(int port,String game,int seats)throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(40);
        Set<String> kept=new HashSet<>();Map<String,Map<String,Object>> answers=new HashMap<>();
        Set<String> settled=new HashSet<>();boolean retryChecked=false,tamperChecked=false;
        while(System.nanoTime()<deadline) {
            Map<String,Map<String,Object>> polls=new LinkedHashMap<>();
            for(int i=0;i<seats;i++) {
                String seat="seat-"+i;Map<String,Object> poll=engineResult(request(port,seat,enginePath(game),engineRequest(game,seat,"poll","after",0L)));
                check(game.equals(poll.get("matchId"))&&seat.equals(poll.get("viewerId")),"poll retains authenticated match and viewer");
                check(!Set.of("ended","closed","failed").contains(poll.get("phase")),"opening remains live: "+poll.get("failure"));
                polls.put(seat,poll);
            }
            privateViews(polls,seats);
            for(var entry:polls.entrySet()) {
                String seat=entry.getKey();Map<String,Object> poll=entry.getValue();
                Map<String,Object> prior=answers.get(seat);
                Map<String,Object> prompt=poll.get("prompt")==null?null:Json.object(poll.get("prompt"));
                if(prior!=null&&(prompt==null||!prior.get("promptId").equals(prompt.get("promptId")))&&!settled.contains(seat)) {
                    Map<String,Object> stale=new LinkedHashMap<>(prior);stale.put("requestId",UUID.randomUUID().toString());
                    engineError(request(port,seat,enginePath(game),engineRequest(game,seat,"respond","command",stale)),"stale_prompt");
                    settled.add(seat);
                }
                if(prompt==null||Boolean.TRUE.equals(prompt.get("submitted")))continue;
                Map<String,Object> payload=Json.object(prompt.get("payload"));String kind=Json.requiredString(prompt,"kind");
                boolean keep="ASK".equals(kind)&&"Keep".equals(Json.object(payload.get("options")).get("UI.right.btn.text"))
                    &&"Mulligan".equals(Json.object(payload.get("options")).get("UI.left.btn.text"));
                if(keep) {
                    check(!kept.contains(seat),"kept opening hand is not asked to mulligan again");
                    Map<String,Object> view=Json.object(Json.object(poll.get("snapshot")).get("gameView"));
                    check(Json.object(view.get("myHand")).size()==7,"each human sees seven real opening cards before keeping");
                    Map<String,Object> command=command(prompt,"boolean",false);
                    if(!tamperChecked) {
                        String other=seat.equals("seat-0")?"seat-1":"seat-0";
                        httpError(port,seat,enginePath(game),engineRequest(game,other,"poll","after",0L),403,"forbidden");
                        httpError(port,seat,enginePath(game),engineRequest(game,other,"respond","command",command),403,"forbidden");
                        engineError(request(port,other,enginePath(game),engineRequest(game,other,"respond","command",command)),"stale_prompt");
                        tamperChecked=true;
                    }
                    Map<String,Object> receipt=engineResult(request(port,seat,enginePath(game),engineRequest(game,seat,"respond","command",command)));
                    check("queued".equals(receipt.get("status")),"legal keep answer queued by real XMage adapter");
                    if(!retryChecked) {
                        Map<String,Object> repeated=engineResult(request(port,seat,enginePath(game),engineRequest(game,seat,"respond","command",command)));
                        check(receipt.equals(repeated),"exact retry returns same receipt rather than another action");
                        Map<String,Object> altered=new LinkedHashMap<>(command);altered.put("answer",Json.map("kind","boolean","value",true));
                        engineError(request(port,seat,enginePath(game),engineRequest(game,seat,"respond","command",altered)),"request_id_reused");
                        retryChecked=true;
                    }
                    kept.add(seat);answers.put(seat,command);
                } else if("PICK_TARGET".equals(kind)&&String.valueOf(payload.get("message")).contains("starting player")) {
                    check(kept.isEmpty(),"starting-player selection precedes mulligans");
                    List<Object> candidates=Json.array(payload.get("candidates"));check(candidates.size()==seats,"starting player uses actual engine candidates");
                    engineResult(request(port,seat,enginePath(game),engineRequest(game,seat,"respond","command",command(prompt,"uuid",candidates.get(0)))));
                } else {
                    check(kept.size()==seats&&"SELECT".equals(kind),"unexpected opening prompt: "+kind+" "+payload.get("message"));
                    if(settled.size()==seats) {
                        check(retryChecked&&tamperChecked,"negative authorization and retry probes ran");
                        for(Map<String,Object> state:polls.values())check(Json.object(Json.object(Json.object(state.get("snapshot")).get("gameView")).get("myHand")).size()>=7,"all kept hands remain privately available");
                        return;
                    }
                }
            }
            // Bound requests below the server's per-player quota even if initialization stalls.
            Thread.sleep(500);
        }
        throw new AssertionError("Opening decisions did not settle within40s; kept="+kept+", settled="+settled);
    }
    static void privateViews(Map<String,Map<String,Object>> polls,int seats) {
        Map<String,Set<String>> hands=new HashMap<>();Map<String,String> promptIds=new HashMap<>();
        for(var entry:polls.entrySet()) {
            Map<String,Object> state=entry.getValue();
            if(state.get("prompt")!=null)promptIds.put(entry.getKey(),Json.requiredString(Json.object(state.get("prompt")),"promptId"));
            if(state.get("snapshot")==null)continue;
            Map<String,Object> snapshot=Json.object(state.get("snapshot")),view=Json.object(snapshot.get("gameView"));
            check(snapshot.get("enginePlayerId").equals(view.get("myPlayerId")),"snapshot owns its actual engine player identity");
            check(Json.array(view.get("players")).size()==seats,"snapshot contains full public pod");
            String expectedName="Player "+entry.getKey().substring("seat-".length());
            Map<String,Object> ownPlayer=Json.array(view.get("players")).stream().map(Json::object).filter(player->expectedName.equals(player.get("name"))).findFirst().orElseThrow();
            check(ownPlayer.get("playerId").equals(view.get("myPlayerId")),"authenticated seat maps to its assigned actual player rather than another viewer");
            for(String key:List.of("opponentHands","watchedHands"))check(Json.object(view.get(key)).isEmpty(),"no foreign private hand map: "+key);
            for(String key:List.of("authorizedOpponentHands","authorizedLookedAt","controlledPlayerViews"))check(Json.object(snapshot.get(key)).isEmpty(),"no unauthorized disclosure: "+key);
            hands.put(entry.getKey(),Json.object(view.get("myHand")).keySet());
        }
        for(var viewer:polls.entrySet()) {
            String encoded=Json.write(viewer.getValue());
            for(var owner:hands.entrySet())if(!owner.getKey().equals(viewer.getKey()))
                for(String card:owner.getValue())check(!encoded.contains(card),"foreign hidden card UUID absent from entire poll including nested DTO/events");
            for(var owner:promptIds.entrySet())if(!owner.getKey().equals(viewer.getKey()))
                check(!encoded.contains(owner.getValue()),"foreign prompt token absent from entire poll including events");
        }
    }
    static Map<String,Object> command(Map<String,Object> prompt,String kind,Object value){return Json.map("requestId",UUID.randomUUID().toString(),"promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),"answer",Json.map("kind",kind,"value",value));}
    static String enginePath(String game){return "/v1/matches/"+game+"/engine";}
    static Map<String,Object> engineRequest(String game,String seat,String op,String field,Object value){return Json.map("protocol",1L,"op",op,"matchId",game,"viewerId",seat,field,value);}
    static Map<String,Object> engineResult(Map<String,Object> envelope){check(Boolean.TRUE.equals(envelope.get("ok")),"engine success: "+Json.write(envelope));return Json.object(envelope.get("result"));}
    static void engineError(Map<String,Object> envelope,String code){check(Boolean.FALSE.equals(envelope.get("ok"))&&code.equals(Json.object(envelope.get("error")).get("code")),"expected engine rejection "+code+": "+Json.write(envelope));}
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);checks++;}
    static void httpError(int port,String uid,String path,Map<String,Object> body,int status,String code)throws Exception {
        var response=send(port,uid,path,body);check(response.statusCode()==status,"HTTP rejects spoofed viewer");
        check(code.equals(Json.object(Json.parseObject(response.body()).get("error")).get("code")),"HTTP rejection retains expected authorization code");
    }
    static Map<String,Object> request(int port,String uid,String path,Map<String,Object> body)throws Exception{
        var response=send(port,uid,path,body);
        if(response.statusCode()!=200)throw new AssertionError("HTTP "+response.statusCode()+": "+response.body());return Json.parseObject(response.body());
    }
    static HttpResponse<String> send(int port,String uid,String path,Map<String,Object> body)throws Exception{
        var r=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+path)).timeout(Duration.ofSeconds(10)).header("Authorization","Bearer "+uid).POST(HttpRequest.BodyPublishers.ofString(Json.write(body))).build();
        return HTTP.send(r,HttpResponse.BodyHandlers.ofString());
    }
}
