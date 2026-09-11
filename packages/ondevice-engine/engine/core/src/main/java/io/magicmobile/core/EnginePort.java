package io.magicmobile.core;

import java.util.Map;

/** Implemented only by the real, embedded XMage adapter in production. */
public interface EnginePort extends AutoCloseable {
    Map<String,Object> create(Map<String,Object> configuration);
    Map<String,Object> poll(String matchId,String viewerId,long after);
    Map<String,Object> respond(String matchId,String authenticatedSeat,Map<String,Object> command);
    void destroy(String matchId);
    Map<String,Object> capabilities();
    @Override void close();
}
