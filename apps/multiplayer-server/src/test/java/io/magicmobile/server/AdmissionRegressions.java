package io.magicmobile.server;

import io.magicmobile.core.*;
import java.net.*;
import java.net.http.*;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** No real engine or database: exercises slow/failed admission without relaxing HTTP deadlines. */
public final class AdmissionRegressions {
    static class Port implements EnginePort {
        public Map<String,Object> validateDeck(Map<String,Object> d){return Map.of("valid",true);}
        public Map<String,Object> create(Map<String,Object> c){throw new AssertionError("Not starting games");}
        public Map<String,Object> poll(String m,String u,long a){return Map.of();}
        public Map<String,Object> respond(String m,String u,Map<String,Object> c){return Map.of();}
        public Map<String,Object> capabilities(){return Map.of();}public void destroy(String id){}public void close(){}
    }
    static HttpClient http=HttpClient.newHttpClient();
    static Map<String,Object> body(){return Json.map("name","Alice","platform","ios","identity",ServerTests.ID,"deck",Map.of("cards",List.of()),"playerCount",2L);}
    static HttpRequest request(MultiplayerServer s,String path,Map<String,Object> body){
        var r=HttpRequest.newBuilder(URI.create("http://127.0.0.1:"+s.port()+path)).timeout(Duration.ofSeconds(3)).header("Authorization","Bearer alice");
        if(body!=null)r.POST(HttpRequest.BodyPublishers.ofString(Json.write(body)));return r.build();
    }
    static HttpResponse<String> call(MultiplayerServer s,String path,Map<String,Object> body)throws Exception{return http.send(request(s,path,body),HttpResponse.BodyHandlers.ofString());}
    static void check(boolean b,String message){if(!b)throw new AssertionError(message);}
    public static void main(String[] ignored)throws Exception{
        var entered=new CountDownLatch(1);var release=new CountDownLatch(1);var backend=new ServerTests.Backend();
        Port blocked=new Port(){public Map<String,Object> validateDeck(Map<String,Object> d){entered.countDown();try{if(!release.await(5,TimeUnit.SECONDS))throw new AssertionError("Test failed to release validator");}catch(InterruptedException e){throw new AssertionError(e);}return super.validateDeck(d);}};
        try(var s=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,()->blocked,ServerTests.ID,"https://example.supabase.co","public",1)){
            s.start();var first=http.sendAsync(request(s,"/v1/lobbies",body()),HttpResponse.BodyHandlers.ofString());
            try{
                check(entered.await(2,TimeUnit.SECONDS),"Validation entered");
                check(call(s,"/v1/lobbies",body()).statusCode()==503,"Concurrent validation fails fast instead of global-monitor wait");
                check(call(s,"/v1/lobbies/current",null).body().equals("null"),"Authenticated recovery remains responsive during validation");
                check(backend.players.isEmpty(),"No partial membership before validation commits");
            }finally{release.countDown();}
            check(first.get(3,TimeUnit.SECONDS).statusCode()==200,"First valid admission completes");
        }
        AtomicLong clock=new AtomicLong();backend=new ServerTests.Backend();var timedBackend=backend;
        Port slow=new Port(){public Map<String,Object> validateDeck(Map<String,Object> d){clock.addAndGet(TimeUnit.SECONDS.toNanos(11));return super.validateDeck(d);}};
        try(var s=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,()->slow,ServerTests.ID,"https://example.supabase.co","public",1,clock::get)){
            s.start();check(call(s,"/v1/lobbies",body()).statusCode()==503,"Late validation rejected");check(timedBackend.players.isEmpty(),"Timed-out admission never creates an orphan lobby");
            check(call(s,"/v1/lobbies/current",null).body().equals("null"),"Timeout recovery remains empty");
        }
        AtomicReference<MultiplayerServer> owner=new AtomicReference<>();AtomicInteger ticks=new AtomicInteger();AtomicBoolean checkedUnderLock=new AtomicBoolean();
        backend=new ServerTests.Backend();
        try(var s=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,Port::new,ServerTests.ID,"https://example.supabase.co","public",1,()->{
            if(ticks.getAndIncrement()==0)return 0;
            checkedUnderLock.set(Thread.holdsLock(owner.get()));return TimeUnit.SECONDS.toNanos(11);
        })){
            owner.set(s);s.start();check(call(s,"/v1/lobbies",body()).statusCode()==503&&checkedUnderLock.get()&&backend.players.isEmpty(),"Deadline rechecked while holding commit monitor before database mutation");
        }
        AtomicInteger validations=new AtomicInteger();backend=new ServerTests.Backend();
        Port invalid=new Port(){public Map<String,Object> validateDeck(Map<String,Object> d){validations.incrementAndGet();return Map.of("valid",false);}};
        try(var s=new MultiplayerServer(new InetSocketAddress("127.0.0.1",0),backend,()->invalid,ServerTests.ID,"https://example.supabase.co","public",1)){
            s.start();var wrong=body();wrong.put("playerCount",9L);check(call(s,"/v1/lobbies",wrong).statusCode()==400&&validations.get()==0,"Cheap malformed request rejected before engine work");
            check(call(s,"/v1/lobbies",body()).body().contains("invalid_deck")&&backend.players.isEmpty(),"Explicit invalid deck result cannot create membership");
            check(call(s,"/v1/lobbies",body()).statusCode()==400&&validations.get()==2,"Failure releases validation permit for retry");
        }
        System.out.println("PASS: 7 synthetic admission regressions (contention, recovery, late mutation, commit-lock deadline, cheap validation, invalid result, permit retry)");
    }
}
