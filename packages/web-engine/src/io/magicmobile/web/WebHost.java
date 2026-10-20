package io.magicmobile.web;

import io.magicmobile.core.*;
import java.util.*;

/**
 * WEB BUILD ONLY. The engine's request loop on its single thread (docs/WEB_ENGINE_M1.md). The page sends one JSON
 * request at a time over the channel and waits for its reply. Between requests the loop runs the game a create
 * deferred (WebThreads); while that game runs, the page is served:
 * - blocking, while a human question waits for its answer (MobileHumanPlayer, through WebThreads.awaitAnswer);
 * - one request without blocking, after each published snapshot, so polls see AI turns as they happen.
 * A request that would start a match (create, restore) or shut the engine down is held until the running game
 * has returned to this loop, so one game never runs inside another's stack.
 */
public final class WebHost implements WebThreads.Host {
    /** The page's side: requests in, replies out, strictly alternating. */
    public interface Channel {
        /** The next request, or null when none came (at once without block, within about 250 ms with it). */
        String take(boolean block);
        void reply(String json);
    }
    private static final Set<String> HELD_WHILE_PLAYING=Set.of("create","restore","shutdown");
    private final Channel channel;
    private final EngineService service;
    private final ArrayDeque<String> held=new ArrayDeque<>();
    /** Requests served, and how many were held for the running game to return (bench diagnostics). */
    long served,heldCount;

    public WebHost(Channel channel,EngineService service) {
        this.channel=Objects.requireNonNull(channel);this.service=Objects.requireNonNull(service);
    }

    /** Never returns: the worker is this loop. */
    public void run() {
        WebThreads.install(this);
        while(true) {
            serveOne(true);
            WebThreads.runDeferred();
        }
    }

    @Override public void serveOne(boolean block) {
        boolean playing=WebThreads.busy();
        String request=!playing && !held.isEmpty()?held.poll():channel.take(block);
        if(request==null || request.isEmpty()) return;
        if(playing && HELD_WHILE_PLAYING.contains(op(request))) {
            held.add(request);heldCount++;
            return;
        }
        served++;
        String reply=service.request(request);
        if(TRACE) trace(block,playing,request,reply);
        channel.reply(reply);
    }

    private static final boolean TRACE=Boolean.getBoolean("magicmobile.webTrace");
    /** JVM harness only (-Dmagicmobile.webTrace=true): each request served, where, and its reply's state. */
    private static void trace(boolean block,boolean playing,String request,String reply) {
        StringBuilder line=new StringBuilder("TRACE ").append(block?"wait ":playing?"snapshot ":"idle ").append(op(request));
        try {
            Object result=Json.parseObject(reply).get("result");
            if(result instanceof Map) {
                Map<?,?> r=(Map<?,?>)result;
                line.append(" rev=").append(r.get("revision")).append(" phase=").append(r.get("phase")).append(" status=").append(r.get("status"));
                if(r.get("prompt") instanceof Map) line.append(" prompt=").append(((Map<?,?>)r.get("prompt")).get("promptId"));
            } else line.append(" ").append(reply.length()>200?reply.substring(0,200):reply);
        } catch(RuntimeException e) { line.append(" ?"); }
        System.err.println(line);
    }

    private static String op(String request) {
        try { Object op=Json.parseObject(request).get("op");return op instanceof String?(String)op:""; }
        catch(RuntimeException invalid) { return ""; } // EngineService answers it with its own error
    }
}
