package io.magicmobile.core;

import java.util.Map;

/** Implemented only by the real, embedded XMage adapter in production. */
public interface EnginePort extends AutoCloseable {
    Map<String,Object> create(Map<String,Object> configuration);
    Map<String,Object> poll(String matchId,String viewerId,long after);
    Map<String,Object> respond(String matchId,String authenticatedSeat,Map<String,Object> command);
    /** The authenticated seat concedes. Older/test backends must not pretend to support it. */
    default void concede(String matchId,String authenticatedSeat) {
        throw new BridgeException("concede_unavailable","This installed engine cannot concede a game");
    }
    /** Restores a solo match from a local checkpoint file. Backends without save/resume say so. */
    default Map<String,Object> restore(Map<String,Object> checkpoint) {
        throw new BridgeException("checkpoint_unavailable","This installed engine cannot restore saved games");
    }
    /**
     * Asks a solo match to save at the human's current or next priority decision, waiting up to
     * waitMillis (0 to 1000) for the write. Backends without on-demand saves say so.
     */
    default Map<String,Object> checkpoint(String matchId,long waitMillis) {
        throw new BridgeException("checkpoint_unavailable","This installed engine cannot save games on request");
    }
    /** Clears a save request that has not been written yet. */
    default Map<String,Object> cancelCheckpoint(String matchId) {
        throw new BridgeException("checkpoint_unavailable","This installed engine cannot save games on request");
    }
    void destroy(String matchId);
    Map<String,Object> capabilities();
    /** Trusted local-only operation. Older/test backends must not imply validation. */
    default Map<String,Object> validateDeck(Map<String,Object> deck) {
        throw new BridgeException("validation_unavailable","This installed engine does not support standalone deck validation");
    }
    @Override void close();
}
