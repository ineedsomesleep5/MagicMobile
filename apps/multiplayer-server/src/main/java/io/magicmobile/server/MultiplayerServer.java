package io.magicmobile.server;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import io.magicmobile.core.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.time.*;
import java.util.*;
import java.util.concurrent.*;
import java.util.function.Supplier;
import java.util.function.LongSupplier;

/** HTTPS terminates at the local reverse proxy. Every game operation binds a verified UID to a seat. */
public final class MultiplayerServer implements AutoCloseable {
    public interface Backend {
        String authenticate(String token);
        Map<String,Object> rpc(String token,String operation,Map<String,Object> parameters);
        Map<String,Object> match(String token,String id);
        List<Map<String,Object>> players(String token,String id);
    }
    record Deck(Map<String,Object> value,Map<String,Object> identity) {}
    static final class Session {
        final EnginePort engine; final EngineService service; final Set<String> members; final String lobby;
        volatile long touched=System.currentTimeMillis();
        volatile boolean closing;
        Session(EnginePort e,Set<String> users,String lobby) {engine=e;service=new EngineService(e);members=Set.copyOf(users);this.lobby=lobby;}
    }
    private final Backend backend;
    private final Supplier<EnginePort> engines;
    private final Map<String,Object> identity,configuration;
    private final int capacity;
    private final LongSupplier admissionClock;
    private final Map<String,Map<String,Deck>> decks=new HashMap<>();
    private final Map<String,Session> sessions=new HashMap<>();
    private final Map<String,String> lobbyGames=new HashMap<>();
    private final Map<String,Long> lobbyTouched=new HashMap<>();
    private final Map<String,String> lobbyCodes=new HashMap<>();
    private final Semaphore validations=new Semaphore(1);
    private final Map<String,long[]> quotas=new HashMap<>();
    private final HttpServer http;
    private final ExecutorService executor=new ThreadPoolExecutor(4,8,30,TimeUnit.SECONDS,new ArrayBlockingQueue<>(32),new ThreadPoolExecutor.AbortPolicy());
    private final ScheduledExecutorService cleanup=Executors.newSingleThreadScheduledExecutor();
    public MultiplayerServer(InetSocketAddress address,Backend backend,Supplier<EnginePort> engines,Map<String,Object> identity,String url,String key,int capacity)throws IOException {
        this(address,backend,engines,identity,url,key,capacity,System::nanoTime);
    }
    MultiplayerServer(InetSocketAddress address,Backend backend,Supplier<EnginePort> engines,Map<String,Object> identity,String url,String key,int capacity,LongSupplier admissionClock)throws IOException {
        this.backend=backend;this.engines=engines;this.identity=Map.copyOf(identity);this.capacity=capacity;
        this.admissionClock=admissionClock;
        if(capacity<1 || capacity>4) throw new IllegalArgumentException("Capacity must be 1–4");
        configuration=Json.map("supabaseUrl",url,"publishableKey",key,"identity",identity,"capabilities",Json.map("privateLobbies",true,"quickMatch",false,"maxPlayers",4,"reconnect",true,"persistentResume",false));
        http=HttpServer.create(address,32);http.setExecutor(executor);http.createContext("/",this::handle);
        cleanup.scheduleAtFixedRate(this::expire,1,1,TimeUnit.MINUTES);
    }
    public void start(){http.start();}
    public int port(){return http.getAddress().getPort();}
    private void handle(HttpExchange exchange)throws IOException {
        try {
            String path=exchange.getRequestURI().getPath(),method=exchange.getRequestMethod();
            if(path.equals("/health") && method.equals("GET")){send(exchange,200,Json.map("ok",true));return;}
            if(path.equals("/v1/config") && method.equals("GET")){send(exchange,200,configuration);return;}
            String authorization=exchange.getRequestHeaders().getFirst("Authorization");
            if(authorization==null || !authorization.startsWith("Bearer ") || authorization.length()>8192) throw fail("unauthorized","Sign in to play online.");
            String token=authorization.substring(7),user=backend.authenticate(token);quota(user);
            Map<String,Object> body=method.equals("POST")?body(exchange):Map.of();
            Object result;
            if(path.equals("/v1/lobbies") && method.equals("POST"))result=enter(token,user,body,false);
            else if(path.equals("/v1/lobbies/join") && method.equals("POST"))result=enter(token,user,body,true);
            else if(path.equals("/v1/lobbies/current") && method.equals("GET")){
                Object current=backend.rpc(token,"status",Map.of()).get("match_id");
                result=current==null?null:lobby(token,user,Json.string(current));
            }
            else if(path.matches("/v1/lobbies/[a-fA-F0-9-]{36}(/(ready|start|leave))?")){
                String[] parts=path.split("/");String id=parts[3];
                if(parts.length==4 && method.equals("GET"))result=lobby(token,user,id);
                else if(parts.length==5 && method.equals("POST"))result=action(token,user,id,parts[4],body);
                else throw fail("not_found","Unknown endpoint.");
            } else if(path.matches("/v1/matches/[a-fA-F0-9-]{36}/engine") && method.equals("POST")){
                result=engine(token,user,path.split("/")[3],body);
            } else throw fail("not_found","Unknown endpoint.");
            send(exchange,200,result);
        }catch(BridgeException error){
            int code=switch(error.code()){case "unauthorized"->401;case "forbidden","membership_lost"->403;case "not_found"->404;case "rate_limit"->429;case "capacity","service_unavailable","engine_busy_shutdown"->503;case "session_lost"->410;default->400;};
            send(exchange,code,Json.map("error",error.envelope()));
        }catch(Exception error){send(exchange,503,Json.map("error",Json.map("code","service_unavailable","message","Online play is temporarily unavailable. Please try again.")));}
        finally{exchange.close();}
    }
    private Map<String,Object> enter(String token,String user,Map<String,Object> body,boolean join){
        Json.onlyKeys(body,Set.of("name","platform","identity","deck","playerCount","code"));
        Map<String,Object> supplied=Json.object(body.get("identity"));
        if(!identity.equals(supplied))throw fail("update_required","Everyone must use the same compatible app update.");
        String name=Json.requiredString(body,"name").strip();if(name.isEmpty()||name.length()>24)throw fail("invalid_name","Use a name with 1–24 characters.");
        String platform=Json.requiredString(body,"platform");if(!Set.of("ios","android").contains(platform))throw fail("invalid_platform","Unsupported platform.");
        Map<String,Object> deck=Json.object(Json.freeze(body.get("deck")));
        // The rules engine validates actual Commander decks before admission, never trusting client validity flags.
        String code=join?Json.requiredString(body,"code").strip().toUpperCase(Locale.ROOT):null;
        long count=join?0:Json.integer(body.get("playerCount"));
        if(!join&&(count<2||count>4))throw fail("invalid_players","Choose 2–4 players.");
        if(join&&!code.matches("[A-Z0-9]{1,32}"))throw fail("invalid_code","Enter a valid lobby code.");
        if(!validations.tryAcquire())throw fail("capacity","Another deck is being checked. Please try again shortly.");
        try {
            long began=admissionClock.getAsLong();
            synchronized(this){
                boolean existing=join&&lobbyCodes.entrySet().stream().anyMatch(e->e.getValue().equals(code)&&decks.containsKey(e.getKey()));
                if(decks.size()>=16&&!existing)throw fail("capacity","The lobby service is full. Try again shortly.");
            }
            // Cold deck loading must not hold the global lobby/game monitor or queue more validators.
            // Java interruption cannot safely cancel XMage initialization. Retain admission ownership
            // until it returns, then reject late work before any database mutation can create a lobby.
            try(EnginePort validator=engines.get()){
                if(!Boolean.TRUE.equals(validator.validateDeck(deck).get("valid")))throw fail("invalid_deck","Choose a valid Commander deck.");
            }
            synchronized(this){
                if(admissionClock.getAsLong()-began>=TimeUnit.SECONDS.toNanos(10))throw fail("service_unavailable","Deck admission exceeded the server budget. Please try again shortly.");
                Map<String,Object> args=Json.map("p_display_name",name,"p_platform",platform,"p_app_version",identity.get("adapterVersion"),"p_engine_build",identity.get("adapterVersion"),"p_upstream",identity.get("upstreamCommit"),"p_catalogue_hash",identity.get("catalogueHash"),"p_protocol_version",identity.get("protocolVersion"),"p_host_score",0);
                if(join)args.put("p_code",code);
                else args.put("p_player_count",count);
                Map<String,Object> row=backend.rpc(token,join?"join_lobby":"create_lobby",args);
                String id=Json.requiredString(row,"match_id");
                decks.computeIfAbsent(id,k->new HashMap<>()).put(user,new Deck(deck,supplied));lobbyTouched.put(id,System.currentTimeMillis());
                return lobby(token,user,id);
            }
        }finally{validations.release();}
    }
    private List<Map<String,Object>> members(String token,String user,String id){
        List<Map<String,Object>> players=backend.players(token,id);
        if(players.stream().noneMatch(p->user.equals(p.get("user_id"))))throw fail("forbidden","You are not a member of this lobby.");
        return players;
    }
    private synchronized Map<String,Object> lobby(String token,String user,String id){
        List<Map<String,Object>> players=members(token,user,id);Map<String,Object> match=backend.match(token,id);
        String status=Json.requiredString(match,"status"),game=lobbyGames.get(id);
        if(game!=null&&sessions.get(game)!=null&&sessions.get(game).closing){status="interrupted";game=null;}
        if(status.equals("active") && game==null)status="interrupted";
        if(Set.of("waiting","ready").contains(status)&&!decks.getOrDefault(id,Map.of()).containsKey(user))status="interrupted";
        List<Object> shown=new ArrayList<>();
        for(Map<String,Object> p:players)shown.add(Json.map("userId",p.get("user_id"),"name",p.get("display_name"),"seatId",p.get("user_id"),"ready",p.get("ready"),"deckSubmitted",decks.getOrDefault(id,Map.of()).containsKey(p.get("user_id"))));
        lobbyTouched.put(id,System.currentTimeMillis());
        if(match.get("join_code") instanceof String code)lobbyCodes.put(id,code);
        return Json.map("id",id,"code",match.get("join_code"),"status",status,"playerCount",match.get("player_count"),"hostUserId",match.get("host_user_id"),"players",shown,"matchId",game,"seatId",game==null?null:user);
    }
    private synchronized Map<String,Object> action(String token,String user,String id,String op,Map<String,Object> body){
        if(op.equals("leave"))return leave(token,user,id,body);
        List<Map<String,Object>> players=members(token,user,id);
        switch(op){
            case "ready":
                Json.onlyKeys(body,Set.of("ready"));boolean ready=Json.bool(body.get("ready"));
                if(ready&&!decks.getOrDefault(id,Map.of()).containsKey(user))throw fail("deck_required","Join again with your chosen deck.");
                backend.rpc(token,"set_ready",Json.map("p_match_id",id,"p_ready",ready));break;
            case "start":
                Json.onlyKeys(body,Set.of());Map<String,Object> match=backend.match(token,id);
                if(!user.equals(match.get("host_user_id")))throw fail("forbidden","Only the lobby creator can start.");
                if(lobbyGames.containsKey(id))return lobby(token,user,id);
                if(!Set.of("waiting","ready").contains(match.get("status")))throw fail("session_lost","Create a new lobby to start another game.");
                if(sessions.size()>=capacity)throw fail("capacity","All game servers are busy. Please try again shortly.");
                if(players.size()!=Json.integer(match.get("player_count")))throw fail("not_ready","Wait for all players to join.");
                List<Object> seats=new ArrayList<>();Set<String> users=new HashSet<>();
                players.sort(Comparator.comparingLong(p->Json.integer(p.get("seat"))));
                for(Map<String,Object> p:players){String uid=Json.requiredString(p,"user_id");Deck d=decks.getOrDefault(id,Map.of()).get(uid);
                    if(d==null || !Boolean.TRUE.equals(p.get("ready")))throw fail("not_ready","Everyone must submit a deck and be ready.");
                    if(!identity.equals(d.identity()))throw fail("update_required","An app update is required.");
                    seats.add(Json.map("seatId",uid,"name",p.get("display_name"),"controller","human","deck",d.value()));users.add(uid);
                }
                EnginePort engine=engines.get();
                String game=UUID.randomUUID().toString();
                Session reserved=new Session(engine,users,id);
                sessions.put(game,reserved);lobbyGames.put(id,game);
                try{String created=Json.requiredString(engine.create(Json.map("seats",seats)),"matchId");
                    sessions.remove(game);game=created;sessions.put(game,reserved);lobbyGames.put(id,game);
                    backend.rpc(token,"start",Json.map("p_match_id",id));
                }catch(RuntimeException e){retryableEnd(id);throw e;}break;
            default:throw fail("not_found","Unknown endpoint.");
        }
        return lobby(token,user,id);
    }
    private Map<String,Object> leave(String token,String user,String id,Map<String,Object> body){
        Json.onlyKeys(body,Set.of());
        Object current=backend.rpc(token,"status",Map.of()).get("match_id");
        if(current!=null&&!id.equals(current))throw fail("forbidden","This is not your current lobby.");
        if(current!=null)backend.rpc(token,"leave_match",Json.map("p_match_id",id));
        String game=lobbyGames.get(id);Session session=game==null?null:sessions.get(game);
        // Missing/finished database membership is already left. Never let that path terminate
        // an unrelated live engine: cleanup still requires the immutable authenticated binding.
        if(session!=null&&session.members.contains(user)){end(id);forgetLobby(id);}
        else{Map<String,Deck> submitted=decks.get(id);if(submitted!=null){submitted.remove(user);if(submitted.isEmpty())forgetLobby(id);}}
        return Json.map("left",true);
    }
    private Object engine(String token,String user,String id,Map<String,Object> request){
        Session session;synchronized(this){session=sessions.get(id);}
        if(session==null)throw fail("session_lost","This game session ended. Return to the lobby.");
        if(!session.members.contains(user))throw fail("forbidden","This is not your game.");
        if(session.closing)throw fail("session_lost","This game is ending. Return to the lobby.");
        if(!id.equals(request.get("matchId")) || !user.equals(request.get("viewerId")))throw fail("forbidden","Invalid player binding.");
        if(!Set.of("poll","respond").contains(request.get("op")))throw fail("forbidden","Only player actions are allowed.");
        // A member can also leave through the public database RPC, bypassing this HTTP adapter.
        // Recheck authoritative membership/status so that cannot leave an orphan live game.
        try {
            Map<String,Object> match=backend.match(token,session.lobby);
            if(!"active".equals(match.get("status")))throw fail("membership_lost","This match ended.");
            members(token,user,session.lobby);
        }catch(BridgeException error){
            if(!Set.of("membership_lost","forbidden").contains(error.code()))throw error;
            synchronized(this){retryableEnd(session.lobby);}
            throw fail("session_lost","A player left or the game ended.");
        }
        session.touched=System.currentTimeMillis();return Json.parse(session.service.request(Json.write(request)));
    }
    private synchronized void quota(String uid){
        long now=System.currentTimeMillis();quotas.entrySet().removeIf(e->now-e.getValue()[0]>60000);
        if(quotas.size()>=2048&&!quotas.containsKey(uid))throw fail("rate_limit","Please try again shortly.");
        long[] q=quotas.computeIfAbsent(uid,k->new long[]{now,0});if(++q[1]>180)throw fail("rate_limit","Too many requests. Please wait a moment.");
    }
    private synchronized void expire(){long now=System.currentTimeMillis();for(String id:new ArrayList<>(lobbyTouched.keySet())){Session s=sessions.get(lobbyGames.get(id));long touched=s==null?lobbyTouched.get(id):s.touched;if((s!=null&&s.closing)||now-touched>Duration.ofMinutes(30).toMillis()){if(retryableEnd(id))forgetLobby(id);}}}
    private boolean retryableEnd(String lobby){try{end(lobby);return true;}catch(RuntimeException failure){System.err.println("Match cleanup pending; engine capacity remains reserved.");return false;}}
    private void end(String lobby){String id=lobbyGames.get(lobby);if(id!=null){Session s=sessions.get(id);if(s!=null){s.closing=true;s.service.close();}sessions.remove(id);lobbyGames.remove(lobby);}}
    private void forgetLobby(String id){decks.remove(id);lobbyTouched.remove(id);lobbyCodes.remove(id);}
    private static Map<String,Object> body(HttpExchange e)throws IOException{byte[] bytes=e.getRequestBody().readNBytes(128*1024+1);if(bytes.length>128*1024)throw fail("request_too_large","Request exceeds the limit.");return Json.parseObject(new String(bytes,StandardCharsets.UTF_8));}
    private static void send(HttpExchange e,int status,Object value)throws IOException{byte[] bytes=Json.write(value).getBytes(StandardCharsets.UTF_8);e.getResponseHeaders().set("Content-Type","application/json; charset=utf-8");e.getResponseHeaders().set("Cache-Control","no-store");e.getResponseHeaders().set("X-Content-Type-Options","nosniff");e.sendResponseHeaders(status,bytes.length);e.getResponseBody().write(bytes);}
    static BridgeException fail(String code,String message){return new BridgeException(code,message);}
    @Override public synchronized void close(){http.stop(1);cleanup.shutdownNow();executor.shutdownNow();for(Session s:sessions.values())s.service.close();sessions.clear();}
}
