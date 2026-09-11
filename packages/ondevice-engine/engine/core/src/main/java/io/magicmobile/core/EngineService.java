package io.magicmobile.core;

import java.util.Map;
import java.util.Set;
import java.util.Objects;

/** A trusted, in-process API. Do NOT expose it directly to unauthenticated peers. */
public final class EngineService {
    public static final int PROTOCOL=1;
    private final EnginePort engine;
    public EngineService(EnginePort engine) { this.engine=Objects.requireNonNull(engine); }
    public String request(String json) {
        try {
            Map<String,Object> r=Json.parseObject(json);
            if(Json.integer(r.get("protocol"))!=PROTOCOL) throw new BridgeException("protocol_mismatch","Expected protocol 1");
            String op=Json.requiredString(r,"op"); Object result;
            switch(op) {
                case "capabilities": keys(r,"protocol","op");result=engine.capabilities();break;
                case "create": keys(r,"protocol","op","configuration");result=engine.create(Json.object(r.get("configuration")));break;
                case "poll": keys(r,"protocol","op","matchId","viewerId","after");result=engine.poll(Json.requiredString(r,"matchId"),Json.requiredString(r,"viewerId"),Json.integer(r.get("after")));break;
                case "respond": keys(r,"protocol","op","matchId","viewerId","command");result=engine.respond(Json.requiredString(r,"matchId"),Json.requiredString(r,"viewerId"),Json.object(r.get("command")));break;
                case "destroy": keys(r,"protocol","op","matchId");engine.destroy(Json.requiredString(r,"matchId"));result=Json.map("destroyed",true);break;
                case "shutdown": keys(r,"protocol","op");engine.close();result=Json.map("closed",true);break;
                default: throw new BridgeException("unknown_operation","Unknown operation");
            }
            return Json.write(Json.map("protocol",PROTOCOL,"ok",true,"result",result));
        } catch(BridgeException e) {
            return Json.write(Json.map("protocol",PROTOCOL,"ok",false,"error",Json.map("code",e.code(),"message",e.getMessage())));
        } catch(Exception e) {
            // Diagnostics must stay on the host; do not leak card-bearing exception messages.
            return Json.write(Json.map("protocol",PROTOCOL,"ok",false,"error",Json.map("code","engine_failure","message","Engine operation failed.")));
        }
    }
    private static void keys(Map<String,Object> r,String... keys) {
        if(!r.keySet().equals(Set.of(keys))) throw new BridgeException("invalid_request","Unexpected or missing request fields");
    }
}
