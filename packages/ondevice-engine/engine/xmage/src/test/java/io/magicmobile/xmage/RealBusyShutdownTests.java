package io.magicmobile.xmage;

import io.magicmobile.core.BridgeException;
import io.magicmobile.core.Json;
import io.magicmobile.core.EngineDiagnostics;
import io.magicmobile.core.DecisionSpec;
import io.magicmobile.core.MatchMailbox;
import mage.game.Game;
import mage.game.events.Listener;
import mage.game.events.PlayerQueryEvent;

import java.lang.reflect.Field;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Actual XmageEngine game worker with a TEST-ONLY injected uninterruptible listener stall.
 * This is NOT evidence of cancellation during a genuine complex rules effect or native/iOS execution.
 * From the package root, using JDK 21 and the current runtime-classpath.txt:
 * javac -J-Xmx384m --release 17 -cp "$BUSY_BASE_CP" -d build/test-busy \
 *   engine/xmage/src/main/java/io/magicmobile/xmage/XmageEngine.java \
 *   engine/xmage/src/test/java/io/magicmobile/xmage/RealBusyShutdownTests.java
 * java -Xmx384m -cp "build/test-busy:$BUSY_BASE_CP" io.magicmobile.xmage.RealBusyShutdownTests build/match.json
 */
public final class RealBusyShutdownTests {
    private static final long CALL_SECONDS=6,START_SECONDS=30;

    public static void main(String[] args) throws Exception {
        Path input=Path.of(args.length==0?"build/match.json":args[0]).toAbsolutePath();
        Map<String,Object> configuration=Json.parseObject(Files.readString(input));
        System.out.println("Scope: real XMage JVM worker with TEST-ONLY injected listener stall; NOT genuine complex-effect cancellation proof; NOT native/iOS");
        System.out.println("Java: "+System.getProperty("java.version")+"; max heap MiB: "+Runtime.getRuntime().maxMemory()/1024/1024);
        System.out.println("Configuration: "+input);
        System.out.println("XmageEngine classes: "+XmageEngine.class.getProtectionDomain().getCodeSource().getLocation());
        destroyRetry(configuration);
        closeRetry(configuration);
        workerDiagnostics(configuration);
        deliveryRetry(configuration);
        System.out.println("RealBusyShutdownTests: 4 passed, 0 failed");
    }

    /** Stall the actual CALL executor, not the GAME worker. No production rules are replaced. */
    private static void deliveryRetry(Map<String,Object> configuration) throws Exception {
        try(Rig r=new Rig(configuration)) {
            String id=r.start();r.prompt(id);
            Running running=r.started.get(0);
            MatchMailbox mailbox=(MatchMailbox)field(running.value,"mailbox");
            String seat=r.seatIds.get(0);
            CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
            AtomicBoolean expired=new AtomicBoolean();
            try {
                mailbox.ask(seat,new DecisionSpec("ASK",Json.map(),Set.of("boolean"),null,null,0,0,null),answer->{
                    entered.countDown();long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(20);
                    while(release.getCount()!=0) {
                        long remaining=deadline-System.nanoTime();
                        if(remaining<=0) {expired.set(true);return;}
                        try {release.await(remaining,TimeUnit.NANOSECONDS);}
                        catch(InterruptedException ignored) { /* test-only bounded CALL barrier */ }
                    }
                });
                Map<String,Object> prompt=Json.object(mailbox.poll(seat,0).get("prompt"));
                r.engine.respond(id,seat,Json.map("requestId",UUID.randomUUID().toString(),
                    "promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),
                    "answer",Json.map("kind","boolean","value",true)));
                check(entered.await(5,TimeUnit.SECONDS),"actual mailbox delivery entered barrier");
                r.expect("engine_busy_shutdown",()->r.engine.destroy(id));
                check(running.worker.isTerminated(),"GAME worker stopped while CALL executor is still held");
                check(r.lookup(id)==running.value,"busy CALL executor retains exact match for cleanup retry");
                check(!expired.get(),"CALL barrier has not reached its emergency deadline");
            } finally {
                release.countDown();mailbox.close();
                check(mailbox.awaitDeliveryTermination(System.nanoTime()+TimeUnit.SECONDS.toNanos(5)),"CALL executor stopped after release");
            }
            r.call(()->r.engine.destroy(id));
            r.expect("unknown_match",()->r.engine.poll(id,seat,0));
            System.out.println("PASS delivery: real CALL worker stalls shutdown; retained match drains and closes on retry (injected stall, NOT native/iOS)");
        }
    }

    private static void workerDiagnostics(Map<String,Object> configuration) throws Exception {
        EngineDiagnostics.clear();
        try(Rig r=new Rig(configuration)) {
            String id=r.start();
            Map<String,Object> pending=r.prompt(id),prompt=Json.object(pending.get("prompt"));
            List<Object> candidates=Json.array(Json.object(prompt.get("payload")).get("candidates"));
            r.started.get(0).game.addPlayerQueryEventListener(event->{
                if(event.getQueryType()!=PlayerQueryEvent.QueryType.PERSONAL_MESSAGE)
                    throw new IllegalStateException("TEST-ONLY private worker failure",new IllegalArgumentException("TEST-ONLY cause"));
            });
            r.engine.respond(id,Json.requiredString(pending,"seat"),Json.map("requestId",UUID.randomUUID().toString(),
                "promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),
                "answer",Json.map("kind","uuid","value",candidates.get(0))));
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            Map<String,Object> poll;
            do {
                poll=r.engine.poll(id,r.seatIds.get(0),0);
                if("failed".equals(poll.get("phase"))) break;
                Thread.sleep(10);
            } while(System.nanoTime()<deadline);
            check("failed".equals(poll.get("phase")),"injected real worker failure reaches failed poll");
            for(String seat:r.seatIds)
                check(!Json.write(r.engine.poll(id,seat,0)).contains("TEST-ONLY"),"private worker exception excluded from every seat");
            String report=Json.write(EngineDiagnostics.read());
            check(report.contains("game-worker") && report.contains("IllegalStateException")
                && report.contains("TEST-ONLY cause") && report.contains("RealBusyShutdownTests"),"actual worker catch retains cause and call site locally");
            System.out.println("PASS diagnostics: real worker injection captured locally; all viewer polls sanitized (NOT the reported native bug)");
        } finally { EngineDiagnostics.clear(); }
    }

    private static void destroyRetry(Map<String,Object> configuration) throws Exception {
        try(Rig r=new Rig(configuration)) {
            String id=r.start();
            Running running=r.stallAfterFirstPrompt(id);
            r.busy(()->r.engine.destroy(id),running,"destroy");
            r.expect("match_limit",()->r.engine.create(configuration));
            check(r.lookup(id)==running.value,"failed destroy retains the same Running instance");
            r.release(running);
            r.call(()->r.engine.destroy(id));
            r.expect("unknown_match",()->r.engine.poll(id,r.seatIds.get(0),0));
            String next=r.start();
            check(!next.equals(id),"replacement is a new real game");
            r.prompt(next); // a real new worker initializes and reaches a playable decision
            r.call(()->r.engine.destroy(next));
            r.expect("unknown_match",()->r.engine.poll(next,r.seatIds.get(0),0));
            System.out.println("PASS destroy: engine_busy_shutdown, live cancelled worker retained, match_limit, release, retry destroy, new real match prompt");
        }
    }

    private static void closeRetry(Map<String,Object> configuration) throws Exception {
        try(Rig r=new Rig(configuration)) {
            String id=r.start();
            Running running=r.stallAfterFirstPrompt(id);
            r.busy(r.engine::close,running,"close");
            check(r.lookup(id)==running.value,"failed close retains the same Running instance");
            r.expect("engine_closed",()->r.engine.create(configuration));
            r.release(running);
            r.call(r.engine::close);
            r.expect("unknown_match",()->r.engine.poll(id,r.seatIds.get(0),0));
            r.expect("engine_closed",()->r.engine.create(configuration));
            r.call(r.engine::close); // successful close is idempotent, not a reopen operation
            System.out.println("PASS close: engine_busy_shutdown, live cancelled worker retained, engine_closed, release, retry close, match removed, idempotent close");
        }
    }

    private static final class Stall implements Listener<PlayerQueryEvent> {
        final CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),exited=new CountDownLatch(1);
        final AtomicBoolean armed=new AtomicBoolean(true);
        final AtomicInteger interruptions=new AtomicInteger();
        volatile Thread thread;
        volatile boolean expired;
        volatile PlayerQueryEvent.QueryType queryType;
        @Override public void event(PlayerQueryEvent event) {
            if(event.getQueryType()==PlayerQueryEvent.QueryType.PERSONAL_MESSAGE || !armed.compareAndSet(true,false))return;
            thread=Thread.currentThread();queryType=event.getQueryType();
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(30);
            entered.countDown();
            try {
                while(release.getCount()!=0) {
                    long remaining=deadline-System.nanoTime();
                    if(remaining<=0){expired=true;return;} // emergency fail-safe, never an infinite stall
                    try {release.await(remaining,TimeUnit.NANOSECONDS);}
                    catch(InterruptedException ignored) {interruptions.incrementAndGet();}
                }
            } finally {
                // Preserve cancellation for the real engine once the injected stall ends.
                if(interruptions.get()!=0)Thread.currentThread().interrupt();
                exited.countDown();
            }
        }
    }

    private static final class Running {
        final Object value;
        final Game game;
        final ExecutorService worker;
        final Future<?> task;
        Running(Object value) throws Exception {
            this.value=value;game=(Game)field(value,"game");
            worker=(ExecutorService)field(value,"worker");task=(Future<?>)field(value,"task");
        }
    }

    private static final class Rig implements AutoCloseable {
        final XmageEngine engine=new XmageEngine("real-busy-shutdown-test");
        final Map<String,Object> configuration;
        final List<String> seatIds=new ArrayList<>();
        final List<Running> started=new ArrayList<>();
        final Stall stall=new Stall();
        final ExecutorService calls=Executors.newSingleThreadExecutor(r->{Thread t=new Thread(r,"CALL busy-shutdown-test");t.setDaemon(true);return t;});
        Rig(Map<String,Object> configuration) {
            this.configuration=configuration;
            for(Object seat:Json.array(configuration.get("seats")))seatIds.add(Json.requiredString(Json.object(seat),"seatId"));
        }
        String start() throws Exception {
            // Startup also has an external deadline; no production worker or Future is replaced.
            Future<Map<String,Object>> created=calls.submit(()->engine.create(configuration));
            String id=Json.requiredString(await(created,START_SECONDS),"matchId");
            started.add(new Running(lookup(id)));return id;
        }
        Object lookup(String id) throws Exception {
            synchronized(engine) {return ((Map<?,?>)field(engine,"matches")).get(id);}
        }
        Map<String,Object> prompt(String id) throws Exception {
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(START_SECONDS);
            while(System.nanoTime()<deadline) {
                for(String seat:seatIds) {
                    Map<String,Object> view=engine.poll(id,seat,0);
                    check(!Set.of("failed","closed","ended").contains(view.get("phase")),"real match unexpectedly stopped: "+view.get("failure"));
                    if(view.get("prompt")!=null)return Json.map("seat",seat,"prompt",view.get("prompt"));
                }
                Thread.sleep(10);
            }
            throw new AssertionError("No real prompt within startup deadline");
        }
        Running stallAfterFirstPrompt(String id) throws Exception {
            Map<String,Object> pending=prompt(id),prompt=Json.object(pending.get("prompt"));
            check(Json.array(prompt.get("responseTypes")).contains("uuid"),"expected real starting-player UUID decision");
            List<Object> candidates=Json.array(Json.object(prompt.get("payload")).get("candidates"));
            check(!candidates.isEmpty(),"starting-player candidates exist");
            Running running=started.get(started.size()-1);
            // Pinned upstream EventDispatcher uses CopyOnWriteArrayList. Listener registration
            // is safe even if the first dispatch is finishing; no game state is mutated here.
            running.game.addPlayerQueryEventListener(stall);
            engine.respond(id,Json.requiredString(pending,"seat"),Json.map("requestId",UUID.randomUUID().toString(),
                "promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),
                "answer",Json.map("kind","uuid","value",candidates.get(0))));
            check(stall.entered.await(10,TimeUnit.SECONDS),"real worker reached injected listener barrier");
            check(stall.thread!=Thread.currentThread() && stall.thread.getName().equals("GAME mobile-"+id),"barrier runs on actual game worker");
            check(Arrays.stream(stall.thread.getStackTrace()).anyMatch(frame->frame.getClassName().equals(XmageEngine.class.getName()+"$Running")
                && frame.getMethodName().startsWith("lambda$start$")),"barrier is inside production Running.start game task");
            System.out.println("Injected stall: "+stall.queryType+" on "+stall.thread.getName());
            return running;
        }
        void busy(Action action,Running running,String operation) throws Exception {
            long before=System.nanoTime();expect("engine_busy_shutdown",action);
            long elapsed=TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-before);
            check(elapsed>=1800 && elapsed<CALL_SECONDS*1000,"shutdown performs its bounded worker wait: "+elapsed+"ms");
            check(stall.thread.isAlive() && !running.worker.isTerminated(),"cancelled worker is still alive, not disposed");
            check(running.task.isCancelled(),"Future cancellation alone does not imply worker termination");
            check(stall.interruptions.get()>0 && !stall.expired && stall.release.getCount()==1,"test barrier absorbed cancellation and remains held");
            System.out.println("Observed "+operation+": engine_busy_shutdown after "+elapsed+"ms; task cancelled, worker still alive");
        }
        void release(Running running) throws Exception {
            stall.release.countDown();
            check(stall.exited.await(3,TimeUnit.SECONDS),"listener releases promptly");
            check(running.worker.awaitTermination(5,TimeUnit.SECONDS),"actual game executor terminates after release");
            stall.thread.join(2000);
            check(!stall.thread.isAlive() && !stall.expired,"actual worker thread exited without barrier timeout");
        }
        void call(Action action) throws Exception {
            await(calls.submit(()->{action.run();return null;}),CALL_SECONDS);
        }
        void expect(String code,Action action) throws Exception {
            try {call(action);}catch(BridgeException e) {check(code.equals(e.code()),"expected "+code+", got "+e.code());return;}
            throw new AssertionError("Expected "+code);
        }
        @Override public void close() throws Exception {
            stall.release.countDown(); // always unblock, including assertion/startup/timeout failures
            try {
                try {call(engine::close);}
                catch(BridgeException e) {if(!"engine_busy_shutdown".equals(e.code()))throw e;}
                for(Running running:started)check(running.worker.awaitTermination(5,TimeUnit.SECONDS),"finally cleanup terminates real worker");
                call(engine::close);
            } finally {
                calls.shutdownNow();check(calls.awaitTermination(3,TimeUnit.SECONDS),"test CALL executor terminates");
            }
        }
    }

    private interface Action {void run() throws Exception;}
    private static Object field(Object owner,String name) throws Exception {
        Field field=owner.getClass().getDeclaredField(name);field.setAccessible(true);return field.get(owner);
    }
    private static <T> T await(Future<T> result,long seconds) throws Exception {
        try {return result.get(seconds,TimeUnit.SECONDS);}
        catch(ExecutionException e) {
            if(e.getCause() instanceof Exception)throw (Exception)e.getCause();
            if(e.getCause() instanceof Error)throw (Error)e.getCause();
            throw new AssertionError(e.getCause());
        } finally {if(!result.isDone())result.cancel(true);}
    }
    private static void check(boolean condition,String message) {if(!condition)throw new AssertionError(message);}
}
