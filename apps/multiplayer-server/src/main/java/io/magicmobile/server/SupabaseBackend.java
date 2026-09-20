package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.net.http.*;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.util.*;

/** Uses only the public key and the caller's JWT. No service-role privilege is needed. */
public final class SupabaseBackend implements MultiplayerServer.Backend {
    record Authentication(String user,long until){}
    private final URI base;private final String key;
    private final HttpClient client=HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(5)).followRedirects(HttpClient.Redirect.NEVER).build();
    private final Map<String,Authentication> cache=new HashMap<>();
    public SupabaseBackend(String url,String key){base=URI.create(url);if(!"https".equals(base.getScheme()))throw new IllegalArgumentException("Supabase requires HTTPS");this.key=key;}
    @Override public String authenticate(String token){
        String hash;try{hash=HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}
        long now=System.currentTimeMillis();synchronized(cache){Authentication a=cache.get(hash);if(a!=null&&a.until()>now)return a.user();}
        Map<String,Object> user=Json.object(request(token,"GET","/auth/v1/user",null));String uid=Json.requiredString(user,"id");
        // JWT payload is used only to shorten a cache lifetime after Auth has verified the token.
        long expiry=now;try{String[] parts=token.split("\\.");Map<String,Object> payload=Json.parseObject(new String(Base64.getUrlDecoder().decode(parts[1]),StandardCharsets.UTF_8));expiry=Json.integer(payload.get("exp"))*1000;}catch(RuntimeException ignored){}
        synchronized(cache){cache.entrySet().removeIf(e->e.getValue().until()<=now);if(cache.size()<2048)cache.put(hash,new Authentication(uid,Math.min(now+30000,expiry)));}
        return uid;
    }
    @Override public Map<String,Object> rpc(String token,String operation,Map<String,Object> parameters){
        if(!Set.of("create_lobby","join_lobby","status","set_ready","start","leave_match").contains(operation))throw new IllegalArgumentException("Unsupported RPC");
        Object result=request(token,"POST","/rest/v1/rpc/matchmaking_"+operation,parameters);
        if(result instanceof List<?> list)return list.isEmpty()?Map.of():Json.object(list.get(0));
        return result==null?Map.of():Json.object(result);
    }
    @Override public Map<String,Object> match(String token,String id){
        UUID.fromString(id);List<Object> result=Json.array(request(token,"GET","/rest/v1/matches?id=eq."+id+"&select=id,join_code,status,host_user_id,player_count",null));
        if(result.size()!=1)throw MultiplayerServer.fail("membership_lost","Lobby is not available to this account.");return Json.object(result.get(0));
    }
    @Override public List<Map<String,Object>> players(String token,String id){
        UUID.fromString(id);List<Object> rows=Json.array(request(token,"GET","/rest/v1/match_players?match_id=eq."+id+"&left_at=is.null&select=user_id,seat,display_name,ready",null));
        List<Map<String,Object>> result=new ArrayList<>();for(Object row:rows)result.add(Json.object(row));return result;
    }
    private Object request(String token,String method,String path,Map<String,Object> body){
        try{
            HttpRequest.Builder request=HttpRequest.newBuilder(base.resolve(path)).timeout(Duration.ofSeconds(10)).header("apikey",key).header("Authorization","Bearer "+token).header("Content-Type","application/json");
            request.method(method,body==null?HttpRequest.BodyPublishers.noBody():HttpRequest.BodyPublishers.ofString(Json.write(body)));
            HttpResponse<java.io.InputStream> response=client.send(request.build(),HttpResponse.BodyHandlers.ofInputStream());
            byte[] bytes;try(var stream=response.body()){bytes=stream.readNBytes(256*1024+1);}
            if(bytes.length>256*1024)throw MultiplayerServer.fail("service_unavailable","Lobby response exceeded its limit.");
            if(response.statusCode()==401)throw MultiplayerServer.fail("unauthorized","Please sign in again.");
            if(response.statusCode()==429)throw MultiplayerServer.fail("rate_limit","Please wait before trying again.");
            if(response.statusCode()<200 || response.statusCode()>=300)throw MultiplayerServer.fail("lobby_unavailable","The lobby request could not complete. Check your code and lobby status.");
            return bytes.length==0?null:Json.parse(new String(bytes,StandardCharsets.UTF_8));
        }catch(BridgeException e){throw e;}catch(InterruptedException e){Thread.currentThread().interrupt();throw MultiplayerServer.fail("service_unavailable","Lobby request interrupted.");}catch(Exception e){throw MultiplayerServer.fail("service_unavailable","Cannot reach the lobby service.");}
    }
}
