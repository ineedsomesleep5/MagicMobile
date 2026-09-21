package io.magicmobile.server;

import com.sun.net.httpserver.HttpServer;
import java.net.*;
import java.net.http.*;
import java.nio.ByteBuffer;
import java.time.Duration;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.*;

/** Loopback transport only; no Supabase credentials, production calls, or rules engine. */
public final class BackendResponseRegressions {
    static void check(boolean condition,String message){if(!condition)throw new AssertionError(message);}
    static final class Subscription implements Flow.Subscription {
        boolean cancelled;public void request(long n){}public void cancel(){cancelled=true;}
    }
    public static void main(String[] args)throws Exception{
        var subscriber=new SupabaseBackend.LimitedBody();var subscription=new Subscription();subscriber.onSubscribe(subscription);
        subscriber.onNext(List.of(ByteBuffer.wrap(new byte[256*1024])));subscriber.onComplete();
        check(subscriber.getBody().toCompletableFuture().get().length==256*1024,"Exact memory limit allowed");
        subscriber=new SupabaseBackend.LimitedBody();subscription=new Subscription();subscriber.onSubscribe(subscription);
        subscriber.onNext(List.of(ByteBuffer.wrap(new byte[256*1024]),ByteBuffer.wrap(new byte[1])));
        check(subscription.cancelled&&subscriber.getBody().toCompletableFuture().isCompletedExceptionally(),"Oversized batch fails and cancels upstream before copying");
        subscriber=new SupabaseBackend.LimitedBody();subscriber.cancel();subscription=new Subscription();subscriber.onSubscribe(subscription);
        check(subscription.cancelled,"Timeout before subscription still cancels later subscription");

        // Use the production client's redirect policy, while directing only this test helper to loopback.
        var backend=new SupabaseBackend("https://example.supabase.co","public");
        var field=SupabaseBackend.class.getDeclaredField("client");field.setAccessible(true);HttpClient client=(HttpClient)field.get(backend);
        HttpServer server=HttpServer.create(new InetSocketAddress("127.0.0.1",0),0);
        ExecutorService workers=Executors.newFixedThreadPool(3);server.setExecutor(workers);
        CountDownLatch bodyStarted=new CountDownLatch(1),release=new CountDownLatch(1);AtomicInteger followed=new AtomicInteger();
        server.createContext("/slow",e->{try{e.sendResponseHeaders(200,0);e.getResponseBody().write('{');e.getResponseBody().flush();bodyStarted.countDown();release.await(5,TimeUnit.SECONDS);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();}finally{e.close();}});
        server.createContext("/ok",e->{byte[] b="{}".getBytes();e.sendResponseHeaders(200,b.length);e.getResponseBody().write(b);e.close();});
        server.createContext("/redirect",e->{e.getResponseHeaders().set("Location","/target");e.sendResponseHeaders(302,-1);e.close();});
        server.createContext("/target",e->{followed.incrementAndGet();e.sendResponseHeaders(200,-1);e.close();});
        server.start();String base="http://127.0.0.1:"+server.getAddress().getPort();
        try{
            long began=System.nanoTime();
            try{SupabaseBackend.boundedResponse(client,HttpRequest.newBuilder(URI.create(base+"/slow")).build(),Duration.ofMillis(700));throw new AssertionError("Slow body escaped deadline");}
            catch(TimeoutException expected){check(bodyStarted.getCount()==0,"Headers and partial body arrived before timeout");check(System.nanoTime()-began<TimeUnit.SECONDS.toNanos(3),"Deadline includes unfinished body");}
            release.countDown();
            var good=SupabaseBackend.boundedResponse(client,HttpRequest.newBuilder(URI.create(base+"/ok")).build(),Duration.ofSeconds(2));
            check(good.statusCode()==200&&new String(good.body()).equals("{}"),"Normal response still succeeds after cancellation");
            var redirected=SupabaseBackend.boundedResponse(client,HttpRequest.newBuilder(URI.create(base+"/redirect")).header("Authorization","Bearer synthetic-test").build(),Duration.ofSeconds(2));
            check(redirected.statusCode()==302&&followed.get()==0,"Credential-bearing redirect never followed");
        }finally{release.countDown();server.stop(0);workers.shutdownNow();}
        System.out.println("PASS: 6 bounded backend response regressions (limit, overflow cancellation, late subscription, streaming deadline, recovery, redirect denial)");
    }
}
