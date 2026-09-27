package io.magicmobile.core;

import java.util.Map;
import java.util.Set;
import java.util.Objects;
import java.util.function.Supplier;

/** A trusted, in-process API. Do NOT expose it directly to unauthenticated peers. */
public final class EngineService implements AutoCloseable {
    public static final int PROTOCOL=1;
    /** Longest wait a checkpoint request may ask for. */
    public static final long MAX_CHECKPOINT_WAIT_MILLIS=1000;
    private EnginePort engine;
    private final Supplier<? extends EnginePort> initializer;
    private boolean closed;
    private boolean terminated;
    public EngineService(EnginePort engine) { this.engine=Objects.requireNonNull(engine);initializer=null; }
    private EngineService(Supplier<? extends EnginePort> initializer) { this.initializer=Objects.requireNonNull(initializer); }
    public static EngineService lazy(Supplier<? extends EnginePort> initializer) { return new EngineService(initializer); }
    private synchronized EnginePort engine() {
        if(closed) throw new BridgeException("engine_closed","Engine is closed");
        if(engine==null) engine=Objects.requireNonNull(initializer.get());
        return engine;
    }
    @Override public synchronized void close() {
        closed=true;
        if(terminated) return;
        if(engine!=null) engine.close();
        terminated=true;engine=null;
    }
    public String request(String json) {
        try {
            Map<String,Object> r=Json.parseObject(json);
            if(Json.integer(r.get("protocol"))!=PROTOCOL) throw new BridgeException("protocol_mismatch","Expected protocol 1");
            String op=Json.requiredString(r,"op"); Object result;
            switch(op) {
                case "capabilities": keys(r,"protocol","op");result=engine().capabilities();break;
                // Trusted local API only. HostRouter independently rejects these for peers.
                case "diagnostics": keys(r,"protocol","op");result=EngineDiagnostics.read();break;
                case "clearDiagnostics": keys(r,"protocol","op");EngineDiagnostics.clear();result=Json.map("cleared",true);break;
                case "validateDeck": keys(r,"protocol","op","deck");result=engine().validateDeck(Json.object(r.get("deck")));break;
                case "create": keys(r,"protocol","op","configuration");result=engine().create(Json.object(r.get("configuration")));break;
                // Trusted local API only: the checkpoint holds every hidden zone. HostRouter never forwards it.
                case "restore": keys(r,"protocol","op","checkpoint");result=engine().restore(Json.object(r.get("checkpoint")));break;
                // Trusted local API only, like restore: saves happen only when the app asks (on leaving).
                case "checkpoint": keys(r,"protocol","op","matchId","waitMillis");
                    result=engine().checkpoint(Json.requiredString(r,"matchId"),waitMillis(r.get("waitMillis")));break;
                case "cancelCheckpoint": keys(r,"protocol","op","matchId");result=engine().cancelCheckpoint(Json.requiredString(r,"matchId"));break;
                case "poll": keys(r,"protocol","op","matchId","viewerId","after");result=engine().poll(Json.requiredString(r,"matchId"),Json.requiredString(r,"viewerId"),Json.integer(r.get("after")));break;
                case "respond": keys(r,"protocol","op","matchId","viewerId","command");result=engine().respond(Json.requiredString(r,"matchId"),Json.requiredString(r,"viewerId"),Json.object(r.get("command")));break;
                case "concede": keys(r,"protocol","op","matchId","viewerId");engine().concede(Json.requiredString(r,"matchId"),Json.requiredString(r,"viewerId"));result=Json.map("conceded",true);break;
                case "destroy": keys(r,"protocol","op","matchId");engine().destroy(Json.requiredString(r,"matchId"));result=Json.map("destroyed",true);break;
                case "shutdown": keys(r,"protocol","op");close();result=Json.map("closed",true);break;
                default: throw new BridgeException("unknown_operation","Unknown operation");
            }
            return Json.write(Json.map("protocol",PROTOCOL,"ok",true,"result",result));
        } catch(BridgeException e) {
            if("invalid_deck".equals(e.code())) EngineDiagnostics.captureIncident("deck-validation",e);
            return Json.write(Json.map("protocol",PROTOCOL,"ok",false,"error",e.envelope()));
        } catch(Exception | LinkageError e) {
            EngineDiagnostics.capture("engine-request",e);
            return Json.write(Json.map("protocol",PROTOCOL,"ok",false,"error",Json.map("code","engine_failure","message","Engine operation failed.")));
        }
    }
    private static long waitMillis(Object value) {
        long millis;
        try { millis=Json.integer(value); }
        catch(BridgeException invalid) { throw new BridgeException("invalid_request","waitMillis must be an integer"); }
        if(millis<0 || millis>MAX_CHECKPOINT_WAIT_MILLIS) throw new BridgeException("invalid_request","waitMillis must be 0 to "+MAX_CHECKPOINT_WAIT_MILLIS);
        return millis;
    }
    private static void keys(Map<String,Object> r,String... keys) {
        if(!r.keySet().equals(Set.of(keys))) throw new BridgeException("invalid_request","Unexpected or missing request fields");
    }
}
