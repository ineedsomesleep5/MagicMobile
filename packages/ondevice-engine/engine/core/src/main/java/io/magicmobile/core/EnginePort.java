package io.magicmobile.core;

import java.util.Map;

/** Implemented only by the real, embedded XMage adapter in production. */
public interface EnginePort extends AutoCloseable {
    Map<String,Object> create(Map<String,Object> configuration);
    Map<String,Object> poll(String matchId,String viewerId,long after);
    Map<String,Object> respond(String matchId,String authenticatedSeat,Map<String,Object> command);
    void destroy(String matchId);
    Map<String,Object> capabilities();
    /** Trusted local-only operation. Older/test backends must not imply validation. */
    default Map<String,Object> validateDeck(Map<String,Object> deck) {
        throw new BridgeException("validation_unavailable","This installed engine does not support standalone deck validation");
    }
    @Override void close();
}
