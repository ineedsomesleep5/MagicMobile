package io.magicmobile.core;

import java.util.*;
import java.util.concurrent.*;

/** Fault-injection tests of the actual API/mailbox; NOT XMage rules or native execution. */
public final class FailureBoundaryTests {
    private static int checks;
    private static final List<String> failures=new ArrayList<>();
    private static void check(boolean value,String name) {checks++;if(!value)failures.add(name);}
    private static final String CREATE="{\"protocol\":1,\"op\":\"create\",\"configuration\":{}}";
    private static final String DIAGNOSTICS="{\"protocol\":1,\"op\":\"diagnostics\"}";
    private static final String CLEAR="{\"protocol\":1,\"op\":\"clearDiagnostics\"}";
    private static final class FaultPort implements EnginePort {
        private final Error fault;
        FaultPort(Error fault) {this.fault=fault;}
        public Map<String,Object> create(Map<String,Object> c) {throw fault;}
        public Map<String,Object> poll(String a,String b,long c) {return Json.map();}
        public Map<String,Object> respond(String a,String b,Map<String,Object> c) {return Json.map();}
        public void destroy(String id) {}
        public Map<String,Object> capabilities() {return Json.map("fixture",true);}
        public void close() {}
    }
    public static void main(String[] args) throws Exception {
        checks=0;failures.clear();
        requestErrors();deliveryErrors();lazyInitialization();retryableShutdown();closedService();deliveryShutdown();
        EngineDiagnostics.clear();
        for(String failure:failures) System.err.println("FAIL: "+failure);
        if(!failures.isEmpty()) throw new AssertionError(failures.size()+" failures in "+checks+" boundary checks");
        System.out.println("PASS: "+checks+" failure-boundary assertions; injected faults, NOT native/iOS acceptance");
    }
    private static void requestErrors() {
        for(Error error:List.of(new UnsatisfiedLinkError("PRIVATE-native-symbol"),
                new NoClassDefFoundError("PRIVATE-missing-class"),
                new ExceptionInInitializerError(new IllegalStateException("PRIVATE-initializer")))) {
            EngineDiagnostics.clear();EngineService service=new EngineService(new FaultPort(error));
            String result;
            try {result=service.request(CREATE);}
            catch(Throwable escaped) {check(false,"request contains "+error.getClass().getSimpleName());continue;}
            Map<String,Object> envelope=Json.parseObject(result);
            check(Boolean.FALSE.equals(envelope.get("ok")),"request error remains a failure");
            check("engine_failure".equals(Json.object(envelope.get("error")).get("code")),"stable request error code");
            check(!result.contains("PRIVATE-") && !result.contains(error.getClass().getSimpleName()),"public reply redacts failure details");
            String report=service.request(DIAGNOSTICS);
            check(report.contains("PRIVATE-") && report.contains(error.getClass().getSimpleName()),"local report preserves linkage cause");
            service.request(CLEAR);
            check(service.request(DIAGNOSTICS).contains("\"report\":null"),"clear removes linkage report");
        }
    }
    private static void deliveryErrors() throws Exception {
        for(Error error:List.of(new UnsatisfiedLinkError("PRIVATE-delivery-symbol"),
                new AssertionError("PRIVATE-delivery-assertion"))) {
            EngineDiagnostics.clear();
            try(MatchMailbox mailbox=new MatchMailbox("failure-fixture",List.of("A","B"))) {
                CountDownLatch attempted=new CountDownLatch(1);
                mailbox.publishSnapshots(Map.of("A",Json.map("hand",List.of("A-SECRET")),"B",Json.map("hand",List.of("B-SECRET"))));
                mailbox.ask("A",new DecisionSpec("ASK",Json.map(),Set.of("boolean"),null,null,0,0,null),answer->{
                    Thread.currentThread().setUncaughtExceptionHandler((thread,failure)->{});
                    attempted.countDown();throw error;
                });
                Map<String,Object> prompt=Json.object(mailbox.poll("A",0).get("prompt"));
                mailbox.submit("A",Json.map("requestId",UUID.randomUUID().toString(),
                        "promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),
                        "answer",Json.map("kind","boolean","value",true)));
                check(attempted.await(2,TimeUnit.SECONDS),"delivery fixture entered actual executor");
                long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(2);
                while(!"failed".equals(mailbox.poll("A",0).get("phase")) && System.nanoTime()<deadline)Thread.sleep(2);
                for(String seat:List.of("A","B")) {
                    Map<String,Object> poll=mailbox.poll(seat,0);String wire=Json.write(poll);
                    check("failed".equals(poll.get("phase")),"delivery "+error.getClass().getSimpleName()+" fails match for "+seat);
                    check(poll.get("prompt")==null,"failed delivery clears pending choice for "+seat);
                    check(!wire.contains("PRIVATE-") && !wire.contains(error.getClass().getSimpleName()),"delivery error stays private for "+seat);
                    check(!wire.contains(seat.equals("A")?"B-SECRET":"A-SECRET"),"failure poll retains seat privacy for "+seat);
                }
                check(Json.write(EngineDiagnostics.read()).contains("PRIVATE-"),"delivery root cause captured locally");
            }
        }
    }
    private static void lazyInitialization() {
        EngineDiagnostics.clear();
        java.util.concurrent.atomic.AtomicInteger attempts=new java.util.concurrent.atomic.AtomicInteger();
        EngineService failed=EngineService.lazy(()->{
            attempts.incrementAndGet();throw new UnsatisfiedLinkError("PRIVATE-bootstrap");
        });
        check(failed.request(DIAGNOSTICS).contains("\"report\":null"),"diagnostics available before bootstrap");
        check(failed.request("{\"protocol\":1,\"op\":\"diagnostics\",\"viewerId\":\"A\"}").contains("invalid_request"),"lazy service retains diagnostic key validation");
        check(failed.request("{\"protocol\":1,\"op\":\"unknown\"}").contains("unknown_operation"),"unknown operation does not bootstrap");
        check(attempts.get()==0,"diagnostics and rejected requests do not initialize engine");
        String reply=failed.request(CREATE);
        check(reply.contains("engine_failure") && !reply.contains("PRIVATE-"),"bootstrap failure is contained and sanitized");
        check(attempts.get()==1,"one failed bootstrap attempt");
        check(failed.request(DIAGNOSTICS).contains("PRIVATE-bootstrap"),"failed bootstrap report remains readable");
        failed.request(CLEAR);
        check(failed.request(DIAGNOSTICS).contains("\"report\":null"),"bootstrap report can be deleted without retrying engine");
        check(attempts.get()==1,"reading/deleting bootstrap report never retries broken initialization");
        failed.close();failed.close();
        check(attempts.get()==1,"closing failed engine does not initialize it");
        check(failed.request(CREATE).contains("engine_closed"),"closed lazy service cannot resurrect engine");
        check(attempts.get()==1,"closed create did not invoke factory");
        java.util.concurrent.atomic.AtomicInteger initialized=new java.util.concurrent.atomic.AtomicInteger();
        EngineService healthy=EngineService.lazy(()->{initialized.incrementAndGet();return new FaultPort(new AssertionError("unused"));});
        String capabilities="{\"protocol\":1,\"op\":\"capabilities\"}";
        check(healthy.request(capabilities).contains("\"ok\":true"),"healthy lazy engine initializes normally");
        healthy.request(capabilities);
        check(initialized.get()==1,"healthy engine initialized once");
        healthy.close();
        EngineService unopened=EngineService.lazy(()->{throw new AssertionError("must not bootstrap on shutdown");});
        check(unopened.request("{\"protocol\":1,\"op\":\"shutdown\"}").contains("\"ok\":true"),"protocol shutdown does not bootstrap unused engine");
        check(unopened.request(CREATE).contains("engine_closed"),"protocol shutdown closes unopened service");
    }
    private static void retryableShutdown() {
        java.util.concurrent.atomic.AtomicInteger attempts=new java.util.concurrent.atomic.AtomicInteger();
        EnginePort port=new EnginePort() {
            public Map<String,Object> create(Map<String,Object> c) {return Json.map();}
            public Map<String,Object> poll(String a,String b,long c) {return Json.map();}
            public Map<String,Object> respond(String a,String b,Map<String,Object> c) {return Json.map();}
            public void destroy(String id) {}
            public Map<String,Object> capabilities() {return Json.map();}
            public void close() {if(attempts.incrementAndGet()==1)throw new BridgeException("engine_busy_shutdown","Retry");}
        };
        EngineService service=new EngineService(port);
        String shutdown="{\"protocol\":1,\"op\":\"shutdown\"}";
        check(service.request(shutdown).contains("engine_busy_shutdown"),"busy shutdown not falsely successful");
        check(service.request(shutdown).contains("\"ok\":true"),"shutdown retries same retained engine");
        check(attempts.get()==2,"retained engine actually retried");
    }

    private static void closedService() {
        java.util.concurrent.atomic.AtomicInteger closes=new java.util.concurrent.atomic.AtomicInteger();
        java.util.concurrent.atomic.AtomicInteger operations=new java.util.concurrent.atomic.AtomicInteger();
        EnginePort port=new EnginePort() {
            public Map<String,Object> create(Map<String,Object> c) {operations.incrementAndGet();return Json.map();}
            public Map<String,Object> poll(String a,String b,long c) {operations.incrementAndGet();return Json.map();}
            public Map<String,Object> respond(String a,String b,Map<String,Object> c) {operations.incrementAndGet();return Json.map();}
            public void destroy(String id) {operations.incrementAndGet();}
            public Map<String,Object> capabilities() {operations.incrementAndGet();return Json.map();}
            public void close() {if(closes.incrementAndGet()==1)throw new BridgeException("engine_busy_shutdown","Retry");}
        };
        EngineService service=new EngineService(port);
        String shutdown="{\"protocol\":1,\"op\":\"shutdown\"}";
        String capabilities="{\"protocol\":1,\"op\":\"capabilities\"}";
        check(service.request(shutdown).contains("engine_busy_shutdown"),"busy close begins durable shutdown");
        check(service.request(CREATE).contains("engine_closed"),"no new create while shutdown is pending");
        check(service.request(capabilities).contains("engine_closed"),"closed reference is not reported usable");
        check(operations.get()==0,"pending shutdown rejects operations before invoking port");
        check(service.request(DIAGNOSTICS).contains("\"ok\":true"),"diagnostics still available during pending shutdown");
        check(service.request(shutdown).contains("\"ok\":true"),"retained port finishes shutdown on retry");
        check(service.request(CREATE).contains("engine_closed"),"confirmed shutdown rejects new work");
        check(service.request(capabilities).contains("engine_closed"),"confirmed shutdown rejects capability access");
        check(service.request(shutdown).contains("\"ok\":true"),"repeated confirmed shutdown remains successful");
        service.close();
        check(closes.get()==2,"successful shutdown does not close the underlying port twice");
        check(operations.get()==0,"closed port never receives later operations");
    }

    private static void deliveryShutdown() throws Exception {
        MatchMailbox mailbox=new MatchMailbox("delivery-shutdown-fixture",List.of("A"));
        CountDownLatch entered=new CountDownLatch(1),release=new CountDownLatch(1),exited=new CountDownLatch(1);
        java.util.concurrent.atomic.AtomicBoolean expired=new java.util.concurrent.atomic.AtomicBoolean();
        mailbox.ask("A",new DecisionSpec("ASK",Json.map(),Set.of("boolean"),null,null,0,0,null),answer->{
            entered.countDown();
            long deadline=System.nanoTime()+TimeUnit.SECONDS.toNanos(10);
            try {
                while(release.getCount()!=0) {
                    long remaining=deadline-System.nanoTime();
                    if(remaining<=0) {expired.set(true);return;}
                    try {release.await(remaining,TimeUnit.NANOSECONDS);}
                    catch(InterruptedException ignored) { /* test-only uninterruptible delivery */ }
                }
                // Exercise a monitor-taking failure callback while teardown waits outside the monitor.
                throw new AssertionError("PRIVATE-delivery-during-close");
            } finally {exited.countDown();}
        });
        Map<String,Object> prompt=Json.object(mailbox.poll("A",0).get("prompt"));
        try {
            mailbox.submit("A",Json.map("requestId",UUID.randomUUID().toString(),
                "promptId",prompt.get("promptId"),"promptRevision",prompt.get("revision"),
                "answer",Json.map("kind","boolean","value",true)));
            check(entered.await(2,TimeUnit.SECONDS),"actual delivery executor entered shutdown barrier");
            mailbox.close();
            check(!mailbox.awaitDeliveryTermination(System.nanoTime()+TimeUnit.MILLISECONDS.toNanos(50)),"interruption alone is not delivery termination");
            check("closed".equals(mailbox.poll("A",0).get("phase")),"closed mailbox stays unavailable during delivery drain");
            check(mailbox.poll("A",0).get("prompt")==null,"teardown removes pending private prompt immediately");
        } finally {
            release.countDown();mailbox.close();
            check(mailbox.awaitDeliveryTermination(System.nanoTime()+TimeUnit.SECONDS.toNanos(3)),"delivery drain and failure callback do not deadlock");
        }
        check(exited.getCount()==0 && !expired.get(),"delivery exited via explicit release, not fail-safe timeout");
        check("closed".equals(mailbox.poll("A",0).get("phase")),"late failure never reopens discarded mailbox");
        EngineDiagnostics.clear();
    }

}
