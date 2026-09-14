package io.magicmobile.core;

import java.lang.reflect.Method;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicInteger;

/** Executes real mailbox threads with controlled sinks; not XMage or native iOS gameplay. */
public final class DeliveryShutdownTests {
    private static int checks;
    private static final List<String> failures=new ArrayList<>();
    private static void check(boolean value,String label) {checks++;if(!value)failures.add(label);}
    private static Map<String,Object> command(MatchMailbox box,String seat) {
        Map<String,Object> p=Json.object(box.poll(seat,0).get("prompt"));
        return Json.map("requestId",UUID.randomUUID().toString(),"promptId",p.get("promptId"),
            "promptRevision",p.get("revision"),"answer",Json.map("kind","boolean","value",true));
    }
    private static DecisionSpec question() {
        return new DecisionSpec("ASK",Json.map(),Set.of("boolean"),null,null,0,0,null);
    }
    private static void waitForExit(String match) throws Exception {
        long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(3);
        while(Thread.getAllStackTraces().keySet().stream().anyMatch(t->t.isAlive() && t.getName().equals("CALL mobile-"+match))) {
            if(System.nanoTime()>=deadline)throw new AssertionError("Mailbox thread did not terminate");
            Thread.sleep(2);
        }
    }
    private static boolean joined(MatchMailbox box,long millis) throws Exception {
        // The baseline has no quiescence API. Returning false exposes the missing guarantee
        // while retaining the independently reproducible cancellation/diagnostic assertions.
        Method method;
        try {method=MatchMailbox.class.getMethod("awaitDeliveryTermination",long.class);}
        catch(NoSuchMethodException absent) {return false;}
        return (Boolean)method.invoke(box,System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(millis));
    }
    public static void main(String[] args) throws Exception {
        cancellationPreservesFailure();boundedDrainAndQueuedCancellation();ordinaryClose();
        EngineDiagnostics.clear();
        for(String failure:failures)System.err.println("FAIL: "+failure);
        if(!failures.isEmpty())throw new AssertionError(failures.size()+" failures in "+checks+" delivery-shutdown assertions");
        System.out.println("PASS: "+checks+" delivery-shutdown assertions; actual mailbox threads, injected sinks; NOT XMage/iOS acceptance");
    }
    private static void cancellationPreservesFailure() throws Exception {
        EngineDiagnostics.clear();
        EngineDiagnostics.capture("original-native-failure",new UnsatisfiedLinkError("ORIGINAL-PRIVATE-CAUSE"));
        String id="interrupt-"+UUID.randomUUID();MatchMailbox box=new MatchMailbox(id,List.of("A"));
        CountDownLatch entered=new CountDownLatch(1);
        box.ask("A",question(),answer->{entered.countDown();new CountDownLatch(1).await();});
        box.submit("A",command(box,"A"));check(entered.await(2,TimeUnit.SECONDS),"delivery entered");
        box.close();waitForExit(id);
        String report=Json.write(EngineDiagnostics.read());
        check(report.contains("ORIGINAL-PRIVATE-CAUSE"),"normal shutdown must preserve the original native cause");
        check(!report.contains("InterruptedException"),"ordinary teardown is not a new engine failure");
        check("closed".equals(box.poll("A",0).get("phase")),"shutdown remains closed");
        check(box.poll("A",0).get("prompt")==null,"shutdown erases the prompt");
    }
    private static void boundedDrainAndQueuedCancellation() throws Exception {
        EngineDiagnostics.clear();
        MatchMailbox box=new MatchMailbox("drain-"+UUID.randomUUID(),List.of("A","B"));
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1);
        AtomicInteger queuedDeliveries=new AtomicInteger();
        try {
            box.ask("A",question(),answer->{
                entered.countDown();
                // Deliberately resists the shutdown interrupt. The native owner must retain
                // its runtime and report busy, not free underneath this callback.
                for(;;)try {release.await();break;}catch(InterruptedException expected) {}
            });
            box.submit("A",command(box,"A"));check(entered.await(2,TimeUnit.SECONDS),"blocked sink entered");
            box.ask("B",question(),answer->queuedDeliveries.incrementAndGet());
            box.submit("B",command(box,"B"));box.close();
            long started=System.nanoTime();
            check(!joined(box,30),"blocked worker cannot claim quiescence");
            check(System.nanoTime()-started<TimeUnit.SECONDS.toNanos(1),"shutdown wait respects deadline");
            check(queuedDeliveries.get()==0,"queued callback is cancelled on close");
            release.countDown();
            check(joined(box,2000),"drain confirms callback termination after release");
            check(queuedDeliveries.get()==0,"queued callback never runs after draining");
            check(EngineDiagnostics.read().get("report")==null,"successful drain creates no diagnostic failure");
        } finally {release.countDown();box.close();}
    }
    private static void ordinaryClose() throws Exception {
        MatchMailbox box=new MatchMailbox("unused-"+UUID.randomUUID(),List.of("A"));
        check(!joined(box,0),"an open mailbox is not quiescent for teardown");
        box.close();check(joined(box,2000),"unused mailbox closes without starting a thread");
        box.close();check(joined(box,0),"repeated closed quiescence check is idempotent");
    }
}
