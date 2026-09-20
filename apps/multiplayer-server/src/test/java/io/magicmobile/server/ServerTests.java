package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.net.http.*;
import java.util.*;

/** Synthetic transport/security regression tests, not XMage acceptance evidence. */
public final class ServerTests {
    static final String LOBBY="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",GAME="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
    static final Map<String,Object> ID=Json.map("protocolVersion",1L,"upstreamCommit","revision","catalogueHash","hash","adapterVersion","0.1.1-test");
    static final class Backend implements MultiplayerServer.Backend{
        List<Map<String,Object>> players=new ArrayList<>();String status="waiting";String otherMatch;int leaveCalls;
        public String authenticate(String token){if(!Set.of("alice","bob","eve").contains(token))throw MultiplayerServer.fail("unauthorized","Invalid token");return token;}
        public Map<String,Object> rpc(String token,String op,Map<String,Object> args){
            switch(op){
                case "create_lobby","join_lobby":players.add(Json.map("user_id",token,"display_name",token,"seat",(long)players.size(),"ready",false));break;
                case "set_ready":players.stream().filter(p->p.get("user_id").equals(token)).forEach(p->p.put("ready",args.get("p_ready")));break;
                case "start":status="active";break;
                case "leave_match":check(LOBBY.equals(args.get("p_match_id")),"Leave RPC binds expected ID");status="abandoned";leaveCalls++;break;
                case "status":
                    return Json.map("match_id",otherMatch!=null?otherMatch:players.stream().anyMatch(p->token.equals(p.get("user_id")))&&!Set.of("abandoned","finished").contains(status)?LOBBY:null);
            }
            return Json.map("match_id",LOBBY);
        }
        public Map<String,Object> match(String token,String id){return Json.map("status",status,"host_user_id","alice","player_count",2L,"join_code","ABC123");}
        public List<Map<String,Object>> players(String token,String id){return new ArrayList<>(players);}
    }
    static final class Port implements EnginePort{
        static int polls,closed;
        public Map<String,Object> validateDeck(Map<String,Object> deck){if(!deck.containsKey("cards"))throw new BridgeException("invalid_deck","Bad deck");return Map.of("valid",true);}
        public Map<String,Object> create(Map<String,Object> config){check(Json.array(config.get("seats")).size()==2,"Two human seats");return Map.of("matchId",GAME);}
        public Map<String,Object> poll(String id,String viewer,long after){polls++;return Map.of("viewer",viewer);}
        public Map<String,Object> respond(String id,String viewer,Map<String,Object> command){return Map.of("viewer",viewer);}
        public void destroy(String id){}public Map<String,Object> capabilities(){return Map.of();}public void close(){closed++;}
    }
    static HttpClient client=HttpClient.newHttpClient();static int port;
    static HttpResponse<String> call(String user,String path,Object body)throws Exception{
        var r=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+port+path));if(user!=null)r.header("Authorization","Bearer "+user);
        if(body!=null)r.POST(HttpRequest.BodyPublishers.ofString(Json.write(body)));return client.send(r.build(),HttpResponse.BodyHandlers.ofString());
    }
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    public static void main(String[] args)throws Exception{
        Backend backend=new Backend();
        try(var server=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,Port::new,ID,"https://example.supabase.co","public",1)){
            server.start();port=server.port();
            check(call(null,"/v1/config",null).statusCode()==200,"Public config");
            check(call(null,"/v1/lobbies",Map.of()).statusCode()==401,"Authentication required");
            check(call("alice","/v1/lobbies/current",null).body().equals("null"),"No current lobby returns JSON null");
            Map<String,Object> create=Json.map("name","Alice","platform","ios","identity",ID,"deck",Map.of("cards",List.of()),"playerCount",2L);
            Map<String,Object> mismatch=new HashMap<>(create);mismatch.put("identity",Map.of());
            check(call("alice","/v1/lobbies",mismatch).statusCode()==400,"Reject incompatible identity");
            check(call("alice","/v1/lobbies",create).statusCode()==200,"Create lobby");
            check(Json.parseObject(call("alice","/v1/lobbies/current",null).body()).get("id").equals(LOBBY),"Recover lost create response");
            Map<String,Object> join=new HashMap<>(create);join.remove("playerCount");join.put("code","ABC123");join.put("platform","android");
            check(call("bob","/v1/lobbies/join",join).statusCode()==200,"Android joins");
            check(Json.parseObject(call("bob","/v1/lobbies/current",null).body()).get("id").equals(LOBBY),"Recover lost join response");
            check(call("eve","/v1/lobbies/current",null).body().equals("null"),"Current lobby is user scoped");
            check(call("eve","/v1/lobbies/"+LOBBY,null).statusCode()==403,"Nonmember cannot read lobby");
            check(call("alice","/v1/lobbies/"+LOBBY+"/start",Map.of()).statusCode()==400,"Require ready");
            for(String uid:List.of("alice","bob"))check(call(uid,"/v1/lobbies/"+LOBBY+"/ready",Map.of("ready",true)).statusCode()==200,"Set ready");
            check(call("bob","/v1/lobbies/"+LOBBY+"/start",Map.of()).statusCode()==403,"Host start only");
            check(call("alice","/v1/lobbies/"+LOBBY+"/start",Map.of()).statusCode()==200,"Start game");
            String route="/v1/matches/"+GAME+"/engine";
            Map<String,Object> poll=Json.map("protocol",1L,"op","poll","matchId",GAME,"viewerId","alice","after",0L);
            check(call("alice",route,poll).body().contains("\"viewer\":\"alice\""),"Own projection");
            check(call("bob",route,poll).statusCode()==403,"Cannot impersonate another seat");
            check(call("eve",route,poll).statusCode()==403,"Cannot enter another match");
            poll.put("op","diagnostics");check(call("alice",route,poll).statusCode()==403,"No privileged engine operations");
            check(Port.polls==1,"Rejected calls never reach engine");
            check(call("eve","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==200,"Already absent is idempotent");
            poll.put("op","poll");check(call("alice",route,poll).statusCode()==200,"Absent nonmember cannot end another game");
            backend.otherMatch="cccccccc-cccc-cccc-cccc-cccccccccccc";
            check(call("bob","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==403,"Never leave another current lobby");
            check(backend.leaveCalls==0,"Wrong-lobby leave does not invoke RPC");backend.otherMatch=null;
            check(call("bob","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==200,"Leave ends match");
            check(call("bob","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==200,"Repeated leave succeeds");
            check(backend.leaveCalls==1,"Repeated leave does not repeat database mutation");
            check(call("alice","/v1/lobbies/current",null).body().equals("null"),"Ended current lobby is null");
            poll.put("op","poll");check(call("alice",route,poll).statusCode()==410,"Ended session explicit");
        }
        backend.status="active";
        try(var restarted=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,Port::new,ID,"https://example.supabase.co","public",1)){
            restarted.start();port=restarted.port();
            Map<String,Object> recovered=Json.parseObject(call("alice","/v1/lobbies/current",null).body());
            check(recovered.get("id").equals(LOBBY)&&recovered.get("status").equals("interrupted")&&recovered.get("matchId")==null,"Restart recovery retains lobby ID but never implies game restoration");
            check(call("alice","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==200,"Can leave after engine memory was lost");
        }
        backend.status="waiting";
        try(var restarted=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,Port::new,ID,"https://example.supabase.co","public",1)){
            restarted.start();port=restarted.port();
            Map<String,Object> recovered=Json.parseObject(call("alice","/v1/lobbies/current",null).body());
            check(recovered.get("status").equals("interrupted"),"Waiting lobby with lost submitted deck is recoverable interruption");
            check(call("alice","/v1/lobbies/"+LOBBY+"/leave",Map.of()).statusCode()==200,"Can leave waiting lobby after deck cache loss");
        }
        System.out.println("PASS: cross-platform lobby flow, auth, seat binding, operation allowlist, ready gate, leave and restart semantics (synthetic engine)");
    }
}
