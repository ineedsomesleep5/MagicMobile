package io.magicmobile.core;

import java.util.*;
import java.util.concurrent.*;

/**
 * Thread boundary between a blocking XMage GAME thread and UI/network CALL threads.
 * Contains no Magic rules. Only viewer-scoped, already-projected snapshots enter it.
 * Responders never receive another player's prompt. No raw GameState is serialized.
 */
public final class MatchMailbox implements AutoCloseable {
    @FunctionalInterface public interface AnswerSink { void deliver(Map<String,Object> answer) throws Exception; }
    private static final int HISTORY_LIMIT=128, RECEIPT_LIMIT=1024;
    private final String matchId;
    private final Set<String> seats;
    private final Map<String,Map<String,Object>> snapshots=new LinkedHashMap<>();
    private final Map<String,Pending> pending=new HashMap<>();
    private final Map<String,ArrayDeque<Map<String,Object>>> history=new HashMap<>();
    private final Map<String,Long> evictedThrough=new HashMap<>();
    private final LinkedHashMap<String,Receipt> receipts=new LinkedHashMap<>();
    private final ExecutorService delivery;
    private long revision;
    private boolean closed;
    private String phase="starting";
    private Map<String,Object> failure;

    private static final class Pending {
        final String token=UUID.randomUUID().toString();
        final DecisionSpec spec; final AnswerSink sink; final long revision;
        boolean submitted;
        Pending(DecisionSpec spec,AnswerSink sink,long revision) { this.spec=spec;this.sink=sink;this.revision=revision; }
        Map<String,Object> json() {
            Map<String,Object> out=new LinkedHashMap<>(spec.describe());
            out.put("promptId",token);out.put("revision",revision);out.put("submitted",submitted);return out;
        }
    }
    private static final class Receipt {
        final String fingerprint; final Map<String,Object> result;
        Receipt(String f,Map<String,Object> r) { fingerprint=f;result=r; }
    }
    public MatchMailbox(String matchId,Collection<String> seats) {
        this.matchId=Objects.requireNonNull(matchId);
        this.seats=Collections.unmodifiableSet(new LinkedHashSet<>(seats));
        if(this.seats.size()!=seats.size() || this.seats.size()<1 || this.seats.size()>4) throw new IllegalArgumentException("Need 1–4 unique recipient seats");
        for(String seat:seats) {
            if(seat==null || seat.isEmpty() || seat.length()>128) throw new IllegalArgumentException("Invalid seat");
            history.put(seat,new ArrayDeque<>());evictedThrough.put(seat,0L);
        }
        delivery=Executors.newSingleThreadExecutor(r -> {
            Thread t=new Thread(r,"CALL mobile-"+matchId);t.setDaemon(true);return t;
        });
    }
    public synchronized void publishSnapshots(Map<String,Map<String,Object>> views) {
        checkOpen();
        if(!views.keySet().equals(seats)) throw new BridgeException("projection_error","Every seat needs its own projection");
        // Validate the entire update before publishing any part.
        Map<String,Map<String,Object>> frozen=new LinkedHashMap<>();
        for(String seat:seats) frozen.put(seat,Json.object(Json.freeze(views.get(seat))));
        snapshots.clear();snapshots.putAll(frozen);revision++;phase="running";
        for(String seat:seats) record(seat,"snapshot",Json.map());
    }
    public synchronized String ask(String seat,DecisionSpec spec,AnswerSink sink) {
        checkOpen();checkSeat(seat);revision++;
        Pending p=new Pending(spec,Objects.requireNonNull(sink),revision);pending.put(seat,p);
        record(seat,"prompt",Json.map("promptId",p.token)); // full current prompt is returned once by poll
        return p.token;
    }
    /** Trusted host transport must supply authenticatedSeat, never trust an actor field from a peer. */
    public synchronized Map<String,Object> submit(String authenticatedSeat,Map<String,Object> command) {
        checkOpen();checkSeat(authenticatedSeat);
        if(!command.keySet().equals(Set.of("requestId","promptId","promptRevision","answer")))
            throw new BridgeException("invalid_command","Unexpected/missing fields; actor identity comes from transport");
        String requestId=Json.requiredString(command,"requestId");
        try { UUID.fromString(requestId); } catch(IllegalArgumentException e) { throw new BridgeException("invalid_command","requestId must be a UUID"); }
        String key=authenticatedSeat+":"+requestId;
        String fingerprint=Json.write(command);
        Receipt previous=receipts.get(key);
        if(previous!=null) {
            if(!previous.fingerprint.equals(fingerprint)) throw new BridgeException("request_id_reused","requestId was reused with different content");
            return previous.result;
        }
        Pending p=pending.get(authenticatedSeat);
        if(p==null || !p.token.equals(Json.requiredString(command,"promptId")) || p.revision!=Json.integer(command.get("promptRevision")))
            throw new BridgeException("stale_prompt","Prompt changed; use the latest exact prompt metadata");
        if(p.submitted) throw new BridgeException("response_pending","An answer is already queued for this prompt");
        Map<String,Object> answer=p.spec.validate(Json.object(command.get("answer")));
        Map<String,Object> result=Json.object(Json.freeze(Json.map("status","queued","requestId",requestId,"promptId",p.token,"revision",revision)));
        p.submitted=true;
        receipts.put(key,new Receipt(fingerprint,result));
        while(receipts.size()>RECEIPT_LIMIT) receipts.remove(receipts.keySet().iterator().next());
        delivery.execute(() -> {
            synchronized(MatchMailbox.this) {
                // A new engine decision or match closure invalidates an undelivered answer.
                if(closed || pending.get(authenticatedSeat)!=p) return;
            }
            try { p.sink.deliver(answer); }
            catch(Throwable ex) {
                synchronized(MatchMailbox.this) {
                    // A close interrupt is expected. Never replace a game's original native
                    // failure with a secondary callback exception while disposing that game.
                    if(closed || phase.equals("ended") || phase.equals("failed")) return;
                    EngineDiagnostics.capture("response-delivery",ex);
                    fail("response_delivery_failed","XMage could not consume the queued response. Inspect the local engine log.");
                }
            }
        });
        return result;
    }
    public synchronized Map<String,Object> poll(String seat,long after) {
        checkSeat(seat);
        if(after<0 || after>revision) throw new BridgeException("invalid_cursor","Cursor is outside this match revision range");
        List<Object> events=new ArrayList<>();ArrayDeque<Map<String,Object>> ring=history.get(seat);
        boolean gap=after<evictedThrough.get(seat);
        for(Map<String,Object> event:ring) if(Json.integer(event.get("revision"))>after) events.add(event);
        Pending p=pending.get(seat);
        return Json.map("matchId",matchId,"viewerId",seat,"revision",revision,"phase",phase,
                "resyncRequired",gap,"snapshot",snapshots.get(seat),"prompt",p==null?null:p.json(),
                "events",events,"failure",failure);
    }
    public synchronized void finish() {
        if(closed || phase.equals("ended") || phase.equals("failed")) return;revision++;phase="ended";pending.clear();
        for(String seat:seats) record(seat,"ended",Json.map());
    }
    public synchronized void fail(String code,String message) {
        if(closed || phase.equals("ended") || phase.equals("failed")) return;revision++;phase="failed";pending.clear();
        failure=Json.map("code",code,"message",message);
        for(String seat:seats) record(seat,"error",failure);
    }
    /** Called by the GAME thread after it takes the response, before it mutates state. */
    public synchronized void consumed(String seat) {
        checkSeat(seat);
        Pending p=pending.get(seat);
        if(p!=null && p.submitted) {
            pending.remove(seat);revision++;
            record(seat,"prompt_consumed",Json.map("promptId",p.token));
        }
    }
    /** Private informational events never replace an outstanding question. */
    public synchronized void inform(String seat,Map<String,Object> message) {
        checkOpen();checkSeat(seat);revision++;record(seat,"message",message);
    }
    public synchronized long revision() { return revision; }
    private void record(String seat,String kind,Map<String,Object> body) {
        Map<String,Object> event=Json.object(Json.freeze(Json.map("revision",revision,"kind",kind,"body",body)));
        ArrayDeque<Map<String,Object>> ring=history.get(seat);ring.addLast(event);
        while(ring.size()>HISTORY_LIMIT) evictedThrough.put(seat,Json.integer(ring.removeFirst().get("revision")));
    }
    private void checkSeat(String seat) {
        if(!seats.contains(seat)) throw new BridgeException("unauthorized_seat","Unknown or unbound player seat");
    }
    private void checkOpen() {
        if(closed || phase.equals("ended") || phase.equals("failed")) throw new BridgeException("match_unavailable","Match is "+phase);
    }
    /**
     * Wait outside the mailbox monitor: a finishing callback may need that monitor.
     * The native owner must retain the isolate until GAME, AI and CALL workers stop.
     * The absolute deadline is shared with the other worker-shutdown checks.
     */
    public boolean awaitDeliveryTermination(long deadlineNanos) throws InterruptedException {
        return delivery.awaitTermination(Math.max(0,deadlineNanos-System.nanoTime()),TimeUnit.NANOSECONDS);
    }
    @Override public synchronized void close() {
        if(closed) return;closed=true;phase="closed";pending.clear();revision++;delivery.shutdownNow();
        // Release hidden information when a match is discarded.
        snapshots.clear();history.values().forEach(ArrayDeque::clear);receipts.clear();
    }
}
