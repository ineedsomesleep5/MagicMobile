package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.net.http.*;
import java.lang.reflect.*;
import java.util.*;

/** Focused failure injection: no real engine, Supabase network, or production data. */
public final class FailureRegressions {
    static final class Backend implements MultiplayerServer.Backend {
        String failure,status="active";boolean startFails;
        public String authenticate(String token){return token;}
        public Map<String,Object> rpc(String token,String op,Map<String,Object> body){if(op.equals("start")&&startFails)throw new BridgeException("service_unavailable","Injected start failure");return Map.of("match_id",ServerTests.LOBBY);}
        public Map<String,Object> match(String token,String id){if(failure!=null)throw new BridgeException(failure,"Injected backend failure");return Json.map("status",status,"host_user_id","alice","player_count",2L,"join_code","ABC123");}
        public List<Map<String,Object>> players(String token,String id){return new ArrayList<>(List.of(Json.map("user_id","alice","display_name","Alice","ready",true,"seat",0L),Json.map("user_id","bob","display_name","Bob","ready",true,"seat",1L)));}
    }
    static final class Port implements EnginePort {
        int failures,closed;
        public Map<String,Object> create(Map<String,Object> c){return Map.of("matchId",ServerTests.GAME);}
        public Map<String,Object> validateDeck(Map<String,Object> d){return Map.of("valid",true);}
        public Map<String,Object> poll(String id,String uid,long after){return Map.of("viewer",uid);}
        public Map<String,Object> respond(String id,String uid,Map<String,Object> c){return Map.of();}
        public Map<String,Object> capabilities(){return Map.of();}public void destroy(String id){}
        public void close(){if(failures>0){failures--;throw new BridgeException("engine_busy_shutdown","Injected busy shutdown");}closed++;}
    }
    @SuppressWarnings("unchecked") static <K,V> Map<K,V> map(Object server,String field)throws Exception{Field f=MultiplayerServer.class.getDeclaredField(field);f.setAccessible(true);return (Map<K,V>)f.get(server);}
    static void expire(MultiplayerServer server)throws Exception{Method m=MultiplayerServer.class.getDeclaredMethod("expire");m.setAccessible(true);m.invoke(server);}
    static MultiplayerServer make(Backend backend,Port port)throws Exception{return new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,()->port,ServerTests.ID,"https://example.supabase.co","public",1);}
    static void install(MultiplayerServer server,Port port)throws Exception{
        map(server,"sessions").put(ServerTests.GAME,new MultiplayerServer.Session(port,Set.of("alice","bob"),ServerTests.LOBBY));
        map(server,"lobbyGames").put(ServerTests.LOBBY,ServerTests.GAME);map(server,"lobbyTouched").put(ServerTests.LOBBY,System.currentTimeMillis());
    }
    static HttpResponse<String> call(MultiplayerServer server,String path,Map<String,Object> body)throws Exception{
        return HttpClient.newHttpClient().send(HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+server.port()+path)).header("Authorization","Bearer alice").POST(HttpRequest.BodyPublishers.ofString(Json.write(body))).build(),HttpResponse.BodyHandlers.ofString());
    }
    static HttpResponse<String> poll(MultiplayerServer server)throws Exception{return call(server,"/v1/matches/"+ServerTests.GAME+"/engine",Json.map("protocol",1L,"op","poll","matchId",ServerTests.GAME,"viewerId","alice","after",0L));}
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception{
        int passed=0;
        for(String failure:List.of("membership_lost","unauthorized","service_unavailable")){
            Backend b=new Backend();b.failure=failure;Port p=new Port();try(var server=make(b,p)){install(server,p);server.start();var response=poll(server);
                int expected=failure.equals("membership_lost")?410:failure.equals("unauthorized")?401:503;
                check(response.statusCode()==expected,"Distinct failure status: "+failure);
                check(failure.equals("membership_lost")?map(server,"sessions").isEmpty():map(server,"sessions").size()==1,"Only lost membership retires engine");
                if(expected==410)check(response.body().contains("session_lost"),"RLS disappearance maps to session_lost");passed++;
            }
        }
        Backend b=new Backend();b.failure="membership_lost";Port p=new Port();p.failures=2;
        try(var server=make(b,p)){install(server,p);server.start();check(poll(server).statusCode()==410,"Close failure preserves client session-lost meaning");
            check(map(server,"sessions").size()==1&&map(server,"lobbyGames").size()==1,"Failed close retains ownership and capacity");
            expire(server);check(map(server,"sessions").size()==1,"Expiry catches retry failure without escaping scheduler");
            expire(server);check(map(server,"sessions").isEmpty()&&map(server,"lobbyGames").isEmpty()&&p.closed==1,"Later expiry retries close and only then frees capacity");passed++;
        }
        b=new Backend();b.status="waiting";p=new Port();
        try(var server=make(b,p)){for(int i=0;i<16;i++)map(server,"decks").put(i==0?ServerTests.LOBBY:UUID.randomUUID().toString(),new HashMap<>());
            map(server,"lobbyCodes").put(ServerTests.LOBBY,"ABC123");server.start();
            Map<String,Object> body=Json.map("name","Alice","platform","ios","identity",ServerTests.ID,"deck",Map.of("cards",List.of()),"code","ABC123");
            check(call(server,"/v1/lobbies/join",body).statusCode()==200,"Existing lobby can be joined at lobby capacity");
            body.remove("code");body.put("playerCount",2L);check(call(server,"/v1/lobbies",body).statusCode()==503,"Capacity still rejects new lobbies");passed++;
        }
        b=new Backend();b.status="ready";b.startFails=true;p=new Port();p.failures=1;
        try(var server=make(b,p)){Map<String,MultiplayerServer.Deck> decks=new HashMap<>();for(String uid:List.of("alice","bob"))decks.put(uid,new MultiplayerServer.Deck(Map.of(),ServerTests.ID));
            map(server,"decks").put(ServerTests.LOBBY,decks);map(server,"lobbyTouched").put(ServerTests.LOBBY,System.currentTimeMillis());server.start();
            check(call(server,"/v1/lobbies/"+ServerTests.LOBBY+"/start",Map.of()).statusCode()==503,"Failed database start returns original service failure");
            check(map(server,"sessions").size()==1,"Failed startup/close retains reserved capacity");expire(server);check(map(server,"sessions").isEmpty(),"Failed startup cleanup retries");passed++;
        }
        System.out.println("PASS: "+passed+" focused synthetic failure regressions");
    }
}
